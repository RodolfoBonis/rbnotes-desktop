import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/data/silence_store.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/system_settings.dart';
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

  test('toggleRecordNote inicia a gravação quando ocioso', () async {
    final cubit = build();
    await cubit.toggleRecordNote();
    expect(cubit.state.status, RecordingStatus.recording);
    await cubit.close();
  });

  test(
    'toggleRecordNote respeita captureSystemAudio das configurações',
    () async {
      await settings.setCaptureSystemAudio(value: true);
      final cubit = build();
      await cubit.toggleRecordNote();
      expect(cubit.state.captureSystemAudio, isTrue);
      expect(native.registeredGlobalHotkeys, isEmpty); // não registra aqui
      await cubit.close();
    },
  );

  test(
    'toggleRecordNote conclui (stop → processamento) quando gravando',
    () async {
      final cubit = build();
      await cubit.toggleRecordNote();
      expect(cubit.state.status, RecordingStatus.recording);
      final created = cubit.createdNotes.first;
      await cubit.toggleRecordNote();
      expect(cubit.state.status, RecordingStatus.processing);
      await created; // pipeline conclui e volta a ocioso
      expect(cubit.state.status, RecordingStatus.idle);
      await cubit.close();
    },
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

  test('remover silêncios: detecta e salva o sidecar ao concluir', () async {
    await settings.setRemoveSilences(value: true);
    native.silences = const [
      SilenceRange(
        start: Duration(seconds: 2),
        end: Duration(seconds: 4),
      ),
    ];
    final cubit = build();
    await cubit.start();
    final id = cubit.state.noteId!;
    final created = cubit.createdNotes.first;
    await cubit.stop();
    await created;
    final saved = await SilenceStore(paths).load(id);
    expect(saved, [(2000, 4000)]);
    await cubit.close();
  });

  test('sem "remover silêncios", não salva o sidecar', () async {
    await settings.setRemoveSilences(value: false);
    native.silences = const [
      SilenceRange(
        start: Duration(seconds: 2),
        end: Duration(seconds: 4),
      ),
    ];
    final cubit = build();
    await cubit.start();
    final id = cubit.state.noteId!;
    final created = cubit.createdNotes.first;
    await cubit.stop();
    await created;
    expect(await SilenceStore(paths).load(id), isEmpty);
    await cubit.close();
  });

  test('travado: overlay do notch não mostra a transcrição ao vivo', () async {
    final cubit = RecordingCubit(
      native: native,
      repository: repo,
      queue: queue,
      settings: settings,
      paths: paths,
      diagnostics: native.diagnostics(),
      isForeground: () async => false, // sem foco → usa o overlay do notch
      isLocked: () => true, // app travado
    );
    await cubit.start();
    final id = cubit.state.noteId!;
    native.emitLiveTranscript(id, 'conteúdo secreto da reunião');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // O overlay nunca recebe o texto ao vivo enquanto travado.
    expect(native.overlayLiveText, anyOf(isNull, isEmpty));
    await cubit.discard();
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

  test('microfone negado mostra aviso acionável e não grava', () async {
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
    expect(cubit.state.noteId, isNull);
    final alert = cubit.state.alert;
    expect(alert, isNotNull);
    expect(alert!.kind, RecordingAlertKind.microphoneDenied);
    expect(alert.permission, RbPermission.microphone);
    expect(alert.message, contains('microfone'));
    await cubit.close();
  });

  test(
    'microfone indeterminado pede permissão e grava quando concedida',
    () async {
      final native = FakeRbNative(
        permissions: {RbPermission.microphone: PermissionStatus.notDetermined},
      );
      final q = TranscriptionQueue(
        native: native,
        repository: repo,
        settings: settings,
        vocabulary: VocabularyRepository(db),
      );
      final cubit = RecordingCubit(
        native: native,
        repository: repo,
        queue: q,
        settings: settings,
        paths: paths,
        diagnostics: native.diagnostics(),
      );
      await cubit.start();
      expect(cubit.state.status, RecordingStatus.recording);
      expect(cubit.state.alert, isNull);
      // O fake concede ao pedir: o microfone agora está autorizado.
      expect(
        await native.permissionStatus(RbPermission.microphone),
        PermissionStatus.granted,
      );
      await cubit.discard();
      await cubit.close();
      await q.dispose();
      await native.dispose();
    },
  );

  test('gravação de tela negada grava só o microfone e avisa', () async {
    await settings.setCaptureSystemAudio(value: true);
    final native = FakeRbNative(
      permissions: {RbPermission.screenRecording: PermissionStatus.denied},
    );
    final q = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: settings,
      vocabulary: VocabularyRepository(db),
    );
    final cubit = RecordingCubit(
      native: native,
      repository: repo,
      queue: q,
      settings: settings,
      paths: paths,
      diagnostics: native.diagnostics(),
    );
    await cubit.start();
    expect(cubit.state.status, RecordingStatus.recording);
    expect(cubit.state.screenDenied, isTrue);
    // Grava só o mic: a captura efetiva do sistema foi desligada.
    expect(cubit.state.captureSystemAudio, isFalse);
    await cubit.discard();
    await cubit.close();
    await q.dispose();
    await native.dispose();
  });

  test('silêncio digital ao vivo no mic marca micNoSignal', () async {
    final native = FakeRbNative(silentMic: true);
    final q = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: settings,
      vocabulary: VocabularyRepository(db),
    );
    final cubit = RecordingCubit(
      native: native,
      repository: repo,
      queue: q,
      settings: settings,
      paths: paths,
      diagnostics: native.diagnostics(),
      signalCheckDelay: const Duration(milliseconds: 80),
    );
    await cubit.start();
    await cubit.stream.firstWhere((s) => s.micNoSignal);
    expect(cubit.state.micNoSignal, isTrue);
    expect(cubit.state.systemNoSignal, isFalse);
    await cubit.discard();
    await cubit.close();
    await q.dispose();
    await native.dispose();
  });

  test('silêncio digital ao vivo no sistema marca systemNoSignal', () async {
    await settings.setCaptureSystemAudio(value: true);
    final native = FakeRbNative(silentSystem: true);
    final q = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: settings,
      vocabulary: VocabularyRepository(db),
    );
    final cubit = RecordingCubit(
      native: native,
      repository: repo,
      queue: q,
      settings: settings,
      paths: paths,
      diagnostics: native.diagnostics(),
      signalCheckDelay: const Duration(milliseconds: 80),
    );
    await cubit.start();
    await cubit.stream.firstWhere((s) => s.systemNoSignal);
    expect(cubit.state.systemNoSignal, isTrue);
    expect(cubit.state.micNoSignal, isFalse);
    await cubit.discard();
    await cubit.close();
    await q.dispose();
    await native.dispose();
  });

  test('pós-gravação sem sinal marca a nota como failed (não ready)', () async {
    final native = FakeRbNative(silentMic: true);
    final q = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: settings,
      vocabulary: VocabularyRepository(db),
    );
    final cubit = RecordingCubit(
      native: native,
      repository: repo,
      queue: q,
      settings: settings,
      paths: paths,
      diagnostics: native.diagnostics(),
    );
    await cubit.start();
    final id = cubit.state.noteId!;
    await cubit.stop();
    expect(cubit.state.audioSignalFailure, isTrue);
    expect(cubit.state.failedStep, 0);
    expect(cubit.state.processingFailed, isTrue);
    expect(cubit.state.error, contains('sem sinal'));
    final saved = await repo.getNote(id);
    expect(saved!.status, NoteStatus.failed);
    await cubit.close();
    await q.dispose();
    await native.dispose();
  });

  test('"tentar de novo" na falha de sinal apaga a nota e regrava', () async {
    final native = FakeRbNative(silentMic: true);
    final q = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: settings,
      vocabulary: VocabularyRepository(db),
    );
    final cubit = RecordingCubit(
      native: native,
      repository: repo,
      queue: q,
      settings: settings,
      paths: paths,
      diagnostics: native.diagnostics(),
    );
    await cubit.start();
    final firstId = cubit.state.noteId!;
    await cubit.stop();
    expect(cubit.state.audioSignalFailure, isTrue);

    await cubit.retryProcessing();
    // A nota vazia foi descartada e uma nova gravação começou.
    expect(await repo.getNote(firstId), isNull);
    expect(cubit.state.status, RecordingStatus.recording);
    expect(cubit.state.noteId, isNot(firstId));
    await cubit.discard();
    await cubit.close();
    await q.dispose();
    await native.dispose();
  });

  test(
    'openMicrophoneSettings abre o painel de Privacidade do microfone',
    () async {
      final opened = <Uri>[];
      final cubit = RecordingCubit(
        native: native,
        repository: repo,
        queue: queue,
        settings: settings,
        paths: paths,
        diagnostics: native.diagnostics(),
        systemSettings: SystemSettingsOpener(
          launcher: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      );
      await cubit.openMicrophoneSettings();
      expect(opened.single.toString(), contains('Privacy_Microphone'));
      await cubit.close();
    },
  );

  test(
    'falha de transcricao mostra erro no HUD e nao encerra (bug/pedido 7)',
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
    },
  );

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
