import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/pulse_dot.dart';
import 'package:rbnotes/features/ai/presentation/ask_cubit.dart';

/// Fundo escurecido com um card centralizado; toque fora fecha.
class ModalScaffold extends StatelessWidget {
  const ModalScaffold({
    required this.child,
    required this.onDismiss,
    this.alignment = Alignment.center,
    this.topPadding = 0,
    super.key,
  });

  final Widget child;
  final VoidCallback onDismiss;
  final Alignment alignment;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: const Color(0x2E1E1914),
        child: Padding(
          padding: EdgeInsets.only(top: topPadding),
          child: Align(
            alignment: alignment,
            child: GestureDetector(
              onTap: () {},
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Card de popover com a superfície `--pop`.
class PopCard extends StatelessWidget {
  const PopCard({
    required this.width,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final double width;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        padding: padding,
        decoration: BoxDecoration(
          color: rb.pop,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: rb.onSurface(0.15), width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x47000000),
              blurRadius: 80,
              offset: Offset(0, 30),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Overlay "Perguntar às notas" (⌘K).
class AskOverlay extends StatelessWidget {
  const AskOverlay({
    required this.onClose,
    required this.onOpenSource,
    required this.colorForNote,
    super.key,
  });

  final VoidCallback onClose;
  final ValueChanged<String> onOpenSource;
  final Color Function(String noteId) colorForNote;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return ModalScaffold(
      onDismiss: onClose,
      alignment: Alignment.topCenter,
      topPadding: 110,
      child: PopCard(
        width: 620,
        padding: EdgeInsets.zero,
        child: BlocBuilder<AskCubit, AskState>(
          builder: (context, state) {
            final cubit = context.read<AskCubit>();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: rb.onSurface(0.08), width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '?',
                        style: context.serif(size: 18, color: rb.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          autofocus: true,
                          onChanged: cubit.setQuery,
                          onSubmitted: cubit.submit,
                          cursorColor: rb.accent,
                          style: context.bodyText(size: 17),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText:
                                'Pergunte qualquer coisa sobre suas notas',
                            hintStyle: context.bodyText(
                              size: 17,
                              color: rb.secondary(0.45),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'esc',
                        style: context.bodyText(
                          size: 11,
                          color: rb.secondary(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.phase == AskPhase.idle)
                  _AskSuggestions(onPick: cubit.submit)
                else if (state.phase == AskPhase.thinking)
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Row(
                      children: [
                        PulseDot(color: rb.accent, size: 7),
                        const SizedBox(width: 10),
                        Text(
                          'Lendo suas notas…',
                          style: context.bodyText(
                            size: 13,
                            color: rb.secondary(0.65),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _AskAnswer(
                    state: state,
                    onOpenSource: onOpenSource,
                    colorForNote: colorForNote,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AskSuggestions extends StatelessWidget {
  const _AskSuggestions({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Text(
              'Sugestões',
              style: context.bodyText(
                size: 11,
                weight: FontWeight.w600,
                color: rb.secondary(0.5),
              ),
            ),
          ),
          for (final s in AskCubit.suggestions)
            GestureDetector(
              onTap: () => onPick(s),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                child: Text(s, style: context.bodyText(size: 13.5)),
              ),
            ),
        ],
      ),
    );
  }
}

class _AskAnswer extends StatelessWidget {
  const _AskAnswer({
    required this.state,
    required this.onOpenSource,
    required this.colorForNote,
  });

  final AskState state;
  final ValueChanged<String> onOpenSource;
  final Color Function(String noteId) colorForNote;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.answer,
            style: context.serif(
              size: 16.5,
              weight: FontWeight.w400,
              height: 1.6,
            ),
          ),
          if (state.phase == AskPhase.done && state.sources.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Fontes',
              style: context.bodyText(
                size: 11,
                weight: FontWeight.w600,
                color: rb.secondary(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in state.sources)
                  GestureDetector(
                    onTap: () => onOpenSource(s.noteId),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: rb.controlFill,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: colorForNote(s.noteId),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(s.title, style: context.bodyText(size: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Modal "Corrigir palavra".
class FixWordModal extends StatefulWidget {
  const FixWordModal({
    required this.wrong,
    required this.suggestion,
    required this.occurrencesText,
    required this.onClose,
    required this.onApply,
    super.key,
  });

  final String wrong;
  final String suggestion;
  final String occurrencesText;
  final VoidCallback onClose;
  final void Function(
    String to, {
    required bool everywhere,
    required bool addVocab,
  })
  onApply;

  @override
  State<FixWordModal> createState() => _FixWordModalState();
}

class _FixWordModalState extends State<FixWordModal> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.suggestion,
  );
  bool _everywhere = true;
  bool _vocab = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return ModalScaffold(
      onDismiss: widget.onClose,
      child: PopCard(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Corrigir palavra',
              style: context.bodyText(size: 15, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'O Whisper ouviu “${widget.wrong}” com baixa confiança. '
              'Como se escreve?',
              style: context.bodyText(
                size: 12.5,
                height: 1.5,
                color: rb.secondary(0.7),
              ),
            ),
            const SizedBox(height: 14),
            _FieldBox(controller: _controller),
            const SizedBox(height: 14),
            _CheckRow(
              checked: _everywhere,
              title: 'Corrigir em todas as notas',
              subtitle: widget.occurrencesText,
              onTap: () => setState(() => _everywhere = !_everywhere),
            ),
            const SizedBox(height: 12),
            _CheckRow(
              checked: _vocab,
              title: 'Adicionar ao vocabulário do Whisper',
              subtitle: 'Para acertar nas próximas gravações',
              onTap: () => setState(() => _vocab = !_vocab),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ModalButton(
                  label: 'Cancelar',
                  onTap: widget.onClose,
                  background: rb.controlFill,
                ),
                const SizedBox(width: 8),
                _ModalButton(
                  label: 'Corrigir',
                  onTap: () => widget.onApply(
                    _controller.text.trim(),
                    everywhere: _everywhere,
                    addVocab: _vocab,
                  ),
                  background: rb.accent,
                  foreground: Colors.white,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal "Nova coleção inteligente".
class NewCollectionModal extends StatefulWidget {
  const NewCollectionModal({
    required this.onClose,
    required this.onCreate,
    super.key,
  });

  final VoidCallback onClose;
  final ValueChanged<String> onCreate;

  @override
  State<NewCollectionModal> createState() => _NewCollectionModalState();
}

class _NewCollectionModalState extends State<NewCollectionModal> {
  final _controller = TextEditingController();

  static const _examples = [
    'Tudo sobre o app de finanças',
    'Conversas com o Rafael',
    'Ideias sobre o podcast',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return ModalScaffold(
      onDismiss: widget.onClose,
      child: PopCard(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nova coleção inteligente',
              style: context.bodyText(size: 15, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Descreva o que deve entrar. O Claude cria a regra e a coleção '
              'se atualiza sozinha a cada nova nota.',
              style: context.bodyText(
                size: 12.5,
                height: 1.5,
                color: rb.secondary(0.7),
              ),
            ),
            const SizedBox(height: 14),
            _FieldBox(
              controller: _controller,
              hint: 'Ex.: tudo sobre o app de finanças',
              autofocus: true,
              onSubmitted: (v) => widget.onCreate(v.trim()),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _examples)
                  GestureDetector(
                    onTap: () => _controller.text = e,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rb.controlFill,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text(e, style: context.bodyText(size: 12)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ModalButton(
                  label: 'Cancelar',
                  onTap: widget.onClose,
                  background: rb.controlFill,
                ),
                const SizedBox(width: 8),
                _ModalButton(
                  label: 'Criar coleção',
                  onTap: () => widget.onCreate(_controller.text.trim()),
                  background: rb.accent,
                  foreground: Colors.white,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Toast flutuante no topo.
class ShellToast extends StatelessWidget {
  const ShellToast({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 64),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xEB1C1C1E),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              message,
              style: context.bodyText(
                size: 12.5,
                weight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({
    required this.controller,
    this.hint,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: rb.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: rb.onSurface(0.22), width: 0.5),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        cursorColor: rb.accent,
        style: context.bodyText(size: 14),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: context.bodyText(size: 14, color: rb.secondary(0.45)),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.checked,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool checked;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: checked ? rb.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: checked
                  ? null
                  : Border.all(color: rb.secondary(0.35), width: 1.5),
            ),
            child: checked
                ? const Icon(Icons.check, size: 10, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.bodyText(size: 13)),
                Text(
                  subtitle,
                  style: context.bodyText(
                    size: 11.5,
                    color: rb.secondary(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModalButton extends StatelessWidget {
  const _ModalButton({
    required this.label,
    required this.onTap,
    required this.background,
    this.foreground,
  });

  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: context.bodyText(
            size: 13,
            weight: FontWeight.w600,
            color: foreground ?? context.rb.text,
          ),
        ),
      ),
    );
  }
}
