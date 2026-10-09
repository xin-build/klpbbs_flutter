import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/thread_summary.dart';
import '../../pages/thread_detail_page.dart';
import '../retry_image.dart';
import '../interactive_animations.dart';
import 'dashboard_card_frame.dart';

/// 当前数据流的帖子卡片，排序仅使用这个列表中实际提供的计数。
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardTheme = DashboardCardTheme.of(context);
    final accentColor = cardTheme.accentColor;

    var workingList = (threads != null && threads!.isNotEmpty)
        ? List<ThreadSummary>.from(threads!)
        : <ThreadSummary>[];
    final filterFid = (item.customParams['filterFid'] as num?)?.toInt() ?? 0;
    if (filterFid > 0) {
      final filtered = workingList.where((t) => t.fid == filterFid).toList();
      workingList = filtered;
    }

    final sortOrder = item.customParams['sortOrder'] as String? ?? 'hot';
    if (const {'replies', 'views', 'hot'}.contains(sortOrder)) {
      final originalOrder = {
        for (var i = 0; i < workingList.length; i++) workingList[i]: i
      };
      int? score(ThreadSummary thread) => switch (sortOrder) {
            'replies' => thread.replies >= 0 ? thread.replies : null,
            'views' => thread.views >= 0 ? thread.views : null,
            _ => thread.replies >= 0 && thread.views >= 0
                ? thread.replies * 3 + thread.views
                : null,
          };
      workingList.sort((a, b) {
        final aScore = score(a), bScore = score(b);
        final comparison = aScore == null
            ? (bScore == null ? 0 : 1)
            : (bScore == null ? -1 : bScore.compareTo(aScore));
        return comparison != 0
            ? comparison
            : originalOrder[a]!.compareTo(originalOrder[b]!);
      });
    }

    final list = workingList;
    final customTitle = item.customParams['customTitle'] as String?;
    final String title;
    if (customTitle != null && customTitle.isNotEmpty) {
      title = customTitle;
    } else if (sortOrder == 'replies') {
      title = '当前列表 · 回复排序';
    } else if (sortOrder == 'views') {
      title = '当前列表 · 浏览排序';
    } else if (sortOrder == 'newest') {
      title = '当前列表 · 原始顺序';
    } else if (sortOrder != 'hot') {
      title = '当前列表';
    } else {
      title = '当前列表 · 互动排序';
    }

    final rawDataStyle = item.customParams['dataStyle'] as String? ?? 'auto';
    String dataStyle;
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
    if (dataStyle == 'magazine' &&
        list.firstOrNull?.coverUrl?.isNotEmpty != true) {
      dataStyle = 'compact';
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
                Icon(Icons.local_fire_department_rounded,
                    size: 17, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: accentColor.withAlpha(50), width: 0.8),
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
                  child:
                      _buildDataContent(context, dataStyle, list, accentColor),
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
    if (list.isEmpty) {
      return Center(
          child: Text(threads == null ? '尚未载入帖子' : '当前列表暂无匹配帖子',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12)));
    }
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
  Widget _buildCompactStyle(
      BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = item.rowSpan <= 1
        ? 1
        : (item.rowSpan == 2 ? 2 : (item.rowSpan == 3 ? 3 : 5));
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
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        if (t.excerpt != null && t.excerpt!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            t.excerpt!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10.5, color: colorScheme.outline),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 9.5,
                                    color: colorScheme.onSurfaceVariant
                                        .withAlpha(180)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (t.replies >= 0)
                              Text(
                                '💬 ${t.replies}',
                                style: TextStyle(
                                    fontSize: 9.5,
                                    color: accentColor,
                                    fontWeight: FontWeight.w600),
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
                            color: colorScheme.surfaceContainerHighest
                                .withAlpha(80),
                            child: Icon(Icons.image_outlined,
                                size: 16, color: colorScheme.outlineVariant),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest
                                .withAlpha(80),
                            child: Icon(Icons.image_outlined,
                                size: 16, color: colorScheme.outlineVariant),
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
  Widget _buildMagazineStyle(
      BuildContext context, List<ThreadSummary> list, Color accentColor) {
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
                        placeholder: (_, __) => Container(
                            color: colorScheme.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                accentColor.withAlpha(160),
                                accentColor.withAlpha(60)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(Icons.art_track_rounded,
                              color: Colors.white, size: 32),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentColor.withAlpha(160),
                              accentColor.withAlpha(60)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.art_track_rounded,
                            color: Colors.white, size: 32),
                      ),
                    // 渐变遮罩与文字浮层
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
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
                                Expanded(
                                  child: Text(
                                    first.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: Colors.white.withAlpha(200),
                                        fontSize: 9.5),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (first.views >= 0)
                                  Text(
                                    '${first.views}阅',
                                    style: const TextStyle(
                                        color: Colors.amberAccent,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold),
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
              separatorBuilder: (_, __) =>
                  const Divider(height: 6, thickness: 0.5),
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
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: accentColor),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (t.replies >= 0)
                          Text('${t.replies}评',
                              style: TextStyle(
                                  fontSize: 9.5, color: colorScheme.outline)),
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
  Widget _buildMinimalStyle(
      BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = item.rowSpan <= 1
        ? 1
        : (item.rowSpan == 2 ? 4 : (item.rowSpan == 3 ? 5 : 7));
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
                    style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (t.views >= 0)
                    Text(
                      '${t.views}阅',
                      style: TextStyle(
                          fontSize: 9.5,
                          color: colorScheme.outline.withAlpha(180)),
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
  Widget _buildLeaderboardStyle(
      BuildContext context, List<ThreadSummary> list, Color accentColor) {
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
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10, color: colorScheme.outline),
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (t.views >= 0 || t.replies >= 0)
                              Text(
                                [
                                  if (t.views >= 0) '${t.views}阅',
                                  if (t.replies >= 0) '${t.replies}评',
                                ].join(' · '),
                                style: TextStyle(
                                    fontSize: 9.5,
                                    color: colorScheme.outline.withAlpha(200)),
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
          border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(80), width: 0.5),
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
