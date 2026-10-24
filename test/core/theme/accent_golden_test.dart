import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/theme/accent_presets.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';

/// One sample tile per preset: the swatch, a filled accent button (onAccent
/// text) and accent text — so the goldens show every preset applied and prove
/// the derived AA-safe foregrounds in both themes.
Widget _gallery({required bool dark}) {
  Widget tile(AccentPreset preset) {
    final theme = dark
        ? RbNotesTheme.dark(preset.color)
        : RbNotesTheme.light(preset.color);
    final t = theme.extension<RbTokens>()!;
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Container(
          color: t.bg,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: t.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 90,
                child: Text(preset.label, style: context.bodyText(size: 14)),
              ),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Gravar',
                  style: context.bodyText(
                    size: 13,
                    weight: FontWeight.w600,
                    color: t.onAccent,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Texto de acento',
                style: context.bodyText(
                  size: 13,
                  weight: FontWeight.w600,
                  color: t.accentText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final p in AccentPresets.all) tile(p)],
      ),
    ),
  );
}

void main() {
  testWidgets('accent presets — claro', (tester) async {
    tester.view.physicalSize = const Size(520, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_gallery(dark: false));
    await tester.pump(const Duration(milliseconds: 50));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/accent_presets_light.png'),
    );
  });

  testWidgets('accent presets — escuro', (tester) async {
    tester.view.physicalSize = const Size(520, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_gallery(dark: true));
    await tester.pump(const Duration(milliseconds: 50));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/accent_presets_dark.png'),
    );
  });
}
