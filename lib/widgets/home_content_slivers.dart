import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../core/discuz_favorites.dart';
import '../core/home_feed.dart';
import '../models/forum.dart';
import '../models/horn_message.dart';
import '../models/server_outage_info.dart';
import '../models/site_stats.dart';
import '../models/thread_summary.dart';
import 'app_motion.dart';
import 'horn_banner_widget.dart';
import 'mobile_home_customizer.dart';
import 'retry_image.dart';
import 'site_stats_card.dart';
import 'sliver_two_column_feed.dart';
import 'thread_card.dart';

/// 首页与画布共同使用的数据渲染边界。请求、持久化和页面导航由调用方负责。
class HomeContentSlivers {
  static List<Widget> build(
    BuildContext context, {
    required List<ForumGroup> groups,
    required List<ThreadSummary> threads,
    required SiteStats stats,
    required bool isDesktop,
    required double centerWidth,
    required List<String> sections,
    required List<String> quickActionIds,
    List<ThreadSummary>? recommendations,
    Set<int> favoriteForumIds = const {},
    List<HornMessage> announcements = const [],
    Widget? announcementContent,
    bool announcementsEnabled = true,
    bool isPreview = false,
    bool compactMobile = true,
    bool showStats = true,
    bool loadingMore = false,
    bool hasMore = true,
    HomeFeed feed = HomeFeed.recommended,
    ValueChanged<HomeFeed>? onSelectFeed,
    bool feedLoading = false,
    String? feedError,
    String? emptyMessage,
    bool refreshing = false,
    ServerOutageInfo? outage,
    VoidCallback? onRefresh,
    VoidCallback? onLoadMore,
    VoidCallback? onCustomize,
    VoidCallback? onAllForums,
    ValueChanged<Forum>? onOpenForum,
    Future<bool> Function(Forum, bool favorite)? onToggleFavorite,
    ValueChanged<ThreadSummary>? onOpenThread,
    ValueChanged<ThreadSummary>? onOpenAuthor,
    ValueChanged<int>? onQuickAction,
  }) {
    final compact = compactMobile && !isDesktop;
    final slivers = <Widget>[];
    for (final section in sections) {
      switch (section) {
        case 'horn_banner':
          if (announcementsEnabled) {
            slivers.add(SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                sliver: SliverToBoxAdapter(
                    key: const ValueKey('home-section-announcements'),
                    // 预览保留真实公告布局，只消费已有数据并禁用网络与写入。
                    child: isPreview || announcementContent == null
                        ? HornBannerWidget(
                            initialMessages: announcements,
                            isPreview: isPreview)
                        : announcementContent)));
          }
        case 'stats':
          if (showStats && !stats.isEmpty) {
            slivers.add(SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                sliver: SliverToBoxAdapter(
                    key: const ValueKey('home-section-stats'),
                    child: compact
                        ? _CompactHomeStats(stats: stats)
                        : SiteStatsCard(stats: stats))));
          }
        case 'forum_nav':
          slivers.add(SliverToBoxAdapter(
              key: const ValueKey('home-section-forums'),
              child: groups.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16), child: Text('暂无已加载的版块'))
                  : ForumNav(
                      groups: groups,
                      favFids: favoriteForumIds,
                      compact: compact,
                      isPreview: isPreview,
                      onOpen: isPreview ? null : onOpenForum,
                      onAllForums: isPreview ? null : onAllForums,
                      onToggleFav: isPreview ? null : onToggleFavorite)));
        case 'quick_actions':
          if (!isDesktop) {
            slivers.add(SliverToBoxAdapter(
                key: const ValueKey('home-section-quick-actions'),
                child: QuickActionsWidget(
                    actionIds: quickActionIds,
                    compact: compact,
                    onNavigate: isPreview ? null : onQuickAction,
                    onCustomize: isPreview ? null : onCustomize)));
          }
        case 'carousel':
          final source = recommendations ?? threads;
          final withCover = source
              .where((thread) => thread.coverUrl?.isNotEmpty == true)
              .toList();
          final featured =
              (withCover.isEmpty ? source : withCover).take(5).toList();
          if (featured.isNotEmpty) {
            slivers.add(SliverToBoxAdapter(
                key: const ValueKey('home-section-carousel'),
                child: RepaintBoundary(
                    child: _RecommendCarousel(
                        threads: featured,
                        compact: compact,
                        isPreview: isPreview,
                        onTap: isPreview
                            ? null
                            : (tid) {
                                final thread =
                                    featured.firstWhere((t) => t.tid == tid);
                                onOpenThread?.call(thread);
                              }))));
          }
      }
    }
    final scheme = Theme.of(context).colorScheme;
    slivers.add(SliverToBoxAdapter(
        key: const ValueKey('home-feed-heading'),
        child: Padding(
            padding: EdgeInsets.fromLTRB(14, compact ? 8 : 12, 14, 10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(builder: (context, box) {
                    final options = <Widget>[
                      for (final option in HomeFeed.values)
                        ChoiceChip(
                          key: ValueKey('home-feed-${option.name}'),
                          label: Text(option.label),
                          avatar: Icon(
                              switch (option) {
                                HomeFeed.recommended =>
                                  Icons.auto_awesome_outlined,
                                HomeFeed.following => Icons.people_outline,
                                HomeFeed.latest => Icons.schedule_rounded,
                                HomeFeed.replies => Icons.forum_outlined,
                                HomeFeed.hot =>
                                  Icons.local_fire_department_outlined,
                                HomeFeed.digest =>
                                  Icons.workspace_premium_outlined,
                                HomeFeed.sofa => Icons.event_seat_outlined,
                              },
                              size: 17),
                          selected: feed == option,
                          showCheckmark: false,
                          onSelected: onSelectFeed == null
                              ? null
                              : (_) => onSelectFeed(option),
                        ),
                    ];
                    if (isDesktop) {
                      return Wrap(spacing: 8, runSpacing: 4, children: options);
                    }
                    return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final option in options)
                            Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: option)
                        ]));
                  }),
                  const SizedBox(height: 10),
                  Row(children: [
                    Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(isDesktop ? feed.description : feed.label,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold))),
                    if (isDesktop)
                      TextButton.icon(
                          onPressed: isPreview || feedLoading || refreshing
                              ? null
                              : onRefresh,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('刷新'))
                    else
                      Text(
                          isPreview
                              ? '布局预览'
                              : refreshing
                                  ? '正在刷新'
                                  : '下拉刷新',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                  ]),
                  if (feedLoading || refreshing) ...[
                    const SizedBox(height: 8),
                    const AppLoadingBar(minHeight: 2),
                  ],
                  if (feedError != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: Text(feedError,
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant))),
                      TextButton(
                          onPressed: isPreview ? null : onRefresh,
                          child: const Text('重试')),
                    ]),
                  ],
                ]))));
    if (threads.isEmpty) {
      slivers.add(SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Text(emptyMessage ??
                    (outage == null
                        ? feedLoading
                            ? '正在读取${feed.label}'
                            : '暂无${feed.label}帖子'
                        : '${feed.label}暂不可用 (${outage.statusCode} ${outage.title})')),
                if (outage != null && !isPreview && onRefresh != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FilledButton.icon(
                          onPressed: onRefresh,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重试连接'))),
              ]))));
    } else {
      final grid = isDesktop && centerWidth >= 620;
      Widget card(BuildContext context, int index) {
        final thread = threads[index];
        return ThreadCard(
            key: ValueKey(thread.tid),
            thread: thread,
            isGrid: grid,
            adaptiveHeight: grid,
            onTap: isPreview || onOpenThread == null
                ? null
                : () => onOpenThread(thread),
            onAuthorTap: isPreview ||
                    onOpenAuthor == null ||
                    (thread.uid == null && thread.author.isEmpty)
                ? null
                : () => onOpenAuthor(thread));
      }

      slivers.add(grid
          ? SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverTwoColumnFeed(
                  itemCount: threads.length, itemBuilder: card))
          : SliverList.builder(itemCount: threads.length, itemBuilder: card));
      if (!isPreview) {
        slivers.add(SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                    child: loadingMore
                        ? const AppLoadingIndicator(strokeWidth: 2)
                        : hasMore
                            ? FilledButton.tonal(
                                onPressed: onLoadMore,
                                child: Text('加载更多${feed.label}'))
                            : Text('已显示全部${feed.label}',
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant))))));
      }
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 80)));
    return slivers;
  }
}

class _CompactHomeStats extends StatelessWidget {
  final SiteStats stats;
  const _CompactHomeStats({required this.stats});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const metrics = [
      ('今日', 'todayPosts'),
      ('昨日', 'yesterdayPosts'),
      ('帖子', 'totalPosts'),
      ('会员', 'totalMembers')
    ];
    return Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: LayoutBuilder(builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final columns = scale > 1.5 ? 2 : 4;
              return Wrap(runSpacing: 8, children: [
                for (final metric in metrics)
                  SizedBox(
                      width: constraints.maxWidth / columns,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(metric.$1,
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(stats.display(metric.$2),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: metric.$2 == 'todayPosts'
                                    ? scheme.primary
                                    : scheme.onSurface)),
                      ])),
              ]);
            })));
  }
}

double _homeTextHeight(
  BuildContext context,
  String text,
  TextStyle style, {
  int maxLines = 1,
  double maxWidth = double.infinity,
}) {
  final defaults = DefaultTextStyle.of(context);
  final painter = TextPainter(
    text: TextSpan(text: text, style: defaults.style.merge(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    textHeightBehavior: defaults.textHeightBehavior,
    maxLines: maxLines,
    ellipsis: '\u2026',
  )..layout(maxWidth: maxWidth);
  final height = painter.height;
  painter.dispose();
  return height;
}

List<String> _homeBoardDetails(Forum forum) => [
      if (forum.todayCount >= 0) '今日 ${forum.displayCount('today')}',
      if (forum.threadCount >= 0) '帖数 ${forum.displayCount('posts')}',
    ];

double _homeBoardChipExtent(
  BuildContext context, {
  double minimum = 56,
  double width = 180,
  Iterable<Forum> forums = const [],
}) {
  final textTheme = Theme.of(context).textTheme;
  final titleStyle = (textTheme.bodyMedium ?? const TextStyle())
      .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600);
  final detailStyle =
      (textTheme.bodySmall ?? const TextStyle()).copyWith(fontSize: 11);
  var height = 26.0;
  for (final forum in forums) {
    final textWidth = max(1.0, width - 70);
    final title = _homeTextHeight(context, forum.name, titleStyle,
        maxLines: 2, maxWidth: textWidth);
    final details = _homeBoardDetails(forum);
    final detail = details.isEmpty
        ? 0.0
        : _homeTextHeight(context, details.join(' · '), detailStyle,
            maxLines: 2, maxWidth: textWidth);
    height = max(height, title + detail + 2);
  }
  return max(minimum, height + 16 + 1.6).ceilToDouble();
}

/// 版块导航（横向滚动）
class ForumNav extends StatefulWidget {
  final List<ForumGroup> groups;
  final Set<int> favFids;
  final Future<bool> Function(Forum, bool favorite)? onToggleFav;
  final ValueChanged<Forum>? onOpen;
  final VoidCallback? onAllForums;
  final bool compact;
  final bool isPreview;

  const ForumNav({
    super.key,
    required this.groups,
    this.favFids = const {},
    this.onToggleFav,
    this.onOpen,
    this.onAllForums,
    this.compact = false,
    this.isPreview = false,
  });

  /// 展平后的全部版块（收藏弹层/检索用）
  List<Forum> get allForums => groups.expand((g) => g.forums).toList();

  /// 按版块名匹配图标颜色
  static Color forumIconColor(String name) {
    if (name.contains('资源') || name.contains('下载') || name.contains('整合')) {
      return const Color(0xFF43A047);
    }
    if (name.contains('求助') || name.contains('问答') || name.contains('问题')) {
      return const Color(0xFFFB8C00);
    }
    if (name.contains('讨论') || name.contains('交流') || name.contains('闲聊')) {
      return const Color(0xFF1E88E5);
    }
    if (name.contains('公告') || name.contains('版务')) {
      return const Color(0xFF8E24AA);
    }
    if (name.contains('作品') || name.contains('创作')) {
      return const Color(0xFFE53935);
    }
    if (name.contains('交易') || name.contains('市场')) {
      return const Color(0xFF00897B);
    }
    return const Color(0xFF1E88E5);
  }

  /// 按版块名匹配图标
  static IconData forumIcon(String name) {
    if (name.contains('资源') || name.contains('下载') || name.contains('整合')) {
      return Icons.download_outlined;
    }
    if (name.contains('求助') || name.contains('问答') || name.contains('问题')) {
      return Icons.help_outline;
    }
    if (name.contains('讨论') || name.contains('交流') || name.contains('闲聊')) {
      return Icons.forum_outlined;
    }
    if (name.contains('公告') || name.contains('版务')) {
      return Icons.campaign_outlined;
    }
    if (name.contains('新闻') || name.contains('资讯')) {
      return Icons.article_outlined;
    }
    if (name.contains('作品') || name.contains('展示') || name.contains('创作')) {
      return Icons.brush_outlined;
    }
    if (name.contains('交易') || name.contains('市场')) {
      return Icons.shopping_cart_outlined;
    }
    return Icons.forum_outlined;
  }

  @override
  State<ForumNav> createState() => _ForumNavState();
}

class _ForumNavState extends State<ForumNav> {
  int? _selectedGroupId;
  bool _showAllInGroup = false;
  bool _expandAll = false;
  bool _compactExpanded = false;

  void _showFavForums(BuildContext context) {
    if (widget.isPreview) return;
    final seen = <int>{};
    final favList = widget.allForums
        .where((f) => widget.favFids.contains(f.fid) && seen.add(f.fid))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _FavForumsSheet(
        forums: favList,
        onToggleFav: widget.onToggleFav,
        onOpen: (forum) => widget.onOpen?.call(forum),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.groups.isEmpty) return const SizedBox.shrink();

    final effectiveGroups = DiscuzFavorites.groupsWithSavedForums(
        widget.groups, widget.favFids,
        knownForums: widget.allForums);
    if (effectiveGroups.isEmpty) return const SizedBox.shrink();
    final currentGroup = effectiveGroups.firstWhere(
        (group) => group.gid == _selectedGroupId,
        orElse: () => effectiveGroups.first);

    Widget animated(Widget child) => AppAnimatedSize(
        duration: AppMotion.duration(context, 180),
        alignment: Alignment.topCenter,
        child: child);

    if (widget.compact && !_compactExpanded) {
      return animated(_compactView(context, currentGroup));
    }

    return animated(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分区标题栏：标题 + 展开/折叠切换 + 收藏 + 全部分区
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.compact)
                TextButton.icon(
                    key: const ValueKey('home-forums-collapse'),
                    onPressed: () => setState(() => _compactExpanded = false),
                    icon: const Icon(Icons.expand_less_rounded, size: 18),
                    label: const Text('收起版块')),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 4,
                    height: 15,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '论坛版块分类',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _expandAll = !_expandAll),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expandAll ? '收起分类' : '展开全部分区',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Icon(
                        _expandAll ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.favFids.isNotEmpty) ...[
                GestureDetector(
                  key: const ValueKey('home-favorites-open'),
                  onTap: () => _showFavForums(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star,
                          size: 15, color: Color(0xFFFFB300)),
                      const SizedBox(width: 2),
                      Text(
                        '收藏 ${widget.favFids.length}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: widget.isPreview ? null : widget.onAllForums,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '全部分区',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 16, color: colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 分区分类 Tab 栏（如果未展开全部时显示）
        if (!_expandAll) ...[
          SizedBox(
            height: max(
                38,
                _homeTextHeight(context, '分类', const TextStyle(fontSize: 12)) +
                    20),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: effectiveGroups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final g = effectiveGroups[i];
                final isSelected = g.gid == currentGroup.gid;
                return ChoiceChip(
                  label: Text(g.name),
                  selected: isSelected,
                  selectedColor: colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                  visualDensity: VisualDensity.compact,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedGroupId = g.gid;
                        _showAllInGroup = false;
                      });
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // 当前选中分区的版块网格（平滑过渡动画 + 全宽自适应网格）
          AnimatedSwitcher(
            duration: AppMotion.duration(context, 220),
            switchInCurve: AppMotion.emphasized,
            switchOutCurve: AppMotion.exit,
            child: KeyedSubtree(
              key: ValueKey<int>(currentGroup.gid),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    final scale =
                        MediaQuery.textScalerOf(context).scale(12.5) / 12.5;
                    final crossCount = (constraints.maxWidth / (160 * scale))
                        .floor()
                        .clamp(1, isWide ? 4 : 2);
                    final limit = isWide ? 8 : 4;
                    final shown = _showAllInGroup
                        ? currentGroup.forums.length
                        : min(limit, currentGroup.forums.length);
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: shown,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossCount,
                          mainAxisExtent: _homeBoardChipExtent(context,
                              width: (constraints.maxWidth -
                                      8 * (crossCount - 1)) /
                                  crossCount,
                              forums: currentGroup.forums.take(shown)),
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemBuilder: (ctx, idx) =>
                            _boardChip(context, currentGroup.forums[idx]),
                      ),
                      if (currentGroup.forums.length > limit)
                        Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => setState(
                                  () => _showAllInGroup = !_showAllInGroup),
                              child: Text(_showAllInGroup
                                  ? '收起当前分区'
                                  : '展开当前分区 · 共 ${currentGroup.forums.length} 个版块'),
                            )),
                    ]);
                  },
                ),
              ),
            ),
          ),
        ] else ...[
          // 展开全部分区手风琴
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final g in effectiveGroups)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: _CollapsibleGroup(
                      group: g,
                      initiallyExpanded: true,
                      favFids: widget.favFids,
                      onToggleFav: widget.onToggleFav,
                      boardChip: _boardChip,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    ));
  }

  Widget _boardChip(BuildContext context, Forum f) {
    final theme = Theme.of(context);
    final fav = widget.favFids.contains(f.fid);
    final todayCount = f.todayCount >= 0 ? f.todayCount : -1;
    final details = _homeBoardDetails(f);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(50),
          width: 0.8,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.isPreview || widget.onOpen == null
              ? null
              : () => widget.onOpen!(f),
          onLongPress: widget.isPreview || widget.onToggleFav == null
              ? null
              : () => widget.onToggleFav!(f, !fav),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                if (f.iconUrl != null)
                  CachedNetworkImage(
                    imageUrl: f.iconUrl!,
                    cacheKey: KlpbbsCacheManager.normalizeCacheKey(f.iconUrl!),
                    cacheManager: KlpbbsCacheManager.instance,
                    httpHeaders: AppConfig.imageHeaders,
                    width: 26,
                    height: 26,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => Icon(
                      ForumNav.forumIcon(f.name),
                      size: 22,
                      color: ForumNav.forumIconColor(f.name),
                    ),
                  )
                else
                  Icon(
                    ForumNav.forumIcon(f.name),
                    size: 22,
                    color: ForumNav.forumIconColor(f.name),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      if (details.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              details.join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: todayCount > 0
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant
                                        .withAlpha(200),
                                fontWeight: todayCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            )),
                    ],
                  ),
                ),
                if (fav)
                  const Icon(Icons.star, size: 14, color: Color(0xFFFFB300)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactView(BuildContext context, ForumGroup group) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 12, 4),
          child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(group.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant)),
                TextButton.icon(
                    key: const ValueKey('home-forums-expand'),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => setState(() => _compactExpanded = true),
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: const Text('展开分类', style: TextStyle(fontSize: 12))),
                TextButton(
                    onPressed: widget.isPreview ? null : widget.onAllForums,
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: const Text('全部版块', style: TextStyle(fontSize: 12))),
                if (widget.favFids.isNotEmpty)
                  TextButton.icon(
                      key: const ValueKey('home-favorites-open'),
                      onPressed: widget.isPreview
                          ? null
                          : () => _showFavForums(context),
                      icon: const Icon(Icons.star_rounded, size: 16),
                      label: Text('${widget.favFids.length}')),
              ])),
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(12.5) / 12.5;
        final width =
            max(1.0, min(constraints.maxWidth - 24, max(210.0, 200 * scale)));
        final height =
            _homeBoardChipExtent(context, width: width, forums: group.forums);
        return SizedBox(
            height: height,
            child: ListView.separated(
                key: const ValueKey('home-compact-forum-strip'),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: group.forums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SizedBox(
                    width: width,
                    child: _boardChip(context, group.forums[index]))));
      }),
    ]);
  }
}

/// 可折叠的版块分组（点击标题展开/收起）
class _CollapsibleGroup extends StatefulWidget {
  final ForumGroup group;
  final bool initiallyExpanded;
  final Set<int> favFids;
  final Future<bool> Function(Forum, bool favorite)? onToggleFav;
  final Widget Function(BuildContext, Forum) boardChip;

  const _CollapsibleGroup({
    required this.group,
    required this.initiallyExpanded,
    required this.favFids,
    this.onToggleFav,
    required this.boardChip,
  });

  @override
  State<_CollapsibleGroup> createState() => _CollapsibleGroupState();
}

class _CollapsibleGroupState extends State<_CollapsibleGroup> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.group.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LayoutBuilder(
              builder: (ctx, c) {
                final scale =
                    MediaQuery.textScalerOf(context).scale(12.5) / 12.5;
                final columns =
                    (c.maxWidth / (160 * scale)).floor().clamp(1, 4);
                return GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: _homeBoardChipExtent(context,
                        width: (c.maxWidth - (columns - 1) * 8) / columns,
                        forums: widget.group.forums),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  children: [
                    for (final f in widget.group.forums)
                      widget.boardChip(context, f),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 收藏版块底部弹层（搜索 + 移除 + 跳转）
class _FavForumsSheet extends StatefulWidget {
  final List<Forum> forums;
  final Future<bool> Function(Forum, bool favorite)? onToggleFav;
  final ValueChanged<Forum> onOpen;

  const _FavForumsSheet({
    required this.forums,
    required this.onToggleFav,
    required this.onOpen,
  });

  @override
  State<_FavForumsSheet> createState() => _FavForumsSheetState();
}

class _FavForumsSheetState extends State<_FavForumsSheet> {
  String _kw = '';

  /// 名称关键词高亮
  TextSpan _highlightName(String text, String kw) {
    if (kw.isEmpty) return TextSpan(text: text);
    final scheme = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    var start = 0;
    while (start < text.length) {
      final idx = text.indexOf(kw, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + kw.length),
          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold),
        ),
      );
      start = idx + kw.length;
      if (kw.isEmpty) break;
    }
    return TextSpan(children: spans);
  }

  bool _editMode = false;
  final Set<int> _selected = {};
  final Set<int> _removed = {};
  final Set<int> _busy = {};
  bool _batchBusy = false;

  List<Forum> get _remainingForums =>
      widget.forums.where((forum) => !_removed.contains(forum.fid)).toList();

  void _removeLocally(Forum forum) {
    if (!mounted) return;
    setState(() {
      _removed.add(forum.fid);
      _selected.remove(forum.fid);
      _busy.remove(forum.fid);
    });
  }

  Future<bool> _removeForum(Forum forum, {bool dismissing = false}) async {
    final callback = widget.onToggleFav;
    if (callback == null ||
        _removed.contains(forum.fid) ||
        !_busy.add(forum.fid)) {
      return false;
    }
    setState(() {});
    var success = false;
    try {
      success = await callback(forum, false);
      if (!mounted) return false;
      if (success && !dismissing) _removeLocally(forum);
      return success;
    } catch (_) {
      // 调用方负责服务器反馈；异常不能被误判为已成功移除。
      return false;
    } finally {
      // 滑动成功后的行保持锁定，直到 onDismissed 同步移出列表。
      if (mounted && (!dismissing || !success)) {
        setState(() => _busy.remove(forum.fid));
      }
    }
  }

  Future<void> _removeSelected() async {
    if (_batchBusy || _selected.isEmpty || widget.onToggleFav == null) return;
    final forums = _remainingForums
        .where((forum) => _selected.contains(forum.fid))
        .toList();
    setState(() => _batchBusy = true);
    try {
      for (final forum in forums) {
        if (!mounted) return;
        await _removeForum(forum);
      }
    } finally {
      if (mounted) {
        setState(() {
          _batchBusy = false;
          if (_selected.isEmpty) _editMode = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final favList = _remainingForums;
    return SafeArea(
      key: const ValueKey('home-favorites-sheet'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(children: [
              Expanded(
                  child: Text('收藏版块（${favList.length}）',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15))),
              TextButton(
                  key: const ValueKey('home-favorites-manage'),
                  onPressed: _batchBusy || _busy.isNotEmpty || favList.isEmpty
                      ? null
                      : () => setState(() {
                            _editMode = !_editMode;
                            if (!_editMode) _selected.clear();
                          }),
                  child: Text(_editMode ? '完成' : '管理')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              key: const ValueKey('home-favorites-search'),
              onChanged: (v) => setState(() => _kw = v.trim()),
              decoration: InputDecoration(
                hintText: '搜索收藏版块',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _kw.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => setState(() => _kw = ''),
                      ),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const Divider(height: 1),
          if (favList.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('暂无收藏版块（长按版块收藏）'),
            )
          else
            ...favList.where((f) => _kw.isEmpty || f.name.contains(_kw)).map(
                  (f) => Dismissible(
                    key: ValueKey('fav_${f.fid}'),
                    // 保持确认中的滑动轴不变；confirmDismiss 与 _busy 拦截重复请求。
                    direction: _batchBusy || widget.onToggleFav == null
                        ? DismissDirection.none
                        : DismissDirection.endToStart,
                    confirmDismiss: (_) => _removeForum(f, dismissing: true),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onDismissed: (_) => _removeLocally(f),
                    child: ListTile(
                      leading: _editMode
                          ? Checkbox(
                              value: _selected.contains(f.fid),
                              onChanged: _batchBusy || _busy.contains(f.fid)
                                  ? null
                                  : (_) => setState(() {
                                        _selected.contains(f.fid)
                                            ? _selected.remove(f.fid)
                                            : _selected.add(f.fid);
                                      }),
                            )
                          : Icon(
                              ForumNav.forumIcon(f.name),
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      title: _kw.isEmpty
                          ? Text(f.name)
                          : Text.rich(_highlightName(f.name, _kw)),
                      trailing: _editMode
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: ValueKey(
                                      'home-favorites-remove-${f.fid}'),
                                  icon: _busy.contains(f.fid)
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: AppLoadingIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.close, size: 16),
                                  tooltip: '移除收藏',
                                  onPressed: _batchBusy ||
                                          _busy.contains(f.fid) ||
                                          widget.onToggleFav == null
                                      ? null
                                      : () => _removeForum(f),
                                ),
                                const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                      onTap: _batchBusy || _busy.contains(f.fid)
                          ? null
                          : () {
                              if (_editMode) {
                                setState(() {
                                  _selected.contains(f.fid)
                                      ? _selected.remove(f.fid)
                                      : _selected.add(f.fid);
                                });
                                return;
                              }
                              Navigator.of(context).pop();
                              widget.onOpen(f);
                            },
                    ),
                  ),
                ),
          if (_editMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.select_all, size: 18),
                    label: Text('全选'),
                    onPressed: _batchBusy || _busy.isNotEmpty
                        ? null
                        : () => setState(() {
                              _selected.isEmpty
                                  ? _selected.addAll(favList.map((f) => f.fid))
                                  : _selected.clear();
                            }),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    key: const ValueKey('home-favorites-remove-selected'),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('移除 (${_selected.length})'),
                    onPressed: _selected.isEmpty ||
                            _batchBusy ||
                            _busy.isNotEmpty ||
                            widget.onToggleFav == null
                        ? null
                        : _removeSelected,
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class QuickActionsWidget extends StatelessWidget {
  final List<String> actionIds;
  final ValueChanged<int>? onNavigate;
  final VoidCallback? onCustomize;
  final bool compact;
  const QuickActionsWidget(
      {super.key,
      required this.actionIds,
      this.onNavigate,
      this.onCustomize,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metadata = {
      for (final item in MobileHomeCustomizer.allQuickActions) item.id: item
    };
    final items = [
      for (final id in actionIds)
        if (metadata[id] != null) metadata[id]!
    ];
    return Padding(
        padding: EdgeInsets.fromLTRB(14, compact ? 4 : 10, 14, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('常用功能',
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600))),
            TextButton.icon(
                key: const ValueKey('home-customize-mobile'),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: onCustomize,
                icon: const Icon(Icons.tune_rounded, size: 15),
                label: const Text('自定义', style: TextStyle(fontSize: 12))),
          ]),
          LayoutBuilder(builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
            final columns = scale > 1.5 ? 2 : 4;
            final width = constraints.maxWidth / columns;
            return Wrap(runSpacing: 6, children: [
              for (final item in items)
                SizedBox(
                    width: width,
                    child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: onNavigate == null
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                onNavigate!(item.tabIndex);
                              },
                        onLongPress: onCustomize,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 2),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                      width: compact ? 38 : 46,
                                      height: compact ? 38 : 46,
                                      decoration: BoxDecoration(
                                          color: item.color.withAlpha(24),
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                      child: Icon(item.icon,
                                          color: item.color, size: 22)),
                                  const SizedBox(height: 4),
                                  Text(item.label,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500)),
                                ])))),
            ]);
          }),
        ]));
  }
}

/// 首页推荐轮播（横幅卡片 + 自动播放 + 指示点）
class _RecommendCarousel extends StatefulWidget {
  final List<ThreadSummary> threads;
  final ValueChanged<int>? onTap;
  final bool compact;
  final bool isPreview;

  const _RecommendCarousel(
      {required this.threads,
      this.onTap,
      this.compact = false,
      this.isPreview = false});

  @override
  State<_RecommendCarousel> createState() => _RecommendCarouselState();
}

class _RecommendCarouselState extends State<_RecommendCarousel>
    with WidgetsBindingObserver {
  final _ctrl = PageController();
  Timer? _timer;
  int _index = 0;
  bool _tickerEnabled = true,
      _resumed = true,
      _systemReduced = false,
      _hovered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.of(context);
    _systemReduced = MediaQuery.disableAnimationsOf(context);
    _pauseAuto();
    _resumeAuto();
  }

  @override
  void didUpdateWidget(covariant _RecommendCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.threads.length) {
      _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ctrl.hasClients) _ctrl.jumpToPage(0);
      });
    }
    _pauseAuto();
    _resumeAuto();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _pauseAuto();
    _resumeAuto();
  }

  void _pauseAuto() {
    _timer?.cancel();
    _timer = null;
  }

  void _resumeAuto() {
    if (_timer != null ||
        widget.isPreview ||
        !_tickerEnabled ||
        !_resumed ||
        _systemReduced ||
        _hovered ||
        AppConfig.reduceMotion ||
        !AppConfig.bannerAutoPlay ||
        widget.threads.length <= 1) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.threads.length <= 1 || !_ctrl.hasClients) return;
      final next = (_index + 1) % widget.threads.length;
      _ctrl.animateToPage(
        next,
        duration: AppMotion.duration(context, 320),
        curve: AppMotion.emphasized,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
        onEnter: (_) {
          _hovered = true;
          _pauseAuto();
        },
        onExit: (_) {
          _hovered = false;
          _resumeAuto();
        },
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _buildContents(context, constraints.maxWidth),
        ));
  }

  double _cardHeight(BuildContext context, double width) {
    final textWidth = max(1.0, width - (widget.compact ? 48 : 52));
    final badgeHeight = _homeTextHeight(
      context,
      '推荐',
      const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
    );
    var contentHeight = 0.0;
    for (final thread in widget.threads) {
      final titleHeight = _homeTextHeight(
        context,
        thread.title,
        const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        maxLines: 2,
        maxWidth: textWidth,
      );
      final info = [thread.author, thread.timeText ?? '']
          .where((value) => value.trim().isNotEmpty)
          .join(' · ');
      final infoHeight = _homeTextHeight(
        context,
        info.isNotEmpty ? info : (thread.forumName ?? ''),
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        maxWidth: textWidth,
      );
      contentHeight = max(contentHeight, titleHeight + infoHeight);
    }
    // Page padding 12 + card padding 28 + badge padding 4 + metadata gap 4.
    // Reserve 8 px between the badge and title even with large system text.
    return max(
            widget.compact ? 92.0 : 110.0,
            (widget.compact ? 32 : 40) +
                badgeHeight +
                4 +
                8 +
                contentHeight +
                4)
        .ceilToDouble();
  }

  Widget _buildContents(BuildContext context, double width) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: _cardHeight(context, width),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification) {
                _pauseAuto();
              } else if (n is ScrollEndNotification) {
                _resumeAuto();
              }
              return false;
            },
            child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(dragDevices: {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.touch,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                }),
                child: PageView.builder(
                  key: const PageStorageKey('rec_carousel'),
                  controller: _ctrl,
                  itemCount: widget.threads.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final t = widget.threads[i];
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                          12, widget.compact ? 4 : 8, 12, 4),
                      child: GestureDetector(
                        onTap: widget.onTap == null
                            ? null
                            : () => widget.onTap!(t.tid),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: scheme.outlineVariant.withAlpha(50),
                              width: 0.8,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // 帖子封面（有图时背景，配深色渐变保证文字可读）
                                  if (t.coverUrl != null &&
                                      t.coverUrl!.isNotEmpty) ...[
                                    RetryImage(
                                      imageUrl: t.coverUrl!,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.center,
                                      filterQuality: FilterQuality.low,
                                      memCacheWidth: 720,
                                      errorWidget: (_, __, ___) =>
                                          const SizedBox.shrink(),
                                    ),
                                    const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0x20000000),
                                            Color(0xCC000000),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  Padding(
                                    padding: EdgeInsets.all(
                                        widget.compact ? 12 : 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: scheme.primary,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '推荐',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: scheme.onPrimary,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          t.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: t.coverUrl != null &&
                                                    t.coverUrl!.isNotEmpty
                                                ? Colors.white
                                                : scheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Builder(
                                          builder: (_) {
                                            final info = [
                                              t.author,
                                              t.timeText ?? ''
                                            ]
                                                .where((value) =>
                                                    value.trim().isNotEmpty)
                                                .join(' · ');
                                            return Text(
                                              info.isNotEmpty
                                                  ? info
                                                  : (t.forumName ?? ''),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: t.coverUrl != null &&
                                                        t.coverUrl!.isNotEmpty
                                                    ? Colors.white
                                                        .withAlpha(220)
                                                    : scheme.onSurfaceVariant,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                )),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.threads.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: i == _index ? 14 : 5,
                height: 4,
                decoration: BoxDecoration(
                  color: i == _index ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
