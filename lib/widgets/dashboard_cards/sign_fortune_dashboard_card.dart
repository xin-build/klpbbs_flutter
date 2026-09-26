import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/sign_rank_page.dart';
import '../../services/auto_sign_service.dart';
import 'dashboard_card_frame.dart';

/// 7. 每日签到与今日运势卡片（对接真实签到状态与连签天数，支持 GPU 隔离与 LOD 尺寸自适应）
class SignFortuneDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const SignFortuneDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<SignFortuneDashboardCard> createState() => _SignFortuneDashboardCardState();
}

class _SignFortuneDashboardCardState extends State<SignFortuneDashboardCard> {
  bool _signed = false;
  int _streakDays = 0;
  int _retroSignDays = 0;
  bool _signing = false;

  static const List<(String, String)> _fortuneList = [
    ('大吉 · 鸿运当头', '宜：下界探宝 忌：直线下挖'),
    ('中吉 · 紫气东来', '宜：附魔武器 忌：直视末影人'),
    ('吉 · 顺遂无虞', '宜：建造庇护所 忌：夜晚逗留'),
    ('小吉 · 平安喜乐', '宜：驯服野狼 忌：岩浆游泳'),
    ('大吉 · 欧皇附体', '宜：挖掘钻石 忌：挑衅铁傀儡'),
    ('上上签 · 福星高照', '宜：探索末地 忌：忘带金苹果'),
    ('吉 · 硕果累累', '宜：开垦农田 忌：乱拆红石线'),
  ];

  (String, String) get _todayFortune {
    final todayStr = AutoSignService.instance.serverTodayStr;
    final idx = (todayStr.hashCode.abs()) % _fortuneList.length;
    return _fortuneList[idx];
  }

  @override
  void initState() {
    super.initState();
    if (widget.isPreview) {
      _signed = AutoSignService.instance.isSignedToday();
      _streakDays = AutoSignService.instance.continuousDays > 0 ? AutoSignService.instance.continuousDays : 7;
      _retroSignDays = 0;
      return;
    }
    AutoSignService.instance.addListener(_onAutoSignChanged);
    _signed = AutoSignService.instance.isSignedToday();
    if (AutoSignService.instance.continuousDays > 0) {
      _streakDays = AutoSignService.instance.continuousDays;
    }
    _checkSignStatus();
  }

  @override
  void dispose() {
    if (!widget.isPreview) {
      AutoSignService.instance.removeListener(_onAutoSignChanged);
    }
    super.dispose();
  }

  void _onAutoSignChanged() {
    if (!mounted || widget.isPreview) return;
    setState(() {
      _signed = AutoSignService.instance.isSignedToday();
      if (AutoSignService.instance.continuousDays > 0) {
        _streakDays = AutoSignService.instance.continuousDays;
      }
    });
  }

  Future<void> _checkSignStatus() async {
    try {
      final info = await KlpbbsApi.getSignHeaderInfo();
      if (mounted) {
        setState(() {
          _signed = info.isSignedToday || AutoSignService.instance.isSignedToday();
          if (info.continuousDays > 0) {
            _streakDays = info.continuousDays;
          } else if (AutoSignService.instance.continuousDays > 0) {
            _streakDays = AutoSignService.instance.continuousDays;
          }
          if (info.retroSignDays > 0) {
            _retroSignDays = info.retroSignDays;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _handleSign() async {
    if (widget.isPreview) {
      if (_signed) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SignRankPage()),
        );
      } else {
        setState(() {
          _signed = true;
          _streakDays++;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('预览模式：签到成功！铁粒 +20，连签天数已更新')),
        );
      }
      return;
    }

    if (_signed) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SignRankPage()),
      );
      return;
    }

    setState(() => _signing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await KlpbbsApi.signIn();
      if (mounted) {
        final success = res.success || res.message.contains('已经签到') || res.message.contains('今日已签');
        setState(() {
          _signed = success;
          if (res.continuousDays != null && res.continuousDays! > 0) {
            _streakDays = res.continuousDays!;
          } else if (res.success) {
            _streakDays++;
          }
        });
        if (success) {
          await AutoSignService.instance.markSignedToday(
            rank: res.rank,
            continuousDays: _streakDays,
            rewardIron: res.rewardIron,
            rewardExp: res.rewardExp,
            notify: true,
          );
          if (!mounted) return;
          _showSignSuccessDialog(
            context: context,
            message: res.message.isNotEmpty ? res.message : '打卡成功！',
            iron: res.rewardIron,
            exp: res.rewardExp,
            rank: res.rank,
            days: _streakDays,
          );
        } else {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text(res.message.isNotEmpty ? res.message : '打卡未完成，请稍后重试')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('签到异常: $e')));
      }
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  void _showSignSuccessDialog({
    required BuildContext context,
    required String message,
    String? iron,
    String? exp,
    int? rank,
    int? days,
  }) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded, color: scheme.primary, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iron != null && iron.isNotEmpty)
              ListTile(
                dense: true,
                leading: const Icon(Icons.monetization_on_rounded, color: Colors.amber),
                title: const Text('获得铁粒'),
                trailing: Text('+$iron 粒', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 14)),
              ),
            if (exp != null && exp.isNotEmpty)
              ListTile(
                dense: true,
                leading: const Icon(Icons.star_rounded, color: Colors.blue),
                title: const Text('获得经验'),
                trailing: Text('+$exp 点', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
              ),
            if (rank != null && rank > 0)
              ListTile(
                dense: true,
                leading: const Icon(Icons.emoji_events_rounded, color: Colors.orange),
                title: const Text('今日排名'),
                trailing: Text('第 $rank 名', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14)),
              ),
            if (days != null && days > 0)
              ListTile(
                dense: true,
                leading: const Icon(Icons.calendar_today_rounded, color: Colors.green),
                title: const Text('连续签到'),
                trailing: Text('$days 天', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('好的'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignRankPage()));
            },
            child: const Text('查看风云榜'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '今日运势与签到';

    final rawDataStyle = widget.item.customParams['dataStyle'] as String? ?? 'auto';
    final String dataStyle;
    if (rawDataStyle == 'auto') {
      final isCompact = widget.item.rowSpan <= 1;
      final isNarrow = widget.item.colSpan <= 2;
      dataStyle = (isCompact || isNarrow) ? 'compact' : 'fortune_card';
    } else {
      dataStyle = rawDataStyle;
    }

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        child: dataStyle == 'compact'
            ? _buildCompactLOD(context, title)
            : _buildExpandedLOD(context, title),
      ),
    );
  }

  Widget _buildCompactLOD(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    final fortune = _todayFortune;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.purple.shade400, Colors.deepPurple.shade700],
            ),
          ),
          child: const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                fortune.$1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                _signed
                    ? (_streakDays > 0 ? '已连续打卡 $_streakDays 天' : '今日已完成打卡')
                    : (_retroSignDays > 0 ? '断签可使用补签卡' : '今日尚未打卡'),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  color: !_signed && _retroSignDays > 0 ? Colors.orange.shade800 : colorScheme.outline,
                  fontWeight: !_signed && _retroSignDays > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _signing ? null : _handleSign,
          child: Text(
            _signed ? '已签' : (_signing ? '中...' : '签到'),
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedLOD(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    final fortune = _todayFortune;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.event_available_rounded, size: 17, color: Colors.purple.shade600),
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
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignRankPage())),
              child: Text(
                '风云榜 >',
                style: TextStyle(fontSize: 11, color: colorScheme.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.purple.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.withAlpha(60), width: 0.8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.stars_rounded, color: Colors.purple, size: 16),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              fortune.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        fortune.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _signed
                            ? (_streakDays > 0 ? '🔥 连续打卡第 $_streakDays 天' : '✨ 今日已完成打卡')
                            : (_retroSignDays > 0 ? '💡 有 $_retroSignDays 天断签，可用补签卡恢复' : '🌟 今天还没有打卡哦'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _signed ? Colors.deepPurple.shade700 : Colors.teal.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _signed ? Colors.grey.shade400 : colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: _signing ? null : _handleSign,
                  child: Text(_signed ? '已打卡' : (_signing ? '打卡中' : '立即签到')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
