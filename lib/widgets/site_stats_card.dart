import 'package:flutter/material.dart';
import '../models/site_stats.dart';

/// 全站统计看板（今日 / 昨日 / 帖子 / 会员，严格还原手机端与全平台视觉）
class SiteStatsCard extends StatelessWidget {
  final SiteStats stats;
  final EdgeInsetsGeometry? margin;

  const SiteStatsCard({
    super.key,
    required this.stats,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return RepaintBoundary(
      child: Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(55),
          width: 0.8,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _buildStatCol(
              context,
              '今日',
              stats.todayPosts > 0 ? '${stats.todayPosts}' : '--',
              highlight: true,
            ),
            _buildVerticalDivider(colorScheme),
            _buildStatCol(
              context,
              '昨日',
              stats.yesterdayPosts > 0 ? '${stats.yesterdayPosts}' : '--',
            ),
            _buildVerticalDivider(colorScheme),
            _buildStatCol(
              context,
              '帖子',
              stats.totalPosts > 0 ? '${stats.totalPosts}' : '--',
            ),
            _buildVerticalDivider(colorScheme),
            _buildStatCol(
              context,
              '会员',
              stats.totalMembers > 0 ? '${stats.totalMembers}' : '--',
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildVerticalDivider(ColorScheme colorScheme) {
    return VerticalDivider(
      color: colorScheme.outlineVariant.withAlpha(50),
      thickness: 0.8,
      width: 1,
      indent: 4,
      endIndent: 4,
    );
  }

  Widget _buildStatCol(
    BuildContext context,
    String label,
    String value, {
    bool highlight = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withAlpha(190),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: highlight
                    ? (theme.brightness == Brightness.dark
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFE65100))
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
