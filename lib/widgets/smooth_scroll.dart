import 'package:flutter/material.dart';

class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  double _targetPixels = 0.0;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) return;

    if (activity is! DrivenScrollActivity) {
      _targetPixels = pixels;
    }

    _targetPixels += delta;
    _targetPixels = _targetPixels.clamp(minScrollExtent, maxScrollExtent);

    animateTo(
      _targetPixels,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutQuad,
    );
  }
}
