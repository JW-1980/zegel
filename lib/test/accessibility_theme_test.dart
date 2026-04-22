import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('AccessibilityTheme', () {
    // Canonical ARGB color constants used across tests.
    const white = 0xFFFFFFFF;
    const black = 0xFF000000;

    // Mid-gray (#767676) is right at the AA boundary on white
    // (contrast ratio ≈ 4.48:1) and fails AAA.
    const midGray = 0xFF767676;

    // A very light gray that fails both AA and AAA on white.
    const lightGray = 0xFFDDDDDD;

    // -------------------------------------------------------------------------
    // relativeLuminance
    // -------------------------------------------------------------------------
    group('relativeLuminance', () {
      test('pure white has luminance 1.0', () {
        expect(AccessibilityTheme.relativeLuminance(white), closeTo(1.0, 1e-6));
      });

      test('pure black has luminance 0.0', () {
        expect(AccessibilityTheme.relativeLuminance(black), closeTo(0.0, 1e-6));
      });

      test('luminance is in [0.0, 1.0]', () {
        for (final color in [
          white,
          black,
          midGray,
          lightGray,
          0xFFFF0000, // red
          0xFF0000FF, // blue
        ]) {
          final l = AccessibilityTheme.relativeLuminance(color);
          expect(l, greaterThanOrEqualTo(0.0));
          expect(l, lessThanOrEqualTo(1.0));
        }
      });

      test('alpha channel is ignored', () {
        // Same RGB but different alpha should produce the same luminance.
        final l1 = AccessibilityTheme.relativeLuminance(0xFF00AA55);
        final l2 = AccessibilityTheme.relativeLuminance(0x0000AA55);
        expect(l1, closeTo(l2, 1e-6));
      });

      test('red has higher luminance than blue', () {
        final lr = AccessibilityTheme.relativeLuminance(0xFFFF0000);
        final lb = AccessibilityTheme.relativeLuminance(0xFF0000FF);
        expect(lr, greaterThan(lb));
      });
    });

    // -------------------------------------------------------------------------
    // contrastRatio
    // -------------------------------------------------------------------------
    group('contrastRatio', () {
      test('black on white is ~21:1', () {
        final ratio = AccessibilityTheme.contrastRatio(black, white);
        expect(ratio, closeTo(21.0, 0.05));
      });

      test('white on black is the same ratio (symmetric)', () {
        final bw = AccessibilityTheme.contrastRatio(black, white);
        final wb = AccessibilityTheme.contrastRatio(white, black);
        expect(bw, closeTo(wb, 1e-6));
      });

      test('identical colors have ratio 1.0', () {
        expect(AccessibilityTheme.contrastRatio(white, white), closeTo(1.0, 1e-6));
        expect(AccessibilityTheme.contrastRatio(black, black), closeTo(1.0, 1e-6));
      });

      test('ratio is always >= 1.0', () {
        for (final pair in [
          [white, black],
          [midGray, white],
          [lightGray, black],
        ]) {
          expect(
            AccessibilityTheme.contrastRatio(pair[0], pair[1]),
            greaterThanOrEqualTo(1.0),
          );
        }
      });
    });

    // -------------------------------------------------------------------------
    // passesAA
    // -------------------------------------------------------------------------
    group('passesAA', () {
      test('black on white passes AA', () {
        expect(AccessibilityTheme.passesAA(black, white), isTrue);
      });

      test('white on black passes AA', () {
        expect(AccessibilityTheme.passesAA(white, black), isTrue);
      });

      test('light gray on white fails AA', () {
        expect(AccessibilityTheme.passesAA(lightGray, white), isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // passesAAA
    // -------------------------------------------------------------------------
    group('passesAAA', () {
      test('pure black on pure white passes AAA', () {
        expect(AccessibilityTheme.passesAAA(black, white), isTrue);
      });

      test('pure white on pure black passes AAA', () {
        expect(AccessibilityTheme.passesAAA(white, black), isTrue);
      });

      test('mid-gray on white does not pass AAA (contrast < 7:1)', () {
        // #767676 on white ≈ 4.48:1 — well below the 7:1 AAA threshold.
        expect(AccessibilityTheme.passesAAA(midGray, white), isFalse);
      });

      test('light gray on white fails AAA', () {
        expect(AccessibilityTheme.passesAAA(lightGray, white), isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // derive
    // -------------------------------------------------------------------------
    group('derive', () {
      final source = ThemeBrand.zegelDefault;

      test('derived light theme has white background', () {
        final theme = AccessibilityTheme.derive(source, dark: false);
        expect(theme.backgroundColor, AccessibilityTheme.blackOnWhiteBackground);
      });

      test('derived light theme has black foreground (primaryColor)', () {
        final theme = AccessibilityTheme.derive(source, dark: false);
        expect(theme.primaryColor, AccessibilityTheme.blackOnWhiteForeground);
      });

      test('derived dark theme has black background', () {
        final theme = AccessibilityTheme.derive(source, dark: true);
        expect(theme.backgroundColor, AccessibilityTheme.whiteOnBlackBackground);
      });

      test('derived dark theme has white foreground (primaryColor)', () {
        final theme = AccessibilityTheme.derive(source, dark: true);
        expect(theme.primaryColor, AccessibilityTheme.whiteOnBlackForeground);
      });

      test('derived theme appends "(High Contrast)" to the name', () {
        final theme = AccessibilityTheme.derive(source);
        expect(theme.name, contains('High Contrast'));
        expect(theme.name, contains(source.name));
      });

      test('derived theme preserves secondary color from source', () {
        final theme = AccessibilityTheme.derive(source);
        expect(theme.secondaryColor, source.secondaryColor);
      });

      test('derived theme preserves font family from source', () {
        final custom = ThemeBrand(
          name: 'Custom',
          primaryColor: 0xFF111111,
          secondaryColor: 0xFF222222,
          backgroundColor: white,
          surfaceColor: white,
          errorColor: 0xFFFF0000,
          fontFamily: 'Roboto',
        );
        final theme = AccessibilityTheme.derive(custom);
        expect(theme.fontFamily, 'Roboto');
      });

      test('surface color matches background color in derived theme', () {
        final light = AccessibilityTheme.derive(source, dark: false);
        expect(light.surfaceColor, light.backgroundColor);

        final dark = AccessibilityTheme.derive(source, dark: true);
        expect(dark.surfaceColor, dark.backgroundColor);
      });

      test('derived light theme foreground/background passes AAA', () {
        final theme = AccessibilityTheme.derive(source, dark: false);
        expect(
          AccessibilityTheme.passesAAA(theme.primaryColor, theme.backgroundColor),
          isTrue,
        );
      });

      test('derived dark theme foreground/background passes AAA', () {
        final theme = AccessibilityTheme.derive(source, dark: true);
        expect(
          AccessibilityTheme.passesAAA(theme.primaryColor, theme.backgroundColor),
          isTrue,
        );
      });
    });

    // -------------------------------------------------------------------------
    // Named constants
    // -------------------------------------------------------------------------
    group('named constants', () {
      test('blackOnWhiteBackground is 0xFFFFFFFF', () {
        expect(AccessibilityTheme.blackOnWhiteBackground, 0xFFFFFFFF);
      });

      test('blackOnWhiteForeground is 0xFF000000', () {
        expect(AccessibilityTheme.blackOnWhiteForeground, 0xFF000000);
      });

      test('whiteOnBlackBackground is 0xFF000000', () {
        expect(AccessibilityTheme.whiteOnBlackBackground, 0xFF000000);
      });

      test('whiteOnBlackForeground is 0xFFFFFFFF', () {
        expect(AccessibilityTheme.whiteOnBlackForeground, 0xFFFFFFFF);
      });
    });
  });
}
