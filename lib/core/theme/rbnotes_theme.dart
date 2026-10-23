import 'package:flutter/material.dart';
import 'package:forma_ui/forma_ui.dart';
import 'package:rbnotes/core/theme/rbnotes_colors.dart';

/// Temas do RbNotes sobre o Forma Design System (desktop-first).
///
/// `MaterialApp(theme: RbNotesTheme.light, darkTheme: RbNotesTheme.dark)`.
abstract final class RbNotesTheme {
  static const FormaThemeExtension lightColors = FormaThemeExtension(
    appBackground: RbNotesColors.neutral50,
    cardBackground: RbNotesColors.neutral0,
    primaryColor: RbNotesColors.primary500,
    primarySurface: RbNotesColors.primary50,
    primaryBorder: RbNotesColors.primary200,
    secondaryColor: RbNotesColors.accent500,
    secondarySurface: RbNotesColors.accent50,
    accentColor: RbNotesColors.accent500,
    accentSurface: RbNotesColors.accent50,
    textPrimary: RbNotesColors.neutral900,
    textMuted: RbNotesColors.neutral500,
    textHint: RbNotesColors.neutral400,
    border: RbNotesColors.neutral150,
    borderStrong: RbNotesColors.neutral200,
    successColor: RbNotesColors.success,
    successSurface: RbNotesColors.successLight,
    successText: RbNotesColors.successDark,
    warningColor: RbNotesColors.warning,
    warningSurface: RbNotesColors.warningLight,
    warningText: RbNotesColors.warningDark,
    urgencySurface: RbNotesColors.errorLight,
    errorColor: RbNotesColors.error,
    errorSurface: RbNotesColors.errorLight,
    errorText: RbNotesColors.errorDark,
    infoSurface: RbNotesColors.infoLight,
    infoText: RbNotesColors.infoDark,
    primaryHover: RbNotesColors.primary600,
    primaryPress: RbNotesColors.primary700,
    primarySubtle: RbNotesColors.primary100,
    onPrimary: RbNotesColors.neutral0,
    surfaceElevated: RbNotesColors.neutral0,
  );

  static const FormaThemeExtension darkColors = FormaThemeExtension(
    appBackground: RbNotesColors.neutral1000,
    cardBackground: RbNotesColors.neutral950,
    primaryColor: RbNotesColors.primary400,
    primarySurface: Color(0xFF1C1F3A),
    primaryBorder: Color(0xFF2E3466),
    secondaryColor: RbNotesColors.accent500,
    secondarySurface: Color(0xFF2E2413),
    accentColor: RbNotesColors.accent500,
    accentSurface: Color(0xFF2E2413),
    textPrimary: Color(0xFFF2F3F5),
    textMuted: Color(0xFFA2A8B4),
    textHint: Color(0xFF6E7585),
    border: RbNotesColors.neutral800,
    borderStrong: Color(0xFF3A3F49),
    successColor: RbNotesColors.success,
    successSurface: Color(0xFF0F2A1E),
    successText: Color(0xFF6FD6A4),
    warningColor: RbNotesColors.warning,
    warningSurface: Color(0xFF2E2413),
    warningText: Color(0xFFF6C98F),
    urgencySurface: Color(0xFF2E1517),
    errorColor: Color(0xFFEF5350),
    errorSurface: Color(0xFF2E1517),
    errorText: Color(0xFFF4A3A1),
    infoSurface: Color(0xFF10233A),
    infoText: Color(0xFF8CC8F2),
    primaryHover: RbNotesColors.primary300,
    primaryPress: RbNotesColors.primary500,
    primarySubtle: Color(0xFF26295A),
    onPrimary: RbNotesColors.neutral0,
    surfaceElevated: RbNotesColors.neutral850,
  );

  static ThemeData get light => _build(lightColors, Brightness.light);

  static ThemeData get dark => _build(darkColors, Brightness.dark);

  static ThemeData _build(FormaThemeExtension c, Brightness brightness) {
    const shape = FormaShapeExtension.desktop;
    final base = FormaTheme.build(
      extension: c,
      fontFamily: 'Inter',
      seedColor: RbNotesColors.primary500,
      brightness: brightness,
      shape: shape,
    );
    final scheme = base.colorScheme.copyWith(
      primary: c.primaryColor,
      onPrimary: c.onPrimary,
      secondary: c.accentColor,
      error: c.errorColor,
      surface: c.cardBackground,
      onSurface: c.textPrimary,
      outline: c.borderStrong,
      outlineVariant: c.border,
      surfaceContainerLowest: c.cardBackground,
      surfaceContainerLow: c.cardBackground,
      surfaceContainer: c.resolvedSurfaceElevated,
      surfaceContainerHigh: c.resolvedSurfaceElevated,
      surfaceContainerHighest: c.appBackground,
    );
    final radius = BorderRadius.circular(shape.dialogRadius);

    return base.copyWith(
      colorScheme: scheme,
      canvasColor: c.appBackground,
      dividerColor: c.border,
      splashFactory: NoSplash.splashFactory,
      hoverColor: c.textPrimary.withValues(alpha: 0.04),
      focusColor: c.primaryColor.withValues(alpha: 0.12),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.primaryColor,
        selectionColor: c.primaryColor.withValues(alpha: 0.25),
        selectionHandleColor: c.primaryColor,
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(8),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll<Color>(
          c.textMuted.withValues(alpha: 0.35),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.cardBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius),
        elevation: 12,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.resolvedSurfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primaryColor,
        linearTrackColor: c.primarySurface,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.resolvedSurfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    );
  }
}
