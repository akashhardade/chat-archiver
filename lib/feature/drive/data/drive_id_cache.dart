import 'dart:convert';

import 'package:chat_archiver/core/storage/storage_keys.dart';
import 'package:chat_archiver/core/storage/key_value_store.dart';

/// Remembers Drive folder / file IDs by path so repeated syncs do not search
/// again. IDs can go stale (user deleted or trashed the folder); the gateway
/// recovers from that.
abstract class DriveIdCache {
  String? get(String key);
  Future<void> put(String key, String id);
  Future<void> remove(String key);

  /// Removes [prefix] and every key below it (`prefix/...`).
  Future<void> removeTree(String prefix);
  Future<void> clear();
}

/// Non-persistent cache (tests).
class InMemoryDriveIdCache implements DriveIdCache {
  final Map<String, String> map = {};

  @override
  String? get(String key) => map[key];

  @override
  Future<void> put(String key, String id) async => map[key] = id;

  @override
  Future<void> remove(String key) async => map.remove(key);

  @override
  Future<void> removeTree(String prefix) async => map.removeWhere(
        (k, _) => k == prefix || k.startsWith('$prefix/'),
      );

  @override
  Future<void> clear() async => map.clear();
}

/// Cache persisted as one JSON map in [StorageService].
class StorageDriveIdCache implements DriveIdCache {
  final KeyValueStore _storage;
  late final Map<String, String> _map = _load();

  StorageDriveIdCache(this._storage);

  Map<String, String> _load() {
    final raw = _storage.readJson(StorageKeys.driveIdCache);
    if (raw is Map) {
      return {for (final e in raw.entries) '${e.key}': '${e.value}'};
    }
    return {};
  }

  Future<void> _persist() =>
      _storage.write(StorageKeys.driveIdCache, jsonEncode(_map));

  @override
  String? get(String key) => _map[key];

  @override
  Future<void> put(String key, String id) async {
    if (_map[key] == id) return;
    _map[key] = id;
    await _persist();
  }

  @override
  Future<void> remove(String key) async {
    if (_map.remove(key) != null) await _persist();
  }

  @override
  Future<void> removeTree(String prefix) async {
    final before = _map.length;
    _map.removeWhere((k, _) => k == prefix || k.startsWith('$prefix/'));
    if (_map.length != before) await _persist();
  }

  @override
  Future<void> clear() async {
    _map.clear();
    await _storage.remove(StorageKeys.driveIdCache);
  }
}
