import 'package:flutter/material.dart';
import 'package:chat_archiver/core/constants/app_colors.dart';
import 'package:chat_archiver/core/constants/font_family_const.dart';

class AppTheme {
  static final ThemeData lightTheme = _baseTheme(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColorConst.lightBackground,
    textColor: AppColorConst.black,
  );

  static final ThemeData darkTheme = _baseTheme(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColorConst.darkBackground,
    textColor: AppColorConst.white,
  );

  static ThemeData _baseTheme({
    required Brightness brightness,
    required Color scaffoldBackgroundColor,
    required Color textColor,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      fontFamily:
          FontFamilyConst.montserrat, // Applies to all text styles globally
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColorConst.seed,
        brightness: brightness,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: brightness == Brightness.light
            ? AppColorConst.white
            : AppColorConst.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: textColor.withValues(alpha: 0.10)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      appBarTheme: AppBarTheme(
        iconTheme: IconThemeData(color: textColor),
        backgroundColor: scaffoldBackgroundColor,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: textColor,
          fontFamily: FontFamilyConst.montserrat,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Define specific text theme overrides if needed,
      // otherwise fontFamily above handles the font.
      // We set the color globally for the main text theme.
      textTheme: TextTheme(
        displayLarge: TextStyle(color: textColor),
        displayMedium: TextStyle(color: textColor),
        displaySmall: TextStyle(color: textColor),
        headlineLarge: TextStyle(color: textColor),
        headlineMedium: TextStyle(color: textColor),
        headlineSmall: TextStyle(color: textColor),
        titleLarge: TextStyle(color: textColor),
        titleMedium: TextStyle(color: textColor),
        titleSmall: TextStyle(color: textColor),
        bodyLarge: TextStyle(color: textColor),
        bodyMedium: TextStyle(color: textColor),
        bodySmall: TextStyle(color: textColor),
        labelLarge: TextStyle(color: textColor),
        labelMedium: TextStyle(color: textColor),
        labelSmall: TextStyle(color: textColor),
      ),

      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(color: textColor),
        hintStyle: TextStyle(color: textColor.withValues(alpha: 0.6)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: textColor.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColorConst.seed, width: 2),
        ),
      ),

      iconTheme: IconThemeData(color: textColor),
    );
  }
}
