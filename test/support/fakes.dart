import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_settings_repository.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_state_repository.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_config.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_event.dart';
import 'package:chat_archiver/feature/automation/domain/entities/pending_export.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_report.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_start_result.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';
import 'package:chat_archiver/feature/drive/domain/drive_gateway.dart';

/// Scriptable [AutomationBridge].
class FakeAutomationBridge implements AutomationBridge {
  final List<PendingExport> pending = [];
  final List<String> acked = [];
  final List<AutomationConfig> savedConfigs = [];
  RunReport? lastReport;
  bool accessibilityEnabled = true;
  bool running = false;
  bool failList = false;
  bool failAck = false;
  RunStartResult runResult = const RunStartResult(started: true);
  int runNowCalls = 0;
  int listCalls = 0;

  final StreamController<AutomationEvent> eventController =
      StreamController<AutomationEvent>.broadcast();
  final StreamController<void> processController =
      StreamController<void>.broadcast();

  @override
  Future<bool> isAccessibilityEnabled() async => accessibilityEnabled;

  @override
  Future<void> openAccessibilitySettings() async {}

  @override
  Future<void> saveConfig(AutomationConfig config) async =>
      savedConfigs.add(config);

  @override
  Future<AutomationConfig?> getConfig() async =>
      savedConfigs.isEmpty ? null : savedConfigs.last;

  @override
  Future<RunStartResult> runNow({List<String> groupIds = const []}) async {
    runNowCalls++;
    return runResult;
  }

  @override
  Future<void> cancelRun() async {}

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<List<PendingExport>> listPendingExports() async {
    listCalls++;
    if (failList) throw const AutomationBridgeException('boom', 'list failed');
    // Return a copy: callers may iterate while acks mutate the list.
    return [...pending];
  }

  @override
  Future<void> ackExport(String jobId) async {
    if (failAck) throw const AutomationBridgeException('boom', 'ack failed');
    acked.add(jobId);
    pending.removeWhere((e) => e.jobId == jobId);
  }

  @override
  Future<RunReport?> getLastRunReport() async => lastReport;

  @override
  Future<String> dumpScreen({int delaySeconds = 10}) async => '/tmp/dump.txt';

  bool batteryUnrestricted = true;
  int batteryRequests = 0;
  int appSettingsOpened = 0;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => batteryUnrestricted;

  @override
  Future<String> requestIgnoreBatteryOptimizations() async {
    batteryRequests++;
    return 'dialog';
  }

  @override
  Future<void> openAppSettings() async => appSettingsOpened++;

  @override
  Stream<AutomationEvent> get events => eventController.stream;

  @override
  Stream<void> get processPendingRequests => processController.stream;
}

/// Records what is uploaded; can fail on demand or block (concurrency test).
class FakeDriveGateway implements DriveGateway {
  /// `folder/segments/fileName` -> content.
  final Map<String, String> files = {};
  final List<String> uploadLog = [];
  Failure? failWith;

  /// When set, only uploads whose path matches fail (others succeed).
  bool Function(String path)? failWhen;

  /// When set, every upload waits for it before completing.
  Completer<void>? gate;
  int concurrent = 0;
  int maxConcurrent = 0;

  static String pathOf(List<String> segments, String name) =>
      [...segments, name].join('/');

  @override
  Future<Either<Failure, String?>> fetchText({
    required List<String> folderSegments,
    required String fileName,
  }) async {
    if (failWith != null && failWhen == null) return Left(failWith!);
    return Right(files[pathOf(folderSegments, fileName)]);
  }

  @override
  Future<Either<Failure, Unit>> upsertText({
    required List<String> folderSegments,
    required String fileName,
    required String content,
    bool cacheFileId = false,
  }) async {
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    try {
      final g = gate;
      if (g != null) await g.future;
      final path = pathOf(folderSegments, fileName);
      final f = failWith;
      if (f != null && (failWhen == null || failWhen!(path))) {
        return Left(f);
      }
      uploadLog.add(path);
      files[path] = content;
      return const Right(unit);
    } finally {
      concurrent--;
    }
  }
}

/// In-memory [ArchiveStateRepository] + settings.
class FakeStateRepository
    implements ArchiveStateRepository, ArchiveSettingsRepository {
  List<ArchivedGroup> groups = [];
  String? lastRunDate;

  @override
  int morningHour = ArchiveSettingsRepository.defaultMorningHour;
  @override
  bool automationEnabled = true;
  @override
  bool setupComplete = false;
  @override
  bool disclosureAccepted = false;
  @override
  String? lastAppliedRunId;

  @override
  Future<Either<Failure, List<ArchivedGroup>>> loadGroups() async =>
      Right([...groups]);

  @override
  Future<Either<Failure, Unit>> saveGroups(List<ArchivedGroup> g) async {
    groups = [...g];
    return const Right(unit);
  }

  @override
  Future<Either<Failure, String?>> loadLastSuccessfulRunDate() async =>
      Right(lastRunDate);

  @override
  Future<Either<Failure, Unit>> saveLastSuccessfulRunDate(String k) async {
    lastRunDate = k;
    return const Right(unit);
  }

  @override
  Future<void> setMorningHour(int hour) async => morningHour = hour;

  @override
  Future<void> setAutomationEnabled(bool enabled) async =>
      automationEnabled = enabled;

  @override
  Future<void> setSetupComplete(bool complete) async =>
      setupComplete = complete;

  @override
  Future<void> setDisclosureAccepted(bool accepted) async =>
      disclosureAccepted = accepted;

  @override
  Future<void> setLastAppliedRunId(String runId) async =>
      lastAppliedRunId = runId;
}
