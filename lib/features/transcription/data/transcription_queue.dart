import 'dart:async';
import 'dart:collection';

import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/transcription/domain/transcription_logic.dart';
import 'package:rbnotes/native/rb_native.dart';

/// Progresso de transcrição de uma nota (0..1), ou estado terminal.
class TranscriptionProgress extends Equatable {
  const TranscriptionProgress({
    required this.noteId,
    required this.progress,
    this.done = false,
    this.failed = false,
  });

  final String noteId;
  final double progress;
  final bool done;
  final bool failed;

  @override
  List<Object?> get props => [noteId, progress, done, failed];
}

/// Fila serial de transcrição em background.
///
/// Transcreve `mic.wav` (eu) e, quando existe, `system.wav` (outros), junta os
/// segmentos por tempo, salva e gera o título automático. Emite progresso por
/// nota em [progress]; a lista de notas assina para mostrar a barra.
class TranscriptionQueue {
  TranscriptionQueue({
    required RbNative native,
    required NoteRepository repository,
    required SettingsStore settings,
  }) : _native = native,
       _repository = repository,
       _settings = settings;

  final RbNative _native;
  final NoteRepository _repository;
  final SettingsStore _settings;

  final _queue = Queue<String>();
  final _controller = StreamController<TranscriptionProgress>.broadcast();
  bool _processing = false;

  Stream<TranscriptionProgress> get progress => _controller.stream;

  /// Enfileira uma nota para transcrição (ignora duplicatas pendentes).
  void enqueue(String noteId) {
    if (_queue.contains(noteId)) return;
    _queue.add(noteId);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        final noteId = _queue.removeFirst();
        await _process(noteId);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _process(String noteId) async {
    final note = await _repository.getNote(noteId);
    if (note == null || note.micWavPath == null) return;
    await _repository.setStatus(noteId, NoteStatus.transcribing);
    _emit(noteId, 0);
    try {
      final model = _settings.model;
      final hasSystem = note.systemWavPath != null;

      final mic = await _native.transcribe(
        wavPath: note.micWavPath!,
        model: model,
        onProgress: (p) => _emit(noteId, hasSystem ? p * 0.5 : p),
      );
      final system = hasSystem
          ? await _native.transcribe(
              wavPath: note.systemWavPath!,
              model: model,
              onProgress: (p) => _emit(noteId, 0.5 + p * 0.5),
            )
          : const <TranscriptSegment>[];

      final merged = mergeSpeakerSegments(mic: mic, system: system);
      await _repository.replaceSegments(noteId, merged);

      if (note.title.trim().isEmpty) {
        final title = titleFromSegments(merged);
        if (title.isNotEmpty) await _repository.updateTitle(noteId, title);
      }
      await _repository.setStatus(noteId, NoteStatus.ready);
      _controller.add(
        TranscriptionProgress(noteId: noteId, progress: 1, done: true),
      );
    } on RbNativeException catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'transcribe',
        category: 'transcription',
      );
      await _repository.setStatus(noteId, NoteStatus.failed);
      _controller.add(
        TranscriptionProgress(noteId: noteId, progress: 0, failed: true),
      );
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'transcribe',
        category: 'transcription',
      );
      await _repository.setStatus(noteId, NoteStatus.failed);
      _controller.add(
        TranscriptionProgress(noteId: noteId, progress: 0, failed: true),
      );
    }
  }

  void _emit(String noteId, double progress) {
    _controller.add(
      TranscriptionProgress(noteId: noteId, progress: progress.clamp(0, 1)),
    );
  }

  Future<void> dispose() => _controller.close();
}
