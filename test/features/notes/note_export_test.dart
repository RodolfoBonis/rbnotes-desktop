import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/domain/note_export.dart';

void main() {
  final note = NoteRow(
    id: 'a',
    title: 'Planejamento',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    durationMs: 0,
    status: NoteStatus.ready,
    pinned: false,
    source: NoteSource.recording,
  );
  const segments = [
    SegmentRow(
      id: 1,
      noteId: 'a',
      speaker: SegmentSpeaker.me,
      startMs: 0,
      endMs: 1000,
      content: 'oi',
    ),
    SegmentRow(
      id: 2,
      noteId: 'a',
      speaker: SegmentSpeaker.others,
      startMs: 65000,
      endMs: 66000,
      content: 'olá',
    ),
  ];

  test('formatTimestamp em mm:ss', () {
    expect(formatTimestamp(65000), '01:05');
  });

  test('transcriptPlainText rotula falante e tempo', () {
    final text = transcriptPlainText(segments);
    expect(text, contains('[00:00] Eu: oi'));
    expect(text, contains('[01:05] Outros: olá'));
  });

  test('markdown inclui título e segmentos', () {
    final md = noteMarkdown(note, segments, const []);
    expect(md, startsWith('# Planejamento'));
    expect(md, contains('**Eu:**'));
  });

  test('txt inclui título e transcrição', () {
    final txt = noteTxt(note, segments);
    expect(txt, startsWith('Planejamento'));
    expect(txt, contains('Outros: olá'));
  });
}
