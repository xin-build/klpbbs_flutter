import 'package:flutter/material.dart';
import 'app_motion.dart';

/// 桌面导航保留短暂的淡入和水平位移，不放大整个工作区。
class DesktopPageTransitionsBuilder extends PageTransitionsBuilder {
  const DesktopPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!AppMotion.enabled(context, MotionScope.navigation)) return child;
    final curved = animation.drive(CurveTween(curve: AppMotion.emphasized));
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: curved
            .drive(Tween(begin: const Offset(0, 0.015), end: Offset.zero)),
        child: child,
      ),
    );
  }
}
