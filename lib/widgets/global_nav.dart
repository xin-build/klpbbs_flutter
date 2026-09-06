import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/main_tab_controller.dart';
import '../pages/credit_page.dart';
import '../pages/darkroom_page.dart';
import '../pages/guide_page.dart';
import '../pages/login_page.dart';
import '../pages/magic_page.dart';
import '../pages/notice_page.dart';
import '../pages/profile_settings_page.dart';
import '../pages/ranklist_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../services/push_notification_service.dart';
import 'app_back_button.dart';
import 'global_app_drawer.dart';
import 'responsive_layout.dart';

class _NavSheetItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int idx;
  final Color color;
  final int badgeCount;

  const _NavSheetItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.idx,
    required this.color,
    this.badgeCount = 0,
  });
}

/// 全局移动端导航菜单：从任意页面弹出精致的网格导航抽屉（原站克米悬浮菜单与全局导航）。
void showGlobalNavSheet(BuildContext context) {
  final unread = PushNotificationService.instance.unreadCount;
  final items = <_NavSheetItem>[
    const _NavSheetItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: '首页',
      idx: 0,
      color: Color(0xFF2196F3),
    ),
    const _NavSheetItem(
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum_rounded,
      label: '版块',
      idx: 1,
      color: Color(0xFF009688),
    ),
    const _NavSheetItem(
      icon: Icons.event_available_outlined,
      selectedIcon: Icons.event_available_rounded,
      label: '签到',
      idx: 2,
      color: Color(0xFFFF9800),
    ),
    const _NavSheetItem(
      icon: Icons.military_tech_outlined,
      selectedIcon: Icons.military_tech,
      label: '勋章',
      idx: 3,
      color: Color(0xFFE91E63),
    ),
    const _NavSheetItem(
      icon: Icons.account_circle_outlined,
      selectedIcon: Icons.account_circle,
      label: '个人中心',
      idx: 4,
      color: Color(0xFF9C27B0),
    ),
    const _NavSheetItem(
      icon: Icons.local_fire_department_outlined,
      selectedIcon: Icons.local_fire_department_rounded,
      label: '导读',
      idx: 11,
      color: Color(0xFFFF5722),
    ),
    const _NavSheetItem(
      icon: Icons.search_outlined,
      selectedIcon: Icons.search_rounded,
      label: '搜索',
      idx: 12,
      color: Color(0xFF3F51B5),
    ),
    const _NavSheetItem(
      icon: Icons.leaderboard_outlined,
      selectedIcon: Icons.leaderboard_rounded,
      label: '排行榜',
      idx: 8,
      color: Color(0xFFFF9800),
    ),
    const _NavSheetItem(
      icon: Icons.auto_fix_high_outlined,
      selectedIcon: Icons.auto_fix_high,
      label: '道具中心',
      idx: 15,
      color: Color(0xFF00BCD4),
    ),
    const _NavSheetItem(
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      label: '积分中心',
      idx: 14,
      color: Color(0xFF4CAF50),
    ),
    const _NavSheetItem(
      icon: Icons.gavel_outlined,
      selectedIcon: Icons.gavel_rounded,
      label: '封神榜',
      idx: 13,
      color: Color(0xFF795548),
    ),
    _NavSheetItem(
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications_rounded,
      label: '消息提醒',
      idx: 10,
      color: const Color(0xFFE91E63),
      badgeCount: unread,
    ),
    const _NavSheetItem(
      icon: Icons.manage_accounts_outlined,
      selectedIcon: Icons.manage_accounts,
      label: '资料设置',
      idx: 6,
      color: Color(0xFF607D8B),
    ),
    const _NavSheetItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: '设置',
      idx: 9,
      color: Color(0xFF546E7A),
    ),
  ];

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final colorScheme = theme.colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // 顶部标题栏 + 侧边栏模式快捷展开
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.apps_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '全站快捷导航',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  if (AppConfig.navLayout == NavLayout.side)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        openGlobalAppDrawer(context);
                      },
                      icon: const Icon(Icons.menu_open_rounded, size: 18),
                      label: const Text('打开侧栏抽屉', style: TextStyle(fontSize: 12)),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 4 列网格导航九宫格
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.95,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = item.idx == mainTabIndex.value;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      if (item.idx < 5) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        mainTabIndex.value = item.idx;
                      } else if (item.idx == 10) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const NoticePage()),
                        );
                      } else if (item.idx == 11) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const GuidePage()),
                        );
                      } else if (item.idx == 12) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SearchPage()),
                        );
                      } else if (item.idx == 13) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DarkroomPage()),
                        );
                      } else if (item.idx == 6) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
                        );
                      } else if (item.idx == 8) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RanklistPage()),
                        );
                      } else if (item.idx == 14) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 0)),
                        );
                      } else if (item.idx == 15) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MagicPage()),
                        );
                      } else if (item.idx == 9) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SettingsPage()),
                        );
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.secondaryContainer.withAlpha(120)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: isSelected
                            ? Border.all(
                                color: colorScheme.primary.withAlpha(120),
                                width: 1.2,
                              )
                            : null,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Badge(
                            isLabelVisible: item.badgeCount > 0,
                            label: Text(
                              item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                            ),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: item.color.withAlpha(30),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: item.color.withAlpha(60),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                isSelected ? item.selectedIcon : item.icon,
                                color: item.color,
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              // 底部快捷操作条（登录 / 退出登录）
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: DioClient.isLoggedIn
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent, width: 0.8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('退出登录'),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          KlpbbsApi.logout().then((_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已退出登录')),
                              );
                            }
                          });
                        },
                      )
                    : FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text('登录苦力怕论坛账号'),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      );
    },
  );
}

/// 全局侧边栏抽屉呼出统一控制器
void openGlobalAppDrawer(BuildContext context) {
  final isDesktop = ResponsiveBreakpoints.isDesktop(context);
  final canPop = Navigator.of(context).canPop();

  // 1. 如果处于桌面主壳根视图（!canPop 且存在活跃的桌面主壳），统一通过主壳专用桌面动效层展开/收起抽屉
  if (isDesktop && !canPop && AdaptiveScaffold.isDesktopActive) {
    if (AdaptiveScaffold.isDesktopDrawerOpen) {
      AdaptiveScaffold.closeMainDrawer();
    } else {
      AdaptiveScaffold.openMainDrawer();
    }
    return;
  }

  // 2. 检查当前脚手架是否挂载了局部 drawer（如测试页面、独立子页面）
  final scaffold = Scaffold.maybeOf(context);
  if (scaffold?.hasDrawer == true) {
    scaffold?.openDrawer();
    return;
  }

  // 3. 仅在根主壳页面且无法再 pop 时，才允许委托给主壳脚手架唤起抽屉
  if (!canPop && AdaptiveScaffold.activeScaffoldKey?.currentState?.hasDrawer == true) {
    AdaptiveScaffold.openMainDrawer();
    return;
  }

  // 4. 子页面或者未挂载 drawer 的独立页面，必须直接在当前页面上以模态侧滑形式展示抽屉，绝不能碰底层的首页脚手架！
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'GlobalAppDrawer',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, anim, secAnim) => const Align(
      alignment: Alignment.centerLeft,
      child: GlobalAppDrawer(),
    ),
    transitionBuilder: (ctx, anim, secAnim, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
  );
}

/// 全局导航菜单按钮（放置在 AppBar leading 最左侧）。
class GlobalNavButton extends StatelessWidget {
  const GlobalNavButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PushNotificationService.instance,
      builder: (context, _) {
        final unread = PushNotificationService.instance.unreadCount;
        return IconButton(
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.menu_rounded),
          ),
          tooltip: '打开侧边栏',
          onPressed: () => openGlobalAppDrawer(context),
        );
      },
    );
  }
}

/// 统一的 AppBar 左侧组件组合（全站导航 + 返回键）
class GlobalNavLeading extends StatelessWidget {
  final bool showBackButton;
  final VoidCallback? onBack;

  const GlobalNavLeading({
    super.key,
    this.showBackButton = true,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    if (!showBackButton) {
      return const GlobalNavButton();
    }
    final canPop = Navigator.of(context).canPop();
    final hasBack = canPop || onBack != null;
    if (!hasBack) {
      return const GlobalNavButton();
    }
    final isDesktop = ResponsiveBreakpoints.isDesktop(context) ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux ||
        Theme.of(context).platform == TargetPlatform.macOS;
    if (isDesktop) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GlobalNavButton(),
          AppBackButton(
            onBack: onBack,
            fallbackToHome: false,
          ),
        ],
      );
    }
    return AppBackButton(
      onBack: onBack,
      fallbackToHome: false,
    );
  }
}
