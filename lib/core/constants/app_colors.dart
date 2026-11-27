import 'package:flutter/material.dart';

class AppColorConst {
  AppColorConst._privateConstructor();

  static final AppColorConst _instance = AppColorConst._privateConstructor();

  factory AppColorConst() {
    return _instance;
  }

  static const Color black = Colors.black;
  static Color grey = Colors.grey;
  static Color greyBlue = Colors.blueGrey;
  static Color primaryColor = Colors.blue;
  static Color primaryblueAccent = Colors.blueAccent;
  static const Color white = Colors.white;

  /// Brand seed for the Material 3 color scheme (deep teal).
  static const Color seed = Color(0xFF0F766E);
  static const Color lightBackground = Color(0xFFF4F7F6);
  static const Color darkBackground = Color(0xFF0B0F0E);
  static const Color darkSurface = Color(0xFF151B1A);

  // Status colors (also readable on dark backgrounds).
  static const Color success = Color(0xFF1B8A4B);
  static const Color warning = Color(0xFFB45309);
  static const Color danger = Color(0xFFC62828);
}
