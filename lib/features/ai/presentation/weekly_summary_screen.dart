import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/presentation/weekly_summary_cubit.dart';

/// Tela "Resumo da semana" (overlay): panorama gerado pelo Claude das notas e
/// tarefas da semana (exceto bloqueadas). Acessível pela sidebar e pela
/// notificação de segunda-feira.
class WeeklySummaryScreen extends StatelessWidget {
  const WeeklySummaryScreen({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: const Color(0x241E1914),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 620,
                constraints: const BoxConstraints(maxHeight: 560),
                decoration: BoxDecoration(
                  color: rb.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: rb.onSurface(0.18), width: 0.5),
                  boxShadow: const [
                    BoxShadow(
                      color: RbTokens.scrim,
                      blurRadius: 80,
                      offset: Offset(0, 30),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: BlocBuilder<WeeklySummaryCubit, WeeklySummaryState>(
                  builder: (context, state) => _Body(state: state),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});
  final WeeklySummaryState state;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    if (state.loading && state.summary == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null && state.summary == null) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.error!,
              style: context.bodyText(size: 13, color: RbTokens.destructive),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.read<WeeklySummaryCubit>().generate(),
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      );
    }
    final s = state.summary;
    if (s == null) return const SizedBox(height: 200);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(34, 30, 34, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumo da semana',
            style: context.bodyText(size: 12, color: rb.secondary(0.6)),
          ),
          const SizedBox(height: 8),
          Text(s.title, style: context.serif(size: 30, height: 1.15)),
          const SizedBox(height: 16),
          Text(
            s.summary,
            style: context.bodyText(size: 14.5, height: 1.6, color: rb.text),
          ),
          if (s.highlights.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _Section(title: 'Destaques'),
            for (final h in s.highlights) _Bullet(text: h),
          ],
          if (s.openTasks.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _Section(title: 'Em aberto'),
            for (final t in s.openTasks) _Bullet(text: t.text),
          ],
          if (s.themes.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _Section(title: 'Temas'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final t in s.themes) _ThemeChip(theme: t)],
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: context.bodyText(
        size: 12,
        weight: FontWeight.w600,
        color: context.rb.secondary(0.6),
      ),
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: rb.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: context.bodyText(size: 13.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({required this.theme});
  final DiaryTheme theme;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: rb.accentWash(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${theme.name} · ${theme.count}',
        style: context.bodyText(
          size: 12,
          weight: FontWeight.w500,
          color: rb.accentText,
        ),
      ),
    );
  }
}
