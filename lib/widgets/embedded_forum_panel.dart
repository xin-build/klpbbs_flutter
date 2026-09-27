import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/klpbbs_api.dart';
import '../models/forum_header_info.dart';
import '../models/thread_summary.dart';
import 'interactive_animations.dart';

/// 帖子详情页桌面工作台左侧栏：1:1 对齐原生版块界面（EmbeddedForumPanel）
/// 具备完整的版块头部、分类筛选ChoiceChips、原生 RefreshIndicator 下拉回弹刷新、双层置顶帖流、跟手切帖与当前阅读高光标记
class EmbeddedForumPanel extends StatefulWidget {
  final int fid;
  final int currentTid;
  final ValueChanged<int> onSelectThread;

  const EmbeddedForumPanel({
    super.key,
    required this.fid,
    required this.currentTid,
    required this.onSelectThread,
  });

  @override
  State<EmbeddedForumPanel> createState() => _EmbeddedForumPanelState();
}

class _EmbeddedForumPanelState extends State<EmbeddedForumPanel> {
  ForumHeaderInfo? _headerInfo;
  List<ThreadSummary> _stickyThreads = [];
  List<ThreadSummary> _normalThreads = [];
  bool _loading = true;
  bool _stickyExpanded = true;

  int _page = 1;
  int? _selectedType;
  String? _orderby = 'lastpost';
  List<({int typeid, String name})> _types = const [];

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchForumData(page: 1, isInitial: true);
    _loadTypes();
  }

  @override
  void didUpdateWidget(covariant EmbeddedForumPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fid != widget.fid) {
      _fetchForumData(page: 1, isInitial: true);
      _loadTypes();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final types = await KlpbbsApi.getThreadTypes(widget.fid);
      if (mounted) setState(() => _types = types);
    } catch (_) {}
  }

  Future<void> _fetchForumData({int page = 1, bool isInitial = false}) async {
    if (isInitial && mounted) {
      setState(() => _loading = true);
    }

    try {
      final bundle = await KlpbbsApi.getForumBundle(
        widget.fid,
        page: page,
        typeid: _selectedType,
        orderby: _orderby,
      );

      if (mounted) {
        setState(() {
          _headerInfo = bundle.header;
          if (bundle.types.isNotEmpty) _types = bundle.types;
          _stickyThreads = bundle.threads.where((t) => t.isSticky).toList();
          final normal = bundle.threads.where((t) => !t.isSticky).toList();
          if (page == 1) {
            _normalThreads = normal;
          } else {
            _normalThreads.addAll(normal);
          }
          _page = page;
          _loading = false;
        });
      }
    } catch (_) {
      // 降级使用普通 getThreadList 兼容
      try {
        final list = await KlpbbsApi.getThreadList(widget.fid, page: page);
        if (mounted) {
          setState(() {
            if (page == 1) {
              _normalThreads = list;
            } else {
              _normalThreads.addAll(list);
            }
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final forumTitle = _headerInfo?.name ?? '当前版块';
    final todayPosts = _headerInfo?.todayPosts ?? 0;
    final totalThreads = _headerInfo?.threadsCount ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 版块原生 Header（图标、版块名、今日统计与切换排序）
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(50),
                width: 0.8,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.forum_rounded, size: 18, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          forumTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '今日 $todayPosts 帖 · 共 $totalThreads 篇主题',
                          style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  // 排序切换菜单
                  PopupMenuButton<String>(
                    tooltip: '排序方式',
                    initialValue: _orderby,
                    icon: Icon(Icons.sort_rounded, size: 20, color: colorScheme.primary),
                    onSelected: (val) {
                      setState(() => _orderby = val);
                      _fetchForumData(page: 1, isInitial: true);
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'lastpost', child: Text('最新回复 (默认)')),
                      PopupMenuItem(value: 'dateline', child: Text('最新发表')),
                      PopupMenuItem(value: 'digest', child: Text('精华帖子')),
                      PopupMenuItem(value: 'views', child: Text('最多浏览')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 2. 分类筛选 ChoiceChips (对齐 ThreadListPage 原版体验)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: _selectedType == null,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        setState(() => _selectedType = null);
                        _fetchForumData(page: 1, isInitial: true);
                      },
                    ),
                    ..._types.map((tp) {
                      final isSel = _selectedType == tp.typeid;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(tp.name),
                          selected: isSel,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            setState(() => _selectedType = isSel ? null : tp.typeid);
                            _fetchForumData(page: 1, isInitial: true);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 3. 原生下拉刷新与跟手切帖双层流
        Expanded(
          child: _loading
              ? Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    HapticFeedback.lightImpact();
                    await _fetchForumData(page: 1);
                  },
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.surface,
                  child: ListView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    children: [
                      // 置顶贴群组折叠区
                      if (_stickyThreads.isNotEmpty) ...[
                        InkWell(
                          onTap: () => setState(() => _stickyExpanded = !_stickyExpanded),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.push_pin_rounded, size: 14, color: Colors.orange.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '版块置顶 (${_stickyThreads.length})',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                                ),
                                const Spacer(),
                                AnimatedExpandArrow(
                                  isCollapsed: !_stickyExpanded,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedCollapseSection(
                          isCollapsed: !_stickyExpanded,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _stickyThreads.map((t) => _buildThreadItem(context, t, isSticky: true)).toList(),
                          ),
                        ),
                        const Divider(height: 12, thickness: 0.8),
                      ],

                      // 普通帖子列表
                      if (_normalThreads.isEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Center(
                            child: Text('本版块暂无相关帖子', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ),
                        ),
                      ] else ...[
                        ..._normalThreads.map((t) => _buildThreadItem(context, t, isSticky: false)),
                      ],

                      // 底部加载更多按钮
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: () => _fetchForumData(page: _page + 1),
                            icon: const Icon(Icons.arrow_downward_rounded, size: 14),
                            label: Text('加载更多 (当前第 $_page 页)', style: const TextStyle(fontSize: 11)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// 单个跟手切帖项（当前浏览中的帖子附带醒目高光标识）
  Widget _buildThreadItem(BuildContext context, ThreadSummary t, {required bool isSticky}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCurrent = t.tid == widget.currentTid;

    return RepaintBoundary(
      child: PressScaleEffect(
      scaleDown: 0.982,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: isCurrent
            ? colorScheme.primaryContainer.withAlpha(110)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: isCurrent
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  widget.onSelectThread(t.tid);
                },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isCurrent
                  ? Border.all(color: colorScheme.primary, width: 1.2)
                  : Border.all(color: colorScheme.outlineVariant.withAlpha(35), width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isSticky)
                      Container(
                        margin: const EdgeInsets.only(right: 6, top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(30),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '置顶',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                          color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      t.author,
                      style: TextStyle(fontSize: 10.5, color: colorScheme.outline.withAlpha(190)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.timeText ?? '',
                      style: TextStyle(fontSize: 10, color: colorScheme.outline.withAlpha(150)),
                    ),
                    const Spacer(),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('正在阅读', style: TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.bold)),
                      )
                    else
                      Text(
                        '${t.replies} 评',
                        style: TextStyle(fontSize: 10, color: colorScheme.outline.withAlpha(180)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
}
}
