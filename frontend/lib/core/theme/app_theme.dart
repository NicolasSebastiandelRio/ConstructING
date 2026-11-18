import 'package:flutter/material.dart';

class AppTheme {
  // Paleta Institucional ConstructING
  static const Color primaryRed = Color(0xFF8C1C13); // Botones y detalles
  static const Color accentGold = Color(0xFFC5A059); // Títulos y Headers
  static const Color darkBackground = Color(0xFF1A1B1C); // Fondo
  static const Color darkSurface = Color(0xFF242526); // Tarjetas / Contenedores
  static const Color lightText = Color(0xFFFFFFFF); // Blanco
  static const Color lightBlue = Color(0xFF3498DB); // Hipervínculos

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      fontFamily: 'Cinzel',
      colorScheme: const ColorScheme.dark(
        primary: primaryRed,
        secondary: accentGold,
        surface: darkSurface,
        onPrimary: lightText,
        onSecondary: lightText,
        onSurface: lightText,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Cinzel', color: accentGold, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(fontFamily: 'Cinzel', color: accentGold, fontWeight: FontWeight.bold),
        headlineLarge: TextStyle(fontFamily: 'Cinzel', color: accentGold, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(fontFamily: 'Cinzel', color: accentGold, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontFamily: 'Cinzel', color: accentGold, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(fontFamily: 'Cinzel', color: accentGold, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontFamily: 'Cinzel', color: lightText),
        bodyMedium: TextStyle(fontFamily: 'Cinzel', color: lightText),
        labelLarge: TextStyle(fontFamily: 'Cinzel', color: lightText, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryRed,
          foregroundColor: lightText,
          textStyle: const TextStyle(
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        labelStyle: const TextStyle(fontFamily: 'Cinzel', color: accentGold),
        hintStyle: const TextStyle(fontFamily: 'Cinzel', color: Colors.white38),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accentGold, width: 1.5),
        ),
      ),
    );
  }
}