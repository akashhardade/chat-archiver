import 'dart:io';

import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/drive/data/drive_id_cache.dart';
import 'package:chat_archiver/feature/drive/data/google_drive_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_drive_server.dart';

void main() {
  late FakeDriveServer server;
  late FakeDriveAuth auth;
  late InMemoryDriveIdCache cache;
  late GoogleDriveGateway gateway;

  const segs = ['WhatsApp Archive', 'Book Club'];

  setUp(() {
    server = FakeDriveServer();
    auth = FakeDriveAuth(server.client);
    cache = InMemoryDriveIdCache();
    gateway = GoogleDriveGateway(auth: auth, cache: cache);
  });

  Future<void> put(String name, String content,
      {List<String> folder = segs, bool cacheFileId = false}) async {
    final r = await gateway.upsertText(
      folderSegments: folder,
      fileName: name,
      content: content,
      cacheFileId: cacheFileId,
    );
    r.fold((f) => fail('upload failed: ${f.message}'), (_) {});
  }

  test('creates the folder chain and the file', () async {
    await put('archive.txt', 'hello', cacheFileId: true);

    expect(server.folders.map((f) => f.name), ['WhatsApp Archive', 'Book Club']);
    final file = server.files.single;
    expect(file.name, 'archive.txt');
    expect(file.content, 'hello');
    expect(file.mime, 'text/plain');
    expect(file.parents, [server.find('Book Club')!.id]);
    expect(server.find('Book Club')!.parents, [server.find('WhatsApp Archive')!.id]);
    expect(server.find('WhatsApp Archive')!.parents, ['root']);
  });

  test('second upload overwrites the same file (no duplicate), reuses cache',
      () async {
    await put('archive.txt', 'v1', cacheFileId: true);
    server.requestLog.clear();
    await put('archive.txt', 'v2 full content', cacheFileId: true);

    expect(server.files, hasLength(1));
    expect(server.files.single.content, 'v2 full content');
    expect(server.folders, hasLength(2));
    // Cached path: verify folder (get), update file; no folder searching.
    expect(server.requestLog.where((l) => l.startsWith('GET') && l.endsWith('/files')),
        isEmpty);
  });

  test('uncached file of the same name is found and updated, not duplicated',
      () async {
    await put('2026-03-12_143001.txt', 'snap');
    await put('2026-03-12_143001.txt', 'snap again');
    expect(server.files, hasLength(1));
    expect(server.files.single.content, 'snap again');
  });

  test('files go to the right folders', () async {
    await put('archive.txt', 'a');
    await put('s.txt', 'b', folder: [...segs, 'snapshots']);
    await put('u.txt', 'c', folder: [...segs, 'updates']);
    expect(server.folders.map((f) => f.name),
        ['WhatsApp Archive', 'Book Club', 'snapshots', 'updates']);
    final snapshots = server.find('snapshots')!;
    expect(server.find('s.txt')!.parents, [snapshots.id]);
    expect(server.find('u.txt')!.parents, [server.find('updates')!.id]);
  });

  test('recovers when a cached folder id returns 404', () async {
    await put('archive.txt', 'v1', cacheFileId: true);
    // The user deleted the whole archive folder in Drive.
    server.items.clear();

    await put('archive.txt', 'v2', cacheFileId: true);

    expect(server.folders.map((f) => f.name), ['WhatsApp Archive', 'Book Club']);
    expect(server.files.single.content, 'v2');
  });

  test('recovers when the cached folder was moved to the trash', () async {
    await put('archive.txt', 'v1', cacheFileId: true);
    server.find('Book Club')!.trashed = true;

    await put('archive.txt', 'v2', cacheFileId: true);

    // A fresh, non-trashed Book Club folder was created and used.
    final live = server.folders.where((f) => f.name == 'Book Club' && !f.trashed);
    expect(live, hasLength(1));
    final fresh = server.files.where((f) => f.parents.contains(live.single.id));
    expect(fresh.single.content, 'v2');
  });

  test('recovers when only the cached archive.txt id is stale', () async {
    await put('archive.txt', 'v1', cacheFileId: true);
    server.items.removeWhere((_, i) => !i.isFolder);

    await put('archive.txt', 'v2', cacheFileId: true);

    expect(server.files.single.content, 'v2');
    expect(server.folders, hasLength(2));
  });

  test('a trashed archive.txt is restored when overwritten', () async {
    await put('archive.txt', 'v1', cacheFileId: true);
    final f = server.files.single..trashed = true;

    await put('archive.txt', 'v2', cacheFileId: true);

    expect(f.trashed, isFalse);
    expect(f.content, 'v2');
  });

  test('names with quotes are escaped in queries', () async {
    await put("it's.txt", 'x', folder: ['WhatsApp Archive', "Dad's group"]);
    await put("it's.txt", 'y', folder: ['WhatsApp Archive', "Dad's group"]);
    expect(server.files, hasLength(1));
    expect(server.files.single.content, 'y');
    expect(GoogleDriveGateway.escapeQuery("a'b\\c"), r"a\'b\\c");
  });

  group('fetchText', () {
    test('returns null and creates nothing when absent', () async {
      final r = await gateway.fetchText(
        folderSegments: segs,
        fileName: 'archive.txt',
      );
      expect(r.getOrElse(() => 'x'), isNull);
      expect(server.items, isEmpty);
    });

    test('returns the content when present', () async {
      await put('archive.txt', 'line 1\nline 2\n');
      final r = await gateway.fetchText(
        folderSegments: segs,
        fileName: 'archive.txt',
      );
      expect(r.getOrElse(() => null), 'line 1\nline 2\n');
    });
  });

  group('error mapping', () {
    Failure? failureOf(dynamic either) =>
        (either as dynamic).fold((f) => f as Failure?, (_) => null);

    test('storage quota -> QuotaFailure', () async {
      server.failNextWithStatus = 403;
      server.failNextReason = 'storageQuotaExceeded';
      final r = await gateway.upsertText(
        folderSegments: segs,
        fileName: 'a.txt',
        content: 'x',
      );
      expect(failureOf(r), isA<QuotaFailure>());
      expect(failureOf(r)!.message, contains('storage is full'));
    });

    test('429 -> QuotaFailure', () async {
      server.failNextWithStatus = 429;
      final r = await gateway.upsertText(
        folderSegments: segs,
        fileName: 'a.txt',
        content: 'x',
      );
      expect(failureOf(r), isA<QuotaFailure>());
    });

    test('403 insufficient permission -> AuthFailure', () async {
      server.failNextWithStatus = 403;
      server.failNextReason = 'insufficientPermissions';
      final r = await gateway.upsertText(
        folderSegments: segs,
        fileName: 'a.txt',
        content: 'x',
      );
      expect(failureOf(r), isA<AuthFailure>());
    });

    test('500 -> ServerFailure', () async {
      server.failNextWithStatus = 503;
      final r = await gateway.upsertText(
        folderSegments: segs,
        fileName: 'a.txt',
        content: 'x',
      );
      expect(failureOf(r), isA<ServerFailure>());
    });

    test('socket error -> NetworkFailure', () async {
      server.throwNext = const SocketException('no route');
      final r = await gateway.upsertText(
        folderSegments: segs,
        fileName: 'a.txt',
        content: 'x',
      );
      expect(failureOf(r), isA<NetworkFailure>());
    });

    test('auth service failure -> AuthFailure, no API call', () async {
      auth.failWith = const AuthFailure('reconnect');
      final r = await gateway.upsertText(
        folderSegments: segs,
        fileName: 'a.txt',
        content: 'x',
      );
      expect(failureOf(r), isA<AuthFailure>());
      expect(failureOf(r)!.message, 'reconnect');
      expect(server.requestLog, isEmpty);
    });

    test('a 401 is retried once with a refreshed token', () async {
      server.unauthorizedResponses = 1;
      await put('a.txt', 'x');
      expect(auth.forceRefreshCalls, [false, true]);
      expect(server.files.single.content, 'x');
    });

    test('a persistent 401 -> AuthFailure', () async {
      server.unauthorizedResponses = 50;
      final r = await gateway.upsertText(
        folderSegments: segs,
        fileName: 'a.txt',
        content: 'x',
      );
      expect(failureOf(r), isA<AuthFailure>());
      expect(auth.forceRefreshCalls, [false, true]);
    });
  });

  group('large files', () {
    test(
        'content above the threshold uses a resumable upload (create and '
        'overwrite), small content stays multipart', () async {
      gateway = GoogleDriveGateway(
        auth: auth,
        cache: cache,
        resumableThreshold: 1000,
      );
      // ~2.6 MB of multi-byte text: several 1 MB chunks.
      final big = List.filled(
        60000,
        '12/03/26, 9:05\u202Fam - Asha: \u0928\u092E\u0938\u094D\u0924\u0947\n',
      ).join();
      await put('archive.txt', big, cacheFileId: true);
      expect(server.resumableSessions, 1);
      expect(server.files.single.content, big);

      final bigger = '$big${'x' * 1500}';
      await put('archive.txt', bigger, cacheFileId: true);
      expect(server.resumableSessions, 2);
      expect(server.files, hasLength(1));
      expect(server.files.single.content, bigger);

      await put('small.txt', 'short');
      expect(server.resumableSessions, 2);
      expect(server.find('small.txt')!.content, 'short');

      final fetched = await gateway.fetchText(
        folderSegments: segs,
        fileName: 'archive.txt',
      );
      expect(fetched.fold((_) => null, (t) => t), bigger);
    });
  });
}
