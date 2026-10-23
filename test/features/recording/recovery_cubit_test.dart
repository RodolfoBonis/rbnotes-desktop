import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/recording/presentation/recovery_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository repo;
  late FakeRbNative native;
  late TranscriptionQueue queue;
  late AppPaths paths;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = memoryDb();
    repo = memoryRepo(db);
    native = FakeRbNative();
    queue = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: SettingsStore(await SharedPreferences.getInstance()),
      vocabulary: VocabularyRepository(db),
    );
    tmp = await Directory.systemTemp.createTemp('rbnotes_recov');
    await Directory(p.join(tmp.path, 'recordings')).create(recursive: true);
    paths = AppPaths.forTesting(tmp);
  });

  tearDown(() async {
    await queue.dispose();
    await native.dispose();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  RecoveryCubit build() => RecoveryCubit(
    native: native,
    repository: repo,
    queue: queue,
    paths: paths,
  );

  Future<void> orphanWav(String id) async {
    final file = File(p.join(paths.recordingsDir, '$id.mic.wav'));
    await file.writeAsBytes(const [0, 0, 0, 0]);
  }

  Future<void> seedRecordingNote(String id, {bool withMicPath = false}) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            status: NoteStatus.recording,
            source: NoteSource.recording,
            micWavPath: withMicPath
                ? Value(p.join(paths.recordingsDir, '$id.mic.wav'))
                : const Value.absent(),
          ),
        );
  }

  test('scan encontra wav órfão sem nota', () async {
    await orphanWav('orphan1');
    final cubit = build();
    await cubit.scan();
    expect(cubit.state.recoverable.single.id, 'orphan1');
  });

  test('scan ignora wav que já virou nota finalizada', () async {
    await orphanWav('known');
    await seedNote(db, id: 'known'); // status ready
    final cubit = build();
    await cubit.scan();
    expect(cubit.state.hasRecoverable, isFalse);
  });

  test('scan recupera nota presa em recording com wav em disco', () async {
    await orphanWav('crashed');
    await seedRecordingNote('crashed', withMicPath: true);
    final cubit = build();
    await cubit.scan();
    expect(cubit.state.recoverable.single.id, 'crashed');
  });

  test('recover atualiza a nota existente em vez de inserir outra', () async {
    await orphanWav('crashed');
    await seedRecordingNote('crashed', withMicPath: true);
    final cubit = build();
    await cubit.scan();
    await cubit.recover(cubit.state.recoverable.single);
    // Continua sendo UMA nota, agora em transcribing/ready.
    final all = await repo.watchNotes().first;
    expect(all.where((n) => n.note.id == 'crashed').length, 1);
    await queue.progress.firstWhere((p) => p.isTerminal);
    expect((await repo.getNote('crashed'))!.status, NoteStatus.ready);
  });

  test('nota recording sem wav no boot vira failed', () async {
    await seedRecordingNote('nowav');
    final cubit = build();
    await cubit.scan();
    expect(cubit.state.hasRecoverable, isFalse);
    expect((await repo.getNote('nowav'))!.status, NoteStatus.failed);
  });

  test('scan não toca na gravação atual', () async {
    await seedRecordingNote('active');
    final cubit = build();
    await cubit.scan(currentRecordingId: 'active');
    expect((await repo.getNote('active'))!.status, NoteStatus.recording);
  });

  test('recover cria a nota quando só existe o wav órfão', () async {
    await orphanWav('r1');
    final cubit = build();
    await cubit.scan();
    await cubit.recover(cubit.state.recoverable.single);
    expect(cubit.state.hasRecoverable, isFalse);
    expect(await repo.getNote('r1'), isNotNull);
    await queue.progress.firstWhere((p) => p.isTerminal);
    expect((await repo.getNote('r1'))!.status, NoteStatus.ready);
  });

  test('discard apaga os arquivos e remove da lista', () async {
    await orphanWav('d1');
    final cubit = build();
    await cubit.scan();
    await cubit.discard(cubit.state.recoverable.single);
    expect(cubit.state.hasRecoverable, isFalse);
    expect(File(p.join(paths.recordingsDir, 'd1.mic.wav')).existsSync(), false);
  });

  test('discard de nota presa em recording a marca failed', () async {
    await orphanWav('crashed');
    await seedRecordingNote('crashed', withMicPath: true);
    final cubit = build();
    await cubit.scan();
    await cubit.discard(cubit.state.recoverable.single);
    expect((await repo.getNote('crashed'))!.status, NoteStatus.failed);
  });
}
