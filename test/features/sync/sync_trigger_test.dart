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

  test(
    'aplicar um pull NÃO redispara o trigger (sem loop de sync a cada ~4s)',
    () async {
      // Spy que conta requestSync mas mantém o syncNow/pull reais herdados.
      final spyService = _SpySyncService(
        client: _OneChangeClient(),
        store: SyncLocalStore(db),
        settings: SettingsStore(prefs),
        prefs: prefs,
      );
      final spyTrigger = SyncTrigger(db: db, sync: spyService)..start();

      await spyService.syncNow();
      // Deixa a notificação de tableUpdates + o dreno da flag rodarem.
      await tick();
      await tick();

      // A nota foi mesmo aplicada localmente (o pull escreveu em `notes`)...
      expect(await notes.getNote('remote1'), isNotNull);
      // ...e mesmo assim o trigger não reagiu a essa escrita.
      expect(spyService.calls, 0);

      await spyTrigger.dispose();
      await spyService.dispose();
    },
  );
}

/// Cliente de pull que devolve exatamente uma mudança (uma nota) na primeira
/// chamada e nada depois, para exercitar a aplicação de um pull.
class _OneChangeClient implements SyncClient {
  bool _served = false;

  @override
  Future<PullResult> pull({String? since}) async {
    if (_served) return PullResult(changes: const [], cursor: since ?? '1');
    _served = true;
    return PullResult(
      changes: [
        SyncChange(
          entity: 'note',
          id: 'remote1',
          updatedAt: DateTime(2026, 10, 23, 12),
          deleted: false,
          data: const {
            'id': 'remote1',
            'title': 'Vinda do servidor',
            'createdAt': '2026-10-23T12:00:00.000Z',
            'durationMs': 0,
            'status': 'ready',
            'source': 'recording',
          },
        ),
      ],
      cursor: '1',
    );
  }

  @override
  Future<PushResult> push(List<SyncChange> changes) async =>
      const PushResult(applied: [], conflicts: []);
}
