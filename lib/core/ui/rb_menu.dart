import 'package:flutter/material.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';

/// Um item do menu de contexto (clique direito / "…"), estilo macOS.
class RbMenuItem<T> {
  const RbMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
    this.dividerAbove = false,
    this.trailing,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool destructive;

  /// Desenha um separador acima deste item (agrupa ações).
  final bool dividerAbove;

  /// Ex.: um chevron para indicar submenu, ou um check.
  final Widget? trailing;
  final bool enabled;
}

/// Abre um menu de contexto na posição global [position] e devolve o valor do
/// item escolhido (ou null se fechou sem escolher). Visual claro/escuro do
/// design; teclado (setas/Enter/Esc) e dismiss por fora vêm do `showMenu`.
Future<T?> showRbMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<RbMenuItem<T>> items,
  double width = 240,
}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final rb = context.rb;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(position, position),
      Offset.zero & overlay.size,
    ),
    color: rb.pop,
    elevation: 12,
    shadowColor: rb.onSurface(0.3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: rb.onSurface(0.12), width: 0.5),
    ),
    constraints: BoxConstraints(minWidth: width, maxWidth: width),
    items: [
      for (final item in items)
        PopupMenuItem<T>(
          value: item.value,
          enabled: item.enabled,
          height: 34,
          padding: EdgeInsets.zero,
          child: _RbMenuRow(item: item),
        ),
    ],
  );
}

class _RbMenuRow<T> extends StatelessWidget {
  const _RbMenuRow({required this.item});
  final RbMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final color = !item.enabled
        ? rb.secondary(0.35)
        : item.destructive
        ? RbTokens.destructive
        : rb.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.dividerAbove)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Divider(height: 1, thickness: 0.5, color: rb.onSurface(0.1)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 15, color: color),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: context.bodyText(size: 13, color: color),
                ),
              ),
              if (item.trailing != null) item.trailing!,
            ],
          ),
        ),
      ],
    );
  }
}
