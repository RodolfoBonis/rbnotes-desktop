import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rbnotes/app/shell/detail_toolbar.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/features/diary/domain/diary_calendar.dart';
import 'package:rbnotes/features/diary/presentation/diary_cubit.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';

/// Painel do Diário: pergunta do dia, gravar resposta, calendário com sequência
/// e "seu mês até agora". Protegido por Touch ID.
class DiaryPane extends StatelessWidget {
  const DiaryPane({
    required this.onRecord,
    required this.onOpenAsk,
    required this.onStartRecording,
    super.key,
  });

  /// Grava uma resposta para a pergunta do dia (modo diário).
  final VoidCallback onRecord;
  final VoidCallback onOpenAsk;
  final VoidCallback onStartRecording;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.rb.bg,
      child: Column(
        children: [
          DetailToolbar(
            onOpenAsk: onOpenAsk,
            onStartRecording: onStartRecording,
          ),
          Expanded(
            child: BlocBuilder<DiaryCubit, DiaryState>(
              builder: (context, state) {
                // O diário é coberto pela trava do app; o resumo do mês só é
                // gerado (diaryMonth) depois que o app está desbloqueado.
                final appLocked = context.watch<AppLockCubit>().state.locked;
                if (!appLocked && !state.monthLoaded) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    unawaited(context.read<DiaryCubit>().loadMonth());
                  });
                }
                return SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(40, 34, 40, 80),
                        child: _DiaryContent(state: state, onRecord: onRecord),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DiaryContent extends StatelessWidget {
  const _DiaryContent({required this.state, required this.onRecord});
  final DiaryState state;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final cubit = context.read<DiaryCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Privado · protegido por Touch ID',
          style: context.bodyText(size: 12, color: rb.secondary(0.65)),
        ),
        const SizedBox(height: 10),
        Text(
          'Diário',
          style: context.serif(
            size: 30,
            weight: FontWeight.w500,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            color: rb.warm,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PERGUNTA DE HOJE',
                style: context.bodyText(
                  size: 11,
                  weight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: rb.secondary(0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                state.prompt,
                style: context.serif(
                  size: 24,
                  weight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  GestureDetector(
                    onTap: onRecord,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.fromLTRB(11, 0, 14, 0),
                      decoration: BoxDecoration(
                        color: rb.accent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Gravar resposta',
                            style: context.bodyText(
                              size: 13,
                              weight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: cubit.nextPrompt,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      'Outra pergunta',
                      style: context.bodyText(
                        size: 12.5,
                        color: rb.secondary(0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _CalendarCard(state: state)),
            const SizedBox(width: 16),
            Expanded(child: _MonthCard(state: state)),
          ],
        ),
      ],
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.state});
  final DiaryState state;

  static const _weekdays = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final monthName = toBeginningOfSentenceCase(
      DateFormat.MMMM('pt_BR').format(DateTime.now()),
    );
    final streak = state.calendar.streak;
    final streakLabel =
        '$streak ${streak == 1 ? 'dia seguido' : 'dias seguidos'}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: rb.fill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                monthName,
                style: context.bodyText(size: 13, weight: FontWeight.w600),
              ),
              Text(
                streakLabel,
                style: context.bodyText(
                  size: 12,
                  weight: FontWeight.w600,
                  color: rb.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final d in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: context.bodyText(
                        size: 10.5,
                        weight: FontWeight.w600,
                        color: rb.secondary(0.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.5,
            children: [
              for (final cell in state.calendar.cells) _DayCell(cell: cell),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.cell});
  final DiaryDayCell cell;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    if (cell.isFiller) return const SizedBox.shrink();
    final fg = cell.isFuture
        ? rb.secondary(0.3)
        : cell.hasEntry
        ? rb.text
        : rb.secondary(0.6);
    return Container(
      decoration: BoxDecoration(
        color: cell.hasEntry ? rb.accentWash(0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: cell.isToday ? Border.all(color: rb.accent, width: 1.5) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${cell.day}',
        style: context.bodyText(
          size: 12,
          weight: cell.hasEntry || cell.isToday
              ? FontWeight.w600
              : FontWeight.w400,
          color: fg,
        ),
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.state});
  final DiaryState state;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: rb.fill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SEU MÊS ATÉ AGORA',
            style: context.bodyText(
              size: 11,
              weight: FontWeight.w600,
              letterSpacing: 0.4,
              color: rb.secondary(0.6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            state.monthSummary.isEmpty
                ? 'Gerando o resumo do mês…'
                : state.monthSummary,
            style: context.serif(
              size: 15,
              weight: FontWeight.w400,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in state.themes)
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: rb.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: rb.onSurface(0.1), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.name, style: context.bodyText(size: 12)),
                      const SizedBox(width: 6),
                      Text(
                        '${t.count}',
                        style: context.bodyText(
                          size: 12,
                          color: rb.secondary(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Gerado pelo Claude a partir de ${state.entriesCount} entradas',
            style: context.bodyText(size: 11, color: rb.secondary(0.55)),
          ),
        ],
      ),
    );
  }
}
