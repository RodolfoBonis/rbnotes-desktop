import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/enrichment_service.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

/// `AiClient` controlável: `enrich` devolve [result] (ou lança, se null).
class _StubAiClient implements AiClient {
  _StubAiClient(this.result);
  NoteAi? result;

  @override
  Future<NoteAi> enrich(EnrichRequest request) async {
    final r = result;
    if (r == null) throw StateError('sem resultado');
    return r;
  }

  @override
  Stream<AiDelta> chat({
    required String noteId,
    required List<AiSegment> segments,
    required List<String> speakers,
    required String message,
  }) => const Stream.empty();

  @override
  Stream<AiDelta> ask({
    required String question,
    required List<AskCandidate> candidates,
  }) => const Stream.empty();

  @override
  Future<CollectionRuleResult> collectionRule(String description) async =>
      throw UnimplementedError();

  @override
  Future<DiaryMonth> diaryMonth({
    required String month,
    required List<String> entries,
  }) async => throw UnimplementedError();

  @override
  Future<String> dailyPrompt(DateTime date) async => throw UnimplementedError();
}

const _empty = NoteAi(
  title: '',
  tldr: '',
  points: [],
  actions: [],
  decisions: [],
  questions: [],
  speakerNames: SpeakerNames(others: [], segments: []),
);

const _good = NoteAi(
  title: 'Bom titulo',
  tldr: 'Um resumo de verdade.',
  points: ['p1'],
  actions: [],
  decisions: [],
  questions: [],
  speakerNames: SpeakerNames(others: [], segments: []),
);

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late NoteAiRepository noteAi;
  late SettingsStore settings;

  setUp(() async {
    db = memoryDb();
    notes = NoteRepository(db);
    noteAi = NoteAiRepository(db);
    SharedPreferences.setMockInitialValues({});
    settings = SettingsStore(await SharedPreferences.getInstance());
  });
  tearDown(() => db.close());

  EnrichmentService make(NoteAi? result) => EnrichmentService(
    ai: _StubAiClient(result),
    notes: notes,
    noteAi: noteAi,
    vocabulary: VocabularyRepository(db),
    settings: settings,
  );

  Future<void> seedNoteWithSegment(String id) async {
    await seedNote(db, id: id);
    await notes.replaceSegments(id, const [
      DraftSegment(
        speaker: SegmentSpeaker.me,
        startMs: 0,
        endMs: 1000,
        content: 'oi',
      ),
    ]);
  }

  test('resumo vazio nunca é salvo nem marcado ready: vira failed', () async {
    await seedNoteWithSegment('n1');
    await make(_empty).enrichNote('n1', force: true);

    expect(await noteAi.getNoteAi('n1'), isNull, reason: 'não grava {}');
    final note = await notes.getNote('n1');
    expect(note!.aiStatus, AiStatus.failed);
    expect(note.title, '', reason: 'título não é atualizado com resumo vazio');
  });

  test('resumo com conteúdo é salvo e marca ready + título', () async {
    await seedNoteWithSegment('n2');
    await make(_good).enrichNote('n2', force: true);

    final ai = await noteAi.getNoteAi('n2');
    expect(ai, isNotNull);
    expect(ai!.title, 'Bom titulo');
    final note = await notes.getNote('n2');
    expect(note!.aiStatus, AiStatus.ready);
    expect(note.title, 'Bom titulo');
  });

  test('boot repara note_ai vazio marcado ready (bug do envelope)', () async {
    // Estado deixado pelo bug: nota ready, note_ai {} (sem título/tldr).
    await seedNoteWithSegment('n3');
    await notes.setAiStatus('n3', AiStatus.ready);
    await noteAi.saveNoteAi('n3', _empty);
    expect(await noteAi.getNoteAi('n3'), isNotNull);

    await make(_good).requeuePending();
    // Deixa os enrich (unawaited) concluírem.
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final ai = await noteAi.getNoteAi('n3');
    expect(ai, isNotNull);
    expect(ai!.title, 'Bom titulo', reason: 're-enriquecido com resumo bom');
    expect((await notes.getNote('n3'))!.aiStatus, AiStatus.ready);
  });

  test(
    'repara apaga o note_ai vazio para não dar push (re-enrich falho)',
    () async {
      await seedNoteWithSegment('n4');
      await notes.setAiStatus('n4', AiStatus.ready);
      await noteAi.saveNoteAi('n4', _empty);

      // Stub sem resultado: o re-enrich falha, mas o {} não pode voltar.
      await make(null).requeuePending();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        await noteAi.getNoteAi('n4'),
        isNull,
        reason: 'o {} local foi removido',
      );
      expect((await notes.getNote('n4'))!.aiStatus, AiStatus.failed);
    },
  );

  test('note_ai com conteúdo marcado ready não é tocado no boot', () async {
    await seedNoteWithSegment('n5');
    await notes.setAiStatus('n5', AiStatus.ready);
    await noteAi.saveNoteAi('n5', _good);

    await make(_empty).requeuePending(); // se re-enriquecesse, viraria failed
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect((await notes.getNote('n5'))!.aiStatus, AiStatus.ready);
    expect((await noteAi.getNoteAi('n5'))!.title, 'Bom titulo');
  });
}
