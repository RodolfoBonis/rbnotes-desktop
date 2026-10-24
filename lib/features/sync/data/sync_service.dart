import 'dart:async';
import 'dart:math';

import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Orquestra o sync: dispara ao abrir o app, a cada 2 min, após mudanças locais
/// (com debounce) e no "Sincronizar agora". Faz pull (aplica) + push (coleta,
/// envia, aplica conflitos), persiste cursor e marca d'água, e usa backoff
/// exponencial em falha sem travar a UI. Respeita "Sincronizar" desligado.
class SyncService {
  SyncService({
    required SyncClient client,
    required SyncLocalStore store,
    required SettingsStore settings,
    required SharedPreferences prefs,
    this.period = const Duration(minutes: 2),
    this.debounce = const Duration(seconds: 3),
    this.backoffBase = const Duration(seconds: 5),
    this.backoffMax = const Duration(minutes: 5),
    Random? random,
  }) : _client = client,
       _store = store,
       _settings = settings,
       _prefs = prefs,
       _random = random ?? Random() {
    _restorePersisted();
  }

  final SyncClient _client;
  final SyncLocalStore _store;
  final SettingsStore _settings;
  final SharedPreferences _prefs;
  final Random _random;

  final Duration period;
  final Duration debounce;
  final Duration backoffBase;
  final Duration backoffMax;

  static const _kCursor = 'sync.cursor';
  static const _kWatermark = 'sync.watermark';
  static const _kLastSyncAt = 'sync.last_sync_at';
  static const _kLastError = 'sync.last_error';
  static const _kPending = 'sync.pending';
  static const _pushLimit = 400;

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus();

  Timer? _periodic;
  Timer? _debounceTimer;
  Timer? _backoffTimer;
  bool _running = false;
  bool _queued = false;
  int _failures = 0;
  DateTime? _lastSyncAt;
  bool _applyingRemote = false;

  /// `true` enquanto o serviço aplica mudanças vindas do servidor (pull ou
  /// conflitos do push). O `SyncTrigger` consulta isto para nao reagir às
  /// escritas que o próprio sync faz — senão o eco do pull dispararia um novo
  /// sync em loop (o bug do `GET /v1/sync/pull` a cada ~4 s em produção).
  bool get isApplyingRemote => _applyingRemote;

  Stream<SyncStatus> get status async* {
    yield _status;
    yield* _statusController.stream;
  }

  SyncStatus get current => _status;

  /// Liga o agendamento periódico e faz um sync inicial.
  void start() {
    _periodic?.cancel();
    _periodic = Timer.periodic(period, (_) => unawaited(syncNow()));
    unawaited(syncNow());
  }

  /// Reage ao toggle "Sincronizar entre dispositivos": ligar dispara um sync
  /// na hora e religa o periódico; desligar cancela os timers pendentes.
  void onEnabledChanged({required bool enabled}) {
    if (enabled) {
      start();
    } else {
      _periodic?.cancel();
      _debounceTimer?.cancel();
      _backoffTimer?.cancel();
      _emit(const SyncStatus(phase: SyncPhase.disabled));
    }
  }

  /// Agenda um sync após mudanças locais (debounced).
  void requestSync() {
    if (!_settings.syncEnabled) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(syncNow()));
  }

  /// Executa um ciclo completo. [manual] vem do botão "Sincronizar agora".
  Future<void> syncNow({bool manual = false}) async {
    if (!_settings.syncEnabled) {
      _emit(const SyncStatus(phase: SyncPhase.disabled));
      return;
    }
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    _backoffTimer?.cancel();
    _emit(_status.copyWith(phase: SyncPhase.syncing, clearMessage: true));
    try {
      await _pull();
      await _push();
      _failures = 0;
      _lastSyncAt = DateTime.now();
      await _persist(lastSyncAt: _lastSyncAt, pending: 0);
      _emit(SyncStatus(lastSyncAt: _lastSyncAt));
      AppLogger.info('Sync concluído', category: 'sync');
    } on ApiError catch (e) {
      _failures++;
      final pending = await _countPending();
      await _persist(error: e.message, pending: pending);
      _emit(
        SyncStatus(
          phase: e.isNetwork ? SyncPhase.offline : SyncPhase.error,
          lastSyncAt: _lastSyncAt,
          message: e.message,
          pendingCount: pending,
        ),
      );
      AppLogger.warning('Falha no sync', category: 'sync', error: e);
      if (!manual) _scheduleBackoff();
    } on Object catch (e, st) {
      _failures++;
      final pending = await _countPending();
      await _persist(error: 'Falha ao sincronizar.', pending: pending);
      _emit(
        SyncStatus(
          phase: SyncPhase.error,
          lastSyncAt: _lastSyncAt,
          message: 'Falha ao sincronizar.',
          pendingCount: pending,
        ),
      );
      await AppLogger.error(e, st, reason: 'sync', category: 'sync');
      if (!manual) _scheduleBackoff();
    } finally {
      _running = false;
      if (_queued) {
        _queued = false;
        unawaited(syncNow());
      }
    }
  }

  /// Executa [op] (que escreve mudanças remotas no banco) com o gatilho de
  /// sync suprimido. A flag permanece ativa por mais um "turno" do event loop
  /// (`Future.delayed(Duration.zero)`) para que as notificações de
  /// `tableUpdates` (entregues em microtask) já encontrem a flag ligada e sejam
  /// ignoradas pelo `SyncTrigger`.
  Future<void> _applyRemote(Future<void> Function() op) async {
    _applyingRemote = true;
    try {
      await op();
    } finally {
      await Future<void>.delayed(Duration.zero);
      _applyingRemote = false;
    }
  }

  Future<void> _pull() async {
    var cursor = _prefs.getString(_kCursor) ?? '';
    while (true) {
      final res = await _client.pull(since: cursor.isEmpty ? null : cursor);
      if (res.changes.isNotEmpty) {
        await _applyRemote(() => _store.applyAll(res.changes));
      }
      final advanced = res.cursor != cursor;
      cursor = res.cursor;
      await _prefs.setString(_kCursor, cursor);
      if (res.changes.isEmpty || !advanced) break;
    }
  }

  Future<void> _push() async {
    var watermark = _readWatermark();
    while (true) {
      final changes = await _store.collectChanges(since: watermark);
      if (changes.isEmpty) break;
      final result = await _client.push(changes);
      if (result.conflicts.isNotEmpty) {
        await _applyRemote(() => _store.applyAll(result.conflicts));
      }
      final maxUp = _store.maxUpdatedAt(changes);
      if (maxUp == null || (watermark != null && !maxUp.isAfter(watermark))) {
        break;
      }
      watermark = maxUp;
      await _prefs.setString(_kWatermark, watermark.toUtc().toIso8601String());
      if (changes.length < _pushLimit) break;
    }
  }

  DateTime? _readWatermark() {
    final raw = _prefs.getString(_kWatermark);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  void _scheduleBackoff() {
    final factor = (1 << (_failures - 1).clamp(0, 10)).toDouble();
    final base = backoffBase * factor;
    final capped = base > backoffMax ? backoffMax : base;
    final jitterMs = _random.nextInt(1000);
    final delay = capped + Duration(milliseconds: jitterMs);
    _backoffTimer?.cancel();
    _backoffTimer = Timer(delay, () => unawaited(syncNow()));
  }

  void _emit(SyncStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  /// Recupera o último estado conhecido (última sincronização, último erro e
  /// pendências) para o indicador aparecer certo já no boot, antes do 1º ciclo.
  void _restorePersisted() {
    final rawAt = _prefs.getString(_kLastSyncAt);
    _lastSyncAt = rawAt == null ? null : DateTime.tryParse(rawAt);
    final error = _prefs.getString(_kLastError);
    final pending = _prefs.getInt(_kPending) ?? 0;
    _status = SyncStatus(
      lastSyncAt: _lastSyncAt,
      message: error,
      pendingCount: pending,
    );
  }

  /// Conta as alterações locais ainda não confirmadas (limitado por
  /// [_pushLimit] — suficiente para um indicador).
  Future<int> _countPending() async {
    try {
      final changes = await _store.collectChanges(since: _readWatermark());
      return changes.length;
    } on Object {
      return _status.pendingCount;
    }
  }

  Future<void> _persist({
    required int pending,
    DateTime? lastSyncAt,
    String? error,
  }) async {
    final at = lastSyncAt;
    if (at != null) {
      await _prefs.setString(_kLastSyncAt, at.toUtc().toIso8601String());
    }
    if (error == null) {
      await _prefs.remove(_kLastError);
    } else {
      await _prefs.setString(_kLastError, error);
    }
    await _prefs.setInt(_kPending, pending);
  }

  /// Empurra as mudanças locais pendentes (ex.: tombstones de "Apagar todos os
  /// dados") sem passar pelo pull nem pelo toggle "Sincronizar". Propaga
  /// [ApiError] para o chamador decidir (offline → apagar só localmente).
  Future<void> pushNow() => _push();

  /// Reseta o cursor/marca d'água e o estado persistido (último sync, erro e
  /// pendências). Usado ao apagar os dados locais ou todos os dados.
  Future<void> resetCursor() async {
    _periodic?.cancel();
    _debounceTimer?.cancel();
    _backoffTimer?.cancel();
    await _prefs.remove(_kCursor);
    await _prefs.remove(_kWatermark);
    await _prefs.remove(_kLastSyncAt);
    await _prefs.remove(_kLastError);
    await _prefs.remove(_kPending);
    _lastSyncAt = null;
    _failures = 0;
    _emit(const SyncStatus());
  }

  Future<void> dispose() async {
    _periodic?.cancel();
    _debounceTimer?.cancel();
    _backoffTimer?.cancel();
    await _statusController.close();
  }
}
