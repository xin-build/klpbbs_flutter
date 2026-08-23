import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/write_confirm.dart';
import '../models/sign_entry.dart';
import '../widgets/global_nav.dart';
import '../widgets/pagination_control.dart';
import 'credit_page.dart';

/// 签到排行（k_misign 只读展示）
class SignRankPage extends StatefulWidget {
  const SignRankPage({super.key});

  @override
  State<SignRankPage> createState() => _SignRankPageState();
}

class _SignRankPageState extends State<SignRankPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    ('today', '今日排行'),
    ('month', '本月排行'),
    ('zong', '总排行'),
    ('calendar', '签到日历'),
  ];

  late final TabController _tabController;
  late Future<List<SignEntry>> _future;
  String _op = 'today';
  int _page = 1;

  // 签到日历状态
  Set<int> _signedDays = {};
  bool _datesLoaded = false;
  int _calYear = 0;
  int _calMonth = 0;
  ({int amount, String timeText})? _todaySignReward;

  /// 带缓存的排行加载（失败时回退缓存）
  Future<List<SignEntry>> _loadWithCache(String op, {int page = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'sign_rank_${op}_$page';
    try {
      final list = await KlpbbsApi.getSignRank(op, page: page);
      if (list.isNotEmpty) {
        // 写缓存（存 JSON）
        final json = list
            .map(
              (e) =>
                  '${e.name}|${e.totalDays}|${e.monthDays}|${e.rewardText}|${e.timeText}|${e.uid}',
            )
            .toList();
        await prefs.setStringList(key, json);
      }
      return list;
    } catch (_) {
      // 离线：回退缓存
      final cached = prefs.getStringList(key) ?? const [];
      return [
        for (final line in cached)
          if (line.contains('|'))
            SignEntry(
              uid: int.tryParse(line.split('|').length > 5 ? line.split('|')[5] : '0') ?? 0,
              name: line.split('|')[0],
              totalDays: int.tryParse(line.split('|')[1]) ?? 0,
              monthDays: int.tryParse(line.split('|')[2]) ?? 0,
              rewardText: line.split('|')[3],
              timeText: line.split('|')[4],
            ),
      ];
    }
  }

  /// 加载本地与服务端签到记录（本月已签日期与积分记录奖励）
  Future<void> _loadSignedDays() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final key = 'sign_dates_${now.year}${now.month.toString().padLeft(2, '0')}';
    final list = (prefs.getStringList(key) ?? []).toSet();
    try {
      final isSignedToday = await KlpbbsApi.checkSigned();
      if (isSignedToday) {
        list.add('${now.day}');
        await prefs.setStringList(key, list.toList());
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _signedDays = list.map((e) => int.tryParse(e) ?? 0).where((d) => d > 0).toSet();
        _datesLoaded = true;
      });
    }

    try {
      final reward = await KlpbbsApi.getTodaySignReward();
      if (reward != null && mounted) {
        setState(() => _todaySignReward = reward);
      }
    } catch (_) {}
  }

  /// 签到成功展示弹窗（展示铁粒、经验、连续天数）
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
              child: Icon(Icons.check_circle, color: scheme.primary, size: 26),
            ),
            const SizedBox(width: 10),
            Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Text('获得铁粒：', style: TextStyle(color: scheme.onSurfaceVariant)),
                      const Spacer(),
                      Text('+${iron ?? "10"} 粒', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 16)),
                    ],
                  ),
                  if (exp != null && exp.isNotEmpty) ...[
                    const Divider(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text('获得经验：', style: TextStyle(color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        Text('+$exp EP', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16)),
                      ],
                    ),
                  ],
                  if (rank != null) ...[
                    const Divider(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.emoji_events, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text('今日签到排名：', style: TextStyle(color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        Text('第 $rank 名', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 15)),
                      ],
                    ),
                  ],
                  if (days != null) ...[
                    const Divider(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.calendar_month, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text('已连续签到：', style: TextStyle(color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        Text('$days 天', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '注：前排签到坛友可额外获得丰厚经验奖励！',
              style: TextStyle(fontSize: 12, color: scheme.outline),
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

  /// 记录签到日期
  Future<void> _recordSignDay() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final key = 'sign_dates_${now.year}${now.month.toString().padLeft(2, '0')}';
    final list = prefs.getStringList(key) ?? [];
    list.add('${now.day}');
    await prefs.setStringList(key, list.toSet().toList());
    await _loadSignedDays();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(_onTabChanged);
    _future = _loadWithCache(_op, page: _page);
    _loadSignedDays();
    final now = DateTime.now();
    _calYear = now.year;
    _calMonth = now.month;
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final op = _tabs[_tabController.index].$1;
    if (op != _op) {
      setState(() {
        _op = op;
        _page = 1;
        _future = _loadWithCache(op, page: 1);
      });
    }
  }

  void _goPage(int page) {
    if (page < 1) return;
    setState(() {
      _page = page;
      _future = _loadWithCache(_op, page: page);
    });
  }

  void _reload() {
    setState(() => _future = _loadWithCache(_op, page: _page));
  }

  bool get _isSignedToday => _signedDays.contains(DateTime.now().day);

  Widget _buildTodaySignStatusBanner() {
    final isSigned = _isSignedToday;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isSigned
            ? Colors.green.shade50.withAlpha(220)
            : Colors.amber.shade50.withAlpha(220),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSigned ? Colors.green.shade200 : Colors.amber.shade300,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSigned ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 22,
            color: isSigned ? Colors.green.shade700 : Colors.amber.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSigned
                      ? (_todaySignReward != null
                          ? '今日已完成签到（+${_todaySignReward!.amount} 铁粒）'
                          : '今日已完成签到')
                      : '今日尚未签到',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: isSigned ? Colors.green.shade900 : Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  isSigned
                      ? (_todaySignReward != null
                          ? '本月已累计签到 ${_signedDays.length} 天 · 奖励入账于 ${_todaySignReward!.timeText}'
                          : '本月已累计签到 ${_signedDays.length} 天，连续签到奖励更多！')
                      : '每日签到可领取铁粒与经验值奖励！',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isSigned ? Colors.green.shade800 : Colors.amber.shade800,
                  ),
                ),
              ],
            ),
          ),
          if (isSigned) ...[
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CreditPage(initialTabIndex: 2),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '明细',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 14, color: Colors.green.shade800),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _signIn,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('立即签到', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _signIn() async {
    final confirmed = await confirmWrite(context, '签到');
    if (!confirmed) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await KlpbbsApi.signIn();
      if (res.success || res.message.contains('已签到')) {
        await _recordSignDay();
        _showSignSuccessDialog(
          message: res.message.contains('已签到') ? '今日已签到' : res.message,
          iron: res.rewardIron,
          exp: res.rewardExp,
          rank: res.rank,
          days: res.continuousDays,
        );
        _reload();
        // 提取最新签到奖励
        final reward = await KlpbbsApi.getTodaySignReward();
        if (reward != null && mounted) {
          setState(() => _todaySignReward = reward);
        }
      } else {
        messenger.showSnackBar(SnackBar(content: Text(res.message)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('签到异常：$e')));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    final isSigned = _isSignedToday;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '签到排行',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: '积分记录流水',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CreditPage(initialTabIndex: 2),
                ),
              );
            },
          ),
          const GlobalNavButton(),
          if (isSigned)
            FilledButton.tonalIcon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🎉 今日已完成签到，无需重复签到'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.check_circle_rounded, size: 18, color: Colors.green),
              label: const Text('已签到'),
              style: FilledButton.styleFrom(
                foregroundColor: Colors.green.shade700,
                backgroundColor: Colors.green.shade50,
              ),
            )
          else
            FilledButton.icon(
              onPressed: _signIn,
              icon: const Icon(Icons.event_available, size: 18),
              label: const Text('签到'),
            ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.outline,
          indicatorColor: Theme.of(context).colorScheme.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: [for (final (_, label) in _tabs) Tab(text: label)],
        ),
      ),
      body: _tabController.index == 3
          ? _buildCalendar()
          : Column(
              children: [
                if (_tabController.index == 0) _buildTodaySignStatusBanner(),
                Expanded(
                  child: FutureBuilder(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('加载失败：${snap.error}', textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _reload,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        );
                      }
                      final entries = snap.data!;
                      if (entries.isEmpty) {
                        return RefreshIndicator(
                          onRefresh: () async => _reload(),
                          child: ListView(
                            children: [
                              const SizedBox(height: 80),
                              Center(
                                child: Text(
                                  _page > 1 ? '第 $_page 页暂无更多排行数据' : '暂无数据',
                                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                                ),
                              ),
                              if (_page > 1) ...[
                                const SizedBox(height: 16),
                                Center(
                                  child: FilledButton.tonal(
                                    onPressed: () => _goPage(_page - 1),
                                    child: const Text('返回上一页'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: () async => _reload(),
                        child: ListView.separated(
                          itemCount: entries.length + 1,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      if (i == entries.length) {
                        return PaginationControl(
                          page: _page,
                          hasMore: entries.length >= 10,
                          onPageChanged: _goPage,
                        );
                      }
                      final e = entries[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          backgroundImage: e.uid > 0
                              ? NetworkImage(
                                  AppConfig.avatarUrl(e.uid, size: 'small'),
                                )
                              : null,
                          onBackgroundImageError: (_, __) {},
                          child: e.uid > 0
                              ? null
                              : Text(
                                  e.name.isNotEmpty
                                      ? e.name.characters.first
                                      : '?',
                                  style: const TextStyle(fontSize: 13),
                                ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                e.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (e.timeText.isNotEmpty)
                              Text(
                                ' ${e.timeText}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '总天数 ${e.totalDays} 天 · 月天数 ${e.monthDays} 天'
                          '${e.rewardText.isNotEmpty ? ' · 奖励 ${e.rewardText}' : ''}',
                        ),
                      );
                    },
                  ),
                );
              },
            ),
                  ),
                ],
              ),
    );
  }

  /// 当前连续签到天数（从今天往前数）
  int get _streakDays {
    if (_signedDays.isEmpty) return 0;
    final now = DateTime.now();
    var streak = 0;
    var d = now.day;
    // 今天未签则从昨天开始数
    if (!_signedDays.contains(d)) d -= 1;
    while (_signedDays.contains(d)) {
      streak += 1;
      d -= 1;
      if (d < 1) break;
    }
    return streak;
  }

  /// 切换日历月份（保留本地记录）
  void _changeMonth(int delta) {
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
    });
  }

  /// 加载指定月的签到记录
  Future<void> _loadMonthSigned() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'sign_dates_$_calYear${_calMonth.toString().padLeft(2, '0')}';
    final list = prefs.getStringList(key) ?? const [];
    if (mounted) setState(() => _signedDays = list.map(int.parse).toSet());
  }

  /// 本月签到日历（本地记录签到日）
  Widget _buildCalendar() {
    if (!_datesLoaded) return const Center(child: CircularProgressIndicator());
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final firstDay = DateTime(_calYear, _calMonth, 1);
    final daysInMonth = DateTime(_calYear, _calMonth + 1, 0).day;
    // 周一为一周开始：周日=0 → 偏移 (weekday+6)%7
    final leading = (firstDay.weekday + 6) % 7;
    final week = ['一', '二', '三', '四', '五', '六', '日'];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 签到状态卡片（现代 Material 3 风格）
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? scheme.surfaceContainerLow
                : scheme.surfaceContainerHighest.withAlpha(90),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withAlpha(80),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              // 签到图标
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: scheme.primary.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.event_available_rounded,
                  color: scheme.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _signedDays.contains(now.day) ? '今日已签到' : '今日未签到',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '连续签到 $_streakDays 天 · 本月已签 ${_signedDays.length} 天',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _signIn,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(_signedDays.contains(now.day) ? '已签到' : '签到'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () {
                        _changeMonth(-1);
                        _loadMonthSigned();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    Column(
                      children: [
                        Text(
                          '$_calYear 年 $_calMonth 月',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          _calYear == DateTime.now().year &&
                                  _calMonth == DateTime.now().month
                              ? '本月已签 ${_signedDays.length} 天 · 连续 $_streakDays 天'
                              : '该月已签 ${_signedDays.length} 天',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () {
                        _changeMonth(1);
                        _loadMonthSigned();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final w in week)
                      Expanded(
                        child: Center(
                          child: Text(
                            w,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (var i = 0; i < leading; i++) const SizedBox(),
                    for (var d = 1; d <= daysInMonth; d++)
                      _buildDayCell(d, now),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '签到说明',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text(
                  '· 每天签到获得积分奖励\n· 连续签到奖励更多\n· 签到记录保存在本地（切换环境后不共享）',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayCell(int day, DateTime now) {
    final signed = _signedDays.contains(day);
    final isToday =
        _calYear == now.year && _calMonth == now.month && day == now.day;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: AnimatedScale(
        scale: signed ? 1 : 0.9,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: signed ? scheme.primary : null,
            borderRadius: BorderRadius.circular(10),
            border: isToday && !signed
                ? Border.all(color: scheme.primary, width: 1.5)
                : null,
            boxShadow: signed
                ? [
                    BoxShadow(
                      color: scheme.primary.withAlpha(45),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 13,
              color: signed
                  ? scheme.onPrimary
                  : isToday
                  ? scheme.primary
                  : null,
              fontWeight: signed || isToday
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
