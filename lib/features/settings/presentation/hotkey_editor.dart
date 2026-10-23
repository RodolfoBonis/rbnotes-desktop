import 'package:flutter/material.dart';
import 'package:forma_ui/forma_ui.dart';
import 'package:rbnotes/native/rb_native.dart';

/// Teclas suportadas pelo atalho do ditado (keyCode virtual do macOS → rótulo).
const _keyNames = <int, String>{
  49: 'Space',
  122: 'F1',
  120: 'F2',
  99: 'F3',
  118: 'F4',
  96: 'F5',
  97: 'F6',
  98: 'F7',
  100: 'F8',
  101: 'F9',
  109: 'F10',
  103: 'F11',
  111: 'F12',
};

const _modifierSymbols = <HotkeyModifier, String>{
  HotkeyModifier.command: '⌘',
  HotkeyModifier.option: '⌥',
  HotkeyModifier.control: '⌃',
  HotkeyModifier.shift: '⇧',
  HotkeyModifier.function: 'fn',
};

const _modifierLabels = <HotkeyModifier, String>{
  HotkeyModifier.command: 'Command ⌘',
  HotkeyModifier.option: 'Option ⌥',
  HotkeyModifier.control: 'Control ⌃',
  HotkeyModifier.shift: 'Shift ⇧',
  HotkeyModifier.function: 'Function (fn)',
};

/// Representação legível do atalho, ex.: `⌥Space`.
String describeHotkey(Hotkey hotkey) {
  final mods = HotkeyModifier.values
      .where(hotkey.modifiers.contains)
      .map((m) => _modifierSymbols[m])
      .join();
  final key = _keyNames[hotkey.keyCode] ?? 'Tecla ${hotkey.keyCode}';
  return '$mods$key';
}

/// Editor simples do atalho: modificadores + tecla. Retorna `null` se cancelar.
Future<Hotkey?> showHotkeyEditor(BuildContext context, Hotkey current) {
  return showDialog<Hotkey>(
    context: context,
    builder: (context) => _HotkeyEditorDialog(current: current),
  );
}

class _HotkeyEditorDialog extends StatefulWidget {
  const _HotkeyEditorDialog({required this.current});

  final Hotkey current;

  @override
  State<_HotkeyEditorDialog> createState() => _HotkeyEditorDialogState();
}

class _HotkeyEditorDialogState extends State<_HotkeyEditorDialog> {
  late final Set<HotkeyModifier> _modifiers;
  late int _keyCode;

  @override
  void initState() {
    super.initState();
    _modifiers = {...widget.current.modifiers};
    _keyCode = _keyNames.containsKey(widget.current.keyCode)
        ? widget.current.keyCode
        : 49;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Atalho do ditado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Prévia: ${describeHotkey(_preview())}'),
          const SizedBox(height: FormaSpacing.base),
          for (final m in HotkeyModifier.values)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _modifiers.contains(m),
              title: Text(_modifierLabels[m]!),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _modifiers.add(m);
                } else {
                  _modifiers.remove(m);
                }
              }),
            ),
          const SizedBox(height: FormaSpacing.sm),
          Row(
            children: [
              const Text('Tecla'),
              const SizedBox(width: FormaSpacing.base),
              DropdownButton<int>(
                value: _keyCode,
                items: [
                  for (final entry in _keyNames.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (v) => setState(() => _keyCode = v ?? _keyCode),
              ),
            ],
          ),
        ],
      ),
      actions: [
        FormaButton.secondary(
          label: 'Cancelar',
          small: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        FormaButton.primary(
          label: 'Salvar',
          small: true,
          onPressed: _modifiers.isEmpty
              ? null
              : () => Navigator.of(context).pop(_preview()),
        ),
      ],
    );
  }

  Hotkey _preview() => Hotkey(keyCode: _keyCode, modifiers: _modifiers);
}
