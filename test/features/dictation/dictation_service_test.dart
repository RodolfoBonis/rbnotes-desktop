import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository repo;
  late FakeRbNative native;
  late SettingsStore store;
  late DictationService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = memoryDb();
    repo = memoryRepo(db);
    native = FakeRbNative();
    store = SettingsStore(await SharedPreferences.getInstance());
    service = DictationService(
      native: native,
      repository: repo,
      settings: store,
      vocabulary: VocabularyRepository(db),
    );
  });

  tearDown(() async {
    await service.dispose();
    await native.dispose();
    await db.close();
  });

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 30));

  test('start registra o atalho do ditado', () async {
    await service.start();
    expect(native.registeredHotkey, store.hotkey);
    expect(service.hotkeyStatus.registered, isTrue);
  });

  test('DictationStopped transcreve, cola e salva nota de ditado', () async {
    await service.start();
    native.emitDictation(const DictationStopped('/tmp/dictation.wav'));
    await pump();
    expect(native.pastedTexts, isNotEmpty);
    expect(service.lastDictatedText, isNotNull);
    final notes = await repo.watchNotes().first;
    expect(notes.single.note.source, NoteSource.dictation);
  });

  test('toca o som de início e de fim pelo lado Dart', () async {
    await service.start();
    native
      ..emitDictation(const DictationStarted())
      ..emitDictation(const DictationStopped('/tmp/dictation.wav'));
    await pump();
    expect(native.playedSounds, contains(DictationSound.start));
    expect(native.playedSounds, contains(DictationSound.end));
  });

  test('apaga o wav temporário após transcrever', () async {
    final tmp = await Directory.systemTemp.createTemp('rbnotes_dict');
    final wav = File(p.join(tmp.path, 'd.wav'));
    await wav.writeAsBytes(const [0, 0, 0, 0]);
    await service.start();
    native.emitDictation(DictationStopped(wav.path));
    await pump();
    expect(wav.existsSync(), isFalse);
    tmp.deleteSync(recursive: true);
  });

  test('ditado transcreve com prioridade alta', () async {
    await service.start();
    native.emitDictation(const DictationStopped('/tmp/d.wav'));
    await pump();
    expect(native.lastTranscribePriority, TranscriptionPriority.high);
  });

  test('pasteLast recola o último texto ditado', () async {
    await service.start();
    native.emitDictation(const DictationStopped('/tmp/d.wav'));
    await pump();
    native.pastedTexts.clear();
    await service.pasteLast();
    expect(native.pastedTexts.single, service.lastDictatedText);
  });

  test('colagem que falha ainda salva a nota e avisa o usuário', () async {
    final failNative = _PasteFailNative();
    final svc = DictationService(
      native: failNative,
      repository: repo,
      settings: store,
      vocabulary: VocabularyRepository(db),
    );
    final notices = <String>[];
    final sub = svc.notices.listen(notices.add);
    await svc.start();
    failNative.emitDictation(const DictationStopped('/tmp/d.wav'));
    await pump();
    // A nota foi salva mesmo com a colagem falhando.
    final notes = await repo.watchNotes().first;
    expect(notes.single.note.source, NoteSource.dictation);
    expect(svc.lastDictatedText, isNotNull);
    expect(notices, isNotEmpty);
    await sub.cancel();
    await svc.dispose();
    await failNative.dispose();
  });

  test('falha ao registrar o atalho vira status visível (sem crash)', () async {
    final failNative = _HotkeyFailNative();
    final svc = DictationService(
      native: failNative,
      repository: repo,
      settings: store,
      vocabulary: VocabularyRepository(db),
    );
    await svc.start();
    expect(svc.hotkeyStatus.registered, isFalse);
    expect(svc.hotkeyStatus.error, isNotNull);
    await svc.dispose();
    await failNative.dispose();
  });

  test('ditado mostra e esconde o overlay do notch (pedido 11)', () async {
    await service.start();
    native.emitDictation(const DictationStarted());
    await pump();
    expect(native.overlayShowCount, 1);
    expect(native.overlayMode, OverlayMode.dictation);

    native.emitDictation(const DictationStopped('/tmp/dictation.wav'));
    await pump();
    expect(native.overlayHideCount, greaterThanOrEqualTo(1));
  });

  group('editor do atalho de ditado (pedido 6)', () {
    test('statusChanges emite registrado ao aplicar', () async {
      final events = <DictationHotkeyStatus>[];
      final sub = service.statusChanges.listen(events.add);
      await store.setDictationEnabled(value: true);
      await service.applySettings();
      await pump();
      expect(events.last.registered, isTrue);
      expect(events.last.hasError, isFalse);
      await sub.cancel();
    });

    test('desabilitar desregistra o atalho', () async {
      await service.start();
      await store.setDictationEnabled(value: false);
      await service.applySettings();
      expect(service.hotkeyStatus.registered, isFalse);
    });

    test('trocar o modo re-registra com o novo modo', () async {
      await store.setDictationMode(DictationMode.toggle);
      await service.applySettings();
      expect(native.registeredMode, DictationMode.toggle);
    });
  });
}

class _PasteFailNative extends FakeRbNative {
  @override
  Future<void> pasteText(String text) async => throw const RbNativeException(
    RbNativeErrorCode.pasteFailed,
    'sem acessibilidade',
  );
}

class _HotkeyFailNative extends FakeRbNative {
  @override
  Future<void> registerDictationHotkey(
    Hotkey hotkey,
    DictationMode mode,
  ) async => throw const RbNativeException(
    RbNativeErrorCode.hotkeyConflict,
    'atalho em uso',
  );
}
