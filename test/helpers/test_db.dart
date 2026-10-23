import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';

/// Banco drift em memória para os testes do repositório/busca.
AppDatabase memoryDb() => AppDatabase.forTesting(
  DatabaseConnection(
    NativeDatabase.memory(),
    closeStreamsSynchronously: true,
  ),
);

NoteRepository memoryRepo(AppDatabase db) => NoteRepository(db);

/// Insere uma nota mínima pronta (status ready).
Future<void> seedNote(
  AppDatabase db, {
  required String id,
  String title = '',
  NoteStatus status = NoteStatus.ready,
  NoteSource source = NoteSource.recording,
  bool pinned = false,
  DateTime? createdAt,
}) async {
  final now = createdAt ?? DateTime(2026, 10, 23, 12);
  await db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: id,
          title: Value(title),
          createdAt: now,
          updatedAt: now,
          status: status,
          source: source,
          pinned: Value(pinned),
        ),
      );
}

Future<void> seedSegment(
  AppDatabase db, {
  required String noteId,
  required String content,
  SegmentSpeaker speaker = SegmentSpeaker.me,
  int startMs = 0,
  int endMs = 1000,
}) async {
  await db
      .into(db.transcriptSegments)
      .insert(
        TranscriptSegmentsCompanion.insert(
          noteId: noteId,
          speaker: speaker,
          startMs: startMs,
          endMs: endMs,
          content: content,
        ),
      );
}
