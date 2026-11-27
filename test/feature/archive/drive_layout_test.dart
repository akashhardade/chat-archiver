import 'package:chat_archiver/feature/archive/domain/services/drive_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'archive_test_helpers.dart';

void main() {
  String folder(String name, [String id = 'g1']) =>
      DriveLayout.groupFolderName(name, id);

  group('groupFolderName', () {
    test('plain names pass through', () {
      expect(folder('Book Club'), 'Book Club');
    });

    test('strips forbidden characters', () {
      expect(folder(r'a\b/c:d*e?f"g<h>i|j'), 'abcdefghij');
    });

    test('strips control characters and collapses whitespace', () {
      expect(folder('  Family \t\n  Chat \u0001\u007F '), 'Family Chat');
    });

    test('keeps emoji', () {
      expect(folder('Book Club \u{1F4DA}\u{1F389}'), 'Book Club \u{1F4DA}\u{1F389}');
      // ZWJ sequence (family emoji) survives.
      const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
      expect(folder('Fam $family'), 'Fam $family');
    });

    test('keeps RTL (Arabic/Hebrew) names but removes bidi marks', () {
      const arabic = '\u0639\u0627\u0626\u0644\u0629';
      expect(folder(arabic), arabic);
      expect(folder('$rlm$arabic$lrm'), arabic);
      expect(folder('\u05E9\u05DC\u05D5\u05DD / \u05E2\u05D5\u05DC\u05DD'),
          '\u05E9\u05DC\u05D5\u05DD \u05E2\u05D5\u05DC\u05DD');
    });

    test('keeps CJK and accents', () {
      expect(folder('\u5BB6\u65CF\u7FA4 caf\u00E9'), '\u5BB6\u65CF\u7FA4 caf\u00E9');
    });

    test('truncates to 80 characters without splitting surrogate pairs', () {
      final long = 'a' * 200;
      expect(folder(long).length, 80);
      final emoji = '\u{1F600}' * 100; // 100 code points, 200 UTF-16 units
      final out = folder(emoji);
      expect(out.runes.length, 80);
      expect(out.runes.every((r) => r == 0x1F600), isTrue);
    });

    test('truncation does not leave trailing space', () {
      final name = '${'a' * 79} bbb';
      expect(folder(name), 'a' * 79);
    });

    test('falls back to group-<id>', () {
      expect(folder('', 'g42'), 'group-g42');
      expect(folder('   ', 'g42'), 'group-g42');
      expect(folder(r'///:::***', 'g42'), 'group-g42');
      expect(folder('..', 'g42'), 'group-g42');
      expect(folder('.', 'g42'), 'group-g42');
      expect(folder('$lrm$rlm', 'g42'), 'group-g42');
    });

    test('dots inside names are fine', () {
      expect(folder('v1.2 team'), 'v1.2 team');
    });
  });

  group('file naming', () {
    final t = DateTime(2026, 3, 5, 7, 8, 9);

    test('timestamp key is zero padded', () {
      expect(DriveLayout.timestampKey(t), '2026-03-05_070809');
    });

    test('snapshot and update names', () {
      expect(DriveLayout.snapshotFileName(t), '2026-03-05_070809.txt');
      expect(DriveLayout.updateFileName(t), '2026-03-05_070809_new.txt');
      expect(DriveLayout.snapshotRelativePath(t),
          'snapshots/2026-03-05_070809.txt');
      expect(DriveLayout.updateRelativePath(t),
          'updates/2026-03-05_070809_new.txt');
    });

    test('constants', () {
      expect(DriveLayout.rootFolderName, 'WhatsApp Archive');
      expect(DriveLayout.archiveFileName, 'archive.txt');
    });

    test('full paths use forward slashes', () {
      expect(DriveLayout.archivePath('Book Club', 'g1'),
          'WhatsApp Archive/Book Club/archive.txt');
      expect(DriveLayout.snapshotPath('Book Club', 'g1', t),
          'WhatsApp Archive/Book Club/snapshots/2026-03-05_070809.txt');
      expect(DriveLayout.updatePath('a/b', 'g1', t),
          'WhatsApp Archive/ab/updates/2026-03-05_070809_new.txt');
    });

    test('folder segments', () {
      expect(DriveLayout.groupFolderSegments('X', 'g'),
          ['WhatsApp Archive', 'X']);
      expect(DriveLayout.snapshotsFolderSegments('X', 'g'),
          ['WhatsApp Archive', 'X', 'snapshots']);
      expect(DriveLayout.updatesFolderSegments('', 'g9'),
          ['WhatsApp Archive', 'group-g9', 'updates']);
    });
  });
}
