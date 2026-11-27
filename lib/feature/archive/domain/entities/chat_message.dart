import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

/// One message (or system line) of a WhatsApp text export.
///
/// Identity for merging purposes is [key], a SHA-1 hex digest over the
/// normalized timestamp, sender and trimmed text. A digest (rather than the
/// concatenated string) is used because it is fixed-length (40 chars): cheap
/// to compare thousands of times while merging, and small enough to persist
/// as `ArchivedGroup.lastMessageKey`. SHA-1 is used purely as a fingerprint,
/// not for security. Fields are separated by NUL characters so that
/// ("ab", "c") and ("a", "bc") never collide, and a `null` sender is encoded
/// differently from an empty-string sender.
class ChatMessage extends Equatable {
  /// Timestamp text as exported (date, separator, time), after
  /// [normalizeText]. Brackets (iOS) and the ` - ` (Android) are NOT part of
  /// it. Empty for the synthetic leading message that holds lines found
  /// before the first timestamp.
  final String rawTimestamp;

  /// Sender display name / phone number, or `null` for system messages.
  final String? sender;

  /// Message body; multi-line bodies are joined with `\n`. Normalized with
  /// [normalizeText] (LRM/RLM stripped, narrow/no-break spaces to spaces).
  final String text;

  /// The original lines of this message, verbatim (no line terminators),
  /// including the header line. Used for faithful re-serialization.
  final List<String> rawLines;

  /// Stable merge identity, see class docs.
  final String key;

  ChatMessage({
    required this.rawTimestamp,
    required this.sender,
    required this.text,
    required this.rawLines,
  }) : key = computeKey(rawTimestamp, sender, text);

  /// True when the message has no sender (group events, encryption notice,
  /// leading orphan lines).
  bool get isSystem => sender == null;

  /// Computes the merge key. Public so tests/callers can derive keys.
  static String computeKey(String rawTimestamp, String? sender, String text) {
    final senderPart = sender == null ? '-' : '+$sender';
    final input = '$rawTimestamp\u0000$senderPart\u0000${text.trim()}';
    return sha1.convert(utf8.encode(input)).toString();
  }

  static final RegExp _invisibleMarks = RegExp('[\u200E\u200F\uFEFF]');
  static final RegExp _oddSpaces = RegExp('[\u202F\u00A0]');

  /// Strips U+200E / U+200F (and a stray BOM U+FEFF) and converts U+202F
  /// (narrow no-break space) and U+00A0 to a normal space. Does not trim.
  static String normalizeText(String s) =>
      s.replaceAll(_invisibleMarks, '').replaceAll(_oddSpaces, ' ');

  /// [normalizeText] followed by trim.
  static String normalizeTimestamp(String s) => normalizeText(s).trim();

  @override
  List<Object?> get props => [rawTimestamp, sender, text, rawLines];

  @override
  String toString() => 'ChatMessage($rawTimestamp | $sender | $text)';
}
