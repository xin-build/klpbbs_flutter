import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/app_config.dart';

/// 保留触摸和触控板的原生物理行为，仅平滑桌面鼠标滚轮。
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
  ) =>
      _WheelScrollPosition(
        physics: physics,
        context: context,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        oldPosition: oldPosition,
        debugLabel: debugLabel,
      );
}

class _WheelScrollPosition extends ScrollPositionWithSingleContext {
  _WheelScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  double? _wheelTarget;
  double _lastDelta = 0;
  int _wheelSequence = 0;

  bool get _smoothEnabled {
    final platform = defaultTargetPlatform;
    return (platform == TargetPlatform.windows ||
            platform == TargetPlatform.macOS ||
            platform == TargetPlatform.linux) &&
        AppConfig.smoothScrollPhysics &&
        !AppConfig.reduceMotion &&
        !(MediaQuery.maybeOf(context.storageContext)?.disableAnimations ??
            false);
  }

  @override
  void pointerScroll(double delta) {
    if (!_smoothEnabled ||
        delta == 0 ||
        !delta.isFinite ||
        !hasContentDimensions ||
        !minScrollExtent.isFinite ||
        !maxScrollExtent.isFinite) {
      _resetWheel();
      super.pointerScroll(delta);
      return;
    }
    final base = _wheelTarget != null && delta.sign == _lastDelta.sign
        ? _wheelTarget!
        : pixels;
    final target = (base + delta).clamp(minScrollExtent, maxScrollExtent);
    if (target == pixels) return;
    _wheelTarget = target;
    _lastDelta = delta;
    final sequence = ++_wheelSequence;
    updateUserScrollDirection(
        delta < 0 ? ScrollDirection.forward : ScrollDirection.reverse);
    unawaited(animateTo(
      target,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    ).whenComplete(() {
      if (sequence == _wheelSequence) _wheelTarget = null;
    }));
  }

  void _resetWheel() {
    _wheelTarget = null;
    _wheelSequence++;
  }

  @override
  void applyUserOffset(double delta) {
    _resetWheel();
    super.applyUserOffset(delta);
  }

  @override
  void jumpTo(double value) {
    _resetWheel();
    super.jumpTo(value);
  }
}
