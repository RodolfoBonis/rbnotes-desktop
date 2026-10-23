import 'package:flutter/material.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';

/// Barra superior (52px) compartilhada pelo detalhe, diário e tarefas:
/// "Perguntar às notas" (⌘K), exportar e "Gravar" (⌘R), como no design v3.
class DetailToolbar extends StatelessWidget {
  const DetailToolbar({
    required this.onOpenAsk,
    required this.onStartRecording,
    this.onExport,
    super.key,
  });

  final VoidCallback onOpenAsk;
  final VoidCallback onStartRecording;

  /// Exportar a nota atual. Quando `null`, o ícone de compartilhar fica inerte
  /// (diário/tarefas não têm nota em foco), mas continua visível como no design.
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: rb.onSurface(0.07), width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: onOpenAsk,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 28,
              padding: const EdgeInsets.fromLTRB(11, 0, 10, 0),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rb.controlFill,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  Text(
                    'Perguntar às notas',
                    style: context.bodyText(
                      size: 12.5,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '⌘K',
                    style: context.bodyText(size: 11, color: rb.secondary(0.5)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onExport,
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: onExport == null ? 0.55 : 1,
              child: SizedBox(
                width: 28,
                height: 28,
                child: Icon(
                  Icons.ios_share,
                  size: 15,
                  color: rb.secondary(0.75),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onStartRecording,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 30,
              padding: const EdgeInsets.fromLTRB(10, 0, 13, 0),
              decoration: BoxDecoration(
                color: rb.accent,
                borderRadius: BorderRadius.circular(15),
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
                    'Gravar',
                    style: context.bodyText(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '⌘R',
                    style: context.bodyText(
                      size: 11,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
