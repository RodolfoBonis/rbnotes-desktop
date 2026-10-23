import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';

AiSegment _seg(int i, AiSpeaker sp, int startMs, String text) => AiSegment(
  index: i,
  speaker: sp,
  startMs: startMs,
  endMs: startMs + 2000,
  text: text,
);

void main() {
  final client = FakeAiClient(
    stepDelay: Duration.zero,
    thinkDelay: Duration.zero,
  );

  final segments = [
    _seg(0, AiSpeaker.me, 0, 'Vou enviar a proposta revisada até sexta.'),
    _seg(
      1,
      AiSpeaker.others,
      64000,
      'Precisamos validar com 200 usuários beta.',
    ),
    _seg(2, AiSpeaker.me, 188000, 'Decidi lançar só no iOS por enquanto.'),
    _seg(3, AiSpeaker.me, 352000, 'Quem aprova o design final?'),
  ];

  group('enrich', () {
    test(
      'derives title, tldr, points, actions, decisions, questions',
      () async {
        final ai = await client.enrich(
          EnrichRequest(
            noteId: 'n1',
            segments: segments,
            speakers: const ['Você', 'Camila'],
          ),
        );
        expect(ai.title, isNotEmpty);
        expect(ai.tldr, isNotEmpty);
        expect(ai.points, isNotEmpty);
        expect(ai.actions.any((a) => a.text.contains('proposta')), isTrue);
        expect(ai.decisions.any((d) => d.contains('iOS')), isTrue);
        expect(ai.questions.any((q) => q.endsWith('?')), isTrue);
        expect(ai.speakerNames.others, ['Camila']);
        expect(ai.quote, isNotNull);
      },
    );

    test('skips actions when extractTasks is false', () async {
      final ai = await client.enrich(
        EnrichRequest(
          noteId: 'n1',
          segments: segments,
          speakers: const ['Você'],
          extractTasks: false,
        ),
      );
      expect(ai.actions, isEmpty);
    });
  });

  group('chat streaming', () {
    test('accumulates text and ends with a done event + cites', () async {
      final deltas = await client
          .chat(
            noteId: 'n1',
            segments: segments,
            speakers: const ['Você', 'Camila'],
            message: 'Resuma em uma frase',
          )
          .toList();
      expect(deltas.length, greaterThan(1));
      // Monotonically growing text.
      for (var i = 1; i < deltas.length; i++) {
        expect(
          deltas[i].text.length,
          greaterThanOrEqualTo(deltas[i - 1].text.length),
        );
      }
      final last = deltas.last;
      expect(last.isDone, isTrue);
      expect(last.cites, isNotEmpty);
    });
  });

  group('ask streaming', () {
    test('returns sources for the candidates', () async {
      final deltas = await client
          .ask(
            question: 'O que ficou pendente?',
            candidates: const [
              AskCandidate(
                noteId: 'n1',
                title: 'Kickoff',
                tldr: 'Resumo do kickoff.',
                transcript: 'texto',
              ),
            ],
          )
          .toList();
      expect(deltas.last.isDone, isTrue);
      expect(deltas.last.sources.single.noteId, 'n1');
    });

    test('handles no candidates gracefully', () async {
      final deltas = await client
          .ask(question: 'qualquer coisa', candidates: const [])
          .toList();
      expect(deltas.last.text, contains('Não encontrei'));
      expect(deltas.last.sources, isEmpty);
    });
  });

  group('collectionRule', () {
    test('produces a local rule', () async {
      final r = await client.collectionRule('tudo sobre o podcast');
      expect(r.rule.keywords, contains('podcast'));
    });
  });

  group('diaryMonth', () {
    test('summarizes and extracts themes', () async {
      final month = await client.diaryMonth(
        month: '2026-10',
        entries: const [
          'Hoje corri de manhã e dormi cedo.',
          'Reunião de trabalho sobre a proposta.',
        ],
      );
      expect(month.summary, contains('2'));
      expect(month.themes, isNotEmpty);
    });
  });
}
