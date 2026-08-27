import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../models/forum.dart';
import '../models/thread_summary.dart';
import '../models/user_space.dart';
import '../widgets/global_nav.dart';
import '../widgets/pagination_control.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/thread_card.dart';
import 'thread_detail_page.dart';
import 'user_space_page.dart';

/// 苦力怕论坛高级搜索页（深度复刻 Discuz Xunsearch 原版布局 + 批量抓取全部 + 即时多维过滤）
class SearchPage extends StatefulWidget {
  final String? initialKeyword;

  const SearchPage({super.key, this.initialKeyword});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _kwCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();

  int _searchMode = 0; // 0: 帖子, 1: 用户
  List<ThreadSummary>? _threadResults;
  List<UserSpace>? _userResults;
  bool _loading = false;
  String? _error;
  List<String> _history = [];
  int _page = 1;
  int _totalPages = 1;

  // 批量获取全部帖子状态
  bool _fetchingAll = false;
  double _fetchAllProgress = 0.0;
  String _fetchAllStatusText = '';
  bool _cancelFetchAll = false;
  bool _isAllMode = false; // 是否处于全部帖子展示模式

  // 客户端高级过滤条件
  bool _showLiveFilter = false;
  final _excludeKwCtrl = TextEditingController();
  final _filterAuthorCtrl = TextEditingController();
  int? _filterFid;
  int _minReplies = 0;
  int _minViews = 0;
  bool _filterOnlyCover = false;
  bool _filterOnlyDigest = false;

  // Xunsearch 高级筛选状态
  bool _showFilter = true;
  String _srchScope = 'fulltext'; // fulltext: 全文, title: 标题
  bool _fuzzy = false; // 模糊搜索
  bool _synonym = true; // 同义词
  String _sortOrder = 'relevance'; // relevance: 相关性, dateline: 发布时间, lastpost: 回复时间
  final Set<int> _selectedFids = {}; // 指定版块 (可多选)

  List<ForumGroup> _forumGroups = [];

  @override
  void initState() {
    super.initState();
    _loadForumGroups();
    _loadHistory();
    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      _kwCtrl.text = widget.initialKeyword!;
      _doSearch(page: 1);
    }
  }

  Future<void> _loadForumGroups() async {
    try {
      final groups = await KlpbbsApi.getForumGroups();
      if (mounted) setState(() => _forumGroups = groups);
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
      () => _history = prefs.getStringList('search_history') ?? const [],
    );
  }

  Future<void> _saveHistory(String kw) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('search_history') ?? [];
    list.remove(kw);
    list.insert(0, kw);
    final trimmed = list.take(16).toList();
    await prefs.setStringList('search_history', trimmed);
    if (mounted) setState(() => _history = trimmed);
  }

  Future<void> _removeHistoryItem(String kw) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('search_history') ?? [];
    list.remove(kw);
    await prefs.setStringList('search_history', list);
    if (mounted) setState(() => _history = list);
  }

  @override
  void dispose() {
    _kwCtrl.dispose();
    _authorCtrl.dispose();
    _excludeKwCtrl.dispose();
    _filterAuthorCtrl.dispose();
    super.dispose();
  }

  Future<void> _doSearch({int page = 1}) async {
    final kw = _kwCtrl.text.trim();
    if (kw.isEmpty) {
      setState(() => _error = '请输入关键词搜索');
      return;
    }
    setState(() {
      _page = page;
      _loading = true;
      _error = null;
      _isAllMode = false;
      _fetchingAll = false;
    });

    try {
      if (_searchMode == 0) {
        // 帖子搜索
        final results = await KlpbbsApi.search(
          kw,
          author: _authorCtrl.text.trim(),
          srchtype: _srchScope == 'fulltext' ? 'fulltext' : 'title',
          orderby: _sortOrder,
          fid: _selectedFids.isNotEmpty ? _selectedFids.first : null,
          page: page,
        );
        if (!mounted) return;
        _saveHistory(kw);
        setState(() {
          _threadResults = results;
          _userResults = null;
          _loading = false;
          if (results.length >= 10) {
            _totalPages = math.max(_totalPages, page + 1);
          } else {
            _totalPages = page;
          }
          if (results.isEmpty) _error = page == 1 ? '未找到相关帖子' : '没有更多搜索结果了';
        });
      } else {
        // 用户搜索（对接 Discuz 原生搜索接口与 UID 精确直达）
        final users = await KlpbbsApi.searchUsers(kw, page: page);
        if (!mounted) return;
        _saveHistory(kw);
        setState(() {
          _userResults = users;
          _threadResults = null;
          _loading = false;
          if (users.length >= 10) {
            _totalPages = math.max(_totalPages, page + 1);
          } else {
            _totalPages = page;
          }
          if (users.isEmpty) _error = page == 1 ? '未找到相关用户' : '没有更多用户了';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '搜索失败：$e';
      });
    }
  }

  /// 批量抓取全部相关帖子（带实时进度条）
  Future<void> _fetchAllMatchingThreads() async {
    final kw = _kwCtrl.text.trim();
    if (kw.isEmpty) return;

    setState(() {
      _fetchingAll = true;
      _cancelFetchAll = false;
      _fetchAllProgress = 0.05;
      _fetchAllStatusText = '正在准备批量获取全部匹配帖子...';
      _isAllMode = true;
    });

    final allList = <ThreadSummary>[];
    final seenTids = <int>{};
    const maxPages = 15; // 限制最大防封防爆页数

    try {
      for (var p = 1; p <= maxPages; p++) {
        if (_cancelFetchAll) break;

        setState(() {
          _fetchAllProgress = p / maxPages;
          _fetchAllStatusText = '正在获取第 $p 页 (已抓取 ${allList.length} 篇帖子)...';
        });

        final pageResults = await KlpbbsApi.search(
          kw,
          author: _authorCtrl.text.trim(),
          srchtype: _srchScope == 'fulltext' ? 'fulltext' : 'title',
          orderby: _sortOrder,
          fid: _selectedFids.isNotEmpty ? _selectedFids.first : null,
          page: p,
        );

        if (pageResults.isEmpty) break;

        var newCount = 0;
        for (final t in pageResults) {
          if (seenTids.add(t.tid)) {
            allList.add(t);
            newCount++;
          }
        }

        if (!mounted) return;
        setState(() {
          _threadResults = List.from(allList);
        });

        if (newCount == 0 || pageResults.length < 10) {
          // 没有更多新帖了
          break;
        }

        // 短暂避让延迟
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (mounted) {
        setState(() {
          _fetchingAll = false;
          _threadResults = allList;
          _fetchAllStatusText = '全部获取完成！共抓取 ${allList.length} 篇帖子';
          if (allList.isEmpty) _error = '未找到相关帖子';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchingAll = false;
          _threadResults = allList;
          _error = '获取中断：$e (已保留获取到的 ${allList.length} 篇帖子)';
        });
      }
    }
  }

  /// 客户端即时过滤结果计算
  List<ThreadSummary> get _filteredThreads {
    if (_threadResults == null) return const [];
    var list = _threadResults!;

    // 1. 排除关键字
    final excludeStr = _excludeKwCtrl.text.trim();
    if (excludeStr.isNotEmpty) {
      final excludes = excludeStr
          .split(RegExp(r'[\s,，;；]+'))
          .where((s) => s.isNotEmpty)
          .map((s) => s.toLowerCase())
          .toList();
      if (excludes.isNotEmpty) {
        list = list.where((t) {
          final text = '${t.title} ${t.excerpt ?? ''}'.toLowerCase();
          return !excludes.any((ex) => text.contains(ex));
        }).toList();
      }
    }

    // 2. 指定作者过滤
    final authorStr = _filterAuthorCtrl.text.trim().toLowerCase();
    if (authorStr.isNotEmpty) {
      list = list.where((t) => t.author.toLowerCase().contains(authorStr)).toList();
    }

    // 3. 指定版块过滤
    if (_filterFid != null && _filterFid! > 0) {
      list = list.where((t) => t.fid == _filterFid).toList();
    }

    // 4. 最小回复数过滤
    if (_minReplies > 0) {
      list = list.where((t) => t.replies >= _minReplies).toList();
    }

    // 5. 最小查看量过滤
    if (_minViews > 0) {
      list = list.where((t) => t.views >= _minViews).toList();
    }

    // 6. 仅看含图片
    if (_filterOnlyCover) {
      list = list.where((t) => t.coverUrl != null && t.coverUrl!.isNotEmpty).toList();
    }

    // 7. 仅看精华
    if (_filterOnlyDigest) {
      list = list.where((t) => t.isDigest).toList();
    }

    return list;
  }

  /// 检查是否有任何过滤条件激活
  int get _activeFilterCount {
    var count = 0;
    if (_excludeKwCtrl.text.trim().isNotEmpty) count++;
    if (_filterAuthorCtrl.text.trim().isNotEmpty) count++;
    if (_filterFid != null && _filterFid! > 0) count++;
    if (_minReplies > 0) count++;
    if (_minViews > 0) count++;
    if (_filterOnlyCover) count++;
    if (_filterOnlyDigest) count++;
    return count;
  }

  void _clearLiveFilters() {
    setState(() {
      _excludeKwCtrl.clear();
      _filterAuthorCtrl.clear();
      _filterFid = null;
      _minReplies = 0;
      _minViews = 0;
      _filterOnlyCover = false;
      _filterOnlyDigest = false;
    });
  }

  /// 热门搜索词
  static const _hotWords = [
    '我的世界',
    '基岩版',
    'Java',
    '光影',
    '模组',
    '整合包',
    '地图',
    '皮肤',
    '红石',
    '服务器',
    '建筑',
    '生存',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('论坛搜索 (Xunsearch)'),
        actions: const [GlobalNavButton()],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            children: [
              // 模式切换 Pills [ 帖子 ] [ 用户 ]
              Row(
                children: [
                  _buildModeTab('帖子', 0),
                  const SizedBox(width: 10),
                  _buildModeTab('用户', 1),
                ],
              ),
              const SizedBox(height: 14),

              // 搜索框 + 搜索按钮
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _kwCtrl,
                        decoration: InputDecoration(
                          hintText: _searchMode == 0 ? '输入关键词搜索' : '输入用户名或 UID 搜索',
                          hintStyle: TextStyle(fontSize: 14, color: colorScheme.outline),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _kwCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(() => _kwCtrl.clear()),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(120)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                          ),
                          filled: true,
                          fillColor: colorScheme.surface,
                        ),
                        onSubmitted: (_) => _doSearch(page: 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: () => _doSearch(page: 1),
                    child: const Text('搜索'),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Xunsearch 高级筛选卡片 (仅帖子模式)
              if (_searchMode == 0) _buildAdvancedFilterCard(theme),

              // 批量获取全部进度条
              if (_fetchingAll)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withAlpha(50),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.primary.withAlpha(90)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _fetchAllStatusText,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _cancelFetchAll = true),
                            child: const Text('取消获取', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _fetchAllProgress,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),

              // 即时高级过滤面板 (在有搜索结果时展示)
              if (_threadResults != null && _threadResults!.isNotEmpty)
                _buildLiveFilterSection(theme),

              const SizedBox(height: 10),

              // 搜索中 loading 骨架屏
              if (_loading && !_fetchingAll) const SkeletonList(itemCount: 6),

              // 错误/空状态提示
              if (_error != null && !_loading && !_fetchingAll)
                Container(
                  padding: const EdgeInsets.all(20),
                  alignment: Alignment.center,
                  child: Text(
                    _error!,
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                  ),
                ),

              // 搜索结果列表
              if (!_loading) ...[
                if (_searchMode == 0 && _threadResults != null) ..._buildThreadResultList(),
                if (_searchMode == 1 && _userResults != null) ..._buildUserResultList(),
              ],

              // 默认展示：搜索历史 & 热门搜索
              if (_threadResults == null && _userResults == null && !_loading)
                _buildHistoryAndHotwords(theme),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildModeTab(String label, int mode) {
    final selected = _searchMode == mode;
    final theme = Theme.of(context);
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        ),
      ),
      selected: selected,
      selectedColor: theme.colorScheme.primary,
      onSelected: (_) => setState(() {
        _searchMode = mode;
        _threadResults = null;
        _userResults = null;
        _error = null;
      }),
    );
  }

  Widget _buildAdvancedFilterCard(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showFilter = !_showFilter),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Xunsearch 高级搜索选项',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showFilter ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_showFilter) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilterRow(
                    label: '按作者',
                    child: TextField(
                      controller: _authorCtrl,
                      decoration: InputDecoration(
                        hintText: '输入作者用户名',
                        hintStyle: TextStyle(fontSize: 12, color: colorScheme.outline),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFilterRow(
                    label: '搜索范围',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Radio<String>(
                              value: 'fulltext',
                              groupValue: _srchScope,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) => setState(() => _srchScope = v!),
                            ),
                            const Text('全文', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Radio<String>(
                              value: 'title',
                              groupValue: _srchScope,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) => setState(() => _srchScope = v!),
                            ),
                            const Text('标题', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _fuzzy,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) => setState(() => _fuzzy = v ?? false),
                            ),
                            const Text('模糊', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _synonym,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) => setState(() => _synonym = v ?? true),
                            ),
                            const Text('同义词', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFilterRow(
                    label: '排序方式',
                    child: DropdownButtonFormField<String>(
                      value: _sortOrder,
                      decoration: _dropdownDeco(),
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 'relevance', child: Text('相关性')),
                        DropdownMenuItem(value: 'dateline', child: Text('发布时间')),
                        DropdownMenuItem(value: 'lastpost', child: Text('回复时间')),
                      ],
                      onChanged: (v) => setState(() => _sortOrder = v ?? 'relevance'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '指定版块 (可多选)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_forumGroups.isNotEmpty)
                    Material(
                      color: colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _forumGroups.length,
                          itemBuilder: (ctx, i) {
                            final group = _forumGroups[i];
                            return ExpansionTile(
                              dense: true,
                              title: Text(
                                group.name,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                              ),
                              children: [
                                for (final f in group.forums)
                                  CheckboxListTile(
                                    dense: true,
                                    title: Text(f.name, style: const TextStyle(fontSize: 12)),
                                    value: _selectedFids.contains(f.fid),
                                    onChanged: (checked) {
                                      setState(() {
                                        if (checked == true) {
                                          _selectedFids.add(f.fid);
                                        } else {
                                          _selectedFids.remove(f.fid);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'Powered by xunsearch',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[400],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 即时多维过滤控制面板
  Widget _buildLiveFilterSection(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final activeCount = _activeFilterCount;
    final totalCount = _threadResults?.length ?? 0;
    final filteredCount = _filteredThreads.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showLiveFilter = !_showLiveFilter),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.filter_alt_outlined, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '结果实时过滤 ${activeCount > 0 ? "($activeCount 项生效)" : ""}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: activeCount > 0 ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '显示 $filteredCount / $totalCount 篇',
                      style: TextStyle(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  if (activeCount > 0)
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                      onPressed: _clearLiveFilters,
                      child: const Text('重置过滤', style: TextStyle(fontSize: 12)),
                    ),
                  Icon(
                    _showLiveFilter ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_showLiveFilter) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 排除关键字
                  Row(
                    children: [
                      const SizedBox(
                        width: 76,
                        child: Text('排除词', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _excludeKwCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: '排除含有此词的帖子（空格分隔多个）',
                            hintStyle: TextStyle(fontSize: 12, color: colorScheme.outline),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 作者过滤
                  Row(
                    children: [
                      const SizedBox(
                        width: 76,
                        child: Text('指定作者', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _filterAuthorCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: '按发帖用户名过滤',
                            hintStyle: TextStyle(fontSize: 12, color: colorScheme.outline),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 快捷开关 Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('仅看含图片', style: TextStyle(fontSize: 12)),
                        selected: _filterOnlyCover,
                        onSelected: (v) => setState(() => _filterOnlyCover = v),
                      ),
                      FilterChip(
                        label: const Text('仅看精华帖', style: TextStyle(fontSize: 12)),
                        selected: _filterOnlyDigest,
                        onSelected: (v) => setState(() => _filterOnlyDigest = v),
                      ),
                      FilterChip(
                        label: Text(_minReplies > 0 ? '回复≥$_minReplies' : '回复>5', style: const TextStyle(fontSize: 12)),
                        selected: _minReplies > 0,
                        onSelected: (v) => setState(() => _minReplies = v ? 5 : 0),
                      ),
                      FilterChip(
                        label: Text(_minViews > 0 ? '查看≥$_minViews' : '查看>100', style: const TextStyle(fontSize: 12)),
                        selected: _minViews > 0,
                        onSelected: (v) => setState(() => _minViews = v ? 100 : 0),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterRow({required String label, required Widget child}) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  InputDecoration _dropdownDeco() {
    return InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      isDense: true,
    );
  }

  List<Widget> _buildThreadResultList() {
    final filtered = _filteredThreads;
    final totalFetched = _threadResults?.length ?? 0;

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(
              _isAllMode
                  ? '全部获取结果：共 $totalFetched 篇（过滤后显示 ${filtered.length} 篇）'
                  : '第 $_page 页 · 共找到 $totalFetched 条（过滤后 ${filtered.length} 条）',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (!_isAllMode && !_fetchingAll)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _fetchAllMatchingThreads,
                icon: const Icon(Icons.download_for_offline_outlined, size: 15),
                label: const Text('获取全部帖子', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
      if (filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Center(
            child: Text(
              '没有符合当前过滤条件的帖子',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ),
      for (final t in filtered)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ThreadCard(
            thread: t,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: t.tid)),
            ),
            onAuthorTap: t.uid == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UserSpacePage(uid: t.uid!),
                      ),
                    ),
          ),
        ),
      const SizedBox(height: 10),
      if (!_isAllMode)
        PaginationControl(
          page: _page,
          totalPages: _totalPages,
          hasMore: _threadResults!.length >= 10,
          onPageChanged: (newPage) => _doSearch(page: newPage),
        ),
      const SizedBox(height: 20),
    ];
  }

  List<Widget> _buildUserResultList() {
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          '找到 ${_userResults!.length} 个匹配用户',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
        ),
      ),
      for (final u in _userResults!)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
          ),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: UserAvatarWidget(
              uid: u.uid,
              author: u.username,
              size: 44,
              faceUrl: u.faceUrl.isNotEmpty ? u.faceUrl : null,
            ),
            title: Text(
              u.username,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'UID: ${u.uid}  ${u.levelName.isNotEmpty ? u.levelName : (u.group.isNotEmpty ? u.group : "")}  ${u.credits.isNotEmpty ? "积分: ${u.credits}" : (u.stats["简介"] ?? "")}',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => UserSpacePage(uid: u.uid)),
            ),
          ),
        ),
    ];
  }

  Widget _buildHistoryAndHotwords(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_history.isNotEmpty) ...[
          Row(
            children: [
              const Text(
                '搜索历史',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('search_history');
                  if (mounted) setState(() => _history = []);
                },
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('清空历史', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in _history)
                InputChip(
                  label: Text(h),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () => _removeHistoryItem(h),
                  onPressed: () {
                    _kwCtrl.text = h;
                    _doSearch(page: 1);
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        const Text(
          '热门搜索',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in _hotWords)
              ActionChip(
                avatar: const Icon(Icons.local_fire_department, size: 14, color: Colors.orange),
                label: Text(w),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.primaryContainer.withAlpha(50),
                onPressed: () {
                  _kwCtrl.text = w;
                  _doSearch(page: 1);
                },
              ),
          ],
        ),
      ],
    );
  }
}
