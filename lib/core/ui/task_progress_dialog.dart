import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';

/// Diálogo não-dispensável genérico de progresso para tarefas longas (ex.:
/// exportação). Mostra um título fixo e uma mensagem/barra ao vivo.
class TaskProgressDialog extends StatelessWidget {
  const TaskProgressDialog({
    required this.title,
    required this.message,
    this.progress,
    super.key,
  });

  final String title;
  final ValueListenable<String> message;

  /// Progresso 0..1; null = indeterminado.
  final ValueListenable<double?>? progress;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Dialog(
      backgroundColor: rb.bg3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.serif(size: 18)),
              const SizedBox(height: 14),
              ValueListenableBuilder<double?>(
                valueListenable: progress ?? ValueNotifier<double?>(null),
                builder: (context, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    backgroundColor: rb.controlFill,
                    valueColor: AlwaysStoppedAnimation(rb.accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: message,
                builder: (context, text, _) => Text(
                  text,
                  style: context.bodyText(size: 13, color: rb.secondary(0.7)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
