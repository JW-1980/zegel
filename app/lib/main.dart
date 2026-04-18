import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/key_service.dart';
import 'services/zegel_service.dart';
import 'services/file_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted locale + theme before the first frame so we never flash
  // the default locale / light theme while reading from disk.
  final prefs = await SharedPreferences.getInstance();
  final savedLocale = _parseLocale(prefs.getString(_localePrefsKey));
  final savedThemeMode = _parseThemeMode(prefs.getString(_themeModePrefsKey));

  runApp(
    ZegelApp(initialLocale: savedLocale, initialThemeMode: savedThemeMode),
  );
}

const String _localePrefsKey = 'zegel.app.locale';
const String _themeModePrefsKey = 'zegel.app.themeMode';

Locale _parseLocale(String? code) {
  switch (code) {
    case 'nl':
      return const Locale('nl');
    case 'en':
    default:
      return const Locale('en');
  }
}

ThemeMode _parseThemeMode(String? name) {
  switch (name) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
    default:
      return ThemeMode.system;
  }
}

/// Root widget for the Zegel application.
class ZegelApp extends StatefulWidget {
  const ZegelApp({
    super.key,
    this.initialLocale = const Locale('en'),
    this.initialThemeMode = ThemeMode.system,
  });

  final Locale initialLocale;
  final ThemeMode initialThemeMode;

  @override
  State<ZegelApp> createState() => _ZegelAppState();
}

class _ZegelAppState extends State<ZegelApp> {
  late Locale _locale;

  @override
  void initState() {
    super.initState();
    _locale = widget.initialLocale;
  }

  void _setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FileService>(create: (_) => FileService()),
        Provider<KeyService>(create: (_) => KeyService()),
        Provider<ZegelService>(create: (_) => ZegelService()),
        ChangeNotifierProvider<LocaleNotifier>(
          create: (_) => LocaleNotifier(_locale, _setLocale),
        ),
        ChangeNotifierProvider<ThemeNotifier>(
          create: (_) => ThemeNotifier(widget.initialThemeMode),
        ),
      ],
      child: Consumer2<LocaleNotifier, ThemeNotifier>(
        builder: (context, localeNotifier, themeNotifier, _) {
          return MaterialApp(
            title: 'Zegel',
            debugShowCheckedModeBanner: false,
            locale: localeNotifier.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('nl')],
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            themeMode: themeNotifier.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    const deepTeal = Color(0xFF004D40);
    const tealAccent = Color(0xFF26A69A);
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: deepTeal,
        primary: deepTeal,
        secondary: tealAccent,
        brightness: brightness,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF002B24) : deepTeal,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: deepTeal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? tealAccent : deepTeal,
          side: BorderSide(color: isDark ? tealAccent : deepTeal),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(
            color: isDark ? tealAccent : deepTeal,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: deepTeal,
        foregroundColor: Colors.white,
      ),
    );
  }
}

/// Notifier for locale changes. Also persists to `SharedPreferences` so
/// the user's language sticks across launches.
class LocaleNotifier extends ChangeNotifier {
  LocaleNotifier(this._locale, this._onLocaleChanged);

  Locale _locale;
  final void Function(Locale) _onLocaleChanged;

  Locale get locale => _locale;

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    _onLocaleChanged(locale);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localePrefsKey, locale.languageCode);
    } catch (_) {
      // Persistence is best-effort; UI state stays correct either way.
    }
  }
}

/// Notifier for theme-mode changes (system / light / dark). Persists to
/// `SharedPreferences` so the user's choice survives app restarts.
class ThemeNotifier extends ChangeNotifier {
  ThemeNotifier(this._themeMode);

  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModePrefsKey, mode.name);
    } catch (_) {
      // Persistence is best-effort.
    }
  }
}
