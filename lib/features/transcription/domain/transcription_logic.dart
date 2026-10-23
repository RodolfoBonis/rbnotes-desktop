import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/native/rb_native.dart';

/// Junta os segmentos do mic ("eu") e do sistema ("outros") num único roteiro
/// ordenado por tempo de início. Empate: o falante do mic vem primeiro.
List<DraftSegment> mergeSpeakerSegments({
  required List<TranscriptSegment> mic,
  required List<TranscriptSegment> system,
}) {
  final drafts =
      <DraftSegment>[
          for (final s in mic)
            DraftSegment(
              speaker: SegmentSpeaker.me,
              startMs: s.start.inMilliseconds,
              endMs: s.end.inMilliseconds,
              content: s.text.trim(),
            ),
          for (final s in system)
            DraftSegment(
              speaker: SegmentSpeaker.others,
              startMs: s.start.inMilliseconds,
              endMs: s.end.inMilliseconds,
              content: s.text.trim(),
            ),
        ]
        ..removeWhere((d) => d.content.isEmpty)
        ..sort((a, b) {
          final byStart = a.startMs.compareTo(b.startMs);
          if (byStart != 0) return byStart;
          // mic antes de sistema no empate.
          return a.speaker == b.speaker
              ? 0
              : (a.speaker == SegmentSpeaker.me ? -1 : 1);
        });
  return drafts;
}

/// Título automático: ~8 primeiras palavras da transcrição, com a primeira
/// letra maiúscula. Vazio quando não há texto.
String titleFromSegments(List<DraftSegment> segments, {int maxWords = 8}) {
  final words = segments
      .map((s) => s.content)
      .join(' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(maxWords)
      .toList();
  if (words.isEmpty) return '';
  final text = words.join(' ');
  return text[0].toUpperCase() + text.substring(1);
}
