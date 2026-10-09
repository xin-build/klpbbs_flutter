import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/credit_page.dart';
import '../../pages/ranklist_page.dart';
import '../../pages/sign_rank_page.dart';
import 'dashboard_card_frame.dart';

/// 排行与积分入口对应实际页面，不提供已被站点关闭的财富榜。
class RanklistDashboardCard extends StatelessWidget {
  final DashboardGridItem item;
  final bool isPreview;
  const RanklistDashboardCard(
      {super.key, required this.item, this.isPreview = false});

  void _open(BuildContext context, String type, int index) {
    if (isPreview) return;
    final Widget page = switch (type) {
      'credits' => CreditPage(
          initialTabIndex: index == 0 ? 0 : 2,
          initialLogCategory: index == 2 ? 'reward' : ''),
      'posts' =>
        RanklistPage(initialPeriod: const ['day', 'week', 'month'][index]),
      _ =>
        SignRankPage(initialOperation: const ['today', 'month', 'zong'][index]),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final type = item.customParams['rankType'] as String? ?? 'auto';
    final title = item.customParams['customTitle'] as String? ??
        (type == 'credits'
            ? '积分中心'
            : type == 'posts'
                ? '热门排行'
                : '签到排行');
    final labels = type == 'credits'
        ? const ['我的积分', '积分流水', '系统奖励']
        : type == 'posts'
            ? const ['日热门', '周热门', '月热门']
            : const ['今日排行', '本月排行', '总排行'];
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
        child: DashboardCardFrame(
      item: item,
      padding: const EdgeInsets.all(12),
      onTap: isPreview ? null : () => _open(context, type, 0),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxHeight < 110) {
          return Row(children: [
            Icon(
                type == 'credits'
                    ? Icons.account_balance_wallet_outlined
                    : Icons.emoji_events_outlined,
                color: scheme.primary,
                size: 22),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 3),
                  Text(labels.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ])),
            Icon(Icons.chevron_right, size: 18, color: scheme.outline),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Expanded(
              child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: labels.length,
                  itemBuilder: (context, index) => ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        leading: Icon(
                            const [
                              Icons.today_outlined,
                              Icons.date_range_outlined,
                              Icons.calendar_month_outlined
                            ][index],
                            size: 18,
                            color: scheme.primary),
                        title: Text(labels[index],
                            style: const TextStyle(fontSize: 12)),
                        trailing: Icon(Icons.chevron_right,
                            size: 16, color: scheme.outline),
                        onTap: isPreview
                            ? null
                            : () => _open(context, type, index),
                      ))),
        ]);
      }),
    ));
  }
}
