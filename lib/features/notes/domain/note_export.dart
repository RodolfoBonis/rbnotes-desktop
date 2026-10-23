import 'package:rbnotes/data/database/database.dart';

String _speakerLabel(SegmentSpeaker s) =>
    s == SegmentSpeaker.me ? 'Eu' : 'Outros';

String formatTimestamp(int ms) {
  final d = Duration(milliseconds: ms);
  final minutes = d.inMinutes.toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Transcrição em texto puro, uma linha por segmento com falante e tempo.
String transcriptPlainText(List<SegmentRow> segments) {
  return segments
      .map(
        (s) =>
            '[${formatTimestamp(s.startMs)}] '
            '${_speakerLabel(s.speaker)}: ${s.content}',
      )
      .join('\n');
}

/// Exportação .md: título, metadados e transcrição.
String noteMarkdown(
  NoteRow note,
  List<SegmentRow> segments,
  List<TagRow> tags,
) {
  final buffer = StringBuffer()
    ..writeln('# ${note.title.isEmpty ? 'Sem título' : note.title}')
    ..writeln();
  if (tags.isNotEmpty) {
    final rendered = tags
        .map((t) => '${t.emoji == null ? '' : '${t.emoji} '}${t.name}')
        .join(', ');
    buffer
      ..writeln('**Tags:** $rendered')
      ..writeln();
  }
  for (final s in segments) {
    buffer.writeln(
      '- `${formatTimestamp(s.startMs)}` **${_speakerLabel(s.speaker)}:** '
      '${s.content}',
    );
  }
  return buffer.toString();
}

/// Exportação .txt (texto puro).
String noteTxt(NoteRow note, List<SegmentRow> segments) {
  final buffer = StringBuffer()
    ..writeln(note.title.isEmpty ? 'Sem título' : note.title)
    ..writeln()
    ..write(transcriptPlainText(segments));
  return buffer.toString();
}
