import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/forum_events.dart';
import '../core/preload_service.dart';
import '../models/forum.dart';
import '../models/forum_header_info.dart';
import '../models/thread_summary.dart';
import '../widgets/desktop_shortcuts.dart';
import '../widgets/empty_view.dart';
import '../widgets/forum_header_widget.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/pagination_control.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/thread_card.dart';
import 'post_page.dart';
import 'search_page.dart';
import 'thread_detail_page.dart';
import 'user_space_page.dart';

/// 版块帖子列表（深度复刻 Discuz 原版版块布局：图三与图四）
class ThreadListPage extends StatefulWidget {
  final int fid;
  final String title;

  const ThreadListPage({super.key, required this.fid, required this.title});

  @override
  State<ThreadListPage> createState() => _ThreadListPageState();
}

class _ThreadListPageState extends State<ThreadListPage> {
  ForumHeaderInfo? _headerInfo;
  List<ThreadSummary> _stickyThreads = [];
  List<ThreadSummary> _normalThreads = [];
  bool _isInitialLoading = true;
  bool _isPageLoading = false;
  String? _errorMessage;

  int _page = 1;
  List<({int typeid, String name})> _types = const [];
  int? _selectedType;
  String? _orderby;
  int? _selectedTid;
  bool _isFav = false;

  List<Forum> _subForums = [];

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    ForumFavoriteNotifier.instance.addListener(_onFavEvent);
    _loadFavStatus();
    _fetchData(page: 1, isInitial: true);
    _loadTypes();
    _loadSubForums();
  }

  @override
  void dispose() {
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
        }
        _errorMessage = null;
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
        _isInitialLoading = false;
        _isPageLoading = false;
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
      setState(() {
        _isInitialLoading = false;
        _isPageLoading = false;
        if (_headerInfo == null) {
          _errorMessage = e.toString();
        } else {
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
    _fetchData(page: page);
  }

  void _openThread(int tid) {
    if (ResponsiveBreakpoints.isDesktop(context) &&
        AppConfig.isMasterDetailEnabled) {
      setState(() => _selectedTid = tid);
    } else {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: tid)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final isMasterDetail = isDesktop &&
        AppConfig.isMasterDetailEnabled &&
        MediaQuery.sizeOf(context).width >= 768.0;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final header = _headerInfo ?? ForumHeaderInfo(fid: widget.fid, name: widget.title);

    // 首次加载且无缓存直出时展示骨架屏
    if (_isInitialLoading && _headerInfo == null) {
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
        body: const SkeletonList(itemCount: 8),
      );
    }

    // 首次加载出错且无数据
    if (_errorMessage != null && _headerInfo == null) {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('加载失败：$_errorMessage', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _reload, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    // 局部刷新的普通帖子区（固定的内容固定，翻页仅刷新普通帖子列表和翻页器）
    Widget normalThreadsSection;
    if (_isPageLoading) {
      normalThreadsSection = Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(height: 10),
              Text(
                '正在加载第 $_page 页...',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    } else if (_normalThreads.isEmpty && _stickyThreads.isEmpty) {
      normalThreadsSection = const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: EmptyView(
          icon: Icons.inbox_outlined,
          title: '本版块暂无更多帖子',
          subtitle: '点击右下角按钮抢先发布！',
        ),
      );
    } else {
      normalThreadsSection = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in _normalThreads)
            RepaintBoundary(
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: (_selectedTid == t.tid &&
                          isDesktop &&
                          AppConfig.isMasterDetailEnabled)
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
              ),
            ),
        ],
      );
    }

    final listView = RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        controller: _scrollController,
        key: PageStorageKey('thread_list_${widget.fid}_${_selectedType ?? 0}'),
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
        children: [
          // 0. 版块头部 Banner + 统计栏 + 导览/版规卡片（常驻稳定）
          ForumHeaderWidget(
            headerInfo: header,
            onPost: _openPostPage,
          ),

          // 1. 分类横向 Tab 栏 (全部 | 村庄改革 | 独立创作...)
          _buildCategoryTabBar(theme),

          // 2. 真实子版块入口
          _buildSubforumSection(theme),

          // 3. 彩色置顶帖区（常驻）
          if (_stickyThreads.isNotEmpty)
            _buildStickySection(_stickyThreads, theme),

          // 4. 排序 Chips
          _buildOrderChips(theme),

          // 5. 局部定向刷新的普通帖子区
          normalThreadsSection,

          // 6. 分页导航
          _buildPagination(theme),
        ],
      ),
    );

    if (isMasterDetail) {
      return DesktopShortcutsWrapper(
        onRefresh: _reload,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧：帖子列表栏（精简顶栏：去除冗余切换版块/跳转页码，版块标题绝不遮挡）
            SizedBox(
              width: 440,
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
                      IconButton(
                        icon: Icon(
                          _isFav ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 22,
                          color: _isFav ? const Color(0xFFFFB300) : null,
                        ),
                        tooltip: _isFav ? '已收藏版块（点击取消）' : '收藏版块',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: _toggleFav,
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
                      const SizedBox(width: 6),
                    ],
                  ),
                  body: listView,
                ),
              ),
            ),
            // 中间：分界线
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withAlpha(80),
            ),
            // 右侧：帖子详情展示区（完全独立解耦，翻页时不闪烁骨架屏）
            Expanded(
              child: ScaffoldMessenger(
                child: _selectedTid == null
                    ? Scaffold(
                        appBar: AppBar(
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
                        showBackButton: false,
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
        drawer: const GlobalAppDrawer(),
        appBar: AppBar(
          leading: const GlobalNavLeading(),
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: Icon(
                _isFav ? Icons.star_rounded : Icons.star_border_rounded,
                color: _isFav ? const Color(0xFFFFB300) : null,
              ),
              tooltip: _isFav ? '已收藏版块（点击取消）' : '收藏版块',
              onPressed: _toggleFav,
            ),
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
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.edit),
          label: const Text('发帖'),
          onPressed: _openPostPage,
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
    return FilterChip(
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
    );
  }

  /// 4. 真实子版块展示（仅当版块确实存在子版块时显示）
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

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '子版块',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final sub in validSubs)
                InkWell(
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
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withAlpha(60),
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right,
                          size: 13,
                          color: Theme.of(context).colorScheme.primary,
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
            ],
          ),
        ],
      ),
    );
  }

  /// 5. 彩色置顶帖区
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < stickyThreads.length; i++) ...[
            InkWell(
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
            if (i < stickyThreads.length - 1)
              Divider(
                height: 1,
                thickness: 0.5,
                color: Colors.grey.withAlpha(40),
              ),
          ],
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
}
