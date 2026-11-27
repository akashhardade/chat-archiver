import 'package:flutter/material.dart';

class CommonPadding extends StatelessWidget {
  const CommonPadding({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
      child: child,
    );
  }
}
