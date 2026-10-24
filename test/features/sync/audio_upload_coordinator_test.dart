import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/sync/data/audio_upload_coordinator.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_audio_sync.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late SettingsStore settings;
  late SharedPreferences prefs;
  late FakeAudioSync audio;
  late AudioUploadQueue queue;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = memoryDb();
    notes = NoteRepository(db);
    settings = SettingsStore(prefs);
    audio = FakeAudioSync();
    await settings.setSendAudio(value: true);
    queue = AudioUploadQueue(
      audio: audio,
      settings: settings,
      prefs: prefs,
      notes: notes,
      backoffBase: const Duration(milliseconds: 1),
    );
    tmp = await Directory.systemTemp.createTemp('audio_upload_test');
  });

  tearDown(() async {
    queue.dispose();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<String> seedWithAudio(String id) async {
    final f = File('${tmp.path}/$id.m4a')..writeAsStringSync('audio-bytes');
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            createdAt: DateTime(2026, 6),
            updatedAt: DateTime(2026, 6),
            durationMs: const Value(1000),
            status: NoteStatus.ready,
            source: NoteSource.recording,
            playbackPath: Value(f.path),
          ),
        );
    return f.path;
  }

  Future<void> drain() async {
    // deixa o process() disparado por enqueue concluir
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('AudioUploadCoordinator', () {
    test('ao terminar a transcrição, enfileira o .m4a (sync ligado)', () async {
      await seedWithAudio('n1');
      final coord = AudioUploadCoordinator(
        queue: queue,
        notes: notes,
        settings: settings,
      );

      await coord.onTranscribed('n1');
      await drain();

      expect(audio.uploaded, contains('n1'));
    });

    test('com sync desligado, não enfileira nada', () async {
      await settings.setSyncEnabled(value: false);
      await seedWithAudio('n1');
      final coord = AudioUploadCoordinator(
        queue: queue,
        notes: notes,
        settings: settings,
      );

      await coord.onTranscribed('n1');
      await drain();

      expect(audio.uploaded, isEmpty);
      expect(queue.pending, isEmpty);
    });

    test('nota sem .m4a local não é enfileirada', () async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: 'no-audio',
              createdAt: DateTime(2026, 6),
              updatedAt: DateTime(2026, 6),
              status: NoteStatus.ready,
              source: NoteSource.recording,
            ),
          );
      final coord = AudioUploadCoordinator(
        queue: queue,
        notes: notes,
        settings: settings,
      );

      await coord.onTranscribed('no-audio');
      await drain();

      expect(queue.pending, isEmpty);
    });
  });

  group('AudioUploadQueue', () {
    test(
      'apaga o áudio local só depois do upload, com delete-after ligado',
      () async {
        await settings.setDeleteAudioAfter(value: true);
        final path = await seedWithAudio('n1');

        await queue.enqueue('n1', path);
        await drain();

        expect(audio.uploaded, contains('n1'));
        expect(File(path).existsSync(), isFalse);
        expect((await notes.getNote('n1'))!.playbackPath, isNull);
      },
    );

    test('mantém o áudio local quando delete-after está desligado', () async {
      await settings.setDeleteAudioAfter(value: false);
      final path = await seedWithAudio('n1');

      await queue.enqueue('n1', path);
      await drain();

      expect(audio.uploaded, contains('n1'));
      expect(File(path).existsSync(), isTrue);
    });

    test('retoma a fila persistida num novo processo (boot)', () async {
      final path = await seedWithAudio('n1');
      await queue.enqueue('n1', path);
      await drain();
      expect(audio.uploaded, contains('n1'));

      // Simula reboot: nova fila com o mesmo prefs/estado persistido.
      final audio2 = FakeAudioSync();
      final path2 = await seedWithAudio('n2');
      final rebooted = AudioUploadQueue(
        audio: audio2,
        settings: settings,
        prefs: prefs,
        notes: notes,
      );
      addTearDown(rebooted.dispose);
      await rebooted.enqueue('n2', path2);
      await drain();

      expect(audio2.uploaded, contains('n2'));
    });
  });

  group('Enviar áudios (pedido B1)', () {
    test('com "Enviar áudios" desligado, não faz upload', () async {
      await settings.setSendAudio(value: false);
      final path = await seedWithAudio('n1');
      await queue.enqueue('n1', path);
      await drain();
      expect(audio.uploaded, isEmpty);
      expect(queue.pending.map((t) => t.noteId), contains('n1'));
    });

    test('expõe o progresso por nota e marca falha para retry', () async {
      audio.failUploads = true;
      final path = await seedWithAudio('n1');
      await queue.enqueue('n1', path);
      await drain();
      final items = queue.current;
      expect(items, isNotEmpty);
      expect(items.first.noteId, 'n1');
      expect(items.first.status, AudioUploadStatus.failed);

      // "Tentar de novo" após o servidor voltar: sobe e limpa a fila.
      audio.failUploads = false;
      await queue.retry();
      await drain();
      expect(audio.uploaded, contains('n1'));
      expect(queue.pending, isEmpty);
    });
  });
}
