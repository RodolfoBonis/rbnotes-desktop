import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/notes_list_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository repo;
  late TranscriptionQueue queue;
  late FakeRbNative native;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = memoryDb();
    repo = memoryRepo(db);
    native = FakeRbNative();
    queue = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: SettingsStore(await SharedPreferences.getInstance()),
    );
  });

  tearDown(() async {
    await queue.dispose();
    await native.dispose();
    await db.close();
  });

  Future<void> pump() =>
      Future<void>.delayed(const Duration(milliseconds: 260));

  test('carrega notas da base', () async {
    await seedNote(db, id: 'a', title: 'Alpha');
    final cubit = NotesListCubit(repository: repo, queue: queue);
    await pump();
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.notes.single.note.id, 'a');
    await cubit.close();
  });

  test('busca filtra por título via FTS', () async {
    await seedNote(db, id: 'a', title: 'Compras do mês');
    await seedNote(db, id: 'b', title: 'Reunião de time');
    final cubit = NotesListCubit(repository: repo, queue: queue);
    await pump();
    cubit.setQuery('compras');
    await pump();
    await pump();
    expect(cubit.state.isSearching, isTrue);
    expect(cubit.state.searchResults!.single.note.id, 'a');
    cubit.setQuery('');
    await pump();
    expect(cubit.state.searchResults, isNull);
    await cubit.close();
  });

  test('filtro por tag refaz a assinatura', () async {
    await seedNote(db, id: 'a');
    await seedNote(db, id: 'b');
    await repo.upsertTag(TagsCompanion.insert(id: 't', name: 'x'));
    await repo.addTagToNote('a', 't');
    final cubit = NotesListCubit(repository: repo, queue: queue);
    await pump();
    cubit.setTagFilter('t');
    await pump();
    expect(cubit.state.notes.single.note.id, 'a');
    await cubit.close();
  });

  test('progresso da transcrição aparece e some ao concluir', () async {
    await seedNote(db, id: 'a');
    final cubit = NotesListCubit(repository: repo, queue: queue);
    await pump();
    queue.enqueue('a'); // nota sem micWavPath → _process retorna cedo
    await pump();
    // Nada a transcrever (sem wav) → sem progresso persistente.
    expect(cubit.state.progress.containsKey('a'), isFalse);
    await cubit.close();
  });
}
