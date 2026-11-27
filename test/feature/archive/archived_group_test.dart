import 'dart:convert';

import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final full = ArchivedGroup(
    id: 'g1',
    name: 'Book Club \u{1F4DA}',
    enabled: false,
    lastSuccessAt: DateTime.utc(2026, 3, 12, 8, 30),
    lastMessageKey: 'abc',
    messageCount: 42,
    status: GroupSyncStatus.gap,
    lastError: 'boom',
  );

  test('defaults', () {
    const g = ArchivedGroup(id: 'g', name: 'N');
    expect(g.enabled, isTrue);
    expect(g.status, GroupSyncStatus.neverSynced);
    expect(g.messageCount, 0);
    expect(g.lastSuccessAt, isNull);
  });

  test('json round trip (through encode/decode)', () {
    final json = jsonDecode(jsonEncode(full.toJson())) as Map<String, dynamic>;
    final back = ArchivedGroup.fromJson(json);
    expect(back, full);
    expect(back.lastSuccessAt!.isAtSameMomentAs(full.lastSuccessAt!), isTrue);
  });

  test('json round trip with nulls', () {
    const g = ArchivedGroup(id: 'g', name: 'N');
    expect(ArchivedGroup.fromJson(g.toJson()), g);
  });

  test('fromJson tolerates missing/unknown fields', () {
    final g = ArchivedGroup.fromJson({
      'id': 'x',
      'name': 'Y',
      'status': 'somethingNew',
      'lastSuccessAt': 'not a date',
    });
    expect(g.status, GroupSyncStatus.neverSynced);
    expect(g.lastSuccessAt, isNull);
    expect(g.enabled, isTrue);
    expect(g.messageCount, 0);
  });

  test('every status survives json', () {
    for (final s in GroupSyncStatus.values) {
      final g = ArchivedGroup(id: 'g', name: 'N', status: s);
      expect(ArchivedGroup.fromJson(g.toJson()).status, s);
    }
  });

  test('copyWith changes only given fields', () {
    final c = full.copyWith(name: 'New', messageCount: 50);
    expect(c.name, 'New');
    expect(c.messageCount, 50);
    expect(c.id, full.id);
    expect(c.lastError, 'boom');
    expect(c.lastSuccessAt, full.lastSuccessAt);
  });

  test('copyWith can clear nullable fields with explicit null', () {
    final c = full.copyWith(
        lastError: null, lastMessageKey: null, lastSuccessAt: null);
    expect(c.lastError, isNull);
    expect(c.lastMessageKey, isNull);
    expect(c.lastSuccessAt, isNull);
    expect(c.status, GroupSyncStatus.gap);
  });

  test('value equality', () {
    expect(full.copyWith(), full);
    expect(full.copyWith(enabled: true), isNot(full));
  });
}
