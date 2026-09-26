import 'package:flutter/material.dart';
import '../core/app_config.dart';

/// 优雅流光骨架屏（带平滑动效的加载占位）
class SkeletonList extends StatefulWidget {
  final int itemCount;
  final bool withThumbnail;
  final bool? isGrid;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.withThumbnail = true,
    this.isGrid,
  });

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.45, end: 0.92).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final boneColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(140)
        : theme.colorScheme.surfaceContainerHighest.withAlpha(180);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useGrid = widget.isGrid ?? (constraints.maxWidth >= 640);
        return RepaintBoundary(
          child: FadeTransition(
            opacity: _opacity,
            child: useGrid ? _buildGrid(theme, boneColor) : _buildList(theme, boneColor),
          ),
        );
      },
    );
  }

  Widget _buildGrid(ThemeData theme, Color boneColor) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 520,
        mainAxisExtent: 138,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: widget.itemCount,
      itemBuilder: (_, __) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(45),
            width: 0.8,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: boneColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 140,
                    height: 11,
                    decoration: BoxDecoration(
                      color: boneColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: boneColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 60,
                        height: 10,
                        decoration: BoxDecoration(
                          color: boneColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 36,
                        height: 10,
                        decoration: BoxDecoration(
                          color: boneColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.withThumbnail) ...[
              const SizedBox(width: 12),
              Container(
                width: 88,
                height: 64,
                decoration: BoxDecoration(
                  color: boneColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme, Color boneColor) {
    return ListView.separated(
      shrinkWrap: true,
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
                  color: boneColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(boneColor, width: 0.9),
                  const SizedBox(height: 8),
                  _bar(boneColor, width: 0.6, height: 10),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: boneColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _bar(boneColor, width: 0.25, height: 10),
                      const Spacer(),
                      _bar(boneColor, width: 0.15, height: 10),
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

  Widget _bar(
    Color color, {
    double? width,
    double height = 14,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final parentW = c.maxWidth.isFinite ? c.maxWidth : 300.0;
        return Container(
          width: parentW * (width ?? 1.0),
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
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
  late final AnimationController _animCtrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.45, end: 0.92).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final boneColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(140)
        : theme.colorScheme.surfaceContainerHighest.withAlpha(180);

    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacity,
        child: Column(
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
                        color: boneColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 版块卡片列表骨架
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 640;
                  if (isWide) {
                    return GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 380,
                        mainAxisExtent: 78,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: 8,
                      itemBuilder: (_, __) => Container(
                        padding: const EdgeInsets.all(10),
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
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: boneColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 100,
                                    height: 15,
                                    decoration: BoxDecoration(
                                      color: boneColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: 140,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: boneColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
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
                              color: boneColor,
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
                                    color: boneColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: 200,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: boneColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 版块主列表流光骨架屏（高保真对齐 Discuz 版块页：版头横幅 + 快捷操作 + 分类标签 + 置顶推荐 + 帖子流）
class ForumThreadListSkeleton extends StatefulWidget {
  final bool isSidebar;

  const ForumThreadListSkeleton({
    super.key,
    this.isSidebar = false,
  });

  @override
  State<ForumThreadListSkeleton> createState() => _ForumThreadListSkeletonState();
}

class _ForumThreadListSkeletonState extends State<ForumThreadListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.45, end: 0.92).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final boneColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(140)
        : theme.colorScheme.surfaceContainerHighest.withAlpha(180);

    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacity,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 版头横幅骨架 (头图与统计看板)
              Container(
                height: widget.isSidebar ? 100 : 130,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withAlpha(45),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: widget.isSidebar ? 32 : 40,
                          height: widget.isSidebar ? 32 : 40,
                          decoration: BoxDecoration(
                            color: boneColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(width: 110, height: 16, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(4))),
                            const SizedBox(height: 5),
                            Container(width: 70, height: 10, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                          ],
                        ),
                        const Spacer(),
                        Container(width: 50, height: 22, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(12))),
                      ],
                    ),
                    const Spacer(),
                    // 统计指示条
                    Row(
                      children: [
                        for (int i = 0; i < 3; i++) ...[
                          Container(width: 48, height: 12, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(4))),
                          if (i < 2) const SizedBox(width: 12),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 2. 六大快捷功能按钮网格 (2 列 × 2 排)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(35)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Container(width: 16, height: 16, decoration: BoxDecoration(color: boneColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Container(width: 60, height: 11, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(35)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Container(width: 16, height: 16, decoration: BoxDecoration(color: boneColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Container(width: 60, height: 11, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(35)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Container(width: 16, height: 16, decoration: BoxDecoration(color: boneColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Container(width: 60, height: 11, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(35)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Container(width: 16, height: 16, decoration: BoxDecoration(color: boneColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Container(width: 60, height: 11, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 3. 分类标签胶囊栏 (Tabs Chips)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: [
                    for (final w in [42.0, 52.0, 52.0, 52.0, 48.0]) ...[
                      Container(
                        width: w,
                        height: 26,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: boneColor,
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 4. 排序与筛选选项 (Order Chips)
              Row(
                children: [
                  Container(width: 64, height: 24, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(6))),
                  const SizedBox(width: 6),
                  Container(width: 64, height: 24, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(6))),
                  const Spacer(),
                  Container(width: 24, height: 24, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(6))),
                ],
              ),
              const SizedBox(height: 10),

              // 5. 置顶推荐主题骨架
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(40)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(50),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 13,
                        decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 6. 主帖卡片信息流骨架 (3-4 项)
              for (int i = 0; i < 4; i++) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(40),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 32, height: 16, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(4))),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(width: double.infinity, height: 14, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(4))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(width: 140, height: 11, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(width: 18, height: 18, decoration: BoxDecoration(color: boneColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Container(width: 60, height: 10, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                          const Spacer(),
                          Container(width: 44, height: 10, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
  late final AnimationController _animCtrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.45, end: 0.92).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final boneColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withAlpha(140)
        : theme.colorScheme.surfaceContainerHighest.withAlpha(180);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return RepaintBoundary(
          child: FadeTransition(
            opacity: _opacity,
            child: width >= 1080
                ? _buildDesktopSkeleton(theme, boneColor, width)
                : width >= 640
                    ? _buildTabletSkeleton(theme, boneColor)
                    : _buildMobileSkeleton(theme, boneColor),
          ),
        );
      },
    );
  }

  Widget _buildDesktopSkeleton(ThemeData theme, Color boneColor, double totalWidth) {
    final showRightSidebar = totalWidth >= 960 && AppConfig.threadRightEnabled;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 中间主贴内容骨架
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(36, 24, 36, 96),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppConfig.threadContentMaxWidth),
                child: _buildPostContentBones(theme, boneColor, isDesktop: true),
              ),
            ),
          ),
        ),
        // 右侧模块/助手工作台边栏骨架 (260px，按需展示)
        if (showRightSidebar)
          SizedBox(
            width: 260,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(50),
                    width: 1,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 80, height: 15, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(4))),
                      const Spacer(),
                      Container(width: 20, height: 15, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(4))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // 工作台卡片骨架 1: 评分大厅
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(40)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 16, height: 16, decoration: BoxDecoration(color: boneColor, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Container(width: 70, height: 12, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(width: double.infinity, height: 26, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(6))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 工作台卡片骨架 2: 帖内搜索框
                  Container(
                    width: double.infinity,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(40)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Container(width: 16, height: 16, decoration: BoxDecoration(color: boneColor, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Container(width: 90, height: 11, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 工作台卡片骨架 3: 签到打卡日历
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(40)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 16, height: 16, decoration: BoxDecoration(color: boneColor, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Container(width: 64, height: 12, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(3))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (int i = 0; i < 5; i++)
                              Container(width: 28, height: 38, decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(6))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTabletSkeleton(ThemeData theme, Color boneColor) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: _buildPostContentBones(theme, boneColor, isDesktop: true),
        ),
      ),
    );
  }

  Widget _buildMobileSkeleton(ThemeData theme, Color boneColor) {
    return Stack(
      children: [
        SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
          child: _buildPostContentBones(theme, boneColor, isDesktop: false),
        ),
        // 移动端底部操作栏占位骨架
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60), width: 0.8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (int i = 0; i < 4; i++)
                  Container(
                    width: 54,
                    height: 22,
                    decoration: BoxDecoration(color: boneColor, borderRadius: BorderRadius.circular(6)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPostContentBones(ThemeData theme, Color boneColor, {required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 帖子标题骨架
        Container(
          width: double.infinity,
          height: isDesktop ? 26 : 21,
          decoration: BoxDecoration(
            color: boneColor,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: isDesktop ? 220 : 160,
          height: isDesktop ? 18 : 14,
          decoration: BoxDecoration(
            color: boneColor,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 18),
        // 作者栏骨架
        Row(
          children: [
            Container(
              width: isDesktop ? 44 : 36,
              height: isDesktop ? 44 : 36,
              decoration: BoxDecoration(
                color: boneColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 90,
                  height: 13,
                  decoration: BoxDecoration(
                    color: boneColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 130,
                  height: 10,
                  decoration: BoxDecoration(
                    color: boneColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        Divider(height: 1, color: theme.colorScheme.outlineVariant.withAlpha(50)),
        const SizedBox(height: 18),
        // 正文文本段落骨架
        for (final w in [1.0, 0.94, 0.88, 0.98, 0.75]) ...[
          FractionallySizedBox(
            widthFactor: w,
            child: Container(
              height: isDesktop ? 14 : 12,
              decoration: BoxDecoration(
                color: boneColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 14),
        // 图片占位骨架
        Container(
          width: double.infinity,
          height: isDesktop ? 240 : 160,
          decoration: BoxDecoration(
            color: boneColor,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 18),
        for (final w in [0.96, 0.9, 0.82]) ...[
          FractionallySizedBox(
            widthFactor: w,
            child: Container(
              height: isDesktop ? 14 : 12,
              decoration: BoxDecoration(
                color: boneColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
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
