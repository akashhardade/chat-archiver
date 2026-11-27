import 'dart:async';

import 'package:chat_archiver/feature/automation/data/method_channel_automation_bridge.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_config.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_errors.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_event.dart';
import 'package:chat_archiver/feature/automation/domain/entities/pending_export.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_report.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_start_result.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PendingExport.fromMap', () {
    test('parses the contract fields', () {
      final e = PendingExport.fromMap({
        'jobId': 'j1',
        'groupId': 'g1',
        'groupName': 'Book Club',
        'filePath': '/data/user/0/app/files/exports/j1.zip',
        'fileName': 'WhatsApp Chat with Book Club.zip',
        'mimeType': 'application/zip',
        'receivedAt': 1767225600000,
        'runId': 'r1',
        'trigger': 'unlock',
      });
      expect(e.jobId, 'j1');
      expect(e.groupId, 'g1');
      expect(e.groupName, 'Book Club');
      expect(e.filePath, endsWith('j1.zip'));
      expect(e.mimeType, 'application/zip');
      expect(e.receivedAt.millisecondsSinceEpoch, 1767225600000);
      expect(e.runId, 'r1');
      expect(e.trigger, ExportTrigger.unlock);
    });

    test('manual share: null groupId / runId, unknown trigger tolerated', () {
      final e = PendingExport.fromMap({
        'jobId': 'j2',
        'groupId': null,
        'groupName': 'Project Alpha',
        'filePath': '/x/j2.txt',
        'fileName': 'WhatsApp Chat with Project Alpha.txt',
        'mimeType': 'text/plain',
        'receivedAt': 1767225600000,
        'runId': null,
        'trigger': 'share',
      });
      expect(e.groupId, isNull);
      expect(e.runId, isNull);
      expect(e.trigger, ExportTrigger.share);
      expect(
        PendingExport.fromMap({
          'jobId': 'j3',
          'filePath': '/x',
          'trigger': 'future-trigger',
        }).trigger,
        ExportTrigger.unknown,
      );
    });
  });

  group('RunReport.fromMap', () {
    final map = {
      'runId': 'r1',
      'trigger': 'manual',
      'startedAt': 1767225600000,
      'finishedAt': 1767225660000,
      'results': [
        {
          'groupId': 'g1',
          'groupName': 'A',
          'status': 'exported',
          'error': null,
          'step': 'share',
        },
        {
          'groupId': 'g2',
          'groupName': 'B',
          'status': 'failed',
          'error': 'group_not_found',
          'step': 'search',
        },
        {
          'groupId': 'g3',
          'groupName': 'C',
          'status': 'skipped',
          'error': null,
          'step': null,
        },
      ],
    };

    test('parses results and counts', () {
      final r = RunReport.fromMap(map);
      expect(r.runId, 'r1');
      expect(r.trigger, 'manual');
      expect(r.finishedAt!.difference(r.startedAt).inSeconds, 60);
      expect(r.results.map((x) => x.status), [
        GroupRunStatus.exported,
        GroupRunStatus.failed,
        GroupRunStatus.skipped,
      ]);
      expect(r.results[1].error, 'group_not_found');
      expect(r.results[1].step, 'search');
      expect(r.exportedCount, 1);
      expect(r.failedCount, 1);
    });

    test('missing finishedAt / results are tolerated', () {
      final r = RunReport.fromMap({
        'runId': 'r2',
        'trigger': 'unlock',
        'startedAt': 5,
      });
      expect(r.finishedAt, isNull);
      expect(r.results, isEmpty);
    });
  });

  group('AutomationEvent.fromMap', () {
    test('every contract event type', () {
      expect(
        AutomationEvent.fromMap({
          'type': 'runStarted',
          'runId': 'r',
          'trigger': 'manual',
          'groupIds': ['a', 'b'],
        }),
        isA<RunStartedEvent>().having((e) => e.groupIds, 'groupIds', ['a', 'b']),
      );
      expect(
        AutomationEvent.fromMap({
          'type': 'groupStarted',
          'runId': 'r',
          'groupId': 'a',
        }),
        isA<GroupStartedEvent>().having((e) => e.groupId, 'groupId', 'a'),
      );
      expect(
        AutomationEvent.fromMap({
          'type': 'groupExported',
          'runId': 'r',
          'groupId': 'a',
          'jobId': 'j',
        }),
        isA<GroupExportedEvent>().having((e) => e.jobId, 'jobId', 'j'),
      );
      expect(
        AutomationEvent.fromMap({
          'type': 'groupFailed',
          'runId': 'r',
          'groupId': 'a',
          'error': 'timeout',
          'step': 'menu',
        }),
        isA<GroupFailedEvent>()
            .having((e) => e.error, 'error', 'timeout')
            .having((e) => e.step, 'step', 'menu'),
      );
      expect(
        AutomationEvent.fromMap({
          'type': 'runFinished',
          'runId': 'r',
          'report': {'runId': 'r', 'startedAt': 1, 'results': []},
        }),
        isA<RunFinishedEvent>().having((e) => e.report?.runId, 'report', 'r'),
      );
      expect(
        AutomationEvent.fromMap({'type': 'exportReceived', 'jobId': 'j'}),
        isA<ExportReceivedEvent>(),
      );
    });

    test('unknown or malformed events are ignored', () {
      expect(AutomationEvent.fromMap({'type': 'somethingNew'}), isNull);
      expect(AutomationEvent.fromMap('nope'), isNull);
      expect(AutomationEvent.fromMap(null), isNull);
    });
  });

  group('config and run start', () {
    test('AutomationConfig round trip matches the saveConfig contract', () {
      const config = AutomationConfig(
        enabled: true,
        morningHour: 7,
        groups: [
          AutomationGroupConfig(id: 'g1', name: 'Book Club', enabled: true),
          AutomationGroupConfig(id: 'g2', name: 'Family', enabled: false),
        ],
      );
      final map = config.toMap();
      expect(map, {
        'enabled': true,
        'morningHour': 7,
        'groups': [
          {'id': 'g1', 'name': 'Book Club', 'enabled': true},
          {'id': 'g2', 'name': 'Family', 'enabled': false},
        ],
      });
      expect(AutomationConfig.fromMap(map), config);
    });

    test('RunStartResult', () {
      expect(
        RunStartResult.fromMap({'started': true, 'reason': null}).started,
        isTrue,
      );
      final refused = RunStartResult.fromMap({
        'started': false,
        'reason': 'accessibility_disabled',
      });
      expect(refused.started, isFalse);
      expect(refused.reason, RunRefusal.accessibilityDisabled);
      expect(RunRefusal.describe(refused.reason), contains('accessibility'));
    });

    test('every contract error code has a human message', () {
      for (final code in [
        'whatsapp_not_installed',
        'search_not_found',
        'group_not_found',
        'wrong_chat',
        'menu_not_found',
        'export_not_found',
        'share_target_not_found',
        'share_not_received',
        'timeout',
        'cancelled',
        'screen_locked',
        'unexpected_screen',
      ]) {
        expect(AutomationErrorCodes.isCode(code), isTrue, reason: code);
        expect(AutomationErrorCodes.describe(code), isNot(code));
      }
      expect(AutomationErrorCodes.describe('Drive is full'), 'Drive is full');
      expect(AutomationErrorCodes.describe(null), '');
    });
  });

  group('MethodChannelAutomationBridge', () {
    const methodChannel = MethodChannel('chat_archiver/automation');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    late MethodChannelAutomationBridge bridge;
    Object? Function(MethodCall call) handler = (_) => null;

    setUp(() {
      calls.clear();
      handler = (_) => null;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        final r = handler(call);
        if (r is PlatformException) throw r;
        return r;
      });
      bridge = MethodChannelAutomationBridge();
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
    });

    test('uses the contract channel names', () {
      expect(MethodChannelAutomationBridge.methodChannelName,
          'chat_archiver/automation');
      expect(MethodChannelAutomationBridge.eventChannelName,
          'chat_archiver/automation/events');
    });

    test('saveConfig / runNow / ackExport / dumpScreen send contract args',
        () async {
      handler = (call) {
        switch (call.method) {
          case 'runNow':
            return {'started': false, 'reason': 'no_groups'};
          case 'dumpScreen':
            return '/data/dump.txt';
        }
        return null;
      };
      await bridge.saveConfig(const AutomationConfig(
        enabled: false,
        morningHour: 9,
        groups: [AutomationGroupConfig(id: 'g', name: 'N', enabled: true)],
      ));
      final run = await bridge.runNow(groupIds: ['g']);
      await bridge.ackExport('job-1');
      final path = await bridge.dumpScreen(delaySeconds: 10);
      await bridge.openAccessibilitySettings();
      await bridge.cancelRun();

      expect(calls.map((c) => c.method), [
        'saveConfig',
        'runNow',
        'ackExport',
        'dumpScreen',
        'openAccessibilitySettings',
        'cancelRun',
      ]);
      expect(calls[0].arguments, {
        'enabled': false,
        'morningHour': 9,
        'groups': [
          {'id': 'g', 'name': 'N', 'enabled': true},
        ],
      });
      expect(calls[1].arguments, {
        'groupIds': ['g'],
      });
      expect(run.started, isFalse);
      expect(run.reason, 'no_groups');
      expect(calls[2].arguments, {'jobId': 'job-1'});
      expect(calls[3].arguments, {'delaySeconds': 10});
      expect(path, '/data/dump.txt');
    });

    test('battery optimisation and app settings methods', () async {
      handler = (call) {
        switch (call.method) {
          case 'isIgnoringBatteryOptimizations':
            return false;
          case 'requestIgnoreBatteryOptimizations':
            return 'list';
        }
        return null;
      };
      expect(await bridge.isIgnoringBatteryOptimizations(), isFalse);
      expect(await bridge.requestIgnoreBatteryOptimizations(), 'list');
      await bridge.openAppSettings();
      expect(calls.map((c) => c.method), [
        'isIgnoringBatteryOptimizations',
        'requestIgnoreBatteryOptimizations',
        'openAppSettings',
      ]);
      expect(calls.every((c) => c.arguments == null), isTrue);
    });

    test('isAccessibilityEnabled / isRunning / getConfig', () async {
      handler = (call) {
        switch (call.method) {
          case 'isAccessibilityEnabled':
            return true;
          case 'isRunning':
            return false;
          case 'getConfig':
            return {
              'enabled': true,
              'morningHour': 8,
              'groups': [
                {'id': 'g1', 'name': 'A', 'enabled': true},
              ],
            };
        }
        return null;
      };
      expect(await bridge.isAccessibilityEnabled(), isTrue);
      expect(await bridge.isRunning(), isFalse);
      final cfg = await bridge.getConfig();
      expect(cfg!.morningHour, 8);
      expect(cfg.groups.single.name, 'A');
    });

    test('getConfig / getLastRunReport null', () async {
      expect(await bridge.getConfig(), isNull);
      expect(await bridge.getLastRunReport(), isNull);
    });

    test('listPendingExports parses and sorts oldest first', () async {
      Map<String, Object?> item(String id, int at) => {
            'jobId': id,
            'groupId': null,
            'groupName': id,
            'filePath': '/x/$id.txt',
            'fileName': '$id.txt',
            'mimeType': 'text/plain',
            'receivedAt': at,
            'runId': null,
            'trigger': 'share',
          };
      handler = (call) => [item('b', 2000), item('a', 1000), item('c', 3000)];
      final list = await bridge.listPendingExports();
      expect(list.map((e) => e.jobId), ['a', 'b', 'c']);
    });

    test('platform errors become AutomationBridgeException', () async {
      handler = (_) => PlatformException(code: 'no_service', message: 'off');
      await expectLater(
        bridge.isAccessibilityEnabled(),
        throwsA(isA<AutomationBridgeException>()
            .having((e) => e.code, 'code', 'no_service')),
      );
    });

    test('a missing plugin is reported, not crashed on', () async {
      messenger.setMockMethodCallHandler(methodChannel, null);
      await expectLater(
        bridge.isRunning(),
        throwsA(isA<AutomationBridgeException>()
            .having((e) => e.code, 'code', 'missing_plugin')),
      );
    });

    test('native onProcessPending is delivered on the stream', () async {
      final received = Completer<void>();
      final sub = bridge.processPendingRequests.listen((_) {
        if (!received.isCompleted) received.complete();
      });
      await messenger.handlePlatformMessage(
        'chat_archiver/automation',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onProcessPending'),
        ),
        (_) {},
      );
      await received.future.timeout(const Duration(seconds: 2));
      await sub.cancel();
    });
  });
}
