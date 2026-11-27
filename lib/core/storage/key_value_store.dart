import 'dart:convert';

/// Synchronous-read key/value storage (see `StorageService`). Abstracted so
/// repositories can be tested with [MemoryKeyValueStore].
abstract class KeyValueStore {
  bool hasData(String key);
  String? read(String key);
  dynamic readJson(String key);
  Future<void> write(String key, dynamic value);
  Future<void> remove(String key);
}

/// In-memory implementation (tests).
class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  bool hasData(String key) => data.containsKey(key);

  @override
  String? read(String key) => data[key];

  @override
  dynamic readJson(String key) {
    final v = data[key];
    if (v == null) return null;
    try {
      return jsonDecode(v);
    } catch (_) {
      return v;
    }
  }

  @override
  Future<void> write(String key, dynamic value) async {
    data[key] = value is String ? value : jsonEncode(value);
  }

  @override
  Future<void> remove(String key) async => data.remove(key);
}
