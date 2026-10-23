import 'dart:async';

import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';

/// Liga o fim da transcrição ao upload de áudio: quando uma nota termina de
/// transcrever (fluxo normal **ou** recuperação de crash, ambos emitem `done`),
/// enfileira o `.m4a` na [AudioUploadQueue] — desde que o sync esteja ligado.
///
/// Com o sync desligado nada é enfileirado; o arquivo fica local e o
/// `RetentionService` cuida de apagá-lo na hora se "apagar áudio após
/// transcrever" estiver ativo.
class AudioUploadCoordinator {
  AudioUploadCoordinator({
    required AudioUploadQueue queue,
    required NoteRepository notes,
    required SettingsStore settings,
  }) : _queue = queue,
       _notes = notes,
       _settings = settings;

  final AudioUploadQueue _queue;
  final NoteRepository _notes;
  final SettingsStore _settings;

  StreamSubscription<TranscriptionProgress>? _sub;

  /// Passa a observar as transcrições concluídas.
  void attachTo(TranscriptionQueue queue) {
    _sub ??= queue.progress.listen((p) {
      if (p.done) unawaited(onTranscribed(p.noteId));
    });
  }

  /// Enfileira o áudio de [noteId] para upload, se houver `.m4a` local e o sync
  /// estiver ligado. Silencioso em falha (nunca derruba o pipeline).
  Future<void> onTranscribed(String noteId) async {
    if (!_settings.syncEnabled) return;
    try {
      final note = await _notes.getNote(noteId);
      final path = note?.playbackPath;
      if (path == null) return;
      await _queue.enqueue(noteId, path);
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'enqueue_audio_upload',
        category: 'sync',
      );
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
