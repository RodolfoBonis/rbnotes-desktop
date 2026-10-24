import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.1 contrast helpers used to validate and adjust the accent color so
/// buttons and accent text stay legible (AA) in both light and dark themes.
abstract final class ColorContrast {
  /// AA threshold for normal-size text.
  static const double aaText = 4.5;

  /// AA threshold for large text and UI component boundaries.
  static const double aaLarge = 3;

  /// Relative luminance per WCAG (channels are the 0..1 doubles of [Color]).
  static double relativeLuminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  /// Contrast ratio (1..21) between [a] and [b].
  static double ratio(Color a, Color b) {
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Black or white — whichever reads better on [background].
  static Color onColorFor(Color background) =>
      ratio(Colors.white, background) >= ratio(Colors.black, background)
      ? Colors.white
      : Colors.black;

  /// Nudges [foreground] toward black (on a light [background]) or white (on a
  /// dark one) until it reaches [min] contrast, so accent-colored text is
  /// always readable. Returns the original hue/saturation with adjusted
  /// lightness.
  static Color ensureReadable(
    Color foreground,
    Color background, {
    double min = aaText,
  }) {
    if (ratio(foreground, background) >= min) return foreground;
    final bgIsDark = relativeLuminance(background) < 0.5;
    final hsl = HSLColor.fromColor(foreground);
    // Walk lightness in small steps toward the readable side.
    for (var i = 1; i <= 100; i++) {
      final l = (bgIsDark ? hsl.lightness + i / 100 : hsl.lightness - i / 100)
          .clamp(0.0, 1.0);
      final candidate = hsl.withLightness(l).toColor();
      if (ratio(candidate, background) >= min) return candidate;
    }
    return bgIsDark ? Colors.white : Colors.black;
  }
}
