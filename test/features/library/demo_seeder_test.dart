import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/diary/data/diary_repository.dart';
import 'package:rbnotes/features/library/data/demo_seeder.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late DemoSeeder seeder;

  setUp(() {
    db = memoryDb();
    notes = NoteRepository(db);
    seeder = DemoSeeder(
      notes: notes,
      noteAi: NoteAiRepository(db),
      library: LibraryRepository(db),
      diary: DiaryRepository(db),
    );
  });
  tearDown(() => db.close());

  test('purgeSeedNotes remove as notas de seed intocadas', () async {
    await seeder.seedIfEmpty();
    expect(await notes.getNote('n1'), isNotNull);

    final removed = await seeder.purgeSeedNotes();
    expect(removed, greaterThan(0));
    for (final id in seeder.seedNoteIds) {
      expect(await notes.getNote(id), isNull, reason: 'seed sumir');
    }
    final meta = await db.select(db.syncMeta).get();
    expect(meta.where((m) => m.entityId == 'n1'), isEmpty);
  });

  test('purgeSeedNotes preserva uma nota de seed editada', () async {
    await seeder.seedIfEmpty();
    await notes.updateTitle('n1', 'Minha reuniao renomeada');

    await seeder.purgeSeedNotes();
    expect(await notes.getNote('n1'), isNotNull);
    expect(await notes.getNote('n2'), isNull);
  });

  test('purgeSeedNotes e idempotente e nao falha em banco sem seed', () async {
    expect(await seeder.purgeSeedNotes(), 0);
  });
}
