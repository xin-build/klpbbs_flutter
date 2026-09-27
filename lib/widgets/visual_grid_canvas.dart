import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_config.dart';
import '../models/dashboard_card_model.dart';
import '../models/site_stats.dart';
import '../models/thread_summary.dart';
import 'dashboard_cards/card_settings_dialog.dart';
import 'dashboard_cards/dashboard_card_factory.dart';
import 'site_stats_card.dart';
import 'thread_card.dart';

/// 全站专业级可视化自由网格画布工作台（支持自由网格吸附、从工具栏拖拽添加、长按移动、拉伸长宽高、右上角保存、恢复默认与 GPU 加速）
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
  bool get _isWorkbenchMode => _currentPage == 'thread' || _currentPage == 'guide';

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

  final ScrollController _canvasScrollCtrl = ScrollController();
  final ScrollController _dockScrollCtrl = ScrollController();
  final GlobalKey _canvasContentKey = GlobalKey();

  static const double _cellHeight = 86.0;
  static const double _spacing = 10.0;
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(14, 14, 14, 160);

  @override
  void initState() {
    super.initState();
    _currentPage = widget.pageCategory;
    _showThreadForumPanel = true;
    _hideLeftCards = false;
    _hideRightCards = false;
    if (_currentPage == 'thread') {
      final validModuleIds = AppConfig.threadRightModules;
      final existingMap = <String, DashboardGridItem>{};
      for (final it in widget.initialLayout) {
        if (it.cardType != 'user_profile' && validModuleIds.contains(it.cardType)) {
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
        );
        currentRow += span;
        return item;
      }).toList();
    } else if (_currentPage == 'guide') {
      _items = widget.initialLayout.map((e) => e.copyWith()).toList();
      if (_items.isEmpty) {
        _items = CardRegistry.getDefaultGuideLayout();
      }
      for (final it in _items) {
        it.col = 8;
        it.colSpan = 4;
      }
    } else {
      _items = widget.initialLayout.map((e) => e.copyWith()).toList();
      final hasLeft = _items.any((it) => (it.col + it.colSpan / 2.0) < 6);
      if (_items.isEmpty || !hasLeft) {
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
    super.dispose();
  }

  void _switchPage(String page) {
    if (_currentPage == page) return;
    setState(() {
      _currentPage = page;
      _selectedCategory = null;
      _snapGhost = null;
      _draggingItemId = null;
      if (page == 'home') {
        _hideLeftCards = false;
        _hideRightCards = false;
        _items = AppConfig.homeDashboardLayout.map((e) => e.copyWith()).toList();
        final hasLeft = _items.any((it) => (it.col + it.colSpan / 2.0) < 6);
        if (_items.isEmpty || !hasLeft) _items = CardRegistry.getDefaultHomeLayout();
      } else if (page == 'thread') {
        _showThreadForumPanel = true;
        final validModuleIds = AppConfig.threadRightModules;
        final existingMap = <String, DashboardGridItem>{};
        for (final it in AppConfig.threadDashboardLayout) {
          if (it.cardType != 'user_profile' && validModuleIds.contains(it.cardType)) {
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
          );
          currentRow += span;
          return item;
        }).toList();
      } else if (page == 'guide') {
        _items = AppConfig.guideDashboardLayout.map((e) => e.copyWith()).toList();
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
        content: const Text('确定要将当前界面的卡片布局重置为官方推荐默认方案吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
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
                const SnackBar(content: Text('已重置为官方推荐默认布局')),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentPage == 'thread'
                    ? '📐 切换帖子工作台预设'
                    : (_currentPage == 'guide' ? '📐 切换导读工作台预设' : '📐 切换首页经典布局预设'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (_currentPage == 'thread') ...[
                ListTile(
                  leading: const Icon(Icons.dashboard_customize_rounded, color: Colors.blue),
                  title: const Text('全能助手预设'),
                  subtitle: const Text('包含文章大纲、楼层罗盘、阅读调谐器与评分大厅'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      int r = 0;
                      _items = ['toc_outline', 'floor_compass', 'reader_tuning', 'rating_hub'].map((id) {
                        final span = CardRegistry.get(id).defaultRowSpan;
                        final it = DashboardGridItem(id: 'th_$id', cardType: id, col: 8, row: r, colSpan: 4, rowSpan: span);
                        r += span;
                        return it;
                      }).toList();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book_rounded, color: Colors.teal),
                  title: const Text('沉浸纯享阅读预设'),
                  subtitle: const Text('仅保留大纲目录与阅读调谐器，极致专注'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      int r = 0;
                      _items = ['toc_outline', 'reader_tuning'].map((id) {
                        final span = CardRegistry.get(id).defaultRowSpan;
                        final it = DashboardGridItem(id: 'th_$id', cardType: id, col: 8, row: r, colSpan: 4, rowSpan: span);
                        r += span;
                        return it;
                      }).toList();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.card_giftcard_rounded, color: Colors.amber),
                  title: const Text('互动与多功能预设'),
                  subtitle: const Text('评分大厅、帕帕 AI 助手、帖内检索与打卡日历'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      int r = 0;
                      _items = ['rating_hub', 'papa_ai_quick', 'thread_search', 'sign_calendar'].map((id) {
                        final span = CardRegistry.get(id).defaultRowSpan;
                        final it = DashboardGridItem(id: 'th_$id', cardType: id, col: 8, row: r, colSpan: 4, rowSpan: span);
                        r += span;
                        return it;
                      }).toList();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
              ] else if (_currentPage == 'guide') ...[
                ListTile(
                  leading: const Icon(Icons.explore_outlined, color: Colors.blue),
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
                  leading: const Icon(Icons.flash_on_rounded, color: Colors.orange),
                  title: const Text('高频互动方案'),
                  subtitle: const Text('快捷发帖、活跃之星、常用版块与签到日历'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      int r = 0;
                      _items = ['quick_post', 'ranklist_card', 'forum_nav', 'sign_calendar'].map((id) {
                        final span = CardRegistry.get(id).defaultRowSpan;
                        final it = DashboardGridItem(id: 'gd_$id', cardType: id, col: 8, row: r, colSpan: 4, rowSpan: span);
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
                        final it = DashboardGridItem(id: 'gd_$id', cardType: id, col: 8, row: r, colSpan: 4, rowSpan: span);
                        r += span;
                        return it;
                      }).toList();
                      _autoAdjustAndCompact();
                    });
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.dashboard_customize_rounded, color: Colors.blue),
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
                  leading: const Icon(Icons.terminal_rounded, color: Colors.teal),
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
                  leading: const Icon(Icons.military_tech_rounded, color: Colors.amber),
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
                  leading: const Icon(Icons.fullscreen_rounded, color: Colors.purple),
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
          activeItem: (activeItem != null && leftGroup.any((x) => x.id == activeItem.id)) ? activeItem : null,
        );
      }

      if (rightGroup.isNotEmpty) {
        _compactGroup(
          rightGroup,
          totalCols: totalCols,
          minCol: 8,
          maxCol: 12,
          activeItem: (activeItem != null && rightGroup.any((x) => x.id == activeItem.id)) ? activeItem : null,
        );
      }
      return;
    }

    if (!_showCenterDemo) {
      _compactGroup(_items, totalCols: totalCols, minCol: 0, maxCol: totalCols, activeItem: activeItem);
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
        item.col = item.col.clamp(0, math.max(0, centerStart - item.colSpan)).toInt();
        leftGroup.add(item);
      } else {
        // 归属右侧区
        final rightMinCol = math.min(totalCols - 1, centerEnd);
        final maxColSpan = math.max(1, totalCols - rightMinCol);
        item.colSpan = item.colSpan.clamp(1, maxColSpan).toInt();
        item.col = item.col.clamp(rightMinCol, math.max(rightMinCol, totalCols - item.colSpan)).toInt();
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
        activeItem: (activeItem != null && leftGroup.any((x) => x.id == activeItem.id)) ? activeItem : null,
      );
    }

    if (centerEnd < totalCols && rightGroup.isNotEmpty) {
      _compactGroup(
        rightGroup,
        totalCols: totalCols,
        minCol: centerEnd,
        maxCol: totalCols,
        activeItem: (activeItem != null && rightGroup.any((x) => x.id == activeItem.id)) ? activeItem : null,
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
      final preferredCol = item.col.clamp(minCol, math.max(minCol, maxCol - span)).toInt();

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
            if (altCol != preferredCol && !hasConflict(testRow, altCol, item.rowSpan, span)) {
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

            final validPresets = allPresets.where((p) =>
              p.colSpan >= def.minColSpan &&
              p.colSpan <= maxCol &&
              p.rowSpan >= def.minRowSpan &&
              p.rowSpan <= def.maxRowSpan
            ).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.tune_rounded, color: colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('调整卡片尺寸', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(def.name, style: TextStyle(fontSize: 12, color: colorScheme.outline)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withAlpha(100),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.primary.withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('当前尺寸', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
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
                          Icon(Icons.auto_awesome_rounded, size: 14, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          const Text('推荐常用规格', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: validPresets.map((p) {
                          final isCur = item.colSpan == p.colSpan && item.rowSpan == p.rowSpan;
                          return ChoiceChip(
                            label: Text(p.label, style: TextStyle(fontSize: 11.5, fontWeight: isCur ? FontWeight.bold : FontWeight.normal)),
                            selected: isCur,
                            onSelected: (_) {
                              setState(() {
                                if (_isWorkbenchMode) {
                                  item.col = 8;
                                  item.colSpan = 4;
                                  item.rowSpan = p.rowSpan;
                                } else {
                                  item.col = item.col.clamp(minCol, math.max(minCol, minCol + maxWingWidth - p.colSpan));
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
                        Icon(Icons.straighten_rounded, size: 14, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        const Text('精准数值微调', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (!_isWorkbenchMode) ...[
                      // 宽度 (列数)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withAlpha(120),
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
                                  const Text('宽度 (列数)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  Text('范围: ${def.minColSpan} ~ $maxCol 列', style: TextStyle(fontSize: 10.5, color: colorScheme.outline)),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              icon: const Icon(Icons.remove, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: item.colSpan > def.minColSpan ? () {
                                setState(() {
                                  item.colSpan--;
                                  _autoAdjustAndCompact(activeItem: item);
                                });
                                setDialogState(() {});
                                HapticFeedback.lightImpact();
                              } : null,
                            ),
                            SizedBox(
                              width: 32,
                              child: Text(
                                '${item.colSpan}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton.filledTonal(
                              icon: const Icon(Icons.add, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: item.colSpan < maxCol ? () {
                                setState(() {
                                  final next = item.colSpan + 1;
                                  item.col = item.col.clamp(minCol, math.max(minCol, minCol + maxWingWidth - next));
                                  item.colSpan = next;
                                  _autoAdjustAndCompact(activeItem: item);
                                });
                                setDialogState(() {});
                                HapticFeedback.lightImpact();
                              } : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // 高度 (行数)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withAlpha(120),
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
                                const Text('高度 (行数)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                Text('范围: ${def.minRowSpan} ~ ${def.maxRowSpan} 行', style: TextStyle(fontSize: 10.5, color: colorScheme.outline)),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.remove, size: 16),
                            visualDensity: VisualDensity.compact,
                            onPressed: item.rowSpan > def.minRowSpan ? () {
                              setState(() {
                                item.rowSpan--;
                                _autoAdjustAndCompact(activeItem: item);
                              });
                              setDialogState(() {});
                              HapticFeedback.lightImpact();
                            } : null,
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${item.rowSpan}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.add, size: 16),
                            visualDensity: VisualDensity.compact,
                            onPressed: item.rowSpan < def.maxRowSpan ? () {
                              setState(() {
                                item.rowSpan++;
                                _autoAdjustAndCompact(activeItem: item);
                              });
                              setDialogState(() {});
                              HapticFeedback.lightImpact();
                            } : null,
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
  void _saveLayout() {
    HapticFeedback.heavyImpact();
    widget.onSave(_items);
    if (_currentPage == 'home') {
      AppConfig.setHomeDashboardLayout(_items);
    } else if (_currentPage == 'thread') {
      final sortedItems = List<DashboardGridItem>.from(_items)
        ..sort((a, b) => a.row.compareTo(b.row));
      AppConfig.setThreadDashboardLayout(sortedItems);
      final moduleIds = sortedItems.map((it) => it.cardType).toList();
      AppConfig.setThreadRightModules(moduleIds);
      AppConfig.setThreadLeftEnabled(_showThreadForumPanel);
    } else {
      final sortedItems = List<DashboardGridItem>.from(_items)
        ..sort((a, b) => a.row.compareTo(b.row));
      AppConfig.setGuideDashboardLayout(sortedItems);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🎉 自定义界面布局已成功保存并立即生效！')),
    );
    widget.onExit();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
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
    final renderBox = _canvasContentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final localPos = renderBox.globalToLocal(globalPos);

    final dx = localPos.dx - _padding.left;
    final dy = localPos.dy - _padding.top - _topHeaderOffset;

    final rawCol = (dx / (cellWidth + _spacing)).round();
    final rawRow = math.max(0, (dy / (_cellHeight + _spacing)).round());

    _applySnapGhost(rawCol, rawRow, colSpan, rowSpan, totalCols);
  }

  // 核心吸附分区约束与列宽自适应
  void _applySnapGhost(int rawCol, int rawRow, int colSpan, int rowSpan, int totalCols) {
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

    final newGhost = (col: targetCol, row: rawRow, colSpan: actualColSpan, rowSpan: rowSpan);
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

  void _onCardDragUpdate(DashboardGridItem item, Offset globalPos, double cellWidth, int totalCols) {
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
      body: Stack(
        children: [
          // 1. 核心可滚动交互网格画布
          LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = constraints.maxWidth;
              const totalCols = 12; // 工作台基准网格始终以标准的 12 列蓝图作为坐标系统，杜绝列数切换导致的错位
              // 严格对齐 HomePage 的 1280px 基准宽度，确保编辑与主页渲染 100% 1:1 几何比例一致
              final canvasWidth = viewportWidth > 1280.0 ? 1280.0 : math.max(viewportWidth, 880.0);
              final availableWidth = canvasWidth - _padding.horizontal;
              final cellWidth = (availableWidth - (totalCols - 1) * _spacing) / totalCols;

              int maxRow = 0;
              for (final item in _items) {
                final bottom = item.row + item.rowSpan;
                if (bottom > maxRow) maxRow = bottom;
              }
              // 底部预留专属安全缓冲区，彻底防止最下方的卡片或放置幽灵被浮动工具箱 Dock Tray 遮挡
              final bottomDockSafetyPadding = _isDockCollapsed ? 60.0 : 200.0;
              final canvasHeight = math.max(
                constraints.maxHeight,
                (maxRow + 3) * (_cellHeight + _spacing) + _padding.top + _topHeaderOffset + bottomDockSafetyPadding,
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
                      _updateSnapGhostFromGlobalPos(details.offset, def.defaultColSpan.clamp(1, totalCols), def.defaultRowSpan, cellWidth, totalCols);
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
                        physics: (_draggingItemId != null || _resizeStartGlobalPos != null)
                            ? const NeverScrollableScrollPhysics()
                            : (canvasWidth > viewportWidth ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics()),
                        child: SingleChildScrollView(
                          controller: _canvasScrollCtrl,
                          physics: (_draggingItemId != null || _resizeStartGlobalPos != null)
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
                                      padding: _padding.copyWith(top: _padding.top + _topHeaderOffset),
                                      gridColor: colorScheme.outlineVariant.withAlpha(35),
                                      isThreadMode: _isWorkbenchMode,
                                      centerColStart: _showCenterDemo ? _effectiveCenterCol : -1,
                                      centerColEnd: _showCenterDemo ? (_effectiveCenterCol + _effectiveCenterColSpan - 1) : -1,
                                      leftColStart: (_currentPage == 'thread' && _showCenterDemo && _showThreadForumPanel) ? 0 : -1,
                                      leftColEnd: (_currentPage == 'thread' && _showCenterDemo && _showThreadForumPanel) ? 3 : -1,
                                    ),
                                  ),
                                ),

                                // 帖子工作台专属：左侧高保真版块列表导航视图 (1:1 对齐 PC 桌面版块分栏，彻底消灭左侧留空白问题)
                                if (_currentPage == 'thread' && _showCenterDemo && _showThreadForumPanel)
                                  _buildLeftForumPanelPreview(
                                    context: context,
                                    left: _padding.left,
                                    top: _padding.top,
                                    width: 4 * cellWidth + 3 * _spacing,
                                    height: math.max(680.0, canvasHeight - _padding.top - _padding.bottom),
                                  ),

                                // 中心高保真页面流仿真视图 (所见即所得，支持位移、尺寸调节与按需关闭)
                                if (_showCenterDemo)
                                  _buildCenterPageDemoPreview(
                                    context: context,
                                    left: _padding.left + _effectiveCenterCol * (cellWidth + _spacing),
                                    top: _padding.top,
                                    width: _effectiveCenterColSpan * cellWidth + (_effectiveCenterColSpan - 1) * _spacing,
                                    height: math.max(680.0, canvasHeight - _padding.top - _padding.bottom),
                                    totalCols: totalCols,
                                  ),

                                // 工作台模式专属（帖子/导读）：右侧工作台助手顶部导航条
                                if (_showCenterDemo && _isWorkbenchMode)
                                  Positioned(
                                    left: _padding.left + 8 * (cellWidth + _spacing),
                                    top: _padding.top,
                                    width: 4 * cellWidth + 3 * _spacing,
                                    height: 38,
                                    child: _buildRightWorkbenchHeader(context),
                                  ),

                                // 首页专属：右侧社区动态顶部导航条 (1:1 对齐 media_1790393468984.png)
                                if (_showCenterDemo && _currentPage == 'home' && !_hideRightCards)
                                  Positioned(
                                    left: _padding.left + 8 * (cellWidth + _spacing),
                                    top: _padding.top,
                                    width: 4 * cellWidth + 3 * _spacing,
                                    height: 38,
                                    child: _buildHomeRightCommunityHeader(context),
                                  ),

                                // 首页专属：左侧个人工具顶部导航条 (1:1 对齐 PC 桌面端左侧工具栏)
                                if (_showCenterDemo && _currentPage == 'home' && !_hideLeftCards)
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
                                    left: _padding.left + _snapGhost!.col * (cellWidth + _spacing),
                                    top: _padding.top + _topHeaderOffset + _snapGhost!.row * (_cellHeight + _spacing),
                                    width: _snapGhost!.colSpan * cellWidth + (_snapGhost!.colSpan - 1) * _spacing,
                                    height: _snapGhost!.rowSpan * _cellHeight + (_snapGhost!.rowSpan - 1) * _spacing,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withAlpha(45),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: colorScheme.primary, width: 2.2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: colorScheme.primary.withAlpha(70),
                                            blurRadius: 12,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary,
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.check_circle_outline_rounded, size: 14, color: Colors.white),
                                              const SizedBox(width: 4),
                                              Text(
                                                '松手自动吸附于此 (${_snapGhost!.colSpan}×${_snapGhost!.rowSpan})',
                                                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // 已放置的卡片列表（仅在拖拽或选中时微调顶层层级，绝不因悬停触发生命周期与 Z 轴翻转，杜绝 MouseTracker 震荡风暴）
                                ...(() {
                                  final sorted = List<DashboardGridItem>.from(_items);
                                  sorted.sort((a, b) {
                                    final aActive = (a.id == _draggingItemId || a.id == _selectedItemId) ? 1 : 0;
                                    final bActive = (b.id == _draggingItemId || b.id == _selectedItemId) ? 1 : 0;
                                    return aActive.compareTo(bActive);
                                  });
                                  return sorted.map((item) {
                                    final isLeftCard = (item.col + item.colSpan / 2) < 6;
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
    );
  }

  /// 顶部专业操作控制栏
  PreferredSizeWidget _buildStudioAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: '放弃并退出',
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('放弃未保存的更改？'),
              content: const Text('退出后刚才在画布上调整的位置和尺寸将不予保存。'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('继续编辑')),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.onExit();
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('确认放弃'),
                ),
              ],
            ),
          );
        },
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.draw_rounded, size: 20),
          const SizedBox(width: 8),
          const Text('自由画布工坊', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          // 页面切换 SegmentedButton
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(120),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPageTab('home', '首页'),
                _buildPageTab('guide', '导读'),
                _buildPageTab('thread', '帖子'),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.tune_rounded),
          tooltip: '工作区与排版参数调谐',
          onPressed: () => _showWorkbenchSettingsSheet(context),
        ),
        IconButton(
          icon: Icon(_showCenterDemo ? Icons.preview_rounded : Icons.preview_outlined),
          tooltip: _showCenterDemo ? '隐藏页面仿真预览' : '显示页面仿真预览',
          color: _showCenterDemo ? colorScheme.primary : null,
          onPressed: () {
            setState(() {
              _showCenterDemo = !_showCenterDemo;
              _autoAdjustAndCompact();
            });
          },
        ),
        // 隐藏/展开左侧卡片（宽版自适应预览）
        IconButton(
          icon: Icon(_hideLeftCards ? Icons.dock_rounded : Icons.view_sidebar_rounded),
          tooltip: _hideLeftCards ? '显示左侧卡片' : '隐藏左侧卡片 (预览自适应宽版)',
          color: _hideLeftCards ? Colors.orange : null,
          onPressed: () {
            setState(() {
              _hideLeftCards = !_hideLeftCards;
              if (!_showCenterDemo) _showCenterDemo = true;
            });
          },
        ),
        // 隐藏/展开右侧卡片（宽版自适应预览）
        IconButton(
          icon: Icon(_hideRightCards ? Icons.dock_rounded : Icons.view_sidebar_outlined),
          tooltip: _hideRightCards ? '显示右侧卡片' : '隐藏右侧卡片 (预览自适应宽版)',
          color: _hideRightCards ? Colors.orange : null,
          onPressed: () {
            setState(() {
              _hideRightCards = !_hideRightCards;
              if (!_showCenterDemo) _showCenterDemo = true;
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.restore_rounded),
          tooltip: '恢复默认布局',
          onPressed: _resetToDefault,
        ),
        IconButton(
          icon: const Icon(Icons.auto_fix_high_rounded),
          tooltip: '智能紧凑整理',
          onPressed: _compactLayout,
        ),
        IconButton(
          icon: const Icon(Icons.style_outlined),
          tooltip: '经典预设模版',
          onPressed: _showPresetPicker,
        ),
        const SizedBox(width: 6),
        // 右上角醒目保存按钮
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('保存布局', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            onPressed: _saveLayout,
          ),
        ),
      ],
      elevation: 1,
      backgroundColor: colorScheme.surfaceContainerLowest,
    );
  }

  /// 工作区参数与排版深度调谐面板（彻底融合 DIY 工作区功能，消除多套入口与数据分裂）
  void _showWorkbenchSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final theme = Theme.of(ctx);
            final colorScheme = theme.colorScheme;

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.78,
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4))],
              ),
              child: Column(
                children: [
                  // 顶部标题栏
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(50), width: 0.8)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.tune_rounded, size: 20, color: colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentPage == 'thread'
                                    ? '帖子工作台与排版参数'
                                    : (_currentPage == 'guide' ? '导读工作台排版参数' : '首页侧栏与流式参数'),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _currentPage == 'thread'
                                    ? '深度调谐助手分栏宽度、正文最大宽、正文字号与行间距'
                                    : (_currentPage == 'guide' ? '控制导读右侧工作台卡片清单与排版参数' : '调节左右侧栏展示与宽度配置'),
                                style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  // 内容主体
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      children: [
                        if (_currentPage == 'thread') ...[
                          // 帖子工作台参数
                          _buildSectionTitle(context, Icons.view_sidebar_rounded, '工作台分栏与正文约束'),
                          const SizedBox(height: 8),
                          Card(
                            elevation: 0,
                            color: colorScheme.surfaceContainerHighest.withAlpha(70),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
                            ),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  title: const Text('启用右侧工作台助手 (桌面端)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                  subtitle: const Text('关闭后详情页将隐藏右侧边栏卡片，正文居中沉浸浏览', style: TextStyle(fontSize: 11)),
                                  value: AppConfig.threadRightEnabled,
                                  onChanged: (val) {
                                    AppConfig.setThreadRightEnabled(val);
                                    setSheetState(() {});
                                    setState(() {});
                                  },
                                ),
                                const Divider(height: 1),
                                SwitchListTile(
                                  title: const Text('启用 PC 左侧版块导航分栏', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                  subtitle: const Text('在超宽屏下呈现左侧版块目录，方便帖间快速切换', style: TextStyle(fontSize: 11)),
                                  value: _showThreadForumPanel,
                                  onChanged: (val) {
                                    setState(() {
                                      _showThreadForumPanel = val;
                                      _autoAdjustAndCompact();
                                    });
                                    AppConfig.setThreadLeftEnabled(val);
                                    setSheetState(() {});
                                  },
                                ),
                                const Divider(height: 1),
                                // 助手栏宽度滑块
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('工作台助手宽度', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                          Text('${AppConfig.threadRightWidth.round()} px', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                                        ],
                                      ),
                                      Slider(
                                        value: AppConfig.threadRightWidth.clamp(240.0, 480.0),
                                        min: 240.0,
                                        max: 480.0,
                                        divisions: 24,
                                        label: '${AppConfig.threadRightWidth.round()} px',
                                        onChanged: (val) {
                                          AppConfig.updateThreadRightWidth(val);
                                          setSheetState(() {});
                                        },
                                        onChangeEnd: (val) {
                                          AppConfig.setThreadRightWidth(val);
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                // 正文最大保护宽度滑块
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('正文阅读区最大限制宽度', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                          Text(
                                            AppConfig.threadContentMaxWidth <= 0 ? '不限制 (全宽)' : '${AppConfig.threadContentMaxWidth.round()} px',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                          ),
                                        ],
                                      ),
                                      Slider(
                                        value: AppConfig.threadContentMaxWidth.clamp(600.0, 1600.0),
                                        min: 600.0,
                                        max: 1600.0,
                                        divisions: 20,
                                        label: '${AppConfig.threadContentMaxWidth.round()} px',
                                        onChanged: (val) {
                                          AppConfig.setThreadContentMaxWidth(val);
                                          setSheetState(() {});
                                        },
                                        onChangeEnd: (val) {
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 正文阅读排版调谐
                          _buildSectionTitle(context, Icons.format_size_rounded, '正文排版与阅读舒适度'),
                          const SizedBox(height: 8),
                          Card(
                            elevation: 0,
                            color: colorScheme.surfaceContainerHighest.withAlpha(70),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('正文字号大小', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      Text('${AppConfig.threadReaderFontSize.toStringAsFixed(1)} pt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                                    ],
                                  ),
                                  Slider(
                                    value: AppConfig.threadReaderFontSize.clamp(12.0, 24.0),
                                    min: 12.0,
                                    max: 24.0,
                                    divisions: 24,
                                    label: '${AppConfig.threadReaderFontSize.toStringAsFixed(1)} pt',
                                    onChanged: (val) {
                                      AppConfig.setThreadReaderFontSize(val);
                                      setSheetState(() {});
                                    },
                                    onChangeEnd: (_) => setState(() {}),
                                  ),
                                  const Divider(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('段落行间距', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      Text('${AppConfig.threadReaderLineHeight.toStringAsFixed(2)}x', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                                    ],
                                  ),
                                  Slider(
                                    value: AppConfig.threadReaderLineHeight.clamp(1.2, 2.4),
                                    min: 1.2,
                                    max: 2.4,
                                    divisions: 12,
                                    label: '${AppConfig.threadReaderLineHeight.toStringAsFixed(2)}x',
                                    onChanged: (val) {
                                      AppConfig.setThreadReaderLineHeight(val);
                                      setSheetState(() {});
                                    },
                                    onChangeEnd: (_) => setState(() {}),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 当前工作台卡片清单
                          _buildSectionTitle(context, Icons.dashboard_customize_rounded, '当前工作台卡片清单 (按上至下排列)'),
                          const SizedBox(height: 8),
                          _buildWorkbenchCardList(context, setSheetState),
                        ] else if (_currentPage == 'guide') ...[
                          _buildSectionTitle(context, Icons.dashboard_customize_rounded, '导读右侧工作台卡片清单'),
                          const SizedBox(height: 8),
                          _buildWorkbenchCardList(context, setSheetState),
                        ] else ...[
                          // 首页参数
                          _buildSectionTitle(context, Icons.view_quilt_rounded, '首页侧栏卡片显示与宽度'),
                          const SizedBox(height: 8),
                          Card(
                            elevation: 0,
                            color: colorScheme.surfaceContainerHighest.withAlpha(70),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
                            ),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  title: const Text('显示左侧分栏卡片', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                  value: AppConfig.homeShowLeftCards,
                                  onChanged: (val) {
                                    AppConfig.setHomeShowLeftCards(val);
                                    setSheetState(() {});
                                    setState(() {});
                                  },
                                ),
                                const Divider(height: 1),
                                SwitchListTile(
                                  title: const Text('显示右侧分栏卡片', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                  value: AppConfig.homeShowRightCards,
                                  onChanged: (val) {
                                    AppConfig.setHomeShowRightCards(val);
                                    setSheetState(() {});
                                    setState(() {});
                                  },
                                ),
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('左侧分栏宽度', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                          Text('${AppConfig.homeLeftSidebarWidth.round()} px', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                                        ],
                                      ),
                                      Slider(
                                        value: AppConfig.homeLeftSidebarWidth.clamp(200.0, 420.0),
                                        min: 200.0,
                                        max: 420.0,
                                        divisions: 22,
                                        label: '${AppConfig.homeLeftSidebarWidth.round()} px',
                                        onChanged: (val) {
                                          AppConfig.updateHomeLeftSidebarWidth(val);
                                          setSheetState(() {});
                                        },
                                        onChangeEnd: (val) {
                                          AppConfig.setHomeLeftSidebarWidth(val);
                                          setState(() {});
                                        },
                                      ),
                                      const Divider(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('右侧分栏宽度', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                          Text('${AppConfig.homeRightSidebarWidth.round()} px', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                                        ],
                                      ),
                                      Slider(
                                        value: AppConfig.homeRightSidebarWidth.clamp(200.0, 420.0),
                                        min: 200.0,
                                        max: 420.0,
                                        divisions: 22,
                                        label: '${AppConfig.homeRightSidebarWidth.round()} px',
                                        onChanged: (val) {
                                          AppConfig.updateHomeRightSidebarWidth(val);
                                          setSheetState(() {});
                                        },
                                        onChangeEnd: (val) {
                                          AppConfig.setHomeRightSidebarWidth(val);
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionTitle(BuildContext context, IconData icon, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildWorkbenchCardList(BuildContext context, StateSetter setSheetState) {
    final colorScheme = Theme.of(context).colorScheme;
    final sortedItems = List<DashboardGridItem>.from(_items)
      ..sort((a, b) => a.row.compareTo(b.row));

    if (sortedItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withAlpha(60),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('当前暂无工作台卡片，可从底部卡片库拖入卡片', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(60),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: sortedItems.length,
        onReorder: (oldIdx, newIdx) {
          if (newIdx > oldIdx) newIdx -= 1;
          final moved = sortedItems.removeAt(oldIdx);
          sortedItems.insert(newIdx, moved);
          int r = 0;
          for (final it in sortedItems) {
            it.col = 8;
            it.colSpan = 4;
            it.row = r;
            r += it.rowSpan;
          }
          setState(() {
            _items = sortedItems;
            _autoAdjustAndCompact();
          });
          setSheetState(() {});
        },
        itemBuilder: (ctx, idx) {
          final item = sortedItems[idx];
          final def = CardRegistry.get(item.cardType);

          return ListTile(
            key: ValueKey(item.id),
            leading: Icon(def.icon, color: colorScheme.primary, size: 20),
            title: Text(def.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('${def.description} · ${item.rowSpan}行高', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                  tooltip: '移除此卡片',
                  onPressed: () {
                    setState(() {
                      _items.removeWhere((it) => it.id == item.id);
                      _autoAdjustAndCompact();
                    });
                    setSheetState(() {});
                  },
                ),
                const Icon(Icons.drag_handle_rounded, size: 18, color: Colors.grey),
              ],
            ),
          );
        },
      ),
    );
  }



  Widget _buildPageTab(String id, String label) {
    final isSelected = _currentPage == id;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _switchPage(id),
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
    final showHandles = isSelected || isHovered || (_resizeStartGlobalPos != null && _selectedItemId == item.id);

    // 外扩命中边缘：严格限制在 4px（<_spacing / 2 = 5px），保证相邻卡片包围盒 100% 互斥无交集，彻底根除交叠引发的 MouseTracker 翻转死循环
    const double handleHitMargin = 4.0;

    final cardLeft = _padding.left + item.col * (cellWidth + _spacing);
    final cardTop = _padding.top + _topHeaderOffset + item.row * (_cellHeight + _spacing);
    final cardWidth = item.colSpan * cellWidth + (item.colSpan - 1) * _spacing;
    final cardHeight = item.rowSpan * _cellHeight + (item.rowSpan - 1) * _spacing;

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
                  onPanStart: (details) => _onCardDragStart(item, details.globalPosition),
                  onPanUpdate: (details) => _onCardDragUpdate(item, details.globalPosition, cellWidth, totalCols),
                  onPanEnd: (_) => _onCardDragEnd(item),
                  onPanCancel: () => _onCardDragCancel(),
                  // 2. 移动端/触屏长按拖拽
                  onLongPressStart: (details) => _onCardDragStart(item, details.globalPosition),
                  onLongPressMoveUpdate: (details) => _onCardDragUpdate(item, details.globalPosition, cellWidth, totalCols),
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
                                  ? Border.all(color: colorScheme.primary, width: 2)
                                  : (isHovered
                                      ? Border.all(color: colorScheme.primary.withAlpha(160), width: 1.5)
                                      : Border.all(color: Colors.transparent, width: 0)),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: colorScheme.primary.withAlpha(50),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : (isHovered
                                      ? [
                                          BoxShadow(
                                            color: colorScheme.primary.withAlpha(25),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: DashboardCardFactory.buildCard(
                                item: item,
                                isPreview: true, // 编辑模式下统一展示展示用数据
                              ),
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
                                    final idx = _items.indexWhere((x) => x.id == item.id);
                                    if (idx != -1) _items[idx] = updated;
                                    _autoAdjustAndCompact(activeItem: _items[idx]);
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
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                              ),
                              child: const Icon(Icons.settings_outlined, size: 14),
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
                                  ? colorScheme.surfaceContainerHighest.withAlpha(240)
                                  : colorScheme.surfaceContainerHighest.withAlpha(180),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: (isSelected || isHovered) ? colorScheme.error : colorScheme.outline,
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
                                onTap: () => _showQuickSizeDialog(context, item, def, totalCols),
                                borderRadius: BorderRadius.circular(12),
                                child: Tooltip(
                                  message: '点击快捷修改尺寸 (${item.colSpan}×${item.rowSpan})',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? colorScheme.primaryContainer
                                          : colorScheme.surfaceContainerHighest.withAlpha(220),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? colorScheme.primary
                                            : colorScheme.outlineVariant.withAlpha(140),
                                        width: 1.0,
                                      ),
                                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.tune_rounded,
                                          size: 11,
                                          color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          _isWorkbenchMode ? '4×${item.rowSpan}' : '${item.colSpan}×${item.rowSpan}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 1),
                                        Icon(
                                          Icons.arrow_drop_down_rounded,
                                          size: 13,
                                          color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
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
                        final totalDelta = details.globalPosition - _resizeStartGlobalPos!;
                        final bottomAnchorRow = _resizeStartRow + _resizeStartRowSpan;
                        final deltaRows = (totalDelta.dy / (_cellHeight + _spacing)).round();
                        final targetRow = (_resizeStartRow + deltaRows).clamp(0, bottomAnchorRow - def.minRowSpan);
                        final targetRowSpan = (bottomAnchorRow - targetRow).clamp(def.minRowSpan, def.maxRowSpan);
                        final newRow = bottomAnchorRow - targetRowSpan;
                        if (newRow != item.row || targetRowSpan != item.rowSpan) {
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
                            color: isSelected ? colorScheme.primary : colorScheme.primary.withAlpha(140),
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
                        final totalDelta = details.globalPosition - _resizeStartGlobalPos!;
                        final deltaRows = (totalDelta.dy / (_cellHeight + _spacing)).round();
                        final newRowSpan = (_resizeStartRowSpan + deltaRows).clamp(def.minRowSpan, def.maxRowSpan);
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
                            color: isSelected ? colorScheme.primary : colorScheme.primary.withAlpha(140),
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
                        final totalDelta = details.globalPosition - _resizeStartGlobalPos!;
                        final rightAnchorCol = _resizeStartCol + _resizeStartColSpan;
                        final deltaCols = (totalDelta.dx / (cellWidth + _spacing)).round();
                        final minCol = _getMinColFor(item);
                        final targetCol = (_resizeStartCol + deltaCols).clamp(minCol, rightAnchorCol - def.minColSpan);
                        final targetColSpan = (rightAnchorCol - targetCol).clamp(def.minColSpan, def.maxColSpan);
                        final newCol = rightAnchorCol - targetColSpan;
                        if (newCol != item.col || targetColSpan != item.colSpan) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            item.col = newCol;
                            item.colSpan = targetColSpan;
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
                          width: 3.5,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isSelected ? colorScheme.primary : colorScheme.primary.withAlpha(140),
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
                        final totalDelta = details.globalPosition - _resizeStartGlobalPos!;
                        final deltaCols = (totalDelta.dx / (cellWidth + _spacing)).round();
                        final maxAllowed = _getMaxColSpanFor(item);
                        final newColSpan = (_resizeStartColSpan + deltaCols).clamp(def.minColSpan, math.max<int>(def.minColSpan, maxAllowed)).toInt();
                        if (newColSpan != item.colSpan) {
                          HapticFeedback.selectionClick();
                          setState(() => item.colSpan = newColSpan);
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
                          width: 3.5,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isSelected ? colorScheme.primary : colorScheme.primary.withAlpha(140),
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
                        final totalDelta = details.globalPosition - _resizeStartGlobalPos!;
                        // 垂直 Y
                        final bottomAnchorRow = _resizeStartRow + _resizeStartRowSpan;
                        final deltaRows = (totalDelta.dy / (_cellHeight + _spacing)).round();
                        final targetRow = (_resizeStartRow + deltaRows).clamp(0, bottomAnchorRow - def.minRowSpan);
                        final targetRowSpan = (bottomAnchorRow - targetRow).clamp(def.minRowSpan, def.maxRowSpan);
                        final newRow = bottomAnchorRow - targetRowSpan;
                        // 水平 X
                        final rightAnchorCol = _resizeStartCol + _resizeStartColSpan;
                        final deltaCols = (totalDelta.dx / (cellWidth + _spacing)).round();
                        final minCol = _getMinColFor(item);
                        final targetCol = (_resizeStartCol + deltaCols).clamp(minCol, rightAnchorCol - def.minColSpan);
                        final targetColSpan = (rightAnchorCol - targetCol).clamp(def.minColSpan, def.maxColSpan);
                        final newCol = rightAnchorCol - targetColSpan;

                        if (newRow != item.row || targetRowSpan != item.rowSpan || newCol != item.col || targetColSpan != item.colSpan) {
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
                        setState(() => _autoAdjustAndCompact(activeItem: item));
                      },
                      onPanCancel: () {
                        _resizeStartGlobalPos = null;
                        setState(() => _autoAdjustAndCompact(activeItem: item));
                      },
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? colorScheme.primary : colorScheme.primary.withAlpha(160),
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
                        final totalDelta = details.globalPosition - _resizeStartGlobalPos!;
                        // 垂直 Y
                        final bottomAnchorRow = _resizeStartRow + _resizeStartRowSpan;
                        final deltaRows = (totalDelta.dy / (_cellHeight + _spacing)).round();
                        final targetRow = (_resizeStartRow + deltaRows).clamp(0, bottomAnchorRow - def.minRowSpan);
                        final targetRowSpan = (bottomAnchorRow - targetRow).clamp(def.minRowSpan, def.maxRowSpan);
                        final newRow = bottomAnchorRow - targetRowSpan;
                        // 水平 X
                        final deltaCols = (totalDelta.dx / (cellWidth + _spacing)).round();
                        final maxAllowed = _getMaxColSpanFor(item);
                        final newColSpan = (_resizeStartColSpan + deltaCols).clamp(def.minColSpan, math.max<int>(def.minColSpan, maxAllowed)).toInt();

                        if (newRow != item.row || targetRowSpan != item.rowSpan || newColSpan != item.colSpan) {
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
                        setState(() => _autoAdjustAndCompact(activeItem: item));
                      },
                      onPanCancel: () {
                        _resizeStartGlobalPos = null;
                        setState(() => _autoAdjustAndCompact(activeItem: item));
                      },
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? colorScheme.primary : colorScheme.primary.withAlpha(160),
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
                        final totalDelta = details.globalPosition - _resizeStartGlobalPos!;
                        // 垂直 Y
                        final deltaRows = (totalDelta.dy / (_cellHeight + _spacing)).round();
                        final newRowSpan = (_resizeStartRowSpan + deltaRows).clamp(def.minRowSpan, def.maxRowSpan);
                        // 水平 X
                        final rightAnchorCol = _resizeStartCol + _resizeStartColSpan;
                        final deltaCols = (totalDelta.dx / (cellWidth + _spacing)).round();
                        final minCol = _getMinColFor(item);
                        final targetCol = (_resizeStartCol + deltaCols).clamp(minCol, rightAnchorCol - def.minColSpan);
                        final targetColSpan = (rightAnchorCol - targetCol).clamp(def.minColSpan, def.maxColSpan);
                        final newCol = rightAnchorCol - targetColSpan;

                        if (newRowSpan != item.rowSpan || newCol != item.col || targetColSpan != item.colSpan) {
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
                        setState(() => _autoAdjustAndCompact(activeItem: item));
                      },
                      onPanCancel: () {
                        _resizeStartGlobalPos = null;
                        setState(() => _autoAdjustAndCompact(activeItem: item));
                      },
                      child: Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? colorScheme.primary : colorScheme.primary.withAlpha(160),
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
                        final totalDelta = details.globalPosition - _resizeStartGlobalPos!;
                        final deltaRows = (totalDelta.dy / (_cellHeight + _spacing)).round();
                        final deltaCols = (totalDelta.dx / (cellWidth + _spacing)).round();
                        final newRowSpan = (_resizeStartRowSpan + deltaRows).clamp(def.minRowSpan, def.maxRowSpan);
                        final maxAllowed = _getMaxColSpanFor(item);
                        final newColSpan = (_resizeStartColSpan + deltaCols).clamp(def.minColSpan, math.max<int>(def.minColSpan, maxAllowed)).toInt();

                        if (newRowSpan != item.rowSpan || newColSpan != item.colSpan) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            item.rowSpan = newRowSpan;
                            item.colSpan = newColSpan;
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
                          width: 8.5,
                          height: 8.5,
                          decoration: BoxDecoration(
                            color: isSelected ? colorScheme.primary : Colors.white,
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
    final availableCategories = DashboardCardCategory.values.where(
      (cat) => pageDefs.any((d) => d.category == cat),
    ).toList();

    final activeCategory = (_selectedCategory != null && availableCategories.contains(_selectedCategory))
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
            top: BorderSide(color: colorScheme.outlineVariant.withAlpha(80), width: 1.0),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.widgets_outlined, size: 16, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '卡片库已收起 (共 ${pageDefs.length} 张可用卡片)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
              label: const Text('展开卡片库', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
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
          top: BorderSide(color: colorScheme.outlineVariant.withAlpha(60), width: 0.8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动提示条与分类过滤
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            child: Row(
              children: [
                const Icon(Icons.touch_app_rounded, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                const Text(
                  '拖拽或长按卡片往画布添加 (松手自动吸附对齐)',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _isDockCollapsed = true),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(140),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.outlineVariant.withAlpha(80)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: colorScheme.primary),
                        const SizedBox(width: 2),
                        Text('收起卡片库', style: TextStyle(fontSize: 10.5, color: colorScheme.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // 分类筛选 chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryFilter(null, '全部 (${pageDefs.length})'),
                      ...availableCategories.map(
                        (c) => _buildCategoryFilter(
                          c,
                          '${c.label} (${pageDefs.where((d) => d.category == c).length})',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
                      backgroundColor: colorScheme.surfaceContainerHighest.withAlpha(120),
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
                            .clamp(0.0, _dockScrollCtrl.position.maxScrollExtent);
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
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (context, idx) {
                            final def = filteredDefs[idx];

                            return Draggable<String>(
                              data: def.cardType,
                              feedback: Material(
                                color: Colors.transparent,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(def.icon, size: 18, color: Colors.white),
                                      const SizedBox(width: 6),
                                      Text(
                                        def.name,
                                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
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
                      backgroundColor: colorScheme.surfaceContainerHighest.withAlpha(120),
                      padding: const EdgeInsets.all(4),
                    ),
                    onPressed: () {
                      _dockScrollCtrl.animateTo(
                        math.min(_dockScrollCtrl.position.maxScrollExtent, _dockScrollCtrl.offset + 260.0),
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
        label: Text(label, style: TextStyle(fontSize: 10.5, color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface)),
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
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(60), width: 0.8),
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
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            _currentPage == 'guide' ? Icons.explore_outlined : Icons.table_chart_rounded,
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
          Icon(Icons.keyboard_double_arrow_right_rounded, size: 15, color: colorScheme.outline),
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
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
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
            icon: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 15),
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
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
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
            icon: const Icon(Icons.keyboard_double_arrow_left_rounded, size: 15),
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
  // 中心区域真实页面流高保真演示 (WYSIWYG 真正预览)
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
            // 顶部高保真原生 AppBar 样式条 (1:1 对齐真实桌面运行界面)
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _currentPage == 'home'
                        ? '苦力怕论坛'
                        : _currentPage == 'thread'
                            ? '帖子详情'
                            : '导读',
                    style: TextStyle(
                      fontSize: _currentPage == 'home' ? 16 : 14.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  // 1:1 原生功能按键群
                  if (_currentPage == 'thread') ...[
                    Icon(Icons.vertical_align_bottom_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.chrome_reader_mode_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.search_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.tune_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.refresh_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.more_vert_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                  ] else if (_currentPage == 'home') ...[
                    Icon(Icons.refresh_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.search_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.tune_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.view_quilt_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.smart_toy_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.notifications_none_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.settings_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.mail_outline_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                  ] else ...[
                    Icon(Icons.search_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.tune_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Icon(Icons.refresh_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                  ],
                  // 分隔线
                  Container(
                    width: 1,
                    height: 14,
                    color: colorScheme.outlineVariant.withAlpha(80),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  // 控制：快捷收起/展开左侧卡片或版块视图
                  if (_currentPage == 'thread')
                    IconButton(
                      icon: Icon(_showThreadForumPanel ? Icons.view_sidebar_rounded : Icons.view_sidebar_outlined, size: 16),
                      tooltip: _showThreadForumPanel ? '收起版块列表 (正文流自适应展开)' : '展开版块列表 (1:1 原生版块分栏)',
                      color: _showThreadForumPanel ? colorScheme.primary : Colors.orange,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () {
                        setState(() {
                          _showThreadForumPanel = !_showThreadForumPanel;
                          _autoAdjustAndCompact();
                        });
                      },
                    )
                  else
                    IconButton(
                      icon: Icon(_hideLeftCards ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded, size: 16),
                      tooltip: _hideLeftCards ? '展开左侧卡片' : '收起左侧卡片 (预览自适应宽版)',
                      color: _hideLeftCards ? Colors.orange : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () {
                        setState(() => _hideLeftCards = !_hideLeftCards);
                      },
                    ),
                  // 控制：全宽阅读沉浸流切换
                  IconButton(
                    icon: Icon((_hideLeftCards && _hideRightCards) ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, size: 16),
                    tooltip: (_hideLeftCards && _hideRightCards) ? '退出全宽阅读流' : '双侧全收起 (纯净全宽预览)',
                    color: (_hideLeftCards && _hideRightCards) ? Colors.orange : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () {
                      setState(() {
                        if (_hideLeftCards && _hideRightCards) {
                          _hideLeftCards = false;
                          _hideRightCards = false;
                        } else {
                          _hideLeftCards = true;
                          _hideRightCards = true;
                        }
                      });
                    },
                  ),
                  // 控制：隐藏预览
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 15),
                    tooltip: '隐藏页面流预览',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () {
                      setState(() {
                        _showCenterDemo = false;
                        _autoAdjustAndCompact();
                      });
                    },
                  ),
                ],
              ),
            ),
            // 主体演示内容 (IgnorePointer 避免拦截底下的手势)
            Expanded(
              child: IgnorePointer(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  child: _currentPage == 'home'
                      ? _buildHomeFeedDemo(context)
                      : _currentPage == 'thread'
                          ? _buildThreadFeedDemo(context)
                          : _buildGuideFeedDemo(context),
                ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Positioned(
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
            // 顶部真实版块导航条 (1:1 对齐 PC 桌面 ThreadListPage 标题栏)
            // 顶部真实版块导航条 (1:1 对齐 media_1790393423740.png: ← 闲聊讨论 ★ ⊞ 🔍 ⟳ ✎ ⇤)
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.arrow_back_rounded, size: 16, color: colorScheme.onSurface),
                  const SizedBox(width: 8),
                  const Text(
                    '闲聊讨论',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Icon(Icons.grid_view_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Icon(Icons.search_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Icon(Icons.refresh_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_note_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Container(
                    width: 1,
                    height: 14,
                    color: colorScheme.outlineVariant.withAlpha(80),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_double_arrow_left_rounded, size: 16),
                    tooltip: '收起版块列表 (正文流自适应展开为 8 列宽版)',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () {
                      setState(() {
                        _showThreadForumPanel = false;
                        _autoAdjustAndCompact();
                      });
                    },
                  ),
                ],
              ),
            ),
            // 版块内容预览（1:1 对齐 media_1790393423740.png 真实帖子列表）
            Expanded(
              child: IgnorePointer(
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(8),
                  children: [
                    // 1. 二次元横幅 (1:1 对齐 media_1790399424134.png 顶部特色插画 Banner)
                    Container(
                      height: 92,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF81D4FA), Color(0xFFF48FB1), Color(0xFFFFCCBC)],
                        ),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Opacity(
                              opacity: 0.88,
                              child: Image.network(
                                'https://klpbbs.com/template/comiis_mi/img/banner.jpg',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF2E3824), Color(0xFF4A6572), Color(0xFF2C3E50)],
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.auto_awesome_rounded, size: 36, color: Colors.white30),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 2. 今日 / 主题 / 排名 统计栏 (1:1 对齐 media_1790399424134.png)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withAlpha(70),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: Colors.green.withAlpha(30), borderRadius: BorderRadius.circular(3)),
                            child: const Text('今日 7', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          Text('|', style: TextStyle(fontSize: 10, color: colorScheme.outlineVariant)),
                          const SizedBox(width: 6),
                          Text('主题 37420', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Text('|', style: TextStyle(fontSize: 10, color: colorScheme.outlineVariant)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(color: Colors.amber.withAlpha(30), borderRadius: BorderRadius.circular(3)),
                            child: const Text('排名 2', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                          ),
                          const Spacer(),
                          Icon(Icons.help_outline_rounded, size: 12, color: colorScheme.outline),
                          const SizedBox(width: 2),
                          Text('积分规则', style: TextStyle(fontSize: 9.5, color: colorScheme.outline)),
                          const SizedBox(width: 6),
                          Icon(Icons.keyboard_arrow_up_rounded, size: 13, color: colorScheme.outline),
                          Text('收起导览', style: TextStyle(fontSize: 9.5, color: colorScheme.outline)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 3. 版主名单行 (1:1 对齐 media_1790399424134.png)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, size: 13, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '版主: 搬运酱, 往来无白丁, 欢乐的东海, Dreeam, HaPi_r, htdashen, 小雪绒, n00b11m, 宣传部',
                              style: TextStyle(fontSize: 9.5, color: colorScheme.onSurfaceVariant.withAlpha(200), height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 4. 苦力怕论坛·闲聊讨论 欢迎大卡片
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colorScheme.primary,
                            colorScheme.primary.withAlpha(210),
                            colorScheme.surfaceContainerHighest,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: colorScheme.onPrimary,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Center(
                                        child: Text('K', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text('苦力怕论坛', style: TextStyle(fontSize: 9.5, color: Colors.white70, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  '闲聊讨论',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                                ),
                                const SizedBox(height: 2),
                                const Text('欢迎来到闲聊讨论版块!', style: TextStyle(fontSize: 9.5, color: Colors.white60)),
                                const SizedBox(height: 6),
                                Text('✦ 畅所欲言 友好交流!', style: TextStyle(fontSize: 9, color: colorScheme.onPrimary.withAlpha(220))),
                                Text('✦ 调侃心情 增长见识!', style: TextStyle(fontSize: 9, color: colorScheme.onPrimary.withAlpha(220))),
                                Text('✦ 游戏之旅 孤岛同行!', style: TextStyle(fontSize: 9, color: colorScheme.onPrimary.withAlpha(220))),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Container(
                              height: 82,
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white12, width: 0.6),
                              ),
                              child: const Stack(
                                children: [
                                  Center(
                                    child: Icon(Icons.people_alt_rounded, size: 36, color: Colors.white30),
                                  ),
                                  Positioned(
                                    bottom: 4,
                                    left: 0,
                                    right: 0,
                                    child: Text('Alex & Steve', textAlign: TextAlign.center, style: TextStyle(fontSize: 8, color: Colors.white38)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 5. 快捷 6 按钮组 (2 列 x 3 行，1:1 对齐 media_1790399424134.png)
                    Row(
                      children: [
                        Expanded(
                          child: _buildLeftActionCard(
                            context: context,
                            title: '【必读】自律公约',
                            desc: '多看版规不吃亏~点击此处阅读闲聊讨论板块自律公约',
                            headerColor: const Color(0xFFE53935),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildLeftActionCard(
                            context: context,
                            title: '【申诉】申诉&报备',
                            desc: '点击这里申请高亮/关闭主题宣传网站/QQ群需点此进行报备',
                            headerColor: const Color(0xFFD81B60),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildLeftActionCard(
                            context: context,
                            title: '【引导】资源下载',
                            desc: '想下载国际版MC/行为包/模组/光影/地图...? 你应该点击这里!',
                            headerColor: const Color(0xFFF57C00),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildLeftActionCard(
                            context: context,
                            title: '【引导】悬赏问答',
                            desc: '你有问题？点击进入「悬赏问答」版块~本版可求助/给钱发帖下载',
                            headerColor: const Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildLeftActionCard(
                            context: context,
                            title: '【Q群】论坛内群',
                            desc: '想为了营造良好的交流环境，点此论坛内群概况及加入方式',
                            headerColor: const Color(0xFFF9A825),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildLeftActionCard(
                            context: context,
                            title: '【发帖】点我发帖',
                            desc: '点击此处在本版块发表帖子',
                            headerColor: const Color(0xFF1E88E5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 6. 分类筛选胶囊行 (1:1 对齐 media_1790399424134.png)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildDemoFilterPill(context, '全部', isSelected: true),
                          const SizedBox(width: 4),
                          _buildDemoFilterPill(context, '闲聊', isSelected: false),
                          const SizedBox(width: 4),
                          _buildDemoFilterPill(context, '展示', isSelected: false),
                          const SizedBox(width: 4),
                          _buildDemoFilterPill(context, '预告', isSelected: false),
                          const SizedBox(width: 4),
                          _buildDemoFilterPill(context, '辩说', isSelected: false),
                          const SizedBox(width: 4),
                          _buildDemoFilterPill(context, '其他', isSelected: false),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 7. 排序胶囊行 (1:1 对齐 media_1790399424134.png)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildDemoFilterPill(context, '✓ 默认排序', isSelected: true),
                          const SizedBox(width: 4),
                          _buildDemoFilterPill(context, '最新回复', isSelected: false),
                          const SizedBox(width: 4),
                          _buildDemoFilterPill(context, '最新发布', isSelected: false),
                          const SizedBox(width: 4),
                          _buildDemoFilterPill(context, '最多回复', isSelected: false),
                          const SizedBox(width: 4),
                          _buildDemoFilterPill(context, '最多浏览', isSelected: false),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 8. 置顶推荐 (5) (1:1 对齐 media_1790399424134.png)
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withAlpha(40),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.push_pin_rounded, size: 13, color: colorScheme.primary),
                              const SizedBox(width: 4),
                              const Text('置顶推荐 (5)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: colorScheme.outline),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _buildDemoStickyItem('置顶', '关于近期部分作品使用付费下载的第三方链接的通告', Colors.blue),
                          _buildDemoStickyItem('置顶', '【全站 | 长期】KLPBBS 人才引进计划', Colors.redAccent),
                          _buildDemoStickyItem('置顶', '【2022-11-30】苦力怕论坛总规', Colors.green),
                          _buildDemoStickyItem('置顶', '「闲聊讨论」版块 非MC内容闲聊榜', Colors.orange),
                          _buildDemoStickyItem('置顶', '“闲聊讨论”版块申诉&报备帖', Colors.blue),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 首页 Feed 流高保真仿真（1:1 对齐 media_1790393468984.png 真实应用表现）
  /// 首页 Feed 流高保真仿真（1:1 对齐真实 HomePage 桌面端中心流）
  Widget _buildHomeFeedDemo(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 原版经典全站小喇叭公告栏 (1:1 对齐真实界面)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(50),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.campaign_rounded, size: 16, color: Colors.orange),
                      const SizedBox(width: 6),
                      const Text('小喇叭', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('✎ 发布', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withAlpha(200))),
                      const SizedBox(width: 10),
                      Text('⟳ 刷新中', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withAlpha(200))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 小喇叭滚动信息骨架与文字
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withAlpha(120),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 9,
                              width: 140,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withAlpha(140),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              height: 7,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withAlpha(70),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 2. 真实全站大盘统计看板 (1:1 对齐 今日 76 | 昨日 221 | 帖子 10314648 | 会员 2327659)
            const SiteStatsCard(
              stats: SiteStats(
                todayPosts: 76,
                yesterdayPosts: 221,
                totalPosts: 10314648,
                totalMembers: 2327659,
              ),
            ),
            const SizedBox(height: 12),

            // 3. 真实论坛版块分类标题与过滤 Chips
            Row(
              children: [
                Container(width: 3.5, height: 14, color: colorScheme.primary, margin: const EdgeInsets.only(right: 6)),
                const Text('论坛版块分类', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('展开全部分区 ▾', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                const Spacer(),
                Text('★ 收藏 1   全部分区 >', style: TextStyle(fontSize: 11, color: colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildDemoFilterPill(context, '✓ 我关注的', isSelected: true),
                  const SizedBox(width: 6),
                  _buildDemoFilterPill(context, '综合分区', isSelected: false),
                  const SizedBox(width: 6),
                  _buildDemoFilterPill(context, '灵感交流', isSelected: false),
                  const SizedBox(width: 6),
                  _buildDemoFilterPill(context, 'BE资源分区', isSelected: false),
                  const SizedBox(width: 6),
                  _buildDemoFilterPill(context, 'JE资源分区', isSelected: false),
                  const SizedBox(width: 6),
                  _buildDemoFilterPill(context, '多人游戏', isSelected: false),
                  const SizedBox(width: 6),
                  _buildDemoFilterPill(context, '其他分区', isSelected: false),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 4. 关注的版块卡片 (闲聊讨论 今日 7)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant.withAlpha(40)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  const Text('闲聊讨论', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('今日 7', style: TextStyle(fontSize: 10, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 5. 推荐轮播卡片 (_RecommendCarousel 1:1 风格)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withAlpha(35),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colorScheme.primary.withAlpha(90), width: 0.8),
                        ),
                        child: Text('推荐', style: TextStyle(fontSize: 9.5, color: colorScheme.primary, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '【非官方活动】【发帖有奖】BE附加包板块·老友回归，新人启程',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('YesNewBee · 2026-11-4 17:00', style: TextStyle(fontSize: 10.5, color: Colors.white.withAlpha(160))),
                  const SizedBox(height: 8),
                  // 轮播点
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 14, height: 3.5, decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 4),
                      Container(width: 3.5, height: 3.5, decoration: const BoxDecoration(color: Colors.white30, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Container(width: 3.5, height: 3.5, decoration: const BoxDecoration(color: Colors.white30, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Container(width: 3.5, height: 3.5, decoration: const BoxDecoration(color: Colors.white30, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Container(width: 3.5, height: 3.5, decoration: const BoxDecoration(color: Colors.white30, shape: BoxShape.circle)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 6. 推荐分区头
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '推荐',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '下拉刷新',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withAlpha(180)),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 7. 双列网格推荐帖子卡片 (1:1 真实 HomePage)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 卡片 1
                Expanded(
                  child: Container(
                    height: 110,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(45),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.outlineVariant.withAlpha(45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber.withAlpha(30),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text('闲聊讨论', style: TextStyle(fontSize: 9, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Expanded(
                          child: Text(
                            '【非官方活动】【发帖有奖】BE附加包板块·老友回归，新人启程',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 卡片 2 (带缩略图)
                Expanded(
                  child: Container(
                    height: 110,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(45),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.outlineVariant.withAlpha(45)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
                          ),
                          child: Icon(Icons.image_outlined, size: 24, color: colorScheme.outline),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withAlpha(30),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text('闲聊讨论', style: TextStyle(fontSize: 9, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(height: 4),
                              const Expanded(
                                child: Text(
                                  '【喜报】恭喜支持成就回归',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),

        // 8. 右下角悬浮发帖按钮 (1:1 对齐 PC 桌面端 HomePage)
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_rounded, size: 16, color: colorScheme.onPrimary),
                const SizedBox(width: 6),
                Text(
                  '发帖',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 帖子工作台 Feed 流高保真仿真（1:1 对齐 media_1790393423740.png 真实详情）
  Widget _buildThreadFeedDemo(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 0. 顶部真实面包屑导航
        Row(
          children: [
            Icon(Icons.home_outlined, size: 14, color: colorScheme.outline),
            const SizedBox(width: 4),
            Text('论坛', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 13, color: colorScheme.outline),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('闲聊讨论', style: TextStyle(fontSize: 10, color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 1. 分类标签
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colorScheme.primary, width: 0.8),
              ),
              child: Text('[闲聊]', style: TextStyle(fontSize: 10, color: colorScheme.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // 2. 帖子主标题 (1:1 真实标题)
        Text(
          '【非官方活动】【发帖有奖】BE附加包板块·老友回归，新人启程',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),

        // 3. 发布时间与阅读统计
        Row(
          children: [
            Icon(Icons.access_time_rounded, size: 13, color: colorScheme.outline),
            const SizedBox(width: 4),
            Text('发布 2026-11-4 17:00:00   最近回复 7 天前', style: TextStyle(fontSize: 10, color: colorScheme.outline)),
            const Spacer(),
            Icon(Icons.visibility_outlined, size: 13, color: colorScheme.outline),
            const SizedBox(width: 3),
            Text('613 浏览 · 15 回复 · 11 点赞', style: TextStyle(fontSize: 10, color: colorScheme.outline)),
          ],
        ),
        const SizedBox(height: 10),

        // 4. 楼主认证条 (带勋章与 IP 属地)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(50),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: Colors.pink.shade300,
                child: const Text('Y', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('YesNe...', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                          decoration: BoxDecoration(
                            color: Colors.purple.withAlpha(25),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: Colors.purple.withAlpha(100), width: 0.7),
                          ),
                          child: Text('版主', style: TextStyle(fontSize: 8.5, color: Colors.purple.shade700, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        // 勋章行
                        const Icon(Icons.shield_rounded, size: 12, color: Colors.blueAccent),
                        const SizedBox(width: 2),
                        const Icon(Icons.grass_rounded, size: 12, color: Colors.green),
                        const SizedBox(width: 2),
                        const Icon(Icons.science_rounded, size: 12, color: Colors.amber),
                        const SizedBox(width: 2),
                        const Icon(Icons.article_rounded, size: 12, color: Colors.teal),
                        const SizedBox(width: 2),
                        const Icon(Icons.star_rounded, size: 12, color: Colors.orange),
                      ],
                    ),
                  ],
                ),
              ),
              Text('11月4日 17:00 广东省', style: TextStyle(fontSize: 10, color: colorScheme.outline)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(35),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('楼主', style: TextStyle(fontSize: 9, color: Colors.amber.shade900, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 5. 审核通过提示条
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '本主题由 YesNewBee 于 2026-9-18 22:04 审核通过',
            style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
          ),
        ),
        const SizedBox(height: 12),

        // 6. 1:1 真实海报海景 (完全对齐 media_1790393423740.png)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF071410),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
          ),
          child: Column(
            children: [
              const Text(
                '【非官方活动】老友回归，新人启程',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4EECE6),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                '不止BE附加包！',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4EECE6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 7. 底部互动操作栏 (1:1 对齐 media_1790393423740.png)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildDemoActionBtn(context, Icons.thumb_up_alt_outlined, '11 赞'),
            _buildDemoActionBtn(context, Icons.star_border_rounded, '2 收藏'),
            _buildDemoActionBtn(context, Icons.share_rounded, '分享'),
            _buildDemoActionBtn(context, Icons.chat_bubble_outline_rounded, '15 回复'),
          ],
        ),
        const Divider(height: 24),

        // 9. 回复楼层列表模拟 (1:1 Discuz 楼层引用与沙发板凳)
        Row(
          children: [
            const Text('全部回帖 (242)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('只看楼主', style: TextStyle(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),

        // 2楼 沙发 (带引用上文)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(50),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outlineVariant.withAlpha(40)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 13, backgroundColor: Colors.teal.shade600, child: const Text('M', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 6),
                  const Text('Minecraft老玩家', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                    decoration: BoxDecoration(color: Colors.teal.withAlpha(25), borderRadius: BorderRadius.circular(3)),
                    child: Text('Lv.5 金牌会员', style: TextStyle(fontSize: 8.5, color: Colors.teal.shade700, fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.red.withAlpha(25), borderRadius: BorderRadius.circular(4)),
                    child: const Text('2# 沙发', style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 原生 Discuz 引用框
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(6),
                  border: const Border(left: BorderSide(color: Colors.grey, width: 3)),
                ),
                child: Text(
                  '引用 楼主 发表于 2024-8-12 18:22: 欢迎来到基岩版（Bedrock Edition）附加包讨论专区...',
                  style: TextStyle(fontSize: 10, color: colorScheme.outline, fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '支持Yes版主的活动！正好手头有一个开发中的RPG附加包准备发布，这次借着活动冲一波！',
                style: TextStyle(fontSize: 11.5, height: 1.45),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('20分钟前 · 来自 Android', style: TextStyle(fontSize: 9.5, color: colorScheme.outline)),
                  const Spacer(),
                  Icon(Icons.thumb_up_alt_outlined, size: 12, color: colorScheme.outline),
                  const SizedBox(width: 2),
                  Text('12', style: TextStyle(fontSize: 9.5, color: colorScheme.outline)),
                  const SizedBox(width: 10),
                  Text('回复', style: TextStyle(fontSize: 10, color: colorScheme.primary, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // 3楼 板凳
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(50),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outlineVariant.withAlpha(40)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 13, backgroundColor: Colors.purple.shade600, child: const Text('S', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 6),
                  const Text('Steve_Alex', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                    decoration: BoxDecoration(color: Colors.purple.withAlpha(25), borderRadius: BorderRadius.circular(3)),
                    child: Text('Lv.3 中级会员', style: TextStyle(fontSize: 8.5, color: Colors.purple.shade700, fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.blue.withAlpha(25), borderRadius: BorderRadius.circular(4)),
                    child: const Text('3# 板凳', style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '奖励很丰厚啊，新人必须冲一波了！请问自制的光影包材质包能和附加包一起投稿吗？',
                style: TextStyle(fontSize: 11.5, height: 1.45),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('45分钟前 · 来自 Windows', style: TextStyle(fontSize: 9.5, color: colorScheme.outline)),
                  const Spacer(),
                  Icon(Icons.thumb_up_alt_outlined, size: 12, color: colorScheme.outline),
                  const SizedBox(width: 2),
                  Text('8', style: TextStyle(fontSize: 9.5, color: colorScheme.outline)),
                  const SizedBox(width: 10),
                  Text('回复', style: TextStyle(fontSize: 10, color: colorScheme.primary, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 导读页 Feed 流高保真仿真（1:1 对齐 GuidePage 真实热门/最新/新帖/精华流）
  Widget _buildGuideFeedDemo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 导读页专属 TabBar 仿真
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildGuideTabPill('热门', isSelected: true, colorScheme: colorScheme),
              _buildGuideTabPill('最新', isSelected: false, colorScheme: colorScheme),
              _buildGuideTabPill('新帖', isSelected: false, colorScheme: colorScheme),
              _buildGuideTabPill('精华', isSelected: false, colorScheme: colorScheme),
              _buildGuideTabPill('图集', isSelected: false, colorScheme: colorScheme),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2. 真实导读帖子列表 (ThreadCard 体系，1:1 对齐原生导读流)
        ThreadCard(
          thread: ThreadSummary(
            tid: 30001,
            title: '【BE附加包】[1.21.x] 简单实用！更多合成配方扩展包 v2.4 (附汉化)',
            author: 'Crafter_Boy',
            uid: 5566,
            badge: '热门',
            typeName: 'BE附加包',
            timeText: '10分钟前',
            views: 12480,
            replies: 156,
            recommendCount: 86,
          ),
          onTap: () {},
        ),
        const SizedBox(height: 8),
        ThreadCard(
          thread: ThreadSummary(
            tid: 30002,
            title: '【JE材质】[1.20+] 原版增强光影与真实水体材质包更新',
            author: 'ShaderMaster',
            uid: 7890,
            badge: '精选',
            typeName: 'JE资源',
            timeText: '35分钟前',
            views: 8920,
            replies: 64,
            recommendCount: 52,
          ),
          onTap: () {},
        ),
        const SizedBox(height: 8),
        ThreadCard(
          thread: ThreadSummary(
            tid: 30003,
            title: '【非官方活动】【发帖有奖】BE附加包板块·老友回归，新人启程',
            author: 'YesNewBee',
            uid: 1001,
            badge: '活动',
            typeName: '闲聊讨论',
            timeText: '1小时前',
            views: 622,
            replies: 16,
            recommendCount: 11,
          ),
          onTap: () {},
        ),
        const SizedBox(height: 8),
        ThreadCard(
          thread: ThreadSummary(
            tid: 30004,
            title: '【服务器】纯净生存与生电联合服务器四期开荒招募中',
            author: 'ServerAdmin',
            uid: 3344,
            badge: '招募',
            typeName: '多人联机',
            timeText: '2小时前',
            views: 3400,
            replies: 28,
            recommendCount: 19,
          ),
          onTap: () {},
        ),
        const SizedBox(height: 12),

        // 3. 真实分页指示条
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('第 1 / 25 页', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withAlpha(90), borderRadius: BorderRadius.circular(6)),
                child: Text('上一页', style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(6)),
                child: Text('1', style: TextStyle(fontSize: 10.5, color: colorScheme.onPrimary, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withAlpha(90), borderRadius: BorderRadius.circular(6)),
                child: Text('2', style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withAlpha(90), borderRadius: BorderRadius.circular(6)),
                child: Text('3', style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withAlpha(90), borderRadius: BorderRadius.circular(6)),
                child: Text('下一页', style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuideTabPill(String title, {required bool isSelected, required ColorScheme colorScheme}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? colorScheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        boxShadow: isSelected ? const [BoxShadow(color: Colors.black12, blurRadius: 3)] : null,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildLeftActionCard({
    required BuildContext context,
    required String title,
    required String desc,
    required Color headerColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(60),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(60), width: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            color: headerColor,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 10, color: Colors.white),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Text(
              desc,
              style: TextStyle(fontSize: 8.5, color: colorScheme.onSurfaceVariant.withAlpha(200), height: 1.25),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoStickyItem(String tag, String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(3)),
            child: Text(tag, style: TextStyle(fontSize: 8.5, color: color, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 高保真演示子组件辅助
  // ==========================================

  Widget _buildDemoFilterPill(BuildContext context, String text, {required bool isSelected}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? colorScheme.primary : colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildDemoActionBtn(BuildContext context, IconData icon, String label) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant)),
      ],
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

    final totalRows = ((size.height - padding.vertical) / (cellHeight + spacing)).ceil() + 1;

    for (int r = 0; r < totalRows; r++) {
      for (int c = 0; c < totalCols; c++) {
        final x = padding.left + c * (cellWidth + spacing);
        final y = padding.top + r * (cellHeight + spacing);

        if (isThreadMode && c < 8) {
          // 在帖子工作台模式下，前 8 列（0..7）为版块边栏与正文流专属区域，绝非卡片可放置网格！
          // 仅绘制极微弱的对齐点，绝对不画任何空的卡片虚线槽位
          canvas.drawCircle(Offset(x, y), 0.8, dotPaint..color = gridColor.withAlpha(12));
          continue;
        }

        final isCenter = (centerColStart >= 0 && c >= centerColStart && c <= centerColEnd) ||
            (leftColStart >= 0 && c >= leftColStart && c <= leftColEnd);
        if (isCenter) {
          // 中心高保真预览区不画单元格厚框，仅留微弱对齐十字点
          canvas.drawCircle(Offset(x, y), 0.8, dotPaint..color = gridColor.withAlpha(15));
          continue;
        }

        // 绘制十字或微圆点
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint..color = gridColor.withAlpha(70));
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

