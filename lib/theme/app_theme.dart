import 'package:flutter/material.dart';

class AppTheme {
  // ─── Light palette (warm, high-contrast) ───
  static const Color primary = Color(0xFF1A2FA0);
  static const Color primaryLight = Color(0xFF3D5AFE);
  static const Color primaryDark = Color(0xFF0D1B6F);
  static const Color background = Color(0xFFFFFBF7);
  static const Color surfaceGrey = Color(0xFFF3F0EC);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF3D3D3D);
  static const Color success = Color(0xFF0D9668);
  static const Color error = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
  static const Color borderColor = Color(0xFFD6D0C8);

  // ─── Dark palette ───
  static const Color _darkBackground = Color(0xFF1A1A2E);
  static const Color _darkSurface = Color(0xFF16213E);
  static const Color _darkPrimary = Color(0xFF5B7FFF);
  static const Color _darkTextPrimary = Color(0xFFEAEAEA);
  static const Color _darkTextSecondary = Color(0xFFC8CBD0);
  static const Color _darkBorder = Color(0xFF2A2D3E);

  static ThemeData get light => _buildTheme(
        brightness: Brightness.light,
        primary: AppTheme.primary,
        background: AppTheme.background,
        surface: surfaceGrey,
        textPrimary: AppTheme.textPrimary,
        textSecondary: AppTheme.textSecondary,
        borderColor: AppTheme.borderColor,
      );

  static ThemeData get dark => _buildTheme(
        brightness: Brightness.dark,
        primary: _darkPrimary,
        background: _darkBackground,
        surface: _darkSurface,
        textPrimary: _darkTextPrimary,
        textSecondary: _darkTextSecondary,
        borderColor: _darkBorder,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color primary,
    required Color background,
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required Color borderColor,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        surface: background,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',

      // ─── Typography (all sizes ≥ 18px for accessibility) ───
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 20,
          color: textPrimary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 18,
          color: textSecondary,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: textPrimary,
        ),
      ),

      // ─── AppBar (standardized across all screens) ───
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          fontFamily: 'Roboto',
        ),
        iconTheme: IconThemeData(color: textPrimary, size: 28),
      ),

      // ─── ElevatedButton (min 64px height, 20px radius) ───
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primary.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          minimumSize: const Size(double.infinity, 64),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          elevation: 2,
          shadowColor: primary.withValues(alpha: 0.3),
        ),
      ),

      // ─── OutlinedButton (NEW — consistent with elevated) ───
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(double.infinity, 64),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide(color: primary, width: 2),
          textStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ─── TextButton (NEW — min 60x60 touch target) ───
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(60, 60),
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ─── Input fields (larger, warmer) ───
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 2.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: error, width: 2.5),
        ),
        hintStyle: TextStyle(color: textSecondary, fontSize: 18),
        labelStyle: TextStyle(color: primary, fontSize: 18),
        errorStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),

      // ─── Card theme (NEW — modern rounded) ───
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        elevation: 2,
        color: surface,
      ),

      // ─── Dialog theme (NEW — large rounded) ───
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          fontFamily: 'Roboto',
        ),
        contentTextStyle: TextStyle(
          fontSize: 18,
          color: textSecondary,
          fontFamily: 'Roboto',
        ),
      ),

      // ─── FAB theme (NEW) ───
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        extendedTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // ─── SnackBar (larger, warmer) ───
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        contentTextStyle:
            const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        actionTextColor: Colors.white,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }
}
