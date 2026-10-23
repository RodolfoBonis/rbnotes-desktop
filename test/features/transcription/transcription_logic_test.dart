import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/transcription/domain/transcription_logic.dart';
import 'package:rbnotes/native/rb_native.dart';

void main() {
  TranscriptSegment seg(int start, int end, String text) => TranscriptSegment(
    start: Duration(milliseconds: start),
    end: Duration(milliseconds: end),
    text: text,
  );

  group('mergeSpeakerSegments', () {
    test('ordena por início e atribui o falante por canal', () {
      final merged = mergeSpeakerSegments(
        mic: [seg(0, 1000, 'eu começo'), seg(2000, 3000, 'eu de novo')],
        system: [seg(1000, 2000, 'outros no meio')],
      );
      expect(merged.map((s) => s.content).toList(), [
        'eu começo',
        'outros no meio',
        'eu de novo',
      ]);
      expect(merged.map((s) => s.speaker).toList(), [
        SegmentSpeaker.me,
        SegmentSpeaker.others,
        SegmentSpeaker.me,
      ]);
    });

    test('no empate o mic vem antes e vazios são descartados', () {
      final merged = mergeSpeakerSegments(
        mic: [seg(0, 500, 'eu'), seg(1000, 1000, '   ')],
        system: [seg(0, 500, 'outros')],
      );
      expect(merged.length, 2);
      expect(merged.first.speaker, SegmentSpeaker.me);
      expect(merged[1].speaker, SegmentSpeaker.others);
    });
  });

  group('titleFromSegments', () {
    test('usa as ~8 primeiras palavras com inicial maiúscula', () {
      final title = titleFromSegments(const [
        DraftSegment(
          speaker: SegmentSpeaker.me,
          startMs: 0,
          endMs: 1,
          content: 'uma nota com várias palavras para virar título bem longo',
        ),
      ]);
      expect(title, 'Uma nota com várias palavras para virar título');
    });

    test('vazio quando não há conteúdo', () {
      expect(titleFromSegments(const []), '');
    });
  });
}
