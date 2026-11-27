import 'package:chat_archiver/feature/automation/domain/entities/automation_config.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_event.dart';
import 'package:chat_archiver/feature/automation/domain/entities/pending_export.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_report.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_start_result.dart';

/// Thrown when a native call fails (platform error, missing plugin, ...).
class AutomationBridgeException implements Exception {
  final String code;
  final String? message;
  const AutomationBridgeException(this.code, [this.message]);

  @override
  String toString() => 'AutomationBridgeException($code, $message)';
}

/// Dart view of the native automation, exactly as defined in
/// `doc/AUTOMATION_CHANNEL.md`. Implemented by `MethodChannelAutomationBridge`;
/// tests use a fake.
abstract class AutomationBridge {
  Future<bool> isAccessibilityEnabled();
  Future<void> openAccessibilitySettings();
  Future<void> saveConfig(AutomationConfig config);
  Future<AutomationConfig?> getConfig();

  /// Empty [groupIds] = all enabled groups.
  Future<RunStartResult> runNow({List<String> groupIds = const []});
  Future<void> cancelRun();

  /// Also the cheap call that makes native flush a queued `onProcessPending`.
  Future<bool> isRunning();

  /// Oldest first.
  Future<List<PendingExport>> listPendingExports();

  /// Deletes the stored file and its record. Call ONLY after every upload for
  /// the export was confirmed.
  Future<void> ackExport(String jobId);
  Future<RunReport?> getLastRunReport();

  /// Path of a text dump of the active window's node tree.
  Future<String> dumpScreen({int delaySeconds = 10});

  /// True when Android does not apply battery optimisation to the app.
  Future<bool> isIgnoringBatteryOptimizations();

  /// Opens Android's "allow to run in background" dialog (or the battery
  /// optimisation list / app info as fallback). Returns which screen opened:
  /// `dialog`, `list`, `app_settings` or `none`.
  Future<String> requestIgnoreBatteryOptimizations();

  /// Opens Android's App info page for this app (restricted settings,
  /// battery, OEM autostart).
  Future<void> openAppSettings();

  /// Best-effort progress events (the UI may be closed; always reconcile with
  /// [listPendingExports] / [getLastRunReport]).
  Stream<AutomationEvent> get events;

  /// Emits whenever native asks Dart to process pending exports
  /// (`onProcessPending`).
  Stream<void> get processPendingRequests;
}
