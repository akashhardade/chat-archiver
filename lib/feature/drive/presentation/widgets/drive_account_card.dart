import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/extensions/snackbar_extension.dart';
import 'package:chat_archiver/core/widgets/app_card.dart';
import 'package:chat_archiver/feature/archive/presentation/view_model/sync_coordinator.dart';

/// Google account status with Connect / Disconnect (Setup and Settings).
class DriveAccountCard extends StatefulWidget {
  const DriveAccountCard({super.key});

  @override
  State<DriveAccountCard> createState() => _DriveAccountCardState();
}

class _DriveAccountCardState extends State<DriveAccountCard> {
  bool _busy = false;

  Future<void> _connect(SyncCoordinator c) async {
    setState(() => _busy = true);
    final result = await c.connectDrive();
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (f) => Get.showErrorSnackBar(
        title: TranslatorConst.driveConnectFailed.tr,
        message: f.message,
      ),
      (_) {
        // Something may have been waiting for Drive.
        c.processNow();
      },
    );
  }

  Future<void> _disconnect(SyncCoordinator c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslatorConst.driveDisconnectTitle.tr),
        content: Text(TranslatorConst.driveDisconnectBody.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslatorConst.cancel.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(TranslatorConst.driveDisconnect.tr),
          ),
        ],
      ),
    );
    if (ok == true) await c.disconnectDrive();
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SyncCoordinator>();
    final theme = Theme.of(context);
    return Obx(() {
      final email = c.driveEmail.value;
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  email == null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                  color: email == null
                      ? theme.disabledColor
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email == null
                            ? TranslatorConst.driveNotConnected.tr
                            : TranslatorConst.driveConnected.tr,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (email != null)
                        Text(
                          email,
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (email == null)
              FilledButton.icon(
                onPressed: _busy ? null : () => _connect(c),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(TranslatorConst.driveConnect.tr),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _connect(c),
                      child: Text(TranslatorConst.driveReconnect.tr),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _disconnect(c),
                      child: Text(TranslatorConst.driveDisconnect.tr),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    });
  }
}
