import 'package:flutter/material.dart';

/// 全局统一分页控制栏组件
/// 提供清晰的上一页、下一页及快捷跳页功能
class PaginationControl extends StatelessWidget {
  final int page;
  final int? totalPages;
  final bool hasMore;
  final ValueChanged<int> onPageChanged;
  final bool compact;

  const PaginationControl({
    super.key,
    required this.page,
    this.totalPages,
    required this.hasMore,
    required this.onPageChanged,
    this.compact = false,
  });

  void _showJumpDialog(BuildContext context) {
    final ctrl = TextEditingController(text: '$page');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转页码'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '输入目标页码',
            helperText: totalPages != null ? '共 $totalPages 页' : null,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            final p = int.tryParse(val);
            if (p != null && p > 0) {
              Navigator.of(ctx).pop();
              onPageChanged(p);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(ctrl.text);
              if (p != null && p > 0) {
                Navigator.of(ctx).pop();
                onPageChanged(p);
              }
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final pageLabel = (totalPages != null && totalPages! > 0)
        ? '第 $page / $totalPages 页'
        : '第 $page 页';

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 8.0 : 16.0,
        horizontal: 12.0,
      ),
      child: Center(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('上一页'),
            ),
            InkWell(
              onTap: () => _showJumpDialog(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pageLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.unfold_more,
                      size: 16,
                      color: colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: (totalPages != null ? page < totalPages! : hasMore)
                  ? () => onPageChanged(page + 1)
                  : null,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('下一页'),
            ),
          ],
        ),
      ),
    );
  }
}
