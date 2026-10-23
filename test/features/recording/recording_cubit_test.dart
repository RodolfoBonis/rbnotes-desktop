import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository repo;
  late FakeRbNative native;
  late TranscriptionQueue queue;
  late SettingsStore settings;
  late AppPaths paths;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = memoryDb();
    repo = memoryRepo(db);
    native = FakeRbNative();
    settings = SettingsStore(await SharedPreferences.getInstance());
    queue = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: settings,
    );
    tmp = await Directory.systemTemp.createTemp('rbnotes_rec');
    paths = AppPaths.forTesting(tmp);
  });

  tearDown(() async {
    await queue.dispose();
    await native.dispose();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  RecordingCubit build() => RecordingCubit(
    native: native,
    repository: repo,
    queue: queue,
    settings: settings,
    paths: paths,
  );

  blocTest<RecordingCubit, RecordingState>(
    'toggle de áudio do sistema atualiza o estado quando ocioso',
    build: build,
    act: (c) => c.setCaptureSystemAudio(value: true),
    expect: () => [
      isA<RecordingState>().having(
        (s) => s.captureSystemAudio,
        'captureSystemAudio',
        true,
      ),
    ],
  );

  test('start cria a nota em status recording', () async {
    final cubit = build();
    await cubit.start();
    expect(cubit.state.status, RecordingStatus.recording);
    final id = cubit.state.noteId!;
    expect((await repo.getNote(id))!.status, NoteStatus.recording);
    await cubit.close();
  });

  test('stop finaliza a nota e enfileira transcrição', () async {
    final cubit = build();
    await cubit.start();
    final id = cubit.state.noteId!;
    await cubit.stop();
    expect(cubit.state.status, RecordingStatus.idle);
    // A fila processa e marca ready.
    await queue.progress.firstWhere((p) => p.done || p.failed);
    final note = await repo.getNote(id);
    expect(note!.micWavPath, isNotNull);
    expect(note.status, NoteStatus.ready);
    await cubit.close();
  });

  test('sem permissão de microfone emite erro e não grava', () async {
    // requestPermission do fake normalmente concede; este nega sempre.
    final cubit = RecordingCubit(
      native: _DenyingNative(),
      repository: repo,
      queue: queue,
      settings: settings,
      paths: paths,
    );
    await cubit.start();
    expect(cubit.state.status, RecordingStatus.idle);
    expect(cubit.state.error, isNotNull);
    await cubit.close();
  });
}

/// Fake que nega o microfone mesmo após requestPermission.
class _DenyingNative extends FakeRbNative {
  @override
  Future<PermissionStatus> permissionStatus(RbPermission p) async =>
      PermissionStatus.denied;

  @override
  Future<PermissionStatus> requestPermission(RbPermission p) async =>
      PermissionStatus.denied;
}
