import 'package:rbnotes/data/database/database.dart' show seedDiaryPrompts;
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';

/// IA simulada, sem rede: gera respostas plausíveis a partir da transcrição e
/// faz streaming artificial. Permite desenvolver e testar todo o fluxo de IA
/// antes da integração com a `rbnotes-api`.
class FakeAiClient implements AiClient {
  FakeAiClient({
    this.chunkChars = 6,
    this.stepDelay = const Duration(milliseconds: 12),
    this.thinkDelay = const Duration(milliseconds: 250),
  });

  /// Caracteres revelados por passo do streaming.
  final int chunkChars;

  /// Pausa entre passos (0 nos testes).
  final Duration stepDelay;

  /// Pausa de "pensando" antes do primeiro texto.
  final Duration thinkDelay;

  static const _actionCues = [
    'preciso',
    'vou ',
    'precisa',
    'enviar',
    'agendar',
    'marcar',
    'testar',
    'fazer',
    'listar',
    'ligar',
    'comprar',
    'escrever',
    'levantar',
    'avisar',
    'repetir',
    'buscar',
    'trocar',
    'até ',
  ];
  static const _decisionCues = [
    'decidi',
    'fica ',
    'ficou',
    'vamos',
    'será',
    'começa',
    'adiado',
    'apenas',
    'só ',
  ];

  @override
  Future<NoteAi> enrich(EnrichRequest request) async {
    await Future<void>.delayed(thinkDelay);
    final segs = request.segments;
    final fullText = segs.map((s) => s.text).join(' ').trim();
    final sentences = _sentences(fullText);
    final others = request.speakers
        .where((s) => s.toLowerCase() != 'você')
        .toList();

    final title = _title(fullText);
    final tldr = sentences.isEmpty
        ? ''
        : sentences
              .take(request.length == SummaryLength.curto ? 1 : 2)
              .join(' ');
    final maxPoints = switch (request.length) {
      SummaryLength.curto => 2,
      SummaryLength.medio => 3,
      SummaryLength.longo => 5,
    };
    final points = sentences
        .where((s) => s.split(' ').length >= 4)
        .take(maxPoints)
        .toList();

    // Citação: o segmento com mais texto.
    NoteQuote? quote;
    if (segs.isNotEmpty) {
      final best = segs.reduce((a, b) => b.text.length > a.text.length ? b : a);
      quote = NoteQuote(
        segmentIndex: best.index,
        text: best.text,
        speaker: best.speaker == AiSpeaker.me
            ? 'Você'
            : (others.isNotEmpty ? others.first : 'Outros'),
        atMs: best.startMs,
      );
    }

    final actions = request.extractTasks
        ? sentences
              .where((s) => _containsAny(s, _actionCues))
              .take(4)
              .map((s) => NoteAction(text: _trimTrailing(s), owner: 'Você'))
              .toList()
        : <NoteAction>[];
    final decisions = sentences
        .where((s) => _containsAny(s, _decisionCues))
        .take(3)
        .map(_trimTrailing)
        .toList();
    final questions = sentences
        .where((s) => s.trimRight().endsWith('?'))
        .take(3)
        .toList();

    return NoteAi(
      title: title,
      tldr: tldr,
      points: points,
      quote: quote,
      actions: actions,
      decisions: decisions,
      questions: questions,
      speakerNames: SpeakerNames(others: others, segments: const []),
    );
  }

  @override
  Stream<AiDelta> chat({
    required String noteId,
    required List<AiSegment> segments,
    required List<String> speakers,
    required String message,
    bool ephemeral = false,
  }) {
    final answer = _chatAnswer(segments, speakers, message);
    return _stream(answer.text, cites: answer.cites);
  }

  @override
  Stream<AiDelta> ask({
    required String question,
    required List<AskCandidate> candidates,
  }) {
    final sources = candidates
        .take(3)
        .map((c) => AskSource(noteId: c.noteId, title: c.title))
        .toList();
    final answer = candidates.isEmpty
        ? 'Não encontrei notas relacionadas a essa pergunta.'
        : _askAnswer(question, candidates);
    return _stream(answer, sources: sources);
  }

  @override
  Future<CollectionRuleResult> collectionRule(String description) async {
    await Future<void>.delayed(thinkDelay);
    return CollectionRuleResult.fromDescription(description);
  }

  @override
  Future<DiaryMonth> diaryMonth({
    required String month,
    required List<String> entries,
  }) async {
    await Future<void>.delayed(thinkDelay);
    final themes = _themes(entries);
    final summary = entries.isEmpty
        ? 'Ainda não há entradas suficientes para um resumo do mês.'
        : 'Ao longo do mês você escreveu ${entries.length} '
              '${entries.length == 1 ? 'entrada' : 'entradas'}. '
              'Os assuntos que mais voltaram foram '
              '${themes.take(2).map((t) => t.name.toLowerCase()).join(' e ')}.';
    return DiaryMonth(summary: summary, themes: themes);
  }

  @override
  Future<String> dailyPrompt(DateTime date) async {
    final doy = int.parse(
      '${date.difference(DateTime(date.year)).inDays}',
    );
    return seedDiaryPrompts[doy % seedDiaryPrompts.length];
  }

  @override
  Future<WeeklySummary> weeklySummary({
    required DateTime weekStart,
    required String tz,
  }) async {
    await Future<void>.delayed(thinkDelay);
    return const WeeklySummary(
      title: 'Sua semana em foco',
      summary:
          'Você registrou várias notas e avançou em tarefas de trabalho '
          'e estudos. Alguns itens ficaram em aberto para a próxima semana.',
      highlights: [
        'Fechou o escopo do protótipo',
        'Três reuniões com decisões registradas',
        'Diário mantido em dia',
      ],
      openTasks: [
        WeeklyOpenTask(text: 'Enviar a proposta revisada'),
        WeeklyOpenTask(text: 'Confirmar a data do teste com usuários'),
      ],
      themes: [
        DiaryTheme(name: 'Trabalho', count: 5),
        DiaryTheme(name: 'Estudos', count: 2),
      ],
    );
  }

  // ---------- geração ----------

  _ChatAnswer _chatAnswer(
    List<AiSegment> segs,
    List<String> speakers,
    String q,
  ) {
    final l = q.toLowerCase();
    int at(int i) =>
        segs.isEmpty ? 0 : segs[i.clamp(0, segs.length - 1)].startMs;
    final sentences = _sentences(segs.map((s) => s.text).join(' '));
    final tldr = sentences.isEmpty ? '' : sentences.first;

    if (l.contains('frase') || l.contains('resuma')) {
      return _ChatAnswer(_trimTrailing(tldr), [at(0)]);
    }
    if (l.contains('lista') || l.contains('tarefa')) {
      final points = sentences.take(4).map((s) => '• ${_trimTrailing(s)}');
      return _ChatAnswer(points.join('\n'), const []);
    }
    if (l.contains('prometi') ||
        l.contains('fazer') ||
        l.contains('responsá')) {
      return _ChatAnswer(
        'Pelo que foi dito, você ficou responsável por acompanhar os '
        'próximos passos desta nota.',
        [at(segs.length - 1)],
      );
    }
    if (l.contains('desacordo') || l.contains('discord')) {
      final open = sentences.firstWhere(
        (s) => s.endsWith('?'),
        orElse: () => 'nenhum ponto explícito',
      );
      return _ChatAnswer(
        'Não houve um desacordo explícito. O ponto em aberto foi: $open',
        [at(1)],
      );
    }
    final first = sentences.isEmpty ? '' : _trimTrailing(sentences.first);
    final second = sentences.length > 1 ? ' ${sentences[1]}' : '';
    return _ChatAnswer('Pelo que foi dito, $first.$second', [at(1), at(2)]);
  }

  String _askAnswer(String question, List<AskCandidate> candidates) {
    final titles = candidates.take(2).map((c) => '“${c.title}”').join(' e ');
    final first = candidates.first;
    final summary = first.tldr.isNotEmpty
        ? first.tldr
        : _sentences(first.transcript).take(1).join(' ');
    return 'Olhando suas notas, as mais relevantes são $titles. $summary';
  }

  Stream<AiDelta> _stream(
    String full, {
    List<int> cites = const [],
    List<AskSource> sources = const [],
  }) async* {
    await Future<void>.delayed(thinkDelay);
    var shown = 0;
    while (shown < full.length) {
      shown = (shown + chunkChars).clamp(0, full.length);
      yield AiDelta(text: full.substring(0, shown));
      if (shown < full.length && stepDelay > Duration.zero) {
        await Future<void>.delayed(stepDelay);
      }
    }
    yield AiDelta(text: full, isDone: true, cites: cites, sources: sources);
  }

  List<DiaryTheme> _themes(List<String> entries) {
    const buckets = {
      'Trabalho': ['trabalho', 'projeto', 'reunião', 'proposta', 'kickoff'],
      'Sono': ['dormir', 'sono', 'noite', 'acordar', 'descanso'],
      'Família': ['família', 'mãe', 'pai', 'filho', 'ana', 'casa'],
      'Corrida': ['corrida', 'correr', 'corri', 'exercício', 'caminhada'],
    };
    final counts = <String, int>{};
    final hay = entries.join(' ').toLowerCase();
    buckets.forEach((name, words) {
      final c = words.fold<int>(0, (acc, w) => acc + _count(hay, w));
      if (c > 0) counts[name] = c;
    });
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => DiaryTheme(name: e.key, count: e.value)).toList();
  }

  static int _count(String hay, String needle) {
    if (needle.isEmpty) return 0;
    var i = 0;
    var n = 0;
    while (true) {
      final j = hay.indexOf(needle, i);
      if (j < 0) break;
      n++;
      i = j + needle.length;
    }
    return n;
  }

  static List<String> _sentences(String text) => text
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  static bool _containsAny(String s, List<String> cues) {
    final l = s.toLowerCase();
    return cues.any(l.contains);
  }

  static String _trimTrailing(String s) =>
      s.replaceAll(RegExp(r'[.!?]+$'), '').trim();

  static String _title(String text) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(6)
        .toList();
    if (words.isEmpty) return 'Nova nota';
    final joined = words.join(' ').replaceAll(RegExp(r'[.,;:]$'), '');
    return joined[0].toUpperCase() + joined.substring(1);
  }
}

class _ChatAnswer {
  const _ChatAnswer(this.text, this.cites);
  final String text;
  final List<int> cites;
}
