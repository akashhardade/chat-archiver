import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_file_store.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_state_repository.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_config_service.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_merger.dart';
import 'package:chat_archiver/feature/archive/domain/services/drive_layout.dart';
import 'package:chat_archiver/feature/archive/domain/services/run_policy.dart';
import 'package:chat_archiver/feature/archive/domain/services/transcript_parser.dart';
import 'package:chat_archiver/feature/archive/domain/usecases/process_export_usecase.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_errors.dart';
import 'package:chat_archiver/feature/automation/domain/entities/pending_export.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_report.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';
import 'package:chat_archiver/feature/drive/domain/drive_gateway.dart';

/// What happened to one pending export.
enum ExportOutcomeKind {
  /// Uploaded to Drive, stored locally and acknowledged.
  uploaded,

  /// Uploaded; the archive already contained everything (snapshot only).
  noChange,

  /// The export could not be aligned with the archive: only the snapshot was
  /// uploaded, the archive was left unchanged and the group is marked `gap`.
  gapHeld,

  /// Something failed; the export stays pending and is retried.
  failed,

  /// No configured group matches the export; it stays pending.
  unmatched,

  /// Not attempted because an older export of the same group failed (order
  /// must be preserved); it stays pending.
  deferred,
}

class ExportOutcome {
  final String jobId;
  final String? groupId;
  final String groupName;
  final ExportOutcomeKind kind;
  final String? message;

  /// Messages appended to the archive by this export.
  final int appended;

  /// True when this export failed because Google Drive needs the user to
  /// sign in again ([AuthFailure]); the UI then offers "Reconnect".
  final bool authProblem;

  const ExportOutcome({
    required this.jobId,
    required this.groupId,
    required this.groupName,
    required this.kind,
    this.message,
    this.appended = 0,
    this.authProblem = false,
  });

  bool get isProblem =>
      kind == ExportOutcomeKind.failed ||
      kind == ExportOutcomeKind.unmatched ||
      kind == ExportOutcomeKind.deferred;
}

class SyncSummary {
  final DateTime at;
  final List<ExportOutcome> outcomes;

  /// Set when pending exports could not even be listed.
  final String? error;

  const SyncSummary({
    required this.at,
    this.outcomes = const [],
    this.error,
  });

  int get uploaded => outcomes
      .where(
        (o) =>
            o.kind == ExportOutcomeKind.uploaded ||
            o.kind == ExportOutcomeKind.noChange ||
            o.kind == ExportOutcomeKind.gapHeld,
      )
      .length;
  bool get hasProblems => error != null || outcomes.any((o) => o.isProblem);

  /// Some export could not be uploaded because Drive access must be renewed.
  bool get needsDriveReconnect => outcomes.any((o) => o.authProblem);
}

/// A pending export together with the group it maps to (null = unmatched).
class PendingStatus {
  final PendingExport export;
  final ArchivedGroup? group;
  const PendingStatus(this.export, this.group);

  bool get isUnmatched => group == null;
}

/// Turns pending exports handed over by native into Drive uploads, without
/// ever losing or duplicating messages.
///
/// ## Guarantees
/// * The native export is acknowledged (and thereby deleted) ONLY after every
///   upload of that export succeeded AND the local archive + group state were
///   written. Any failure leaves it pending for the next attempt.
/// * Retries are idempotent: the snapshot / update file names derive from the
///   export's `receivedAt` and the Drive gateway overwrites a file of the same
///   name, `archive.txt` is a full overwrite, and re-merging a snapshot that
///   was already merged yields `noChange`.
/// * The local archive is replaced atomically and only after Drive confirmed.
/// * Exports of one group are processed oldest first; if one fails, newer
///   ones of that group wait (otherwise the older snapshot would no longer
///   align with the advanced archive).
/// * If the local archive is missing (app data cleared) the Drive copy of
///   `archive.txt` is fetched first, so a first sync after reinstall never
///   overwrites existing history.
/// * A single lock guarantees one processing pass at a time; overlapping
///   triggers (start, resume, `onProcessPending`, run finished) are coalesced.
class SyncOrchestrator {
  final AutomationBridge _bridge;
  final DriveGateway _drive;
  final ArchiveConfigService _config;
  final ArchiveStateRepository _state;
  final ArchiveFileStore _store;
  final ProcessExportUseCase _process;
  final DateTime Function() _now;

  SyncOrchestrator({
    required AutomationBridge bridge,
    required DriveGateway drive,
    required ArchiveConfigService config,
    required ArchiveStateRepository state,
    required ArchiveFileStore store,
    ProcessExportUseCase process = const ProcessExportUseCase(),
    DateTime Function()? now,
  })  : _bridge = bridge,
        _drive = drive,
        _config = config,
        _state = state,
        _store = store,
        _process = process,
        _now = now ?? DateTime.now;

  Future<SyncSummary>? _processing;
  bool _rerun = false;
  Future<void>? _lockHolder;

  final StreamController<SyncSummary> _summaries =
      StreamController<SyncSummary>.broadcast();

  /// Emits the result of every processing pass.
  Stream<SyncSummary> get summaries => _summaries.stream;

  SyncSummary? lastSummary;

  bool get isProcessing => _processing != null;

  // ------------------------------------------------------------ public API

  /// Processes every pending export, oldest first. Concurrent calls are
  /// coalesced: while a pass is running, further calls return the same future
  /// and cause one more pass afterwards (so an export that arrived meanwhile
  /// is not missed).
  Future<SyncSummary> processPending() {
    final running = _processing;
    if (running != null) {
      _rerun = true;
      return running;
    }
    final future = _exclusive(() async {
      SyncSummary summary;
      final byJob = <String, ExportOutcome>{};
      String? error;
      do {
        _rerun = false;
        try {
          summary = await _pass();
        } catch (e) {
          summary = SyncSummary(at: _now(), error: 'Unexpected error: $e');
        }
        error = summary.error;
        for (final o in summary.outcomes) {
          byJob[o.jobId] = o;
        }
      } while (_rerun);
      final merged = SyncSummary(
        at: summary.at,
        outcomes: byJob.values.toList(),
        error: error,
      );
      lastSummary = merged;
      _summaries.add(merged);
      return merged;
    });
    _processing = future;
    unawaited(
      future.then<void>((_) => _processing = null, onError: (_) {
        _processing = null;
      }),
    );
    return future;
  }

  /// Pending exports with their matched group (UI: banner, retry).
  Future<List<PendingStatus>> inspectPending() async {
    final List<PendingExport> pending;
    try {
      pending = await _bridge.listPendingExports();
    } catch (_) {
      return const [];
    }
    final groups = await _config.groups();
    return [for (final e in pending) PendingStatus(e, matchGroup(e, groups))];
  }

  /// Gives up on an export (unreadable or never going to match): deletes it
  /// natively. Only call on explicit user request.
  Future<void> discardExport(String jobId) => _bridge.ackExport(jobId);

  /// "Accept snapshot as new baseline": re-processes the snapshot held back
  /// after a `gap`, appending it in full (`GapPolicy.appendSnapshot`). The
  /// snapshot itself is already on Drive; the update file and `archive.txt`
  /// are uploaded now.
  Future<Either<Failure, Unit>> acceptSnapshotAsBaseline(String groupId) {
    return _exclusive(() async {
      final group = await _config.groupById(groupId);
      if (group == null) {
        return const Left(NotFoundFailure('Group not found.'));
      }
      final held = await _store.readHeldSnapshot(groupId);
      if (held == null || held.isEmpty) {
        return const Left(
          ValidationFailure('There is no held-back snapshot for this group.'),
        );
      }

      final localArchive = await _store.readArchive(groupId);
      final archiveMessages = TranscriptParser.parse(localArchive ?? '');
      final processed = _process(
        ProcessExportParams(
          group: group,
          archiveMessages: archiveMessages,
          exportBytes: utf8.encode(held),
          fileName: 'snapshot.txt',
          mimeType: 'text/plain',
          onGap: GapPolicy.appendSnapshot,
        ),
      );
      final processFailure = processed.leftOrNull;
      if (processFailure != null) return Left(processFailure);
      final result = processed.rightOrNull!;

      final now = _now();
      final failure = await _uploadDelta(
        group: group,
        result: result,
        stamp: now,
        includeSnapshot: false,
      );
      if (failure != null) {
        await _keepGapWithError(group.id, failure.message);
        return Left(failure);
      }
      try {
        if (result.archiveChanged || localArchive == null) {
          await _store.writeArchive(groupId, result.archiveText);
        }
        await _store.deleteHeldSnapshot(groupId);
      } catch (e) {
        final f = CacheFailure('Could not save the archive on this phone: $e');
        await _keepGapWithError(group.id, f.message);
        return Left(f);
      }
      await _config.updateGroupState(
        groupId,
        (_) => result.markUploaded(now).copyWith(
              status: GroupSyncStatus.ok,
              lastError: null,
            ),
      );
      return const Right(unit);
    });
  }

  // ------------------------------------------------------------- internals

  /// Waits for any running exclusive section, then runs [body] alone.
  Future<T> _exclusive<T>(Future<T> Function() body) async {
    while (_lockHolder != null) {
      await _lockHolder;
    }
    final done = Completer<void>();
    _lockHolder = done.future;
    try {
      return await body();
    } finally {
      _lockHolder = null;
      done.complete();
    }
  }

  /// Matches an export to a configured group: by `groupId`, else by exact
  /// normalised title (manual shares).
  static ArchivedGroup? matchGroup(
    PendingExport export,
    List<ArchivedGroup> groups,
  ) {
    final id = export.groupId;
    if (id != null) {
      for (final g in groups) {
        if (g.id == id) return g;
      }
    }
    final name = ArchiveConfigService.normalizeName(export.groupName);
    if (name.isEmpty) return null;
    for (final g in groups) {
      if (ArchiveConfigService.normalizeName(g.name) == name) return g;
    }
    return null;
  }

  Future<SyncSummary> _pass() async {
    final List<PendingExport> pending;
    try {
      pending = [...await _bridge.listPendingExports()]
        ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    } catch (e) {
      return SyncSummary(
        at: _now(),
        error: 'Could not read the exported chats from the automation: $e',
      );
    }

    final groups = await _config.groups();
    final blocked = <String>{};
    final outcomes = <ExportOutcome>[];

    for (final export in pending) {
      final matched = matchGroup(export, groups);
      if (matched == null) {
        outcomes.add(
          ExportOutcome(
            jobId: export.jobId,
            groupId: export.groupId,
            groupName: export.groupName,
            kind: ExportOutcomeKind.unmatched,
            message:
                'No configured group is called "${export.groupName}". Add a group with exactly this title.',
          ),
        );
        continue;
      }
      if (blocked.contains(matched.id)) {
        outcomes.add(
          ExportOutcome(
            jobId: export.jobId,
            groupId: matched.id,
            groupName: matched.name,
            kind: ExportOutcomeKind.deferred,
            message: 'Waiting for an earlier export of this group.',
          ),
        );
        continue;
      }
      // Fresh state: an earlier export in this pass may have changed it.
      final group = await _config.groupById(matched.id) ?? matched;
      final outcome = await _processOne(export, group);
      outcomes.add(outcome);
      if (outcome.kind == ExportOutcomeKind.failed) blocked.add(group.id);
    }

    await _applyRunReport(
      allOk: outcomes.every((o) => !o.isProblem),
    );
    return SyncSummary(at: _now(), outcomes: outcomes);
  }

  Future<ExportOutcome> _processOne(
    PendingExport export,
    ArchivedGroup group,
  ) async {
    ExportOutcome failed(String message, {bool authProblem = false}) =>
        ExportOutcome(
          jobId: export.jobId,
          groupId: group.id,
          groupName: group.name,
          kind: ExportOutcomeKind.failed,
          message: message,
          authProblem: authProblem,
        );

    // 1. Read the export.
    final List<int> bytes;
    try {
      bytes = await _store.readExportBytes(export.filePath);
    } on ExportFileMissingException {
      // Nothing can ever be retried: clear the dangling record.
      const msg = 'The exported file was missing on the phone. Run Sync now again.';
      await _markFailed(group.id, msg);
      await _tryAck(export.jobId);
      return failed(msg);
    } catch (e) {
      final msg = 'Could not read the exported file: $e';
      await _markFailed(group.id, msg);
      return failed(msg);
    }

    // 2. Local archive (or restore from Drive when it is missing).
    String? localArchive;
    try {
      localArchive = await _store.readArchive(group.id);
    } catch (e) {
      final msg = 'Could not read the archive on this phone: $e';
      await _markFailed(group.id, msg);
      return failed(msg);
    }
    var baseArchive = localArchive;
    if (baseArchive == null) {
      final restored = await _drive.fetchText(
        folderSegments: DriveLayout.groupFolderSegments(group.name, group.id),
        fileName: DriveLayout.archiveFileName,
      );
      final restoreFailure = restored.leftOrNull;
      if (restoreFailure != null) {
        await _markFailed(group.id, restoreFailure.message);
        return failed(
          restoreFailure.message,
          authProblem: restoreFailure is AuthFailure,
        );
      }
      baseArchive = restored.rightOrNull;
    }
    final archiveMessages = TranscriptParser.parse(baseArchive ?? '');

    // 3. Merge.
    final processed = _process(
      ProcessExportParams(
        group: group,
        archiveMessages: archiveMessages,
        exportBytes: bytes,
        fileName: export.fileName,
        mimeType: export.mimeType,
      ),
    );
    final processFailure = processed.leftOrNull;
    if (processFailure != null) {
      final msg = 'The export could not be read: ${processFailure.message}';
      await _markFailed(group.id, msg);
      return failed(msg);
    }
    final result = processed.rightOrNull!;

    // 4. Uploads: snapshot, update, archive.txt.
    final failure = await _uploadDelta(
      group: group,
      result: result,
      stamp: export.receivedAt,
      includeSnapshot: true,
    );
    if (failure != null) {
      await _markFailed(group.id, failure.message);
      return failed(failure.message, authProblem: failure is AuthFailure);
    }

    // 5. Only now touch local state.
    final isGap = result.merge.status == MergeStatus.gap;
    try {
      if (result.archiveChanged || localArchive == null) {
        await _store.writeArchive(group.id, result.archiveText);
      }
      if (isGap) {
        await _store.writeHeldSnapshot(group.id, result.snapshotText);
      } else {
        await _store.deleteHeldSnapshot(group.id);
      }
    } catch (e) {
      final msg = 'Uploaded to Drive, but could not save on this phone: $e';
      await _markFailed(group.id, msg);
      return failed(msg);
    }
    final now = _now();
    await _config.updateGroupState(group.id, (_) => result.markUploaded(now));
    await _tryAck(export.jobId);

    return ExportOutcome(
      jobId: export.jobId,
      groupId: group.id,
      groupName: group.name,
      kind: isGap
          ? ExportOutcomeKind.gapHeld
          : (result.merge.status == MergeStatus.noChange
              ? ExportOutcomeKind.noChange
              : ExportOutcomeKind.uploaded),
      appended: result.appendedMessages.length,
      message: isGap ? result.pendingGroupUpdate.lastError : null,
    );
  }

  /// Uploads in the required order. Returns the first failure, or null.
  Future<Failure?> _uploadDelta({
    required ArchivedGroup group,
    required ProcessExportResult result,
    required DateTime stamp,
    required bool includeSnapshot,
  }) async {
    if (includeSnapshot) {
      final r = await _drive.upsertText(
        folderSegments: DriveLayout.snapshotsFolderSegments(
          group.name,
          group.id,
        ),
        fileName: DriveLayout.snapshotFileName(stamp),
        content: result.snapshotText,
      );
      final f = r.leftOrNull;
      if (f != null) return f;
    }
    if (result.hasUpdate) {
      final r = await _drive.upsertText(
        folderSegments: DriveLayout.updatesFolderSegments(group.name, group.id),
        fileName: DriveLayout.updateFileName(stamp),
        content: result.updateText,
      );
      final f = r.leftOrNull;
      if (f != null) return f;
    }
    if (result.archiveChanged) {
      final r = await _drive.upsertText(
        folderSegments: DriveLayout.groupFolderSegments(group.name, group.id),
        fileName: DriveLayout.archiveFileName,
        content: result.archiveText,
        cacheFileId: true,
      );
      final f = r.leftOrNull;
      if (f != null) return f;
    }
    return null;
  }

  /// A failed "accept baseline" keeps the group in `gap` (so the action
  /// stays available) and only records why it failed.
  Future<void> _keepGapWithError(String groupId, String message) {
    return _config.updateGroupState(
      groupId,
      (cur) => cur.copyWith(lastError: 'Could not accept the snapshot: $message'),
    );
  }

  Future<void> _markFailed(String groupId, String message) {
    return _config.updateGroupState(
      groupId,
      (cur) => cur.copyWith(status: GroupSyncStatus.failed, lastError: message),
    );
  }

  /// Acknowledging is best effort: if it fails the export stays pending and
  /// the next pass finds `noChange`.
  Future<void> _tryAck(String jobId) async {
    try {
      await _bridge.ackExport(jobId);
    } catch (_) {}
  }

  /// Reflects the native run's per-group failures on the groups (after the
  /// exports of that run were processed, so they do not overwrite each
  /// other).
  Future<void> _applyRunReport({required bool allOk}) async {
    final RunReport? report;
    try {
      report = await _bridge.getLastRunReport();
    } catch (_) {
      return;
    }
    if (report == null || report.finishedAt == null) return;
    if (report.runId == _config.settings.lastAppliedRunId) return;

    for (final r in report.results) {
      if (r.status != GroupRunStatus.failed) continue;
      final code = r.error ?? 'unknown';
      final status = AutomationErrorCodes.needsAttention.contains(code)
          ? GroupSyncStatus.needsAttention
          : GroupSyncStatus.failed;
      await _config.updateGroupState(r.groupId, (cur) {
        // A held-back gap is the more important thing to show.
        if (cur.status == GroupSyncStatus.gap) return cur;
        return cur.copyWith(status: status, lastError: code);
      });
    }
    await _config.settings.setLastAppliedRunId(report.runId);
    if (allOk && report.failedCount == 0 && report.exportedCount > 0) {
      await _state.saveLastSuccessfulRunDate(
        RunPolicy.dateKey(report.finishedAt!),
      );
    }
  }

  void dispose() => _summaries.close();
}

extension _EitherX<L, R> on Either<L, R> {
  L? get leftOrNull => fold((l) => l, (_) => null);
  R? get rightOrNull => fold((_) => null, (r) => r);
}
