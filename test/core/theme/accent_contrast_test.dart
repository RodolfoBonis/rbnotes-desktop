import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/theme/accent_presets.dart';
import 'package:rbnotes/core/theme/color_contrast.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';

void main() {
  group('ColorContrast', () {
    test('ratio is symmetric and bounded 1..21', () {
      expect(
        ColorContrast.ratio(Colors.black, Colors.white),
        closeTo(21, 0.1),
      );
      expect(ColorContrast.ratio(Colors.white, Colors.white), closeTo(1, 0.01));
      expect(
        ColorContrast.ratio(Colors.black, Colors.white),
        closeTo(ColorContrast.ratio(Colors.white, Colors.black), 0.001),
      );
    });

    test('onColorFor picks the readable foreground', () {
      expect(ColorContrast.onColorFor(Colors.white), Colors.black);
      expect(ColorContrast.onColorFor(Colors.black), Colors.white);
    });

    test('ensureReadable reaches the requested contrast', () {
      const bg = Color(0xFFFFFFFF);
      // A light amber fails as text on white; it must be darkened to pass AA.
      const amber = Color(0xFFF5C518);
      final fixed = ColorContrast.ensureReadable(amber, bg);
      expect(
        ColorContrast.ratio(fixed, bg),
        greaterThanOrEqualTo(ColorContrast.aaText - 0.01),
      );
    });
  });

  group('accent presets', () {
    for (final preset in AccentPresets.all) {
      test('${preset.label}: onAccent passes AA-large on the fill', () {
        final on = ColorContrast.onColorFor(preset.color);
        expect(
          ColorContrast.ratio(on, preset.color),
          greaterThanOrEqualTo(ColorContrast.aaLarge),
          reason: '${preset.label} button text must stay legible',
        );
      });

      test('${preset.label}: accentText passes AA in light and dark', () {
        final light = RbTokens.light(preset.color);
        final dark = RbTokens.dark(preset.color);
        expect(
          ColorContrast.ratio(light.accentText, light.bg),
          greaterThanOrEqualTo(ColorContrast.aaText - 0.01),
          reason: '${preset.label} accent text on light bg',
        );
        expect(
          ColorContrast.ratio(dark.accentText, dark.bg),
          greaterThanOrEqualTo(ColorContrast.aaText - 0.01),
          reason: '${preset.label} accent text on dark bg',
        );
      });
    }

    test('forColor round-trips preset colors and rejects custom', () {
      expect(AccentPresets.forColor(AccentPresets.azul.color)?.id, 'azul');
      expect(AccentPresets.forColor(const Color(0xFF123456)), isNull);
    });
  });
}
