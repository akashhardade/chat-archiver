import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/constants/app_colors.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';

/// Label, color and icon of a group's [GroupSyncStatus].
class GroupStatusView {
  final String label;
  final Color color;
  final IconData icon;

  const GroupStatusView(this.label, this.color, this.icon);

  factory GroupStatusView.of(ArchivedGroup g) {
    if (!g.enabled) {
      return GroupStatusView(
        TranslatorConst.statusDisabled.tr,
        AppColorConst.grey,
        Icons.pause_circle_outline,
      );
    }
    switch (g.status) {
      case GroupSyncStatus.neverSynced:
        return GroupStatusView(
          TranslatorConst.statusNeverSynced.tr,
          AppColorConst.grey,
          Icons.schedule,
        );
      case GroupSyncStatus.ok:
        return GroupStatusView(
          TranslatorConst.statusOk.tr,
          AppColorConst.success,
          Icons.check_circle_outline,
        );
      case GroupSyncStatus.gap:
        return GroupStatusView(
          TranslatorConst.statusGap.tr,
          AppColorConst.warning,
          Icons.help_outline,
        );
      case GroupSyncStatus.failed:
        return GroupStatusView(
          TranslatorConst.statusFailed.tr,
          AppColorConst.danger,
          Icons.error_outline,
        );
      case GroupSyncStatus.needsAttention:
        return GroupStatusView(
          TranslatorConst.statusNeedsAttention.tr,
          AppColorConst.warning,
          Icons.warning_amber_outlined,
        );
    }
  }
}

/// Small rounded chip showing a [GroupStatusView].
class StatusChip extends StatelessWidget {
  final GroupStatusView view;
  const StatusChip({super.key, required this.view});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: view.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(view.icon, size: 14, color: view.color),
          const SizedBox(width: 4),
          Text(
            view.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: view.color,
            ),
          ),
        ],
      ),
    );
  }
}
