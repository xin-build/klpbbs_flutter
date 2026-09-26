import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../models/credit_log.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/credit_page.dart';
import 'dashboard_card_frame.dart';

/// 4. 积分流水账卡片（支持 GPU 隔离与 LOD 尺寸自适应）
class CreditLogDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const CreditLogDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<CreditLogDashboardCard> createState() => _CreditLogDashboardCardState();
}

class _CreditLogDashboardCardState extends State<CreditLogDashboardCard> {
  List<CreditLogEntry> _logs = [];
  int _iron = 25680;
  int _credits = 10420;
  bool _loading = true;

  // 专属高保真固定演示数据
  static const List<CreditLogEntry> _fixedPreviewLogs = [
    CreditLogEntry(
      operation: '每日签到打卡',
      amount: '+20',
      creditType: '铁粒',
      timeText: '今天 08:30',
      detail: '连续打卡额外奖励',
    ),
    CreditLogEntry(
      operation: '发布原创资源',
      amount: '+150',
      creditType: '铁粒',
      timeText: '昨天 21:15',
      detail: '版块加精奖励',
    ),
    CreditLogEntry(
      operation: '打赏优秀作者',
      amount: '-50',
      creditType: '铁粒',
      timeText: '昨天 17:40',
      detail: '评分扣除',
    ),
    CreditLogEntry(
      operation: '购买提升卡',
      amount: '-100',
      creditType: '铁粒',
      timeText: '前天 14:02',
      detail: '道具商城消费',
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isPreview) {
      _logs = _fixedPreviewLogs;
      _loading = false;
    } else {
      _loadRealLogs();
    }
  }

  Future<void> _loadRealLogs() async {
    try {
      final res = await KlpbbsApi.getCreditLogs(page: 1);
      final myUid = await KlpbbsApi.getMyUid() ?? 1;
      final space = await KlpbbsApi.getUserSpace(myUid);
      if (mounted) {
        setState(() {
          _logs = res.isNotEmpty ? res : _fixedPreviewLogs;
          if (space != null) {
            final ironStr = space.creditsDetail['铁粒'] ?? space.stats['铁粒'] ?? '';
            final parsedIron = int.tryParse(ironStr.replaceAll(RegExp(r'[^\d]'), ''));
            if (parsedIron != null) _iron = parsedIron;
            final creditsDigits = space.credits.replaceAll(RegExp(r'[^\d]'), '');
            final parsedCredits = int.tryParse(creditsDigits);
            if (parsedCredits != null) _credits = parsedCredits;
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _logs = _fixedPreviewLogs;
          _loading = false;
        });
      }
    }
  }

  void _openCreditPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompact = widget.item.rowSpan <= 1;
    final isNarrow = widget.item.colSpan <= 2;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '积分流水账';

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        onTap: _openCreditPage,
        child: _loading
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                ),
              )
            : (isCompact || isNarrow)
                ? _buildCompactLOD(context, title: title)
                : _buildFullLOD(context, title: title),
      ),
    );
  }

  /// 缩放较小（2x1）时的极简自适应外观
  Widget _buildCompactLOD(BuildContext context, {required String title}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.green.shade500, Colors.teal.shade700],
            ),
          ),
          child: const Icon(Icons.account_balance_wallet_rounded, size: 18, color: Colors.white),
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
                '总积分: $_credits',
                maxLines: 1,
                style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.green.withAlpha(30),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green.withAlpha(80), width: 0.8),
          ),
          child: Text(
            '$_iron 铁粒',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade700),
          ),
        ),
      ],
    );
  }

  /// 展开模式
  Widget _buildFullLOD(BuildContext context, {required String title}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet_rounded, size: 17, color: Colors.green.shade600),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '铁粒: $_iron',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.green.shade700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _logs.take(3).length,
            separatorBuilder: (_, __) => const Divider(height: 8, thickness: 0.5),
            itemBuilder: (context, idx) {
              final log = _logs[idx];
              final isIncome = log.isPositive;
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.operation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          log.timeText,
                          style: TextStyle(fontSize: 9.5, color: colorScheme.outline.withAlpha(160)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isIncome ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${log.amount} ${log.creditType}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
