import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/ai/presentation/ask_cubit.dart';
import 'package:rbnotes/features/diary/data/diary_repository.dart';
import 'package:rbnotes/features/diary/presentation/diary_cubit.dart';
import 'package:rbnotes/features/library/data/demo_seeder.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_audio_player.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late NoteAiRepository noteAi;
  late LibraryRepository library;
  late DiaryRepository diary;
  late FakeRbNative native;
  late FakeAiClient ai;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = memoryDb();
    notes = NoteRepository(db);
    noteAi = NoteAiRepository(db);
    library = LibraryRepository(db);
    diary = DiaryRepository(db);
    native = FakeRbNative();
    ai = FakeAiClient(stepDelay: Duration.zero, thinkDelay: Duration.zero);
    await DemoSeeder(
      notes: notes,
      noteAi: noteAi,
      library: library,
      diary: diary,
    ).seedIfEmpty();
  });

  tearDown(() async {
    await native.dispose();
    await db.close();
  });

  group('LibraryCubit', () {
    test('carrega pastas, notas e seleciona a primeira', () async {
      final cubit = LibraryCubit(
        notes: notes,
        noteAi: noteAi,
        library: library,
      );
      await settle();
      expect(cubit.state.folders.where((f) => !f.hidden).length, 4);
      expect(cubit.state.allCount, 6);
      expect(cubit.state.diaryCount, 3);
      expect(cubit.state.selectedNoteId, isNotNull);
      await cubit.close();
    });

    test('a coleção Tarefas esquecidas conta ações antigas', () async {
      final cubit = LibraryCubit(
        notes: notes,
        noteAi: noteAi,
        library: library,
      );
      await settle();
      final forgot = cubit.state.forgotten(DateTime.now());
      expect(forgot, isNotEmpty);
      await cubit.close();
    });

    test('selecionar Reuniões filtra notas com mais de um falante', () async {
      final cubit = LibraryCubit(
        notes: notes,
        noteAi: noteAi,
        library: library,
      );
      await settle();
      final meetings = cubit.state.collections.firstWhere(
        (c) => c.id == 'c-meet',
      );
      final count = cubit.state.collectionCount(meetings, DateTime.now());
      expect(count, greaterThanOrEqualTo(3));
      await cubit.close();
    });
  });

  group('NoteViewCubit', () {
    NoteViewCubit build() => NoteViewCubit(
      notes: notes,
      noteAi: noteAi,
      ai: ai,
      native: native,
      player: FakeAudioPlayer(),
    );

    test('carrega a nota com resumo, segmentos e waveform', () async {
      final cubit = build();
      await cubit.load('n1');
      await settle();
      expect(cubit.state.note?.title, contains('Kickoff'));
      expect(cubit.state.ai?.tldr, isNotEmpty);
      expect(cubit.state.segments, isNotEmpty);
      expect(cubit.state.peaks, isNotEmpty);
      await cubit.close();
    });

    test('o chat salva a pergunta e a resposta com streaming', () async {
      final cubit = build();
      await cubit.load('n1');
      await settle();
      await cubit.sendChat('Resuma em uma frase');
      await settle();
      final roles = cubit.state.chat.map((m) => m.role).toList();
      expect(roles, contains(ChatRole.user));
      expect(roles, contains(ChatRole.ai));
      await cubit.close();
    });

    test('corrigir palavra substitui em todas as notas e avisa', () async {
      final cubit = build();
      await cubit.load('n1');
      await settle();
      final noticeFuture = cubit.notices.first;
      await cubit.fixWord(
        'Taís',
        'Thaís',
        everywhere: true,
        addToVocabulary: true,
      );
      final notice = await noticeFuture;
      expect(notice, contains('Thaís'));
      final segs = await notes.getSegments('n1');
      expect(segs.any((s) => s.content.contains('Taís')), isFalse);
      await cubit.close();
    });
  });

  group('AskCubit', () {
    test('responde com streaming e fontes', () async {
      final cubit = AskCubit(ai: ai, notes: notes, noteAi: noteAi);
      await cubit.submit('O que ficou pendente?');
      await settle();
      expect(cubit.state.phase, AskPhase.done);
      expect(cubit.state.answer, isNotEmpty);
      expect(cubit.state.sources, isNotEmpty);
      await cubit.close();
    });
  });

  group('DiaryCubit', () {
    test('carrega perguntas, calendário e resumo do mês', () async {
      final cubit = DiaryCubit(
        diary: diary,
        notes: notes,
        noteAi: noteAi,
        ai: ai,
      );
      await cubit.load();
      await settle();
      expect(cubit.state.prompts, isNotEmpty);
      expect(cubit.state.calendar.cells, isNotEmpty);
      // O resumo do mês só carrega após o app desbloqueado.
      await cubit.loadMonth();
      await settle();
      expect(cubit.state.monthSummary, isNotEmpty);
      final before = cubit.state.prompt;
      cubit.nextPrompt();
      expect(cubit.state.prompt, isNot(before));
      await cubit.close();
    });
  });
}
