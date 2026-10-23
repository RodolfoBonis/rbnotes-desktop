import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';

/// Dropdown nativo estilo macOS (NSPopUpButton): abre um menu popup ancorado no
/// campo, com o item atual marcado (check), navegação por setas + Enter, Esc
/// para fechar e rolagem quando a lista é longa. Visual claro/escuro do design.
///
/// Substitui o antigo "pill que só cicla" dos selects do app.
class RbSelect<T> extends StatefulWidget {
  const RbSelect({
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelOf,
    this.leadingOf,
    this.enabled = true,
    this.minMenuWidth = 180,
    super.key,
  });

  final T value;
  final List<T> options;
  final ValueChanged<T> onChanged;

  /// Rótulo de cada opção (default: `toString`).
  final String Function(T value)? labelOf;

  /// Widget opcional à esquerda de cada opção (ex.: bolinha de cor da pasta).
  final Widget Function(T value)? leadingOf;

  final bool enabled;
  final double minMenuWidth;

  String _label(T v) => labelOf?.call(v) ?? '$v';

  @override
  State<RbSelect<T>> createState() => _RbSelectState<T>();
}

class _RbSelectState<T> extends State<RbSelect<T>> {
  final _link = LayerLink();
  final _menuController = OverlayPortalController();
  final _focusNode = FocusNode(debugLabel: 'RbSelect');
  final _scroll = ScrollController();

  int _highlight = 0;
  Size _fieldSize = Size.zero;

  static const _rowHeight = 30.0;
  static const _maxMenuHeight = 300.0;

  bool get _isOpen => _menuController.isShowing;

  void _open() {
    if (!widget.enabled || widget.options.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    _fieldSize = box?.size ?? Size.zero;
    _highlight = widget.options
        .indexOf(widget.value)
        .clamp(
          0,
          widget.options.length - 1,
        );
    _menuController.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _scrollToHighlight();
    });
    setState(() {});
  }

  void _close() {
    if (!_isOpen) return;
    _menuController.hide();
    setState(() {});
  }

  void _select(int index) {
    if (index < 0 || index >= widget.options.length) return;
    final option = widget.options[index];
    _close();
    widget.onChanged(option);
  }

  void _moveHighlight(int delta) {
    final n = widget.options.length;
    setState(() => _highlight = (_highlight + delta) % n);
    if (_highlight < 0) _highlight += n;
    _scrollToHighlight();
  }

  void _scrollToHighlight() {
    if (!_scroll.hasClients) return;
    final target = _highlight * _rowHeight;
    final viewport = _scroll.position.viewportDimension;
    final current = _scroll.offset;
    if (target < current) {
      _scroll.jumpTo(target);
    } else if (target + _rowHeight > current + viewport) {
      _scroll.jumpTo(target + _rowHeight - viewport);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _moveHighlight(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveHighlight(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.space:
        _select(_highlight);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _close();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _menuController,
        overlayChildBuilder: _buildMenu,
        child: _RbSelectField(
          label: widget._label(widget.value),
          leading: widget.leadingOf?.call(widget.value),
          enabled: widget.enabled,
          open: _isOpen,
          onTap: _isOpen ? _close : _open,
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final rb = context.rb;
    final width = _fieldSize.width < widget.minMenuWidth
        ? widget.minMenuWidth
        : _fieldSize.width;
    return Stack(
      children: [
        // Captura toques fora do menu para fechar.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          offset: const Offset(0, 6),
          child: Align(
            alignment: Alignment.topLeft,
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _onKey,
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  width: width,
                  constraints: const BoxConstraints(
                    maxHeight: _maxMenuHeight,
                  ),
                  decoration: BoxDecoration(
                    color: rb.pop,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: rb.onSurface(0.12), width: 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: rb.onSurface(0.22),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _MenuList<T>(
                    options: widget.options,
                    labelOf: widget._label,
                    leadingOf: widget.leadingOf,
                    selected: widget.value,
                    highlight: _highlight,
                    scroll: _scroll,
                    rowHeight: _rowHeight,
                    onHover: (i) => setState(() => _highlight = i),
                    onSelect: _select,
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

class _MenuList<T> extends StatelessWidget {
  const _MenuList({
    required this.options,
    required this.labelOf,
    required this.leadingOf,
    required this.selected,
    required this.highlight,
    required this.scroll,
    required this.rowHeight,
    required this.onHover,
    required this.onSelect,
  });

  final List<T> options;
  final String Function(T) labelOf;
  final Widget Function(T)? leadingOf;
  final T selected;
  final int highlight;
  final ScrollController scroll;
  final double rowHeight;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return ListView.builder(
      controller: scroll,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: options.length,
      itemExtent: rowHeight,
      itemBuilder: (context, i) {
        final option = options[i];
        final isSelected = option == selected;
        final isHighlighted = i == highlight;
        return MouseRegion(
          onEnter: (_) => onHover(i),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(i),
            child: Container(
              height: rowHeight,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isHighlighted ? rb.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            size: 14,
                            color: isHighlighted ? Colors.white : rb.accent,
                          )
                        : null,
                  ),
                  if (leadingOf != null) ...[
                    leadingOf!(option),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      labelOf(option),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.bodyText(
                        size: 13,
                        color: isHighlighted ? Colors.white : rb.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RbSelectField extends StatelessWidget {
  const _RbSelectField({
    required this.label,
    required this.leading,
    required this.enabled,
    required this.open,
    required this.onTap,
  });

  final String label;
  final Widget? leading;
  final bool enabled;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 24,
          padding: const EdgeInsets.fromLTRB(10, 0, 7, 0),
          decoration: BoxDecoration(
            color: rb.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: open ? rb.accent : rb.onSurface(0.2),
              width: open ? 1 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.bodyText(size: 12.5),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.unfold_more, size: 12, color: rb.secondary(0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
