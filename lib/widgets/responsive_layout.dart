import 'package:flutter/material.dart';
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

class _AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  bool _isRailExtended = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isDesktop) {
      // 桌面 PC 宽屏排版：左侧 NavigationRail + 右侧主体
      return Scaffold(
        body: Row(
          children: [
            // 左侧桌面侧边栏
            Material(
              color: colorScheme.surfaceContainerLow,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
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
                            if (_isRailExtended) ...[
                              const SizedBox(width: 12),
                              Expanded(
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
                            ],
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
                                        if (_isRailExtended) ...[
                                          const SizedBox(width: 14),
                                          Expanded(
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
                                        ],
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
            // 右侧主体
            Expanded(
              child: Scaffold(
                appBar: widget.appBar,
                body: widget.body,
                floatingActionButton: widget.floatingActionButton,
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
              selectedIndex: widget.currentIndex.clamp(
                0,
                effectiveBottomNav.length - 1,
              ),
              onDestinationSelected: (idx) {
                final item = effectiveBottomNav[idx];
                if (item.onTap != null) {
                  item.onTap!();
                } else {
                  widget.onNavigationChanged(idx);
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
