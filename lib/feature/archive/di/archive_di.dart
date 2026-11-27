import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:chat_archiver/core/storage/storage_service.dart';
import 'package:chat_archiver/feature/archive/data/archive_state_repository_impl.dart';
import 'package:chat_archiver/feature/archive/data/local_archive_store.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_file_store.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_settings_repository.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_state_repository.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_config_service.dart';
import 'package:chat_archiver/feature/archive/domain/usecases/sync_orchestrator.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/groups_controller.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';
import 'package:chat_archiver/feature/drive/domain/drive_auth_service.dart';
import 'package:chat_archiver/feature/drive/domain/drive_gateway.dart';

/// Archive state, orchestrator and shared controllers. Needs the automation
/// and Drive modules to be set up first.
class ArchiveDI {
  static Future<void> setup() async {
    final docs = await getApplicationDocumentsDirectory();
    final repo = ArchiveStateRepositoryImpl(Get.find<StorageService>());
    Get.put<ArchiveStateRepository>(repo, permanent: true);
    Get.put<ArchiveSettingsRepository>(repo, permanent: true);
    Get.put<ArchiveFileStore>(LocalArchiveStore(docs), permanent: true);

    final driveAuth = Get.find<DriveAuthService>();
    final config = ArchiveConfigService(
      state: repo,
      settings: repo,
      bridge: Get.find<AutomationBridge>(),
      isDriveConnected: () => driveAuth.isConnected,
    );
    Get.put<ArchiveConfigService>(config, permanent: true);

    final orchestrator = SyncOrchestrator(
      bridge: Get.find<AutomationBridge>(),
      drive: Get.find<DriveGateway>(),
      config: config,
      state: repo,
      store: Get.find<ArchiveFileStore>(),
    );
    Get.put<SyncOrchestrator>(orchestrator, permanent: true);

    // Starts listening to native events and processing pending exports.
    final coordinator = SyncCoordinator(
      bridge: Get.find<AutomationBridge>(),
      orchestrator: orchestrator,
      config: config,
      drive: Get.find<DriveAuthService>(),
    );
    Get.put<SyncCoordinator>(coordinator, permanent: true);

    Get.lazyPut<GroupsController>(
      () => GroupsController(
        coordinator: Get.find<SyncCoordinator>(),
        config: Get.find<ArchiveConfigService>(),
      ),
      fenix: true,
    );
  }
}
