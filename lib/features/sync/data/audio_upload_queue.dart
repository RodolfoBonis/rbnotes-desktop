import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/sync/data/audio_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Um item da fila de upload de áudio.
class AudioUploadTask {
  const AudioUploadTask({required this.noteId, required this.path});

  factory AudioUploadTask.fromJson(Map<String, dynamic> j) => AudioUploadTask(
    noteId: j['noteId'] as String,
    path: j['path'] as String,
  );

  final String noteId;
  final String path;

  Map<String, dynamic> toJson() => {'noteId': noteId, 'path': path};
}

/// Fila persistente de upload de áudio, com retomada entre execuções e backoff.
///
/// Só roda com "Sincronizar" ligado. A retenção/"apagar áudio após transcrever"
/// é aplicada por `RetentionService`; a fila sobe o que ainda existe no disco
/// e descarta silenciosamente itens cujo arquivo já sumiu.
class AudioUploadQueue {
  AudioUploadQueue({
    required AudioSync audio,
    required SettingsStore settings,
    required SharedPreferences prefs,
    this.backoffBase = const Duration(seconds: 5),
    this.backoffMax = const Duration(minutes: 5),
  }) : _audio = audio,
       _settings = settings,
       _prefs = prefs;

  final AudioSync _audio;
  final SettingsStore _settings;
  final SharedPreferences _prefs;
  final Duration backoffBase;
  final Duration backoffMax;

  static const _kQueue = 'audio.upload.queue';

  bool _running = false;
  Timer? _retry;

  List<AudioUploadTask> get pending {
    final raw = _prefs.getString(_kQueue);
    if (raw == null || raw.isEmpty) return const [];
    final list = (jsonDecode(raw) as List).whereType<Map<String, dynamic>>();
    return list.map(AudioUploadTask.fromJson).toList();
  }

  Future<void> _save(List<AudioUploadTask> tasks) => _prefs.setString(
    _kQueue,
    jsonEncode(tasks.map((t) => t.toJson()).toList()),
  );

  /// Enfileira um áudio e dispara o processamento.
  Future<void> enqueue(String noteId, String path) async {
    final tasks = pending.where((t) => t.noteId != noteId).toList()
      ..add(AudioUploadTask(noteId: noteId, path: path));
    await _save(tasks);
    unawaited(process());
  }

  /// Processa a fila em ordem. Sucesso remove o item; falha transitória agenda
  /// um retry com backoff.
  Future<void> process() async {
    if (_running || !_settings.syncEnabled) return;
    _running = true;
    _retry?.cancel();
    try {
      var tasks = pending;
      var failures = 0;
      while (tasks.isNotEmpty) {
        final task = tasks.first;
        if (!File(task.path).existsSync()) {
          tasks = tasks.sublist(1);
          await _save(tasks);
          continue;
        }
        try {
          await _audio.uploadFile(task.noteId, task.path);
          tasks = tasks.sublist(1);
          await _save(tasks);
          failures = 0;
        } on ApiError catch (e) {
          failures++;
          AppLogger.warning(
            'Falha no upload de áudio',
            category: 'sync',
            error: e,
          );
          _scheduleRetry(failures);
          return;
        }
      }
    } finally {
      _running = false;
    }
  }

  void _scheduleRetry(int failures) {
    final factor = (1 << (failures - 1).clamp(0, 10)).toDouble();
    final base = backoffBase * factor;
    final delay = base > backoffMax ? backoffMax : base;
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(process()));
  }

  void dispose() => _retry?.cancel();
}
