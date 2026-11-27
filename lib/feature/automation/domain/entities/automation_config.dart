import 'package:equatable/equatable.dart';

/// One group as native needs to know it.
class AutomationGroupConfig extends Equatable {
  final String id;
  final String name;
  final bool enabled;

  const AutomationGroupConfig({
    required this.id,
    required this.name,
    required this.enabled,
  });

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'enabled': enabled};

  factory AutomationGroupConfig.fromMap(Map<dynamic, dynamic> map) =>
      AutomationGroupConfig(
        id: map['id'] as String,
        name: map['name'] as String,
        enabled: map['enabled'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [id, name, enabled];
}

/// Config persisted natively so the unlock trigger works with the UI closed.
class AutomationConfig extends Equatable {
  final bool enabled;

  /// 0-23
  final int morningHour;
  final List<AutomationGroupConfig> groups;

  const AutomationConfig({
    required this.enabled,
    required this.morningHour,
    required this.groups,
  });

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'morningHour': morningHour,
        'groups': [for (final g in groups) g.toMap()],
      };

  factory AutomationConfig.fromMap(Map<dynamic, dynamic> map) {
    final raw = map['groups'];
    return AutomationConfig(
      enabled: map['enabled'] as bool? ?? false,
      morningHour: (map['morningHour'] as num?)?.toInt() ?? 7,
      groups: raw is List
          ? [
              for (final g in raw)
                if (g is Map) AutomationGroupConfig.fromMap(g),
            ]
          : const [],
    );
  }

  @override
  List<Object?> get props => [enabled, morningHour, groups];
}
