import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/config/theme/theme_controller.dart';
import 'package:chat_archiver/core/constants/app_colors.dart';
import 'package:chat_archiver/core/widgets/app_card.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/background_run_card.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/groups_editor.dart';
import 'package:chat_archiver/feature/archive/presentation/widgets/hour_picker.dart';
import 'package:chat_archiver/feature/drive/presentation/widgets/drive_account_card.dart';
import 'package:chat_archiver/feature/settings/presentation/view_model/settings_controller.dart';

class SettingsPage extends GetView<SettingsController> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coordinator = controller.coordinator;
    return Scaffold(
      appBar: AppBar(title: Text(TranslatorConst.settingsTitle.tr)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            SectionTitle(TranslatorConst.settingsAutomation.tr),
            Obx(
              () => AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(TranslatorConst.settingsAutoRun.tr),
                      subtitle: Text(TranslatorConst.settingsAutoRunHint.tr),
                      value: coordinator.automationEnabled.value,
                      onChanged: coordinator.setAutomationEnabled,
                    ),
                    const Divider(height: 24),
                    const HourPicker(),
                    const SizedBox(height: 8),
                    Text(
                      TranslatorConst.timeExplain.tr,
                      style: theme.textTheme.bodySmall,
                    ),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        coordinator.accessibilityEnabled.value
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: coordinator.accessibilityEnabled.value
                            ? AppColorConst.success
                            : AppColorConst.warning,
                      ),
                      title: Text(TranslatorConst.settingsAccessibility.tr),
                      subtitle: Text(
                        coordinator.accessibilityEnabled.value
                            ? TranslatorConst.permissionGranted.tr
                            : TranslatorConst.permissionMissing.tr,
                      ),
                      trailing: coordinator.accessibilityEnabled.value
                          ? TextButton(
                              onPressed: controller.openAccessibilitySettings,
                              child: Text(
                                TranslatorConst.permissionOpenAgain.tr,
                              ),
                            )
                          : FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(88, 40),
                              ),
                              onPressed: () =>
                                  controller.turnOnAccessibility(context),
                              child: Text(TranslatorConst.permissionTurnOn.tr),
                            ),
                    ),
                    if (!coordinator.accessibilityEnabled.value) ...[
                      Text(
                        TranslatorConst.permissionRestricted.tr,
                        style: theme.textTheme.bodySmall,
                      ),
                      TextButton(
                        onPressed: coordinator.openAppSettings,
                        child: Text(TranslatorConst.openAppInfo.tr),
                      ),
                    ],
                    const Divider(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_open_outlined,
                          size: 16,
                          color: theme.disabledColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            TranslatorConst.keepUnlockedNote.tr,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const BackgroundRunCard(),
            SectionTitle(TranslatorConst.settingsDrive.tr),
            const DriveAccountCard(),
            SectionTitle(TranslatorConst.settingsGroups.tr),
            const GroupsEditor(),
            SectionTitle(TranslatorConst.settingsAppearance.tr),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Obx(() {
                final theme = Get.find<ThemeController>();
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(TranslatorConst.settingsDarkMode.tr),
                  value: theme.isDarkMode,
                  onChanged: (_) => theme.toggleTheme(),
                );
              }),
            ),
            SectionTitle(TranslatorConst.settingsDiagnostics.tr),
            AppCard(
              child: Obx(
                () => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      TranslatorConst.diagnosticsBody.tr,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      TranslatorConst.diagnosticsCaptureHint.tr,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: controller.capturing.value
                          ? null
                          : controller.captureScreen,
                      icon: controller.capturing.value
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.screenshot_monitor),
                      label: Text(TranslatorConst.diagnosticsCapture.tr),
                    ),
                    if (controller.capturePath.value != null) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: controller.shareCapture,
                        icon: const Icon(Icons.share),
                        label: Text(TranslatorConst.diagnosticsShare.tr),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 16, color: theme.disabledColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TranslatorConst.settingsPrivacyNote.tr,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
