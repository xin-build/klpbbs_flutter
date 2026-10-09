import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../core/dio_client.dart';
import '../../core/discuz_sign_response.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/sign_entry.dart';
import '../../pages/login_page.dart';
import '../../pages/sign_rank_page.dart';
import '../../services/auto_sign_service.dart';
import 'dashboard_card_frame.dart';

/// 7. 每日签到与本地游戏提示，签到字段取自当前账号的站点响应
class SignFortuneDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const SignFortuneDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<SignFortuneDashboardCard> createState() =>
      _SignFortuneDashboardCardState();
}

class _SignFortuneDashboardCardState extends State<SignFortuneDashboardCard> {
  bool _signed = false;
  bool _stateKnown = false;
  bool _streakKnown = false;
  String _stateDay = '';
  int _streakDays = 0;
  int _retroSignDays = 0;
  bool _signing = false;

  static const List<(String, String)> _fortuneList = [
    ('本地提示 · 下界探宝', '宜：下界探宝 忌：直线下挖'),
    ('本地提示 · 武器附魔', '宜：附魔武器 忌：直视末影人'),
    ('本地提示 · 建造庇护所', '宜：建造庇护所 忌：夜晚逗留'),
    ('本地提示 · 驯服伙伴', '宜：驯服野狼 忌：岩浆游泳'),
    ('本地提示 · 钻石探索', '宜：挖掘钻石 忌：挑衅铁傀儡'),
    ('本地提示 · 末地探索', '宜：探索末地 忌：忘带金苹果'),
    ('本地提示 · 农田建设', '宜：开垦农田 忌：乱拆红石线'),
  ];

  (String, String) get _todayFortune {
    final todayStr = AutoSignService.instance.serverTodayStr;
    final idx = (todayStr.hashCode.abs()) % _fortuneList.length;
    return _fortuneList[idx];
  }

  @override
  void initState() {
    super.initState();
    _syncLocalState();
    if (widget.isPreview) return;
    AutoSignService.instance.addListener(_onAutoSignChanged);
    DioClient.sessionChanges.addListener(_onAccountChanged);
    _checkSignStatus();
  }

  void _applyHeader(SignHeaderInfo info) {
    if (info.hasPersonalState && DioClient.isLoggedIn) {
      _stateKnown = true;
      _signed = info.isSignedToday;
      _retroSignDays = info.retroSignDays;
    }
    if (info.hasContinuousDays && DioClient.isLoggedIn) {
      _streakDays = info.continuousDays;
      _streakKnown = true;
    }
  }

  void _syncLocalState() {
    final service = AutoSignService.instance;
    final day = service.serverTodayStr;
    if (_stateDay != day) {
      _signed = false;
      _stateKnown = false;
      _streakKnown = false;
      _streakDays = 0;
      _retroSignDays = 0;
    }
    _stateDay = day;
    final state = service.confirmedTodayState;
    if (state != null) {
      _stateKnown = true;
      _signed = state;
    }
    final days = service.currentContinuousDays;
    if (days != null) {
      _streakDays = days;
      _streakKnown = true;
    }
    final cached = KlpbbsApi.cachedSignHeaderInfo;
    if (cached != null) _applyHeader(cached);
  }

  void _onAccountChanged() {
    if (!mounted) return;
    setState(() {
      _stateDay = '';
      _signing = false;
      _syncLocalState();
    });
    _checkSignStatus();
  }

  String get _statusText {
    if (!DioClient.isLoggedIn) return '登录后查看签到状态';
    if (!_stateKnown || _stateDay != AutoSignService.instance.serverTodayStr) {
      return '签到状态待确认';
    }
    if (_signed) {
      return _streakKnown && _streakDays > 0
          ? '已连续打卡 $_streakDays 天'
          : '今日已完成打卡';
    }
    return _retroSignDays > 0 ? '可补签 $_retroSignDays 天' : '今日尚未打卡';
  }

  @override
  void dispose() {
    if (!widget.isPreview) {
      AutoSignService.instance.removeListener(_onAutoSignChanged);
      DioClient.sessionChanges.removeListener(_onAccountChanged);
    }
    super.dispose();
  }

  void _onAutoSignChanged() {
    if (!mounted || widget.isPreview) return;
    setState(_syncLocalState);
  }

  Future<void> _checkSignStatus() async {
    final session = DioClient.sessionKey;
    final day = AutoSignService.instance.serverTodayStr;
    if (!DioClient.isLoggedIn) return;
    try {
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: false);
      if (mounted &&
          session == DioClient.sessionKey &&
          day == AutoSignService.instance.serverTodayStr) {
        setState(() {
          _stateDay = day;
          _applyHeader(info);
        });
      }
    } catch (_) {}
  }

  Future<void> _handleSign() async {
    if (_signing) return;
    if (widget.isPreview) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('布局预览中不会提交签到')));
      return;
    }
    if (!DioClient.isLoggedIn) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }

    if (_signed) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SignRankPage()),
      );
      return;
    }

    final session = DioClient.sessionKey;
    final day = AutoSignService.instance.serverTodayStr;
    setState(() => _signing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await KlpbbsApi.signIn();
      if (mounted &&
          session == DioClient.sessionKey &&
          day == AutoSignService.instance.serverTodayStr) {
        final success = res.confirmed;
        setState(() {
          if (success) {
            _signed = true;
            _stateKnown = true;
            _stateDay = day;
          }
          if (res.continuousDays != null) {
            _streakDays = res.continuousDays!;
            _streakKnown = true;
          }
        });
        if (success) {
          await AutoSignService.instance.markSignedToday(
            rank: res.rank,
            continuousDays: res.continuousDays,
            expectedSession: session,
            rewardIron: res.rewardIron,
            rewardExp: res.rewardExp,
            notify: res.success,
          );
          if (!mounted ||
              session != DioClient.sessionKey ||
              day != AutoSignService.instance.serverTodayStr) {
            return;
          }
          if (res.alreadySigned) {
            messenger.showSnackBar(SnackBar(content: Text(res.message)));
            return;
          }
          _showSignSuccessDialog(
            context: context,
            message: res.message.isNotEmpty ? res.message : '打卡成功！',
            iron: res.rewardIron,
            exp: res.rewardExp,
            rank: res.rank,
            days: res.continuousDays,
          );
        } else {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(
                content:
                    Text(res.message.isNotEmpty ? res.message : '打卡未完成，请稍后重试')),
          );
        }
      }
    } catch (e) {
      if (mounted && session == DioClient.sessionKey) {
        messenger.showSnackBar(SnackBar(content: Text('签到异常: $e')));
      }
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _signing = false);
      }
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
              child: Icon(Icons.check_circle_rounded,
                  color: scheme.primary, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iron != null && iron.isNotEmpty)
              ListTile(
                dense: true,
                leading:
                    Icon(Icons.monetization_on_rounded, color: scheme.primary),
                title: const Text('获得铁粒'),
                trailing: Text('+$iron 粒',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                        fontSize: 14)),
              ),
            if (exp != null && exp.isNotEmpty)
              ListTile(
                dense: true,
                leading: Icon(Icons.star_rounded, color: scheme.primary),
                title: const Text('获得经验'),
                trailing: Text('+$exp 点',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                        fontSize: 14)),
              ),
            if (rank != null && rank > 0)
              ListTile(
                dense: true,
                leading:
                    Icon(Icons.emoji_events_rounded, color: scheme.primary),
                title: const Text('今日排名'),
                trailing: Text('第 $rank 名',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                        fontSize: 14)),
              ),
            if (days != null && days > 0)
              ListTile(
                dense: true,
                leading:
                    Icon(Icons.calendar_today_rounded, color: scheme.primary),
                title: const Text('连续签到'),
                trailing: Text('$days 天',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                        fontSize: 14)),
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
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SignRankPage()));
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
    final title = (customTitle != null && customTitle.isNotEmpty)
        ? customTitle
        : '签到与游戏提示';

    final rawDataStyle =
        widget.item.customParams['dataStyle'] as String? ?? 'auto';
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
    final accent = DashboardCardTheme.of(context).accentColor;
    final fortune = _todayFortune;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withAlpha(24),
          ),
          child: Icon(Icons.auto_awesome_rounded, size: 18, color: accent),
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
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                _statusText,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  color: _stateKnown && !_signed && _retroSignDays > 0
                      ? Colors.orange.shade800
                      : colorScheme.outline,
                  fontWeight: _stateKnown && !_signed && _retroSignDays > 0
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            visualDensity: VisualDensity.compact,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _signing ? null : _handleSign,
          child: Text(
            !DioClient.isLoggedIn
                ? '登录'
                : _signed
                    ? '已签'
                    : (_signing ? '签到中' : '签到'),
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedLOD(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = DashboardCardTheme.of(context).accentColor;
    final fortune = _todayFortune;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.event_available_rounded, size: 17, color: accent),
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
            )),
            InkWell(
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SignRankPage())),
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
              color: accent.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withAlpha(60), width: 0.8),
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
                          Icon(Icons.stars_rounded, color: accent, size: 16),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              fortune.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        fortune.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5, color: colorScheme.outline),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: !_stateKnown
                              ? colorScheme.onSurfaceVariant
                              : _signed
                                  ? accent
                                  : colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _signed
                        ? colorScheme.secondaryContainer
                        : colorScheme.primary,
                    foregroundColor: _signed
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: _signing ? null : _handleSign,
                  child: Text(!DioClient.isLoggedIn
                      ? '登录'
                      : _signed
                          ? '已打卡'
                          : (_signing ? '打卡中' : '立即签到')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
