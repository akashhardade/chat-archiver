import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_merger.dart';
import 'package:chat_archiver/feature/archive/domain/usecases/process_export_usecase.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import 'archive_test_helpers.dart';

const day1 = '12/03/2026, 14:05 - Alice: hi\n'
    '12/03/2026, 14:06 - Bob: yo\nsecond line\n';
const day2 = '$day1'
    '13/03/2026, 09:00 - Alice: morning\n'
    '13/03/2026, 09:01 - Bob: hey\n';

const testGroup = ArchivedGroup(id: 'g1', name: 'Book Club');
const useCase = ProcessExportUseCase();

ProcessExportResult ok(Either<Failure, ProcessExportResult> r) =>
    r.fold((l) => fail('unexpected failure: ${l.message}'), (v) => v);

void main() {
  test('first run: initial, full archive, update equals archive', () {
    final r = ok(useCase(ProcessExportParams(
      group: testGroup,
      archiveMessages: const [],
      exportBytes: utf8.encode(day1),
    )));
    expect(r.merge.status, MergeStatus.initial);
    expect(r.archiveText, day1);
    expect(r.updateText, day1);
    expect(r.snapshotText, day1);
    expect(r.archiveChanged, isTrue);
    expect(r.hasUpdate, isTrue);
    expect(r.pendingGroupUpdate.status, GroupSyncStatus.ok);
    expect(r.pendingGroupUpdate.messageCount, 2);
    expect(r.pendingGroupUpdate.lastMessageKey, r.mergedMessages.last.key);
    expect(r.pendingGroupUpdate.lastSuccessAt, isNull,
        reason: 'only set by markUploaded');
  });

  test('second day: appended, delta contains only new messages', () {
    final r = ok(useCase(ProcessExportParams(
      group: testGroup,
      archiveMessages: parse(day1),
      exportBytes: utf8.encode(day2),
    )));
    expect(r.merge.status, MergeStatus.appended);
    expect(r.updateText,
        '13/03/2026, 09:00 - Alice: morning\n13/03/2026, 09:01 - Bob: hey\n');
    expect(r.archiveText, day2);
    expect(r.snapshotText, day2);
    expect(r.pendingGroupUpdate.messageCount, 4);
  });

  test('re-running with the same export: noChange, empty delta', () {
    final r = ok(useCase(ProcessExportParams(
      group: testGroup,
      archiveMessages: parse(day2),
      exportBytes: utf8.encode(day2),
    )));
    expect(r.merge.status, MergeStatus.noChange);
    expect(r.updateText, '');
    expect(r.hasUpdate, isFalse);
    expect(r.archiveChanged, isFalse);
    expect(r.archiveText, day2);
    expect(r.pendingGroupUpdate.status, GroupSyncStatus.ok);
    expect(r.pendingGroupUpdate.messageCount, 4);
  });

  test('accepts zipped exports and CRLF/BOM', () {
    final zipped = Archive()
      ..addFile(ArchiveFile('WhatsApp Chat with Book Club.txt', 0,
          utf8.encode('$bom${day2.replaceAll('\n', '\r\n')}')));
    final r = ok(useCase(ProcessExportParams(
      group: testGroup,
      archiveMessages: parse(day1),
      exportBytes: ZipEncoder().encode(zipped),
      fileName: 'WhatsApp Chat with Book Club.zip',
    )));
    expect(r.merge.status, MergeStatus.appended);
    expect(r.archiveText, day2);
    expect(r.snapshotText.contains(bom), isFalse);
  });

  test('markUploaded sets lastSuccessAt and keeps computed state', () {
    final r = ok(useCase(ProcessExportParams(
      group: testGroup,
      archiveMessages: parse(day1),
      exportBytes: utf8.encode(day2),
    )));
    final now = DateTime(2026, 3, 13, 9, 5);
    final done = r.markUploaded(now);
    expect(done.lastSuccessAt, now);
    expect(done.status, GroupSyncStatus.ok);
    expect(done.messageCount, 4);
    expect(done.lastMessageKey, r.pendingGroupUpdate.lastMessageKey);
    expect(r.pendingGroupUpdate.lastSuccessAt, isNull,
        reason: 'original pending update untouched');
  });

  test('previous error is cleared on a successful run', () {
    final failed = testGroup.copyWith(
        status: GroupSyncStatus.failed, lastError: 'export timed out');
    final r = ok(useCase(ProcessExportParams(
      group: failed,
      archiveMessages: parse(day1),
      exportBytes: utf8.encode(day2),
    )));
    expect(r.pendingGroupUpdate.status, GroupSyncStatus.ok);
    expect(r.pendingGroupUpdate.lastError, isNull);
  });

  group('gap', () {
    const unrelated = '01/01/2025, 10:00 - Zed: totally different\n'
        '01/01/2025, 10:01 - Zed: chat\n';

    test('default holdBack leaves archive unchanged but returns snapshot', () {
      final r = ok(useCase(ProcessExportParams(
        group: testGroup.copyWith(messageCount: 2),
        archiveMessages: parse(day1),
        exportBytes: utf8.encode(unrelated),
      )));
      expect(r.merge.status, MergeStatus.gap);
      expect(r.archiveChanged, isFalse);
      expect(r.archiveText, day1);
      expect(r.updateText, '');
      expect(r.snapshotText, unrelated);
      expect(r.pendingGroupUpdate.status, GroupSyncStatus.gap);
      expect(r.pendingGroupUpdate.messageCount, 2);
      expect(r.pendingGroupUpdate.lastError, isNotNull);
      expect(r.merge.newMessages, hasLength(2));
    });

    test('appendSnapshot appends everything', () {
      final r = ok(useCase(ProcessExportParams(
        group: testGroup,
        archiveMessages: parse(day1),
        exportBytes: utf8.encode(unrelated),
        onGap: GapPolicy.appendSnapshot,
      )));
      expect(r.merge.status, MergeStatus.gap);
      expect(r.archiveText, '$day1$unrelated');
      expect(r.updateText, unrelated);
      expect(r.pendingGroupUpdate.status, GroupSyncStatus.gap);
      expect(r.pendingGroupUpdate.messageCount, 4);
    });

    test('markUploaded on a gap keeps gap status and error', () {
      final r = ok(useCase(ProcessExportParams(
        group: testGroup,
        archiveMessages: parse(day1),
        exportBytes: utf8.encode(unrelated),
      )));
      final done = r.markUploaded(DateTime(2026, 3, 13));
      expect(done.status, GroupSyncStatus.gap);
      expect(done.lastError, isNotNull);
      expect(done.lastSuccessAt, DateTime(2026, 3, 13));
    });
  });

  group('failures', () {
    test('empty bytes -> ValidationFailure', () {
      final r = useCase(ProcessExportParams(
          group: testGroup, archiveMessages: const [], exportBytes: const []));
      expect(r.isLeft(), isTrue);
      r.fold((l) => expect(l, isA<ValidationFailure>()), (_) => fail('x'));
    });

    test('zip without txt -> ValidationFailure', () {
      final z = Archive()..addFile(ArchiveFile('a.jpg', 3, [1, 2, 3]));
      final r = useCase(ProcessExportParams(
          group: testGroup,
          archiveMessages: const [],
          exportBytes: ZipEncoder().encode(z)));
      r.fold((l) => expect(l, isA<ValidationFailure>()), (_) => fail('x'));
    });

    test('text without any message -> ValidationFailure', () {
      final r = useCase(ProcessExportParams(
          group: testGroup,
          archiveMessages: parse(day1),
          exportBytes: utf8.encode('\n\n   \n')));
      expect(r.isLeft(), isTrue);
    });
  });
}
