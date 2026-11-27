import 'package:chat_archiver/feature/archive/domain/entities/chat_message.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_merger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'archive_test_helpers.dart';

MergeResult merge(List<ChatMessage> a, List<ChatMessage> s) =>
    ArchiveMerger.merge(archive: a, snapshot: s);

/// Applies a merge the way the use case does (append for initial/appended).
List<ChatMessage> apply(List<ChatMessage> a, MergeResult r) =>
    r.status == MergeStatus.gap ? a : [...a, ...r.newMessages];

void main() {
  group('basic statuses', () {
    test('empty archive -> initial with all messages', () {
      final s = seq(0, 4);
      final r = merge([], s);
      expect(r.status, MergeStatus.initial);
      expect(texts(r.newMessages), ['m0', 'm1', 'm2', 'm3']);
      expect(r.anchorIndex, -1);
    });

    test('empty archive and empty snapshot -> initial, nothing new', () {
      final r = merge([], []);
      expect(r.status, MergeStatus.initial);
      expect(r.newMessages, isEmpty);
    });

    test('identical snapshot -> noChange', () {
      final s = seq(0, 8);
      final r = merge(s, s);
      expect(r.status, MergeStatus.noChange);
      expect(r.newMessages, isEmpty);
      expect(r.anchorIndex, 7);
      expect(r.anchorLength, 5);
      expect(r.anchorTailOffset, 0);
    });

    test('only new messages after archive tail -> appended', () {
      final s = seq(0, 10);
      final r = merge(s.sublist(0, 6), s);
      expect(r.status, MergeStatus.appended);
      expect(texts(r.newMessages), ['m6', 'm7', 'm8', 'm9']);
      expect(r.anchorIndex, 5);
      expect(r.anchorLength, 5);
    });

    test('archive shorter than 5 uses its full length as anchor', () {
      final s = seq(0, 6);
      final r = merge(s.sublist(0, 2), s);
      expect(r.status, MergeStatus.appended);
      expect(r.anchorLength, 2);
      expect(texts(r.newMessages), ['m2', 'm3', 'm4', 'm5']);
    });

    test('single-message archive', () {
      final s = seq(0, 3);
      final r = merge(s.sublist(0, 1), s);
      expect(r.status, MergeStatus.appended);
      expect(texts(r.newMessages), ['m1', 'm2']);
    });
  });

  group('truncated history', () {
    test('snapshot lost its oldest messages but keeps archive tail', () {
      final all = seq(0, 20);
      final archive = all.sublist(0, 12);
      final snapshot = all.sublist(8); // oldest 8 truncated
      final r = merge(archive, snapshot);
      expect(r.status, MergeStatus.appended);
      expect(texts(r.newMessages), texts(all.sublist(12)));
      expect(r.anchorIndex, 3);
    });

    test('snapshot truncated to exactly the tail -> noChange', () {
      final all = seq(0, 12);
      final r = merge(all, all.sublist(7));
      expect(r.status, MergeStatus.noChange);
    });

    test('snapshot truncated so far that only part of the window remains', () {
      final all = seq(0, 12);
      // archive tail = m7..m11 but snapshot only starts at m10 (m10, m11, new).
      final snapshot = [...all.sublist(10), ...seq(12, 2)];
      final r = merge(all, snapshot);
      expect(r.status, MergeStatus.appended);
      expect(r.anchorLength, 2);
      expect(texts(r.newMessages), ['m12', 'm13']);
    });
  });

  group('gap', () {
    test('completely unrelated snapshot', () {
      final archive = seq(0, 6);
      final snapshot = seq(100, 5, sender: 'Zed');
      final r = merge(archive, snapshot);
      expect(r.status, MergeStatus.gap);
      expect(r.newMessages.length, 5);
      expect(r.anchorIndex, -1);
      expect(r.anchorLength, 0);
    });

    test('snapshot starts after archive tail (history gap)', () {
      final all = seq(0, 30);
      final r = merge(all.sublist(0, 10), all.sublist(15));
      expect(r.status, MergeStatus.gap);
      expect(texts(r.newMessages), texts(all.sublist(15)));
    });

    test('empty snapshot against non-empty archive -> gap with nothing', () {
      final r = merge(seq(0, 3), []);
      expect(r.status, MergeStatus.gap);
      expect(r.newMessages, isEmpty);
    });

    test('more than 3 newest archived messages changed -> gap', () {
      final all = seq(0, 12);
      final snapshot = [
        ...all.sublist(0, 6),
        for (var i = 6; i < 12; i++)
          msg('12/03/2026, 10:${i.toString().padLeft(2, '0')}', 'Alice', 'edited$i'),
      ];
      // Windows ending at A[n-1..n-4] all contain edited messages, but
      // k=1 at d=3 ends at m8 which is edited too; m5 sits at d=6.
      final r = merge(all, snapshot);
      expect(r.status, MergeStatus.gap);
    });
  });

  group('repeated identical messages', () {
    test('"ok" x3 same minute: archive has 3, snapshot has 3 -> noChange', () {
      final ok = msg('12/03/2026, 10:00', 'Bob', 'ok');
      final r = merge([ok, ok, ok], [ok, ok, ok]);
      expect(r.status, MergeStatus.noChange);
    });

    test('archive has 3 identical, snapshot has 4 -> exactly one new', () {
      final ok = msg('12/03/2026, 10:00', 'Bob', 'ok');
      final r = merge([ok, ok, ok], [ok, ok, ok, ok]);
      expect(r.status, MergeStatus.appended);
      expect(r.newMessages, hasLength(1));
    });

    test('identical run preceded by other message', () {
      final a = msg('12/03/2026, 09:00', 'Alice', 'start');
      final ok = msg('12/03/2026, 10:00', 'Bob', 'ok');
      final archive = [a, ok, ok, ok];
      final snapshot = [a, ok, ok, ok, ok, ok];
      final r = merge(archive, snapshot);
      expect(r.status, MergeStatus.appended);
      expect(r.newMessages, hasLength(2));
    });

    test('long identical run (more than anchor length)', () {
      final ok = msg('12/03/2026, 10:00', 'Bob', 'ok');
      final r = merge(List.filled(8, ok), List.filled(10, ok));
      expect(r.status, MergeStatus.appended);
      expect(r.newMessages, hasLength(2));
    });

    test('same text at different minutes are distinct messages', () {
      final a = msg('12/03/2026, 10:00', 'Bob', 'ok');
      final b = msg('12/03/2026, 10:01', 'Bob', 'ok');
      final c = msg('12/03/2026, 10:02', 'Bob', 'ok');
      final r = merge([a, b], [a, b, c]);
      expect(r.status, MergeStatus.appended);
      expect(r.newMessages, [c]);
    });

    test('same message text earlier in snapshot does not fool the anchor', () {
      final ok = msg('12/03/2026, 10:00', 'Bob', 'ok');
      final x = msg('12/03/2026, 10:01', 'Alice', 'x');
      final y = msg('12/03/2026, 10:02', 'Alice', 'y');
      final r = merge([ok, x], [ok, x, y, ok]);
      // Anchor [ok, x] is unique; both y and the later ok are new.
      expect(r.status, MergeStatus.appended);
      expect(r.newMessages, [y, ok]);
    });
  });

  group('edits and deletions of archived messages', () {
    List<ChatMessage> edited(List<ChatMessage> ms, int index, String newText) =>
        [
          for (var i = 0; i < ms.length; i++)
            i == index
                ? msg(ms[i].rawTimestamp, ms[i].sender, newText)
                : ms[i],
        ];

    test('newest archived message edited: anchor on earlier ones, no dup', () {
      final all = seq(0, 10);
      final archive = all.sublist(0, 8);
      final snapshot = [...edited(all, 7, 'm7 (edited)')]; // m8,m9 new
      final r = merge(archive, snapshot);
      expect(r.status, MergeStatus.appended);
      expect(texts(r.newMessages), ['m8', 'm9']);
      expect(r.anchorTailOffset, 1);
      expect(r.skippedAsEdited, 1);
      expect(r.anchorLength, 5);
    });

    test('newest archived message edited and nothing new -> noChange', () {
      final all = seq(0, 8);
      final r = merge(all, edited(all, 7, 'm7 (edited)'));
      expect(r.status, MergeStatus.noChange);
      expect(r.newMessages, isEmpty);
    });

    test('last 3 archived messages edited -> still anchors (d=3)', () {
      final all = seq(0, 12);
      final archive = all.sublist(0, 10);
      var snapshot = edited(all, 9, 'x9');
      snapshot = edited(snapshot, 8, 'x8');
      snapshot = edited(snapshot, 7, 'x7');
      final r = merge(archive, snapshot);
      expect(r.status, MergeStatus.appended);
      expect(texts(r.newMessages), ['m10', 'm11']);
      expect(r.anchorTailOffset, 3);
      expect(r.skippedAsEdited, 3);
    });

    test('edit in the middle of the tail window shortens the anchor', () {
      final all = seq(0, 12);
      final archive = all.sublist(0, 10);
      final snapshot = edited(all, 6, 'edited6'); // m6 changed, tail intact
      final r = merge(archive, snapshot);
      expect(r.status, MergeStatus.appended);
      expect(texts(r.newMessages), ['m10', 'm11']);
      expect(r.anchorLength, 3); // m7..m9
      expect(r.anchorTailOffset, 0);
    });

    test('message deleted-for-everyone (text replaced) behaves like an edit',
        () {
      final all = seq(0, 8);
      final snapshot = [
        ...edited(all, 7, 'This message was deleted'),
        ...seq(8, 1),
      ];
      final r = merge(all, snapshot);
      expect(texts(r.newMessages), ['m8']);
    });

    test('newest archived message removed from the phone entirely', () {
      final all = seq(0, 10);
      final archive = all.sublist(0, 8);
      // m7 vanished; m8, m9 are new.
      final snapshot = [...all.sublist(0, 7), all[8], all[9]];
      final r = merge(archive, snapshot);
      expect(r.status, MergeStatus.appended);
      expect(texts(r.newMessages), ['m8', 'm9']);
      expect(r.anchorTailOffset, 1);
      expect(r.skippedAsEdited, 0, reason: 'm8 has a different timestamp');
    });

    test('edited message with same-minute new message by another sender', () {
      final a0 = msg('12/03/2026, 10:00', 'Alice', 'a');
      final a1 = msg('12/03/2026, 10:01', 'Alice', 'b');
      final a2 = msg('12/03/2026, 10:02', 'Alice', 'c');
      final a3 = msg('12/03/2026, 10:03', 'Alice', 'd');
      final a4 = msg('12/03/2026, 10:04', 'Alice', 'e');
      final a5 = msg('12/03/2026, 10:05', 'Alice', 'f');
      final archive = [a0, a1, a2, a3, a4, a5];
      final f2 = msg('12/03/2026, 10:05', 'Alice', 'f edited');
      final newSameMinute = msg('12/03/2026, 10:05', 'Bob', 'reply');
      final r = merge(archive, [a0, a1, a2, a3, a4, f2, newSameMinute]);
      expect(r.status, MergeStatus.appended);
      expect(r.newMessages, [newSameMinute]);
    });

    test('edited tail plus truncated history', () {
      final all = seq(0, 20);
      final archive = all.sublist(0, 12);
      final snapshot = edited(all.sublist(6), 5, 'm11 edited'); // index 5 = m11
      final r = merge(archive, snapshot);
      expect(r.status, MergeStatus.appended);
      expect(texts(r.newMessages), texts(all.sublist(12)));
    });
  });

  group('idempotency', () {
    test('merging the same snapshot twice adds nothing the second time', () {
      final all = seq(0, 15);
      var archive = all.sublist(0, 9);
      final first = merge(archive, all);
      archive = apply(archive, first);
      expect(keys(archive), keys(all));
      final second = merge(archive, all);
      expect(second.status, MergeStatus.noChange);
      expect(second.newMessages, isEmpty);
    });

    test('idempotent after an edit-skip merge', () {
      final all = seq(0, 10);
      var archive = all.sublist(0, 8);
      final snapshot = [
        ...all.sublist(0, 7),
        msg(all[7].rawTimestamp, all[7].sender, 'edited'),
        all[8],
        all[9],
      ];
      final first = merge(archive, snapshot);
      archive = apply(archive, first);
      expect(archive, hasLength(10));
      final second = merge(archive, snapshot);
      expect(second.status, MergeStatus.noChange);
    });

    test('idempotent for identical repeated messages', () {
      final ok = msg('12/03/2026, 10:00', 'Bob', 'ok');
      var archive = <ChatMessage>[ok];
      final snapshot = [ok, ok, ok];
      final first = merge(archive, snapshot);
      archive = apply(archive, first);
      expect(archive, hasLength(3));
      expect(merge(archive, snapshot).status, MergeStatus.noChange);
    });

    test('initial then repeat', () {
      final s = seq(0, 7);
      var archive = <ChatMessage>[];
      archive = apply(archive, merge(archive, s));
      expect(archive, hasLength(7));
      expect(merge(archive, s).status, MergeStatus.noChange);
    });

    test('daily growth sequence stays consistent with truncation', () {
      final all = seq(0, 40);
      var archive = <ChatMessage>[];
      for (final end in [10, 14, 14, 22, 30, 40]) {
        final start = end > 15 ? end - 15 : 0; // phone keeps last 15 only
        final snapshot = all.sublist(start, end);
        archive = apply(archive, merge(archive, snapshot));
      }
      expect(keys(archive), keys(all));
    });
  });

  group('end to end with parser/writer', () {
    test('real-looking exports across days', () {
      const day1 = '12/03/2026, 14:05 - Alice: hi\n'
          '12/03/2026, 14:06 - Bob: yo\nsecond line\n';
      const day2 = '12/03/2026, 14:05 - Alice: hi\n'
          '12/03/2026, 14:06 - Bob: yo\nsecond line\n'
          '13/03/2026, 09:00 - Alice: morning\n';
      final archive = parse(day1);
      final r = merge(archive, parse(day2));
      expect(r.status, MergeStatus.appended);
      expect(texts(r.newMessages), ['morning']);
    });
  });
}
