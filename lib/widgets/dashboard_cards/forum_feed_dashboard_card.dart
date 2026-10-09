import '../app_motion.dart';
import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../core/preload_service.dart';
import '../../core/dio_client.dart';
import '../../models/forum.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/thread_summary.dart';
import '../../pages/thread_detail_page.dart';
import '../../pages/thread_list_page.dart';
import '../retry_image.dart';
import '../interactive_animations.dart';
import 'dashboard_card_frame.dart';

/// 指定版块帖子流卡片（可自定义关联版块）。
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
  bool _known = false;
  String? _error;
  late int _targetFid;
  late String _forumName;

  @override
  void initState() {
    super.initState();
    final forums = PreloadService.instance
            .get<List<ForumGroup>>('forum_groups', ignoreExpired: true)
            ?.expand((group) => group.forums)
            .toList() ??
        const <Forum>[];
    _targetFid = (widget.item.customParams['targetFid'] as num?)?.toInt() ??
        forums.firstOrNull?.fid ??
        0;
    _forumName =
        forums.where((forum) => forum.fid == _targetFid).firstOrNull?.name ??
            '版块帖子';

    final cached = PreloadService.instance.get<List<ThreadSummary>>(
        'thread_list_${_targetFid}_null_null_1',
        ignoreExpired: true);
    _threads = cached ?? [];
    _known = cached != null;
    _loading = !widget.isPreview && !_known;
    if (widget.isPreview) {
      if (!_known) {
        _error = _targetFid <= 0 ? '请在卡片设置中选择版块' : '尚未载入此版块数据';
      }
      _loading = false;
    } else {
      _loadForumThreads();
    }
  }

  Future<void> _loadForumThreads() async {
    final session = DioClient.sessionKey;
    if (_targetFid <= 0) {
      _loading = false;
      _error = '请在卡片设置中选择版块';
      return;
    }
    try {
      final list = await KlpbbsApi.getThreadList(_targetFid, page: 1);
      if (mounted && session == DioClient.sessionKey) {
        setState(() {
          _threads = list;
          _known = true;
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && session == DioClient.sessionKey) {
        setState(() {
          _loading = false;
          _error = '暂未取得版块内容';
        });
      }
    }
  }

  void _openForum() {
    if (_targetFid <= 0) return;
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
          content: Text('预览模式：查看帖子「$title」'),
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
    final title = (customTitle != null && customTitle.isNotEmpty)
        ? customTitle
        : _forumName;

    final rawDataStyle =
        widget.item.customParams['dataStyle'] as String? ?? 'auto';
    String dataStyle;
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
    if (dataStyle == 'magazine' &&
        (_threads.firstOrNull?.coverUrl?.isNotEmpty != true)) {
      dataStyle = 'compact';
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                          child: AppLoadingIndicator(
                              strokeWidth: 2, color: accentColor),
                        ),
                      )
                    : KeyedSubtree(
                        key: ValueKey('content-$dataStyle-${_threads.length}'),
                        child: _buildDataContent(
                            context, dataStyle, _threads, accentColor),
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
    if (list.isEmpty) {
      return Center(
          child: Text(_error ?? (_known ? '暂无帖子' : '尚未载入此版块数据'),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12)));
    }
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
  Widget _buildCompactStyle(
      BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = widget.item.rowSpan <= 1
        ? 1
        : (widget.item.rowSpan == 2 ? 2 : (widget.item.rowSpan == 3 ? 3 : 5));
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
                                '💬 ${t.replies} 评',
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

  /// 2. 焦点画报大图数据样式
  Widget _buildMagazineStyle(
      BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    if (list.isEmpty) return const SizedBox.shrink();
    final first = list.first;
    final subList =
        list.skip(1).take(widget.item.rowSpan >= 3 ? 2 : 1).toList();

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
                                if (first.replies >= 0)
                                  Text(
                                    '💬 ${first.replies} 评',
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
                    onTap: () => _openThread(t.tid, t.title),
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

  /// 3. 极简文字流数据样式
  Widget _buildMinimalStyle(
      BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = widget.item.rowSpan <= 1
        ? 1
        : (widget.item.rowSpan == 2 ? 4 : (widget.item.rowSpan == 3 ? 5 : 7));
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
                  if (t.replies >= 0)
                    Text(
                      '${t.replies}评',
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

  /// 4. 序号榜单数据样式
  Widget _buildLeaderboardStyle(
      BuildContext context, List<ThreadSummary> list, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final takeCount = widget.item.rowSpan <= 1
        ? 1
        : (widget.item.rowSpan == 2 ? 3 : (widget.item.rowSpan == 3 ? 4 : 6));
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
                      color: idx < 3
                          ? accentColor.withAlpha(
                              idx == 0 ? 220 : (idx == 1 ? 170 : 120))
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${idx + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: idx < 3
                            ? Colors.white
                            : colorScheme.onSurfaceVariant,
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
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                                child: Text(t.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: colorScheme.outline))),
                            const SizedBox(width: 6),
                            if (t.replies >= 0 || t.views >= 0)
                              Text(
                                  [
                                    if (t.replies >= 0) '${t.replies}评',
                                    if (t.views >= 0) '${t.views}阅',
                                  ].join(' · '),
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      color:
                                          colorScheme.outline.withAlpha(180))),
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
