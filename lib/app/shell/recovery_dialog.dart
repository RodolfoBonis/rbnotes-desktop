import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/core/format/formatters.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/features/recording/presentation/recovery_cubit.dart';

/// Oferece recuperar ou descartar gravações interrompidas.
Future<void> showRecoveryDialog(BuildContext context, RecoveryCubit cubit) {
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: const _RecoveryDialog(),
    ),
  );
}

class _RecoveryDialog extends StatelessWidget {
  const _RecoveryDialog();

  @override
  Widget build(BuildContext context) {
    // Fecha sozinho quando não sobra nada para recuperar: sem isso o diálogo
    // ficava vazio e a barreira cinza bloqueava o app.
    return BlocConsumer<RecoveryCubit, RecoveryState>(
      listenWhen: (prev, next) => prev.hasRecoverable && !next.hasRecoverable,
      listener: (context, _) => Navigator.of(context).maybePop(),
      builder: (context, state) {
        final cubit = context.read<RecoveryCubit>();
        final rb = context.rb;
        final body = Theme.of(context).textTheme.bodyMedium;
        return AlertDialog(
          title: const Text('Gravações interrompidas'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Encontramos gravações que não foram finalizadas. '
                  'Recuperar transcreve e salva como nota.',
                  style: body?.copyWith(color: rb.textSecondary),
                ),
                const SizedBox(height: 16),
                for (final rec in state.recoverable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.restore_rounded,
                          size: 18,
                          color: rb.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Gravação ${Formatters.duration(rec.duration)}',
                            style: body,
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: RbTokens.destructive,
                          ),
                          onPressed: () => cubit.discard(rec),
                          child: const Text('Descartar'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: () => cubit.recover(rec),
                          child: const Text('Recuperar'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }
}
