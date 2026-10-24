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
    // Simula um banco v4: remove a coluna nova e marca a versão antiga.
    await v4.customStatement('ALTER TABLE notes DROP COLUMN locked');
    await v4.customStatement('PRAGMA user_version = 4');
    await v4.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    final cols = await migrated.customSelect('PRAGMA table_info(notes)').get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('locked'));
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
            variables: [Variable<String>('n1')],
          )
          .getSingle();
      expect(fts.read<String>('title'), '');
      expect(fts.read<String>('body'), '');

      await repo.setLocked('n1', locked: false);
      expect((await repo.search('salários')).map((h) => h.note.id), ['n1']);
      expect((await repo.search('orçamento')).map((h) => h.note.id), ['n1']);
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
