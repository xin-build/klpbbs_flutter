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
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          final groups = rawGroups.isNotEmpty ? rawGroups : SeedData.forumGroups;

          // 搜索模式：跨所有分区检索匹配的版块
          if (_searchQuery.isNotEmpty) {
            final allForums = groups.expand((g) => g.forums).toList();
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
                      ? const EmptyView(
                          icon: Icons.forum_outlined,
                          title: '暂无版块',
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
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: (forum.iconUrl != null && forum.iconUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: forum.iconUrl!,
                          cacheManager: KlpbbsCacheManager.instance,
                          httpHeaders: AppConfig.imageHeaders,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.forum_outlined,
                              color: colorScheme.outline,
                              size: 22,
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.forum_outlined,
                              color: colorScheme.outline,
                              size: 22,
                            ),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.forum_outlined,
                            color: colorScheme.primary,
                            size: 22,
                          ),
                        ),
                ),
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
                  isFav ? Icons.star : Icons.star_border,
                  color: isFav ? const Color(0xFFFFB300) : colorScheme.outline,
                  size: 20,
                ),
                tooltip: isFav ? '已收藏' : '收藏版块',
                onPressed: () {
                  setState(() {
                    if (isFav) {
                      _favFids.remove(forum.fid);
                    } else {
                      _favFids.add(forum.fid);
                    }
                  });
                },
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
