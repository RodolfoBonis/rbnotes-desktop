import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late NoteAiRepository noteAi;

  setUp(() async {
    db = memoryDb();
    notes = NoteRepository(db);
    noteAi = NoteAiRepository(db);
    await seedNote(db, id: 'n', title: 'Nota');
  });
  tearDown(() => db.close());

  test('updateSegmentContent edita o texto e reindexa o FTS', () async {
    await notes.replaceSegments('n', const [
      DraftSegment(
        speaker: SegmentSpeaker.me,
        startMs: 0,
        endMs: 1000,
        content: 'palavra original',
      ),
    ]);
    final seg = (await notes.getSegments('n')).single;
    await notes.updateSegmentContent('n', seg.id, 'palavra corrigida');

    expect((await notes.getSegments('n')).single.content, 'palavra corrigida');
    // FTS reindexado: busca o novo termo, não o antigo.
    expect((await notes.search('corrigida')).single.note.id, 'n');
    expect(await notes.search('original'), isEmpty);
  });

  test('updateAction e deleteAction (texto, responsável, prazo, apagar)',
      () async {
    await db
        .into(db.actions)
        .insert(
          ActionsCompanion.insert(
            id: 'a1',
            noteId: 'n',
            content: 'Enviar proposta',
            updatedAt: DateTime(2026),
          ),
        );
    final due = DateTime(2026, 11);
    await noteAi.updateAction(
      'a1',
      content: 'Enviar proposta revisada',
      owner: 'Você',
      due: due,
    );
    var rows = await noteAi.watchActions('n').first;
    expect(rows.single.content, 'Enviar proposta revisada');
    expect(rows.single.owner, 'Você');
    expect(rows.single.due, due);

    await noteAi.updateAction('a1', clearOwner: true, clearDue: true);
    rows = await noteAi.watchActions('n').first;
    expect(rows.single.owner, isNull);
    expect(rows.single.due, isNull);

    await noteAi.deleteAction('a1');
    expect(await noteAi.watchActions('n').first, isEmpty);
  });

  test('speakerNames + speakersJson refletem a renomeação (via repos)',
      () async {
    await notes.setSpeakers('n', 'Você\u001fCamila');
    await noteAi.saveNoteAi(
      'n',
      const NoteAi(
        title: 'Nota',
        tldr: 't',
        points: [],
        actions: [],
        decisions: [],
        questions: [],
        speakerNames: SpeakerNames(
          others: ['Camila'],
          segments: [
            SpeakerSegment(index: 0, speaker: 'Camila', inferred: true),
          ],
        ),
      ),
    );

    // Simula o efeito de renameSpeaker('Camila','Cris').
    final ai = (await noteAi.getNoteAi('n'))!;
    await noteAi.saveNoteAi(
      'n',
      NoteAi(
        title: ai.title,
        tldr: ai.tldr,
        points: ai.points,
        actions: ai.actions,
        decisions: ai.decisions,
        questions: ai.questions,
        quote: ai.quote,
        speakerNames: const SpeakerNames(
          others: ['Cris'],
          segments: [
            SpeakerSegment(index: 0, speaker: 'Cris', inferred: true),
          ],
        ),
      ),
    );
    await notes.setSpeakers('n', 'Você\u001fCris');

    expect((await noteAi.getNoteAi('n'))!.speakerNames.others, ['Cris']);
    expect((await notes.getNote('n'))!.speakersJson, contains('Cris'));
  });
}
