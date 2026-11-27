import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/constants/app_colors.dart';
import 'package:chat_archiver/core/widgets/app_card.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/accessibility_disclosure.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/background_run_card.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/groups_editor.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/hour_picker.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/run_progress_list.dart';
import 'package:chat_archiver/feature/drive/presentation/widgets/drive_account_card.dart';
import 'package:chat_archiver/feature/setup/presentation/view_model/setup_controller.dart';

/// Setup wizard: Drive, groups, automation permission, morning time, first
/// sync. Shown until completed.
class SetupPage extends GetView<SetupController> {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(TranslatorConst.setupTitle.tr),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              _Header(controller: controller),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Obx(() => _stepBody(context)),
                ),
              ),
              _Footer(controller: controller),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    switch (controller.step.value) {
      case SetupStep.drive:
        return _StepScaffold(
          title: TranslatorConst.driveTitle.tr,
          intro: TranslatorConst.driveIntro.tr,
          child: const DriveAccountCard(),
        );
      case SetupStep.groups:
        return _StepScaffold(
          title: TranslatorConst.groupsTitle.tr,
          intro: TranslatorConst.groupsIntro.tr,
          child: const GroupsEditor(),
        );
      case SetupStep.permission:
        return _PermissionStep(controller: controller);
      case SetupStep.time:
        return _StepScaffold(
          title: TranslatorConst.timeTitle.tr,
          intro: TranslatorConst.timeIntro.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const HourPicker(),
              const SizedBox(height: 12),
              Text(
                TranslatorConst.timeExplain.tr,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _Note(text: TranslatorConst.timeKeepUnlocked.tr),
            ],
          ),
        );
      case SetupStep.firstSync:
        return _FirstSyncStep(controller: controller);
    }
  }
}

class _Header extends StatelessWidget {
  final SetupController controller;
  const _Header({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final n = controller.stepNumber;
      final label = switch (controller.step.value) {
        SetupStep.drive => TranslatorConst.stepDrive.tr,
        SetupStep.groups => TranslatorConst.stepGroups.tr,
        SetupStep.permission => TranslatorConst.stepPermission.tr,
        SetupStep.time => TranslatorConst.stepTime.tr,
        SetupStep.firstSync => TranslatorConst.stepFirstSync.tr,
      };
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  TranslatorConst.setupStepOf.trParams({
                    'n': '$n',
                    'total': '${SetupController.total}',
                  }),
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: n / SetupController.total,
                minHeight: 6,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _Footer extends StatelessWidget {
  final SetupController controller;
  const _Footer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final last = controller.isLast;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: [
            if (!controller.isFirst)
              Expanded(
                child: OutlinedButton(
                  onPressed: controller.back,
                  child: Text(TranslatorConst.back.tr),
                ),
              ),
            if (!controller.isFirst) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: last
                    ? controller.finish
                    : (controller.canContinue ? controller.next : null),
                child: Text(
                  last
                      ? TranslatorConst.setupFinish.tr
                      : TranslatorConst.continueLabel.tr,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _StepScaffold extends StatelessWidget {
  final String title;
  final String intro;
  final Widget child;
  const _StepScaffold({
    required this.title,
    required this.intro,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(intro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        child,
      ],
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note({required this.text});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tint: AppColorConst.warning,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_open_outlined, size: 20, color: AppColorConst.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PermissionStep extends StatelessWidget {
  final SetupController controller;
  const _PermissionStep({required this.controller});

  @override
  Widget build(BuildContext context) {
    final coordinator = Get.find<SyncCoordinator>();
    final theme = Theme.of(context);
    return _StepScaffold(
      title: TranslatorConst.permissionTitle.tr,
      intro: TranslatorConst.permissionIntro.tr,
      child: Obx(() {
        if (coordinator.accessibilityEnabled.value) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                tint: AppColorConst.success,
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColorConst.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        TranslatorConst.permissionGranted.tr,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const BackgroundRunCard(),
            ],
          );
        }
        if (!controller.disclosureAccepted.value) {
          return AccessibilityDisclosureCard(
            onAgree: controller.agreeAndOpenSettings,
            onDecline: controller.back,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      TranslatorConst.permissionHowTo.tr,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslatorConst.permissionMissing.tr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColorConst.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: controller.openSettings,
              child: Text(TranslatorConst.permissionOpenAgain.tr),
            ),
            const SizedBox(height: 16),
            Text(
              TranslatorConst.permissionRestricted.tr,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: coordinator.openAppSettings,
              child: Text(TranslatorConst.openAppInfo.tr),
            ),
          ],
        );
      }),
    );
  }
}

class _FirstSyncStep extends StatelessWidget {
  final SetupController controller;
  const _FirstSyncStep({required this.controller});

  @override
  Widget build(BuildContext context) {
    final coordinator = Get.find<SyncCoordinator>();
    return _StepScaffold(
      title: TranslatorConst.firstSyncTitle.tr,
      intro: TranslatorConst.firstSyncIntro.tr,
      child: Obx(() {
        final running = coordinator.isBusy || controller.startingSync.value;
        final blocked = coordinator.syncBlock;
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: (running || blocked != null)
                  ? null
                  : controller.startFirstSync,
              icon: running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(
                running
                    ? TranslatorConst.firstSyncRunning.tr
                    : TranslatorConst.firstSyncStart.tr,
              ),
            ),
            if (controller.syncAttempted.value) ...[
              const SizedBox(height: 16),
              AppCard(child: const RunProgressList()),
              if (coordinator.processing.value) ...[
                const SizedBox(height: 8),
                Text(
                  TranslatorConst.syncProcessing.tr,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (!running && coordinator.runProgress.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  TranslatorConst.firstSyncDone.tr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            _Note(text: TranslatorConst.keepUnlockedNote.tr),
          ],
        );
      }),
    );
  }
}
