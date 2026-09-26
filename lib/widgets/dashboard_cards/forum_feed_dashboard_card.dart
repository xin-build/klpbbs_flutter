import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/thread_summary.dart';
import '../../pages/thread_detail_page.dart';
import '../../pages/thread_list_page.dart';
import '../retry_image.dart';
import '../interactive_animations.dart';
import 'dashboard_card_frame.dart';

/// 11. 指定版块精选帖子流卡片（可自定义关联版块）
/// 支持多种数据展示样式：
/// - compact: 紧凑图文行（高信息密度，左侧摘要右侧缩略图）
/// - magazine: 画报大图焦点（首条 16:9 全景头图 + 精品条目列表）
/// - minimal: 极简文字流（无图纯净文本，极致信息空间利用）
/// - leaderboard: 热度排行榜（排位徽章与评阅统计）
class ForumFeedDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const ForumFeedDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<ForumFeedDashboardCard> createState() => _ForumFeedDashboardCardState();
}

class _ForumFeedDashboardCardState extends State<ForumFeedDashboardCard> {
  List<ThreadSummary> _threads = [];
  bool _loading = true;
  late int _targetFid;
  late String _forumName;

  static const List<ThreadSummary> _fixedPreviewThreads = [
    ThreadSummary(
      tid: 1001,
      title: '【活动】BE附加包板块·老友回归，新人启程（发帖有奖）',
      author: 'YesNewBee',
      uid: 8812,
      timeText: '30分钟前',
      replies: 14,
      views: 520,
      excerpt: '参与 BE 社区讨论或分享原创作品，即有机会赢取正版周边与论坛定制徽章！',
      coverUrl: 'https://img.klpbbs.com/attachment/forum/202401/01/be_event.jpg',
    ),
    ThreadSummary(
      tid: 1002,
      title: '【闲聊】主世界月刊——社区交流讨论与最新动态汇总',
      author: '采矿与合成',
      uid: 4321,
      timeText: '1小时前',
      replies: 28,
      views: 1850,
      excerpt: '回顾近期基岩版与 Java 版优质资源，精选社区精彩热帖与建造趣闻。',
      coverUrl: 'https://img.klpbbs.com/attachment/forum/202401/02/overworld_monthly.jpg',
    ),
    ThreadSummary(
      tid: 1003,
      title: '【讨论】关于 1.21 基岩版与Java版跨平台联机体验交流',
      author: 'MC探索者',
      uid: 12580,
      timeText: '2小时前',
      replies: 45,
      views: 2400,
      excerpt: '通过 Geyser 等中间件实现双端互通的红石时序差异与方块碰撞兼容总结。',
    ),
    ThreadSummary(
      tid: 1004,
      title: '【建筑】中世纪欧式城堡全景搭建过程与内饰设计分享',
      author: '方块艺术家',
      uid: 9527,
      timeText: '4小时前',
      replies: 32,
      views: 1680,
      excerpt: '耗时两个月完成的哥特式大教堂与内饰精细布局全角度截图。',
      coverUrl: 'https://img.klpbbs.com/attachment/forum/202401/03/castle_preview.jpg',
    ),
    ThreadSummary(
      tid: 1005,
      title: '【分享】轻量级光影着色器低配优化方案测评',
      author: '光影工坊',
      uid: 6688,
      timeText: '6小时前',
      replies: 56,
      views: 3200,
      excerpt: '专为千元机与老旧核显调优的实时光追光影包，兼顾帧率与水面反光。',
    ),
    ThreadSummary(
      tid: 1006,
      title: '【问答】红石自动分类机防漏漏斗时序调优指南',
      author: '红石极客',
      uid: 26,
      timeText: '8小时前',
      replies: 19,
      views: 1120,
      excerpt: '解决大流量堆叠物品冲击下漏斗锁死与非正常穿透的根本解决方案。',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _targetFid = (widget.item.customParams['targetFid'] as num?)?.toInt() ?? 41;
    _forumName = widget.item.customParams['forumName'] as String? ?? '闲聊讨论';

    if (widget.isPreview) {
      _threads = _fixedPreviewThreads;
      _loading = false;
    } else {
      _loadForumThreads();
    }
  }

  Future<void> _loadForumThreads() async {
    try {
      final list = await KlpbbsApi.getThreadList(_targetFid, page: 1);
      if (mounted) {
        setState(() {
          _threads = list.isNotEmpty ? list : _fixedPreviewThreads;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _threads = _fixedPreviewThreads;
          _loading = false;
        });
      }
    }
  }

  void _openForum() {
    if (widget.isPreview) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('预览模式：打开版块「$_forumName」'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadListPage(fid: _targetFid, title: _forumName),
      ),
    );
  }

  void _openThread(int tid, String title) {
    if (widget.isPreview) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('预览模式：查看精选帖子「$title」'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailPage(tid: tid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardTheme = DashboardCardTheme.of(context);
    final accentColor = cardTheme.accentColor;

    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '$_forumName · 精选';

    final rawDataStyle = widget.item.customParams['dataStyle'] as String? ?? 'auto';
    final String dataStyle;
    if (rawDataStyle == 'auto') {
      if (widget.item.rowSpan <= 1) {
        dataStyle = 'minimal';
      } else if (widget.item.rowSpan == 2) {
        dataStyle = 'compact';
      } else {
        dataStyle = widget.item.colSpan >= 4 ? 'magazine' : 'compact';
      }
    } else {
      dataStyle = rawDataStyle;
    }

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部
            Row(
              children: [
                Icon(Icons.dynamic_feed_rounded, size: 17, color: accentColor),
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
                InkWell(
                  onTap: _openForum,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      '进版块 >',
                      style: TextStyle(
                        fontSize: 11,
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 数据内容展示
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _loading
                    ? Center(
                        key: const ValueKey('loading'),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                        ),
                      )
                    : KeyedSubtree(
                        key: ValueKey('content-$dataStyle-${_threads.length}'),
                        child: _buildDataContent(context, dataStyle, _threads, accentColor),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataContent(
    BuildContext context,
    String dataStyle,
    List<ThreadSummary> list,
    Color accentColor,
  ) {
    switch (dataStyle) {
      case 'magazine':
        return _buildMagazineStyle(context, list, accentColor);
      case 'minimal':
        return _buildMinimalStyle(context, list, accentColor);
      case 'leaderboard':
        return _buildLeaderboardStyle(context, list, accentColor);
      case 'compact':
      default:
        return _buildCompactStyle(context, list, accentColor);
    }
  }

  /// 1. 紧凑图文行数据样式（左侧文字摘要 + 右侧缩略图）
  Widget _buildCompactStyle(BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = widget.item.rowSpan <= 1 ? 1 : (widget.item.rowSpan == 2 ? 2 : (widget.item.rowSpan == 3 ? 3 : 5));
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
            onTap: () => _openThread(t.tid, t.title),
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
                              '💬 ${t.replies} 评',
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

  /// 2. 焦点画报大图数据样式
  Widget _buildMagazineStyle(BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    if (list.isEmpty) return const SizedBox.shrink();
    final first = list.first;
    final subList = list.skip(1).take(widget.item.rowSpan >= 3 ? 2 : 1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 焦点头图
        Expanded(
          flex: 5,
          child: PressScaleEffect(
            scaleDown: 0.985,
            child: InkWell(
              onTap: () => _openThread(first.tid, first.title),
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
                                  '💬 ${first.replies} 评',
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
                    onTap: () => _openThread(t.tid, t.title),
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

  /// 3. 极简文字流数据样式
  Widget _buildMinimalStyle(BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = widget.item.rowSpan <= 1 ? 1 : (widget.item.rowSpan == 2 ? 4 : (widget.item.rowSpan == 3 ? 5 : 7));
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
            onTap: () => _openThread(t.tid, t.title),
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
                    '${t.replies}评',
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

  /// 4. 序号榜单数据样式
  Widget _buildLeaderboardStyle(BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = widget.item.rowSpan <= 1 ? 1 : (widget.item.rowSpan == 2 ? 3 : (widget.item.rowSpan == 3 ? 4 : 6));
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
            onTap: () => _openThread(t.tid, t.title),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: idx < 3 ? accentColor.withAlpha(idx == 0 ? 220 : (idx == 1 ? 170 : 120)) : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${idx + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: idx < 3 ? Colors.white : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
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
                            Text(t.author, style: TextStyle(fontSize: 10, color: colorScheme.outline)),
                            const Spacer(),
                            Text('${t.replies}评 · ${t.views}阅', style: TextStyle(fontSize: 9.5, color: colorScheme.outline.withAlpha(180))),
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
}
