import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/network/api_error.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_mappers.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:rbnotes/features/sync/data/sync_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

class _FakeSyncClient implements SyncClient {
  List<List<SyncChange>> pushed = [];
  List<PullResult> pulls = [];
  PushResult pushResult = const PushResult(applied: [], conflicts: []);
  Exception? pullError;
  Exception? pushError;

  @override
  Future<PullResult> pull({String? since}) async {
    if (pullError != null) throw pullError!;
    if (pulls.isNotEmpty) return pulls.removeAt(0);
    return PullResult(changes: const [], cursor: since ?? '0');
  }

  @override
  Future<PushResult> push(List<SyncChange> changes) async {
    pushed.add(changes);
    if (pushError != null) throw pushError!;
    return pushResult;
  }
}

void main() {
  late AppDatabase db;
  late SettingsStore settings;
  late SharedPreferences prefs;
  late _FakeSyncClient client;
  late SyncService service;

  final t1 = DateTime(2026, 10, 23, 12);
  final t2 = DateTime(2026, 10, 23, 13);

  setUp(() async {
    db = memoryDb();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settings = SettingsStore(prefs);
    client = _FakeSyncClient();
    service = SyncService(
      client: client,
      store: SyncLocalStore(db),
      settings: settings,
      prefs: prefs,
      backoffBase: const Duration(milliseconds: 1),
    );
  });

  tearDown(() async {
    await service.dispose();
    await db.close();
  });

  Future<void> insertNote(String id, {String title = '', DateTime? at}) {
    final when = at ?? t1;
    return db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            title: Value(title),
            createdAt: when,
            updatedAt: when,
            status: NoteStatus.ready,
            source: NoteSource.recording,
          ),
        );
  }

  test('respeita "Sincronizar" desligado', () async {
    await settings.setSyncEnabled(value: false);
    await service.syncNow(manual: true);
    expect(client.pushed, isEmpty);
    expect(service.current.phase, SyncPhase.disabled);
  });

  test('pull aplica mudanças e avança o cursor', () async {
    client.pulls.add(
      PullResult(
        changes: [
          SyncChange(
            entity: SyncEntities.folder,
            id: 'f-new',
            updatedAt: t2,
            deleted: false,
            data: const {
              'name': 'Nova',
              'colorHex': '#111111',
              'sortOrder': 9,
              'hidden': false,
            },
          ),
        ],
        cursor: '42',
      ),
    );
    await service.syncNow();
    final folder = await (db.select(
      db.folders,
    )..where((f) => f.id.equals('f-new'))).getSingleOrNull();
    expect(folder?.name, 'Nova');
    expect(prefs.getString('sync.cursor'), '42');
    expect(service.current.phase, SyncPhase.idle);
    expect(service.current.lastSyncAt, isNotNull);
  });

  test('push coleta mudanças locais e envia', () async {
    await insertNote('n1', title: 'Local');
    await service.syncNow();
    expect(client.pushed, isNotEmpty);
    final ids = client.pushed.expand((b) => b).map((c) => c.id).toList();
    expect(ids, contains('n1'));
  });

  test('conflito do servidor é aplicado localmente', () async {
    await insertNote('n1', title: 'Local', at: t1);
    client.pushResult = PushResult(
      applied: const [],
      conflicts: [
        SyncChange(
          entity: SyncEntities.note,
          id: 'n1',
          updatedAt: t2,
          deleted: false,
          data: const {
            'title': 'Servidor venceu',
            'status': 'ready',
            'source': 'recording',
          },
        ),
      ],
    );
    await service.syncNow();
    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals('n1'))).getSingle();
    expect(note.title, 'Servidor venceu');
  });

  test('falha de rede → offline; erro HTTP → error', () async {
    client.pullError = const ApiError.network();
    await service.syncNow(manual: true);
    expect(service.current.phase, SyncPhase.offline);

    client.pullError = const ApiError(statusCode: 500);
    await service.syncNow(manual: true);
    expect(service.current.phase, SyncPhase.error);
  });

  test('falha persiste erro e conta pendências', () async {
    await insertNote('n1', title: 'Local');
    client.pushError = const ApiError(statusCode: 500);
    await service.syncNow(manual: true);
    expect(service.current.phase, SyncPhase.error);
    expect(service.current.pendingCount, greaterThan(0));
    expect(prefs.getInt('sync.pending'), greaterThan(0));
    expect(prefs.getString('sync.last_error'), isNotNull);
  });

  test('sucesso zera pendências e persiste a última sincronização', () async {
    await insertNote('n1', title: 'Local');
    await service.syncNow();
    expect(service.current.pendingCount, 0);
    expect(prefs.getInt('sync.pending'), 0);
    expect(prefs.getString('sync.last_sync_at'), isNotNull);
    expect(prefs.getString('sync.last_error'), isNull);
  });

  test('restaura o último estado conhecido no boot', () async {
    SharedPreferences.setMockInitialValues({
      'sync.last_sync_at': t1.toUtc().toIso8601String(),
      'sync.pending': 3,
      'sync.last_error': 'Falha anterior',
    });
    final prefs2 = await SharedPreferences.getInstance();
    final restored = SyncService(
      client: _FakeSyncClient(),
      store: SyncLocalStore(db),
      settings: SettingsStore(prefs2),
      prefs: prefs2,
    );
    expect(restored.current.pendingCount, 3);
    expect(restored.current.lastSyncAt, isNotNull);
    expect(restored.current.message, 'Falha anterior');
    await restored.dispose();
  });

  group('onEnabledChanged', () {
    test('ligar dispara um sync imediato', () async {
      await settings.setSyncEnabled(value: true);
      service.onEnabledChanged(enabled: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.pushed, isNotEmpty);
    });

    test('desligar cancela e marca disabled', () async {
      service.onEnabledChanged(enabled: false);
      expect(service.current.phase, SyncPhase.disabled);
    });
  });
}
