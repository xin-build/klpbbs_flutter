import 'package:flutter/material.dart';

/// 优雅流光骨架屏（带平滑动效的加载占位）
class SkeletonList extends StatefulWidget {
  final int itemCount;
  final bool withThumbnail;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.withThumbnail = true,
  });

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(140)
        : theme.colorScheme.surfaceContainerHighest.withAlpha(180);
    final highlightColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(240)
        : Colors.white.withAlpha(200);

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        final progress = _animCtrl.value;
        final shimmerGradient = LinearGradient(
          begin: Alignment(-1.5 + (progress * 3.0), -0.3),
          end: Alignment(-0.5 + (progress * 3.0), 0.3),
          colors: [
            baseColor,
            highlightColor,
            baseColor,
          ],
          stops: const [0.1, 0.5, 0.9],
        );

        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.itemCount,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.withThumbnail) ...[
                  Container(
                    width: 100,
                    height: 63,
                    decoration: BoxDecoration(
                      gradient: shimmerGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bar(context, shimmerGradient, width: 0.9),
                      const SizedBox(height: 8),
                      _bar(context, shimmerGradient, width: 0.6, height: 10),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              gradient: shimmerGradient,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _bar(context, shimmerGradient, width: 0.25, height: 10),
                          const Spacer(),
                          _bar(context, shimmerGradient, width: 0.15, height: 10),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bar(
    BuildContext context,
    Gradient gradient, {
    double? width,
    double height = 14,
  }) {
    return Container(
      width: (MediaQuery.of(context).size.width - 56) * (width ?? 1.0),
      height: height,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// 呼吸占位块（图片加载中动效）
class PulsePlaceholder extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? radius;

  const PulsePlaceholder({
    super.key,
    this.width,
    this.height,
    this.radius,
  });

  @override
  State<PulsePlaceholder> createState() => _PulsePlaceholderState();
}

class _PulsePlaceholderState extends State<PulsePlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 0.95).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: widget.radius ?? BorderRadius.circular(8),
        ),
      ),
    );
  }
}
