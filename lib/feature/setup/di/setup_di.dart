import 'package:get/get.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_config_service.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';
import 'package:chat_archiver/feature/setup/presentation/view_model/setup_controller.dart';

class SetupDI {
  static void setup() {
    Get.lazyPut<SetupController>(
      () => SetupController(
        coordinator: Get.find<SyncCoordinator>(),
        config: Get.find<ArchiveConfigService>(),
        bridge: Get.find<AutomationBridge>(),
      ),
      fenix: true,
    );
  }
}
