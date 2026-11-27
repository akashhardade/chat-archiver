import 'dart:async';

import 'package:flutter/services.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_config.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_event.dart';
import 'package:chat_archiver/feature/automation/domain/entities/pending_export.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_report.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_start_result.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';

/// [AutomationBridge] over the platform channels of the contract:
/// MethodChannel `chat_archiver/automation`, EventChannel
/// `chat_archiver/automation/events`.
class MethodChannelAutomationBridge implements AutomationBridge {
  static const String methodChannelName = 'chat_archiver/automation';
  static const String eventChannelName = 'chat_archiver/automation/events';

  final MethodChannel _method;
  final EventChannel _events;
  final StreamController<void> _processPending =
      StreamController<void>.broadcast();

  MethodChannelAutomationBridge({MethodChannel? method, EventChannel? events})
      : _method = method ?? const MethodChannel(methodChannelName),
        _events = events ?? const EventChannel(eventChannelName) {
    // Register the handler for native -> Dart calls right away; native holds
    // `onProcessPending` until Dart's first call (see [isRunning]).
    _method.setMethodCallHandler(_onNativeCall);
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onProcessPending') {
      _processPending.add(null);
      return null;
    }
    throw MissingPluginException('Unknown method ${call.method}');
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _method.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw AutomationBridgeException(e.code, e.message);
    } on MissingPluginException catch (e) {
      throw AutomationBridgeException('missing_plugin', e.message);
    }
  }

  @override
  Future<bool> isAccessibilityEnabled() async =>
      (await _invoke<bool>('isAccessibilityEnabled')) ?? false;

  @override
  Future<void> openAccessibilitySettings() =>
      _invoke<void>('openAccessibilitySettings');

  @override
  Future<void> saveConfig(AutomationConfig config) =>
      _invoke<void>('saveConfig', config.toMap());

  @override
  Future<AutomationConfig?> getConfig() async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getConfig');
    return raw == null ? null : AutomationConfig.fromMap(raw);
  }

  @override
  Future<RunStartResult> runNow({List<String> groupIds = const []}) async {
    final raw = await _invoke<Map<dynamic, dynamic>>('runNow', {
      'groupIds': groupIds,
    });
    return raw == null
        ? const RunStartResult(started: false, reason: 'unknown')
        : RunStartResult.fromMap(raw);
  }

  @override
  Future<void> cancelRun() => _invoke<void>('cancelRun');

  @override
  Future<bool> isRunning() async => (await _invoke<bool>('isRunning')) ?? false;

  @override
  Future<List<PendingExport>> listPendingExports() async {
    final raw = await _invoke<List<dynamic>>('listPendingExports');
    final items = <PendingExport>[
      for (final e in raw ?? const [])
        if (e is Map) PendingExport.fromMap(e),
    ];
    // The contract says oldest first; correctness must not rely on it.
    items.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    return items;
  }

  @override
  Future<void> ackExport(String jobId) =>
      _invoke<void>('ackExport', {'jobId': jobId});

  @override
  Future<RunReport?> getLastRunReport() async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getLastRunReport');
    return raw == null ? null : RunReport.fromMap(raw);
  }

  @override
  Future<String> dumpScreen({int delaySeconds = 10}) async {
    final path = await _invoke<String>('dumpScreen', {
      'delaySeconds': delaySeconds,
    });
    if (path == null || path.isEmpty) {
      throw const AutomationBridgeException('dump_failed', 'No file returned');
    }
    return path;
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async =>
      (await _invoke<bool>('isIgnoringBatteryOptimizations')) ?? false;

  @override
  Future<String> requestIgnoreBatteryOptimizations() async =>
      (await _invoke<String>('requestIgnoreBatteryOptimizations')) ?? 'none';

  @override
  Future<void> openAppSettings() => _invoke<void>('openAppSettings');

  @override
  Stream<AutomationEvent> get events => _events
      .receiveBroadcastStream()
      .map(AutomationEvent.fromMap)
      .where((e) => e != null)
      .cast<AutomationEvent>();

  @override
  Stream<void> get processPendingRequests => _processPending.stream;
}
