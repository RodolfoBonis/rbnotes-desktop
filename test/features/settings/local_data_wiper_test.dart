import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/local_data_wiper.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_audio_sync.dart';
import '../../helpers/test_db.dart';

class _FakeSyncClient implements SyncClient {
  @override
  Future<PullResult> pull({String? since}) async =>
      PullResult(changes: const [], cursor: since ?? '0');

  @override
  Future<PushResult> push(List<SyncChange> changes) async =>
      const PushResult(applied: [], conflicts: []);
}

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late SettingsStore settings;
  late SharedPreferences prefs;
  late AppPaths paths;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = memoryDb();
    notes = NoteRepository(db);
    settings = SettingsStore(prefs);
    tmp = await Directory.systemTemp.createTemp('rbnotes_wipe');
    paths = AppPaths.forTesting(tmp);
    await Directory(paths.recordingsDir).create(recursive: true);
    await Directory(paths.audioCacheDir).create(recursive: true);
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('apaga banco, arquivos, caches, cursor e fila de áudio', () async {
    // Nota com arquivo de áudio.
    final audioFile = File('${paths.recordingsDir}/n1.m4a')
      ..writeAsStringSync('bytes');
    final cacheFile = File('${paths.audioCacheDir}/n1.m4a')
      ..writeAsStringSync('bytes');
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'n1',
            createdAt: DateTime(2026, 6),
            updatedAt: DateTime(2026, 6),
            status: NoteStatus.ready,
            source: NoteSource.recording,
            playbackPath: Value(audioFile.path),
          ),
        );
    await db
        .into(db.vocabulary)
        .insert(
          VocabularyCompanion.insert(
            id: 'v1',
            term: 'Kubernetes',
            updatedAt: DateTime(2026, 6),
          ),
        );

    // Estado de sync + fila de áudio.
    await prefs.setString('sync.cursor', '99');
    await prefs.setString('sync.watermark', '2026-06-01T00:00:00Z');
    final sync = SyncService(
      client: _FakeSyncClient(),
      store: SyncLocalStore(db),
      settings: settings,
      prefs: prefs,
    );
    await settings.setSendAudio(value: true);
    final queue = AudioUploadQueue(
      audio: FakeAudioSync()..failUploads = true,
      settings: settings,
      prefs: prefs,
      notes: notes,
    );
    await queue.enqueue('n1', audioFile.path);

    final wiper = LocalDataWiper(
      db: db,
      notes: notes,
      paths: paths,
      sync: sync,
      audioQueue: queue,
    );
    await wiper.wipe();

    expect(await notes.getAllNotes(), isEmpty);
    expect(await db.select(db.vocabulary).get(), isEmpty);
    expect(audioFile.existsSync(), isFalse);
    expect(cacheFile.existsSync(), isFalse);
    expect(prefs.getString('sync.cursor'), isNull);
    expect(prefs.getString('sync.watermark'), isNull);
    expect(queue.pending, isEmpty);

    await sync.dispose();
    queue.dispose();
  });
}
