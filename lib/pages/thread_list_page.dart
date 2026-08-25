import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../models/forum.dart';
import '../models/forum_header_info.dart';
import '../models/thread_summary.dart';
import '../widgets/desktop_shortcuts.dart';
import '../widgets/empty_view.dart';
import '../widgets/forum_header_widget.dart';
import '../widgets/pagination_control.dart';
import '../widgets/responsive_layout.dart';
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
  late Future<({List<ThreadSummary> threads, ForumHeaderInfo header})> _future;
  int _page = 1;
  List<({int typeid, String name})> _types = const [];
  int? _selectedType;
  String? _orderby;
  int? _selectedTid;
  bool _isFav = false;

  List<Forum> _allForums = [];
  List<Forum> _subForums = [];

  @override
  void initState() {
    super.initState();
    _loadFavStatus();
    _future = _fetchData();
    _loadTypes();
    _loadAllForums();
    _loadSubForums();
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
    // 立即响应 UI，无需等待网络返回，保证即时刷新
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

  Future<void> _loadAllForums() async {
    try {
      final list = await KlpbbsApi.getForums();
      if (mounted) setState(() => _allForums = list);
    } catch (_) {}
  }

  Future<({List<ThreadSummary> threads, ForumHeaderInfo header})> _fetchData({int page = 1}) async {
    final results = await Future.wait([
      KlpbbsApi.getThreadList(
        widget.fid,
        page: page,
        typeid: _selectedType,
        orderby: _orderby,
      ),
      KlpbbsApi.getForumHeader(widget.fid),
    ]);
    final header = results[1] as ForumHeaderInfo;
    // 仅当服务端明确识别为已收藏且本地尚未标记时主动标记，绝不单向清空用户本地状态
    if (mounted && header.isFavorited && !_isFav) {
      setState(() => _isFav = true);
      SharedPreferences.getInstance().then((prefs) {
        final list = (prefs.getStringList('fav_forums') ?? []).toSet();
        if (list.add('${widget.fid}')) {
          prefs.setStringList('fav_forums', list.toList());
        }
      }).catchError((_) {});
    }
    return (
      threads: results[0] as List<ThreadSummary>,
      header: header,
    );
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
      _page = 1;
      _future = _fetchData(page: 1);
      _loadTypes();
      _loadSubForums();
    });
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
    setState(() {
      _page = page;
      _future = _fetchData(page: page);
    });
  }

  Future<void> _jumpPage() async {
    final ctrl = TextEditingController();
    final target = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到第几页'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: '输入页码',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final p = int.tryParse(v);
            if (p != null && p >= 1) Navigator.of(ctx).pop(p);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(ctrl.text.trim());
              if (p != null && p >= 1) Navigator.of(ctx).pop(p);
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (target != null && target >= 1) _goPage(target);
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

  void _showForumPicker() {
    if (_allForums.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => ListView.builder(
          controller: scrollCtrl,
          itemCount: _allForums.length,
          itemBuilder: (_, i) {
            final f = _allForums[i];
            final isCurrent = f.fid == widget.fid;
            return ListTile(
              title: Text(
                f.name,
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color: isCurrent ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
              trailing: isCurrent ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () {
                Navigator.of(ctx).pop();
                if (!isCurrent) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => ThreadListPage(fid: f.fid, title: f.name),
                    ),
                  );
                }
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final isMasterDetail = isDesktop && AppConfig.isMasterDetailEnabled;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final body = FutureBuilder<({List<ThreadSummary> threads, ForumHeaderInfo header})>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
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
        final threads = snap.data?.threads ?? [];
        final header = snap.data?.header ?? ForumHeaderInfo(fid: widget.fid, name: widget.title);

        // 默认选中首篇
        if (_selectedTid == null && threads.isNotEmpty && isDesktop) {
          _selectedTid = threads.first.tid;
        }

        final stickyThreads = threads.where((t) => t.isSticky).toList();
        final normalThreads = threads.where((t) => !t.isSticky).toList();

        final listView = RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            key: PageStorageKey('thread_list_${widget.fid}_$_selectedType'),
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
            children: [
              // 0. 版块头部 Banner + 统计栏 + 导览/版规卡片（100% 对齐网页版）
              ForumHeaderWidget(
                headerInfo: header,
                onPost: _openPostPage,
              ),

              // 1. 分类横向 Tab 栏 (全部 | 村庄改革 | 独立创作...)
              _buildCategoryTabBar(theme),

              // 2. 真实子版块入口
              _buildSubforumSection(theme),

              // 3. 彩色置顶帖区
              if (stickyThreads.isNotEmpty)
                _buildStickySection(stickyThreads, theme),

              // 4. 排序 Chips
              _buildOrderChips(theme),

              // 8. 普通帖子列表
              if (normalThreads.isEmpty && stickyThreads.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: EmptyView(
                    icon: Icons.inbox_outlined,
                    title: '本版块暂无更多帖子',
                    subtitle: '点击右下角按钮抢先发布！',
                  ),
                )
              else
                for (final t in normalThreads)
                  Container(
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
                                  builder: (_) =>
                                      UserSpacePage(uid: t.uid!),
                                ),
                              ),
                    ),
                  ),

              // 9. 分页导航
              _buildPagination(theme),
            ],
          ),
        );

        if (isMasterDetail) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左侧：帖子列表栏（自带版块专属顶栏，高度与右侧详情栏完全一致平整对齐）
              SizedBox(
                width: 440,
                child: ScaffoldMessenger(
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(widget.title),
                      actions: [
                        if (_allForums.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.swap_horiz, size: 20),
                            tooltip: '切换版块',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            onPressed: _showForumPicker,
                          ),
                        IconButton(
                          icon: const Icon(Icons.pin_outlined, size: 20),
                          tooltip: '跳转页码',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: _jumpPage,
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
              // 中间：优雅的分界线
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withAlpha(80),
              ),
              // 右侧：帖子详情展示区（自带独立 ScaffoldMessenger，杜绝双栏同时弹出通知）
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
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: listView,
          ),
        );
      },
    );

    if (isMasterDetail) {
      return DesktopShortcutsWrapper(
        onRefresh: _reload,
        child: body,
      );
    }

    return DesktopShortcutsWrapper(
      onRefresh: _reload,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              icon: Icon(
                _isFav ? Icons.star_rounded : Icons.star_border_rounded,
                color: _isFav ? const Color(0xFFFFB300) : null,
              ),
              tooltip: _isFav ? '已收藏版块（点击取消）' : '收藏版块',
              onPressed: _toggleFav,
            ),
            if (_allForums.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                tooltip: '切换版块',
                onPressed: _showForumPicker,
              ),
            IconButton(
              icon: const Icon(Icons.pin_outlined),
              tooltip: '跳转页码',
              onPressed: _jumpPage,
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
        body: body,
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
              setState(() => _selectedType = null);
              _reload();
            },
            colorScheme: colorScheme,
          ),
          for (final t in _types) ...[
            const SizedBox(width: 6),
            _buildFilterChip(
              label: t.name,
              selected: _selectedType == t.typeid,
              onSelected: () {
                setState(() => _selectedType = t.typeid);
                _reload();
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
                onSelected: (_) => setState(() {
                  _orderby = key;
                  _page = 1;
                  _future = _fetchData(page: 1);
                }),
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
