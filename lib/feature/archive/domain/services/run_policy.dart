/// Decides when the daily archive run should start.
class RunPolicy {
  const RunPolicy._();

  /// True when it is at or past [morningHour] (0-23, in the same clock as
  /// [now] - pass local time) and no run has succeeded yet today
  /// ([lastSuccessfulRunDate] is a `yyyy-MM-dd` key from [dateKey], or null).
  static bool shouldRunOnUnlock({
    required DateTime now,
    required int morningHour,
    required String? lastSuccessfulRunDate,
  }) {
    return now.hour >= morningHour && lastSuccessfulRunDate != dateKey(now);
  }

  /// `yyyy-MM-dd` of [d] as given (no time-zone conversion).
  static String dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
