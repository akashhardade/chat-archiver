import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/en_us/en_us_translations.dart';
import 'package:chat_archiver/core/storage/app_preferences.dart';

/// GetX translations. Only English is shipped; add another map here (and in
/// [getSupportedLanguages]) to localize.
class AppLocalization extends Translations {
  static const Locale fallbackLocale = Locale('en', 'US');
  static final Locale locale = AppPreferences.getLocale();

  @override
  Map<String, Map<String, String>> get keys => {'en_US': enUs};

  static void changeLocale(Locale locale) {
    Get.updateLocale(locale);
    AppPreferences.setLocale(locale);
  }

  static List<Map<String, String>> getSupportedLanguages() {
    return [
      {'key': 'en_US', 'name': 'English'},
    ];
  }
}
