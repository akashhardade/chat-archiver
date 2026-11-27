import 'package:chat_archiver/feature/archive/domain/entities/chat_message.dart';

/// Serializes messages back to transcript text using each message's verbatim
/// [ChatMessage.rawLines], so that
/// `TranscriptParser.parse(TranscriptWriter.write(m))` yields the same keys
/// as `m`.
///
/// Lines are joined with `\n` (never CRLF); non-empty output always ends with
/// a single trailing `\n`; an empty list yields an empty string. No BOM is
/// written.
class TranscriptWriter {
  const TranscriptWriter();

  static String write(Iterable<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      for (final line in message.rawLines) {
        buffer
          ..write(line.replaceAll('\r', ''))
          ..write('\n');
      }
    }
    return buffer.toString();
  }
}
