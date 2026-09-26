import 'package:flutter/material.dart';

import '../core/app_config.dart';
import 'visual_grid_canvas.dart';

/// DIY 模块元数据注册定义
class DiyModuleMeta {
  final String id;
  final String name;
  final String description;
  final IconData icon;

  const DiyModuleMeta({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
  });
}

/// DIY 布局工坊（支持实时所见即所得调控）
class DiyLayoutStudio extends StatefulWidget {
  final int initialTab; // 0: 首页, 1: 帖子详情页, 2: 预设

  const DiyLayoutStudio({super.key, this.initialTab = 0});

  /// 静态呼出方法
  static Future<void> show(BuildContext context, {int initialTab = 0}) {
    return showDialog(
      context: context,
      barrierColor: Colors.black45,
      builder: (_) => DiyLayoutStudio(initialTab: initialTab),
    );
  }

  /// 公共模块元数据字典查询
  static Map<String, DiyModuleMeta> get homeModuleRegistry => _DiyLayoutStudioState.homeModuleRegistry;
  static Map<String, DiyModuleMeta> get forumModuleRegistry => _DiyLayoutStudioState.forumModuleRegistry;
  static Map<String, DiyModuleMeta> get threadModuleRegistry => _DiyLayoutStudioState.threadModuleRegistry;

  @override
  State<DiyLayoutStudio> createState() => _DiyLayoutStudioState();
}

class _DiyLayoutStudioState extends State<DiyLayoutStudio>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 首页可选模块字典
  static const Map<String, DiyModuleMeta> homeModuleRegistry = {
    'tuhao_stats': DiyModuleMeta(
      id: 'tuhao_stats',
      name: '今日之星与全站统计',
      description: '呈现全站帖子、会员统计与今日焦点之星',
      icon: Icons.workspace_premium_rounded,
    ),
    'horn_banner': DiyModuleMeta(
      id: 'horn_banner',
      name: '全站小喇叭广播',
      description: '论坛广播消息跑马灯横幅',
      icon: Icons.campaign_rounded,
    ),
    'credit_log': DiyModuleMeta(
      id: 'credit_log',
      name: '个人积分流水账卡片',
      description: '实时显示个人总积分、铁粒余额与最新收支明细',
      icon: Icons.account_balance_wallet_rounded,
    ),
    'forum_grid': DiyModuleMeta(
      id: 'forum_grid',
      name: '版块分类与关注网格',
      description: '全论坛版块分类导航及已收藏版块快捷入口',
      icon: Icons.dashboard_customize_rounded,
    ),
    'feed_list': DiyModuleMeta(
      id: 'feed_list',
      name: '帖子动态信息流',
      description: '推荐/最新/精华主题帖子流，支持多种卡片排版',
      icon: Icons.dynamic_feed_rounded,
    ),
  };

  // 版块页面可选模块字典
  static const Map<String, DiyModuleMeta> forumModuleRegistry = {
    'forum_header': DiyModuleMeta(
      id: 'forum_header',
      name: '版块信息与统计看板',
      description: '呈现版块横幅、今日新帖、主题总量、版规及现任版主',
      icon: Icons.info_outline_rounded,
    ),
    'sub_forums': DiyModuleMeta(
      id: 'sub_forums',
      name: '子版块 / 关联版块网格',
      description: '快捷展开版块下属子板块、分区或相关专区导航',
      icon: Icons.grid_view_rounded,
    ),
    'type_filter': DiyModuleMeta(
      id: 'type_filter',
      name: '分类标签与排序筛选',
      description: '全版块主题分类/高亮筛选（悬赏/教程/资源等）及排序选项',
      icon: Icons.filter_alt_outlined,
    ),
    'sticky_threads': DiyModuleMeta(
      id: 'sticky_threads',
      name: '置顶推荐主题区',
      description: '高亮置顶公告、官方活动与精华置顶帖子',
      icon: Icons.push_pin_rounded,
    ),
    'thread_feed': DiyModuleMeta(
      id: 'thread_feed',
      name: '版块帖子主信息流',
      description: '主线帖子列表，包含封面、作者、摘要与统计',
      icon: Icons.dynamic_feed_rounded,
    ),
  };

  // 帖子详情页右侧工作台可选模块字典
  static const Map<String, DiyModuleMeta> threadModuleRegistry = {
    'toc_outline': DiyModuleMeta(
      id: 'toc_outline',
      name: '文章大纲目录树 (TOC)',
      description: '自动提取正文与各楼层标题，点击平滑滚动直达',
      icon: Icons.format_list_bulleted_rounded,
    ),
    'floor_compass': DiyModuleMeta(
      id: 'floor_compass',
      name: '楼层罗盘与精准直达',
      description: '快速定位 1#、最新回复、只看楼主或输入楼层跳达',
      icon: Icons.explore_rounded,
    ),
    'reader_tuning': DiyModuleMeta(
      id: 'reader_tuning',
      name: '阅读排版调谐器',
      description: '无级微调正文字号、行间距与正文最大宽度',
      icon: Icons.tune_rounded,
    ),
    'rating_hub': DiyModuleMeta(
      id: 'rating_hub',
      name: '打赏评分筛选大厅',
      description: '多币种汇总徽章、实时模糊搜索与大额排序',
      icon: Icons.card_giftcard_rounded,
    ),
    'media_gallery': DiyModuleMeta(
      id: 'media_gallery',
      name: '全帖媒体附件画廊',
      description: '聚合当前帖子所有图片与资源附件，支持沉浸画廊',
      icon: Icons.photo_library_rounded,
    ),
    'thread_search': DiyModuleMeta(
      id: 'thread_search',
      name: '帖内检索与内容速查',
      description: '实时检索全帖楼层关键词、高亮命中与快速跳达',
      icon: Icons.search_rounded,
    ),
    'author_card': DiyModuleMeta(
      id: 'author_card',
      name: '楼主名片与作者档案',
      description: '展示楼主权威身份、勋章、空间主页与发帖历史',
      icon: Icons.badge_outlined,
    ),
    'sign_calendar': DiyModuleMeta(
      id: 'sign_calendar',
      name: '每日签到打卡日历',
      description: '帖内直接查看连签进度、本周打卡与快捷签到',
      icon: Icons.calendar_month_rounded,
    ),
    'forum_list': DiyModuleMeta(
      id: 'forum_list',
      name: '版块主题流速览',
      description: '同版块主题动态速览与跟手切帖面板',
      icon: Icons.list_alt_rounded,
    ),
    'quick_reply': DiyModuleMeta(
      id: 'quick_reply',
      name: '快捷回复输入框',
      description: '单行输入与表情，快速互动',
      icon: Icons.reply_all_rounded,
    ),
    'papa_ai_quick': DiyModuleMeta(
      id: 'papa_ai_quick',
      name: '帕帕 AI 助手',
      description: '快捷提问、大纲生成与灵感助手',
      icon: Icons.smart_toy_rounded,
    ),
    'sign_fortune': DiyModuleMeta(
      id: 'sign_fortune',
      name: '签到与今日运势',
      description: '今日运势签文诗号、打卡天数与一键签到',
      icon: Icons.event_available_rounded,
    ),
    'tuhao_stats': DiyModuleMeta(
      id: 'tuhao_stats',
      name: '今日之星与全站统计',
      description: '今日签到/霸屏榜首、全站发帖与会员数据统计',
      icon: Icons.workspace_premium_rounded,
    ),
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isCompact ? size.width * 0.96 : 680,
          maxHeight: isCompact ? size.height * 0.88 : 640,
        ),
        child: Material(
          color: colorScheme.surface,
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // 头部操作条
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withAlpha(80),
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withAlpha(40),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.space_dashboard_rounded,
                        size: 20,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DIY 布局工坊',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '实时所见即所得 · 模块化自定义排版',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withAlpha(190),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF059669).withAlpha(80),
                          width: 0.6,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, size: 13, color: Color(0xFF059669)),
                          SizedBox(width: 3),
                          Text(
                            '实时生效',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: '完成并关闭',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Tab 切换栏
              TabBar(
                controller: _tabController,
                labelColor: colorScheme.primary,
                unselectedLabelColor: colorScheme.onSurfaceVariant,
                indicatorColor: colorScheme.primary,
                indicatorWeight: 2.5,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.home_outlined, size: 18),
                    text: '首页模块 DIY',
                  ),
                  Tab(
                    icon: Icon(Icons.forum_outlined, size: 18),
                    text: '版块模块 DIY',
                  ),
                  Tab(
                    icon: Icon(Icons.article_outlined, size: 18),
                    text: '帖子详情工作台',
                  ),
                  Tab(
                    icon: Icon(Icons.tune_rounded, size: 18),
                    text: '尺寸与预设',
                  ),
                ],
              ),

              // Tab 页面
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildHomeTab(context),
                    _buildForumTab(context),
                    _buildThreadTab(context),
                    _buildTuningTab(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 1. 首页 DIY 选项卡 =================
  Widget _buildHomeTab(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeModules = List<String>.from(AppConfig.homeModules);

    // 未添加的可用模块
    final availableModules = homeModuleRegistry.keys
        .where((id) => !activeModules.contains(id))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 0. 进入 2D 可视化自由排版画布（首页）
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer.withAlpha(120),
                colorScheme.surfaceContainerHighest.withAlpha(100),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.primary.withAlpha(60), width: 0.8),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.grid_view_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('首页 2D 可视化自由画布', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '桌面端左右侧栏卡片自由拖拽、无级拉伸尺寸与实时吸附对齐',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('进入画布', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VisualGridCanvas(
                        pageCategory: 'home',
                        initialLayout: AppConfig.homeDashboardLayout,
                        onSave: (layout) {
                          AppConfig.setHomeDashboardLayout(layout);
                        },
                        onExit: () => Navigator.of(context).pop(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // 1. 移动端/流式排版说明与已启用列表
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withAlpha(40), width: 0.8),
          ),
          child: Row(
            children: [
              Icon(Icons.stay_current_portrait_rounded, size: 20, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('移动端 / 竖屏信息流组件排版', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '移动端及主信息流中广播喇叭、版块导航、全站统计与帖子流的上下展示顺序与开关。',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Row(
          children: [
            Text(
              '当前已启用信息流组件（上下拖拽排序）',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '${activeModules.length} 个组件',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 已启用列表
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: activeModules.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = activeModules.removeAt(oldIndex);
              activeModules.insert(newIndex, item);
              AppConfig.setHomeModules(activeModules);
            });
          },
          itemBuilder: (ctx, index) {
            final id = activeModules[index];
            final meta = homeModuleRegistry[id] ??
                DiyModuleMeta(
                  id: id,
                  name: id,
                  description: '自定义模块',
                  icon: Icons.widgets_outlined,
                );

            return Container(
              key: ValueKey('home_$id'),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(70),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.outlineVariant.withAlpha(40),
                  width: 0.8,
                ),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                leading: Icon(meta.icon, size: 22, color: colorScheme.primary),
                title: Text(
                  meta.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                subtitle: Text(
                  meta.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withAlpha(180),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      tooltip: '从首页移除',
                      color: colorScheme.error.withAlpha(200),
                      onPressed: () {
                        setState(() {
                          activeModules.removeAt(index);
                          AppConfig.setHomeModules(activeModules);
                        });
                      },
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          size: 20,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),
        if (availableModules.isNotEmpty) ...[
          Text(
            '可添加的模块库（点击即可加入首页）',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          for (final id in availableModules) ...[
            Builder(builder: (ctx) {
              final meta = homeModuleRegistry[id]!;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withAlpha(45),
                    width: 0.8,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(meta.icon, size: 20, color: colorScheme.outline),
                  title: Text(
                    meta.name,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                  subtitle: Text(
                    meta.description,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withAlpha(160),
                    ),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () {
                      setState(() {
                        activeModules.add(id);
                        AppConfig.setHomeModules(activeModules);
                      });
                    },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14),
                        SizedBox(width: 4),
                        Text('添加', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ],
    );
  }

  // ================= 2. 版块模块 DIY 选项卡 =================
  Widget _buildForumTab(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeModules = List<String>.from(AppConfig.forumModules);

    final availableModules = forumModuleRegistry.keys
        .where((id) => !activeModules.contains(id))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 版块单列信息流架构说明横幅
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer.withAlpha(90),
                colorScheme.surfaceContainerHighest.withAlpha(80),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.primary.withAlpha(50), width: 0.8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.view_stream_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('版块页信息流排版定制', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(
                      '版块列表页采用原汁原味的垂直流式架构（非 2D 网格）。您可以在下方上下拖拽调整版头横幅、分类筛选、子版块网格、置顶主题与主帖列表的显示顺序及启用状态。',
                      style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Text(
              '当前已启用版块组件（上下拖拽排序）',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '${activeModules.length} 个组件',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 已启用列表
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: activeModules.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = activeModules.removeAt(oldIndex);
              activeModules.insert(newIndex, item);
              AppConfig.setForumModules(activeModules);
            });
          },
          itemBuilder: (ctx, index) {
            final id = activeModules[index];
            final meta = forumModuleRegistry[id] ??
                DiyModuleMeta(
                  id: id,
                  name: id,
                  description: '版块组件',
                  icon: Icons.widgets_outlined,
                );

            return Container(
              key: ValueKey('forum_$id'),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(70),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.outlineVariant.withAlpha(40),
                  width: 0.8,
                ),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                leading: Icon(meta.icon, size: 22, color: colorScheme.primary),
                title: Text(
                  meta.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                subtitle: Text(
                  meta.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withAlpha(180),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      tooltip: '隐藏此组件',
                      color: colorScheme.error.withAlpha(200),
                      onPressed: () {
                        setState(() {
                          activeModules.removeAt(index);
                          AppConfig.setForumModules(activeModules);
                        });
                      },
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          size: 20,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),
        if (availableModules.isNotEmpty) ...[
          Text(
            '未启用的版块组件（点击加入版块流）',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          for (final id in availableModules) ...[
            Builder(builder: (ctx) {
              final meta = forumModuleRegistry[id]!;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withAlpha(45),
                    width: 0.8,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(meta.icon, size: 20, color: colorScheme.outline),
                  title: Text(
                    meta.name,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                  subtitle: Text(
                    meta.description,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withAlpha(160),
                    ),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () {
                      setState(() {
                        activeModules.add(id);
                        AppConfig.setForumModules(activeModules);
                      });
                    },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14),
                        SizedBox(width: 4),
                        Text('添加', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ],
    );
  }

  // ================= 3. 帖子详情工作台选项卡 =================
  Widget _buildThreadTab(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rightModules = List<String>.from(AppConfig.threadRightModules);

    // 未添加至工作台的模块
    final unassigned = threadModuleRegistry.keys
        .where((id) => !rightModules.contains(id))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 0. 进入 2D 可视化自由排版画布
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer.withAlpha(120),
                colorScheme.surfaceContainerHighest.withAlpha(100),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.primary.withAlpha(60), width: 0.8),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.grid_view_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('2D 可视化自由排版画布', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '自由拖拽卡片、无级拉伸尺寸、实时 1:1 仿真对齐',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('进入画布', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VisualGridCanvas(
                        pageCategory: 'thread',
                        initialLayout: AppConfig.threadDashboardLayout,
                        onSave: (layout) {
                          AppConfig.setThreadDashboardLayout(layout);
                        },
                        onExit: () => Navigator.of(context).pop(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // 1. 左侧版块导航分栏配置
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withAlpha(40), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.view_sidebar_rounded, size: 20, color: Colors.blue),
                ),
                title: const Text('左侧版块列表分栏', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Text('桌面宽屏下，帖子左侧展示同版块帖子列表，支持自由拖拽调宽与 1 键快捷折叠', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                value: AppConfig.threadLeftEnabled,
                onChanged: (v) {
                  setState(() => AppConfig.setThreadLeftEnabled(v));
                },
              ),
              if (AppConfig.threadLeftEnabled) ...[
                const Divider(height: 12),
                Row(
                  children: [
                    const Text('分栏默认宽度：', style: TextStyle(fontSize: 12)),
                    Text(
                      '${AppConfig.threadForumSidebarWidth.toInt()} px',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () {
                        setState(() => AppConfig.setThreadForumSidebarWidth(380.0));
                      },
                      child: const Text('恢复 380px', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                Slider(
                  value: AppConfig.threadForumSidebarWidth.clamp(240.0, 640.0),
                  min: 240,
                  max: 640,
                  divisions: 40,
                  label: '${AppConfig.threadForumSidebarWidth.toInt()}px',
                  onChanged: (v) {
                    setState(() => AppConfig.updateThreadForumSidebarWidth(v));
                  },
                  onChangeEnd: (v) {
                    AppConfig.setThreadForumSidebarWidth(v);
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. 右侧工作台助手总开关与说明
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withAlpha(40), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.purple.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.dashboard_customize_rounded, size: 20, color: Colors.purple),
                ),
                title: const Text('右侧工作台助手', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Text('桌面宽屏常驻助手，提供目录树、打赏大厅、阅读字号微调与楼层罗盘', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                value: AppConfig.threadRightEnabled,
                onChanged: (v) {
                  setState(() => AppConfig.setThreadRightEnabled(v));
                },
              ),
              if (AppConfig.threadRightEnabled) ...[
                const Divider(height: 12),
                Row(
                  children: [
                    const Text('工作台默认宽度：', style: TextStyle(fontSize: 12)),
                    Text(
                      '${AppConfig.threadRightWidth.toInt()} px',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () {
                        setState(() => AppConfig.setThreadRightWidth(320.0));
                      },
                      child: const Text('恢复 320px', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                Slider(
                  value: AppConfig.threadRightWidth.clamp(200.0, 500.0),
                  min: 200,
                  max: 500,
                  divisions: 30,
                  label: '${AppConfig.threadRightWidth.toInt()}px',
                  onChanged: (v) {
                    setState(() => AppConfig.updateThreadRightWidth(v));
                  },
                  onChangeEnd: (v) {
                    AppConfig.setThreadRightWidth(v);
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 已挂载的工作台模块
        Row(
          children: [
            Text(
              '已挂载工作台模块（拖动调整上下顺序）',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '${rightModules.length} 个模块',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (rightModules.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withAlpha(50),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text('当前工作台未挂载任何模块，点击下方卡片可快速添加', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: rightModules.length,
            onReorder: (oldIdx, newIdx) {
              if (newIdx > oldIdx) newIdx -= 1;
              final item = rightModules.removeAt(oldIdx);
              rightModules.insert(newIdx, item);
              setState(() {
                AppConfig.setThreadRightModules(rightModules);
              });
            },
            itemBuilder: (ctx, idx) {
              final id = rightModules[idx];
              final meta = threadModuleRegistry[id] ??
                  DiyModuleMeta(
                    id: id,
                    name: id,
                    description: '',
                    icon: Icons.widgets_outlined,
                  );

              return Container(
                key: ValueKey('th_$id'),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(70),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant.withAlpha(40), width: 0.8),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Icon(meta.icon, size: 22, color: colorScheme.primary),
                  title: Text(meta.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  subtitle: Text(meta.description, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withAlpha(180))),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        tooltip: '从工作台移除',
                        color: colorScheme.error.withAlpha(200),
                        onPressed: () {
                          setState(() {
                            rightModules.removeAt(idx);
                            AppConfig.setThreadRightModules(rightModules);
                          });
                        },
                      ),
                      ReorderableDragStartListener(
                        index: idx,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle_rounded, size: 20, color: colorScheme.outline),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        const SizedBox(height: 18),
        // 未添加模块池
        if (unassigned.isNotEmpty) ...[
          Text(
            '未挂载模块库（点击即可加入右侧工作台）',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          for (final id in unassigned) ...[
            Builder(builder: (ctx) {
              final meta = threadModuleRegistry[id]!;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(meta.icon, size: 20, color: colorScheme.outline),
                  title: Text(meta.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  subtitle: Text(meta.description, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withAlpha(160))),
                  trailing: FilledButton.tonal(
                    onPressed: () {
                      setState(() {
                        rightModules.add(id);
                        AppConfig.setThreadRightModules(rightModules);
                      });
                    },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14),
                        SizedBox(width: 4),
                        Text('添加至工作台', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ],
    );
  }

  // ================= 3. 尺寸与预设选项卡 =================
  Widget _buildTuningTab(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '正文与边栏尺寸微调',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // 正文最大宽度
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('正文限制宽度：', style: TextStyle(fontSize: 13)),
                Text(
                  AppConfig.threadContentMaxWidth == 0
                      ? '100% 全屏满铺'
                      : '${AppConfig.threadContentMaxWidth.toInt()} px',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      AppConfig.setThreadContentMaxWidth(
                        AppConfig.threadContentMaxWidth == 0 ? 960.0 : 0,
                      );
                    });
                  },
                  child: Text(
                    AppConfig.threadContentMaxWidth == 0 ? '设为 960px' : '一键全屏满铺',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            Slider(
              value: AppConfig.threadContentMaxWidth == 0 ? 1800 : AppConfig.threadContentMaxWidth,
              min: 680,
              max: 1800,
              divisions: 28,
              label: AppConfig.threadContentMaxWidth == 0
                  ? '全屏'
                  : '${AppConfig.threadContentMaxWidth.toInt()}px',
              onChanged: (v) {
                setState(() => AppConfig.updateThreadContentMaxWidth(v));
              },
              onChangeEnd: (v) {
                AppConfig.setThreadContentMaxWidth(v);
              },
            ),
          ],
        ),

        // 版块列表边栏宽度（左侧）
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('版块列表边栏宽度（左侧）：', style: TextStyle(fontSize: 13)),
                Text(
                  '${AppConfig.threadForumSidebarWidth.toInt()} px',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      AppConfig.setThreadForumSidebarWidth(380.0);
                    });
                  },
                  child: const Text('重置为 380px', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            Slider(
              value: AppConfig.threadForumSidebarWidth.clamp(240.0, 680.0),
              min: 240,
              max: 680,
              divisions: 44,
              label: '${AppConfig.threadForumSidebarWidth.toInt()}px',
              onChanged: (v) {
                setState(() => AppConfig.updateThreadForumSidebarWidth(v));
              },
              onChangeEnd: (v) {
                AppConfig.setThreadForumSidebarWidth(v);
              },
            ),
          ],
        ),

        // 右侧栏工作台宽度
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('右侧工作台宽度：', style: TextStyle(fontSize: 13)),
                Text(
                  '${AppConfig.threadRightWidth.toInt()} px',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            Slider(
              value: AppConfig.threadRightWidth,
              min: 200,
              max: 500,
              divisions: 30,
              label: '${AppConfig.threadRightWidth.toInt()}px',
              onChanged: (v) {
                setState(() => AppConfig.updateThreadRightWidth(v));
              },
              onChangeEnd: (v) {
                AppConfig.setThreadRightWidth(v);
              },
            ),
          ],
        ),

        const Divider(height: 24),
        Text(
          '一键经典布局预设',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.dashboard_customize_rounded, size: 16),
              label: const Text('标准双栏工作台'),
              onPressed: () {
                setState(() {
                  AppConfig.setHomeModules(List.from(AppConfig.defaultHomeModules));
                  AppConfig.setForumModules(List.from(AppConfig.defaultForumModules));
                  AppConfig.setThreadRightModules(['toc_outline', 'floor_compass', 'reader_tuning', 'rating_hub']);
                  AppConfig.setThreadRightEnabled(true);
                  AppConfig.setThreadForumSidebarWidth(380);
                  AppConfig.setThreadRightWidth(320);
                  AppConfig.setThreadContentMaxWidth(960);
                });
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.menu_book_rounded, size: 16),
              label: const Text('沉浸专注阅读'),
              onPressed: () {
                setState(() {
                  AppConfig.setThreadRightEnabled(false);
                  AppConfig.setThreadContentMaxWidth(1100);
                });
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.fullscreen_rounded, size: 16),
              label: const Text('100% 满屏填满'),
              onPressed: () {
                setState(() {
                  AppConfig.setThreadContentMaxWidth(0);
                });
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.restore_rounded, size: 16),
              label: const Text('恢复全部默认'),
              onPressed: () {
                setState(() {
                  AppConfig.resetDiyLayout();
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}
