import 'package:intl/intl.dart';

/// Human friendly time helpers (English).
class TimeFormat {
  TimeFormat._();

  /// "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago", or a date
  /// for anything older than a week.
  static String relative(DateTime t, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final diff = current.difference(t);
    if (diff.isNegative || diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    final sameDay = t.year == current.year &&
        t.month == current.month &&
        t.day == current.day;
    if (diff.inHours < 24 && sameDay) return '${diff.inHours} h ago';
    final today = DateTime(current.year, current.month, current.day);
    final thatDay = DateTime(t.year, t.month, t.day);
    final days = today.difference(thatDay).inDays;
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    return DateFormat.yMMMd().format(t);
  }

  /// `7:00 AM`, `12:00 PM`, `12:00 AM` for hour 0-23.
  static String hour(int hour24) {
    final h = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$h:00 ${hour24 < 12 ? 'AM' : 'PM'}';
  }

  /// Date and time, e.g. `13 Mar, 9:05 AM`.
  static String dateTime(DateTime t) => DateFormat('d MMM, h:mm a').format(t);
}
