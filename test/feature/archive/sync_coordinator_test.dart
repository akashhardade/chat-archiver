import 'dart:io';

import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/archive/data/local_archive_store.dart';
import 'package:chat_archiver/feature/drive/domain/drive_auth_service.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_config_service.dart';
import 'package:chat_archiver/feature/archive/domain/usecases/sync_orchestrator.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/groups_controller.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_event.dart';
import 'package:chat_archiver/feature/automation/domain/entities/pending_export.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_report.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_start_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../support/fake_drive_server.dart';
import '../../support/fakes.dart';

const day1 = '12/03/2026, 14:05 - Alice: hi\n12/03/2026, 14:06 - Bob: yo\n';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

/// Polls until [condition] holds (events are asynchronous; CPU load varies).
Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached in time');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FakeAutomationBridge bridge;
  late FakeDriveGateway drive;
  late FakeStateRepository state;
  late FakeDriveAuth auth;
  late ArchiveConfigService config;
  late SyncCoordinator coordinator;
  var ids = 0;

  setUp(() async {
    Get.reset();
    tmp = await Directory.systemTemp.createTemp('coordinator_test');
    bridge = FakeAutomationBridge();
    drive = FakeDriveGateway();
    state = FakeStateRepository();
    auth = FakeDriveAuth(FakeDriveServer().client);
    ids = 0;
    config = ArchiveConfigService(
      state: state,
      settings: state,
      bridge: bridge,
      idGenerator: () => 'g${++ids}',
      isDriveConnected: () => auth.isConnected,
    );
    coordinator = SyncCoordinator(
      bridge: bridge,
      orchestrator: SyncOrchestrator(
        bridge: bridge,
        drive: drive,
        config: config,
        state: state,
        store: LocalArchiveStore(tmp),
      ),
      config: config,
      drive: auth,
    );
  });

  tearDown(() async {
    // Let any background processing finish before removing its files.
    await until(() => !coordinator.processing.value);
    Get.reset();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<PendingExport> addExport(String groupId) async {
    final f = File('${tmp.path}/e${bridge.pending.length}.txt')
      ..writeAsStringSync(day1);
    final e = PendingExport(
      jobId: 'job${bridge.pending.length + 1}',
      groupId: groupId,
      groupName: 'Book Club',
      filePath: f.path,
      fileName: 'x.txt',
      mimeType: 'text/plain',
      receivedAt: DateTime(2026, 3, 12, 14, 30),
    );
    bridge.pending.add(e);
    return e;
  }

  group('sync block reasons', () {
    test('drive first, then accessibility, then groups, then busy', () async {
      auth.account = null;
      bridge.accessibilityEnabled = false;
      await coordinator.reload();
      expect(coordinator.syncBlock, SyncBlock.driveNotConnected);

      auth.account = const DriveAccount(email: 'a@b.c');
      await coordinator.reload();
      expect(coordinator.syncBlock, SyncBlock.accessibilityOff);

      bridge.accessibilityEnabled = true;
      await coordinator.reload();
      expect(coordinator.syncBlock, SyncBlock.noGroups);

      await config.addGroup('Book Club');
      await coordinator.reload();
      expect(coordinator.syncBlock, isNull);

      coordinator.nativeRunning.value = true;
      expect(coordinator.syncBlock, SyncBlock.busy);
    });
  });

  group('start-up', () {
    test('calls isRunning, pushes config, processes pending exports', () async {
      final g = (await config.addGroup('Book Club')).getOrElse(() => fail('x'));
      await addExport(g.id);
      bridge.savedConfigs.clear();

      await coordinator.start();

      expect(bridge.acked, ['job1']);
      expect(bridge.savedConfigs, isNotEmpty);
      expect(coordinator.ready.value, isTrue);
      expect(coordinator.groups.single.status, GroupSyncStatus.ok);
      expect(coordinator.pending, isEmpty);
    });

    test('with Drive disconnected nothing is processed and the export stays',
        () async {
      auth.account = null;
      final g = (await config.addGroup('Book Club')).getOrElse(() => fail('x'));
      await addExport(g.id);

      await coordinator.start();

      expect(bridge.acked, isEmpty);
      expect(drive.uploadLog, isEmpty);
      expect(coordinator.pending, hasLength(1));
    });
  });

  group('Drive access expired', () {
    test(
        'an AuthFailure keeps the export and asks to reconnect; a successful '
        'upload afterwards clears it', () async {
      final g = (await config.addGroup('Book Club')).getOrElse(() => fail('x'));
      await addExport(g.id);
      drive.failWith = const AuthFailure('expired');

      final summary = await coordinator.processNow();

      expect(summary!.needsDriveReconnect, isTrue);
      expect(coordinator.driveNeedsReconnect.value, isTrue);
      expect(bridge.acked, isEmpty);
      expect(coordinator.pending, hasLength(1));

      drive.failWith = null;
      await coordinator.processNow();
      expect(coordinator.driveNeedsReconnect.value, isFalse);
      expect(bridge.acked, ['job1']);
    });

    test('a network failure is not a reconnect problem', () async {
      final g = (await config.addGroup('Book Club')).getOrElse(() => fail('x'));
      await addExport(g.id);
      drive.failWith = const NetworkFailure('offline');

      await coordinator.processNow();

      expect(coordinator.driveNeedsReconnect.value, isFalse);
      expect(bridge.acked, isEmpty);
    });

    test('disconnecting Drive also stops the automatic runs', () async {
      await state.setSetupComplete(true);
      await config.addGroup('Book Club');
      expect(bridge.savedConfigs.last.enabled, isTrue);

      await coordinator.disconnectDrive();
      expect(bridge.savedConfigs.last.enabled, isFalse);

      auth.account = const DriveAccount(email: 'a@b.c'); // what connect() does
      await coordinator.connectDrive();
      expect(bridge.savedConfigs.last.enabled, isTrue);
    });

    test('connectDrive clears the reconnect state', () async {
      coordinator.driveNeedsReconnect.value = true;
      await coordinator.connectDrive();
      expect(coordinator.driveNeedsReconnect.value, isFalse);
    });
  });

  group('battery optimisation', () {
    test('reload reflects the battery state; the request goes to native',
        () async {
      bridge.batteryUnrestricted = false;
      await coordinator.reload();
      expect(coordinator.batteryUnrestricted.value, isFalse);

      await coordinator.requestBatteryExemption();
      await coordinator.openAppSettings();
      expect(bridge.batteryRequests, 1);
      expect(bridge.appSettingsOpened, 1);

      bridge.batteryUnrestricted = true;
      await coordinator.reload();
      expect(coordinator.batteryUnrestricted.value, isTrue);
    });
  });

  group('events and triggers', () {
    test('onProcessPending from native triggers processing', () async {
      Get.put(coordinator); // runs onInit: subscriptions
      await settle();
      final g = (await config.addGroup('Book Club')).getOrElse(() => fail('x'));
      await addExport(g.id);

      bridge.processController.add(null);
      await until(() => bridge.acked.isNotEmpty);

      expect(bridge.acked, ['job1']);
    });

    test('run events drive progress; runFinished processes the exports',
        () async {
      Get.put(coordinator);
      final g = (await config.addGroup('Book Club')).getOrElse(() => fail('x'));
      await settle();
      await addExport(g.id);

      bridge.eventController.add(
        RunStartedEvent(runId: 'r', trigger: 'manual', groupIds: [g.id]),
      );
      await until(() => coordinator.nativeRunning.value);
      expect(coordinator.nativeRunning.value, isTrue);
      expect(coordinator.runProgress[g.id], RunGroupProgress.waiting);

      bridge.eventController.add(GroupStartedEvent(runId: 'r', groupId: g.id));
      await until(() => coordinator.currentGroupId.value == g.id);
      expect(coordinator.runProgress[g.id], RunGroupProgress.exporting);
      expect(coordinator.currentGroupName, 'Book Club');

      bridge.eventController.add(
        GroupFailedEvent(runId: 'r', groupId: g.id, error: 'timeout'),
      );
      await until(() => coordinator.runErrors[g.id] != null);
      expect(coordinator.runProgress[g.id], RunGroupProgress.failed);
      expect(coordinator.runErrors[g.id], 'timeout');

      bridge.eventController.add(
        RunFinishedEvent(
          runId: 'r',
          report: RunReport(
            runId: 'r',
            trigger: 'manual',
            startedAt: DateTime(2026, 3, 12),
            finishedAt: DateTime(2026, 3, 12, 0, 1),
            results: [
              GroupRunResult(
                groupId: g.id,
                groupName: 'Book Club',
                status: GroupRunStatus.exported,
              ),
            ],
          ),
        ),
      );
      await until(() => bridge.acked.isNotEmpty);

      expect(coordinator.nativeRunning.value, isFalse);
      expect(coordinator.runProgress[g.id], RunGroupProgress.exported);
      expect(bridge.acked, ['job1']);
    });

    test('syncNow forwards the refusal reason', () async {
      bridge.runResult = const RunStartResult(
        started: false,
        reason: RunRefusal.noGroups,
      );
      final r = await coordinator.syncNow();
      expect(r.started, isFalse);
      expect(r.reason, RunRefusal.noGroups);
      expect(coordinator.nativeRunning.value, isFalse);

      bridge.runResult = const RunStartResult(started: true);
      await config.addGroup('Book Club');
      await coordinator.reload();
      expect((await coordinator.syncNow()).started, isTrue);
      expect(coordinator.nativeRunning.value, isTrue);
    });
  });

  group('GroupsController', () {
    late GroupsController groups;

    setUp(() {
      groups = GroupsController(coordinator: coordinator, config: config);
    });

    test('add validates and trims; duplicates are rejected', () async {
      expect(await groups.add('   '), isNotNull);
      expect(await groups.add('  Book   Club  '), isNull);
      expect(groups.groups.single.name, 'Book Club');
      expect(await groups.add('Book Club'), contains('already'));
      expect(groups.groups, hasLength(1));
    });

    test('edit, toggle and remove push the config to native', () async {
      expect(await groups.add('Book Club'), isNull);
      final id = groups.groups.single.id;

      expect(await groups.rename(id, 'Book Club 2'), isNull);
      expect(groups.groups.single.name, 'Book Club 2');
      expect(bridge.savedConfigs.last.groups.single.name, 'Book Club 2');

      await groups.setEnabled(id, false);
      expect(groups.groups.single.enabled, isFalse);
      expect(bridge.savedConfigs.last.groups.single.enabled, isFalse);

      await groups.remove(id);
      expect(groups.groups, isEmpty);
      expect(bridge.savedConfigs.last.groups, isEmpty);
    });

    test('renaming a group that has an archive starts a new archive', () async {
      await groups.add('Book Club');
      final old = groups.groups.single;
      await config.updateGroupState(
        old.id,
        (g) => g.copyWith(messageCount: 5, status: GroupSyncStatus.ok),
      );

      expect(await groups.rename(old.id, 'Reading Club'), isNull);

      final renamed = groups.groups.single;
      expect(renamed.id, isNot(old.id));
      expect(renamed.messageCount, 0);
      expect(renamed.status, GroupSyncStatus.neverSynced);
    });

    test('state updates never overwrite a concurrent title edit', () async {
      await groups.add('Book Club');
      final id = groups.groups.single.id;

      final state1 = config.updateGroupState(
        id,
        (g) => g.copyWith(status: GroupSyncStatus.failed, lastError: 'x'),
      );
      final rename = groups.rename(id, 'Renamed');
      await Future.wait([state1, rename]);

      final g = (await config.groups()).single;
      expect(g.name, 'Renamed');
    });
  });
}
