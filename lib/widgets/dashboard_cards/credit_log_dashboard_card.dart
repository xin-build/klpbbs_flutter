import '../app_motion.dart';
import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../core/dio_client.dart';
import '../../core/preload_service.dart';
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
  String _iron = '—';
  String _credits = '—';
  bool _loading = true;
  bool _known = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _logs = PreloadService.instance
            .get<List<CreditLogEntry>>('credit_logs__1', ignoreExpired: true) ??
        [];
    _known = PreloadService.instance.has('credit_logs__1', allowExpired: true);
    _iron = KlpbbsApi.cachedSpace?.creditsDetail['铁粒'] ?? '—';
    _credits = KlpbbsApi.cachedSpace?.credits ?? '—';
    _loading = !widget.isPreview && !_known;
    if (widget.isPreview) {
      _loading = false;
    } else {
      _loadRealLogs();
    }
  }

  Future<void> _loadRealLogs() async {
    if (!DioClient.isLoggedIn) {
      setState(() {
        _loading = false;
        _message = '登录后查看积分记录';
      });
      return;
    }
    final session = DioClient.sessionKey;
    try {
      final res = await KlpbbsApi.getCreditLogs(page: 1);
      final myUid = await KlpbbsApi.getMyUid();
      if (myUid == null || myUid <= 0) throw StateError('未取得当前账号');
      final space = await KlpbbsApi.getUserSpace(myUid);
      if (mounted && session == DioClient.sessionKey) {
        setState(() {
          _logs = res;
          _known = true;
          _iron = space?.creditsDetail['铁粒'] ?? space?.stats['铁粒'] ?? '—';
          _credits = space?.credits.isNotEmpty == true ? space!.credits : '—';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && session == DioClient.sessionKey) {
        setState(() {
          _loading = false;
          _message = '暂未取得积分记录';
        });
      }
    }
  }

  void _openCreditPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompact = widget.item.rowSpan <= 1;
    final isNarrow = widget.item.colSpan <= 2;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title =
        (customTitle != null && customTitle.isNotEmpty) ? customTitle : '积分流水账';

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
                  child: AppLoadingIndicator(
                      strokeWidth: 2, color: colorScheme.primary),
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
          child: const Icon(Icons.account_balance_wallet_rounded,
              size: 18, color: Colors.white),
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
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.bold),
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
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700),
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
            Icon(Icons.account_balance_wallet_rounded,
                size: 17, color: Colors.green.shade600),
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
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _logs.isEmpty
              ? Center(
                  child: Text(_message ?? (_known ? '暂无积分记录' : '尚未载入积分记录'),
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant)))
              : ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: _logs.take(3).length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 8, thickness: 0.5),
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
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500),
                              ),
                              Text(
                                log.timeText,
                                style: TextStyle(
                                    fontSize: 9.5,
                                    color: colorScheme.outline.withAlpha(160)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isIncome
                                ? Colors.green.withAlpha(30)
                                : Colors.red.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${log.amount} ${log.creditType}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isIncome
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
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
