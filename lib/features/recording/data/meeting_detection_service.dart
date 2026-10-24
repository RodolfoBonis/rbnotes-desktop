import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/rb_native.dart';

/// Uma sugestão de gravar a reunião detectada (app em foco usando o microfone).
class MeetingSuggestion extends Equatable {
  const MeetingSuggestion({required this.app, required this.meetingKey});

  /// App da reunião (ex.: `zoom.us`, `Microsoft Teams`, `Google Chrome`).
  final String app;

  /// Chave única da reunião (app + início), para não repetir a sugestão.
  final String meetingKey;

  @override
  List<Object?> get props => [app, meetingKey];
}

/// "Sugerir gravação ao detectar reunião": liga/desliga a detecção nativa
/// (`setMeetingDetection`) conforme a opção e, a cada início de reunião
/// (`meetingSignals` com `micInUse: true`), emite uma [MeetingSuggestion] uma
/// vez por reunião. Respeita a trava do app ([locked]).
class MeetingDetectionService {
  MeetingDetectionService({
    required RbNative native,
    required SettingsStore settings,
  }) : _native = native,
       _settings = settings;

  final RbNative _native;
  final SettingsStore _settings;

  StreamSubscription<MeetingSignal>? _sub;
  final _seen = <String>{};
  final _controller = StreamController<MeetingSuggestion>.broadcast();

  /// Trava do app por Touch ID. Enquanto `true`, nenhuma sugestão é emitida
  /// (nem marcada como vista) — o app está bloqueado.
  bool locked = false;

  Stream<MeetingSuggestion> get suggestions => _controller.stream;

  /// Liga ou desliga a detecção conforme "Sugerir gravação ao detectar
  /// reunião". Idempotente; chamado no boot e quando a opção muda.
  Future<void> applySettings() async {
    try {
      if (_settings.autoMeet) {
        await _native.setMeetingDetection(true);
        _sub ??= _native.meetingSignals().listen(
          _onSignal,
          onError: (Object e, StackTrace st) {
            unawaited(
              AppLogger.error(
                e,
                st,
                reason: 'meeting_signals',
                category: 'recording',
              ),
            );
          },
        );
      } else {
        await _native.setMeetingDetection(false);
        await _sub?.cancel();
        _sub = null;
        _seen.clear();
      }
    } on Object catch (e) {
      AppLogger.warning(
        'meeting detection toggle failed',
        category: 'recording',
        error: e,
      );
    }
  }

  void _onSignal(MeetingSignal signal) {
    if (!signal.micInUse) return; // só sugere no início da reunião
    if (locked) return; // respeita a trava do app
    final key = '${signal.app}@${signal.startedAt.millisecondsSinceEpoch}';
    if (!_seen.add(key)) return; // já sugerida
    _controller.add(MeetingSuggestion(app: signal.app, meetingKey: key));
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}
