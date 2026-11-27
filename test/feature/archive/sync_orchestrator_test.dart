import 'dart:async';
import 'dart:io';

import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/archive/data/local_archive_store.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_config_service.dart';
import 'package:chat_archiver/feature/archive/domain/services/drive_layout.dart';
import 'package:chat_archiver/feature/archive/domain/usecases/sync_orchestrator.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_errors.dart';
import 'package:chat_archiver/feature/automation/domain/entities/pending_export.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_report.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

const day1 = '12/03/2026, 14:05 - Alice: hi\n'
    '12/03/2026, 14:06 - Bob: yo\nsecond line\n';
const day2 = '$day1'
    '13/03/2026, 09:00 - Alice: morning\n'
    '13/03/2026, 09:01 - Bob: hey\n';
const day2Delta = '13/03/2026, 09:00 - Alice: morning\n'
    '13/03/2026, 09:01 - Bob: hey\n';
const unrelated = '01/01/2025, 08:00 - Zed: something else\n'
    '01/01/2025, 08:01 - Yan: entirely different\n'
    '01/01/2025, 08:02 - Zed: chat\n';

void main() {
  late Directory tmp;
  late FakeAutomationBridge bridge;
  late FakeDriveGateway drive;
  late FakeStateRepository state;
  late ArchiveConfigService config;
  late LocalArchiveStore store;
  late SyncOrchestrator orchestrator;
  late DateTime clock;
  var jobCounter = 0;
  var idCounter = 0;

  Future<PendingExport> addExport(
    String text, {
    String? groupId,
    String groupName = 'Book Club',
    DateTime? receivedAt,
    String? jobId,
  }) async {
    jobCounter++;
    final file = File('${tmp.path}/export_$jobCounter.txt');
    await file.writeAsString(text);
    final e = PendingExport(
      jobId: jobId ?? 'job$jobCounter',
      groupId: groupId,
      groupName: groupName,
      filePath: file.path,
      fileName: 'WhatsApp Chat with $groupName.txt',
      mimeType: 'text/plain',
      receivedAt: receivedAt ?? DateTime(2026, 3, 12, 14, 30, jobCounter),
      trigger: ExportTrigger.unlock,
    );
    bridge.pending.add(e);
    return e;
  }

  Future<ArchivedGroup> addGroup(String name) async {
    final r = await config.addGroup(name);
    return r.fold((f) => fail(f.message), (g) => g);
  }

  Future<ArchivedGroup> stored(String id) async =>
      (await config.groupById(id))!;

  String archivePath(ArchivedGroup g) => FakeDriveGateway.pathOf(
        DriveLayout.groupFolderSegments(g.name, g.id),
        DriveLayout.archiveFileName,
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('orchestrator_test');
    bridge = FakeAutomationBridge();
    drive = FakeDriveGateway();
    state = FakeStateRepository();
    jobCounter = 0;
    idCounter = 0;
    clock = DateTime(2026, 3, 13, 9, 30);
    config = ArchiveConfigService(
      state: state,
      settings: state,
      bridge: bridge,
      idGenerator: () => 'g${++idCounter}',
    );
    store = LocalArchiveStore(tmp);
    orchestrator = SyncOrchestrator(
      bridge: bridge,
      drive: drive,
      config: config,
      state: state,
      store: store,
      now: () => clock,
    );
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('happy path', () {
    test('initial export: snapshot, update, archive uploaded, then acked',
        () async {
      final g = await addGroup('Book Club');
      final e = await addExport(day1, groupId: g.id);

      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.uploaded);
      expect(summary.hasProblems, isFalse);
      final stamp = DriveLayout.timestampKey(e.receivedAt);
      expect(drive.uploadLog, [
        'WhatsApp Archive/Book Club/snapshots/$stamp.txt',
        'WhatsApp Archive/Book Club/updates/${stamp}_new.txt',
        'WhatsApp Archive/Book Club/archive.txt',
      ], reason: 'order: snapshot, update, archive.txt');
      expect(drive.files[archivePath(g)], day1);
      expect(await store.readArchive(g.id), day1);
      expect(bridge.acked, [e.jobId]);
      final s = await stored(g.id);
      expect(s.status, GroupSyncStatus.ok);
      expect(s.messageCount, 2);
      expect(s.lastSuccessAt, clock);
      expect(s.lastError, isNull);
      expect(bridge.pending, isEmpty);
    });

    test('next day: only the delta goes to updates/, archive.txt is overwritten',
        () async {
      final g = await addGroup('Book Club');
      await addExport(day1, groupId: g.id);
      await orchestrator.processPending();
      drive.uploadLog.clear();

      final e2 = await addExport(day2, groupId: g.id);
      clock = DateTime(2026, 3, 14, 9, 30);
      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.uploaded);
      expect(summary.outcomes.single.appended, 2);
      final stamp = DriveLayout.timestampKey(e2.receivedAt);
      expect(
        drive.files['WhatsApp Archive/Book Club/updates/${stamp}_new.txt'],
        day2Delta,
      );
      expect(
        drive.files['WhatsApp Archive/Book Club/snapshots/$stamp.txt'],
        day2,
      );
      expect(drive.files[archivePath(g)], day2);
      expect(await store.readArchive(g.id), day2);
      expect((await stored(g.id)).messageCount, 4);
      expect(bridge.acked, hasLength(2));
    });

    test('same snapshot again: noChange, no update file, archive untouched',
        () async {
      final g = await addGroup('Book Club');
      await addExport(day1, groupId: g.id);
      await orchestrator.processPending();
      drive.uploadLog.clear();

      final e = await addExport(day1, groupId: g.id);
      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.noChange);
      final stamp = DriveLayout.timestampKey(e.receivedAt);
      expect(drive.uploadLog, [
        'WhatsApp Archive/Book Club/snapshots/$stamp.txt',
      ]);
      expect(bridge.acked, hasLength(2));
    });

    test('config changes are pushed to native', () async {
      await addGroup('Book Club');
      await config.setMorningHour(9);
      await config.setAutomationEnabled(false);
      final last = bridge.savedConfigs.last;
      expect(last.morningHour, 9);
      expect(last.enabled, isFalse);
      expect(last.groups.single.name, 'Book Club');
      expect(last.groups.single.enabled, isTrue);
      expect(bridge.savedConfigs.length, 3);
    });

    test('automatic runs stay off until the setup wizard is finished',
        () async {
      await addGroup('Book Club');
      expect(bridge.savedConfigs.last.enabled, isFalse);

      await state.setSetupComplete(true);
      await config.pushConfig();
      expect(bridge.savedConfigs.last.enabled, isTrue);

      await config.setAutomationEnabled(false);
      expect(bridge.savedConfigs.last.enabled, isFalse);
    });
  });

  group('upload failure and retry', () {
    test('failure keeps the export pending and the local archive unchanged',
        () async {
      final g = await addGroup('Book Club');
      await addExport(day1, groupId: g.id);
      await orchestrator.processPending();
      expect(await store.readArchive(g.id), day1);

      final e2 = await addExport(day2, groupId: g.id);
      drive.failWith = const NetworkFailure('offline');
      drive.failWhen = (p) => p.endsWith('archive.txt');
      clock = DateTime(2026, 3, 14, 9, 30);
      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.failed);
      expect(summary.hasProblems, isTrue);
      expect(bridge.acked, hasLength(1), reason: 'second export not acked');
      expect(bridge.pending.single.jobId, e2.jobId);
      expect(await store.readArchive(g.id), day1,
          reason: 'local archive must not advance before Drive confirmed');
      expect(drive.files[archivePath(g)], day1);
      final s = await stored(g.id);
      expect(s.status, GroupSyncStatus.failed);
      expect(s.lastError, 'offline');
      expect(s.messageCount, 2, reason: 'counts only change on success');
    });

    test('a failing group does not stop the others', () async {
      final a = await addGroup('Alpha');
      final b = await addGroup('Beta');
      final ea = await addExport(day1, groupId: a.id, groupName: 'Alpha');
      final eb = await addExport(day1, groupId: b.id, groupName: 'Beta');
      drive.failWith = const QuotaFailure('Drive full');
      drive.failWhen = (p) => p.contains('/Alpha/');

      final summary = await orchestrator.processPending();

      final byJob = {for (final o in summary.outcomes) o.jobId: o};
      expect(byJob[ea.jobId]!.kind, ExportOutcomeKind.failed);
      expect(byJob[eb.jobId]!.kind, ExportOutcomeKind.uploaded);
      expect(bridge.acked, [eb.jobId]);
      expect((await stored(a.id)).status, GroupSyncStatus.failed);
      expect((await stored(b.id)).status, GroupSyncStatus.ok);
    });

    test('retry after failure is idempotent: no duplicates, no loss', () async {
      final g = await addGroup('Book Club');
      await addExport(day1, groupId: g.id);
      // Fail the very last upload: snapshot + update already went through.
      drive.failWith = const NetworkFailure('offline');
      drive.failWhen = (p) => p.endsWith('archive.txt');
      await orchestrator.processPending();
      expect(await store.readArchive(g.id), isNull);
      expect(bridge.acked, isEmpty);
      final filesAfterFailure = drive.files.keys.toSet();

      drive.failWith = null;
      drive.failWhen = null;
      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.uploaded);
      expect(drive.files.keys.toSet(), {
        ...filesAfterFailure,
        archivePath(g),
      }, reason: 'same snapshot/update names are overwritten, not duplicated');
      expect(drive.files[archivePath(g)], day1);
      expect(await store.readArchive(g.id), day1);
      expect(bridge.acked, hasLength(1));
      expect((await stored(g.id)).status, GroupSyncStatus.ok);
      expect((await stored(g.id)).messageCount, 2);
    });

    test('ack failure: next pass finds noChange and does not duplicate',
        () async {
      final g = await addGroup('Book Club');
      final e = await addExport(day1, groupId: g.id);
      bridge.failAck = true;
      await orchestrator.processPending();
      expect(bridge.pending, hasLength(1));

      bridge.failAck = false;
      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.noChange);
      expect(drive.files[archivePath(g)], day1);
      expect((await stored(g.id)).messageCount, 2);
      expect(bridge.acked, [e.jobId]);
    });

    test('an older failing export blocks newer ones of the same group',
        () async {
      final g = await addGroup('Book Club');
      final old = await addExport(
        day1,
        groupId: g.id,
        receivedAt: DateTime(2026, 3, 12, 9),
      );
      final newer = await addExport(
        day2,
        groupId: g.id,
        receivedAt: DateTime(2026, 3, 13, 9),
      );
      drive.failWith = const NetworkFailure('offline');

      final summary = await orchestrator.processPending();

      final byJob = {for (final o in summary.outcomes) o.jobId: o};
      expect(byJob[old.jobId]!.kind, ExportOutcomeKind.failed);
      expect(byJob[newer.jobId]!.kind, ExportOutcomeKind.deferred);
      expect(bridge.pending, hasLength(2));

      drive.failWith = null;
      final retry = await orchestrator.processPending();
      expect(retry.outcomes.map((o) => o.kind), [
        ExportOutcomeKind.uploaded,
        ExportOutcomeKind.uploaded,
      ]);
      expect(drive.files[archivePath(g)], day2);
      expect((await stored(g.id)).messageCount, 4);
    });

    test('missing local archive is restored from Drive, never overwritten',
        () async {
      final g = await addGroup('Book Club');
      drive.files[archivePath(g)] = day1; // history from before a reinstall
      await addExport(day2, groupId: g.id);

      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.uploaded);
      expect(summary.outcomes.single.appended, 2);
      final updates = drive.files.entries
          .firstWhere((e) => e.key.contains('/updates/'))
          .value;
      expect(updates, day2Delta);
      expect(drive.files[archivePath(g)], day2);
      expect(await store.readArchive(g.id), day2);
    });

    test('exported file gone: group marked failed, dangling record acked',
        () async {
      final g = await addGroup('Book Club');
      final e = await addExport(day1, groupId: g.id);
      await File(e.filePath).delete();

      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.failed);
      expect(bridge.acked, [e.jobId]);
      expect((await stored(g.id)).status, GroupSyncStatus.failed);
    });

    test('unreadable export is kept pending and reported', () async {
      final g = await addGroup('Book Club');
      await addExport('   \n', groupId: g.id);

      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.failed);
      expect(bridge.pending, hasLength(1));
      expect(drive.uploadLog, isEmpty);
    });
  });

  group('gap', () {
    test('held back: snapshot only, group gap, acked; then accepted as baseline',
        () async {
      final g = await addGroup('Book Club');
      await addExport(day1, groupId: g.id);
      await orchestrator.processPending();
      drive.uploadLog.clear();

      final e2 = await addExport(unrelated, groupId: g.id);
      clock = DateTime(2026, 3, 14, 9);
      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.gapHeld);
      final stamp = DriveLayout.timestampKey(e2.receivedAt);
      expect(drive.uploadLog, [
        'WhatsApp Archive/Book Club/snapshots/$stamp.txt',
      ], reason: 'snapshot only');
      expect(drive.files[archivePath(g)], day1);
      expect(await store.readArchive(g.id), day1);
      expect(await store.readHeldSnapshot(g.id), unrelated);
      expect(bridge.acked, contains(e2.jobId));
      final held = await stored(g.id);
      expect(held.status, GroupSyncStatus.gap);
      expect(held.messageCount, 2);

      // The user accepts the snapshot as the new baseline.
      clock = DateTime(2026, 3, 14, 10);
      final result = await orchestrator.acceptSnapshotAsBaseline(g.id);

      expect(result.isRight(), isTrue);
      expect(drive.files[archivePath(g)], '$day1$unrelated');
      expect(await store.readArchive(g.id), '$day1$unrelated');
      expect(await store.readHeldSnapshot(g.id), isNull);
      final accepted = await stored(g.id);
      expect(accepted.status, GroupSyncStatus.ok);
      expect(accepted.lastError, isNull);
      expect(accepted.messageCount, 5);
      expect(accepted.lastSuccessAt, clock);
      expect(drive.files.keys.where((k) => k.contains('/updates/')), hasLength(2));
    });

    test('accept without a held snapshot is rejected', () async {
      final g = await addGroup('Book Club');
      final r = await orchestrator.acceptSnapshotAsBaseline(g.id);
      expect(r.isLeft(), isTrue);
    });

    test('failed accept keeps the held snapshot and the gap state', () async {
      final g = await addGroup('Book Club');
      await addExport(day1, groupId: g.id);
      await orchestrator.processPending();
      await addExport(unrelated, groupId: g.id);
      await orchestrator.processPending();

      drive.failWith = const NetworkFailure('offline');
      final r = await orchestrator.acceptSnapshotAsBaseline(g.id);

      expect(r.isLeft(), isTrue);
      expect(await store.readHeldSnapshot(g.id), unrelated);
      expect(await store.readArchive(g.id), day1);
      expect((await stored(g.id)).status, GroupSyncStatus.gap,
          reason: 'stays gap so the action remains available');
      expect((await stored(g.id)).lastError, contains('offline'));

      drive.failWith = null;
      final retry = await orchestrator.acceptSnapshotAsBaseline(g.id);
      expect(retry.isRight(), isTrue);
      expect(await store.readArchive(g.id), '$day1$unrelated');
    });
  });

  group('matching', () {
    test('unmatched manual share stays pending and is surfaced', () async {
      await addGroup('Book Club');
      final e = await addExport(day1, groupName: 'Some Other Group');

      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.unmatched);
      expect(summary.hasProblems, isTrue);
      expect(bridge.pending.single.jobId, e.jobId);
      expect(bridge.acked, isEmpty);
      expect(drive.uploadLog, isEmpty);
      final inspected = await orchestrator.inspectPending();
      expect(inspected.single.isUnmatched, isTrue);
    });

    test('manual share matches by normalised exact name once configured',
        () async {
      await addGroup('Book Club');
      // Extra / odd whitespace in the parsed name still matches.
      final e = await addExport(
        day1,
        groupName: '  Book${String.fromCharCode(0x00A0)}Club ',
      );

      final summary = await orchestrator.processPending();

      expect(summary.outcomes.single.kind, ExportOutcomeKind.uploaded);
      expect(bridge.acked, [e.jobId]);
    });

    test('name match is exact: a longer title does not match', () async {
      await addGroup('Book Club');
      await addExport(day1, groupName: 'Book Club 2');
      final summary = await orchestrator.processPending();
      expect(summary.outcomes.single.kind, ExportOutcomeKind.unmatched);
    });

    test('unknown groupId falls back to the name', () async {
      final g = await addGroup('Book Club');
      await addExport(day1, groupId: 'deleted-id', groupName: 'Book Club');
      final summary = await orchestrator.processPending();
      expect(summary.outcomes.single.groupId, g.id);
      expect(summary.outcomes.single.kind, ExportOutcomeKind.uploaded);
    });
  });

  group('concurrency', () {
    test('overlapping calls are coalesced into one in-flight pass', () async {
      final g = await addGroup('Book Club');
      await addExport(day1, groupId: g.id);
      final gate = Completer<void>();
      drive.gate = gate;

      final first = orchestrator.processPending();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(orchestrator.isProcessing, isTrue);
      final second = orchestrator.processPending();
      final third = orchestrator.processPending();
      expect(identical(first, second), isTrue);
      expect(identical(first, third), isTrue);

      gate.complete();
      await Future.wait([first, second, third]);

      expect(drive.maxConcurrent, 1);
      expect(bridge.acked, hasLength(1));
      // The first pass uploaded 3 files; the follow-up pass (requested while
      // busy) found nothing pending and uploaded nothing more.
      expect(drive.uploadLog, hasLength(3));
      expect(orchestrator.isProcessing, isFalse);
    });

    test('an export arriving during a pass is picked up by the follow-up',
        () async {
      final a = await addGroup('Alpha');
      final b = await addGroup('Beta');
      await addExport(day1, groupId: a.id, groupName: 'Alpha');
      final gate = Completer<void>();
      drive.gate = gate;

      final first = orchestrator.processPending();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await addExport(day1, groupId: b.id, groupName: 'Beta');
      final second = orchestrator.processPending();
      gate.complete();
      final summary = await second;
      await first;

      expect(bridge.pending, isEmpty);
      expect(summary.outcomes, hasLength(2));
      expect(drive.maxConcurrent, 1);
    });

    test('accept waits for a running pass', () async {
      final g = await addGroup('Book Club');
      await addExport(day1, groupId: g.id);
      final gate = Completer<void>();
      drive.gate = gate;
      final pass = orchestrator.processPending();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final accept = orchestrator.acceptSnapshotAsBaseline(g.id);
      gate.complete();
      await pass;
      final r = await accept;

      expect(r.isLeft(), isTrue, reason: 'nothing held for this group');
      expect(drive.maxConcurrent, 1);
    });
  });

  group('native run report', () {
    RunReport report(String id, List<GroupRunResult> results) => RunReport(
          runId: id,
          trigger: 'manual',
          startedAt: DateTime(2026, 3, 13, 9),
          finishedAt: DateTime(2026, 3, 13, 9, 1),
          results: results,
        );

    test('native failures are reflected on the groups once', () async {
      final a = await addGroup('Alpha');
      final b = await addGroup('Beta');
      bridge.lastReport = report('run1', [
        GroupRunResult(
          groupId: a.id,
          groupName: 'Alpha',
          status: GroupRunStatus.failed,
          error: AutomationErrorCodes.groupNotFound,
        ),
        GroupRunResult(
          groupId: b.id,
          groupName: 'Beta',
          status: GroupRunStatus.failed,
          error: AutomationErrorCodes.timeout,
        ),
      ]);

      await orchestrator.processPending();

      expect((await stored(a.id)).status, GroupSyncStatus.needsAttention);
      expect((await stored(a.id)).lastError, 'group_not_found');
      expect((await stored(b.id)).status, GroupSyncStatus.failed);
      expect(state.lastAppliedRunId, 'run1');

      // Applied only once: a later success is not overwritten again.
      await addExport(day1, groupId: a.id, groupName: 'Alpha');
      await orchestrator.processPending();
      expect((await stored(a.id)).status, GroupSyncStatus.ok);
    });
  });
}
