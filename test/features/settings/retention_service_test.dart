import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/retention_service.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late SettingsStore settings;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = memoryDb();
    notes = NoteRepository(db);
    settings = SettingsStore(await SharedPreferences.getInstance());
    tmp = await Directory.systemTemp.createTemp('retention_test');
  });
  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<String> seed(
    String id, {
    required DateTime createdAt,
    NoteStatus status = NoteStatus.ready,
    bool withFiles = false,
  }) async {
    String? playback;
    if (withFiles) {
      final f = File('${tmp.path}/$id.m4a')..writeAsStringSync('audio');
      playback = f.path;
    }
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            createdAt: createdAt,
            updatedAt: createdAt,
            status: status,
            source: NoteSource.recording,
            playbackPath: Value(playback),
          ),
        );
    return playback ?? '';
  }

  group('retentionDays', () {
    test('mapeia os rótulos do design', () {
      expect(RetentionService.retentionDays('30 dias'), 30);
      expect(RetentionService.retentionDays('90 dias'), 90);
      expect(RetentionService.retentionDays('1 ano'), 365);
      expect(RetentionService.retentionDays('Para sempre'), isNull);
    });
  });

  group('retenção', () {
    test(
      'apaga notas mais antigas que o limite e preserva as recentes',
      () async {
        final now = DateTime(2026, 6);
        await settings.setRetention('30 dias');
        await seed('old', createdAt: now.subtract(const Duration(days: 40)));
        await seed('new', createdAt: now.subtract(const Duration(days: 5)));

        final service = RetentionService(settings: settings, notes: notes);
        await service.sweep(now: now);

        expect(await notes.getNote('old'), isNull);
        expect(await notes.getNote('new'), isNotNull);
      },
    );

    test('"Para sempre" nunca apaga', () async {
      final now = DateTime(2026, 6);
      await settings.setRetention('Para sempre');
      await seed('ancient', createdAt: DateTime(2000));

      await RetentionService(settings: settings, notes: notes).sweep(now: now);

      expect(await notes.getNote('ancient'), isNotNull);
    });

    test('remove o arquivo de áudio da nota expirada', () async {
      final now = DateTime(2026, 6);
      await settings.setRetention('30 dias');
      final path = await seed(
        'old',
        createdAt: now.subtract(const Duration(days: 40)),
        withFiles: true,
      );
      expect(File(path).existsSync(), isTrue);

      await RetentionService(settings: settings, notes: notes).sweep(now: now);

      expect(File(path).existsSync(), isFalse);
    });
  });

  group('apagar áudio após transcrever', () {
    test('remove o áudio e zera os caminhos das notas prontas', () async {
      await settings.setRetention('Para sempre');
      await settings.setDeleteAudioAfter(value: true);
      final path = await seed(
        'ready',
        createdAt: DateTime(2026, 6),
        withFiles: true,
      );

      await RetentionService(settings: settings, notes: notes).sweep();

      expect(File(path).existsSync(), isFalse);
      expect((await notes.getNote('ready'))!.playbackPath, isNull);
    });

    test('não mexe no áudio quando a opção está desligada', () async {
      await settings.setRetention('Para sempre');
      await settings.setDeleteAudioAfter(value: false);
      final path = await seed(
        'ready',
        createdAt: DateTime(2026, 6),
        withFiles: true,
      );

      await RetentionService(settings: settings, notes: notes).sweep();

      expect(File(path).existsSync(), isTrue);
      expect((await notes.getNote('ready'))!.playbackPath, isNotNull);
    });

    test('ignora notas ainda não prontas', () async {
      await settings.setRetention('Para sempre');
      await settings.setDeleteAudioAfter(value: true);
      final path = await seed(
        'pending',
        createdAt: DateTime(2026, 6),
        status: NoteStatus.transcribing,
        withFiles: true,
      );

      await RetentionService(settings: settings, notes: notes).sweep();

      expect(File(path).existsSync(), isTrue);
    });
  });
}
