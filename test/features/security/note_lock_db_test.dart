import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';

import '../../helpers/test_db.dart';

void main() {
  test('upgrade v4 → v5 adiciona notes.locked (reparo genérico)', () async {
    final dir = await Directory.systemTemp.createTemp('rbnotes_v5');
    final file = File(p.join(dir.path, 'db.sqlite'));
    addTearDown(() => dir.deleteSync(recursive: true));

    final v4 = AppDatabase.forTesting(NativeDatabase(file));
    await v4.customStatement('SELECT 1'); // força onCreate (schema atual)
    // Simula um banco v4: um banco v4 não tinha o trigger ciente de `locked`
    // (ele referencia `new.locked`), então o derruba antes de remover a coluna.
    await v4.customStatement('DROP TRIGGER IF EXISTS notes_au');
    await v4.customStatement('ALTER TABLE notes DROP COLUMN locked');
    await v4.customStatement('PRAGMA user_version = 4');
    await v4.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    final cols = await migrated.customSelect('PRAGMA table_info(notes)').get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('locked'));
    await migrated.close();
  });

  test('upgrade < v7 recria notes_au para não reindexar bloqueadas', () async {
    final dir = await Directory.systemTemp.createTemp('rbnotes_v7');
    final file = File(p.join(dir.path, 'db.sqlite'));
    addTearDown(() => dir.deleteSync(recursive: true));

    final v6 = AppDatabase.forTesting(NativeDatabase(file));
    await v6.customStatement('SELECT 1'); // onCreate (schema atual)
    // Simula um banco v6 com o trigger antigo (sem o CASE de locked).
    await v6.customStatement('DROP TRIGGER IF EXISTS notes_au');
    await v6.customStatement(
      'CREATE TRIGGER notes_au AFTER UPDATE OF title ON notes BEGIN '
      'UPDATE notes_fts SET title = new.title WHERE rowid = new.rowid; END',
    );
    await v6.customStatement('PRAGMA user_version = 6');
    await v6.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    final repo = NoteRepository(migrated);
    await seedNote(migrated, id: 'm1', title: 'Original');
    await repo.setLocked('m1', locked: true);
    await repo.updateTitle('m1', 'Deveria sumir', autoTitle: true);
    final fts = await migrated
        .customSelect(
          'SELECT title FROM notes_fts WHERE rowid = '
          '(SELECT rowid FROM notes WHERE id = ?1)',
          variables: [const Variable<String>('m1')],
        )
        .getSingle();
    expect(fts.read<String>('title'), '');
    await migrated.close();
  });

  group('FTS exclui notas bloqueadas', () {
    late AppDatabase db;
    late NoteRepository repo;

    setUp(() async {
      db = memoryDb();
      repo = memoryRepo(db);
      await seedNote(db, id: 'n1', title: 'Reunião de orçamento');
      await seedSegment(
        db,
        noteId: 'n1',
        content: 'falamos sobre salários e metas',
      );
    });

    tearDown(() => db.close());

    test('nota some da busca ao bloquear e volta ao desbloquear', () async {
      expect((await repo.search('salários')).map((h) => h.note.id), ['n1']);

      await repo.setLocked('n1', locked: true);
      expect(await repo.search('salários'), isEmpty);
      expect(await repo.search('orçamento'), isEmpty);

      // O índice FTS foi esvaziado para a nota.
      final fts = await db
          .customSelect(
            'SELECT title, body FROM notes_fts WHERE rowid = '
            '(SELECT rowid FROM notes WHERE id = ?1)',
            variables: [const Variable<String>('n1')],
          )
          .getSingle();
      expect(fts.read<String>('title'), '');
      expect(fts.read<String>('body'), '');

      await repo.setLocked('n1', locked: false);
      expect((await repo.search('salários')).map((h) => h.note.id), ['n1']);
      expect((await repo.search('orçamento')).map((h) => h.note.id), ['n1']);
    });

    // M11: o trigger `notes_au` não reindexa o título de uma nota bloqueada.
    test('updateTitle de nota bloqueada mantém o FTS vazio', () async {
      await repo.setLocked('n1', locked: true);
      // Enriquecimento/renome pode mexer no título da nota bloqueada.
      await repo.updateTitle('n1', 'Projeto Confidencial', autoTitle: true);

      final fts = await db
          .customSelect(
            'SELECT title FROM notes_fts WHERE rowid = '
            '(SELECT rowid FROM notes WHERE id = ?1)',
            variables: [const Variable<String>('n1')],
          )
          .getSingle();
      expect(fts.read<String>('title'), '');
      expect(await repo.search('Confidencial'), isEmpty);
    });

    test('setLocked marca a coluna e bumpa updatedAt', () async {
      final before = (await repo.getNote('n1'))!;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await repo.setLocked('n1', locked: true);
      final after = (await repo.getNote('n1'))!;
      expect(after.locked, isTrue);
      expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
    });
  });
}
