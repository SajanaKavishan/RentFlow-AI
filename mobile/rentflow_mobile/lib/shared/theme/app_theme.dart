import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const primary = Color(0xFF5D6842);
  static const background = Color(0xFFF7F5EF);
  static const surface = Colors.white;
  static const text = Color(0xFF31362A);
  static const muted = Color(0xFF6F7469);
  static const border = Color(0xFFDEDBD0);
  static const danger = Color(0xFF9A3F3B);
  static const success = Color(0xFF35613B);
  static const warning = Color(0xFF755B15);
  static const neutral = Color(0xFF5F625E);
  static const pending = Color(0xFFFFF1C7);
  static const progress = Color(0xFFDDE7EF);
  static const authPrimary = Color(0xFF303C1F);
  static const authPressed = Color(0xFF46552E);
  static const authCard = Color(0xFFF7F4ED);
  static const authInput = Color(0xFFF3F0E8);
  static const authText = Color(0xFF20211D);
  static const authMuted = Color(0xFF737368);
  static const authBorder = Color(0xFFDED9CF);
  static const authSage = Color(0xFFDDE5CC);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const base = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class AppRadii {
  static const small = 10.0;
  static const card = 18.0;
  static const authCard = 24.0;
  static const authField = 12.0;
}

abstract final class AppTheme {
  static ThemeData build() {
    final scheme = ColorScheme.fromSeed(seedColor: AppPalette.primary);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: AppPalette.primary,
        surface: AppPalette.surface,
        error: AppPalette.danger,
      ),
      scaffoldBackgroundColor: AppPalette.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.primary,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: AppPalette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppPalette.border),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          backgroundColor: AppPalette.primary,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(44, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
      ),
    );
  }
}
