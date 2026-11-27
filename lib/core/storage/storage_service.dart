import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:chat_archiver/core/storage/key_value_store.dart';

/// Service for handling local storage using FlutterSecureStorage with strict caching
/// to allow synchronous reads.
class StorageService implements KeyValueStore {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked),
  );

  final Map<String, String> _cache = {};

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initialize the storage service by loading all data into memory.
  /// Must be called before accessing data.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final allData = await _storage.readAll();
      _cache.addAll(allData);
      _initialized = true;
    } catch (e) {
      // Handle error or clear storage if corrupted
      if (kDebugMode) {
        print("StorageService init error: $e");
      }
    }
  }

  /// Check if data exists
  @override
  bool hasData(String key) {
    return _cache.containsKey(key);
  }

  /// Read value by key
  @override
  String? read(String key) {
    return _cache[key];
  }

  /// Read JSON/Object by key
  @override
  dynamic readJson(String key) {
    final value = _cache[key];
    if (value == null) return null;
    try {
      return jsonDecode(value);
    } catch (e) {
      return value;
    }
  }

  /// Write value by key
  @override
  Future<void> write(String key, dynamic value) async {
    String strValue;
    if (value is String) {
      strValue = value;
    } else {
      strValue = jsonEncode(value);
    }

    _cache[key] = strValue;
    await _storage.write(key: key, value: strValue);
  }

  /// Remove value by key
  @override
  Future<void> remove(String key) async {
    _cache.remove(key);
    await _storage.delete(key: key);
  }

  /// Clear all data
  Future<void> clear() async {
    _cache.clear();
    await _storage.deleteAll();
  }
}
