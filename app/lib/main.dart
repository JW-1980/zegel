import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/key_service.dart';
import 'services/zegel_service.dart';
import 'services/file_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZegelApp());
}

/// Root widget for the Zegel application.
class ZegelApp extends StatefulWidget {
  const ZegelApp({super.key});

  @override
  State<ZegelApp> createState() => _ZegelAppState();
}

class _ZegelAppState extends State<ZegelApp> {
  Locale _locale = const Locale('en');

  void _setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FileService>(
          create: (_) => FileService(),
        ),
        Provider<KeyService>(
          create: (_) => KeyService(),
        ),
        Provider<ZegelService>(
          create: (_) => ZegelService(),
        ),
        ChangeNotifierProvider<LocaleNotifier>(
          create: (_) => LocaleNotifier(_locale, _setLocale),
        ),
      ],
      child: Consumer<LocaleNotifier>(
        builder: (context, localeNotifier, _) {
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
            supportedLocales: const [
              Locale('en'),
              Locale('nl'),
            ],
            theme: _buildTheme(),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme() {
    const deepTeal = Color(0xFF00695C);
    const tealAccent = Color(0xFF26A69A);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: deepTeal,
        primary: deepTeal,
        secondary: tealAccent,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: deepTeal,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: deepTeal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: deepTeal,
          side: const BorderSide(color: deepTeal),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: deepTeal, width: 2),
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

/// Notifier for locale changes, allowing the app to switch languages.
class LocaleNotifier extends ChangeNotifier {
  Locale _locale;
  final void Function(Locale) _onLocaleChanged;

  LocaleNotifier(this._locale, this._onLocaleChanged);

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (_locale != locale) {
      _locale = locale;
      _onLocaleChanged(locale);
      notifyListeners();
    }
  }
}
