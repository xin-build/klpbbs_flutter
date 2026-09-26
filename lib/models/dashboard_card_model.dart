import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 卡片所属业务大类
enum DashboardCardCategory {
  stats('统计与数据', Icons.analytics_outlined),
  user('个人与资产', Icons.person_outline),
  content('内容与阅读', Icons.article_outlined),
  tool('实用工具', Icons.build_outlined),
  social('社交与动态', Icons.people_outline);

  final String label;
  final IconData icon;
  const DashboardCardCategory(this.label, this.icon);
}

/// 单个网格卡片放置项配置
class DashboardGridItem {
  final String id;
  final String cardType;
  int col;
  int row;
  int colSpan;
  int rowSpan;
  Map<String, dynamic> customParams;

  DashboardGridItem({
    required this.id,
    required this.cardType,
    required this.col,
    required this.row,
    required this.colSpan,
    required this.rowSpan,
    Map<String, dynamic>? customParams,
  }) : customParams = customParams ?? {};

  DashboardGridItem copyWith({
    String? id,
    String? cardType,
    int? col,
    int? row,
    int? colSpan,
    int? rowSpan,
    Map<String, dynamic>? customParams,
  }) {
    return DashboardGridItem(
      id: id ?? this.id,
      cardType: cardType ?? this.cardType,
      col: col ?? this.col,
      row: row ?? this.row,
      colSpan: colSpan ?? this.colSpan,
      rowSpan: rowSpan ?? this.rowSpan,
      customParams: customParams != null
          ? Map<String, dynamic>.from(customParams)
          : Map<String, dynamic>.from(this.customParams),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cardType': cardType,
      'col': col,
      'row': row,
      'colSpan': colSpan,
      'rowSpan': rowSpan,
      'customParams': customParams,
    };
  }

  factory DashboardGridItem.fromJson(Map<String, dynamic> json) {
    return DashboardGridItem(
      id: json['id'] as String? ?? 'item_${DateTime.now().millisecondsSinceEpoch}',
      cardType: json['cardType'] as String? ?? 'user_profile',
      col: (json['col'] as num?)?.toInt() ?? 0,
      row: (json['row'] as num?)?.toInt() ?? 0,
      colSpan: (json['colSpan'] as num?)?.toInt() ?? 2,
      rowSpan: (json['rowSpan'] as num?)?.toInt() ?? 1,
      customParams: json['customParams'] is Map
          ? Map<String, dynamic>.from(json['customParams'] as Map)
          : {},
    );
  }
}

/// 卡片定义元数据
class CardDefinition {
  final String cardType;
  final String name;
  final String description;
  final IconData icon;
  final DashboardCardCategory category;
  final Set<String> supportedPages; // 'home', 'thread', 'forum'
  final int minColSpan;
  final int minRowSpan;
  final int maxColSpan;
  final int maxRowSpan;
  final int defaultColSpan;
  final int defaultRowSpan;

  const CardDefinition({
    required this.cardType,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    this.supportedPages = const {'home'},
    this.minColSpan = 2,
    this.minRowSpan = 1,
    this.maxColSpan = 12,
    this.maxRowSpan = 6,
    this.defaultColSpan = 3,
    this.defaultRowSpan = 2,
  });
}

/// 全站卡片集中注册中心（严格按所属页面分类隔离，严禁跨页面出现专属卡片）
class CardRegistry {
  static const Map<String, CardDefinition> definitions = {
    // 1. 快捷发帖卡片（首页、导读页）
    'quick_post': CardDefinition(
      cardType: 'quick_post',
      name: '快捷发帖',
      description: '选择版块与表情，一键撰写新帖',
      icon: Icons.post_add_rounded,
      category: DashboardCardCategory.tool,
      supportedPages: {'home', 'guide'},
      minColSpan: 3,
      minRowSpan: 2,
      defaultColSpan: 6,
      defaultRowSpan: 2,
    ),

    // 2. 快捷回复卡片（仅帖子详情页专属，严禁在首页出现）
    'quick_reply': CardDefinition(
      cardType: 'quick_reply',
      name: '快捷回复',
      description: '单行输入与表情，快速互动',
      icon: Icons.reply_all_rounded,
      category: DashboardCardCategory.tool,
      supportedPages: {'thread'},
      minColSpan: 3,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 1,
    ),

    // 3. 勋章墙卡片（首页）
    'medal_wall': CardDefinition(
      cardType: 'medal_wall',
      name: '勋章展示墙',
      description: '展示拥有的荣誉勋章，带高光效果',
      icon: Icons.military_tech_rounded,
      category: DashboardCardCategory.user,
      supportedPages: {'home'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 4. 今日之星与全站统计（首页、导读页、帖子页）
    'tuhao_stats': CardDefinition(
      cardType: 'tuhao_stats',
      name: '今日之星与全站统计',
      description: '今日焦点之星、全站发帖与会员数据统计',
      icon: Icons.workspace_premium_rounded,
      category: DashboardCardCategory.stats,
      supportedPages: {'home', 'guide', 'thread'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 5. 每日签到与今日运势（首页、导读页、帖子页）
    'sign_fortune': CardDefinition(
      cardType: 'sign_fortune',
      name: '签到与今日运势',
      description: '今日运势签文诗号、打卡天数与一键签到',
      icon: Icons.event_available_rounded,
      category: DashboardCardCategory.tool,
      supportedPages: {'home', 'guide', 'thread'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 5.1 签到打卡日历（首页、导读页、帖子页，支持自适应全尺寸月历与连签）
    'sign_calendar': CardDefinition(
      cardType: 'sign_calendar',
      name: '签到日历与连签里程碑',
      description: '月度打卡日历网格、7天连签追踪器与补签卡管理',
      icon: Icons.calendar_month_rounded,
      category: DashboardCardCategory.user,
      supportedPages: {'home', 'guide', 'thread'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 3,
    ),

    // 6. 每日任务中心（首页、导读页）
    'task_box': CardDefinition(
      cardType: 'task_box',
      name: '每日任务中心',
      description: '活跃度进度、发帖/回帖打卡进度条',
      icon: Icons.checklist_rounded,
      category: DashboardCardCategory.tool,
      supportedPages: {'home', 'guide'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 7. 我的道具背包（首页、导读页）
    'magic_bag': CardDefinition(
      cardType: 'magic_bag',
      name: '道具背包',
      description: '展示拥有的提升卡/改名卡/补签卡等道具',
      icon: Icons.auto_fix_high_rounded,
      category: DashboardCardCategory.user,
      supportedPages: {'home', 'guide'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 8. 帕帕 AI 快捷助手（首页、导读页、帖子页）
    'papa_ai_quick': CardDefinition(
      cardType: 'papa_ai_quick',
      name: '帕帕 AI 助手',
      description: '快捷提问、大纲生成与灵感助手',
      icon: Icons.smart_toy_rounded,
      category: DashboardCardCategory.tool,
      supportedPages: {'home', 'guide', 'thread'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 9. 快捷版块导航（首页、导读页）
    'forum_nav': CardDefinition(
      cardType: 'forum_nav',
      name: '常用版块网格',
      description: '自选常用版块图标与直达入口',
      icon: Icons.grid_view_rounded,
      category: DashboardCardCategory.content,
      supportedPages: {'home', 'guide'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 10. 指定版块精选流（首页）
    'forum_feed': CardDefinition(
      cardType: 'forum_feed',
      name: '指定版块精选流',
      description: '可指定展示任意版块（如闲聊、资源）帖子',
      icon: Icons.dynamic_feed_rounded,
      category: DashboardCardCategory.content,
      supportedPages: {'home'},
      minColSpan: 3,
      minRowSpan: 2,
      defaultColSpan: 6,
      defaultRowSpan: 3,
    ),

    // 11. 全站热门帖子（首页、导读页）
    'hot_threads': CardDefinition(
      cardType: 'hot_threads',
      name: '全站热帖榜',
      description: '精选全站最高赞、最高回复热门帖子',
      icon: Icons.local_fire_department_rounded,
      category: DashboardCardCategory.content,
      supportedPages: {'home', 'guide'},
      minColSpan: 3,
      minRowSpan: 2,
      defaultColSpan: 6,
      defaultRowSpan: 3,
    ),

    // 12. 个人空间名片（首页、导读页）
    'user_profile': CardDefinition(
      cardType: 'user_profile',
      name: '个人空间名片',
      description: '头像、头衔、用户等级与空间直达',
      icon: Icons.badge_rounded,
      category: DashboardCardCategory.user,
      supportedPages: {'home', 'guide'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 13. 私信与系统通知（首页）
    'messages_brief': CardDefinition(
      cardType: 'messages_brief',
      name: '消息与通知',
      description: '未读私信与系统通知快捷简报',
      icon: Icons.mail_rounded,
      category: DashboardCardCategory.social,
      supportedPages: {'home'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 14. 小黑屋违规动态（首页）
    'darkroom_log': CardDefinition(
      cardType: 'darkroom_log',
      name: '小黑屋动态',
      description: '全站最新违规封禁记录与警示',
      icon: Icons.gavel_rounded,
      category: DashboardCardCategory.social,
      supportedPages: {'home'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 15. 签到风云排行榜（首页、导读页）
    'ranklist_card': CardDefinition(
      cardType: 'ranklist_card',
      name: '签到风云榜',
      description: '全站今日签到首位、连签百强与活跃排行榜',
      icon: Icons.emoji_events_rounded,
      category: DashboardCardCategory.stats,
      supportedPages: {'home', 'guide'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 16. 快捷页面传送门（首页）
    'page_portal': CardDefinition(
      cardType: 'page_portal',
      name: '快捷页面传送门',
      description: '自定义直达勋章、道具、积分、排行榜等页面',
      icon: Icons.open_in_new_rounded,
      category: DashboardCardCategory.tool,
      supportedPages: {'home'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 1,
    ),

    // 17. 服务器状态监控 (status.klpz.net)（首页、导读页、帖子页）
    'server_status': CardDefinition(
      cardType: 'server_status',
      name: '服务器状态',
      description: '实时监控论坛主站、存储与节点状态 (status.klpz.net)',
      icon: Icons.dns_rounded,
      category: DashboardCardCategory.stats,
      supportedPages: {'home', 'guide', 'thread'},
      minColSpan: 2,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // --- 帖子详情页专属卡片（严格隔离，绝不在首页出现）---
    // 18. 文章大纲目录树 (TOC)
    'toc_outline': CardDefinition(
      cardType: 'toc_outline',
      name: '帖子目录大纲 (TOC)',
      description: '自动提取正文与各楼层标题，点击平滑滚动直达',
      icon: Icons.format_list_bulleted_rounded,
      category: DashboardCardCategory.content,
      supportedPages: {'thread'},
      minColSpan: 3,
      minRowSpan: 2,
      defaultColSpan: 4,
      defaultRowSpan: 3,
    ),

    // 19. 楼层快速导航
    'floor_compass': CardDefinition(
      cardType: 'floor_compass',
      name: '楼层快速导航',
      description: '快速直达首层、最新回复、只看楼主或跳转指定楼层',
      icon: Icons.explore_rounded,
      category: DashboardCardCategory.tool,
      supportedPages: {'thread'},
      minColSpan: 3,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 20. 阅读排版调节
    'reader_tuning': CardDefinition(
      cardType: 'reader_tuning',
      name: '阅读排版调节',
      description: '实时调节正文字号、行间距与正文最大宽度',
      icon: Icons.tune_rounded,
      category: DashboardCardCategory.tool,
      supportedPages: {'thread'},
      minColSpan: 3,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 21. 打赏与评分明细
    'rating_hub': CardDefinition(
      cardType: 'rating_hub',
      name: '打赏与评分明细',
      description: '多币种汇总徽章、实时搜索打赏人与大额排序',
      icon: Icons.card_giftcard_rounded,
      category: DashboardCardCategory.stats,
      supportedPages: {'thread'},
      minColSpan: 3,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 22. 帖子图片与附件
    'media_gallery': CardDefinition(
      cardType: 'media_gallery',
      name: '帖子图片与附件',
      description: '聚合当前帖子所有图片与资源附件，支持沉浸画廊',
      icon: Icons.photo_library_rounded,
      category: DashboardCardCategory.content,
      supportedPages: {'thread'},
      minColSpan: 3,
      minRowSpan: 2,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 23. 楼层内容搜索
    'thread_search': CardDefinition(
      cardType: 'thread_search',
      name: '楼层内容搜索',
      description: '实时检索全帖楼层关键词、高亮命中并快速跳转',
      icon: Icons.search_rounded,
      category: DashboardCardCategory.tool,
      supportedPages: {'thread'},
      minColSpan: 3,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 24. 楼主名片与作者档案
    'author_card': CardDefinition(
      cardType: 'author_card',
      name: '楼主名片与作者档案',
      description: '展示楼主权威身份、勋章、空间主页与发帖历史',
      icon: Icons.badge_outlined,
      category: DashboardCardCategory.user,
      supportedPages: {'thread'},
      minColSpan: 3,
      minRowSpan: 1,
      defaultColSpan: 4,
      defaultRowSpan: 2,
    ),

    // 25. 版块主题流速览
    'forum_list': CardDefinition(
      cardType: 'forum_list',
      name: '版块主题速览',
      description: '同版块主题动态速览与跟手切帖面板',
      icon: Icons.list_alt_rounded,
      category: DashboardCardCategory.content,
      supportedPages: {'thread'},
      minColSpan: 3,
      minRowSpan: 2,
      defaultColSpan: 4,
      defaultRowSpan: 3,
    ),
  };

  static CardDefinition get(String cardType) {
    return definitions[cardType] ??
        CardDefinition(
          cardType: cardType,
          name: cardType,
          description: '自定义功能卡片',
          icon: Icons.widgets_rounded,
          category: DashboardCardCategory.tool,
        );
  }

  /// 经典预设：默认平衡推荐（左侧个人/任务/导航，右侧状态/签到/土豪，无积分流水冗余，为中间留出完整空间）
  static List<DashboardGridItem> getDefaultHomeLayout() {
    return [
      // --- 左侧功能区卡片 (col: 0) ---
      DashboardGridItem(
        id: 'profile_1',
        cardType: 'user_profile',
        col: 0,
        row: 0,
        colSpan: 4,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'task_1',
        cardType: 'task_box',
        col: 0,
        row: 2,
        colSpan: 4,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'nav_1',
        cardType: 'forum_nav',
        col: 0,
        row: 4,
        colSpan: 4,
        rowSpan: 2,
      ),
      // --- 右侧社区/监控卡片 (col: 8) ---
      DashboardGridItem(
        id: 'server_status_1',
        cardType: 'server_status',
        col: 8,
        row: 0,
        colSpan: 4,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'sign_1',
        cardType: 'sign_fortune',
        col: 8,
        row: 2,
        colSpan: 4,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'tuhao_1',
        cardType: 'tuhao_stats',
        col: 8,
        row: 4,
        colSpan: 4,
        rowSpan: 2,
      ),
    ];
  }

  /// 导读页专属工作台默认方案（只支持右侧 4 列：签到日历、帕帕 AI、服务器状态、全站热帖）
  static List<DashboardGridItem> getDefaultGuideLayout() {
    return [
      DashboardGridItem(
        id: 'gd_sign',
        cardType: 'sign_calendar',
        col: 8,
        row: 0,
        colSpan: 4,
        rowSpan: 3,
      ),
      DashboardGridItem(
        id: 'gd_ai',
        cardType: 'papa_ai_quick',
        col: 8,
        row: 3,
        colSpan: 4,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'gd_server',
        cardType: 'server_status',
        col: 8,
        row: 5,
        colSpan: 4,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'gd_hot',
        cardType: 'hot_threads',
        col: 8,
        row: 7,
        colSpan: 4,
        rowSpan: 3,
      ),
    ];
  }

  /// 经典预设：极客生产力工作台
  static List<DashboardGridItem> getGeekProductivityLayout() {
    return [
      DashboardGridItem(
        id: 'post_1',
        cardType: 'quick_post',
        col: 0,
        row: 0,
        colSpan: 8,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'ai_1',
        cardType: 'papa_ai_quick',
        col: 8,
        row: 0,
        colSpan: 4,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'feed_1',
        cardType: 'forum_feed',
        col: 0,
        row: 2,
        colSpan: 6,
        rowSpan: 3,
        customParams: {'targetFid': 2, 'forumName': '闲聊讨论'},
      ),
      DashboardGridItem(
        id: 'hot_1',
        cardType: 'hot_threads',
        col: 6,
        row: 2,
        colSpan: 6,
        rowSpan: 3,
      ),
      DashboardGridItem(
        id: 'task_1',
        cardType: 'task_box',
        col: 0,
        row: 5,
        colSpan: 6,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'magic_1',
        cardType: 'magic_bag',
        col: 6,
        row: 5,
        colSpan: 6,
        rowSpan: 2,
      ),
    ];
  }

  /// 经典预设：勋章与资产收藏家
  static List<DashboardGridItem> getCollectorLayout() {
    return [
      DashboardGridItem(
        id: 'medal_1',
        cardType: 'medal_wall',
        col: 0,
        row: 0,
        colSpan: 6,
        rowSpan: 3,
      ),
      DashboardGridItem(
        id: 'tuhao_1',
        cardType: 'tuhao_stats',
        col: 6,
        row: 0,
        colSpan: 3,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'rank_1',
        cardType: 'ranklist_card',
        col: 9,
        row: 0,
        colSpan: 3,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'magic_1',
        cardType: 'magic_bag',
        col: 0,
        row: 3,
        colSpan: 6,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'sign_1',
        cardType: 'sign_fortune',
        col: 6,
        row: 2,
        colSpan: 6,
        rowSpan: 2,
      ),
    ];
  }

  /// 经典预设：极简沉浸流
  static List<DashboardGridItem> getMinimalLayout() {
    return [
      DashboardGridItem(
        id: 'sign_1',
        cardType: 'sign_fortune',
        col: 0,
        row: 0,
        colSpan: 4,
        rowSpan: 2,
      ),
      DashboardGridItem(
        id: 'nav_1',
        cardType: 'forum_nav',
        col: 4,
        row: 0,
        colSpan: 8,
        rowSpan: 2,
      ),
    ];
  }
}

/// 经过响应式解算的已定位卡片项（消除碰撞、越界与错位）
class ResolvedGridItem {
  final DashboardGridItem item;
  final int col;
  final int row;
  final int colSpan;
  final int rowSpan;

  const ResolvedGridItem({
    required this.item,
    required this.col,
    required this.row,
    required this.colSpan,
    required this.rowSpan,
  });
}

/// 智能响应式重排算法解析器（深度消除由于屏幕宽度、列数变化导致的横向越界与错位 Bug）
class DashboardGridResolver {
  DashboardGridResolver._();

  /// 智能二维网格紧凑装箱算法（重力垂直向上压实，去除所有空行与空隙，保持列和相对顺序）
  static List<DashboardGridItem> compactPack({
    required List<DashboardGridItem> items,
    int totalCols = 12,
  }) {
    if (items.isEmpty) return const [];
    final sorted = List<DashboardGridItem>.from(items)
      ..sort((a, b) {
        if (a.row != b.row) return a.row.compareTo(b.row);
        return a.col.compareTo(b.col);
      });

    final occupied = <String>{};

    bool hasConflict(int r, int c, int rs, int cs) {
      if (c + cs > totalCols) return true;
      for (int dr = 0; dr < rs; dr++) {
        for (int dc = 0; dc < cs; dc++) {
          if (occupied.contains('${r + dr}_${c + dc}')) return true;
        }
      }
      return false;
    }

    void markOccupied(int r, int c, int rs, int cs) {
      for (int dr = 0; dr < rs; dr++) {
        for (int dc = 0; dc < cs; dc++) {
          occupied.add('${r + dr}_${c + dc}');
        }
      }
    }

    final result = <DashboardGridItem>[];

    for (final item in sorted) {
      final colSpan = item.colSpan.clamp(1, totalCols);
      final rowSpan = math.max(1, item.rowSpan);
      final targetCol = item.col.clamp(0, totalCols - colSpan);

      // 从第 0 行开始向上试探，尽可能贴紧上方卡片
      int bestRow = 0;
      while (hasConflict(bestRow, targetCol, rowSpan, colSpan) && bestRow < 100) {
        bestRow++;
      }

      markOccupied(bestRow, targetCol, rowSpan, colSpan);
      result.add(item.copyWith(
        row: bestRow,
        col: targetCol,
        colSpan: colSpan,
        rowSpan: rowSpan,
      ));
    }

    return result;
  }

  /// 将 12 列基准的 DIY 卡片列表，根据当前的实际可用列数（totalCols: 12 / 8 / 4）
  /// 进行严格的边界约束与自动排版流（Auto-Reflow），确保：
  /// 1. 在 12 列（大屏/标准工作台）下 1:1 精确呈现用户所设计的相对坐标与跨度；
  /// 2. 在 8 列或 4 列（平板/手机/分屏）下智能按比例降级并向下顺排，绝不溢出屏幕右边界；
  /// 3. 彻底消除卡片互相重叠和坐标重叠的严重错位现象。
  static List<ResolvedGridItem> resolve({
    required List<DashboardGridItem> items,
    required int totalCols,
  }) {
    if (items.isEmpty) return const [];

    // 先克隆并按原先规划的 row，随后 col 升序排序
    final sorted = List<DashboardGridItem>.from(items)
      ..sort((a, b) {
        final rowCmp = a.row.compareTo(b.row);
        if (rowCmp != 0) return rowCmp;
        return a.col.compareTo(b.col);
      });

    final resolved = <ResolvedGridItem>[];

    // 如果是大屏且列数完整（12列），我们优先尊重绝对排版，但进行越界与碰撞防护
    if (totalCols >= 12) {
      final occupied = <String>{};

      for (final item in sorted) {
        int colSpan = item.colSpan.clamp(1, totalCols);
        int col = item.col.clamp(0, totalCols - colSpan);
        int row = math.max(0, item.row);
        int rowSpan = math.max(1, item.rowSpan);

        bool hasConflict(int r, int c, int rs, int cs) {
          for (int dr = 0; dr < rs; dr++) {
            for (int dc = 0; dc < cs; dc++) {
              if (occupied.contains('${r + dr}_${c + dc}')) return true;
            }
          }
          return false;
        }

        // 如果该位置已被占用，向下寻找可用行
        int attempts = 0;
        while (hasConflict(row, col, rowSpan, colSpan) && attempts < 100) {
          row++;
          attempts++;
        }

        for (int dr = 0; dr < rowSpan; dr++) {
          for (int dc = 0; dc < colSpan; dc++) {
            occupied.add('${row + dr}_${col + dc}');
          }
        }

        resolved.add(ResolvedGridItem(
          item: item,
          col: col,
          row: row,
          colSpan: colSpan,
          rowSpan: rowSpan,
        ));
      }
      return resolved;
    }

    // 如果列数小于 12（如 8 列平板或 4 列手机端），进行自适应栅格流式重排
    final gridOccupied = <String>{};

    bool isCellFree(int r, int c, int rs, int cs) {
      if (c + cs > totalCols) return false;
      for (int dr = 0; dr < rs; dr++) {
        for (int dc = 0; dc < cs; dc++) {
          if (gridOccupied.contains('${r + dr}_${c + dc}')) return false;
        }
      }
      return true;
    }

    void markOccupied(int r, int c, int rs, int cs) {
      for (int dr = 0; dr < rs; dr++) {
        for (int dc = 0; dc < cs; dc++) {
          gridOccupied.add('${r + dr}_${c + dc}');
        }
      }
    }

    for (final item in sorted) {
      int targetColSpan;
      if (totalCols <= 4) {
        targetColSpan = (item.colSpan <= 2) ? math.min(2, totalCols) : totalCols;
      } else {
        // totalCols == 8
        targetColSpan = ((item.colSpan / 12.0) * totalCols).round().clamp(2, totalCols);
      }
      int targetRowSpan = item.rowSpan.clamp(1, 4);

      int tryR = 0;
      int tryC = 0;
      bool placed = false;
      int attempts = 0;

      while (!placed && attempts < 300) {
        attempts++;
        if (isCellFree(tryR, tryC, targetRowSpan, targetColSpan)) {
          markOccupied(tryR, tryC, targetRowSpan, targetColSpan);
          resolved.add(ResolvedGridItem(
            item: item,
            col: tryC,
            row: tryR,
            colSpan: targetColSpan,
            rowSpan: targetRowSpan,
          ));
          placed = true;
        } else {
          tryC++;
          if (tryC + targetColSpan > totalCols) {
            tryC = 0;
            tryR++;
          }
        }
      }
      if (!placed) {
        resolved.add(ResolvedGridItem(
          item: item,
          col: 0,
          row: tryR,
          colSpan: math.min(targetColSpan, totalCols),
          rowSpan: targetRowSpan,
        ));
      }
    }

    return resolved;
  }
}

