import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/config/routes/app_route.dart';
import 'package:chat_archiver/core/extensions/snackbar_extension.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/usecases/sync_orchestrator.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_start_result.dart';

/// Home screen actions. State lives in [SyncCoordinator].
class HomeController extends GetxController {
  final SyncCoordinator coordinator;

  HomeController({required this.coordinator});

  /// Text explaining why "Sync now" is disabled, or null when enabled.
  String? get syncDisabledReason {
    switch (coordinator.syncBlock) {
      case null:
        return null;
      case SyncBlock.driveNotConnected:
        return TranslatorConst.syncDisabledDrive.tr;
      case SyncBlock.accessibilityOff:
        return TranslatorConst.syncDisabledAccessibility.tr;
      case SyncBlock.noGroups:
        return TranslatorConst.syncDisabledNoGroups.tr;
      case SyncBlock.busy:
        return TranslatorConst.syncDisabledRunning.tr;
    }
  }

  Future<void> syncNow() async {
    final result = await coordinator.syncNow();
    if (result.started) {
      Get.showInfoSnackBar(message: TranslatorConst.syncStarted.tr);
    } else {
      Get.showErrorSnackBar(message: RunRefusal.describe(result.reason));
    }
  }

  Future<void> retryPending() async {
    final summary = await coordinator.processNow();
    if (summary == null) {
      Get.showWarningSnackBar(message: TranslatorConst.syncDisabledDrive.tr);
    } else if (summary.hasProblems) {
      Get.showWarningSnackBar(message: TranslatorConst.retryStillFailing.tr);
    } else {
      Get.showSuccessSnackBar(message: TranslatorConst.retryDone.tr);
    }
  }

  /// Confirms, then re-processes the held-back snapshot with
  /// `GapPolicy.appendSnapshot`.
  Future<void> acceptBaseline(BuildContext context, ArchivedGroup group) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslatorConst.gapAcceptConfirmTitle.tr),
        content: Text(TranslatorConst.gapAcceptConfirmBody.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslatorConst.cancel.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(TranslatorConst.gapAccept.tr),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await coordinator.acceptBaseline(group.id);
    result.fold(
      (f) => Get.showErrorSnackBar(message: f.message),
      (_) => Get.showSuccessSnackBar(message: TranslatorConst.gapAcceptDone.tr),
    );
  }

  Future<void> discard(BuildContext context, PendingStatus item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslatorConst.pendingDiscardTitle.tr),
        content: Text(
          '"${item.export.groupName}"\n\n${TranslatorConst.pendingDiscardBody.tr}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslatorConst.cancel.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(TranslatorConst.pendingDiscard.tr),
          ),
        ],
      ),
    );
    if (ok == true) await coordinator.discardExport(item.export.jobId);
  }

  /// Interactive Google sign-in again (expired / revoked Drive access), then
  /// upload whatever is waiting.
  Future<void> reconnectDrive() async {
    final result = await coordinator.connectDrive();
    await result.fold(
      (f) async => Get.showErrorSnackBar(
        title: TranslatorConst.driveConnectFailed.tr,
        message: f.message,
      ),
      (_) async => retryPending(),
    );
  }

  void openSettings() => Get.toNamed(AppRoutes.settings);
}
