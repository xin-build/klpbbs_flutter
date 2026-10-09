import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/main_tab_controller.dart';
import '../core/preload_service.dart';
import '../models/user_space.dart';
import '../pages/credit_page.dart';
import '../pages/membership_page.dart';
import '../pages/darkroom_page.dart';
import '../pages/favorite_hub_page.dart';
import '../pages/guide_page.dart';
import '../pages/login_page.dart';
import '../pages/magic_page.dart';
import '../pages/modcp_page.dart';
import '../models/user_role.dart';
import '../pages/notice_page.dart';
import '../pages/papa_ai_chat_page.dart';
import '../pages/pm_inbox_page.dart';
import '../pages/profile_settings_page.dart';
import '../pages/ranklist_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../pages/task_page.dart';
import '../pages/user_space_page.dart';
import '../pages/user_threads_page.dart';
import '../pages/web_login_page.dart';
import '../services/push_notification_service.dart';
import 'user_avatar_widget.dart';
import 'responsive_layout.dart';
import 'app_motion.dart';

/// 全站统一左侧边栏抽屉组件
/// 拥有精致的现代卡片式头部、全站核心版块直达、个人互动中心与系统设置
class GlobalAppDrawer extends StatefulWidget {
  final int? currentTabIndex;

  const GlobalAppDrawer({super.key, this.currentTabIndex});

  @override
  State<GlobalAppDrawer> createState() => _GlobalAppDrawerState();
}

class _GlobalAppDrawerState extends State<GlobalAppDrawer> {
  int? _myUid;
  String? _myUsername;
  DiscuzUserRole? _userRole;
  int _userGeneration = 0;

  @override
  void initState() {
    super.initState();
    _myUid = KlpbbsApi.currentCachedMyUid;
    _myUsername = KlpbbsApi.currentCachedMyUsername;
    if (_myUid != null && _myUsername == null) {
      final cachedSpace = PreloadService.instance.get<UserSpace>(
        'user_space_$_myUid',
        ignoreExpired: true,
      );
      if (cachedSpace != null && cachedSpace.username.isNotEmpty) {
        _myUsername = cachedSpace.username;
      }
    }
    DioClient.sessionChanges.addListener(_onSessionChanged);
    KlpbbsApi.profileChanges.addListener(_onProfileChanged);
    _loadUser();
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    KlpbbsApi.profileChanges.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    setState(() {
      _myUid = null;
      _myUsername = null;
      _userRole = null;
    });
    _loadUser();
  }

  void _onProfileChanged() {
    if (mounted) _loadUser(forceRefresh: true);
  }

  Future<void> _loadUser({bool forceRefresh = false}) async {
    final generation = ++_userGeneration;
    final session = DioClient.sessionKey;
    try {
      final uid = await KlpbbsApi.getMyUid();
      if (!mounted ||
          session != DioClient.sessionKey ||
          generation != _userGeneration) {
        return;
      }
      if (uid != null && uid > 0) {
        String? name = KlpbbsApi.currentCachedMyUsername;
        final cachedSpace = forceRefresh
            ? await KlpbbsApi.getUserSpace(uid, forceRefresh: true)
            : PreloadService.instance.get<UserSpace>(
                'user_space_$uid',
                ignoreExpired: true,
              );
        if (!mounted ||
            session != DioClient.sessionKey ||
            generation != _userGeneration) {
          return;
        }
        if (cachedSpace != null &&
            cachedSpace.uid == uid &&
            cachedSpace.username.isNotEmpty) {
          name = cachedSpace.username;
        }
        final role = await KlpbbsApi.getMyRole();
        if (!mounted ||
            session != DioClient.sessionKey ||
            generation != _userGeneration) {
          return;
        }
        setState(() {
          _myUid = uid;
          _myUsername = name;
          _userRole = role;
        });
      }
    } catch (_) {
      // Keep the session-checked cached identity when a background read fails.
    }
  }

  void _closeDrawer() {
    if (AdaptiveScaffold.isDesktopDrawerOpen) {
      AdaptiveScaffold.closeMainDrawer();
      return;
    }
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen == true) {
      scaffold?.closeDrawer();
      return;
    }
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  void _switchRootTab(int index) {
    _closeDrawer();
    final nav = Navigator.of(context);
    // 如果在子页面，回到首页
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
    mainTabIndex.value = index;
  }

  Future<T?> _pushPage<T>(Widget page) {
    _closeDrawer();
    return Navigator.of(context)
        .push<T>(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = DioClient.isLoggedIn && _myUid != null;
    final curIdx = widget.currentTabIndex ?? mainTabIndex.value;

    return Drawer(
      backgroundColor: colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  12, MediaQuery.paddingOf(context).top + 12, 12, 8),
              child: Material(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => isLoggedIn
                      ? _pushPage(UserSpacePage(uid: _myUid!, isMe: true))
                      : _pushPage(const LoginPage()),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isLoggedIn)
                                  UserAvatarWidget(
                                      uid: _myUid,
                                      author: _myUsername ?? '',
                                      reserveFrameSpace: true,
                                      size: 52)
                                else
                                  CircleAvatar(
                                      radius: 26,
                                      backgroundColor:
                                          colorScheme.surfaceContainer,
                                      child: Icon(Icons.person_outline_rounded,
                                          color: colorScheme.primary,
                                          size: 30)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(
                                        isLoggedIn
                                            ? _myUsername ?? '论坛账号'
                                            : '登录论坛',
                                        key: const ValueKey(
                                            'drawer-account-name'),
                                        softWrap: true,
                                        style: TextStyle(
                                            color:
                                                colorScheme.onPrimaryContainer,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600))),
                                IconButton(
                                    key: const ValueKey('drawer-close'),
                                    onPressed: _closeDrawer,
                                    tooltip: '关闭侧边栏',
                                    color: colorScheme.onPrimaryContainer,
                                    style: IconButton.styleFrom(
                                        minimumSize: const Size(48, 48)),
                                    icon: const Icon(Icons.close_rounded,
                                        size: 20)),
                              ]),
                          const SizedBox(height: 10),
                          Text(isLoggedIn ? 'UID $_myUid · 个人空间' : '查看消息与我的收藏',
                              key: const ValueKey('drawer-account-uid'),
                              softWrap: true,
                              style: TextStyle(
                                  color: colorScheme.onPrimaryContainer
                                      .withAlpha(190),
                                  fontSize: 12.5)),
                          if (isLoggedIn) ...[
                            const SizedBox(height: 14),
                            Row(children: [
                              _buildHeaderChip(
                                  icon: Icons.military_tech_outlined,
                                  label: '勋章',
                                  onTap: () => _switchRootTab(3)),
                              const SizedBox(width: 6),
                              _buildHeaderChip(
                                  icon: Icons.account_balance_wallet_outlined,
                                  label: '积分',
                                  onTap: () => _pushPage(const CreditPage())),
                              const SizedBox(width: 6),
                              _buildHeaderChip(
                                  icon: Icons.auto_fix_high_outlined,
                                  label: '道具',
                                  onTap: () => _pushPage(const MagicPage())),
                            ]),
                          ],
                        ]),
                  ),
                ),
              ),
            ),

            // 2. 抽屉导航列表
            Expanded(
              child: ListView(
                key: const ValueKey('drawer-navigation-list'),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                children: [
                  _buildSectionHeader('全站导航'),
                  _buildNavItem(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    title: '论坛首页',
                    isSelected: curIdx == 0,
                    onTap: () => _switchRootTab(0),
                  ),
                  _buildNavItem(
                    icon: Icons.forum_outlined,
                    selectedIcon: Icons.forum_rounded,
                    title: '社区版块',
                    isSelected: curIdx == 1,
                    onTap: () => _switchRootTab(1),
                  ),
                  _buildNavItem(
                    icon: Icons.smart_toy_outlined,
                    selectedIcon: Icons.smart_toy_rounded,
                    title: '帕帕 AI 助手',
                    onTap: () => _pushPage(const PapaAiChatPage()),
                  ),
                  _buildNavItem(
                    icon: Icons.event_available_outlined,
                    selectedIcon: Icons.event_available_rounded,
                    title: '每日签到',
                    isSelected: curIdx == 2,
                    onTap: () => _switchRootTab(2),
                  ),
                  _buildNavItem(
                    icon: Icons.military_tech_outlined,
                    selectedIcon: Icons.military_tech_rounded,
                    title: '勋章中心',
                    isSelected: curIdx == 3,
                    onTap: () => _switchRootTab(3),
                  ),
                  _buildNavItem(
                    icon: Icons.account_circle_outlined,
                    selectedIcon: Icons.account_circle_rounded,
                    title: '个人中心',
                    isSelected: curIdx == 4,
                    onTap: () => _switchRootTab(4),
                  ),
                  _buildNavItem(
                    icon: Icons.local_fire_department_outlined,
                    selectedIcon: Icons.local_fire_department_rounded,
                    title: '论坛导读',
                    onTap: () => _pushPage(const GuidePage()),
                  ),
                  _buildNavItem(
                    icon: Icons.search_rounded,
                    selectedIcon: Icons.search_rounded,
                    title: '全站搜索',
                    onTap: () => _pushPage(const SearchPage()),
                  ),
                  _buildNavItem(
                    icon: Icons.leaderboard_outlined,
                    selectedIcon: Icons.leaderboard_rounded,
                    title: '排行榜',
                    onTap: () => _pushPage(const RanklistPage()),
                  ),
                  _buildNavItem(
                    icon: Icons.gavel_outlined,
                    selectedIcon: Icons.gavel_rounded,
                    title: '封神榜 (违规公示)',
                    onTap: () => _pushPage(const DarkroomPage()),
                  ),
                  const Divider(height: 16),
                  _buildNavItem(
                      icon: Icons.workspace_premium_outlined,
                      selectedIcon: Icons.workspace_premium_rounded,
                      title: '用户组与会员',
                      onTap: () => _pushPage(const MembershipPage())),
                  const Divider(height: 16),
                  _buildSectionHeader('互动与个人'),
                  ListenableBuilder(
                    listenable: PushNotificationService.instance,
                    builder: (context, _) {
                      final unreadNotices =
                          PushNotificationService.instance.unreadNotices;
                      return _buildNavItem(
                        icon: Icons.notifications_outlined,
                        selectedIcon: Icons.notifications_rounded,
                        title: '消息提醒',
                        badgeCount: unreadNotices,
                        onTap: () => _pushPage(const NoticePage()),
                      );
                    },
                  ),
                  ListenableBuilder(
                    listenable: PushNotificationService.instance,
                    builder: (context, _) {
                      final unreadPm =
                          PushNotificationService.instance.unreadPm;
                      return _buildNavItem(
                        icon: Icons.mail_outline_rounded,
                        selectedIcon: Icons.mail_rounded,
                        title: '我的私信',
                        badgeCount: unreadPm,
                        onTap: () => _pushPage(const PmInboxPage()),
                      );
                    },
                  ),
                  if (isLoggedIn) ...[
                    _buildNavItem(
                      icon: Icons.article_outlined,
                      selectedIcon: Icons.article_rounded,
                      title: '我的帖子',
                      onTap: () => _pushPage(UserThreadsPage(
                          uid: _myUid!, type: 'thread', title: '我的帖子')),
                    ),
                    _buildNavItem(
                      icon: Icons.star_border_rounded,
                      selectedIcon: Icons.star_rounded,
                      title: '我的收藏',
                      onTap: () => _pushPage(FavoriteHubPage(uid: _myUid!)),
                    ),
                    _buildNavItem(
                      icon: Icons.task_alt_rounded,
                      selectedIcon: Icons.task_alt_rounded,
                      title: '任务中心',
                      onTap: () => _pushPage(const TaskPage()),
                    ),
                    _buildNavItem(
                      icon: Icons.manage_accounts_outlined,
                      selectedIcon: Icons.manage_accounts_rounded,
                      title: '资料设置',
                      onTap: () => _pushPage(ProfileSettingsPage(uid: _myUid)),
                    ),
                  ],
                  if (_userRole?.hasAnyModPermission == true) ...[
                    const Divider(height: 16),
                    _buildSectionHeader('管理权限'),
                    _buildNavItem(
                      icon: Icons.admin_panel_settings_outlined,
                      selectedIcon: Icons.admin_panel_settings_rounded,
                      title: '前台管理中心 (ModCP)',
                      color: colorScheme.primary,
                      onTap: () => _pushPage(const ModCpPage()),
                    ),
                  ],
                  const Divider(height: 16),
                  _buildSectionHeader('系统与设置'),
                  _buildNavItem(
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings_rounded,
                    title: '应用设置',
                    onTap: () => _pushPage(const SettingsPage()),
                  ),
                  _buildNavItem(
                    icon: Icons.web_rounded,
                    selectedIcon: Icons.web_rounded,
                    title: '网页版登录 / 验证',
                    onTap: () {
                      _pushPage<bool>(const WebLoginPage()).then((res) {
                        if (res == true && mounted) _loadUser();
                      });
                    },
                  ),
                  if (isLoggedIn)
                    _buildNavItem(
                      icon: Icons.logout_rounded,
                      selectedIcon: Icons.logout_rounded,
                      title: '退出登录',
                      color: Colors.redAccent,
                      onTap: () {
                        _closeDrawer();
                        KlpbbsApi.logout().then((_) {
                          if (mounted) setState(() => _myUid = null);
                        });
                      },
                    )
                  else
                    _buildNavItem(
                      icon: Icons.login_rounded,
                      selectedIcon: Icons.login_rounded,
                      title: '登录账号',
                      color: colorScheme.primary,
                      onTap: () {
                        _pushPage<bool>(const LoginPage()).then((res) {
                          if (res == true && mounted) _loadUser();
                        });
                      },
                    ),
                ],
              ),
            ),

            // 3. 底部版权与版本信息
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant.withAlpha(40),
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded,
                      size: 16, color: colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '苦力怕论坛客户端 ${AppConfig.versionDisplay}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderChip(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
        child: FilledButton.tonal(
      key: ValueKey('drawer-shortcut-$label'),
      onPressed: onTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        backgroundColor: scheme.surfaceContainerLow.withAlpha(170),
        foregroundColor: scheme.onPrimaryContainer,
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 44),
      ),
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18),
            const SizedBox(width: 4),
            Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13))),
          ])),
    ));
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData selectedIcon,
    required String title,
    required VoidCallback onTap,
    bool isSelected = false,
    int badgeCount = 0,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final itemColor = color ??
        (isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurface);

    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
            key: ValueKey('drawer-item-$title'),
            color: isSelected
                ? colorScheme.secondaryContainer
                : Colors.transparent,
            animationDuration: AppMotion.duration(context, 160),
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              minTileHeight: 48,
              minLeadingWidth: 24,
              horizontalTitleGap: 16,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              shape: const StadiumBorder(),
              selected: isSelected,
              leading: badgeCount > 0
                  ? Badge(
                      label: Text('$badgeCount'),
                      child: Icon(isSelected ? selectedIcon : icon,
                          color: itemColor, size: 24),
                    )
                  : Icon(isSelected ? selectedIcon : icon,
                      color: itemColor, size: 24),
              title: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: itemColor,
                ),
              ),
              onTap: onTap,
            )));
  }
}
