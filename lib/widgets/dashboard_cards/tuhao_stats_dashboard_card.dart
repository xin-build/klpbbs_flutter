import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/site_stats.dart';
import '../../pages/sign_rank_page.dart';
import '../../pages/thread_detail_page.dart';
import 'dashboard_card_frame.dart';

/// 5. 今日之星与全站统计卡片（对接真实土豪霸屏/签到冠军与全站实时统计，支持 GPU 光栅化隔离与多维度数据选择）
class TuhaoStatsDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;
  final SiteStats? realStats;

  const TuhaoStatsDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
    this.realStats,
  });

  @override
  State<TuhaoStatsDashboardCard> createState() => _TuhaoStatsDashboardCardState();
}

class _TuhaoStatsDashboardCardState extends State<TuhaoStatsDashboardCard> {
  SiteStats? _stats;
  ({String author, String avatarUrl, String message, String linkUrl, int tid, int uid})? _tuhao;
  String? _starUsername;

  @override
  void initState() {
    super.initState();
    _stats = widget.realStats;
    if (!widget.isPreview) {
      _loadData();
    }
  }

  @override
  void didUpdateWidget(covariant TuhaoStatsDashboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.customParams['starSource'] != widget.item.customParams['starSource']) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    try {
      if (_stats == null) {
        final s = await KlpbbsApi.getSiteStats();
        if (mounted) setState(() => _stats = s);
      }
      final starSource = widget.item.customParams['starSource'] as String? ?? 'auto';

      if (starSource != 'sign_star') {
        final t = await KlpbbsApi.getTuhaoBanner();
        if (mounted) setState(() => _tuhao = t);
      } else {
        if (mounted) setState(() => _tuhao = null);
      }

      if (starSource != 'tuhao') {
        if (_tuhao == null || starSource == 'sign_star') {
          final signHeader = await KlpbbsApi.getSignHeaderInfo(forceRefresh: false);
          if (mounted && signHeader.starUsername.isNotEmpty) {
            setState(() => _starUsername = signHeader.starUsername);
          }
        }
      } else {
        if (mounted) setState(() => _starUsername = null);
      }
    } catch (_) {}
  }

  static String _formatNumber(int val) {
    if (val <= 0) return '0';
    final str = val.toString();
    final len = str.length;
    final sb = StringBuffer();
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) {
        sb.write(',');
      }
      sb.write(str[i]);
    }
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final String title;
    if (customTitle != null && customTitle.isNotEmpty) {
      title = customTitle;
    } else {
      title = '今日之星与全站统计';
    }

    final rawDataStyle = widget.item.customParams['dataStyle'] as String? ?? 'auto';
    final String dataStyle;
    if (rawDataStyle == 'auto') {
      final isCompact = widget.item.rowSpan <= 1;
      final isNarrow = widget.item.colSpan <= 2;
      dataStyle = (isCompact || isNarrow) ? 'list' : 'podium';
    } else {
      dataStyle = rawDataStyle;
    }

    final stats = _stats ??
        widget.realStats ??
        const SiteStats(
          todayPosts: 1248,
          yesterdayPosts: 3892,
          totalPosts: 852930,
          totalMembers: 412039,
        );

    final rawMetrics = widget.item.customParams['metrics'];
    final List<String> metrics;
    if (rawMetrics is List && rawMetrics.isNotEmpty) {
      metrics = rawMetrics.map((e) => e.toString()).toList();
    } else {
      metrics = const ['todayPosts', 'yesterdayPosts', 'totalMembers'];
    }

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        onTap: () {
          if (_tuhao != null && _tuhao!.tid > 0) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: _tuhao!.tid)),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SignRankPage()),
            );
          }
        },
        child: dataStyle == 'list'
            ? _buildCompact(context, stats, title, metrics)
            : _buildExpanded(context, stats, title, metrics),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, SiteStats stats, String title, List<String> metrics) {
    final colorScheme = Theme.of(context).colorScheme;
    final championName = _tuhao?.author ?? _starUsername ?? '虚位以待';
    final prefix = _tuhao != null ? '全站广播' : (_starUsername != null ? '签到之星' : '今日之星');

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
            ),
          ),
          child: const Icon(Icons.workspace_premium_rounded, size: 18, color: Colors.white),
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
                '$prefix: $championName · 今日: ${_formatNumber(stats.todayPosts)} 帖',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${_formatNumber(stats.totalMembers)} 玩家',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.deepOrange.shade700),
          ),
        ),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context, SiteStats stats, String title, List<String> metrics) {
    final colorScheme = Theme.of(context).colorScheme;

    final String tag;
    final String name;
    final String desc;
    if (_tuhao != null) {
      tag = '全站广播';
      name = _tuhao!.author;
      desc = _tuhao!.message.isNotEmpty ? _tuhao!.message : '全站广播公告';
    } else if (_starUsername != null) {
      tag = '签到之星';
      name = _starUsername!;
      desc = '今日首位打卡';
    } else {
      tag = '今日之星';
      name = '虚位以待';
      desc = '抢先签到登榜';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.workspace_premium_rounded, size: 17, color: Colors.deepOrange.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SignRankPage()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '签到风云榜',
                      style: TextStyle(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 14, color: colorScheme.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              // 领奖台 Top 1
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withAlpha(70), width: 0.8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.military_tech_rounded, color: Colors.amber, size: 22),
                      const SizedBox(height: 1),
                      Text(
                        tag,
                        style: const TextStyle(fontSize: 9.5, color: Colors.amber, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9.5, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 核心指标面板（支持用户自定义 3 项数据）
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final m in metrics.take(3)) _buildMetricRow(m, stats),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(String key, SiteStats stats) {
    switch (key) {
      case 'todayPosts':
        return _buildStatRow('今日新帖', _formatNumber(stats.todayPosts), Colors.blue);
      case 'yesterdayPosts':
        return _buildStatRow('昨日发帖', _formatNumber(stats.yesterdayPosts), Colors.indigo);
      case 'totalPosts':
        return _buildStatRow('全站总帖', _formatNumber(stats.totalPosts), Colors.deepPurple);
      case 'totalMembers':
      default:
        return _buildStatRow('总会员数', _formatNumber(stats.totalMembers), Colors.teal);
    }
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
