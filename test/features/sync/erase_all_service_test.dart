import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/auth/auth_tokens.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/session_events.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/erase_all_service.dart';
import 'package:rbnotes/features/settings/data/local_data_wiper.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/sync/data/api_sync_client.dart';
import 'package:rbnotes/features/sync/data/audio_sync.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/local_server.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late SettingsStore settings;
  late SharedPreferences prefs;
  late AppPaths paths;
  late Directory tmp;
  LocalServer? server;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = memoryDb();
    notes = NoteRepository(db);
    settings = SettingsStore(prefs);
    tmp = await Directory.systemTemp.createTemp('rbnotes_erase');
    paths = AppPaths.forTesting(tmp);
    await Directory(paths.recordingsDir).create(recursive: true);
    await Directory(paths.audioCacheDir).create(recursive: true);
  });

  tearDown(() async {
    await server?.close();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ApiClient apiFor(String base) => ApiClient(
    baseUrl: '$base/v1',
    tokens: MemoryTokenStore(
      const AuthTokens(accessToken: 'a', refreshToken: 'r'),
    ),
    oidc: OidcClient(
      dio: Dio(),
      issuer: '$base/realms/rbnotes',
      clientId: 'rbnotes-desktop',
      redirectUri: 'http://127.0.0.1:53682/callback',
    ),
    events: SessionEvents(),
  );

  Future<void> seedNoteWithAudio(String id) async {
    final f = File('${paths.recordingsDir}/$id.m4a')
      ..writeAsStringSync('bytes');
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            createdAt: DateTime(2026, 6),
            updatedAt: DateTime(2026, 6),
            status: NoteStatus.ready,
            source: NoteSource.recording,
            playbackPath: Value(f.path),
          ),
        );
  }

  test('ordem: tombstones → push → DELETE áudio → limpeza + reset', () async {
    final events = <String>[];
    server = await LocalServer.start((req) async {
      events.add('${req.method} ${req.uri.path}');
      await req.drain<void>();
      if (req.uri.path.endsWith('/sync/push')) {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"applied":[],"conflicts":[]}');
      } else {
        req.response.statusCode = 204; // DELETE áudio (idempotente)
      }
      await req.response.close();
    });

    await seedNoteWithAudio('n1');
    await prefs.setString('sync.cursor', '42');

    final api = apiFor(server!.base);
    final sync = SyncService(
      client: ApiSyncClient(api),
      store: SyncLocalStore(db),
      settings: settings,
      prefs: prefs,
    );
    final wiper = LocalDataWiper(
      db: db,
      notes: notes,
      paths: paths,
      sync: sync,
    );
    final service = EraseAllService(
      notes: notes,
      store: SyncLocalStore(db),
      wiper: wiper,
      sync: sync,
      audio: AudioSync(api),
    );

    final steps = <EraseProgress>[];
    final result = await service.eraseAll(onProgress: steps.add);

    expect(result, EraseResult.done);
    final pushIdx = events.indexWhere((e) => e.contains('/sync/push'));
    final delIdx = events.indexWhere(
      (e) => e == 'DELETE /v1/notes/n1/audio',
    );
    expect(pushIdx, greaterThanOrEqualTo(0));
    expect(delIdx, greaterThan(pushIdx));
    // Limpeza local + reset do cursor.
    expect(await db.select(db.notes).get(), isEmpty);
    expect(prefs.getString('sync.cursor'), isNull);
    // Progresso cobriu as 4 etapas.
    expect(steps.last.step, steps.last.total);

    await sync.dispose();
  });

  test('offline: apaga só localmente quando o dono confirma', () async {
    await seedNoteWithAudio('n1');
    // Backend inacessível → erro de rede no push.
    final api = apiFor('http://127.0.0.1:1');
    final sync = SyncService(
      client: ApiSyncClient(api),
      store: SyncLocalStore(db),
      settings: settings,
      prefs: prefs,
    );
    final service = EraseAllService(
      notes: notes,
      store: SyncLocalStore(db),
      wiper: LocalDataWiper(db: db, notes: notes, paths: paths, sync: sync),
      sync: sync,
      audio: AudioSync(api),
    );

    final pending = await service.eraseAll();
    expect(pending, EraseResult.offlinePending);
    // Tombstones já marcados; a limpeza local só acontece se o dono confirmar.
    final result = await service.finishLocalOnly();
    expect(result, EraseResult.doneLocalOnly);
    expect(await db.select(db.notes).get(), isEmpty);
    await sync.dispose();
  });

  test(
    'offline: cancelar deixa os tombstones para sincronizar depois',
    () async {
      await seedNoteWithAudio('n1');
      final api = apiFor('http://127.0.0.1:1');
      final sync = SyncService(
        client: ApiSyncClient(api),
        store: SyncLocalStore(db),
        settings: settings,
        prefs: prefs,
      );
      final service = EraseAllService(
        notes: notes,
        store: SyncLocalStore(db),
        wiper: LocalDataWiper(db: db, notes: notes, paths: paths, sync: sync),
        sync: sync,
        audio: AudioSync(api),
      );

      final result = await service.eraseAll();
      expect(result, EraseResult.offlinePending);
      // Cancelar = não chamar finishLocalOnly: a nota permanece, porém marcada
      // como excluída (tombstone local para sincronizar depois).
      final row = await (db.select(
        db.notes,
      )..where((n) => n.id.equals('n1'))).getSingle();
      expect(row.deleted, isTrue);
      await sync.dispose();
    },
  );

  test('sem backend: faz só a limpeza local', () async {
    await seedNoteWithAudio('n1');
    final service = EraseAllService(
      notes: notes,
      store: SyncLocalStore(db),
      wiper: LocalDataWiper(db: db, notes: notes, paths: paths),
    );
    final result = await service.eraseAll();
    expect(result, EraseResult.done);
    expect(await db.select(db.notes).get(), isEmpty);
  });
}
