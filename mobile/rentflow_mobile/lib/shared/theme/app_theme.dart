import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const darkOlive = Color(0xFF303C1F);
  static const olive = Color(0xFF5F7144);
  static const sage = Color(0xFFDDE5CC);
  static const warmCream = Color(0xFFF7F4ED);
  static const softCream = Color(0xFFF3F0E8);
  static const primaryText = Color(0xFF20211D);
  static const secondaryText = Color(0xFF737368);
  static const outline = Color(0xFFDED9CF);
  static const white = Color(0xFFFFFFFF);

  // Semantic aliases keep existing feature screens aligned with the shared
  // authenticated visual system without changing their behavior.
  static const primary = olive;
  static const background = warmCream;
  static const surface = white;
  static const text = primaryText;
  static const muted = secondaryText;
  static const border = outline;
  static const danger = Color(0xFF9A3F3B);
  static const success = Color(0xFF3F6335);
  static const warning = Color(0xFF755B15);
  static const neutral = Color(0xFF5F625E);
  static const pending = Color(0xFFFFF1C7);
  static const progress = Color(0xFFDDE7EF);

  // Authentication aliases are intentionally retained so the existing
  // landing and authentication screens keep their current appearance.
  static const authPrimary = darkOlive;
  static const authPressed = Color(0xFF46552E);
  static const authCard = warmCream;
  static const authInput = softCream;
  static const authText = primaryText;
  static const authMuted = secondaryText;
  static const authBorder = outline;
  static const authSage = sage;
}

abstract final class AppSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const base = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 40.0;

  static const page = EdgeInsets.symmetric(horizontal: 20, vertical: 20);
  static const card = EdgeInsets.all(base);
}

abstract final class AppRadii {
  static const small = 10.0;
  static const medium = 14.0;
  static const card = 18.0;
  static const pill = 999.0;
  static const authCard = 22.0;
  static const authField = 12.0;
}

abstract final class AppTheme {
  static ThemeData build() {
    const scheme = ColorScheme.light(
      primary: AppPalette.olive,
      onPrimary: AppPalette.white,
      secondary: AppPalette.darkOlive,
      onSecondary: AppPalette.white,
      surface: AppPalette.white,
      onSurface: AppPalette.primaryText,
      error: AppPalette.danger,
      onError: AppPalette.white,
      outline: AppPalette.outline,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppPalette.warmCream,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: AppPalette.primaryText,
          fontSize: 26,
          height: 1.18,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: AppPalette.primaryText,
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: AppPalette.primaryText,
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: AppPalette.primaryText,
          fontSize: 16,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          color: AppPalette.secondaryText,
          fontSize: 14,
          height: 1.45,
        ),
        labelLarge: TextStyle(fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: AppPalette.warmCream,
        foregroundColor: AppPalette.darkOlive,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppPalette.primaryText,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppPalette.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppPalette.outline),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: AppPalette.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppPalette.sage,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppPalette.darkOlive
                : AppPalette.secondaryText,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppPalette.darkOlive
                : AppPalette.secondaryText,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppPalette.outline),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppPalette.darkOlive,
        contentTextStyle: const TextStyle(
          color: AppPalette.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          backgroundColor: AppPalette.darkOlive,
          foregroundColor: AppPalette.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          foregroundColor: AppPalette.darkOlive,
          side: const BorderSide(color: AppPalette.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: AppPalette.darkOlive,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.softCream,
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: AppPalette.outline),
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
    );
  }
}
