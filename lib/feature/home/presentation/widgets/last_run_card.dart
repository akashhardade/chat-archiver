import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/constants/app_colors.dart';
import 'package:chat_archiver/core/utils/time_format.dart';
import 'package:chat_archiver/core/widgets/app_card.dart';
import 'package:chat_archiver/feature/automation/domain/entities/automation_errors.dart';
import 'package:chat_archiver/feature/automation/domain/entities/run_report.dart';

/// Summary of the last native run.
class LastRunCard extends StatelessWidget {
  final RunReport? report;
  const LastRunCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = report;
    if (r == null) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.history, color: theme.disabledColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                TranslatorConst.lastRunNone.tr,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    final failed = r.results.where((x) => x.status == GroupRunStatus.failed);
    final total = r.results.where((x) => x.status != GroupRunStatus.skipped).length;
    final trigger = r.trigger == 'unlock'
        ? TranslatorConst.lastRunTriggerUnlock.tr
        : TranslatorConst.lastRunTriggerManual.tr;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                r.failedCount == 0 ? Icons.check_circle_outline : Icons.error_outline,
                color: r.failedCount == 0
                    ? AppColorConst.success
                    : AppColorConst.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  TranslatorConst.lastRun.tr,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                TimeFormat.relative(r.startedAt),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            TranslatorConst.lastRunSummary.trParams({
              'ok': '${r.exportedCount}',
              'total': '$total',
            }),
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            '$trigger  ·  ${TimeFormat.dateTime(r.startedAt)}',
            style: theme.textTheme.bodySmall,
          ),
          for (final f in failed) ...[
            const SizedBox(height: 8),
            Text(
              f.groupName,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              AutomationErrorCodes.describe(f.error ?? 'unknown'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColorConst.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
