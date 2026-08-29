import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/comiis_parser.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/preload_service.dart';
import '../core/seed_data.dart';
import '../models/forum.dart';
import '../models/site_stats.dart';
import '../models/thread_summary.dart';
import '../widgets/desktop_shortcuts.dart';
import '../widgets/horn_banner_widget.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/retry_image.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/thread_card.dart';
import '../widgets/tuhao_banner_widget.dart';
import '../services/auto_sign_service.dart';
import '../services/push_notification_service.dart';
import 'credit_page.dart';
import 'darkroom_page.dart';
import 'forums_page.dart';
import 'guide_page.dart';
import 'login_page.dart';
import 'magic_page.dart';
import 'medal_page.dart';
import 'notice_page.dart';
import 'pm_inbox_page.dart';
import 'ranklist_page.dart';
import 'search_page.dart';
import 'thread_detail_page.dart';
import 'thread_list_page.dart';
import 'user_space_page.dart';

/// 首页：版块导航 + 推荐帖子
class HomePage extends StatefulWidget {
  /// 底部导航切换回调（由主壳提供）
  final ValueChanged<int>? onSwitchTab;

  /// 打开设置页回调
  final VoidCallback? onOpenSettings;

  /// 侧边栏模式显示菜单按钮（打开主 Drawer）
  final bool showDrawerButton;
  final VoidCallback? onOpenDrawer;

  const HomePage({
    super.key,
    this.onSwitchTab,
    this.onOpenSettings,
    this.showDrawerButton = false,
    this.onOpenDrawer,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<(List<ForumGroup>, List<ThreadSummary>, SiteStats)> _future;
  final _homeScrollCtrl = ScrollController();
  int _unreadPm = 0;
  int _unreadNotice = 0;
  Set<int> _favForums = {};
  List<ThreadSummary> _more = [];
  int _morePage = 1;
  bool _loadingMore = false;
  List<ThreadSummary> _memoizedAllThreads = [];
  List<ThreadSummary>? _lastInitialThreads;
  int _lastMoreLength = -1;
  bool _showBackToTop = false;
  ValueChanged<int>? get _onSwitchTab => widget.onSwitchTab;

  @override
  void initState() {
    super.initState();
    _homeScrollCtrl.addListener(_onHomeScroll);
    PushNotificationService.instance.addListener(_onPushNotificationUpdate);
    ComiisParser.loadTidForumCache();
    _future = _load();
    _loadFavForums();
    if ((AppConfig.autoCheckin || AutoSignService.instance.autoSignOnLaunch) && DioClient.isLoggedIn) {
      AutoSignService.instance.checkAndAutoSignIn(triggerSource: '首页启动自动打卡');
    }
  }

  void _onPushNotificationUpdate() {
    if (mounted) {
      setState(() {
        _unreadNotice = PushNotificationService.instance.unreadCount;
      });
    }
  }

  Future<void> _loadFavForums() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
      () => _favForums = (prefs.getStringList('fav_forums') ?? const [])
          .map(int.parse)
          .toSet(),
    );
  }

  /// 切换版块收藏（本地持久化并同步原站）
  Future<void> _toggleFavForum(Forum f) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList('fav_forums') ?? []).toSet();
    final isFav = _favForums.contains(f.fid);
    if (isFav) {
      list.remove('${f.fid}');
      _favForums.remove(f.fid);
      KlpbbsApi.unfavoriteForum(f.fid).catchError((_) => (success: false, message: ''));
    } else {
      list.add('${f.fid}');
      _favForums.add(f.fid);
      KlpbbsApi.favoriteForum(f.fid).catchError((_) => (success: false, message: ''));
    }
    await prefs.setStringList('fav_forums', list.toList());
    if (mounted) setState(() {});
  }

  Future<(List<ForumGroup>, List<ThreadSummary>, SiteStats)> _load({bool forceRefresh = false}) async {
    final cachedGroups = PreloadService.instance.get<List<ForumGroup>>('forum_groups', ignoreExpired: true);
    final cachedThreads = PreloadService.instance.get<List<ThreadSummary>>('home_threads', ignoreExpired: true);
    final cachedStats = PreloadService.instance.get<SiteStats>('site_stats', ignoreExpired: true);

    if (!forceRefresh && cachedGroups != null && cachedThreads != null) {
      // 命中本地缓存直接 0ms 秒开呈现，并在后台静默拉取网络最新数据
      unawaited(() async {
        try {
          final results = await Future.wait([
            KlpbbsApi.getForumGroups(),
            KlpbbsApi.getHome(),
            KlpbbsApi.getSiteStats(forceRefresh: false),
          ]);
          _loadUnread();
          if (mounted) {
            final freshGroups = results[0] as List<ForumGroup>;
            final freshThreads = results[1] as List<ThreadSummary>;
            final freshStats = results[2] as SiteStats;
            setState(() {
              _future = Future.value((freshGroups, freshThreads, freshStats));
            });
          }
        } catch (_) {}
      }());
      _loadUnread();
      return (
        cachedGroups,
        cachedThreads,
        cachedStats ?? const SiteStats(
          todayPosts: 61,
          yesterdayPosts: 273,
          totalPosts: 10310794,
          totalMembers: 2317632,
        ),
      );
    }

    try {
      final results = await Future.wait([
        KlpbbsApi.getForumGroups(),
        KlpbbsApi.getHome(),
        KlpbbsApi.getSiteStats(forceRefresh: forceRefresh),
      ]);
      _loadUnread();
      final groups = results[0] as List<ForumGroup>;
      final threads = results[1] as List<ThreadSummary>;
      final stats = results[2] as SiteStats;

      // 自动合并服务端已关注的版块到 _favForums（只合并不误删）
      bool hasNew = false;
      for (final g in groups) {
        if (g.gid == 0 || g.name.contains('关注') || g.name.contains('收藏')) {
          for (final f in g.forums) {
            if (_favForums.add(f.fid)) hasNew = true;
          }
        }
      }
      if (hasNew) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setStringList('fav_forums', _favForums.map((e) => '$e').toList());
        }).catchError((_) {});
      }

      if (groups.isEmpty && threads.isEmpty) {
        throw Exception('暂未获取到内容，请检查网络或点击重试');
      }
      return (groups, threads, stats);
    } catch (e) {
      if (cachedGroups != null || cachedThreads != null) {
        return (
          cachedGroups ?? SeedData.forumGroups,
          cachedThreads ?? SeedData.homeThreads,
          cachedStats ?? const SiteStats(
            todayPosts: 61,
            yesterdayPosts: 273,
            totalPosts: 10310794,
            totalMembers: 2317632,
          ),
        );
      }
      rethrow;
    }
  }

  void _reload() {
    PreloadService.instance.remove('home_threads');
    PreloadService.instance.remove('forum_groups');
    PreloadService.instance.remove('site_stats');
    setState(() {
      _more = [];
      _morePage = 1;
      _future = _load(forceRefresh: true);
    });
  }

  /// 统计私信未读会话数与通知未读红点（本地已读记录过滤与服务端状态比对）
  Future<void> _loadUnread() async {
    try {
      // 检查未读通知与私信
      if (!DioClient.isLoggedIn) {
        if (mounted) setState(() { _unreadPm = 0; _unreadNotice = 0; });
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final read = (prefs.getStringList('pm_read') ?? const [])
          .map(int.parse)
          .toSet();
      final unreadOverride = (prefs.getStringList('pm_unread_override') ?? const [])
          .map(int.parse)
          .toSet();
      final list = await KlpbbsApi.getPmList();
      final unread = list
          .where((c) => (c.isNew && !read.contains(c.touid)) || unreadOverride.contains(c.touid))
          .length;
      if (mounted) setState(() => _unreadPm = unread);

      // 通知未读：严格遵循 Discuz 服务端真实未读数与角标
      final summary = await KlpbbsApi.getUnreadSummary();
      if (mounted) setState(() => _unreadNotice = summary.unreadNotices);
    } catch (_) {}
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    _loadingMore = true;
    try {
      final nextPage = _morePage + 1;
      var next = await KlpbbsApi.getGuide('newthread', page: nextPage);
      if (next.isEmpty) {
        next = await KlpbbsApi.getGuide('digest', page: nextPage);
      }
      if (next.isEmpty) {
        next = await KlpbbsApi.getThreadList(2, page: nextPage);
      }
      if (!mounted) return;
      if (next.isNotEmpty) {
        _morePage = nextPage;
        _more.addAll(next);
        _memoizedAllThreads = _dedupeThreads([..._lastInitialThreads ?? const [], ..._more]);
        _lastMoreLength = _more.length;
        setState(() {});
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      } else {
        _loadingMore = false;
      }
    }
  }

  @override
  void dispose() {
    _homeScrollCtrl.dispose();
    PushNotificationService.instance.removeListener(_onPushNotificationUpdate);
    super.dispose();
  }

  /// 提前 600px 后台静默预加载更多，并管理回到顶部悬浮按钮显示状态
  void _onHomeScroll() {
    if (!_homeScrollCtrl.hasClients) return;
    final pos = _homeScrollCtrl.position;
    if (pos.pixels > 380 && !_showBackToTop) {
      setState(() => _showBackToTop = true);
    } else if (pos.pixels <= 380 && _showBackToTop) {
      setState(() => _showBackToTop = false);
    }
    if (!_loadingMore && pos.pixels >= pos.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  void _scrollToTop() {
    HapticFeedback.lightImpact();
    _homeScrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openNotifications() async {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    setState(() => _unreadNotice = 0);
    try {
      final prefs = await SharedPreferences.getInstance();
      final notices = await KlpbbsApi.getNotices('mypost');
      if (notices.isNotEmpty) {
        final top = notices.first;
        await prefs.setString(
          'notice_last_read_key',
          '${top.tid}_${top.pid}_${top.timeText}',
        );
      }
    } catch (_) {}
    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NoticePage()),
      );
    }
  }

  void _openPmInbox() {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PmInboxPage()),
    );
  }

  Future<void> _openAccountMenu() async {
    if (DioClient.isLoggedIn) {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle),
                title: const Text('我的空间'),
                onTap: () => Navigator.of(ctx).pop('space'),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('积分中心'),
                onTap: () => Navigator.of(ctx).pop('credit'),
              ),
              ListTile(
                leading: const Icon(Icons.military_tech_outlined),
                title: const Text('勋章中心'),
                onTap: () => Navigator.of(ctx).pop('medal'),
              ),
              ListTile(
                leading: const Icon(Icons.auto_fix_high_outlined),
                title: const Text('道具中心'),
                onTap: () => Navigator.of(ctx).pop('magic'),
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('私信收件箱'),
                trailing: _unreadPm > 0
                    ? Badge.count(count: _unreadPm)
                    : null,
                onTap: () => Navigator.of(ctx).pop('pm'),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('通知'),
                onTap: () => Navigator.of(ctx).pop('notice'),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
                onTap: () => Navigator.of(ctx).pop('settings'),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('退出登录'),
                onTap: () => Navigator.of(ctx).pop('logout'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (action == 'space') {
        final uid = await KlpbbsApi.getMyUid() ?? 1;
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserSpacePage(uid: uid)),
        );
      } else if (action == 'credit') {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 0)),
        );
      } else if (action == 'medal') {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MedalPage()),
        );
      } else if (action == 'magic') {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MagicPage()),
        );
      } else if (action == 'pm') {
        _openPmInbox();
      } else if (action == 'notice') {
        _openNotifications();
      } else if (action == 'settings') {
        widget.onOpenSettings?.call();
      } else if (action == 'logout') {
        final ok = await KlpbbsApi.logout();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok ? '已退出登录' : '退出失败')),
          );
          _reload();
        }
      }
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);

    return DesktopShortcutsWrapper(
      onRefresh: _reload,
      onSearch: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SearchPage())),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '苦力怕论坛',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          automaticallyImplyLeading: !isDesktop,
          leading: (!isDesktop && widget.showDrawerButton)
              ? IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: '打开导航菜单',
                  onPressed: widget.onOpenDrawer,
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '手动刷新',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              onPressed: () {
                HapticFeedback.lightImpact();
                _reload();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已刷新首页内容'),
                    duration: Duration(milliseconds: 1500),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索 (Ctrl+F)',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SearchPage()));
              },
            ),
            Badge(
              isLabelVisible: _unreadNotice > 0,
              label: Text(
                '$_unreadNotice',
                style: const TextStyle(fontSize: 10),
              ),
              child: IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: '通知',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                onPressed: _openNotifications,
              ),
            ),
            if (isDesktop)
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '设置',
                onPressed: widget.onOpenSettings,
              ),
            Badge(
              isLabelVisible: _unreadPm > 0,
              label: Text('$_unreadPm', style: const TextStyle(fontSize: 10)),
              child: IconButton(
                icon: const Icon(Icons.mail_outline),
                tooltip: '私信收件箱',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                onPressed: _openPmInbox,
              ),
            ),
            IconButton(
              icon: Icon(
                DioClient.isLoggedIn ? Icons.account_circle : Icons.login,
              ),
              tooltip: DioClient.isLoggedIn ? '我的空间' : '登录',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              onPressed: _openAccountMenu,
            ),
          ],
        ),
        body: FutureBuilder(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              if (snap.hasError) {
                return _ErrorView(error: '${snap.error}', onRetry: _reload);
              }
              // 列表骨架屏
              return const SkeletonList(itemCount: 8);
            }
            final (groups, threads, stats) = snap.data!;
            final messenger = ScaffoldMessenger.of(context);
            final allThreads = _getDisplayThreads(threads);
            final isDesktop = ResponsiveBreakpoints.isDesktop(context);

            return RefreshIndicator(
              onRefresh: () async {
                HapticFeedback.lightImpact();
                _reload();
                await Future.delayed(const Duration(milliseconds: 400));
                if (mounted) {
                  final now = DateTime.now();
                  final hm =
                      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                  messenger.showSnackBar(SnackBar(content: Text('已刷新 $hm')));
                }
              },
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.surface,
              displacement: 40,
              edgeOffset: 8,
              child: SafeArea(
                top: false,
                left: true,
                right: true,
                bottom: true,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: CustomScrollView(
                    controller: _homeScrollCtrl,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // 社区顶部土豪霸屏与全站数据统计栏（实时动态刷新）
                      SliverToBoxAdapter(child: TuhaoBannerWidget(stats: stats)),
                      // 小喇叭广播跑马灯
                      const SliverToBoxAdapter(child: HornBannerWidget()),
                      if (groups.isNotEmpty)
                        SliverToBoxAdapter(
                          child: ForumNav(
                            groups: groups,
                            favFids: _favForums,
                            onToggleFav: _toggleFavForum,
                          ),
                        )
                      else
                        // 空态
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.forum_outlined,
                                    size: 40,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '暂无版块',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // 快捷入口：仅在移动端展示（桌面端已有左侧侧边栏导航）
                      if (!isDesktop)
                        SliverToBoxAdapter(
                          child: QuickActionsWidget(onNavigate: _onNavigateTab),
                        ),
                      // 推荐分区头
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '推荐',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '下拉刷新',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(180),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 推荐轮播（前 5 篇，移动端展示）
                      if (threads.isNotEmpty && !isDesktop)
                        SliverToBoxAdapter(
                          child: _RecommendCarousel(
                            threads: threads.take(5).toList(),
                            onTap: _openThread,
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 6)),
                      // 帖子列表（LAZY 动态虚拟列表构建，仅在滚动进入视口时实例化，彻底消除卡顿）
                      if (isDesktop)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 520,
                                  mainAxisExtent: 138,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                ),
                            itemCount: allThreads.length,
                            itemBuilder: (ctx, i) {
                              final t = allThreads[i];
                              return RepaintBoundary(
                                child: ThreadCard(
                                  thread: t,
                                  isGrid: true,
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
                              );
                            },
                          ),
                        )
                      else
                        SliverList.builder(
                          itemCount: allThreads.length,
                          itemBuilder: (ctx, i) {
                            final t = allThreads[i];
                            return RepaintBoundary(
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
                            );
                          },
                        ),
                      // 加载更多
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: _loadingMore
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : FilledButton.tonal(
                                    onPressed: _loadMore,
                                    child: const Text('加载更多推荐'),
                                  ),
                          ),
                        ),
                      ),
                      // 给右下角发帖与回到顶部 FAB 预留空间，避免遮挡最后一张卡片
                      const SliverToBoxAdapter(child: SizedBox(height: 96)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
        floatingActionButton: _showBackToTop
            ? FloatingActionButton.small(
                key: const ValueKey('home_back_to_top_btn'),
                tooltip: '回到顶部',
                elevation: 3,
                onPressed: _scrollToTop,
                child: const Icon(Icons.arrow_upward_rounded),
              )
            : null,
      ),
    );
  }

  /// 缓存与防抖首页推荐合并列表，避免在滑动或 rebuild 期间频繁执行重复计算
  List<ThreadSummary> _getDisplayThreads(List<ThreadSummary> initialThreads) {
    if (identical(_lastInitialThreads, initialThreads) &&
        _lastMoreLength == _more.length) {
      return _memoizedAllThreads;
    }
    _lastInitialThreads = initialThreads;
    _lastMoreLength = _more.length;
    _memoizedAllThreads = _dedupeThreads([...initialThreads, ..._more]);
    return _memoizedAllThreads;
  }

  /// 按 tid 去重（跨首页推荐与加载更多来源，并保证每个帖子均具备准确版块标识）
  List<ThreadSummary> _dedupeThreads(List<ThreadSummary> list) {
    final seen = <int>{};
    return [
      for (final t in list)
        if (seen.add(t.tid))
          t.copyWith(
            forumName: ComiisParser.resolveForumName(
              tid: t.tid,
              fid: t.fid,
              rawForumName: t.forumName,
              title: t.title,
              typeName: t.typeName,
            ),
          ),
    ];
  }

  void _openThread(int tid) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: tid)));
  }

  /// 切换到底部导航对应 tab（由主壳提供）或跳转对应路由
  void _onNavigateTab(int index) {
    if (index == 10) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const GuidePage()));
      return;
    }
    if (index == 11) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SearchPage()));
      return;
    }
    if (index == 12) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const DarkroomPage()));
      return;
    }
    if (index == 13) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const RanklistPage()));
      return;
    }
    if (index == 14) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PmInboxPage()));
      return;
    }
    if (_onSwitchTab != null) _onSwitchTab!(index);
  }
}

/// 版块导航（横向滚动）
class ForumNav extends StatefulWidget {
  final List<ForumGroup> groups;
  final Set<int> favFids;
  final ValueChanged<Forum>? onToggleFav;

  const ForumNav({
    super.key,
    required this.groups,
    this.favFids = const {},
    this.onToggleFav,
  });

  /// 展平后的全部版块（收藏弹层/检索用）
  List<Forum> get allForums => groups.expand((g) => g.forums).toList();

  /// 按版块名匹配图标颜色
  static Color forumIconColor(String name) {
    if (name.contains('资源') || name.contains('下载') || name.contains('整合')) {
      return const Color(0xFF43A047);
    }
    if (name.contains('求助') || name.contains('问答') || name.contains('问题')) {
      return const Color(0xFFFB8C00);
    }
    if (name.contains('讨论') || name.contains('交流') || name.contains('闲聊')) {
      return const Color(0xFF1E88E5);
    }
    if (name.contains('公告') || name.contains('版务')) {
      return const Color(0xFF8E24AA);
    }
    if (name.contains('作品') || name.contains('创作')) {
      return const Color(0xFFE53935);
    }
    if (name.contains('交易') || name.contains('市场')) {
      return const Color(0xFF00897B);
    }
    return const Color(0xFF1E88E5);
  }

  /// 按版块名匹配图标
  static IconData forumIcon(String name) {
    if (name.contains('资源') || name.contains('下载') || name.contains('整合')) {
      return Icons.download_outlined;
    }
    if (name.contains('求助') || name.contains('问答') || name.contains('问题')) {
      return Icons.help_outline;
    }
    if (name.contains('讨论') || name.contains('交流') || name.contains('闲聊')) {
      return Icons.forum_outlined;
    }
    if (name.contains('公告') || name.contains('版务')) {
      return Icons.campaign_outlined;
    }
    if (name.contains('新闻') || name.contains('资讯')) {
      return Icons.article_outlined;
    }
    if (name.contains('作品') || name.contains('展示') || name.contains('创作')) {
      return Icons.brush_outlined;
    }
    if (name.contains('交易') || name.contains('市场')) {
      return Icons.shopping_cart_outlined;
    }
    return Icons.forum_outlined;
  }

  @override
  State<ForumNav> createState() => _ForumNavState();
}

class _ForumNavState extends State<ForumNav> {
  int _selectedGroupIdx = 0;
  bool _expandAll = false;

  void _showFavForums(BuildContext context) {
    final favList = widget.allForums
        .where((f) => widget.favFids.contains(f.fid))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _FavForumsSheet(
        forums: favList,
        onToggleFav: widget.onToggleFav,
        onOpen: (f) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadListPage(fid: f.fid, title: f.name),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.groups.isEmpty) return const SizedBox.shrink();

    final allKnownForums = <int, Forum>{};
    for (final g in widget.groups) {
      for (final f in g.forums) {
        allKnownForums[f.fid] = f;
      }
    }
    for (final f in widget.allForums) {
      allKnownForums[f.fid] = f;
    }
    for (final g in SeedData.forumGroups) {
      for (final f in g.forums) {
        allKnownForums.putIfAbsent(f.fid, () => f);
      }
    }

    final combinedFavs = <Forum>[];
    final seenFids = <int>{};
    for (final fid in widget.favFids) {
      if (seenFids.add(fid)) {
        final f = allKnownForums[fid] ?? Forum(fid: fid, name: '版块 $fid');
        combinedFavs.add(f);
      }
    }
    for (final g in widget.groups) {
      if (g.gid == 0 || g.name.contains('关注')) {
        for (final f in g.forums) {
          if (seenFids.add(f.fid)) {
            combinedFavs.add(f);
          }
        }
      }
    }
    if (combinedFavs.isEmpty) {
      const defaultFids = [41, 43, 52];
      for (final fid in defaultFids) {
        if (seenFids.add(fid)) {
          final f = allKnownForums[fid] ?? Forum(fid: fid, name: '版块 $fid');
          combinedFavs.add(f);
        }
      }
    }

    final effectiveGroups = <ForumGroup>[
      ForumGroup(
        gid: 0,
        name: '我关注的',
        forums: combinedFavs,
      ),
    ];

    for (final g in widget.groups) {
      if (g.gid != 0 && !g.name.contains('关注')) {
        effectiveGroups.add(g);
      }
    }

    final currentGroup = effectiveGroups[_selectedGroupIdx.clamp(0, effectiveGroups.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分区标题栏：标题 + 展开/折叠切换 + 收藏 + 全部分区
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
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
              const Text(
                '论坛版块分类',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _expandAll = !_expandAll),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expandAll ? '收起分类' : '展开全部分区',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Icon(
                        _expandAll ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (widget.favFids.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => _showFavForums(context),
                  child: Row(
                    children: [
                      const Icon(Icons.star, size: 15, color: Color(0xFFFFB300)),
                      const SizedBox(width: 2),
                      Text(
                        '收藏 ${widget.favFids.length}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ForumsPage()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        '全部分区',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 分区分类 Tab 栏（如果未展开全部时显示）
        if (!_expandAll) ...[
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: effectiveGroups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final g = effectiveGroups[i];
                final isSelected = i == _selectedGroupIdx;
                return ChoiceChip(
                  label: Text(g.name),
                  selected: isSelected,
                  selectedColor: colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  ),
                  visualDensity: VisualDensity.compact,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedGroupIdx = i);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // 当前选中分区的版块网格（全宽双列自适应网格，彻底消除孤立留白）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth > 600;
                final crossCount = isWide ? 4 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: currentGroup.forums.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    mainAxisExtent: 52,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (ctx, idx) => _boardChip(context, currentGroup.forums[idx]),
                );
              },
            ),
          ),
        ] else ...[
          // 展开全部分区手风琴
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                for (final g in effectiveGroups)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: _CollapsibleGroup(
                      group: g,
                      initiallyExpanded: true,
                      favFids: widget.favFids,
                      onToggleFav: widget.onToggleFav,
                      boardChip: _boardChip,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _boardChip(BuildContext context, Forum f) {
    final theme = Theme.of(context);
    final fav = widget.favFids.contains(f.fid);
    final seed = SeedData.forumGroups
        .expand((g) => g.forums)
        .firstWhere((s) => s.fid == f.fid, orElse: () => f);
    final threadCount = f.threadCount > 0 ? f.threadCount : seed.threadCount;
    final todayCount = f.todayCount >= 0 ? f.todayCount : seed.todayCount;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(50),
          width: 0.8,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ThreadListPage(fid: f.fid, title: f.name),
              ),
            );
          },
          onLongPress: () {
            widget.onToggleFav?.call(f);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(fav ? '已取消收藏：${f.name}' : '已收藏版块：${f.name}'),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                if (f.iconUrl != null)
                  CachedNetworkImage(
                    imageUrl: f.iconUrl!,
                    httpHeaders: AppConfig.imageHeaders,
                    width: 26,
                    height: 26,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => Icon(
                      ForumNav.forumIcon(f.name),
                      size: 22,
                      color: ForumNav.forumIconColor(f.name),
                    ),
                  )
                else
                  Icon(
                    ForumNav.forumIcon(f.name),
                    size: 22,
                    color: ForumNav.forumIconColor(f.name),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      if (threadCount > 0 || todayCount > 0)
                        Text(
                          todayCount > 0
                              ? (threadCount > 0
                                  ? '今日 $todayCount · 帖数 ${threadCount > 9999 ? "${(threadCount / 10000).toStringAsFixed(1)}w" : threadCount}'
                                  : '今日 $todayCount')
                              : (threadCount > 9999
                                  ? '帖数 ${(threadCount / 10000).toStringAsFixed(1)}w'
                                  : '帖数 $threadCount'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 9.5,
                            color: todayCount > 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant.withAlpha(200),
                            fontWeight: todayCount > 0 ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                ),
                if (fav)
                  const Icon(Icons.star, size: 14, color: Color(0xFFFFB300)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 可折叠的版块分组（点击标题展开/收起）
class _CollapsibleGroup extends StatefulWidget {
  final ForumGroup group;
  final bool initiallyExpanded;
  final Set<int> favFids;
  final ValueChanged<Forum>? onToggleFav;
  final Widget Function(BuildContext, Forum) boardChip;

  const _CollapsibleGroup({
    required this.group,
    required this.initiallyExpanded,
    required this.favFids,
    this.onToggleFav,
    required this.boardChip,
  });

  @override
  State<_CollapsibleGroup> createState() => _CollapsibleGroupState();
}

class _CollapsibleGroupState extends State<_CollapsibleGroup> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.group.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LayoutBuilder(
              builder: (ctx, c) {
                return GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisExtent: 48,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  children: [
                    for (final f in widget.group.forums)
                      widget.boardChip(context, f),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 收藏版块底部弹层（搜索 + 移除 + 跳转）
class _FavForumsSheet extends StatefulWidget {
  final List<Forum> forums;
  final ValueChanged<Forum>? onToggleFav;
  final ValueChanged<Forum> onOpen;

  const _FavForumsSheet({
    required this.forums,
    required this.onToggleFav,
    required this.onOpen,
  });

  @override
  State<_FavForumsSheet> createState() => _FavForumsSheetState();
}

class _FavForumsSheetState extends State<_FavForumsSheet> {
  String _kw = '';

  /// 名称关键词高亮
  TextSpan _highlightName(String text, String kw) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = text.indexOf(kw, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + kw.length),
          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold),
        ),
      );
      start = idx + kw.length;
    }
    return TextSpan(children: spans);
  }

  bool _editMode = false;
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    final favList = widget.forums;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text(
              '收藏版块（${favList.length}）',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _kw = v.trim()),
              decoration: InputDecoration(
                hintText: '搜索收藏版块',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _kw.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => setState(() => _kw = ''),
                      ),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const Divider(height: 1),
          if (favList.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('暂无收藏版块（长按版块收藏）'),
            )
          else
            ...favList
                .where((f) => _kw.isEmpty || f.name.contains(_kw))
                .map(
                  (f) => Dismissible(
                    key: ValueKey('fav_${f.fid}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onDismissed: (_) {
                      widget.onToggleFav?.call(f);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已取消收藏：${f.name}')),
                      );
                    },
                    child: ListTile(
                      leading: _editMode
                          ? Checkbox(
                              value: _selected.contains(f.fid),
                              onChanged: (_) => setState(() {
                                _selected.contains(f.fid)
                                    ? _selected.remove(f.fid)
                                    : _selected.add(f.fid);
                              }),
                            )
                          : Icon(
                              ForumNav.forumIcon(f.name),
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      title: _kw.isEmpty
                          ? Text(f.name)
                          : Text.rich(_highlightName(f.name, _kw)),
                      trailing: _editMode
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  tooltip: '移除收藏',
                                  onPressed: () {
                                    widget.onToggleFav?.call(f);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('已取消收藏：${f.name}'),
                                      ),
                                    );
                                  },
                                ),
                                const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                      onTap: () {
                        if (_editMode) {
                          setState(() {
                            _selected.contains(f.fid)
                                ? _selected.remove(f.fid)
                                : _selected.add(f.fid);
                          });
                          return;
                        }
                        Navigator.of(context).pop();
                        widget.onOpen(f);
                      },
                    ),
                  ),
                ),
          if (_editMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.select_all, size: 18),
                    label: Text('全选'),
                    onPressed: () => setState(() {
                      _selected.isEmpty
                          ? _selected.addAll(widget.forums.map((f) => f.fid))
                          : _selected.clear();
                    }),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('移除 (${_selected.length})'),
                    onPressed: _selected.isEmpty
                        ? null
                        : () async {
                            for (final fid in _selected.toList()) {
                              final f = widget.forums
                                  .where((x) => x.fid == fid)
                                  .firstOrNull;
                              if (f != null) {
                                widget.onToggleFav?.call(f);
                              }
                            }
                            if (mounted) {
                              setState(() {
                                _editMode = false;
                                _selected.clear();
                              });
                            }
                          },
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class QuickActionsWidget extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const QuickActionsWidget({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 快捷金刚区：舒展的 2 排 × 4 宫格排布，带 M3 触觉反馈与色彩主题
    final items = [
      (Icons.forum_outlined, '版块导航', const Color(0xFF008AC5), 1),
      (Icons.event_available, '今日签到', const Color(0xFF00A2FF), 2),
      (Icons.military_tech, '勋章中心', const Color(0xFF9C27B0), 3),
      (Icons.local_fire_department, '导读精选', const Color(0xFFFF7043), 10),
      (Icons.search, '全站搜索', const Color(0xFF2E7D32), 11),
      (Icons.gavel, '封神榜', Colors.redAccent, 12),
      (Icons.leaderboard, '积分排行', const Color(0xFF7E57C2), 13),
      (Icons.mail_outline, '私信消息', const Color(0xFF009688), 14),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: _buildItem(context, theme, items[i]),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 4; i < 8; i++)
                Expanded(
                  child: _buildItem(context, theme, items[i]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    ThemeData theme,
    (IconData, String, Color, int) item,
  ) {
    final (icon, label, color, tabIndex) = item;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.lightImpact();
        onNavigate(tabIndex);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withAlpha(24),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(16),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  String _friendlyMessage(String raw) {
    if (raw.contains('523') || raw.contains('522') || raw.contains('521') || raw.contains('502') || raw.contains('503') || raw.contains('504')) {
      return '论坛服务器暂时繁忙或连接超时，请点击下方按钮重试';
    }
    if (raw.contains('SocketException') || raw.contains('connection refused') || raw.contains('Network is unreachable')) {
      return '网络连接失败，请检查网络设置或稍后重试';
    }
    if (raw.contains('timeout')) {
      return '网络请求超时，请点击下方按钮重试';
    }
    if (raw.contains('DioException')) {
      return '网络请求出现异常，请点击重试';
    }
    return raw.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(height: 14),
            Text(
              '加载失败',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _friendlyMessage(error),
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页推荐轮播（横幅卡片 + 自动播放 + 指示点）
class _RecommendCarousel extends StatefulWidget {
  final List<ThreadSummary> threads;
  final ValueChanged<int> onTap;

  const _RecommendCarousel({required this.threads, required this.onTap});

  @override
  State<_RecommendCarousel> createState() => _RecommendCarouselState();
}

class _RecommendCarouselState extends State<_RecommendCarousel> {
  final _ctrl = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.threads.length <= 1) return;
      final next = (_index + 1) % widget.threads.length;
      _ctrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  void _pauseAuto() {
    _timer?.cancel();
    _timer = null;
  }

  void _resumeAuto() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.threads.length <= 1) return;
      final next = (_index + 1) % widget.threads.length;
      _ctrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 110,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification) {
                _pauseAuto();
              } else if (n is ScrollEndNotification) {
                _resumeAuto();
              }
              return false;
            },
            child: PageView.builder(
              key: const PageStorageKey('rec_carousel'),
              controller: _ctrl,
              itemCount: widget.threads.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final t = widget.threads[i];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: GestureDetector(
                    onTap: () => widget.onTap(t.tid),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withAlpha(25),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                scheme.primaryContainer,
                                scheme.secondaryContainer,
                              ],
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // 帖子封面（有图时背景，配深色渐变保证文字可读）
                              if (t.coverUrl != null && t.coverUrl!.isNotEmpty) ...[
                                RetryImage(
                                  imageUrl: t.coverUrl!,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  filterQuality: FilterQuality.medium,
                                  memCacheWidth: 720,
                                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                                ),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0x20000000),
                                        Color(0xCC000000),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.primary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '推荐',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: scheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      t.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: t.coverUrl != null && t.coverUrl!.isNotEmpty
                                            ? Colors.white
                                            : scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (t.author.isNotEmpty || (t.timeText != null && t.timeText!.isNotEmpty))
                                          ? [
                                              if (t.author.isNotEmpty) t.author,
                                              if (t.timeText != null && t.timeText!.isNotEmpty) t.timeText!,
                                            ].join(' · ')
                                          : (t.forumName ?? ''),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: t.coverUrl != null && t.coverUrl!.isNotEmpty
                                            ? Colors.white.withAlpha(220)
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.threads.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: i == _index ? 14 : 5,
                height: 4,
                decoration: BoxDecoration(
                  color: i == _index ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
