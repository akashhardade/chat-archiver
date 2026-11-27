import 'package:get/get.dart';
import 'package:chat_archiver/config/routes/app_route.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_config_service.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';

/// Shows the splash briefly, then opens the setup wizard until it has been
/// completed, otherwise Home.
class SplashController extends GetxController {
  final SyncCoordinator coordinator;
  final ArchiveConfigService config;

  SplashController({required this.coordinator, required this.config});

  @override
  void onInit() {
    super.onInit();
    _navigate();
  }

  Future<void> _navigate() async {
    // Minimum splash time, and wait (briefly) for the first state load so Home
    // does not flash empty.
    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 900)),
      _waitUntilReady(),
    ]);
    Get.offAllNamed(
      config.settings.setupComplete ? AppRoutes.home : AppRoutes.setup,
    );
  }

  Future<void> _waitUntilReady() async {
    if (coordinator.ready.value) return;
    try {
      await coordinator.ready.stream
          .firstWhere((r) => r)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }
}
