import 'package:flutter/material.dart';

/// Card with a consistent inner padding.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? tint;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(child: Padding(padding: padding, child: child));
    if (tint == null) return card;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint!.withValues(alpha: 0.5)),
        color: tint!.withValues(alpha: 0.08),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Small section heading used on Settings / Setup pages.
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
