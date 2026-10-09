import '../widgets/app_motion.dart';
import '../widgets/today_sign_star.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../core/discuz_sign_response.dart';
import '../core/discuz_sign_pagination.dart';
import '../core/main_tab_controller.dart';
import '../core/write_confirm.dart';
import '../models/sign_entry.dart';
import '../services/auto_sign_service.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/pagination_control.dart';
import '../models/server_outage_info.dart';
import '../widgets/server_outage_view.dart';
import '../widgets/thread_card.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/year_month_picker_dialog.dart';
import 'credit_page.dart';
import 'func_list_page.dart';
import 'magic_page.dart';
import 'settings_page.dart';
import 'user_space_page.dart';

/// 每日签到与排行榜（深度融合 App 现代 Material 3 设计系统，100% 对齐官方 k_misign 规则）
class SignRankPage extends StatefulWidget {
  final String initialOperation;
  const SignRankPage({super.key, this.initialOperation = 'today'});

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
  final _rankFutures = <String, Future<List<SignEntry>>>{};
  final _rankEntries = <String, List<SignEntry>>{};
  final _rankFetchedAt = <String, DateTime>{};
  final _tabPages = <String, int>{};
  int _rankGeneration = 0;

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

  int _headerGeneration = 0;
  int _calendarGeneration = 0;

  /// 实时拉取头部统计与个人签到数据（严格与网页端实时同步）
  Future<void> _loadHeaderRealtime({bool forceRefresh = true}) async {
    if (!mounted) return;
    final generation = ++_headerGeneration;
    final session = DioClient.sessionKey;
    final signWriteRevision = AutoSignService.instance.signWriteRevision;
    setState(() => _loadingHeader = true);
    try {
      final info =
          await KlpbbsApi.getSignHeaderInfo(forceRefresh: forceRefresh);
      final uid = DioClient.isLoggedIn ? await KlpbbsApi.getMyUid() : null;
      if (!mounted ||
          generation != _headerGeneration ||
          session != DioClient.sessionKey) {
        return;
      }
      if (signWriteRevision != AutoSignService.instance.signWriteRevision) {
        setState(() => _loadingHeader = false);
        return;
      }
      final now = AutoSignService.instance.estimatedServerNow;
      final signed = info.hasPersonalState
          ? info.isSignedToday
          : AutoSignService.instance.isSignedToday();
      setState(() {
        _myUid = uid;
        _myUsername = info.username.isNotEmpty
            ? info.username
            : KlpbbsApi.cachedSpace?.username;
        _headerInfo = info.copyWith(
            uid: uid, username: _myUsername, isSignedToday: signed);
        _loadingHeader = false;
        if (_calYear == now.year && _calMonth == now.month) {
          if (signed) {
            _signedDays.add(now.day);
          } else if (info.hasPersonalState) {
            _signedDays.remove(now.day);
          }
        }
      });
      if (signed) {
        await AutoSignService.instance.markSignedToday(
          rank: info.mySignRank,
          continuousDays: info.hasContinuousDays ? info.continuousDays : null,
          rewardIron: info.rewardIron.isEmpty ? null : info.rewardIron,
          expectedSession: session,
          expectedWriteRevision: signWriteRevision,
        );
      } else if (info.hasPersonalState) {
        await AutoSignService.instance.markUnsignedToday(
            expectedSession: session, expectedWriteRevision: signWriteRevision);
      }
    } catch (_) {
      if (mounted &&
          generation == _headerGeneration &&
          session == DioClient.sessionKey) {
        setState(() => _loadingHeader = false);
      }
    }
  }

  /// Retain confirmed data per tab/page, never display the previous page's rows
  /// under a new page number. Failed futures can be retried immediately.
  Future<List<SignEntry>> _loadRankList(String op,
      {int page = 1, bool forceRefresh = false}) {
    if (op == 'calendar') return Future.value(const <SignEntry>[]);
    final key = '$op:$page';
    final fetched = _rankFetchedAt[key];
    if (!forceRefresh &&
        _rankFutures.containsKey(key) &&
        (fetched == null ||
            DateTime.now().difference(fetched) < const Duration(minutes: 1))) {
      return _rankFutures[key]!;
    }
    final session = DioClient.sessionKey, generation = _rankGeneration;
    late final Future<List<SignEntry>> future;
    future = KlpbbsApi.getSignRank(op, page: page, forceRefresh: forceRefresh)
        .then((entries) {
      if (mounted &&
          session == DioClient.sessionKey &&
          generation == _rankGeneration &&
          identical(_rankFutures[key], future)) {
        _rankEntries[key] = entries;
        _rankFetchedAt[key] = DateTime.now();
      }
      return entries;
    }).catchError((Object error, StackTrace stack) {
      if (identical(_rankFutures[key], future)) _rankFutures.remove(key);
      Error.throwWithStackTrace(error, stack);
    });
    future.ignore();
    _rankFutures[key] = future;
    return future;
  }

  /// 加载日历签到记录（以服务端官方日历数据为准）
  Future<void> _loadSignedDays({bool forceRefresh = false}) async {
    final session = DioClient.sessionKey;
    final generation = ++_calendarGeneration;
    final now = AutoSignService.instance.estimatedServerNow;
    final year = _calYear > 0 ? _calYear : now.year;
    final month = _calMonth > 0 ? _calMonth : now.month;
    final key = KlpbbsApi.signCalendarKey(year, month);
    bool current() =>
        mounted &&
        session == DioClient.sessionKey &&
        generation == _calendarGeneration &&
        year == _calYear &&
        month == _calMonth;
    try {
      final days = await KlpbbsApi.getSignedDaysFromServerCalendar(
          month: month, year: year, forceRefresh: forceRefresh);
      if (!current()) return;
      final confirmed = Set<int>.from(days);
      if (year == now.year && month == now.month) {
        if (_headerInfo.isSignedToday ||
            AutoSignService.instance.isSignedToday()) {
          confirmed.add(now.day);
        } else if (_headerInfo.hasPersonalState) {
          confirmed.remove(now.day);
        }
      }
      setState(() {
        _signedDays = confirmed;
        _datesLoaded = true;
      });
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return;
      await prefs.setStringList(
          key, confirmed.map((day) => day.toString()).toList());
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return;
      final days = (prefs.getStringList(key) ?? const <String>[])
          .map(int.tryParse)
          .whereType<int>()
          .where((day) => day > 0 && day <= 31)
          .toSet();
      setState(() {
        _signedDays = days;
        _datesLoaded = true;
      });
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
                      Icon(Icons.monetization_on_rounded,
                          color: scheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Text('基础铁粒奖励',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 13.5)),
                      const Spacer(),
                      Text(
                        (iron != null && iron.isNotEmpty)
                            ? '+$iron 粒'
                            : '网站未提供',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                            fontSize: 16),
                      ),
                    ],
                  ),
                  if (exp != null && exp.isNotEmpty) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        Icon(Icons.bolt_rounded,
                            color: scheme.primary, size: 20),
                        const SizedBox(width: 10),
                        Text('前排 EP 经验奖励',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13.5)),
                        const Spacer(),
                        Text('+$exp EP',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                                fontSize: 16)),
                      ],
                    ),
                  ],
                  if (rank != null && rank > 0) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        Icon(Icons.emoji_events_rounded,
                            color: scheme.primary, size: 20),
                        const SizedBox(width: 10),
                        Text('今日签到排名',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13.5)),
                        const Spacer(),
                        Text('第 $rank 名',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                                fontSize: 15)),
                      ],
                    ),
                  ],
                  if (days != null && days > 0) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        Icon(Icons.local_fire_department_rounded,
                            color: scheme.primary, size: 20),
                        const SizedBox(width: 10),
                        Text('已连续签到',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13.5)),
                        const Spacer(),
                        Text('$days 天',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                                fontSize: 15)),
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
    showDialog<void>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
              title: const Text('签到规则'),
              children: [
                for (final rule in const [
                  ('签到等级', 'k_misign-misc.html?operation=leval'),
                  ('签到奖励规则', 'k_misign-misc.html?operation=rewardrule'),
                ])
                  SimpleDialogOption(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              FuncListPage(title: rule.$1, path: rule.$2)));
                    },
                    child: Row(children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 12),
                      Expanded(child: Text(rule.$1)),
                      const Icon(Icons.chevron_right),
                    ]),
                  ),
              ],
            ));
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
    final initial =
        _tabs.indexWhere((tab) => tab.$1 == widget.initialOperation);
    _currentTabIndex = initial < 0 ? 0 : initial;
    _op = _tabs[_currentTabIndex].$1;
    _tabController = TabController(
        length: _tabs.length, initialIndex: _currentTabIndex, vsync: this)
      ..addListener(_onTabControllerTick);
    _future = _loadRankList(_op, page: _page);
    _headerInfo = KlpbbsApi.cachedSignHeaderInfo ?? const SignHeaderInfo();
    _loadHeaderRealtime(forceRefresh: false);
    _loadSignedDays();
    _lastAutoSignState = AutoSignService.instance.isSignedToday();
    AutoSignService.instance.addListener(_onAutoSignChanged);
    DioClient.sessionChanges.addListener(_onAccountChanged);
  }

  void _onAccountChanged() {
    if (!mounted) return;
    ++_headerGeneration;
    ++_calendarGeneration;
    setState(() {
      _headerInfo = const SignHeaderInfo();
      _myUid = null;
      _myUsername = null;
      _signedDays.clear();
      _datesLoaded = false;
      _isSigning = false;
      _lastAutoSignState = null;
      _page = 1;
      _rankFutures.clear();
      _rankEntries.clear();
      _rankFetchedAt.clear();
      _rankGeneration++;
      _tabPages.clear();
    });
    _reload(forceRefresh: true);
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
    DioClient.sessionChanges.removeListener(_onAccountChanged);
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
    final isCurrentMonth = _calYear == 0 ||
        (_calYear == serverNow.year && _calMonth == serverNow.month);
    setState(() {
      if (!isSigned) {
        // 零点跨天或状态重置，立即翻转头部状态与排名，防止按钮锁死在已签到
        _headerInfo = _headerInfo.copyWith(
          isSignedToday: false,
          mySignRank: null,
          clearMySignRank: true,
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
    if (index == _currentTabIndex) return;
    _tabPages[_op] = _page;
    final op = _tabs[index].$1;
    setState(() {
      _currentTabIndex = index;
      _op = op;
      final remembered = _tabPages[op] ?? 1;
      _page = op == 'calendar'
          ? 1
          : remembered.clamp(1, _totalRankPages(op) ?? remembered);
      if (_tabController.index != index) {
        _tabController.animateTo(index);
      }
      if (op != 'calendar') {
        _future = _loadRankList(op, page: _page);
      } else {
        if (!_datesLoaded) _loadSignedDays();
      }
    });
  }

  void _goPage(int page) {
    if (page < 1 || _op == 'calendar') return;
    final target = page.clamp(1, _totalRankPages(_op) ?? page);
    setState(() {
      _page = target;
      _tabPages[_op] = target;
      _future = _loadRankList(_op, page: target);
    });
  }

  int? _totalRankPages(String op) =>
      KlpbbsApi.signRankTotalPages(op) ??
      (op == 'today' && _headerInfo.hasTodaySignCount
          ? DiscuzSignPagination.pagesForCount(_headerInfo.todaySignCount)
          : null);

  void _reload({bool forceRefresh = true}) {
    setState(() {
      if (_op != 'calendar') {
        _future = _loadRankList(_op, page: _page, forceRefresh: forceRefresh);
      }
    });
    _loadHeaderRealtime(forceRefresh: forceRefresh);
    _loadSignedDays(forceRefresh: forceRefresh);
  }

  bool get _isSignedToday =>
      _headerInfo.isSignedToday ||
      AutoSignService.instance.isSignedToday() ||
      (_calYear == AutoSignService.instance.estimatedServerNow.year &&
          _calMonth == AutoSignService.instance.estimatedServerNow.month &&
          _signedDays
              .contains(AutoSignService.instance.estimatedServerNow.day));

  Future<void> _signIn() async {
    if (_isSigning || _isSignedToday) return;
    final session = DioClient.sessionKey;
    final confirmed = await confirmWrite(context, '签到');
    if (!confirmed || !mounted || session != DioClient.sessionKey) return;
    setState(() => _isSigning = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await KlpbbsApi.signIn();
      if (!mounted || session != DioClient.sessionKey) return;
      if (!result.confirmed) {
        messenger.showSnackBar(SnackBar(content: Text(result.message)));
        return;
      }
      await AutoSignService.instance.markSignedToday(
          rank: result.rank,
          continuousDays: result.continuousDays,
          rewardIron: result.rewardIron,
          rewardExp: result.rewardExp,
          notify: result.success,
          expectedSession: session);
      if (!mounted || session != DioClient.sessionKey) return;
      final now = AutoSignService.instance.estimatedServerNow;
      setState(() {
        if (_calYear == now.year && _calMonth == now.month) {
          _signedDays.add(now.day);
        }
        _headerInfo = _headerInfo.copyWith(
          hasPersonalState: true,
          hasContinuousDays:
              result.continuousDays != null || _headerInfo.hasContinuousDays,
          isSignedToday: true,
          mySignRank: result.rank,
          clearMySignRank: result.rank == null,
          continuousDays: result.continuousDays,
          rewardIron: result.rewardIron,
        );
      });
      _showSignSuccessDialog(
          message: result.message,
          iron: result.rewardIron,
          exp: result.rewardExp,
          rank: result.rank,
          days: result.continuousDays);
      _reload(forceRefresh: true);
    } catch (error) {
      if (mounted && session == DioClient.sessionKey) {
        messenger.showSnackBar(SnackBar(content: Text('签到异常：$error')));
      }
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _isSigning = false);
      }
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
        leadingWidth: (isDesktop && !canPop)
            ? null
            : GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('每日签到',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        bottom: _loadingHeader
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: AppLoadingBar(minHeight: 2),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TodaySignStar(
                        info: _headerInfo,
                        loading: _loadingHeader,
                        onRetry: () => _loadHeaderRealtime(forceRefresh: true)),
                    const SizedBox(height: 12),
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

    final continuous = _headerInfo.hasContinuousDays
        ? _headerInfo.continuousDays.toString()
        : '—';
    final total =
        _headerInfo.hasTotalDays ? _headerInfo.totalDays.toString() : '—';

    final accountName = _headerInfo.username.isNotEmpty
        ? _headerInfo.username
        : (_myUsername != null && _myUsername!.isNotEmpty
            ? _myUsername!
            : (DioClient.isLoggedIn ? '我的账号' : '未登录'));
    final signButton = FilledButton.icon(
      key: const ValueKey('sign-hero-button'),
      onPressed: (_isSigning || _loadingHeader)
          ? null
          : (isSigned
              ? () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _headerInfo.mySignRank != null &&
                                _headerInfo.mySignRank! > 0
                            ? '今日已签到！您的签到排名为第 ${_headerInfo.mySignRank} 名'
                            : '今日已完成签到，无需重复签到',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              : _signIn),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: isSigned ? scheme.secondaryContainer : scheme.primary,
        foregroundColor:
            isSigned ? scheme.onSecondaryContainer : scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: _isSigning
          ? SizedBox(
              width: 18,
              height: 18,
              child: AppLoadingIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
              ),
            )
          : Icon(
              isSigned ? Icons.check_circle_rounded : Icons.touch_app_rounded,
              size: 18),
      label: Text(
        _isSigning ? '签到中...' : (isSigned ? '今日已签' : '立即签到'),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );

    Widget buildAccountArea() => Row(
          key: const ValueKey('sign-hero-account-area'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatarWidget(
              uid: _headerInfo.uid ?? _myUid,
              author: accountName,
              size: 46,
              reserveFrameSpace: true,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(accountName,
                          key: const ValueKey('sign-hero-account-name'),
                          softWrap: true,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      if (_headerInfo.signLevel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(_headerInfo.signLevel,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: scheme.onPrimaryContainer,
                              )),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isSigned &&
                            _headerInfo.mySignRank != null &&
                            _headerInfo.mySignRank! > 0
                        ? '今日签到排名：第 ${_headerInfo.mySignRank} 名'
                        : (isSigned ? '今日已完成签到' : '今日尚未签到，签到领铁粒与经验'),
                    key: const ValueKey('sign-hero-state'),
                    softWrap: true,
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        );
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withAlpha(80)),
      ),
      color:
          isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            // Preserve readable account width before placing a trailing action.
            LayoutBuilder(
              key: const ValueKey('sign-hero-header'),
              builder: (context, constraints) {
                final textScale =
                    MediaQuery.textScalerOf(context).scale(16) / 16;
                final stacked =
                    constraints.maxWidth < 480 * textScale.clamp(1.0, 2.0);
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      buildAccountArea(),
                      const SizedBox(height: 14),
                      signButton,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: buildAccountArea()),
                    const SizedBox(width: 16),
                    signButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Natural height and full text; narrow or large-text layouts use two columns.
            LayoutBuilder(
              key: const ValueKey('sign-hero-stats'),
              builder: (context, constraints) {
                final textScale =
                    MediaQuery.textScalerOf(context).scale(16) / 16;
                final columns = constraints.maxWidth < 220
                    ? 1
                    : (constraints.maxWidth >= 520 * textScale.clamp(1.0, 2.0)
                        ? 4
                        : 2);
                final items = [
                  _buildModernStatItem(
                      key: const ValueKey('sign-hero-stat-continuous'),
                      icon: Icons.local_fire_department_rounded,
                      label: '连续签到',
                      value: continuous,
                      unit: '天'),
                  _buildModernStatItem(
                      key: const ValueKey('sign-hero-stat-level'),
                      icon: Icons.military_tech_rounded,
                      label: '签到等级',
                      value: _headerInfo.signLevel.isNotEmpty
                          ? _headerInfo.signLevel
                          : '—',
                      unit: ''),
                  _buildModernStatItem(
                      key: const ValueKey('sign-hero-stat-reward'),
                      icon: Icons.monetization_on_rounded,
                      label: '今日奖励',
                      value: _headerInfo.rewardIron.isNotEmpty
                          ? _headerInfo.rewardIron
                          : '—',
                      unit: '粒'),
                  _buildModernStatItem(
                      key: const ValueKey('sign-hero-stat-total'),
                      icon: Icons.event_available_rounded,
                      label: '累计签到',
                      value: total,
                      unit: '天'),
                ];
                return Column(children: [
                  for (var row = 0; row < items.length ~/ columns; row++) ...[
                    if (row > 0) const SizedBox(height: 10),
                    IntrinsicHeight(
                      child: Row(
                        key: ValueKey('sign-hero-stat-row-$row'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var column = 0; column < columns; column++) ...[
                            if (column > 0) const SizedBox(width: 10),
                            Expanded(child: items[row * columns + column]),
                          ],
                        ],
                      ),
                    ),
                  ],
                ]);
              },
            ),
            const SizedBox(height: 14),

            // 底部：全站今日之星与规则入口
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 520;
                if (isCompact) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withAlpha(70),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.people_alt_rounded,
                                size: 15, color: scheme.primary),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text.rich(TextSpan(
                                text: '今日已签 ',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant),
                                children: [
                                  TextSpan(
                                    text: _headerInfo.hasTodaySignCount
                                        ? '${_headerInfo.todaySignCount} 人'
                                        : '—',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: scheme.primary),
                                  )
                                ],
                              )),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _showRewardRuleDialog,
                            icon: const Icon(Icons.help_outline_rounded,
                                size: 18),
                            label: const Text('奖励规则'),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withAlpha(70),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.people_alt_rounded,
                          size: 15, color: scheme.primary),
                      const SizedBox(width: 5),
                      Text('今日已签 ',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                      Text(
                        _headerInfo.hasTodaySignCount
                            ? '${_headerInfo.todaySignCount} 人'
                            : '—',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: scheme.primary),
                      ),
                      const Spacer(),
                      if (_headerInfo.highestCount > 0) ...[
                        Text(
                          '历史最高: ${_headerInfo.highestCount}人',
                          style:
                              TextStyle(fontSize: 11.5, color: scheme.outline),
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
                            Icon(Icons.help_outline_rounded,
                                size: 14, color: scheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              '奖励规则',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernStatItem({
    Key? key,
    required IconData icon,
    Color? iconColor,
    required String label,
    required String value,
    required String unit,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final effectiveColor = iconColor ?? scheme.primary;

    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surfaceContainerHighest.withAlpha(80)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withAlpha(40)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: effectiveColor),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              children: [
                if (unit.isNotEmpty)
                  TextSpan(
                      text: unit,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.normal,
                          color: scheme.onSurfaceVariant)),
              ],
            ),
            textAlign: TextAlign.center,
            softWrap: true,
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
                  color: _currentTabIndex == i
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                ),
                label: Text(_tabs[i].$2),
                labelStyle: TextStyle(
                  fontWeight: _currentTabIndex == i
                      ? FontWeight.bold
                      : FontWeight.normal,
                  fontSize: 13,
                  color: _currentTabIndex == i
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                ),
                selected: _currentTabIndex == i,
                selectedColor: scheme.primary,
                backgroundColor: isDark
                    ? scheme.surfaceContainerHigh
                    : scheme.surfaceContainerLow,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
        final pending = snap.connectionState != ConnectionState.done;
        final entries = pending || snap.hasError
            ? _rankEntries['$_op:$_page'] ?? const <SignEntry>[]
            : snap.data ?? const <SignEntry>[];
        final pagination = KlpbbsApi.signRankPagination(_op, _page);
        Widget withControls(Widget child) => Column(children: [
              child,
              PaginationControl(
                key: const ValueKey('sign-rank-pagination'),
                page: _page,
                totalPages: _totalRankPages(_op),
                hasMore: !pending &&
                    !snap.hasError &&
                    (pagination?.nextPage != null || entries.length >= 10),
                onPageChanged: _goPage,
              ),
              if (entries.isEmpty && _page > 1)
                TextButton.icon(
                    onPressed: () => _goPage(1),
                    icon: const Icon(Icons.first_page_rounded),
                    label: const Text('返回第一页')),
            ]);
        if (pending && entries.isEmpty) {
          return withControls(const Padding(
            padding: EdgeInsets.all(50),
            child: Center(child: AppLoadingIndicator()),
          ));
        }
        if (snap.hasError && entries.isEmpty) {
          final outage = ServerOutageInfo.tryParse(snap.error);
          if (outage != null) {
            return withControls(Padding(
              padding: const EdgeInsets.all(24),
              child: ServerOutageView(
                outage: outage,
                onRetry: () => _reload(forceRefresh: true),
              ),
            ));
          }
          return withControls(Padding(
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
          ));
        }
        if (entries.isEmpty) {
          return withControls(const EmptyView(
            icon: Icons.leaderboard_outlined,
            title: '暂无更多排行数据',
            subtitle: '可返回上一页，或下拉刷新',
          ));
        }

        return withControls(Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant.withAlpha(60)),
          ),
          color: isDark
              ? scheme.surfaceContainerHigh
              : scheme.surfaceContainerLowest,
          child: Column(
            children: [
              if (pending) const LinearProgressIndicator(minHeight: 2),
              if (snap.hasError)
                Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: Row(children: [
                      const Expanded(child: Text('刷新失败，保留上次加载的排行')),
                      TextButton(
                          onPressed: () => _reload(forceRefresh: true),
                          child: const Text('重试')),
                    ])),
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
                          MaterialPageRoute(
                              builder: (_) => UserSpacePage(uid: e.uid)),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          UserAvatarWidget(
                              uid: e.uid,
                              author: e.name,
                              size: 40,
                              reserveFrameSpace: true),
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
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14),
                                      ),
                                    ),
                                    if (e.displayLevel.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: scheme.primary.withAlpha(20),
                                          borderRadius:
                                              BorderRadius.circular(6),
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
                                    Text('总签到: ${e.totalDays}天',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant)),
                                    Text('月签到: ${e.monthDays}天',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant)),
                                    if (e.timeText.isNotEmpty)
                                      Text(e.timeText.replaceAll('2026-', ''),
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: scheme.outline)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (isRewardOp && rewardDisplay.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withAlpha(140),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: scheme.outlineVariant.withAlpha(50)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.monetization_on_rounded,
                                      size: 14, color: scheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    rewardDisplay,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Icon(Icons.chevron_right_rounded,
                                size: 18, color: scheme.outline.withAlpha(150)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ));
      },
    );
  }

  /// 现代 Material 3 签到日历与进阶卡片
  void _changeMonth(int delta) {
    final now = AutoSignService.instance.estimatedServerNow;
    if (delta > 0) {
      if (_calYear > now.year ||
          (_calYear == now.year && _calMonth >= now.month)) {
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
        child: Center(child: AppLoadingIndicator()),
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
          color: isDark
              ? scheme.surfaceContainerHigh
              : scheme.surfaceContainerLowest,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$_calYear 年 $_calMonth 月',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17),
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
                              (_datesLoaded
                                      ? '已确认 ${_signedDays.length} 天'
                                      : '正在读取已确认记录') +
                                  (isCurrentMonth &&
                                          _headerInfo.hasContinuousDays
                                      ? ' · 连续签到 ${_headerInfo.continuousDays} 天'
                                      : ''),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed:
                          isCurrentOrFutureMonth ? null : () => _changeMonth(1),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. 星期栏
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withAlpha(120),
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
                                color: scheme.onSurfaceVariant,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
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
    if (_headerInfo.retroSignDays <= 0 && _headerInfo.retroSignBid == null) {
      return const SizedBox.shrink();
    }
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
          Icon(Icons.history_toggle_off_rounded,
              color: scheme.tertiary, size: 22),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _handleRetroSign(bid),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_fix_high_rounded, size: 14),
                SizedBox(width: 4),
                Text('立即补签',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
    final session = DioClient.sessionKey;
    int? targetBid = bid ?? _headerInfo.retroSignBid;
    if (targetBid == null) {
      try {
        final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
        if (!mounted || session != DioClient.sessionKey) return;
        targetBid = info.retroSignBid;
      } catch (_) {}
    }

    if (targetBid == null) {
      if (!mounted) return;
      final buy = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final dialogScheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.shopping_bag_rounded, color: dialogScheme.primary),
                const SizedBox(width: 8),
                const Text('获取补签卡'),
              ],
            ),
            content: const Text(
                '论坛签到页面暂未指定当前断签的补签批次 ID，或者您需要先在道具商城购买【补签卡】。是否前往道具商城？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('前往商城')),
            ],
          );
        },
      );
      if (buy == true && mounted && session == DioClient.sessionKey) {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const MagicPage()));
      }
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.auto_fix_high_rounded, color: dialogScheme.primary),
              const SizedBox(width: 8),
              const Text('使用补签卡'),
            ],
          ),
          content: Text(
            _headerInfo.retroSignTip.isNotEmpty
                ? '${_headerInfo.retroSignTip}\n\n是否立即消耗 1 张补签卡进行补签？'
                : '确定消耗 1 张补签卡，恢复最近的断签并续接连续签到天数吗？',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认补签')),
          ],
        );
      },
    );

    if (confirmed != true || !mounted || session != DioClient.sessionKey) {
      return;
    }

    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(const SnackBar(content: Text('正在提交补签申请...')));

    final res = await KlpbbsApi.useRetroSignCard(bid: targetBid);
    if (!mounted || session != DioClient.sessionKey) return;

    if (res.success) {
      scaffold.showSnackBar(
          SnackBar(content: Text(res.message), backgroundColor: Colors.green));
      _reload(forceRefresh: true);
    } else {
      if (res.message.contains('商城') || res.message.contains('暂无')) {
        final goToShop = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('背包暂无补签卡'),
            content: Text('${res.message}\n\n是否立即前往道具商城选购？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('前往购买')),
            ],
          ),
        );
        if (goToShop == true && mounted && session == DioClient.sessionKey) {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const MagicPage()));
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
    final isToday =
        _calYear == now.year && _calMonth == now.month && day == now.day;
    final isPastMissed = _calYear == now.year &&
        _calMonth == now.month &&
        day < now.day &&
        !signed;

    final cell = Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: signed
              ? (isToday
                  ? scheme.primary
                  : scheme.primaryContainer.withAlpha(isDark ? 160 : 200))
              : (isToday
                  ? scheme.surfaceContainerHighest.withAlpha(140)
                  : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
          border:
              isToday ? Border.all(color: scheme.primary, width: 1.6) : null,
          boxShadow: isToday && signed
              ? [
                  BoxShadow(
                    color: scheme.primary.withAlpha(60),
                    blurRadius: 6,
                    spreadRadius: 1,
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
                fontWeight:
                    signed || isToday ? FontWeight.bold : FontWeight.normal,
                color: signed
                    ? (isToday ? scheme.onPrimary : scheme.onPrimaryContainer)
                    : (isToday
                        ? scheme.primary
                        : (isPastMissed
                            ? scheme.outline.withAlpha(140)
                            : (isDark
                                ? scheme.onSurface
                                : const Color(0xFF334155)))),
              ),
            ),
            if (signed)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: isToday ? scheme.onPrimary : scheme.primary,
                  shape: BoxShape.circle,
                ),
              )
            else if (isPastMissed)
              Container(
                width: 3.5,
                height: 3.5,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: scheme.tertiary.withAlpha(160),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );

    if (isPastMissed) {
      return Tooltip(
        message: '$day 日未在已确认记录中',
        child: InkWell(
          onTap: null,
          borderRadius: BorderRadius.circular(10),
          child: cell,
        ),
      );
    }

    return cell;
  }

  /// 当前站点实际提供的个人签到记录
  Widget _buildNextLevelProgressCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.military_tech_outlined, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  _headerInfo.signLevel.isEmpty
                      ? '签到记录'
                      : _headerInfo.signLevel,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: _showRewardRuleDialog, child: const Text('等级与奖励规则')),
        ]),
        if (_headerInfo.hasPersonalStats)
          Text(
              '累计签到 ${_headerInfo.hasTotalDays ? _headerInfo.totalDays.toString() : '—'} 天 · 连续签到 ${_headerInfo.hasContinuousDays ? _headerInfo.continuousDays.toString() : '—'} 天',
              style: TextStyle(color: scheme.onSurfaceVariant))
        else
          Text('查看已确认的月度记录，等级和奖励以网站规则为准',
              style: TextStyle(color: scheme.onSurfaceVariant)),
      ]),
    ));
  }
}
