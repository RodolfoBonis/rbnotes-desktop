import 'package:flutter/services.dart';
import 'package:rbnotes/native/rb_native.dart';

/// Pure mapping between macOS virtual key codes (what the native Carbon hotkey
/// API needs), Flutter [LogicalKeyboardKey]s (what a capture widget observes)
/// and human-readable labels (what the settings UI shows).
///
/// Only the keys that make sense in a global shortcut are mapped; an unknown
/// code degrades to a readable fallback and an unmapped captured key returns
/// null so the UI can reject it.
abstract final class MacKeyCodes {
  /// macOS `kVK_*` virtual key code → display label.
  static const Map<int, String> _labels = {
    0: 'A',
    1: 'S',
    2: 'D',
    3: 'F',
    4: 'H',
    5: 'G',
    6: 'Z',
    7: 'X',
    8: 'C',
    9: 'V',
    11: 'B',
    12: 'Q',
    13: 'W',
    14: 'E',
    15: 'R',
    16: 'Y',
    17: 'T',
    18: '1',
    19: '2',
    20: '3',
    21: '4',
    22: '6',
    23: '5',
    24: '=',
    25: '9',
    26: '7',
    27: '-',
    28: '8',
    29: '0',
    30: ']',
    31: 'O',
    32: 'U',
    33: '[',
    34: 'I',
    35: 'P',
    37: 'L',
    38: 'J',
    39: "'",
    40: 'K',
    41: ';',
    42: r'\',
    43: ',',
    44: '/',
    45: 'N',
    46: 'M',
    47: '.',
    50: '`',
    36: 'Return',
    48: 'Tab',
    49: 'Espaço',
    51: 'Delete',
    53: 'Esc',
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
    123: '←',
    124: '→',
    125: '↓',
    126: '↑',
  };

  /// Flutter keys that don't carry a single-character label, mapped directly to
  /// their macOS virtual key code. `LogicalKeyboardKey` overrides `==`, so this
  /// can't be a `const` map.
  static final Map<LogicalKeyboardKey, int> _special = {
    LogicalKeyboardKey.space: 49,
    LogicalKeyboardKey.enter: 36,
    LogicalKeyboardKey.tab: 48,
    LogicalKeyboardKey.backspace: 51,
    LogicalKeyboardKey.escape: 53,
    LogicalKeyboardKey.arrowLeft: 123,
    LogicalKeyboardKey.arrowRight: 124,
    LogicalKeyboardKey.arrowDown: 125,
    LogicalKeyboardKey.arrowUp: 126,
    LogicalKeyboardKey.f1: 122,
    LogicalKeyboardKey.f2: 120,
    LogicalKeyboardKey.f3: 99,
    LogicalKeyboardKey.f4: 118,
    LogicalKeyboardKey.f5: 96,
    LogicalKeyboardKey.f6: 97,
    LogicalKeyboardKey.f7: 98,
    LogicalKeyboardKey.f8: 100,
    LogicalKeyboardKey.f9: 101,
    LogicalKeyboardKey.f10: 109,
    LogicalKeyboardKey.f11: 103,
    LogicalKeyboardKey.f12: 111,
  };

  static final Set<LogicalKeyboardKey> _modifiers = {
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.fn,
  };

  /// A readable label for [keyCode] (fallback includes the raw code).
  static String keyLabel(int keyCode) => _labels[keyCode] ?? 'Tecla $keyCode';

  /// The macOS virtual key code for a captured Flutter [key], or null when the
  /// key cannot be part of a hotkey (e.g. a bare modifier or an unmapped key).
  static int? fromLogicalKey(LogicalKeyboardKey key) {
    final direct = _special[key];
    if (direct != null) return direct;

    // Letters and digits: match by the (upper-cased) label.
    final label = key.keyLabel.toUpperCase();
    if (label.length == 1) {
      for (final entry in _labels.entries) {
        if (entry.value == label) return entry.key;
      }
    }
    return null;
  }

  /// Whether [key] is a bare modifier (shouldn't be captured as the main key).
  static bool isModifier(LogicalKeyboardKey key) => _modifiers.contains(key);

  /// The symbols for a [hotkey], in the standard macOS order (⌃⌥⇧⌘ + key),
  /// for the shortcut chips in the settings UI.
  static List<String> symbols(Hotkey hotkey) => [
    if (hotkey.modifiers.contains(HotkeyModifier.control)) '⌃',
    if (hotkey.modifiers.contains(HotkeyModifier.option)) '⌥',
    if (hotkey.modifiers.contains(HotkeyModifier.shift)) '⇧',
    if (hotkey.modifiers.contains(HotkeyModifier.command)) '⌘',
    if (hotkey.modifiers.contains(HotkeyModifier.function)) 'fn',
    keyLabel(hotkey.keyCode),
  ];
}
