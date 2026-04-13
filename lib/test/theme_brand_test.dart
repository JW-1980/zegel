import 'dart:convert';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('ThemeBrand', () {
    // A fully-populated brand used across multiple tests.
    const fullBrand = ThemeBrand(
      name: 'ACME Corp',
      primaryColor: 0xFF1A237E,
      secondaryColor: 0xFF283593,
      accentColor: 0xFFFF6F00,
      backgroundColor: 0xFFFFFFFF,
      surfaceColor: 0xFFF5F5F5,
      errorColor: 0xFFB71C1C,
      fontFamily: 'Roboto',
      logoAssetPath: 'assets/logo.png',
      iconPackId: 'material',
      extraColors: <String, int>{
        'chart.axis': 0xFF607D8B,
        'banner.warning': 0xFFFFF176,
      },
    );

    group('toJson', () {
      test('contains all required fields', () {
        final json = fullBrand.toJson();
        expect(json['name'], 'ACME Corp');
        expect(json['primary_color'], 0xFF1A237E);
        expect(json['secondary_color'], 0xFF283593);
        expect(json['accent_color'], 0xFFFF6F00);
        expect(json['background_color'], 0xFFFFFFFF);
        expect(json['surface_color'], 0xFFF5F5F5);
        expect(json['error_color'], 0xFFB71C1C);
        expect(json['font_family'], 'Roboto');
        expect(json['logo_asset_path'], 'assets/logo.png');
        expect(json['icon_pack_id'], 'material');
        expect(json['extra_colors'], isA<Map<String, dynamic>>());
      });

      test('omits optional null fields', () {
        const minimal = ThemeBrand(
          name: 'Minimal',
          primaryColor: 0xFF000000,
          secondaryColor: 0xFF111111,
          backgroundColor: 0xFFFFFFFF,
          surfaceColor: 0xFFFAFAFA,
          errorColor: 0xFFFF0000,
        );
        final json = minimal.toJson();
        expect(json.containsKey('accent_color'), isFalse);
        expect(json.containsKey('font_family'), isFalse);
        expect(json.containsKey('logo_asset_path'), isFalse);
        expect(json.containsKey('icon_pack_id'), isFalse);
      });
    });

    group('fromJson', () {
      test('reconstructs all fields', () {
        final brand = ThemeBrand.fromJson(fullBrand.toJson());
        expect(brand.name, fullBrand.name);
        expect(brand.primaryColor, fullBrand.primaryColor);
        expect(brand.secondaryColor, fullBrand.secondaryColor);
        expect(brand.accentColor, fullBrand.accentColor);
        expect(brand.backgroundColor, fullBrand.backgroundColor);
        expect(brand.surfaceColor, fullBrand.surfaceColor);
        expect(brand.errorColor, fullBrand.errorColor);
        expect(brand.fontFamily, fullBrand.fontFamily);
        expect(brand.logoAssetPath, fullBrand.logoAssetPath);
        expect(brand.iconPackId, fullBrand.iconPackId);
        expect(brand.extraColors, fullBrand.extraColors);
      });

      test('handles missing optional fields gracefully', () {
        final json = <String, dynamic>{
          'name': 'Bare',
          'primary_color': 0xFF001122,
          'secondary_color': 0xFF003344,
          'background_color': 0xFFFFFFFF,
          'surface_color': 0xFFFAFAFA,
          'error_color': 0xFFCC0000,
          'extra_colors': <String, dynamic>{},
        };
        final brand = ThemeBrand.fromJson(json);
        expect(brand.accentColor, isNull);
        expect(brand.fontFamily, isNull);
        expect(brand.logoAssetPath, isNull);
        expect(brand.iconPackId, isNull);
        expect(brand.extraColors, isEmpty);
      });

      test('extraColors are parsed correctly', () {
        final brand = ThemeBrand.fromJson(fullBrand.toJson());
        expect(brand.extraColors['chart.axis'], 0xFF607D8B);
        expect(brand.extraColors['banner.warning'], 0xFFFFF176);
      });
    });

    group('encode / decodeJson round trip', () {
      test('full brand survives JSON string round trip', () {
        final encoded = fullBrand.encode();
        expect(encoded, isA<String>());
        // Must be valid JSON.
        expect(() => jsonDecode(encoded), returnsNormally);

        final decoded = ThemeBrand.decodeJson(encoded);
        expect(decoded.name, fullBrand.name);
        expect(decoded.primaryColor, fullBrand.primaryColor);
        expect(decoded.accentColor, fullBrand.accentColor);
        expect(decoded.fontFamily, fullBrand.fontFamily);
        expect(decoded.extraColors, fullBrand.extraColors);
      });

      test('minimal brand survives round trip without optional fields', () {
        const minimal = ThemeBrand(
          name: 'Minimal',
          primaryColor: 0xFF112233,
          secondaryColor: 0xFF445566,
          backgroundColor: 0xFFFFFFFF,
          surfaceColor: 0xFFFAFAFA,
          errorColor: 0xFFFF0000,
        );
        final decoded = ThemeBrand.decodeJson(minimal.encode());
        expect(decoded.name, minimal.name);
        expect(decoded.accentColor, isNull);
        expect(decoded.fontFamily, isNull);
        expect(decoded.extraColors, isEmpty);
      });

      test('color integers survive JSON number conversion', () {
        // JSON encodes numbers as doubles; fromJson must coerce back to int.
        const brand = ThemeBrand(
          name: 'Colors',
          primaryColor: 0xFFABCDEF,
          secondaryColor: 0xFF123456,
          backgroundColor: 0xFF000000,
          surfaceColor: 0xFFFFFFFF,
          errorColor: 0xFFFF0000,
        );
        final decoded = ThemeBrand.decodeJson(brand.encode());
        expect(decoded.primaryColor, 0xFFABCDEF);
        expect(decoded.secondaryColor, 0xFF123456);
      });
    });

    group('zegelDefault', () {
      test('is a const with expected values', () {
        expect(ThemeBrand.zegelDefault.name, 'Zegel Default');
        expect(ThemeBrand.zegelDefault.primaryColor, 0xFF004D40);
        expect(ThemeBrand.zegelDefault.secondaryColor, 0xFF26A69A);
        expect(ThemeBrand.zegelDefault.backgroundColor, 0xFFFFFFFF);
        expect(ThemeBrand.zegelDefault.surfaceColor, 0xFFFAFAFA);
        expect(ThemeBrand.zegelDefault.errorColor, 0xFFB00020);
        expect(ThemeBrand.zegelDefault.accentColor, isNull);
        expect(ThemeBrand.zegelDefault.fontFamily, isNull);
      });

      test('zegelDefault serialises and deserialises', () {
        final decoded = ThemeBrand.decodeJson(ThemeBrand.zegelDefault.encode());
        expect(decoded.name, ThemeBrand.zegelDefault.name);
        expect(decoded.primaryColor, ThemeBrand.zegelDefault.primaryColor);
      });
    });
  });
}
