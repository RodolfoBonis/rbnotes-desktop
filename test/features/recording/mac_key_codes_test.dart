import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/recording/data/mac_key_codes.dart';
import 'package:rbnotes/native/rb_native.dart';

void main() {
  group('keyLabel', () {
    test('known codes map to their label', () {
      expect(MacKeyCodes.keyLabel(49), 'Espaço');
      expect(MacKeyCodes.keyLabel(15), 'R');
      expect(MacKeyCodes.keyLabel(53), 'Esc');
    });

    test('unknown code degrades to a readable fallback', () {
      expect(MacKeyCodes.keyLabel(999), 'Tecla 999');
    });
  });

  group('fromLogicalKey', () {
    test('maps letters, digits, space and specials', () {
      expect(MacKeyCodes.fromLogicalKey(LogicalKeyboardKey.keyR), 15);
      expect(MacKeyCodes.fromLogicalKey(LogicalKeyboardKey.digit1), 18);
      expect(MacKeyCodes.fromLogicalKey(LogicalKeyboardKey.space), 49);
      expect(MacKeyCodes.fromLogicalKey(LogicalKeyboardKey.escape), 53);
    });

    test('returns null for an unmapped key', () {
      expect(
        MacKeyCodes.fromLogicalKey(LogicalKeyboardKey.contextMenu),
        isNull,
      );
    });
  });

  group('isModifier', () {
    test('recognizes bare modifiers', () {
      expect(MacKeyCodes.isModifier(LogicalKeyboardKey.shiftLeft), isTrue);
      expect(MacKeyCodes.isModifier(LogicalKeyboardKey.metaRight), isTrue);
      expect(MacKeyCodes.isModifier(LogicalKeyboardKey.keyR), isFalse);
    });
  });

  group('symbols', () {
    test('orders modifiers ⌃⌥⇧⌘ then the key', () {
      const hotkey = Hotkey(
        keyCode: 49,
        modifiers: {
          HotkeyModifier.command,
          HotkeyModifier.shift,
          HotkeyModifier.option,
          HotkeyModifier.control,
        },
      );
      expect(MacKeyCodes.symbols(hotkey), ['⌃', '⌥', '⇧', '⌘', 'Espaço']);
    });

    test('default record hotkey is ⌥⇧Espaço', () {
      expect(
        MacKeyCodes.symbols(
          const Hotkey(
            keyCode: 49,
            modifiers: {HotkeyModifier.option, HotkeyModifier.shift},
          ),
        ),
        ['⌥', '⇧', 'Espaço'],
      );
    });
  });
}
