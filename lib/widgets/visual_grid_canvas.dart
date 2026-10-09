import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../api/comiis_parser.dart';
import '../models/forum.dart';
import '../models/horn_message.dart';
import 'home_content_slivers.dart';
import 'home_page_header.dart';
import 'guide_content.dart';
import 'discuz_post_renderer.dart';
import '../core/preload_service.dart';
import '../core/home_layout_metrics.dart';
import '../core/home_feed.dart';
import '../models/dashboard_card_model.dart';
import '../models/site_stats.dart';
import '../models/thread_summary.dart';
import 'dashboard_cards/card_settings_dialog.dart';
import 'dashboard_cards/dashboard_card_factory.dart';
import 'animated_side_panel.dart';
import 'responsive_layout.dart';
import 'diy_layout_studio.dart';

dynamic _copyCanvasParameter(dynamic value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key, _copyCanvasParameter(item)));
  }
  if (value is List) {
    return value.map(_copyCanvasParameter).toList();
  }
  return value;
}

DashboardGridItem _copyCanvasItem(DashboardGridItem item) => item.copyWith(
    customParams: item.customParams
        .map((key, value) => MapEntry(key, _copyCanvasParameter(value))));

class _CanvasPageDraft {
  final List<DashboardGridItem> items;
  final bool hideLeft;
  final bool hideRight;
  final bool showCenter;
  final bool showThreadForum;
  final bool dockCollapsed;

  _CanvasPageDraft({
    required List<DashboardGridItem> items,
    required this.hideLeft,
    required this.hideRight,
    required this.showCenter,
    required this.showThreadForum,
    required this.dockCollapsed,
  }) : items = items.map(_copyCanvasItem).toList();
}

/// 全站专业级可视化自由网格画布工作台（支持自由网格吸附、从工具栏拖拽添加、长按移动、拉伸长宽高、右上角保存、恢复默认与页面预览）
class VisualGridCanvas extends StatefulWidget {
  final List<DashboardGridItem> initialLayout;
  final String pageCategory; // 'home', 'guide', 'thread'
  final VoidCallback onExit;
  final ValueChanged<List<DashboardGridItem>> onSave;

  const VisualGridCanvas({
    super.key,
    required this.initialLayout,
    this.pageCategory = 'home',
    required this.onExit,
    required this.onSave,
  });

  @override
  State<VisualGridCanvas> createState() => _VisualGridCanvasState();
}

class _VisualGridCanvasState extends State<VisualGridCanvas> {
  late List<DashboardGridItem> _items;
  late String _currentPage;
  final Map<String, _CanvasPageDraft> _pageDrafts = {};
  DashboardCardCategory? _selectedCategory;

  // 交互拖拽与调整状态
  String? _selectedItemId;
  String? _draggingItemId;
  String? _hoveredItemId;
  ({int col, int row, int colSpan, int rowSpan})? _snapGhost;
  Offset? _dragStartGlobalPos;
  int _dragStartCardCol = 0;
  int _dragStartCardRow = 0;
  Offset? _resizeStartGlobalPos;
  int _resizeStartCol = 0;
  int _resizeStartRow = 0;
  int _resizeStartColSpan = 1;
  int _resizeStartRowSpan = 1;

  // 中央页面流仿真设置（可控制显示、调整列位与宽度，不阻挡卡片排版）
  bool _showCenterDemo = true;
  final int _centerDemoCol = 4;
  final int _centerDemoColSpan = 4;

  // 左右卡片隐藏与宽版仿真自适应预览模式（支持隐藏左侧/右侧/双侧并无缝展开中央页面流）
  bool _hideLeftCards = false;
  bool _hideRightCards = false;

  // 帖子工作台专属：是否展开左侧版块列表导航视图 (1:1 对齐 PC 版块边栏)
  late bool _showThreadForumPanel;

  /// 帖子与导读属于专属内容+工作台模式（左侧0..7为主体，右侧8..11为单列工作台）
  bool get _isWorkbenchMode =>
      _currentPage == 'thread' || _currentPage == 'guide';

  /// 顶部原生栏高度偏移（当显示页面流时，各列卡片均在 44px 真实标题条下起排，保证水平基准线 1:1 绝对对齐）
  double get _topHeaderOffset => _showCenterDemo ? 44.0 : 0.0;

  int get _effectiveCenterCol {
    if (_currentPage == 'thread') {
      return _showThreadForumPanel ? 4 : 0;
    }
    if (_currentPage == 'guide') {
      return 0;
    }
    if (_hideLeftCards) return 0;
    return _centerDemoCol;
  }

  int get _effectiveCenterColSpan {
    const totalCols = 12;
    if (_currentPage == 'thread') {
      return _showThreadForumPanel ? 4 : 8;
    }
    if (_currentPage == 'guide') {
      return 8;
    }
    if (_hideLeftCards && _hideRightCards) {
      return totalCols;
    } else if (_hideLeftCards) {
      return math.min(totalCols, _centerDemoCol + _centerDemoColSpan);
    } else if (_hideRightCards) {
      final start = _effectiveCenterCol;
      return math.max(1, totalCols - start);
    }
    return _centerDemoColSpan;
  }

  // 底部卡片库折叠状态（收起后仅占 32px，彻底避免遮挡底部卡片）
  bool _isDockCollapsed = false;
  bool _saving = false;
  HomeFeed _homePreviewFeed = HomeFeed.recommended;

  final ScrollController _canvasScrollCtrl = ScrollController();
  final ScrollController _dockScrollCtrl = ScrollController();
  final TextEditingController _previewSearchCtrl = TextEditingController();
  final GlobalKey _canvasContentKey = GlobalKey();

  static const double _cellHeight = 88.0;
  static const double _spacing = 8.0;
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(14, 14, 14, 160);

  @override
  void initState() {
    super.initState();
    final homeSelection = PreloadService.instance
        .get<({String session, HomeFeed feed})>('home_feed_selection',
            ignoreExpired: true);
    if (homeSelection?.session == DioClient.sessionKey) {
      _homePreviewFeed = homeSelection!.feed;
    }
    _currentPage = widget.pageCategory;
    _showThreadForumPanel = AppConfig.threadLeftEnabled;
    _hideLeftCards =
        _currentPage == 'home' ? !AppConfig.homeShowLeftCards : true;
    _hideRightCards = _currentPage == 'home'
        ? !AppConfig.homeShowRightCards
        : _currentPage == 'thread'
            ? !AppConfig.threadRightEnabled
            : false;
    if (_currentPage == 'thread') {
      final validModuleIds = AppConfig.threadRightModules;
      final existingMap = <String, DashboardGridItem>{};
      for (final it in widget.initialLayout) {
        if (it.cardType != 'user_profile' &&
            validModuleIds.contains(it.cardType)) {
          existingMap[it.cardType] = it;
        }
      }
      int currentRow = 0;
      _items = validModuleIds.map((id) {
        final existing = existingMap[id];
        final def = CardRegistry.definitions[id];
        final span = existing?.rowSpan ?? def?.defaultRowSpan ?? 2;
        final item = DashboardGridItem(
          id: existing?.id ?? 'th_$id',
          cardType: id,
          col: 8,
          row: currentRow,
          colSpan: 4,
          rowSpan: span,
          customParams: existing?.customParams == null
              ? null
              : _copyCanvasItem(existing!).customParams,
        );
        currentRow += span;
        return item;
      }).toList();
    } else if (_currentPage == 'guide') {
      _items = widget.initialLayout.map(_copyCanvasItem).toList();
      if (_items.isEmpty) {
        _items = CardRegistry.getDefaultGuideLayout();
      }
      for (final it in _items) {
        it.col = 8;
        it.colSpan = 4;
      }
    } else {
      _items = widget.initialLayout.map(_copyCanvasItem).toList();
      if (_items.isEmpty) {
        _items = CardRegistry.getDefaultHomeLayout();
      }
    }
    // 首次进入自动执行一次自适应校准与紧凑整理，消除旧数据可能遗留的错位或空洞
    _autoAdjustAndCompact();
  }

  @override
  void dispose() {
    _canvasScrollCtrl.dispose();
    _dockScrollCtrl.dispose();
    _previewSearchCtrl.dispose();
    super.dispose();
  }

  void _switchPage(String page) {
    if (_currentPage == page || _saving) return;
    setState(() {
      _pageDrafts[_currentPage] = _CanvasPageDraft(
          items: _items,
          hideLeft: _hideLeftCards,
          hideRight: _hideRightCards,
          showCenter: _showCenterDemo,
          showThreadForum: _showThreadForumPanel,
          dockCollapsed: _isDockCollapsed);
      _currentPage = page;
      _selectedCategory = null;
      _selectedItemId = null;
      _snapGhost = null;
      _draggingItemId = null;
      _hoveredItemId = null;
      _dragStartGlobalPos = null;
      _resizeStartGlobalPos = null;
      final draft = _pageDrafts[page];
      if (draft != null) {
        _items = draft.items.map(_copyCanvasItem).toList();
        _hideLeftCards = draft.hideLeft;
        _hideRightCards = draft.hideRight;
        _showCenterDemo = draft.showCenter;
        _showThreadForumPanel = draft.showThreadForum;
        _isDockCollapsed = draft.dockCollapsed;
        return;
      }
      _showCenterDemo = true;
      _isDockCollapsed = false;
      if (page == 'home') {
        _hideLeftCards = !AppConfig.homeShowLeftCards;
        _hideRightCards = !AppConfig.homeShowRightCards;
        _items = AppConfig.homeDashboardLayout.map(_copyCanvasItem).toList();
        if (_items.isEmpty) {
          _items = CardRegistry.getDefaultHomeLayout();
        }
      } else if (page == 'thread') {
        _showThreadForumPanel = AppConfig.threadLeftEnabled;
        _hideLeftCards = true;
        _hideRightCards = !AppConfig.threadRightEnabled;
        final validModuleIds = AppConfig.threadRightModules;
        final existingMap = <String, DashboardGridItem>{};
        for (final it in AppConfig.threadDashboardLayout) {
          if (it.cardType != 'user_profile' &&
              validModuleIds.contains(it.cardType)) {
            existingMap[it.cardType] = it;
          }
        }
        int currentRow = 0;
        _items = validModuleIds.map((id) {
          final existing = existingMap[id];
          final def = CardRegistry.definitions[id];
          final span = existing?.rowSpan ?? def?.defaultRowSpan ?? 2;
          final item = DashboardGridItem(
            id: existing?.id ?? 'th_$id',
            cardType: id,
            col: 8,
            row: currentRow,
            colSpan: 4,
            rowSpan: span,
            customParams: existing?.customParams == null
                ? null
                : _copyCanvasItem(existing!).customParams,
          );
          currentRow += span;
          return item;
        }).toList();
      } else if (page == 'guide') {
        _hideLeftCards = true;
        _hideRightCards = false;
        _items = AppConfig.guideDashboardLayout.map(_copyCanvasItem).toList();
        if (_items.isEmpty) {
          _items = CardRegistry.getDefaultGuideLayout();
        }
        for (final it in _items) {
          it.col = 8;
          it.colSpan = 4;
        }
      }
      _autoAdjustAndCompact();
    });
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('canvasCurrentPage', _currentPage));
    properties.add(IterableProperty<String>(
        'canvasItemIds', _items.map((item) => item.id)));
    properties
        .add(IterableProperty<String>('canvasDraftPages', _pageDrafts.keys));
    for (final draft in _pageDrafts.entries) {
      properties.add(IterableProperty<String>('canvasDraftItemIds-${draft.key}',
          draft.value.items.map((item) => item.id)));
    }
    properties.add(FlagProperty('canvasHideLeft',
        value: _hideLeftCards, ifTrue: 'left hidden', ifFalse: 'left visible'));
    properties.add(FlagProperty('canvasHideRight',
        value: _hideRightCards,
        ifTrue: 'right hidden',
        ifFalse: 'right visible'));
    properties.add(FlagProperty('canvasShowCenter',
        value: _showCenterDemo,
        ifTrue: 'center visible',
        ifFalse: 'center hidden'));
    properties.add(FlagProperty('canvasThreadForumPanel',
        value: _showThreadForumPanel,
        ifTrue: 'forum panel visible',
        ifFalse: 'forum panel hidden'));
  }

  // 1. 恢复系统默认
  void _resetToDefault() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restore_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('恢复默认布局'),
          ],
        ),
        content: const Text('确定恢复当前页面的默认布局？更改会在保存当前页后生效。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _pageDrafts.remove(_currentPage);
                if (_currentPage == 'home') {
                  _items = CardRegistry.getDefaultHomeLayout();
                } else if (_currentPage == 'thread') {
                  int r = 0;
                  _items = AppConfig.defaultThreadRightModules.map((id) {
                    final def = CardRegistry.get(id);
                    final span = def.defaultRowSpan;
                    final item = DashboardGridItem(
                      id: 'th_$id',
                      cardType: id,
                      col: 8,
                      row: r,
                      colSpan: 4,
                      rowSpan: span,
                    );
                    r += span;
                    return item;
                  }).toList();
                } else if (_currentPage == 'guide') {
                  _items = CardRegistry.getDefaultGuideLayout();
                }
                _autoAdjustAndCompact();
              });
              HapticFeedback.mediumImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('当前页已恢复默认布局，请保存后应用')),
              );
            },
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
  }

  // 2. 经典预设模版快速切换
  void _showPresetPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentPage == 'thread'
                    ? '切换帖子排版预设'
                    : (_currentPage == 'guide' ? '切换导读排版预设' : '切换首页排版预设'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (_currentPage == 'thread') ...[
                ListTile(
                  leading: const Icon(Icons.dashboard_customize_rounded,
                      color: Colors.blue),
                  title: const Text('全能助手预设'),
                  subtitle: const Text('包含文章大纲、楼层罗盘、阅读调谐器与评分大厅'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      int r = 0;
                      _items = [
                        'toc_outline',
                        'floor_compass',
                        'reader_tuning',
                        'rating_hub'
                      ].map((id) {
                        final span = CardRegistry.get(id).defaultRowSpan;
                        final it = DashboardGridItem(
                            id: 'th_$id',
                            cardType: id,
                            col: 8,
                            row: r,
                            colSpan: 4,
                            rowSpan: span);
                        r += span;
                        return it;
                      }).toList();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.menu_book_rounded, color: Colors.teal),
                  title: const Text('沉浸纯享阅读预设'),
                  subtitle: const Text('仅保留大纲目录与阅读调谐器，极致专注'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      int r = 0;
                      _items = ['toc_outline', 'reader_tuning'].map((id) {
                        final span = CardRegistry.get(id).defaultRowSpan;
                        final it = DashboardGridItem(
                            id: 'th_$id',
                            cardType: id,
                            col: 8,
                            row: r,
                            colSpan: 4,
                            rowSpan: span);
                        r += span;
                        return it;
                      }).toList();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.card_giftcard_rounded,
                      color: Colors.amber),
                  title: const Text('互动与多功能预设'),
                  subtitle: const Text('评分大厅、帕帕 AI 助手、帖内检索与打卡日历'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      int r = 0;
                      _items = [
                        'rating_hub',
                        'papa_ai_quick',
                        'thread_search',
                        'sign_calendar'
                      ].map((id) {
                        final span = CardRegistry.get(id).defaultRowSpan;
                        final it = DashboardGridItem(
                            id: 'th_$id',
                            cardType: id,
                            col: 8,
                            row: r,
                            colSpan: 4,
                            rowSpan: span);
                        r += span;
                        return it;
                      }).toList();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
              ] else if (_currentPage == 'guide') ...[
                ListTile(
                  leading:
                      const Icon(Icons.explore_outlined, color: Colors.blue),
                  title: const Text('导读全能推荐方案'),
                  subtitle: const Text('每日签到日历、帕帕 AI 助手、服务器监控与全站热帖'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _items = CardRegistry.getDefaultGuideLayout();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.flash_on_rounded, color: Colors.orange),
                  title: const Text('高频互动方案'),
                  subtitle: const Text('快捷发帖、活跃之星、常用版块与签到日历'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      int r = 0;
                      _items = [
                        'quick_post',
                        'ranklist_card',
                        'forum_nav',
                        'sign_calendar'
                      ].map((id) {
                        final span = CardRegistry.get(id).defaultRowSpan;
                        final it = DashboardGridItem(
                            id: 'gd_$id',
                            cardType: id,
                            col: 8,
                            row: r,
                            colSpan: 4,
                            rowSpan: span);
                        r += span;
                        return it;
                      }).toList();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.dns_rounded, color: Colors.teal),
                  title: const Text('极简状态监控方案'),
                  subtitle: const Text('签到日历与服务器状态看板，清爽精炼'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      int r = 0;
                      _items = ['sign_calendar', 'server_status'].map((id) {
                        final span = CardRegistry.get(id).defaultRowSpan;
                        final it = DashboardGridItem(
                            id: 'gd_$id',
                            cardType: id,
                            col: 8,
                            row: r,
                            colSpan: 4,
                            rowSpan: span);
                        r += span;
                        return it;
                      }).toList();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.dashboard_customize_rounded,
                      color: Colors.blue),
                  title: const Text('默认平衡推荐'),
                  subtitle: const Text('包含个人名片、每日任务、版块导航、服务器状态、签到与土豪榜'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _items = CardRegistry.getDefaultHomeLayout();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.terminal_rounded, color: Colors.teal),
                  title: const Text('极客生产力工作台'),
                  subtitle: const Text('聚焦快捷发帖、帕帕 AI 助手、版块精选流与道具管理'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _items = CardRegistry.getGeekProductivityLayout();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.military_tech_rounded,
                      color: Colors.amber),
                  title: const Text('勋章与资产收藏家'),
                  subtitle: const Text('大幅展示勋章展厅、土豪风云榜与资产数据'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _items = CardRegistry.getCollectorLayout();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.fullscreen_rounded,
                      color: Colors.purple),
                  title: const Text('极简沉浸流'),
                  subtitle: const Text('仅保留快捷版块与每日打卡，极致紧凑'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _items = CardRegistry.getMinimalLayout();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 3. 一键紧凑整理（智能去空隙吸附，基于 2D 重力压实算法）
  void _compactLayout() {
    HapticFeedback.lightImpact();
    setState(() {
      _autoAdjustAndCompact();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已完成智能紧凑吸附整理')),
    );
  }

  /// 智能全自动分区分栏避让与 2D 重力压实算法 (彻底杜绝重叠、越界穿透与断层空洞)
  void _autoAdjustAndCompact({DashboardGridItem? activeItem}) {
    if (_items.isEmpty) return;

    const totalCols = 12;

    if (_isWorkbenchMode) {
      // 工作台模式专属（帖子与版块）：卡片 100% 专属于右侧单列助手工作台 (列 8..11, 宽 4 列)，垂直向上紧凑压实
      for (final item in _items) {
        item.colSpan = 4;
        item.col = 8;
      }
      _compactGroup(
        _items,
        totalCols: totalCols,
        minCol: 8,
        maxCol: 12,
        activeItem: activeItem,
      );
      return;
    }

    if (_currentPage == 'home') {
      // 首页模式：保障左侧区 (0..3 列) 与右侧区 (8..11 列) 双侧卡片同时支持与紧凑压实，绝不侵入中央内容流 (4..7 列)
      final leftGroup = <DashboardGridItem>[];
      final rightGroup = <DashboardGridItem>[];

      for (final item in _items) {
        final midCol = item.col + item.colSpan / 2.0;
        if (midCol < 6) {
          item.colSpan = item.colSpan.clamp(1, 4).toInt();
          item.col = item.col.clamp(0, 4 - item.colSpan).toInt();
          leftGroup.add(item);
        } else {
          item.colSpan = item.colSpan.clamp(1, 4).toInt();
          item.col = item.col.clamp(8, 12 - item.colSpan).toInt();
          rightGroup.add(item);
        }
      }

      if (leftGroup.isNotEmpty) {
        _compactGroup(
          leftGroup,
          totalCols: totalCols,
          minCol: 0,
          maxCol: 4,
          activeItem: (activeItem != null &&
                  leftGroup.any((x) => x.id == activeItem.id))
              ? activeItem
              : null,
        );
      }

      if (rightGroup.isNotEmpty) {
        _compactGroup(
          rightGroup,
          totalCols: totalCols,
          minCol: 8,
          maxCol: 12,
          activeItem: (activeItem != null &&
                  rightGroup.any((x) => x.id == activeItem.id))
              ? activeItem
              : null,
        );
      }
      return;
    }

    if (!_showCenterDemo) {
      _compactGroup(_items,
          totalCols: totalCols,
          minCol: 0,
          maxCol: totalCols,
          activeItem: activeItem);
      return;
    }

    final centerStart = _effectiveCenterCol;
    final centerEnd = _effectiveCenterCol + _effectiveCenterColSpan;
    final divider = (centerStart + centerEnd) / 2.0;

    final leftGroup = <DashboardGridItem>[];
    final rightGroup = <DashboardGridItem>[];

    for (final item in _items) {
      final midCol = item.col + item.colSpan / 2.0;
      if (centerStart > 0 && midCol < divider) {
        // 归属左侧区
        final maxColSpan = math.max(1, centerStart);
        item.colSpan = item.colSpan.clamp(1, maxColSpan).toInt();
        item.col =
            item.col.clamp(0, math.max(0, centerStart - item.colSpan)).toInt();
        leftGroup.add(item);
      } else {
        // 归属右侧区
        final rightMinCol = math.min(totalCols - 1, centerEnd);
        final maxColSpan = math.max(1, totalCols - rightMinCol);
        item.colSpan = item.colSpan.clamp(1, maxColSpan).toInt();
        item.col = item.col
            .clamp(rightMinCol, math.max(rightMinCol, totalCols - item.colSpan))
            .toInt();
        rightGroup.add(item);
      }
    }

    // 分别对左侧与右侧卡片群执行 2D 向上重力紧凑压实
    if (centerStart > 0 && leftGroup.isNotEmpty) {
      _compactGroup(
        leftGroup,
        totalCols: totalCols,
        minCol: 0,
        maxCol: centerStart,
        activeItem:
            (activeItem != null && leftGroup.any((x) => x.id == activeItem.id))
                ? activeItem
                : null,
      );
    }

    if (centerEnd < totalCols && rightGroup.isNotEmpty) {
      _compactGroup(
        rightGroup,
        totalCols: totalCols,
        minCol: centerEnd,
        maxCol: totalCols,
        activeItem:
            (activeItem != null && rightGroup.any((x) => x.id == activeItem.id))
                ? activeItem
                : null,
      );
    }
  }

  void _compactGroup(
    List<DashboardGridItem> group, {
    required int totalCols,
    required int minCol,
    required int maxCol,
    DashboardGridItem? activeItem,
  }) {
    if (group.isEmpty) return;
    if (maxCol <= minCol) return; // 彻底防止 minCol >= maxCol 导致无解死循环

    final occupied = <String>{};

    bool hasConflict(int r, int c, int rs, int cs) {
      if (c < minCol || c + cs > maxCol) return true;
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

    // 先根据 activeItem 目标位置和原位置构建平滑重力排序队列
    final ordered = List<DashboardGridItem>.from(group);
    ordered.sort((a, b) {
      if (identical(a, b) || a.id == b.id) return 0;
      final rCmp = a.row.compareTo(b.row);
      if (rCmp != 0) return rCmp;
      final cCmp = a.col.compareTo(b.col);
      if (cCmp != 0) return cCmp;
      return a.id.compareTo(b.id);
    });

    // 向上重力紧凑压实：优先原列向上滑动，若遇窄卡片同排空槽则自动吸附填补，消除任何悬空断层
    for (final item in ordered) {
      final span = item.colSpan.clamp(1, math.max(1, maxCol - minCol)).toInt();
      item.colSpan = span;
      final preferredCol =
          item.col.clamp(minCol, math.max(minCol, maxCol - span)).toInt();

      int testRow = 0;
      int chosenCol = preferredCol;
      bool found = false;

      while (!found && testRow < 100) {
        if (!hasConflict(testRow, preferredCol, item.rowSpan, span)) {
          chosenCol = preferredCol;
          found = true;
          break;
        }
        // 如果首选列冲突，且卡片宽度小于该分区宽度，检查该行其他对齐列是否有空位（如两张 2 列卡片同排并列互换）
        if (span < (maxCol - minCol)) {
          for (int altCol = minCol; altCol <= maxCol - span; altCol += span) {
            if (altCol != preferredCol &&
                !hasConflict(testRow, altCol, item.rowSpan, span)) {
              chosenCol = altCol;
              found = true;
              break;
            }
          }
        }
        if (!found) {
          testRow++;
        }
      }

      if (!found) {
        chosenCol = preferredCol;
      }

      item.col = chosenCol;
      item.row = testRow;
      markOccupied(testRow, chosenCol, item.rowSpan, span);
    }
  }

  int _getMaxColSpanFor(DashboardGridItem item) {
    if (_isWorkbenchMode) return 4;
    final def = CardRegistry.get(item.cardType);
    if (!_showCenterDemo) {
      return math.min(def.maxColSpan, 12 - item.col);
    }
    final centerStart = _effectiveCenterCol;
    if (item.col < centerStart) {
      return math.min(def.maxColSpan, centerStart - item.col);
    } else {
      return math.min(def.maxColSpan, 12 - item.col);
    }
  }

  int _getMinColFor(DashboardGridItem item) {
    if (_isWorkbenchMode) return 8;
    if (!_showCenterDemo) return 0;
    final centerEnd = _effectiveCenterCol + _effectiveCenterColSpan;
    if (item.col >= centerEnd) return centerEnd;
    return 0;
  }

  /// 快速卡片尺寸调整对话框（包含常用规格预设与精准步进微调）
  void _showQuickSizeDialog(
    BuildContext context,
    DashboardGridItem item,
    CardDefinition def,
    int totalCols,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final theme = Theme.of(ctx);
            final colorScheme = theme.colorScheme;

            final centerStart = _effectiveCenterCol;
            final centerEnd = _effectiveCenterCol + _effectiveCenterColSpan;
            final isRightWing = _showCenterDemo && item.col >= centerEnd;
            final minCol = !_showCenterDemo ? 0 : (isRightWing ? centerEnd : 0);
            final maxWingWidth = !_showCenterDemo
                ? totalCols
                : (isRightWing ? (totalCols - centerEnd) : centerStart);
            final maxCol = math.min(def.maxColSpan, maxWingWidth);

            // 常用推荐规格预设 (在当前卡片与当前区域允许范围内)
            final allPresets = _isWorkbenchMode
                ? [
                    (colSpan: 4, rowSpan: 1, label: '4×1 紧凑条'),
                    (colSpan: 4, rowSpan: 2, label: '4×2 双栏常规'),
                    (colSpan: 4, rowSpan: 3, label: '4×3 扩展大卡'),
                    (colSpan: 4, rowSpan: 4, label: '4×4 全宽高卡'),
                  ]
                : [
                    (colSpan: 2, rowSpan: 1, label: '2×1 紧凑条'),
                    (colSpan: 2, rowSpan: 2, label: '2×2 小方块'),
                    (colSpan: 3, rowSpan: 2, label: '3×2 半宽标准'),
                    (colSpan: 4, rowSpan: 2, label: '4×2 双栏常规'),
                    (colSpan: 4, rowSpan: 3, label: '4×3 双栏大卡'),
                    (colSpan: 6, rowSpan: 2, label: '6×2 全宽横幅'),
                    (colSpan: 6, rowSpan: 3, label: '6×3 全宽中卡'),
                    (colSpan: 6, rowSpan: 4, label: '6×4 全宽高卡'),
                  ];

            final validPresets = allPresets
                .where((p) =>
                    p.colSpan >= def.minColSpan &&
                    p.colSpan <= maxCol &&
                    p.rowSpan >= def.minRowSpan &&
                    p.rowSpan <= def.maxRowSpan)
                .toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.tune_rounded,
                        color: colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('调整卡片尺寸',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(def.name,
                            style: TextStyle(
                                fontSize: 12, color: colorScheme.outline)),
                      ],
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 当前尺寸高亮卡片
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withAlpha(100),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: colorScheme.primary.withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('当前尺寸',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant)),
                          Text(
                            _isWorkbenchMode
                                ? '充满工作台栏宽 × ${item.rowSpan} 行高'
                                : '${item.colSpan} 列宽 × ${item.rowSpan} 行高',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 常用预设规格
                    if (validPresets.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 14, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          const Text('推荐常用规格',
                              style: TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: validPresets.map((p) {
                          final isCur = item.colSpan == p.colSpan &&
                              item.rowSpan == p.rowSpan;
                          return ChoiceChip(
                            label: Text(p.label,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isCur
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                            selected: isCur,
                            onSelected: (_) {
                              setState(() {
                                if (_isWorkbenchMode) {
                                  item.col = 8;
                                  item.colSpan = 4;
                                  item.rowSpan = p.rowSpan;
                                } else {
                                  item.col = item.col.clamp(
                                      minCol,
                                      math.max(minCol,
                                          minCol + maxWingWidth - p.colSpan));
                                  item.colSpan = p.colSpan;
                                  item.rowSpan = p.rowSpan;
                                }
                                _autoAdjustAndCompact(activeItem: item);
                              });
                              setDialogState(() {});
                              HapticFeedback.selectionClick();
                            },
                          );
                        }).toList(),
                      ),
                      const Divider(height: 24),
                    ],

                    // 精准步进微调
                    Row(
                      children: [
                        Icon(Icons.straighten_rounded,
                            size: 14, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        const Text('精准数值微调',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (!_isWorkbenchMode) ...[
                      // 宽度 (列数)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withAlpha(120),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.swap_horiz_rounded, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('宽度 (列数)',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600)),
                                  Text('范围: ${def.minColSpan} ~ $maxCol 列',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: colorScheme.outline)),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              icon: const Icon(Icons.remove, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: item.colSpan > def.minColSpan
                                  ? () {
                                      setState(() {
                                        item.colSpan--;
                                        _autoAdjustAndCompact(activeItem: item);
                                      });
                                      setDialogState(() {});
                                      HapticFeedback.lightImpact();
                                    }
                                  : null,
                            ),
                            SizedBox(
                              width: 32,
                              child: Text(
                                '${item.colSpan}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton.filledTonal(
                              icon: const Icon(Icons.add, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: item.colSpan < maxCol
                                  ? () {
                                      setState(() {
                                        final next = item.colSpan + 1;
                                        item.col = item.col.clamp(
                                            minCol,
                                            math.max(minCol,
                                                minCol + maxWingWidth - next));
                                        item.colSpan = next;
                                        _autoAdjustAndCompact(activeItem: item);
                                      });
                                      setDialogState(() {});
                                      HapticFeedback.lightImpact();
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // 高度 (行数)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHighest.withAlpha(120),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.swap_vert_rounded, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('高度 (行数)',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    '范围: ${def.minRowSpan} ~ ${def.maxRowSpan} 行',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: colorScheme.outline)),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.remove, size: 16),
                            visualDensity: VisualDensity.compact,
                            onPressed: item.rowSpan > def.minRowSpan
                                ? () {
                                    setState(() {
                                      item.rowSpan--;
                                      _autoAdjustAndCompact(activeItem: item);
                                    });
                                    setDialogState(() {});
                                    HapticFeedback.lightImpact();
                                  }
                                : null,
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${item.rowSpan}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.add, size: 16),
                            visualDensity: VisualDensity.compact,
                            onPressed: item.rowSpan < def.maxRowSpan
                                ? () {
                                    setState(() {
                                      item.rowSpan++;
                                      _autoAdjustAndCompact(activeItem: item);
                                    });
                                    setDialogState(() {});
                                    HapticFeedback.lightImpact();
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 4. 右上角高亮保存
  Future<void> _saveLayout() async {
    if (_saving) return;
    setState(() => _saving = true);
    final savedPage = _currentPage;
    final saved = _items.map(_copyCanvasItem).toList();
    try {
      await AppConfig.saveCanvasLayout(savedPage, saved,
          showLeft:
              savedPage == 'thread' ? _showThreadForumPanel : !_hideLeftCards,
          showRight: !_hideRightCards);
      if (!mounted) return;
      _pageDrafts.remove(savedPage);
      _items = saved.map(_copyCanvasItem).toList();
      widget.onSave(saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${savedPage == 'home' ? '首页' : savedPage == 'guide' ? '导读' : '帖子'}布局已保存')));
      widget.onExit();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // 1. 已放置卡片基于位移增量精准吸附 (零跳变，完美抗抖动)
  void _updateSnapGhostForPlacedCard(
    DashboardGridItem item,
    Offset currentGlobalPos,
    double cellWidth,
    int totalCols,
  ) {
    if (_dragStartGlobalPos == null) return;
    final delta = currentGlobalPos - _dragStartGlobalPos!;
    final deltaCols = (delta.dx / (cellWidth + _spacing)).round();
    final deltaRows = (delta.dy / (_cellHeight + _spacing)).round();

    final rawCol = _dragStartCardCol + deltaCols;
    final rawRow = math.max(0, _dragStartCardRow + deltaRows);

    _applySnapGhost(rawCol, rawRow, item.colSpan, item.rowSpan, totalCols);
  }

  // 2. 从外部卡片库拖入卡片时的绝对坐标吸附
  void _updateSnapGhostFromGlobalPos(
    Offset globalPos,
    int colSpan,
    int rowSpan,
    double cellWidth,
    int totalCols,
  ) {
    final renderBox =
        _canvasContentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localPos = renderBox.globalToLocal(globalPos);

    final dx = localPos.dx - _padding.left;
    final dy = localPos.dy - _padding.top - _topHeaderOffset;

    final rawCol = (dx / (cellWidth + _spacing)).round();
    final rawRow = math.max(0, (dy / (_cellHeight + _spacing)).round());

    _applySnapGhost(rawCol, rawRow, colSpan, rowSpan, totalCols);
  }

  // 核心吸附分区约束与列宽自适应
  void _applySnapGhost(
      int rawCol, int rawRow, int colSpan, int rowSpan, int totalCols) {
    int targetCol;
    int actualColSpan;

    if (_isWorkbenchMode) {
      // 帖子与版块工作台模式专属约束：卡片 100% 专属于右侧单列助手工作台 (列 8..11, 宽 4 列)
      // 无论鼠标位于何处（包括滑动到左侧 0..7 列），强制锁定吸附在第 8 列，彻底杜绝在左侧放置卡片！
      actualColSpan = 4;
      targetCol = 8;
    } else if (_currentPage == 'home') {
      // 首页专属吸附：支持左侧 (0..3 列) 与右侧 (8..11 列) 双侧自由吸附！绝不落入中央内容流 (4..7 列)
      actualColSpan = colSpan.clamp(1, 4);
      final midCol = rawCol + colSpan / 2.0;
      if (midCol < 6) {
        // 吸附到左侧区 [0, 4)
        targetCol = rawCol.clamp(0, 4 - actualColSpan);
      } else {
        // 吸附到右侧区 [8, 12)
        targetCol = rawCol.clamp(8, 12 - actualColSpan);
      }
    } else if (!_showCenterDemo) {
      actualColSpan = colSpan.clamp(1, totalCols);
      final maxCol = math.max(0, totalCols - actualColSpan);
      targetCol = rawCol.clamp(0, maxCol);
    } else {
      final centerStart = _effectiveCenterCol;
      final centerEnd = _effectiveCenterCol + _effectiveCenterColSpan;
      final divider = (centerStart + centerEnd) / 2.0;
      final midCol = rawCol + colSpan / 2.0;

      if (centerStart > 0 && midCol < divider) {
        // 归属左侧区 [0, centerStart)
        final leftWidth = math.max(1, centerStart);
        actualColSpan = colSpan.clamp(1, leftWidth);
        final maxCol = math.max(0, centerStart - actualColSpan);
        targetCol = rawCol.clamp(0, maxCol);
      } else {
        // 归属右侧区 [centerEnd, totalCols)
        final rightMin = math.min(totalCols - 1, centerEnd);
        final rightWidth = math.max(1, totalCols - rightMin);
        actualColSpan = colSpan.clamp(1, rightWidth);
        final maxCol = math.max(rightMin, totalCols - actualColSpan);
        targetCol = rawCol.clamp(rightMin, maxCol);
      }
    }

    final newGhost =
        (col: targetCol, row: rawRow, colSpan: actualColSpan, rowSpan: rowSpan);
    if (_snapGhost?.col != newGhost.col ||
        _snapGhost?.row != newGhost.row ||
        _snapGhost?.colSpan != newGhost.colSpan ||
        _snapGhost?.rowSpan != newGhost.rowSpan) {
      setState(() {
        _snapGhost = newGhost;
      });
    }
  }

  void _onCardDragStart(DashboardGridItem item, Offset globalPos) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedItemId = item.id;
      _draggingItemId = item.id;
      _dragStartGlobalPos = globalPos;
      _dragStartCardCol = item.col;
      _dragStartCardRow = item.row;
    });
  }

  void _onCardDragUpdate(DashboardGridItem item, Offset globalPos,
      double cellWidth, int totalCols) {
    _updateSnapGhostForPlacedCard(item, globalPos, cellWidth, totalCols);
  }

  void _onCardDragEnd(DashboardGridItem item) {
    _dragStartGlobalPos = null;
    if (_snapGhost != null) {
      setState(() {
        item.col = _isWorkbenchMode ? 8 : _snapGhost!.col;
        item.row = _snapGhost!.row;
        item.colSpan = _isWorkbenchMode ? 4 : _snapGhost!.colSpan;
        item.rowSpan = _snapGhost!.rowSpan;
        _autoAdjustAndCompact(activeItem: item);
        _snapGhost = null;
        _draggingItemId = null;
      });
      HapticFeedback.lightImpact();
    } else {
      setState(() {
        if (_isWorkbenchMode) {
          item.col = 8;
          item.colSpan = 4;
          _autoAdjustAndCompact(activeItem: item);
        }
        _snapGhost = null;
        _draggingItemId = null;
      });
    }
  }

  void _onCardDragCancel() {
    _dragStartGlobalPos = null;
    setState(() {
      _snapGhost = null;
      _draggingItemId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: _buildStudioAppBar(context),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Stack(
          children: [
            // 1. 核心可滚动交互网格画布
            LayoutBuilder(
              builder: (context, constraints) {
                final viewportWidth = constraints.maxWidth;
                const totalCols = 12; // 工作台基准网格始终以标准的 12 列蓝图作为坐标系统，杜绝列数切换导致的错位
                // 编辑网格保留固定坐标；页面预览使用首页实际响应式分栏。
                final canvasWidth = viewportWidth > 1280.0
                    ? 1280.0
                    : math.max(viewportWidth, 880.0);
                final availableWidth = canvasWidth - _padding.horizontal;
                final cellWidth =
                    (availableWidth - (totalCols - 1) * _spacing) / totalCols;

                int maxRow = 0;
                for (final item in _items) {
                  final bottom = item.row + item.rowSpan;
                  if (bottom > maxRow) maxRow = bottom;
                }
                // 底部预留专属安全缓冲区，彻底防止最下方的卡片或放置幽灵被浮动工具箱 Dock Tray 遮挡
                final bottomDockSafetyPadding = _isDockCollapsed ? 60.0 : 200.0;
                final canvasHeight = math.max(
                  constraints.maxHeight,
                  (maxRow + 3) * (_cellHeight + _spacing) +
                      _padding.top +
                      _topHeaderOffset +
                      bottomDockSafetyPadding,
                );

                return Center(
                  child: SizedBox(
                    width: canvasWidth,
                    height: constraints.maxHeight,
                    child: DragTarget<String>(
                      onWillAcceptWithDetails: (details) {
                        final def = CardRegistry.get(details.data);
                        return def.supportedPages.contains(_currentPage);
                      },
                      onMove: (details) {
                        final def = CardRegistry.get(details.data);
                        _updateSnapGhostFromGlobalPos(
                            details.offset,
                            def.defaultColSpan.clamp(1, totalCols),
                            def.defaultRowSpan,
                            cellWidth,
                            totalCols);
                      },
                      onLeave: (_) {
                        setState(() => _snapGhost = null);
                      },
                      onAcceptWithDetails: (details) {
                        if (_snapGhost != null) {
                          final def = CardRegistry.get(details.data);
                          if (!def.supportedPages.contains(_currentPage)) {
                            setState(() => _snapGhost = null);
                            return;
                          }
                          final newItem = DashboardGridItem(
                            id: '${details.data}_${DateTime.now().millisecondsSinceEpoch}',
                            cardType: details.data,
                            col: _isWorkbenchMode ? 8 : _snapGhost!.col,
                            row: _snapGhost!.row,
                            colSpan: _isWorkbenchMode ? 4 : _snapGhost!.colSpan,
                            rowSpan: _snapGhost!.rowSpan,
                          );
                          setState(() {
                            _items.add(newItem);
                            _autoAdjustAndCompact(activeItem: newItem);
                            _snapGhost = null;
                            _selectedItemId = newItem.id;
                          });
                          HapticFeedback.mediumImpact();
                        }
                      },
                      builder: (context, candidateData, rejectedData) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: (_draggingItemId != null ||
                                  _resizeStartGlobalPos != null)
                              ? const NeverScrollableScrollPhysics()
                              : (canvasWidth > viewportWidth
                                  ? const BouncingScrollPhysics()
                                  : const NeverScrollableScrollPhysics()),
                          child: SingleChildScrollView(
                            controller: _canvasScrollCtrl,
                            physics: (_draggingItemId != null ||
                                    _resizeStartGlobalPos != null)
                                ? const NeverScrollableScrollPhysics()
                                : const BouncingScrollPhysics(),
                            child: SizedBox(
                              key: _canvasContentKey,
                              width: canvasWidth,
                              height: canvasHeight,
                              child: Stack(
                                children: [
                                  // 网格蓝图底衬 (绘制坐标参考线与吸附点)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _GridBlueprintPainter(
                                        totalCols: totalCols,
                                        cellWidth: cellWidth,
                                        cellHeight: _cellHeight,
                                        spacing: _spacing,
                                        padding: _padding.copyWith(
                                            top: _padding.top +
                                                _topHeaderOffset),
                                        gridColor: colorScheme.outlineVariant
                                            .withAlpha(35),
                                        isThreadMode: _isWorkbenchMode,
                                        centerColStart: _showCenterDemo
                                            ? _effectiveCenterCol
                                            : -1,
                                        centerColEnd: _showCenterDemo
                                            ? (_effectiveCenterCol +
                                                _effectiveCenterColSpan -
                                                1)
                                            : -1,
                                        leftColStart:
                                            (_currentPage == 'thread' &&
                                                    _showCenterDemo &&
                                                    _showThreadForumPanel)
                                                ? 0
                                                : -1,
                                        leftColEnd: (_currentPage == 'thread' &&
                                                _showCenterDemo &&
                                                _showThreadForumPanel)
                                            ? 3
                                            : -1,
                                      ),
                                    ),
                                  ),

                                  // 帖子工作台专属：左侧高保真版块列表导航视图 (1:1 对齐 PC 桌面版块分栏，彻底消灭左侧留空白问题)
                                  if (_currentPage == 'thread' &&
                                      _showCenterDemo &&
                                      _showThreadForumPanel)
                                    _buildLeftForumPanelPreview(
                                      context: context,
                                      left: _padding.left,
                                      top: _padding.top,
                                      width: 4 * cellWidth + 3 * _spacing,
                                      height: math.max(
                                          680.0,
                                          canvasHeight -
                                              _padding.top -
                                              _padding.bottom),
                                    ),

                                  // 中心高保真页面流仿真视图 (所见即所得，支持位移、尺寸调节与按需关闭)
                                  if (_showCenterDemo)
                                    _buildCenterPageDemoPreview(
                                      context: context,
                                      left: _padding.left +
                                          _effectiveCenterCol *
                                              (cellWidth + _spacing),
                                      top: _padding.top,
                                      width:
                                          _effectiveCenterColSpan * cellWidth +
                                              (_effectiveCenterColSpan - 1) *
                                                  _spacing,
                                      height: math.max(
                                          680.0,
                                          canvasHeight -
                                              _padding.top -
                                              _padding.bottom),
                                      totalCols: totalCols,
                                    ),

                                  // 工作台模式专属（帖子/导读）：右侧工作台助手顶部导航条
                                  if (_showCenterDemo && _isWorkbenchMode)
                                    Positioned(
                                      left: _padding.left +
                                          8 * (cellWidth + _spacing),
                                      top: _padding.top,
                                      width: 4 * cellWidth + 3 * _spacing,
                                      height: 38,
                                      child:
                                          _buildRightWorkbenchHeader(context),
                                    ),

                                  // 首页专属：右侧社区动态顶部导航条 (1:1 对齐 media_1790393468984.png)
                                  if (_showCenterDemo &&
                                      _currentPage == 'home' &&
                                      !_hideRightCards)
                                    Positioned(
                                      left: _padding.left +
                                          8 * (cellWidth + _spacing),
                                      top: _padding.top,
                                      width: 4 * cellWidth + 3 * _spacing,
                                      height: 38,
                                      child: _buildHomeRightCommunityHeader(
                                          context),
                                    ),

                                  // 首页专属：左侧个人工具顶部导航条 (1:1 对齐 PC 桌面端左侧工具栏)
                                  if (_showCenterDemo &&
                                      _currentPage == 'home' &&
                                      !_hideLeftCards)
                                    Positioned(
                                      left: _padding.left,
                                      top: _padding.top,
                                      width: 4 * cellWidth + 3 * _spacing,
                                      height: 38,
                                      child: _buildHomeLeftToolsHeader(context),
                                    ),

                                  // 幽灵吸附预览投影框 (Ghost Snap Preview)
                                  if (_snapGhost != null)
                                    Positioned(
                                      left: _padding.left +
                                          _snapGhost!.col *
                                              (cellWidth + _spacing),
                                      top: _padding.top +
                                          _topHeaderOffset +
                                          _snapGhost!.row *
                                              (_cellHeight + _spacing),
                                      width: _snapGhost!.colSpan * cellWidth +
                                          (_snapGhost!.colSpan - 1) * _spacing,
                                      height: _snapGhost!.rowSpan *
                                              _cellHeight +
                                          (_snapGhost!.rowSpan - 1) * _spacing,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color:
                                              colorScheme.primary.withAlpha(45),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: colorScheme.primary,
                                              width: 2.2),
                                          boxShadow: [
                                            BoxShadow(
                                              color: colorScheme.primary
                                                  .withAlpha(70),
                                              blurRadius: 12,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: colorScheme.primary,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              boxShadow: const [
                                                BoxShadow(
                                                    color: Colors.black26,
                                                    blurRadius: 4)
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                    Icons
                                                        .check_circle_outline_rounded,
                                                    size: 14,
                                                    color: Colors.white),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '松手自动吸附于此 (${_snapGhost!.colSpan}×${_snapGhost!.rowSpan})',
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  // 已放置的卡片列表（仅在拖拽或选中时微调顶层层级，绝不因悬停触发生命周期与 Z 轴翻转，杜绝 MouseTracker 震荡风暴）
                                  ...(() {
                                    final sorted =
                                        List<DashboardGridItem>.from(_items);
                                    sorted.sort((a, b) {
                                      final aActive =
                                          (a.id == _draggingItemId ||
                                                  a.id == _selectedItemId)
                                              ? 1
                                              : 0;
                                      final bActive =
                                          (b.id == _draggingItemId ||
                                                  b.id == _selectedItemId)
                                              ? 1
                                              : 0;
                                      return aActive.compareTo(bActive);
                                    });
                                    return sorted.map((item) {
                                      final isLeftCard =
                                          (item.col + item.colSpan / 2) < 6;
                                      if (_hideLeftCards && isLeftCard) {
                                        return const SizedBox.shrink();
                                      }
                                      if (_hideRightCards && !isLeftCard) {
                                        return const SizedBox.shrink();
                                      }
                                      return _buildPlacedCard(
                                        context,
                                        item,
                                        cellWidth: cellWidth,
                                        totalCols: totalCols,
                                      );
                                    });
                                  })(),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),

            // 2. 底部悬浮卡片工具箱（Card Library Tray - 随时拖拽卡片上画布）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildCardDockTray(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部专业操作控制栏
  PreferredSizeWidget _buildStudioAppBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 1280;
    final controls = <(String, String, IconData)>[
      ('settings', '工作区与排版设置', Icons.tune_rounded),
      ('center', _showCenterDemo ? '隐藏页面流' : '显示页面流', Icons.preview_outlined),
      (
        'left',
        _hideLeftCards ? '显示左侧卡片' : '隐藏左侧卡片',
        Icons.view_sidebar_rounded
      ),
      (
        'right',
        _hideRightCards ? '显示右侧卡片' : '隐藏右侧卡片',
        Icons.view_sidebar_outlined
      ),
      ('reset', '恢复默认布局', Icons.restore_rounded),
      ('compact', '整理卡片', Icons.auto_fix_high_rounded),
      ('preset', '布局预设', Icons.style_outlined),
    ];
    void action(String value) {
      switch (value) {
        case 'settings':
          _showWorkbenchSettingsSheet(context);
        case 'center':
          setState(() {
            _showCenterDemo = !_showCenterDemo;
            _autoAdjustAndCompact();
          });
        case 'left':
          setState(() => _hideLeftCards = !_hideLeftCards);
        case 'right':
          setState(() => _hideRightCards = !_hideRightCards);
        case 'reset':
          _resetToDefault();
        case 'compact':
          _compactLayout();
        case 'preset':
          _showPresetPicker();
      }
    }

    Widget tabs() => Row(mainAxisSize: MainAxisSize.min, children: [
          _buildPageTab('home', '首页'),
          _buildPageTab('guide', '导读'),
          _buildPageTab('thread', '帖子'),
        ]);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: '放弃并退出',
        onPressed: _saving
            ? null
            : () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('放弃未保存的更改？'),
                    content: const Text('退出后，本次画布中所有未保存的页面草稿都会被放弃。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('继续编辑')),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onExit();
                        },
                        child: const Text('确认放弃'),
                      ),
                    ],
                  ),
                ),
      ),
      title: compact
          ? const Text('自由画布工坊', maxLines: 1, overflow: TextOverflow.ellipsis)
          : Row(children: [
              const Icon(Icons.draw_rounded, size: 20),
              const SizedBox(width: 8),
              const Flexible(
                  child: Text('自由画布工坊',
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 12),
              tabs(),
            ]),
      bottom: compact
          ? PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: Padding(
                  padding: const EdgeInsets.only(bottom: 8), child: tabs()))
          : null,
      actions: [
        if (MediaQuery.sizeOf(context).width >= 800)
          TextButton.icon(
              key: const ValueKey('canvas-layout-studio'),
              onPressed: _saving ? null : _openLayoutStudio,
              icon: const Icon(Icons.space_dashboard_outlined, size: 18),
              label: const Text('布局工坊'))
        else
          IconButton(
              key: const ValueKey('canvas-layout-studio'),
              tooltip: '布局工坊 · 模块与尺寸',
              onPressed: _saving ? null : _openLayoutStudio,
              icon: const Icon(Icons.space_dashboard_outlined)),
        IconButton(
          key: const ValueKey('canvas-open-page-preview'),
          icon: const Icon(Icons.desktop_windows_outlined),
          tooltip: '按窗口尺寸预览页面',
          onPressed: _saving ? null : _showPagePreview,
        ),
        if (!compact)
          for (final control in controls)
            IconButton(
                key: ValueKey('canvas-toggle-${control.$1}'),
                icon: Icon(control.$3),
                tooltip: control.$2,
                onPressed: _saving ? null : () => action(control.$1)),
        if (compact)
          PopupMenuButton<String>(
            enabled: !_saving,
            tooltip: '布局工具',
            onSelected: action,
            itemBuilder: (_) => [
              for (final control in controls)
                PopupMenuItem(
                    value: control.$1,
                    child: Row(children: [
                      Icon(control.$3, size: 18),
                      const SizedBox(width: 10),
                      Text(control.$2),
                    ])),
            ],
          ),
        if (compact)
          IconButton(
              key: const ValueKey('canvas-save-current-page'),
              icon: const Icon(Icons.save_rounded),
              tooltip: '保存当前页面的布局并退出',
              onPressed: _saving ? null : _saveLayout)
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FilledButton.icon(
              key: const ValueKey('canvas-save-current-page'),
              onPressed: _saving ? null : _saveLayout,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('保存当前页'),
            ),
          ),
      ],
      backgroundColor: scheme.surfaceContainerLowest,
    );
  }

  Future<void> _openLayoutStudio() async {
    final result = await DiyLayoutStudio.show(context,
        embeddedInCanvas: true, initialTab: _currentPage == 'thread' ? 2 : 0);
    if (!mounted || result == null) return;
    final changes = result.changes;
    if (changes.containsKey('threadRightModules')) {
      List<DashboardGridItem> merge(List<DashboardGridItem> draft) {
        final active = AppConfig.threadRightModules.toSet();
        final kept = draft
            .where((item) => active.contains(item.cardType))
            .map(_copyCanvasItem)
            .toList();
        for (final template in AppConfig.threadDashboardLayout) {
          if (!kept.any((item) => item.cardType == template.cardType)) {
            kept.add(_copyCanvasItem(template));
          }
        }
        return kept;
      }

      if (_currentPage == 'thread') _items = merge(_items);
    }
    final savedDraft = _pageDrafts['thread'];
    if (savedDraft != null &&
        (changes.containsKey('threadRightModules') ||
            changes.containsKey('threadRightEnabled') ||
            changes.containsKey('threadLeftEnabled'))) {
      final active = AppConfig.threadRightModules.toSet();
      final items = savedDraft.items
          .where((item) =>
              !changes.containsKey('threadRightModules') ||
              active.contains(item.cardType))
          .map(_copyCanvasItem)
          .toList();
      if (changes.containsKey('threadRightModules')) {
        for (final template in AppConfig.threadDashboardLayout) {
          if (!items.any((item) => item.cardType == template.cardType)) {
            items.add(_copyCanvasItem(template));
          }
        }
      }
      _pageDrafts['thread'] = _CanvasPageDraft(
          items: items,
          hideLeft: savedDraft.hideLeft,
          hideRight: changes.containsKey('threadRightEnabled')
              ? !AppConfig.threadRightEnabled
              : savedDraft.hideRight,
          showCenter: savedDraft.showCenter,
          showThreadForum: changes.containsKey('threadLeftEnabled')
              ? AppConfig.threadLeftEnabled
              : savedDraft.showThreadForum,
          dockCollapsed: savedDraft.dockCollapsed);
    }
    setState(() {
      if (_currentPage == 'thread') {
        if (changes.containsKey('threadRightEnabled')) {
          _hideRightCards = !AppConfig.threadRightEnabled;
        }
        if (changes.containsKey('threadLeftEnabled')) {
          _showThreadForumPanel = AppConfig.threadLeftEnabled;
        }
        _autoAdjustAndCompact();
      }
    });
  }

  void _showWorkbenchSettingsSheet(BuildContext context) {
    _openLayoutStudio();
  }

  Widget _buildPageTab(String id, String label) {
    final isSelected = _currentPage == id;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      key: ValueKey('canvas-page-tab-$id'),
      onTap: _saving ? null : () => _switchPage(id),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// 单个放置卡片（具备长按拖拽移位、外扩 100% 命中把手、快捷尺寸面板、删除与参数弹窗）
  Widget _buildPlacedCard(
    BuildContext context,
    DashboardGridItem item, {
    required double cellWidth,
    required int totalCols,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final def = CardRegistry.get(item.cardType);
    final isSelected = _selectedItemId == item.id;
    final isHovered = _hoveredItemId == item.id;
    final showHandles = isSelected ||
        isHovered ||
        (_resizeStartGlobalPos != null && _selectedItemId == item.id);

    // 外扩命中边缘：严格限制在 4px（<_spacing / 2 = 5px），保证相邻卡片包围盒 100% 互斥无交集，彻底根除交叠引发的 MouseTracker 翻转死循环
    const double handleHitMargin = 4.0;

    final cardLeft = _padding.left + item.col * (cellWidth + _spacing);
    final cardTop =
        _padding.top + _topHeaderOffset + item.row * (_cellHeight + _spacing);
    final cardWidth = item.colSpan * cellWidth + (item.colSpan - 1) * _spacing;
    final cardHeight =
        item.rowSpan * _cellHeight + (item.rowSpan - 1) * _spacing;

    final isDragging = _draggingItemId == item.id;

    return Positioned(
      key: ValueKey(item.id),
      left: cardLeft - handleHitMargin,
      top: cardTop - handleHitMargin,
      width: cardWidth + handleHitMargin * 2,
      height: cardHeight + handleHitMargin * 2,
      child: MouseRegion(
        onEnter: (_) {
          if (_hoveredItemId != item.id && _selectedItemId != item.id) {
            _hoveredItemId = item.id;
            setState(() {});
          }
        },
        onExit: (_) {
          if (_hoveredItemId == item.id) {
            _hoveredItemId = null;
            setState(() {});
          }
        },
        child: Opacity(
          opacity: isDragging ? 0.35 : 1.0,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. 卡片主体 (内嵌 handleHitMargin，仅在主体区域响应整卡拖拽)
              Positioned(
                left: handleHitMargin,
                top: handleHitMargin,
                width: cardWidth,
                height: cardHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selectedItemId = item.id),
                  // 1. 桌面端鼠标直接拖拽
                  onPanStart: (details) =>
                      _onCardDragStart(item, details.globalPosition),
                  onPanUpdate: (details) => _onCardDragUpdate(
                      item, details.globalPosition, cellWidth, totalCols),
                  onPanEnd: (_) => _onCardDragEnd(item),
                  onPanCancel: () => _onCardDragCancel(),
                  // 2. 移动端/触屏长按拖拽
                  onLongPressStart: (details) =>
                      _onCardDragStart(item, details.globalPosition),
                  onLongPressMoveUpdate: (details) => _onCardDragUpdate(
                      item, details.globalPosition, cellWidth, totalCols),
                  onLongPressEnd: (_) => _onCardDragEnd(item),
                  onLongPressCancel: () => _onCardDragCancel(),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 1.1 卡片核心展示区（必须包裹 IgnorePointer，严防内部 ListView/按钮吞噬手势导致移不动卡片）
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: true,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: isSelected
                                  ? Border.all(
                                      color: colorScheme.primary, width: 2)
                                  : (isHovered
                                      ? Border.all(
                                          color: colorScheme.primary
                                              .withAlpha(160),
                                          width: 1.5)
                                      : Border.all(
                                          color: Colors.transparent, width: 0)),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color:
                                            colorScheme.primary.withAlpha(50),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : (isHovered
                                      ? [
                                          BoxShadow(
                                            color: colorScheme.primary
                                                .withAlpha(25),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null),
                            ),
                            child: DashboardCardFactory.buildCard(
                              item: item,
                              isPreview: true, // 编辑时读取已加载的数据，禁止触发写操作
                              threads: _previewThreads,
                              threadsCacheKey: _previewThreadsCacheKey,
                              stats: PreloadService.instance.get<SiteStats>(
                                  'site_stats',
                                  ignoreExpired: true),
                              suppressDefaultStats: _currentPage == 'home' &&
                                  PreloadService.instance
                                          .get<SiteStats>('site_stats',
                                              ignoreExpired: true)
                                          ?.isEmpty ==
                                      false &&
                                  AppConfig.mobileHomeSections
                                      .contains('stats'),
                            ),
                          ),
                        ),
                      ),

                      // 1.2 齿轮配置按钮 (仅在选中或悬停时呈现，常态保持卡片自身标题干净原生)
                      if (isSelected || isHovered)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: InkWell(
                            onTap: () {
                              CardSettingsDialog.show(
                                context,
                                item: item,
                                onSave: (updated) {
                                  setState(() {
                                    final idx = _items
                                        .indexWhere((x) => x.id == item.id);
                                    if (idx != -1) _items[idx] = updated;
                                    _autoAdjustAndCompact(
                                        activeItem: _items[idx]);
                                  });
                                },
                              );
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: colorScheme.surface.withAlpha(220),
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black12, blurRadius: 4)
                                ],
                              ),
                              child:
                                  const Icon(Icons.settings_outlined, size: 14),
                            ),
                          ),
                        ),

                      // 1.3 删除按钮 (1:1 对齐 ThreadLayoutWorkbench 优雅原生微圆角，Hover/选中时突出)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _items.removeWhere((x) => x.id == item.id);
                              _autoAdjustAndCompact();
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: (isSelected || isHovered)
                                  ? colorScheme.surfaceContainerHighest
                                      .withAlpha(240)
                                  : colorScheme.surfaceContainerHighest
                                      .withAlpha(180),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: (isSelected || isHovered)
                                  ? colorScheme.error
                                  : colorScheme.outline,
                            ),
                          ),
                        ),
                      ),

                      // 1.4 顶部中心尺寸胶囊标签：仅在选中或悬停时浮出，常态绝对不遮挡卡片原生标题
                      if (isSelected || isHovered)
                        Positioned(
                          top: 5,
                          left: 36,
                          right: 36,
                          child: Center(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _showQuickSizeDialog(
                                    context, item, def, totalCols),
                                borderRadius: BorderRadius.circular(12),
                                child: Tooltip(
                                  message:
                                      '点击快捷修改尺寸 (${item.colSpan}×${item.rowSpan})',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? colorScheme.primaryContainer
                                          : colorScheme.surfaceContainerHighest
                                              .withAlpha(220),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? colorScheme.primary
                                            : colorScheme.outlineVariant
                                                .withAlpha(140),
                                        width: 1.0,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                            color: Colors.black12,
                                            blurRadius: 2)
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.tune_rounded,
                                          size: 11,
                                          color: isSelected
                                              ? colorScheme.primary
                                              : colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          _isWorkbenchMode
                                              ? '4×${item.rowSpan}'
                                              : '${item.colSpan}×${item.rowSpan}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 1),
                                        Icon(
                                          Icons.arrow_drop_down_rounded,
                                          size: 13,
                                          color: isSelected
                                              ? colorScheme.primary
                                              : colorScheme.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // 右下角显式对角线角标（帮助用户明确此处可快速拖拽改尺寸）
                      if (showHandles && !_isWorkbenchMode)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: IgnorePointer(
                            ignoring: true,
                            child: Icon(
                              Icons.south_east_rounded,
                              size: 10,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.primary.withAlpha(140),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ========================================================
              // 外层 8 方向全能拉伸把手（100% 位于外层边界内，彻底消除溢出裁切缺陷）
              // ========================================================
              if (showHandles) ...[
                // [1/8] 顶边缘拉伸把手
                Positioned(
                  top: 0,
                  left: 24,
                  right: 24,
                  height: 12,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        _selectedItemId = item.id;
                        _resizeStartGlobalPos = details.globalPosition;
                        _resizeStartCol = item.col;
                        _resizeStartRow = item.row;
                        _resizeStartColSpan = item.colSpan;
                        _resizeStartRowSpan = item.rowSpan;
                        setState(() {});
                      },
                      onPanUpdate: (details) {
                        if (_resizeStartGlobalPos == null) return;
                        final totalDelta =
                            details.globalPosition - _resizeStartGlobalPos!;
                        final bottomAnchorRow =
                            _resizeStartRow + _resizeStartRowSpan;
                        final deltaRows =
                            (totalDelta.dy / (_cellHeight + _spacing)).round();
                        final targetRow = (_resizeStartRow + deltaRows)
                            .clamp(0, bottomAnchorRow - def.minRowSpan);
                        final targetRowSpan = (bottomAnchorRow - targetRow)
                            .clamp(def.minRowSpan, def.maxRowSpan);
                        final newRow = bottomAnchorRow - targetRowSpan;
                        if (newRow != item.row ||
                            targetRowSpan != item.rowSpan) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            item.row = newRow;
                            item.rowSpan = targetRowSpan;
                          });
                        }
                      },
                      onPanEnd: (_) {
                        _resizeStartGlobalPos = null;
                        setState(() => _autoAdjustAndCompact(activeItem: item));
                      },
                      onPanCancel: () {
                        _resizeStartGlobalPos = null;
                        setState(() => _autoAdjustAndCompact(activeItem: item));
                      },
                      child: Center(
                        child: Container(
                          height: 3.5,
                          width: 28,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.primary.withAlpha(140),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // [2/8] 底边缘拉伸把手
                Positioned(
                  bottom: 0,
                  left: 24,
                  right: 24,
                  height: 12,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        _selectedItemId = item.id;
                        _resizeStartGlobalPos = details.globalPosition;
                        _resizeStartCol = item.col;
                        _resizeStartRow = item.row;
                        _resizeStartColSpan = item.colSpan;
                        _resizeStartRowSpan = item.rowSpan;
                        setState(() {});
                      },
                      onPanUpdate: (details) {
                        if (_resizeStartGlobalPos == null) return;
                        final totalDelta =
                            details.globalPosition - _resizeStartGlobalPos!;
                        final deltaRows =
                            (totalDelta.dy / (_cellHeight + _spacing)).round();
                        final newRowSpan = (_resizeStartRowSpan + deltaRows)
                            .clamp(def.minRowSpan, def.maxRowSpan);
                        if (newRowSpan != item.rowSpan) {
                          HapticFeedback.selectionClick();
                          setState(() => item.rowSpan = newRowSpan);
                        }
                      },
                      onPanEnd: (_) {
                        _resizeStartGlobalPos = null;
                        setState(() => _autoAdjustAndCompact(activeItem: item));
                      },
                      onPanCancel: () {
                        _resizeStartGlobalPos = null;
                        setState(() => _autoAdjustAndCompact(activeItem: item));
                      },
                      child: Center(
                        child: Container(
                          height: 3.5,
                          width: 28,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.primary.withAlpha(140),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (!_isWorkbenchMode) ...[
                  // [3/8] 左边缘拉伸把手
                  Positioned(
                    left: 0,
                    top: 24,
                    bottom: 24,
                    width: 12,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          _selectedItemId = item.id;
                          _resizeStartGlobalPos = details.globalPosition;
                          _resizeStartCol = item.col;
                          _resizeStartRow = item.row;
                          _resizeStartColSpan = item.colSpan;
                          _resizeStartRowSpan = item.rowSpan;
                          setState(() {});
                        },
                        onPanUpdate: (details) {
                          if (_resizeStartGlobalPos == null) return;
                          final totalDelta =
                              details.globalPosition - _resizeStartGlobalPos!;
                          final rightAnchorCol =
                              _resizeStartCol + _resizeStartColSpan;
                          final deltaCols =
                              (totalDelta.dx / (cellWidth + _spacing)).round();
                          final minCol = _getMinColFor(item);
                          final targetCol = (_resizeStartCol + deltaCols)
                              .clamp(minCol, rightAnchorCol - def.minColSpan);
                          final targetColSpan = (rightAnchorCol - targetCol)
                              .clamp(def.minColSpan, def.maxColSpan);
                          final newCol = rightAnchorCol - targetColSpan;
                          if (newCol != item.col ||
                              targetColSpan != item.colSpan) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              item.col = newCol;
                              item.colSpan = targetColSpan;
                            });
                          }
                        },
                        onPanEnd: (_) {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        onPanCancel: () {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        child: Center(
                          child: Container(
                            width: 3.5,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.primary.withAlpha(140),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // [4/8] 右边缘拉伸把手
                  Positioned(
                    right: 0,
                    top: 24,
                    bottom: 24,
                    width: 12,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          _selectedItemId = item.id;
                          _resizeStartGlobalPos = details.globalPosition;
                          _resizeStartCol = item.col;
                          _resizeStartRow = item.row;
                          _resizeStartColSpan = item.colSpan;
                          _resizeStartRowSpan = item.rowSpan;
                          setState(() {});
                        },
                        onPanUpdate: (details) {
                          if (_resizeStartGlobalPos == null) return;
                          final totalDelta =
                              details.globalPosition - _resizeStartGlobalPos!;
                          final deltaCols =
                              (totalDelta.dx / (cellWidth + _spacing)).round();
                          final maxAllowed = _getMaxColSpanFor(item);
                          final newColSpan = (_resizeStartColSpan + deltaCols)
                              .clamp(def.minColSpan,
                                  math.max<int>(def.minColSpan, maxAllowed))
                              .toInt();
                          if (newColSpan != item.colSpan) {
                            HapticFeedback.selectionClick();
                            setState(() => item.colSpan = newColSpan);
                          }
                        },
                        onPanEnd: (_) {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        onPanCancel: () {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        child: Center(
                          child: Container(
                            width: 3.5,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.primary.withAlpha(140),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // [5/8] 左上角拉伸把手
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 16,
                    height: 16,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpLeftDownRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          _selectedItemId = item.id;
                          _resizeStartGlobalPos = details.globalPosition;
                          _resizeStartCol = item.col;
                          _resizeStartRow = item.row;
                          _resizeStartColSpan = item.colSpan;
                          _resizeStartRowSpan = item.rowSpan;
                          setState(() {});
                        },
                        onPanUpdate: (details) {
                          if (_resizeStartGlobalPos == null) return;
                          final totalDelta =
                              details.globalPosition - _resizeStartGlobalPos!;
                          // 垂直 Y
                          final bottomAnchorRow =
                              _resizeStartRow + _resizeStartRowSpan;
                          final deltaRows =
                              (totalDelta.dy / (_cellHeight + _spacing))
                                  .round();
                          final targetRow = (_resizeStartRow + deltaRows)
                              .clamp(0, bottomAnchorRow - def.minRowSpan);
                          final targetRowSpan = (bottomAnchorRow - targetRow)
                              .clamp(def.minRowSpan, def.maxRowSpan);
                          final newRow = bottomAnchorRow - targetRowSpan;
                          // 水平 X
                          final rightAnchorCol =
                              _resizeStartCol + _resizeStartColSpan;
                          final deltaCols =
                              (totalDelta.dx / (cellWidth + _spacing)).round();
                          final minCol = _getMinColFor(item);
                          final targetCol = (_resizeStartCol + deltaCols)
                              .clamp(minCol, rightAnchorCol - def.minColSpan);
                          final targetColSpan = (rightAnchorCol - targetCol)
                              .clamp(def.minColSpan, def.maxColSpan);
                          final newCol = rightAnchorCol - targetColSpan;

                          if (newRow != item.row ||
                              targetRowSpan != item.rowSpan ||
                              newCol != item.col ||
                              targetColSpan != item.colSpan) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              item.row = newRow;
                              item.rowSpan = targetRowSpan;
                              item.col = newCol;
                              item.colSpan = targetColSpan;
                            });
                          }
                        },
                        onPanEnd: (_) {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        onPanCancel: () {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        child: Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.primary.withAlpha(160),
                                width: 1.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(45),
                                  blurRadius: 2,
                                  offset: const Offset(0, 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // [6/8] 右上角拉伸把手
                  Positioned(
                    right: 0,
                    top: 0,
                    width: 16,
                    height: 16,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpRightDownLeft,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          _selectedItemId = item.id;
                          _resizeStartGlobalPos = details.globalPosition;
                          _resizeStartCol = item.col;
                          _resizeStartRow = item.row;
                          _resizeStartColSpan = item.colSpan;
                          _resizeStartRowSpan = item.rowSpan;
                          setState(() {});
                        },
                        onPanUpdate: (details) {
                          if (_resizeStartGlobalPos == null) return;
                          final totalDelta =
                              details.globalPosition - _resizeStartGlobalPos!;
                          // 垂直 Y
                          final bottomAnchorRow =
                              _resizeStartRow + _resizeStartRowSpan;
                          final deltaRows =
                              (totalDelta.dy / (_cellHeight + _spacing))
                                  .round();
                          final targetRow = (_resizeStartRow + deltaRows)
                              .clamp(0, bottomAnchorRow - def.minRowSpan);
                          final targetRowSpan = (bottomAnchorRow - targetRow)
                              .clamp(def.minRowSpan, def.maxRowSpan);
                          final newRow = bottomAnchorRow - targetRowSpan;
                          // 水平 X
                          final deltaCols =
                              (totalDelta.dx / (cellWidth + _spacing)).round();
                          final maxAllowed = _getMaxColSpanFor(item);
                          final newColSpan = (_resizeStartColSpan + deltaCols)
                              .clamp(def.minColSpan,
                                  math.max<int>(def.minColSpan, maxAllowed))
                              .toInt();

                          if (newRow != item.row ||
                              targetRowSpan != item.rowSpan ||
                              newColSpan != item.colSpan) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              item.row = newRow;
                              item.rowSpan = targetRowSpan;
                              item.colSpan = newColSpan;
                            });
                          }
                        },
                        onPanEnd: (_) {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        onPanCancel: () {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        child: Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.primary.withAlpha(160),
                                width: 1.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(45),
                                  blurRadius: 2,
                                  offset: const Offset(0, 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // [7/8] 左下角拉伸把手
                  Positioned(
                    left: 0,
                    bottom: 0,
                    width: 16,
                    height: 16,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpRightDownLeft,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          _selectedItemId = item.id;
                          _resizeStartGlobalPos = details.globalPosition;
                          _resizeStartCol = item.col;
                          _resizeStartRow = item.row;
                          _resizeStartColSpan = item.colSpan;
                          _resizeStartRowSpan = item.rowSpan;
                          setState(() {});
                        },
                        onPanUpdate: (details) {
                          if (_resizeStartGlobalPos == null) return;
                          final totalDelta =
                              details.globalPosition - _resizeStartGlobalPos!;
                          // 垂直 Y
                          final deltaRows =
                              (totalDelta.dy / (_cellHeight + _spacing))
                                  .round();
                          final newRowSpan = (_resizeStartRowSpan + deltaRows)
                              .clamp(def.minRowSpan, def.maxRowSpan);
                          // 水平 X
                          final rightAnchorCol =
                              _resizeStartCol + _resizeStartColSpan;
                          final deltaCols =
                              (totalDelta.dx / (cellWidth + _spacing)).round();
                          final minCol = _getMinColFor(item);
                          final targetCol = (_resizeStartCol + deltaCols)
                              .clamp(minCol, rightAnchorCol - def.minColSpan);
                          final targetColSpan = (rightAnchorCol - targetCol)
                              .clamp(def.minColSpan, def.maxColSpan);
                          final newCol = rightAnchorCol - targetColSpan;

                          if (newRowSpan != item.rowSpan ||
                              newCol != item.col ||
                              targetColSpan != item.colSpan) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              item.rowSpan = newRowSpan;
                              item.col = newCol;
                              item.colSpan = targetColSpan;
                            });
                          }
                        },
                        onPanEnd: (_) {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        onPanCancel: () {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        child: Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.primary.withAlpha(160),
                                width: 1.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(45),
                                  blurRadius: 2,
                                  offset: const Offset(0, 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // [8/8] 右下角对角线拉伸把手（主拉伸把手，带有强化抓取视觉）
                  Positioned(
                    right: 0,
                    bottom: 0,
                    width: 16,
                    height: 16,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          _selectedItemId = item.id;
                          _resizeStartGlobalPos = details.globalPosition;
                          _resizeStartCol = item.col;
                          _resizeStartRow = item.row;
                          _resizeStartColSpan = item.colSpan;
                          _resizeStartRowSpan = item.rowSpan;
                          setState(() {});
                        },
                        onPanUpdate: (details) {
                          if (_resizeStartGlobalPos == null) return;
                          final totalDelta =
                              details.globalPosition - _resizeStartGlobalPos!;
                          final deltaRows =
                              (totalDelta.dy / (_cellHeight + _spacing))
                                  .round();
                          final deltaCols =
                              (totalDelta.dx / (cellWidth + _spacing)).round();
                          final newRowSpan = (_resizeStartRowSpan + deltaRows)
                              .clamp(def.minRowSpan, def.maxRowSpan);
                          final maxAllowed = _getMaxColSpanFor(item);
                          final newColSpan = (_resizeStartColSpan + deltaCols)
                              .clamp(def.minColSpan,
                                  math.max<int>(def.minColSpan, maxAllowed))
                              .toInt();

                          if (newRowSpan != item.rowSpan ||
                              newColSpan != item.colSpan) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              item.rowSpan = newRowSpan;
                              item.colSpan = newColSpan;
                            });
                          }
                        },
                        onPanEnd: (_) {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        onPanCancel: () {
                          _resizeStartGlobalPos = null;
                          setState(
                              () => _autoAdjustAndCompact(activeItem: item));
                        },
                        child: Center(
                          child: Container(
                            width: 8.5,
                            height: 8.5,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.primary
                                  : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.primary,
                                width: 1.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withAlpha(80),
                                  blurRadius: 3,
                                  offset: const Offset(0, 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 底部悬浮卡片库（Card Library Tray - 严格按页面分类过滤，支持长按往画布拖入）
  Widget _buildCardDockTray(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 严格按当前页面过滤支持的卡片（杜绝跨页面不相干卡片污染）
    final pageDefs = CardRegistry.definitions.values
        .where((d) => d.supportedPages.contains(_currentPage))
        .toList();

    // 仅显示当前页面实际拥有的卡片所属分类
    final availableCategories = DashboardCardCategory.values
        .where(
          (cat) => pageDefs.any((d) => d.category == cat),
        )
        .toList();

    final activeCategory = (_selectedCategory != null &&
            availableCategories.contains(_selectedCategory))
        ? _selectedCategory
        : null;

    final filteredDefs = activeCategory == null
        ? pageDefs
        : pageDefs.where((d) => d.category == activeCategory).toList();

    if (_isDockCollapsed) {
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest.withAlpha(245),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(25),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
          border: Border(
            top: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(80), width: 1.0),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.widgets_outlined, size: 16, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              '卡片库已收起 (共 ${pageDefs.length} 张可用卡片)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface),
            )),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
              label: const Text('展开卡片库',
                  style:
                      TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              onPressed: () => setState(() => _isDockCollapsed = false),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withAlpha(245),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border(
          top: BorderSide(
              color: colorScheme.outlineVariant.withAlpha(60), width: 0.8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.touch_app_rounded, size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                        child: Text(
                      '拖拽或长按卡片添加到画布',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5),
                    )),
                    TextButton.icon(
                      onPressed: () => setState(() => _isDockCollapsed = true),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          size: 16),
                      label: const Text('收起'),
                    ),
                  ]),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _buildCategoryFilter(null, '全部 (${pageDefs.length})'),
                      for (final category in availableCategories)
                        _buildCategoryFilter(category,
                            '${category.label} (${pageDefs.where((definition) => definition.category == category).length})'),
                    ]),
                  ),
                ]),
          ),

          // 卡片陈列架 (带左右快捷滚动按钮、横向鼠标滚轮监听与显式可拖拽滚动条)
          Container(
            height: 98,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                // 左侧快速翻动按钮
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 22),
                    tooltip: '向左翻看卡片',
                    style: IconButton.styleFrom(
                      backgroundColor:
                          colorScheme.surfaceContainerHighest.withAlpha(120),
                      padding: const EdgeInsets.all(4),
                    ),
                    onPressed: () {
                      _dockScrollCtrl.animateTo(
                        math.max(0.0, _dockScrollCtrl.offset - 260.0),
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    },
                  ),
                ),

                // 核心卡片列表与横向滚轮适配
                Expanded(
                  child: Listener(
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        final delta = pointerSignal.scrollDelta.dy != 0
                            ? pointerSignal.scrollDelta.dy
                            : pointerSignal.scrollDelta.dx;
                        final target = (_dockScrollCtrl.offset + delta * 2)
                            .clamp(
                                0.0, _dockScrollCtrl.position.maxScrollExtent);
                        _dockScrollCtrl.jumpTo(target);
                      }
                    },
                    child: Scrollbar(
                      controller: _dockScrollCtrl,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                            PointerDeviceKind.stylus,
                          },
                        ),
                        child: ListView.separated(
                          controller: _dockScrollCtrl,
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                          scrollDirection: Axis.horizontal,
                          itemCount: filteredDefs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, idx) {
                            final def = filteredDefs[idx];

                            return Draggable<String>(
                              data: def.cardType,
                              feedback: Material(
                                color: Colors.transparent,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 10,
                                          offset: Offset(0, 4))
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(def.icon,
                                          size: 18, color: Colors.white),
                                      const SizedBox(width: 6),
                                      Text(
                                        def.name,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.4,
                                child: _buildMiniCardChip(context, def),
                              ),
                              child: _buildMiniCardChip(context, def),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // 右侧快速翻动按钮
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 22),
                    tooltip: '向右翻看更多卡片',
                    style: IconButton.styleFrom(
                      backgroundColor:
                          colorScheme.surfaceContainerHighest.withAlpha(120),
                      padding: const EdgeInsets.all(4),
                    ),
                    onPressed: () {
                      _dockScrollCtrl.animateTo(
                        math.min(_dockScrollCtrl.position.maxScrollExtent,
                            _dockScrollCtrl.offset + 260.0),
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter(DashboardCardCategory? cat, String label) {
    final isSelected = _selectedCategory == cat;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
                fontSize: 10.5,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface)),
        selected: isSelected,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        onSelected: (_) => setState(() => _selectedCategory = cat),
      ),
    );
  }

  Widget _buildMiniCardChip(BuildContext context, CardDefinition def) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColSpan = _isWorkbenchMode ? 4 : def.defaultColSpan;

    return Container(
      width: 108,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(60), width: 0.8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(def.icon, size: 20, color: colorScheme.primary),
          const SizedBox(height: 3),
          Text(
            def.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 1),
          Text(
            '$effectiveColSpan×${def.defaultRowSpan}',
            style: TextStyle(fontSize: 9.5, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 真实分栏顶部导航栏高保真还原 (1:1 绝对对齐实际桌面界面)
  // ==========================================

  Widget _buildRightWorkbenchHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            _currentPage == 'guide'
                ? Icons.explore_outlined
                : Icons.table_chart_rounded,
            size: 15,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 6),
          Text(
            _currentPage == 'guide' ? '导读 · 工作台' : '工作台 · 助手',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colorScheme.outline,
            ),
          ),
          const Spacer(),
          Icon(Icons.tune_rounded, size: 14, color: colorScheme.outline),
          const SizedBox(width: 8),
          Icon(Icons.keyboard_double_arrow_right_rounded,
              size: 15, color: colorScheme.outline),
        ],
      ),
    );
  }

  Widget _buildHomeRightCommunityHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_rounded, size: 15, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '社区动态',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withAlpha(210),
            ),
          ),
          const Spacer(),
          Icon(Icons.tune_rounded, size: 14, color: colorScheme.outline),
          const SizedBox(width: 8),
          IconButton(
            icon:
                const Icon(Icons.keyboard_double_arrow_right_rounded, size: 15),
            tooltip: '收起右侧卡片 (中央页面流自适应展开)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            onPressed: () {
              setState(() => _hideRightCards = true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHomeLeftToolsHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(Icons.widgets_outlined, size: 15, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '个人工具',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withAlpha(210),
            ),
          ),
          const Spacer(),
          Icon(Icons.tune_rounded, size: 14, color: colorScheme.outline),
          const SizedBox(width: 8),
          IconButton(
            icon:
                const Icon(Icons.keyboard_double_arrow_left_rounded, size: 15),
            tooltip: '收起左侧卡片 (中央页面流自适应展开)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            onPressed: () {
              setState(() => _hideLeftCards = true);
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 使用已加载数据预览中央内容；首页与实际页面共享 sliver 布局。
  // ==========================================

  Widget _buildCenterPageDemoPreview({
    required BuildContext context,
    required double left,
    required double top,
    required double width,
    required double height,
    required int totalCols,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      key: const ValueKey('canvas-center-demo-preview'),
      left: left,
      top: top,
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(45),
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: colorScheme.outlineVariant.withAlpha(45))),
              ),
              child: Row(children: [
                Expanded(
                    child: Text(
                  _currentPage == 'home'
                      ? '首页'
                      : _currentPage == 'thread'
                          ? '帖子详情'
                          : '导读',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )),
                IconButton(
                  tooltip: '按窗口尺寸预览页面',
                  icon: const Icon(Icons.open_in_full_rounded, size: 16),
                  onPressed: _showPagePreview,
                ),
                IconButton(
                  tooltip: '隐藏页面流预览',
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () => setState(() {
                    _showCenterDemo = false;
                    _autoAdjustAndCompact();
                  }),
                ),
              ]),
            ),
            // 主体演示内容 (IgnorePointer 避免拦截底下的手势)
            Expanded(
              child: _currentPage == 'guide'
                  ? _buildGuideFeedDemo(context)
                  : IgnorePointer(
                      child: _currentPage == 'home'
                          ? _buildHomeFeedDemo(context, scrollable: false)
                          : SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              child: _buildThreadFeedDemo(context)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 帖子工作台专属：1:1 原生版块列表导航流仿真（EmbeddedForumPanel 对应视觉效果，对齐真实 PC 桌面版块分栏）
  Widget _buildLeftForumPanelPreview({
    required BuildContext context,
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    final groups = PreloadService.instance
            .get<List<ForumGroup>>('forum_groups', ignoreExpired: true) ??
        const [];
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Card.outlined(
        margin: EdgeInsets.zero,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          const Text('版块导航', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (groups.isEmpty) const Text('暂无已加载的版块'),
          for (final group in groups) ...[
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(group.name,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary))),
            for (final forum in group.forums)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(forum.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: forum.todayCount >= 0
                    ? Text('今日 ${forum.todayCount}')
                    : null,
              ),
          ],
        ]),
      ),
    );
  }

  ({String view, int page}) get _guidePreviewSelection {
    final cached = PreloadService.instance.get<({String view, int page})>(
        'guide_preview_selection',
        ignoreExpired: true);
    if (cached != null &&
        cached.page > 0 &&
        guideViews.any((view) => view.$1 == cached.view)) {
      return cached;
    }
    for (final (view, _, _) in guideViews) {
      if (_guideCachedThreads(view, 1) != null) return (view: view, page: 1);
    }
    return (view: 'hot', page: 1);
  }

  List<ThreadSummary>? _guideCachedThreads(String view, int page) =>
      PreloadService.instance
          .get<List<ThreadSummary>>('guide_${view}_$page', ignoreExpired: true);

  String get _previewThreadsCacheKey {
    if (_currentPage == 'guide') {
      final selection = _guidePreviewSelection;
      return 'guide_${selection.view}_${selection.page}';
    }
    return _homePreviewFeed.guideView == null
        ? 'home_threads'
        : 'guide_${_homePreviewFeed.guideView}_1';
  }

  List<ThreadSummary> get _previewThreads =>
      PreloadService.instance.get<List<ThreadSummary>>(_previewThreadsCacheKey,
          ignoreExpired: true) ??
      const [];

  Widget _buildHomeFeedDemo(BuildContext context, {bool scrollable = true}) =>
      LayoutBuilder(builder: (context, constraints) {
        final desktop = ResponsiveBreakpoints.isDesktop(context);
        final groups = PreloadService.instance
                .get<List<ForumGroup>>('forum_groups', ignoreExpired: true) ??
            const <ForumGroup>[];
        final stats = PreloadService.instance
                .get<SiteStats>('site_stats', ignoreExpired: true) ??
            const SiteStats();
        final announcements = PreloadService.instance
                .get<List<HornMessage>>('horn_messages', ignoreExpired: true) ??
            const <HornMessage>[];
        return CustomScrollView(
            key: const ValueKey('canvas-home-content'),
            primary: false,
            physics: scrollable ? null : const NeverScrollableScrollPhysics(),
            slivers: HomeContentSlivers.build(context,
                groups: groups,
                threads: _previewThreads,
                feed: _homePreviewFeed,
                emptyMessage: !PreloadService.instance.has(
                        _homePreviewFeed.guideView == null
                            ? 'home_threads'
                            : 'guide_${_homePreviewFeed.guideView}_1',
                        allowExpired: true)
                    ? '尚未取得${_homePreviewFeed.label}的预览数据'
                    : null,
                recommendations: PreloadService.instance
                    .get<List<ThreadSummary>>('home_threads',
                        ignoreExpired: true),
                onSelectFeed: (feed) => setState(() => _homePreviewFeed = feed),
                stats: stats,
                announcements: announcements,
                favoriteForumIds: {
                  for (final group in groups)
                    if (group.gid == 0)
                      for (final forum in group.forums) forum.fid,
                },
                isDesktop: desktop,
                centerWidth: constraints.maxWidth,
                sections: !desktop || constraints.maxWidth < 600
                    ? AppConfig.mobileHomeSections
                    : AppConfig.defaultMobileHomeSections,
                quickActionIds: AppConfig.mobileQuickActions,
                announcementsEnabled:
                    AppConfig.homeModules.contains('horn_banner'),
                isPreview: true));
      });
  Widget _buildGuideFeedDemo(BuildContext context, {bool scrollable = true}) {
    final selection = _guidePreviewSelection;
    return CachedGuidePreview(
        key: const ValueKey('canvas-guide-cached-preview'),
        initialView: selection.view,
        initialPage: selection.page,
        readThreads: _guideCachedThreads,
        readHasMore: (view, page) =>
            PreloadService.instance
                .get<bool>('guide_next_${view}_$page', ignoreExpired: true) ==
            true,
        scrollable: scrollable,
        loggedIn: DioClient.isLoggedIn);
  }

  Widget _buildThreadFeedDemo(BuildContext context) {
    final preview = PreloadService.instance
        .get<({int tid, ThreadDetailParsed detail})>('thread_preview_detail',
            ignoreExpired: true);
    if (preview == null || preview.detail.floors.isEmpty) {
      return const Card.outlined(
          child: Padding(
              padding: EdgeInsets.all(24), child: Text('打开帖子后，可在这里预览实际正文。')));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(preview.detail.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      for (final floor in preview.detail.floors.take(3))
        Card.outlined(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(floor.author,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            DiscuzPostRenderer(floor: floor, tid: preview.tid),
          ]),
        )),
    ]);
  }

  Future<void> _showPagePreview() async {
    var hideLeft = _hideLeftCards;
    var hideRight = _hideRightCards;
    final selection = _guidePreviewSelection;
    var guideView = selection.view;
    var guidePage = selection.page;
    final previewMessenger = GlobalKey<ScaffoldMessengerState>();
    await showDialog<void>(
      context: context,
      builder: (context) => DefaultTabController(
          length: guideViews.length,
          initialIndex: guideViews.indexWhere((view) => view.$1 == guideView),
          child: StatefulBuilder(builder: (context, setPreviewState) {
            final desktop = ResponsiveBreakpoints.isDesktop(context);
            final nativeDesktop = !kIsWeb &&
                const {
                  TargetPlatform.windows,
                  TargetPlatform.macOS,
                  TargetPlatform.linux,
                }.contains(defaultTargetPlatform);
            void previewNotice() => previewMessenger.currentState?.showSnackBar(
                const SnackBar(content: Text('这是布局预览。此操作请返回实际页面使用。')));
            void previewHomeAction(HomeHeaderAction action) {
              if (action == HomeHeaderAction.left ||
                  action == HomeHeaderAction.right) {
                setPreviewState(() {
                  if (action == HomeHeaderAction.left) {
                    hideLeft = !hideLeft;
                  } else {
                    hideRight = !hideRight;
                  }
                });
              } else {
                previewNotice();
              }
            }

            final cachedCounts = PreloadService.instance
                .get<({String session, int pm, int notice})>(
                    'home_header_counts',
                    ignoreExpired: true);
            final currentCounts = cachedCounts?.session == DioClient.sessionKey
                ? cachedCounts
                : null;
            final close = IconButton(
                key: const ValueKey('canvas-preview-close'),
                tooltip: '关闭布局预览',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop());
            return Dialog.fullscreen(
              child: ScaffoldMessenger(
                  key: previewMessenger,
                  child: Scaffold(
                      key: const ValueKey('canvas-page-preview'),
                      appBar: _currentPage == 'home'
                          ? HomePageHeader(
                              key: const ValueKey('canvas-preview-home-header'),
                              isDesktop: desktop,
                              nativeDesktop: nativeDesktop,
                              searchController: _previewSearchCtrl,
                              toolbarHeight: HomePageHeader.heightFor(context),
                              leading: close,
                              loggedIn: DioClient.isLoggedIn,
                              unreadPm: currentCounts?.pm ?? 0,
                              unreadNotice: currentCounts?.notice ?? 0,
                              leftExpanded: !hideLeft,
                              rightExpanded: !hideRight,
                              onAction: previewHomeAction)
                          : _currentPage == 'guide'
                              ? GuidePageHeader(
                                  key: const ValueKey(
                                      'canvas-preview-guide-header'),
                                  tabHeight:
                                      GuideCategoryTabs.heightFor(context),
                                  toolbarHeight:
                                      GuidePageHeader.toolbarHeightFor(context),
                                  searchController: _previewSearchCtrl,
                                  onSearch: previewNotice,
                                  onRefresh: previewNotice,
                                  onCustomize: previewNotice,
                                  workbenchExpanded: !hideRight,
                                  onToggleWorkbench: () => setPreviewState(
                                      () => hideRight = !hideRight),
                                  leading: close,
                                  onViewSelected: (view) => setPreviewState(() {
                                        guideView = view;
                                        guidePage = 1;
                                      }))
                              : AppBar(
                                  title: const Text('页面布局预览'), leading: close),
                      body: LayoutBuilder(builder: (context, constraints) {
                        final desktop =
                            ResponsiveBreakpoints.isDesktop(context);
                        final visibleItems = _currentPage == 'home'
                            ? _items.where((item) =>
                                item.cardType != 'credit_log' &&
                                item.cardType != 'horn_banner')
                            : _items;
                        final guideThreads =
                            _guideCachedThreads(guideView, guidePage);
                        List<DashboardGridItem> itemsFor(bool left) =>
                            visibleItems
                                .where((item) =>
                                    ((item.col + item.colSpan / 2) < 6) == left)
                                .toList()
                              ..sort((a, b) => a.row != b.row
                                  ? a.row.compareTo(b.row)
                                  : a.col.compareTo(b.col));
                        final leftItems = itemsFor(true);
                        final rightItems = itemsFor(false);
                        final metrics = HomeLayoutMetrics.calculate(
                            width: constraints.maxWidth,
                            desktop: desktop,
                            leftEnabled: !hideLeft && leftItems.isNotEmpty,
                            rightEnabled: !hideRight && rightItems.isNotEmpty,
                            preferredLeft: AppConfig.homeLeftSidebarWidth,
                            preferredRight: AppConfig.homeRightSidebarWidth,
                            minimumCenterWidth: AppConfig.mainContentMinWidth);
                        Widget pane(bool left, double width) {
                          final items = left ? leftItems : rightItems;
                          if (_currentPage == 'guide') {
                            return GuideWorkbench(
                                key: ValueKey(
                                    'canvas-preview-${left ? 'left' : 'right'}-pane'),
                                items: items,
                                onSettings: previewNotice,
                                onCollapse: () =>
                                    setPreviewState(() => hideRight = true),
                                cardBuilder: (context, item) {
                                  final card = DashboardCardFactory.buildCard(
                                      item: item,
                                      isPreview: true,
                                      threads: guideThreads,
                                      threadsCacheKey:
                                          'guide_${guideView}_$guidePage');
                                  return item.cardType == 'tuhao_stats'
                                      ? card
                                      : IgnorePointer(child: card);
                                });
                          }
                          final scheme = Theme.of(context).colorScheme;
                          return Container(
                              key: ValueKey(
                                  'canvas-preview-${left ? 'left' : 'right'}-pane'),
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? scheme.surfaceContainerLow
                                  : scheme.surfaceContainerLowest,
                              child: Column(children: [
                                Container(
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    decoration: BoxDecoration(
                                        border: Border(
                                            bottom: BorderSide(
                                                color: scheme.outlineVariant
                                                    .withAlpha(25),
                                                width: .8))),
                                    child: Row(children: [
                                      Icon(
                                          left
                                              ? Icons.widgets_outlined
                                              : Icons.insights_rounded,
                                          size: 16,
                                          color: scheme.primary),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: Text(left ? '个人工具' : '社区动态',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis)),
                                      IconButton(
                                          key: ValueKey(
                                              'canvas-preview-${left ? 'left' : 'right'}-collapse'),
                                          tooltip: left ? '收起左侧栏' : '收起右侧栏',
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 26, minHeight: 26),
                                          icon: Icon(
                                              left
                                                  ? Icons.first_page_rounded
                                                  : Icons.last_page_rounded,
                                              size: 17),
                                          onPressed: () => setPreviewState(() {
                                                if (left) {
                                                  hideLeft = true;
                                                } else {
                                                  hideRight = true;
                                                }
                                              })),
                                    ])),
                                Expanded(
                                    child: ListView.separated(
                                        padding: const EdgeInsets.fromLTRB(
                                            10, 10, 10, 16),
                                        itemCount: items.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 10),
                                        itemBuilder: (context, index) {
                                          final item = items[index];
                                          final card = DashboardCardFactory.buildCard(
                                              item: item,
                                              isPreview: true,
                                              suppressDefaultStats: _currentPage ==
                                                      'home' &&
                                                  PreloadService.instance
                                                          .get<SiteStats>(
                                                              'site_stats',
                                                              ignoreExpired:
                                                                  true)
                                                          ?.isEmpty ==
                                                      false &&
                                                  (desktop &&
                                                          metrics.centerWidth >=
                                                              600 ||
                                                      AppConfig
                                                          .mobileHomeSections
                                                          .contains('stats')),
                                              threads: _previewThreads,
                                              threadsCacheKey:
                                                  _previewThreadsCacheKey,
                                              stats: PreloadService.instance
                                                  .get<SiteStats>('site_stats',
                                                      ignoreExpired: true));
                                          return SizedBox(
                                              height: HomeLayoutMetrics
                                                  .sidebarCardHeight(
                                                      type: item.cardType,
                                                      rows: item.rowSpan,
                                                      width: width),
                                              // 霸屏预览仅允许本地分页；组件自身已禁用
                                              // 网络、跳转与发布入口。
                                              child: item.cardType ==
                                                      'tuhao_stats'
                                                  ? card
                                                  : IgnorePointer(child: card));
                                        })),
                              ]));
                        }

                        Widget splitter() => SizedBox(
                            width: 8,
                            child: Center(
                                child: Container(
                                    width: 2,
                                    height: 36,
                                    decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withAlpha(80),
                                        borderRadius:
                                            BorderRadius.circular(1)))));
                        Widget handle(bool left) => SizedBox(
                            key: ValueKey(
                                'canvas-preview-${left ? 'left' : 'right'}-handle'),
                            width: _currentPage == 'guide'
                                ? GuideLayout.collapsedWidth
                                : 26,
                            child: Center(
                                child: IconButton(
                                    tooltip: left ? '展开左侧个人工具栏' : '展开右侧社区动态栏',
                                    padding: EdgeInsets.zero,
                                    iconSize: 18,
                                    icon: Icon(left
                                        ? Icons.chevron_right_rounded
                                        : Icons.chevron_left_rounded),
                                    onPressed: _currentPage != 'guide' &&
                                            (left ? leftItems : rightItems)
                                                .isEmpty
                                        ? null
                                        : () => setPreviewState(() {
                                              if (left) {
                                                hideLeft = false;
                                              } else {
                                                hideRight = false;
                                              }
                                            }))));
                        final feed = KeyedSubtree(
                            key: const ValueKey('canvas-preview-center'),
                            child: _currentPage == 'home'
                                ? _buildHomeFeedDemo(context)
                                : _currentPage == 'guide'
                                    ? GuideContent(
                                        key: ValueKey(
                                            'canvas-preview-guide-feed-$guideView-$guidePage'),
                                        threads: guideThreads ?? const [],
                                        page: guidePage,
                                        hasMore: PreloadService.instance.get<
                                                    bool>(
                                                'guide_next_${guideView}_$guidePage',
                                                ignoreExpired: true) ==
                                            true,
                                        loginRequired: guideView == 'follow' &&
                                            !DioClient.isLoggedIn,
                                        emptySubtitle: guideThreads == null
                                            ? '浏览此导读分类后，可在这里预览真实列表。预览不会联网加载。'
                                            : null,
                                        onPageChanged: (page) {
                                          if (_guideCachedThreads(
                                                  guideView, page) !=
                                              null) {
                                            setPreviewState(
                                                () => guidePage = page);
                                          } else {
                                            previewMessenger.currentState
                                                ?.showSnackBar(const SnackBar(
                                                    content: Text(
                                                        '此页尚未缓存，请在实际导读页面浏览后再预览。')));
                                          }
                                        })
                                    : SingleChildScrollView(
                                        padding: const EdgeInsets.all(12),
                                        child: IgnorePointer(
                                            child: _buildThreadFeedDemo(
                                                context))));
                        if (_currentPage != 'home') {
                          final viable = _currentPage == 'guide'
                              ? GuideLayout.canShowWorkbench(
                                  context, constraints.maxWidth)
                              : desktop && constraints.maxWidth >= 680;
                          final showWorkbench = viable &&
                              !hideRight &&
                              (_currentPage == 'guide' ||
                                  rightItems.isNotEmpty);
                          final rightWidth = _currentPage == 'guide'
                              ? GuideLayout.workbenchWidth
                              : AppConfig.threadRightWidth.clamp(200.0, 520.0);
                          return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                    child: Align(
                                        alignment: Alignment.topCenter,
                                        child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                                maxWidth: _currentPage ==
                                                        'guide'
                                                    ? GuideLayout
                                                        .contentMaxWidth
                                                    : AppConfig.threadContentMaxWidth >
                                                            0
                                                        ? AppConfig
                                                            .threadContentMaxWidth
                                                        : double.infinity),
                                            child: feed))),
                                if (_currentPage == 'guide' && viable)
                                  GuideWorkbenchRegion(
                                      key: const ValueKey(
                                          'canvas-preview-guide-workbench-region'),
                                      expanded: showWorkbench,
                                      workbenchBuilder: (_) =>
                                          pane(false, rightWidth),
                                      handleKey: const ValueKey(
                                          'canvas-preview-right-handle'),
                                      onExpand: () => setPreviewState(
                                          () => hideRight = false))
                                else if (showWorkbench) ...[
                                  if (_currentPage == 'thread') splitter(),
                                  SizedBox(
                                      width: rightWidth,
                                      child: pane(false, rightWidth)),
                                ] else if (viable)
                                  handle(false),
                              ]);
                        }
                        return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (desktop)
                                AnimatedSidePanel(
                                    key: const ValueKey(
                                        'canvas-preview-left-panel'),
                                    expanded: metrics.showLeft,
                                    width: metrics.leftWidth,
                                    isLeft: true,
                                    splitter: splitter(),
                                    handle: handle(true),
                                    child: pane(true, metrics.leftWidth)),
                              Expanded(child: feed),
                              if (desktop)
                                AnimatedSidePanel(
                                    key: const ValueKey(
                                        'canvas-preview-right-panel'),
                                    expanded: metrics.showRight,
                                    width: metrics.rightWidth,
                                    isLeft: false,
                                    splitter: splitter(),
                                    handle: handle(false),
                                    child: pane(false, metrics.rightWidth)),
                            ]);
                      }))),
            );
          })),
    );
  }
}

/// 蓝图网格绘制器（在画布背景绘制浅色微点阵或网格线，中心区域与左侧版块视图留出真实内容流预览舞台）
class _GridBlueprintPainter extends CustomPainter {
  final int totalCols;
  final double cellWidth;
  final double cellHeight;
  final double spacing;
  final EdgeInsets padding;
  final Color gridColor;
  final bool isThreadMode;
  final int centerColStart;
  final int centerColEnd;
  final int leftColStart;
  final int leftColEnd;

  _GridBlueprintPainter({
    required this.totalCols,
    required this.cellWidth,
    required this.cellHeight,
    required this.spacing,
    required this.padding,
    required this.gridColor,
    this.isThreadMode = false,
    this.centerColStart = 4,
    this.centerColEnd = 7,
    this.leftColStart = -1,
    this.leftColEnd = -1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = gridColor.withAlpha(70)
      ..style = PaintingStyle.fill;

    final totalRows =
        ((size.height - padding.vertical) / (cellHeight + spacing)).ceil() + 1;

    for (int r = 0; r < totalRows; r++) {
      for (int c = 0; c < totalCols; c++) {
        final x = padding.left + c * (cellWidth + spacing);
        final y = padding.top + r * (cellHeight + spacing);

        if (isThreadMode && c < 8) {
          // 在帖子工作台模式下，前 8 列（0..7）为版块边栏与正文流专属区域，绝非卡片可放置网格！
          // 仅绘制极微弱的对齐点，绝对不画任何空的卡片虚线槽位
          canvas.drawCircle(
              Offset(x, y), 0.8, dotPaint..color = gridColor.withAlpha(12));
          continue;
        }

        final isCenter =
            (centerColStart >= 0 && c >= centerColStart && c <= centerColEnd) ||
                (leftColStart >= 0 && c >= leftColStart && c <= leftColEnd);
        if (isCenter) {
          // 中心高保真预览区不画单元格厚框，仅留微弱对齐十字点
          canvas.drawCircle(
              Offset(x, y), 0.8, dotPaint..color = gridColor.withAlpha(15));
          continue;
        }

        // 绘制十字或微圆点
        canvas.drawCircle(
            Offset(x, y), 1.2, dotPaint..color = gridColor.withAlpha(70));
        // 绘制单元格虚线外框
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cellWidth, cellHeight),
          const Radius.circular(6),
        );
        canvas.drawRRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridBlueprintPainter oldDelegate) {
    return oldDelegate.totalCols != totalCols ||
        oldDelegate.cellWidth != cellWidth ||
        oldDelegate.cellHeight != cellHeight ||
        oldDelegate.isThreadMode != isThreadMode ||
        oldDelegate.centerColStart != centerColStart ||
        oldDelegate.centerColEnd != centerColEnd ||
        oldDelegate.leftColStart != leftColStart ||
        oldDelegate.leftColEnd != leftColEnd;
  }
}
