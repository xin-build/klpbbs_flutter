import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/preload_service.dart';
import '../widgets/guide_content.dart';
import '../widgets/smooth_scroll_controller.dart';
import '../models/thread_summary.dart';
import '../widgets/dashboard_cards/dashboard_card_factory.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/app_motion.dart';
import '../widgets/visual_grid_canvas.dart';
import 'search_page.dart';
import 'thread_detail_page.dart';
import 'user_space_page.dart';
import 'login_page.dart';

/// 网站当前导读分类（forum.php?mod=guide）。
class GuidePage extends StatefulWidget {
  final String initialView;
  const GuidePage({super.key, this.initialView = 'hot'});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage>
    with SingleTickerProviderStateMixin {
  static const _views = guideViews;

  late final TabController _tabController;
  late Future<List<ThreadSummary>> _future;
  final Map<String, List<ThreadSummary>> _tabCache = {};
  final Map<String, int> _viewPages = {};
  final Map<String, double> _offsets = {};
  final Map<String, Object> _errors = {};
  final Map<String, int> _requests = {};
  final Set<String> _pending = {};
  final Map<String, Future<List<ThreadSummary>>> _loads = {};
  final Map<String, int> _displayPages = {};
  final Map<String, int> _failedPages = {};
  final _searchController = TextEditingController();
  final SmoothScrollController _scroll = SmoothScrollController();
  String _view = 'hot';
  int _page = 1;
  bool _showWorkbench = true;
  String get _selection => '${_view}_$_page';

  @override
  void initState() {
    super.initState();
    final index = _views.indexWhere((view) => view.$1 == widget.initialView);
    _view = index < 0 ? 'hot' : widget.initialView;
    _tabController = TabController(
        length: _views.length, initialIndex: index < 0 ? 0 : index, vsync: this)
      ..addListener(_onTabChanged);
    _fetch();
    DioClient.sessionChanges.addListener(_onAccountChanged);
  }

  void _onAccountChanged() {
    _tabCache.clear();
    _viewPages.clear();
    _offsets.clear();
    _errors.clear();
    _requests.clear();
    _pending.clear();
    _loads.clear();
    _displayPages.clear();
    _failedPages.clear();
    _page = 1;
    if (mounted) {
      setState(() {
        _fetch(forceRefresh: true);
      });
    }
  }

  void _fetch({bool forceRefresh = false}) {
    if (_view == 'follow' && !DioClient.isLoggedIn) {
      _future = Future.value(const []);
      return;
    }
    final session = DioClient.sessionKey;
    final requestedView = _view;
    final requestedPage = _page;
    final cacheKey = '${requestedView}_$requestedPage';
    if (!forceRefresh && _tabCache.containsKey(cacheKey)) {
      _future = Future.value(_tabCache[cacheKey]);
      PreloadService.instance.set('guide_preview_selection',
          (view: requestedView, page: requestedPage));
      return;
    }
    final pending = _loads[cacheKey];
    if (pending != null) {
      _future = pending;
      return;
    }
    final request = (_requests[cacheKey] ?? 0) + 1;
    final hadContent = _tabCache.containsKey(cacheKey);
    _requests[cacheKey] = request;
    _pending.add(cacheKey);
    _errors.remove(cacheKey);
    _future = KlpbbsApi.getGuide(requestedView,
            page: requestedPage, forceRefresh: forceRefresh)
        .then((list) {
      if (mounted &&
          session == DioClient.sessionKey &&
          _requests[cacheKey] == request) {
        _tabCache[cacheKey] = list;
        _displayPages[requestedView] = requestedPage;
        if (_failedPages[requestedView] == requestedPage) {
          _failedPages.remove(requestedView);
        }
        if (_tabCache.length > 24) {
          final oldest = _tabCache.keys.first;
          _tabCache.remove(oldest);
          _errors.remove(oldest);
        }
        _pending.remove(cacheKey);
        _loads.remove(cacheKey);
        _errors.remove(cacheKey);
        if (mounted && _view == requestedView && _page == requestedPage) {
          PreloadService.instance.set('guide_preview_selection',
              (view: requestedView, page: requestedPage));
          setState(() {});
          if (!hadContent) _restorePosition();
        }
      }
      return list;
    }, onError: (Object error, StackTrace stack) {
      if (mounted &&
          session == DioClient.sessionKey &&
          _requests[cacheKey] == request) {
        _pending.remove(cacheKey);
        _loads.remove(cacheKey);
        _errors[cacheKey] = error;
        if (_selection == cacheKey) {
          final priorPage = _displayPages[requestedView];
          if (!_tabCache.containsKey(cacheKey) && priorPage != null) {
            _page = priorPage;
            _viewPages[requestedView] = priorPage;
            _failedPages[requestedView] = requestedPage;
            _errors[_selection] = error;
          }
          setState(() {});
          _restorePosition();
        }
      }
      Error.throwWithStackTrace(error, stack);
    });
    // A failed or superseded request must remain observed even off-screen.
    // The selected snapshot and its error banner own rendering independently.
    _future.ignore();
    _loads[cacheKey] = _future;
  }

  void _onTabChanged() {
    final view = _views[_tabController.index].$1;
    if (view != _view) {
      _rememberPosition();
      setState(() {
        _view = view;
        _page = _viewPages[view] ?? 1;
        _fetch();
      });
      _restorePosition();
    }
  }

  void _reload({bool forceRefresh = true}) {
    _failedPages.remove(_view);
    setState(() {
      _fetch(forceRefresh: forceRefresh);
    });
  }

  void _retry() {
    final page = _failedPages[_view];
    if (page != null) {
      setState(() {
        _page = page;
        _fetch(forceRefresh: true);
      });
    } else {
      _reload();
    }
  }

  void _openSearch() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          SearchPage(initialKeyword: _searchController.text.trim())));

  void _openCanvas() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VisualGridCanvas(
          pageCategory: 'guide',
          initialLayout: AppConfig.guideDashboardLayout,
          onSave: (_) {
            if (mounted) setState(() {});
          },
          onExit: () => Navigator.of(context).pop())));

  void _goPage(int p) {
    if (p < 1 || p == _page) return;
    _rememberPosition();
    setState(() {
      _page = p;
      _fetch();
    });
    _restorePosition();
  }

  void _rememberPosition() {
    _viewPages[_view] = _page;
    if (_scroll.hasClients) _offsets[_selection] = _scroll.offset;
  }

  void _restorePosition() {
    final selected = _selection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selection != selected || !_scroll.hasClients) return;
      _scroll.jumpTo((_offsets[selected] ?? 0)
          .clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_onAccountChanged);
    _scroll.dispose();
    _searchController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      appBar: GuidePageHeader(
        controller: _tabController,
        tabHeight: GuideCategoryTabs.heightFor(context),
        toolbarHeight: GuidePageHeader.toolbarHeightFor(context),
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        searchController: _searchController,
        onSearch: _openSearch,
        onRefresh: _reload,
        onCustomize: _openCanvas,
        workbenchExpanded: _showWorkbench,
        loading: _pending.contains(_selection),
        onToggleWorkbench: GuideLayout.canShowWorkbench(
                context, MediaQuery.sizeOf(context).width)
            ? () => setState(() => _showWorkbench = !_showWorkbench)
            : null,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWorkbenchViable =
              GuideLayout.canShowWorkbench(context, constraints.maxWidth);
          final feedContent = Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: GuideLayout.contentMaxWidth),
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
              GuideWorkbenchRegion(
                  key: const ValueKey('guide-workbench-region'),
                  expanded: _showWorkbench,
                  workbenchBuilder: _buildWorkbench,
                  onExpand: () => setState(() => _showWorkbench = true)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWorkbench(BuildContext context) => ListenableBuilder(
      listenable: AppConfig.instance,
      builder: (context, _) => GuideWorkbench(
          items: AppConfig.guideDashboardLayout,
          onSettings: _openCanvas,
          onCollapse: () => setState(() => _showWorkbench = false),
          cardBuilder: (context, item) => DashboardCardFactory.buildCard(
              item: item,
              isPreview: false,
              threads: _tabCache[_selection] ??
                  _tabCache['${_view}_${_displayPages[_view]}'])));

  Widget _buildFeed(BuildContext context) {
    if (_view == 'follow' && !DioClient.isLoggedIn) {
      return GuideContent(
          threads: const [],
          page: _page,
          hasMore: false,
          loginRequired: true,
          onLogin: () async {
            await Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LoginPage()));
            if (mounted) _reload();
          });
    }
    final requestedData = _tabCache[_selection];
    final priorPage = _displayPages[_view];
    final data = requestedData ??
        (priorPage == null ? null : _tabCache['${_view}_$priorPage']);
    final displayPage = requestedData != null ? _page : priorPage ?? _page;
    final loading = _pending.contains(_selection);
    final error = _errors[_selection];
    if (data == null) {
      if (loading) {
        return const SkeletonList(itemCount: 6);
      }
      if (error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('加载失败：$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _retry, child: const Text('重试')),
            ],
          ),
        );
      }
    }
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Expanded(
                child: Text(
                    '${_views.firstWhere((view) => view.$1 == _view).$2} · 第 $displayPage 页',
                    style: Theme.of(context).textTheme.titleSmall)),
            Text(
                loading && requestedData == null
                    ? '正在读取第 $_page 页'
                    : '${data?.length ?? 0} 条已加载',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
      if (loading)
        const AppLoadingBar(
            key: ValueKey('guide-refresh-progress'), minHeight: 2),
      if (error != null)
        MaterialBanner(
            key: const ValueKey('guide-refresh-error'),
            content: Text(_failedPages[_view] == null
                ? '刷新失败，已保留此分类的内容。'
                : '第 ${_failedPages[_view]} 页未能读取，已保留第 $displayPage 页。'),
            actions: [TextButton(onPressed: _retry, child: const Text('重试'))]),
      Expanded(
          child: GuideContent(
        key: ValueKey('guide-feed-${_view}_$displayPage'),
        threads: data ?? const [],
        page: displayPage,
        hasMore: KlpbbsApi.guideHasNextPage(_view, displayPage) == true,
        controller: _scroll,
        onPageChanged: loading ? null : _goPage,
        onOpenThread: (thread) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ThreadDetailPage(tid: thread.tid))),
        onOpenAuthor: (uid) => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => UserSpacePage(uid: uid))),
        onRefresh: () async {
          _reload(forceRefresh: true);
          try {
            await _future;
          } catch (_) {
            // FutureBuilder presents the error and its retry action.
          }
        },
      )),
    ]);
  }
}
