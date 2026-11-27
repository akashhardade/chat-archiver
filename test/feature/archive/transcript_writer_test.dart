import 'package:chat_archiver/feature/archive/domain/services/transcript_writer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'archive_test_helpers.dart';

void main() {
  test('empty list writes empty string', () {
    expect(TranscriptWriter.write([]), '');
  });

  test('writes rawLines joined by LF with single trailing newline', () {
    final out = TranscriptWriter.write(parse(androidSample));
    expect(out.endsWith('\n'), isTrue);
    expect(out.endsWith('\n\n'), isFalse);
    expect(out, contains('12/03/2026, 14:08 - Bob: hello!\nsecond line of bob\n\nafter a blank line\n'));
  });

  test('round trip keeps keys for the Android sample', () {
    final a = parse(androidSample);
    final b = parse(TranscriptWriter.write(a));
    expect(keys(b), keys(a));
    expect(b, a);
  });

  test('round trip with iOS LRM, NNBSP, BOM, CRLF, orphan lead lines', () {
    final source = '${bom}stray\r\n'
        '$lrm[12/03/2026, 14:05:22] Alice: hi\r\n'
        '$lrm[12/03/2026, 14:05:23] Bob: ${lrm}image omitted\r\n'
        '12/03/26, 2:05${nnbsp}pm - Carol: yo\r\n'
        'continued\r\n\r\n'
        '3/12/26, 2:06 PM - Dan: <Media omitted>\r\n\r\n';
    final a = parse(source);
    final out = TranscriptWriter.write(a);
    expect(out.contains('\r'), isFalse);
    expect(out.startsWith(bom), isFalse);
    final b = parse(out);
    expect(keys(b), keys(a));
    // Verbatim characters survive.
    expect(out, contains('$lrm[12/03/2026, 14:05:22] Alice: hi\n'));
    expect(out, contains('2:05${nnbsp}pm'));
  });

  test('writing is stable (write(parse(write(x))) == write(x))', () {
    final once = TranscriptWriter.write(parse(androidSample));
    final twice = TranscriptWriter.write(parse(once));
    expect(twice, once);
  });

  test('writing a subset gives only those messages', () {
    final ms = parse(androidSample);
    final out = TranscriptWriter.write(ms.sublist(3, 4));
    expect(out, '12/03/2026, 14:07 - Alice: hi everyone\n');
  });
}
