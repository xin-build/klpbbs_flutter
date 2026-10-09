import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'forum_search_field.dart';

import '../core/home_layout_metrics.dart';
import '../models/dashboard_card_model.dart';
import '../models/thread_summary.dart';
import 'app_motion.dart';
import 'animated_side_panel.dart';
import 'empty_view.dart';
import 'pagination_control.dart';
import 'responsive_layout.dart';
import 'sliver_two_column_feed.dart';
import 'smooth_scroll_controller.dart';
import 'thread_card.dart';

const guideViews = [
  ('hot', '热门', Icons.local_fire_department_rounded),
  ('new', '最新回复', Icons.auto_awesome_rounded),
  ('newthread', '最新发表', Icons.access_time_rounded),
  ('digest', '精华', Icons.workspace_premium_rounded),
  ('follow', '我关注的', Icons.people_alt_outlined),
  ('sofa', '抢沙发', Icons.event_seat_outlined),
];

/// Shared geometry for the live guide and the canvas viewport preview.
class GuideLayout {
  static const contentMaxWidth = 1200.0;
  static const workbenchWidth = 320.0;
  static const collapsedWidth = 20.0;

  static bool canShowWorkbench(BuildContext context, double width) =>
      ResponsiveBreakpoints.isDesktop(context) && width >= 1040;

  static double cardHeight(int rows) => HomeLayoutMetrics.sidebarCardHeight(
      type: '', rows: rows, width: workbenchWidth);
}

/// Category tabs are measured with the user's text scale, including the icons
/// and tab padding. Neither this header nor GuideContent loads data.
class GuideCategoryTabs extends StatelessWidget implements PreferredSizeWidget {
  final TabController? controller;
  final double tabHeight;
  final ValueChanged<String>? onViewSelected;

  const GuideCategoryTabs({
    super.key,
    this.controller,
    required this.tabHeight,
    this.onViewSelected,
  });

  static double heightFor(BuildContext context) {
    final painter = TextPainter(
        text: const TextSpan(
            text: '最新回复',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context))
      ..layout();
    return math.max(44, painter.height + 16);
  }

  @override
  Size get preferredSize => Size.fromHeight(tabHeight + 14);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
        child: Material(
          color: scheme.surfaceContainerHighest.withAlpha(120),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: LayoutBuilder(builder: (context, constraints) {
              var requiredWidth = 0.0;
              for (final (_, label, _) in guideViews) {
                final painter = TextPainter(
                    text: TextSpan(
                        text: label,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    textScaler: MediaQuery.textScalerOf(context),
                    textDirection: Directionality.of(context))
                  ..layout();
                requiredWidth += painter.width + 14 + 4 + 32;
              }
              final scrollable = requiredWidth > constraints.maxWidth;
              return SizedBox(
                  height: tabHeight,
                  child: TabBar(
                    key: const ValueKey('guide-category-tabs'),
                    controller: controller,
                    isScrollable: scrollable,
                    tabAlignment:
                        scrollable ? TabAlignment.start : TabAlignment.fill,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(19),
                      color: scheme.secondaryContainer,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: scheme.onSecondaryContainer,
                    unselectedLabelColor: scheme.onSurfaceVariant,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13),
                    onTap: onViewSelected == null
                        ? null
                        : (index) => onViewSelected!(guideViews[index].$1),
                    tabs: [
                      for (final (view, label, icon) in guideViews)
                        Tab(
                            key: ValueKey('guide-tab-$view'),
                            height: tabHeight,
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 14),
                                  const SizedBox(width: 4),
                                  Text(label),
                                ])),
                    ],
                  ));
            }),
          ),
        ));
  }
}

class GuidePageHeader extends StatelessWidget implements PreferredSizeWidget {
  final TabController? controller;
  final double tabHeight;
  final double toolbarHeight;
  final Widget? leading;
  final double? leadingWidth;
  final ValueChanged<String>? onViewSelected;
  final TextEditingController? searchController;
  final VoidCallback? onSearch, onRefresh, onCustomize, onToggleWorkbench;
  final bool workbenchExpanded, loading;

  const GuidePageHeader({
    super.key,
    this.controller,
    required this.tabHeight,
    this.toolbarHeight = kToolbarHeight,
    this.leading,
    this.leadingWidth,
    this.onViewSelected,
    this.searchController,
    this.onSearch,
    this.onRefresh,
    this.onCustomize,
    this.onToggleWorkbench,
    this.workbenchExpanded = true,
    this.loading = false,
  });

  static double toolbarHeightFor(BuildContext context) =>
      math.max(64, MediaQuery.textScalerOf(context).scale(18) + 28);

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight + tabHeight + 14);

  @override
  Widget build(BuildContext context) {
    final desktop = ResponsiveBreakpoints.isDesktop(context);
    final inline = desktop &&
        MediaQuery.sizeOf(context).width >= 960 &&
        searchController != null;
    return AppBar(
      key: const ValueKey('guide-page-header'),
      toolbarHeight: toolbarHeight,
      leading: leading,
      leadingWidth: leadingWidth,
      title: inline
          ? Row(children: [
              const Text('导读'),
              const SizedBox(width: 20),
              Expanded(
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: ForumSearchField(
                              fieldKey: const ValueKey('guide-search'),
                              controller: searchController!,
                              onSearch: onSearch)))),
            ])
          : const Text('导读'),
      centerTitle: !inline,
      actions: [
        if (!inline && onSearch != null)
          IconButton(
              onPressed: onSearch,
              tooltip: '搜索论坛',
              icon: const Icon(Icons.search_rounded)),
        if (onRefresh != null)
          IconButton(
              key: const ValueKey('guide-header-refresh'),
              onPressed: loading ? null : onRefresh,
              tooltip: '刷新当前分类',
              icon: const Icon(Icons.refresh_rounded)),
        if (desktop && onToggleWorkbench != null)
          IconButton(
              key: const ValueKey('guide-header-workbench'),
              onPressed: onToggleWorkbench,
              tooltip: workbenchExpanded ? '收起工作台' : '展开工作台',
              icon: Icon(workbenchExpanded
                  ? Icons.last_page_rounded
                  : Icons.first_page_rounded)),
        if (desktop && onCustomize != null)
          IconButton(
              key: const ValueKey('guide-header-canvas'),
              onPressed: onCustomize,
              tooltip: '自由画布工坊',
              icon: const Icon(Icons.dashboard_customize_outlined)),
        const SizedBox(width: 8),
      ],
      bottom: GuideCategoryTabs(
          controller: controller,
          tabHeight: tabHeight,
          onViewSelected: onViewSelected),
    );
  }
}

class GuideWorkbenchHeader extends StatelessWidget {
  final VoidCallback? onSettings;
  final VoidCallback? onCollapse;

  const GuideWorkbenchHeader({
    super.key,
    this.onSettings,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
        key: const ValueKey('guide-workbench-header'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: scheme.outlineVariant.withAlpha(30), width: .5))),
        child: Row(children: [
          Icon(Icons.explore_outlined, size: 15, color: scheme.outline),
          const SizedBox(width: 6),
          Expanded(
              child: Text('导读 · 工作台',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.outline))),
          IconButton(
              key: const ValueKey('guide-workbench-settings'),
              icon: const Icon(Icons.tune_rounded, size: 15),
              tooltip: '工作台排版与设置',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: onSettings),
          const SizedBox(width: 4),
          IconButton(
              key: const ValueKey('guide-workbench-collapse'),
              icon: const Icon(Icons.last_page_rounded, size: 16),
              tooltip: '收起工作台',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: onCollapse),
        ]));
  }
}

class GuideWorkbench extends StatelessWidget {
  final List<DashboardGridItem> items;
  final Widget Function(BuildContext context, DashboardGridItem item)
      cardBuilder;
  final VoidCallback? onSettings;
  final VoidCallback? onCollapse;

  const GuideWorkbench({
    super.key,
    required this.items,
    required this.cardBuilder,
    this.onSettings,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
        width: GuideLayout.workbenchWidth,
        decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border(
                left: BorderSide(
                    color: scheme.outlineVariant.withAlpha(35), width: .8))),
        child: Column(children: [
          GuideWorkbenchHeader(onSettings: onSettings, onCollapse: onCollapse),
          Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('暂无工作台卡片\n可在设置中添加',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 12, color: scheme.outline)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => SizedBox(
                          height: GuideLayout.cardHeight(items[index].rowSpan),
                          child: cardBuilder(context, items[index])))),
        ]));
  }
}

class GuideWorkbenchHandle extends StatelessWidget {
  final VoidCallback? onExpand;

  const GuideWorkbenchHandle({super.key, this.onExpand});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
        message: '展开右侧边栏 (导读工作台)',
        child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Material(
                color: Colors.transparent,
                child: InkWell(
                    onTap: onExpand,
                    child: Container(
                        width: GuideLayout.collapsedWidth,
                        decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withAlpha(40),
                            border: Border(
                                left: BorderSide(
                                    color: scheme.outlineVariant.withAlpha(60),
                                    width: .8))),
                        child: Center(
                            child: Container(
                                width: 18,
                                height: 80,
                                decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(8),
                                        bottomLeft: Radius.circular(8)),
                                    border: Border.all(
                                        color: scheme.outlineVariant
                                            .withAlpha(140)),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black12, blurRadius: 4),
                                    ]),
                                child: Icon(Icons.chevron_left_rounded,
                                    size: 16, color: scheme.primary))))))));
  }
}

/// Unopened workbenches are lazy. Once opened, closing retains their state
/// offstage without ticking, so reopening does not restart every card request.
class GuideWorkbenchRegion extends StatelessWidget {
  final bool expanded;
  final WidgetBuilder workbenchBuilder;
  final VoidCallback? onExpand;
  final Key? handleKey;

  const GuideWorkbenchRegion({
    super.key,
    required this.expanded,
    required this.workbenchBuilder,
    this.onExpand,
    this.handleKey,
  });

  @override
  Widget build(BuildContext context) => AnimatedSidePanel(
      key: const ValueKey('guide-workbench-size'),
      expanded: expanded,
      width: GuideLayout.workbenchWidth,
      collapsedWidth: GuideLayout.collapsedWidth,
      splitterWidth: 0,
      isLeft: false,
      splitter: const SizedBox.shrink(),
      handle: GuideWorkbenchHandle(key: handleKey, onExpand: onExpand),
      child: Builder(builder: workbenchBuilder));
}

/// Local preview state reads only host-supplied cached data. A selected tab and
/// its rendered list always change together; missing pages stay explicit.
class CachedGuidePreview extends StatefulWidget {
  final String initialView;
  final int initialPage;
  final List<ThreadSummary>? Function(String view, int page) readThreads;
  final bool Function(String view, int page) readHasMore;
  final bool loggedIn;
  final bool scrollable;

  const CachedGuidePreview({
    super.key,
    required this.initialView,
    required this.initialPage,
    required this.readThreads,
    required this.readHasMore,
    this.loggedIn = false,
    this.scrollable = true,
  });

  @override
  State<CachedGuidePreview> createState() => _CachedGuidePreviewState();
}

class _CachedGuidePreviewState extends State<CachedGuidePreview>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late String _view;
  late int _page;
  final Map<String, int> _pages = {};
  final Map<String, double> _offsets = {};
  final SmoothScrollController _scroll = SmoothScrollController();

  @override
  void initState() {
    super.initState();
    final index =
        guideViews.indexWhere((view) => view.$1 == widget.initialView);
    _view = index < 0 ? 'hot' : widget.initialView;
    _page = widget.initialPage > 0 ? widget.initialPage : 1;
    _tabs = TabController(
        length: guideViews.length,
        initialIndex: index < 0 ? 0 : index,
        vsync: this)
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() => _selectView(guideViews[_tabs.index].$1);

  void _selectView(String view) {
    if (view == _view) return;
    _rememberPosition();
    setState(() {
      _view = view;
      _page = _pages[view] ?? 1;
    });
    _restorePosition();
  }

  void _selectPage(int page) {
    if (page < 1 || page == _page) return;
    if (widget.readThreads(_view, page) == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('此页尚未缓存，请在实际导读页面浏览后再预览。')));
      return;
    }
    _rememberPosition();
    setState(() => _page = page);
    _restorePosition();
  }

  void _rememberPosition() {
    _pages[_view] = _page;
    if (_scroll.hasClients) _offsets['${_view}_$_page'] = _scroll.offset;
  }

  void _restorePosition() {
    final key = '${_view}_$_page';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || key != '${_view}_$_page' || !_scroll.hasClients) return;
      _scroll.jumpTo(
          (_offsets[key] ?? 0).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cached = widget.readThreads(_view, _page);
    return Column(children: [
      GuideCategoryTabs(
          controller: _tabs,
          tabHeight: GuideCategoryTabs.heightFor(context),
          onViewSelected: _selectView),
      Expanded(
          child: GuideContent(
              threads: cached ?? const [],
              page: _page,
              hasMore: widget.readHasMore(_view, _page),
              controller: _scroll,
              onPageChanged: _selectPage,
              scrollable: widget.scrollable,
              loginRequired: _view == 'follow' && !widget.loggedIn,
              emptySubtitle:
                  cached == null ? '浏览此导读分类后，可在这里预览真实列表。预览不会联网加载。' : null)),
    ]);
  }
}

/// Actual guide feed renderer, shared with the canvas. Hosts own fetching,
/// navigation and page state. Preview callbacks can only select cached data.
class GuideContent extends StatelessWidget {
  final List<ThreadSummary> threads;
  final int page;
  final bool hasMore;
  final ScrollController? controller;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<ThreadSummary>? onOpenThread;
  final ValueChanged<int>? onOpenAuthor;
  final Future<void> Function()? onRefresh;
  final bool scrollable;
  final bool loginRequired;
  final VoidCallback? onLogin;
  final String? emptySubtitle;

  const GuideContent({
    super.key,
    required this.threads,
    required this.page,
    required this.hasMore,
    this.controller,
    this.onPageChanged,
    this.onOpenThread,
    this.onOpenAuthor,
    this.onRefresh,
    this.scrollable = true,
    this.loginRequired = false,
    this.onLogin,
    this.emptySubtitle,
  });

  @override
  Widget build(BuildContext context) {
    if (loginRequired) {
      return EmptyView(
          icon: Icons.people_alt_outlined,
          title: '登录后查看关注动态',
          action: FilledButton(onPressed: onLogin, child: const Text('登录')));
    }
    Widget card(int index, bool grid) {
      final thread = threads[index];
      return ThreadCard(
          key: ValueKey(thread.tid),
          thread: thread,
          isGrid: grid,
          adaptiveHeight: true,
          onTap: onOpenThread == null ? null : () => onOpenThread!(thread),
          onAuthorTap: thread.uid == null || onOpenAuthor == null
              ? null
              : () => onOpenAuthor!(thread.uid!));
    }

    final feed = LayoutBuilder(builder: (context, constraints) {
      final grid = ResponsiveBreakpoints.isDesktop(context) &&
          constraints.maxWidth >= 620;
      return CustomScrollView(
          key: const ValueKey('guide-content'),
          controller: controller,
          primary: false,
          physics: scrollable
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          slivers: [
            if (threads.isEmpty)
              SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyView(
                      icon: Icons.article_outlined,
                      title: '暂无导读内容',
                      subtitle: emptySubtitle ?? '切换其他分类或稍后重试',
                      action: onRefresh == null
                          ? null
                          : TextButton.icon(
                              key: const ValueKey('guide-empty-refresh'),
                              onPressed: () => onRefresh!(),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('刷新'))))
            else if (grid)
              SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverTwoColumnFeed(
                      itemCount: threads.length,
                      itemBuilder: (_, index) => card(index, true)))
            else
              SliverList.builder(
                  itemCount: threads.length,
                  itemBuilder: (_, index) => AppFadeIn(
                      index: index,
                      key: ValueKey('guide-entry-${threads[index].tid}'),
                      child: card(index, false))),
            SliverToBoxAdapter(
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: IgnorePointer(
                        ignoring: onPageChanged == null,
                        child: PaginationControl(
                            page: page,
                            hasMore: hasMore,
                            onPageChanged: onPageChanged ?? (_) {})))),
          ]);
    });
    return onRefresh == null
        ? feed
        : RefreshIndicator(onRefresh: onRefresh!, child: feed);
  }
}
