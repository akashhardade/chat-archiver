import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:chat_archiver/config/localization/translator_const.dart';
import 'package:chat_archiver/core/widgets/app_card.dart';

/// Prominent disclosure of what the accessibility service does. The caller
/// shows it BEFORE sending the user to Android's accessibility settings and
/// must only proceed after an explicit "I agree".
class AccessibilityDisclosureContent extends StatelessWidget {
  const AccessibilityDisclosureContent({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TranslatorConst.disclosureBody.tr,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        bullet(TranslatorConst.disclosure1.tr),
        bullet(TranslatorConst.disclosure2.tr),
        bullet(TranslatorConst.disclosure3.tr),
        bullet(TranslatorConst.disclosure4.tr),
        const SizedBox(height: 8),
        Text(
          TranslatorConst.disclosureNothing.tr,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// In-page disclosure card (setup flow).
class AccessibilityDisclosureCard extends StatelessWidget {
  final VoidCallback onAgree;
  final VoidCallback? onDecline;

  const AccessibilityDisclosureCard({
    super.key,
    required this.onAgree,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      tint: theme.colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.accessibility_new, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  TranslatorConst.disclosureTitle.tr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const AccessibilityDisclosureContent(),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onAgree,
            child: Text(TranslatorConst.disclosureAgree.tr),
          ),
          if (onDecline != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onDecline,
              child: Text(TranslatorConst.disclosureDecline.tr),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dialog variant (Settings). Resolves true only on "I agree".
Future<bool> showAccessibilityDisclosureDialog(BuildContext context) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(TranslatorConst.disclosureTitle.tr),
      content: const SingleChildScrollView(
        child: AccessibilityDisclosureContent(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(TranslatorConst.disclosureDecline.tr),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(TranslatorConst.disclosureAgree.tr),
        ),
      ],
    ),
  );
  return agreed == true;
}
