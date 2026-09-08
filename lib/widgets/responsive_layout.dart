import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_config.dart';

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
    if (AppConfig.desktopGridColumns > 0) {
      return AppConfig.desktopGridColumns;
    }
    if (isMobile(context)) return 1;
    final width = MediaQuery.sizeOf(context).width;
    if (width < 900) return 2;
    if (width < 1400) return 3;
    return 4;
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
    if (_activeState != null && _activeState!.mounted && _activeState!._isDesktop) {
      _activeState!.openDesktopDrawer();
      return;
    }
    activeScaffoldKey?.currentState?.openDrawer();
  }

  static void closeMainDrawer() {
    if (_activeState != null && _activeState!.mounted && _activeState!._isDesktop) {
      _activeState!.closeDesktopDrawer();
      return;
    }
    activeScaffoldKey?.currentState?.closeDrawer();
  }

  static bool get isDesktopDrawerOpen =>
      _activeState != null && _activeState!.mounted && _activeState!._isDesktopDrawerOpen;

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
    _desktopDrawerAnim = CurvedAnimation(
      parent: _desktopDrawerCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
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
    if (!_isDesktopDrawerOpen) {
      setState(() => _isDesktopDrawerOpen = true);
      _desktopDrawerCtrl.forward(from: 0.0);
    }
  }

  void closeDesktopDrawer() {
    if (_isDesktopDrawerOpen) {
      _desktopDrawerCtrl.reverse().then((_) {
        if (mounted) setState(() => _isDesktopDrawerOpen = false);
      });
    }
  }

  void toggleDesktopDrawer() {
    if (_isDesktopDrawerOpen) {
      closeDesktopDrawer();
    } else {
      openDesktopDrawer();
    }
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
      final headerBg = theme.appBarTheme.backgroundColor ?? colorScheme.primary;
      final headerFg = theme.appBarTheme.foregroundColor ?? Colors.white;
      final useLightIcons =
          ThemeData.estimateBrightnessForColor(headerBg) == Brightness.dark;
      final overlayStyle = SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            useLightIcons ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            useLightIcons ? Brightness.dark : Brightness.light,
      );

      // 侧边栏主体背景色：白天使用柔和清爽的 M3 表面底色（不再是刺眼生硬的纯白），夜间使用深邃底色
      final sidebarBodyBg = isLight
          ? colorScheme.surfaceContainerLowest
          : (AppConfig.isOledDark
              ? Colors.black
              : colorScheme.surfaceContainerLow);

      // 侧边栏宽度：在手机等窄屏下严格保持 68px 紧凑态，杜绝展开后挤爆右侧内容
      final effectiveExtended = !isNarrow && _isRailExtended;
      final railWidth = effectiveExtended ? 200.0 : 68.0;

      // 抽屉最大宽度自适应，保证遮罩层至少留有 32px 供点击退出
      final drawerWidth = (screenWidth - railWidth - 32.0).clamp(240.0, 320.0);

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
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
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
                        child: Column(
                          children: [
                            // 顶部 Logo / 标题区（高度精准对应 AppBar 的 kToolbarHeight 56px）
                            Container(
                              height: kToolbarHeight,
                              width: double.infinity,
                              color: headerBg,
                              padding: EdgeInsets.symmetric(
                                horizontal: effectiveExtended ? 14 : 0,
                              ),
                              child: effectiveExtended
                                  ? Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withAlpha(36),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: Colors.white.withAlpha(60),
                                              width: 1,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.view_in_ar_rounded,
                                            color: Colors.white,
                                            size: 21,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '苦力怕论坛',
                                                style: TextStyle(
                                                  color: headerFg,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  letterSpacing: 0.5,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                'KLPBBS Desktop',
                                                style: TextStyle(
                                                  color:
                                                      headerFg.withAlpha(180),
                                                  fontSize: 10.5,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
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
                                            color: Colors.white.withAlpha(36),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: Colors.white.withAlpha(60),
                                              width: 1,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.view_in_ar_rounded,
                                            color: Colors.white,
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
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 4),
                                itemCount: widget.navItems.length,
                                itemBuilder: (context, index) {
                                  final item = widget.navItems[index];
                                  final isSelected =
                                      widget.currentIndex == index;
                                  final activeBg = isLight
                                      ? colorScheme.primary.withAlpha(28)
                                      : colorScheme.primaryContainer
                                          .withAlpha(100);
                                  final activeFg = isLight
                                      ? colorScheme.primary
                                      : colorScheme.primary;

                                  void handleTap() {
                                    if (item.onTap != null) {
                                      item.onTap!();
                                    } else {
                                      widget.onNavigationChanged(index);
                                    }
                                  }

                                  if (!effectiveExtended) {
                                    // 紧凑模式 (68px)：胶囊药丸指示器 + 精致小标
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 3, horizontal: 4),
                                      child: Tooltip(
                                        message: item.label,
                                        preferBelow: false,
                                        child: InkWell(
                                          onTap: handleTap,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 4),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                AnimatedContainer(
                                                  duration: const Duration(
                                                      milliseconds: 180),
                                                  curve: Curves.easeOutCubic,
                                                  width: 48,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? activeBg
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Badge(
                                                    isLabelVisible:
                                                        (item.badgeCount ?? 0) >
                                                            0,
                                                    label: Text(
                                                        '${item.badgeCount}'),
                                                    child: Icon(
                                                      isSelected
                                                          ? item.selectedIcon
                                                          : item.icon,
                                                      size: 20,
                                                      color: isSelected
                                                          ? activeFg
                                                          : colorScheme
                                                              .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  item.label,
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: isSelected
                                                        ? FontWeight.bold
                                                        : FontWeight.w500,
                                                    color: isSelected
                                                        ? activeFg
                                                        : colorScheme
                                                            .onSurfaceVariant
                                                            .withAlpha(200),
                                                    letterSpacing: 0.2,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  // 展开模式 (200px)：横向胶囊
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 3, horizontal: 8),
                                    child: InkWell(
                                      onTap: handleTap,
                                      borderRadius: BorderRadius.circular(14),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        curve: Curves.easeOutCubic,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? activeBg
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Row(
                                          children: [
                                            Badge(
                                              isLabelVisible:
                                                  (item.badgeCount ?? 0) > 0,
                                              label:
                                                  Text('${item.badgeCount}'),
                                              child: Icon(
                                                isSelected
                                                    ? item.selectedIcon
                                                    : item.icon,
                                                size: 22,
                                                color: isSelected
                                                    ? activeFg
                                                    : colorScheme
                                                        .onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Text(
                                                item.label,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.w500,
                                                  color: isSelected
                                                      ? activeFg
                                                      : colorScheme.onSurface,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
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
                                      tooltip: _isRailExtended
                                          ? '收起侧栏'
                                          : '展开侧栏',
                                      icon: AnimatedRotation(
                                        turns: _isRailExtended ? 0.5 : 0.0,
                                        duration:
                                            const Duration(milliseconds: 200),
                                        child: Icon(
                                          _isRailExtended
                                              ? Icons.arrow_back_ios_new_rounded
                                              : Icons.arrow_forward_ios_rounded,
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
                                          // 2. 抽屉面板：平滑淡入 + 35px 优雅微滑出
                                          Positioned(
                                            top: 0,
                                            bottom: 0,
                                            left: 0,
                                            child: Transform.translate(
                                              offset: Offset(
                                                  -35.0 * (1.0 - t), 0),
                                              child: Opacity(
                                                opacity: t.clamp(0.0, 1.0),
                                                child: Material(
                                                  elevation: 16,
                                                  shadowColor: Colors.black38,
                                                  borderRadius:
                                                      const BorderRadius.horizontal(
                                                    right: Radius.circular(16),
                                                  ),
                                                  clipBehavior: Clip.antiAlias,
                                                  child: SizedBox(
                                                    width: drawerWidth,
                                                    child: widget.drawer,
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
    final bottomNavItems = widget.navItems.where((item) => item.onTap == null).toList();
    final effectiveBottomNav = bottomNavItems.isNotEmpty ? bottomNavItems : widget.navItems;

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
                final effIdx = curItem != null ? effectiveBottomNav.indexOf(curItem) : -1;
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
    final activeBg = isLight ? colorScheme.primaryContainer : colorScheme.primary.withAlpha(50);
    final activeFg = isLight ? colorScheme.onPrimaryContainer : colorScheme.primary;
    final sidebarBg = isLight
        ? colorScheme.surfaceContainerLowest
        : (AppConfig.isOledDark ? Colors.black : colorScheme.surfaceContainerLow);

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
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
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
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                width: 46,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isSelected ? activeBg : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                alignment: Alignment.center,
                                child: Badge(
                                  isLabelVisible: (item.badgeCount ?? 0) > 0,
                                  label: Text('${item.badgeCount}'),
                                  child: Icon(
                                    isSelected ? item.selectedIcon : item.icon,
                                    size: 20,
                                    color: isSelected ? activeFg : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected
                                      ? activeFg
                                      : colorScheme.onSurfaceVariant.withAlpha(200),
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
