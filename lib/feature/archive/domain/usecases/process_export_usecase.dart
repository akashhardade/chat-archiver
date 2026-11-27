import 'package:dartz/dartz.dart';
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/entities/chat_message.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_merger.dart';
import 'package:chat_archiver/feature/archive/domain/services/export_file_reader.dart';
import 'package:chat_archiver/feature/archive/domain/services/transcript_parser.dart';
import 'package:chat_archiver/feature/archive/domain/services/transcript_writer.dart';

/// What to do with the archive when the export cannot be aligned with it
/// ([MergeStatus.gap]).
enum GapPolicy {
  /// Leave the archive untouched (default, safest: a wrong-chat export cannot
  /// pollute the archive). The raw snapshot payload is still produced so the
  /// caller can upload it to `snapshots/` and nothing is lost.
  holdBack,

  /// Append the whole snapshot to the archive (nothing is lost, but messages
  /// already archived may be duplicated).
  appendSnapshot,
}

class ProcessExportParams {
  final ArchivedGroup group;

  /// Messages currently in the group's archive (parse `archive.txt` with
  /// `TranscriptParser.parse`); empty for a first run.
  final List<ChatMessage> archiveMessages;

  /// Bytes as received from WhatsApp (zip or txt).
  final List<int> exportBytes;
  final String? fileName;
  final String? mimeType;
  final GapPolicy onGap;

  const ProcessExportParams({
    required this.group,
    required this.archiveMessages,
    required this.exportBytes,
    this.fileName,
    this.mimeType,
    this.onGap = GapPolicy.holdBack,
  });
}

/// Everything the caller needs to upload and persist after a processed
/// export. Nothing here has been uploaded yet.
class ProcessExportResult {
  final MergeResult merge;

  /// The group state to persist ONCE THE UPLOAD IS CONFIRMED, via
  /// [markUploaded]. `status` is `ok` (initial/appended/noChange) or `gap`;
  /// `messageCount`/`lastMessageKey` describe the resulting archive;
  /// `lastSuccessAt` is deliberately left unchanged here.
  final ArchivedGroup pendingGroupUpdate;

  /// Archive after the merge (equals the input archive if nothing was added).
  final List<ChatMessage> mergedMessages;

  /// Messages actually appended to the archive (empty for noChange, and for a
  /// gap with [GapPolicy.holdBack]).
  final List<ChatMessage> appendedMessages;

  /// Full new `archive.txt` content.
  final String archiveText;

  /// `updates/<ts>_new.txt` content: only [appendedMessages]; empty string if
  /// none (then there is nothing to upload).
  final String updateText;

  /// Raw decoded export (for `snapshots/<ts>.txt`), as received.
  final String snapshotText;

  const ProcessExportResult({
    required this.merge,
    required this.pendingGroupUpdate,
    required this.mergedMessages,
    required this.appendedMessages,
    required this.archiveText,
    required this.updateText,
    required this.snapshotText,
  });

  /// True when `archive.txt` differs from before and must be re-uploaded.
  bool get archiveChanged => appendedMessages.isNotEmpty;

  /// True when there is an update delta to upload.
  bool get hasUpdate => updateText.isNotEmpty;

  /// Call after all uploads were confirmed: returns the group to persist,
  /// with `lastSuccessAt = now` (also for a `gap`
  /// outcome, where the run completed but status and `lastError` stay `gap`).
  ArchivedGroup markUploaded(DateTime now) =>
      pendingGroupUpdate.copyWith(lastSuccessAt: now);
}

/// Pure (no I/O) processing of one group's export: read -> parse -> merge ->
/// serialize.
class ProcessExportUseCase {
  const ProcessExportUseCase();

  Either<Failure, ProcessExportResult> call(ProcessExportParams params) {
    final String snapshotText;
    try {
      snapshotText = ExportFileReader.readTranscript(
        params.exportBytes,
        fileName: params.fileName,
        mimeType: params.mimeType,
      );
    } on ExportFormatException catch (e) {
      return Left(ValidationFailure(e.message));
    }

    final snapshot = TranscriptParser.parse(snapshotText);
    if (snapshot.isEmpty) {
      return const Left(ValidationFailure('Export contains no messages'));
    }

    final archive = params.archiveMessages;
    final merge = ArchiveMerger.merge(archive: archive, snapshot: snapshot);

    final List<ChatMessage> appended;
    switch (merge.status) {
      case MergeStatus.initial:
      case MergeStatus.appended:
        appended = merge.newMessages;
      case MergeStatus.noChange:
        appended = const [];
      case MergeStatus.gap:
        appended = params.onGap == GapPolicy.appendSnapshot
            ? merge.newMessages
            : const [];
    }

    final merged = [...archive, ...appended];
    final isGap = merge.status == MergeStatus.gap;
    final group = params.group.copyWith(
      status: isGap ? GroupSyncStatus.gap : GroupSyncStatus.ok,
      messageCount: merged.length,
      lastMessageKey: merged.isEmpty ? null : merged.last.key,
      lastError: isGap
          ? 'Export could not be aligned with the existing archive '
              '(${params.onGap == GapPolicy.appendSnapshot ? 'snapshot appended in full' : 'archive left unchanged'}).'
          : null,
    );

    return Right(ProcessExportResult(
      merge: merge,
      pendingGroupUpdate: group,
      mergedMessages: merged,
      appendedMessages: appended,
      archiveText: TranscriptWriter.write(merged),
      updateText: TranscriptWriter.write(appended),
      snapshotText: snapshotText,
    ));
  }
}
