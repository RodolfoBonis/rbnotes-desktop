import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/recording/presentation/recovery_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
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

  test('scan encontra wav órfão sem nota', () async {
    await orphanWav('orphan1');
    final cubit = build();
    await cubit.scan();
    expect(cubit.state.recoverable.single.id, 'orphan1');
  });

  test('scan ignora wav que já virou nota', () async {
    await orphanWav('known');
    await seedNote(db, id: 'known');
    final cubit = build();
    await cubit.scan();
    expect(cubit.state.hasRecoverable, isFalse);
  });

  test('recover cria a nota e enfileira transcrição', () async {
    await orphanWav('r1');
    final cubit = build();
    await cubit.scan();
    await cubit.recover(cubit.state.recoverable.single);
    expect(cubit.state.hasRecoverable, isFalse);
    expect(await repo.getNote('r1'), isNotNull);
    await queue.progress.firstWhere((p) => p.done || p.failed);
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
}
