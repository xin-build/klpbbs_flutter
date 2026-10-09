import 'package:flutter/material.dart';
import 'app_motion.dart';

/// 带平滑渐变淡入动画与按需惰性挂载的 IndexedStack，完整保留所有子页面状态（滚动位置、输入内容、缓存数据）
class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;
  final Curve curve;
  final bool lazy;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 220),
    this.curve = Curves.easeOutCubic,
    this.lazy = true,
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late int _currentIndex;
  late final Set<int> _activatedIndices;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _activatedIndices = {widget.index};
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _activatedIndices.add(widget.index);
      setState(() {
        _currentIndex = widget.index;
      });
      if (!AppMotion.enabled(context, MotionScope.navigation)) {
        _controller.value = 1;
      } else {
        _controller.duration = AppMotion.duration(
            context, widget.duration.inMilliseconds,
            scope: MotionScope.navigation);
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.duration(
        context, widget.duration.inMilliseconds,
        scope: MotionScope.navigation);
    if (!AppMotion.enabled(context, MotionScope.navigation)) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
        position: _animation
            .drive(Tween(begin: const Offset(0, .008), end: Offset.zero)),
        child: FadeTransition(
          opacity: _animation,
          child: IndexedStack(
            index: _currentIndex.clamp(
                0, widget.children.isEmpty ? 0 : widget.children.length - 1),
            children: List.generate(widget.children.length, (i) {
              if (!widget.lazy || _activatedIndices.contains(i)) {
                return TickerMode(
                    enabled: i == _currentIndex, child: widget.children[i]);
              }
              return const SizedBox.shrink();
            }),
          ),
        ));
  }
}
