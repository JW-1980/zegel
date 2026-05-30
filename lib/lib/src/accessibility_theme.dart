import 'dart:math' as math;

import 'theme_brand.dart';

/// High-contrast accessibility theme helper (improvement #48).
///
/// Produces a WCAG 2.1 AA-compliant variant of any [ThemeBrand] by
/// snapping its foreground/background pairs to the nearest canonical
/// high-contrast tones. Keeps the library free of Flutter imports so
/// it can be unit-tested without a binding.
class AccessibilityTheme {
  AccessibilityTheme._();

  /// Pure black foreground on pure white background — the simplest
  /// guarantee of passing contrast ratios above 7:1.
  static const int blackOnWhiteBackground = 0xFFFFFFFF;
  static const int blackOnWhiteForeground = 0xFF000000;

  /// Inverted pair for dark-mode high contrast.
  static const int whiteOnBlackBackground = 0xFF000000;
  static const int whiteOnBlackForeground = 0xFFFFFFFF;

  /// Returns a [ThemeBrand] that keeps the semantic colours from
  /// [source] (primary / secondary as accent hints) but forces the
  /// surface / background / text colours into the chosen contrast
  /// pair. Use [dark] to select the black-on-white or white-on-black
  /// variant.
  static ThemeBrand derive(ThemeBrand source, {bool dark = false}) {
    final bg = dark ? whiteOnBlackBackground : blackOnWhiteBackground;
    final fg = dark ? whiteOnBlackForeground : blackOnWhiteForeground;
    return ThemeBrand(
      name: '${source.name} (High Contrast)',
      primaryColor: fg,
      secondaryColor: source.secondaryColor,
      accentColor: source.accentColor,
      backgroundColor: bg,
      surfaceColor: bg,
      errorColor: 0xFFD32F2F,
      fontFamily: source.fontFamily,
      logoAssetPath: source.logoAssetPath,
      iconPackId: source.iconPackId,
      extraColors: source.extraColors,
    );
  }

  /// Computes the relative luminance of an ARGB color as defined by
  /// WCAG 2.1. Alpha is ignored.
  static double relativeLuminance(int argb) {
    double channel(int c) {
      final v = c / 255.0;
      return v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = channel((argb >> 16) & 0xFF);
    final g = channel((argb >> 8) & 0xFF);
    final b = channel(argb & 0xFF);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Returns the contrast ratio between two colors, per WCAG 2.1.
  /// A ratio of 7.0 or higher passes AAA; 4.5+ passes AA.
  static double contrastRatio(int argb1, int argb2) {
    final l1 = relativeLuminance(argb1);
    final l2 = relativeLuminance(argb2);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// True when [fg] on [bg] passes the 4.5:1 AA threshold.
  static bool passesAA(int fg, int bg) => contrastRatio(fg, bg) >= 4.5;

  /// True when [fg] on [bg] passes the 7.0:1 AAA threshold.
  static bool passesAAA(int fg, int bg) => contrastRatio(fg, bg) >= 7.0;
}
