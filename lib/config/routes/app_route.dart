import 'package:get/get.dart';
import 'package:chat_archiver/feature/home/presentation/pages/home_page.dart';
import 'package:chat_archiver/feature/settings/presentation/pages/settings_page.dart';
import 'package:chat_archiver/feature/setup/presentation/pages/setup_page.dart';
import 'package:chat_archiver/feature/splash/presentation/pages/splash_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String initial = '/';
  static const String setup = '/setup';
  static const String home = '/home';
  static const String settings = '/settings';

  static final routes = [
    GetPage(name: initial, page: () => const SplashScreen()),
    GetPage(name: setup, page: () => const SetupPage()),
    GetPage(name: home, page: () => const HomePage()),
    GetPage(name: settings, page: () => const SettingsPage()),
  ];
}
