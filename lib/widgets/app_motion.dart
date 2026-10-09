import 'package:flutter/material.dart';
import '../core/app_config.dart';

enum MotionScope { navigation, panels, lists, loading }

class AppMotionSettings extends InheritedNotifier<ChangeNotifier> {
  AppMotionSettings({super.key, required super.child})
      : super(notifier: AppConfig.instance);
}

/// 所有可配置动效共用同一节奏，并响应系统的减少动画设置。
class AppMotion {
  AppMotion._();

  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve exit = Cubic(0.3, 0, 0.8, 0.15);

  static bool enabled(BuildContext context,
      [MotionScope scope = MotionScope.panels]) {
    context.dependOnInheritedWidgetOfExactType<AppMotionSettings>();
    if (AppConfig.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      return false;
    }
    return switch (scope) {
      MotionScope.navigation => AppConfig.animatePageTransitions,
      MotionScope.panels => AppConfig.animatePanels,
      MotionScope.lists => AppConfig.animateLists,
      MotionScope.loading => AppConfig.animateLoading,
    };
  }

  static Duration duration(BuildContext context, int milliseconds,
          {MotionScope scope = MotionScope.panels}) =>
      enabled(context, scope)
          ? Duration(
              milliseconds:
                  (milliseconds * AppConfig.motionPace.factor).round())
          : Duration.zero;
}

/// 只用于初次进入可见区域的内容；复用键后刷新不会重复播放。
class AppFadeIn extends StatelessWidget {
  final Widget child;
  final int index;
  const AppFadeIn({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    if (index >= 10 || !AppMotion.enabled(context, MotionScope.lists)) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.duration(context, 240, scope: MotionScope.lists),
      curve: AppMotion.emphasized,
      child: child,
      builder: (_, value, content) => Opacity(
        opacity: value,
        child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)), child: content),
      ),
    );
  }
}

/// 零时长的 AnimatedSize 会在布局阶段同步结束动画；关闭动效时直接布局。
class AppAnimatedSize extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Duration? reverseDuration;
  final AlignmentGeometry alignment;
  final Curve curve;
  final Clip clipBehavior;
  final VoidCallback? onEnd;

  const AppAnimatedSize({
    super.key,
    required this.child,
    required this.duration,
    this.reverseDuration,
    this.alignment = Alignment.center,
    this.curve = AppMotion.emphasized,
    this.clipBehavior = Clip.hardEdge,
    this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    if (duration == Duration.zero || !AppMotion.enabled(context)) return child;
    return AnimatedSize(
      duration: duration,
      reverseDuration: reverseDuration,
      alignment: alignment,
      curve: curve,
      clipBehavior: clipBehavior,
      onEnd: onEnd,
      child: child,
    );
  }
}

class AppLoadingIndicator extends StatelessWidget {
  final double? value, strokeWidth;
  final Color? color, backgroundColor;
  final Animation<Color?>? valueColor;
  final String? semanticsLabel, semanticsValue;
  const AppLoadingIndicator({
    super.key,
    this.value,
    this.strokeWidth,
    this.color,
    this.backgroundColor,
    this.valueColor,
    this.semanticsLabel,
    this.semanticsValue,
  });

  @override
  Widget build(BuildContext context) => CircularProgressIndicator(
        value: value ??
            (AppMotion.enabled(context, MotionScope.loading) &&
                    TickerMode.of(context)
                ? null
                : .65),
        strokeWidth: strokeWidth,
        color: color,
        backgroundColor: backgroundColor,
        valueColor: valueColor,
        semanticsLabel: semanticsLabel ?? '加载中',
        semanticsValue: semanticsValue,
      );
}

class AppLoadingBar extends StatelessWidget {
  final double? value, minHeight;
  final Color? color, backgroundColor;
  final Animation<Color?>? valueColor;
  final String? semanticsLabel, semanticsValue;
  const AppLoadingBar({
    super.key,
    this.value,
    this.minHeight,
    this.color,
    this.backgroundColor,
    this.valueColor,
    this.semanticsLabel,
    this.semanticsValue,
  });

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
        value: value ??
            (AppMotion.enabled(context, MotionScope.loading) &&
                    TickerMode.of(context)
                ? null
                : .65),
        minHeight: minHeight,
        color: color,
        backgroundColor: backgroundColor,
        valueColor: valueColor,
        semanticsLabel: semanticsLabel ?? '加载中',
        semanticsValue: semanticsValue,
      );
}

/// 一个骨架组共享一次绘制动画，隐藏页面不继续消耗帧。
class AppSkeletonPulse extends StatefulWidget {
  final Widget child;
  const AppSkeletonPulse({super.key, required this.child});
  @override
  State<AppSkeletonPulse> createState() => _AppSkeletonPulseState();
}

class _AppSkeletonPulseState extends State<AppSkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    lowerBound: .52,
    upperBound: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.enabled(context, MotionScope.loading) &&
        TickerMode.of(context)) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: FadeTransition(opacity: _controller, child: widget.child),
      );
}
