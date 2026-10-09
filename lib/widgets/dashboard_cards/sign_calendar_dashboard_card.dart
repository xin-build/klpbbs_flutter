import '../app_motion.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/klpbbs_api.dart';
import '../../core/dio_client.dart';
import '../../core/discuz_sign_response.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/server_outage_info.dart';
import '../../models/sign_entry.dart';
import '../../pages/login_page.dart';
import '../../pages/sign_rank_page.dart';
import '../../services/auto_sign_service.dart';
import '../year_month_picker_dialog.dart';
import 'dashboard_card_frame.dart';

/// 签到打卡日历卡片
/// 支持不同尺寸（LOD）自适应展示：
/// - 紧凑尺寸 (1x1 / 2x1)：7 天连签打卡进度条、今日签到状态与快捷签到按钮
/// - 标准尺寸 (3x2 / 4x2)：连签里程碑徽章、周历进度、补签卡与风云榜入口
/// - 展开网格 (4x3 / 6x3 及以上)：全功能交互式月度打卡日历网格，高亮已签/断签/今日，支持历史月份查阅
class SignInCalendarDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const SignInCalendarDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<SignInCalendarDashboardCard> createState() =>
      _SignInCalendarDashboardCardState();
}

class _SignInCalendarDashboardCardState
    extends State<SignInCalendarDashboardCard> {
  bool _signed = false;
  bool _stateKnown = false;
  bool _streakKnown = false;
  String _stateDay = '';
  int _streakDays = 0;
  int _retroSignDays = 0;
  bool _signing = false;
  DateTime _currentMonth = DateTime.now();
  Set<int> _signedDays = {};
  final Map<int, Set<int>> _extraMonthSigned = {};
  final Set<int> _knownMonths = {};
  bool _loadingMonth = false;
  bool _loadingSignData = false;
  int _dataGeneration = 0;

  String get _todayLabel => !DioClient.isLoggedIn
      ? '登录后查看'
      : !_stateKnown
          ? '状态待确认'
          : _signed
              ? '今日已打卡'
              : '今日尚未签到';
  String get _streakLabel => _streakKnown ? '$_streakDays' : '—';
  String get _monthLabel =>
      _knownMonths.contains(_currentMonth.year * 100 + _currentMonth.month)
          ? '已签 ${_signedDays.length} 天'
          : '已确认 ${_signedDays.length} 天';

  void _applyHeader(SignHeaderInfo info) {
    if (info.hasPersonalState && DioClient.isLoggedIn) {
      _stateKnown = true;
      _signed = info.isSignedToday;
      _retroSignDays = info.retroSignDays;
    }
    if (info.hasContinuousDays && DioClient.isLoggedIn) {
      _streakKnown = true;
      _streakDays = info.continuousDays;
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
      _streakKnown = true;
      _streakDays = days;
    }
    final cached = KlpbbsApi.cachedSignHeaderInfo;
    if (cached != null) _applyHeader(cached);
  }

  @override
  void initState() {
    super.initState();
    final serverNow = AutoSignService.instance.estimatedServerNow;
    _currentMonth = DateTime(serverNow.year, serverNow.month, 1);
    _syncLocalState();

    if (widget.isPreview) {
      _loadPreviewCalendar();
      return;
    }

    AutoSignService.instance.addListener(_onAutoSignChanged);
    DioClient.sessionChanges.addListener(_onAccountChanged);
    _loadSignData();
  }

  Future<void> _loadPreviewCalendar() async {
    final session = DioClient.sessionKey;
    final key =
        KlpbbsApi.signCalendarKey(_currentMonth.year, _currentMonth.month);
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || session != DioClient.sessionKey) return;
    setState(() {
      _signedDays = (prefs.getStringList(key) ?? const [])
          .map(int.tryParse)
          .whereType<int>()
          .where((day) =>
              day > 0 &&
              day <=
                  DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day)
          .toSet();
      if (_signed) {
        _signedDays.add(AutoSignService.instance.estimatedServerNow.day);
      }
    });
  }

  void _onAccountChanged() {
    if (!mounted) return;
    _dataGeneration++;
    setState(() {
      _stateDay = '';
      _syncLocalState();
      _signing = false;
      _signedDays.clear();
      _extraMonthSigned.clear();
      _knownMonths.clear();
      _loadingMonth = false;
      _loadingSignData = false;
    });
    _loadSignData();
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
    final serverNow = AutoSignService.instance.estimatedServerNow;
    setState(() {
      _syncLocalState();
      if (_currentMonth.year == serverNow.year &&
          _currentMonth.month == serverNow.month) {
        if (_stateKnown && _signed) {
          _signedDays.add(serverNow.day);
        } else if (_stateKnown) {
          _signedDays.remove(serverNow.day);
        }
      }
    });
    // 严禁在此处调用 _loadSignData()！因为 _loadSignData 会调用 KlpbbsApi，
    // 而 KlpbbsApi 会调用 AutoSignService.markSignedToday()，从而形成无限异步重入级联死循环！
  }

  bool _isDaySigned(DateTime d) {
    final serverNow = AutoSignService.instance.estimatedServerNow;
    if (d.year == serverNow.year &&
        d.month == serverNow.month &&
        d.day == serverNow.day) {
      return _signed;
    }
    if (d.year == _currentMonth.year && d.month == _currentMonth.month) {
      return _signedDays.contains(d.day);
    }
    final key = d.year * 100 + d.month;
    return _extraMonthSigned[key]?.contains(d.day) ?? false;
  }

  bool _isDayKnown(DateTime day) {
    final now = AutoSignService.instance.estimatedServerNow;
    if (day.year == now.year && day.month == now.month && day.day == now.day) {
      return _stateKnown;
    }
    return _isDaySigned(day) ||
        _knownMonths.contains(day.year * 100 + day.month);
  }

  Future<void> _loadSignData() async {
    if (_loadingSignData || widget.isPreview || !DioClient.isLoggedIn) return;
    _loadingSignData = true;
    final generation = ++_dataGeneration;
    final session = DioClient.sessionKey;

    final serverNow = AutoSignService.instance.estimatedServerNow;
    final targetYear = _currentMonth.year;
    final targetMonth = _currentMonth.month;

    // 1. 优先从本地持久化缓存读取目标月份及跨月周历数据，实现零延迟即时展示
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted ||
          session != DioClient.sessionKey ||
          generation != _dataGeneration) {
        return;
      }
      final monthKey = KlpbbsApi.signCalendarKey(targetYear, targetMonth);
      final cachedList = sp.getStringList(monthKey);
      final isTodaySigned = AutoSignService.instance.isSignedToday();

      // 预读上一个月本地打卡记录，供跨月 7 天胶囊视图使用
      final prevMonthDate = DateTime(targetYear, targetMonth - 1, 1);
      final prevMonthKey =
          KlpbbsApi.signCalendarKey(prevMonthDate.year, prevMonthDate.month);
      final prevCached = sp.getStringList(prevMonthKey);
      if (prevCached != null && prevCached.isNotEmpty) {
        final prevDays = prevCached
            .map((d) => int.tryParse(d) ?? 0)
            .where((d) => d > 0)
            .toSet();
        _extraMonthSigned[prevMonthDate.year * 100 + prevMonthDate.month] =
            prevDays;
      }

      if (cachedList != null && cachedList.isNotEmpty) {
        final localDays = cachedList
            .map((d) => int.tryParse(d) ?? 0)
            .where((d) => d > 0)
            .toSet();
        if (targetYear == serverNow.year && targetMonth == serverNow.month) {
          if (isTodaySigned) {
            localDays.add(serverNow.day);
          } else if (AutoSignService.instance.confirmedTodayState == false) {
            localDays.remove(serverNow.day);
          }
        }
        if (mounted &&
            session == DioClient.sessionKey &&
            _currentMonth.year == targetYear &&
            _currentMonth.month == targetMonth) {
          setState(() {
            _syncLocalState();
            _signedDays = localDays;
          });
        }
      } else if (isTodaySigned &&
          targetYear == serverNow.year &&
          targetMonth == serverNow.month) {
        if (mounted &&
            session == DioClient.sessionKey &&
            _currentMonth.year == targetYear &&
            _currentMonth.month == targetMonth) {
          setState(() {
            _signed = true;
            _signedDays = {serverNow.day};
          });
        }
      }
    } catch (_) {}

    // 2. 从服务端抓取权威最新签到状态与当前月份日历
    try {
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: false);
      if (!mounted ||
          session != DioClient.sessionKey ||
          generation != _dataGeneration) {
        return;
      }
      setState(() {
        _stateDay = AutoSignService.instance.serverTodayStr;
        _applyHeader(info);
      });
      final days = await KlpbbsApi.getSignedDaysFromServerCalendar(
        year: targetYear,
        month: targetMonth,
        forceRefresh: false,
      );
      if (mounted &&
          session == DioClient.sessionKey &&
          generation == _dataGeneration &&
          _currentMonth.year == targetYear &&
          _currentMonth.month == targetMonth) {
        final effSigned = info.hasPersonalState
            ? info.isSignedToday
            : AutoSignService.instance.isSignedToday();
        final effectiveDays = <int>{...days};
        if (effSigned &&
            targetYear == serverNow.year &&
            targetMonth == serverNow.month) {
          effectiveDays.add(serverNow.day);
        }
        setState(() {
          _stateDay = AutoSignService.instance.serverTodayStr;
          _applyHeader(info);
          _knownMonths.add(targetYear * 100 + targetMonth);
          _signedDays = effectiveDays;
        });
      }
    } catch (_) {
    } finally {
      if (generation == _dataGeneration) _loadingSignData = false;
    }
  }

  Future<void> _jumpToMonth(int targetYear, int targetMonth) async {
    final session = DioClient.sessionKey;
    final serverNow = AutoSignService.instance.estimatedServerNow;
    if (_currentMonth.year == targetYear &&
        _currentMonth.month == targetMonth) {
      return;
    }

    final currentTarget = DateTime(targetYear, targetMonth, 1);
    final monthKey =
        KlpbbsApi.signCalendarKey(currentTarget.year, currentTarget.month);
    Set<int> initialDays = {};
    try {
      final sp = await SharedPreferences.getInstance();
      final cachedList = sp.getStringList(monthKey);
      if (cachedList != null && cachedList.isNotEmpty) {
        initialDays = cachedList
            .map((d) => int.tryParse(d) ?? 0)
            .where((d) => d > 0)
            .toSet();
      }
    } catch (_) {}
    if (!mounted || session != DioClient.sessionKey) return;

    final isCurrent =
        (targetYear == serverNow.year && targetMonth == serverNow.month);
    final effSigned = _signed || AutoSignService.instance.isSignedToday();

    setState(() {
      _currentMonth = currentTarget;
      _signedDays = initialDays;
      if (effSigned && isCurrent) {
        _signedDays.add(serverNow.day);
      }
      _loadingMonth = true;
    });

    try {
      final days = await KlpbbsApi.getSignedDaysFromServerCalendar(
        year: currentTarget.year,
        month: currentTarget.month,
      );
      if (mounted &&
          session == DioClient.sessionKey &&
          _currentMonth.year == targetYear &&
          _currentMonth.month == targetMonth) {
        final effectiveDays = <int>{...days};
        if (effSigned && isCurrent) {
          effectiveDays.add(serverNow.day);
        }
        setState(() {
          _signedDays = effectiveDays;
          _knownMonths.add(targetYear * 100 + targetMonth);
          _loadingMonth = false;
        });
      }
    } catch (_) {
      if (mounted &&
          session == DioClient.sessionKey &&
          _currentMonth.year == targetYear &&
          _currentMonth.month == targetMonth) {
        setState(() => _loadingMonth = false);
      }
    }
  }

  Future<void> _changeMonth(int delta) async {
    final serverNow = AutoSignService.instance.estimatedServerNow;
    final next = DateTime(_currentMonth.year, _currentMonth.month + delta, 1);

    // 限制只能在过去 36 个月至当前月份之间切换
    final minMonth = DateTime(serverNow.year - 3, 1, 1);
    final maxMonth = DateTime(serverNow.year, serverNow.month, 1);
    if (next.isBefore(minMonth) || next.isAfter(maxMonth)) return;

    await _jumpToMonth(next.year, next.month);
  }

  Future<void> _jumpToCurrentMonth() async {
    final serverNow = AutoSignService.instance.estimatedServerNow;
    await _jumpToMonth(serverNow.year, serverNow.month);
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
    final serverDay = AutoSignService.instance.estimatedServerNow;
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
          if (success &&
              _currentMonth.year == serverDay.year &&
              _currentMonth.month == serverDay.month) {
            _signedDays.add(serverDay.day);
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
        }
        if (!mounted || session != DioClient.sessionKey) return;
        final isOutageProbing = AutoSignService.instance.isProbingRecovery;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              res.message.isNotEmpty
                  ? res.message
                  : (success
                      ? '打卡成功！'
                      : (isOutageProbing
                          ? '服务器异常，后台已启动静默实时探测，恢复后即刻打卡！'
                          : '打卡未完成')),
            ),
            duration: Duration(seconds: isOutageProbing ? 4 : 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted || session != DioClient.sessionKey) return;
      final outage = ServerOutageInfo.tryParse(e);
      if (outage != null) {
        AutoSignService.instance.notifyServerOutage(outage, source: '桌面卡片手动签到');
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              outage != null
                  ? '论坛服务器异常 (${outage.statusCode})，本次签到未确认，请稍后重试'
                  : '签到异常: $e',
            ),
            duration: Duration(seconds: outage != null ? 4 : 3),
          ),
        );
      }
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _signing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colSpan = widget.item.colSpan;
    final rowSpan = widget.item.rowSpan;

    final rawDataStyle =
        widget.item.customParams['dataStyle'] as String? ?? 'auto';
    final String dataStyle;
    if (rawDataStyle == 'auto') {
      final isCompact = rowSpan <= 1 || colSpan <= 2;
      final isExpanded = rowSpan >= 3 && colSpan >= 4;
      dataStyle = isCompact ? 'minimal' : (isExpanded ? 'calendar' : 'week');
    } else {
      dataStyle = rawDataStyle;
    }

    Widget content;
    switch (dataStyle) {
      case 'calendar':
        content = _buildFullCalendarLOD(context);
        break;
      case 'streak':
        content = _buildStreakMilestoneLOD(context);
        break;
      case 'minimal':
        content = _buildCompactLOD(context);
        break;
      case 'week':
      default:
        content = _buildMediumLOD(context);
        break;
    }

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        child: content,
      ),
    );
  }

  /// 连签里程碑大卡数据展示样式（突出连续签到天数、大徽章、今日签到状态与奖励预览）
  Widget _buildStreakMilestoneLOD(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardTheme = DashboardCardTheme.of(context);
    final accent = cardTheme.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部
        Row(
          children: [
            Icon(Icons.military_tech_rounded, size: 18, color: accent),
            const SizedBox(width: 6),
            Text(
              '每日打卡 · 连签里程碑',
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
                color: _signed
                    ? const Color(0xFF4CAF50).withAlpha(25)
                    : accent.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _signed
                      ? const Color(0xFF4CAF50).withAlpha(50)
                      : accent.withAlpha(50),
                  width: 0.8,
                ),
              ),
              child: Text(
                _todayLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _signed ? const Color(0xFF4CAF50) : accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 主体区域
        Expanded(
          child: Row(
            children: [
              // 左侧连签徽章
              Container(
                width: 96,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: colorScheme.outlineVariant.withAlpha(60),
                      width: 0.8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 24,
                      color: _signed ? accent : colorScheme.outline,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _streakLabel,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: _signed ? accent : colorScheme.onSurface,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      '连续打卡天数',
                      style: TextStyle(
                          fontSize: 9.5,
                          color: colorScheme.onSurfaceVariant.withAlpha(160)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // 右侧打卡操作与数据摘要
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _signed ? '今日已完成签到' : _todayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_monthLabel${_retroSignDays > 0 ? ' · 可补签 $_retroSignDays 天' : ''}',
                      style:
                          TextStyle(fontSize: 11, color: colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _signed
                              ? colorScheme.surfaceContainerHighest
                              : accent,
                          foregroundColor: _signed
                              ? colorScheme.onSurfaceVariant
                              : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _signing ? null : _handleSign,
                        icon: _signing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: AppLoadingIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(
                                _signed
                                    ? Icons.emoji_events_rounded
                                    : Icons.touch_app_rounded,
                                size: 16,
                              ),
                        label: Text(
                          _signed ? '查看打卡风云榜' : '立即签到打卡',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 1. 紧凑 LOD（1x1 / 2x1 迷你状态栏与快捷签到）
  Widget _buildCompactLOD(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardTheme = DashboardCardTheme.of(context);
    final accent = cardTheme.accentColor;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withAlpha(24),
          ),
          child: Icon(Icons.calendar_month_rounded, size: 18, color: accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Text(
                    _todayLabel,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  if (_streakKnown && _streakDays > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, size: 11, color: accent),
                          const SizedBox(width: 1.5),
                          Text(
                            '$_streakDays天',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$_monthLabel${_retroSignDays > 0 ? ' · 可补签 $_retroSignDays 天' : ''}',
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
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
            backgroundColor:
                (!_signed && AutoSignService.instance.isProbingRecovery)
                    ? Colors.amber.withAlpha(50)
                    : accent.withAlpha(cardTheme.isDark ? 45 : 30),
          ),
          onPressed: _signing ? null : _handleSign,
          child: Text(
            _signed
                ? '日历'
                : (_signing
                    ? '中...'
                    : (AutoSignService.instance.isProbingRecovery
                        ? '探测'
                        : '签到')),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: (!_signed && AutoSignService.instance.isProbingRecovery)
                  ? Colors.amber.shade900
                  : accent,
            ),
          ),
        ),
      ],
    );
  }

  /// 2. 标准 LOD（2x2 / 3x2：7 天连续打卡环 + 里程碑奖励进度条）
  Widget _buildMediumLOD(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardTheme = DashboardCardTheme.of(context);
    final accent = cardTheme.accentColor;
    final isDark = cardTheme.isDark;
    final now = AutoSignService.instance.estimatedServerNow;

    // 计算本周 7 天的日期
    final currentWeekday = now.weekday; // 1 (Mon) .. 7 (Sun)
    final monday = now.subtract(Duration(days: currentWeekday - 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部
        Row(
          children: [
            Icon(Icons.event_available_rounded, size: 16, color: accent),
            const SizedBox(width: 6),
            Text(
              '每日签到日历',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: accent.withAlpha(isDark ? 45 : 25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _streakKnown ? '连签 $_streakDays 天' : '连签 —',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold, color: accent),
              ),
            ),
            const Spacer(),
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

        // 7 天打卡胶囊行
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final dayDate = monday.add(Duration(days: i));
              final isToday = dayDate.day == now.day &&
                  dayDate.month == now.month &&
                  dayDate.year == now.year;
              final isPast =
                  dayDate.isBefore(DateTime(now.year, now.month, now.day));
              final isSignedDay = _isDaySigned(dayDate);
              final weekdayName = ['一', '二', '三', '四', '五', '六', '日'][i];

              Color bgColor;
              Color fgColor;
              Widget statusIcon;

              if (isSignedDay) {
                bgColor = accent.withAlpha(isDark ? 45 : 30);
                fgColor = accent;
                statusIcon =
                    Icon(Icons.check_circle_rounded, size: 14, color: accent);
              } else if (isToday) {
                bgColor = _signed
                    ? accent.withAlpha(isDark ? 45 : 30)
                    : accent.withAlpha(25);
                fgColor = accent;
                statusIcon = Icon(
                  _signed
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_checked_rounded,
                  size: 14,
                  color: accent,
                );
              } else if (isPast && _isDayKnown(dayDate)) {
                bgColor = Colors.grey.withAlpha(20);
                fgColor = colorScheme.outline;
                statusIcon = Icon(Icons.remove_circle_outline_rounded,
                    size: 13, color: colorScheme.outlineVariant);
              } else {
                bgColor = Colors.transparent;
                fgColor = colorScheme.outline.withAlpha(140);
                statusIcon = Icon(Icons.radio_button_unchecked_rounded,
                    size: 13, color: colorScheme.outlineVariant);
              }

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          isToday ? accent.withAlpha(150) : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        weekdayName,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: fgColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${dayDate.day}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: fgColor),
                      ),
                      const SizedBox(height: 3),
                      statusIcon,
                    ],
                  ),
                ),
              );
            }),
          ),
        ),

        const SizedBox(height: 8),
        // 底部动作条
        Row(
          children: [
            Expanded(
              child: Text(
                _signed
                    ? '今日已完成签到'
                    : (AutoSignService.instance.isProbingRecovery
                        ? '📡 论坛502异常 · 静默探测中(${AutoSignService.instance.recoveryProbeCount}次)'
                        : (!_stateKnown
                            ? _todayLabel
                            : _retroSignDays > 0
                                ? '发现断签记录，可用补签卡挽救连签'
                                : '坚持打卡，保持连续签到记录')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color:
                      (!_signed && AutoSignService.instance.isProbingRecovery)
                          ? Colors.amber.shade800
                          : colorScheme.outline,
                  fontWeight:
                      (!_signed && AutoSignService.instance.isProbingRecovery)
                          ? FontWeight.w600
                          : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                backgroundColor:
                    (!_signed && AutoSignService.instance.isProbingRecovery)
                        ? Colors.amber.withAlpha(50)
                        : null,
              ),
              onPressed: _signing ? null : _handleSign,
              child: Text(
                _signed
                    ? '查看日历'
                    : (_signing
                        ? '打卡中'
                        : (AutoSignService.instance.isProbingRecovery
                            ? '502探测中'
                            : '立即签到')),
                style: TextStyle(
                  color:
                      (!_signed && AutoSignService.instance.isProbingRecovery)
                          ? Colors.amber.shade900
                          : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 3. 全量日历 LOD（4x3 及以上：完整交互式月历网格，高亮打卡数据）
  Widget _buildFullCalendarLOD(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardTheme = DashboardCardTheme.of(context);
    final accent = cardTheme.accentColor;
    final isDark = cardTheme.isDark;
    final serverNow = AutoSignService.instance.estimatedServerNow;

    final y = _currentMonth.year;
    final m = _currentMonth.month;
    final firstDayOfMonth = DateTime(y, m, 1);
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday; // 1 (Mon) .. 7 (Sun)
    final isCurrentMonth = (y == serverNow.year && m == serverNow.month);
    final minMonth = DateTime(serverNow.year - 1, serverNow.month, 1);
    final canGoPrev = firstDayOfMonth.isAfter(minMonth);
    final canGoNext = !isCurrentMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部切换条（自适应防溢出排版）
        Row(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(isDark ? 45 : 25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.calendar_month_rounded,
                        size: 14, color: accent),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () async {
                        final res = await YearMonthPickerDialog.show(
                          context,
                          initialYear: y,
                          initialMonth: m,
                        );
                        if (res != null && mounted) {
                          _jumpToMonth(res.$1, res.$2);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                '$y年$m月',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.arrow_drop_down_rounded,
                                size: 16, color: accent),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(isDark ? 35 : 20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _knownMonths.contains(y * 100 + m)
                          ? '${_signedDays.length}/$daysInMonth天'
                          : '已确认 ${_signedDays.length} 天',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            // 月份切换按钮与动作组
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 17),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  onPressed: canGoPrev ? () => _changeMonth(-1) : null,
                  tooltip: canGoPrev ? '上一月' : '已是最早月份',
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 17),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  onPressed: canGoNext ? () => _changeMonth(1) : null,
                  tooltip: canGoNext ? '下一月' : '已是当月',
                ),
                const SizedBox(width: 2),
                if (!isCurrentMonth)
                  Tooltip(
                    message: '返回当前月份',
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.today_rounded, size: 11),
                      label: const Text('当月',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 0),
                        minimumSize: const Size(0, 24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        side: BorderSide(
                            color: accent.withAlpha(120), width: 0.9),
                        foregroundColor: accent,
                      ),
                      onPressed: _jumpToCurrentMonth,
                    ),
                  )
                else
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 0),
                      minimumSize: const Size(0, 24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                      backgroundColor: (!_signed &&
                              AutoSignService.instance.isProbingRecovery)
                          ? Colors.amber.withAlpha(50)
                          : accent.withAlpha(isDark ? 45 : 30),
                    ),
                    onPressed: _signing ? null : _handleSign,
                    child: Text(
                      _signed
                          ? '已打卡'
                          : (AutoSignService.instance.isProbingRecovery
                              ? '502探测'
                              : '打卡'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: (!_signed &&
                                AutoSignService.instance.isProbingRecovery)
                            ? Colors.amber.shade900
                            : accent,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),

        // 星期表头
        Row(
          children: ['一', '二', '三', '四', '五', '六', '日'].map((w) {
            final isWeekend = w == '六' || w == '日';
            return Expanded(
              child: Center(
                child: Text(
                  w,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isWeekend
                        ? colorScheme.primary.withAlpha(210)
                        : colorScheme.onSurfaceVariant.withAlpha(150),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),

        // 日历网格
        Expanded(
          child: _loadingMonth
              ? const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: AppLoadingIndicator(strokeWidth: 2)))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final rawHeight = constraints.maxHeight.isFinite
                        ? constraints.maxHeight
                        : 180.0;
                    final cellHeight = (rawHeight / 6.0).clamp(14.0, 36.0);
                    final cellWidth = constraints.maxWidth / 7.0;
                    final ratio = (cellWidth / cellHeight).clamp(1.1, 2.6);
                    return GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 42, // 6 行 x 7 列
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        childAspectRatio: ratio,
                      ),
                      itemBuilder: (context, idx) {
                        final dayNum = idx - (startWeekday - 2);
                        if (dayNum < 1 || dayNum > daysInMonth) {
                          return const SizedBox.shrink();
                        }

                        final isToday = (y == serverNow.year &&
                            m == serverNow.month &&
                            dayNum == serverNow.day);
                        final isPast = (y < serverNow.year) ||
                            (y == serverNow.year && m < serverNow.month) ||
                            (y == serverNow.year &&
                                m == serverNow.month &&
                                dayNum < serverNow.day);
                        final isSigned = _signedDays.contains(dayNum);

                        Color bg = Colors.transparent;
                        Color textColor = colorScheme.onSurface;
                        Border? border;

                        if (isSigned) {
                          bg = colorScheme.primaryContainer
                              .withAlpha(isDark ? 160 : 200);
                          textColor = colorScheme.onPrimaryContainer;
                        } else if (isToday) {
                          bg = colorScheme.surfaceContainerHighest
                              .withAlpha(140);
                          textColor = colorScheme.primary;
                          border = Border.all(
                              color: colorScheme.primary, width: 1.2);
                        } else if (isPast) {
                          textColor = colorScheme.outline.withAlpha(120);
                        }

                        return Center(
                          child: Container(
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(8),
                              border: border,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$dayNum',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isToday || isSigned
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: textColor,
                                    ),
                                  ),
                                  if (isSigned)
                                    Container(
                                      width: 3.5,
                                      height: 3.5,
                                      margin: const EdgeInsets.only(top: 1),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),

        // 底部指标（横向滚动防溢出）
        Container(
          padding: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(
                    color: colorScheme.outlineVariant.withAlpha(30),
                    width: 0.8)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (!_stateKnown) ...[
                  _buildMiniMetric('今日', '待确认', accent),
                  const SizedBox(width: 8),
                ],
                _buildMiniMetric(
                    '连签', _streakKnown ? '$_streakDays天' : '—', accent),
                const SizedBox(width: 8),
                _buildMiniMetric(
                    isCurrentMonth ? '本月出勤' : '当月出勤',
                    _knownMonths.contains(y * 100 + m)
                        ? '${_signedDays.length}/$daysInMonth'
                        : '已确认 ${_signedDays.length} 天',
                    accent),
                const SizedBox(width: 8),
                _buildMiniMetric(
                    '可补签', _stateKnown ? '$_retroSignDays天' : '—', accent),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SignRankPage())),
                  child: Text('查看连签排行 ›',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: accent,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniMetric(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(
              fontSize: 10.5, color: Theme.of(context).colorScheme.outline),
        ),
        Text(
          value,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
