import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/diarization_store.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/features/transcription/domain/diarization_mapping.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

void main() {
  group('assignDiarizationLabels', () {
    test('mapeia turnos a segmentos de Outros por maior sobreposição', () {
      final labels = assignDiarizationLabels(
        segments: const [
          (index: 0, startMs: 0, endMs: 2000, isOthers: false), // você
          (index: 1, startMs: 2000, endMs: 4000, isOthers: true),
          (index: 2, startMs: 4000, endMs: 6000, isOthers: true),
          (index: 3, startMs: 6000, endMs: 8000, isOthers: true),
        ],
        turns: const [
          (startMs: 1800, endMs: 4200, speaker: 7),
          (startMs: 4200, endMs: 6200, speaker: 3),
          (startMs: 6000, endMs: 8000, speaker: 7),
        ],
      );
      // Renumerado por ordem de aparição: cluster 7 → Pessoa 1, cluster 3 → 2.
      expect(labels[1], 'Pessoa 1');
      expect(labels[2], 'Pessoa 2');
      expect(labels[3], 'Pessoa 1');
      expect(labels.containsKey(0), isFalse); // "você" não recebe rótulo
    });

    test('sem turnos devolve vazio', () {
      expect(
        assignDiarizationLabels(
          segments: const [(index: 0, startMs: 0, endMs: 1, isOthers: true)],
          turns: const [],
        ),
        isEmpty,
      );
    });
  });

  group('pipeline', () {
    late AppDatabase db;
    late NoteRepository repo;
    late FakeRbNative native;
    late SettingsStore settings;
    late TranscriptionQueue queue;
    late AppPaths paths;
    late Directory tmp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = memoryDb();
      repo = memoryRepo(db);
      native = FakeRbNative();
      settings = SettingsStore(await SharedPreferences.getInstance());
      tmp = await Directory.systemTemp.createTemp('diar_pipe');
      paths = AppPaths.forTesting(tmp);
      await Directory(paths.recordingsDir).create(recursive: true);
      queue = TranscriptionQueue(
        native: native,
        repository: repo,
        settings: settings,
        vocabulary: VocabularyRepository(db),
        paths: paths,
      );
    });

    tearDown(() async {
      await queue.dispose();
      await native.dispose();
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<String> seedWithSystem(String id) async {
      final mic = File('${paths.recordingsDir}/$id.mic.wav')
        ..writeAsStringSync('m');
      final sys = File('${paths.recordingsDir}/$id.system.wav')
        ..writeAsStringSync('s');
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: id,
              createdAt: DateTime(2026, 6),
              updatedAt: DateTime(2026, 6),
              status: NoteStatus.transcribing,
              source: NoteSource.recording,
              micWavPath: Value(mic.path),
              systemWavPath: Value(sys.path),
            ),
          );
      return id;
    }

    Future<void> drain() async {
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test(
      'com Identificar falantes + áudio do sistema, salva o sidecar',
      () async {
        await settings.setIdentifySpeakers(value: true);
        native.diarizationTurns = const [
          SpeakerTurn(
            start: Duration.zero,
            end: Duration(seconds: 2),
            speaker: 0,
          ),
          SpeakerTurn(
            start: Duration(seconds: 2),
            end: Duration(seconds: 4),
            speaker: 1,
          ),
        ];
        await seedWithSystem('n1');
        queue.enqueue('n1');
        await drain();

        final labels = await DiarizationStore(paths).load('n1');
        expect(labels, isNotEmpty);
        expect(labels.values, contains('Pessoa 1'));
      },
    );

    test('com a opção desligada, não diariza', () async {
      await settings.setIdentifySpeakers(value: false);
      native.diarizationTurns = const [
        SpeakerTurn(
          start: Duration.zero,
          end: Duration(seconds: 2),
          speaker: 0,
        ),
      ];
      await seedWithSystem('n2');
      queue.enqueue('n2');
      await drain();
      expect(await DiarizationStore(paths).load('n2'), isEmpty);
    });

    test('falha na diarização mantém Outros (sem sidecar)', () async {
      await settings.setIdentifySpeakers(value: true);
      native.diarizationModelDownloaded = false; // diarize lança
      await seedWithSystem('n3');
      queue.enqueue('n3');
      await drain();
      // Nota transcreve normalmente; diarização falhou → sem sidecar.
      expect((await repo.getNote('n3'))!.status, NoteStatus.ready);
      expect(await DiarizationStore(paths).load('n3'), isEmpty);
    });
  });
}
