import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  test('watchNotes retorna fixadas primeiro e depois por data desc', () async {
    final repo = memoryRepo(db);
    await seedNote(db, id: 'a', createdAt: DateTime(2026, 10, 20));
    await seedNote(db, id: 'b', createdAt: DateTime(2026, 10, 22));
    await seedNote(db, id: 'c', pinned: true, createdAt: DateTime(2026));

    final notes = await repo.watchNotes().first;
    expect(notes.map((n) => n.note.id).toList(), ['c', 'b', 'a']);
  });

  test('watchNotes filtra por tag', () async {
    final repo = memoryRepo(db);
    await seedNote(db, id: 'a');
    await seedNote(db, id: 'b');
    await repo.upsertTag(TagsCompanion.insert(id: 't1', name: 'Trabalho'));
    await repo.addTagToNote('a', 't1');

    final filtered = await repo.watchNotes(tagId: 't1').first;
    expect(filtered.map((n) => n.note.id).toList(), ['a']);
    expect(filtered.first.tags.single.name, 'Trabalho');
  });

  test(
    'busca FTS encontra por título e por transcrição, com snippet',
    () async {
      final repo = memoryRepo(db);
      await seedNote(db, id: 'a', title: 'Reunião de planejamento');
      await seedSegment(
        db,
        noteId: 'a',
        content: 'vamos revisar o orçamento trimestral da equipe',
      );

      final byTitle = await repo.search('planejamento');
      expect(byTitle.single.note.id, 'a');

      final byBody = await repo.search('orçamento');
      expect(byBody.single.note.id, 'a');
      expect(byBody.single.snippet, contains('['));

      expect(await repo.search('inexistente'), isEmpty);
      expect(await repo.search('   '), isEmpty);
    },
  );

  test('replaceSegments substitui os segmentos e dispara o FTS', () async {
    final repo = memoryRepo(db);
    await seedNote(db, id: 'a', title: 'Nota');
    await repo.replaceSegments('a', const [
      DraftSegment(
        speaker: SegmentSpeaker.me,
        startMs: 0,
        endMs: 1000,
        content: 'primeiro conteudo',
      ),
    ]);
    expect((await repo.search('primeiro')).single.note.id, 'a');

    await repo.replaceSegments('a', const [
      DraftSegment(
        speaker: SegmentSpeaker.others,
        startMs: 0,
        endMs: 1000,
        content: 'segundo assunto',
      ),
    ]);
    expect(await repo.search('primeiro'), isEmpty);
    expect((await repo.search('segundo')).single.note.id, 'a');
  });

  test('deleteNote remove a nota e limpa o índice FTS', () async {
    final repo = memoryRepo(db);
    await seedNote(db, id: 'a', title: 'apagar');
    await repo.deleteNote('a');
    expect(await repo.search('apagar'), isEmpty);
    expect(await repo.getNote('a'), isNull);
  });

  test('updateTitle reflete na busca por título', () async {
    final repo = memoryRepo(db);
    await seedNote(db, id: 'a', title: 'antigo');
    await repo.updateTitle('a', 'titulo novo');
    expect(await repo.search('antigo'), isEmpty);
    expect((await repo.search('novo')).single.note.id, 'a');
  });

  test('match só no título destaca o título (snippet fallback)', () async {
    final repo = memoryRepo(db);
    await seedNote(db, id: 'a', title: 'Reunião de planejamento');
    await seedSegment(db, noteId: 'a', content: 'conteúdo sem o termo buscado');
    final hit = (await repo.search('planejamento')).single;
    expect(hit.note.id, 'a');
    // Sem match no corpo → o snippet cai para o título destacado.
    expect(hit.snippet, contains('['));
    expect(hit.snippet.toLowerCase(), contains('planejamento'));
  });

  test('replaceSegments repetido recompõe o corpo a cada chamada', () async {
    final repo = memoryRepo(db);
    await seedNote(db, id: 'a', title: 'Nota');
    for (final word in ['alpha', 'beta', 'gamma']) {
      await repo.replaceSegments('a', [
        DraftSegment(
          speaker: SegmentSpeaker.me,
          startMs: 0,
          endMs: 1000,
          content: 'palavra $word',
        ),
      ]);
    }
    expect(await repo.search('alpha'), isEmpty);
    expect(await repo.search('beta'), isEmpty);
    expect((await repo.search('gamma')).single.note.id, 'a');
  });

  test('rebuildSearchIndex repopula o índice do zero', () async {
    final repo = memoryRepo(db);
    await seedNote(db, id: 'a', title: 'Título');
    await repo.replaceSegments('a', const [
      DraftSegment(
        speaker: SegmentSpeaker.me,
        startMs: 0,
        endMs: 1000,
        content: 'corpo pesquisável',
      ),
    ]);
    // Corrompe o índice.
    await db.customStatement('DELETE FROM notes_fts');
    expect(await repo.search('pesquisável'), isEmpty);
    // Reconstrói e volta a encontrar por título e por corpo.
    await db.rebuildSearchIndex();
    expect((await repo.search('título')).single.note.id, 'a');
    expect((await repo.search('pesquisável')).single.note.id, 'a');
  });
}
