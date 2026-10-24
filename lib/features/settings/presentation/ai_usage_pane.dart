import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/features/ai/data/ai_usage.dart';
import 'package:rbnotes/features/ai/presentation/ai_usage_cubit.dart';

/// Aba "Uso" das Configurações: consumo de IA do dono — requisições, tokens,
/// custo estimado (USD), detalhamento por tipo, gráfico diário e cota de 24 h.
class AiUsagePane extends StatelessWidget {
  const AiUsagePane({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AiUsageCubit, AiUsageState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PeriodSelector(state: state),
            const SizedBox(height: 16),
            if (state.loading && state.usage == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null && state.usage == null)
              _ErrorBox(
                message: state.error!,
                onRetry: () => context.read<AiUsageCubit>().refresh(),
              )
            else if (state.usage != null)
              _UsageBody(usage: state.usage!)
            else
              const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.state});
  final AiUsageState state;

  static const _labels = <UsagePeriod, String>{
    UsagePeriod.thisMonth: 'Este mês',
    UsagePeriod.last30Days: '30 dias',
    UsagePeriod.previousMonth: 'Mês anterior',
    UsagePeriod.custom: 'Personalizado',
  };

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final cubit = context.read<AiUsageCubit>();
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: rb.controlFill,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in _labels.entries)
            GestureDetector(
              onTap: () => e.key == UsagePeriod.custom
                  ? _pickCustom(context, cubit)
                  : cubit.selectPeriod(e.key),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: state.period == e.key ? rb.seg : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: state.period == e.key
                      ? [
                          BoxShadow(
                            color: rb.onSurface(0.12),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  e.value,
                  style: context.bodyText(size: 12, weight: FontWeight.w500),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickCustom(BuildContext context, AiUsageCubit cubit) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: state.from != null && state.to != null
          ? DateTimeRange(start: state.from!, end: state.to!)
          : null,
    );
    if (range != null) {
      await cubit.setCustomRange(range.start, range.end);
    }
  }
}

class _UsageBody extends StatelessWidget {
  const _UsageBody({required this.usage});
  final AiUsage usage;

  @override
  Widget build(BuildContext context) {
    final t = usage.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Requisições',
                value: _int(t.requests),
                sub: t.errors > 0 ? '${_int(t.errors)} com erro' : 'todas ok',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Tokens',
                value: _compact(t.totalTokens),
                sub:
                    '${_compact(t.inputTokens)} in · '
                    '${_compact(t.outputTokens)} out',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Custo estimado',
                value: _usd(t.costUsd),
                accent: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Estimativa pelo preço da API: você usa a assinatura, não é '
          'cobrança real.',
          style: context.bodyText(
            size: 11,
            height: 1.4,
            color: context.rb.secondary(0.55),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle('Por tipo'),
        const SizedBox(height: 8),
        _KindBreakdown(usage: usage),
        const SizedBox(height: 18),
        const _SectionTitle('Custo por dia'),
        const SizedBox(height: 10),
        CostBarChart(days: usage.days),
        const SizedBox(height: 18),
        _QuotaCard(quota: usage.quota),
      ],
    );
  }

  static String _int(int v) => v.toString();
  static String _usd(double v) => '\$${v.toStringAsFixed(2)}';
  static String _compact(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toString();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.sub,
    this.accent = false,
  });

  final String label;
  final String value;
  final String? sub;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: rb.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: rb.onSurface(0.09), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.bodyText(size: 11.5, color: rb.secondary(0.62)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: context.serif(
              size: 24,
              color: accent ? rb.accentText : rb.text,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              style: context.bodyText(size: 10.5, color: rb.secondary(0.5)),
            ),
          ],
        ],
      ),
    );
  }
}

class _KindBreakdown extends StatelessWidget {
  const _KindBreakdown({required this.usage});
  final AiUsage usage;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final rows = usage.byKind;
    final maxCost = rows.fold<double>(
      0,
      (m, k) => k.costUsd > m ? k.costUsd : m,
    );
    if (rows.isEmpty) {
      return const _EmptyHint('Sem uso de IA no período.');
    }
    return Container(
      decoration: BoxDecoration(
        color: rb.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: rb.onSurface(0.09), width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(
                        top: BorderSide(
                          color: rb.onSurface(0.08),
                          width: 0.5,
                        ),
                      ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      aiKindLabel(rows[i].kind),
                      style: context.bodyText(size: 12.5),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: maxCost == 0 ? 0 : rows[i].costUsd / maxCost,
                        minHeight: 6,
                        backgroundColor: rb.controlFill,
                        valueColor: AlwaysStoppedAnimation(rb.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 46,
                    child: Text(
                      '${rows[i].requests}×',
                      textAlign: TextAlign.right,
                      style: context.bodyText(
                        size: 11.5,
                        color: rb.secondary(0.6),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 58,
                    child: Text(
                      '\$${rows[i].costUsd.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: context.bodyText(
                        size: 12,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Gráfico de barras do custo diário (sem dependências). Barras com o acento,
/// rótulos de dia esparsos e tooltip com a data e o custo por barra.
class CostBarChart extends StatelessWidget {
  const CostBarChart({required this.days, super.key});
  final List<DayUsage> days;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    if (days.isEmpty) return const _EmptyHint('Sem dados no período.');
    final maxCost = days.fold<double>(
      0,
      (m, d) => d.costUsd > m ? d.costUsd : m,
    );
    final step = (days.length / 6).ceil().clamp(1, days.length);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: rb.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: rb.onSurface(0.09), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: Tooltip(
                      message: '${d.date} · \$${d.costUsd.toStringAsFixed(2)}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: _Bar(
                          fraction: maxCost == 0 ? 0 : d.costUsd / maxCost,
                          color: rb.accent,
                          track: rb.controlFill,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Text(
                    i % step == 0 ? _dayLabel(days[i].date) : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: context.bodyText(
                      size: 9,
                      color: rb.secondary(0.5),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _dayLabel(String isoDate) {
    final parts = isoDate.split('-');
    return parts.length == 3 ? parts[2] : isoDate;
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.color,
    required this.track,
  });
  final double fraction;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: fraction <= 0 ? 0.02 : fraction.clamp(0.02, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: fraction <= 0 ? track : color,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota});
  final UsageQuota quota;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final frac = quota.limit == 0 ? 0.0 : quota.used24h / quota.limit;
    final near = frac >= 0.8;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: rb.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: rb.onSurface(0.09), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cota de 24 horas',
                style: context.bodyText(size: 12.5, weight: FontWeight.w600),
              ),
              Text(
                '${quota.used24h} de ${quota.limit}',
                style: context.bodyText(
                  size: 12,
                  color: near ? RbTokens.warning : rb.secondary(0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: rb.controlFill,
              valueColor: AlwaysStoppedAnimation(
                near ? RbTokens.warning : rb.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: context.bodyText(
        size: 12,
        weight: FontWeight.w600,
        color: context.rb.secondary(0.65),
      ),
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 24),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.rb.card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.rb.onSurface(0.09), width: 0.5),
    ),
    child: Text(
      text,
      style: context.bodyText(size: 12.5, color: context.rb.secondary(0.6)),
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.rb.card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.rb.onSurface(0.09), width: 0.5),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          style: context.bodyText(size: 12.5, color: RbTokens.destructive),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
      ],
    ),
  );
}
