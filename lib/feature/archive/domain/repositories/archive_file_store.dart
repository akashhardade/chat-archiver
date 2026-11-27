/// Local files of the archiver (implemented over the app documents folder).
abstract class ArchiveFileStore {
  /// Content of `archives/<groupId>/archive.txt`, or null if absent.
  Future<String?> readArchive(String groupId);

  /// Atomically replaces the archive (temp file + rename).
  Future<void> writeArchive(String groupId, String text);

  /// Snapshot kept after a held-back gap, until the user resolves it.
  Future<String?> readHeldSnapshot(String groupId);
  Future<void> writeHeldSnapshot(String groupId, String text);
  Future<void> deleteHeldSnapshot(String groupId);

  /// Raw bytes of an export file handed over by native. Throws
  /// [ExportFileMissingException] when the file does not exist.
  Future<List<int>> readExportBytes(String path);
}

class ExportFileMissingException implements Exception {
  final String path;
  const ExportFileMissingException(this.path);

  @override
  String toString() => 'Export file missing: $path';
}
