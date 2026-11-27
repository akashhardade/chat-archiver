import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/drive/domain/drive_auth_service.dart';

class FakeItem {
  final String id;
  String name;
  final String mime;
  final List<String> parents;
  String content;
  bool trashed;

  FakeItem(this.id, this.name, this.mime, this.parents,
      {this.content = '', this.trashed = false});

  bool get isFolder => mime == 'application/vnd.google-apps.folder';
}

/// A tiny in-memory Google Drive v3 behind an [http.Client], good enough for
/// the calls [GoogleDriveGateway] makes (list, get, create, multipart
/// create/update, metadata update).
class FakeDriveServer {
  final Map<String, FakeItem> items = {};
  final List<String> requestLog = [];
  int _next = 1;

  /// Respond with this status to the next matching request, then clear.
  int? failNextWithStatus;
  String? failNextReason;
  Object? throwNext;
  int unauthorizedResponses = 0;

  late final MockClient client = MockClient(_handle);

  /// Open resumable upload sessions: upload_id -> session.
  final Map<String, _Session> _sessions = {};
  int resumableSessions = 0;

  Iterable<FakeItem> get files => items.values.where((i) => !i.isFolder);
  Iterable<FakeItem> get folders => items.values.where((i) => i.isFolder);

  FakeItem? find(String name, {String? parent}) {
    for (final i in items.values) {
      if (i.name == name && (parent == null || i.parents.contains(parent))) {
        return i;
      }
    }
    return null;
  }

  http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  http.Response _error(int status, {String reason = 'notFound'}) => _json({
        'error': {
          'code': status,
          'message': 'error $status',
          'errors': [
            {'reason': reason, 'message': 'error $status'},
          ],
        },
      }, status);

  Future<http.Response> _handle(http.Request r) async {
    requestLog.add('${r.method} ${r.url.path}');
    if (throwNext != null) {
      final e = throwNext!;
      throwNext = null;
      throw e;
    }
    if (unauthorizedResponses > 0) {
      unauthorizedResponses--;
      return _error(401, reason: 'authError');
    }
    if (failNextWithStatus != null) {
      final s = failNextWithStatus!;
      failNextWithStatus = null;
      return _error(s, reason: failNextReason ?? 'backendError');
    }
    // googleapis sends resumable session starts to /resumable/upload/...
    final path = r.url.path.replaceFirst(RegExp('^/resumable/'), '/');
    final isUpload = path.startsWith('/upload/');
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    // [drive, v3, files, id?] or [upload, drive, v3, files, id?]
    final rest = segs.sublist(isUpload ? 4 : 3);
    final id = rest.isEmpty ? null : rest.first;

    // Resumable upload: chunk PUTs to the session URL.
    final uploadId = r.url.queryParameters['upload_id'];
    if (uploadId != null) return _resumableChunk(r, uploadId);
    // Resumable upload: session start (metadata only, media follows).
    if (isUpload && r.url.queryParameters['uploadType'] == 'resumable') {
      final sid = 's${_sessions.length + 1}';
      resumableSessions++;
      _sessions[sid] = _Session(
        r.method,
        id,
        r.body.isEmpty ? const {} : jsonDecode(r.body) as Map,
      );
      return http.Response('', 200, headers: {
        'location':
            'https://www.googleapis.com/upload/drive/v3/files?upload_id=$sid',
      });
    }

    if (r.method == 'GET' && id == null) return _list(r.url.queryParameters['q'] ?? '');
    if (r.method == 'GET' && id != null) {
      final item = items[id];
      if (item == null) return _error(404);
      if (r.url.queryParameters['alt'] == 'media') {
        return http.Response.bytes(utf8.encode(item.content), 200,
            headers: {'content-type': 'text/plain'});
      }
      return _json({'id': item.id, 'trashed': item.trashed});
    }
    if (r.method == 'POST' && id == null) {
      final parsed = isUpload ? _multipart(r) : (jsonDecode(r.body) as Map);
      final meta = parsed is _Multi ? parsed.meta : parsed as Map;
      final item = FakeItem(
        'id${_next++}',
        meta['name'] as String,
        (meta['mimeType'] as String?) ?? 'application/octet-stream',
        [for (final p in (meta['parents'] as List? ?? const [])) '$p'],
        content: parsed is _Multi ? parsed.content : '',
      );
      items[item.id] = item;
      return _json({'id': item.id});
    }
    if (r.method == 'PATCH' && id != null) {
      final item = items[id];
      if (item == null) return _error(404);
      if (isUpload) {
        final m = _multipart(r);
        item.content = m.content;
      } else {
        final meta = jsonDecode(r.body) as Map;
        if (meta['trashed'] is bool) item.trashed = meta['trashed'] as bool;
      }
      return _json({'id': item.id, 'trashed': item.trashed});
    }
    return _error(400, reason: 'unsupported');
  }

  http.Response _resumableChunk(http.Request r, String sid) {
    final session = _sessions[sid];
    if (session == null) return _error(404);
    session.bytes.addAll(r.bodyBytes);
    final range = r.headers['content-range'] ?? '';
    final total = int.tryParse(range.split('/').last);
    if (total == null || session.bytes.length < total) {
      return http.Response('', 308, headers: {
        'range': 'bytes=0-${session.bytes.length - 1}',
      });
    }
    final content = utf8.decode(session.bytes);
    if (session.method == 'POST') {
      final meta = session.meta;
      final item = FakeItem(
        'id${_next++}',
        meta['name'] as String,
        (meta['mimeType'] as String?) ?? 'application/octet-stream',
        [for (final p in (meta['parents'] as List? ?? const [])) '$p'],
        content: content,
      );
      items[item.id] = item;
      return _json({'id': item.id});
    }
    final item = items[session.fileId];
    if (item == null) return _error(404);
    item.content = content;
    return _json({'id': item.id, 'trashed': item.trashed});
  }

  http.Response _list(String q) {
    final name = RegExp(r"name = '((?:[^'\\]|\\.)*)'").firstMatch(q)?.group(1);
    final unescaped = name?.replaceAll(r"\'", "'").replaceAll(r'\\', r'\');
    final parent = RegExp(r"'([^']+)' in parents").firstMatch(q)?.group(1);
    final wantFolder = q.contains("mimeType = 'application/vnd.google-apps.folder'");
    final wantFile = q.contains("mimeType != 'application/vnd.google-apps.folder'");
    final out = [
      for (final i in items.values)
        if (!i.trashed &&
            i.name == unescaped &&
            (parent == null || i.parents.contains(parent)) &&
            (!wantFolder || i.isFolder) &&
            (!wantFile || !i.isFolder))
          {'id': i.id, 'name': i.name},
    ];
    return _json({'files': out});
  }

  _Multi _multipart(http.Request r) {
    final ct = r.headers['content-type'] ?? '';
    final boundary = RegExp(r'boundary="?([^";]+)"?').firstMatch(ct)!.group(1)!;
    final parts = r.body.split('--$boundary');
    // parts: ['', part1, part2, '--\r\n']
    String bodyOf(String part) {
      final i = part.indexOf('\r\n\r\n');
      return part.substring(i + 4).replaceFirst(RegExp(r'\r\n$'), '');
    }

    final meta = jsonDecode(bodyOf(parts[1])) as Map;
    final content = utf8.decode(base64.decode(bodyOf(parts[2]).trim()));
    return _Multi(meta, content);
  }
}

class _Session {
  final String method;
  final String? fileId;
  final Map meta;
  final List<int> bytes = [];
  _Session(this.method, this.fileId, this.meta);
}

class _Multi {
  final Map meta;
  final String content;
  _Multi(this.meta, this.content);
}

/// [DriveAuthService] handing out a fixed client.
class FakeDriveAuth implements DriveAuthService {
  final http.Client client;
  DriveAccount? account = const DriveAccount(email: 'user@example.com');
  Failure? failWith;
  final List<bool> forceRefreshCalls = [];

  FakeDriveAuth(this.client);

  @override
  DriveAccount? get currentAccount => account;

  @override
  bool get isConnected => account != null;

  @override
  Future<Either<Failure, DriveAccount>> connect() async => Right(account!);

  @override
  Future<Either<Failure, http.Client>> authorizedClient({
    bool forceRefresh = false,
  }) async {
    forceRefreshCalls.add(forceRefresh);
    if (failWith != null) return Left(failWith!);
    // The gateway closes what it gets; hand out a wrapper that ignores close.
    return Right(_NoCloseClient(client));
  }

  @override
  Future<void> disconnect() async => account = null;
}

class _NoCloseClient extends http.BaseClient {
  final http.Client _inner;
  _NoCloseClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {}
}
