import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
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

enum AudioUploadStatus { pending, uploading, failed }

/// Estado de um item da fila para a UI (progresso por nota + retry).
class AudioUploadItem extends Equatable {
  const AudioUploadItem({
    required this.noteId,
    required this.status,
    this.progress = 0,
  });

  final String noteId;
  final AudioUploadStatus status;

  /// Progresso do item em andamento (0..1). Zero para os que esperam a vez.
  final double progress;

  @override
  List<Object?> get props => [noteId, status, progress];
}

/// Fila persistente de upload de áudio, com retomada entre execuções e backoff.
///
/// Só roda com "Sincronizar" **e** "Enviar áudios" ligados. Coordena com
/// "Apagar áudio após transcrever": quando a opção está ligada, o arquivo local
/// só é apagado **depois** do upload concluído (aqui, em [_onUploaded]); se o
/// sync estiver desligado, nem chega a enfileirar e o `RetentionService` apaga
/// na hora. A fila descarta silenciosamente itens cujo arquivo já sumiu.
///
/// O progresso por nota é publicado em [items] para a tela de Configurações
/// mostrar a fila e oferecer "Tentar de novo".
class AudioUploadQueue {
  AudioUploadQueue({
    required AudioSync audio,
    required SettingsStore settings,
    required SharedPreferences prefs,
    NoteRepository? notes,
    this.backoffBase = const Duration(seconds: 5),
    this.backoffMax = const Duration(minutes: 5),
  }) : _audio = audio,
       _settings = settings,
       _prefs = prefs,
       _notes = notes;

  final AudioSync _audio;
  final SettingsStore _settings;
  final SharedPreferences _prefs;
  final NoteRepository? _notes;
  final Duration backoffBase;
  final Duration backoffMax;

  static const _kQueue = 'audio.upload.queue';

  bool _running = false;
  Timer? _retry;

  /// Nota em upload no momento e seu progresso (para compor [items]).
  String? _activeId;
  double _activeProgress = 0;
  bool _lastFailed = false;

  final _itemsController = StreamController<List<AudioUploadItem>>.broadcast();

  /// Estado ao vivo da fila (upload por nota + status).
  Stream<List<AudioUploadItem>> get items async* {
    yield current;
    yield* _itemsController.stream;
  }

  /// Snapshot atual da fila.
  List<AudioUploadItem> get current {
    final tasks = pending;
    return [
      for (final t in tasks)
        AudioUploadItem(
          noteId: t.noteId,
          status: t.noteId == _activeId
              ? AudioUploadStatus.uploading
              : (_lastFailed && t == tasks.first
                    ? AudioUploadStatus.failed
                    : AudioUploadStatus.pending),
          progress: t.noteId == _activeId ? _activeProgress : 0,
        ),
    ];
  }

  void _emit() {
    if (!_itemsController.isClosed) _itemsController.add(current);
  }

  List<AudioUploadTask> get pending {
    final raw = _prefs.getString(_kQueue);
    if (raw == null || raw.isEmpty) return const [];
    final list = (jsonDecode(raw) as List).whereType<Map<String, dynamic>>();
    return list.map(AudioUploadTask.fromJson).toList();
  }

  /// A nota [noteId] está aguardando upload?
  bool isPending(String noteId) => pending.any((t) => t.noteId == noteId);

  Future<void> _save(List<AudioUploadTask> tasks) => _prefs.setString(
    _kQueue,
    jsonEncode(tasks.map((t) => t.toJson()).toList()),
  );

  /// Enfileira um áudio e dispara o processamento. Dedup por nota.
  Future<void> enqueue(String noteId, String path) async {
    final tasks = pending.where((t) => t.noteId != noteId).toList()
      ..add(AudioUploadTask(noteId: noteId, path: path));
    await _save(tasks);
    _emit();
    unawaited(process());
  }

  /// "Tentar de novo": limpa o backoff e reprocessa a partir da cabeça da fila.
  Future<void> retry() async {
    _retry?.cancel();
    _lastFailed = false;
    _emit();
    await process();
  }

  /// Processa a fila em ordem. Sucesso remove o item; falha transitória agenda
  /// um retry com backoff.
  Future<void> process() async {
    if (_running || !_settings.syncEnabled || !_settings.sendAudio) return;
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
          _emit();
          continue;
        }
        _activeId = task.noteId;
        _activeProgress = 0;
        _lastFailed = false;
        _emit();
        try {
          await _audio.uploadFile(
            task.noteId,
            task.path,
            onProgress: (p) {
              _activeProgress = p;
              _emit();
            },
          );
          tasks = tasks.sublist(1);
          await _save(tasks);
          _activeId = null;
          _activeProgress = 0;
          failures = 0;
          _emit();
          await _onUploaded(task.noteId);
        } on ApiError catch (e) {
          failures++;
          _activeId = null;
          _lastFailed = true;
          _emit();
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

  /// Pós-upload: com "apagar áudio após transcrever" ligado, agora que o áudio
  /// está no servidor dá para remover o arquivo local e zerar os caminhos.
  Future<void> _onUploaded(String noteId) async {
    final notes = _notes;
    if (notes == null || !_settings.deleteAudioAfter) return;
    try {
      final note = await notes.getNote(noteId);
      if (note == null) return;
      for (final path in [
        note.playbackPath,
        note.micWavPath,
        note.systemWavPath,
      ]) {
        if (path == null) continue;
        final file = File(path);
        if (file.existsSync()) await file.delete();
      }
      await notes.clearAudioPaths(noteId);
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'audio_delete_after_upload',
        category: 'sync',
      );
    }
  }

  void _scheduleRetry(int failures) {
    final factor = (1 << (failures - 1).clamp(0, 10)).toDouble();
    final base = backoffBase * factor;
    final delay = base > backoffMax ? backoffMax : base;
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(process()));
  }

  void dispose() {
    _retry?.cancel();
    unawaited(_itemsController.close());
  }
}
