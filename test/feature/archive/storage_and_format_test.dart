import 'dart:io';

import 'package:chat_archiver/core/storage/key_value_store.dart';
import 'package:chat_archiver/core/utils/time_format.dart';
import 'package:chat_archiver/feature/archive/data/archive_state_repository_impl.dart';
import 'package:chat_archiver/feature/archive/data/local_archive_store.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_file_store.dart';
import 'package:chat_archiver/feature/drive/data/drive_id_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArchiveStateRepositoryImpl', () {
    late MemoryKeyValueStore store;
    late ArchiveStateRepositoryImpl repo;

    setUp(() {
      store = MemoryKeyValueStore();
      repo = ArchiveStateRepositoryImpl(store);
    });

    test('groups round trip through storage', () async {
      expect((await repo.loadGroups()).getOrElse(() => fail('x')), isEmpty);
      final groups = [
        const ArchivedGroup(id: 'g1', name: 'Book Club \u{1F4DA}'),
        ArchivedGroup(
          id: 'g2',
          name: 'Family',
          enabled: false,
          lastSuccessAt: DateTime.utc(2026, 3, 12, 9),
          messageCount: 42,
          status: GroupSyncStatus.gap,
          lastError: 'x',
          lastMessageKey: 'k',
        ),
      ];
      expect((await repo.saveGroups(groups)).isRight(), isTrue);

      final loaded = (await repo.loadGroups()).getOrElse(() => fail('x'));
      expect(loaded, groups);
    });

    test('corrupt groups JSON yields a CacheFailure, not a crash', () async {
      await store.write('archive_groups_v1', '{"not":"a list"}');
      expect((await repo.loadGroups()).isLeft(), isTrue);
    });

    test('settings defaults and persistence', () async {
      expect(repo.morningHour, 7);
      expect(repo.automationEnabled, isTrue);
      expect(repo.setupComplete, isFalse);
      expect(repo.disclosureAccepted, isFalse);
      expect(repo.lastAppliedRunId, isNull);

      await repo.setMorningHour(9);
      await repo.setAutomationEnabled(false);
      await repo.setSetupComplete(true);
      await repo.setDisclosureAccepted(true);
      await repo.setLastAppliedRunId('r1');
      await repo.saveLastSuccessfulRunDate('2026-03-12');

      final again = ArchiveStateRepositoryImpl(store);
      expect(again.morningHour, 9);
      expect(again.automationEnabled, isFalse);
      expect(again.setupComplete, isTrue);
      expect(again.disclosureAccepted, isTrue);
      expect(again.lastAppliedRunId, 'r1');
      expect(
        (await again.loadLastSuccessfulRunDate()).getOrElse(() => null),
        '2026-03-12',
      );
    });

    test('morning hour is clamped to 0-23', () async {
      await repo.setMorningHour(99);
      expect(repo.morningHour, 23);
      await store.write('archive_morning_hour', '-3');
      expect(repo.morningHour, 7, reason: 'invalid stored value -> default');
    });
  });

  group('LocalArchiveStore', () {
    late Directory tmp;
    late LocalArchiveStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('local_store_test');
      store = LocalArchiveStore(tmp);
    });
    tearDown(() => tmp.delete(recursive: true));

    test('archive is written atomically and read back (UTF-8, emoji)',
        () async {
      expect(await store.readArchive('g1'), isNull);
      const text = '12/03/2026, 14:05 - Alice: café \u{1F600}\n';
      await store.writeArchive('g1', text);
      expect(await store.readArchive('g1'), text);
      await store.writeArchive('g1', '$text$text');
      expect(await store.readArchive('g1'), '$text$text');

      final names = Directory('${tmp.path}/archives/g1')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .toList();
      expect(names, ['archive.txt'], reason: 'no temp file left behind');
    });

    test('groups are isolated and ids cannot escape the folder', () async {
      await store.writeArchive('../evil', 'x');
      expect(File('${tmp.path}/evil/archive.txt').existsSync(), isFalse);
      expect(await store.readArchive('../evil'), 'x');
      expect(await store.readArchive('g2'), isNull);
    });

    test('held snapshot lifecycle', () async {
      expect(await store.readHeldSnapshot('g1'), isNull);
      await store.writeHeldSnapshot('g1', 'snap');
      expect(await store.readHeldSnapshot('g1'), 'snap');
      await store.deleteHeldSnapshot('g1');
      expect(await store.readHeldSnapshot('g1'), isNull);
      await store.deleteHeldSnapshot('g1'); // idempotent
    });

    test('missing export file is reported', () async {
      await expectLater(
        store.readExportBytes('${tmp.path}/nope.txt'),
        throwsA(isA<ExportFileMissingException>()),
      );
      final f = File('${tmp.path}/e.txt')..writeAsBytesSync([1, 2, 3]);
      expect(await store.readExportBytes(f.path), [1, 2, 3]);
    });
  });

  group('DriveIdCache', () {
    test('storage cache persists and removes subtrees', () async {
      final kv = MemoryKeyValueStore();
      final cache = StorageDriveIdCache(kv);
      await cache.put('a|WhatsApp Archive', '1');
      await cache.put('a|WhatsApp Archive/Family', '2');
      await cache.put('a|WhatsApp Archive/Family2', '3');
      expect(StorageDriveIdCache(kv).get('a|WhatsApp Archive/Family'), '2');

      await cache.removeTree('a|WhatsApp Archive/Family');
      expect(cache.get('a|WhatsApp Archive/Family'), isNull);
      expect(cache.get('a|WhatsApp Archive/Family2'), '3');
      expect(cache.get('a|WhatsApp Archive'), '1');

      await cache.clear();
      expect(StorageDriveIdCache(kv).get('a|WhatsApp Archive'), isNull);
    });
  });

  group('TimeFormat', () {
    final now = DateTime(2026, 3, 13, 12, 0);

    test('relative', () {
      expect(TimeFormat.relative(now.subtract(const Duration(seconds: 20)), now: now),
          'just now');
      expect(TimeFormat.relative(now.subtract(const Duration(minutes: 5)), now: now),
          '5 min ago');
      expect(TimeFormat.relative(now.subtract(const Duration(hours: 3)), now: now),
          '3 h ago');
      expect(TimeFormat.relative(DateTime(2026, 3, 12, 23, 0), now: now),
          'yesterday');
      expect(TimeFormat.relative(DateTime(2026, 3, 10, 9, 0), now: now),
          '3 days ago');
      expect(TimeFormat.relative(DateTime(2026, 1, 2), now: now), contains('2026'));
      expect(TimeFormat.relative(now.add(const Duration(hours: 1)), now: now),
          'just now');
    });

    test('hour', () {
      expect(TimeFormat.hour(0), '12:00 AM');
      expect(TimeFormat.hour(7), '7:00 AM');
      expect(TimeFormat.hour(12), '12:00 PM');
      expect(TimeFormat.hour(23), '11:00 PM');
    });
  });
}
