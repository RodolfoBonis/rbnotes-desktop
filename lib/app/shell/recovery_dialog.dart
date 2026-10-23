import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forma_ui/forma_ui.dart';
import 'package:rbnotes/core/format/formatters.dart';
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
    return BlocBuilder<RecoveryCubit, RecoveryState>(
      builder: (context, state) {
        final cubit = context.read<RecoveryCubit>();
        if (!state.hasRecoverable) {
          return const SizedBox.shrink();
        }
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
                  style: context.formaTypography.body13,
                ),
                const SizedBox(height: FormaSpacing.base),
                for (final rec in state.recoverable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FormaSpacing.sm),
                    child: Row(
                      children: [
                        const Icon(Icons.restore_rounded, size: 18),
                        const SizedBox(width: FormaSpacing.sm),
                        Expanded(
                          child: Text(
                            'Gravação ${Formatters.duration(rec.duration)}',
                            style: context.formaTypography.body14,
                          ),
                        ),
                        FormaButton.secondary(
                          label: 'Descartar',
                          small: true,
                          onPressed: () => cubit.discard(rec),
                        ),
                        const SizedBox(width: FormaSpacing.xs),
                        FormaButton.primary(
                          label: 'Recuperar',
                          small: true,
                          onPressed: () => cubit.recover(rec),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            FormaButton.secondary(
              label: 'Fechar',
              small: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}
