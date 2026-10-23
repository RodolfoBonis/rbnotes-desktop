import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';
import 'package:rbnotes/features/ai/data/enrichment_service.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_audio_player.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late NoteAiRepository noteAi;
  late TranscriptionQueue queue;
  late EnrichmentService enrichment;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = memoryDb();
    notes = NoteRepository(db);
    noteAi = NoteAiRepository(db);
    final settings = SettingsStore(prefs);
    final vocab = VocabularyRepository(db);
    queue = TranscriptionQueue(
      native: FakeRbNative(),
      repository: notes,
      settings: settings,
      vocabulary: vocab,
    );
    enrichment = EnrichmentService(
      ai: FakeAiClient(),
      notes: notes,
      noteAi: noteAi,
      vocabulary: vocab,
      settings: settings,
    );
  });

  tearDown(() async {
    await queue.dispose();
    await enrichment.dispose();
    await db.close();
  });

  NoteViewCubit build() => NoteViewCubit(
    notes: notes,
    noteAi: noteAi,
    ai: FakeAiClient(),
    native: FakeRbNative(),
    player: FakeAudioPlayer(),
    queue: queue,
    enrichment: enrichment,
    aiActivity: AiActivity(),
  );

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('retryTranscription reenfileira e a nota volta a ready', () async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'n',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            status: NoteStatus.failed,
            source: NoteSource.recording,
            micWavPath: const Value('/tmp/n.mic.wav'),
          ),
        );
    final cubit = build();
    await cubit.load('n');
    await settle();

    await cubit.retryTranscription();
    await queue.progress.firstWhere((p) => p.isTerminal);
    await settle();

    expect((await notes.getNote('n'))!.status, NoteStatus.ready);
    expect(await notes.getSegments('n'), isNotEmpty);
    await cubit.close();
  });

  test('retrySummary re-enriquece mesmo com auto-resumo desligado', () async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'n2',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            status: NoteStatus.ready,
            source: NoteSource.recording,
            aiStatus: const Value(AiStatus.failed),
          ),
        );
    await notes.replaceSegments('n2', const [
      DraftSegment(
        speaker: SegmentSpeaker.me,
        startMs: 0,
        endMs: 1000,
        content: 'conteudo para resumir',
      ),
    ]);
    final cubit = build();
    await cubit.load('n2');
    await settle();

    await cubit.retrySummary();
    await settle();

    expect((await notes.getNote('n2'))!.aiStatus, AiStatus.ready);
    await cubit.close();
  });
}
