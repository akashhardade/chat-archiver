import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/constants/app_colors.dart';
import 'package:chat_archiver/core/widgets/app_card.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';

/// "Let Chat Archiver run in the background": battery optimisation status,
/// the system request, and the manufacturer-specific tips (Setup + Settings).
class BackgroundRunCard extends StatelessWidget {
  const BackgroundRunCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SyncCoordinator>();
    final theme = Theme.of(context);
    return Obx(() {
      final ok = c.batteryUnrestricted.value;
      return AppCard(
        tint: ok ? null : AppColorConst.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  ok ? Icons.battery_full : Icons.battery_alert_outlined,
                  color: ok ? AppColorConst.success : AppColorConst.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ok
                        ? TranslatorConst.batteryOk.tr
                        : TranslatorConst.batteryTitle.tr,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (!ok) ...[
              const SizedBox(height: 8),
              Text(
                TranslatorConst.batteryBody.tr,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: c.requestBatteryExemption,
                child: Text(TranslatorConst.batteryAllow.tr),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              TranslatorConst.batteryOemTip.tr,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: c.openAppSettings,
              child: Text(TranslatorConst.openAppInfo.tr),
            ),
          ],
        ),
      );
    });
  }
}
