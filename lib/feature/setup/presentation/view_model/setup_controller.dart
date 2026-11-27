import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/config/routes/app_route.dart';
import 'package:chat_archiver/core/extensions/snackbar_extension.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_config_service.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_start_result.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';

/// The five setup steps, in order.
enum SetupStep { drive, groups, permission, time, firstSync }

class SetupController extends GetxController {
  final SyncCoordinator coordinator;
  final ArchiveConfigService config;
  final AutomationBridge bridge;

  SetupController({
    required this.coordinator,
    required this.config,
    required this.bridge,
  });

  final step = SetupStep.drive.obs;
  final disclosureAccepted = false.obs;
  final startingSync = false.obs;
  final syncAttempted = false.obs;

  static const int total = 5;

  @override
  void onInit() {
    super.onInit();
    disclosureAccepted.value = config.settings.disclosureAccepted;
  }

  int get stepNumber => step.value.index + 1;

  /// Whether the current step is satisfied.
  bool get canContinue {
    switch (step.value) {
      case SetupStep.drive:
        return coordinator.driveEmail.value != null;
      case SetupStep.groups:
        return coordinator.groups.isNotEmpty;
      case SetupStep.permission:
        return coordinator.accessibilityEnabled.value;
      case SetupStep.time:
      case SetupStep.firstSync:
        return true;
    }
  }

  bool get isFirst => step.value == SetupStep.drive;
  bool get isLast => step.value == SetupStep.firstSync;

  void next() {
    if (!canContinue || isLast) return;
    step.value = SetupStep.values[step.value.index + 1];
    if (step.value == SetupStep.permission) coordinator.reload();
  }

  void back() {
    if (isFirst) return;
    step.value = SetupStep.values[step.value.index - 1];
  }

  /// Called only after the explicit "I agree" on the disclosure.
  Future<void> agreeAndOpenSettings() async {
    await config.settings.setDisclosureAccepted(true);
    disclosureAccepted.value = true;
    await openSettings();
  }

  Future<void> openSettings() async {
    try {
      await bridge.openAccessibilitySettings();
    } catch (_) {
      Get.showErrorSnackBar(message: TranslatorConst.errorGeneric.tr);
    }
  }

  Future<void> startFirstSync() async {
    startingSync.value = true;
    syncAttempted.value = true;
    final result = await coordinator.syncNow();
    startingSync.value = false;
    if (!result.started) {
      Get.showErrorSnackBar(
        title: TranslatorConst.firstSyncFailedToStart.tr,
        message: RunRefusal.describe(result.reason),
      );
    }
  }

  Future<void> finish() async {
    await config.settings.setSetupComplete(true);
    await config.pushConfig();
    Get.offAllNamed(AppRoutes.home);
  }
}
