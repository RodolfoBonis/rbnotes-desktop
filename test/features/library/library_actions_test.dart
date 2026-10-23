import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late LibraryCubit cubit;

  Future<void> seed(String id, {String title = 'Nota', bool fav = false}) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: id,
          title: Value(title),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          status: NoteStatus.ready,
          source: NoteSource.recording,
          favorite: Value(fav),
        ),
      );

  setUp(() {
    db = memoryDb();
    notes = NoteRepository(db);
    cubit = LibraryCubit(
      notes: notes,
      noteAi: NoteAiRepository(db),
      library: LibraryRepository(db),
    );
  });
  tearDown(() async {
    await cubit.close();
    await db.close();
  });

  test('deleteNote faz soft-delete (some da UI + tombstone)', () async {
    await seed('a');
    await cubit.deleteNote('a');
    final raw = await (db.select(db.notes)..where((n) => n.id.equals('a')))
        .getSingleOrNull();
    expect(raw, isNotNull);
    expect(raw!.deleted, isTrue);
    expect(await notes.getAllNotes(), isEmpty); // some da lista
  });

  test('moveToFolder e toggleFavorite persistem', () async {
    await seed('b');
    await cubit.moveToFolder('b', 'trabalho');
    expect((await notes.getNote('b'))!.folderId, 'trabalho');

    final note = (await notes.getNote('b'))!;
    await cubit.toggleFavorite(note);
    expect((await notes.getNote('b'))!.favorite, isTrue);
  });

  test('renameNote ignora vazio e salva o titulo limpo', () async {
    await seed('c', title: 'Velho');
    await cubit.renameNote('c', '   ');
    expect((await notes.getNote('c'))!.title, 'Velho');
    await cubit.renameNote('c', '  Novo nome ');
    expect((await notes.getNote('c'))!.title, 'Novo nome');
  });

  test('duplicateNote copia nota e segmentos', () async {
    await seed('d', title: 'Original');
    await notes.replaceSegments('d', const [
      DraftSegment(
        speaker: SegmentSpeaker.me,
        startMs: 0,
        endMs: 1000,
        content: 'ola mundo',
      ),
    ]);
    final newId = await cubit.duplicateNote('d');
    expect(newId, isNotNull);
    final copy = await notes.getNote(newId!);
    expect(copy!.title, 'Original (cópia)');
    expect(copy.favorite, isFalse);
    final segs = await notes.getSegments(newId);
    expect(segs.single.content, 'ola mundo');
  });

  test('transcriptText monta o texto por falante', () async {
    await seed('e');
    await notes.replaceSegments('e', const [
      DraftSegment(
        speaker: SegmentSpeaker.me,
        startMs: 0,
        endMs: 500,
        content: 'primeira fala',
      ),
      DraftSegment(
        speaker: SegmentSpeaker.others,
        startMs: 500,
        endMs: 900,
        content: 'resposta',
      ),
    ]);
    final text = await cubit.transcriptText('e');
    expect(text, contains('primeira fala'));
    expect(text, contains('Outros: resposta'));
  });
}
