import 'package:flutter/material.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';

/// Builds the RbNotes [ThemeData] for light and dark, wiring the [RbTokens]
/// extension and the serif/body font families from the design.
abstract final class RbNotesTheme {
  /// Design accent (#E0512E). Settings can swap it via `AccentCubit`; the
  /// tokens carry the chosen accent through [light]/[dark].
  static const accent = Color(0xFFE0512E);

  static ThemeData light([Color accent = accent]) =>
      _build(RbTokens.light(accent));
  static ThemeData dark([Color accent = accent]) =>
      _build(RbTokens.dark(accent));

  static ThemeData _build(RbTokens t) {
    final brightness = t.brightnessIsDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: t.accent,
      brightness: brightness,
      primary: t.accent,
      surface: t.bg,
      onSurface: t.text,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.bg,
      fontFamily: RbFonts.body,
      fontFamilyFallback: RbFonts.bodyFallback,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      extensions: [t],
      textTheme: base.textTheme.apply(
        bodyColor: t.text,
        displayColor: t.text,
        fontFamily: RbFonts.body,
        fontFamilyFallback: RbFonts.bodyFallback,
      ),
      dividerTheme: DividerThemeData(
        color: t.hairline,
        thickness: 0.5,
        space: 0.5,
      ),
      iconTheme: IconThemeData(color: t.secondary(0.75), size: 16),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xEB1C1C1E),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontFamily: RbFonts.body,
          fontFamilyFallback: RbFonts.bodyFallback,
        ),
      ),
    );
  }
}
