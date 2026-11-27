import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/drive/data/drive_id_cache.dart';
import 'package:chat_archiver/feature/drive/domain/drive_auth_service.dart';
import 'package:chat_archiver/feature/drive/domain/drive_gateway.dart';

/// Internal carrier so auth failures from [DriveAuthService] flow through the
/// same error mapping as API errors.
class _FailureException implements Exception {
  final Failure failure;
  const _FailureException(this.failure);
}

/// [DriveGateway] over Google Drive API v3 (`drive.file` scope).
///
/// * Folders are found by name + parent + folder mime type + `trashed=false`
///   and created when missing. The folder ID of a path is cached; before a
///   cached ID is used it is verified (`files.get`), and a 404 / trashed
///   folder drops the cached subtree and walks the path again.
/// * Files are found by name inside their folder; present -> `files.update`
///   with new media, absent -> `files.create`. This makes retries idempotent.
/// * A 401 triggers one retry with a fresh token.
/// * Content above [resumableThreshold] bytes (a long-lived `archive.txt` can
///   reach tens of MB) is sent with a resumable upload in 1 MB chunks, as
///   Google recommends for files over 5 MB; smaller files use one multipart
///   request.
class GoogleDriveGateway implements DriveGateway {
  static const String folderMime = 'application/vnd.google-apps.folder';
  static const String textMime = 'text/plain';
  static const String textContentType = 'text/plain; charset=utf-8';

  /// Upper bound for one fetch/upload, including the folder lookups. Generous
  /// so that a large archive on a slow mobile connection still completes; a
  /// timed-out upload is simply retried later (uploads are idempotent).
  static const Duration operationTimeout = Duration(minutes: 10);
  static const int defaultResumableThreshold = 5 * 1024 * 1024;

  final DriveAuthService _auth;
  final DriveIdCache _cache;
  final int resumableThreshold;

  GoogleDriveGateway({
    required DriveAuthService auth,
    required DriveIdCache cache,
    this.resumableThreshold = defaultResumableThreshold,
  })  : _auth = auth,
        _cache = cache;

  // ---------------------------------------------------------------- public

  @override
  Future<Either<Failure, String?>> fetchText({
    required List<String> folderSegments,
    required String fileName,
  }) {
    return _guard(() => _withApi((api) async {
          final folderId = await _resolveFolder(
            api,
            folderSegments,
            create: false,
          );
          if (folderId == null) return null;
          final id = await _findFile(api, folderId, fileName);
          if (id == null) return null;
          final media = await api.files.get(
            id,
            downloadOptions: drive.DownloadOptions.fullMedia,
          ) as drive.Media;
          final bytes = BytesBuilder(copy: false);
          await for (final chunk in media.stream) {
            bytes.add(chunk);
          }
          return utf8.decode(bytes.takeBytes(), allowMalformed: true);
        }));
  }

  @override
  Future<Either<Failure, Unit>> upsertText({
    required List<String> folderSegments,
    required String fileName,
    required String content,
    bool cacheFileId = false,
  }) {
    return _guard(() => _withApi((api) async {
          final folderId = await _resolveFolder(
            api,
            folderSegments,
            create: true,
          );
          await _upsertFile(
            api,
            folderId!,
            fileName,
            content,
            cacheKey: cacheFileId ? _fileKey(folderSegments, fileName) : null,
          );
          return unit;
        }));
  }

  // ------------------------------------------------------------- internals

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Right(await body().timeout(operationTimeout));
    } catch (e) {
      return Left(mapError(e));
    }
  }

  Future<T> _withApi<T>(Future<T> Function(drive.DriveApi api) body) async {
    var attempt = 0;
    while (true) {
      final clientResult = await _auth.authorizedClient(
        forceRefresh: attempt > 0,
      );
      final http.Client client = clientResult.fold(
        (f) => throw _FailureException(f),
        (c) => c,
      );
      try {
        return await body(drive.DriveApi(client));
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status == 401 && attempt == 0) {
          attempt++;
          continue;
        }
        rethrow;
      } finally {
        client.close();
      }
    }
  }

  String get _accountKey => _auth.currentAccount?.email ?? '';

  String _folderKey(List<String> segments) =>
      '$_accountKey|${segments.join('/')}';

  String _fileKey(List<String> folderSegments, String name) =>
      '$_accountKey|${[...folderSegments, name].join('/')}';

  /// Escapes a value for use inside single quotes in a Drive `q` expression.
  static String escapeQuery(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  Future<String?> _findFolder(
    drive.DriveApi api,
    String parentId,
    String name,
  ) async {
    final list = await api.files.list(
      q: "name = '${escapeQuery(name)}' and mimeType = '$folderMime' "
          "and '$parentId' in parents and trashed = false",
      spaces: 'drive',
      orderBy: 'createdTime',
      pageSize: 10,
      $fields: 'files(id,name)',
    );
    final files = list.files ?? const <drive.File>[];
    return files.isEmpty ? null : files.first.id;
  }

  Future<String?> _findFile(
    drive.DriveApi api,
    String parentId,
    String name,
  ) async {
    final list = await api.files.list(
      q: "name = '${escapeQuery(name)}' and mimeType != '$folderMime' "
          "and '$parentId' in parents and trashed = false",
      spaces: 'drive',
      orderBy: 'createdTime',
      pageSize: 10,
      $fields: 'files(id,name)',
    );
    final files = list.files ?? const <drive.File>[];
    return files.isEmpty ? null : files.first.id;
  }

  /// True when [id] still exists and is not trashed.
  Future<bool> _folderAlive(drive.DriveApi api, String id) async {
    try {
      final f = await api.files.get(id, $fields: 'id,trashed') as drive.File;
      return f.trashed != true;
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) return false;
      rethrow;
    }
  }

  /// Returns the folder ID for [segments] from the Drive root; creates the
  /// missing levels when [create], else returns null if any level is absent.
  Future<String?> _resolveFolder(
    drive.DriveApi api,
    List<String> segments, {
    required bool create,
  }) async {
    final leafKey = _folderKey(segments);
    final cached = _cache.get(leafKey);
    if (cached != null) {
      if (await _folderAlive(api, cached)) return cached;
      await _cache.removeTree(leafKey);
    }

    var parent = 'root';
    for (var i = 0; i < segments.length; i++) {
      final sub = segments.sublist(0, i + 1);
      final key = _folderKey(sub);
      var id = await _findFolder(api, parent, segments[i]);
      if (id == null) {
        if (!create) return null;
        final created = await api.files.create(
          drive.File()
            ..name = segments[i]
            ..mimeType = folderMime
            ..parents = [parent],
          $fields: 'id',
        );
        id = created.id;
        if (id == null) {
          throw const _FailureException(
            ServerFailure('Google Drive did not return a folder ID.'),
          );
        }
      }
      await _cache.put(key, id);
      parent = id;
    }
    return parent;
  }

  drive.Media _media(List<int> bytes) => drive.Media(
        Stream<List<int>>.value(bytes),
        bytes.length,
        contentType: textContentType,
      );

  drive.UploadOptions _uploadOptions(List<int> bytes) =>
      bytes.length > resumableThreshold
          ? drive.ResumableUploadOptions()
          : drive.UploadOptions.defaultOptions;

  Future<void> _upsertFile(
    drive.DriveApi api,
    String folderId,
    String name,
    String content, {
    String? cacheKey,
  }) async {
    var id = cacheKey == null ? null : _cache.get(cacheKey);
    if (id != null) {
      try {
        await _updateFile(api, id, content);
        return;
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status != 404) rethrow;
        await _cache.remove(cacheKey!);
        id = null;
      }
    }

    id = await _findFile(api, folderId, name);
    if (id != null) {
      await _updateFile(api, id, content);
    } else {
      final bytes = utf8.encode(content);
      final created = await api.files.create(
        drive.File()
          ..name = name
          ..mimeType = textMime
          ..parents = [folderId],
        uploadMedia: _media(bytes),
        uploadOptions: _uploadOptions(bytes),
        $fields: 'id',
      );
      id = created.id;
    }
    if (cacheKey != null && id != null) await _cache.put(cacheKey, id);
  }

  Future<void> _updateFile(drive.DriveApi api, String id, String content) async {
    final bytes = utf8.encode(content);
    final updated = await api.files.update(
      drive.File(),
      id,
      uploadMedia: _media(bytes),
      uploadOptions: _uploadOptions(bytes),
      $fields: 'id,trashed',
    );
    if (updated.trashed == true) {
      // The user trashed archive.txt: bring it back instead of writing into
      // the bin.
      await api.files.update(
        drive.File()..trashed = false,
        id,
        $fields: 'id',
      );
    }
  }

  // ------------------------------------------------------------ error map

  static const Set<String> _quotaReasons = {
    'storageQuotaExceeded',
    'quotaExceeded',
    'rateLimitExceeded',
    'userRateLimitExceeded',
    'dailyLimitExceeded',
    'sharingRateLimitExceeded',
  };

  /// Maps any thrown error to a [Failure] (auth / network / quota / other).
  static Failure mapError(Object e) {
    if (e is _FailureException) return e.failure;
    if (e is drive.DetailedApiRequestError) {
      final status = e.status ?? 0;
      final reasons = {for (final d in e.errors) d.reason};
      if (status == 429 || reasons.any(_quotaReasons.contains)) {
        final full = reasons.contains('storageQuotaExceeded');
        return QuotaFailure(
          full
              ? 'Your Google Drive storage is full.'
              : 'Google Drive is rate limiting requests. It will be retried later.',
        );
      }
      if (status == 401) {
        return const AuthFailure(
          'Google Drive rejected the sign-in. Open Chat Archiver and reconnect Drive.',
        );
      }
      if (status == 403) {
        return AuthFailure(
          'Google Drive refused access: ${e.message ?? 'permission denied'}. '
          'Check that the Drive API is enabled and the account is allowed.',
        );
      }
      if (status == 404) {
        return NotFoundFailure('Google Drive item not found: ${e.message}');
      }
      if (status >= 500) {
        return const ServerFailure(
          'Google Drive is temporarily unavailable. It will be retried later.',
        );
      }
      return UnknownFailure('Google Drive error $status: ${e.message}');
    }
    if (e is SocketException ||
        e is http.ClientException ||
        e is TimeoutException ||
        e is HandshakeException) {
      return const NetworkFailure(
        'No connection to Google Drive. It will be retried later.',
      );
    }
    return UnknownFailure('Unexpected Google Drive error: $e');
  }
}
