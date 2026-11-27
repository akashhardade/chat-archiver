import 'dart:async';
import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_settings_repository.dart';
import 'package:chat_archiver/feature/archive/domain/repositories/archive_state_repository.dart';
import 'package:chat_archiver/feature/archive/domain/services/drive_layout.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_config.dart';
import 'package:chat_archiver/feature/automation/domain/repositories/automation_bridge.dart';

/// Single owner of the persisted group list and automation settings.
///
/// * All read-modify-write operations are serialized, so the sync
///   orchestrator (which updates per-group state in the background) and the
///   UI (which edits titles / toggles) cannot overwrite each other.
/// * Every change of groups, morning hour or the enabled switch is pushed to
///   native through `saveConfig`, so the unlock trigger works with the UI
///   closed. State-only updates ([updateGroupState]) do not need a push.
class ArchiveConfigService {
  final ArchiveStateRepository _state;
  final ArchiveSettingsRepository _settings;
  final AutomationBridge _bridge;
  final String Function() _newId;
  final bool Function() _driveConnected;

  Future<void> _tail = Future<void>.value();
  final StreamController<void> _changes = StreamController<void>.broadcast();

  ArchiveConfigService({
    required ArchiveStateRepository state,
    required ArchiveSettingsRepository settings,
    required AutomationBridge bridge,
    String Function()? idGenerator,
    bool Function()? isDriveConnected,
  })  : _state = state,
        _settings = settings,
        _bridge = bridge,
        _newId = idGenerator ?? _defaultId,
        _driveConnected = isDriveConnected ?? _always;

  static bool _always() => true;

  static final Random _random = Random();
  static String _defaultId() =>
      'g${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 20).toRadixString(36)}';

  /// Fires after every persisted change (config or state).
  Stream<void> get changes => _changes.stream;

  ArchiveSettingsRepository get settings => _settings;

  /// Normalised form of a group title used for matching: invisible marks and
  /// odd spaces removed, whitespace collapsed and trimmed. Case is kept
  /// (WhatsApp titles are case sensitive).
  static final RegExp _invisible = RegExp(
    '[${String.fromCharCodes(const [0x200E, 0x200F, 0xFEFF, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069])}]',
  );
  static final RegExp _oddSpaces = RegExp(
    '[${String.fromCharCodes(const [0x202F, 0x00A0])}]',
  );

  static String normalizeName(String s) => s
      .replaceAll(_invisible, '')
      .replaceAll(_oddSpaces, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<List<ArchivedGroup>> _load() async =>
      (await _state.loadGroups()).fold((_) => <ArchivedGroup>[], (g) => g);

  Future<Either<Failure, Unit>> _save(List<ArchivedGroup> groups) async {
    final r = await _state.saveGroups(groups);
    if (r.isRight()) _changes.add(null);
    return r;
  }

  // ------------------------------------------------------------------ read

  Future<List<ArchivedGroup>> groups() => _serialized(_load);

  Future<ArchivedGroup?> groupById(String id) async {
    for (final g in await groups()) {
      if (g.id == id) return g;
    }
    return null;
  }

  // ----------------------------------------------------------------- write

  Future<Either<Failure, ArchivedGroup>> addGroup(String name) {
    return _serialized<Either<Failure, ArchivedGroup>>(() async {
      final title = normalizeName(name);
      final groups = await _load();
      final invalid = _validate(title, groups, exceptId: null);
      if (invalid != null) return Left<Failure, ArchivedGroup>(invalid);
      final group = ArchivedGroup(id: _newId(), name: title);
      final saved = await _save([...groups, group]);
      return saved.fold(
        (f) => Left<Failure, ArchivedGroup>(f),
        (_) => Right<Failure, ArchivedGroup>(group),
      );
    }).then(_pushAfter);
  }

  /// Changes the title. A group that already has an archive gets a fresh id
  /// (and therefore a fresh archive and Drive folder): the old archive stays
  /// where it is.
  Future<Either<Failure, ArchivedGroup>> renameGroup(String id, String name) {
    return _serialized<Either<Failure, ArchivedGroup>>(() async {
      final title = normalizeName(name);
      final groups = await _load();
      final index = groups.indexWhere((g) => g.id == id);
      if (index < 0) {
        return const Left<Failure, ArchivedGroup>(
          NotFoundFailure('Group not found'),
        );
      }
      final current = groups[index];
      if (current.name == title) return Right<Failure, ArchivedGroup>(current);
      final invalid = _validate(title, groups, exceptId: id);
      if (invalid != null) return Left<Failure, ArchivedGroup>(invalid);
      final updated = current.messageCount > 0 || current.lastMessageKey != null
          ? ArchivedGroup(id: _newId(), name: title, enabled: current.enabled)
          : current.copyWith(
              name: title,
              status: GroupSyncStatus.neverSynced,
              lastError: null,
            );
      final next = [...groups]..[index] = updated;
      final saved = await _save(next);
      return saved.fold(
        (f) => Left<Failure, ArchivedGroup>(f),
        (_) => Right<Failure, ArchivedGroup>(updated),
      );
    }).then(_pushAfter);
  }

  Future<Either<Failure, Unit>> removeGroup(String id) {
    return _serialized<Either<Failure, Unit>>(() async {
      final groups = await _load();
      return _save([for (final g in groups) if (g.id != id) g]);
    }).then(_pushAfter);
  }

  Future<Either<Failure, Unit>> setGroupEnabled(String id, bool enabled) {
    return _serialized<Either<Failure, Unit>>(() async {
      final groups = await _load();
      return _save([
        for (final g in groups) g.id == id ? g.copyWith(enabled: enabled) : g,
      ]);
    }).then(_pushAfter);
  }

  Future<void> setMorningHour(int hour) async {
    await _settings.setMorningHour(hour);
    _changes.add(null);
    await pushConfig();
  }

  Future<void> setAutomationEnabled(bool enabled) async {
    await _settings.setAutomationEnabled(enabled);
    _changes.add(null);
    await pushConfig();
  }

  /// Applies [transform] to the stored group [id] (if it still exists).
  /// [transform] receives the CURRENT stored group, so concurrent title or
  /// toggle edits are never overwritten. No config push (state only).
  Future<void> updateGroupState(
    String id,
    ArchivedGroup Function(ArchivedGroup current) transform,
  ) {
    return _serialized(() async {
      final groups = await _load();
      final index = groups.indexWhere((g) => g.id == id);
      if (index < 0) return;
      final updated = transform(groups[index]);
      // Never let a state update change identity or user-editable config.
      final next = [...groups]
        ..[index] = updated.copyWith(
          id: groups[index].id,
          name: groups[index].name,
          enabled: groups[index].enabled,
        );
      await _save(next);
    });
  }

  // ------------------------------------------------------------------ push

  /// Sends groups, morning hour and the enabled switch to native. Returns
  /// false (never throws) when native is unreachable.
  ///
  /// Automatic (unlock) runs stay off until the setup wizard is finished, so
  /// WhatsApp does not open by itself while the client is still setting up,
  /// and while Google Drive is disconnected (nothing could be uploaded).
  Future<bool> pushConfig() async {
    try {
      final groups = await this.groups();
      await _bridge.saveConfig(
        AutomationConfig(
          enabled: _settings.automationEnabled &&
              _settings.setupComplete &&
              _driveConnected(),
          morningHour: _settings.morningHour,
          groups: [
            for (final g in groups)
              AutomationGroupConfig(id: g.id, name: g.name, enabled: g.enabled),
          ],
        ),
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('saveConfig failed: $e');
      return false;
    }
  }

  Future<Either<Failure, T>> _pushAfter<T>(Either<Failure, T> result) async {
    if (result.isRight()) await pushConfig();
    return result;
  }

  Failure? _validate(
    String title,
    List<ArchivedGroup> groups, {
    required String? exceptId,
  }) {
    if (title.isEmpty) {
      return const ValidationFailure('Enter the exact WhatsApp group title.');
    }
    final folder = DriveLayout.groupFolderName(title, 'x');
    for (final g in groups) {
      if (g.id == exceptId) continue;
      if (g.name == title) {
        return const ValidationFailure('This group is already in the list.');
      }
      if (DriveLayout.groupFolderName(g.name, 'x') == folder) {
        return const ValidationFailure(
          'Another group would use the same Google Drive folder name.',
        );
      }
    }
    return null;
  }

  void dispose() => _changes.close();
}
