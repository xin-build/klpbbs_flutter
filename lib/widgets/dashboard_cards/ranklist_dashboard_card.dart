import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/ranklist_page.dart';
import '../../pages/sign_rank_page.dart';
import 'dashboard_card_frame.dart';

/// 17. 签到风云榜 / 活跃排行榜卡片（支持 GPU 隔离与 LOD 尺寸自适应）
class RanklistDashboardCard extends StatelessWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const RanklistDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final rankType = item.customParams['rankType'] as String? ?? 'auto';
    final customTitle = item.customParams['customTitle'] as String?;
    final String title;
    if (customTitle != null && customTitle.isNotEmpty) {
      title = customTitle;
    } else if (rankType == 'posts') {
      title = '发帖风云榜';
    } else if (rankType == 'credits') {
      title = '积分财富榜';
    } else {
      title = '签到风云榜';
    }

    final rawDataStyle = item.customParams['dataStyle'] as String? ?? 'auto';
    final String dataStyle;
    if (rawDataStyle == 'auto') {
      final isCompact = item.rowSpan <= 1;
      final isNarrow = item.colSpan <= 2;
      dataStyle = (isCompact || isNarrow) ? 'list' : 'podium';
    } else {
      dataStyle = rawDataStyle;
    }

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: item,
        padding: const EdgeInsets.all(12),
        onTap: () {
          if (rankType == 'posts' || rankType == 'credits') {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RanklistPage()));
          } else {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignRankPage()));
          }
        },
        child: dataStyle == 'list'
            ? _buildCompact(context, title, rankType)
            : _buildExpanded(context, title, rankType),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, String title, String rankType) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.amber.shade400, Colors.orange.shade700],
            ),
          ),
          child: const Icon(Icons.emoji_events_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              Text(
                rankType == 'posts'
                    ? '今日 · 本周 · 本月发帖榜'
                    : rankType == 'credits'
                        ? '绿宝石 · 金粒 · 贡献财富榜'
                        : '今日首签 · 连签 · 累计签到榜',
                maxLines: 1,
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.outline),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context, String title, String rankType) {
    final colorScheme = Theme.of(context).colorScheme;

    final List<(String, String, IconData, Color)> categories;
    if (rankType == 'posts') {
      categories = [
        ('今日发帖', '今日争锋', Icons.today_rounded, Colors.orange),
        ('本周发帖', '七日领跑', Icons.date_range_rounded, Colors.blue),
        ('本月发帖', '月度巨匠', Icons.calendar_month_rounded, Colors.purple),
      ];
    } else if (rankType == 'credits') {
      categories = [
        ('绿宝石榜', '核心资产', Icons.diamond_rounded, Colors.teal),
        ('金粒资产', '交易财富', Icons.monetization_on_rounded, Colors.amber),
        ('贡献积分', '社区声望', Icons.military_tech_rounded, Colors.deepPurple),
      ];
    } else {
      categories = [
        ('今日首签', '抢先打卡', Icons.bolt_rounded, Colors.orange),
        ('连签王者', '持之以恒', Icons.local_fire_department_rounded, Colors.redAccent),
        ('累计签到', '历久弥坚', Icons.event_available_rounded, Colors.green),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events_rounded, size: 17, color: Colors.amber),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Text('完整榜单 >', style: TextStyle(fontSize: 11, color: colorScheme.primary)),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              for (int i = 0; i < categories.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _buildRankCategory(categories[i].$1, categories[i].$2, categories[i].$3, categories[i].$4),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRankCategory(String name, String desc, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(45), width: 0.8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 1),
            Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
