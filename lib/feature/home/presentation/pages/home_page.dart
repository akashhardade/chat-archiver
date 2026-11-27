import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/constants/app_colors.dart';
import 'package:chat_archiver/core/widgets/app_card.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/run_progress_list.dart';
import 'package:chat_archiver/feature/home/presentation/view_model/home_controller.dart';
import 'package:chat_archiver/feature/home/presentation/widgets/group_card.dart';
import 'package:chat_archiver/feature/home/presentation/widgets/last_run_card.dart';
import 'package:chat_archiver/feature/home/presentation/widgets/pending_banner.dart';

class HomePage extends GetView<HomeController> {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller.coordinator;
    return Scaffold(
      appBar: AppBar(
        title: Text(TranslatorConst.homeTitle.tr),
        actions: [
          IconButton(
            tooltip: TranslatorConst.settingsTitle.tr,
            icon: const Icon(Icons.settings_outlined),
            onPressed: controller.openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.reload,
                child: Obx(() => _list(context, c)),
              ),
            ),
            _SyncBar(controller: controller),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, SyncCoordinator c) {
    final theme = Theme.of(context);
    final groups = c.groups.toList();
    final pending = c.pending.toList();
    final busy = c.isBusy;
    final widgets = <Widget>[];

    void gap() => widgets.add(const SizedBox(height: 12));

    if (c.driveEmail.value == null) {
      widgets.add(
        _FixBanner(
          text: TranslatorConst.bannerDriveOff.tr,
          onFix: controller.openSettings,
        ),
      );
      gap();
    }
    if (c.driveEmail.value != null && c.driveNeedsReconnect.value) {
      widgets.add(
        _FixBanner(
          text: TranslatorConst.bannerDriveReconnect.tr,
          actionLabel: TranslatorConst.driveReconnect.tr,
          onFix: controller.reconnectDrive,
        ),
      );
      gap();
    }
    if (!c.accessibilityEnabled.value) {
      widgets.add(
        _FixBanner(
          text: TranslatorConst.bannerAccessibilityOff.tr,
          onFix: controller.openSettings,
        ),
      );
      gap();
    }
    if (pending.isNotEmpty) {
      widgets.add(
        PendingBanner(
          items: pending,
          busy: c.processing.value,
          onRetry: controller.retryPending,
          onDiscard: (item) => controller.discard(context, item),
        ),
      );
      gap();
    }
    if (busy) {
      widgets.add(
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      c.processing.value && !c.nativeRunning.value
                          ? TranslatorConst.syncProcessing.tr
                          : (c.currentGroupName != null
                              ? TranslatorConst.syncRunning.trParams({
                                  'name': c.currentGroupName!,
                                })
                              : TranslatorConst.syncRunningGeneric.tr),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const RunProgressList(),
            ],
          ),
        ),
      );
      gap();
    }
    widgets.add(LastRunCard(report: c.lastReport.value));
    gap();
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
        child: Text(
          TranslatorConst.homeYourGroups.tr,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    if (groups.isEmpty) {
      widgets.add(
        AppCard(
          child: Text(
            TranslatorConst.homeNoGroups.tr,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    } else {
      for (final g in groups) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GroupCard(
              group: g,
              onAcceptBaseline:
                  busy ? null : () => controller.acceptBaseline(context, g),
            ),
          ),
        );
      }
    }
    widgets.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_open_outlined, size: 16, color: theme.disabledColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                TranslatorConst.keepUnlockedNote.tr,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      children: widgets,
    );
  }
}

class _SyncBar extends StatelessWidget {
  final HomeController controller;
  const _SyncBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final reason = controller.syncDisabledReason;
      final busy = controller.coordinator.isBusy;
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: reason == null ? controller.syncNow : null,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(TranslatorConst.syncNow.tr),
            ),
            if (reason != null) ...[
              const SizedBox(height: 6),
              Text(
                reason,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _FixBanner extends StatelessWidget {
  final String text;
  final VoidCallback onFix;
  final String? actionLabel;
  const _FixBanner({required this.text, required this.onFix, this.actionLabel});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tint: AppColorConst.warning,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: AppColorConst.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(
            onPressed: onFix,
            child: Text(actionLabel ?? TranslatorConst.bannerFix.tr),
          ),
        ],
      ),
    );
  }
}
