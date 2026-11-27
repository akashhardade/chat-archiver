import 'package:chat_archiver/feature/archive/domain/entities/chat_message.dart';
import 'package:chat_archiver/feature/archive/domain/services/transcript_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'archive_test_helpers.dart';

void main() {
  group('Android 24h format', () {
    test('parses sender, timestamp and text', () {
      final ms = parse('12/03/2026, 14:05 - Alice: hi\n');
      expect(ms, hasLength(1));
      expect(ms[0].rawTimestamp, '12/03/2026, 14:05');
      expect(ms[0].sender, 'Alice');
      expect(ms[0].text, 'hi');
      expect(ms[0].rawLines, ['12/03/2026, 14:05 - Alice: hi']);
      expect(ms[0].isSystem, isFalse);
    });

    test('full sample: counts, system vs sender, special texts', () {
      final ms = parse(androidSample);
      expect(ms, hasLength(8));
      expect(ms[0].sender, isNull);
      expect(ms[0].text, startsWith('Messages and calls are end-to-end'));
      expect(ms[1].sender, isNull);
      expect(ms[1].text, 'Alice created group "Book Club"');
      expect(ms[2].sender, isNull);
      expect(ms[2].text, 'Alice added Bob');
      expect(ms[3].sender, 'Alice');
      expect(ms[5].text, '<Media omitted>');
      expect(ms[6].text, 'This message was deleted');
      expect(ms[7].text, 'fixed typo <This message was edited>');
    });
  });

  group('Android 12h format', () {
    test('narrow no-break space before pm is normalized in rawTimestamp', () {
      final ms = parse('12/03/26, 2:05${nnbsp}pm - Alice: hi\n');
      expect(ms, hasLength(1));
      expect(ms[0].rawTimestamp, '12/03/26, 2:05 pm');
      expect(ms[0].sender, 'Alice');
      // rawLines stay verbatim.
      expect(ms[0].rawLines.single, contains(nnbsp));
    });

    test('US order with uppercase PM', () {
      final ms = parse('3/12/26, 2:05 PM - Bob: yo\n');
      expect(ms.single.rawTimestamp, '3/12/26, 2:05 PM');
      expect(ms.single.sender, 'Bob');
      expect(ms.single.text, 'yo');
    });

    test('p.m. and no-break space variants', () {
      final ms = parse('3/12/26, 2:05${nbsp}p.m. - Bob: yo\n');
      expect(ms.single.rawTimestamp, '3/12/26, 2:05 p.m.');
      expect(ms.single.sender, 'Bob');
    });

    test('same message in NNBSP and plain-space exports has equal key', () {
      final a = parse('12/03/26, 2:05${nnbsp}pm - Alice: hi\n').single;
      final b = parse('12/03/26, 2:05 pm - Alice: hi\n').single;
      expect(a.key, b.key);
    });
  });

  group('iOS bracket format', () {
    test('with seconds and leading LRM', () {
      final ms = parse('$lrm[12/03/2026, 14:05:22] Alice: hi\n');
      expect(ms, hasLength(1));
      expect(ms[0].rawTimestamp, '12/03/2026, 14:05:22');
      expect(ms[0].sender, 'Alice');
      expect(ms[0].text, 'hi');
      expect(ms[0].rawLines.single.startsWith(lrm), isTrue);
    });

    test('LRM inside body is stripped from text but kept in rawLines', () {
      final ms =
          parse('[12/03/2026, 14:05:22] Alice: ${lrm}image omitted\n');
      expect(ms.single.text, 'image omitted');
      expect(ms.single.rawLines.single, contains(lrm));
    });

    test('system line without sender', () {
      final ms = parse(
          '$lrm[12/03/2026, 14:05:22] Alice: ${lrm}Messages and calls are end-to-end encrypted.\n'
          '$lrm[12/03/2026, 14:06:00] ${lrm}Bob joined using this group\'s invite link\n');
      expect(ms, hasLength(2));
      expect(ms[1].sender, isNull);
      expect(ms[1].text, 'Bob joined using this group\'s invite link');
    });

    test('12h iOS time with narrow space', () {
      final ms = parse('[12/03/2026, 2:05:22${nnbsp}PM] Alice: hi\n');
      expect(ms.single.rawTimestamp, '12/03/2026, 2:05:22 PM');
    });

    test('iOS and Android exports of same message share key', () {
      final a = parse('12/03/2026, 14:05 - Alice: hi\n').single;
      final i = parse('[12/03/2026, 14:05] Alice: hi\n').single;
      expect(a.key, i.key);
    });
  });

  group('date variants', () {
    test('dot separators, 2-digit year, with seconds', () {
      final ms = parse('12.03.26, 14:05:09 - Alice: hallo\n');
      expect(ms.single.rawTimestamp, '12.03.26, 14:05:09');
      expect(ms.single.sender, 'Alice');
    });

    test('dash separators and year-first dates', () {
      final ms = parse('2026-03-12, 14:05 - Alice: a\n12-03-2026, 14:06 - Bob: b\n');
      expect(ms, hasLength(2));
      expect(ms[0].rawTimestamp, '2026-03-12, 14:05');
      expect(ms[1].rawTimestamp, '12-03-2026, 14:06');
    });

    test('no comma between date and time', () {
      final ms = parse('12/03/2026 14:05 - Alice: hi\n');
      expect(ms.single.sender, 'Alice');
      expect(ms.single.rawTimestamp, '12/03/2026 14:05');
    });
  });

  group('multi-line messages', () {
    test('continuation lines join with newline, blank lines kept inside', () {
      final ms = parse(androidSample);
      expect(ms[4].sender, 'Bob');
      expect(ms[4].text, 'hello!\nsecond line of bob\n\nafter a blank line');
      expect(ms[4].rawLines, hasLength(4));
    });

    test('trailing blank lines are dropped from message', () {
      final ms = parse('12/03/2026, 14:05 - Alice: a\nb\n\n\n'
          '12/03/2026, 14:06 - Bob: c\n\n\n');
      expect(ms[0].text, 'a\nb');
      expect(ms[0].rawLines, ['12/03/2026, 14:05 - Alice: a', 'b']);
      expect(ms[1].text, 'c');
    });

    test('line that merely contains a date is a continuation', () {
      final ms = parse('12/03/2026, 14:05 - Alice: see\n'
          'meet on 12/03/2026, 14:05 ok\n'
          '12/03/2026 only\n');
      expect(ms, hasLength(1));
      expect(ms[0].text, 'see\nmeet on 12/03/2026, 14:05 ok\n12/03/2026 only');
    });
  });

  group('system messages and sender splitting', () {
    test('subject change with ": " inside quotes is a system message', () {
      final ms = parse(
          '12/03/2026, 14:05 - Alice changed the subject from "a: b" to "c"\n');
      expect(ms.single.sender, isNull);
      expect(ms.single.text, 'Alice changed the subject from "a: b" to "c"');
    });

    test('colon in the new subject only', () {
      final ms = parse(
          '12/03/2026, 14:05 - Alice changed the subject from "Team" to "Plan: B"\n');
      expect(ms.single.sender, isNull);
    });

    test('unquoted subject-change phrase is still system', () {
      final ms = parse(
          '12/03/2026, 14:05 - Alice changed the subject from x to y: z\n');
      expect(ms.single.sender, isNull);
    });

    test('colon in message text stays in text (split on first ": ")', () {
      final ms = parse('12/03/2026, 14:05 - Alice: note: buy milk\n');
      expect(ms.single.sender, 'Alice');
      expect(ms.single.text, 'note: buy milk');
    });

    test('phone-number sender', () {
      final ms = parse('12/03/2026, 14:05 - +91 98765 43210: hello\n');
      expect(ms.single.sender, '+91 98765 43210');
    });

    test('sender containing balanced quotes is still a sender', () {
      final ms = parse('12/03/2026, 14:05 - Bob "Bobby" Smith: hi\n');
      expect(ms.single.sender, 'Bob "Bobby" Smith');
    });

    test('sender with emoji', () {
      final ms = parse('12/03/2026, 14:05 - Alice \u{1F600}: hi\n');
      expect(ms.single.sender, 'Alice \u{1F600}');
    });

    test('you created group, added, left, removed', () {
      final ms = parse('12/03/2026, 14:05 - You created group "X"\n'
          '12/03/2026, 14:05 - Alice added Bob\n'
          '12/03/2026, 14:06 - Bob left\n'
          '12/03/2026, 14:07 - Alice removed Carol\n');
      expect(ms.every((m) => m.isSystem), isTrue);
      expect(ms, hasLength(4));
    });

    test('empty text after sender', () {
      final ms = parse('12/03/2026, 14:05 - Alice: \nstill alice\n');
      expect(ms.single.sender, 'Alice');
      expect(ms.single.text, '\nstill alice');
    });
  });

  group('file-level handling', () {
    test('UTF-8 BOM, CRLF and trailing newline', () {
      final ms = parse('${bom}12/03/2026, 14:05 - Alice: hi\r\n'
          'more\r\n'
          '12/03/2026, 14:06 - Bob: yo\r\n');
      expect(ms, hasLength(2));
      expect(ms[0].text, 'hi\nmore');
      expect(ms[0].rawLines, ['12/03/2026, 14:05 - Alice: hi', 'more']);
      expect(ms[1].text, 'yo');
      expect(ms.any((m) => m.rawLines.any((l) => l.contains('\r'))), isFalse);
    });

    test('no trailing newline works', () {
      expect(parse('12/03/2026, 14:05 - Alice: hi'), hasLength(1));
    });

    test('lines before first timestamp become a leading system message', () {
      final ms = parse('stray header line\nanother\n'
          '12/03/2026, 14:05 - Alice: hi\n');
      expect(ms, hasLength(2));
      expect(ms[0].rawTimestamp, '');
      expect(ms[0].sender, isNull);
      expect(ms[0].text, 'stray header line\nanother');
      expect(ms[1].sender, 'Alice');
    });

    test('empty and whitespace-only inputs yield nothing', () {
      expect(parse(''), isEmpty);
      expect(parse('\n\n'), isEmpty);
      expect(parse(bom), isEmpty);
    });

    test('blank lines before first header are dropped', () {
      final ms = parse('\n\n12/03/2026, 14:05 - Alice: hi\n');
      expect(ms, hasLength(1));
    });

    test('non-WhatsApp text is one leading system message', () {
      final ms = parse('hello world\n');
      expect(ms, hasLength(1));
      expect(ms.single.rawTimestamp, '');
    });
  });

  group('ChatMessage key', () {
    test('differs by timestamp, sender and text; stable otherwise', () {
      final base = msg('12/03/2026, 14:05', 'Alice', 'hi');
      expect(base.key, msg('12/03/2026, 14:05', 'Alice', 'hi').key);
      expect(base.key, isNot(msg('12/03/2026, 14:06', 'Alice', 'hi').key));
      expect(base.key, isNot(msg('12/03/2026, 14:05', 'Bob', 'hi').key));
      expect(base.key, isNot(msg('12/03/2026, 14:05', 'Alice', 'hi!').key));
      expect(base.key.length, 40);
    });

    test('null sender differs from empty sender and field boundaries hold', () {
      expect(ChatMessage.computeKey('t', null, 'x'),
          isNot(ChatMessage.computeKey('t', '', 'x')));
      expect(ChatMessage.computeKey('t', 'ab', 'c'),
          isNot(ChatMessage.computeKey('t', 'a', 'bc')));
    });

    test('trailing whitespace of text does not change key', () {
      expect(ChatMessage.computeKey('t', 'a', 'hi '),
          ChatMessage.computeKey('t', 'a', 'hi'));
    });
  });

  group('tryParseTimestamp', () {
    test('24h day-first', () {
      expect(TranscriptParser.tryParseTimestamp('13/03/2026, 14:05'),
          DateTime(2026, 3, 13, 14, 5));
    });

    test('month-first when second field > 12', () {
      expect(TranscriptParser.tryParseTimestamp('3/13/26, 2:05 PM'),
          DateTime(2026, 3, 13, 14, 5));
    });

    test('ambiguous date is day-first unless monthFirst', () {
      expect(TranscriptParser.tryParseTimestamp('03/04/2026, 08:00'),
          DateTime(2026, 4, 3, 8, 0));
      expect(
          TranscriptParser.tryParseTimestamp('03/04/2026, 08:00',
              monthFirst: true),
          DateTime(2026, 3, 4, 8, 0));
    });

    test('12 am / 12 pm and seconds, narrow space', () {
      expect(TranscriptParser.tryParseTimestamp('12/03/26, 12:05${nnbsp}am'),
          DateTime(2026, 3, 12, 0, 5));
      expect(TranscriptParser.tryParseTimestamp('12/03/26, 12:05 pm'),
          DateTime(2026, 3, 12, 12, 5));
      expect(TranscriptParser.tryParseTimestamp('12/03/2026, 14:05:22'),
          DateTime(2026, 3, 12, 14, 5, 22));
    });

    test('year-first', () {
      expect(TranscriptParser.tryParseTimestamp('2026-03-12, 14:05'),
          DateTime(2026, 3, 12, 14, 5));
    });

    test('garbage and impossible dates give null', () {
      expect(TranscriptParser.tryParseTimestamp(''), isNull);
      expect(TranscriptParser.tryParseTimestamp('hello'), isNull);
      expect(TranscriptParser.tryParseTimestamp('31/02/2026, 10:00'), isNull);
      expect(TranscriptParser.tryParseTimestamp('12/03/2026, 25:00'), isNull);
      expect(TranscriptParser.tryParseTimestamp('12/03/2026, 13:00 pm'), isNull);
    });
  });
}
