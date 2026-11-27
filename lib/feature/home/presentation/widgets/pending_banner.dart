import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/constants/app_colors.dart';
import 'package:chat_archiver/core/widgets/app_card.dart';
import 'package:chat_archiver/feature/archive/domain/entities/archived_group.dart';
import 'package:chat_archiver/feature/archive/domain/usecases/sync_orchestrator.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_errors.dart';

/// Banner for exports that are waiting: unmatched titles or failed uploads.
class PendingBanner extends StatelessWidget {
  final List<PendingStatus> items;
  final bool busy;
  final VoidCallback onRetry;
  final void Function(PendingStatus item) onDiscard;

  const PendingBanner({
    super.key,
    required this.items,
    required this.busy,
    required this.onRetry,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      tint: AppColorConst.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.inbox_outlined, color: AppColorConst.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  TranslatorConst.pendingBannerTitle.tr,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            TranslatorConst.pendingBannerBody.trParams({
              'count': '${items.length}',
            }),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.export.groupName.trim().isEmpty
                              ? item.export.fileName
                              : item.export.groupName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _reason(item),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => onDiscard(item),
                    child: Text(TranslatorConst.pendingDiscard.tr),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : onRetry,
            child: Text(TranslatorConst.pendingRetry.tr),
          ),
        ],
      ),
    );
  }

  String _reason(PendingStatus item) {
    final group = item.group;
    if (group == null && item.export.groupName.trim().isEmpty) {
      return TranslatorConst.pendingUnknown.tr;
    }
    if (group == null) {
      return TranslatorConst.pendingUnmatched.trParams({
        'name': item.export.groupName,
      });
    }
    if (group.status == GroupSyncStatus.failed && group.lastError != null) {
      return AutomationErrorCodes.describe(group.lastError);
    }
    return TranslatorConst.syncProcessing.tr;
  }
}
