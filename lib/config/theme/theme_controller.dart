// ignore_for_file: unused_field
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/core/storage/app_preferences.dart';
import 'app_theme.dart';

enum _InitialThemeMode { system, light, dark }

class ThemeController {
  // Configuration: Set default theme behavior for first launch
  static const _defaultMode = _InitialThemeMode.system;

  // Reactive theme state
  final _isDarkMode =
      (AppPreferences.getTheme() ??
              (_defaultMode == _InitialThemeMode.system
                  ? WidgetsBinding
                          .instance
                          .platformDispatcher
                          .platformBrightness ==
                      Brightness.dark
                  : _defaultMode == _InitialThemeMode.dark))
          .obs;

  // Getter for current theme mode
  bool get isDarkMode => _isDarkMode.value;

  // Toggle theme and save preference
  void toggleTheme() {
    _isDarkMode.value = !_isDarkMode.value;
    AppPreferences.setTheme(_isDarkMode.value);
  }

  // Getter for current theme data
  ThemeData get currentTheme =>
      isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme;
}



//!default text size
// displayLarge: 57.0 (Default)
// displayMedium: 45.0 (Default)
// displaySmall: 36.0 (Default)
// headlineLarge: 32.0 (Default)
// headlineMedium: 28.0 (Default)
// headlineSmall: 24.0 (Default)
// titleLarge: 22.0 (Default)
// titleMedium: 16.0 (Default)
// titleSmall: 14.0 (Default)
// bodyLarge: 16.0 (Default)
// bodyMedium: 14.0 (Default)
// bodySmall: 12.0 (Default)
// labelLarge: 14.0 (Default)
// labelMedium: 12.0 (Default)
// labelSmall: 11.0 (Default)