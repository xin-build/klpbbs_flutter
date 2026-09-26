import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../models/credit_log.dart';
import '../pages/credit_page.dart';
import '../pages/login_page.dart';

/// 首页可 DIY 挂载的积分流水账与个人资产明细卡片
class CreditLogCard extends StatefulWidget {
  const CreditLogCard({super.key});

  @override
  State<CreditLogCard> createState() => _CreditLogCardState();
}

class _CreditLogCardState extends State<CreditLogCard> {
  bool _loading = false;
  CreditBaseInfo? _baseInfo;
  List<CreditLogEntry> _recentLogs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (DioClient.isLoggedIn) {
      _loadData();
    }
  }

  Future<void> _loadData({bool force = false}) async {
    if (!DioClient.isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        KlpbbsApi.getCreditBase(),
        KlpbbsApi.getCreditLogs(page: 1, forceRefresh: force),
      ]);

      if (mounted) {
        setState(() {
          _baseInfo = results[0] as CreditBaseInfo?;
          _recentLogs = results[1] as List<CreditLogEntry>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '获取积分流水失败';
          _loading = false;
        });
      }
    }
  }

  void _openCreditCenter(int tabIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreditPage(initialTabIndex: tabIndex)),
    ).then((_) {
      if (mounted && DioClient.isLoggedIn) {
        _loadData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: colorScheme.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withAlpha(45),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 卡片头部
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withAlpha(120),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '积分流水账',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withAlpha(100),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '实时资产',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                if (DioClient.isLoggedIn) ...[
                  IconButton(
                    icon: _loading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: '刷新积分',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    onPressed: _loading ? null : () => _loadData(force: true),
                  ),
                  InkWell(
                    onTap: () => _openCreditCenter(2),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '完整流水',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // 未登录态
            if (!DioClient.isLoggedIn) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withAlpha(70),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '登录苦力怕论坛账号，即可在首页实时查看铁粒、经验变动与流水账',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        ).then((_) {
                          if (mounted && DioClient.isLoggedIn) {
                            _loadData();
                          }
                        });
                      },
                      icon: const Icon(Icons.login, size: 16),
                      label: const Text('立即登录'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_loading && _baseInfo == null && _recentLogs.isEmpty) ...[
              // 首次加载占位
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ] else if (_error != null && _recentLogs.isEmpty) ...[
              // 错误态
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: TextStyle(fontSize: 12, color: colorScheme.error)),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => _loadData(force: true),
                        child: const Text('重试', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // 资产概览药丸栏
              if (_baseInfo != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh.withAlpha(90),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withAlpha(30),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _openCreditCenter(0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '总积分',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant.withAlpha(180),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _baseInfo!.totalCredits.isNotEmpty ? _baseInfo!.totalCredits : '--',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: colorScheme.outlineVariant.withAlpha(50),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => _openCreditCenter(0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '铁粒',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant.withAlpha(180),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.monetization_on_rounded,
                                    size: 12,
                                    color: const Color(0xFFD97706),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _baseInfo!.iron > 0 ? '${_baseInfo!.iron}' : (_baseInfo!.details['铁粒'] ?? '--'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: const Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_baseInfo!.details.containsKey('贡献') || _baseInfo!.details.containsKey('人气')) ...[
                        Container(
                          width: 1,
                          height: 28,
                          color: colorScheme.outlineVariant.withAlpha(50),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => _openCreditCenter(0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _baseInfo!.details.containsKey('贡献') ? '贡献' : '人气',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant.withAlpha(180),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _baseInfo!.details['贡献'] ?? _baseInfo!.details['人气'] ?? '--',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // 最近流水条目 (展示最新 3~4 条)
              if (_recentLogs.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      '近期暂无积分明细记录',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  ),
                ),
              ] else ...[
                for (int i = 0; i < _recentLogs.take(3).length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 8,
                      thickness: 0.5,
                      color: colorScheme.outlineVariant.withAlpha(35),
                    ),
                  _buildLogItem(context, _recentLogs[i]),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(BuildContext context, CreditLogEntry entry) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPos = entry.isPositive;

    final badgeBg = isPos
        ? const Color(0xFF10B981).withAlpha(30)
        : const Color(0xFFEF4444).withAlpha(30);
    final badgeFg = isPos ? const Color(0xFF059669) : const Color(0xFFDC2626);

    return InkWell(
      onTap: () => _openCreditCenter(2),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            // 操作动作标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(90),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.operation.isNotEmpty ? entry.operation : entry.creditType,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 详细说明或时间
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.detail.isNotEmpty ? entry.detail : entry.operation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (entry.timeText.isNotEmpty)
                    Text(
                      entry.timeText,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colorScheme.outline.withAlpha(160),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 变动数额徽章 (如 +11 铁粒)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: badgeFg.withAlpha(60), width: 0.5),
              ),
              child: Text(
                '${entry.amount} ${entry.creditType}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: badgeFg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
