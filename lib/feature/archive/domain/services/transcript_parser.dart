import 'package:chat_archiver/feature/archive/domain/entities/chat_message.dart';

/// Parses WhatsApp "Export chat" text transcripts (Android and iOS styles).
///
/// Header line formats recognised (after normalization, see
/// [ChatMessage.normalizeText]):
///
/// * Android: `DATE, TIME - rest`   e.g. `12/03/2026, 14:05 - Alice: hi`
/// * iOS:     `[DATE, TIME] rest`   e.g. `[12/03/2026, 14:05:22] Alice: hi`
///
/// where DATE is three numeric groups separated by `/`, `.` or `-` (2 or 4
/// digit year, either field order), TIME is `H:MM[:SS]` optionally followed by
/// am/pm (`pm`, `PM`, `p.m.`, with a normal, no-break or narrow no-break
/// space before it). The comma after the date is optional.
///
/// Any line that is not a header is a continuation of the previous message
/// (blank lines included). Known limitation: a continuation line that itself
/// looks exactly like a header (e.g. someone pasted an export into a message)
/// is treated as a new message.
///
/// Sender / system split rule: the part after the header is split on the
/// FIRST `: `. The left part is accepted as a sender unless it
///  * is empty,
///  * contains an unbalanced quote character (`"`, or curly quotes) - this is
///    what identifies system lines such as
///    `Alice changed the subject from "a: b" to "c"`, whose first `: ` sits
///    inside quotes, or
///  * contains a known English system phrase that can carry a colon
///    (`changed the subject`, `changed the group description`,
///    `changed this group's`).
/// Otherwise the whole remainder is the text of a system message
/// (`sender == null`). Lines such as `Alice added Bob` have no `: ` and so are
/// system messages. System lines in other languages that contain `: ` before
/// any quote are indistinguishable from chat lines and parse as sender
/// messages; this only affects display, not merge correctness (keys are
/// deterministic either way).
///
/// Other behaviour: leading UTF-8 BOM is dropped; CRLF/CR/LF are all line
/// terminators; trailing blank lines of every message (including the final
/// newline of the file) are dropped; lines before the first header become one
/// leading system message with an empty [ChatMessage.rawTimestamp] (dropped
/// if they are all blank).
class TranscriptParser {
  const TranscriptParser();

  static const String _date = r'\d{1,4}[/.\-]\d{1,2}[/.\-]\d{1,4}';
  static const String _time =
      r'\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp]\.?[Mm]\.?)?';
  static const String _stamp = '$_date,?\\s+$_time';

  static final RegExp _android = RegExp('^($_stamp)\\s-(?:\\s(.*))?\$');
  static final RegExp _ios = RegExp('^\\[($_stamp)\\]\\s?(.*)\$');
  static final RegExp _lineBreak = RegExp(r'\r\n|\n|\r');
  static final RegExp _systemPhrase = RegExp(
    "changed the subject|changed the group description|changed this group's",
  );

  /// Parses [text] into messages in file order.
  static List<ChatMessage> parse(String text) {
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final lines = text.split(_lineBreak);

    final result = <ChatMessage>[];
    var ts = '';
    String? sender;
    var firstBody = '';
    var raw = <String>[];
    var extra = <String>[];
    var open = false;

    void flush() {
      if (!open) return;
      final rawLines = List<String>.from(raw);
      final bodyLines = <String>[firstBody, ...extra];
      // Drop trailing blank lines.
      while (rawLines.length > 1 && rawLines.last.trim().isEmpty) {
        rawLines.removeLast();
      }
      while (bodyLines.length > 1 && bodyLines.last.trim().isEmpty) {
        bodyLines.removeLast();
      }
      final bodyText = bodyLines.map(ChatMessage.normalizeText).join('\n');
      // Leading blank-only orphan lines carry nothing worth keeping.
      if (!(ts.isEmpty && bodyText.trim().isEmpty)) {
        result.add(ChatMessage(
          rawTimestamp: ts,
          sender: sender,
          text: bodyText,
          rawLines: rawLines,
        ));
      }
      open = false;
      raw = [];
      extra = [];
    }

    for (final line in lines) {
      final header = _matchHeader(line);
      if (header != null) {
        flush();
        open = true;
        ts = header.timestamp;
        sender = header.sender;
        firstBody = header.body;
        raw = [line];
        extra = [];
      } else if (!open) {
        // Orphan lines before the first header.
        open = true;
        ts = '';
        sender = null;
        firstBody = line;
        raw = [line];
        extra = [];
      } else {
        raw.add(line);
        extra.add(line);
      }
    }
    flush();
    return result;
  }

  static _Header? _matchHeader(String rawLine) {
    final line = ChatMessage.normalizeText(rawLine);
    final m = _android.firstMatch(line) ?? _ios.firstMatch(line);
    if (m == null) return null;
    final ts = ChatMessage.normalizeTimestamp(m.group(1)!);
    final rest = m.group(2) ?? '';
    final split = _splitSender(rest);
    return _Header(ts, split.$1, split.$2);
  }

  static (String?, String) _splitSender(String rest) {
    final idx = rest.indexOf(': ');
    if (idx <= 0) return (null, rest);
    final candidate = rest.substring(0, idx);
    if (candidate.trim().isEmpty ||
        _hasUnbalancedQuotes(candidate) ||
        _systemPhrase.hasMatch(candidate)) {
      return (null, rest);
    }
    return (candidate.trim(), rest.substring(idx + 2));
  }

  static bool _hasUnbalancedQuotes(String s) {
    var straight = 0, open = 0, close = 0;
    for (final c in s.runes) {
      if (c == 0x22) straight++;
      if (c == 0x201C) open++;
      if (c == 0x201D) close++;
    }
    return straight.isOdd || open != close;
  }

  static final RegExp _parts = RegExp(
    r'^(\d{1,4})[/.\-](\d{1,2})[/.\-](\d{1,4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s?([AaPp])\.?[Mm]\.?)?$',
  );

  /// Best-effort conversion of a [ChatMessage.rawTimestamp] to a [DateTime]
  /// (no time zone, i.e. "local wall clock"). Returns `null` if it cannot be
  /// parsed. Date field order is guessed: a 3-4 digit first field means
  /// year-first; otherwise a field > 12 decides, and a fully ambiguous date
  /// (both <= 12) is read day-first unless [monthFirst] is true.
  ///
  /// The merger never uses this; it is a convenience only.
  static DateTime? tryParseTimestamp(String rawTimestamp,
      {bool monthFirst = false}) {
    final m = _parts.firstMatch(ChatMessage.normalizeTimestamp(rawTimestamp));
    if (m == null) return null;
    final a = m.group(1)!, b = int.parse(m.group(2)!), c = m.group(3)!;
    int year, month, day;
    if (a.length >= 3) {
      year = int.parse(a);
      month = b;
      day = int.parse(c);
    } else {
      year = int.parse(c);
      if (c.length <= 2) year += 2000;
      final x = int.parse(a);
      if (x > 12) {
        day = x;
        month = b;
      } else if (b > 12) {
        month = x;
        day = b;
      } else if (monthFirst) {
        month = x;
        day = b;
      } else {
        day = x;
        month = b;
      }
    }
    var hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = m.group(6) == null ? 0 : int.parse(m.group(6)!);
    final ampm = m.group(7)?.toLowerCase();
    if (ampm != null) {
      if (hour < 1 || hour > 12) return null;
      if (ampm == 'a') {
        if (hour == 12) hour = 0;
      } else if (hour != 12) {
        hour += 12;
      }
    }
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    final dt = DateTime(year, month, day, hour, minute, second);
    if (dt.month != month || dt.day != day) return null;
    return dt;
  }
}

class _Header {
  final String timestamp;
  final String? sender;
  final String body;
  _Header(this.timestamp, this.sender, this.body);
}
