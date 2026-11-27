import 'package:chat_archiver/feature/archive/domain/entities/chat_message.dart';
import 'package:chat_archiver/feature/archive/domain/services/transcript_parser.dart';

/// Invisible / unusual characters, built from code points so the source file
/// never contains them literally.
final String lrm = String.fromCharCode(0x200E);
final String rlm = String.fromCharCode(0x200F);
final String nnbsp = String.fromCharCode(0x202F);
final String nbsp = String.fromCharCode(0x00A0);
final String bom = String.fromCharCode(0xFEFF);

/// Builds a single-line Android-style message for merger tests.
ChatMessage msg(String ts, String? sender, String text) {
  final line = sender == null ? '$ts - $text' : '$ts - $sender: $text';
  return ChatMessage(
    rawTimestamp: ts,
    sender: sender,
    text: text,
    rawLines: [line],
  );
}

/// Builds `count` sequential distinct messages "m<i>" with minute timestamps.
List<ChatMessage> seq(int from, int count, {String sender = 'Alice'}) => [
      for (var i = from; i < from + count; i++)
        msg('12/03/2026, 10:${i.toString().padLeft(2, '0')}', sender, 'm$i'),
    ];

List<String> keys(List<ChatMessage> ms) => [for (final m in ms) m.key];

List<String> texts(List<ChatMessage> ms) => [for (final m in ms) m.text];

List<ChatMessage> parse(String s) => TranscriptParser.parse(s);

/// Android 24h transcript with fictitious people.
const String androidSample = '12/03/2026, 14:05 - Messages and calls are '
    'end-to-end encrypted. No one outside of this chat, not even WhatsApp, '
    'can read or listen to them. Tap to learn more.\n'
    '12/03/2026, 14:05 - Alice created group "Book Club"\n'
    '12/03/2026, 14:06 - Alice added Bob\n'
    '12/03/2026, 14:07 - Alice: hi everyone\n'
    '12/03/2026, 14:08 - Bob: hello!\n'
    'second line of bob\n'
    '\n'
    'after a blank line\n'
    '12/03/2026, 14:09 - Alice: <Media omitted>\n'
    '12/03/2026, 14:10 - Bob: This message was deleted\n'
    '12/03/2026, 14:11 - Alice: fixed typo <This message was edited>\n';
