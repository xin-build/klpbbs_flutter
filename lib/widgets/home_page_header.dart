import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'forum_search_field.dart';

/// The header renders capabilities supplied by its host. It owns no navigation,
/// forum requests, account state or persisted layout preferences.
enum HomeHeaderAction {
  refresh,
  favorites,
  search,
  ai,
  pm,
  notice,
  guide,
  membership,
  canvas,
  layout,
  mobile,
  left,
  right,
  settings,
  account,
}

class HomePageHeader extends StatelessWidget implements PreferredSizeWidget {
  final bool isDesktop;
  final bool nativeDesktop;
  final bool showDrawerButton;
  final bool loggedIn;
  final bool leftExpanded;
  final bool rightExpanded;
  final bool settingsAvailable;
  final int unreadPm;
  final int unreadNotice;
  final TextEditingController searchController;
  final ValueChanged<HomeHeaderAction>? onAction;
  final VoidCallback? onOpenDrawer;
  final Widget? leading;
  final double toolbarHeight;

  const HomePageHeader({
    super.key,
    required this.isDesktop,
    required this.nativeDesktop,
    required this.searchController,
    this.showDrawerButton = false,
    this.loggedIn = false,
    this.leftExpanded = true,
    this.rightExpanded = true,
    this.settingsAvailable = true,
    this.unreadPm = 0,
    this.unreadNotice = 0,
    this.onAction,
    this.onOpenDrawer,
    this.leading,
    this.toolbarHeight = kToolbarHeight,
  });

  static double heightFor(BuildContext context) =>
      math.max(kToolbarHeight, MediaQuery.textScalerOf(context).scale(16) + 32);

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  VoidCallback? _callback(HomeHeaderAction action) =>
      onAction == null ? null : () => onAction!(action);

  PopupMenuItem<HomeHeaderAction> _entry(
          HomeHeaderAction value, IconData icon, String label) =>
      PopupMenuItem(
          value: value,
          child: Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Flexible(child: Text(label)),
          ]));

  List<Widget> _actions(BuildContext context, bool roomy) => [
        if (isDesktop) ...[
          IconButton(
              key: const ValueKey('home-header-refresh'),
              tooltip: '刷新首页 (Ctrl+R)',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _callback(HomeHeaderAction.refresh)),
          IconButton(
              key: const ValueKey('home-header-favorites'),
              tooltip: '我的收藏',
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: _callback(HomeHeaderAction.favorites)),
        ],
        if (!roomy && isDesktop)
          IconButton(
              key: const ValueKey('home-header-search'),
              tooltip: '搜索 (Ctrl+F)',
              icon: const Icon(Icons.search),
              onPressed: _callback(HomeHeaderAction.search)),
        if (roomy) ...[
          IconButton(
              key: const ValueKey('home-header-ai'),
              tooltip: '帕帕 AI',
              icon: const Icon(Icons.smart_toy_outlined),
              onPressed: _callback(HomeHeaderAction.ai)),
          Badge.count(
              count: unreadPm,
              isLabelVisible: unreadPm > 0,
              child: IconButton(
                  key: const ValueKey('home-header-pm'),
                  tooltip: '私信',
                  icon: const Icon(Icons.mail_outline_rounded),
                  onPressed: _callback(HomeHeaderAction.pm))),
          Badge.count(
              count: unreadNotice,
              isLabelVisible: unreadNotice > 0,
              child: IconButton(
                  key: const ValueKey('home-header-notice'),
                  tooltip: '通知',
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: _callback(HomeHeaderAction.notice))),
          IconButton(
              key: const ValueKey('home-header-settings'),
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
              onPressed: settingsAvailable
                  ? _callback(HomeHeaderAction.settings)
                  : null),
        ],
        if (!roomy)
          Badge.count(
              count: unreadNotice + unreadPm,
              isLabelVisible: unreadNotice + unreadPm > 0,
              child: PopupMenuButton<HomeHeaderAction>(
                key: const ValueKey('home-header-messages'),
                tooltip: '消息',
                icon: const Icon(Icons.notifications_outlined),
                onSelected: onAction,
                itemBuilder: (_) => [
                  _entry(HomeHeaderAction.notice, Icons.notifications_outlined,
                      '通知${unreadNotice > 0 ? ' · $unreadNotice' : ''}'),
                  _entry(HomeHeaderAction.pm, Icons.mail_outline,
                      '私信${unreadPm > 0 ? ' · $unreadPm' : ''}'),
                ],
              )),
        PopupMenuButton<HomeHeaderAction>(
          key: const ValueKey('home-header-more'),
          tooltip: '工具与自定义',
          icon: const Icon(Icons.more_vert),
          onSelected: onAction,
          itemBuilder: (_) => [
            const PopupMenuItem<HomeHeaderAction>(
                enabled: false, child: Text('社区工具')),
            _entry(HomeHeaderAction.refresh, Icons.refresh, '刷新首页'),
            _entry(HomeHeaderAction.ai, Icons.smart_toy_outlined, '帕帕 AI'),
            _entry(HomeHeaderAction.membership,
                Icons.workspace_premium_outlined, '用户组与会员'),
            const PopupMenuDivider(),
            const PopupMenuItem<HomeHeaderAction>(
                enabled: false, child: Text('布局与外观')),
            if (isDesktop) ...[
              _entry(HomeHeaderAction.canvas,
                  Icons.dashboard_customize_outlined, '自由画布工坊'),
            ],
            if (!isDesktop)
              _entry(HomeHeaderAction.mobile, Icons.tune, '手机首页自定义'),
            if (isDesktop) ...[
              _entry(HomeHeaderAction.left, Icons.view_sidebar_outlined,
                  leftExpanded ? '收起左侧数据栏' : '展开左侧数据栏'),
              _entry(HomeHeaderAction.right, Icons.dock_outlined,
                  rightExpanded ? '收起右侧数据栏' : '展开右侧数据栏'),
            ],
            _entry(HomeHeaderAction.settings, Icons.settings_outlined, '设置'),
            const PopupMenuDivider(),
            _entry(HomeHeaderAction.account, Icons.account_circle_outlined,
                loggedIn ? '我的空间与账号' : '登录账号'),
          ],
        ),
        const SizedBox(width: 8),
      ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final roomy = isDesktop && width >= 1050;
    final inlineSearch = roomy && nativeDesktop;
    return AppBar(
      key: const ValueKey('home-page-header'),
      toolbarHeight: toolbarHeight,
      titleSpacing: isDesktop ? 16 : null,
      title: isDesktop && nativeDesktop
          ? Row(children: [
              const Icon(Icons.home_outlined, size: 20),
              const SizedBox(width: 10),
              const Text('首页',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
              if (inlineSearch) ...[
                const SizedBox(width: 24),
                Flexible(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: ForumSearchField(
                            fieldKey: const ValueKey('home-desktop-search'),
                            controller: searchController,
                            onSearch: _callback(HomeHeaderAction.search)))),
                const SizedBox(width: 12),
              ],
              if (width >= 1380) ...[
                TextButton.icon(
                    key: const ValueKey('home-header-guide'),
                    onPressed: _callback(HomeHeaderAction.guide),
                    icon: const Icon(Icons.local_fire_department_outlined,
                        size: 18),
                    label: const Text('热门 / 导读')),
                TextButton.icon(
                    key: const ValueKey('home-header-membership'),
                    onPressed: _callback(HomeHeaderAction.membership),
                    icon:
                        const Icon(Icons.workspace_premium_outlined, size: 18),
                    label: const Text('会员')),
              ],
            ])
          : !isDesktop
              ? ForumSearchField(
                  fieldKey: const ValueKey('home-mobile-search'),
                  controller: searchController,
                  hint: '搜索主题、资源',
                  compact: true,
                  onSearch: _callback(HomeHeaderAction.search),
                )
              : const Text('苦力怕论坛',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
      automaticallyImplyLeading: !isDesktop,
      leading: leading ??
          (!isDesktop && showDrawerButton
              ? IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: '打开导航菜单',
                  onPressed: onOpenDrawer)
              : null),
      actions: _actions(context, roomy),
    );
  }
}
