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

/// Na inicialização, procura gravações órfãs (`.mic.wav` sem nota) e oferece
/// recuperar (vira nota + transcrição) ou descartar.
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

  Future<void> scan() async {
    try {
      final found = await _native.findRecoverableRecordings(
        _paths.recordingsDir,
      );
      // Só oferece recuperar o que ainda não virou nota.
      final fresh = <RecoverableRecording>[];
      for (final rec in found) {
        if (await _repository.getNote(rec.id) == null) fresh.add(rec);
      }
      emit(RecoveryState(recoverable: fresh));
    } on RbNativeException catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'scan_recoverable',
        category: 'recording',
      );
    }
  }

  Future<void> recover(RecoverableRecording rec) async {
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
    _queue.enqueue(rec.id);
    _remove(rec);
  }

  Future<void> discard(RecoverableRecording rec) async {
    for (final path in [rec.micWavPath, rec.systemWavPath]) {
      if (path == null) continue;
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
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
