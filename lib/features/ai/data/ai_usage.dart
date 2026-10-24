import 'package:equatable/equatable.dart';

/// Resposta de `GET /v1/ai/usage` (ver `docs/phase3-contracts.md`).
///
/// Todos os custos são uma **estimativa** pelo preço de API do Claude
/// ([costIsEstimate] = true): o dono usa a assinatura, não é cobrança real.
class AiUsage extends Equatable {
  const AiUsage({
    required this.from,
    required this.to,
    required this.tz,
    required this.currency,
    required this.costIsEstimate,
    required this.quota,
    required this.totals,
    required this.byKind,
    required this.days,
  });

  factory AiUsage.fromJson(Map<String, dynamic> json) => AiUsage(
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    tz: json['tz'] as String? ?? 'UTC',
    currency: json['currency'] as String? ?? 'USD',
    costIsEstimate: json['costIsEstimate'] as bool? ?? true,
    quota: UsageQuota.fromJson(
      (json['quota'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    totals: UsageTotals.fromJson(
      (json['totals'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    byKind: [
      for (final k in (json['byKind'] as List? ?? const []))
        KindUsage.fromJson((k as Map).cast<String, dynamic>()),
    ],
    days: [
      for (final d in (json['days'] as List? ?? const []))
        DayUsage.fromJson((d as Map).cast<String, dynamic>()),
    ],
  );

  final String from;
  final String to;
  final String tz;
  final String currency;
  final bool costIsEstimate;
  final UsageQuota quota;
  final UsageTotals totals;
  final List<KindUsage> byKind;
  final List<DayUsage> days;

  @override
  List<Object?> get props => [
    from,
    to,
    tz,
    currency,
    costIsEstimate,
    quota,
    totals,
    byKind,
    days,
  ];
}

class UsageQuota extends Equatable {
  const UsageQuota({required this.limit, required this.used24h});

  factory UsageQuota.fromJson(Map<String, dynamic> json) => UsageQuota(
    limit: (json['limit'] as num?)?.toInt() ?? 0,
    used24h: (json['used24h'] as num?)?.toInt() ?? 0,
  );

  final int limit;
  final int used24h;

  int get remaining => (limit - used24h).clamp(0, limit);

  @override
  List<Object?> get props => [limit, used24h];
}

class UsageTotals extends Equatable {
  const UsageTotals({
    required this.requests,
    required this.done,
    required this.errors,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheCreationTokens,
    required this.cacheReadTokens,
    required this.costUsd,
    required this.durationMs,
  });

  factory UsageTotals.fromJson(Map<String, dynamic> json) => UsageTotals(
    requests: (json['requests'] as num?)?.toInt() ?? 0,
    done: (json['done'] as num?)?.toInt() ?? 0,
    errors: (json['errors'] as num?)?.toInt() ?? 0,
    inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
    outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
    cacheCreationTokens: (json['cacheCreationTokens'] as num?)?.toInt() ?? 0,
    cacheReadTokens: (json['cacheReadTokens'] as num?)?.toInt() ?? 0,
    costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
  );

  final int requests;
  final int done;
  final int errors;
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;
  final double costUsd;
  final int durationMs;

  /// Soma de todos os tokens (entrada + saída + cache).
  int get totalTokens =>
      inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens;

  @override
  List<Object?> get props => [
    requests,
    done,
    errors,
    inputTokens,
    outputTokens,
    cacheCreationTokens,
    cacheReadTokens,
    costUsd,
    durationMs,
  ];
}

class KindUsage extends Equatable {
  const KindUsage({
    required this.kind,
    required this.requests,
    required this.costUsd,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });

  factory KindUsage.fromJson(Map<String, dynamic> json) => KindUsage(
    kind: json['kind'] as String? ?? '',
    requests: (json['requests'] as num?)?.toInt() ?? 0,
    costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
    inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
    outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
  );

  final String kind;
  final int requests;
  final double costUsd;
  final int inputTokens;
  final int outputTokens;

  @override
  List<Object?> get props => [
    kind,
    requests,
    costUsd,
    inputTokens,
    outputTokens,
  ];
}

class DayUsage extends Equatable {
  const DayUsage({
    required this.date,
    required this.requests,
    required this.costUsd,
    required this.kinds,
  });

  factory DayUsage.fromJson(Map<String, dynamic> json) => DayUsage(
    date: json['date'] as String? ?? '',
    requests: (json['requests'] as num?)?.toInt() ?? 0,
    costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
    kinds: [
      for (final k in (json['kinds'] as List? ?? const []))
        KindUsage.fromJson((k as Map).cast<String, dynamic>()),
    ],
  );

  final String date;
  final int requests;
  final double costUsd;
  final List<KindUsage> kinds;

  @override
  List<Object?> get props => [date, requests, costUsd, kinds];
}

/// Rótulos em português para os `kind`s de job de IA.
String aiKindLabel(String kind) => switch (kind) {
  'note_enrich' => 'Resumos',
  'note_chat' => 'Conversas',
  'ask' => 'Perguntar',
  'collection_rule' => 'Coleções',
  'diary_month' => 'Diário',
  'diary_prompt' => 'Diário',
  'weekly_summary' => 'Resumo semanal',
  _ => kind,
};
