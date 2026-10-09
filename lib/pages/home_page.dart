import '../widgets/animated_side_panel.dart';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/comiis_parser.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/home_layout_metrics.dart';
import '../core/home_feed.dart';
import '../core/dio_client.dart';
import '../core/forum_events.dart';
import '../core/preload_service.dart';
import '../core/write_confirm.dart';
import '../models/dashboard_card_model.dart';
import '../models/forum.dart';
import '../models/site_stats.dart';
import '../models/thread_summary.dart';
import '../models/server_outage_info.dart';
import '../widgets/server_outage_view.dart';
import '../widgets/dashboard_cards/dashboard_card_factory.dart';
import '../widgets/desktop_shortcuts.dart';
import '../widgets/horn_banner_widget.dart';
import '../widgets/home_content_slivers.dart';
import '../widgets/home_page_header.dart';
import '../widgets/mobile_home_customizer.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/interactive_animations.dart';
import '../widgets/smooth_scroll_controller.dart';
import '../widgets/visual_grid_canvas.dart';
import '../services/auto_sign_service.dart';
import '../services/push_notification_service.dart';
import 'credit_page.dart';
import 'darkroom_page.dart';
import 'favorite_hub_page.dart';
import 'forums_page.dart';
import 'membership_page.dart';
import 'guide_page.dart';
import 'login_page.dart';
import 'magic_page.dart';
import 'medal_page.dart';
import 'notice_page.dart';
import 'papa_ai_chat_page.dart';
import 'pm_inbox_page.dart';
import 'post_page.dart';
import 'ranklist_page.dart';
import 'search_page.dart';
import 'task_page.dart';
import 'thread_detail_page.dart';
import 'thread_list_page.dart';
import 'user_space_page.dart';
import 'user_threads_page.dart';

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
  ServerOutageInfo? _activeOutage;
  final _homeScrollCtrl = SmoothScrollController();
  final _homeSearchCtrl = TextEditingController();
  int _unreadPm = 0;
  int _unreadNotice = 0;
  Set<int> _favForums = {};
  final Set<int> _busyFavoriteForums = {};
  HomeFeed _feed = HomeFeed.recommended;
  final _feeds = <HomeFeed, HomeFeedState>{};
  HomeFeedState get _feedState => _feeds.putIfAbsent(_feed, HomeFeedState.new);
  List<ThreadSummary> get _more => _feedState.more;
  int get _morePage => _feedState.page;
  bool get _loadingMore => _feedState.loadingMore;
  set _loadingMore(bool value) => _feedState.loadingMore = value;
  bool get _hasMore => _feedState.hasMore;
  set _hasMore(bool value) => _feedState.hasMore = value;
  bool _refreshing = false;
  List<ThreadSummary> _memoizedAllThreads = [];
  List<ThreadSummary>? _lastInitialThreads;
  int _lastMoreLength = -1;
  bool _showBackToTop = false;
  bool _compactHomeFab = false;
  int _loadGeneration = 0;
  ValueChanged<int>? get _onSwitchTab => widget.onSwitchTab;

  @override
  void initState() {
    super.initState();
    _homeScrollCtrl.addListener(_onHomeScroll);
    PushNotificationService.instance.addListener(_onPushNotificationUpdate);
    ForumFavoriteNotifier.instance.addListener(_loadFavForums);
    AppConfig.instance.addListener(_onAppConfigUpdate);
    ComiisParser.loadTidForumCache();
    _future = _load();
    _future.ignore();
    _loadFavForums();
    _syncFavoriteForums();
    DioClient.sessionChanges.addListener(_onSessionChanged);
    if (DioClient.isLoggedIn) {
      AutoSignService.instance.checkOnAppLaunch();
    }
  }

  void _onAppConfigUpdate() {
    if (mounted) setState(() {});
  }

  void _onPushNotificationUpdate() {
    if (_unreadNotice == PushNotificationService.instance.unreadNotices &&
        _unreadPm == PushNotificationService.instance.unreadPm) {
      return;
    }
    if (mounted) {
      setState(() {
        _unreadNotice = PushNotificationService.instance.unreadNotices;
        _unreadPm = PushNotificationService.instance.unreadPm;
        _rememberHomeHeaderCounts();
      });
    }
  }

  Future<void> _loadFavForums() async {
    final session = DioClient.sessionKey;
    final ids = await KlpbbsApi.getSavedFavoriteForumIds();
    if (!mounted || session != DioClient.sessionKey) return;
    setState(() => _favForums = ids);
  }

  Future<void> _syncFavoriteForums() async {
    try {
      final uid = await KlpbbsApi.getMyUid();
      if (uid != null) {
        await KlpbbsApi.getFavoriteForums(uid, forceRefresh: true);
      }
      await _loadFavForums();
    } catch (_) {}
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _favForums = {};
      _busyFavoriteForums.clear();
      _unreadPm = 0;
      _unreadNotice = 0;
      _rememberHomeHeaderCounts();
      _loadGeneration++;
      _feeds.clear();
      _feed = HomeFeed.recommended;
      _refreshing = false;
      _future = _load(forceRefresh: true);
      _future.ignore();
    });
    unawaited(_syncFavoriteForums());
  }

  /// 按目标状态同步收藏；弹层移除不会因为旧快照再次收藏版块。
  Future<bool> _setForumFavorite(Forum f, bool favorite,
      {required String expectedSession}) async {
    if (!mounted || expectedSession != DioClient.sessionKey) return false;
    if (!_busyFavoriteForums.add(f.fid)) return false;
    final session = expectedSession;
    try {
      if (_favForums.contains(f.fid) == favorite) return true;
      final result = favorite
          ? await KlpbbsApi.favoriteForum(f.fid)
          : await KlpbbsApi.unfavoriteForum(f.fid);
      if (!mounted || session != DioClient.sessionKey) return false;
      if (result.success) await _loadFavForums();
      if (!mounted || session != DioClient.sessionKey) return false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      return result.success;
    } catch (_) {
      if (mounted && session == DioClient.sessionKey) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('收藏同步失败，请稍后重试')));
      }
      return false;
    } finally {
      if (session == DioClient.sessionKey) _busyFavoriteForums.remove(f.fid);
    }
  }

  Future<(List<ForumGroup>, List<ThreadSummary>, SiteStats)> _load(
      {bool forceRefresh = false}) async {
    final session = DioClient.sessionKey;
    final generation = _loadGeneration;
    final cachedGroups = PreloadService.instance
        .get<List<ForumGroup>>('forum_groups', ignoreExpired: true);
    final cachedThreads = PreloadService.instance
        .get<List<ThreadSummary>>('home_threads', ignoreExpired: true);
    final cachedStats = PreloadService.instance
        .get<SiteStats>('site_stats', ignoreExpired: true);

    // Recognized empty feeds are valid; tab revisits keep content until the
    // user refreshes rather than restarting an automatic global refresh.
    final hasValidCache = cachedGroups != null &&
        cachedGroups.isNotEmpty &&
        cachedThreads != null;

    if (!forceRefresh && hasValidCache) {
      _loadUnread();
      return (
        cachedGroups,
        cachedThreads,
        cachedStats ?? const SiteStats(),
      );
    }

    try {
      final results = await Future.wait([
        KlpbbsApi.getForumGroups(forceRefresh: forceRefresh),
        KlpbbsApi.getHome(forceRefresh: forceRefresh),
        KlpbbsApi.getSiteStats(forceRefresh: forceRefresh)
            .catchError((_) => cachedStats ?? const SiteStats()),
      ]);
      if (session != DioClient.sessionKey || generation != _loadGeneration) {
        throw StateError('页面已刷新，请等待最新数据');
      }
      _loadUnread();
      final groups = results[0] as List<ForumGroup>;
      final threads = results[1] as List<ThreadSummary>;
      final stats = results[2] as SiteStats;

      if (groups.isEmpty && threads.isEmpty) {
        throw Exception('暂未获取到内容，请检查网络或点击重试');
      }
      _activeOutage = null;
      return (groups, threads, stats);
    } catch (e) {
      if (session != DioClient.sessionKey || generation != _loadGeneration) {
        rethrow;
      }
      final outage = ServerOutageInfo.tryParse(e);
      if (outage != null) {
        _activeOutage = outage;
        // 关键修复：强制刷新（用户手动重试）或本地无完整有效帖子缓存时，坚决不静默回退，必须抛出展示 502 网关故障页！
        if (forceRefresh || !hasValidCache) {
          rethrow;
        }
        // 仅在静默初次加载且存在完整非空旧缓存时，优雅降级展示缓存并附带故障警告横幅
        return (
          cachedGroups,
          cachedThreads,
          cachedStats ?? const SiteStats(),
        );
      }
      if (!forceRefresh && hasValidCache) {
        return (
          cachedGroups,
          cachedThreads,
          cachedStats ?? const SiteStats(),
        );
      }
      rethrow;
    }
  }

  Future<bool> _reload() async {
    if (!mounted || _refreshing) return false;
    if (_feed != HomeFeed.recommended) {
      final feed = _feed;
      final state = _feedState;
      await _loadFeed(feed, forceRefresh: true);
      return state.error == null;
    }
    final session = DioClient.sessionKey;
    final state = _feeds.putIfAbsent(HomeFeed.recommended, HomeFeedState.new);
    final revision = state.beginRefresh();
    setState(() => _refreshing = true);
    _syncFavoriteForums();
    // Forced API reads bypass their caches; retain last good data so a failed
    // refresh can still offer the explicit cached-view action.
    unawaited(KlpbbsApi.getServerStatus(forceRefresh: true)
        .then<void>((_) {}, onError: (_) {}));
    try {
      final result = await _load(forceRefresh: true);
      if (!mounted || session != DioClient.sessionKey) return false;
      setState(() {
        _activeOutage = null;
        state.more = [];
        state.page = 1;
        state.hasMore = true;
        state.error = null;
        _lastInitialThreads = null;
        _future = Future.value(result);
      });
      return true;
    } catch (error) {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _activeOutage = ServerOutageInfo.tryParse(error));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('刷新暂未完成，已保留当前内容')));
      }
      return false;
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() {
          if (state.accepts(revision)) state.loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _selectFeed(HomeFeed feed) {
    if (feed == _feed) return;
    if (_homeScrollCtrl.hasClients) {
      _feedState.scrollOffset = _homeScrollCtrl.offset;
    }
    setState(() {
      _feed = feed;
      _lastInitialThreads = null;
      _lastMoreLength = -1;
    });
    PreloadService.instance.set('home_feed_selection',
        (session: DioClient.sessionKey, feed: feed));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _feed == feed && _homeScrollCtrl.hasClients) {
        _homeScrollCtrl.jumpTo(_feedState.scrollOffset
            .clamp(0, _homeScrollCtrl.position.maxScrollExtent)
            .toDouble());
      }
    });
    if (feed != HomeFeed.recommended && _feedState.initial == null) {
      unawaited(_loadFeed(feed));
    }
  }

  Future<void> _loadFeed(HomeFeed feed, {bool forceRefresh = false}) async {
    final state = _feeds.putIfAbsent(feed, HomeFeedState.new);
    if (state.pending != null) return state.pending;
    if (!forceRefresh && state.initial != null) return;
    final session = DioClient.sessionKey, generation = _loadGeneration;
    final revision = state.beginRefresh();
    if (mounted) setState(() {});
    final future = Future<void>.microtask(() async {
      try {
        if (feed == HomeFeed.following && !DioClient.isLoggedIn) {
          throw StateError('登录后查看关注的帖子');
        }
        final list = await KlpbbsApi.getGuide(feed.guideView!,
            forceRefresh: forceRefresh);
        if (session != DioClient.sessionKey ||
            generation != _loadGeneration ||
            !state.accepts(revision)) {
          return;
        }
        state.initial = list;
        state.more = [];
        state.page = 1;
        state.hasMore = KlpbbsApi.guideHasNextPage(feed.guideView!, 1) != false;
      } catch (error) {
        if (session == DioClient.sessionKey &&
            generation == _loadGeneration &&
            state.accepts(revision)) {
          state.error = error is StateError
              ? error.message.toString()
              : '暂时连接不上论坛，已保留本分类内容';
        }
      } finally {
        state.pending = null;
        state.loading = false;
        if (mounted &&
            session == DioClient.sessionKey &&
            generation == _loadGeneration) {
          setState(() => _lastInitialThreads = null);
        }
      }
    });
    state.pending = future;
    await future;
  }

  void _rememberHomeHeaderCounts() => PreloadService.instance.set(
      'home_header_counts',
      (session: DioClient.sessionKey, pm: _unreadPm, notice: _unreadNotice));

  /// 统计私信未读会话数与通知未读红点（本地已读记录过滤与服务端状态比对）
  Future<void> _loadUnread() async {
    final session = DioClient.sessionKey;
    try {
      // 检查未读通知与私信
      if (!DioClient.isLoggedIn) {
        if (mounted) {
          setState(() {
            _unreadPm = 0;
            _unreadNotice = 0;
            _rememberHomeHeaderCounts();
          });
        }
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || session != DioClient.sessionKey) return;
      final read =
          (prefs.getStringList('pm_read') ?? const []).map(int.parse).toSet();
      final unreadOverride =
          (prefs.getStringList('pm_unread_override') ?? const [])
              .map(int.parse)
              .toSet();
      final list = await KlpbbsApi.getPmList();
      if (!mounted || session != DioClient.sessionKey) return;
      final unread = list
          .where((c) =>
              (c.isNew && !read.contains(c.touid)) ||
              unreadOverride.contains(c.touid))
          .length;
      if (mounted) {
        setState(() {
          _unreadPm = unread;
          _rememberHomeHeaderCounts();
        });
      }

      // 通知未读：优先从 PushNotificationService 状态复用，避免全量重复抓取解析
      final notices = PushNotificationService.instance.unreadNotices;
      if (mounted) {
        setState(() {
          _unreadNotice = notices;
          _rememberHomeHeaderCounts();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || !mounted) return;
    final state = _feedState;
    if (state.loading || state.pending != null) return;
    final revision = state.revision;
    final view = _feed.guideView ?? 'newthread';
    if (KlpbbsApi.guideHasNextPage(view, _morePage) == false) {
      _hasMore = false;
      return;
    }
    final generation = _loadGeneration, session = DioClient.sessionKey;
    final nextPage = _morePage + 1;
    setState(() => _loadingMore = true);
    try {
      final next = await KlpbbsApi.getGuide(view, page: nextPage);
      if (!mounted ||
          generation != _loadGeneration ||
          session != DioClient.sessionKey ||
          !state.accepts(revision)) {
        return;
      }
      state.hasMore = next.isNotEmpty &&
          KlpbbsApi.guideHasNextPage(view, nextPage) != false;
      if (next.isNotEmpty) {
        state.page = nextPage;
        state.more.addAll(next);
        state.error = null;
        _lastInitialThreads = null;
        setState(() {});
      }
    } catch (_) {
      if (mounted &&
          generation == _loadGeneration &&
          session == DioClient.sessionKey &&
          state.accepts(revision)) {
        setState(() => state.error = '加载更多暂未完成，可手动重试');
      }
    } finally {
      if (mounted &&
          generation == _loadGeneration &&
          session == DioClient.sessionKey &&
          state.accepts(revision)) {
        setState(() => state.loadingMore = false);
      }
    }
  }

  @override
  void dispose() {
    _homeSearchCtrl.dispose();
    _homeScrollCtrl.dispose();
    PushNotificationService.instance.removeListener(_onPushNotificationUpdate);
    ForumFavoriteNotifier.instance.removeListener(_loadFavForums);
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    AppConfig.instance.removeListener(_onAppConfigUpdate);
    super.dispose();
  }

  /// 提前 600px 后台静默预加载更多，并管理回到顶部悬浮按钮显示状态
  void _onHomeScroll() {
    if (!_homeScrollCtrl.hasClients) return;
    final pos = _homeScrollCtrl.position;
    final showBackToTop = pos.pixels > 380;
    // 顶部仍显示文字入口；不同阈值避免在顶端轻微滚动时反复伸缩。
    final compactFab = pos.pixels > (_compactHomeFab ? 8 : 24);
    if (_showBackToTop != showBackToTop || _compactHomeFab != compactFab) {
      setState(() {
        _showBackToTop = showBackToTop;
        _compactHomeFab = compactFab;
      });
    }
    if (!_loadingMore &&
        _feedState.error == null &&
        pos.pixels >= pos.maxScrollExtent - 600) {
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

  void _openPost() {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录发表新帖')),
      );
      return;
    }
    confirmWrite(context, '发帖').then((ok) {
      if (ok && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PostPage()),
        );
      }
    });
  }

  Future<void> _openNotifications() async {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    setState(() {
      _unreadNotice = 0;
      _rememberHomeHeaderCounts();
    });
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先登录')));
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
                leading: const Icon(Icons.smart_toy_outlined),
                title: const Text('帕帕 AI 助手'),
                onTap: () => Navigator.of(ctx).pop('papa_ai'),
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('私信收件箱'),
                trailing: _unreadPm > 0 ? Badge.count(count: _unreadPm) : null,
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
        final uid = await KlpbbsApi.getMyUid();
        if (!mounted) return;
        if (uid == null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('当前账号资料尚未加载，请刷新后重试')));
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserSpacePage(uid: uid)),
        );
      } else if (action == 'credit') {
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => const CreditPage(initialTabIndex: 0)),
        );
      } else if (action == 'medal') {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MedalPage()),
        );
      } else if (action == 'magic') {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MagicPage()),
        );
      } else if (action == 'papa_ai') {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PapaAiChatPage()),
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

  Future<void> _openFavorites() async {
    if (!DioClient.isLoggedIn) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (!mounted || !DioClient.isLoggedIn) return;
    }
    final session = DioClient.sessionKey;
    final uid = await KlpbbsApi.getMyUid();
    if (!mounted || uid == null || session != DioClient.sessionKey) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => FavoriteHubPage(uid: uid)));
  }

  void _openHomeSearch() {
    final keyword = _homeSearchCtrl.text.trim();
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            SearchPage(initialKeyword: keyword.isEmpty ? null : keyword)));
  }

  void _onHomeHeaderAction(HomeHeaderAction action) {
    switch (action) {
      case HomeHeaderAction.refresh:
        _reload();
      case HomeHeaderAction.favorites:
        _openFavorites();
      case HomeHeaderAction.search:
        _openHomeSearch();
      case HomeHeaderAction.ai:
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PapaAiChatPage()));
      case HomeHeaderAction.pm:
        _openPmInbox();
      case HomeHeaderAction.notice:
        _openNotifications();
      case HomeHeaderAction.guide:
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const GuidePage()));
      case HomeHeaderAction.membership:
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MembershipPage()));
      case HomeHeaderAction.canvas:
      case HomeHeaderAction.layout:
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => VisualGridCanvas(
                pageCategory: 'home',
                initialLayout: AppConfig.homeDashboardLayout,
                onExit: () => Navigator.of(context).pop(),
                onSave: (_) {
                  if (mounted) setState(() {});
                })));
      case HomeHeaderAction.mobile:
        MobileHomeCustomizer.show(context);
      case HomeHeaderAction.left:
        AppConfig.setHomeShowLeftCards(!AppConfig.homeShowLeftCards);
      case HomeHeaderAction.right:
        AppConfig.setHomeShowRightCards(!AppConfig.homeShowRightCards);
      case HomeHeaderAction.settings:
        widget.onOpenSettings?.call();
      case HomeHeaderAction.account:
        _openAccountMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final nativeDesktop = !kIsWeb &&
        const {
          TargetPlatform.windows,
          TargetPlatform.macOS,
          TargetPlatform.linux
        }.contains(defaultTargetPlatform);

    return DesktopShortcutsWrapper(
      onRefresh: _reload,
      onSearch: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SearchPage())),
      child: Scaffold(
        appBar: HomePageHeader(
          isDesktop: isDesktop,
          nativeDesktop: nativeDesktop,
          searchController: _homeSearchCtrl,
          toolbarHeight: HomePageHeader.heightFor(context),
          showDrawerButton: widget.showDrawerButton,
          onOpenDrawer: widget.onOpenDrawer,
          loggedIn: DioClient.isLoggedIn,
          leftExpanded: AppConfig.homeShowLeftCards,
          rightExpanded: AppConfig.homeShowRightCards,
          settingsAvailable: widget.onOpenSettings != null,
          unreadPm: _unreadPm,
          unreadNotice: _unreadNotice,
          onAction: _onHomeHeaderAction,
        ),
        body: FutureBuilder(
          key: ValueKey('home-session-${DioClient.sessionKey}'),
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              if (snap.hasError) {
                final hasCache = PreloadService.instance
                            .get<List<ForumGroup>>('forum_groups',
                                ignoreExpired: true)
                            ?.isNotEmpty ==
                        true &&
                    PreloadService.instance
                            .get<List<ThreadSummary>>('home_threads',
                                ignoreExpired: true)
                            ?.isNotEmpty ==
                        true;
                return _ErrorView(
                  error: '${snap.error}',
                  onRetry: _reload,
                  onViewCache: hasCache
                      ? () {
                          final cg = PreloadService.instance
                                  .get<List<ForumGroup>>('forum_groups',
                                      ignoreExpired: true) ??
                              [];
                          final ct = PreloadService.instance
                                  .get<List<ThreadSummary>>('home_threads',
                                      ignoreExpired: true) ??
                              [];
                          final cs = PreloadService.instance.get<SiteStats>(
                                  'site_stats',
                                  ignoreExpired: true) ??
                              const SiteStats();
                          setState(() {
                            _future = Future.value((cg, ct, cs));
                          });
                        }
                      : null,
                );
              }
              // 响应式优雅微光骨架屏（PC 三栏比例与移动端单列流自适应，杜绝 12 列网格变形拉伸）
              return _buildHomeLoadingView(context, isDesktop);
            }
            final (groups, threads, stats) = snap.data!;
            final messenger = ScaffoldMessenger.of(context);
            final allThreads = _getDisplayThreads(_feed == HomeFeed.recommended
                ? threads
                : _feedState.initial ?? const []);

            return SafeArea(
              top: false,
              left: true,
              right: true,
              bottom: true,
              child: Column(
                children: [
                  if (_activeOutage != null)
                    ServerOutageBanner(
                      outage: _activeOutage!,
                      onRetry: _reload,
                      onViewDetails: () {
                        ServerOutageView.showAsDialog(
                          context,
                          outage: _activeOutage!,
                          onRetry: _reload,
                        );
                      },
                      onDismiss: () {
                        setState(() => _activeOutage = null);
                      },
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableWidth = constraints.maxWidth;

                        // 卡片分配与过滤：彻底移除 credit_log 与 horn_banner
                        final layout = AppConfig.homeDashboardLayout
                            .where((c) =>
                                c.cardType != 'credit_log' &&
                                c.cardType != 'horn_banner')
                            .toList();

                        final leftCards = layout.where((c) {
                          return (c.col + c.colSpan / 2) < 6;
                        }).toList()
                          ..sort((a, b) => a.row != b.row
                              ? a.row.compareTo(b.row)
                              : a.col.compareTo(b.col));

                        final rightCards = layout.where((c) {
                          return (c.col + c.colSpan / 2) >= 6;
                        }).toList()
                          ..sort((a, b) => a.row != b.row
                              ? a.row.compareTo(b.row)
                              : a.col.compareTo(b.col));

                        final metrics = HomeLayoutMetrics.calculate(
                          width: availableWidth,
                          desktop: isDesktop,
                          leftEnabled: AppConfig.homeShowLeftCards &&
                              leftCards.isNotEmpty,
                          rightEnabled: AppConfig.homeShowRightCards &&
                              rightCards.isNotEmpty,
                          preferredLeft: AppConfig.homeLeftSidebarWidth,
                          preferredRight: AppConfig.homeRightSidebarWidth,
                          minimumCenterWidth: AppConfig.mainContentMinWidth,
                        );
                        final showLeft = metrics.showLeft,
                            showRight = metrics.showRight;
                        final suppressDefaultStats = !stats.isEmpty &&
                            (metrics.centerWidth < 600
                                    ? AppConfig.mobileHomeSections
                                    : AppConfig.defaultMobileHomeSections)
                                .contains('stats');

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isDesktop)
                              ValueListenableBuilder<double>(
                                valueListenable:
                                    AppConfig.homeLeftSidebarWidthNotifier,
                                builder: (context, width, _) {
                                  final panelWidth =
                                      HomeLayoutMetrics.calculate(
                                    width: availableWidth,
                                    desktop: true,
                                    leftEnabled: showLeft,
                                    rightEnabled: showRight,
                                    preferredLeft: width,
                                    preferredRight:
                                        AppConfig.homeRightSidebarWidth,
                                    minimumCenterWidth:
                                        AppConfig.mainContentMinWidth,
                                  ).leftWidth;
                                  return AnimatedSidePanel(
                                    key: const ValueKey('home-left-panel'),
                                    expanded: showLeft,
                                    width: panelWidth,
                                    isLeft: true,
                                    splitter:
                                        _buildSidebarSplitter(isLeft: true),
                                    handle:
                                        _buildCollapsedEdgeHandle(isLeft: true),
                                    child: _buildCardSidebar(
                                        context: context,
                                        isLeft: true,
                                        cards: leftCards,
                                        allThreads: allThreads,
                                        stats: stats,
                                        suppressDefaultStats:
                                            suppressDefaultStats,
                                        width: panelWidth),
                                  );
                                },
                              ),

                            // 中间原版内容（自适应填满剩余全部空间，独立 RepaintBoundary 隔离，杜绝滚动时向上传播重绘全局窗口）
                            Expanded(
                              child: RepaintBoundary(
                                child: RefreshIndicator(
                                  onRefresh: () async {
                                    HapticFeedback.lightImpact();
                                    final refreshed = await _reload();
                                    if (mounted) {
                                      final now = DateTime.now();
                                      final hm =
                                          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                                      messenger.showSnackBar(SnackBar(
                                          content: Text(refreshed
                                              ? '刷新完成 $hm'
                                              : '刷新未完成，请稍后重试')));
                                    }
                                  },
                                  color: Theme.of(context).colorScheme.primary,
                                  backgroundColor:
                                      Theme.of(context).colorScheme.surface,
                                  displacement: 40,
                                  edgeOffset: 8,
                                  child: LayoutBuilder(
                                      builder: (context, center) =>
                                          CustomScrollView(
                                            controller: _homeScrollCtrl,
                                            physics:
                                                const AlwaysScrollableScrollPhysics(),
                                            slivers:
                                                _buildCenterOriginalSlivers(
                                              context: context,
                                              groups: groups,
                                              threads: threads,
                                              allThreads: allThreads,
                                              stats: stats,
                                              isDesktop: isDesktop,
                                              centerWidth: center.maxWidth,
                                            ),
                                          )),
                                ),
                              ),
                            ),

                            if (isDesktop)
                              ValueListenableBuilder<double>(
                                valueListenable:
                                    AppConfig.homeRightSidebarWidthNotifier,
                                builder: (context, width, _) {
                                  final panelWidth =
                                      HomeLayoutMetrics.calculate(
                                    width: availableWidth,
                                    desktop: true,
                                    leftEnabled: showLeft,
                                    rightEnabled: showRight,
                                    preferredLeft:
                                        AppConfig.homeLeftSidebarWidth,
                                    preferredRight: width,
                                    minimumCenterWidth:
                                        AppConfig.mainContentMinWidth,
                                  ).rightWidth;
                                  return AnimatedSidePanel(
                                    key: const ValueKey('home-right-panel'),
                                    expanded: showRight,
                                    width: panelWidth,
                                    isLeft: false,
                                    splitter:
                                        _buildSidebarSplitter(isLeft: false),
                                    handle: _buildCollapsedEdgeHandle(
                                        isLeft: false),
                                    child: _buildCardSidebar(
                                        context: context,
                                        isLeft: false,
                                        cards: rightCards,
                                        allThreads: allThreads,
                                        stats: stats,
                                        suppressDefaultStats:
                                            suppressDefaultStats,
                                        width: panelWidth),
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: CoordinatedActionFabGroup(
          key: const ValueKey('home-action-fab-group'),
          showBackToTop: _showBackToTop,
          onBackToTop: _scrollToTop,
          extendPrimary: isDesktop ||
              (!_compactHomeFab &&
                  MediaQuery.textScalerOf(context).scale(14) / 14 < 1.3),
          primaryIcon: Icons.edit_rounded,
          primaryLabel: '发帖',
          primaryTooltip: isDesktop ? '发布新帖 (Ctrl+N)' : '发布新帖',
          onPrimaryAction: _openPost,
          heroTagPrefix: 'home',
        ),
      ),
    );
  }

  /// 构建侧栏卡片容器（支持左右独立展开/折叠、自适应高度、RepaintBoundary 隔离）
  Widget _buildCardSidebar({
    required BuildContext context,
    required bool isLeft,
    required List<DashboardGridItem> cards,
    required List<ThreadSummary> allThreads,
    required SiteStats stats,
    required double width,
    bool suppressDefaultStats = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerLow
            : theme.colorScheme.surfaceContainerLowest,
        border: Border(
          right: isLeft
              ? BorderSide(color: theme.dividerColor.withAlpha(35), width: 1)
              : BorderSide.none,
          left: !isLeft
              ? BorderSide(color: theme.dividerColor.withAlpha(35), width: 1)
              : BorderSide.none,
        ),
      ),
      child: Column(
        children: [
          // 侧栏标题与折叠栏
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: theme.dividerColor.withAlpha(25), width: 0.8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isLeft ? Icons.widgets_outlined : Icons.insights_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  isLeft ? '个人工具' : '社区动态',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withAlpha(210),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon:
                      const Icon(Icons.dashboard_customize_outlined, size: 16),
                  tooltip: '自由画布工坊 (DIY 界面)',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VisualGridCanvas(
                          pageCategory: 'home',
                          initialLayout: AppConfig.homeDashboardLayout,
                          onExit: () => Navigator.of(context).pop(),
                          onSave: (saved) {
                            setState(() {});
                          },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    isLeft ? Icons.first_page_rounded : Icons.last_page_rounded,
                    size: 17,
                  ),
                  tooltip: isLeft ? '收起左侧栏' : '收起右侧栏',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    if (isLeft) {
                      AppConfig.setHomeShowLeftCards(false);
                    } else {
                      AppConfig.setHomeShowRightCards(false);
                    }
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
          // 卡片滚动流
          Expanded(
            child: cards.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.dashboard_customize_outlined,
                            size: 32,
                            color: theme.colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isLeft ? '暂无左侧卡片' : '暂无右侧卡片',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => VisualGridCanvas(
                                    pageCategory: 'home',
                                    initialLayout:
                                        AppConfig.homeDashboardLayout,
                                    onExit: () => Navigator.of(context).pop(),
                                    onSave: (saved) {
                                      setState(() {});
                                    },
                                  ),
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                            child: const Text('前往自由画布添加卡片'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                    itemCount: cards.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = cards[index];
                      final cardHeight = HomeLayoutMetrics.sidebarCardHeight(
                          type: item.cardType,
                          rows: item.rowSpan,
                          width: width);
                      return SizedBox(
                        height: cardHeight,
                        child: DashboardCardFactory.buildCard(
                          item: item,
                          isPreview: false,
                          threads: allThreads,
                          stats: stats,
                          suppressDefaultStats: suppressDefaultStats,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 侧边栏拖拽快捷调整大小分割条（鼠标按住拖动即可直接调整宽度并持久化保存）
  Widget _buildSidebarSplitter({required bool isLeft}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final delta = details.delta.dx;
          if (isLeft) {
            final newWidth =
                (AppConfig.homeLeftSidebarWidth + delta).clamp(200.0, 480.0);
            AppConfig.updateHomeLeftSidebarWidth(newWidth);
          } else {
            final newWidth =
                (AppConfig.homeRightSidebarWidth - delta).clamp(200.0, 480.0);
            AppConfig.updateHomeRightSidebarWidth(newWidth);
          }
        },
        onHorizontalDragEnd: (_) {
          if (isLeft) {
            AppConfig.setHomeLeftSidebarWidth(AppConfig.homeLeftSidebarWidth);
          } else {
            AppConfig.setHomeRightSidebarWidth(AppConfig.homeRightSidebarWidth);
          }
        },
        child: Container(
          width: 8,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 2.5,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withAlpha(90),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 响应式优雅微光骨架屏（PC 三栏比例与移动端单列流自适应，杜绝 12 列网格变形拉伸）
  Widget _buildHomeLoadingView(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseShimmer =
        isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8);

    if (isDesktop) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final showSidebars = w >= 900;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSidebars)
                SizedBox(
                  width: 240,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildShimmerBox(
                            height: 120, color: baseShimmer, radius: 12),
                        const SizedBox(height: 12),
                        _buildShimmerBox(
                            height: 160, color: baseShimmer, radius: 12),
                        const SizedBox(height: 12),
                        _buildShimmerBox(
                            height: 100, color: baseShimmer, radius: 12),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildShimmerBox(
                          height: 180, color: baseShimmer, radius: 12),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildShimmerBox(
                              width: 80,
                              height: 20,
                              color: baseShimmer,
                              radius: 6),
                          const Spacer(),
                          _buildShimmerBox(
                              width: 60,
                              height: 16,
                              color: baseShimmer,
                              radius: 6),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisExtent: 156,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                          itemCount: 6,
                          itemBuilder: (_, __) => _buildShimmerBox(
                            height: 138,
                            color: baseShimmer,
                            radius: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showSidebars && w >= 1150)
                SizedBox(
                  width: 260,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildShimmerBox(
                            height: 150, color: baseShimmer, radius: 12),
                        const SizedBox(height: 12),
                        _buildShimmerBox(
                            height: 200, color: baseShimmer, radius: 12),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildShimmerBox(height: 150, color: baseShimmer, radius: 12),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
              4,
              (_) => _buildShimmerBox(
                  width: 48, height: 48, color: baseShimmer, radius: 24),
            ),
          ),
          const SizedBox(height: 16),
          _buildShimmerBox(
              width: 64, height: 18, color: baseShimmer, radius: 6),
          const SizedBox(height: 12),
          const Expanded(child: SkeletonList(itemCount: 5)),
        ],
      ),
    );
  }

  Widget _buildShimmerBox(
      {double? width,
      required double height,
      required Color color,
      double radius = 8}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  /// 侧栏收起后的边缘展开把手（全高度停靠边缘条 + 居中高亮交互把手，点击任意区域立即重新展开对应侧栏）
  Widget _buildCollapsedEdgeHandle({required bool isLeft}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: isLeft ? '展开左侧个人工具栏 (点击重新开启)' : '展开右侧社区动态栏 (点击重新开启)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              if (isLeft) {
                AppConfig.setHomeShowLeftCards(true);
              } else {
                AppConfig.setHomeShowRightCards(true);
              }
              if (mounted) setState(() {});
            },
            child: Container(
              width: 26,
              color: Colors.transparent,
              child: Stack(
                alignment:
                    isLeft ? Alignment.centerLeft : Alignment.centerRight,
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment:
                          isLeft ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: 1,
                        color: colorScheme.outlineVariant.withAlpha(80),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 22,
                      height: 84,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.only(
                          topRight:
                              isLeft ? const Radius.circular(10) : Radius.zero,
                          bottomRight:
                              isLeft ? const Radius.circular(10) : Radius.zero,
                          topLeft:
                              !isLeft ? const Radius.circular(10) : Radius.zero,
                          bottomLeft:
                              !isLeft ? const Radius.circular(10) : Radius.zero,
                        ),
                        border: Border.all(
                          color: colorScheme.primary.withAlpha(150),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(30),
                            blurRadius: 6,
                            offset: Offset(isLeft ? 1 : -1, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          isLeft
                              ? Icons.chevron_right_rounded
                              : Icons.chevron_left_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Loading and navigation remain in the page; the shared renderer uses data.
  List<Widget> _buildCenterOriginalSlivers({
    required BuildContext context,
    required List<ForumGroup> groups,
    required List<ThreadSummary> threads,
    required List<ThreadSummary> allThreads,
    required SiteStats stats,
    required bool isDesktop,
    required double centerWidth,
  }) {
    final favoriteSession = DioClient.sessionKey;
    final slivers = HomeContentSlivers.build(context,
        groups: groups,
        threads: allThreads,
        recommendations: threads,
        stats: stats,
        isDesktop: isDesktop,
        centerWidth: centerWidth,
        sections: (!isDesktop || centerWidth < 600)
            ? AppConfig.mobileHomeSections
            : AppConfig.defaultMobileHomeSections,
        quickActionIds: AppConfig.mobileQuickActions,
        favoriteForumIds: _favForums,
        announcementsEnabled: AppConfig.homeModules.contains('horn_banner'),
        announcementContent: const HornBannerWidget(),
        loadingMore: _loadingMore,
        hasMore: _hasMore,
        feed: _feed,
        onSelectFeed: _selectFeed,
        feedLoading: _feedState.loading,
        feedError: _feedState.error,
        refreshing: _refreshing,
        outage: _activeOutage,
        onRefresh: _reload,
        onLoadMore: _loadMore,
        onCustomize: () => MobileHomeCustomizer.show(context),
        onAllForums: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ForumsPage())),
        onOpenForum: (forum) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ThreadListPage(fid: forum.fid, title: forum.name))),
        onToggleFavorite: (forum, favorite) => _setForumFavorite(
            forum, favorite, expectedSession: favoriteSession),
        onOpenThread: (thread) => _openThread(thread.tid, fid: thread.fid),
        onOpenAuthor: (thread) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => UserSpacePage(
                uid: thread.uid,
                username: thread.author.isNotEmpty ? thread.author : null))),
        onQuickAction: _onNavigateTab);
    if (!isDesktop) {
      // 共享流已有80px尾距，另留48px让最后一条内容能滚到两枚悬浮按钮上方。
      slivers.add(const SliverToBoxAdapter(
          key: ValueKey('home-mobile-fab-bottom-space'),
          child: SizedBox(height: 48)));
    }
    return slivers;
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

  void _openThread(int tid, {int? fid}) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(
        builder: (_) => ThreadDetailPage(tid: tid, fid: fid)));
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
    if (index == 15) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PapaAiChatPage()));
      return;
    }
    if (index == 16) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TaskPage()));
      return;
    }
    if (index == 17) {
      if (!DioClient.isLoggedIn) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请先登录查看我的收藏')));
        return;
      }
      KlpbbsApi.getMyUid().then((uid) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => FavoriteHubPage(uid: uid ?? 0)),
          );
        }
      });
      return;
    }
    if (index == 18) {
      if (!DioClient.isLoggedIn) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请先登录查看我的主题')));
        return;
      }
      KlpbbsApi.getMyUid().then((uid) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => UserThreadsPage(
                uid: uid ?? 0,
                type: 'thread',
                title: '我的主题',
              ),
            ),
          );
        }
      });
      return;
    }
    if (index == 19) {
      if (!DioClient.isLoggedIn) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请先登录发表新帖')));
        return;
      }
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PostPage()));
      return;
    }
    if (_onSwitchTab != null) _onSwitchTab!(index);
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final VoidCallback? onViewCache;

  const _ErrorView({
    required this.error,
    required this.onRetry,
    this.onViewCache,
  });

  String _friendlyMessage(String raw) {
    if (raw.contains('523') ||
        raw.contains('522') ||
        raw.contains('521') ||
        raw.contains('502') ||
        raw.contains('503') ||
        raw.contains('504')) {
      return '论坛服务器暂时繁忙或连接超时，请点击下方按钮重试';
    }
    if (raw.contains('SocketException') ||
        raw.contains('connection refused') ||
        raw.contains('Network is unreachable')) {
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
    final outage = ServerOutageInfo.tryParse(error);
    if (outage != null) {
      return ServerOutageView(
        outage: outage,
        onRetry: onRetry,
        onViewCache: onViewCache,
      );
    }

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
