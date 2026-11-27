import 'package:flutter/material.dart';
import 'package:chat_archiver/core/storage/storage_keys.dart';
import 'package:chat_archiver/core/storage/storage_service.dart';

class AppPreferences {
  static final StorageService _storage = StorageService();

  static Future<void> setLocale(Locale locale) async {
    await _storage.write(StorageKeys.localizationsKey, locale.toString());
  }

  static Locale getLocale() {
    String? localeString = _storage.read(StorageKeys.localizationsKey);
    if (localeString != null) {
      final parts = localeString.split('_');
      return Locale(parts[0], parts.length > 1 ? parts[1] : null);
    } else {
      return const Locale('en', 'US');
    }
  }

  static Future<void> setLanguageCount(
    Map<String, dynamic> languageCountData,
  ) async {
    await _storage.write(StorageKeys.languageCountKey, languageCountData);
  }

  static Map<String, dynamic> getLanguageCount() {
    final data = _storage.readJson(StorageKeys.languageCountKey);
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {};
  }

  static Future<void> setTheme(bool isDarkMode) async {
    await _storage.write(StorageKeys.isDarkMode, isDarkMode);
  }

  static bool? getTheme() {
    final value = _storage.readJson(StorageKeys.isDarkMode);
    if (value is bool) return value;
    return null;
  }

}
