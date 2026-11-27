import 'package:path/path.dart' as p;

/// Pure naming of the Google Drive folder tree:
///
/// ```
/// WhatsApp Archive/
///   <group name>/
///     archive.txt
///     snapshots/<yyyy-MM-dd_HHmmss>.txt
///     updates/<yyyy-MM-dd_HHmmss>_new.txt
/// ```
class DriveLayout {
  const DriveLayout._();

  static const String rootFolderName = 'WhatsApp Archive';
  static const String archiveFileName = 'archive.txt';
  static const String snapshotsFolderName = 'snapshots';
  static const String updatesFolderName = 'updates';
  static const int maxFolderNameLength = 80;

  static final RegExp _forbidden = RegExp(r'[\\/:*?"<>|\u0000-\u001F\u007F-\u009F]');
  // LRM/RLM and embedded bidi controls: invisible, would make otherwise equal
  // names differ. (ZWJ / variation selectors are kept for emoji.)
  static final RegExp _bidiControls =
      RegExp('[\u200E\u200F\u202A-\u202E\u2066-\u2069]');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Folder name for a group: forbidden characters (`\ / : * ? " < > |`,
  /// control and bidi-control characters) removed, whitespace collapsed and
  /// trimmed, truncated to 80 code points (emoji and RTL text are kept;
  /// surrogate pairs are never split). Falls back to `group-<id>` if nothing
  /// usable remains (empty, or only dots).
  ///
  /// Note: two different titles can sanitize to the same name (e.g. `A/B` and
  /// `AB`); callers needing uniqueness must handle that.
  static String groupFolderName(String name, String id) {
    var s = name
        .replaceAll(_bidiControls, '')
        .replaceAll(_forbidden, '')
        .replaceAll(_spaces, ' ')
        .trim();
    final runes = s.runes.toList();
    if (runes.length > maxFolderNameLength) {
      s = String.fromCharCodes(runes.take(maxFolderNameLength)).trim();
    }
    // A dangling zero-width joiner after truncation is meaningless.
    while (s.endsWith('\u200D')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty || RegExp(r'^\.+$').hasMatch(s)) return 'group-$id';
    return s;
  }

  /// `yyyy-MM-dd_HHmmss` using [t] as given (no time-zone conversion).
  static String timestampKey(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
        '_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// `snapshots/<yyyy-MM-dd_HHmmss>.txt` (relative to the group folder).
  static String snapshotRelativePath(DateTime t) =>
      '$snapshotsFolderName/${timestampKey(t)}.txt';

  /// `updates/<yyyy-MM-dd_HHmmss>_new.txt` (relative to the group folder).
  static String updateRelativePath(DateTime t) =>
      '$updatesFolderName/${timestampKey(t)}_new.txt';

  /// File name only: `<yyyy-MM-dd_HHmmss>.txt`.
  static String snapshotFileName(DateTime t) => '${timestampKey(t)}.txt';

  /// File name only: `<yyyy-MM-dd_HHmmss>_new.txt`.
  static String updateFileName(DateTime t) => '${timestampKey(t)}_new.txt';

  /// Full path segments from the Drive root, e.g.
  /// `['WhatsApp Archive', 'Family', 'snapshots']`.
  static List<String> snapshotsFolderSegments(String name, String id) =>
      [rootFolderName, groupFolderName(name, id), snapshotsFolderName];

  static List<String> updatesFolderSegments(String name, String id) =>
      [rootFolderName, groupFolderName(name, id), updatesFolderName];

  static List<String> groupFolderSegments(String name, String id) =>
      [rootFolderName, groupFolderName(name, id)];

  /// `WhatsApp Archive/<group>/archive.txt`
  static String archivePath(String name, String id) => p.posix.join(
      rootFolderName, groupFolderName(name, id), archiveFileName);

  /// `WhatsApp Archive/<group>/snapshots/<ts>.txt`
  static String snapshotPath(String name, String id, DateTime t) =>
      p.posix.join(rootFolderName, groupFolderName(name, id),
          snapshotRelativePath(t));

  /// `WhatsApp Archive/<group>/updates/<ts>_new.txt`
  static String updatePath(String name, String id, DateTime t) =>
      p.posix.join(
          rootFolderName, groupFolderName(name, id), updateRelativePath(t));
}
