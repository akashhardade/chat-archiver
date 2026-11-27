import 'run_report.dart';

/// Best-effort progress events from the native run (EventChannel).
sealed class AutomationEvent {
  const AutomationEvent();

  /// Returns null for unknown / malformed events (forward compatible).
  static AutomationEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final runId = (raw['runId'] as String?) ?? '';
    switch (raw['type']) {
      case 'runStarted':
        return RunStartedEvent(
          runId: runId,
          trigger: (raw['trigger'] as String?) ?? 'manual',
          groupIds: [
            for (final g in (raw['groupIds'] as List? ?? const []))
              g.toString(),
          ],
        );
      case 'groupStarted':
        return GroupStartedEvent(
          runId: runId,
          groupId: (raw['groupId'] as String?) ?? '',
        );
      case 'groupExported':
        return GroupExportedEvent(
          runId: runId,
          groupId: (raw['groupId'] as String?) ?? '',
          jobId: (raw['jobId'] as String?) ?? '',
        );
      case 'groupFailed':
        return GroupFailedEvent(
          runId: runId,
          groupId: (raw['groupId'] as String?) ?? '',
          error: (raw['error'] as String?) ?? 'unknown',
          step: raw['step'] as String?,
        );
      case 'runFinished':
        final report = raw['report'];
        return RunFinishedEvent(
          runId: runId,
          report: report is Map ? RunReport.fromMap(report) : null,
        );
      case 'exportReceived':
        return ExportReceivedEvent(jobId: (raw['jobId'] as String?) ?? '');
    }
    return null;
  }
}

class RunStartedEvent extends AutomationEvent {
  final String runId;
  final String trigger;
  final List<String> groupIds;
  const RunStartedEvent({
    required this.runId,
    required this.trigger,
    required this.groupIds,
  });
}

class GroupStartedEvent extends AutomationEvent {
  final String runId;
  final String groupId;
  const GroupStartedEvent({required this.runId, required this.groupId});
}

class GroupExportedEvent extends AutomationEvent {
  final String runId;
  final String groupId;
  final String jobId;
  const GroupExportedEvent({
    required this.runId,
    required this.groupId,
    required this.jobId,
  });
}

class GroupFailedEvent extends AutomationEvent {
  final String runId;
  final String groupId;
  final String error;
  final String? step;
  const GroupFailedEvent({
    required this.runId,
    required this.groupId,
    required this.error,
    this.step,
  });
}

class RunFinishedEvent extends AutomationEvent {
  final String runId;
  final RunReport? report;
  const RunFinishedEvent({required this.runId, this.report});
}

class ExportReceivedEvent extends AutomationEvent {
  final String jobId;
  const ExportReceivedEvent({required this.jobId});
}
