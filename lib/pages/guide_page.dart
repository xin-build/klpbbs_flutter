import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../models/thread_summary.dart';
import '../widgets/dashboard_cards/dashboard_card_factory.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/pagination_control.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/thread_card.dart';
import 'settings_page.dart';
import 'thread_detail_page.dart';
import 'user_space_page.dart';

/// 导读页：热门 / 最新 / 新帖 / 精华 / 图集（forum.php?mod=guide）
class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage>
    with SingleTickerProviderStateMixin {
  static const _views = [
    ('hot', '热门'),
    ('new', '最新'),
    ('newthread', '新帖'),
    ('digest', '精华'),
    ('pic', '图集'),
  ];

  late final TabController _tabController;
  late Future<List<ThreadSummary>> _future;
  final Map<String, List<ThreadSummary>> _tabCache = {};
  String _view = 'hot';
  int _page = 1;
  bool _showWorkbench = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _views.length, vsync: this)
      ..addListener(_onTabChanged);
    _fetch();
  }

  void _fetch({bool forceRefresh = false}) {
    final cacheKey = '${_view}_$_page';
    if (!forceRefresh && _tabCache.containsKey(cacheKey)) {
      _future = Future.value(_tabCache[cacheKey]);
      return;
    }
    _future = KlpbbsApi.getGuide(_view, page: _page, forceRefresh: forceRefresh).then((list) {
      if (list.isNotEmpty) {
        _tabCache[cacheKey] = list;
      }
      return list;
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final view = _views[_tabController.index].$1;
    if (view != _view) {
      setState(() {
        _view = view;
        _page = 1;
        _fetch();
      });
    }
  }

  void _reload({bool forceRefresh = true}) {
    setState(() => _fetch(forceRefresh: forceRefresh));
  }

  void _goPage(int p) {
    if (p < 1) return;
    setState(() {
      _page = p;
      _fetch();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('导读'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          indicatorColor: theme.colorScheme.primary,
          tabs: [for (final (_, label) in _views) Tab(text: label)],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWorkbenchViable = constraints.maxWidth >= 720;
          final feedContent = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: _buildFeed(context),
            ),
          );

          if (!isWorkbenchViable) {
            return feedContent;
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: feedContent),
              if (_showWorkbench)
                _buildWorkbench(context)
              else
                _buildCollapsedEdgeHandle(colorScheme),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCollapsedEdgeHandle(ColorScheme colorScheme) {
    return Center(
      child: Tooltip(
        message: '展开右侧边栏 (导读工作台)',
        child: InkWell(
          onTap: () {
            setState(() => _showWorkbench = true);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 18,
            height: 60,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(160),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant.withAlpha(60), width: 0.8),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Icon(
              Icons.chevron_left_rounded,
              size: 16,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkbench(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(35),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withAlpha(30),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.explore_outlined,
                  size: 15,
                  color: colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  '导读 · 工作台',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.outline,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  tooltip: '工作台排版与设置',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsPage(initialCategory: SettingsCategory.layout),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.last_page_rounded, size: 16),
                  tooltip: '收起工作台',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () {
                    setState(() => _showWorkbench = false);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: AppConfig.instance,
              builder: (ctx, _) {
                final items = AppConfig.guideDashboardLayout;
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      '暂无工作台卡片\n可在设置中添加',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, index) {
                    final item = items[index];
                    final cardHeight = (item.rowSpan * 88.0 + (item.rowSpan - 1) * 8.0).clamp(86.0, 420.0);
                    final guideThreads = _tabCache['${_view}_$_page'] ?? _tabCache['hot_1'];
                    return SizedBox(
                      height: cardHeight,
                      child: DashboardCardFactory.buildCard(
                        item: item,
                        isPreview: false,
                        threads: guideThreads,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeed(BuildContext context) {
    return FutureBuilder<List<ThreadSummary>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SkeletonList(itemCount: 6);
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载失败：${snap.error}', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _reload, child: const Text('重试')),
              ],
            ),
          );
        }
        final threads = snap.data ?? [];
        if (threads.isEmpty) {
          return const EmptyView(
            icon: Icons.article_outlined,
            title: '暂无导读内容',
            subtitle: '切换其他分类或稍后重试',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(forceRefresh: true),
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: threads.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == threads.length) {
                return PaginationControl(
                  page: _page,
                  hasMore: threads.length >= 10,
                  onPageChanged: _goPage,
                );
              }
              final t = threads[i];
              return ThreadCard(
                thread: t,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ThreadDetailPage(tid: t.tid),
                  ),
                ),
                onAuthorTap: t.uid == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UserSpacePage(uid: t.uid!),
                        ),
                      ),
              );
            },
          ),
        );
      },
    );
  }
}
