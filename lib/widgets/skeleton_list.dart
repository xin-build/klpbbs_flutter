import 'package:flutter/material.dart';

/// 列表骨架屏（加载占位）
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final bool withThumbnail;

  const SkeletonList(
      {super.key, this.itemCount = 6, this.withThumbnail = true});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (withThumbnail) ...[
              Container(
                width: 100,
                height: 63,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(context, width: 0.9),
                  const SizedBox(height: 8),
                  _bar(context, width: 0.6, height: 10),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      CircleAvatar(radius: 8, backgroundColor: base),
                      const SizedBox(width: 6),
                      _bar(context, width: 0.25, height: 10),
                      const Spacer(),
                      _bar(context, width: 0.15, height: 10),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, {double? width, double height = 14}) {
    return Container(
      width: (MediaQuery.of(context).size.width - 56) * (width ?? 1.0),
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}


/// 呼吸占位块（图片加载中动画）
class PulsePlaceholder extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? radius;

  const PulsePlaceholder(
      {super.key, this.width, this.height, this.radius});

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
      opacity: Tween(begin: 0.5, end: 1.0).animate(_ctrl),
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
