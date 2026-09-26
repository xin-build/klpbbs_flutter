import 'package:flutter/material.dart';
import '../models/dashboard_card_model.dart';

/// 布局同步动态网格骨架屏（根据用户当前 DIY 网格几何结构 1:1 动态生成自适应呼吸加载卡片，零 GPU/CPU 额外开销）
class DashboardSkeletonView extends StatefulWidget {
  final List<DashboardGridItem> layout;
  final int totalColumns;
  final double cellHeight;
  final double spacing;
  final EdgeInsets padding;

  const DashboardSkeletonView({
    super.key,
    required this.layout,
    this.totalColumns = 12,
    this.cellHeight = 86.0,
    this.spacing = 10.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  });

  @override
  State<DashboardSkeletonView> createState() => _DashboardSkeletonViewState();
}

class _DashboardSkeletonViewState extends State<DashboardSkeletonView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  late final Animation<double> _opacityAnim = Tween<double>(
    begin: 0.45,
    end: 0.92,
  ).animate(
    CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.layout.isEmpty) {
      return const SizedBox(height: 100);
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final boneColor = isDark
        ? colorScheme.surfaceContainerHighest.withAlpha(90)
        : colorScheme.surfaceContainerHighest.withAlpha(150);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final totalCols = totalWidth >= 900 ? 12 : (totalWidth >= 600 ? 8 : 4);
        final resolvedItems = DashboardGridResolver.resolve(
          items: widget.layout,
          totalCols: totalCols,
        );

        final availableWidth = totalWidth - widget.padding.horizontal;
        final cellWidth = (availableWidth - (totalCols - 1) * widget.spacing) / totalCols;

        int maxRow = 0;
        for (final res in resolvedItems) {
          final bottom = res.row + res.rowSpan;
          if (bottom > maxRow) maxRow = bottom;
        }
        final totalHeight = maxRow * (widget.cellHeight + widget.spacing) + widget.padding.vertical;

        return RepaintBoundary(
          child: SizedBox(
            width: totalWidth,
            height: totalHeight,
            child: FadeTransition(
              opacity: _opacityAnim,
              child: Stack(
                children: resolvedItems.map((res) {
                  final left = widget.padding.left + res.col * (cellWidth + widget.spacing);
                  final top = widget.padding.top + res.row * (widget.cellHeight + widget.spacing);
                  final width = res.colSpan * cellWidth + (res.colSpan - 1) * widget.spacing;
                  final height = res.rowSpan * widget.cellHeight + (res.rowSpan - 1) * widget.spacing;

                  final item = res.item.copyWith(
                    col: res.col,
                    row: res.row,
                    colSpan: res.colSpan,
                    rowSpan: res.rowSpan,
                  );

                  return Positioned(
                    left: left,
                    top: top,
                    width: width,
                    height: height,
                    child: _buildSkeletonCard(
                      context,
                      item,
                      boneColor,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeletonCard(
    BuildContext context,
    DashboardGridItem item,
    Color boneColor,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(40), width: 0.8),
      ),
      child: _buildCardInternalBones(item, boneColor),
    );
  }

  Widget _buildCardInternalBones(DashboardGridItem item, Color color) {
    final isCompact = item.rowSpan <= 1;

    if (isCompact) {
      return Row(
        children: [
          Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: double.infinity, height: 10, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: color)),
                const SizedBox(height: 6),
                Container(width: 80, height: 8, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: color)),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 18, height: 18, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: color)),
            const SizedBox(width: 8),
            Container(width: 90, height: 12, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: color)),
            const Spacer(),
            Container(width: 40, height: 10, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: color)),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Container(width: double.infinity, height: 10, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: color)),
              Container(width: double.infinity, height: 10, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: color)),
              Container(width: 120, height: 8, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: color)),
            ],
          ),
        ),
      ],
    );
  }
}
