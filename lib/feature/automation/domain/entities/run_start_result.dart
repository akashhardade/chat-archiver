import 'package:equatable/equatable.dart';

/// Reasons `runNow` can refuse to start (contract values).
class RunRefusal {
  RunRefusal._();
  static const accessibilityDisabled = 'accessibility_disabled';
  static const alreadyRunning = 'already_running';
  static const noGroups = 'no_groups';
  static const whatsappNotInstalled = 'whatsapp_not_installed';

  static String describe(String? reason) {
    switch (reason) {
      case accessibilityDisabled:
        return 'Turn on the Chat Archiver accessibility service first (Settings > Accessibility service). If it already shows as on, switch it off and on again in Android Settings.';
      case alreadyRunning:
        return 'A sync is already running.';
      case noGroups:
        return 'Add and enable at least one group first.';
      case whatsappNotInstalled:
        return 'WhatsApp is not installed on this phone.';
      default:
        return 'The sync could not be started.';
    }
  }
}

class RunStartResult extends Equatable {
  final bool started;

  /// One of [RunRefusal] when [started] is false.
  final String? reason;

  const RunStartResult({required this.started, this.reason});

  factory RunStartResult.fromMap(Map<dynamic, dynamic> map) => RunStartResult(
        started: map['started'] as bool? ?? false,
        reason: map['reason'] as String?,
      );

  @override
  List<Object?> get props => [started, reason];
}
