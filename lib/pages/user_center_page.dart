import '../widgets/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/preload_service.dart';
import '../models/user_space.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/thread_card.dart';
import 'credit_page.dart';
import 'facemall_page.dart';
import 'favorite_hub_page.dart';
import 'membership_page.dart';
import 'friend_page.dart';
import 'homestyle_page.dart';
import 'login_page.dart';
import 'magic_page.dart';
import 'medal_page.dart';
import 'modcp_page.dart';
import '../models/user_role.dart';
import 'notice_page.dart';
import 'profile_settings_page.dart';
import 'settings_page.dart';
import 'sign_rank_page.dart';
import 'user_space_page.dart';
import 'user_threads_page.dart';

/// 苦力怕论坛全新独立个人中心（聚合资产、装扮、日常互动与账号管理）
class UserCenterPage extends StatefulWidget {
  const UserCenterPage({super.key});

  @override
  State<UserCenterPage> createState() => _UserCenterPageState();
}

class _UserCenterPageState extends State<UserCenterPage> {
  int? _myUid;
  UserSpace? _userSpace;
  DiscuzUserRole? _userRole;
  bool _loading = true;
  String _iron = '';
  String _credits = '';
  String _medalsCount = '';
  String _threadsCount = '';
  int _profileGeneration = 0;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_onSessionChanged);
    KlpbbsApi.profileChanges.addListener(_onProfileChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    _profileGeneration++;
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    KlpbbsApi.profileChanges.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _myUid = null;
      _userSpace = null;
      _userRole = null;
      _iron = _credits = _medalsCount = _threadsCount = '';
    });
    _loadProfile(forceRefresh: true);
  }

  void _onProfileChanged() {
    if (mounted) _loadProfile(forceRefresh: true, showLoading: false);
  }

  void _applyProfile(UserSpace space) {
    _userSpace = space;
    _iron = (space.creditsDetail['铁粒'] ?? space.stats['铁粒'] ?? '')
        .replaceAll(RegExp(r'铁粒|粒|[,，\s]'), '');
    _credits = space.credits.isNotEmpty
        ? space.credits
        : (space.creditsDetail['积分'] ?? '');
    _medalsCount = space.stats['勋章'] ??
        (space.medals.isNotEmpty ? '${space.medals.length}' : '');
    _threadsCount = space.stats['主题'] ?? space.stats['帖子'] ?? '';
    _loading = false;
  }

  static String _cleanPlainText(String html) {
    if (html.isEmpty) return '';
    return html
        .replaceAll(
            RegExp(r'<style[^>]*>[\s\S]*?<\/style>', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'<script[^>]*>[\s\S]*?<\/script>', caseSensitive: false),
            '')
        .replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _loadProfile(
      {bool forceRefresh = false, bool showLoading = true}) async {
    if (!mounted) return;
    final generation = ++_profileGeneration;
    final session = DioClient.sessionKey;
    bool current() =>
        mounted &&
        generation == _profileGeneration &&
        session == DioClient.sessionKey;
    try {
      final uid = await KlpbbsApi.getMyUid(forceRefresh: forceRefresh);
      if (!current()) return;
      if (uid == null || uid <= 0) {
        setState(() {
          _myUid = null;
          _userSpace = null;
          _userRole = null;
          _iron = _credits = _medalsCount = _threadsCount = '';
          _loading = false;
          _profileError = DioClient.isLoggedIn ? '暂未取得登录资料，请刷新重试' : null;
        });
        return;
      }
      setState(() {
        if (_myUid != uid) {
          _userSpace = null;
        }
        _myUid = uid;
        _profileError = null;
        final cached = forceRefresh
            ? null
            : PreloadService.instance
                .get<UserSpace>('user_space_$uid', ignoreExpired: true);
        if (cached != null) {
          _applyProfile(cached);
        }
        _loading = _userSpace == null || (forceRefresh && showLoading);
      });
      KlpbbsApi.getMyRole().then((role) {
        if (current()) setState(() => _userRole = role);
      }).catchError((_) {});
      final space =
          await KlpbbsApi.getUserSpace(uid, forceRefresh: forceRefresh);
      if (!current()) return;
      setState(() {
        if (space != null && space.uid == uid) {
          _applyProfile(space);
        } else {
          _loading = false;
          _profileError = '资料加载失败，请重试';
        }
      });
    } catch (_) {
      if (current()) {
        setState(() {
          _loading = false;
          _profileError = _userSpace == null ? '资料加载失败，请重试' : '刷新失败，已保留上次资料';
        });
      }
    }
  }

  void _openSpace() {
    if (_myUid != null && _myUid! > 0) {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => UserSpacePage(
                  uid: _myUid!, isMe: true, initialUser: _userSpace),
            ),
          )
          .then((_) => _loadProfile(showLoading: false));
    } else {
      _openLogin();
    }
  }

  void _openLogin() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (_) => const LoginPage()),
        )
        .then((_) => _loadProfile(forceRefresh: true));
  }

  Future<void> _handleLogout() async {
    final session = DioClient.sessionKey;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前论坛账号吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted && session == DioClient.sessionKey) {
      await KlpbbsApi.logout();
      await AppConfig.setMyFaceUrl(null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('已退出登录'), behavior: SnackBarBehavior.floating),
      );
      _loadProfile(forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        title: const Text('个人中心'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新资料',
            onPressed: () => _loadProfile(forceRefresh: true),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '应用设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: Column(children: [
        if (_loading && _userSpace != null) const AppLoadingBar(),
        if (_profileError != null)
          MaterialBanner(
            content: Text(_profileError!),
            actions: [
              TextButton(
                  onPressed: () => _loadProfile(forceRefresh: true),
                  child: const Text('重试'))
            ],
          ),
        Expanded(
            child: RefreshIndicator(
          onRefresh: () async {
            HapticFeedback.lightImpact();
            await _loadProfile(forceRefresh: true);
          },
          child: isDesktop
              ? _buildDesktopLayout(theme, colorScheme)
              : _buildMobileLayout(theme, colorScheme),
        )),
      ]),
    );
  }

  Widget _buildMobileLayout(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. 用户信息概览卡片
            _buildUserHeaderCard(theme, colorScheme),
            const SizedBox(height: 14),

            // 2. 核心资产快捷数字条 (铁粒 / 总积分 / 勋章 / 主题)
            _buildQuickAssetBar(theme, colorScheme),
            const SizedBox(height: 18),

            // 3. 个人资产与空间装扮
            _buildSectionTitle('资产与空间装扮', colorScheme),
            const SizedBox(height: 8),
            _buildCardGroup([
              _buildMenuTile(
                icon: Icons.account_balance_wallet_rounded,
                title: '积分中心',
                subtitle: '我的积分 / 积分转账 / 交易记录流水',
                trailingText: _iron.isEmpty ? null : '$_iron 铁粒',
                onTap: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                          builder: (_) => const CreditPage(initialTabIndex: 0)),
                    )
                    .then((_) => _loadProfile()),
              ),
              _buildMenuTile(
                icon: Icons.extension_rounded,
                title: '道具中心',
                subtitle: '道具商店 / 我的道具包 / 道具记录',
                onTap: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(builder: (_) => const MagicPage()),
                    )
                    .then((_) => _loadProfile()),
              ),
              _buildMenuTile(
                icon: Icons.military_tech_rounded,
                title: '勋章中心',
                subtitle: '勋章佩戴 / 勋章商城 / 勋章日志',
                trailingText: _medalsCount.isEmpty ? null : '$_medalsCount 枚',
                onTap: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(builder: (_) => const MedalPage()),
                    )
                    .then((_) => _loadProfile()),
              ),
              _buildMenuTile(
                icon: Icons.face_retouching_natural_rounded,
                title: '头像挂件',
                subtitle: '挂件商城 / 我的挂件 / 头像边框装扮',
                onTap: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                          builder: (_) => FacemallPage(
                              uid: _myUid, username: _userSpace?.username)),
                    )
                    .then((_) => _loadProfile()),
              ),
              _buildMenuTile(
                icon: Icons.wallpaper_rounded,
                title: '装扮空间',
                subtitle: '空间主题壁纸 / 主世界 / 地狱 / 可爱风格',
                onTap: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                          builder: (_) => HomeStylePage(
                              uid: _myUid, username: _userSpace?.username)),
                    )
                    .then((_) => _loadProfile()),
              ),
            ], colorScheme),
            const SizedBox(height: 18),

            // 4. 论坛日常与互动
            _buildSectionTitle('日常与论坛互动', colorScheme),
            const SizedBox(height: 8),
            _buildCardGroup([
              _buildMenuTile(
                icon: Icons.event_available_rounded,
                title: '每日签到',
                subtitle: '每日打卡 / 连续签到奖励 / 签到榜单',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SignRankPage()),
                ),
              ),
              _buildMenuTile(
                icon: Icons.article_rounded,
                title: '我的帖子',
                subtitle: '我发表的主题与回复历史',
                trailingText: _threadsCount.isEmpty ? null : '$_threadsCount 篇',
                onTap: () {
                  if (_myUid != null && _myUid! > 0) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UserThreadsPage(
                          uid: _myUid!,
                          type: 'thread',
                          title: '我的主题',
                        ),
                      ),
                    );
                  } else {
                    _openLogin();
                  }
                },
              ),
              _buildMenuTile(
                icon: Icons.bookmark_rounded,
                title: '我的收藏',
                subtitle: '收藏的主题与关注的版块',
                onTap: () {
                  if (_myUid != null && _myUid! > 0) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => FavoriteHubPage(uid: _myUid!)),
                    );
                  } else {
                    _openLogin();
                  }
                },
              ),
              _buildMenuTile(
                icon: Icons.notifications_rounded,
                title: '我的消息',
                subtitle: '系统提醒 / 坛友私信 / 互动回复通知',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NoticePage()),
                ),
              ),
              _buildMenuTile(
                icon: Icons.people_alt_rounded,
                title: '我的好友',
                subtitle: '好友列表与关注动态',
                onTap: () {
                  if (_myUid != null && _myUid! > 0) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => FriendPage(uid: _myUid!)),
                    );
                  } else {
                    _openLogin();
                  }
                },
              ),
            ], colorScheme),
            const SizedBox(height: 18),

            if (_userRole?.hasAnyModPermission == true) ...[
              _buildSectionTitle('管理控制台', colorScheme),
              const SizedBox(height: 8),
              _buildCardGroup([
                _buildMenuTile(
                  icon: Icons.admin_panel_settings_rounded,
                  title: '前台管理中心 (ModCP)',
                  subtitle: '违规举报跟进 / 违规用户禁言与封禁 / 主题管理',
                  trailingText: _userRole?.groupTitle ?? '管理组',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ModCpPage()),
                  ),
                ),
              ], colorScheme),
              const SizedBox(height: 18),
            ],

            // 5. 账号设置与系统
            _buildCardGroup([
              _buildMenuTile(
                  icon: Icons.workspace_premium_outlined,
                  title: '用户组与会员',
                  subtitle: 'VIP / SVIP、续费与权限对比',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MembershipPage()))),
            ], colorScheme),
            const SizedBox(height: 18),
            _buildSectionTitle('账号与应用设置', colorScheme),
            const SizedBox(height: 8),
            _buildCardGroup([
              _buildMenuTile(
                icon: Icons.manage_accounts_rounded,
                title: '个人资料设置',
                subtitle: '修改昵称、密码、个性签名档与公开资料',
                onTap: () {
                  if (_myUid != null && _myUid! > 0) {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                              builder: (_) => ProfileSettingsPage(uid: _myUid)),
                        )
                        .then((_) => _loadProfile());
                  } else {
                    _openLogin();
                  }
                },
              ),
              _buildMenuTile(
                icon: Icons.tune_rounded,
                title: '外观与偏好设置',
                subtitle: '主题模式、RGB 流光、字号大小与单实例保护',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
              ),
              if (_myUid != null && _myUid! > 0)
                _buildMenuTile(
                  icon: Icons.logout_rounded,
                  title: '退出登录',
                  subtitle: '退出当前账号或切换其他论坛账号',
                  isDestructive: true,
                  onTap: _handleLogout,
                )
              else
                _buildMenuTile(
                  icon: Icons.login_rounded,
                  title: '登录账号',
                  subtitle: '登录苦力怕论坛账号解锁全部特权',
                  onTap: _openLogin,
                ),
            ], colorScheme),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  /// 桌面端双栏自适应布局：左侧信息与资产名片 + 右侧常用功能网格
  Widget _buildDesktopLayout(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧 320px 个人名片与核心资产立柱
              SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildUserHeaderCard(theme, colorScheme),
                      const SizedBox(height: 12),
                      _buildQuickAssetBar(theme, colorScheme),
                      const SizedBox(height: 12),
                      _buildDesktopAccountCard(colorScheme),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // 右侧主功能网格
              Expanded(
                child: ListView(
                  children: [
                    _buildSectionTitle('资产与空间装扮', colorScheme),
                    const SizedBox(height: 8),
                    _buildFeatureGrid([
                      _buildGridCard(
                        icon: Icons.account_balance_wallet_rounded,
                        title: '积分中心',
                        subtitle: '我的积分 / 积分转账 / 交易记录流水',
                        trailingText: _iron.isEmpty ? null : '$_iron 铁粒',
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const CreditPage(initialTabIndex: 0)),
                            )
                            .then((_) => _loadProfile()),
                        colorScheme: colorScheme,
                      ),
                      _buildGridCard(
                        icon: Icons.military_tech_rounded,
                        title: '勋章中心',
                        subtitle: '勋章佩戴 / 勋章商城 / 勋章日志',
                        trailingText:
                            _medalsCount.isEmpty ? null : '$_medalsCount 枚',
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                  builder: (_) => const MedalPage()),
                            )
                            .then((_) => _loadProfile()),
                        colorScheme: colorScheme,
                      ),
                      _buildGridCard(
                        icon: Icons.extension_rounded,
                        title: '道具中心',
                        subtitle: '道具商店 / 我的道具包 / 道具记录',
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                  builder: (_) => const MagicPage()),
                            )
                            .then((_) => _loadProfile()),
                        colorScheme: colorScheme,
                      ),
                      _buildGridCard(
                        icon: Icons.face_retouching_natural_rounded,
                        title: '头像挂件',
                        subtitle: '挂件商城 / 我的挂件 / 头像边框装扮',
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                  builder: (_) => FacemallPage(
                                      uid: _myUid,
                                      username: _userSpace?.username)),
                            )
                            .then((_) => _loadProfile()),
                        colorScheme: colorScheme,
                      ),
                      _buildGridCard(
                        icon: Icons.wallpaper_rounded,
                        title: '装扮空间',
                        subtitle: '空间主题壁纸 / 主世界 / 地狱 / 可爱风格',
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                  builder: (_) => HomeStylePage(
                                      uid: _myUid,
                                      username: _userSpace?.username)),
                            )
                            .then((_) => _loadProfile()),
                        colorScheme: colorScheme,
                      ),
                    ]),
                    const SizedBox(height: 18),
                    _buildSectionTitle('日常与论坛互动', colorScheme),
                    const SizedBox(height: 8),
                    _buildFeatureGrid([
                      _buildGridCard(
                        icon: Icons.event_available_rounded,
                        title: '每日签到',
                        subtitle: '每日打卡 / 连续签到奖励 / 签到榜单',
                        onTap: () => Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                  builder: (_) => const SignRankPage()),
                            )
                            .then((_) => _loadProfile()),
                        colorScheme: colorScheme,
                      ),
                      _buildGridCard(
                        icon: Icons.notifications_rounded,
                        title: '消息通知',
                        subtitle: '系统提醒 / 回复互动 / 关注动态',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const NoticePage()),
                        ),
                        colorScheme: colorScheme,
                      ),
                      _buildGridCard(
                        icon: Icons.bookmark_rounded,
                        title: '我的收藏',
                        subtitle: '已收藏的精华贴与实用资源',
                        onTap: () {
                          if (_myUid != null && _myUid! > 0) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      FavoriteHubPage(uid: _myUid!)),
                            );
                          } else {
                            _openLogin();
                          }
                        },
                        colorScheme: colorScheme,
                      ),
                      _buildGridCard(
                        icon: Icons.article_rounded,
                        title: '我的主题与回复',
                        subtitle: '我发表的主题帖、社区回帖归档',
                        trailingText:
                            _threadsCount.isEmpty ? null : '$_threadsCount 帖',
                        onTap: () {
                          if (_myUid != null && _myUid! > 0) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => UserThreadsPage(
                                  uid: _myUid!,
                                  type: 'thread',
                                  title: '我的主题',
                                ),
                              ),
                            );
                          } else {
                            _openLogin();
                          }
                        },
                        colorScheme: colorScheme,
                      ),
                      _buildGridCard(
                        icon: Icons.people_alt_rounded,
                        title: '我的好友',
                        subtitle: '好友列表、在线状态与申请管理',
                        onTap: () {
                          if (_myUid != null && _myUid! > 0) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => FriendPage(uid: _myUid!)),
                            );
                          } else {
                            _openLogin();
                          }
                        },
                        colorScheme: colorScheme,
                      ),
                    ]),
                    const SizedBox(height: 18),
                    _buildSectionTitle('账号与应用设置', colorScheme),
                    const SizedBox(height: 8),
                    _buildFeatureGrid([
                      _buildGridCard(
                        icon: Icons.manage_accounts_rounded,
                        title: '个人资料设置',
                        subtitle: '修改昵称、密码、个性签名档与公开资料',
                        onTap: () {
                          if (_myUid != null && _myUid! > 0) {
                            Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          ProfileSettingsPage(uid: _myUid)),
                                )
                                .then((_) => _loadProfile());
                          } else {
                            _openLogin();
                          }
                        },
                        colorScheme: colorScheme,
                      ),
                      _buildGridCard(
                        icon: Icons.tune_rounded,
                        title: '外观与偏好设置',
                        subtitle: '主题模式、RGB 流光、字号大小与单实例保护',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SettingsPage()),
                        ),
                        colorScheme: colorScheme,
                      ),
                      _buildGridCard(
                          icon: Icons.workspace_premium_outlined,
                          title: '用户组与会员',
                          subtitle: 'VIP / SVIP、续费与权限对比',
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const MembershipPage())),
                          colorScheme: colorScheme),
                      if (_userRole?.hasAnyModPermission == true)
                        _buildGridCard(
                          icon: Icons.admin_panel_settings_rounded,
                          title: '前台管理中心 (ModCP)',
                          subtitle: '违规举报跟进 / 违规用户禁言与封禁 / 主题管理',
                          trailingText: _userRole?.groupTitle ?? '管理组',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ModCpPage()),
                          ),
                          colorScheme: colorScheme,
                        ),
                    ]),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 桌面端左侧账号操作小卡片
  Widget _buildDesktopAccountCard(ColorScheme colorScheme) {
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(50), width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.person_pin_outlined,
                color: colorScheme.primary, size: 20),
            title: const Text('个人空间主页',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right_rounded, size: 18),
            onTap: _openSpace,
            dense: true,
          ),
          Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(35)),
          if (_myUid != null && _myUid! > 0)
            ListTile(
              leading: const Icon(Icons.logout_rounded,
                  color: Colors.redAccent, size: 18),
              title: const Text('退出登录',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w500)),
              onTap: _handleLogout,
              dense: true,
            )
          else
            ListTile(
              leading: Icon(Icons.login_rounded,
                  color: colorScheme.primary, size: 18),
              title: const Text('登录账号',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              onTap: _openLogin,
              dense: true,
            ),
        ],
      ),
    );
  }

  /// 桌面端网格容器
  Widget _buildFeatureGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaled = MediaQuery.textScalerOf(context).scale(14) > 19;
        final count = constraints.maxWidth >= 810 && !scaled
            ? 3
            : constraints.maxWidth >= (scaled ? 660 : 440)
                ? 2
                : 1;
        final width = (constraints.maxWidth - (count - 1) * 10) / count;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < children.length; i++)
            SizedBox(
                width: width, child: AppFadeIn(index: i, child: children[i])),
        ]);
      },
    );
  }

  /// 桌面端功能小卡片
  Widget _buildGridCard({
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    String? trailingText,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool isDestructive = false,
  }) {
    final effectiveIconColor =
        iconColor ?? (isDestructive ? Colors.redAccent : colorScheme.primary);
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(50), width: 0.8),
      ),
      clipBehavior: Clip.none,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDestructive
                      ? Colors.redAccent.withAlpha(20)
                      : colorScheme.surfaceContainerHighest.withAlpha(140),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: effectiveIconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailingText != null && trailingText.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(120),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    trailingText,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: colorScheme.outline.withAlpha(120)),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部用户信息展示卡片
  Widget _buildUserHeaderCard(ThemeData theme, ColorScheme colorScheme) {
    if (_loading && _userSpace == null) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
        ),
        child: const Center(child: AppLoadingIndicator()),
      );
    }

    if (_myUid == null || _myUid! <= 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: colorScheme.surfaceContainerHighest,
              child: Icon(Icons.person_outline_rounded,
                  size: 30, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '尚未登录论坛账号',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击此处立即登录，同步个人资产与帖子',
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: _openLogin,
              child: const Text('登录 / 注册',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    final user = _userSpace;
    if (user == null) {
      return ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text('UID: $_myUid'),
        subtitle: const Text('资料暂未加载，点击重试'),
        trailing: const Icon(Icons.refresh),
        onTap: () => _loadProfile(forceRefresh: true),
      );
    }

    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(50), width: 0.8),
      ),
      child: InkWell(
        onTap: _openSpace,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // 用户头像（叠放挂件）
              UserAvatarWidget(
                reserveFrameSpace: true,
                uid: _myUid,
                author: user.username,
                faceUrl: UserAvatarWidget.optionalFrame(user.faceUrl),
                size: 64,
              ),
              const SizedBox(width: 16),
              // 用户资料信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            user.group.isNotEmpty
                                ? user.group
                                : (user.levelName.isNotEmpty
                                    ? user.levelName
                                    : (_userRole?.groupTitle.isNotEmpty == true
                                        ? _userRole!.groupTitle
                                        : '用户组待加载')),
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'UID: $_myUid${_threadsCount.isEmpty ? '' : '   ·   $_threadsCount 主题'}',
                      style: TextStyle(
                          color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _cleanPlainText(user.signature).isNotEmpty
                          ? _cleanPlainText(user.signature)
                          : '点击进入个人空间查看详细主页与动态',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: colorScheme.onSurfaceVariant.withAlpha(180),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: colorScheme.outline.withAlpha(120)),
            ],
          ),
        ),
      ),
    );
  }

  /// 核心资产快捷数据栏（铁粒 / 总积分 / 勋章 / 主题数）
  Widget _buildQuickAssetBar(ThemeData theme, ColorScheme colorScheme) {
    if ([_iron, _credits, _medalsCount, _threadsCount]
        .every((value) => value.isEmpty)) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 350;
        final ironItem = _buildAssetNumberItem(
          icon: Icons.toll_rounded,
          label: '铁粒余额',
          value: _iron,
          color: colorScheme.primary,
          onTap: () => Navigator.of(context)
              .push(
                MaterialPageRoute(
                    builder: (_) => const CreditPage(initialTabIndex: 0)),
              )
              .then((_) => _loadProfile()),
        );
        final creditsItem = _buildAssetNumberItem(
          icon: Icons.stars_rounded,
          label: '论坛积分',
          value: _credits,
          color: colorScheme.primary,
          onTap: () => Navigator.of(context)
              .push(
                MaterialPageRoute(
                    builder: (_) => const CreditPage(initialTabIndex: 0)),
              )
              .then((_) => _loadProfile()),
        );
        final medalsItem = _buildAssetNumberItem(
          icon: Icons.military_tech_rounded,
          label: '勋章数量',
          value: _medalsCount,
          color: colorScheme.primary,
          onTap: () => Navigator.of(context)
              .push(
                MaterialPageRoute(builder: (_) => const MedalPage()),
              )
              .then((_) => _loadProfile()),
        );
        final threadsItem = _buildAssetNumberItem(
          icon: Icons.edit_note_rounded,
          label: '发表主题',
          value: _threadsCount,
          color: colorScheme.primary,
          onTap: () {
            if (_myUid != null && _myUid! > 0) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserThreadsPage(
                    uid: _myUid!,
                    type: 'thread',
                    title: '我的主题',
                  ),
                ),
              );
            } else {
              _openLogin();
            }
          },
        );

        if (isCompact) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    if (_iron.isNotEmpty) Expanded(child: ironItem),
                    if (_iron.isNotEmpty && _credits.isNotEmpty)
                      _buildDivider(colorScheme),
                    if (_credits.isNotEmpty) Expanded(child: creditsItem),
                  ],
                ),
                Divider(
                    height: 10,
                    thickness: 0.6,
                    color: colorScheme.outlineVariant.withAlpha(35)),
                Row(
                  children: [
                    if (_medalsCount.isNotEmpty) Expanded(child: medalsItem),
                    if (_medalsCount.isNotEmpty && _threadsCount.isNotEmpty)
                      _buildDivider(colorScheme),
                    if (_threadsCount.isNotEmpty) Expanded(child: threadsItem),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (_iron.isNotEmpty) Expanded(child: ironItem),
              if (_credits.isNotEmpty) Expanded(child: creditsItem),
              if (_medalsCount.isNotEmpty) Expanded(child: medalsItem),
              if (_threadsCount.isNotEmpty) Expanded(child: threadsItem),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAssetNumberItem({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: effectiveColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant.withAlpha(190),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Container(
      width: 1,
      height: 24,
      color: colorScheme.outlineVariant.withAlpha(50),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: colorScheme.primary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildCardGroup(List<Widget> children, ColorScheme colorScheme) {
    return Material(
      color: colorScheme.surface,
      elevation: 0.5,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.6,
                color: colorScheme.outlineVariant.withAlpha(35),
              ),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    String? trailingText,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveIconColor =
        iconColor ?? (isDestructive ? Colors.redAccent : colorScheme.primary);
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isDestructive
              ? Colors.redAccent.withAlpha(20)
              : colorScheme.surfaceContainerHighest.withAlpha(140),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: effectiveIconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDestructive ? Colors.redAccent : colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          color: colorScheme.onSurfaceVariant.withAlpha(180),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) ...[
            Text(
              trailingText,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Icon(Icons.chevron_right_rounded,
              size: 18, color: colorScheme.outline.withAlpha(120)),
        ],
      ),
      onTap: onTap,
    );
  }
}
