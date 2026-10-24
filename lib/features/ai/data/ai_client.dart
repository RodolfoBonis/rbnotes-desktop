import 'package:equatable/equatable.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';

/// Falante de um segmento enviado à IA (contrato: `"me" | "others" | <nome>`).
enum AiSpeaker { me, others }

/// Segmento de transcrição enviado à IA.
class AiSegment extends Equatable {
  const AiSegment({
    required this.index,
    required this.speaker,
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  final int index;
  final AiSpeaker speaker;
  final int startMs;
  final int endMs;
  final String text;

  @override
  List<Object?> get props => [index, speaker, startMs, endMs, text];
}

/// Estilo e tamanho do resumo (preferências de Inteligência).
enum SummaryStyle { objetivo, detalhado, topicos }

enum SummaryLength { curto, medio, longo }

/// Pedido de enriquecimento de uma nota.
class EnrichRequest extends Equatable {
  const EnrichRequest({
    required this.noteId,
    required this.segments,
    required this.speakers,
    this.folder,
    this.style = SummaryStyle.objetivo,
    this.length = SummaryLength.medio,
    this.extractTasks = true,
    this.ephemeral = false,
  });

  final String noteId;
  final List<AiSegment> segments;
  final List<String> speakers;
  final String? folder;
  final SummaryStyle style;
  final SummaryLength length;
  final bool extractTasks;

  /// Nota bloqueada: o servidor roda o enrich mas não grava `note_ai` em texto
  /// claro (o cliente salva e cifra); o resultado volta só pelo SSE.
  final bool ephemeral;

  @override
  List<Object?> get props => [
    noteId,
    segments,
    speakers,
    folder,
    style,
    length,
    extractTasks,
    ephemeral,
  ];
}

/// Fonte citada por "Perguntar às notas".
class AskSource extends Equatable {
  const AskSource({required this.noteId, required this.title});

  final String noteId;
  final String title;

  @override
  List<Object?> get props => [noteId, title];
}

/// Atualização incremental de uma resposta em streaming (chat ou ask). [text]
/// é o texto acumulado; ao final, [isDone] é true e as citações/fontes chegam.
class AiDelta extends Equatable {
  const AiDelta({
    required this.text,
    this.isDone = false,
    this.cites = const [],
    this.sources = const [],
  });

  final String text;
  final bool isDone;

  /// Instantes do áudio citados (ms), para os chips "ouvir em …".
  final List<int> cites;

  /// Fontes (notas) citadas por "Perguntar às notas".
  final List<AskSource> sources;

  @override
  List<Object?> get props => [text, isDone, cites, sources];
}

/// Resumo mensal do diário.
class DiaryMonth extends Equatable {
  const DiaryMonth({required this.summary, required this.themes});

  final String summary;
  final List<DiaryTheme> themes;

  @override
  List<Object?> get props => [summary, themes];
}

class DiaryTheme extends Equatable {
  const DiaryTheme({required this.name, required this.count});

  final String name;
  final int count;

  @override
  List<Object?> get props => [name, count];
}

/// Resumo semanal (Claude), excluindo notas bloqueadas.
class WeeklySummary extends Equatable {
  const WeeklySummary({
    required this.title,
    required this.summary,
    required this.highlights,
    required this.openTasks,
    required this.themes,
  });

  factory WeeklySummary.fromJson(Map<String, dynamic> j) => WeeklySummary(
    title: j['title'] as String? ?? 'Resumo da semana',
    summary: j['summary'] as String? ?? '',
    highlights: [
      for (final h in (j['highlights'] as List? ?? const [])) h.toString(),
    ],
    openTasks: [
      for (final t in (j['openTasks'] as List? ?? const []))
        WeeklyOpenTask.fromJson((t as Map).cast<String, dynamic>()),
    ],
    themes: [
      for (final t in (j['themes'] as List? ?? const []))
        DiaryTheme(
          name: (t as Map)['name']?.toString() ?? '',
          count: ((t['count']) as num?)?.toInt() ?? 0,
        ),
    ],
  );

  final String title;
  final String summary;
  final List<String> highlights;
  final List<WeeklyOpenTask> openTasks;
  final List<DiaryTheme> themes;

  @override
  List<Object?> get props => [title, summary, highlights, openTasks, themes];
}

class WeeklyOpenTask extends Equatable {
  const WeeklyOpenTask({required this.text, this.noteId});

  factory WeeklyOpenTask.fromJson(Map<String, dynamic> j) => WeeklyOpenTask(
    text: j['text'] as String? ?? '',
    noteId: j['noteId'] as String?,
  );

  final String text;
  final String? noteId;

  @override
  List<Object?> get props => [text, noteId];
}

/// Cliente de IA (enriquecimento, chat, perguntar às notas, regras de coleção,
/// diário). Local-first via `FakeAiClient`; a implementação real fala com a
/// `rbnotes-api` (SSE) e é injetada depois.
abstract interface class AiClient {
  /// Gera título, resumo, pontos, citação, ações, decisões e nomes de falantes.
  Future<NoteAi> enrich(EnrichRequest request);

  /// Chat sobre uma única nota (streaming + citações de tempo no final).
  Stream<AiDelta> chat({
    required String noteId,
    required List<AiSegment> segments,
    required List<String> speakers,
    required String message,
    bool ephemeral = false,
  });

  /// "Perguntar às notas": responde a partir das notas candidatas (streaming +
  /// fontes no final).
  Stream<AiDelta> ask({
    required String question,
    required List<AskCandidate> candidates,
  });

  /// Converte uma descrição em linguagem natural numa regra de coleção.
  Future<CollectionRuleResult> collectionRule(String description);

  /// Resumo do mês do diário + temas recorrentes.
  Future<DiaryMonth> diaryMonth({
    required String month,
    required List<String> entries,
  });

  /// Pergunta do dia para o diário.
  Future<String> dailyPrompt(DateTime date);

  /// Resumo semanal: notas e tarefas da semana (exceto bloqueadas).
  Future<WeeklySummary> weeklySummary({
    required DateTime weekStart,
    required String tz,
  });
}

/// Nota candidata para "Perguntar às notas".
class AskCandidate extends Equatable {
  const AskCandidate({
    required this.noteId,
    required this.title,
    required this.tldr,
    required this.transcript,
  });

  final String noteId;
  final String title;
  final String tldr;
  final String transcript;

  @override
  List<Object?> get props => [noteId, title, tldr, transcript];
}
