import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/note_detail_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_audio_player.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository repo;
  late FakeAudioPlayer player;
  late FakeRbNative native;
  late TranscriptionQueue queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = memoryDb();
    repo = memoryRepo(db);
    player = FakeAudioPlayer();
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

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

  NoteDetailCubit build(String id) => NoteDetailCubit(
    noteId: id,
    repository: repo,
    player: player,
    queue: queue,
  );

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

  test('delete cancela a transcrição dos wavs antes de apagar', () async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'a',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            status: NoteStatus.transcribing,
            source: NoteSource.recording,
            micWavPath: const Value('/tmp/a.mic.wav'),
            systemWavPath: const Value('/tmp/a.system.wav'),
          ),
        );
    final cubit = build('a');
    await pump();
    await cubit.delete();
    await pump();
    expect(native.cancelledWavs, contains('/tmp/a.mic.wav'));
    expect(native.cancelledWavs, contains('/tmp/a.system.wav'));
    await cubit.close();
  });

  test('retryTranscription reenfileira a nota', () async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'a',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            status: NoteStatus.failed,
            source: NoteSource.recording,
            micWavPath: const Value('/tmp/a.mic.wav'),
          ),
        );
    final cubit = build('a');
    await pump();
    cubit.retryTranscription();
    await queue.progress.firstWhere((p) => p.isTerminal);
    expect((await repo.getNote('a'))!.status, NoteStatus.ready);
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
