import 'package:equatable/equatable.dart';

/// Outcome of the last sync attempt for a group.
enum GroupSyncStatus { neverSynced, ok, gap, failed, needsAttention }

const Object _unset = Object();

/// A WhatsApp group selected for archiving, plus its sync state.
class ArchivedGroup extends Equatable {
  /// Stable local identifier (not shown to the user).
  final String id;

  /// Exact WhatsApp group title (used to find the chat via accessibility).
  final String name;
  final bool enabled;

  /// When the last fully uploaded run finished.
  final DateTime? lastSuccessAt;

  /// [ChatMessage.key] of the newest message in the archive.
  final String? lastMessageKey;

  /// Number of messages in the archive.
  final int messageCount;
  final GroupSyncStatus status;
  final String? lastError;

  const ArchivedGroup({
    required this.id,
    required this.name,
    this.enabled = true,
    this.lastSuccessAt,
    this.lastMessageKey,
    this.messageCount = 0,
    this.status = GroupSyncStatus.neverSynced,
    this.lastError,
  });

  /// Nullable fields ([lastSuccessAt], [lastMessageKey], [lastError]) can be
  /// reset to `null` by passing `null` explicitly; omitting them keeps the
  /// current value.
  ArchivedGroup copyWith({
    String? id,
    String? name,
    bool? enabled,
    Object? lastSuccessAt = _unset,
    Object? lastMessageKey = _unset,
    int? messageCount,
    GroupSyncStatus? status,
    Object? lastError = _unset,
  }) {
    return ArchivedGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      lastSuccessAt: identical(lastSuccessAt, _unset)
          ? this.lastSuccessAt
          : lastSuccessAt as DateTime?,
      lastMessageKey: identical(lastMessageKey, _unset)
          ? this.lastMessageKey
          : lastMessageKey as String?,
      messageCount: messageCount ?? this.messageCount,
      status: status ?? this.status,
      lastError: identical(lastError, _unset)
          ? this.lastError
          : lastError as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'lastSuccessAt': lastSuccessAt?.toUtc().toIso8601String(),
        'lastMessageKey': lastMessageKey,
        'messageCount': messageCount,
        'status': status.name,
        'lastError': lastError,
      };

  factory ArchivedGroup.fromJson(Map<String, dynamic> json) {
    final lastSuccess = json['lastSuccessAt'] as String?;
    return ArchivedGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      enabled: json['enabled'] as bool? ?? true,
      lastSuccessAt: lastSuccess == null ? null : DateTime.tryParse(lastSuccess),
      lastMessageKey: json['lastMessageKey'] as String?,
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      status: GroupSyncStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => GroupSyncStatus.neverSynced,
      ),
      lastError: json['lastError'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        enabled,
        lastSuccessAt,
        lastMessageKey,
        messageCount,
        status,
        lastError,
      ];
}
