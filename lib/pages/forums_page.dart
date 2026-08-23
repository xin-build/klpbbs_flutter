import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../core/seed_data.dart';
import '../models/forum.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_nav.dart';
import '../widgets/skeleton_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'thread_list_page.dart';

/// 社区版块大全 / 版块导航中心
class ForumsPage extends StatefulWidget {
  const ForumsPage({super.key});

  @override
  State<ForumsPage> createState() => _ForumsPageState();
}

class _ForumsPageState extends State<ForumsPage> {
  late Future<List<ForumGroup>> _future;
  String _searchQuery = '';
  int _selectedGroupGid = 0; // 默认选中首个分组 (0: 我关注的, 1: 综合分区, 等)
  final Set<int> _favFids = {};
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFavs();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFavs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('fav_forums') ?? [];
      if (mounted) {
        setState(() {
          _favFids.clear();
          _favFids.addAll(list.map((e) => int.tryParse(e) ?? 0).where((f) => f > 0));
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFav(Forum forum) async {
    final isFav = _favFids.contains(forum.fid);
    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList('fav_forums') ?? []).toSet();
    if (isFav) {
      _favFids.remove(forum.fid);
      list.remove('${forum.fid}');
    } else {
      _favFids.add(forum.fid);
      list.add('${forum.fid}');
    }
    await prefs.setStringList('fav_forums', list.toList());
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isFav ? '已取消收藏「${forum.name}」' : '已收藏版块「${forum.name}」'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    // 同步到 Discuz 服务端
    KlpbbsApi.favoriteForum(forum.fid).catchError((_) => false);
  }

  void _load() {
    _future = KlpbbsApi.getForumGroups();
  }

  void _reload() {
    setState(() {
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: '搜索版块名称或别名...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              )
            : const Text('版块分类'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消搜索',
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchCtrl.clear();
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索版块',
              onPressed: () => setState(() => _isSearching = true),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _reload,
          ),
          const GlobalNavButton(),
        ],
      ),
      body: FutureBuilder<List<ForumGroup>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 48, color: colorScheme.outline),
                      const SizedBox(height: 12),
                      Text('版块列表加载失败', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );
            }
            return const SkeletonList(itemCount: 8);
          }

          final rawGroups = snapshot.data!;
          final baseGroups = rawGroups.isNotEmpty ? rawGroups : SeedData.forumGroups;

          // 自动同步服务端「我关注的」版块至 _favFids 与本地缓存
          bool hasNewFavs = false;
          for (final g in baseGroups) {
            if (g.gid == 0 || g.name.contains('关注') || g.name.contains('收藏')) {
              for (final f in g.forums) {
                if (_favFids.add(f.fid)) {
                  hasNewFavs = true;
                }
              }
            }
          }
          if (hasNewFavs) {
            SharedPreferences.getInstance().then((prefs) {
              prefs.setStringList('fav_forums', _favFids.map((e) => '$e').toList());
            }).catchError((_) {});
          }

          final allForums = baseGroups.expand((g) => g.forums).toList();
          final favForums = allForums.where((f) => _favFids.contains(f.fid)).toList();

          final groups = <ForumGroup>[];
          final hasFavGroup = baseGroups.any((g) => g.gid == 0 || g.name.contains('关注') || g.name.contains('收藏'));

          if (hasFavGroup) {
            for (final g in baseGroups) {
              if (g.gid == 0 || g.name.contains('关注') || g.name.contains('收藏')) {
                // 合并本地收藏版块与服务端已关注版块
                final combined = <Forum>[];
                final seenFids = <int>{};
                for (final f in favForums) {
                  if (seenFids.add(f.fid)) combined.add(f);
                }
                for (final f in g.forums) {
                  if (seenFids.add(f.fid)) combined.add(f);
                }
                groups.add(ForumGroup(
                  gid: 0,
                  name: '我关注的${combined.isNotEmpty ? ' (${combined.length})' : ''}',
                  forums: combined,
                ));
              } else {
                groups.add(g);
              }
            }
          } else {
            groups.add(ForumGroup(
              gid: 0,
              name: '我关注的${favForums.isNotEmpty ? ' (${favForums.length})' : ''}',
              forums: favForums,
            ));
            for (final g in baseGroups) {
              if (g.gid != 0) groups.add(g);
            }
          }

          // 搜索模式：跨所有分区检索匹配的版块
          if (_searchQuery.isNotEmpty) {
            final matches = allForums.where((f) {
              final q = _searchQuery.toLowerCase();
              return f.name.toLowerCase().contains(q) ||
                  (f.description?.toLowerCase().contains(q) ?? false);
            }).toList();

            if (matches.isEmpty) {
              return const EmptyView(
                icon: Icons.search_off,
                title: '未找到相关版块',
                subtitle: '尝试输入其他关键词搜索',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: matches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _buildForumCard(ctx, matches[i]),
            );
          }

          // 正常模式：顶部横向分区 Tab + 当前分区下的版块网格列表
          final selectedGroup = groups.firstWhere(
            (g) => g.gid == _selectedGroupGid,
            orElse: () => groups.first,
          );

          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 横向分区选择栏
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant.withAlpha(50),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: groups.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final g = groups[i];
                      final isSelected = g.gid == selectedGroup.gid;
                      return ChoiceChip(
                        label: Text(g.name),
                        selected: isSelected,
                        selectedColor: colorScheme.primaryContainer,
                        labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                        ),
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedGroupGid = g.gid);
                          }
                        },
                      );
                    },
                  ),
                ),

                // 2. 分区简介与版块数量条
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 15,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        selectedGroup.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '共 ${selectedGroup.forums.length} 个版块',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. 版块列表
                Expanded(
                  child: selectedGroup.forums.isEmpty
                      ? EmptyView(
                          icon: selectedGroup.gid == 0 ? Icons.star_border : Icons.forum_outlined,
                          title: selectedGroup.gid == 0 ? '暂无收藏版块' : '暂无版块',
                          subtitle: selectedGroup.gid == 0 ? '点击任意版块卡片右侧的星标即可收藏' : null,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: selectedGroup.forums.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) =>
                              _buildForumCard(ctx, selectedGroup.forums[i]),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFallbackIcon(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.forum_outlined, color: colorScheme.outline, size: 22),
    );
  }

  Widget _buildForumCard(BuildContext context, Forum forum) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFav = _favFids.contains(forum.fid);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withAlpha(60),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadListPage(
                fid: forum.fid,
                title: forum.name,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 版块图标
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: forum.iconUrl != null && forum.iconUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: forum.iconUrl!,
                        cacheManager: KlpbbsCacheManager.instance,
                        httpHeaders: AppConfig.imageHeaders,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildFallbackIcon(colorScheme),
                      )
                    : _buildFallbackIcon(colorScheme),
              ),
              const SizedBox(width: 12),
              // 版块名称与简介
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            forum.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (forum.todayCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '今日 +${forum.todayCount}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (forum.description != null && forum.description!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        forum.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 收藏/进入图标
              IconButton(
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isFav ? const Color(0xFFFFB300) : colorScheme.outline,
                  size: 22,
                ),
                tooltip: isFav ? '已收藏（点击取消）' : '收藏版块',
                onPressed: () => _toggleFav(forum),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: colorScheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
