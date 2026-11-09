import 'package:flutter/material.dart';

/// Centralized light and dark palettes for consistent styling.
class AppTheme {
  static const Color woodBrown = Color(0xFF8B4513);
  static const Color warmToffee = Color(0xFFD2691E);

  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: woodBrown,
      onPrimary: Colors.white,
      secondary: Color(0xFFB77945),
      onSecondary: Colors.white,
      error: Color(0xFFB3261E),
      onError: Colors.white,
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF2D211A),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF7F4EF),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F4EF),
        foregroundColor: Color(0xFF2D211A),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1.5,
        shadowColor: const Color(0xFF6B4226).withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: Color(0xFF9A8D83)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE9E0D7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: woodBrown, width: 1.4),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: woodBrown,
        unselectedItemColor: Color(0xFF9A8D83),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  static ThemeData get dark {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: warmToffee,
      onPrimary: Color(0xFF1C130E),
      secondary: Color(0xFFE6A06A),
      onSecondary: Color(0xFF1C130E),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: Color(0xFF36251C),
      onSurface: Color(0xFFF5E8DC),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF1C130E),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1C130E),
        foregroundColor: Color(0xFFF5E8DC),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF36251C),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF36251C),
        hintStyle: const TextStyle(color: Color(0xFFB6A294)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF594032)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: warmToffee, width: 1.4),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF281B14),
        selectedItemColor: warmToffee,
        unselectedItemColor: Color(0xFFB6A294),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
