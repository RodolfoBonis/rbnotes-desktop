import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/app/shell/detail_toolbar.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/rb_lottie.dart';
import 'package:rbnotes/features/collections/domain/forgotten_tasks.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';

/// Painel "Tarefas esquecidas" (ações abertas há mais de 3 dias).
class TasksPane extends StatelessWidget {
  const TasksPane({
    required this.onDone,
    required this.onSnooze,
    required this.onDismiss,
    required this.onOpenNote,
    required this.onOpenAsk,
    required this.onStartRecording,
    super.key,
  });

  final ValueChanged<ForgottenTask> onDone;
  final ValueChanged<ForgottenTask> onSnooze;
  final ValueChanged<ForgottenTask> onDismiss;
  final ValueChanged<String> onOpenNote;
  final VoidCallback onOpenAsk;
  final VoidCallback onStartRecording;

  static String _intro(int count) {
    if (count == 0) return 'Nenhuma tarefa parada há mais de 3 dias.';
    final noun = count == 1 ? 'tarefa aberta' : 'tarefas abertas';
    return '$count $noun há mais de 3 dias, encontradas nas suas notas.';
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return ColoredBox(
      color: rb.bg,
      child: Column(
        children: [
          DetailToolbar(
            onOpenAsk: onOpenAsk,
            onStartRecording: onStartRecording,
          ),
          Expanded(
            child: BlocBuilder<LibraryCubit, LibraryState>(
              builder: (context, state) {
                final tasks = state.forgotten(DateTime.now());
                return SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(40, 34, 40, 80),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Coleção inteligente',
                              style: context.bodyText(
                                size: 12,
                                color: rb.secondary(0.65),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Tarefas esquecidas',
                              style: context.serif(
                                size: 30,
                                weight: FontWeight.w500,
                                height: 1.15,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _intro(tasks.length),
                              style: context.bodyText(
                                size: 14,
                                height: 1.5,
                                color: rb.secondary(0.7),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (tasks.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 40,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    RbLottie(
                                      asset: 'assets/lottie/pulse.json',
                                      size: 64,
                                      recolor: context.rb.accent,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Nada esquecido.',
                                      style: context.serif(size: 20),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Todas as tarefas das suas notas '
                                      'estão em dia.',
                                      style: context.bodyText(
                                        size: 13,
                                        color: rb.secondary(0.65),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              for (final t in tasks)
                                _TaskCard(
                                  task: t,
                                  onDone: () => onDone(t),
                                  onSnooze: () => onSnooze(t),
                                  onDismiss: () => onDismiss(t),
                                  onOpenNote: () => onOpenNote(t.noteId),
                                ),
                          ],
                        ),
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

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onDone,
    required this.onSnooze,
    required this.onDismiss,
    required this.onOpenNote,
  });

  final ForgottenTask task;
  final VoidCallback onDone;
  final VoidCallback onSnooze;
  final VoidCallback onDismiss;
  final VoidCallback onOpenNote;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: rb.fill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onDone,
            behavior: HitTestBehavior.opaque,
            child: Container(
              margin: const EdgeInsets.only(top: 1),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: rb.secondary(0.35), width: 1.5),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.text,
                  style: context.bodyText(
                    size: 14,
                    weight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    GestureDetector(
                      onTap: onOpenNote,
                      child: Text(
                        task.noteTitle,
                        style: context.bodyText(size: 12, color: rb.accent),
                      ),
                    ),
                    Text(
                      '·',
                      style: context.bodyText(
                        size: 12,
                        color: rb.secondary(0.65),
                      ),
                    ),
                    Text(
                      'há ${task.ageDays} dias',
                      style: context.bodyText(
                        size: 12,
                        color: rb.secondary(0.65),
                      ),
                    ),
                    if (task.owner != null) ...[
                      Text(
                        '·',
                        style: context.bodyText(
                          size: 12,
                          color: rb.secondary(0.65),
                        ),
                      ),
                      Text(
                        task.owner!.split(' ·').first,
                        style: context.bodyText(
                          size: 12,
                          color: rb.secondary(0.65),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _SmallButton(
                      label: 'Lembrar amanhã',
                      onTap: onSnooze,
                      background: rb.controlFill,
                    ),
                    const SizedBox(width: 6),
                    _SmallButton(
                      label: 'Não é mais relevante',
                      onTap: onDismiss,
                      foreground: rb.secondary(0.75),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    this.background,
    this.foreground,
  });

  final String label;
  final VoidCallback onTap;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background ?? Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: context.bodyText(
            size: 12,
            weight: FontWeight.w500,
            color: foreground ?? context.rb.text,
          ),
        ),
      ),
    );
  }
}
