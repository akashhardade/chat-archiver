import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/extensions/snackbar_extension.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_config_service.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/accessibility_disclosure.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';

class SettingsController extends GetxController {
  final SyncCoordinator coordinator;
  final ArchiveConfigService config;
  final AutomationBridge bridge;

  SettingsController({
    required this.coordinator,
    required this.config,
    required this.bridge,
  });

  /// True while the 10 second screen capture is pending.
  final capturing = false.obs;

  /// Path of the last screen capture, if any.
  final capturePath = RxnString();

  /// Turning the service on needs the disclosure first (once).
  Future<void> turnOnAccessibility(BuildContext context) async {
    if (!config.settings.disclosureAccepted) {
      final agreed = await showAccessibilityDisclosureDialog(context);
      if (!agreed) return;
      await config.settings.setDisclosureAccepted(true);
    }
    await openAccessibilitySettings();
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await bridge.openAccessibilitySettings();
    } catch (_) {
      Get.showErrorSnackBar(message: TranslatorConst.errorGeneric.tr);
    }
  }

  /// Asks native to dump the active window after 10 s, so the user can open
  /// the WhatsApp screen of interest meanwhile.
  Future<void> captureScreen() async {
    if (capturing.value) return;
    capturing.value = true;
    capturePath.value = null;
    Get.showInfoSnackBar(message: TranslatorConst.diagnosticsCapturing.tr);
    try {
      capturePath.value = await bridge.dumpScreen(delaySeconds: 10);
      Get.showSuccessSnackBar(message: TranslatorConst.diagnosticsDone.tr);
    } catch (e) {
      Get.showErrorSnackBar(
        title: TranslatorConst.diagnosticsFailed.tr,
        message: '$e',
      );
    } finally {
      capturing.value = false;
    }
  }

  Future<void> shareCapture() async {
    final path = capturePath.value;
    if (path == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'text/plain')],
          subject: 'Chat Archiver screen capture',
          text: 'Chat Archiver screen capture',
        ),
      );
    } catch (e) {
      Get.showErrorSnackBar(message: '$e');
    }
  }
}
