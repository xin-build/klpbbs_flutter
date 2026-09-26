import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../core/main_tab_controller.dart';
import '../core/write_confirm.dart';
import '../models/sign_entry.dart';
import '../services/auto_sign_service.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/pagination_control.dart';
import '../widgets/thread_card.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/year_month_picker_dialog.dart';
import 'credit_page.dart';
import 'magic_page.dart';
import 'settings_page.dart';
import 'user_space_page.dart';

/// 每日签到与排行榜（深度融合 App 现代 Material 3 设计系统，100% 对齐官方 k_misign 规则）
class SignRankPage extends StatefulWidget {
  const SignRankPage({super.key});

  @override
  State<SignRankPage> createState() => _SignRankPageState();
}

class _SignRankPageState extends State<SignRankPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _tabs = [
    ('today', '今日排行', Icons.today_rounded),
    ('month', '本月排行', Icons.calendar_view_month_rounded),
    ('zong', '总排行', Icons.emoji_events_rounded),
    ('rewardlist', '奖励排行', Icons.monetization_on_rounded),
    ('calendar', '签到日历', Icons.event_note_rounded),
  ];

  late final TabController _tabController;
  late Future<List<SignEntry>> _future;
  int _currentTabIndex = 0;
  String _op = 'today';
  int _page = 1;

  // 实时头部数据
  SignHeaderInfo _headerInfo = const SignHeaderInfo();
  bool _loadingHeader = false;
  int? _myUid;
  String? _myUsername;

  // 签到日历状态
  Set<int> _signedDays = {};
  bool _datesLoaded = false;
  int _calYear = 0;
  int _calMonth = 0;

  // 官方 Discuz k_misign 签到等级对照表（https://klpbbs.com/k_misign-misc.html?operation=leval）
  static const _officialLevels = [
    ('LV.1 原木', 1, '1 天'),
    ('LV.2 圆石', 3, '3 天'),
    ('LV.3 煤炭', 7, '7 天'),
    ('LV.4 铁锭', 15, '15 天'),
    ('LV.5 金锭', 30, '30 天'),
    ('LV.6 青金石', 60, '60 天'),
    ('LV.7 绿宝石', 120, '120 天'),
    ('LV.8 钻石', 240, '240 天'),
    ('LV.9 下界合金锭', 365, '365 天'),
    ('LV.10 黑曜石', 750, '750 天'),
    ('LV.11 基岩', 1500, '1500 天'),
  ];

  // 官方前排额外 EP 经验奖励表（https://klpbbs.com/k_misign-misc.html?operation=rewardrule）
  static const _topRankRewards = [
    ('第 1 ~ 10 名', '+10 EP 经验'),
    ('第 11 ~ 20 名', '+9 EP 经验'),
    ('第 21 ~ 30 名', '+8 EP 经验'),
    ('第 31 ~ 40 名', '+7 EP 经验'),
    ('第 41 ~ 50 名', '+6 EP 经验'),
    ('第 51 ~ 60 名', '+5 EP 经验'),
    ('第 61 ~ 70 名', '+4 EP 经验'),
    ('第 71 ~ 80 名', '+3 EP 经验'),
    ('第 81 ~ 90 名', '+2 EP 经验'),
    ('第 91 ~ 150 名', '+1 EP 经验'),
  ];

  /// 实时拉取头部统计与个人签到数据（严格与网页端实时同步）
  Future<void> _loadHeaderRealtime({bool forceRefresh = true}) async {
    if (!mounted) return;
    setState(() => _loadingHeader = true);
    try {
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: forceRefresh);
      int? uid = info.uid ?? _myUid;
      String? username = info.username.isNotEmpty ? info.username : _myUsername;

      if (uid == null || uid <= 0 || username == null || username.isEmpty) {
        final cachedUid = await KlpbbsApi.getMyUid();
        if (cachedUid != null && cachedUid > 0) {
          uid = cachedUid;
          final space = await KlpbbsApi.getUserSpace(cachedUid);
          if (space != null && space.username.isNotEmpty) {
            username = space.username;
          }
        }
      }

      if (mounted) {
        final serverNow = AutoSignService.instance.estimatedServerNow;
        // 严格以服务端真实权威数据为最高准则，杜绝本地脏缓存反向篡改
        final isSigned = info.isSignedToday;

        // 统计人数保底：如果解析到的今日签到人数为 0，而当前已有排名（如第 50 名），则人数至少为该排名
        int effectiveTodayCount = info.todaySignCount;
        if (effectiveTodayCount <= 0 && info.mySignRank != null && info.mySignRank! > 0) {
          effectiveTodayCount = info.mySignRank!;
        }
        if (effectiveTodayCount <= 0 && _headerInfo.todaySignCount > 0) {
          effectiveTodayCount = _headerInfo.todaySignCount;
        }

        setState(() {
          _myUid = uid;
          _myUsername = username;
          _headerInfo = info.copyWith(
            uid: uid,
            username: username,
            isSignedToday: isSigned,
            todaySignCount: effectiveTodayCount,
          );
          _loadingHeader = false;
          if ((_calYear == 0 || _calYear == serverNow.year) &&
              (_calMonth == 0 || _calMonth == serverNow.month)) {
            if (isSigned) {
              _signedDays.add(serverNow.day);
            } else {
              _signedDays.remove(serverNow.day);
            }
          }
        });
        if (isSigned) {
          await AutoSignService.instance.markSignedToday(
            rank: info.mySignRank,
            continuousDays: info.continuousDays,
          );
        } else {
          await AutoSignService.instance.markUnsignedToday();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHeader = false);
    }
  }

  /// 排行榜数据加载（严格实时直连服务器获取；失败时降级本地缓存）
  Future<List<SignEntry>> _loadRankList(String op, {int page = 1, bool forceRefresh = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'sign_rank_${op}_$page';
    try {
      final list = await KlpbbsApi.getSignRank(op, page: page, forceRefresh: forceRefresh);
      if (list.isNotEmpty) {
        final json = list
            .map(
              (e) =>
                  '${e.name}|${e.totalDays}|${e.monthDays}|${e.rewardText}|${e.timeText}|${e.uid}|${e.usergroup}|${e.totalReward}',
            )
            .toList();
        await prefs.setStringList(key, json);

        // 自愈同步：若当前头部统计人数为 0，且加载的是今日排行，可用今日排行首屏人数做权威保底
        if ((_headerInfo.todaySignCount == 0 || _headerInfo.todaySignCount < list.length) &&
            (op == 'today' || op.isEmpty)) {
          if (mounted) {
            setState(() {
              _headerInfo = _headerInfo.copyWith(
                todaySignCount: list.length > _headerInfo.todaySignCount ? list.length : _headerInfo.todaySignCount,
              );
            });
          }
        }
        return list;
      }
    } catch (_) {}

    final cached = prefs.getStringList(key) ?? const [];
    return [
      for (final line in cached)
        if (line.contains('|'))
          SignEntry(
            name: line.split('|')[0],
            totalDays: int.tryParse(line.split('|')[1]) ?? 0,
            monthDays: int.tryParse(line.split('|')[2]) ?? 0,
            rewardText: line.split('|')[3],
            timeText: line.split('|')[4],
            uid: int.tryParse(line.split('|').length > 5 ? line.split('|')[5] : '0') ?? 0,
            usergroup: line.split('|').length > 6 ? line.split('|')[6] : '',
            totalReward: line.split('|').length > 7 ? line.split('|')[7] : '',
          ),
    ];
  }

  /// 加载日历签到记录（以服务端官方日历数据为准）
  Future<void> _loadSignedDays({bool forceRefresh = false}) async {
    final serverNow = AutoSignService.instance.estimatedServerNow;
    final y = _calYear > 0 ? _calYear : serverNow.year;
    final m = _calMonth > 0 ? _calMonth : serverNow.month;
    try {
      final serverSignedDays = await KlpbbsApi.getSignedDaysFromServerCalendar(
        month: m,
        year: y,
        forceRefresh: forceRefresh,
      );
      if (mounted && y == _calYear && m == _calMonth) {
        Set<int> daysToDisplay = Set<int>.from(serverSignedDays);
        if (daysToDisplay.isEmpty) {
          try {
            final sp = await SharedPreferences.getInstance();
            final monthKey = 'sign_dates_$y${m.toString().padLeft(2, '0')}';
            final localDays = sp.getStringList(monthKey) ?? [];
            if (localDays.isNotEmpty) {
              daysToDisplay = localDays.map((d) => int.tryParse(d) ?? 0).where((d) => d > 0).toSet();
            }
          } catch (_) {}
        }
        if (!mounted || y != _calYear || m != _calMonth) return;
        setState(() {
          _signedDays = daysToDisplay;
          if (y == serverNow.year && m == serverNow.month) {
            final isSigned = _headerInfo.isSignedToday || AutoSignService.instance.isSignedToday();
            if (isSigned) {
              _signedDays.add(serverNow.day);
              final streak = _headerInfo.continuousDays > 0
                  ? _headerInfo.continuousDays
                  : AutoSignService.instance.continuousDays;
              if (streak > 1) {
                for (int i = 1; i < streak; i++) {
                  final streakDay = serverNow.day - i;
                  if (streakDay >= 1) _signedDays.add(streakDay);
                }
              }
            } else {
              // 服务端确凿未签，剔除今日
              _signedDays.remove(serverNow.day);
            }
          }
          _datesLoaded = true;
        });

        // 自动反哺落库本地持久化，保证离线与快速切换零延迟
        if (_signedDays.isNotEmpty) {
          try {
            final sp = await SharedPreferences.getInstance();
            final monthKey = 'sign_dates_$y${m.toString().padLeft(2, '0')}';
            await sp.setStringList(monthKey, _signedDays.map((d) => '$d').toList());
          } catch (_) {}
        }

        if (y == serverNow.year && m == serverNow.month && (_headerInfo.isSignedToday || AutoSignService.instance.isSignedToday())) {
          // 服务端权威确认今日已签，自愈同步 AutoSignService
          AutoSignService.instance.markSignedToday(
            rank: _headerInfo.mySignRank,
            continuousDays: _headerInfo.continuousDays,
            rewardIron: _headerInfo.rewardIron,
            notify: AutoSignService.instance.notifyOnResult,
          );
        }
      }
    } catch (_) {
      if (mounted && y == _calYear && m == _calMonth) {
        try {
          final sp = await SharedPreferences.getInstance();
          final monthKey = 'sign_dates_$y${m.toString().padLeft(2, '0')}';
          final localDays = sp.getStringList(monthKey) ?? [];
          final localSet = localDays.map((d) => int.tryParse(d) ?? 0).where((d) => d > 0).toSet();
          if (y == serverNow.year && m == serverNow.month) {
            final isSigned = _headerInfo.isSignedToday || AutoSignService.instance.isSignedToday();
            if (isSigned) {
              localSet.add(serverNow.day);
              final streak = _headerInfo.continuousDays > 0
                  ? _headerInfo.continuousDays
                  : AutoSignService.instance.continuousDays;
              if (streak > 1) {
                for (int i = 1; i < streak; i++) {
                  final streakDay = serverNow.day - i;
                  if (streakDay >= 1) localSet.add(streakDay);
                }
              }
            }
          }
          if (mounted && y == _calYear && m == _calMonth) {
            setState(() {
              _signedDays = localSet;
              _datesLoaded = true;
            });
            return;
          }
        } catch (_) {}
        if (mounted && y == _calYear && m == _calMonth) {
          setState(() => _datesLoaded = true);
        }
      }
    }
  }

  /// 签到成功弹窗
  void _showSignSuccessDialog({
    required String message,
    String? iron,
    String? exp,
    int? rank,
    int? days,
  }) {
    if (!mounted) return;
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withAlpha(100),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant.withAlpha(60)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 10),
                      Text('基础铁粒奖励', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
                      const Spacer(),
                      Text(
                        (iron != null && iron.isNotEmpty) ? '+$iron 粒' : '5~15 粒 (随机)',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 16),
                      ),
                    ],
                  ),
                  if (exp != null && exp.isNotEmpty) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        const Icon(Icons.bolt_rounded, color: Colors.orange, size: 20),
                        const SizedBox(width: 10),
                        Text('前排 EP 经验奖励', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
                        const Spacer(),
                        Text('+$exp EP', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16)),
                      ],
                    ),
                  ],
                  if (rank != null && rank > 0) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: Colors.blue, size: 20),
                        const SizedBox(width: 10),
                        Text('今日签到排名', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
                        const Spacer(),
                        Text('第 $rank 名', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 15)),
                      ],
                    ),
                  ],
                  if (days != null && days > 0) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department_rounded, color: Colors.deepOrange, size: 20),
                        const SizedBox(width: 10),
                        Text('已连续签到', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
                        const Spacer(),
                        Text('$days 天', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 15)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  /// 展示官方 Discuz k_misign 签到等级与奖励规则弹窗（真实对齐官网）
  void _showRewardRuleDialog() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.workspace_premium_rounded, color: Colors.amber.shade700, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('签到规则与等级说明', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 基础奖励说明
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(isDark ? 30 : 20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('基础签到奖励', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                            const SizedBox(height: 2),
                            Text(
                              '每日签到随机获得 5 ~ 15 粒铁粒',
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. 前排签到额外奖励表
                Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      '前排额外 EP 经验奖励',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.outlineVariant.withAlpha(60)),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(1.0),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withAlpha(90),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                        ),
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Text('签到名次', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Text('额外奖励', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                      for (final (rankRange, reward) in _topRankRewards)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Text(rankRange, style: TextStyle(fontSize: 12, color: scheme.onSurface)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Text(reward, style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 3. 签到等级表
                Row(
                  children: [
                    Icon(Icons.military_tech_rounded, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '签到等级称号门槛',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.outlineVariant.withAlpha(60)),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(1.0),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withAlpha(90),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                        ),
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Text('等级称号', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Text('累计/连续天数', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                      for (final (level, _, daysText) in _officialLevels)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Text(level, style: TextStyle(fontSize: 12, color: scheme.onSurface, fontWeight: FontWeight.w500)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Text(daysText, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 4. 道具扩展说明
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withAlpha(80),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.card_giftcard_rounded, size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '道具说明：若因忘记签到导致连续签到中断，可在道具商城使用【补签卡】进行补签。',
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  /// 记录签到日期
  Future<void> _recordSignDay() async {
    final prefs = await SharedPreferences.getInstance();
    final now = AutoSignService.instance.estimatedServerNow;
    final todayStr = AutoSignService.instance.serverTodayStr;
    final key = 'sign_dates_${now.year}${now.month.toString().padLeft(2, '0')}';
    final list = prefs.getStringList(key) ?? [];
    list.add('${now.day}');
    await prefs.setStringList(key, list.toSet().toList());
    await prefs.setString('auto_sign_last_success_date', todayStr);
  }

  bool? _lastAutoSignState;
  bool _isSigning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    mainTabIndex.addListener(_onMainTabChanged);
    final now = AutoSignService.instance.estimatedServerNow;
    _calYear = now.year;
    _calMonth = now.month;
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(_onTabControllerTick);
    _future = _loadRankList(_op, page: _page, forceRefresh: true);
    _loadHeaderRealtime(forceRefresh: true);
    _loadSignedDays();
    _lastAutoSignState = AutoSignService.instance.isSignedToday();
    AutoSignService.instance.addListener(_onAutoSignChanged);
  }

  void _onMainTabChanged() {
    // 切换至每日签到 Tab 时，仅同步当前年月，不频繁自动刷新排行榜，回归手动刷新
    if (mainTabIndex.value == 2 && mounted) {
      final now = AutoSignService.instance.estimatedServerNow;
      if (_calYear != now.year || _calMonth != now.month) {
        setState(() {
          _calYear = now.year;
          _calMonth = now.month;
          _signedDays.clear();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    mainTabIndex.removeListener(_onMainTabChanged);
    AutoSignService.instance.removeListener(_onAutoSignChanged);
    _tabController.removeListener(_onTabControllerTick);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final now = AutoSignService.instance.estimatedServerNow;
      // 跨月或跨天切回时更新本地年月基准，不发起额外网络请求，回归手动刷新
      if (_calYear != now.year || _calMonth != now.month) {
        setState(() {
          _calYear = now.year;
          _calMonth = now.month;
          _signedDays.clear();
        });
      }
    }
  }

  void _onAutoSignChanged() {
    if (!mounted) return;
    final isSigned = AutoSignService.instance.isSignedToday();
    final serverNow = AutoSignService.instance.estimatedServerNow;
    if (_lastAutoSignState == isSigned) {
      // 签到状态实质未变（仅状态文字更新或时钟校准），阻断级联触发全量网络请求
      return;
    }
    _lastAutoSignState = isSigned;
    final isCurrentMonth = _calYear == 0 || (_calYear == serverNow.year && _calMonth == serverNow.month);
    setState(() {
      if (!isSigned) {
        // 零点跨天或状态重置，立即翻转头部状态与排名，防止按钮锁死在已签到
        _headerInfo = _headerInfo.copyWith(
          isSignedToday: false,
          mySignRank: null,
        );
        if (isCurrentMonth) {
          _signedDays.remove(serverNow.day);
        }
      } else {
        if (isCurrentMonth) {
          _signedDays.add(serverNow.day);
        }
      }
    });
    _loadHeaderRealtime(forceRefresh: true);
    if (isCurrentMonth) {
      _loadSignedDays(forceRefresh: true);
    }
  }

  void _onTabControllerTick() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index != _currentTabIndex) {
      _switchTab(_tabController.index);
    }
  }

  void _switchTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final op = _tabs[index].$1;
    setState(() {
      _currentTabIndex = index;
      _op = op;
      _page = 1;
      if (_tabController.index != index) {
        _tabController.animateTo(index);
      }
      if (op != 'calendar') {
        _future = _loadRankList(op, page: 1, forceRefresh: true);
      } else {
        _loadSignedDays(forceRefresh: true);
      }
    });
  }

  void _goPage(int page) {
    if (page < 1) return;
    setState(() {
      _page = page;
      _future = _loadRankList(_op, page: page, forceRefresh: true);
    });
  }

  void _reload({bool forceRefresh = true}) {
    setState(() {
      if (_op != 'calendar') {
        _future = _loadRankList(_op, page: _page, forceRefresh: forceRefresh);
      }
    });
    _loadHeaderRealtime(forceRefresh: forceRefresh);
    _loadSignedDays(forceRefresh: forceRefresh);
  }

  bool get _isSignedToday => _headerInfo.isSignedToday;

  int get _streakDays => _headerInfo.continuousDays > 0 ? _headerInfo.continuousDays : 0;

  Future<void> _signIn() async {
    if (_isSigning || _isSignedToday) return;
    final confirmed = await confirmWrite(context, '签到');
    if (!confirmed) return;
    if (!mounted) return;
    setState(() => _isSigning = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await KlpbbsApi.signIn();
      final isAlready = res.message.contains('已签到') ||
          res.message.contains('签过到') ||
          res.message.contains('今日已签') ||
          res.message.contains('无需重复签到') ||
          res.message.contains('k_misign:tdyq') ||
          res.message.contains('k_misign:signed') ||
          res.message.contains('已打卡');
      bool isReallySigned = res.success || (res.rank != null && res.rank! > 0) || isAlready;
      if (!isReallySigned) {
        // 二次通过服务端权威页面状态核查
        final header = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
        if (header.isSignedToday) isReallySigned = true;
      }
      if (isReallySigned) {
        await _recordSignDay();
        await AutoSignService.instance.markSignedToday(
          rank: res.rank ?? _headerInfo.mySignRank,
          continuousDays: res.continuousDays ?? _headerInfo.continuousDays,
          rewardIron: res.rewardIron ?? (_headerInfo.rewardIron.isNotEmpty ? _headerInfo.rewardIron : null),
          rewardExp: res.rewardExp,
          notify: true,
        );
        final serverNow = AutoSignService.instance.estimatedServerNow;
        if (mounted) {
          setState(() {
            if ((_calYear == 0 || _calYear == serverNow.year) &&
                (_calMonth == 0 || _calMonth == serverNow.month)) {
              _signedDays.add(serverNow.day);
            }
            _headerInfo = _headerInfo.copyWith(
              todaySignCount: _headerInfo.todaySignCount > 0 ? _headerInfo.todaySignCount + 1 : 1,
              mySignRank: res.rank ?? _headerInfo.mySignRank,
              isSignedToday: true,
              continuousDays: res.continuousDays ?? (_headerInfo.continuousDays > 0 ? _headerInfo.continuousDays + 1 : 1),
              rewardIron: res.rewardIron ?? _headerInfo.rewardIron,
              totalDays: _headerInfo.totalDays > 0 ? _headerInfo.totalDays + 1 : 1,
            );
          });
        }
        // 清空所有本地预加载缓存，确保立即与网页端 100% 实时同步
        final prefs = await SharedPreferences.getInstance();
        for (final t in _tabs) {
          for (var p = 1; p <= 5; p++) {
            await prefs.remove('sign_rank_${t.$1}_$p');
          }
        }
        _showSignSuccessDialog(
          message: isAlready
              ? '今日已签到'
              : res.message,
          iron: (res.rewardIron != null && res.rewardIron!.isNotEmpty)
              ? res.rewardIron
              : (_headerInfo.rewardIron.isNotEmpty ? _headerInfo.rewardIron : null),
          exp: res.rewardExp,
          rank: res.rank ?? _headerInfo.mySignRank,
          days: res.continuousDays ?? _headerInfo.continuousDays,
        );
        _reload(forceRefresh: true);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(res.message)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('签到异常：$e')));
    } finally {
      if (mounted) setState(() => _isSigning = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      appBar: AppBar(
        automaticallyImplyLeading: !isDesktop,
        leading: (isDesktop && !canPop) ? null : const GlobalNavLeading(),
        leadingWidth: (isDesktop && !canPop) ? null : GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('每日签到', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        bottom: _loadingHeader
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '实时刷新',
            onPressed: () => _reload(forceRefresh: true),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: '自动签到设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('自动签到')),
                    body: SettingsPage.buildCategoryView(SettingsCategory.sign),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            tooltip: '积分记录流水',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CreditPage(initialTabIndex: 2),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(forceRefresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 顶部 Hero 聚合个人卡片
                    _buildModernHeroCard(),
                    const SizedBox(height: 16),

                    // 2. Tab 切换导航（Material 3 药丸胶囊风格）
                    _buildModernTabBar(),
                    const SizedBox(height: 14),

                    // 3. 内容区：排行榜列表 / 签到日历
                    _currentTabIndex == 4
                        ? _buildModernCalendar()
                        : _buildModernRankList(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 现代 Material 3 风格 Hero 签到卡片
  Widget _buildModernHeroCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isSigned = _isSignedToday;

    final continuous = _headerInfo.continuousDays > 0 ? _headerInfo.continuousDays : _streakDays;
    final total = _headerInfo.totalDays > 0 ? _headerInfo.totalDays : _signedDays.length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withAlpha(80)),
      ),
      color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            // 顶部：用户信息 + 签到按钮
            Row(
              children: [
                UserAvatarWidget(
                  uid: _headerInfo.uid ?? _myUid,
                  author: _headerInfo.username.isNotEmpty
                      ? _headerInfo.username
                      : (_myUsername != null && _myUsername!.isNotEmpty
                          ? _myUsername!
                          : '我的账号'),
                  size: 46,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _headerInfo.username.isNotEmpty
                                  ? _headerInfo.username
                                  : (_myUsername != null && _myUsername!.isNotEmpty
                                      ? _myUsername!
                                      : '苦力怕论坛坛友'),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _headerInfo.signLevel.isNotEmpty ? _headerInfo.signLevel : 'Lv.1',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isSigned && _headerInfo.mySignRank != null && _headerInfo.mySignRank! > 0
                            ? '今日签到排名：第 ${_headerInfo.mySignRank} 名'
                            : (isSigned ? '今日已完成签到' : '今日尚未签到，签到领铁粒与经验'),
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // 签到大按钮
                FilledButton.icon(
                  onPressed: (_isSigning || _loadingHeader)
                      ? null
                      : (isSigned
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _headerInfo.mySignRank != null && _headerInfo.mySignRank! > 0
                                        ? '🎉 今日已签到！您的签到排名为第 ${_headerInfo.mySignRank} 名'
                                        : '🎉 今日已完成签到，无需重复签到',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          : _signIn),
                  style: FilledButton.styleFrom(
                    backgroundColor: isSigned ? scheme.secondaryContainer : scheme.primary,
                    foregroundColor: isSigned ? scheme.onSecondaryContainer : scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _isSigning
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                          ),
                        )
                      : Icon(isSigned ? Icons.check_circle_rounded : Icons.touch_app_rounded, size: 18),
                  label: Text(
                    _isSigning ? '签到中...' : (isSigned ? '今日已签' : '立即签到'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 中间：4项核心数据现代化卡片
            Row(
              children: [
                Expanded(
                  child: _buildModernStatItem(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: Colors.deepOrange,
                    label: '连续签到',
                    value: '$continuous',
                    unit: '天',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildModernStatItem(
                    icon: Icons.military_tech_rounded,
                    iconColor: Colors.blue,
                    label: '签到等级',
                    value: _headerInfo.signLevel.isNotEmpty ? _headerInfo.signLevel : 'Lv.1',
                    unit: '',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildModernStatItem(
                    icon: Icons.monetization_on_rounded,
                    iconColor: Colors.amber.shade700,
                    label: '基础奖励',
                    value: '5~15',
                    unit: '粒',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildModernStatItem(
                    icon: Icons.event_available_rounded,
                    iconColor: Colors.teal,
                    label: '累计签到',
                    value: '$total',
                    unit: '天',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 底部：全站今日之星与规则入口
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withAlpha(70),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_alt_rounded, size: 15, color: Colors.blueAccent),
                  const SizedBox(width: 5),
                  Text('今日已签 ', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  Text(
                    '${_headerInfo.todaySignCount > 0 ? _headerInfo.todaySignCount : (_headerInfo.mySignRank != null && _headerInfo.mySignRank! > 0 ? _headerInfo.mySignRank! : "--")} 人',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.primary),
                  ),
                  if (_headerInfo.starUsername.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('·', style: TextStyle(color: scheme.outline)),
                    const SizedBox(width: 8),
                    const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        if (_headerInfo.starUid != null && _headerInfo.starUid! > 0) {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => UserSpacePage(uid: _headerInfo.starUid!)),
                          );
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('今日之星: ', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          Text(
                            _headerInfo.starUsername,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (_headerInfo.highestCount > 0) ...[
                    Text(
                      '历史最高: ${_headerInfo.highestCount}人',
                      style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    ),
                    const SizedBox(width: 8),
                    Text('·', style: TextStyle(color: scheme.outline)),
                    const SizedBox(width: 8),
                  ],
                  InkWell(
                    onTap: _showRewardRuleDialog,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.help_outline_rounded, size: 14, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '奖励规则',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernStatItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerHighest.withAlpha(80) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 1),
                  Text(
                    unit,
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 现代 Material 3 药丸胶囊风格 Tab 导航
  Widget _buildModernTabBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                showCheckmark: false,
                avatar: Icon(
                  _tabs[i].$3,
                  size: 16,
                  color: _currentTabIndex == i ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
                label: Text(_tabs[i].$2),
                labelStyle: TextStyle(
                  fontWeight: _currentTabIndex == i ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                  color: _currentTabIndex == i ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
                selected: _currentTabIndex == i,
                selectedColor: scheme.primary,
                backgroundColor: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (selected) {
                  if (selected) {
                    _switchTab(i);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  /// 现代排行榜列表（Top 3 奖牌勋章 + 丰富坛友数据卡片）
  Widget _buildModernRankList() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isRewardOp = _op == 'rewardlist' || _op == 'reward';

    return FutureBuilder<List<SignEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(50),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(30),
            child: Center(
              child: Column(
                children: [
                  Text('排行榜加载失败：${snap.error}'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _reload(forceRefresh: true),
                    child: const Text('重新加载'),
                  ),
                ],
              ),
            ),
          );
        }
        final entries = snap.data ?? [];
        if (entries.isEmpty) {
          return const EmptyView(
            icon: Icons.leaderboard_outlined,
            title: '暂无更多排行数据',
            subtitle: '下拉即可刷新或稍后重试',
          );
        }

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant.withAlpha(60)),
          ),
          color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
          child: Column(
            children: [
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entries.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: scheme.outlineVariant.withAlpha(40),
                ),
                itemBuilder: (context, i) {
                  final e = entries[i];
                  final rewardDisplay = e.totalReward.isNotEmpty
                      ? e.totalReward
                      : (e.rewardText.isNotEmpty ? e.rewardText : '');

                  return InkWell(
                    onTap: () {
                      if (e.uid > 0) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => UserSpacePage(uid: e.uid)),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          UserAvatarWidget(uid: e.uid, author: e.name, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        e.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),
                                    if (e.displayLevel.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: scheme.primary.withAlpha(20),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          e.displayLevel,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: scheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    Text('总签到: ${e.totalDays}天', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                    Text('月签到: ${e.monthDays}天', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                    if (e.timeText.isNotEmpty)
                                      Text(e.timeText.replaceAll('2026-', ''), style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (isRewardOp && rewardDisplay.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.amber.withAlpha(25),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.withAlpha(80)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.monetization_on_rounded, size: 14, color: Colors.amber),
                                  const SizedBox(width: 4),
                                  Text(
                                    rewardDisplay,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.amber.shade400 : Colors.amber.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline.withAlpha(150)),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // 分页控制器
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: PaginationControl(
                  page: _page,
                  hasMore: entries.length >= 10,
                  onPageChanged: _goPage,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 现代 Material 3 签到日历与进阶卡片
  void _changeMonth(int delta) {
    final now = AutoSignService.instance.estimatedServerNow;
    if (delta > 0) {
      if (_calYear > now.year || (_calYear == now.year && _calMonth >= now.month)) {
        return; // 禁止翻到未来月份
      }
    }
    setState(() {
      var m = _calMonth + delta;
      var y = _calYear;
      if (m < 1) {
        m = 12;
        y -= 1;
      } else if (m > 12) {
        m = 1;
        y += 1;
      }
      _calMonth = m;
      _calYear = y;
      _signedDays = {};
      _datesLoaded = false;
    });
    _loadSignedDays(forceRefresh: true);
  }

  Widget _buildModernCalendar() {
    if (!_datesLoaded) {
      return const Padding(
        padding: EdgeInsets.all(50),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final now = AutoSignService.instance.estimatedServerNow;
    final firstDay = DateTime(_calYear, _calMonth, 1);
    final daysInMonth = DateTime(_calYear, _calMonth + 1, 0).day;
    final leading = firstDay.weekday % 7; // 周日为 0
    final week = ['日', '一', '二', '三', '四', '五', '六'];
    final isCurrentOrFutureMonth =
        _calYear > now.year || (_calYear == now.year && _calMonth >= now.month);
    final isCurrentMonth = _calYear == now.year && _calMonth == now.month;

    return Column(
      children: [
        // 0. 补签卡挽回断签提示栏
        _buildRetroSignBanner(),

        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant.withAlpha(80)),
          ),
          color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                // 1. 月份切换头部
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => _changeMonth(-1),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final res = await YearMonthPickerDialog.show(
                          context,
                          initialYear: _calYear,
                          initialMonth: _calMonth,
                        );
                        if (res != null && mounted) {
                          if (res.$1 != _calYear || res.$2 != _calMonth) {
                            setState(() {
                              _calYear = res.$1;
                              _calMonth = res.$2;
                              _signedDays = {};
                              _datesLoaded = false;
                            });
                            _loadSignedDays(forceRefresh: true);
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$_calYear 年 $_calMonth 月',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_drop_down_circle_outlined,
                                  size: 16,
                                  color: scheme.primary,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isCurrentMonth
                                  ? '本月已出勤 ${_signedDays.length} 天 · 连续签到 $_streakDays 天'
                                  : '该月已出勤 ${_signedDays.length} 天 · 点击快速切换',
                              style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: isCurrentOrFutureMonth ? null : () => _changeMonth(1),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. 星期栏
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withAlpha(100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      for (final w in week)
                        Expanded(
                          child: Center(
                            child: Text(
                              w,
                              style: TextStyle(
                                color: scheme.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 3. 日期网格
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.2,
                  children: [
                    for (var i = 0; i < leading; i++) const SizedBox(),
                    for (var d = 1; d <= daysInMonth; d++)
                      _buildModernDayCell(d, now),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 4. 下一等级进阶卡片
        _buildNextLevelProgressCard(),
      ],
    );
  }

  Widget _buildRetroSignBanner() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final now = AutoSignService.instance.estimatedServerNow;
    final isCurrentMonth = _calYear == now.year && _calMonth == now.month;
    if (!isCurrentMonth) return const SizedBox.shrink();

    final bid = _headerInfo.retroSignBid;
    final tip = _headerInfo.retroSignTip;
    final days = _headerInfo.retroSignDays;

    final hasMissedPastDays = List.generate(now.day - 1, (i) => i + 1)
        .any((d) => !_signedDays.contains(d));

    if (bid == null && !hasMissedPastDays && tip.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayText = tip.isNotEmpty
        ? tip
        : (days > 0 ? '您有 $days 天可补签，使用补签卡可挽回连续天数' : '本月有断签记录，可使用补签卡恢复连签');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withAlpha(isDark ? 80 : 130),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.tertiary.withAlpha(60), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(Icons.history_toggle_off_rounded, color: scheme.tertiary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '补签卡挽回断签',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayText,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onTertiaryContainer.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.tertiary,
              foregroundColor: scheme.onTertiary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _handleRetroSign(bid),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_fix_high_rounded, size: 14),
                SizedBox(width: 4),
                Text('立即补签', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRetroSign(int? bid) async {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录论坛账号')),
      );
      return;
    }

    int? targetBid = bid ?? _headerInfo.retroSignBid;
    if (targetBid == null) {
      try {
        final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
        targetBid = info.retroSignBid;
      } catch (_) {}
    }

    if (targetBid == null) {
      if (!mounted) return;
      final buy = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.shopping_bag_rounded, color: Colors.blue),
              SizedBox(width: 8),
              Text('获取补签卡'),
            ],
          ),
          content: const Text('论坛签到页面暂未指定当前断签的补签批次 ID，或者您需要先在道具商城购买【补签卡】。是否前往道具商城？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('前往商城')),
          ],
        ),
      );
      if (buy == true && mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MagicPage()));
      }
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high_rounded, color: Colors.teal),
            SizedBox(width: 8),
            Text('使用补签卡'),
          ],
        ),
        content: Text(
          _headerInfo.retroSignTip.isNotEmpty
              ? '${_headerInfo.retroSignTip}\n\n是否立即消耗 1 张补签卡进行补签？'
              : '确定消耗 1 张补签卡，恢复最近的断签并续接连续签到天数吗？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认补签')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(const SnackBar(content: Text('正在提交补签申请...')));

    final res = await KlpbbsApi.useRetroSignCard(bid: targetBid);
    if (!mounted) return;

    if (res.success) {
      scaffold.showSnackBar(SnackBar(content: Text(res.message), backgroundColor: Colors.green));
      _reload(forceRefresh: true);
    } else {
      if (res.message.contains('商城') || res.message.contains('暂无')) {
        final goToShop = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('背包暂无补签卡'),
            content: Text('${res.message}\n\n是否立即前往道具商城选购？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('前往购买')),
            ],
          ),
        );
        if (goToShop == true && mounted) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MagicPage()));
        }
      } else {
        scaffold.showSnackBar(SnackBar(content: Text(res.message)));
      }
    }
  }

  Widget _buildModernDayCell(int day, DateTime now) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final signed = _signedDays.contains(day);
    final isToday = _calYear == now.year && _calMonth == now.month && day == now.day;
    final isPastMissed = _calYear == now.year && _calMonth == now.month && day < now.day && !signed;

    final cell = Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: signed
              ? scheme.primary
              : (isToday ? scheme.primaryContainer.withAlpha(120) : (isPastMissed ? scheme.errorContainer.withAlpha(30) : Colors.transparent)),
          borderRadius: BorderRadius.circular(10),
          border: isToday && !signed
              ? Border.all(color: scheme.primary, width: 1.5)
              : (isPastMissed ? Border.all(color: scheme.error.withAlpha(60), width: 1) : null),
          boxShadow: signed
              ? [
                  BoxShadow(
                    color: scheme.primary.withAlpha(60),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                fontWeight: signed || isToday ? FontWeight.bold : FontWeight.normal,
                color: signed
                    ? scheme.onPrimary
                    : (isToday
                        ? scheme.primary
                        : (isPastMissed
                            ? scheme.error
                            : (isDark ? scheme.onSurface : const Color(0xFF334155)))),
              ),
            ),
            if (signed)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: scheme.onPrimary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );

    if (isPastMissed) {
      return InkWell(
        onTap: () => _handleRetroSign(_headerInfo.retroSignBid),
        borderRadius: BorderRadius.circular(10),
        child: cell,
      );
    }

    return cell;
  }

  /// 签到等级进阶提示卡片（按官方总签到天数规则精准计算）
  Widget _buildNextLevelProgressCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final total = _headerInfo.totalDays > 0 ? _headerInfo.totalDays : _signedDays.length;
    final continuous = _headerInfo.continuousDays > 0 ? _headerInfo.continuousDays : _streakDays;

    // 官方等级按累计签到总天数判定
    (String, int, String)? nextLevel;
    for (final r in _officialLevels) {
      if (total < r.$2) {
        nextLevel = (r.$1, r.$2, r.$3);
        break;
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withAlpha(60)),
      ),
      color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('签到等级进阶', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                if (_headerInfo.totalDays > 0)
                  Text(
                    '总签到 $total 天 · 连续 $continuous 天',
                    style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.bold),
                  )
                else
                  Text(
                    '已打卡 $total 天',
                    style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (nextLevel != null) ...[
              Text(
                _headerInfo.totalDays > 0
                    ? '当前等级【${_headerInfo.signLevel.isNotEmpty ? _headerInfo.signLevel : "Lv.1"}】（累计签到 $total 天），距离下一称号【${nextLevel.$1}】还需累计签到 ${nextLevel.$2 - total} 天（累计达到 ${nextLevel.$3} 即可晋升）。'
                    : '签到等级根据累计总签到天数评定，累计达到 ${nextLevel.$3} 即可晋升为【${nextLevel.$1}】。',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.45),
              ),
            ] else ...[
              Text(
                '恭喜您！累计总签到已达 $total 天，已达到论坛最高签到等级【LV.11 基岩】（累计 1500 天以上）！',
                style: const TextStyle(fontSize: 12.5, color: Colors.amber, fontWeight: FontWeight.w600, height: 1.45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

