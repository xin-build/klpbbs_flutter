import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_config.dart';
import '../models/dashboard_card_model.dart';
import '../models/post_floor.dart';
import '../pages/settings_page.dart';
import '../pages/user_space_page.dart';
import 'dashboard_cards/dashboard_card_factory.dart';
import 'dashboard_cards/sign_calendar_dashboard_card.dart';
import 'embedded_forum_panel.dart';
import 'image_viewer_dialog.dart';
import 'retry_image.dart';
import 'thread_card.dart';

/// 帖子详情页专属桌面 DIY 模块化工作台容器
class ThreadLayoutWorkbench extends StatefulWidget {
  final int tid;
  final int? fid;
  final String? forumName;
  final List<PostFloor> floors;
  final ScrollController scrollController;
  final Widget child;
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final int currentPage;
  final int totalPages;
  final int totalReplies;
  final bool isDescOrder;
  final ValueChanged<int>? onNavigateToFloor;
  final ValueChanged<int>? onJumpToFloor;
  final ValueChanged<int>? onSelectThread;
  final VoidCallback? onOpenRatingFilter;

  const ThreadLayoutWorkbench({
    super.key,
    required this.tid,
    this.fid,
    this.forumName,
    required this.floors,
    required this.scrollController,
    required this.child,
    this.bottomBar,
    this.floatingActionButton,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalReplies = 0,
    this.isDescOrder = false,
    this.onNavigateToFloor,
    this.onJumpToFloor,
    this.onSelectThread,
    this.onOpenRatingFilter,
  });

  @override
  State<ThreadLayoutWorkbench> createState() => _ThreadLayoutWorkbenchState();
}

class _ThreadLayoutWorkbenchState extends State<ThreadLayoutWorkbench> {
  final _searchController = TextEditingController();
  final _compassController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _compassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 当可用宽度小于 680 时自动降级为标准流式布局；在 680 以上时即可呈现右侧工作台助手
        final isWorkbenchViable = constraints.maxWidth >= 680;
        if (!isWorkbenchViable) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AppConfig.threadContentMaxWidth > 0
                    ? AppConfig.threadContentMaxWidth
                    : double.infinity,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.child,
                  if (widget.bottomBar != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: widget.bottomBar!,
                    ),
                  if (widget.floatingActionButton != null)
                    Positioned(
                      right: 16,
                      bottom: widget.bottomBar != null ? (bottomInset + 72) : (bottomInset + 16),
                      child: widget.floatingActionButton!,
                    ),
                ],
              ),
            ),
          );
        }

        return ListenableBuilder(
          listenable: AppConfig.instance,
          builder: (context, _) {
            final showRight = AppConfig.threadRightEnabled && AppConfig.threadRightModules.isNotEmpty;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ================= 1. 中间正文区域（左侧一律留给版块列表） =================
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: ValueListenableBuilder<double>(
                          valueListenable: AppConfig.threadContentMaxWidthNotifier,
                          builder: (context, maxWidth, contentChild) {
                            return ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: maxWidth > 0 ? maxWidth : double.infinity,
                              ),
                              child: contentChild,
                            );
                          },
                          child: widget.child,
                        ),
                      ),
                      if (widget.bottomBar != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: widget.bottomBar!,
                        ),
                      if (widget.floatingActionButton != null)
                        Positioned(
                          right: 16,
                          bottom: widget.bottomBar != null ? (bottomInset + 72) : (bottomInset + 16),
                          child: widget.floatingActionButton!,
                        ),
                    ],
                  ),
                ),

                // ================= 2. 右侧可拖拽助手工作台 =================
                if (showRight) ...[
                  // 鼠标自由拖拽调节右栏宽度手柄
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        final newW = AppConfig.threadRightWidth - details.delta.dx;
                        AppConfig.updateThreadRightWidth(newW);
                      },
                      onHorizontalDragEnd: (_) {
                        AppConfig.setThreadRightWidth(AppConfig.threadRightWidth);
                      },
                      child: Container(
                        width: 8,
                        color: Colors.transparent,
                        child: Center(
                          child: Container(
                            width: 2,
                            height: 36,
                            decoration: BoxDecoration(
                              color: colorScheme.outlineVariant.withAlpha(80),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: AppConfig.threadRightWidthNotifier,
                    builder: (context, rightW, rightChild) {
                      return SizedBox(
                        width: rightW.clamp(200.0, 520.0),
                        child: rightChild,
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        border: Border(
                          left: BorderSide(
                            color: colorScheme.outlineVariant.withAlpha(35),
                            width: 0.8,
                          ),
                        ),
                      ),
                      child: _buildPanelContent(
                        context,
                        modules: AppConfig.threadRightModules,
                      ),
                    ),
                  ),
                ] else if (AppConfig.threadRightModules.isNotEmpty) ...[
                  _buildCollapsedEdgeHandle(),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCollapsedEdgeHandle() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Tooltip(
        message: '展开右侧边栏 (工作台助手)',
        child: InkWell(
          onTap: () {
            AppConfig.setThreadRightEnabled(true);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 18,
            height: 60,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(160),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant.withAlpha(60), width: 0.8),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Icon(
              Icons.chevron_left_rounded,
              size: 16,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanelContent(
    BuildContext context, {
    required List<String> modules,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // 侧栏顶部轻量控制条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(30),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.table_chart_rounded,
                size: 15,
                color: colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Text(
                '工作台 · 助手',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.outline,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.tune_rounded, size: 15),
                tooltip: '工作台排版与设置',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsPage(initialCategory: SettingsCategory.layout),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.last_page_rounded, size: 16),
                tooltip: '收起工作台助手',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () {
                  AppConfig.setThreadRightEnabled(false);
                },
              ),
            ],
          ),
        ),

        // 模块卡片垂直滚动容器（纯净展示助手，排版增删统一由系统设置处理）
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
            itemCount: modules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, index) {
              final moduleId = modules[index];
              return _buildModuleWidget(context, moduleId);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModuleWidget(BuildContext context, String moduleId) {
    switch (moduleId) {
      case 'forum_list':
        return _buildForumListModule(context);
      case 'toc_outline':
        return _buildTocOutlineModule(context);
      case 'floor_compass':
        return _buildFloorCompassModule(context);
      case 'reader_tuning':
        return _buildReaderTuningModule(context);
      case 'rating_hub':
        return _buildRatingHubModule(context);
      case 'media_gallery':
        return _buildMediaGalleryModule(context);
      case 'thread_search':
        return _buildThreadSearchModule(context);
      case 'author_card':
        return _buildAuthorCardModule(context);
      case 'sign_calendar':
        return _buildSignInCalendarModule(context);
      default:
        // 全站卡片自适应渲染（如快捷回复、土豪榜、帕帕AI、签到运势等放入工作台的卡片）
        if (CardRegistry.definitions.containsKey(moduleId)) {
          final def = CardRegistry.get(moduleId);
          return _buildGenericCardModule(context, moduleId, def);
        }
        return const SizedBox.shrink();
    }
  }

  /// 全站通用卡片工作台自适应包装器
  Widget _buildGenericCardModule(BuildContext context, String moduleId, CardDefinition def) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final savedItem = AppConfig.threadDashboardLayout.cast<DashboardGridItem?>().firstWhere(
      (e) => e?.cardType == moduleId,
      orElse: () => null,
    );
    final rowSpan = savedItem?.rowSpan ?? def.defaultRowSpan;
    final item = DashboardGridItem(
      id: savedItem?.id ?? 'th_$moduleId',
      cardType: moduleId,
      col: 8,
      row: 0,
      colSpan: 4,
      rowSpan: rowSpan,
    );

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(40),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(50),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: rowSpan * 64.0,
          maxHeight: rowSpan * 88.0 + 30,
        ),
        child: DashboardCardFactory.buildCard(
          item: item,
          isPreview: false,
        ),
      ),
    );
  }

  // 1. 同版块帖子列表（1:1 对齐原生版块界面，具备分类芯片、原生 RefreshIndicator、置顶流与高光跟手切帖）
  Widget _buildForumListModule(BuildContext context) {
    final fid = widget.fid ?? 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: EmbeddedForumPanel(
        fid: fid,
        currentTid: widget.tid,
        onSelectThread: (tid) => widget.onSelectThread?.call(tid),
      ),
    );
  }

  // 2. 文章大纲目录树 (TOC)
  Widget _buildTocOutlineModule(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 提取主要标题段落或楼层标记
    final outlineItems = <({int floorIdx, String text, int level})>[];
    for (int i = 0; i < widget.floors.length; i++) {
      final f = widget.floors[i];
      if (widget.currentPage == 1 && i == 0) {
        outlineItems.add((floorIdx: i, text: '主帖 · 楼主正文', level: 1));
      } else if (f.isBestAnswer) {
        outlineItems.add((floorIdx: i, text: '★ 最佳答案 (${f.author})', level: 2));
      } else if (!widget.isDescOrder && widget.currentPage == 1 && i == 1) {
        outlineItems.add((floorIdx: i, text: '2# 沙发 (${f.author})', level: 2));
      } else if (!widget.isDescOrder && widget.currentPage == 1 && i == 2) {
        outlineItems.add((floorIdx: i, text: '3# 板凳 (${f.author})', level: 2));
      } else if (widget.isDescOrder && widget.currentPage == 1 && i == 1) {
        final label = f.floorNumber.isNotEmpty ? f.floorNumber : '最新回帖';
        outlineItems.add((floorIdx: i, text: '最新回帖 · $label (${f.author})', level: 2));
      } else {
        final fn = f.floorNumber.trim();
        String label = '';
        if (fn.isNotEmpty && fn != '楼主') {
          label = fn.endsWith('#') ? fn : '$fn#';
        } else if (!widget.isDescOrder) {
          label = '${(widget.currentPage - 1) * 10 + i + 1}#';
        } else {
          label = '${i + 1}#';
        }
        if (i == 0 || i == 1 || i % 5 == 0 || i == widget.floors.length - 1) {
          final authorSuffix = f.author.isNotEmpty ? ' (${f.author})' : '';
          outlineItems.add((floorIdx: i, text: '$label$authorSuffix', level: 2));
        }
      }
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.format_list_bulleted_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                const Text(
                  '文章大纲目录',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (outlineItems.isEmpty) ...[
              Text('暂无目录节点', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
            ] else ...[
              for (final item in outlineItems) ...[
                InkWell(
                  onTap: () => widget.onJumpToFloor?.call(item.floorIdx),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _executeFloorJump(String rawText, BuildContext context) {
    final text = rawText.trim();
    if (text.isEmpty) return;
    final num = int.tryParse(text.replaceAll(RegExp(r'[^\d]'), ''));
    if (num == null || num <= 0) return;

    // 1. 优先在当前页寻找真实楼层或称谓，杜绝不必要的页面重载
    int? targetIndex;
    if (num == 1 && widget.currentPage == 1) {
      targetIndex = 0;
    } else {
      for (int i = 0; i < widget.floors.length; i++) {
        final f = widget.floors[i];
        final fNum = f.floorNumber.replaceAll(RegExp(r'[^\d]'), '');
        if (fNum.isNotEmpty && int.tryParse(fNum) == num) {
          targetIndex = i;
          break;
        }
        if (num == 1 && (f.floorNumber == '楼主' || f.isThreadAuthor || (widget.currentPage == 1 && i == 0))) {
          targetIndex = i;
          break;
        }
        if (num == 2 && f.floorNumber.contains('沙发')) {
          targetIndex = i;
          break;
        }
        if (num == 3 && f.floorNumber.contains('板凳')) {
          targetIndex = i;
          break;
        }
        if (num == 4 && f.floorNumber.contains('地板')) {
          targetIndex = i;
          break;
        }
      }
    }

    if (targetIndex != null) {
      widget.onJumpToFloor?.call(targetIndex);
      return;
    }

    // 2. 当前页未找到，委托全局跨页导航器
    if (widget.onNavigateToFloor != null) {
      widget.onNavigateToFloor!(num);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('当前页未找到 $num# 楼，请使用分页器翻至对应页面'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 3. 楼层罗盘与精准直达
  Widget _buildFloorCompassModule(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalReplies = widget.totalReplies;
    final totalFloors = totalReplies > 0 ? totalReplies + 1 : widget.floors.length;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.explore_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                const Text(
                  '楼层罗盘',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  '第 ${widget.currentPage}/${widget.totalPages} 页 · 共 $totalFloors 楼',
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('1# 楼主', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    if (widget.currentPage == 1) {
                      widget.onJumpToFloor?.call(0);
                    } else if (widget.onNavigateToFloor != null) {
                      widget.onNavigateToFloor!(1);
                    }
                  },
                ),
                if (totalFloors > 1)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('2# 沙发', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      if (!widget.isDescOrder && widget.currentPage == 1) {
                        widget.onJumpToFloor?.call(widget.floors.length > 1 ? 1 : 0);
                      } else if (widget.onNavigateToFloor != null) {
                        widget.onNavigateToFloor!(2);
                      }
                    },
                  ),
                if (totalFloors > 2)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('3# 板凳', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      if (!widget.isDescOrder && widget.currentPage == 1) {
                        widget.onJumpToFloor?.call(widget.floors.length > 2 ? 2 : 0);
                      } else if (widget.onNavigateToFloor != null) {
                        widget.onNavigateToFloor!(3);
                      }
                    },
                  ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(widget.isDescOrder ? '最新回帖 (第1页)' : '最新回帖 ($totalFloors#)', style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    if (widget.isDescOrder && widget.currentPage == 1) {
                      final idx = widget.floors.length > 1 ? 1 : 0;
                      widget.onJumpToFloor?.call(idx);
                    } else if (widget.onNavigateToFloor != null) {
                      widget.onNavigateToFloor!(totalFloors);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _compassController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: '直达楼层号 (如 5)',
                        hintStyle: TextStyle(fontSize: 11, color: colorScheme.outline),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onSubmitted: (v) => _executeFloorJump(v, context),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.tonal(
                  onPressed: () => _executeFloorJump(_compassController.text, context),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text('跳转', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 4. 阅读排版调谐器
  Widget _buildReaderTuningModule(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                const Text(
                  '阅读排版调谐器',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 字号
            Row(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: AppConfig.threadReaderFontSizeNotifier,
                  builder: (context, size, _) => Text(
                    '字号: ${size.toInt()} pt',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder<double>(
                    valueListenable: AppConfig.threadReaderFontSizeNotifier,
                    builder: (context, size, _) => Slider(
                      value: size,
                      min: 12,
                      max: 22,
                      divisions: 10,
                      label: '${size.toInt()}',
                      onChanged: (v) {
                        AppConfig.updateThreadReaderFontSize(v);
                      },
                      onChangeEnd: (v) {
                        AppConfig.setThreadReaderFontSize(v);
                      },
                    ),
                  ),
                ),
              ],
            ),
            // 行间距
            Row(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: AppConfig.threadReaderLineHeightNotifier,
                  builder: (context, height, _) => Text(
                    '行距: ${height.toStringAsFixed(1)}x',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder<double>(
                    valueListenable: AppConfig.threadReaderLineHeightNotifier,
                    builder: (context, height, _) => Slider(
                      value: height,
                      min: 1.3,
                      max: 2.2,
                      divisions: 9,
                      label: height.toStringAsFixed(1),
                      onChanged: (v) {
                        AppConfig.updateThreadReaderLineHeight(v);
                      },
                      onChangeEnd: (v) {
                        AppConfig.setThreadReaderLineHeight(v);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 5. 评分与打赏筛选大厅模块
  Widget _buildRatingHubModule(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final firstFloor = widget.floors.isNotEmpty ? widget.floors.first : null;
    final rewardList = firstFloor?.rewards ?? const [];

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.card_giftcard_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                const Text(
                  '评分与打赏大厅',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  '${rewardList.length} 条记录',
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(60),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '支持多币种汇总、实时模糊搜索与大额正向加分筛选',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withAlpha(200)),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: widget.onOpenRatingFilter,
              icon: const Icon(Icons.filter_list_rounded, size: 15),
              label: const Text('打开全功能筛选面板', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 32),
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 6. 全帖媒体附件画廊
  Widget _buildMediaGalleryModule(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 汇总各楼层图片
    final allImages = <String>{};
    for (final f in widget.floors) {
      allImages.addAll(f.images);
    }
    final imgList = allImages.toList();

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(45), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.photo_library_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                const Text(
                  '全帖媒体画廊',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  '${imgList.length} 张图',
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (imgList.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text('本帖未包含图片附件', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                ),
              ),
            ] else ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: imgList.length.clamp(0, 9),
                itemBuilder: (ctx, idx) {
                  final imgUrl = imgList[idx];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: () {
                        ImageViewerDialog.show(
                          context,
                          imageUrls: imgList,
                          initialIndex: idx,
                        );
                      },
                      child: RetryImage(
                        imageUrl: imgUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        placeholder: (_, __) => Container(
                          color: colorScheme.surfaceContainerHighest.withAlpha(80),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 7. 帖内内容快速检索模块
  Widget _buildThreadSearchModule(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final query = _searchQuery.trim().toLowerCase();

    final matchedFloors = <({int index, PostFloor floor})>[];
    if (query.isNotEmpty) {
      for (var i = 0; i < widget.floors.length; i++) {
        final f = widget.floors[i];
        if (f.contentHtml.toLowerCase().contains(query) ||
            f.author.toLowerCase().contains(query) ||
            f.floorNumber.contains(query)) {
          matchedFloors.add((index: i, floor: f));
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(50),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.search_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '帖内搜索',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (query.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withAlpha(60),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${matchedFloors.length} 条命中',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              hintText: '搜索本帖楼层、内容、作者...',
              hintStyle: TextStyle(fontSize: 12, color: colorScheme.outline),
              prefixIcon: const Icon(Icons.search, size: 16),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
              ),
            ),
            onChanged: (val) {
              setState(() => _searchQuery = val);
            },
          ),
          if (query.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (matchedFloors.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    '未找到与 "$query" 相关的楼层',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: matchedFloors.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withAlpha(30),
                  ),
                  itemBuilder: (context, idx) {
                    final item = matchedFloors[idx];
                    final f = item.floor;
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => widget.onJumpToFloor?.call(item.index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withAlpha(20),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    f.floorNumber.isNotEmpty ? f.floorNumber : '${item.index + 1}#',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    f.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios_rounded, size: 10, color: colorScheme.outline),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              f.contentHtml.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('\n', ' ').trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  // 8. 楼主与作者名片模块
  Widget _buildAuthorCardModule(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final firstFloor = widget.floors.isNotEmpty ? widget.floors.first : null;
    if (firstFloor == null) return const SizedBox.shrink();

    final uid = firstFloor.uid ?? 0;
    final author = firstFloor.author;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(50),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatarWidget(
                uid: uid,
                author: author,
                size: 38,
                onTap: uid > 0
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UserSpacePage(uid: uid),
                          ),
                        )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '楼主',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'UID: $uid',
                      style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.person_outline, size: 14),
                  label: const Text('个人空间', style: TextStyle(fontSize: 11)),
                  onPressed: uid > 0
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => UserSpacePage(uid: uid),
                            ),
                          )
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('复制 UID', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '$uid'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已复制 UID: $uid')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 9. 嵌入式每日签到日历模块（对齐视觉画布 1:1 月历全尺寸与自定义样式）
  Widget _buildSignInCalendarModule(BuildContext context) {
    DashboardGridItem? savedItem;
    try {
      savedItem = AppConfig.threadDashboardLayout.firstWhere((i) => i.cardType == 'sign_calendar');
    } catch (_) {}

    final item = savedItem ??
        DashboardGridItem(
          id: 'workbench_sign_calendar',
          cardType: 'sign_calendar',
          col: 0,
          row: 0,
          colSpan: 4,
          rowSpan: 3,
        );

    final effectiveRowSpan = item.rowSpan >= 1 ? item.rowSpan : 3;
    final cardHeight = (effectiveRowSpan * 88.0 + (effectiveRowSpan - 1) * 8.0).clamp(170.0, 380.0);

    return SizedBox(
      height: cardHeight,
      child: SignInCalendarDashboardCard(
        item: item,
      ),
    );
  }
}
