import 'package:flutter/material.dart';
import 'app_motion.dart';
import 'package:flutter/services.dart';
import '../core/app_config.dart';
import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../pages/favorite_hub_page.dart';
import '../pages/guide_page.dart';
import '../pages/login_page.dart';
import '../pages/membership_page.dart';
import '../pages/notice_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';

/// 响应式断点与设备排版辅助类
class ResponsiveBreakpoints {
  static const double mobileMaxWidth = 768.0;
  static const double tabletMaxWidth = 1100.0;
  static const double desktopMaxWidth = 1600.0;

  /// 当前是否应当使用桌面 PC 宽屏排版（考虑了用户设置 AppLayoutMode）
  static bool isDesktop(BuildContext context) {
    if (AppConfig.layoutMode == AppLayoutMode.desktop) return true;
    if (AppConfig.layoutMode == AppLayoutMode.mobile) return false;
    final width = MediaQuery.sizeOf(context).width;
    return width >= mobileMaxWidth;
  }

  /// 当前是否移动端排版
  static bool isMobile(BuildContext context) => !isDesktop(context);

  /// 当前是否特宽屏 (>1200px)
  static bool isWideDesktop(BuildContext context) {
    return isDesktop(context) && MediaQuery.sizeOf(context).width >= 1200.0;
  }

  /// 计算网格列表适合的列数
  static int getGridColumnCount(BuildContext context) {
    if (isMobile(context)) return 1;
    if (AppConfig.desktopGridColumns > 0) {
      return AppConfig.desktopGridColumns;
    }
    return 2;
  }
}

/// 导航项定义
class NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? badgeCount;
  final VoidCallback? onTap;

  const NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount,
    this.onTap,
  });
}

/// 自适应主框架：桌面宽屏侧边导航 + 移动端底部/抽屉导航
class AdaptiveScaffold extends StatefulWidget {
  static GlobalKey<ScaffoldState>? activeScaffoldKey;
  static _AdaptiveScaffoldState? _activeState;

  /// 供全局任意子页面打开主壳侧边栏抽屉
  static void openMainDrawer() {
    if (_activeState != null &&
        _activeState!.mounted &&
        _activeState!._isDesktop) {
      _activeState!.openDesktopDrawer();
      return;
    }
    activeScaffoldKey?.currentState?.openDrawer();
  }

  static void closeMainDrawer() {
    if (_activeState != null &&
        _activeState!.mounted &&
        _activeState!._isDesktop) {
      _activeState!.closeDesktopDrawer();
      return;
    }
    activeScaffoldKey?.currentState?.closeDrawer();
  }

  static bool get isDesktopDrawerOpen =>
      _activeState != null &&
      _activeState!.mounted &&
      _activeState!._isDesktopDrawerOpen;

  static bool get isDesktopActive =>
      _activeState != null && _activeState!.mounted && _activeState!._isDesktop;

  final int currentIndex;
  final ValueChanged<int> onNavigationChanged;
  final List<NavItem> navItems;
  final Widget body;
  final Widget? drawer;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? desktopHeader;
  final Widget? desktopFooter;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const AdaptiveScaffold({
    super.key,
    required this.currentIndex,
    required this.onNavigationChanged,
    required this.navItems,
    required this.body,
    this.drawer,
    this.appBar,
    this.floatingActionButton,
    this.desktopHeader,
    this.desktopFooter,
    this.scaffoldKey,
  });

  @override
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends State<AdaptiveScaffold>
    with SingleTickerProviderStateMixin {
  bool _isRailExtended = false;
  bool _isDesktop = false;
  bool _isDesktopDrawerOpen = false;
  bool _drawerClosing = false;
  int _drawerTransition = 0;
  late AnimationController _desktopDrawerCtrl;
  late Animation<double> _desktopDrawerAnim;

  @override
  void initState() {
    super.initState();
    AdaptiveScaffold._activeState = this;
    _desktopDrawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _desktopDrawerAnim = _desktopDrawerCtrl;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _desktopDrawerCtrl.duration = AppMotion.duration(context, 300);
    _desktopDrawerCtrl.reverseDuration = AppMotion.duration(context, 220);
    if (!AppMotion.enabled(context)) {
      _desktopDrawerCtrl.value =
          _isDesktopDrawerOpen && !_drawerClosing ? 1 : 0;
      if (_drawerClosing) _isDesktopDrawerOpen = false;
    }
  }

  @override
  void dispose() {
    if (AdaptiveScaffold._activeState == this) {
      AdaptiveScaffold._activeState = null;
    }
    _desktopDrawerCtrl.dispose();
    super.dispose();
  }

  void openDesktopDrawer() {
    _drawerTransition++;
    _drawerClosing = false;
    setState(() => _isDesktopDrawerOpen = true);
    _desktopDrawerCtrl.animateTo(1, curve: AppMotion.emphasized);
  }

  void closeDesktopDrawer() {
    if (_isDesktopDrawerOpen) {
      final transition = ++_drawerTransition;
      _drawerClosing = true;
      _desktopDrawerCtrl.animateBack(0, curve: AppMotion.exit).then((_) {
        if (mounted &&
            transition == _drawerTransition &&
            _desktopDrawerCtrl.isDismissed) {
          setState(() {
            _isDesktopDrawerOpen = false;
            _drawerClosing = false;
          });
        }
      });
    }
  }

  void toggleDesktopDrawer() {
    if (_isDesktopDrawerOpen && !_drawerClosing) {
      closeDesktopDrawer();
    } else {
      openDesktopDrawer();
    }
  }

  void _pushRailPage(Widget page) {
    if (_isDesktopDrawerOpen) closeDesktopDrawer();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _openRailFavorites() async {
    final session = DioClient.sessionKey;
    try {
      final uid = await KlpbbsApi.getMyUid();
      if (!mounted || session != DioClient.sessionKey) return;
      _pushRailPage(uid != null && uid > 0
          ? FavoriteHubPage(uid: uid)
          : const LoginPage());
    } catch (_) {
      if (mounted && session == DioClient.sessionKey) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('暂时无法读取账号，请重试。')));
      }
    }
  }

  List<NavItem> get _desktopShortcuts => [
        NavItem(
            icon: Icons.search_rounded,
            selectedIcon: Icons.search_rounded,
            label: '搜索',
            onTap: () => _pushRailPage(const SearchPage())),
        NavItem(
            icon: Icons.local_fire_department_outlined,
            selectedIcon: Icons.local_fire_department_rounded,
            label: '导读',
            onTap: () => _pushRailPage(const GuidePage())),
        NavItem(
            icon: Icons.notifications_outlined,
            selectedIcon: Icons.notifications_rounded,
            label: '消息',
            onTap: () => _pushRailPage(const NoticePage())),
        NavItem(
            icon: Icons.star_border_rounded,
            selectedIcon: Icons.star_rounded,
            label: '收藏',
            onTap: _openRailFavorites),
        NavItem(
            icon: Icons.workspace_premium_outlined,
            selectedIcon: Icons.workspace_premium_rounded,
            label: '会员',
            onTap: () => _pushRailPage(const MembershipPage())),
        NavItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: '设置',
            onTap: () => _pushRailPage(const SettingsPage())),
      ];

  Widget _buildRailItem(BuildContext context, NavItem item,
      {required bool selected,
      required bool extended,
      required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final indicator = selected ? scheme.secondaryContainer : Colors.transparent;
    final duration = AppMotion.duration(context, 160);
    Widget icon = Badge(
      isLabelVisible: (item.badgeCount ?? 0) > 0,
      label: Text('${item.badgeCount ?? 0}'),
      child: Icon(selected ? item.selectedIcon : item.icon,
          size: 24, color: foreground),
    );
    final label = Text(item.label,
        maxLines: extended ? 1 : 2,
        textAlign: extended ? TextAlign.start : TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: extended ? 14 : 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: foreground));
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2, horizontal: extended ? 8 : 4),
      child: Tooltip(
        message: item.label,
        child: Semantics(
          selected: selected,
          button: true,
          child: Material(
            color: extended ? indicator : Colors.transparent,
            animationDuration: duration,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('desktop-nav-${item.label}'),
              borderRadius: BorderRadius.circular(28),
              onTap: onTap,
              child: extended
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(children: [
                        icon,
                        const SizedBox(width: 14),
                        Expanded(child: label)
                      ]))
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Material(
                            color: indicator,
                            animationDuration: duration,
                            borderRadius: BorderRadius.circular(18),
                            child: SizedBox(
                                width: 52,
                                height: 32,
                                child: Center(child: icon))),
                        const SizedBox(height: 4),
                        label,
                      ])),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AdaptiveScaffold.activeScaffoldKey = widget.scaffoldKey;
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    _isDesktop = isDesktop;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isDesktop) {
      final isLight = theme.brightness == Brightness.light;
      final topPadding = MediaQuery.paddingOf(context).top;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final isNarrow = screenWidth < 768.0;

      // 顶栏背景色与前景色（与全局 AppBarTheme 严格保持 100% 一致，沉浸统合）
      final headerBg = theme.appBarTheme.backgroundColor ?? colorScheme.surface;
      final headerFg =
          theme.appBarTheme.foregroundColor ?? colorScheme.onSurface;
      final useLightIcons =
          ThemeData.estimateBrightnessForColor(headerBg) == Brightness.dark;
      final overlayStyle = SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            useLightIcons ? Brightness.light : Brightness.dark,
        statusBarBrightness: useLightIcons ? Brightness.dark : Brightness.light,
      );

      // 侧边栏主体背景色：白天使用柔和清爽的 M3 表面底色（不再是刺眼生硬的纯白），夜间使用深邃底色
      final sidebarBodyBg = isLight
          ? colorScheme.surfaceContainerLowest
          : (AppConfig.isOledDark
              ? Colors.black
              : colorScheme.surfaceContainerLow);

      // 窄窗口保持紧凑导航；扩展模式为文字和操作留足空间。
      final effectiveExtended = !isNarrow && _isRailExtended;
      final railWidth = effectiveExtended ? 216.0 : 76.0;
      final railItems = [
        ...widget.navItems,
        ..._desktopShortcuts.where((shortcut) =>
            !widget.navItems.any((item) => item.label == shortcut.label))
      ];

      // 抽屉最大宽度自适应，保证遮罩层至少留有 32px 供点击退出
      final drawerWidth = (screenWidth - railWidth - 32.0).clamp(0.0, 320.0);

      // 桌面 PC 宽屏排版：外层统合顶栏状态栏 + 左侧精致 NavigationRail + 右侧主体
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: Scaffold(
          backgroundColor: headerBg,
          body: Column(
            children: [
              // 1. 系统顶栏沉浸区域填充（移动端适配，PC 端 height 为 0）
              if (topPadding > 0)
                Container(
                  height: topPadding,
                  width: double.infinity,
                  color: headerBg,
                ),
              // 2. 主体工作区（Header + Body）
              Expanded(
                child: Row(
                  children: [
                    // 左侧侧边栏
                    Material(
                      color: sidebarBodyBg,
                      child: ClipRect(
                        clipBehavior: Clip.hardEdge,
                        child: AnimatedContainer(
                          key: const ValueKey('desktop-navigation-rail'),
                          duration: AppMotion.duration(context, 240),
                          curve: AppMotion.emphasized,
                          width: railWidth,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: colorScheme.outlineVariant
                                    .withAlpha(isLight ? 45 : 35),
                                width: 1,
                              ),
                            ),
                          ),
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: railWidth,
                            maxWidth: railWidth,
                            child: Column(
                              children: [
                                // 顶部标题区正常保持工具栏高度，大字号允许自然增高。
                                Container(
                                  constraints: const BoxConstraints(
                                      minHeight: kToolbarHeight),
                                  width: double.infinity,
                                  color: headerBg,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: effectiveExtended ? 14 : 0,
                                    vertical: 8,
                                  ),
                                  child: effectiveExtended
                                      ? Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: colorScheme
                                                    .primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: colorScheme
                                                      .outlineVariant,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.view_in_ar_rounded,
                                                color: colorScheme
                                                    .onPrimaryContainer,
                                                size: 21,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '苦力怕论坛',
                                                    style: TextStyle(
                                                      color: headerFg,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15,
                                                      letterSpacing: 0.5,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    'KLPBBS Desktop',
                                                    style: TextStyle(
                                                      color: headerFg
                                                          .withAlpha(180),
                                                      fontSize: 10.5,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : Center(
                                          child: Tooltip(
                                            message: '苦力怕论坛',
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: colorScheme
                                                    .primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: colorScheme
                                                      .outlineVariant,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.view_in_ar_rounded,
                                                color: colorScheme
                                                    .onPrimaryContainer,
                                                size: 21,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                                if (widget.desktopHeader != null)
                                  widget.desktopHeader!,
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: colorScheme.outlineVariant
                                      .withAlpha(isLight ? 40 : 25),
                                ),
                                // 导航项列表
                                Expanded(
                                  child: ScrollConfiguration(
                                    behavior: ScrollConfiguration.of(context)
                                        .copyWith(scrollbars: false),
                                    child: ListView.builder(
                                      primary: false,
                                      physics: const ClampingScrollPhysics(),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8, horizontal: 4),
                                      itemCount: railItems.length,
                                      itemBuilder: (context, index) {
                                        final item = railItems[index];
                                        final button = _buildRailItem(
                                            context, item,
                                            selected: index <
                                                    widget.navItems.length &&
                                                widget.currentIndex == index,
                                            extended: effectiveExtended,
                                            onTap: item.onTap ??
                                                () =>
                                                    widget.onNavigationChanged(
                                                        index));
                                        return index == widget.navItems.length
                                            ? Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                    Divider(
                                                        height: 16,
                                                        indent: 12,
                                                        endIndent: 12,
                                                        color: colorScheme
                                                            .outlineVariant),
                                                    button
                                                  ])
                                            : button;
                                      },
                                    ),
                                  ),
                                ),
                                // 底部折叠切换与操作
                                if (widget.desktopFooter != null)
                                  widget.desktopFooter!,
                                Divider(
                                  height: 1,
                                  indent: 8,
                                  endIndent: 8,
                                  color: colorScheme.outlineVariant
                                      .withAlpha(isLight ? 40 : 25),
                                ),
                                if (!isNarrow)
                                  IconButton(
                                    tooltip: '更多功能与设置',
                                    icon: Icon(Icons.apps_rounded,
                                        color: colorScheme.onSurfaceVariant),
                                    onPressed: openDesktopDrawer,
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: isNarrow
                                      ? IconButton(
                                          tooltip: '更多功能菜单',
                                          icon: Icon(
                                            Icons.menu_rounded,
                                            size: 20,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          onPressed: openDesktopDrawer,
                                        )
                                      : IconButton(
                                          key: const ValueKey(
                                              'desktop-rail-toggle'),
                                          tooltip:
                                              _isRailExtended ? '收起侧栏' : '展开侧栏',
                                          icon: AnimatedRotation(
                                            turns: _isRailExtended ? 0.5 : 0.0,
                                            duration: AppMotion.duration(
                                                context, 200),
                                            child: Icon(
                                              _isRailExtended
                                                  ? Icons
                                                      .arrow_back_ios_new_rounded
                                                  : Icons
                                                      .arrow_forward_ios_rounded,
                                              size: 17,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          onPressed: () {
                                            setState(() => _isRailExtended =
                                                !_isRailExtended);
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 右侧主体：严格 ClipRect + 抽屉动效层
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: topPadding > 0,
                        child: ClipRect(
                          child: Stack(
                            children: [
                              Scaffold(
                                key: widget.scaffoldKey,
                                appBar: widget.appBar,
                                body: widget.body,
                                floatingActionButton:
                                    widget.floatingActionButton,
                              ),
                              if (_isDesktopDrawerOpen && widget.drawer != null)
                                Positioned.fill(
                                  child: AnimatedBuilder(
                                    animation: _desktopDrawerAnim,
                                    builder: (context, child) {
                                      final t = _desktopDrawerAnim.value;
                                      return Stack(
                                        children: [
                                          // 1. 半透明背景柔和遮罩（点击收起）
                                          Positioned.fill(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: closeDesktopDrawer,
                                              child: Container(
                                                color: Colors.black
                                                    .withOpacity(0.32 * t),
                                              ),
                                            ),
                                          ),
                                          // 面板从边缘完整滑入，拖动时直接跟随指针。
                                          Positioned(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            child: Transform.translate(
                                              offset: Offset(
                                                  -drawerWidth * (1.0 - t), 0),
                                              child: Opacity(
                                                opacity: 1,
                                                child: Material(
                                                  elevation: 2,
                                                  shadowColor: Colors.black38,
                                                  borderRadius:
                                                      const BorderRadius
                                                          .horizontal(
                                                    right: Radius.circular(28),
                                                  ),
                                                  clipBehavior: Clip.antiAlias,
                                                  child: SizedBox(
                                                    width: drawerWidth,
                                                    child: GestureDetector(
                                                      onHorizontalDragStart:
                                                          (_) {
                                                        _drawerTransition++;
                                                        _drawerClosing = false;
                                                        _desktopDrawerCtrl
                                                            .stop();
                                                      },
                                                      onHorizontalDragUpdate:
                                                          (details) {
                                                        _desktopDrawerCtrl
                                                                .value =
                                                            (_desktopDrawerCtrl
                                                                        .value +
                                                                    details.delta
                                                                            .dx /
                                                                        drawerWidth)
                                                                .clamp(
                                                                    0.0, 1.0);
                                                      },
                                                      onHorizontalDragEnd:
                                                          (details) {
                                                        if ((details.primaryVelocity ??
                                                                    0) <
                                                                -300 ||
                                                            _desktopDrawerCtrl
                                                                    .value <
                                                                .5) {
                                                          closeDesktopDrawer();
                                                        } else {
                                                          openDesktopDrawer();
                                                        }
                                                      },
                                                      child: widget.drawer,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
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

    // 移动端排版：常驻底栏 或 常驻紧凑侧轨（确保导航菜单始终常驻）
    final useSideRail = AppConfig.navLayout == NavLayout.side;
    final bottomNavItems =
        widget.navItems.where((item) => item.onTap == null).toList();
    final effectiveBottomNav =
        bottomNavItems.isNotEmpty ? bottomNavItems : widget.navItems;

    final mobileBody = useSideRail
        ? Row(
            children: [
              _buildMobileSideRail(theme, colorScheme),
              Expanded(child: widget.body),
            ],
          )
        : widget.body;

    return Scaffold(
      key: widget.scaffoldKey,
      appBar: widget.appBar,
      drawer: widget.drawer,
      drawerEdgeDragWidth: 50.0,
      body: mobileBody,
      floatingActionButton: widget.floatingActionButton,
      bottomNavigationBar: useSideRail
          ? null
          : NavigationBar(
              height: 66,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: (() {
                final curItem = widget.currentIndex < widget.navItems.length
                    ? widget.navItems[widget.currentIndex]
                    : null;
                final effIdx =
                    curItem != null ? effectiveBottomNav.indexOf(curItem) : -1;
                return (effIdx >= 0 ? effIdx : widget.currentIndex)
                    .clamp(0, effectiveBottomNav.length - 1);
              })(),
              onDestinationSelected: (idx) {
                HapticFeedback.selectionClick();
                final item = effectiveBottomNav[idx];
                if (item.onTap != null) {
                  item.onTap!();
                } else {
                  final origIdx = widget.navItems.indexOf(item);
                  widget.onNavigationChanged(origIdx >= 0 ? origIdx : idx);
                }
              },
              destinations: effectiveBottomNav.map((item) {
                return NavigationDestination(
                  icon: Badge(
                    isLabelVisible: (item.badgeCount ?? 0) > 0,
                    label: Text('${item.badgeCount}'),
                    child: Icon(item.icon),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: (item.badgeCount ?? 0) > 0,
                    label: Text('${item.badgeCount}'),
                    child: Icon(item.selectedIcon),
                  ),
                  label: item.label,
                );
              }).toList(),
            ),
    );
  }

  Widget _buildMobileSideRail(ThemeData theme, ColorScheme colorScheme) {
    final isLight = theme.brightness == Brightness.light;
    final activeBg = isLight
        ? colorScheme.primaryContainer
        : colorScheme.primary.withAlpha(50);
    final activeFg =
        isLight ? colorScheme.onPrimaryContainer : colorScheme.primary;
    final sidebarBg = isLight
        ? colorScheme.surfaceContainerLowest
        : (AppConfig.isOledDark
            ? Colors.black
            : colorScheme.surfaceContainerLow);

    return Material(
      color: sidebarBg,
      child: Container(
        width: 64,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: colorScheme.outlineVariant.withAlpha(isLight ? 45 : 35),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: Column(
            children: [
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: widget.navItems.length,
                  itemBuilder: (context, i) {
                    final item = widget.navItems[i];
                    final isSelected = i == widget.currentIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 6),
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (item.onTap != null) {
                            item.onTap!();
                          } else {
                            widget.onNavigationChanged(i);
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: AppMotion.duration(context, 180),
                                curve: AppMotion.emphasized,
                                width: 46,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? activeBg
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                alignment: Alignment.center,
                                child: Badge(
                                  isLabelVisible: (item.badgeCount ?? 0) > 0,
                                  label: Text('${item.badgeCount}'),
                                  child: Icon(
                                    isSelected ? item.selectedIcon : item.icon,
                                    size: 20,
                                    color: isSelected
                                        ? activeFg
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? activeFg
                                      : colorScheme.onSurfaceVariant
                                          .withAlpha(200),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 响应式多列网格容器
class ResponsiveGridView extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  const ResponsiveGridView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = const EdgeInsets.all(12),
    this.spacing = 12,
    this.controller,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    final cols = ResponsiveBreakpoints.getGridColumnCount(context);
    if (cols <= 1) {
      return ListView.builder(
        controller: controller,
        physics: physics,
        padding: padding,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    }
    return GridView.builder(
      controller: controller,
      physics: physics,
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: cols >= 3 ? 1.05 : 1.2,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
