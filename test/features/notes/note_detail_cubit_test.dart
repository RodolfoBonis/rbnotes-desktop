import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/note_detail_cubit.dart';

import '../../helpers/fake_audio_player.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository repo;
  late FakeAudioPlayer player;

  setUp(() {
    db = memoryDb();
    repo = memoryRepo(db);
    player = FakeAudioPlayer();
  });
  tearDown(() => db.close());

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

  NoteDetailCubit build(String id) =>
      NoteDetailCubit(noteId: id, repository: repo, player: player);

  test('carrega nota, segmentos e tags', () async {
    await seedNote(db, id: 'a', title: 'Minha nota');
    await seedSegment(db, noteId: 'a', content: 'olá mundo');
    final cubit = build('a');
    await pump();
    expect(cubit.state.note!.title, 'Minha nota');
    expect(cubit.state.segments.single.content, 'olá mundo');
    await cubit.close();
  });

  test('seekToSegment pula para o início e toca', () async {
    await seedNote(db, id: 'a');
    await seedSegment(
      db,
      noteId: 'a',
      content: 'x',
      startMs: 5000,
      endMs: 6000,
    );
    final cubit = build('a');
    await pump();
    await cubit.seekToSegment(cubit.state.segments.single);
    expect(player.seeks.single, const Duration(milliseconds: 5000));
    expect(player.isPlaying, isTrue);
    await cubit.close();
  });

  test('segmento ativo acompanha a posição do player', () async {
    await seedNote(db, id: 'a');
    await seedSegment(db, noteId: 'a', content: 'um');
    await seedSegment(
      db,
      noteId: 'a',
      content: 'dois',
      startMs: 1000,
      endMs: 2000,
    );
    final cubit = build('a');
    await pump();
    player.emitPosition(const Duration(milliseconds: 1500));
    await pump();
    expect(cubit.state.activeSegmentIndex, 1);
    await cubit.close();
  });

  test('updateTitle e togglePin persistem', () async {
    await seedNote(db, id: 'a', title: 'antigo');
    final cubit = build('a');
    await pump();
    await cubit.updateTitle('novo');
    await cubit.togglePin();
    await pump();
    final note = await repo.getNote('a');
    expect(note!.title, 'novo');
    expect(note.pinned, isTrue);
    await cubit.close();
  });

  test('delete remove a nota e marca deleted', () async {
    await seedNote(db, id: 'a');
    final cubit = build('a');
    await pump();
    await cubit.delete();
    await pump();
    expect(cubit.state.deleted, isTrue);
    expect(await repo.getNote('a'), isNull);
    await cubit.close();
  });

  test('createTagAndAttach cria tag e associa', () async {
    await seedNote(db, id: 'a');
    final cubit = build('a');
    await pump();
    await cubit.createTagAndAttach('Ideias', emoji: '💡');
    await pump();
    expect(cubit.state.tags.single.name, 'Ideias');
    expect(cubit.state.tags.single.emoji, '💡');
    await cubit.close();
  });
}
