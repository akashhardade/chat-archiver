import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_config_service.dart';
import 'package:chat_archiver/feature/archive/domain/usecases/sync_orchestrator.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_event.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_report.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_start_result.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';
import 'package:chat_archiver/feature/drive/domain/drive_auth_service.dart';

/// Per-group progress of the current / last native run.
enum RunGroupProgress { waiting, exporting, exported, failed }

/// Why "Sync now" is not available (null = available).
enum SyncBlock { driveNotConnected, accessibilityOff, noGroups, busy }

/// App-wide state: groups, permission, run progress, pending exports. Owns
/// the triggers that make the orchestrator process pending exports (start,
/// resume, `onProcessPending`, run finished).
class SyncCoordinator extends GetxController with WidgetsBindingObserver {
  final AutomationBridge bridge;
  final SyncOrchestrator orchestrator;
  final ArchiveConfigService config;
  final DriveAuthService drive;

  SyncCoordinator({
    required this.bridge,
    required this.orchestrator,
    required this.config,
    required this.drive,
  });

  final groups = <ArchivedGroup>[].obs;
  final pending = <PendingStatus>[].obs;
  final accessibilityEnabled = false.obs;

  /// Android does not apply battery optimisation to the app (true until the
  /// first check, so nothing flashes).
  final batteryUnrestricted = true.obs;
  final nativeRunning = false.obs;

  /// The last upload attempt failed because Google Drive access must be
  /// renewed; cleared by a successful [connectDrive] or upload pass.
  final driveNeedsReconnect = false.obs;
  final processing = false.obs;
  final driveEmail = RxnString();
  final lastReport = Rxn<RunReport>();
  final lastSummary = Rxn<SyncSummary>();
  final currentGroupId = RxnString();
  final automationEnabled = true.obs;
  final morningHour = 7.obs;
  final ready = false.obs;

  /// groupId -> progress of the run in progress (or just finished).
  final runProgress = <String, RunGroupProgress>{}.obs;

  /// groupId -> native error code for groups that failed in this run.
  final runErrors = <String, String>{}.obs;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _subs.add(bridge.processPendingRequests.listen((_) => processNow()));
    _subs.add(config.changes.listen((_) => loadLocal()));
    _subs.add(
      bridge.events.listen(
        _onEvent,
        onError: (Object e) {
          if (kDebugMode) debugPrint('automation events error: $e');
        },
      ),
    );
    unawaited(start());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    super.onClose();
  }

  /// Cheap native call first (native flushes a queued `onProcessPending`),
  /// then reconcile and process anything pending.
  Future<void> start() async {
    try {
      nativeRunning.value = await bridge.isRunning();
    } catch (_) {}
    await reload();
    await config.pushConfig();
    ready.value = true;
    await processNow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(() async {
        await reload();
        await processNow();
      }());
    }
  }

  // ------------------------------------------------------------------ state

  /// Reloads everything that is cheap to read.
  Future<void> reload() async {
    await loadLocal();
    try {
      accessibilityEnabled.value = await bridge.isAccessibilityEnabled();
    } catch (_) {
      accessibilityEnabled.value = false;
    }
    try {
      batteryUnrestricted.value = await bridge.isIgnoringBatteryOptimizations();
    } catch (_) {}
    try {
      nativeRunning.value = await bridge.isRunning();
      lastReport.value = await bridge.getLastRunReport();
    } catch (_) {}
    pending.assignAll(await orchestrator.inspectPending());
  }

  /// Reloads groups and settings from storage.
  Future<void> loadLocal() async {
    groups.assignAll(await config.groups());
    automationEnabled.value = config.settings.automationEnabled;
    morningHour.value = config.settings.morningHour;
    driveEmail.value = drive.currentAccount?.email;
  }

  bool get hasEnabledGroups => groups.any((g) => g.enabled);

  SyncBlock? get syncBlock {
    if (nativeRunning.value || processing.value) return SyncBlock.busy;
    if (driveEmail.value == null) return SyncBlock.driveNotConnected;
    if (!accessibilityEnabled.value) return SyncBlock.accessibilityOff;
    if (!hasEnabledGroups) return SyncBlock.noGroups;
    return null;
  }

  bool get isBusy => nativeRunning.value || processing.value;

  // ---------------------------------------------------------------- actions

  /// Uploads everything native has exported and is still pending.
  Future<SyncSummary?> processNow() async {
    if (!drive.isConnected) {
      pending.assignAll(await orchestrator.inspectPending());
      return null;
    }
    processing.value = true;
    try {
      final summary = await orchestrator.processPending();
      lastSummary.value = summary;
      if (summary.needsDriveReconnect) {
        driveNeedsReconnect.value = true;
      } else if (summary.outcomes.any(
        (o) => o.kind != ExportOutcomeKind.failed && o.groupId != null,
      )) {
        // Something reached Drive: access works again.
        driveNeedsReconnect.value = false;
      }
      return summary;
    } finally {
      processing.value = false;
      await reload();
    }
  }

  /// Starts a native run for all enabled groups.
  Future<RunStartResult> syncNow() async {
    try {
      final result = await bridge.runNow();
      if (result.started) {
        nativeRunning.value = true;
        currentGroupId.value = null;
        _resetProgress([for (final g in groups) if (g.enabled) g.id]);
      }
      return result;
    } catch (e) {
      return const RunStartResult(started: false, reason: 'unknown');
    }
  }

  Future<Either<Failure, DriveAccount>> connectDrive() async {
    final result = await drive.connect();
    if (result.isRight()) driveNeedsReconnect.value = false;
    await loadLocal();
    await config.pushConfig(); // automatic runs need Drive
    return result;
  }

  Future<void> disconnectDrive() async {
    await drive.disconnect();
    driveNeedsReconnect.value = false;
    await loadLocal();
    await config.pushConfig(); // no automatic runs without Drive
  }

  /// "Allow Chat Archiver to run in the background" (battery optimisation).
  Future<void> requestBatteryExemption() async {
    try {
      await bridge.requestIgnoreBatteryOptimizations();
    } catch (_) {}
  }

  /// Android's App info page (restricted settings, battery, autostart).
  Future<void> openAppSettings() async {
    try {
      await bridge.openAppSettings();
    } catch (_) {}
  }

  Future<void> setMorningHour(int hour) async {
    await config.setMorningHour(hour);
    morningHour.value = hour;
  }

  Future<void> setAutomationEnabled(bool enabled) async {
    await config.setAutomationEnabled(enabled);
    automationEnabled.value = enabled;
  }

  Future<Either<Failure, Unit>> acceptBaseline(String groupId) async {
    processing.value = true;
    try {
      return await orchestrator.acceptSnapshotAsBaseline(groupId);
    } finally {
      processing.value = false;
      await reload();
    }
  }

  Future<void> discardExport(String jobId) async {
    await orchestrator.discardExport(jobId);
    await reload();
  }

  // ----------------------------------------------------------------- events

  void _onEvent(AutomationEvent event) {
    switch (event) {
      case RunStartedEvent(:final groupIds):
        nativeRunning.value = true;
        currentGroupId.value = null;
        _resetProgress(groupIds);
      case GroupStartedEvent(:final groupId):
        currentGroupId.value = groupId;
        runProgress[groupId] = RunGroupProgress.exporting;
      case GroupExportedEvent(:final groupId):
        runProgress[groupId] = RunGroupProgress.exported;
        unawaited(reload());
      case GroupFailedEvent(:final groupId, :final error):
        runProgress[groupId] = RunGroupProgress.failed;
        runErrors[groupId] = error;
        unawaited(reload());
      case ExportReceivedEvent():
        unawaited(reload());
      case RunFinishedEvent(:final report):
        nativeRunning.value = false;
        currentGroupId.value = null;
        if (report != null) {
          lastReport.value = report;
          for (final r in report.results) {
            if (r.status == GroupRunStatus.exported) {
              runProgress[r.groupId] = RunGroupProgress.exported;
            } else if (r.status == GroupRunStatus.failed) {
              runProgress[r.groupId] = RunGroupProgress.failed;
              runErrors[r.groupId] = r.error ?? 'unknown';
            }
          }
        }
        unawaited(processNow());
    }
  }

  void _resetProgress(List<String> groupIds) {
    runErrors.clear();
    runProgress
      ..clear()
      ..addAll({for (final id in groupIds) id: RunGroupProgress.waiting});
  }

  /// Name of the group currently being exported, if any.
  String? get currentGroupName {
    final id = currentGroupId.value;
    if (id == null) return null;
    for (final g in groups) {
      if (g.id == id) return g.name;
    }
    return null;
  }
}
