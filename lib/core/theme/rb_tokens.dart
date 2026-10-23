import 'package:flutter/material.dart';

/// Semantic design tokens for RbNotes, ported 1:1 from the Claude Design v3
/// prototype (`docs/design/RbNotes v3.dc.html`, `applyAccent()`).
///
/// Exposed as a [ThemeExtension] so every widget reads colors in a type-safe
/// way (`context.rb.accent`) and light/dark swap automatically with the
/// `MaterialApp` theme. The CSS custom properties map here as:
/// `--acc` → [accent], `--tx` → [text], `--bg` → [bg], `--fill` → [fill`], etc.
@immutable
class RbTokens extends ThemeExtension<RbTokens> {
  const RbTokens({
    required this.brightnessIsDark,
    required this.accent,
    required this.text,
    required this.textSecondary,
    required this.textFaint,
    required this.hairline,
    required this.ink,
    required this.bg,
    required this.bg2,
    required this.bg3,
    required this.card,
    required this.fill,
    required this.fill2,
    required this.side,
    required this.sideCard,
    required this.pop,
    required this.seg,
    required this.warm,
    required this.wallpaper,
    required this.controlFill,
  });

  /// Light theme — CSS defaults.
  factory RbTokens.light(Color accent) => RbTokens(
    brightnessIsDark: false,
    accent: accent,
    text: const Color(0xFF1D1D1F),
    textSecondary: const Color(0x993C3C43), // rgba(60,60,67,.6)
    textFaint: const Color(0x663C3C43), // rgba(60,60,67,.4)
    hairline: const Color(0x1F000000), // rgba(0,0,0,.12)
    ink: const Color(0xFF1D1D1F),
    bg: const Color(0xFFFFFFFF),
    bg2: const Color(0xFFFBFAF8),
    bg3: const Color(0xFFF5F3F0),
    card: const Color(0xFFFFFFFF),
    fill: const Color(0xFFF6F4F1),
    fill2: const Color(0xFFF1EEEA),
    side: const Color(0xD1EEEBE6), // rgba(238,235,230,.82)
    sideCard: const Color(0x8CFFFFFF), // rgba(255,255,255,.55)
    pop: const Color(0xF5FCFBF9), // rgba(252,251,249,.96)
    seg: const Color(0xFFFFFFFF),
    warm: const Color(0xFFF1ECE4),
    wallpaper: const Color(0xFFCFC9BF),
    controlFill: const Color(0x1A767680), // rgba(118,118,128,.1)
  );

  /// Dark theme — the `D` token map in `applyAccent()`.
  factory RbTokens.dark(Color accent) => RbTokens(
    brightnessIsDark: true,
    accent: accent,
    text: const Color(0xFFF2F2F4),
    textSecondary: const Color(0x99EBEBF5), // rgba(235,235,245,.6)
    textFaint: const Color(0x66EBEBF5),
    hairline: const Color(0x1FFFFFFF), // rgba(255,255,255,.12)
    ink: const Color(0xFF55555A),
    bg: const Color(0xFF1E1E20),
    bg2: const Color(0xFF242426),
    bg3: const Color(0xFF232325),
    card: const Color(0xFF2E2E31),
    fill: const Color(0xFF2A2A2D),
    fill2: const Color(0xFF333336),
    side: const Color(0xCC2A2A2D), // rgba(42,42,45,.8)
    sideCard: const Color(0x0FFFFFFF), // rgba(255,255,255,.06)
    pop: const Color(0xF528282B), // rgba(40,40,43,.96)
    seg: const Color(0xFF636366),
    warm: const Color(0xFF2A2724),
    wallpaper: const Color(0xFF24221F),
    controlFill: const Color(0x1AFFFFFF),
  );

  final bool brightnessIsDark;

  /// `--acc` — brand accent (#E0512E by default).
  final Color accent;

  /// `--tx` — primary text.
  final Color text;

  /// `rgba(--s,.6)` — secondary/muted text.
  final Color textSecondary;

  /// `rgba(--s,.4)` — faint text (placeholders, disabled).
  final Color textFaint;

  /// `rgba(--k,.12)` — hairline borders/dividers.
  final Color hairline;

  /// `--ink` — dark pill/avatar/play-button background.
  final Color ink;

  /// `--bg` — detail pane background.
  final Color bg;

  /// `--bg2` — list pane / login / onboarding background.
  final Color bg2;

  /// `--bg3` — settings window background.
  final Color bg3;

  /// `--card` — elevated card surface.
  final Color card;

  /// `--fill` — inset fills (player, chips, cards).
  final Color fill;

  /// `--fill2` — slightly deeper fill (hover).
  final Color fill2;

  /// `--side` — translucent sidebar background (vibrancy).
  final Color side;

  /// `--sidecard` — status card inside the sidebar.
  final Color sideCard;

  /// `--pop` — popover/overlay surface.
  final Color pop;

  /// `--seg` — selected segment of a segmented control.
  final Color seg;

  /// `--warm` — warm paper panel (login left, diary prompt).
  final Color warm;

  /// `--wall` — desktop wallpaper tint behind the window.
  final Color wallpaper;

  /// `rgba(118,118,128,.1)` — neutral control fill (search, chips).
  final Color controlFill;

  /// `rgba(--s, opacity)` — muted text at an arbitrary opacity.
  Color secondary(double opacity) =>
      (brightnessIsDark ? const Color(0xFFEBEBF5) : const Color(0xFF3C3C43))
          .withValues(alpha: opacity);

  /// `rgba(--k, opacity)` — black/white overlay at an arbitrary opacity.
  Color onSurface(double opacity) =>
      (brightnessIsDark ? Colors.white : Colors.black).withValues(
        alpha: opacity,
      );

  /// `color-mix(in srgb, accent X%, transparent)`.
  Color accentWash(double fraction) => accent.withValues(alpha: fraction);

  // ---- Fixed brand colors (identical in both themes) ----

  /// macOS traffic-light colors.
  static const trafficRed = Color(0xFFFF5F57);
  static const trafficYellow = Color(0xFFFEBC2E);
  static const trafficGreen = Color(0xFF28C840);

  /// Live recording dot (#FF453A) and paused dot (#FEBC2E).
  static const recDot = Color(0xFFFF453A);
  static const pausedDot = Color(0xFFFEBC2E);

  /// Status "online" dot in the sidebar card.
  static const statusGreen = Color(0xFF28A745);

  /// "Permitido" / success check.
  static const permitGreen = Color(0xFF1E8C5A);

  /// Destructive action text.
  static const destructive = Color(0xFFD70015);

  /// Folder swatch colors (seeded in drift v3), by folder id.
  static const folderColors = <String, Color>{
    'trabalho': Color(0xFF2F6BEB),
    'pessoal': Color(0xFF1E8C5A),
    'estudos': Color(0xFFB7791F),
    'ideias': Color(0xFFD9472B),
    'diario': Color(0xFF8A7A66),
  };

  /// Speaker avatar colors by channel index (0 = me/ink, then others).
  List<Color> get speakerColors => [
    ink,
    const Color(0xFF2F6BEB),
    const Color(0xFF1E8C5A),
    const Color(0xFFB7791F),
  ];

  static Color folderColor(String? id) =>
      folderColors[id] ?? const Color(0xFF8A7A66);

  @override
  RbTokens copyWith({
    bool? brightnessIsDark,
    Color? accent,
    Color? text,
    Color? textSecondary,
    Color? textFaint,
    Color? hairline,
    Color? ink,
    Color? bg,
    Color? bg2,
    Color? bg3,
    Color? card,
    Color? fill,
    Color? fill2,
    Color? side,
    Color? sideCard,
    Color? pop,
    Color? seg,
    Color? warm,
    Color? wallpaper,
    Color? controlFill,
  }) => RbTokens(
    brightnessIsDark: brightnessIsDark ?? this.brightnessIsDark,
    accent: accent ?? this.accent,
    text: text ?? this.text,
    textSecondary: textSecondary ?? this.textSecondary,
    textFaint: textFaint ?? this.textFaint,
    hairline: hairline ?? this.hairline,
    ink: ink ?? this.ink,
    bg: bg ?? this.bg,
    bg2: bg2 ?? this.bg2,
    bg3: bg3 ?? this.bg3,
    card: card ?? this.card,
    fill: fill ?? this.fill,
    fill2: fill2 ?? this.fill2,
    side: side ?? this.side,
    sideCard: sideCard ?? this.sideCard,
    pop: pop ?? this.pop,
    seg: seg ?? this.seg,
    warm: warm ?? this.warm,
    wallpaper: wallpaper ?? this.wallpaper,
    controlFill: controlFill ?? this.controlFill,
  );

  @override
  RbTokens lerp(ThemeExtension<RbTokens>? other, double t) {
    if (other is! RbTokens) return this;
    return RbTokens(
      brightnessIsDark: t < 0.5 ? brightnessIsDark : other.brightnessIsDark,
      accent: Color.lerp(accent, other.accent, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      bg3: Color.lerp(bg3, other.bg3, t)!,
      card: Color.lerp(card, other.card, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
      fill2: Color.lerp(fill2, other.fill2, t)!,
      side: Color.lerp(side, other.side, t)!,
      sideCard: Color.lerp(sideCard, other.sideCard, t)!,
      pop: Color.lerp(pop, other.pop, t)!,
      seg: Color.lerp(seg, other.seg, t)!,
      warm: Color.lerp(warm, other.warm, t)!,
      wallpaper: Color.lerp(wallpaper, other.wallpaper, t)!,
      controlFill: Color.lerp(controlFill, other.controlFill, t)!,
    );
  }
}

/// Serif (Newsreader / New York) and body (SF Pro) font families.
abstract final class RbFonts {
  /// Display/title serif — bundled Newsreader, falling back to the macOS
  /// system serif "New York".
  static const serif = 'Newsreader';
  static const serifFallback = <String>['New York', 'Georgia'];

  /// Body — the macOS system UI font (SF Pro), falling back to bundled Inter
  /// so text still renders in headless tests.
  static const body = '.AppleSystemUIFont';
  static const bodyFallback = <String>['Inter'];
}

/// Ergonomic access to [RbTokens] from a [BuildContext].
extension RbTokensContext on BuildContext {
  RbTokens get rb => Theme.of(this).extension<RbTokens>()!;

  /// A serif [TextStyle] (titles, pull quotes).
  TextStyle serif({
    required double size,
    FontWeight weight = FontWeight.w600,
    double? height,
    double letterSpacing = 0,
    Color? color,
    FontStyle? style,
  }) => TextStyle(
    fontFamily: RbFonts.serif,
    fontFamilyFallback: RbFonts.serifFallback,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    fontStyle: style,
    color: color ?? rb.text,
  );

  /// A body [TextStyle] (SF Pro).
  TextStyle bodyText({
    required double size,
    FontWeight weight = FontWeight.w400,
    double? height,
    double letterSpacing = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: RbFonts.body,
    fontFamilyFallback: RbFonts.bodyFallback,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? rb.text,
  );
}
