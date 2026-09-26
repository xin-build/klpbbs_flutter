import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/klpbbs_api.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/server_outage_info.dart';
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
  State<SignInCalendarDashboardCard> createState() => _SignInCalendarDashboardCardState();
}

class _SignInCalendarDashboardCardState extends State<SignInCalendarDashboardCard> {
  bool _signed = false;
  int _streakDays = 0;
  int _retroSignDays = 0;
  bool _signing = false;
  DateTime _currentMonth = DateTime.now();
  Set<int> _signedDays = {};
  final Map<int, Set<int>> _extraMonthSigned = {};
  bool _loadingMonth = false;
  bool _loadingSignData = false;

  @override
  void initState() {
    super.initState();
    final serverNow = AutoSignService.instance.estimatedServerNow;
    _currentMonth = DateTime(serverNow.year, serverNow.month, 1);

    if (widget.isPreview) {
      final isAlreadySigned = AutoSignService.instance.isSignedToday();
      _signed = isAlreadySigned;
      _streakDays = AutoSignService.instance.continuousDays > 0 ? AutoSignService.instance.continuousDays : 12;
      _retroSignDays = 2;
      _signedDays = {
        for (int i = 1; i <= serverNow.day; i++)
          if (i % 4 != 0) i,
      };
      if (_signed) _signedDays.add(serverNow.day);
      return;
    }

    AutoSignService.instance.addListener(_onAutoSignChanged);
    _signed = AutoSignService.instance.isSignedToday();
    if (AutoSignService.instance.continuousDays > 0) {
      _streakDays = AutoSignService.instance.continuousDays;
    }
    _loadSignData();
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
    final isTodaySigned = AutoSignService.instance.isSignedToday();
    final serviceDays = AutoSignService.instance.continuousDays;
    final serverNow = AutoSignService.instance.estimatedServerNow;
    setState(() {
      _signed = isTodaySigned;
      if (serviceDays > 0) _streakDays = serviceDays;
      if (_currentMonth.year == serverNow.year && _currentMonth.month == serverNow.month) {
        if (isTodaySigned) {
          _signedDays.add(serverNow.day);
        } else {
          _signedDays.remove(serverNow.day);
        }
      }
    });
    // 严禁在此处调用 _loadSignData()！因为 _loadSignData 会调用 KlpbbsApi，
    // 而 KlpbbsApi 会调用 AutoSignService.markSignedToday()，从而形成无限异步重入级联死循环！
  }

  bool _isDaySigned(DateTime d) {
    final serverNow = AutoSignService.instance.estimatedServerNow;
    if (d.year == serverNow.year && d.month == serverNow.month && d.day == serverNow.day) {
      return _signed;
    }
    if (d.year == _currentMonth.year && d.month == _currentMonth.month) {
      return _signedDays.contains(d.day);
    }
    final key = d.year * 100 + d.month;
    return _extraMonthSigned[key]?.contains(d.day) ?? false;
  }

  Future<void> _loadSignData() async {
    if (_loadingSignData || widget.isPreview) return;
    _loadingSignData = true;

    final serverNow = AutoSignService.instance.estimatedServerNow;
    final targetYear = _currentMonth.year;
    final targetMonth = _currentMonth.month;

    // 1. 优先从本地持久化缓存读取目标月份及跨月周历数据，实现零延迟即时展示
    try {
      final sp = await SharedPreferences.getInstance();
      final monthKey = 'sign_dates_$targetYear${targetMonth.toString().padLeft(2, '0')}';
      final cachedList = sp.getStringList(monthKey);
      final isTodaySigned = AutoSignService.instance.isSignedToday();

      // 预读上一个月本地打卡记录，供跨月 7 天胶囊视图使用
      final prevMonthDate = DateTime(targetYear, targetMonth - 1, 1);
      final prevMonthKey = 'sign_dates_${prevMonthDate.year}${prevMonthDate.month.toString().padLeft(2, '0')}';
      final prevCached = sp.getStringList(prevMonthKey);
      if (prevCached != null && prevCached.isNotEmpty) {
        final prevDays = prevCached.map((d) => int.tryParse(d) ?? 0).where((d) => d > 0).toSet();
        _extraMonthSigned[prevMonthDate.year * 100 + prevMonthDate.month] = prevDays;
      }

      if (cachedList != null && cachedList.isNotEmpty) {
        final localDays = cachedList.map((d) => int.tryParse(d) ?? 0).where((d) => d > 0).toSet();
        if (targetYear == serverNow.year && targetMonth == serverNow.month) {
          if (isTodaySigned) {
            localDays.add(serverNow.day);
          } else {
            localDays.remove(serverNow.day);
          }
        }
        if (mounted && _currentMonth.year == targetYear && _currentMonth.month == targetMonth) {
          setState(() {
            _signed = isTodaySigned;
            _signedDays = localDays;
          });
        }
      } else if (isTodaySigned && targetYear == serverNow.year && targetMonth == serverNow.month) {
        if (mounted && _currentMonth.year == targetYear && _currentMonth.month == targetMonth) {
          setState(() {
            _signed = true;
            _signedDays = {serverNow.day};
          });
        }
      }
    } catch (_) {}

    // 2. 从服务端抓取权威最新签到状态与当前月份日历
    try {
      final info = await KlpbbsApi.getSignHeaderInfo();
      final days = await KlpbbsApi.getSignedDaysFromServerCalendar(
        year: targetYear,
        month: targetMonth,
      );
      if (mounted && _currentMonth.year == targetYear && _currentMonth.month == targetMonth) {
        final effSigned = info.isSignedToday || AutoSignService.instance.isSignedToday();
        final streak = info.continuousDays > 0
            ? info.continuousDays
            : (AutoSignService.instance.continuousDays > 0 ? AutoSignService.instance.continuousDays : 0);
        final effectiveDays = <int>{...days};
        if (effSigned && targetYear == serverNow.year && targetMonth == serverNow.month) {
          effectiveDays.add(serverNow.day);
          for (var i = 1; i < streak; i++) {
            final pastDay = serverNow.day - i;
            if (pastDay >= 1) {
              effectiveDays.add(pastDay);
            }
          }
        }
        setState(() {
          _signed = effSigned;
          if (streak > 0) _streakDays = streak;
          if (info.retroSignDays > 0) _retroSignDays = info.retroSignDays;
          _signedDays = effectiveDays.isNotEmpty ? effectiveDays : _signedDays;
        });
      }
    } catch (_) {
    } finally {
      _loadingSignData = false;
    }
  }

  Future<void> _jumpToMonth(int targetYear, int targetMonth) async {
    final serverNow = AutoSignService.instance.estimatedServerNow;
    if (_currentMonth.year == targetYear && _currentMonth.month == targetMonth) {
      return;
    }

    final currentTarget = DateTime(targetYear, targetMonth, 1);
    final monthKey = 'sign_dates_${currentTarget.year}${currentTarget.month.toString().padLeft(2, '0')}';
    Set<int> initialDays = {};
    try {
      final sp = await SharedPreferences.getInstance();
      final cachedList = sp.getStringList(monthKey);
      if (cachedList != null && cachedList.isNotEmpty) {
        initialDays = cachedList.map((d) => int.tryParse(d) ?? 0).where((d) => d > 0).toSet();
      }
    } catch (_) {}

    final isCurrent = (targetYear == serverNow.year && targetMonth == serverNow.month);
    final effSigned = _signed || AutoSignService.instance.isSignedToday();

    setState(() {
      _currentMonth = currentTarget;
      _signedDays = initialDays;
      if (effSigned && isCurrent) {
        _signedDays.add(serverNow.day);
        for (var i = 1; i < _streakDays && serverNow.day - i >= 1; i++) {
          _signedDays.add(serverNow.day - i);
        }
      }
      _loadingMonth = true;
    });

    try {
      final days = await KlpbbsApi.getSignedDaysFromServerCalendar(
        year: currentTarget.year,
        month: currentTarget.month,
      );
      if (mounted && _currentMonth.year == targetYear && _currentMonth.month == targetMonth) {
        final effectiveDays = <int>{...days};
        if (effSigned && isCurrent) {
          effectiveDays.add(serverNow.day);
          for (var i = 1; i < _streakDays && serverNow.day - i >= 1; i++) {
            effectiveDays.add(serverNow.day - i);
          }
        }
        setState(() {
          _signedDays = effectiveDays.isNotEmpty ? effectiveDays : initialDays;
          _loadingMonth = false;
        });
      }
    } catch (_) {
      if (mounted && _currentMonth.year == targetYear && _currentMonth.month == targetMonth) {
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
    if (widget.isPreview) {
      if (_signed) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SignRankPage()),
        );
      } else {
        setState(() => _signed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('预览模式：打卡完成！连签天数已更新')),
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
          if (success) {
            _signedDays.add(DateTime.now().day);
            for (var i = 1; i < _streakDays && DateTime.now().day - i >= 1; i++) {
              _signedDays.add(DateTime.now().day - i);
            }
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
        }
        final isOutageProbing = AutoSignService.instance.isProbingRecovery;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              res.message.isNotEmpty
                  ? res.message
                  : (success
                      ? '打卡成功！'
                      : (isOutageProbing ? '服务器异常，后台已启动静默实时探测，恢复后即刻打卡！' : '打卡未完成')),
            ),
            duration: Duration(seconds: isOutageProbing ? 4 : 2),
          ),
        );
      }
    } catch (e) {
      final outage = ServerOutageInfo.tryParse(e);
      if (outage != null) {
        AutoSignService.instance.notifyServerOutage(outage, source: '桌面卡片手动签到');
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              outage != null
                  ? '论坛服务器异常 (${outage.statusCode})：已启动后台静默实时探测，恢复后自动打卡'
                  : '签到异常: $e',
            ),
            duration: Duration(seconds: outage != null ? 4 : 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colSpan = widget.item.colSpan;
    final rowSpan = widget.item.rowSpan;

    final rawDataStyle = widget.item.customParams['dataStyle'] as String? ?? 'auto';
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
                color: _signed ? const Color(0xFF4CAF50).withAlpha(25) : accent.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _signed ? const Color(0xFF4CAF50).withAlpha(50) : accent.withAlpha(50),
                  width: 0.8,
                ),
              ),
              child: Text(
                _signed ? '今日已打卡' : '等待打卡',
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
                  border: Border.all(color: colorScheme.outlineVariant.withAlpha(60), width: 0.8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 24,
                      color: _signed ? Colors.orange : colorScheme.outline,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_streakDays',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: _signed ? Colors.orange.shade700 : colorScheme.onSurface,
                        height: 1.1,
                      ),
                    ),
                    const Text(
                      '连续打卡天数',
                      style: TextStyle(fontSize: 9.5, color: Colors.grey),
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
                      _signed ? '今日已完成签到，连签状态良好！' : '打卡可领 20 铁粒与成长经验',
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
                      '本月已签 ${_signedDays.length} 天 · 剩余补签卡 $_retroSignDays 张',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _signed ? colorScheme.surfaceContainerHighest : accent,
                          foregroundColor: _signed ? colorScheme.onSurfaceVariant : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _signing ? null : _handleSign,
                        icon: _signing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(
                                _signed ? Icons.emoji_events_rounded : Icons.touch_app_rounded,
                                size: 16,
                              ),
                        label: Text(
                          _signed ? '查看打卡风云榜' : '立即签到打卡',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
            gradient: LinearGradient(
              colors: [accent.withAlpha(190), accent],
            ),
          ),
          child: const Icon(Icons.calendar_month_rounded, size: 18, color: Colors.white),
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
                    _signed ? '今日已打卡' : '今日尚未签到',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  if (_streakDays > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '🔥$_streakDays天',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '本月打卡 ${_signedDays.length} 天${_retroSignDays > 0 ? ' · 可补签 $_retroSignDays 天' : ''}',
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: (!_signed && AutoSignService.instance.isProbingRecovery)
                ? Colors.amber.withAlpha(50)
                : accent.withAlpha(cardTheme.isDark ? 45 : 30),
          ),
          onPressed: _signing ? null : _handleSign,
          child: Text(
            _signed
                ? '日历'
                : (_signing
                    ? '中...'
                    : (AutoSignService.instance.isProbingRecovery ? '探测' : '签到')),
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
    final now = DateTime.now();

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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: accent.withAlpha(isDark ? 45 : 25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '连签 $_streakDays 天',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accent),
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

        // 7 天打卡胶囊行
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final dayDate = monday.add(Duration(days: i));
              final isToday = dayDate.day == now.day && dayDate.month == now.month && dayDate.year == now.year;
              final isPast = dayDate.isBefore(DateTime(now.year, now.month, now.day));
              final isSignedDay = _isDaySigned(dayDate);
              final weekdayName = ['一', '二', '三', '四', '五', '六', '日'][i];

              Color bgColor;
              Color fgColor;
              Widget statusIcon;

              if (isSignedDay) {
                bgColor = accent.withAlpha(isDark ? 45 : 30);
                fgColor = accent;
                statusIcon = Icon(Icons.check_circle_rounded, size: 14, color: accent);
              } else if (isToday) {
                bgColor = _signed ? accent.withAlpha(isDark ? 45 : 30) : accent.withAlpha(25);
                fgColor = accent;
                statusIcon = Icon(
                  _signed ? Icons.check_circle_rounded : Icons.radio_button_checked_rounded,
                  size: 14,
                  color: accent,
                );
              } else if (isPast) {
                bgColor = Colors.grey.withAlpha(20);
                fgColor = colorScheme.outline;
                statusIcon = Icon(Icons.remove_circle_outline_rounded, size: 13, color: colorScheme.outlineVariant);
              } else {
                bgColor = Colors.transparent;
                fgColor = colorScheme.outline.withAlpha(140);
                statusIcon = Icon(Icons.radio_button_unchecked_rounded, size: 13, color: colorScheme.outlineVariant);
              }

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isToday ? accent.withAlpha(150) : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        weekdayName,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fgColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${dayDate.day}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fgColor),
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
                    ? '🎉 今日已打卡，获得每日金粒奖励'
                    : (AutoSignService.instance.isProbingRecovery
                        ? '📡 论坛502异常 · 静默探测中(${AutoSignService.instance.recoveryProbeCount}次)'
                        : (_retroSignDays > 0 ? '💡 发现断签记录，可用补签卡挽救连签' : '✨ 坚持打卡，解锁高阶连签荣誉徽章')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: (!_signed && AutoSignService.instance.isProbingRecovery)
                      ? Colors.amber.shade800
                      : colorScheme.outline,
                  fontWeight: (!_signed && AutoSignService.instance.isProbingRecovery)
                      ? FontWeight.w600
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                backgroundColor: (!_signed && AutoSignService.instance.isProbingRecovery)
                    ? Colors.amber.withAlpha(50)
                    : null,
              ),
              onPressed: _signing ? null : _handleSign,
              child: Text(
                _signed
                    ? '查看日历'
                    : (_signing
                        ? '打卡中'
                        : (AutoSignService.instance.isProbingRecovery ? '502探测中' : '立即签到')),
                style: TextStyle(
                  color: (!_signed && AutoSignService.instance.isProbingRecovery)
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
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: accent.withAlpha(isDark ? 45 : 25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.calendar_month_rounded, size: 15, color: accent),
            ),
            const SizedBox(width: 6),
            Expanded(
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
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '$y年$m月',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down_rounded, size: 16, color: accent),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: accent.withAlpha(isDark ? 35 : 20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${_signedDays.length}/$daysInMonth天',
                          style: TextStyle(
                            fontSize: 10,
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // 月份切换按钮与动作组
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: canGoPrev ? () => _changeMonth(-1) : null,
                  tooltip: canGoPrev ? '上一月' : '已是最早月份',
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: canGoNext ? () => _changeMonth(1) : null,
                  tooltip: canGoNext ? '下一月' : '已是当月',
                ),
                const SizedBox(width: 4),
                if (!isCurrentMonth)
                  Tooltip(
                    message: '返回当前月份',
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.today_rounded, size: 12),
                      label: const Text('当月', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 0),
                        minimumSize: const Size(0, 26),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        side: BorderSide(color: accent.withAlpha(120), width: 0.9),
                        foregroundColor: accent,
                      ),
                      onPressed: _jumpToCurrentMonth,
                    ),
                  )
                else
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 0),
                      minimumSize: const Size(0, 26),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      backgroundColor: (!_signed && AutoSignService.instance.isProbingRecovery)
                          ? Colors.amber.withAlpha(50)
                          : accent.withAlpha(isDark ? 45 : 30),
                    ),
                    onPressed: _signing ? null : _handleSign,
                    child: Text(
                      _signed
                          ? '已打卡'
                          : (AutoSignService.instance.isProbingRecovery ? '502探测' : '打卡'),
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
                    fontWeight: FontWeight.bold,
                    color: isWeekend ? Colors.orange.shade700 : colorScheme.outline,
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
              ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final rawHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 180.0;
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

                    final isToday = (y == serverNow.year && m == serverNow.month && dayNum == serverNow.day);
                    final isPast = (y < serverNow.year) ||
                        (y == serverNow.year && m < serverNow.month) ||
                        (y == serverNow.year && m == serverNow.month && dayNum < serverNow.day);
                    final isSigned = _signedDays.contains(dayNum);

                    Color bg = Colors.transparent;
                    Color textColor = colorScheme.onSurface;
                    Border? border;

                    if (isSigned) {
                      bg = accent.withAlpha(isDark ? 45 : 35);
                      textColor = accent;
                    } else if (isToday) {
                      textColor = accent;
                      border = Border.all(color: accent, width: 1.4);
                    } else if (isPast) {
                      textColor = colorScheme.outline.withAlpha(120);
                    }

                    return Container(
                      margin: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(4),
                        border: border,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isToday || isSigned ? FontWeight.bold : FontWeight.normal,
                              color: textColor,
                            ),
                          ),
                          if (isSigned)
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Icon(Icons.check, size: 8, color: accent),
                            ),
                        ],
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
            border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(30), width: 0.8)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildMiniMetric('连签', '$_streakDays天', accent),
                const SizedBox(width: 8),
                _buildMiniMetric(isCurrentMonth ? '本月出勤' : '当月出勤', '${_signedDays.length}/$daysInMonth', Colors.blue.shade600),
                const SizedBox(width: 8),
                _buildMiniMetric('可补签', '$_retroSignDays天', Colors.orange.shade600),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignRankPage())),
                  child: Text('查看连签排行 ›', style: TextStyle(fontSize: 10.5, color: accent, fontWeight: FontWeight.bold)),
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
          style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.outline),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
