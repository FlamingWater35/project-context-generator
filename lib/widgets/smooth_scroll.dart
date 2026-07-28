import 'package:flutter/material.dart';
import 'package:silky_scroll/silky_scroll.dart';

/// Reusable smooth scroll wrapper powered by silky_scroll with tuned fast scroll speed and snappy animation duration
class SmoothScrollView extends StatelessWidget {
  const SmoothScrollView({
    super.key,
    required this.builder,
    this.scrollSpeed = 1.1,
    this.silkyScrollDuration = const Duration(milliseconds: 1400),
    this.animationCurve = Curves.easeOutQuad,
  });

  final Curve animationCurve;
  final Widget Function(
    BuildContext context,
    ScrollController controller,
    ScrollPhysics physics,
  )
  builder;
  final Duration silkyScrollDuration;
  final double scrollSpeed;

  @override
  Widget build(BuildContext context) {
    return SilkyScroll(
      scrollSpeed: scrollSpeed,
      silkyScrollDuration: silkyScrollDuration,
      animationCurve: animationCurve,
      builder: (context, controller, physics, _) {
        return builder(context, controller, physics);
      },
    );
  }
}
