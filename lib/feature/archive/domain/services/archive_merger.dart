import 'package:chat_archiver/feature/archive/domain/entities/chat_message.dart';

/// Outcome category of an [ArchiveMerger.merge].
enum MergeStatus {
  /// The archive was empty; every snapshot message is new.
  initial,

  /// The archive tail was found in the snapshot and messages follow it.
  appended,

  /// The archive tail was found at the very end of the snapshot.
  noChange,

  /// No anchor could be found; [MergeResult.newMessages] is the whole
  /// snapshot and the caller must decide what to do.
  gap,
}

/// Result of [ArchiveMerger.merge].
class MergeResult {
  final MergeStatus status;

  /// Messages to append to the archive, in order. For [MergeStatus.gap] this
  /// is the entire snapshot (NOT safe to append blindly).
  final List<ChatMessage> newMessages;

  /// Index in the snapshot of the LAST message of the matched anchor run, or
  /// -1 when there was no anchor ([MergeStatus.initial] / [MergeStatus.gap]).
  final int anchorIndex;

  /// Number of consecutive messages that matched (1..5), 0 if no anchor.
  final int anchorLength;

  /// How many archive tail messages were NOT part of the anchor (0..3). A
  /// value above 0 means the newest archived message(s) no longer match the
  /// snapshot (edited / deleted in WhatsApp).
  final int anchorTailOffset;

  /// How many snapshot messages right after the anchor were recognised as
  /// edited/deleted versions of already-archived messages and skipped.
  final int skippedAsEdited;

  const MergeResult({
    required this.status,
    required this.newMessages,
    this.anchorIndex = -1,
    this.anchorLength = 0,
    this.anchorTailOffset = 0,
    this.skippedAsEdited = 0,
  });
}

/// Merges a full WhatsApp export snapshot into an existing incremental
/// archive. Pure function, no I/O.
///
/// ## Model
/// Every export is a FULL snapshot of what the phone currently holds (the
/// oldest end may be truncated). Messages are identified by
/// [ChatMessage.key] (timestamp + sender + text), never by parsed dates.
///
/// ## Exact rule
/// Let `A` be the archive (length n) and `S` the snapshot.
///
/// 1. `A` empty -> [MergeStatus.initial], new = all of `S`.
/// 2. Candidate anchors are runs of `k` consecutive archive messages ending
///    `d` messages before the archive tail, i.e. `A[n-d-k .. n-d-1]`, for
///    `k` in 5..1 (outer loop, longest first) and `d` in 0..3 (inner loop,
///    closest to the tail first); windows that do not fit (`n-d-k < 0`) are
///    skipped. The first candidate whose key sequence occurs contiguously in
///    `S` wins; if the run occurs several times, the LAST occurrence in `S`
///    is used. `d > 0` is the tolerance for the newest archived message(s)
///    having been edited or deleted in WhatsApp since the last run (their
///    text, hence key, changed).
/// 3. Identical-run refinement: if the matched end message `S[e]` belongs to a
///    run of identical keys, let `rA` be the length of the identical-key run
///    ending at the matched archive message and `R` the length of the
///    maximal identical-key run containing `S[e]`. When `R >= rA` the anchor
///    end is moved to `s + rA - 1` (s = start of that run in `S`), so the
///    surplus `R - rA` identical copies count as new (e.g. archive has 3
///    identical "ok", snapshot has 4 -> exactly one new "ok").
/// 4. Edited-skip (only when `d > 0`): walking the `d` unmatched archive
///    tail messages in order, a snapshot message directly after the anchor
///    is skipped (not re-added) if it has the same `rawTimestamp` and
///    `sender` as the next unmatched archive message; if it does not, that
///    archive message is considered removed from the phone and nothing is
///    skipped for it. Skipping is therefore bounded by `d` and by actual
///    timestamp+sender correspondence.
/// 5. Everything after the anchor (and skipped messages) is new. If nothing
///    is left -> [MergeStatus.noChange], else [MergeStatus.appended].
/// 6. No candidate matched -> [MergeStatus.gap], new = whole `S`
///    ([MergeResult.anchorIndex] = -1).
///
/// ## Limitations
/// * Messages with an identical key (same minute, sender and text) that are
///   separated by other messages are ambiguous; the LAST occurrence wins.
/// * If a newly arrived message shares timestamp and sender with an archived
///   message that was deleted-for-me, it can be mis-skipped (step 4).
/// * Edits/deletions older than the 3 newest archived messages are only
///   tolerated if some unchanged window of up to 5 messages ends within the
///   newest 4; otherwise the result is [MergeStatus.gap].
/// * Messages inserted into the middle/past of the snapshot (late sync) are
///   not detected.
class ArchiveMerger {
  const ArchiveMerger();

  static const int maxAnchorLength = 5;
  static const int maxTailOffset = 3;

  static MergeResult merge({
    required List<ChatMessage> archive,
    required List<ChatMessage> snapshot,
  }) {
    if (archive.isEmpty) {
      return MergeResult(
        status: MergeStatus.initial,
        newMessages: List<ChatMessage>.unmodifiable(snapshot),
      );
    }
    final n = archive.length;
    final aKeys = [for (final m in archive) m.key];
    final sKeys = [for (final m in snapshot) m.key];

    for (var k = maxAnchorLength; k >= 1; k--) {
      for (var d = 0; d <= maxTailOffset; d++) {
        final start = n - d - k;
        if (start < 0) continue;
        final p = _lastOccurrence(sKeys, aKeys, start, k);
        if (p < 0) continue;
        return _buildResult(
          archive: archive,
          snapshot: snapshot,
          aKeys: aKeys,
          sKeys: sKeys,
          matchedArchiveEnd: n - d - 1,
          snapshotEnd: p + k - 1,
          k: k,
          d: d,
        );
      }
    }
    return MergeResult(
      status: MergeStatus.gap,
      newMessages: List<ChatMessage>.unmodifiable(snapshot),
    );
  }

  static int _lastOccurrence(
      List<String> s, List<String> a, int aStart, int k) {
    for (var p = s.length - k; p >= 0; p--) {
      var ok = true;
      for (var i = 0; i < k; i++) {
        if (s[p + i] != a[aStart + i]) {
          ok = false;
          break;
        }
      }
      if (ok) return p;
    }
    return -1;
  }

  static MergeResult _buildResult({
    required List<ChatMessage> archive,
    required List<ChatMessage> snapshot,
    required List<String> aKeys,
    required List<String> sKeys,
    required int matchedArchiveEnd,
    required int snapshotEnd,
    required int k,
    required int d,
  }) {
    var e = snapshotEnd;

    // Identical-run refinement (rule 3).
    final key = sKeys[e];
    var rA = 0;
    for (var i = matchedArchiveEnd; i >= 0 && aKeys[i] == key; i--) {
      rA++;
    }
    var s = e;
    while (s > 0 && sKeys[s - 1] == key) {
      s--;
    }
    var t = e;
    while (t < sKeys.length - 1 && sKeys[t + 1] == key) {
      t++;
    }
    final runLen = t - s + 1;
    if (runLen >= rA && rA > 0) {
      e = s + rA - 1;
    }

    // Edited-skip (rule 4).
    var next = e + 1;
    var skipped = 0;
    final n = archive.length;
    for (var i = n - d; i < n; i++) {
      if (next >= snapshot.length) break;
      final a = archive[i];
      final c = snapshot[next];
      if (c.rawTimestamp == a.rawTimestamp && c.sender == a.sender) {
        next++;
        skipped++;
      }
    }

    final newMessages = snapshot.sublist(next);
    return MergeResult(
      status:
          newMessages.isEmpty ? MergeStatus.noChange : MergeStatus.appended,
      newMessages: List<ChatMessage>.unmodifiable(newMessages),
      anchorIndex: e,
      anchorLength: k,
      anchorTailOffset: d,
      skippedAsEdited: skipped,
    );
  }
}
