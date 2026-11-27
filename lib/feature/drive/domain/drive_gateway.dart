import 'package:dartz/dartz.dart';
import 'package:chat_archiver/core/error/failure.dart';

/// Minimal Drive operations the archiver needs. Paths are folder name
/// segments from the Drive root (see `DriveLayout`), e.g.
/// `['WhatsApp Archive', 'Family', 'snapshots']`.
///
/// Implementations must be idempotent: uploading the same file name into the
/// same folder again replaces the content instead of creating a duplicate, so
/// a retried export never produces duplicate files.
abstract class DriveGateway {
  /// Content of [fileName] in the folder, or `null` when the folder or file
  /// does not exist (nothing is created). Used to restore `archive.txt` when
  /// the local copy is missing.
  Future<Either<Failure, String?>> fetchText({
    required List<String> folderSegments,
    required String fileName,
  });

  /// Ensures the folder path exists, then creates [fileName] or overwrites it
  /// with [content] (`text/plain; charset=utf-8`).
  Future<Either<Failure, Unit>> upsertText({
    required List<String> folderSegments,
    required String fileName,
    required String content,
    bool cacheFileId = false,
  });
}
