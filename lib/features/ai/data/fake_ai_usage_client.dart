import 'package:rbnotes/features/ai/data/ai_usage.dart';
import 'package:rbnotes/features/ai/data/ai_usage_client.dart';

/// `AiUsageClient` local-first/determinístico: gera uma série plausível a
/// partir do intervalo pedido (sem rede), para dev, testes e goldens.
class FakeAiUsageClient implements AiUsageClient {
  const FakeAiUsageClient();

  static const _kinds = <String>[
    'note_enrich',
    'note_chat',
    'ask',
    'collection_rule',
    'diary_month',
    'weekly_summary',
  ];

  @override
  Future<AiUsage> fetch({
    required String from,
    required String to,
    required String tz,
  }) async {
    final start = DateTime.parse(from);
    final end = DateTime.parse(to);
    final days = <DayUsage>[];
    final kindTotals = <String, (int, double)>{};
    var totalReq = 0;
    var totalCost = 0.0;
    var totalIn = 0;
    var totalOut = 0;

    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final seed = (d.year * 372 + d.month * 31 + d.day) % 97;
      final dayKinds = <KindUsage>[];
      var dayReq = 0;
      var dayCost = 0.0;
      for (var i = 0; i < _kinds.length; i++) {
        final kind = _kinds[i];
        final req = (seed * (i + 3)) % 6;
        if (req == 0) continue;
        final cost = req * (0.012 + 0.004 * i);
        final inTok = req * (900 + 120 * i);
        final outTok = req * (260 + 40 * i);
        dayKinds.add(
          KindUsage(
            kind: kind,
            requests: req,
            costUsd: cost,
            inputTokens: inTok,
            outputTokens: outTok,
          ),
        );
        dayReq += req;
        dayCost += cost;
        totalIn += inTok;
        totalOut += outTok;
        final prev = kindTotals[kind] ?? (0, 0.0);
        kindTotals[kind] = (prev.$1 + req, prev.$2 + cost);
      }
      days.add(
        DayUsage(
          date: _fmt(d),
          requests: dayReq,
          costUsd: dayCost,
          kinds: dayKinds,
        ),
      );
      totalReq += dayReq;
      totalCost += dayCost;
    }

    final byKind = [
      for (final e in kindTotals.entries)
        KindUsage(kind: e.key, requests: e.value.$1, costUsd: e.value.$2),
    ]..sort((a, b) => b.costUsd.compareTo(a.costUsd));

    final used24h = days.isEmpty ? 0 : days.last.requests;

    return AiUsage(
      from: from,
      to: to,
      tz: tz,
      currency: 'USD',
      costIsEstimate: true,
      quota: UsageQuota(limit: 200, used24h: used24h),
      totals: UsageTotals(
        requests: totalReq,
        done: totalReq,
        errors: 0,
        inputTokens: totalIn,
        outputTokens: totalOut,
        cacheCreationTokens: 0,
        cacheReadTokens: 0,
        costUsd: totalCost,
        durationMs: totalReq * 1800,
      ),
      byKind: byKind,
      days: days,
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
