import 'package:equatable/equatable.dart';

/// How an export reached the app.
enum ExportTrigger { unlock, manual, share, unknown }

ExportTrigger _parseTrigger(Object? v) {
  switch (v) {
    case 'unlock':
      return ExportTrigger.unlock;
    case 'manual':
      return ExportTrigger.manual;
    case 'share':
      return ExportTrigger.share;
    default:
      return ExportTrigger.unknown;
  }
}

/// An exported WhatsApp transcript that native stored in app-private storage
/// and that Dart has not acknowledged yet (see `doc/AUTOMATION_CHANNEL.md`).
class PendingExport extends Equatable {
  final String jobId;

  /// Config group id, or null for a manual share outside a run.
  final String? groupId;

  /// Group title (from config, or parsed from the share subject / file name).
  final String groupName;

  /// Absolute path in app-private storage.
  final String filePath;
  final String fileName;
  final String? mimeType;
  final DateTime receivedAt;
  final String? runId;
  final ExportTrigger trigger;

  const PendingExport({
    required this.jobId,
    required this.groupId,
    required this.groupName,
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.receivedAt,
    this.runId,
    this.trigger = ExportTrigger.unknown,
  });

  factory PendingExport.fromMap(Map<dynamic, dynamic> map) {
    final received = map['receivedAt'];
    return PendingExport(
      jobId: map['jobId'] as String,
      groupId: map['groupId'] as String?,
      groupName: (map['groupName'] as String?) ?? '',
      filePath: map['filePath'] as String,
      fileName: (map['fileName'] as String?) ?? '',
      mimeType: map['mimeType'] as String?,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        received is num ? received.toInt() : 0,
      ),
      runId: map['runId'] as String?,
      trigger: _parseTrigger(map['trigger']),
    );
  }

  @override
  List<Object?> get props => [
        jobId,
        groupId,
        groupName,
        filePath,
        fileName,
        mimeType,
        receivedAt,
        runId,
        trigger,
      ];
}
