import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/thread_summary.dart';
import '../../pages/thread_detail_page.dart';
import '../retry_image.dart';
import '../interactive_animations.dart';
import 'dashboard_card_frame.dart';

/// 13. 全站热门帖子卡片
/// 支持多种数据展示样式：
/// - leaderboard: 热度排行榜（金银铜奖牌标，热度值与阅评统计）
/// - compact: 紧凑图文行（高信息密度，左侧摘要右侧高清缩略图，1:1 对齐实际论坛卡片）
/// - magazine: 画报大图焦点（首条 16:9 全景头图 + 精品条目列表）
/// - minimal: 极简文字流（纯文本高密度速览）
class HotThreadsDashboardCard extends StatelessWidget {
  final DashboardGridItem item;
  final bool isPreview;
  final List<ThreadSummary>? threads;

  const HotThreadsDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
    this.threads,
  });

  static const List<ThreadSummary> _fixedHotThreads = [
    ThreadSummary(
      tid: 9901,
      title: '【官方】苦力怕论坛 2026 年度社区创作激励与总坛规说明',
      author: '苦力怕论坛管理组',
      uid: 1,
      timeText: '全站置顶',
      replies: 520,
      views: 18900,
      excerpt: '开启全新创作者激励计划，全面提升优质模组、整合包与材质光影资源扶持力度！',
      coverUrl: 'https://img.klpbbs.com/attachment/forum/202401/01/banner_2024.jpg',
    ),
    ThreadSummary(
      tid: 9902,
      title: '【材质】超沉浸全自然生态材质包 4K 演示及下载',
      author: '自然工匠',
      uid: 5,
      timeText: '2小时前',
      replies: 231,
      views: 8900,
      excerpt: '重构光影算法与全动态视差贴图，呈现电影级方块世界光影艺术。',
      coverUrl: 'https://img.klpbbs.com/attachment/forum/202401/02/nature_texture.jpg',
    ),
    ThreadSummary(
      tid: 9903,
      title: '【教程】用单指令方块搞定全服跨维度传送门系统',
      author: '指令狂人',
      uid: 8,
      timeText: '3小时前',
      replies: 165,
      views: 7420,
      excerpt: '无需插件与前置库，纯原版指令实现丝滑跨服重定向与多世界传送。',
    ),
    ThreadSummary(
      tid: 9904,
      title: '【活动】第三届苦力怕建筑大赛：重构文明古迹',
      author: '活动菌',
      uid: 12,
      timeText: '5小时前',
      replies: 388,
      views: 14200,
      excerpt: '千元奖池与限定金质勋章等你来拿，立即报名展现你的绝佳匠心！',
      coverUrl: 'https://img.klpbbs.com/attachment/forum/202401/03/build_contest.jpg',
    ),
    ThreadSummary(
      tid: 9905,
      title: '【模组】机械纪元：自动化工厂与红石流水线模组发布',
      author: '红石极客',
      uid: 26,
      timeText: '6小时前',
      replies: 142,
      views: 6300,
      excerpt: '引入超过 80 种高精度自动化机械、齿轮传动与动力网络系统。',
    ),
    ThreadSummary(
      tid: 9906,
      title: '【整合】荒野生存极限难度 100 天生存整合包 v2.4',
      author: '生存挑战者',
      uid: 33,
      timeText: '8小时前',
      replies: 279,
      views: 9800,
      excerpt: '真实体温、水分与重伤机制，打造硬核极限挑战体验。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardTheme = DashboardCardTheme.of(context);
    final accentColor = cardTheme.accentColor;

    var workingList = (threads != null && threads!.isNotEmpty)
        ? List<ThreadSummary>.from(threads!)
        : List<ThreadSummary>.from(_fixedHotThreads);
    final filterFid = (item.customParams['filterFid'] as num?)?.toInt() ?? 0;
    if (filterFid > 0) {
      final filtered = workingList.where((t) => t.fid == filterFid).toList();
      if (filtered.isNotEmpty) {
        workingList = filtered;
      }
    }

    final sortOrder = item.customParams['sortOrder'] as String? ?? 'hot';
    if (sortOrder == 'replies') {
      workingList.sort((a, b) => b.replies.compareTo(a.replies));
    } else if (sortOrder == 'views') {
      workingList.sort((a, b) => b.views.compareTo(a.views));
    } else if (sortOrder == 'hot') {
      workingList.sort((a, b) => (b.replies * 3 + b.views).compareTo(a.replies * 3 + a.views));
    }

    final list = workingList;
    final customTitle = item.customParams['customTitle'] as String?;
    final String title;
    if (customTitle != null && customTitle.isNotEmpty) {
      title = customTitle;
    } else if (sortOrder == 'replies') {
      title = '全站热评帖子';
    } else if (sortOrder == 'views') {
      title = '全站高阅读帖';
    } else if (sortOrder == 'newest') {
      title = '全站最新帖子';
    } else {
      title = '全站热帖榜';
    }

    final rawDataStyle = item.customParams['dataStyle'] as String? ?? 'auto';
    final String dataStyle;
    if (rawDataStyle == 'auto') {
      if (item.rowSpan <= 1) {
        dataStyle = 'minimal';
      } else if (item.rowSpan == 2) {
        dataStyle = 'leaderboard';
      } else {
        dataStyle = item.colSpan >= 4 ? 'magazine' : 'compact';
      }
    } else {
      dataStyle = rawDataStyle;
    }

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: item,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department_rounded, size: 17, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: accentColor.withAlpha(50), width: 0.8),
                  ),
                  child: Text(
                    _getDataStyleBadge(dataStyle),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey('hot-$dataStyle-${list.length}'),
                  child: _buildDataContent(context, dataStyle, list, accentColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDataStyleBadge(String style) {
    switch (style) {
      case 'compact':
        return '图文行';
      case 'magazine':
        return '焦点画报';
      case 'minimal':
        return '速览';
      case 'leaderboard':
      default:
        return 'TOP 榜';
    }
  }

  Widget _buildDataContent(
    BuildContext context,
    String dataStyle,
    List<ThreadSummary> list,
    Color accentColor,
  ) {
    switch (dataStyle) {
      case 'compact':
        return _buildCompactStyle(context, list, accentColor);
      case 'magazine':
        return _buildMagazineStyle(context, list, accentColor);
      case 'minimal':
        return _buildMinimalStyle(context, list, accentColor);
      case 'leaderboard':
      default:
        return _buildLeaderboardStyle(context, list, accentColor);
    }
  }

  void _onThreadTap(BuildContext context, ThreadSummary t) {
    if (isPreview) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('预览模式：查看热门帖子「${t.title}」'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: t.tid)),
    );
  }

  /// 1. 紧凑图文行数据样式（1:1 对齐实际论坛 ThreadCard 紧凑排版）
  Widget _buildCompactStyle(BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = item.rowSpan <= 1 ? 1 : (item.rowSpan == 2 ? 2 : (item.rowSpan == 3 ? 3 : 5));
    final displayList = list.take(takeCount).toList();

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: displayList.length,
      separatorBuilder: (_, __) => const Divider(height: 8, thickness: 0.5),
      itemBuilder: (context, idx) {
        final t = displayList[idx];
        final hasImage = t.coverUrl != null && t.coverUrl!.isNotEmpty;

        return PressScaleEffect(
          scaleDown: 0.985,
          child: InkWell(
            onTap: () => _onThreadTap(context, t),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        if (t.excerpt != null && t.excerpt!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            t.excerpt!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              t.author,
                              style: TextStyle(fontSize: 9.5, color: colorScheme.onSurfaceVariant.withAlpha(180)),
                            ),
                            const Spacer(),
                            Text(
                              '💬 ${t.replies}',
                              style: TextStyle(fontSize: 9.5, color: accentColor, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (hasImage) ...[
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 58,
                        height: 42,
                        child: RetryImage(
                          imageUrl: t.coverUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 150,
                          placeholder: (_, __) => Container(
                            color: colorScheme.surfaceContainerHighest.withAlpha(80),
                            child: Icon(Icons.image_outlined, size: 16, color: colorScheme.outlineVariant),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest.withAlpha(80),
                            child: Icon(Icons.image_outlined, size: 16, color: colorScheme.outlineVariant),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 2. 焦点画报大图数据样式（头条全景大图 + 精品条目列表）
  Widget _buildMagazineStyle(BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    if (list.isEmpty) return const SizedBox.shrink();
    final first = list.first;
    final subList = list.skip(1).take(item.rowSpan >= 3 ? 2 : 1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 焦点头图
        Expanded(
          flex: 5,
          child: PressScaleEffect(
            scaleDown: 0.985,
            child: InkWell(
              onTap: () => _onThreadTap(context, first),
              borderRadius: BorderRadius.circular(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (first.coverUrl != null && first.coverUrl!.isNotEmpty)
                      RetryImage(
                        imageUrl: first.coverUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 400,
                        placeholder: (_, __) => Container(color: colorScheme.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [accentColor.withAlpha(160), accentColor.withAlpha(60)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(Icons.art_track_rounded, color: Colors.white, size: 32),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accentColor.withAlpha(160), accentColor.withAlpha(60)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.art_track_rounded, color: Colors.white, size: 32),
                      ),
                    // 渐变遮罩与文字浮层
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, Colors.black87],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              first.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  first.author,
                                  style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 9.5),
                                ),
                                const Spacer(),
                                Text(
                                  '🔥 ${first.views}',
                                  style: const TextStyle(color: Colors.amberAccent, fontSize: 9.5, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (subList.isNotEmpty) ...[
          const SizedBox(height: 6),
          // 次级精品条目
          Expanded(
            flex: 4,
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: subList.length,
              separatorBuilder: (_, __) => const Divider(height: 6, thickness: 0.5),
              itemBuilder: (context, i) {
                final t = subList[i];
                return PressScaleEffect(
                  scaleDown: 0.985,
                  child: InkWell(
                    onTap: () => _onThreadTap(context, t),
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('${t.replies}评', style: TextStyle(fontSize: 9.5, color: colorScheme.outline)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  /// 3. 极简文字流数据样式（纯净文本高密度速览）
  Widget _buildMinimalStyle(BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = item.rowSpan <= 1 ? 1 : (item.rowSpan == 2 ? 4 : (item.rowSpan == 3 ? 5 : 7));
    final displayList = list.take(takeCount).toList();

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: displayList.length,
      separatorBuilder: (_, __) => const Divider(height: 6, thickness: 0.4),
      itemBuilder: (context, idx) {
        final t = displayList[idx];
        return PressScaleEffect(
          scaleDown: 0.985,
          child: InkWell(
            onTap: () => _onThreadTap(context, t),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  Text(
                    '•',
                    style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${t.views}阅',
                    style: TextStyle(fontSize: 9.5, color: colorScheme.outline.withAlpha(180)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 4. 经典热度排行榜数据样式（金银铜奖牌标，热度值与阅评统计）
  Widget _buildLeaderboardStyle(BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = item.rowSpan <= 1
        ? 1
        : (item.rowSpan == 2 ? 3 : (item.rowSpan == 3 ? 4 : 6));
    final displayList = list.take(takeCount).toList();

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: displayList.length,
      separatorBuilder: (_, __) => const Divider(height: 7, thickness: 0.5),
      itemBuilder: (context, idx) {
        final t = displayList[idx];
        return PressScaleEffect(
          scaleDown: 0.985,
          child: InkWell(
            onTap: () => _onThreadTap(context, t),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildRankBadge(idx, accentColor, colorScheme),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: colorScheme.outline),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '🔥 ${t.views} 阅 · ${t.replies} 评',
                              style: TextStyle(fontSize: 9.5, color: colorScheme.outline.withAlpha(200)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRankBadge(int idx, Color accentColor, ColorScheme colorScheme) {
    BoxDecoration decoration;
    Color textColor = Colors.white;

    switch (idx) {
      case 0:
        decoration = BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFB300), Color(0xFFF57C00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF9800).withAlpha(100),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        );
        break;
      case 1:
        decoration = BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB0BEC5), Color(0xFF78909C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(4),
        );
        break;
      case 2:
        decoration = BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8A65), Color(0xFFD84315)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(4),
        );
        break;
      default:
        decoration = BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withAlpha(140),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outlineVariant.withAlpha(80), width: 0.5),
        );
        textColor = colorScheme.onSurfaceVariant;
    }

    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: decoration,
      child: Text(
        '${idx + 1}',
        style: TextStyle(
          fontSize: 10,
          color: textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
