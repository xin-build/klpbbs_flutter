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
      // 桌面 PC 宽屏排版：左侧 NavigationRail + 右侧主体（抽屉挂载于右侧主体，从侧栏右缘滑入，不再横穿左侧栏）
      return Scaffold(
        body: Row(
          children: [
            // 左侧桌面侧边栏
            Material(
              color: colorScheme.surfaceContainerLow,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                width: _isRailExtended ? 220 : 80,
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: colorScheme.outlineVariant.withAlpha(50),
                      width: 1,
                    ),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      // 顶部 Logo / 标题区
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 16),
                        child: Row(
                          mainAxisAlignment: _isRailExtended
                              ? MainAxisAlignment.start
                              : MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.shadow.withAlpha(20),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.view_in_ar_rounded,
                                color: colorScheme.primary,
                                size: 26,
                              ),
                            ),
                            ClipRect(
                              child: AnimatedCrossFade(
                                duration: const Duration(milliseconds: 220),
                                crossFadeState: _isRailExtended
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                firstChild: const SizedBox.shrink(),
                                secondChild: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '苦力怕论坛',
                                        style:
                                            theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'KLPBBS Desktop',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.outline,
                                          fontSize: 11,
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
                      if (widget.desktopHeader != null) widget.desktopHeader!,
                      const Divider(height: 1, indent: 8, endIndent: 8),
                      // 导航项列表
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 8),
                          itemCount: widget.navItems.length,
                          itemBuilder: (context, index) {
                            final item = widget.navItems[index];
                            final isSelected = widget.currentIndex == index;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Tooltip(
                                message: _isRailExtended ? '' : item.label,
                                preferBelow: false,
                                child: InkWell(
                                  onTap: () {
                                    if (item.onTap != null) {
                                      item.onTap!();
                                    } else {
                                      widget.onNavigationChanged(index);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(14),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: _isRailExtended ? 14 : 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? colorScheme.secondaryContainer
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: _isRailExtended
                                          ? MainAxisAlignment.start
                                          : MainAxisAlignment.center,
                                      children: [
                                        Badge(
                                          isLabelVisible:
                                              (item.badgeCount ?? 0) > 0,
                                          label: Text('${item.badgeCount}'),
                                          child: Icon(
                                            isSelected
                                                ? item.selectedIcon
                                                : item.icon,
                                            color: isSelected
                                                ? colorScheme
                                                    .onSecondaryContainer
                                                : colorScheme.onSurfaceVariant,
                                            size: 24,
                                          ),
                                        ),
                                        ClipRect(
                                          child: AnimatedCrossFade(
                                            duration: const Duration(milliseconds: 220),
                                            crossFadeState: _isRailExtended
                                                ? CrossFadeState.showSecond
                                                : CrossFadeState.showFirst,
                                            firstChild: const SizedBox.shrink(),
                                            secondChild: Padding(
                                              padding: const EdgeInsets.only(left: 14),
                                              child: Text(
                                                item.label,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: isSelected
                                                      ? colorScheme
                                                          .onSecondaryContainer
                                                      : colorScheme.onSurface,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
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
                          },
                        ),
                      ),
                      // 底部折叠切换与操作
                      if (widget.desktopFooter != null) widget.desktopFooter!,
                      const Divider(height: 1, indent: 8, endIndent: 8),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: IconButton(
                          tooltip: _isRailExtended ? '收起侧栏' : '展开侧栏',
                          icon: Icon(
                            _isRailExtended
                                ? Icons.menu_open_rounded
                                : Icons.menu_rounded,
                            color: colorScheme.outline,
                          ),
                          onPressed: () {
                            setState(() => _isRailExtended = !_isRailExtended);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 右侧主体：严格 ClipRect 边界守护 + Stack 桌面卡片动效层，杜绝跨越左侧栏
            Expanded(
              child: ClipRect(
                child: Stack(
                  children: [
                    Scaffold(
                      key: widget.scaffoldKey,
                      appBar: widget.appBar,
                      body: widget.body,
                      floatingActionButton: widget.floatingActionButton,
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
                                      color: Colors.black.withOpacity(0.32 * t),
                                    ),
                                  ),
                                ),
                                // 2. 抽屉面板：平滑淡入 + 35px 优雅微滑出，严禁越界横跨左侧栏
                                Positioned(
                                  top: 0,
                                  bottom: 0,
                                  left: 0,
                                  child: Transform.translate(
                                    offset: Offset(-35.0 * (1.0 - t), 0),
                                    child: Opacity(
                                      opacity: t.clamp(0.0, 1.0),
                                      child: Material(
                                        elevation: 16,
                                        shadowColor: Colors.black38,
                                        borderRadius: const BorderRadius.horizontal(
                                          right: Radius.circular(16),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: SizedBox(
                                          width: 320,
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
          ],
        ),
      );
    }

    // 移动端排版：底栏或抽屉
    final useBottomNav = AppConfig.navLayout == NavLayout.bottom;
    final bottomNavItems = widget.navItems.where((item) => item.onTap == null).toList();
    final effectiveBottomNav = bottomNavItems.isNotEmpty ? bottomNavItems : widget.navItems;

    return Scaffold(
      key: widget.scaffoldKey,
      appBar: widget.appBar,
      drawer: widget.drawer,
      body: widget.body,
      floatingActionButton: widget.floatingActionButton,
      bottomNavigationBar: useBottomNav
          ? NavigationBar(
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
            )
          : null,
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
