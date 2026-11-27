import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/core/storage/key_value_store.dart';
import 'package:chat_archiver/core/storage/storage_keys.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_settings_repository.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_state_repository.dart';

/// Groups JSON, settings and run bookkeeping over [KeyValueStore]
/// (`StorageService` in the app).
class ArchiveStateRepositoryImpl
    implements ArchiveStateRepository, ArchiveSettingsRepository {
  final KeyValueStore _store;

  ArchiveStateRepositoryImpl(this._store);

  // -------------------------------------------------- ArchiveStateRepository

  @override
  Future<Either<Failure, List<ArchivedGroup>>> loadGroups() async {
    try {
      final raw = _store.readJson(StorageKeys.archiveGroups);
      if (raw == null) return const Right([]);
      if (raw is! List) {
        return const Left(CacheFailure('Stored groups are corrupted'));
      }
      return Right([
        for (final e in raw)
          if (e is Map) ArchivedGroup.fromJson(Map<String, dynamic>.from(e)),
      ]);
    } catch (e) {
      return Left(CacheFailure('Could not read groups: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> saveGroups(List<ArchivedGroup> groups) async {
    try {
      await _store.write(
        StorageKeys.archiveGroups,
        jsonEncode([for (final g in groups) g.toJson()]),
      );
      return const Right(unit);
    } catch (e) {
      return Left(CacheFailure('Could not save groups: $e'));
    }
  }

  @override
  Future<Either<Failure, String?>> loadLastSuccessfulRunDate() async {
    try {
      return Right(_store.read(StorageKeys.lastSuccessfulRunDate));
    } catch (e) {
      return Left(CacheFailure('$e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> saveLastSuccessfulRunDate(
    String dateKey,
  ) async {
    try {
      await _store.write(StorageKeys.lastSuccessfulRunDate, dateKey);
      return const Right(unit);
    } catch (e) {
      return Left(CacheFailure('$e'));
    }
  }

  // ----------------------------------------------- ArchiveSettingsRepository

  @override
  int get morningHour {
    final v = _store.readJson(StorageKeys.morningHour);
    if (v is num && v >= 0 && v <= 23) return v.toInt();
    return ArchiveSettingsRepository.defaultMorningHour;
  }

  @override
  Future<void> setMorningHour(int hour) =>
      _store.write(StorageKeys.morningHour, hour.clamp(0, 23));

  bool _bool(String key, bool fallback) {
    final v = _store.readJson(key);
    return v is bool ? v : fallback;
  }

  @override
  bool get automationEnabled => _bool(StorageKeys.automationEnabled, true);

  @override
  Future<void> setAutomationEnabled(bool enabled) =>
      _store.write(StorageKeys.automationEnabled, enabled);

  @override
  bool get setupComplete => _bool(StorageKeys.setupComplete, false);

  @override
  Future<void> setSetupComplete(bool complete) =>
      _store.write(StorageKeys.setupComplete, complete);

  @override
  bool get disclosureAccepted => _bool(StorageKeys.disclosureAccepted, false);

  @override
  Future<void> setDisclosureAccepted(bool accepted) =>
      _store.write(StorageKeys.disclosureAccepted, accepted);

  @override
  String? get lastAppliedRunId => _store.read(StorageKeys.lastAppliedRunId);

  @override
  Future<void> setLastAppliedRunId(String runId) =>
      _store.write(StorageKeys.lastAppliedRunId, runId);
}
