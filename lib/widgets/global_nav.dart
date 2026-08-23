import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
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

/// 全局移动端导航菜单：从任意 pushed 页面弹出底部导航抽屉（原站克米悬浮菜单与全局导航）。
void showGlobalNavSheet(BuildContext context) {
  final unread = PushNotificationService.instance.unreadCount;
  final items = <(IconData, IconData, String, int)>[
    (Icons.home_outlined, Icons.home_rounded, '首页', 0),
    (Icons.forum_outlined, Icons.forum_rounded, '版块', 1),
    (Icons.emoji_events_outlined, Icons.emoji_events_rounded, '签到', 2),
    (Icons.military_tech_outlined, Icons.military_tech, '勋章中心', 3),
    (Icons.auto_fix_high_outlined, Icons.auto_fix_high, '道具中心', 15),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, '积分中心', 14),
    (Icons.account_circle_outlined, Icons.account_circle, '个人中心', 4),
    (
      Icons.local_fire_department_outlined,
      Icons.local_fire_department_rounded,
      '导读',
      11,
    ),
    (Icons.search_outlined, Icons.search_rounded, '搜索', 12),
    (Icons.gavel_outlined, Icons.gavel_rounded, '封神榜', 13),
    (
      Icons.notifications_outlined,
      Icons.notifications_rounded,
      unread > 0 ? '消息提醒 ($unread)' : '消息提醒',
      10,
    ),
    (Icons.manage_accounts_outlined, Icons.manage_accounts, '资料设置', 6),
    (Icons.leaderboard_outlined, Icons.leaderboard_rounded, '排行榜', 8),
    (Icons.settings_outlined, Icons.settings_rounded, '设置', 9),
  ];

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '全站导航',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final (icon, selectedIcon, label, idx) in items)
              ListTile(
                leading: Icon(idx == mainTabIndex.value ? selectedIcon : icon),
                title: Text(label),
                selected: idx == mainTabIndex.value,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (idx < 5) {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    mainTabIndex.value = idx;
                  } else if (idx == 10) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NoticePage()),
                    );
                  } else if (idx == 11) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GuidePage()),
                    );
                  } else if (idx == 12) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchPage()),
                    );
                  } else if (idx == 13) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DarkroomPage()),
                    );
                  } else if (idx == 6) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
                    );
                  } else if (idx == 8) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RanklistPage()),
                    );
                  } else if (idx == 14) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 0)),
                    );
                  } else if (idx == 15) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MagicPage()),
                    );
                  } else if (idx == 9) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  }
                },
              ),
            const Divider(height: 1),
            if (DioClient.isLoggedIn)
              ListTile(
                leading: const Icon(Icons.logout_outlined, color: Colors.red),
                title: const Text('退出登录', style: TextStyle(color: Colors.red)),
                onTap: () {
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
            else
              ListTile(
                leading: const Icon(Icons.login_outlined),
                title: const Text('登录 / 注册'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
                },
              ),
          ],
        ),
      );
    },
  );
}

/// 全局导航菜单按钮（建议放在 pushed 页面 AppBar actions 第一位）。
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
          tooltip: '全站导航',
          onPressed: () => showGlobalNavSheet(context),
        );
      },
    );
  }
}
