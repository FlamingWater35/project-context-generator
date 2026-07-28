import 'package:flutter/material.dart';
import 'package:silky_scroll/silky_scroll.dart';

/// Reusable smooth scroll wrapper powered by silky_scroll for desktop mouse wheel, trackpad, and touch inputs
class SmoothScrollView extends StatelessWidget {
  const SmoothScrollView({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    ScrollController controller,
    ScrollPhysics physics,
  )
  builder;

  @override
  Widget build(BuildContext context) {
    return SilkyScroll(
      builder: (context, controller, physics, _) {
        return builder(context, controller, physics);
      },
    );
  }
}
