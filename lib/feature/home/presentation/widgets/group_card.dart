import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/constants/app_colors.dart';
import 'package:chat_archiver/core/utils/time_format.dart';
import 'package:chat_archiver/core/widgets/app_card.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/group_status_view.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_errors.dart';

/// One group: status chip, last upload, archived count, last error.
class GroupCard extends StatelessWidget {
  final ArchivedGroup group;
  final VoidCallback? onAcceptBaseline;
  final DateTime? now;

  const GroupCard({
    super.key,
    required this.group,
    this.onAcceptBaseline,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = GroupStatusView.of(group);
    final lastSuccess = group.lastSuccessAt;
    final error = group.lastError;
    final isGap = group.status == GroupSyncStatus.gap && group.enabled;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(view: status),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.cloud_upload_outlined,
            label: TranslatorConst.lastUpload.tr,
            value: lastSuccess == null
                ? TranslatorConst.lastUploadNever.tr
                : TimeFormat.relative(lastSuccess.toLocal(), now: now),
          ),
          const SizedBox(height: 4),
          _InfoRow(
            icon: Icons.chat_bubble_outline,
            label: group.messageCount == 0
                ? TranslatorConst.messagesArchivedNone.tr
                : TranslatorConst.messagesArchived.trParams({
                    'count': '${group.messageCount}',
                  }),
          ),
          if (isGap) ...[
            const SizedBox(height: 10),
            Text(
              TranslatorConst.gapExplain.tr,
              style: theme.textTheme.bodySmall,
            ),
            if (onAcceptBaseline != null) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: onAcceptBaseline,
                child: Text(TranslatorConst.gapAccept.tr),
              ),
            ],
          ],
          if (error != null &&
              error.isNotEmpty &&
              group.status != GroupSyncStatus.ok &&
              !(isGap && error.startsWith('Export could not be aligned'))) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: status.color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    AutomationErrorCodes.describe(error),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: group.status == GroupSyncStatus.failed
                          ? AppColorConst.danger
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _InfoRow({required this.icon, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.textTheme.bodySmall?.color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value == null ? label : '$label: $value',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
