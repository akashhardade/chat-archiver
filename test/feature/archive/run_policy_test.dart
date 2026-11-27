import 'package:chat_archiver/feature/archive/domain/services/run_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dateKey', () {
    test('zero pads', () {
      expect(RunPolicy.dateKey(DateTime(2026, 3, 5, 23, 59)), '2026-03-05');
      expect(RunPolicy.dateKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('shouldRunOnUnlock', () {
    test('before morning hour -> false', () {
      expect(
          RunPolicy.shouldRunOnUnlock(
              now: DateTime(2026, 3, 12, 5, 59),
              morningHour: 6,
              lastSuccessfulRunDate: null),
          isFalse);
    });

    test('exactly at morning hour and never ran -> true', () {
      expect(
          RunPolicy.shouldRunOnUnlock(
              now: DateTime(2026, 3, 12, 6, 0),
              morningHour: 6,
              lastSuccessfulRunDate: null),
          isTrue);
    });

    test('after morning hour, last success yesterday -> true', () {
      expect(
          RunPolicy.shouldRunOnUnlock(
              now: DateTime(2026, 3, 12, 14, 0),
              morningHour: 6,
              lastSuccessfulRunDate: '2026-03-11'),
          isTrue);
    });

    test('already succeeded today -> false', () {
      expect(
          RunPolicy.shouldRunOnUnlock(
              now: DateTime(2026, 3, 12, 14, 0),
              morningHour: 6,
              lastSuccessfulRunDate: '2026-03-12'),
          isFalse);
    });

    test('morningHour 0 runs any time of day', () {
      expect(
          RunPolicy.shouldRunOnUnlock(
              now: DateTime(2026, 3, 12, 0, 1),
              morningHour: 0,
              lastSuccessfulRunDate: '2026-03-11'),
          isTrue);
    });

    test('past midnight counts as a new day', () {
      expect(
          RunPolicy.shouldRunOnUnlock(
              now: DateTime(2026, 3, 13, 7, 0),
              morningHour: 6,
              lastSuccessfulRunDate: '2026-03-12'),
          isTrue);
    });

    test('key from dateKey round trips with policy', () {
      final now = DateTime(2026, 3, 12, 9);
      expect(
          RunPolicy.shouldRunOnUnlock(
              now: now,
              morningHour: 6,
              lastSuccessfulRunDate: RunPolicy.dateKey(now)),
          isFalse);
    });
  });
}
