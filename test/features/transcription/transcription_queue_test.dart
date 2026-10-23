import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepositoryQueueHarness h;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = memoryDb();
    h = NoteRepositoryQueueHarness(db, await SharedPreferences.getInstance());
  });
  tearDown(() async {
    await h.queue.dispose();
    await db.close();
  });

  Future<void> seedRecording(String id, {bool withSystem = false}) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            status: NoteStatus.transcribing,
            source: NoteSource.recording,
            micWavPath: Value('/tmp/$id.mic.wav'),
            systemWavPath: withSystem
                ? Value('/tmp/$id.system.wav')
                : const Value.absent(),
          ),
        );
  }

  test('transcreve, salva segmentos, gera título e marca ready', () async {
    await seedRecording('n1');
    h.queue.enqueue('n1');
    final result = await h.queue.progress.firstWhere((p) => p.done || p.failed);
    expect(result.failed, isFalse);

    final note = await h.repo.getNote('n1');
    expect(note!.status, NoteStatus.ready);
    expect(note.title, isNotEmpty);
    final segments = await h.repo.getSegments('n1');
    expect(segments, isNotEmpty);
    expect(segments.every((s) => s.speaker == SegmentSpeaker.me), isTrue);
  });

  test('com áudio do sistema junta falantes eu/outros', () async {
    await seedRecording('n2', withSystem: true);
    h.queue.enqueue('n2');
    await h.queue.progress.firstWhere((p) => p.done || p.failed);
    final segments = await h.repo.getSegments('n2');
    expect(segments.any((s) => s.speaker == SegmentSpeaker.me), isTrue);
    expect(segments.any((s) => s.speaker == SegmentSpeaker.others), isTrue);
  });

  test('modelo ausente marca a nota como failed', () async {
    h.native.modelDownloaded = false;
    await seedRecording('n3');
    h.queue.enqueue('n3');
    final result = await h.queue.progress.firstWhere((p) => p.done || p.failed);
    expect(result.failed, isTrue);
    expect((await h.repo.getNote('n3'))!.status, NoteStatus.failed);
  });
}

class NoteRepositoryQueueHarness {
  NoteRepositoryQueueHarness(AppDatabase db, SharedPreferences prefs)
    : repo = memoryRepo(db),
      native = FakeRbNative(),
      settings = SettingsStore(prefs) {
    queue = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: settings,
    );
  }

  final NoteRepository repo;
  final FakeRbNative native;
  final SettingsStore settings;
  late final TranscriptionQueue queue;
}
