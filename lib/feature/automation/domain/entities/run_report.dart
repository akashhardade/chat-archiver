import 'package:equatable/equatable.dart';

enum GroupRunStatus { exported, failed, skipped }

/// Outcome of one group within a native run.
class GroupRunResult extends Equatable {
  final String groupId;
  final String groupName;
  final GroupRunStatus status;

  /// Error code (see `AutomationErrorCodes`) or null.
  final String? error;

  /// Last automation step reached, for diagnostics.
  final String? step;

  const GroupRunResult({
    required this.groupId,
    required this.groupName,
    required this.status,
    this.error,
    this.step,
  });

  factory GroupRunResult.fromMap(Map<dynamic, dynamic> map) {
    return GroupRunResult(
      groupId: (map['groupId'] as String?) ?? '',
      groupName: (map['groupName'] as String?) ?? '',
      status: switch (map['status']) {
        'exported' => GroupRunStatus.exported,
        'skipped' => GroupRunStatus.skipped,
        _ => GroupRunStatus.failed,
      },
      error: map['error'] as String?,
      step: map['step'] as String?,
    );
  }

  @override
  List<Object?> get props => [groupId, groupName, status, error, step];
}

/// Summary of a finished native run.
class RunReport extends Equatable {
  final String runId;

  /// `unlock` or `manual`.
  final String trigger;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final List<GroupRunResult> results;

  const RunReport({
    required this.runId,
    required this.trigger,
    required this.startedAt,
    required this.finishedAt,
    required this.results,
  });

  factory RunReport.fromMap(Map<dynamic, dynamic> map) {
    DateTime? ts(Object? v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    final raw = map['results'];
    return RunReport(
      runId: map['runId'] as String,
      trigger: (map['trigger'] as String?) ?? 'manual',
      startedAt: ts(map['startedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      finishedAt: ts(map['finishedAt']),
      results: raw is List
          ? [
              for (final r in raw)
                if (r is Map) GroupRunResult.fromMap(r),
            ]
          : const [],
    );
  }

  int get exportedCount =>
      results.where((r) => r.status == GroupRunStatus.exported).length;
  int get failedCount =>
      results.where((r) => r.status == GroupRunStatus.failed).length;

  @override
  List<Object?> get props => [runId, trigger, startedAt, finishedAt, results];
}
