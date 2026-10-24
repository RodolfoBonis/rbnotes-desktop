import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/features/settings/data/erase_all_service.dart';

/// Diálogo não-dispensável que mostra o progresso de "Apagar todos os dados".
class EraseProgressDialog extends StatelessWidget {
  const EraseProgressDialog({required this.progress, super.key});

  final ValueListenable<EraseProgress?> progress;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Dialog(
      backgroundColor: rb.bg3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          child: ValueListenableBuilder<EraseProgress?>(
            valueListenable: progress,
            builder: (context, p, _) {
              final value = p == null || p.total == 0 ? null : p.step / p.total;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Apagando seus dados', style: context.serif(size: 18)),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 4,
                      backgroundColor: rb.controlFill,
                      valueColor: AlwaysStoppedAnimation(rb.accent),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    p?.label ?? 'Preparando…',
                    style: context.bodyText(size: 13, color: rb.secondary(0.7)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
