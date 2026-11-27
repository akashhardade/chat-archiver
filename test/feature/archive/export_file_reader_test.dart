import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:chat_archiver/feature/archive/domain/services/export_file_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'archive_test_helpers.dart';

List<int> zipOf(Map<String, String> entries, {List<String> dirs = const []}) {
  final archive = Archive();
  for (final d in dirs) {
    archive.addFile(ArchiveFile('$d/', 0, <int>[])..isFile = false);
  }
  entries.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}

void main() {
  const line = '12/03/2026, 14:05 - Alice: hi\n';

  group('plain text', () {
    test('decodes UTF-8 text', () {
      expect(ExportFileReader.readTranscript(utf8.encode(line)), line);
    });

    test('strips BOM', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(line)];
      expect(ExportFileReader.readTranscript(bytes), line);
    });

    test('keeps non-ASCII text and emoji', () {
      const s = '12/03/2026, 14:05 - Alice: caf\u00E9 \u{1F600}\n';
      expect(ExportFileReader.readTranscript(utf8.encode(s)), s);
    });

    test('malformed UTF-8 does not throw', () {
      final bytes = [...utf8.encode('12/03/2026, 14:05 - Alice: a'), 0xFF, 0x0A];
      final text = ExportFileReader.readTranscript(bytes);
      expect(text, startsWith('12/03/2026, 14:05 - Alice: a'));
    });

    test('empty bytes throw', () {
      expect(() => ExportFileReader.readTranscript([]),
          throwsA(isA<ExportFormatException>()));
    });

    test('whitespace-only content throws', () {
      expect(() => ExportFileReader.readTranscript(utf8.encode('  \n\n')),
          throwsA(isA<ExportFormatException>()));
    });

    test('a .zip file name with text content is read as text', () {
      expect(
          ExportFileReader.readTranscript(utf8.encode(line),
              fileName: 'chat.zip', mimeType: 'application/zip'),
          line);
    });
  });

  group('zip', () {
    test('reads the transcript from a zip, detected by magic bytes', () {
      final bytes = zipOf({'WhatsApp Chat with Book Club.txt': line});
      expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      // Wrong file name and mime type must not matter.
      expect(
          ExportFileReader.readTranscript(bytes,
              fileName: 'export.bin', mimeType: 'text/plain'),
          line);
    });

    test('_chat.txt (iOS) works', () {
      final bytes = zipOf({'_chat.txt': line});
      expect(ExportFileReader.readTranscript(bytes), line);
    });

    test('prefers WhatsApp Chat file over a larger unrelated txt', () {
      final bytes = zipOf({
        'notes.txt': 'x' * 5000,
        'WhatsApp Chat with Book Club.txt': line,
      });
      expect(ExportFileReader.readTranscript(bytes), line);
    });

    test('among several preferred files the largest wins', () {
      final bigger = '$line$line$line';
      final bytes = zipOf({
        'WhatsApp Chat - small.txt': line,
        'WhatsApp Chat - big.txt': bigger,
      });
      expect(ExportFileReader.readTranscript(bytes), bigger);
    });

    test('falls back to largest .txt when none is preferred', () {
      final bytes = zipOf({'a.txt': 'tiny a', 'b.txt': '$line$line'});
      expect(ExportFileReader.readTranscript(bytes), '$line$line');
    });

    test('ignores directories, __MACOSX and non-txt entries', () {
      final bytes = zipOf({
        '__MACOSX/._WhatsApp Chat.txt': 'y' * 9000,
        'media/photo.jpg': 'binary',
        'folder/WhatsApp Chat.txt': line,
      }, dirs: ['folder', 'media']);
      expect(ExportFileReader.readTranscript(bytes), line);
    });

    test('strips BOM inside the zipped txt', () {
      final archive = Archive()
        ..addFile(ArchiveFile('WhatsApp Chat.txt', 0, [0xEF, 0xBB, 0xBF, ...utf8.encode(line)]));
      expect(ExportFileReader.readTranscript(ZipEncoder().encode(archive)), line);
    });

    test('zip without txt throws', () {
      final bytes = zipOf({'photo.jpg': 'binary'});
      expect(() => ExportFileReader.readTranscript(bytes),
          throwsA(isA<ExportFormatException>()));
    });

    test('empty zip throws', () {
      expect(() => ExportFileReader.readTranscript(zipOf({})),
          throwsA(isA<ExportFormatException>()));
    });

    test('corrupt zip throws typed exception', () {
      final bytes = [0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4, 5, 6, 7, 8];
      expect(() => ExportFileReader.readTranscript(bytes),
          throwsA(isA<ExportFormatException>()));
    });

    test('zipped transcript feeds the parser', () {
      final bytes = zipOf({'WhatsApp Chat.txt': androidSample});
      final text = ExportFileReader.readTranscript(bytes);
      expect(parse(text), hasLength(8));
    });
  });
}
