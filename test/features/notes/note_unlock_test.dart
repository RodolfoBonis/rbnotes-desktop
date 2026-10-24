import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';
import 'package:rbnotes/native/fake_rb_native.dart';

import '../../helpers/fake_audio_player.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;

  setUp(() async {
    db = memoryDb();
    notes = NoteRepository(db);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'n',
            title: const Value('Segredo'),
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            status: NoteStatus.ready,
            source: NoteSource.recording,
            locked: const Value(true),
          ),
        );
    await db
        .into(db.transcriptSegments)
        .insert(
          TranscriptSegmentsCompanion.insert(
            noteId: 'n',
            speaker: SegmentSpeaker.me,
            startMs: 0,
            endMs: 1000,
            content: 'texto secreto da nota',
          ),
        );
  });

  tearDown(() => db.close());

  NoteViewCubit build(BiometricAuth auth) => NoteViewCubit(
    notes: notes,
    noteAi: NoteAiRepository(db),
    ai: FakeAiClient(),
    native: FakeRbNative(),
    player: FakeAudioPlayer(),
    aiActivity: AiActivity(),
    auth: auth,
  );

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('a locked note needs unlocking before showing content', () async {
    final cubit = build(FakeBiometricAuth());
    await cubit.load('n');
    await settle();
    expect(cubit.state.note?.locked, isTrue);
    expect(cubit.state.needsUnlock, isTrue);
    addTearDown(cubit.close);
  });

  test('unlockNote opens the session with Touch ID', () async {
    final cubit = build(FakeBiometricAuth());
    await cubit.load('n');
    await settle();

    final ok = await cubit.unlockNote();
    expect(ok, isTrue);
    expect(cubit.state.needsUnlock, isFalse);
    addTearDown(cubit.close);
  });

  test('a failed Touch ID keeps the note locked', () async {
    final cubit = build(FakeBiometricAuth(result: false));
    await cubit.load('n');
    await settle();

    final ok = await cubit.unlockNote();
    expect(ok, isFalse);
    expect(cubit.state.needsUnlock, isTrue);
    addTearDown(cubit.close);
  });

  // C2/B16: o conteúdo da nota bloqueada não é carregado antes do Touch ID.
  test('locked content is not loaded before unlock', () async {
    final cubit = build(FakeBiometricAuth());
    await cubit.load('n');
    await settle();
    expect(cubit.state.needsUnlock, isTrue);
    expect(cubit.state.segments, isEmpty);
    expect(cubit.state.ai, isNull);
    addTearDown(cubit.close);
  });

  test('unlock reveals the content, expiry clears it again', () async {
    final cubit = NoteViewCubit(
      notes: notes,
      noteAi: NoteAiRepository(db),
      ai: FakeAiClient(),
      native: FakeRbNative(),
      player: FakeAudioPlayer(),
      aiActivity: AiActivity(),
      auth: FakeBiometricAuth(),
      unlockSession: const Duration(milliseconds: 80),
    );
    await cubit.load('n');
    await settle();
    expect(cubit.state.segments, isEmpty);

    await cubit.unlockNote();
    await settle();
    expect(cubit.state.needsUnlock, isFalse);
    expect(
      cubit.state.segments.single.content,
      'texto secreto da nota',
    );

    // A sessão expira: o conteúdo em claro some e volta o placeholder.
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(cubit.state.needsUnlock, isTrue);
    expect(cubit.state.segments, isEmpty);
    addTearDown(cubit.close);
  });
}
