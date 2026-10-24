import 'package:flutter/material.dart';

/// A named accent color the user can pick in Settings → Geral.
///
/// The color is applied to both light and dark themes; the readable
/// on-accent/accent-text variants are derived at theme-build time
/// (see `RbTokens`), so every preset keeps AA contrast in both themes.
@immutable
class AccentPreset {
  const AccentPreset({
    required this.id,
    required this.label,
    required this.color,
  });

  final String id;
  final String label;
  final Color color;
}

/// The seven built-in accents. "Laranja" is the original design accent
/// (#E0512E); the rest are harmonic tones chosen to sit well on the warm paper
/// palette and to pass AA contrast for buttons and accent text (validated in
/// `test/core/theme/accent_contrast_test.dart`).
abstract final class AccentPresets {
  static const laranja = AccentPreset(
    id: 'laranja',
    label: 'Laranja',
    color: Color(0xFFE0512E),
  );
  static const azul = AccentPreset(
    id: 'azul',
    label: 'Azul',
    color: Color(0xFF2F6BEB),
  );
  static const verde = AccentPreset(
    id: 'verde',
    label: 'Verde',
    color: Color(0xFF1E8C5A),
  );
  static const roxo = AccentPreset(
    id: 'roxo',
    label: 'Roxo',
    color: Color(0xFF7A5AF0),
  );
  static const rosa = AccentPreset(
    id: 'rosa',
    label: 'Rosa',
    color: Color(0xFFD64B8A),
  );
  static const ambar = AccentPreset(
    id: 'ambar',
    label: 'Âmbar',
    color: Color(0xFFCB8A16),
  );
  static const grafite = AccentPreset(
    id: 'grafite',
    label: 'Grafite',
    color: Color(0xFF5B5B61),
  );

  static const all = <AccentPreset>[
    laranja,
    azul,
    verde,
    roxo,
    rosa,
    ambar,
    grafite,
  ];

  /// The default accent (the original design orange).
  static const AccentPreset fallback = laranja;

  /// The preset whose color matches [color], or null for a custom color.
  static AccentPreset? forColor(Color color) {
    for (final p in all) {
      if (p.color.toARGB32() == color.toARGB32()) return p;
    }
    return null;
  }

  static AccentPreset? byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
