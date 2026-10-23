import 'package:flutter/painting.dart';

/// Paleta da marca RbNotes: índigo como primária, âmbar como acento (destaque
/// de gravação/busca) e uma escala neutra fria. O mapeamento semântico fica
/// em `RbNotesTheme`.
abstract final class RbNotesColors {
  // Primary — índigo.
  static const Color primary50 = Color(0xFFEEF0FF);
  static const Color primary100 = Color(0xFFDDE1FF);
  static const Color primary200 = Color(0xFFC0C6FF);
  static const Color primary300 = Color(0xFF9AA3FF);
  static const Color primary400 = Color(0xFF7A82FA);
  static const Color primary500 = Color(0xFF5B63E8);
  static const Color primary600 = Color(0xFF4A51CF);
  static const Color primary700 = Color(0xFF3B41AB);
  static const Color primary800 = Color(0xFF2F3488);
  static const Color primary900 = Color(0xFF262A6B);

  // Accent — âmbar.
  static const Color accent50 = Color(0xFFFFF6E6);
  static const Color accent500 = Color(0xFFF5A623);
  static const Color accent600 = Color(0xFFDB9015);

  // Neutral — frio.
  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFF6F7F9);
  static const Color neutral100 = Color(0xFFECEEF2);
  static const Color neutral150 = Color(0xFFE4E7ED);
  static const Color neutral200 = Color(0xFFD6DAE2);
  static const Color neutral300 = Color(0xFFBEC4CF);
  static const Color neutral400 = Color(0xFF959CAB);
  static const Color neutral500 = Color(0xFF6E7585);
  static const Color neutral600 = Color(0xFF4E5461);
  static const Color neutral700 = Color(0xFF3A3F49);
  static const Color neutral800 = Color(0xFF282C34);
  static const Color neutral850 = Color(0xFF21242B);
  static const Color neutral900 = Color(0xFF1A1C22);
  static const Color neutral950 = Color(0xFF141519);
  static const Color neutral1000 = Color(0xFF0E0F12);

  // Semânticas.
  static const Color success = Color(0xFF2BB673);
  static const Color successLight = Color(0xFFE6F6EE);
  static const Color successDark = Color(0xFF167C4A);
  static const Color warning = Color(0xFFE8A13B);
  static const Color warningLight = Color(0xFFFBF1E0);
  static const Color warningDark = Color(0xFF8A5A12);
  static const Color error = Color(0xFFE5484D);
  static const Color errorLight = Color(0xFFFBE7E8);
  static const Color errorDark = Color(0xFF8A1F22);
  static const Color infoLight = Color(0xFFE7EEFB);
  static const Color infoDark = Color(0xFF1E3A8A);
}
