import 'package:dartz/dartz.dart';
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';

/// Persistence of archive configuration/state (implemented elsewhere).
abstract class ArchiveStateRepository {
  /// All configured groups (empty list if none).
  Future<Either<Failure, List<ArchivedGroup>>> loadGroups();

  /// Replaces the stored list of groups.
  Future<Either<Failure, Unit>> saveGroups(List<ArchivedGroup> groups);

  /// `yyyy-MM-dd` of the last day a full run succeeded, or null.
  Future<Either<Failure, String?>> loadLastSuccessfulRunDate();

  Future<Either<Failure, Unit>> saveLastSuccessfulRunDate(String dateKey);
}
