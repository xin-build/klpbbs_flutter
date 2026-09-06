import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/main_tab_controller.dart';
import '../core/preload_service.dart';
import '../models/user_space.dart';
import '../pages/credit_page.dart';
import '../pages/darkroom_page.dart';
import '../pages/favorite_forums_page.dart';
import '../pages/guide_page.dart';
import '../pages/login_page.dart';
import '../pages/magic_page.dart';
import '../pages/notice_page.dart';
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
import 'package:cached_network_image/cached_network_image.dart';
import '../core/cache_manager.dart';
import 'responsive_layout.dart';

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
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = await KlpbbsApi.getMyUid();
    if (!mounted) return;
    if (uid != null && uid > 0) {
      String? name;
      final cachedSpace = PreloadService.instance.get<UserSpace>(
        'user_space_$uid',
        ignoreExpired: true,
      );
      if (cachedSpace != null && cachedSpace.username.isNotEmpty) {
        name = cachedSpace.username;
      }
      setState(() {
        _myUid = uid;
        _myUsername = name;
      });
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
    return Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = DioClient.isLoggedIn && _myUid != null;
    final curIdx = widget.currentTabIndex ?? mainTabIndex.value;

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // 1. 顶部用户信息卡片
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 16,
                16,
                16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.secondary,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isLoggedIn
                  ? InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        _pushPage(UserSpacePage(uid: _myUid!, isMe: true));
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(40),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                 child: ClipOval(
                                   child: CachedNetworkImage(
                                     imageUrl: AppConfig.avatarUrl(_myUid!, size: 'middle'),
                                     cacheManager: KlpbbsCacheManager.instance,
                                     httpHeaders: AppConfig.imageHeaders,
                                     width: 52,
                                     height: 52,
                                     fit: BoxFit.cover,
                                     errorWidget: (_, __, ___) => const CircleAvatar(
                                       radius: 26,
                                       child: Icon(Icons.person, size: 28),
                                     ),
                                   ),
                                 ),
                               ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _myUsername ?? '苦力怕居民',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(45),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'UID: $_myUid  点击进入空间 >',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // 快捷入口小芯片
                          Row(
                            children: [
                              _buildHeaderChip(
                                icon: Icons.military_tech_rounded,
                                label: '勋章',
                                onTap: () => _switchRootTab(3),
                              ),
                              const SizedBox(width: 8),
                              _buildHeaderChip(
                                icon: Icons.account_balance_wallet_rounded,
                                label: '积分',
                                onTap: () => _pushPage(const CreditPage()),
                              ),
                              const SizedBox(width: 8),
                              _buildHeaderChip(
                                icon: Icons.auto_fix_high_rounded,
                                label: '道具',
                                onTap: () => _pushPage(const MagicPage()),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        _pushPage(const LoginPage());
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.white.withAlpha(50),
                              child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 30),
                            ),
                            const SizedBox(width: 14),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '点击登录账号',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '登录体验苦力怕论坛全功能',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // 2. 抽屉导航列表
            Expanded(
              child: ListView(
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
                    title: '综合排行榜',
                    onTap: () => _pushPage(const RanklistPage()),
                  ),
                  _buildNavItem(
                    icon: Icons.gavel_outlined,
                    selectedIcon: Icons.gavel_rounded,
                    title: '封神榜 (小黑屋)',
                    onTap: () => _pushPage(const DarkroomPage()),
                  ),

                  const Divider(height: 16),
                  _buildSectionHeader('互动与个人'),
                  ListenableBuilder(
                    listenable: PushNotificationService.instance,
                    builder: (context, _) {
                      final unread = PushNotificationService.instance.unreadCount;
                      return _buildNavItem(
                        icon: Icons.notifications_outlined,
                        selectedIcon: Icons.notifications_rounded,
                        title: '消息提醒',
                        badgeCount: unread,
                        onTap: () => _pushPage(const NoticePage()),
                      );
                    },
                  ),
                  _buildNavItem(
                    icon: Icons.mail_outline_rounded,
                    selectedIcon: Icons.mail_rounded,
                    title: '我的私信',
                    onTap: () => _pushPage(const PmInboxPage()),
                  ),
                  if (isLoggedIn) ...[
                    _buildNavItem(
                      icon: Icons.article_outlined,
                      selectedIcon: Icons.article_rounded,
                      title: '我的帖子',
                      onTap: () => _pushPage(UserThreadsPage(uid: _myUid!, type: 'thread', title: '我的帖子')),
                    ),
                    _buildNavItem(
                      icon: Icons.star_border_rounded,
                      selectedIcon: Icons.star_rounded,
                      title: '收藏版块',
                      onTap: () => _pushPage(FavoriteForumsPage(uid: _myUid!)),
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
                        Navigator.of(context).pop();
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
                  Icon(Icons.terminal_rounded, size: 16, color: colorScheme.outline),
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

  Widget _buildHeaderChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.white.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
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
    final itemColor = color ?? (isSelected ? colorScheme.primary : colorScheme.onSurface);

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withAlpha(90),
      leading: badgeCount > 0
          ? Badge(
              label: Text('$badgeCount'),
              child: Icon(isSelected ? selectedIcon : icon, color: itemColor, size: 22),
            )
          : Icon(isSelected ? selectedIcon : icon, color: itemColor, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: itemColor,
        ),
      ),
      onTap: onTap,
    );
  }
}
