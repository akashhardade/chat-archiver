import 'package:get/get.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/services/archive_config_service.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';

/// Add / edit / remove / toggle groups (used by Setup and Settings).
class GroupsController extends GetxController {
  final SyncCoordinator coordinator;
  final ArchiveConfigService config;

  GroupsController({required this.coordinator, required this.config});

  RxList<ArchivedGroup> get groups => coordinator.groups;

  /// Returns an error message, or null on success.
  Future<String?> add(String name) async {
    final r = await config.addGroup(name);
    await coordinator.loadLocal();
    return r.fold((f) => f.message, (_) => null);
  }

  /// Returns an error message, or null on success.
  Future<String?> rename(String id, String name) async {
    final r = await config.renameGroup(id, name);
    await coordinator.loadLocal();
    return r.fold((f) => f.message, (_) => null);
  }

  Future<void> remove(String id) async {
    await config.removeGroup(id);
    await coordinator.loadLocal();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await config.setGroupEnabled(id, enabled);
    await coordinator.loadLocal();
  }
}
