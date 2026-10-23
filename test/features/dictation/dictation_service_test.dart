import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
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

  test('pasteLast recola o último texto ditado', () async {
    await service.start();
    native.emitDictation(const DictationStopped('/tmp/d.wav'));
    await pump();
    native.pastedTexts.clear();
    await service.pasteLast();
    expect(native.pastedTexts.single, service.lastDictatedText);
  });
}
