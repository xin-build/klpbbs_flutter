import '../widgets/app_motion.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';

import '../widgets/usergroup_comparison_sheet.dart';
import '../api/comiis_parser.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../core/dio_client.dart';
import '../core/preload_service.dart';
import '../models/server_outage_info.dart';
import '../models/user_space.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/inline_html_text.dart';
import '../widgets/server_outage_view.dart';
import '../widgets/thread_card.dart';
import 'credit_page.dart';
import 'friend_page.dart';
import 'homestyle_page.dart';
import 'login_page.dart';
import 'medal_page.dart';
import 'pm_detail_page.dart';
import 'profile_settings_page.dart';
import 'user_threads_page.dart';

/// 苦力怕论坛个人空间 / 我的空间（深度复刻图二：官方移动端空间完整资料与操作体系，100% 防塌陷架构）
class UserSpacePage extends StatefulWidget {
  final int? uid;
  final String? username;
  final bool? isMe;
  final UserSpace? initialUser;

  const UserSpacePage({
    super.key,
    this.uid,
    this.username,
    this.isMe,
    this.initialUser,
  });

  @override
  State<UserSpacePage> createState() => _UserSpacePageState();
}

class _UserSpacePageState extends State<UserSpacePage> {
  late Future<UserSpace?> _future;
  int _selectedTab = 0; // 0: 资料, 1: 帖子
  bool _threadsVisited = false;
  bool _isMe = false;
  int _resolvedUid = 0;
  UserSpace? _cachedUser;
  int _loadSequence = 0;
  late final String _initialSession;

  int get targetUid => _resolvedUid > 0 ? _resolvedUid : (widget.uid ?? 0);

  @override
  void initState() {
    super.initState();
    _initialSession = DioClient.sessionKey;
    DioClient.sessionChanges.addListener(_onSessionChanged);
    KlpbbsApi.profileChanges.addListener(_onProfileChanged);
    _resolvedUid = widget.uid ?? widget.initialUser?.uid ?? 0;
    final effectiveUid =
        (widget.uid != null && widget.uid! > 0) ? widget.uid! : _resolvedUid;
    if (effectiveUid > 0) {
      _cachedUser = PreloadService.instance.get<UserSpace>(
              'user_space_$effectiveUid',
              ignoreExpired: true) ??
          widget.initialUser;
    } else {
      _cachedUser = widget.initialUser;
    }
    if (_cachedUser != null) {
      _future = Future.value(_cachedUser);
      _isMe = widget.isMe ?? false;
      _loadData();
    } else {
      _loadData();
    }
  }

  void _loadData({bool forceRefresh = false}) {
    final sequence = ++_loadSequence;
    final session = DioClient.sessionKey;
    bool current() =>
        mounted && sequence == _loadSequence && session == DioClient.sessionKey;
    final effectiveUid =
        (widget.uid != null && widget.uid! > 0) ? widget.uid! : _resolvedUid;
    if (effectiveUid > 0) {
      final cached = PreloadService.instance
          .get<UserSpace>('user_space_$effectiveUid', ignoreExpired: true);
      final candidate = cached ??
          _cachedUser ??
          (session == _initialSession ? widget.initialUser : null);
      final initialCandidate =
          candidate?.uid == effectiveUid ? candidate : null;
      if (initialCandidate != null) {
        _cachedUser = initialCandidate;
      }
      final bool hasFullData = initialCandidate != null &&
          (initialCandidate.creditsDetail.isNotEmpty ||
              initialCandidate.stats.isNotEmpty ||
              initialCandidate.isLocked);
      if (!forceRefresh &&
          hasFullData &&
          PreloadService.instance.has('user_space_$effectiveUid')) {
        _future = Future.value(initialCandidate);
      } else {
        if (initialCandidate != null) {
          _future =
              KlpbbsApi.getUserSpace(effectiveUid, forceRefresh: forceRefresh)
                  .then((fresh) {
            if (current() && fresh != null && fresh.uid > 0) {
              setState(() {
                _resolvedUid = fresh.uid;
                _cachedUser = fresh;
                _future = Future.value(fresh);
              });
            }
            return fresh ?? initialCandidate;
          });
        } else {
          setState(() {
            _future =
                KlpbbsApi.getUserSpace(effectiveUid, forceRefresh: forceRefresh)
                    .then((fresh) {
              if (current() && fresh != null && fresh.uid > 0) {
                setState(() {
                  _resolvedUid = fresh.uid;
                  _cachedUser = fresh;
                });
              }
              return fresh;
            });
          });
        }
      }
    } else if (widget.username != null && widget.username!.isNotEmpty) {
      setState(() {
        _future = KlpbbsApi.getUserSpaceByName(widget.username!).then((fresh) {
          if (current() && fresh != null && fresh.uid > 0) {
            setState(() {
              _resolvedUid = fresh.uid;
              _cachedUser = fresh;
            });
          }
          return fresh;
        });
      });
    } else {
      _future = Future.value(null);
    }

    _future.ignore();
    if (!DioClient.isLoggedIn) {
      _isMe = false;
    } else if (KlpbbsApi.currentCachedMyUid != null) {
      _isMe = KlpbbsApi.currentCachedMyUid == targetUid;
    } else {
      KlpbbsApi.getMyUid().then((myUid) {
        if (current() && myUid != null) {
          setState(() => _isMe = (myUid == targetUid));
        }
      }).catchError((_) {});
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _cachedUser = null;
      _isMe = false;
      _loadData(forceRefresh: true);
    });
  }

  void _onProfileChanged() {
    if (mounted && targetUid == KlpbbsApi.currentCachedMyUid) {
      setState(() => _loadData(forceRefresh: true));
    }
  }

  @override
  void dispose() {
    _loadSequence++;
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    KlpbbsApi.profileChanges.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _showQrCodeDialog(UserSpace user) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${user.username} 的空间二维码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withAlpha(50)),
              ),
              child: QrImageView(
                  data: '${AppConfig.baseUrl}space-uid-${user.uid}.html',
                  size: 180,
                  padding: const EdgeInsets.all(12),
                  backgroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            SelectableText(
              '${AppConfig.baseUrl}space-uid-${user.uid}.html',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: '${AppConfig.baseUrl}space-uid-${user.uid}.html'));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制个人空间链接')),
              );
            },
            child: const Text('复制链接'),
          ),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  void _showUsergroupPrivilegesDialog(UserSpace user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 900),
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: const UsergroupComparisonSheet(),
      ),
    );
  }

  void _showMoreActions(UserSpace user) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('空间二维码'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showQrCodeDialog(user);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制空间链接'),
              onTap: () {
                Clipboard.setData(ClipboardData(
                    text: '${AppConfig.baseUrl}space-uid-${user.uid}.html'));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制个人空间链接')),
                );
              },
            ),
            if (_isMe)
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('资料设置'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                            builder: (_) => ProfileSettingsPage(uid: user.uid)),
                      )
                      .then((_) => _loadData());
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpaceSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final placeholderColor = isDark
        ? colorScheme.surfaceContainerHighest.withAlpha(90)
        : Colors.grey.shade200;

    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: Text(_isMe ? '我的空间' : '个人空间'),
      ),
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 空间顶部横幅背景与头像骨架
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: placeholderColor,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    placeholderColor.withAlpha(140),
                    placeholderColor,
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    bottom: 16,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.surface,
                        border:
                            Border.all(color: colorScheme.surface, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: placeholderColor.withAlpha(180),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 用户名与等级徽章骨架
            Center(
              child: Column(
                children: [
                  Container(
                    width: 140,
                    height: 22,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 55,
                        height: 18,
                        decoration: BoxDecoration(
                          color: placeholderColor.withAlpha(160),
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 75,
                        height: 18,
                        decoration: BoxDecoration(
                          color: placeholderColor.withAlpha(160),
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // 4 列数据卡片骨架 (主题 / 回复 / 积分 / 人气)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: colorScheme.outlineVariant.withAlpha(40)),
                ),
                child: Row(
                  children: List.generate(
                      4,
                      (i) => Expanded(
                            child: Column(
                              children: [
                                Container(
                                  width: 32,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: placeholderColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: 24,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: placeholderColor.withAlpha(140),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ],
                            ),
                          )),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 标签栏骨架
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(60),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 60,
                    height: 28,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 60,
                    height: 28,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 帖子卡片骨架列表
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: List.generate(
                    3,
                    (i) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    colorScheme.outlineVariant.withAlpha(35)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: placeholderColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 180,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: placeholderColor.withAlpha(120),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ],
                          ),
                        )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<UserSpace?>(
      initialData: _cachedUser ??
          (_initialSession == DioClient.sessionKey ? widget.initialUser : null),
      future: _future,
      builder: (context, snap) {
        Widget content;
        if (snap.connectionState != ConnectionState.done && snap.data == null) {
          content = KeyedSubtree(
            key: const ValueKey('space_skeleton'),
            child: _buildSpaceSkeleton(context),
          );
        } else if (snap.hasError &&
            snap.data == null &&
            ServerOutageInfo.tryParse(snap.error) != null) {
          final outage = ServerOutageInfo.tryParse(snap.error)!;
          content = KeyedSubtree(
            key: const ValueKey('space_outage'),
            child: Scaffold(
              appBar: AppBar(
                title: Text(_isMe ? '我的空间' : 'Ta 的空间'),
              ),
              body: ServerOutageView(
                outage: outage,
                onRetry: () => _loadData(forceRefresh: true),
                onGoHome: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
              ),
            ),
          );
        } else if (snap.data == null) {
          content = KeyedSubtree(
            key: const ValueKey('space_error'),
            child: Scaffold(
              drawer: const GlobalAppDrawer(),
              drawerEdgeDragWidth: 50.0,
              appBar: AppBar(
                leading: const GlobalNavLeading(),
                leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
                title: Text(_isMe ? '我的空间' : 'Ta 的空间'),
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: theme.colorScheme.error),
                    const SizedBox(height: 12),
                    const Text('用户信息加载失败', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _loadData, child: const Text('重新加载')),
                  ],
                ),
              ),
            ),
          );
        } else {
          final user = snap.data!;
          if (user.isLocked) {
            content = KeyedSubtree(
              key: ValueKey('space_locked_${user.uid}'),
              child: Scaffold(
                drawer: const GlobalAppDrawer(),
                drawerEdgeDragWidth: 50.0,
                appBar: AppBar(
                  leading: const GlobalNavLeading(),
                  leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
                  title: const Text('提示信息'),
                  centerTitle: true,
                ),
                body: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 48),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withAlpha(80),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 56,
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          user.lockReason.isNotEmpty
                              ? user.lockReason
                              : '空间已被锁定无法访问，如有疑问请联系管理员',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 36),
                        SizedBox(
                          width: 260,
                          height: 44,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF4FC3F7),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              }
                            },
                            child: const Text(
                              '返回上一页',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          } else {
            content = KeyedSubtree(
              key: ValueKey('space_content_${user.uid}'),
              child: Scaffold(
                drawer: const GlobalAppDrawer(),
                drawerEdgeDragWidth: 50.0,
                body: Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          _loadData(forceRefresh: true);
                          await _future;
                        },
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics()),
                          slivers: [
                            // 1. 顶部 Minecraft 森林沉浸式 Hero 顶栏
                            SliverAppBar(
                              expandedHeight: 220,
                              pinned: true,
                              foregroundColor: Colors.white,
                              backgroundColor: theme.colorScheme.primary,
                              leading:
                                  const GlobalNavLeading(color: Colors.white),
                              leadingWidth:
                                  GlobalNavLeading.preferredLeadingWidth(
                                      context),
                              title: Text(
                                _isMe ? '我的空间' : 'Ta 的空间',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 17),
                              ),
                              actions: [
                                IconButton(
                                  icon: const Icon(Icons.more_horiz),
                                  tooltip: '更多',
                                  onPressed: () => _showMoreActions(user),
                                ),
                              ],
                              flexibleSpace: FlexibleSpaceBar(
                                background: _buildHeroHeader(user, theme),
                              ),
                            ),

                            // 2. Tab 切换栏 (资料 / 帖子)
                            SliverToBoxAdapter(
                              child: Container(
                                color: theme.colorScheme.surface,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 880),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                              color: theme
                                                  .colorScheme.outlineVariant
                                                  .withAlpha(60)),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          _buildTabItem(0, '资料', theme),
                                          _buildTabItem(
                                              1,
                                              '帖子 (${_cleanNumericStat(user.stats['主题'] ?? user.stats['帖子'])})',
                                              theme),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // 3. Tab 内容区 (多端自适应响应式排版 + 平滑过渡动画)
                            SliverToBoxAdapter(
                              child: AnimatedCrossFade(
                                duration: AppMotion.duration(context, 240),
                                sizeCurve: AppMotion.emphasized,
                                firstCurve: AppMotion.emphasized,
                                secondCurve: AppMotion.emphasized,
                                crossFadeState: _selectedTab == 0
                                    ? CrossFadeState.showFirst
                                    : CrossFadeState.showSecond,
                                firstChild: TickerMode(
                                    enabled: _selectedTab == 0,
                                    child: _buildProfileTab(user, theme)),
                                secondChild: TickerMode(
                                    enabled: _selectedTab == 1,
                                    child: _threadsVisited
                                        ? _buildThreadsTab(user, theme)
                                        : const SizedBox.shrink()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildBottomActions(context, user),
                  ],
                ),
              ),
            );
          }
        }
        return AnimatedSwitcher(
          duration: AppMotion.duration(context, 240),
          switchInCurve: AppMotion.emphasized,
          switchOutCurve: AppMotion.exit,
          child: content,
        );
      },
    );
  }

  Widget _staggerCard(Widget child, int index) {
    return AppFadeIn(
      key: ValueKey('space_card_${widget.uid}_$index'),
      index: index,
      child: child,
    );
  }

  Widget _buildProfileTab(UserSpace user, ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;
        if (isWide) {
          // PC 桌面端 / 平板宽屏：优雅双列卡片布局
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左列（约 380px 固定）：用户组、4 大核心统计、基本资料
                    SizedBox(
                      width: 380,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _staggerCard(_buildUsergroupCard(user, theme), 0),
                          const SizedBox(height: 12),
                          _staggerCard(_buildStatsCard(user, theme), 2),
                          const SizedBox(height: 12),
                          _staggerCard(_buildBasicInfoCard(user, theme), 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    // 右列（弹性铺满）：勋章墙、积分资产明细表、个人签名
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _staggerCard(_buildMedalCard(user, theme), 1),
                          const SizedBox(height: 12),
                          _staggerCard(_buildCreditsCard(user, theme), 3),
                          const SizedBox(height: 12),
                          _staggerCard(_buildSignatureCard(user, theme), 5),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 移动端 / 窄屏：单列流式卡片布局
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _staggerCard(_buildUsergroupCard(user, theme), 0),
                  const SizedBox(height: 10),
                  _staggerCard(_buildMedalCard(user, theme), 1),
                  const SizedBox(height: 10),
                  _staggerCard(_buildSignatureCard(user, theme), 2),
                  const SizedBox(height: 10),
                  _staggerCard(_buildStatsCard(user, theme), 3),
                  const SizedBox(height: 10),
                  _staggerCard(_buildCreditsCard(user, theme), 4),
                  const SizedBox(height: 10),
                  _staggerCard(_buildBasicInfoCard(user, theme), 5),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThreadsTab(UserSpace user, ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: UserThreadsPage(
            uid: user.uid,
            type: 'thread',
            title: '${user.username} 的主题',
            showAppBar: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String title, ThemeData theme) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _selectedTab = index;
          _threadsVisited = _threadsVisited || index == 1;
        }),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: AppMotion.duration(context, 200),
          curve: AppMotion.emphasized,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color:
                    isSelected ? theme.colorScheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              child: Text(title),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader(UserSpace user, ThemeData theme) {
    // 空间壁纸：优先 user.bgUrl，其次 AppConfig.spaceWallpaper，默认 klpbbs 官方风景空间壁纸
    const defaultBg =
        'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/1.png';
    final rawWallpaper = user.bgUrl.isNotEmpty
        ? user.bgUrl
        : (_isMe ? (AppConfig.spaceWallpaper ?? defaultBg) : defaultBg);
    // Keep the actual declared asset, including its animation format. Guessed
    // filename substitutions made the saved style and its space look different.
    final declared = Uri.tryParse(rawWallpaper);
    final resolved = declared == null
        ? null
        : Uri.parse(AppConfig.baseUrl).resolveUri(declared);
    final wallpaperUrl = resolved != null &&
            const {'http', 'https'}.contains(resolved.scheme) &&
            resolved.host.isNotEmpty &&
            resolved.userInfo.isEmpty
        ? resolved.toString()
        : defaultBg;
    final hasWallpaper = wallpaperUrl.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 空间壁纸或深色纯色背景
        CachedNetworkImage(
          imageUrl: wallpaperUrl,
          cacheKey: KlpbbsCacheManager.normalizeCacheKey(wallpaperUrl),
          cacheManager: KlpbbsCacheManager.instance,
          fit: BoxFit.cover,
          placeholder: (_, __) =>
              Container(color: theme.colorScheme.surfaceContainerHighest),
          errorWidget: (_, __, ___) => wallpaperUrl != defaultBg
              ? CachedNetworkImage(
                  imageUrl: defaultBg,
                  cacheKey: KlpbbsCacheManager.normalizeCacheKey(defaultBg),
                  cacheManager: KlpbbsCacheManager.instance,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceContainerHighest),
                )
              : Container(color: theme.colorScheme.surfaceContainerHighest),
        ),
        // 半透明微暗遮罩（确保文字在任何壁纸下均清晰可见）
        Container(
          color: Colors.black.withAlpha(hasWallpaper ? 110 : 40),
        ),
        // 用户信息卡 (居中响应式)
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Row(
                children: [
                  UserAvatarWidget(
                    reserveFrameSpace: true,
                    uid: user.uid,
                    author: user.username,
                    size: 64,
                    faceUrl: UserAvatarWidget.optionalFrame(user.faceUrl),
                    isOnline: user.isOnline,
                    showOnlineBadge: true,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(color: Colors.black54, blurRadius: 4)
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Builder(
                              builder: (context) {
                                final isOnline = _isMe || user.isOnline;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isOnline
                                        ? const Color(0xFF4CAF50).withAlpha(220)
                                        : Colors.black.withAlpha(120),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isOnline
                                          ? const Color(0xFF81C784)
                                          : Colors.white24,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.only(right: 4),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isOnline
                                              ? Colors.white
                                              : Colors.white54,
                                        ),
                                      ),
                                      Text(
                                        isOnline ? '在线' : '离线',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (user.stats['人气']?.isNotEmpty == true)
                              '${user.stats['人气']} 人气',
                            if (user.credits.isNotEmpty) '${user.credits} 积分',
                          ].join(' · '),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            shadows: [
                              Shadow(color: Colors.black38, blurRadius: 3)
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (user.gameProfile['性别'] == '男' ||
                                user.gameProfile['性别'] == '女')
                              _buildSmallBadge(
                                user.gameProfile['性别'] == '女' ? '♀ 女' : '♂ 男',
                                user.gameProfile['性别'] == '女'
                                    ? const Color(0xFFE91E63)
                                    : const Color(0xFF1976D2),
                              ),
                            _buildSmallBadge(
                              _formatUserLevel(user),
                              theme.colorScheme.secondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatUserLevel(UserSpace user) {
    final lvlName = user.levelName.trim();
    final lvl = user.level.trim();
    if (lvlName.isEmpty && lvl.isEmpty) return '注册会员';
    if (lvlName.isEmpty) return lvl;
    if (lvl.isEmpty) return lvlName;
    if (lvlName.toLowerCase().startsWith(lvl.toLowerCase()) ||
        lvlName.contains(lvl)) {
      return lvlName;
    }
    if (RegExp(r'^Lv\.\d+', caseSensitive: false).hasMatch(lvlName)) {
      return lvlName;
    }
    return '$lvl $lvlName';
  }

  Widget _buildSmallBadge(String text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildUsergroupCard(UserSpace user, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Text('用户组',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 14),
            _buildSmallBadge(
              _formatUserLevel(user),
              theme.colorScheme.secondary,
            ),
            const Spacer(),
            InkWell(
              onTap: () => _showUsergroupPrivilegesDialog(user),
              child: const Row(
                children: [
                  Text('用户组权限详情',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF57C00))),
                  Icon(Icons.chevron_right, size: 16, color: Color(0xFFF57C00)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedalCard(UserSpace user, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('勋章荣誉',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant)),
                const Spacer(),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MedalPage()),
                  ),
                  child: Row(
                    children: [
                      Text('勋章中心',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.primary)),
                      Icon(Icons.chevron_right,
                          size: 16, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: user.medals.isNotEmpty
                  ? ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: user.medals.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final m = user.medals[i];
                        return Tooltip(
                          message: '${m.name}\n${m.desc}',
                          child: CachedNetworkImage(
                            imageUrl: m.img,
                            cacheKey:
                                KlpbbsCacheManager.normalizeCacheKey(m.img),
                            cacheManager: KlpbbsCacheManager.instance,
                            httpHeaders: AppConfig.imageHeaders,
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.amber.withAlpha(30),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.military_tech,
                                  size: 20, color: Colors.amber),
                            ),
                          ),
                        );
                      },
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Text('暂无佩戴勋章',
                          style: TextStyle(
                              fontSize: 12, color: theme.colorScheme.outline)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureCard(UserSpace user, ThemeData theme) {
    final sigRaw = user.signature.isNotEmpty
        ? user.signature
        : (user.gameProfile['个人签名'] ?? '暂未设置个性签名');
    final sigHtml =
        sigRaw.contains('<') ? sigRaw : ComiisParser.bbcodeToHtml(sigRaw);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_rounded,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '个人签名',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InlineHtmlText(
                html: sigHtml,
                baseStyle: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (user.gameProfile['自定义头衔'] != null &&
                user.gameProfile['自定义头衔']!.isNotEmpty) ...[
              Divider(
                  height: 16,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildInfoRow('自定义头衔', user.gameProfile['自定义头衔']!, theme),
            ],
            Divider(
                height: 16,
                color: theme.colorScheme.outlineVariant.withAlpha(40)),
            InkWell(
              onTap: () => _showQrCodeDialog(user),
              child: Row(
                children: [
                  Text('二维码',
                      style: TextStyle(
                          fontSize: 13.5, color: theme.colorScheme.outline)),
                  const Spacer(),
                  Icon(Icons.qr_code,
                      size: 18, color: theme.colorScheme.outline),
                  Icon(Icons.chevron_right,
                      size: 18, color: theme.colorScheme.outline),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(UserSpace user, ThemeData theme) {
    if (!['主题', '帖子', '回复', '回帖', '好友', '人气']
        .any((key) => user.stats[key]?.isNotEmpty == true)) {
      return const SizedBox.shrink();
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            if (user.stats['主题']?.isNotEmpty == true ||
                user.stats['帖子']?.isNotEmpty == true)
              _buildClickableStat(
                '帖子',
                _cleanNumericStat(user.stats['主题'] ?? user.stats['帖子']),
                Icons.chat_bubble_outline_rounded,
                theme.colorScheme.primary,
                () => setState(() => _selectedTab = 1),
              ),
            if (user.stats['回复']?.isNotEmpty == true ||
                user.stats['回帖']?.isNotEmpty == true)
              _buildClickableStat(
                '回复',
                _cleanNumericStat(user.stats['回复'] ?? user.stats['回帖']),
                Icons.reply_rounded,
                const Color(0xFFFF9800),
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserThreadsPage(
                        uid: user.uid,
                        type: 'reply',
                        title: '${user.username} 的回复'),
                  ),
                ),
              ),
            if (user.stats['好友']?.isNotEmpty == true)
              _buildClickableStat(
                '好友',
                _cleanNumericStat(user.stats['好友']),
                Icons.people_outline_rounded,
                const Color(0xFF2196F3),
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FriendPage(
                      uid: user.uid,
                      username: user.username,
                      isMe: _isMe,
                    ),
                  ),
                ),
              ),
            if (user.stats['人气']?.isNotEmpty == true)
              _buildClickableStat(
                '人气',
                _cleanNumericStat(user.stats['人气']),
                Icons.local_fire_department_outlined,
                const Color(0xFFE91E63),
                null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditsCard(UserSpace user, ThemeData theme) {
    final assets = <String, String>{
      ...user.creditsDetail,
      if (user.credits.isNotEmpty) '积分': user.credits,
    }..removeWhere((key, value) => value.trim().isEmpty);
    if (assets.isEmpty) return const SizedBox.shrink();
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
            builder: (context, constraints) =>
                Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final entry in assets.entries)
                    SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: _buildAssetCell(entry.key, entry.value, theme)),
                  if (_isMe)
                    SizedBox(
                        width: constraints.maxWidth,
                        child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const CreditPage(initialTabIndex: 2))),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('积分记录'))),
                ])),
      ),
    );
  }

  Widget _buildBasicInfoCard(UserSpace user, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildFieldRow('用户ID', '${user.uid}', theme),
            if (user.gameProfile.containsKey('生日')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('生日', user.gameProfile['生日']!, theme),
            ],
            if (user.gameProfile.containsKey('基岩版用户名')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('基岩版用户名', user.gameProfile['基岩版用户名']!, theme),
            ],
            if (user.gameProfile.containsKey('网易用户名') ||
                user.gameProfile.containsKey('网易版用户名')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow(
                  '网易用户名',
                  (user.gameProfile['网易用户名'] ?? user.gameProfile['网易版用户名'])!,
                  theme),
            ],
            if (user.gameProfile.containsKey('QQ')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('QQ', user.gameProfile['QQ']!, theme),
            ],
            if (user.gameProfile.containsKey('代表作')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('代表作', user.gameProfile['代表作']!, theme),
            ],
            if (user.gameProfile.containsKey('性别')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('性别', user.gameProfile['性别']!, theme),
            ],
            if (user.gameProfile.containsKey('在线时间')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('在线时间', user.gameProfile['在线时间']!, theme),
            ],
            if (user.regdate.isNotEmpty ||
                user.gameProfile.containsKey('注册时间')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow(
                  '注册时间',
                  user.regdate.isNotEmpty
                      ? user.regdate
                      : user.gameProfile['注册时间']!,
                  theme),
            ],
            if (user.lastvisit.isNotEmpty ||
                user.gameProfile.containsKey('最后访问')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow(
                  '最后访问',
                  user.lastvisit.isNotEmpty
                      ? user.lastvisit
                      : user.gameProfile['最后访问']!,
                  theme),
            ],
            if (user.gameProfile.containsKey('上次活动时间')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('上次活动时间', user.gameProfile['上次活动时间']!, theme),
            ],
            if (user.gameProfile.containsKey('上次发表时间')) ...[
              Divider(
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('上次发表时间', user.gameProfile['上次发表时间']!, theme),
            ],
          ],
        ),
      ),
    );
  }

  static String _cleanNumericStat(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final m = RegExp(r'[\d,，]+(?:\.\d+)?\s*[万亿]?').firstMatch(raw.trim());
    return m?.group(0)?.trim() ?? '—';
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant))),
        Expanded(
          child: SelectableText(
            value,
            style:
                TextStyle(fontSize: 13.5, color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  Widget _buildClickableStat(String label, String count, IconData icon,
      Color color, VoidCallback? onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withAlpha(30),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              '$label $count',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetCell(String label, String val, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant)),
          const Spacer(),
          Text(
            val,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, String val, ThemeData theme) {
    var displayVal = val;
    if (label.contains('时间') || label.contains('访问')) {
      displayVal = displayVal.replaceAllMapped(
        RegExp(r'(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2})(\d{2})\b'),
        (m) => '${m[1]}:${m[2]}',
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: SelectableText(
            displayVal,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  /// 底部固定操作栏 (图二: [✎ 更新资料] [⚙ 装扮空间])
  Widget _buildBottomActions(BuildContext context, UserSpace user) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top:
              BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: _isMe
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: const Text('更新资料'),
                          onPressed: () {
                            Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          ProfileSettingsPage(uid: user.uid)),
                                )
                                .then((_) => _loadData());
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          icon:
                              const Icon(Icons.auto_awesome_outlined, size: 17),
                          label: const Text('装扮空间'),
                          onPressed: () {
                            Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                    builder: (_) => HomeStylePage(
                                      uid: user.uid,
                                      username: user.username,
                                    ),
                                  ),
                                )
                                .then((_) => _loadData());
                          },
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.person_add_alt, size: 16),
                          label: const Text('加好友'),
                          onPressed: () async {
                            final noteCtrl = TextEditingController();
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('申请添加「${user.username}」为好友'),
                                content: TextField(
                                  controller: noteCtrl,
                                  decoration: const InputDecoration(
                                    labelText: '附言（可选）',
                                    hintText: '例如：你好，我是...',
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLength: 50,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('发送申请'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !context.mounted) return;
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final ok = await KlpbbsApi.addFriend(
                                user.uid,
                                noteCtrl.text.trim(),
                              );
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(ok ? '好友请求已发送' : '请求失败，请稍后重试'),
                                ),
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('发送异常：$e')),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.chat_bubble_outline, size: 16),
                          label: const Text('私信'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PmDetailPage(
                                touid: user.uid,
                                toUsername: user.username,
                                isOnline: user.isOnline,
                                onlineStatusText: user.onlineStatusText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 快速打开当前登录用户的「我的空间」
class MySpacePage extends StatefulWidget {
  const MySpacePage({super.key});

  @override
  State<MySpacePage> createState() => _MySpacePageState();
}

class _MySpacePageState extends State<MySpacePage> {
  int? _uid;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final uid = await KlpbbsApi.getMyUid();
    if (mounted) {
      setState(() {
        _uid = uid;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        drawer: GlobalAppDrawer(),
        body: Center(child: AppLoadingIndicator()),
      );
    }

    if (_uid == null || _uid == 0) {
      return Scaffold(
        drawer: const GlobalAppDrawer(),
        drawerEdgeDragWidth: 50.0,
        appBar: AppBar(
          leading: const GlobalNavLeading(),
          leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
          title: const Text('我的空间'),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(100),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_pin_rounded,
                      size: 52, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 18),
                const Text(
                  '未登录账号',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '登录苦力怕论坛账号，查看您的积分资产、勋章荣誉与空间装扮',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.outline,
                      height: 1.4),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 240,
                  height: 44,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                                builder: (_) => const LoginPage()),
                          )
                          .then((_) => _checkLogin());
                    },
                    child: const Text(
                      '立即登录 / 注册',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return UserSpacePage(uid: _uid!, isMe: true);
  }
}
