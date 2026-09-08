import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dark theme is "Aetheris Command" (the app's default, glassmorphism dark
/// palette). Light theme is "Clinical Clarity" — both are the actual named
/// design systems from the project's Stitch design file, not ad hoc colors.
class ThemeProvider extends ChangeNotifier {
  static const String _storageKey = 'theme_mode';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Loads a previously-saved preference, if any. Defaults to dark (the
  /// app's original look) when nothing has been saved yet.
  Future<void> loadSavedTheme() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      if (saved == 'light') {
        _themeMode = ThemeMode.light;
        notifyListeners();
      }
    } catch (_) {
      // Keep the dark default if secure storage isn't available yet.
    }
  }

  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    try {
      await _storage.write(
        key: _storageKey,
        value: isDark ? 'dark' : 'light',
      );
    } catch (_) {
      // Persistence failing shouldn't block the in-session toggle.
    }
  }

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF041329),
      cardColor: const Color(0xFF071A33),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF38debb),
        secondary: Color(0xFF2DD4BF),
        tertiary: Color(0xFF38BDF8),
        surfaceContainerHighest: Color(0xFF1c2a41),
        onSurface: Color(0xFFffffff),
        onSurfaceVariant: Color(0xFFbacac3),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFFffffff)),
        bodyMedium: TextStyle(color: Color(0xFFbacac3)),
      ),
      iconTheme: const IconThemeData(color: Color(0xFFbacac3)),
    );
  }

  /// "Clinical Clarity" — the light design system from the project's Stitch
  /// file (stitch.withgoogle.com/projects/5956398488277013784), reused
  /// verbatim rather than inventing a new light palette.
  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: const Color(0xFFf8f9ff),
      cardColor: const Color(0xFFffffff),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF004553),
        onPrimary: Color(0xFFffffff),
        primaryContainer: Color(0xFF0d5e6f),
        secondary: Color(0xFF006973),
        onSecondary: Color(0xFFffffff),
        secondaryContainer: Color(0xFF99f0fd),
        tertiary: Color(0xFF0369A1),
        onTertiary: Color(0xFFffffff),
        surface: Color(0xFFf8f9ff),
        surfaceContainerLowest: Color(0xFFffffff),
        surfaceContainerLow: Color(0xFFeff4ff),
        surfaceContainer: Color(0xFFe5eeff),
        surfaceContainerHigh: Color(0xFFdce9ff),
        surfaceContainerHighest: Color(0xFFd3e4fe),
        onSurface: Color(0xFF0b1c30),
        onSurfaceVariant: Color(0xFF3f484b),
        outline: Color(0xFF70797c),
        error: Color(0xFFba1a1a),
        onError: Color(0xFFffffff),
        errorContainer: Color(0xFFffdad6),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF0b1c30)),
        titleTextStyle: TextStyle(
            color: Color(0xFF0b1c30),
            fontSize: 20,
            fontWeight: FontWeight.bold),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFF0b1c30)),
        bodyMedium: TextStyle(color: Color(0xFF3f484b)),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF3f484b)),
    );
  }

  ThemeData get themeData => isDarkMode ? darkTheme : lightTheme;
}
