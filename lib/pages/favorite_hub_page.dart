import '../widgets/app_motion.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../core/dio_client.dart';
import '../core/forum_events.dart';
import '../models/forum.dart';
import '../models/server_outage_info.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/server_outage_view.dart';
import 'forums_page.dart';
import 'thread_list_page.dart';
import 'user_threads_page.dart';

/// 统一的「我的收藏与关注」中心
/// 深度同步 Discuz 服务端权威数据，双选项卡同时聚合【收藏的主题】与【关注的版块】
class FavoriteHubPage extends StatefulWidget {
  final int uid;
  final int initialIndex;

  const FavoriteHubPage({
    super.key,
    required this.uid,
    this.initialIndex = 0,
  });

  @override
  State<FavoriteHubPage> createState() => _FavoriteHubPageState();
}

class _FavoriteHubPageState extends State<FavoriteHubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final String _ownerSession;

  @override
  void initState() {
    super.initState();
    _ownerSession = DioClient.sessionKey;
    DioClient.sessionChanges.addListener(_sessionChanged);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_sessionChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      appBar: AppBar(
        automaticallyImplyLeading: !isDesktop,
        leading: (isDesktop && !canPop) ? null : const GlobalNavLeading(),
        leadingWidth: (isDesktop && !canPop)
            ? null
            : GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('我的收藏'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.article_outlined, size: 20),
                    text: '收藏的主题',
                  ),
                  Tab(
                    icon: Icon(Icons.star_rounded, size: 20),
                    text: '关注的版块',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _ownerSession != DioClient.sessionKey
          ? const Center(child: Text('账号已切换，请从个人中心重新打开我的收藏'))
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: 收藏的主题（支持标签筛选、分页、即时取消、与服务端对齐）
                UserThreadsPage(
                  uid: widget.uid,
                  type: 'favorite',
                  title: '收藏的主题',
                  showAppBar: false,
                ),

                // Tab 2: 关注的版块（直连 Discuz 原生收藏接口与版块事件监听）
                _FavoriteForumsView(uid: widget.uid),
              ],
            ),
    );
  }
}

/// 关注版块专属视图
class _FavoriteForumsView extends StatefulWidget {
  final int uid;

  const _FavoriteForumsView({required this.uid});

  @override
  State<_FavoriteForumsView> createState() => _FavoriteForumsViewState();
}

class _FavoriteForumsViewState extends State<_FavoriteForumsView>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Forum>> _future;
  final Set<int> _busy = {};
  List<Forum>? _loaded;
  String? _refreshError;
  late String _dataSession;
  int _loadGeneration = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _dataSession = DioClient.sessionKey;
    ForumFavoriteNotifier.instance.addListener(_onFavChanged);
    DioClient.sessionChanges.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    ForumFavoriteNotifier.instance.removeListener(_onFavChanged);
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onFavChanged() {
    if (!mounted) return;
    _load(forceRefresh: true);
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _dataSession = DioClient.sessionKey;
    _loaded = null;
    _busy.clear();
    _load();
  }

  void _load({bool forceRefresh = false}) {
    setState(() {
      final generation = ++_loadGeneration, session = DioClient.sessionKey;
      _refreshError = null;
      _future =
          KlpbbsApi.getFavoriteForums(widget.uid, forceRefresh: forceRefresh)
              .then((data) {
        if (mounted &&
            generation == _loadGeneration &&
            session == DioClient.sessionKey) {
          _loaded = data;
        }
        return data;
      }, onError: (Object error, StackTrace stack) {
        if (mounted &&
            generation == _loadGeneration &&
            session == DioClient.sessionKey &&
            _loaded != null) {
          _refreshError = '刷新失败，已保留上次关注版块';
          return _loaded!;
        }
        Error.throwWithStackTrace(error, stack);
      });
      _future.ignore();
    });
  }

  Future<void> _unfavorite(Forum forum) async {
    final session = DioClient.sessionKey;
    if (_dataSession != session) return;
    if (!_busy.add(forum.fid)) return;
    HapticFeedback.lightImpact();
    try {
      final uid = await KlpbbsApi.getMyUid();
      if (!mounted || session != DioClient.sessionKey || uid != widget.uid) {
        return;
      }
      final res =
          await KlpbbsApi.unfavoriteForum(forum.fid, favid: forum.favid);
      if (mounted && session == DioClient.sessionKey) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (res.success) _load(forceRefresh: true);
      }
    } finally {
      _busy.remove(forum.fid);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedback.lightImpact();
        _load(forceRefresh: true);
        await _future.catchError((_) => <Forum>[]);
      },
      child: FutureBuilder<List<Forum>>(
        key: ValueKey('favorite-forums:${widget.uid}:$_dataSession'),
        initialData: _loaded,
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const Center(child: AppLoadingIndicator());
          }
          if (snap.hasError) {
            final outage = ServerOutageInfo.tryParse(snap.error);
            if (outage != null) {
              return ServerOutageView(
                outage: outage,
                onRetry: () => _load(forceRefresh: true),
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
                    Text('关注版块加载失败', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '${snap.error}',
                      style:
                          TextStyle(fontSize: 12, color: colorScheme.outline),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => _load(forceRefresh: true),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }

          final list = snap.data ?? [];
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_border_rounded,
                        size: 56, color: colorScheme.outline),
                    const SizedBox(height: 12),
                    Text('暂无关注的版块', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '在版块大全或版块详情内点击星标即可关注，随时掌握版块最新动向',
                      style:
                          TextStyle(fontSize: 13, color: colorScheme.outline),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.explore_outlined, size: 18),
                      label: const Text('前往版块大全'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ForumsPage()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(children: [
            if (snap.connectionState != ConnectionState.done)
              const AppLoadingBar(),
            if (_refreshError != null)
              MaterialBanner(content: Text(_refreshError!), actions: [
                TextButton(
                    onPressed: () => _load(forceRefresh: true),
                    child: const Text('重试')),
              ]),
            Expanded(
                child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        MediaQuery.textScalerOf(context).scale(14) > 20
                            ? (isDesktop ? 2 : 1)
                            : (isDesktop ? 3 : 2),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent:
                        (MediaQuery.textScalerOf(context).scale(14) * 1.45 +
                                MediaQuery.textScalerOf(context).scale(11) * 3 +
                                30)
                            .clamp(86.0, 240.0),
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final f = list[i];
                    return _buildForumCard(context, f);
                  },
                ),
              ),
            )),
          ]);
        },
      ),
    );
  }

  Widget _buildForumCard(BuildContext context, Forum forum) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final counters = <(String, bool)>[
      if (forum.topicCount >= 0) ('主题 ${forum.displayCount('topics')}', false),
      if (forum.threadCount >= 0) ('帖数 ${forum.displayCount('posts')}', false),
      if (forum.todayCount >= 0) ('今日 ${forum.displayCount('today')}', true),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(50),
          width: 0.8,
        ),
      ),
      child: Material(
        color: Colors.transparent,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // 版块高清图标
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: forum.iconUrl != null && forum.iconUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: forum.iconUrl!,
                          cacheKey: KlpbbsCacheManager.normalizeCacheKey(
                              forum.iconUrl!),
                          cacheManager: KlpbbsCacheManager.instance,
                          httpHeaders: AppConfig.imageHeaders,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _buildFallbackIcon(colorScheme),
                        )
                      : _buildFallbackIcon(colorScheme),
                ),
                const SizedBox(width: 10),
                // 版块信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        forum.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (counters.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          children: [
                            for (final (label, daily) in counters)
                              Text(label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: daily ? FontWeight.w600 : null,
                                    color: daily
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  )),
                          ],
                        )
                      else if (forum.description != null &&
                          forum.description!.isNotEmpty)
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
                // 取消关注星标
                IconButton(
                  icon: const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFFFB300),
                    size: 22,
                  ),
                  tooltip: '取消关注',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _unfavorite(forum),
                ),
              ],
            ),
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
