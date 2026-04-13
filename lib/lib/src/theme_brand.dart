import 'dart:convert';

/// Custom theme / white-label brand specification (improvement #3).
///
/// A framework-agnostic description of the colors, fonts, and
/// iconography an enterprise customer wants the Zegel UI to use. The
/// specification is serialized as JSON so it can be shipped as a config
/// file, loaded from an environment variable, or fetched from a
/// management server.
///
/// Colors are stored as 32-bit ARGB integers to match Flutter's
/// `Color.value`, but the class is deliberately free of Flutter imports.
class ThemeBrand {
  const ThemeBrand({
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.errorColor,
    this.accentColor,
    this.fontFamily,
    this.logoAssetPath,
    this.iconPackId,
    this.extraColors = const <String, int>{},
  });

  /// Short human-readable name (e.g. `"ACME Corp Sealed"`).
  final String name;

  final int primaryColor;
  final int secondaryColor;
  final int? accentColor;
  final int backgroundColor;
  final int surfaceColor;
  final int errorColor;

  /// Optional custom font family name already registered in the app.
  final String? fontFamily;

  /// Optional asset path to the brand logo used in the app bar.
  final String? logoAssetPath;

  /// Optional icon pack identifier.
  final String? iconPackId;

  /// Additional named colors the UI may consult by key (e.g.
  /// `"chart.axis"`, `"banner.warning"`).
  final Map<String, int> extraColors;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'primary_color': primaryColor,
        'secondary_color': secondaryColor,
        if (accentColor != null) 'accent_color': accentColor,
        'background_color': backgroundColor,
        'surface_color': surfaceColor,
        'error_color': errorColor,
        if (fontFamily != null) 'font_family': fontFamily,
        if (logoAssetPath != null) 'logo_asset_path': logoAssetPath,
        if (iconPackId != null) 'icon_pack_id': iconPackId,
        'extra_colors': extraColors,
      };

  String encode() => jsonEncode(toJson());

  static ThemeBrand fromJson(Map<String, dynamic> json) => ThemeBrand(
        name: json['name'] as String,
        primaryColor: (json['primary_color'] as num).toInt(),
        secondaryColor: (json['secondary_color'] as num).toInt(),
        accentColor: (json['accent_color'] as num?)?.toInt(),
        backgroundColor: (json['background_color'] as num).toInt(),
        surfaceColor: (json['surface_color'] as num).toInt(),
        errorColor: (json['error_color'] as num).toInt(),
        fontFamily: json['font_family'] as String?,
        logoAssetPath: json['logo_asset_path'] as String?,
        iconPackId: json['icon_pack_id'] as String?,
        extraColors: <String, int>{
          if (json['extra_colors'] != null)
            for (final entry
                in (json['extra_colors'] as Map<String, dynamic>).entries)
              entry.key: (entry.value as num).toInt(),
        },
      );

  static ThemeBrand decodeJson(String raw) =>
      fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// The Zegel default theme (deep teal + accent).
  static const ThemeBrand zegelDefault = ThemeBrand(
    name: 'Zegel Default',
    primaryColor: 0xFF004D40,
    secondaryColor: 0xFF26A69A,
    backgroundColor: 0xFFFFFFFF,
    surfaceColor: 0xFFFAFAFA,
    errorColor: 0xFFB00020,
  );
}
