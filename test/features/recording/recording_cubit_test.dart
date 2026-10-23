import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
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
      vocabulary: VocabularyRepository(db),
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
    diagnostics: native.diagnostics(),
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

  test('stop finaliza, processa e volta a ocioso', () async {
    final cubit = build();
    await cubit.start();
    final id = cubit.state.noteId!;
    final created = cubit.createdNotes.first;
    await cubit.stop();
    // Entra no HUD de processamento.
    expect(cubit.state.status, RecordingStatus.processing);
    // Ao terminar (transcrição + IA), emite a nota criada e volta a ocioso.
    final note = await created;
    expect(note.id, id);
    final saved = await repo.getNote(id);
    expect(saved!.micWavPath, isNotNull);
    expect(saved.status, NoteStatus.ready);
    expect(cubit.state.status, RecordingStatus.idle);
    await cubit.close();
  });

  test('diagnóstico system_audio_stopped marca systemAudioDropped', () async {
    final cubit = build();
    await cubit.start();
    final id = cubit.state.noteId!;
    native.emitDiagnostic(
      NativeDiagnostic(
        code: 'system_audio_stopped',
        message: 'SCStream parou',
        recordingId: id,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cubit.state.systemAudioDropped, isTrue);
    await cubit.close();
  });

  test('sem permissão de microfone emite erro e não grava', () async {
    // requestPermission do fake normalmente concede; este nega sempre.
    final denying = _DenyingNative();
    final cubit = RecordingCubit(
      native: denying,
      repository: repo,
      queue: queue,
      settings: settings,
      paths: paths,
      diagnostics: denying.diagnostics(),
    );
    await cubit.start();
    expect(cubit.state.status, RecordingStatus.idle);
    expect(cubit.state.error, isNotNull);
    await cubit.close();
  });

  test('falha de transcricao mostra erro no HUD e nao encerra (bug/pedido 7)',
      () async {
    native.modelDownloaded = false; // transcribe lanca model_missing
    final cubit = build();
    await cubit.start();
    await cubit.stop();
    await cubit.stream.firstWhere((s) => s.processingFailed);
    expect(cubit.state.failedStep, 0);
    expect(cubit.state.hudVisible, isTrue);
    expect(cubit.state.isProcessing, isTrue);

    cubit.closeHud(); // "Fechar" encerra o HUD
    expect(cubit.state.isActive, isFalse);
    await cubit.close();
  });

  test('gravacao background mostra o overlay do notch (pedido 11)', () async {
    final cubit = build();
    await cubit.start(background: true);
    expect(cubit.state.background, isTrue);
    expect(native.overlayShowCount, 1);
    expect(native.overlayMode, OverlayMode.recording);
    expect(cubit.state.hudVisible, isFalse); // sem HUD interno duplicado

    // A acao "stop" do overlay encerra a gravacao.
    native.emitOverlayAction(OverlayAction.stop);
    await cubit.stream.firstWhere((s) => s.isProcessing || !s.isActive);
    expect(cubit.state.isRecording, isFalse);
    await cubit.close();
  });

  test('gravacao em foco usa o HUD interno, sem overlay', () async {
    final cubit = build();
    await cubit.start(); // foreground (isForeground nao injetado => true)
    expect(cubit.state.background, isFalse);
    expect(native.overlayShowCount, 0);
    expect(cubit.state.hudVisible, isTrue);
    await cubit.close();
  });

  test('acao openApp traz a janela ao foco e esconde o overlay', () async {
    var opened = false;
    final cubit = RecordingCubit(
      native: native,
      repository: repo,
      queue: queue,
      settings: settings,
      paths: paths,
      diagnostics: native.diagnostics(),
      onOpenApp: () async => opened = true,
    );
    await cubit.start(background: true);
    expect(native.overlayShowCount, 1);
    native.emitOverlayAction(OverlayAction.openApp);
    await cubit.stream.firstWhere((s) => !s.background);
    expect(opened, isTrue);
    expect(cubit.state.hudVisible, isTrue); // HUD interno assume
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
