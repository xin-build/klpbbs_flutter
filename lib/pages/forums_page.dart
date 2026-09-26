import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../core/forum_events.dart';
import '../core/preload_service.dart';
import '../models/forum.dart';
import '../models/server_outage_info.dart';
import '../models/site_stats.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/server_outage_view.dart';
import '../widgets/global_nav.dart';
import '../widgets/horn_banner_widget.dart';
import '../widgets/interactive_animations.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/site_stats_card.dart';
import '../widgets/skeleton_list.dart';
import 'thread_list_page.dart';

/// 社区版块大全 / 版块导航中心
/// 深度对齐 Discuz 移动版原生社区架构（小喇叭 + 全站统计看板 + 全景分区双列网格 + 服务端关注实时同步）
class ForumsPage extends StatefulWidget {
  const ForumsPage({super.key});

  @override
  State<ForumsPage> createState() => _ForumsPageState();
}

class _ForumsPageState extends State<ForumsPage> {
  late Future<(List<ForumGroup>, SiteStats)> _future;
  ServerOutageInfo? _activeOutage;
  bool _viewCacheAnyway = false;
  String _searchQuery = '';
  final Set<int> _favFids = {};
  final Set<int> _collapsedGids = {}; // 记录用户折叠的分区
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    ForumFavoriteNotifier.instance.addListener(_onFavChanged);
    _loadFavs();
    _load();
    _syncServerFavs();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    if (offset > 240 && !_showBackToTop) {
      setState(() => _showBackToTop = true);
    } else if (offset <= 240 && _showBackToTop) {
      setState(() => _showBackToTop = false);
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
  void dispose() {
    _scrollController.dispose();
    ForumFavoriteNotifier.instance.removeListener(_onFavChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onFavChanged() {
    if (!mounted) return;
    _loadFavs();
    _load(forceRefresh: true);
  }

  /// 本地优先加载关注版块
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

  /// 主动与 Discuz 服务端权威关注列表对齐
  Future<void> _syncServerFavs() async {
    try {
      final uid = await KlpbbsApi.getMyUid();
      if (uid != null && uid > 0) {
        final serverFavs = await KlpbbsApi.getFavoriteForums(uid, forceRefresh: true);
        if (mounted && serverFavs.isNotEmpty) {
          final serverFids = serverFavs.map((f) => f.fid).where((f) => f > 0).toSet();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('fav_forums', serverFids.map((f) => '$f').toList());
          setState(() {
            _favFids.clear();
            _favFids.addAll(serverFids);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleFav(Forum forum) async {
    HapticFeedback.lightImpact();
    final isFav = _favFids.contains(forum.fid);
    final nextFav = !isFav;

    // 立即响应 UI，无需等待网络返回，保证极致流畅
    setState(() {
      if (nextFav) {
        _favFids.add(forum.fid);
      } else {
        _favFids.remove(forum.fid);
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList('fav_forums') ?? []).toSet();
    if (nextFav) {
      list.add('${forum.fid}');
    } else {
      list.remove('${forum.fid}');
    }
    await prefs.setStringList('fav_forums', list.toList());

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextFav ? '已关注版块「${forum.name}」' : '已取消关注「${forum.name}」'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // 异步同步至 Discuz 服务端权威源
    if (nextFav) {
      KlpbbsApi.favoriteForum(forum.fid).catchError((_) => (success: false, message: ''));
    } else {
      KlpbbsApi.unfavoriteForum(forum.fid).catchError((_) => (success: false, message: ''));
    }
  }

  void _load({bool forceRefresh = false}) {
    final cachedGroups = PreloadService.instance.get<List<ForumGroup>>('forum_groups', ignoreExpired: true);
    final cachedStats = PreloadService.instance.get<SiteStats>('site_stats', ignoreExpired: true);

    if (!forceRefresh && cachedGroups != null && cachedGroups.isNotEmpty) {
      _future = Future.value((cachedGroups, cachedStats ?? const SiteStats()));
      // 后台静默抓取网络最新数据并同步
      unawaited(() async {
        try {
          final results = await Future.wait([
            KlpbbsApi.getForumGroups(forceRefresh: true),
            KlpbbsApi.getSiteStats(forceRefresh: true),
          ]);
          if (mounted) {
            setState(() {
              _activeOutage = null;
              _future = Future.value((results[0] as List<ForumGroup>, results[1] as SiteStats));
            });
          }
        } catch (e) {
          final outage = ServerOutageInfo.tryParse(e);
          if (outage != null && mounted) {
            setState(() {
              _activeOutage = outage;
            });
          }
        }
      }());
    } else {
      _future = Future.wait([
        KlpbbsApi.getForumGroups(forceRefresh: forceRefresh),
        KlpbbsApi.getSiteStats(forceRefresh: forceRefresh),
      ]).then((results) {
        if (mounted) setState(() => _activeOutage = null);
        return (results[0] as List<ForumGroup>, results[1] as SiteStats);
      });
    }
  }

  void _reload() {
    PreloadService.instance.remove('forum_groups');
    PreloadService.instance.remove('site_stats');
    setState(() {
      _viewCacheAnyway = false;
      _activeOutage = null;
      _load(forceRefresh: true);
      _syncServerFavs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final canPop = Navigator.of(context).canPop();

    // 当遇到 502/服务端故障且用户未选择“强制浏览离线缓存”时，坚决优先全屏展示 502 诊断页（无论之前是否有缓存直出）
    if (_activeOutage != null && !_viewCacheAnyway) {
      final hasCache = PreloadService.instance.has('forum_groups');
      return Scaffold(
        drawer: const GlobalAppDrawer(),
        drawerEdgeDragWidth: 50.0,
        appBar: AppBar(
          automaticallyImplyLeading: !isDesktop,
          leading: (isDesktop && !canPop) ? null : const GlobalNavLeading(),
          leadingWidth: (isDesktop && !canPop) ? null : GlobalNavLeading.preferredLeadingWidth(context),
          title: const Text('社区版块'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新重试',
              onPressed: _reload,
            ),
          ],
        ),
        body: ServerOutageView(
          outage: _activeOutage!,
          onRetry: _reload,
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

    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      appBar: AppBar(
        automaticallyImplyLeading: !isDesktop,
        leading: (isDesktop && !canPop) ? null : const GlobalNavLeading(),
        leadingWidth: (isDesktop && !canPop) ? null : GlobalNavLeading.preferredLeadingWidth(context),
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
                decoration: InputDecoration(
                  hintText: '搜索版块名称或别名...',
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withAlpha(180)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              )
            : const Text('社区版块'),
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
        ],
      ),
      body: FutureBuilder<(List<ForumGroup>, SiteStats)>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              final outage = ServerOutageInfo.tryParse(snapshot.error);
              if (outage != null) {
                final hasCache = PreloadService.instance.has('forum_groups');
                return ServerOutageView(
                  outage: outage,
                  onRetry: _reload,
                  onViewCache: hasCache
                      ? () {
                          final cachedGroups = PreloadService.instance.get<List<ForumGroup>>('forum_groups', ignoreExpired: true);
                          final cachedStats = PreloadService.instance.get<SiteStats>('site_stats', ignoreExpired: true);
                          if (cachedGroups != null && cachedGroups.isNotEmpty) {
                            setState(() {
                              _activeOutage = outage;
                              _viewCacheAnyway = true;
                              _future = Future.value((cachedGroups, cachedStats ?? const SiteStats()));
                            });
                          }
                        }
                      : null,
                  onGoHome: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  },
                );
              }
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
            return const ForumSkeleton();
          }

          final (rawGroups, siteStats) = snapshot.data!;
          if (rawGroups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 48, color: colorScheme.outline),
                    const SizedBox(height: 12),
                    Text('暂无版块数据', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            );
          }

          final forumMap = <int, Forum>{};
          for (final g in rawGroups) {
            for (final f in g.forums) {
              forumMap.putIfAbsent(f.fid, () => f);
            }
          }
          final allForums = forumMap.values.toList();

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

            final crossAxisCount = isDesktop ? 3 : 2;

            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 78,
              ),
              itemCount: matches.length,
              itemBuilder: (ctx, i) => _buildForumCard(ctx, matches[i]),
            );
          }

          // 正常模式：经典社区全景流（小喇叭 -> 全站数据统计栏 -> 我关注的版块 -> 全分区网格）
          final seenFavFids = <int>{};
          final favForums = allForums
              .where((f) => _favFids.contains(f.fid) && seenFavFids.add(f.fid))
              .toList();
          final normalGroups = rawGroups
              .where((g) => g.gid != 0 && !g.name.contains('关注') && !g.name.contains('收藏'))
              .toList();

          return RefreshIndicator(
            onRefresh: () async {
              HapticFeedback.lightImpact();
              _reload();
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: ListView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
              children: [
                if (_activeOutage != null) ...[
                  ServerOutageBanner(
                    outage: _activeOutage!,
                    onRetry: _reload,
                    onViewDetails: () {
                      setState(() => _viewCacheAnyway = false);
                    },
                    onDismiss: () => setState(() => _activeOutage = null),
                  ),
                  const SizedBox(height: 6),
                ],
                // 1. 小喇叭广播区（与手机版截图顶栏完全对齐）
                const HornBannerWidget(),
                const SizedBox(height: 8),

                // 2. 全站统计看板（红圈数据：今日 / 昨日 / 帖子 / 会员）
                SiteStatsCard(stats: siteStats),
                const SizedBox(height: 14),

                // 3. 我关注的版块（如果已有关注版块，置顶展示）
                if (favForums.isNotEmpty) ...[
                  _buildSectionHeader(
                    context,
                    title: '我关注的版块',
                    count: favForums.length,
                    icon: Icons.star_rounded,
                    iconColor: const Color(0xFFFFB300),
                    isCollapsed: _collapsedGids.contains(0),
                    onToggleCollapse: () {
                      setState(() {
                        if (_collapsedGids.contains(0)) {
                          _collapsedGids.remove(0);
                        } else {
                          _collapsedGids.add(0);
                        }
                      });
                    },
                  ),
                  AnimatedCollapseSection(
                    isCollapsed: _collapsedGids.contains(0),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildForumGrid(context, favForums),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 4. 各分区全景列表（综合分区、灵感交流、BE资源分区等）
                for (final group in normalGroups) ...[
                  _buildSectionHeader(
                    context,
                    title: group.name,
                    count: group.forums.length,
                    icon: Icons.grid_view_rounded,
                    iconColor: colorScheme.primary,
                    isCollapsed: _collapsedGids.contains(group.gid),
                    onToggleCollapse: () {
                      setState(() {
                        if (_collapsedGids.contains(group.gid)) {
                          _collapsedGids.remove(group.gid);
                        } else {
                          _collapsedGids.add(group.gid);
                        }
                      });
                    },
                  ),
                  AnimatedCollapseSection(
                    isCollapsed: _collapsedGids.contains(group.gid),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildForumGrid(context, group.forums),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: ScrollDirectionAwareFab(
        isVisible: _showBackToTop,
        child: isDesktop
            ? FloatingActionButton.extended(
                key: const ValueKey('forums_back_to_top_btn'),
                tooltip: '回到顶部',
                elevation: 4,
                onPressed: _scrollToTop,
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                label: const Text(
                  '回到顶部',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              )
            : FloatingActionButton.small(
                key: const ValueKey('forums_back_to_top_btn'),
                tooltip: '回到顶部',
                elevation: 3,
                onPressed: _scrollToTop,
                child: const Icon(Icons.arrow_upward_rounded),
              ),
      ),
    );
  }

  /// 分区头部条（分区名、版块数、折叠/展开开关）
  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required int count,
    required IconData icon,
    required Color iconColor,
    required bool isCollapsed,
    required VoidCallback onToggleCollapse,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressScaleEffect(
      scaleDown: 0.985,
      enableHaptic: true,
      onTap: onToggleCollapse,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(140),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.outline,
                ),
              ),
            ),
            const Spacer(),
            // 现代极简折叠切换开关/箭头（丝滑旋转动效）
            AnimatedExpandArrow(
              isCollapsed: isCollapsed,
              color: colorScheme.onSurfaceVariant.withAlpha(160),
            ),
          ],
        ),
      ),
    );
  }

  /// 分区版块对称网格（手机端双列，宽屏 3~4 列，带弹性微动效与错峰入场）
  Widget _buildForumGrid(BuildContext context, List<Forum> forums) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final isLargeScreen = MediaQuery.of(context).size.width > 1100;
    final crossAxisCount = isLargeScreen ? 4 : (isDesktop ? 3 : 2);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 78,
      ),
      itemCount: forums.length,
      itemBuilder: (ctx, i) => ScrollAwareSpringEntrance(
        index: i,
        child: _buildForumCard(ctx, forums[i]),
      ),
    );
  }

  /// 高保真版块卡片（按压微缩放、PC悬停微浮起、星标弹跳动效、高清图标、名称、今日帖数、右上角橙色角标）
  Widget _buildForumCard(BuildContext context, Forum forum) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFav = _favFids.contains(forum.fid);

    return HoverScaleElevationEffect(
      child: PressScaleEffect(
        scaleDown: 0.968,
        enableHaptic: true,
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
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(50),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(theme.brightness == Brightness.dark ? 20 : 6),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 200),
                            errorWidget: (_, __, ___) => _buildFallbackIcon(colorScheme),
                          )
                        : _buildFallbackIcon(colorScheme),
                  ),
                  const SizedBox(width: 10),
                  // 版块标题与指标
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 28), // 避开右上角 badge
                          child: Text(
                            forum.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (forum.todayCount > 0)
                          Text(
                            '今日: ${forum.todayCount}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF8F00),
                            ),
                          )
                        else if (forum.threadCount > 0)
                          Text(
                            '帖数: ${forum.threadCount}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.outline,
                            ),
                          )
                        else if (forum.description != null && forum.description!.isNotEmpty)
                          Text(
                            forum.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.outline,
                            ),
                          )
                        else
                          Text(
                            '点击进入版块',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 关注星标（带弹跳微动效）
                  BouncingIcon(
                    isTriggered: isFav,
                    size: 20,
                    tooltip: isFav ? '已关注（点击取消）' : '关注版块',
                    activeIcon: const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 20),
                    inactiveIcon: Icon(Icons.star_border_rounded, color: colorScheme.onSurfaceVariant.withAlpha(120), size: 20),
                    onTap: () => _toggleFav(forum),
                  ),
                ],
              ),
            ),

              // 右上角橙色今日角标（对齐克米手机版 BE地图等角标样式）
              if (forum.todayCount > 0)
                Positioned(
                  top: 6,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8F00),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${forum.todayCount}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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

  Widget _buildFallbackIcon(ColorScheme colorScheme) {
    return Container(
      width: 40,
      height: 40,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.forum_outlined, color: colorScheme.outline, size: 20),
    );
  }
}
