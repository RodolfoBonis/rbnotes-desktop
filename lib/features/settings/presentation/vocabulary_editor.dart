import 'package:flutter/material.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:uuid/uuid.dart';

/// Editor do "Vocabulário personalizado": lista, adiciona e remove termos que
/// viram o `initialPrompt` do Whisper.
class VocabularyEditorDialog extends StatefulWidget {
  const VocabularyEditorDialog({required this.repository, super.key});

  final VocabularyRepository repository;

  @override
  State<VocabularyEditorDialog> createState() => _VocabularyEditorDialogState();
}

class _VocabularyEditorDialogState extends State<VocabularyEditorDialog> {
  final _controller = TextEditingController();
  final _uuid = const Uuid();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final term = _controller.text.trim();
    if (term.isEmpty) return;
    await widget.repository.add(_uuid.v4(), term);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Dialog(
      backgroundColor: rb.pop,
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vocabulário personalizado',
                style: context.bodyText(size: 15, weight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Nomes e termos que o Whisper deve reconhecer.',
                style: context.bodyText(size: 12, color: rb.secondary(0.65)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Adicionar termo',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _add, child: const Text('Adicionar')),
                ],
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: StreamBuilder<List<VocabularyRow>>(
                  stream: widget.repository.watchTerms(),
                  builder: (context, snapshot) {
                    final terms = snapshot.data ?? const <VocabularyRow>[];
                    if (terms.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Nenhum termo ainda.',
                          style: context.bodyText(
                            size: 12.5,
                            color: rb.secondary(0.6),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: terms.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: rb.hairline),
                      itemBuilder: (context, i) {
                        final t = terms[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.term,
                                  style: context.bodyText(size: 13),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => widget.repository.remove(t.id),
                                behavior: HitTestBehavior.opaque,
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: rb.secondary(0.6),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
