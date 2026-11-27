import 'package:get/get.dart';
import 'package:chat_archiver/config/theme/theme_controller.dart';
import 'package:chat_archiver/core/storage/storage_service.dart';
import 'package:chat_archiver/feature/archive/di/archive_di.dart';
import 'package:chat_archiver/feature/automation/di/automation_di.dart';
import 'package:chat_archiver/feature/drive/di/drive_di.dart';
import 'package:chat_archiver/feature/home/di/home_di.dart';
import 'package:chat_archiver/feature/settings/di/settings_di.dart';
import 'package:chat_archiver/feature/setup/di/setup_di.dart';
import 'package:chat_archiver/feature/splash/di/splash_di.dart';

/// Initialize all dependencies
Future<void> setupServiceLocator() async {
  await _initCore();
  await _initFeatures();
}

/// Core dependencies (storage, theme).
Future<void> _initCore() async {
  await Get.putAsync<StorageService>(() async {
    final service = StorageService();
    await service.init();
    return service;
  }, permanent: true);

  // Theme controller (after storage is initialized)
  Get.put<ThemeController>(ThemeController(), permanent: true);
}

/// Feature modules. Order matters: automation -> drive -> archive -> screens.
Future<void> _initFeatures() async {
  AutomationDI.setup();
  DriveDI.setup();
  await ArchiveDI.setup();

  SplashDI.setup();
  SetupDI.setup();
  HomeDI.setup();
  SettingsDI.setup();
}
