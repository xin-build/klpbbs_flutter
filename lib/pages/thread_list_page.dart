import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/forum_events.dart';
import '../core/preload_service.dart';
import '../models/forum.dart';
import '../models/forum_header_info.dart';
import '../models/server_outage_info.dart';
import '../models/thread_summary.dart';
import '../widgets/server_outage_view.dart';
import '../widgets/desktop_shortcuts.dart';
import '../widgets/empty_view.dart';
import '../widgets/forum_header_widget.dart';
import '../widgets/bili_video_player.dart';
import '../widgets/general_audio_player.dart';
import '../widgets/general_video_player.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/netease_music_player.dart';
import '../widgets/pagination_control.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/thread_card.dart';
import '../widgets/interactive_animations.dart';
import 'post_page.dart';
import 'search_page.dart';
import 'thread_detail_page.dart';
import 'user_space_page.dart';

/// 版块帖子列表（深度复刻 Discuz 原版版块布局：图三与图四）
class ThreadListPage extends StatefulWidget {
  final int fid;
  final String title;
  final bool isSidebar;
  final int? activeTid;
  final ValueChanged<int>? onThreadSelected;
  final VoidCallback? onCloseSidebar;

  const ThreadListPage({
    super.key,
    required this.fid,
    required this.title,
    this.isSidebar = false,
    this.activeTid,
    this.onThreadSelected,
    this.onCloseSidebar,
  });

  @override
  State<ThreadListPage> createState() => _ThreadListPageState();
}

class _ThreadListPageState extends State<ThreadListPage> {
  ForumHeaderInfo? _headerInfo;
  List<ThreadSummary> _stickyThreads = [];
  List<ThreadSummary> _normalThreads = [];
  bool _isInitialLoading = true;
  bool _isPageLoading = false;
  Object? _loadError;
  ServerOutageInfo? _activeOutage;
  bool _viewCacheAnyway = false;

  int _page = 1;
  int? _loadingTargetPage;
  List<({int typeid, String name})> _types = const [];
  int? _selectedType;
  String? _orderby;
  int? _selectedTid;
  bool _isFav = false;

  List<Forum> _subForums = [];
  bool _stickyCollapsed = false;
  bool _subforumsCollapsed = false;
  bool _isForumCollapsed = false;

  void _toggleMasterCollapse() {
    setState(() {
      _isForumCollapsed = !_isForumCollapsed;
    });
  }

  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  void _onThreadListScroll() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 280;
    if (show != _showBackToTop) {
      setState(() => _showBackToTop = show);
    }
  }

  void _scrollToTop() {
    HapticFeedback.lightImpact();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onThreadListScroll);
    if (widget.activeTid != null) {
      _selectedTid = widget.activeTid;
    }
    ForumFavoriteNotifier.instance.addListener(_onFavEvent);
    _loadFavStatus();
    _loadCollapsePreferences();
    _fetchData(page: 1, isInitial: true);
    _loadTypes();
    _loadSubForums();
  }

  Future<void> _loadCollapsePreferences() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _stickyCollapsed = sp.getBool('fid_${widget.fid}_sticky_collapsed') ?? false;
          _subforumsCollapsed = sp.getBool('fid_${widget.fid}_subforums_collapsed') ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleStickyCollapse() async {
    setState(() => _stickyCollapsed = !_stickyCollapsed);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('fid_${widget.fid}_sticky_collapsed', _stickyCollapsed);
    } catch (_) {}
  }

  Future<void> _toggleSubforumsCollapse() async {
    setState(() => _subforumsCollapsed = !_subforumsCollapsed);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('fid_${widget.fid}_subforums_collapsed', _subforumsCollapsed);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant ThreadListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeTid != oldWidget.activeTid && widget.activeTid != null) {
      setState(() => _selectedTid = widget.activeTid);
    }
    if (widget.fid != oldWidget.fid) {
      _fetchData(page: 1, isInitial: true, forceRefresh: true);
    }
  }

  @override
  void dispose() {
    // 退出版块列表页时，停止所有内嵌媒体播放器
    BiliVideoPlayer.stopAll();
    NetEaseMusicPlayer.stopAll();
    GeneralAudioPlayer.stopAll();
    GeneralVideoPlayer.stopAll();
    _scrollController.dispose();
    ForumFavoriteNotifier.instance.removeListener(_onFavEvent);
    super.dispose();
  }

  void _onFavEvent() {
    if (!mounted) return;
    final lastFid = ForumFavoriteNotifier.instance.lastChangedFid;
    if (lastFid == widget.fid) {
      final isFav = ForumFavoriteNotifier.instance.lastIsFav ?? false;
      if (_isFav != isFav) {
        setState(() => _isFav = isFav);
      }
    }
  }

  Future<void> _loadFavStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('fav_forums') ?? [];
      final isFav = list.contains('${widget.fid}');
      if (mounted) setState(() => _isFav = isFav);
    } catch (_) {}
  }

  Future<void> _toggleFav() async {
    final nextFav = !_isFav;
    setState(() => _isFav = nextFav);

    try {
      final prefs = await SharedPreferences.getInstance();
      final set = (prefs.getStringList('fav_forums') ?? []).toSet();
      if (nextFav) {
        set.add('${widget.fid}');
      } else {
        set.remove('${widget.fid}');
      }
      await prefs.setStringList('fav_forums', set.toList());

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextFav ? '已收藏版块「${widget.title}」' : '已取消收藏「${widget.title}」'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      if (nextFav) {
        await KlpbbsApi.favoriteForum(widget.fid);
      } else {
        await KlpbbsApi.unfavoriteForum(widget.fid);
      }
    } catch (_) {}
  }

  Future<void> _fetchData({
    int page = 1,
    bool forceRefresh = false,
    bool isInitial = false,
  }) async {
    final cacheKey = 'forum_bundle_${widget.fid}_${page}_${_selectedType ?? 0}_${_orderby ?? ""}';
    final cached = PreloadService.instance.get<
      ({
        List<ThreadSummary> threads,
        ForumHeaderInfo header,
        List<({int typeid, String name})> types,
        List<Forum> subForums,
      })
    >(cacheKey);

    if (isInitial && cached != null && !forceRefresh) {
      if (mounted) {
        setState(() {
          _headerInfo = cached.header;
          if (cached.types.isNotEmpty) _types = cached.types;
          if (cached.subForums.isNotEmpty) _subForums = cached.subForums;
          _stickyThreads = cached.threads.where((t) => t.isSticky).toList();
          _normalThreads = cached.threads.where((t) => !t.isSticky).toList();
          _isInitialLoading = false;
          _isPageLoading = false;
          _page = page;
          if (_selectedTid == null && cached.threads.isNotEmpty) {
            _selectedTid = cached.threads.first.tid;
          }
        });
      }
      unawaited(_fetchData(page: page, forceRefresh: true));
      return;
    }

    if (mounted) {
      setState(() {
        if (_headerInfo == null && isInitial) {
          _isInitialLoading = true;
        } else {
          _isPageLoading = true;
          _loadingTargetPage = page;
        }
        _loadError = null;
        _activeOutage = null;
      });
    }

    try {
      final bundle = await KlpbbsApi.getForumBundle(
        widget.fid,
        page: page,
        typeid: _selectedType,
        orderby: _orderby,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      setState(() {
        _headerInfo = bundle.header;
        if (bundle.types.isNotEmpty) _types = bundle.types;
        if (bundle.subForums.isNotEmpty) _subForums = bundle.subForums;
        _stickyThreads = bundle.threads.where((t) => t.isSticky).toList();
        _normalThreads = bundle.threads.where((t) => !t.isSticky).toList();
        _page = page;
        _loadingTargetPage = null;
        _isInitialLoading = false;
        _isPageLoading = false;
        _loadError = null;
        _activeOutage = null;
        if (_selectedTid == null && bundle.threads.isNotEmpty) {
          _selectedTid = bundle.threads.first.tid;
        }
        if (bundle.header.isFavorited && !_isFav) {
          _isFav = true;
          SharedPreferences.getInstance().then((prefs) {
            final list = (prefs.getStringList('fav_forums') ?? []).toSet();
            if (list.add('${widget.fid}')) {
              prefs.setStringList('fav_forums', list.toList());
            }
          }).catchError((_) {});
        }
      });
      if (_scrollController.hasClients && _scrollController.offset > 280) {
        _scrollController.animateTo(
          280,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (!mounted) return;
      final outage = ServerOutageInfo.tryParse(e);
      setState(() {
        _loadingTargetPage = null;
        _isInitialLoading = false;
        _isPageLoading = false;
        _loadError = e;
        _activeOutage = outage;
        if (outage == null && _headerInfo != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加载失败：$e')),
          );
        }
      });
    }
  }

  Future<void> _loadSubForums() async {
    try {
      final list = await KlpbbsApi.getSubForums(widget.fid);
      if (mounted) setState(() => _subForums = list);
    } catch (_) {}
  }

  Future<void> _loadTypes() async {
    try {
      final list = await KlpbbsApi.getThreadTypes(widget.fid);
      if (mounted) setState(() => _types = list);
    } catch (_) {}
  }

  void _reload() {
    setState(() {
      _viewCacheAnyway = false;
      _activeOutage = null;
    });
    _fetchData(page: _page, forceRefresh: true);
  }

  Future<void> _openPostPage() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PostPage(fid: widget.fid),
      ),
    );
    if (posted == true) _reload();
  }

  void _goPage(int page) {
    if (page == _page && !_isPageLoading) return;
    setState(() {
      _viewCacheAnyway = false;
      _activeOutage = null;
    });
    _fetchData(page: page);
  }

  void _openThread(int tid) {
    if (widget.onThreadSelected != null) {
      setState(() => _selectedTid = tid);
      widget.onThreadSelected!(tid);
      return;
    }
    if (ResponsiveBreakpoints.isDesktop(context) &&
        AppConfig.isMasterDetailEnabled &&
        !widget.isSidebar) {
      if (_selectedTid != tid) {
        // 切换不同帖子时停止旧帖播放器
        BiliVideoPlayer.stopAll();
        NetEaseMusicPlayer.stopAll();
        GeneralAudioPlayer.stopAll();
        GeneralVideoPlayer.stopAll();
        setState(() => _selectedTid = tid);
      }
    } else {
      Navigator.of(
        context,
      ).push(
        MaterialPageRoute(
          builder: (_) => ThreadDetailPage(
            tid: tid,
            fid: widget.fid,
            canShowForumSidebar: false,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final isMasterDetail = !widget.isSidebar &&
        isDesktop &&
        AppConfig.isMasterDetailEnabled &&
        MediaQuery.sizeOf(context).width >= 768.0;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final header = _headerInfo ?? ForumHeaderInfo(fid: widget.fid, name: widget.title);

    // 首次加载且无缓存直出时展示骨架屏
    if (_isInitialLoading && _headerInfo == null) {
      return Scaffold(
        appBar: AppBar(
          leading: widget.isSidebar && widget.onCloseSidebar != null
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '收起版块列表',
                  onPressed: widget.onCloseSidebar,
                )
              : (Navigator.of(context).canPop()
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null),
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        body: ForumThreadListSkeleton(isSidebar: widget.isSidebar),
      );
    }

    // 当遇到 502/服务端故障且用户未选择“强制浏览离线缓存”时，坚决优先全屏展示 502 诊断页（无论之前是否有缓存直出）
    if (_activeOutage != null && !_viewCacheAnyway) {
      final hasCache = _headerInfo != null ||
          PreloadService.instance.has(
            'forum_bundle_${widget.fid}_${_page}_${_selectedType ?? 0}_${_orderby ?? ""}',
          );
      return Scaffold(
        appBar: AppBar(
          leading: widget.isSidebar && widget.onCloseSidebar != null
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '收起版块列表',
                  onPressed: widget.onCloseSidebar,
                )
              : (Navigator.of(context).canPop()
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null),
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新重试',
              onPressed: () {
                setState(() => _viewCacheAnyway = false);
                _reload();
              },
            ),
          ],
        ),
        body: ServerOutageView(
          outage: _activeOutage!,
          isCompact: widget.isSidebar,
          onRetry: () {
            setState(() => _viewCacheAnyway = false);
            _reload();
          },
          onViewCache: hasCache
              ? () {
                  setState(() => _viewCacheAnyway = true);
                }
              : null,
          onGoHome: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
        ),
      );
    }

    // 首次加载常规错误且无数据展示通用错误页
    if (_loadError != null && _headerInfo == null) {
      return Scaffold(
        appBar: AppBar(
          leading: Navigator.of(context).canPop()
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  '版块内容加载失败',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_loadError',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final List<Widget> slivers = [];
    if (_activeOutage != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: ServerOutageBanner(
            outage: _activeOutage!,
            onRetry: () {
              setState(() => _viewCacheAnyway = false);
              _reload();
            },
            onViewDetails: () {
              setState(() => _viewCacheAnyway = false);
            },
            onDismiss: () => setState(() => _activeOutage = null),
          ),
        ),
      );
    }
    final activeModules = AppConfig.forumModules;

    for (final mod in activeModules) {
      switch (mod) {
        case 'forum_header':
          slivers.add(
            SliverToBoxAdapter(
              child: ForumHeaderWidget(
                headerInfo: header,
                onPost: _openPostPage,
              ),
            ),
          );
          break;
        case 'type_filter':
          slivers.add(
            SliverToBoxAdapter(
              child: _buildCategoryTabBar(theme),
            ),
          );
          slivers.add(
            SliverToBoxAdapter(
              child: _buildOrderChips(theme),
            ),
          );
          break;
        case 'sub_forums':
          slivers.add(
            SliverToBoxAdapter(
              child: _buildSubforumSection(theme),
            ),
          );
          break;
        case 'sticky_threads':
          if (_stickyThreads.isNotEmpty) {
            slivers.add(
              SliverToBoxAdapter(
                child: _buildStickySection(_stickyThreads, theme),
              ),
            );
          }
          break;
        case 'thread_feed':
          // 帖子信息流在后续统一追加渲染
          break;
      }
    }

    if (_isPageLoading) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(80),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '正在加载第 ${_loadingTargetPage ?? _page} 页...',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const SkeletonList(itemCount: 3, withThumbnail: false, isGrid: false),
              ],
            ),
          ),
        ),
      );
    } else if (_normalThreads.isEmpty && _stickyThreads.isEmpty) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: EmptyView(
              icon: Icons.inbox_outlined,
              title: '本版块暂无更多帖子',
              subtitle: '点击右下角按钮抢先发布！',
            ),
          ),
        ),
      );
    } else {
      slivers.add(
        SliverList.builder(
          itemCount: _normalThreads.length,
          itemBuilder: (context, index) {
            final t = _normalThreads[index];
            return Container(
              margin: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: ((_selectedTid == t.tid || widget.activeTid == t.tid) &&
                        (isDesktop || widget.isSidebar))
                    ? Border.all(
                        color: colorScheme.primary,
                        width: 1.8,
                      )
                    : null,
              ),
              child: ThreadCard(
                thread: t,
                onTap: () => _openThread(t.tid),
                onAuthorTap: t.uid == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UserSpacePage(uid: t.uid!),
                          ),
                        ),
              ),
            );
          },
        ),
      );
    }

    // 6. 分页导航
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 80),
          child: _buildPagination(theme),
        ),
      ),
    );

    final listView = RepaintBoundary(
      child: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: CustomScrollView(
          controller: _scrollController,
          key: PageStorageKey('thread_list_${widget.fid}_${_selectedType ?? 0}'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: slivers,
        ),
      ),
    );

    if (isMasterDetail) {
      return DesktopShortcutsWrapper(
        onRefresh: _reload,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧：帖子列表栏（支持鼠标拖拽自由调节宽度，无级缩放与快速折叠）
            if (!_isForumCollapsed) ...[
              ValueListenableBuilder<double>(
                valueListenable: AppConfig.threadForumSidebarWidthNotifier,
                builder: (context, sidebarWidth, listChild) {
                  return SizedBox(
                    width: sidebarWidth.clamp(260.0, 640.0),
                    child: listChild,
                  );
                },
                child: ScaffoldMessenger(
                  child: Scaffold(
                    appBar: AppBar(
                      leading: Navigator.of(context).canPop()
                          ? IconButton(
                              icon: const Icon(Icons.arrow_back),
                              tooltip: '返回',
                              onPressed: () => Navigator.of(context).maybePop(),
                            )
                          : null,
                      title: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      actions: [
                        BouncingIcon(
                          isTriggered: _isFav,
                          size: 22,
                          tooltip: _isFav ? '已收藏版块（点击取消）' : '收藏版块',
                          activeIcon: const Icon(Icons.star_rounded, size: 22, color: Color(0xFFFFB300)),
                          inactiveIcon: const Icon(Icons.star_border_rounded, size: 22),
                          onTap: _toggleFav,
                        ),
                        IconButton(
                          icon: const Icon(Icons.search, size: 20),
                          tooltip: '搜索',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SearchPage(),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: '刷新',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: _reload,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: '发帖',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: _openPostPage,
                        ),
                        IconButton(
                          icon: const Icon(Icons.first_page_rounded, size: 22),
                          tooltip: '收起版块列表',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: _toggleMasterCollapse,
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                    body: listView,
                  ),
                ),
              ),
              // 中间：可自由拖拽宽度手柄分界线（双击恢复默认 380px，支持折叠按钮）
              _buildMasterDetailSplitter(),
            ] else ...[
              // 已折叠时，在最左侧放置一个纤细优雅的展开把手
              _buildCollapsedMasterHandle(),
            ],
            // 右侧：帖子详情展示区（完全独立解耦，翻页时不闪烁骨架屏，RepaintBoundary 隔离，杜绝双排版块嵌套）
            Expanded(
              child: RepaintBoundary(
                child: ScaffoldMessenger(
                  child: _selectedTid == null
                      ? Scaffold(
                          appBar: AppBar(
                            leading: _isForumCollapsed
                                ? IconButton(
                                    icon: const Icon(Icons.view_sidebar_outlined),
                                    tooltip: '展开版块列表',
                                    onPressed: _toggleMasterCollapse,
                                  )
                                : null,
                            title: const Text('帖子详情'),
                          ),
                          body: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.article_outlined,
                                  size: 56,
                                  color: colorScheme.outlineVariant,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '选择左侧帖子查看详情',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ThreadDetailPage(
                          key: ValueKey(_selectedTid),
                          tid: _selectedTid!,
                          fid: widget.fid,
                          showBackButton: false,
                          stopPlayersOnDispose: false,
                          canShowForumSidebar: false,
                          onToggleForumSidebar: _toggleMasterCollapse,
                          isForumSidebarVisible: !_isForumCollapsed,
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return DesktopShortcutsWrapper(
      onRefresh: _reload,
      child: Scaffold(
        drawer: widget.isSidebar ? null : const GlobalAppDrawer(),
        drawerEdgeDragWidth: widget.isSidebar ? 0 : 50.0,
        appBar: AppBar(
          leading: widget.isSidebar && widget.onCloseSidebar != null
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '收起版块列表',
                  onPressed: widget.onCloseSidebar,
                )
              : const GlobalNavLeading(),
          leadingWidth: widget.isSidebar ? null : GlobalNavLeading.preferredLeadingWidth(context),
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            BouncingIcon(
              isTriggered: _isFav,
              size: 22,
              tooltip: _isFav ? '已收藏版块（点击取消）' : '收藏版块',
              activeIcon: const Icon(Icons.star_rounded, size: 22, color: Color(0xFFFFB300)),
              inactiveIcon: const Icon(Icons.star_border_rounded, size: 22),
              onTap: _toggleFav,
            ),
            if (widget.isSidebar)
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded),
                tooltip: '进入完整版块',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ThreadListPage(fid: widget.fid, title: widget.title),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: '搜索',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SearchPage(),
                    ),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: _reload,
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: listView,
          ),
        ),
        floatingActionButton: widget.isSidebar
            ? null
            : CoordinatedActionFabGroup(
                showBackToTop: _showBackToTop,
                onBackToTop: _scrollToTop,
                primaryIcon: Icons.edit_rounded,
                primaryLabel: '发帖',
                primaryTooltip: '在此版块发帖',
                onPrimaryAction: _openPostPage,
                heroTagPrefix: 'thread_list',
              ),
      ),
    );
  }

  /// 1. 紧凑分类 Tab 栏
  Widget _buildCategoryTabBar(ThemeData theme) {
    if (_types.isEmpty) return const SizedBox.shrink();
    final colorScheme = theme.colorScheme;

    return Container(
      height: 36,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
            label: '全部',
            selected: _selectedType == null,
            onSelected: () {
              if (_selectedType == null) return;
              setState(() {
                _selectedType = null;
                _page = 1;
                _viewCacheAnyway = false;
                _activeOutage = null;
              });
              _fetchData(page: 1);
            },
            colorScheme: colorScheme,
          ),
          for (final t in _types) ...[
            const SizedBox(width: 6),
            _buildFilterChip(
              label: t.name,
              selected: _selectedType == t.typeid,
              onSelected: () {
                if (_selectedType == t.typeid) return;
                setState(() {
                  _selectedType = t.typeid;
                  _page = 1;
                  _viewCacheAnyway = false;
                  _activeOutage = null;
                });
                _fetchData(page: 1);
              },
              colorScheme: colorScheme,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    required ColorScheme colorScheme,
  }) {
    return PressScaleEffect(
      scaleDown: 0.94,
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
        ),
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.transparent,
        selectedColor: colorScheme.primaryContainer.withAlpha(120),
        side: BorderSide(
          color: selected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withAlpha(80),
          width: selected ? 1.0 : 0.6,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  /// 4. 真实子版块展示（仅当版块确实存在子版块时显示，支持收起/展开与记忆）
  Widget _buildSubforumSection(ThemeData theme) {
    final validSubs = _subForums.where((s) =>
        s.fid != widget.fid &&
        s.fid > 0 &&
        s.name.trim().isNotEmpty &&
        s.name != '首页' &&
        s.name != '论坛' &&
        s.name != '全部' &&
        s.name != '服务器列表'
    ).toList();
    if (validSubs.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggleSubforumsCollapse,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.folder_special_rounded, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    '子版块 (${validSubs.length})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedExpandArrow(
                    isCollapsed: _subforumsCollapsed,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCollapseSection(
            isCollapsed: _subforumsCollapsed,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final sub in validSubs)
                    PressScaleEffect(
                      scaleDown: 0.95,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ThreadListPage(
                                fid: sub.fid,
                                title: sub.name,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withAlpha(60),
                              width: 0.6,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.subdirectory_arrow_right,
                                size: 13,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                sub.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (sub.todayCount > 0) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[800],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${sub.todayCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 5. 彩色置顶帖区（支持一键收起/展开与记忆）
  Widget _buildStickySection(
    List<ThreadSummary> stickyThreads,
    ThemeData theme,
  ) {
    final colors = [
      const Color(0xFF1976D2), // 蓝
      const Color(0xFFD32F2F), // 红
      const Color(0xFF388E3C), // 绿
      const Color(0xFFF57C00), // 橙
    ];
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _toggleStickyCollapse,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.push_pin_rounded, size: 14, color: colors[0]),
                  const SizedBox(width: 6),
                  Text(
                    '置顶推荐 (${stickyThreads.length})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedExpandArrow(
                    isCollapsed: _stickyCollapsed,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCollapseSection(
            isCollapsed: _stickyCollapsed,
            child: Column(
              children: [
                Divider(
                  height: 1,
                  thickness: 0.6,
                  color: colorScheme.outlineVariant.withAlpha(40),
                ),
                for (var i = 0; i < stickyThreads.length; i++) ...[
                  PressScaleEffect(
                    scaleDown: 0.985,
                    child: InkWell(
                      onTap: () => _openThread(stickyThreads[i].tid),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: colors[i % colors.length].withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: colors[i % colors.length].withAlpha(100),
                                  width: 0.6,
                                ),
                              ),
                              child: Text(
                                '置顶',
                                style: TextStyle(
                                  color: colors[i % colors.length],
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                stickyThreads[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors[i % colors.length],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (i < stickyThreads.length - 1)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.grey.withAlpha(40),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 7. 排序 Chips
  Widget _buildOrderChips(ThemeData theme) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: [
          for (final (key, label) in const [
            (null, '默认排序'),
            ('lastpost', '最新回复'),
            ('dateline', '最新发布'),
            ('replies', '最多回复'),
            ('views', '最多查看'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: _orderby == key,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  if (_orderby == key) return;
                  setState(() {
                    _orderby = key;
                    _page = 1;
                    _viewCacheAnyway = false;
                    _activeOutage = null;
                  });
                  _fetchData(page: 1);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// 9. 统一底部翻页控件
  Widget _buildPagination(ThemeData theme) {
    return PaginationControl(
      page: _page,
      hasMore: true,
      onPageChanged: _goPage,
    );
  }

  /// 10. 桌面端版块列表与帖子详情之间的拖拽调节手柄
  Widget _buildMasterDetailSplitter() {
    return _MasterDetailSplitter(
      onToggleCollapse: _toggleMasterCollapse,
    );
  }

  /// 11. 桌面端版块列表折叠后的纤细展开把手
  Widget _buildCollapsedMasterHandle() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: theme.cardColor,
      child: InkWell(
        onTap: _toggleMasterCollapse,
        child: Container(
          width: 30,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: theme.dividerColor.withAlpha(50),
              ),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Tooltip(
                message: '展开版块列表',
                child: Container(
                  width: 24,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withAlpha(120),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              RotatedBox(
                quarterTurns: 1,
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant.withAlpha(180),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasterDetailSplitter extends StatefulWidget {
  final VoidCallback? onToggleCollapse;
  const _MasterDetailSplitter({this.onToggleCollapse});

  @override
  State<_MasterDetailSplitter> createState() => _MasterDetailSplitterState();
}

class _MasterDetailSplitterState extends State<_MasterDetailSplitter> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final active = _isHovered || _isDragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => AppConfig.setThreadForumSidebarWidth(380.0),
        onHorizontalDragStart: (_) => setState(() => _isDragging = true),
        onHorizontalDragUpdate: (details) {
          final newW = AppConfig.threadForumSidebarWidth + details.delta.dx;
          AppConfig.updateThreadForumSidebarWidth(newW);
        },
        onHorizontalDragEnd: (_) {
          setState(() => _isDragging = false);
          AppConfig.setThreadForumSidebarWidth(AppConfig.threadForumSidebarWidth);
        },
        onHorizontalDragCancel: () => setState(() => _isDragging = false),
        child: Container(
          width: 14,
          color: active ? colorScheme.primary.withAlpha(20) : Colors.transparent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: active ? 3 : 1.5,
                height: active ? 80 : 36,
                decoration: BoxDecoration(
                  color: active
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withAlpha(110),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (_isHovered && widget.onToggleCollapse != null)
                Positioned(
                  top: 14,
                  child: Tooltip(
                    message: '收起版块列表',
                    child: InkWell(
                      onTap: widget.onToggleCollapse,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 18,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          border: Border.all(
                            color: colorScheme.outlineVariant.withAlpha(150),
                            width: 0.8,
                          ),
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(20),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.chevron_left_rounded,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
