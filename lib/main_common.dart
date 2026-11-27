import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/di/service_locator.dart';
import 'package:chat_archiver/config/flavor/flavor_config.dart';
import 'package:chat_archiver/config/localization/app_localization.dart';
import 'package:chat_archiver/config/routes/app_route.dart';
import 'package:chat_archiver/config/theme/theme_controller.dart';
import 'package:chat_archiver/core/constants/app_const.dart';
import 'package:chat_archiver/core/constants/data_const.dart';

Future<void> mainCommon({required String flavor}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize flavor
  FlavorConfig.init(flavor: flavor);

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Storage, native bridge, Drive and archive services. The bridge registers
  // the handler for native -> Dart `onProcessPending` here.
  await setupServiceLocator();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Get.find<ThemeController>();
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      builder: (context, child) {
        return Obx(() {
          return GetMaterialApp(
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: messangerKey,
            navigatorKey: navigatorKey,
            theme: themeProvider.currentTheme, // Use reactive theme
            translations: AppLocalization(),
            locale: AppLocalization.locale,
            fallbackLocale: AppLocalization.fallbackLocale,
            title: DataConstant.appTitle,
            initialRoute: AppRoutes.initial, // Default route
            getPages: AppRoutes.routes, // Define routes
          );
        });
      },
    );
  }
}

// ==================== HOW TO RUN THE APP ====================
//
// Option 1: VS Code launch configurations (F5): Dev / Stage / Prod, each in
// Debug / Profile / Release (see .vscode/launch.json).
//
// Option 2: command line. Copy dart_defines.json.example -> dart_defines.json,
// put the Google OAuth *web* client ID there (see doc/GOOGLE_DRIVE_SETUP.md),
// then:
//
// flutter run -t lib/main_dev.dart   --flavor dev   --dart-define-from-file=dart_defines.json
// flutter run -t lib/main_stage.dart --flavor stage --dart-define-from-file=dart_defines.json
// flutter run -t lib/main_prod.dart  --flavor prod  --dart-define-from-file=dart_defines.json
//
// ==================== HOW TO BUILD THE APP ====================
//
// flutter build apk --release -t lib/main_prod.dart --flavor prod --dart-define-from-file=dart_defines.json
// flutter build appbundle --release -t lib/main_prod.dart --flavor prod --dart-define-from-file=dart_defines.json
// (same for dev / stage with their main_*.dart)
