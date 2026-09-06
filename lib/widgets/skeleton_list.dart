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
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(120)
        : theme.colorScheme.surfaceContainerHighest.withAlpha(160);
    final highlightColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(255)
        : Colors.white.withAlpha(220);

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        final progress = Curves.easeInOutSine.transform(_animCtrl.value);
        final shimmerGradient = LinearGradient(
          begin: Alignment(-2.2 + (progress * 4.4), -0.2),
          end: Alignment(-0.6 + (progress * 4.4), 0.2),
          colors: [
            baseColor,
            highlightColor,
            baseColor,
          ],
          stops: const [0.15, 0.5, 0.85],
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

/// 版块列表流光骨架屏（横向分区标签 + 版块卡片网格占位）
class ForumSkeleton extends StatefulWidget {
  const ForumSkeleton({super.key});

  @override
  State<ForumSkeleton> createState() => _ForumSkeletonState();
}

class _ForumSkeletonState extends State<ForumSkeleton>
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
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(120)
        : theme.colorScheme.surfaceContainerHighest.withAlpha(160);
    final highlightColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(255)
        : Colors.white.withAlpha(220);

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        final progress = Curves.easeInOutSine.transform(_animCtrl.value);
        final shimmerGradient = LinearGradient(
          begin: Alignment(-2.2 + (progress * 4.4), -0.2),
          end: Alignment(-0.6 + (progress * 4.4), 0.2),
          colors: [baseColor, highlightColor, baseColor],
          stops: const [0.15, 0.5, 0.85],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部横向分区 Tab 骨架
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  for (final w in [72.0, 84.0, 96.0, 68.0])
                    Container(
                      width: w,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        gradient: shimmerGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 版块卡片列表骨架
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: 6,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, __) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(40),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: shimmerGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 120,
                              height: 16,
                              decoration: BoxDecoration(
                                gradient: shimmerGradient,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 200,
                              height: 12,
                              decoration: BoxDecoration(
                                gradient: shimmerGradient,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 帖子详情页流光骨架屏（标题 + 作者栏 + 正文段落 + 底部交互栏）
class ThreadDetailSkeleton extends StatefulWidget {
  const ThreadDetailSkeleton({super.key});

  @override
  State<ThreadDetailSkeleton> createState() => _ThreadDetailSkeletonState();
}

class _ThreadDetailSkeletonState extends State<ThreadDetailSkeleton>
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
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(120)
        : theme.colorScheme.surfaceContainerHighest.withAlpha(160);
    final highlightColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(255)
        : Colors.white.withAlpha(220);

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        final progress = Curves.easeInOutSine.transform(_animCtrl.value);
        final shimmerGradient = LinearGradient(
          begin: Alignment(-2.2 + (progress * 4.4), -0.2),
          end: Alignment(-0.6 + (progress * 4.4), 0.2),
          colors: [baseColor, highlightColor, baseColor],
          stops: const [0.15, 0.5, 0.85],
        );

        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 帖子标题骨架
              Container(
                width: double.infinity,
                height: 24,
                decoration: BoxDecoration(
                  gradient: shimmerGradient,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 220,
                height: 20,
                decoration: BoxDecoration(
                  gradient: shimmerGradient,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 20),
              // 作者栏骨架
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: shimmerGradient,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 100,
                        height: 14,
                        decoration: BoxDecoration(
                          gradient: shimmerGradient,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 140,
                        height: 11,
                        decoration: BoxDecoration(
                          gradient: shimmerGradient,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 20),
              // 正文文本段落骨架
              for (final w in [1.0, 0.94, 0.88, 0.98, 0.75]) ...[
                FractionallySizedBox(
                  widthFactor: w,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      gradient: shimmerGradient,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 16),
              // 图片占位骨架
              Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  gradient: shimmerGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              for (final w in [0.96, 0.9, 0.82]) ...[
                FractionallySizedBox(
                  widthFactor: w,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      gradient: shimmerGradient,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 统一的高质感加载视图（带轻量渐变或提示文案）
class AppLoadingView extends StatelessWidget {
  final String? message;
  final double size;

  const AppLoadingView({
    super.key,
    this.message,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.primary.withAlpha(40),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
