import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:rbnotes/features/sync/data/sync_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

/// Espiona `requestSync`: o contrato do trigger é chamá-lo nas escritas de
/// entidades sincronizáveis (o respeito a "Sincronizar desligado" é do
/// SyncService e já é coberto em sync_service_test).
class _SpySyncService extends SyncService {
  _SpySyncService({
    required super.client,
    required super.store,
    required super.settings,
    required super.prefs,
  });

  int calls = 0;

  @override
  void requestSync() => calls++;
}

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late SharedPreferences prefs;
  late _SpySyncService service;
  late SyncTrigger trigger;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = memoryDb();
    notes = NoteRepository(db);
    service = _SpySyncService(
      client: const FakeSyncClient(),
      store: SyncLocalStore(db),
      settings: SettingsStore(prefs),
      prefs: prefs,
    );
    trigger = SyncTrigger(db: db, sync: service)..start();
  });

  tearDown(() async {
    await trigger.dispose();
    await service.dispose();
    await db.close();
  });

  Future<void> insertNote(String id) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: id,
          createdAt: DateTime(2026, 6),
          updatedAt: DateTime(2026, 6),
          status: NoteStatus.ready,
          source: NoteSource.recording,
        ),
      );

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 50));

  // Aquece o banco (dispara a semente de pastas) e zera o contador para que
  // cada teste meça só a sua própria mutação.
  Future<void> warmUpAndReset() async {
    await insertNote('warm');
    await tick();
    service.calls = 0;
  }

  test('mutação não-criação (favorito) chama requestSync', () async {
    await warmUpAndReset();

    await notes.setFavorite('warm', favorite: true);
    await tick();

    expect(service.calls, greaterThan(0));
  });

  test('exclusão de nota chama requestSync', () async {
    await warmUpAndReset();

    await notes.deleteNote('warm');
    await tick();

    expect(service.calls, greaterThan(0));
  });

  test(
    'escrita em tabela não sincronizável (tags) NÃO chama requestSync',
    () async {
      await warmUpAndReset();

      await notes.upsertTag(TagsCompanion.insert(id: 't1', name: 'Projeto'));
      await tick();

      expect(service.calls, 0);
    },
  );

  test('edição de segmentos chama requestSync', () async {
    await warmUpAndReset();

    await notes.replaceSegments('warm', const [
      DraftSegment(
        speaker: SegmentSpeaker.me,
        startMs: 0,
        endMs: 500,
        content: 'oi',
      ),
    ]);
    await tick();

    expect(service.calls, greaterThan(0));
  });
}
