import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/features/security/data/note_cipher.dart';
import 'package:rbnotes/features/security/data/note_key.dart';
import 'package:rbnotes/features/security/data/note_key_store.dart';

/// Diálogo "Chave de recuperação" da aba Privacidade.
///
/// Mostra e copia a chave AES das notas bloqueadas em base32 agrupado e
/// deixa
/// importar uma chave de outro Mac (com teste de round-trip antes de
/// salvar).
class RecoveryKeyDialog extends StatefulWidget {
  const RecoveryKeyDialog({
    required this.keyStore,
    this.onKeyChanged,
    super.key,
  });

  final NoteKeyStore keyStore;

  /// Chamado depois de importar/gerar uma chave (para invalidar caches, ex.: o
  /// `SyncCrypto`).
  final VoidCallback? onKeyChanged;

  @override
  State<RecoveryKeyDialog> createState() => _RecoveryKeyDialogState();
}

class _RecoveryKeyDialogState extends State<RecoveryKeyDialog> {
  final _import = TextEditingController();
  NoteKey? _current;
  bool _loading = true;
  bool _revealed = false;
  String? _message;
  bool _messageOk = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final key = await widget.keyStore.load();
    if (!mounted) return;
    setState(() {
      _current = key;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _import.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final key = _current;
    if (key == null) return;
    await Clipboard.setData(ClipboardData(text: key.recovery));
    if (mounted) {
      setState(() {
        _message = 'Chave copiada.';
        _messageOk = true;
      });
    }
  }

  Future<void> _importKey() async {
    final raw = _import.text.trim();
    if (raw.isEmpty) return;
    try {
      final key = NoteKey.fromRecovery(raw);
      // Teste de round-trip antes de salvar: a chave precisa cifrar/decifrar.
      final cipher = NoteCipher(key);
      final probe = await cipher.encrypt({'probe': 'ok'});
      final back = await cipher.decrypt(probe);
      if (back['probe'] != 'ok') throw const FormatException('round-trip');
      await widget.keyStore.import(key);
      widget.onKeyChanged?.call();
      if (mounted) {
        setState(() {
          _current = key;
          _import.clear();
          _message = 'Chave importada e testada com sucesso.';
          _messageOk = true;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'Chave de recuperação inválida.';
          _messageOk = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return AlertDialog(
      backgroundColor: rb.card,
      title: const Text('Chave de recuperação'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Guarde esta chave em local seguro. Com ela, outro Mac consegue '
              'abrir suas notas bloqueadas sincronizadas.',
              style: context.bodyText(
                size: 12,
                height: 1.4,
                color: rb.secondary(0.7),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_current == null)
              Text(
                'Nenhuma chave ainda. Bloqueie uma nota para gerá-la, ou '
                'importe uma chave abaixo.',
                style: context.bodyText(size: 12.5, color: rb.secondary(0.7)),
              )
            else
              _KeyBox(
                recovery: _current!.recovery,
                revealed: _revealed,
                onReveal: () => setState(() => _revealed = true),
                onCopy: _copy,
              ),
            const SizedBox(height: 18),
            Text(
              'Importar de outro Mac',
              style: context.bodyText(size: 12, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const Key('recovery-import-field'),
              controller: _import,
              minLines: 1,
              maxLines: 2,
              style: context.bodyText(size: 12.5),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Cole a chave (base32)…',
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(
                _message!,
                style: context.bodyText(
                  size: 11.5,
                  color: _messageOk
                      ? RbTokens.permitGreen
                      : RbTokens.destructive,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
        TextButton(
          key: const Key('recovery-import-button'),
          onPressed: _importKey,
          child: const Text('Importar e testar'),
        ),
      ],
    );
  }
}

class _KeyBox extends StatelessWidget {
  const _KeyBox({
    required this.recovery,
    required this.revealed,
    required this.onReveal,
    required this.onCopy,
  });

  final String recovery;
  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: rb.fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: rb.onSurface(0.1), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            revealed ? recovery : _mask(recovery),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.5,
              letterSpacing: 0.5,
              color: rb.text,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!revealed)
                _MiniButton(
                  label: 'Mostrar',
                  icon: Icons.visibility_outlined,
                  onTap: onReveal,
                ),
              if (revealed)
                _MiniButton(
                  label: 'Copiar',
                  icon: Icons.copy_outlined,
                  onTap: onCopy,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _mask(String s) => s.replaceAll(RegExp('[A-Z2-7]'), '•');
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: rb.controlFill,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: rb.text),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.bodyText(size: 12, weight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
