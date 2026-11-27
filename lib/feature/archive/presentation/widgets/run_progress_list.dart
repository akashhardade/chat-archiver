import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/core/constants/app_colors.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_errors.dart';

/// Per-group progress of the current sync, driven by native events.
class RunProgressList extends StatelessWidget {
  const RunProgressList({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SyncCoordinator>();
    final theme = Theme.of(context);
    return Obx(() {
      final groups = c.groups.where((g) => g.enabled).toList();
      final progress = Map<String, RunGroupProgress>.of(c.runProgress);
      final errors = Map<String, String>.of(c.runErrors);
      final processing = c.processing.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _icon(progress[g.id], processing),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name, style: theme.textTheme.bodyMedium),
                        if (errors[g.id] != null)
                          Text(
                            AutomationErrorCodes.describe(errors[g.id]),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColorConst.danger,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _icon(RunGroupProgress? p, bool uploading) {
    switch (p) {
      case RunGroupProgress.exporting:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
      case RunGroupProgress.exported:
        return Icon(
          uploading ? Icons.cloud_upload_outlined : Icons.check_circle,
          size: 20,
          color: AppColorConst.success,
        );
      case RunGroupProgress.failed:
        return Icon(Icons.error, size: 20, color: AppColorConst.danger);
      case RunGroupProgress.waiting:
      case null:
        return Icon(Icons.radio_button_unchecked, size: 20, color: AppColorConst.grey);
    }
  }
}
