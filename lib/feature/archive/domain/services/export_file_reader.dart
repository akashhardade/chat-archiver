import 'dart:convert';

import 'package:archive/archive.dart';

/// Thrown when no usable transcript could be extracted from an export.
class ExportFormatException implements Exception {
  final String message;
  const ExportFormatException(this.message);

  @override
  String toString() => 'ExportFormatException: $message';
}

/// Turns the raw bytes WhatsApp hands over ("Export chat" -> without media)
/// into transcript text. Handles both a bare `.txt` and a `.zip` containing
/// the `.txt`.
class ExportFileReader {
  const ExportFileReader();

  /// Reads the transcript from [bytes].
  ///
  /// The container is detected from the magic bytes `PK\x03\x04` (so a zip
  /// with a wrong/missing name or MIME type still works, and a `.zip` name on
  /// text content is read as text). [fileName] and [mimeType] are accepted for
  /// diagnostics/future use only.
  ///
  /// For zips: directories, `__MACOSX/` and `._*` entries are ignored; among
  /// `.txt` entries, those whose base name starts with `WhatsApp Chat` or
  /// equals `_chat.txt` (case-insensitive) are preferred; if several
  /// candidates remain the largest is used. Text is decoded as UTF-8
  /// (malformed sequences replaced) and a leading BOM is stripped.
  ///
  /// Throws [ExportFormatException] if the zip is corrupt, contains no `.txt`
  /// entry, or the resulting text is empty.
  static String readTranscript(
    List<int> bytes, {
    String? fileName,
    String? mimeType,
  }) {
    if (bytes.isEmpty) {
      throw const ExportFormatException('Export is empty');
    }
    final List<int> textBytes = _isZip(bytes) ? _extractFromZip(bytes) : bytes;
    var text = utf8.decode(textBytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    if (text.trim().isEmpty) {
      throw const ExportFormatException('Transcript is empty');
    }
    return text;
  }

  /// `PK\x03\x04` (local file header) or `PK\x05\x06` (an empty zip consists
  /// only of the end-of-central-directory record).
  static bool _isZip(List<int> b) =>
      b.length >= 4 &&
      b[0] == 0x50 &&
      b[1] == 0x4B &&
      ((b[2] == 0x03 && b[3] == 0x04) || (b[2] == 0x05 && b[3] == 0x06));

  static List<int> _extractFromZip(List<int> bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw ExportFormatException('Could not read zip: $e');
    }
    final candidates = <ArchiveFile>[];
    for (final f in zip.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      final base = name.split('/').last;
      if (name.startsWith('__MACOSX/') || base.startsWith('._')) continue;
      if (!base.toLowerCase().endsWith('.txt')) continue;
      candidates.add(f);
    }
    if (candidates.isEmpty) {
      throw const ExportFormatException('No .txt transcript found in zip');
    }
    bool preferred(ArchiveFile f) {
      final base = f.name.replaceAll('\\', '/').split('/').last.toLowerCase();
      return base.startsWith('whatsapp chat') || base == '_chat.txt';
    }

    final preferredOnes = candidates.where(preferred).toList();
    final pool = preferredOnes.isNotEmpty ? preferredOnes : candidates;
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.first.readBytes() ?? const <int>[];
  }
}
