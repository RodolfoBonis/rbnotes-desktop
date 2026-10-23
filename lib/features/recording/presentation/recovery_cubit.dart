import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/rb_native.dart';

class RecoveryState extends Equatable {
  const RecoveryState({this.recoverable = const []});

  final List<RecoverableRecording> recoverable;

  bool get hasRecoverable => recoverable.isNotEmpty;

  @override
  List<Object?> get props => [recoverable];
}

/// Na inicialização, concilia as gravações interrompidas por um crash:
///
/// - `.wav` órfão sem nota → oferece recuperar (vira nota + transcrição).
/// - nota presa em `recording` com `.wav` em disco → oferece recuperar
///   (atualiza a nota existente, não cria outra).
/// - nota presa em `recording` sem `.wav` (e que não é a gravação atual) →
///   marca como `failed` (não há áudio para recuperar).
class RecoveryCubit extends Cubit<RecoveryState> {
  RecoveryCubit({
    required RbNative native,
    required NoteRepository repository,
    required TranscriptionQueue queue,
    required AppPaths paths,
  }) : _native = native,
       _repository = repository,
       _queue = queue,
       _paths = paths,
       super(const RecoveryState());

  final RbNative _native;
  final NoteRepository _repository;
  final TranscriptionQueue _queue;
  final AppPaths _paths;

  /// [currentRecordingId] protege uma gravação em andamento (se houver) de ser
  /// marcada como falha pela varredura.
  Future<void> scan({String? currentRecordingId}) async {
    try {
      final found = await _native.findRecoverableRecordings(
        _paths.recordingsDir,
      );
      final foundIds = {for (final rec in found) rec.id};

      // Recuperável = wav órfão sem nota, ou nota ainda presa em `recording`.
      final recoverable = <RecoverableRecording>[];
      for (final rec in found) {
        if (rec.id == currentRecordingId) continue;
        final note = await _repository.getNote(rec.id);
        if (note == null || note.status == NoteStatus.recording) {
          recoverable.add(rec);
        }
      }

      // Notas presas em `recording` sem áudio em disco: não há o que recuperar.
      final stuck = await _repository.notesWithStatus(NoteStatus.recording);
      for (final note in stuck) {
        if (note.id == currentRecordingId) continue;
        if (!foundIds.contains(note.id)) {
          await _repository.setStatus(note.id, NoteStatus.failed);
        }
      }

      emit(RecoveryState(recoverable: recoverable));
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'scan_recoverable',
        category: 'recording',
      );
    }
  }

  Future<void> recover(RecoverableRecording rec) async {
    final existing = await _repository.getNote(rec.id);
    if (existing == null) {
      final now = DateTime.now();
      await _repository.insertNote(
        NotesCompanion.insert(
          id: rec.id,
          createdAt: now,
          updatedAt: now,
          durationMs: Value(rec.duration.inMilliseconds),
          micWavPath: Value(rec.micWavPath),
          systemWavPath: Value(rec.systemWavPath),
          status: NoteStatus.transcribing,
          source: NoteSource.recording,
        ),
      );
    } else {
      // Nota já existe (presa em `recording`): atualiza em vez de inserir.
      await _repository.recoverRecording(
        rec.id,
        durationMs: rec.duration.inMilliseconds,
        micWavPath: rec.micWavPath,
        systemWavPath: rec.systemWavPath,
      );
    }
    _queue.enqueue(rec.id);
    _remove(rec);
  }

  Future<void> discard(RecoverableRecording rec) async {
    for (final path in [rec.micWavPath, rec.systemWavPath]) {
      if (path == null) continue;
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
    // Se existir nota presa em `recording`, não deixe órfã: marca como falha.
    final note = await _repository.getNote(rec.id);
    if (note != null && note.status == NoteStatus.recording) {
      await _repository.setStatus(rec.id, NoteStatus.failed);
    }
    _remove(rec);
  }

  void _remove(RecoverableRecording rec) {
    emit(
      RecoveryState(
        recoverable: state.recoverable.where((r) => r.id != rec.id).toList(),
      ),
    );
  }
}
