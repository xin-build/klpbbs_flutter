import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../models/thread_summary.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_nav.dart';
import '../widgets/pagination_control.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/thread_card.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('导读'),
        centerTitle: true,
        actions: const [GlobalNavButton()],
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: FutureBuilder<List<ThreadSummary>>(
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
          ),
        ),
      ),
    );
  }
}
