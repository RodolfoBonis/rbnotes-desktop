import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/features/security/data/note_cipher.dart';
import 'package:rbnotes/features/security/data/note_key.dart';
import 'package:rbnotes/features/security/data/note_key_store.dart';

/// Valor claro do sentinela da chave (M10): um envelope cifrado com a chave
/// guardado localmente; uma chave de recuperação importada só é aceita se
/// decifrar o sentinela de volta a este valor.
const _keyCheckClear = {'check': 'rbnotes-key-check'};

/// Tempo até limpar a área de transferência depois de copiar a chave (M13).
const _clipboardClearAfter = Duration(seconds: 60);

/// Limpa a área de transferência (M13), mas só se ela ainda contiver [value] —
/// o usuário pode ter copiado outra coisa nesse meio-tempo. Exposto para teste.
@visibleForTesting
Future<void> clearRecoveryClipboard(
  String value, {
  Future<ClipboardData?> Function()? read,
  Future<void> Function(ClipboardData) write = Clipboard.setData,
}) async {
  final readData = read ?? () => Clipboard.getData(Clipboard.kTextPlain);
  final data = await readData();
  if (data?.text == value) {
    await write(const ClipboardData(text: ''));
  }
}

/// Diálogo "Chave de recuperação" da aba Privacidade.
///
/// Mostra e copia a chave AES das notas bloqueadas em base32 agrupado e deixa
/// importar uma chave de outro Mac. A chave fica só neste Mac (ver A3); a chave
/// de recuperação é o caminho para abrir as notas bloqueadas em outro Mac.
class RecoveryKeyDialog extends StatefulWidget {
  const RecoveryKeyDialog({
    required this.keyStore,
    this.onKeyChanged,
    this.loadKeyCheck,
    this.saveKeyCheck,
    super.key,
  });

  final NoteKeyStore keyStore;

  /// Chamado depois de importar/gerar uma chave (para invalidar caches, ex.: o
  /// `SyncCrypto`).
  final VoidCallback? onKeyChanged;

  /// Carrega o sentinela cifrado atual (M10), ou null se não houver. Quando há,
  /// uma chave importada precisa decifrá-lo para ser aceita.
  final Future<Map<String, dynamic>?> Function()? loadKeyCheck;

  /// Persiste um novo sentinela cifrado com a chave recém-importada.
  final Future<void> Function(Map<String, dynamic> envelope)? saveKeyCheck;

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
  Timer? _clearClipboardTimer;

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
    // Backfill do sentinela no Mac de origem: se já há chave mas nenhum
    // sentinela guardado, grava um agora para validar importações futuras.
    if (key != null && await widget.loadKeyCheck?.call() == null) {
      await _persistCheck(key);
    }
  }

  @override
  void dispose() {
    _clearClipboardTimer?.cancel();
    _import.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final key = _current;
    if (key == null) return;
    final value = key.recovery;
    await Clipboard.setData(ClipboardData(text: value));
    // Não deixa a chave parada na área de transferência (M13): limpa em 60 s,
    // mas só se ela ainda contiver a chave (o usuário pode ter copiado outra).
    _clearClipboardTimer?.cancel();
    _clearClipboardTimer = Timer(
      _clipboardClearAfter,
      () => unawaited(_clearClipboardIfKey(value)),
    );
    if (mounted) {
      setState(() {
        _message = 'Chave copiada. A área de transferência será limpa em 60 s.';
        _messageOk = true;
      });
    }
  }

  Future<void> _clearClipboardIfKey(String value) =>
      clearRecoveryClipboard(value);

  Future<void> _importKey() async {
    final raw = _import.text.trim();
    if (raw.isEmpty) return;

    final NoteKey key;
    try {
      key = NoteKey.fromRecovery(raw);
    } on Object {
      _setMessage('Chave de recuperação inválida.', ok: false);
      return;
    }

    // Validação de verdade (M10): a chave precisa abrir o sentinela existente.
    // Sem sentinela (primeiro Mac), não há como validar — aceitamos.
    final check = await widget.loadKeyCheck?.call();
    if (check != null && !await _opensCheck(key, check)) {
      _setMessage('Esta chave não abre suas notas bloqueadas.', ok: false);
      return;
    }

    // Confirma antes de sobrescrever uma chave já existente neste Mac.
    if (_current != null && !await _confirmOverwrite()) return;

    try {
      await widget.keyStore.import(key);
      await _persistCheck(key);
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
      _setMessage('Chave de recuperação inválida.', ok: false);
    }
  }

  Future<bool> _opensCheck(NoteKey key, Map<String, dynamic> envelope) async {
    try {
      final clear = await NoteCipher(key).decrypt(envelope);
      return jsonEncode(clear) == jsonEncode(_keyCheckClear);
    } on Object {
      return false;
    }
  }

  Future<void> _persistCheck(NoteKey key) async {
    final save = widget.saveKeyCheck;
    if (save == null) return;
    final envelope = await NoteCipher(key).encrypt(Map.of(_keyCheckClear));
    await save(envelope);
  }

  Future<bool> _confirmOverwrite() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Substituir a chave deste Mac?'),
        content: const Text(
          'Já existe uma chave neste Mac. Importar vai substituí-la pela chave '
          'colada. As notas bloqueadas com a chave antiga só abrem com ela.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: RbTokens.destructive),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Substituir'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _setMessage(String message, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageOk = ok;
    });
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
              'A chave das notas bloqueadas fica só neste Mac. Guarde esta '
              'chave de recuperação em local seguro: é com ela que você abre '
              'as notas bloqueadas em outro Mac.',
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
