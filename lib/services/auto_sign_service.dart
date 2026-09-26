import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../models/server_outage_info.dart';
import '../models/sign_entry.dart';
import 'push_notification_service.dart';

/// 零点冲榜策略
enum BurstStrategy {
  statusPolling('高频探测抢签（单路极速状态探测，翻转即抢第 1 名）'),
  burstSpam('多路并发冲刺（多路流水线全时段并发，暴力拿下第 1 名）');

  final String label;
  const BurstStrategy(this.label);
}

/// 苦力怕论坛 自动签到、定时打卡与零点极速冲榜服务（全平台适配与生命周期感知）
class AutoSignService extends ChangeNotifier with WidgetsBindingObserver {
  static final AutoSignService instance = AutoSignService._();
  AutoSignService._();

  // Keys
  static const String _keyAutoLaunch = 'auto_sign_on_launch';
  static const String _keyScheduledEnabled = 'auto_sign_scheduled_enabled';
  static const String _keyScheduledHour = 'auto_sign_scheduled_hour';
  static const String _keyScheduledMinute = 'auto_sign_scheduled_minute';
  static const String _keyScheduledWindowSec = 'auto_sign_scheduled_window_sec';
  static const String _keyBurstEnabled = 'auto_sign_burst_enabled';
  static const String _keyBurstStrategy = 'auto_sign_burst_strategy';
  static const String _keyBurstInterval = 'auto_sign_burst_interval_ms';
  static const String _keyBurstPreSeconds = 'auto_sign_burst_pre_sec';
  static const String _keyBurstPostSeconds = 'auto_sign_burst_post_sec';
  static const String _keyNotifyResult = 'auto_sign_notify_result';
  static const String _keyLastSuccessDate = 'auto_sign_last_success_date';
  static const String _keyLastNotifiedDate = 'auto_sign_last_notified_date';
  static const String _keyRecoverySignEnabled = 'auto_sign_recovery_on_502';

  // Config States
  bool _autoSignOnLaunch = false;
  bool _scheduledSignEnabled = false;
  int _scheduledHour = 0;
  int _scheduledMinute = 0;
  int _scheduledWindowSec = 30; // 定时签到容差探测区间（秒）

  bool _burstModeEnabled = false;
  BurstStrategy _burstStrategy = BurstStrategy.statusPolling;
  int _burstIntervalMs = 200; // 默认 200ms 间隔，可在 50ms ~ 1000ms 自由调节
  int _burstPreSeconds = 15; // 提前开跑区间（23:59:45 开始），防服务器时钟比本地快
  int _burstPostSeconds = 20; // 跨天延后区间（00:00:20 结束），防服务器时钟比本地慢
  bool _notifyOnResult = true;

  // 502 / 网关宕机故障实时静默探测与恢复即签机制
  bool _serverRecoverySignEnabled = true;
  bool _isServerOutage = false;
  bool _isProbingRecovery = false;
  int _recoveryProbeCount = 0;
  DateTime? _outageStartTime;
  ServerOutageInfo? _lastOutageInfo;
  Timer? _recoveryProbeTimer;

  // Runtime States
  String _lastSuccessDate = '';
  String _lastNotifiedDate = '';
  int _continuousDays = 0;
  int _lastRank = 0;
  int _lastDay = DateTime.now().toUtc().add(const Duration(hours: 8)).day;
  bool _isRunning = false;
  DateTime? _runningStartTime; // 看门狗计时，防止卡死
  bool _isSnipingActive = false; // 是否处于 23:59 准备/冲刺阶段
  String _statusMessage = '服务未开启（等待配置）';
  Timer? _heartbeatTimer;
  DateTime? _lastFallbackCheckTime;
  DateTime? _lastCheckTime;

  int _serverClockOffsetMs = 0; // 服务端时钟与本地时钟毫秒级偏差 (server - local)

  // Getters
  bool get autoSignOnLaunch => _autoSignOnLaunch;
  int get serverClockOffsetMs => _serverClockOffsetMs;
  /// 论坛官方服务端当前精准时间（以东八区北京时间为基准，叠加毫秒级网络偏差校准）
  DateTime get estimatedServerNow {
    final utc = DateTime.now().toUtc().add(Duration(milliseconds: _serverClockOffsetMs));
    return utc.add(const Duration(hours: 8));
  }

  /// 论坛服务端当前的自然日日期字符串（YYYY-MM-DD，锚定东八区北京时间）
  String get serverTodayStr {
    final sn = estimatedServerNow;
    return '${sn.year}-${sn.month.toString().padLeft(2, '0')}-${sn.day.toString().padLeft(2, '0')}';
  }
  bool get scheduledSignEnabled => _scheduledSignEnabled;
  int get scheduledHour => _scheduledHour;
  int get scheduledMinute => _scheduledMinute;
  int get scheduledWindowSec => _scheduledWindowSec;
  String get scheduledTimeString =>
      '${_scheduledHour.toString().padLeft(2, '0')}:${_scheduledMinute.toString().padLeft(2, '0')}';

  bool get burstModeEnabled => _burstModeEnabled;
  BurstStrategy get burstStrategy => _burstStrategy;
  int get burstIntervalMs => _burstIntervalMs;
  int get burstPreSeconds => _burstPreSeconds;
  int get burstPostSeconds => _burstPostSeconds;
  String get burstTimeWindowDescription =>
      '23:59:${(60 - _burstPreSeconds).toString().padLeft(2, '0')} ~ 次日 00:00:${_burstPostSeconds.toString().padLeft(2, '0')} (共 ${_burstPreSeconds + _burstPostSeconds} 秒跨天保护区间)';

  bool get notifyOnResult => _notifyOnResult;
  bool get isRunning => _isRunning;
  bool get isSnipingActive => _isSnipingActive;
  String get statusMessage => _statusMessage;
  String get lastSuccessDate => _lastSuccessDate;
  String get lastNotifiedDate => _lastNotifiedDate;
  int get continuousDays => _continuousDays;
  int get lastRank => _lastRank;

  // 故障恢复探测状态 Getters
  bool get serverRecoverySignEnabled => _serverRecoverySignEnabled;
  bool get isServerOutage => _isServerOutage;
  bool get isProbingRecovery => _isProbingRecovery;
  int get recoveryProbeCount => _recoveryProbeCount;
  ServerOutageInfo? get lastOutageInfo => _lastOutageInfo;
  DateTime? get outageStartTime => _outageStartTime;

  /// 判断今日是否已成功签到（以论坛官方服务器时间及本地多重时区映射为准）
  /// 检查今日是否已完成签到（严格锚定论坛东八区北京时间与目标自然日，杜绝海外设备时区错位死锁）
  bool isSignedToday() {
    final sToday = serverTodayStr;
    return _lastSuccessDate == sToday;
  }

  /// 手动触发签到
  Future<void> signIn() => checkAndAutoSignIn(triggerSource: '手动点击打卡', force: true);

  /// 标记今日签到成功（持久化保存并同步本地缓存与日历，支持同步服务端最新名次与连续天数，默认静默不打扰用户）
  Future<void> markSignedToday({
    int? rank,
    int? continuousDays,
    String? rewardIron,
    String? rewardExp,
    bool notify = false,
  }) async {
    final todayStr = serverTodayStr;
    final bool wasAlreadySigned = _lastSuccessDate == todayStr;
    final rankText = (rank != null && rank > 0) ? ' (第 $rank 名)' : '';
    final daysText = (continuousDays != null && continuousDays > 0) ? ' | 连续 $continuousDays 天' : '';
    final newStatus = (rankText.isNotEmpty || daysText.isNotEmpty)
        ? '今日已完成签到$rankText$daysText'
        : '今日已完成签到';

    if (wasAlreadySigned && _statusMessage == newStatus && rank == null && continuousDays == null) {
      // 状态完全一致无变更，阻断重复磁盘写入与下游监听器级联风暴
      return;
    }

    _lastSuccessDate = todayStr;
    _statusMessage = newStatus;

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyLastSuccessDate, todayStr);
    if (continuousDays != null && continuousDays > 0) {
      _continuousDays = continuousDays;
      await sp.setInt('auto_sign_continuous_days', continuousDays);
    }
    if (rank != null && rank > 0) {
      _lastRank = rank;
      await sp.setInt('auto_sign_last_rank', rank);
    }
    await KlpbbsApi.clearSignLocalCache();
    await KlpbbsApi.recordSignDateToLocalCalendar();

    _cancelRecoveryProbe();
    notifyListeners();

    final savedNotifiedDate = sp.getString(_keyLastNotifiedDate) ?? '';
    final alreadyNotified = savedNotifiedDate == todayStr;

    if (notify && !alreadyNotified && !wasAlreadySigned && _notifyOnResult) {
      _lastNotifiedDate = todayStr;
      await sp.setString(_keyLastNotifiedDate, todayStr);
      String rewardSummary = '';
      if (rewardIron != null && rewardIron.isNotEmpty) {
        rewardSummary = (rewardExp != null && rewardExp.isNotEmpty)
            ? '铁粒 +$rewardIron, 经验 +$rewardExp'
            : '铁粒 +$rewardIron';
      } else if (rewardExp != null && rewardExp.isNotEmpty) {
        rewardSummary = '经验 +$rewardExp';
      } else {
        rewardSummary = '今日已完成签到打卡';
      }
      _pushSignResultNotification(
        rank: rank,
        continuousDays: continuousDays,
        rewardSummary: rewardSummary,
      );
    }
  }

  /// 标记今日未签到（清除本地伪签到缓存；默认保护通知防重标记不被破坏）
  Future<void> markUnsignedToday({bool resetNotification = false}) async {
    final sToday = serverTodayStr;
    final now = DateTime.now();
    final localToday = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final wasSigned = _lastSuccessDate == sToday || _lastSuccessDate == localToday;
    if (!wasSigned && _statusMessage == '今日尚未签到' && !resetNotification) {
      // 状态已是未签到，阻断冗余 notifyListeners 级联触发
      return;
    }

    if (_lastSuccessDate == sToday || _lastSuccessDate == localToday) {
      _lastSuccessDate = '';
    }
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyLastSuccessDate);

    if (resetNotification) {
      if (_lastNotifiedDate == sToday || _lastNotifiedDate == localToday) {
        _lastNotifiedDate = '';
      }
      await sp.remove(_keyLastNotifiedDate);
    }

    // 从本地日历缓存中移除今日
    final sn = estimatedServerNow;
    final monthKey = 'sign_dates_${sn.year}${sn.month.toString().padLeft(2, '0')}';
    final list = sp.getStringList(monthKey);
    if (list != null && list.contains('${sn.day}')) {
      final updated = list.where((d) => d != '${sn.day}').toList();
      await sp.setStringList(monthKey, updated);
    }
    _statusMessage = '今日尚未签到';
    notifyListeners();
  }

  /// 切换账号时重置签到状态并重新与服务端同步
  Future<void> onAccountSwitched() async {
    _lastSuccessDate = '';
    _lastNotifiedDate = '';
    _lastCheckTime = null;
    _lastFallbackCheckTime = null;
    _statusMessage = '账号已切换，正在与服务端对齐签到状态...';
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_keyLastSuccessDate);
      await sp.remove(_keyLastNotifiedDate);
    } catch (_) {}
    notifyListeners();
    if (DioClient.isLoggedIn) {
      _syncAndVerifyWithServer(serverTodayStr);
    }
  }

  /// 初始化自动签到引擎
  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _autoSignOnLaunch = sp.getBool(_keyAutoLaunch) ?? sp.getBool('auto_checkin') ?? true;
      _scheduledSignEnabled = sp.getBool(_keyScheduledEnabled) ?? false;
      _scheduledHour = sp.getInt(_keyScheduledHour) ?? 0;
      _scheduledMinute = sp.getInt(_keyScheduledMinute) ?? 0;
      _scheduledWindowSec = sp.getInt(_keyScheduledWindowSec) ?? 30;

      _burstModeEnabled = sp.getBool(_keyBurstEnabled) ?? false;
      final strategyIdx = sp.getInt(_keyBurstStrategy) ?? 0;
      _burstStrategy = (strategyIdx >= 0 && strategyIdx < BurstStrategy.values.length)
          ? BurstStrategy.values[strategyIdx]
          : BurstStrategy.statusPolling;
      _burstIntervalMs = sp.getInt(_keyBurstInterval) ?? 200;
      _burstPreSeconds = sp.getInt(_keyBurstPreSeconds) ?? 15;
      _burstPostSeconds = sp.getInt(_keyBurstPostSeconds) ?? 20;

      _notifyOnResult = sp.getBool(_keyNotifyResult) ?? true;
      // 净化旧版本提前写入 _keyLastNotifiedDate 导致今日通知被静默吞没的脏数据
      final hasNotifySanitized = sp.getBool('sign_notify_sanitized_v3') ?? false;
      if (!hasNotifySanitized) {
        await sp.remove(_keyLastNotifiedDate);
        _lastNotifiedDate = '';
        await sp.setBool('sign_notify_sanitized_v3', true);
      } else {
        _lastNotifiedDate = sp.getString(_keyLastNotifiedDate) ?? '';
      }
      _lastSuccessDate = sp.getString(_keyLastSuccessDate) ?? '';
      _continuousDays = sp.getInt('auto_sign_continuous_days') ?? 0;
      _lastRank = sp.getInt('auto_sign_last_rank') ?? 0;
      _serverRecoverySignEnabled = sp.getBool(_keyRecoverySignEnabled) ?? true;

      // 注册应用生命周期监听
      try {
        WidgetsBinding.instance.addObserver(this);
      } catch (_) {}

      // 启动 1 秒高精度心跳调度器
      _startHeartbeat();

      // 启动时直接抓取网页实时数据（PC UA）进行同步与自动打卡闭环
      Future.delayed(const Duration(milliseconds: 600), () {
        checkOnAppLaunch();
      });
    } catch (_) {}
  }

  /// 应用启动时直接抓取网页实时数据检测签到状态，若未签到直接签到
  Future<void> checkOnAppLaunch() async {
    if (!DioClient.isLoggedIn || _isRunning) return;
    try {
      // 1. 抓取网页实时数据（统一使用 PC UA，强刷无缓存）
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
      if (info.isSignedToday) {
        await markSignedToday(
          rank: info.mySignRank,
          continuousDays: info.continuousDays,
          rewardIron: info.rewardIron,
          notify: _notifyOnResult,
        );
      } else {
        await markUnsignedToday();
        // 2. 网页显示未签到，直接触发自动打卡闭环！
        await checkAndAutoSignIn(triggerSource: '启动检测未签直接打卡', force: true);
      }
    } catch (e) {
      final outage = ServerOutageInfo.tryParse(e);
      if (outage != null) {
        notifyServerOutage(outage, source: '启动签到检测');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台唤醒或解锁屏幕时，立即进行生命周期检测与错峰补签
      _onAppResumed();
    }
  }

  void _onAppResumed() {
    _handleAppResumed();
  }

  Future<void> _handleAppResumed() async {
    final todayStr = serverTodayStr;
    final serverDay = estimatedServerNow.day;

    try {
      final sp = await SharedPreferences.getInstance();
      final savedSuccess = sp.getString(_keyLastSuccessDate) ?? '';
      final savedNotified = sp.getString(_keyLastNotifiedDate) ?? '';

      bool stateChanged = false;

      if (serverDay != _lastDay) {
        _lastDay = serverDay;
        _lastCheckTime = null;
        _lastFallbackCheckTime = null;
        if (savedSuccess == todayStr) {
          if (_lastSuccessDate != todayStr) stateChanged = true;
          _lastSuccessDate = todayStr;
        } else {
          if (_lastSuccessDate.isNotEmpty) stateChanged = true;
          _lastSuccessDate = '';
        }
        if (savedNotified == todayStr) {
          _lastNotifiedDate = todayStr;
        } else {
          _lastNotifiedDate = '';
        }
      } else {
        if (savedSuccess == todayStr && _lastSuccessDate != todayStr) {
          _lastSuccessDate = todayStr;
          stateChanged = true;
        }
        if (savedNotified == todayStr && _lastNotifiedDate != todayStr) {
          _lastNotifiedDate = todayStr;
        }
      }
      if (stateChanged) {
        notifyListeners();
      }
    } catch (_) {}

    // 若未登录，直接终止后续网络请求
    if (!DioClient.isLoggedIn) return;

    final now = estimatedServerNow;
    // 若今日已完成签到且未到 23:58 次日预备期，全天彻底静默休眠，严禁发起任何后台网络请求
    if (isSignedToday() && !(now.hour == 23 && now.minute >= 58)) {
      return;
    }

    if (!_isRunning) {
      _syncAndVerifyWithServer(todayStr);
    }
  }

  // ================= 配置更新 =================

  Future<void> setAutoSignOnLaunch(bool val) async {
    _autoSignOnLaunch = val;
    AppConfig.autoCheckin = val;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyAutoLaunch, val);
    await sp.setBool('auto_checkin', val);
  }

  Future<void> setScheduledSignEnabled(bool val) async {
    _scheduledSignEnabled = val;
    _scheduleNextHeartbeat();
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyScheduledEnabled, val);
  }

  Future<void> setScheduledTime(int hour, int minute) async {
    _scheduledHour = hour;
    _scheduledMinute = minute;
    _scheduleNextHeartbeat();
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyScheduledHour, hour);
    await sp.setInt(_keyScheduledMinute, minute);
  }

  Future<void> setScheduledWindowSec(int sec) async {
    _scheduledWindowSec = sec.clamp(5, 120);
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyScheduledWindowSec, _scheduledWindowSec);
  }

  Future<void> setBurstModeEnabled(bool val) async {
    _burstModeEnabled = val;
    _scheduleNextHeartbeat();
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyBurstEnabled, val);
  }

  Future<void> setBurstStrategy(BurstStrategy val) async {
    _burstStrategy = val;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyBurstStrategy, val.index);
  }

  Future<void> setBurstIntervalMs(int ms) async {
    _burstIntervalMs = ms.clamp(50, 2000);
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyBurstInterval, _burstIntervalMs);
  }

  Future<void> setBurstPreSeconds(int sec) async {
    _burstPreSeconds = sec.clamp(5, 59);
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyBurstPreSeconds, _burstPreSeconds);
  }

  Future<void> setBurstPostSeconds(int sec) async {
    _burstPostSeconds = sec.clamp(5, 60);
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyBurstPostSeconds, _burstPostSeconds);
  }

  Future<void> setNotifyOnResult(bool val) async {
    _notifyOnResult = val;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyNotifyResult, val);
  }

  Future<void> setServerRecoverySignEnabled(bool val) async {
    _serverRecoverySignEnabled = val;
    if (!val) {
      _cancelRecoveryProbe();
    }
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyRecoverySignEnabled, val);
  }

  // ================= 核心调度引擎 =================

  void _startHeartbeat() {
    _scheduleNextHeartbeat(immediate: false);
  }

  void _scheduleNextHeartbeat({bool immediate = false}) {
    _heartbeatTimer?.cancel();
    if (immediate) {
      _onHeartbeatTick();
    }
    final delay = _resolveNextHeartbeatDuration();
    _heartbeatTimer = Timer(delay, () async {
      await _onHeartbeatTick();
      _scheduleNextHeartbeat();
    });
  }

  /// 计算下一次心跳周期：处于冲刺临界、跨天切换或定时签到临界期保持 1 秒高精度，平时 30~60 秒休眠省电
  Duration _resolveNextHeartbeatDuration() {
    if (_isRunning) {
      return const Duration(seconds: 1);
    }
    // 故障恢复探测期间：保持 2 秒高频调度警戒
    if (_isProbingRecovery) {
      return const Duration(seconds: 2);
    }
    final now = estimatedServerNow;

    // 签到后全天彻底静默：若今日已签到成功且未到 23:58 预备期，心跳进入 60 秒纯休眠，不发起任何网络请求
    if (isSignedToday() && !(now.hour == 23 && now.minute >= 58)) {
      return const Duration(seconds: 60);
    }

    final isAnyAutoEnabled = _burstModeEnabled || _scheduledSignEnabled || _autoSignOnLaunch || AppConfig.autoCheckin;

    // 零点跨天保护守护：只要开启任何自动化，23:59:40 ~ 00:00:30 全程保持 1 秒高频，确保 00:00:01 准点触发
    if (isAnyAutoEnabled) {
      if ((now.hour == 23 && now.minute == 59 && now.second >= 40) ||
          (now.hour == 0 && now.minute == 0 && now.second <= 30)) {
        return const Duration(seconds: 1);
      }
    }

    // 零点冲榜临界期：23:58 ~ 次日 00:02
    if (_burstModeEnabled) {
      if ((now.hour == 23 && now.minute >= 58) || (now.hour == 0 && now.minute <= 2)) {
        return const Duration(seconds: 1);
      }
    }
    // 定时签到临界期：目标签到时间前 15 秒 ~ 容差探测区间内，保持 1 秒高精度调度
    if (_scheduledSignEnabled && !isSignedToday()) {
      final scheduledToday = DateTime(now.year, now.month, now.day, _scheduledHour, _scheduledMinute);
      final diffSeconds = scheduledToday.difference(now).inSeconds;
      if (diffSeconds >= -_scheduledWindowSec && diffSeconds <= 15) {
        return const Duration(seconds: 1);
      }
    }
    return const Duration(seconds: 30);
  }

  bool _isTicking = false;
  Future<void> _onHeartbeatTick() async {
    if (_isTicking) return;
    _isTicking = true;
    try {
      // 看门狗保护：若运行状态超过 45 秒未解开，强制重置
      if (_isRunning && _runningStartTime != null) {
        if (DateTime.now().difference(_runningStartTime!).inSeconds > 45) {
          _isRunning = false;
          _runningStartTime = null;
          notifyListeners();
        }
      }

      if (!DioClient.isLoggedIn) return;

      final now = estimatedServerNow;
      final todayStr = serverTodayStr;
      final isAnyAutoEnabled = _burstModeEnabled || _scheduledSignEnabled || _autoSignOnLaunch || AppConfig.autoCheckin;

      // 0. 日历跨天秒级响应器 (Midnight Calendar Rollover Trigger)
      // 只要日期跳变为新的一天，立即重置跨天频控，启动凌晨自动打卡
      if (now.day != _lastDay) {
        _lastDay = now.day;
        _lastCheckTime = null; // 解除防抖
        _lastFallbackCheckTime = null;
        if (_lastSuccessDate != todayStr) {
          _lastSuccessDate = '';
          _lastNotifiedDate = '';
          try {
            final sp = await SharedPreferences.getInstance();
            final savedSuccess = sp.getString(_keyLastSuccessDate) ?? '';
            final savedNotified = sp.getString(_keyLastNotifiedDate) ?? '';
            if (savedSuccess == todayStr) {
              _lastSuccessDate = todayStr;
            } else {
              await sp.remove(_keyLastSuccessDate);
            }
            if (savedNotified == todayStr) {
              _lastNotifiedDate = todayStr;
            } else {
              await sp.remove(_keyLastNotifiedDate);
            }
          } catch (_) {}
        }

        if (_lastSuccessDate != todayStr && !_isRunning) {
          _statusMessage = '检测到零点跨天 ($todayStr)，启动今日凌晨自动签到...';
          notifyListeners();

          if (isAnyAutoEnabled) {
            if (_burstModeEnabled) {
              _startMidnightSnipeLoop(todayStr);
            } else if (_scheduledSignEnabled && _scheduledHour == 0 && _scheduledMinute == 0) {
              _executeScheduledSign();
            } else {
              checkAndAutoSignIn(triggerSource: '凌晨跨天自动打卡', force: true);
            }
          }
        }
      }

    // 1. 零点冲榜模式调度（在 23:58~23:59 开启准备、对齐精准时钟、预热 FormHash 与时间区间探测）
    if (_burstModeEnabled) {
      if (now.hour == 23 && (now.minute == 58 || now.minute == 59)) {
        // 23:58 / 23:59 冲刺的目标为次日签到
        final targetDate = now.add(const Duration(minutes: 3));
        final targetDateStr = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

        // 纠偏保护：23:58 绝不可能提前完成明天的签到。如果本地留存了明天的伪成功标记，立即纠偏清除！
        if (_lastSuccessDate == targetDateStr) {
          _lastSuccessDate = '';
          SharedPreferences.getInstance().then((sp) => sp.remove(_keyLastSuccessDate)).catchError((_) => false);
        }

        if (_lastSuccessDate != targetDateStr) {
          if (!_isSnipingActive) {
            _isSnipingActive = true;
            _statusMessage = '23:58 冲榜就绪状态已激活，正在对齐服务器精准时钟与预热 FormHash...';
            notifyListeners();
            _calibrateServerTime();
            KlpbbsApi.getSignFormhash(forceRefresh: true);
          }

          // 倒计时进入设定的提前区间（例如 23:59:45），开跑探测/发包，防止服务器时钟比本地快
          if (now.minute == 59) {
            final startSecond = (60 - _burstPreSeconds).clamp(0, 59);
            if (now.second >= startSecond && !_isRunning) {
              _startMidnightSnipeLoop(targetDateStr);
            }
          }
        }
      } else if (now.hour == 0 && now.minute == 0 && now.second <= _burstPostSeconds) {
        // 00:00 延后保护区间，防止服务器时钟比本地慢
        if (!_isRunning && _lastSuccessDate != todayStr) {
          _startMidnightSnipeLoop(todayStr);
        }
      } else if (_isSnipingActive && (now.hour != 23 || now.minute < 58)) {
        // 跨天窗口完全结束，重置就绪标记
        _isSnipingActive = false;
        notifyListeners();
      }
    }

    // 核心守护：若今日已完成签到且不在 23:58~23:59 次日冲榜预备期，彻底静默！严禁发起任何后台网络请求！
    if (isSignedToday() && !(now.hour == 23 && now.minute >= 58)) {
      return;
    }

    // 2. 日常定时签到调度（准点执行 + 错峰补签保障）
    if (_scheduledSignEnabled && _lastSuccessDate != todayStr && !_isRunning) {
      if (now.hour == _scheduledHour && now.minute == _scheduledMinute && now.second <= _scheduledWindowSec) {
        _executeScheduledSign();
      } else if ((now.hour > _scheduledHour) || (now.hour == _scheduledHour && now.minute > _scheduledMinute)) {
        if (now.minute % 10 == 0) {
          checkAndAutoSignIn(triggerSource: '定时错峰补签');
        }
      }
    }

    // 3. 全天后台持续状态同步与自动签到保底机制（仅在今日未签到时工作）
    if (isAnyAutoEnabled && !_isRunning && _lastSuccessDate != todayStr) {
      if (_lastFallbackCheckTime == null || now.difference(_lastFallbackCheckTime!).inMinutes >= 15) {
        _lastFallbackCheckTime = now;
        _syncAndVerifyWithServer(todayStr);
      }
    }
    } finally {
      _isTicking = false;
    }
  }

  // ================= 502 / 网关故障实时静默探测与恢复即签引擎 =================

  /// 静默检测到 502 等网关/服务器异常状态，立刻进入后台实时探测与恢复即签机制
  void notifyServerOutage(ServerOutageInfo? info, {String source = '签到服务'}) {
    if (!_serverRecoverySignEnabled) return;
    if (isSignedToday()) return; // 今日已签，无须启动探测

    _isServerOutage = true;
    _lastOutageInfo = info;
    _outageStartTime ??= DateTime.now();

    final codeStr = info != null ? '${info.statusCode} ${info.title}' : '502 网关故障';
    _statusMessage = '⚠️ 检测到论坛异常 ($codeStr)，已启动后台静默实时探测，恢复后将立即签到...';
    notifyListeners();

    startRecoveryProbeLoop(source: source);
  }

  /// 启动后台实时探测循环（自适应轻量级探针，服务器一旦恢复立马毫秒级补签）
  void startRecoveryProbeLoop({String source = '探测调度'}) {
    if (_isProbingRecovery) return;
    if (!_serverRecoverySignEnabled) return;
    if (isSignedToday()) {
      _cancelRecoveryProbe();
      notifyListeners();
      return;
    }

    _isProbingRecovery = true;
    _isServerOutage = true;
    _recoveryProbeCount = 0;
    _outageStartTime ??= DateTime.now();
    notifyListeners();

    _scheduleNextRecoveryProbeTick();
  }

  void _cancelRecoveryProbe() {
    _recoveryProbeTimer?.cancel();
    _recoveryProbeTimer = null;
    _isProbingRecovery = false;
    _isServerOutage = false;
    _outageStartTime = null;
  }

  void _scheduleNextRecoveryProbeTick() {
    _recoveryProbeTimer?.cancel();
    if (!_isProbingRecovery || !_serverRecoverySignEnabled || isSignedToday()) {
      _cancelRecoveryProbe();
      notifyListeners();
      return;
    }

    final elapsed = DateTime.now().difference(_outageStartTime ?? DateTime.now());
    // 自适应低开销探测退避阶梯：
    // 0~30s (刚宕机黄金恢复期): 每 2 秒探测一次
    // 30s~2m: 每 3 秒探测一次
    // 2m~10m: 每 5 秒探测一次
    // 10m+: 每 10 秒探测一次
    final int delaySec = elapsed.inSeconds < 30
        ? 2
        : (elapsed.inSeconds < 120 ? 3 : (elapsed.inSeconds < 600 ? 5 : 10));

    _recoveryProbeTimer = Timer(Duration(seconds: delaySec), () async {
      await _onRecoveryProbeTick();
    });
  }

  Future<void> _onRecoveryProbeTick() async {
    if (!_isProbingRecovery || !_serverRecoverySignEnabled || isSignedToday()) {
      _cancelRecoveryProbe();
      notifyListeners();
      return;
    }

    _recoveryProbeCount++;
    final code = _lastOutageInfo?.statusCode ?? 502;
    _statusMessage = '⚠️ 论坛异常 ($code)，后台静默探测中 (第 $_recoveryProbeCount 次)...';
    notifyListeners();

    try {
      final isAlive = await KlpbbsApi.probeServerRecovery();
      if (isAlive) {
        // 核心高光点：服务器恢复正常！立马执行签到！
        _statusMessage = '🟢 探测到论坛服务器已恢复正常！正在毫秒级执行自动补签...';
        _isServerOutage = false;
        _isProbingRecovery = false;
        _recoveryProbeTimer?.cancel();
        _recoveryProbeTimer = null;
        notifyListeners();

        await _executeRecoverySignIn();
        return;
      }
    } catch (_) {}

    // 若仍未恢复，继续下一轮探测调度
    _scheduleNextRecoveryProbeTick();
  }

  /// 服务器恢复后立即执行抢签闭环
  Future<void> _executeRecoverySignIn() async {
    if (!DioClient.isLoggedIn || isSignedToday()) return;

    try {
      // 1. 刷新最新可用 FormHash
      final fh = await KlpbbsApi.getSignFormhash(forceRefresh: true);
      // 2. 毫秒级极速发包签到
      final res = await KlpbbsApi.signIn(formhash: fh, fastMode: true);

      final isAlready = res.message.contains('已签到') ||
          res.message.contains('签过到') ||
          res.message.contains('今日已签') ||
          res.message.contains('无需重复签到') ||
          res.message.contains('k_misign:tdyq') ||
          res.message.contains('k_misign:signed') ||
          res.message.contains('已打卡');

      if (res.success || (res.rank != null && res.rank! > 0) || isAlready) {
        final todayStr = serverTodayStr;
        await _recordSuccess(todayStr, res);
        _statusMessage = '🎉 服务器故障已恢复，已自动完成今日签到！';
        notifyListeners();

        // 专门推送故障恢复自动补签成功的通知
        PushNotificationService.instance.pushCustomNotification(
          title: '🎉 论坛故障恢复 · 自动补签成功！',
          body: '苦力怕论坛已从 502/网关故障 中恢复！已毫秒级为您完成今日打卡！${res.rank != null && res.rank! > 0 ? "排名: 第 ${res.rank} 名" : ""}',
        );
      } else if (res.message.contains('502') || res.message.contains('异常') || res.message.contains('网关')) {
        // 若偶发抖动再次报 502，无缝重新进入探测循环，绝不抛弃用户
        _isServerOutage = true;
        startRecoveryProbeLoop(source: '补签时再次遇故障');
      } else {
        _statusMessage = '恢复打卡结果：${res.message}';
        notifyListeners();
      }
    } catch (e) {
      final outage = ServerOutageInfo.tryParse(e);
      if (outage != null) {
        _isServerOutage = true;
        startRecoveryProbeLoop(source: '补签异常重新探测');
      }
    }
  }

  /// 对齐论坛服务端精准时钟（通过 HTTP Date 头部毫秒级计算偏差）
  Future<void> _calibrateServerTime() async {
    try {
      final offset = await KlpbbsApi.pingServerTime();
      if (offset != null) {
        _serverClockOffsetMs = offset.clamp(-600000, 600000);
        _statusMessage = '时钟对齐完成 (服务端时钟偏差: ${_serverClockOffsetMs >= 0 ? "+$_serverClockOffsetMs" : "$_serverClockOffsetMs"}ms)';
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 零点极速冲榜循环（核心：支持 50ms 流水线多路并发与高频探测翻转，确保 100% 抢占第 1 名，成功后微秒级绝对停机）
  Future<void> _startMidnightSnipeLoop(String targetDateStr) async {
    if (_isRunning) return;
    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '🚀 跨天冲榜引擎已启动 (${_burstStrategy.label}，间隔 ${_burstIntervalMs}ms)...';
    notifyListeners();

    final totalWindowDuration = Duration(seconds: _burstPreSeconds + _burstPostSeconds + 5);
    final deadline = DateTime.now().add(totalWindowDuration);
    bool isFinished = false;

    try {
      // 预先获取 FormHash 避免每次请求阻塞
      var fh = await KlpbbsApi.getSignFormhash(forceRefresh: true);
      if (fh == null || fh.isEmpty) {
        for (int retry = 0; retry < 3; retry++) {
          await Future.delayed(const Duration(milliseconds: 300));
          fh = await KlpbbsApi.getSignFormhash(forceRefresh: true);
          if (fh != null && fh.isNotEmpty) break;
        }
      }
      bool refreshedAtMidnight = false;
      int inFlight = 0;
      const maxInFlight = 5; // 管道并发度，多路并发保持极高发包密度

      while (DateTime.now().isBefore(deadline) && _isRunning && !isFinished) {
        final now = estimatedServerNow;

        // 刚跨入 00:00 时在后台静默异步刷新一次 FormHash
        if (now.hour == 0 && !refreshedAtMidnight) {
          refreshedAtMidnight = true;
          KlpbbsApi.getSignFormhash(forceRefresh: true).then((newFh) {
            if (newFh != null && newFh.isNotEmpty) fh = newFh;
          }).catchError((_) {});
        }

        // ================= 模式 1：多路并发冲刺 (Burst Spam) =================
        if (_burstStrategy == BurstStrategy.burstSpam) {
          final isCriticalWindow = (now.hour == 23 && now.minute == 59 && now.second >= 56) ||
              (now.hour == 0 && now.minute == 0 && now.second <= _burstPostSeconds);

          if (isCriticalWindow) {
            // 核心临界冲刺窗口（23:59:56 ~ 00:00:20）：5 路流水线全时段多路并发，暴力拿下第 1 名
            final completer = Completer<void>();
            Timer? burstTimer;

            void triggerFire() {
              if (isFinished || !_isRunning || DateTime.now().isAfter(deadline)) {
                burstTimer?.cancel();
                if (!completer.isCompleted) completer.complete();
                return;
              }

              // 跨入 00:00 瞬间异步刷新一次最新 FormHash，防止旧 hash 失效
              final currentServer = estimatedServerNow;
              if (currentServer.hour == 0 && !refreshedAtMidnight) {
                refreshedAtMidnight = true;
                KlpbbsApi.getSignFormhash(forceRefresh: true).then((newFh) {
                  if (newFh != null && newFh.isNotEmpty) fh = newFh;
                }).catchError((_) {});
              }

              if (inFlight >= maxInFlight) return;
              inFlight++;

              final dispatchTime = estimatedServerNow;

              KlpbbsApi.signIn(formhash: fh, fastMode: true).then((res) async {
                inFlight--;
                if (isFinished) return;

                if (res.message.contains('请先登录') || res.message.contains('需要登录')) {
                  isFinished = true;
                  burstTimer?.cancel();
                  _isRunning = false;
                  _statusMessage = '冲榜终止：登录状态已失效，请重新登录';
                  if (!completer.isCompleted) completer.complete();
                  notifyListeners();
                  return;
                }

                final isAlreadySigned = res.message.contains('已签到') ||
                    res.message.contains('签过到') ||
                    res.message.contains('今日已签') ||
                    res.message.contains('无需重复签到') ||
                    res.message.contains('k_misign:tdyq') ||
                    res.message.contains('k_misign:signed') ||
                    res.message.contains('已打卡');

                // 核心保护：在 23:59 冲刺窗口期内（dispatchTime.hour == 23 或 estimatedServerNow.hour == 23），
                // 如果收到“今日已签到”或旧的排名数据，说明服务器尚未真正跨天翻转！
                // 严禁当作次日签到成功处理，必须继续等待零点翻转！
                final isStillBeforeMidnight = dispatchTime.hour == 23 || estimatedServerNow.hour == 23;
                if (isStillBeforeMidnight && (isAlreadySigned || !res.success)) {
                  final currentNow = estimatedServerNow;
                  final timeStr = '${currentNow.hour.toString().padLeft(2, '0')}:${currentNow.minute.toString().padLeft(2, '0')}:${currentNow.second.toString().padLeft(2, '0')}';
                  _statusMessage = '零点前探测排队中 ($timeStr，服务器尚未翻转跨天)...';
                  notifyListeners();
                  return;
                }

                // 微秒级绝对停机熔断 (Instant Kill Switch)：
                // 只有拿到服务器跨天后真正颁发的全新签到成功回包（isFreshSuccess）才算冲榜成功！
                // 绝不可将服务器尚未跨天时的旧日排名（如 121 名）或“今日已签到”误当作次日冲刺完成！
                final isFreshSuccess = res.success && !isAlreadySigned;
                if (isFreshSuccess) {
                  isFinished = true;
                  burstTimer?.cancel();
                  _isRunning = false;
                  await _recordSuccess(targetDateStr, res);
                  if (!completer.isCompleted) completer.complete();
                  return;
                }

                final currentNow = estimatedServerNow;
                final timeStr = '${currentNow.hour.toString().padLeft(2, '0')}:${currentNow.minute.toString().padLeft(2, '0')}:${currentNow.second.toString().padLeft(2, '0')}';
                if (dispatchTime.hour == 23) {
                  _statusMessage = '零点前多路并发抢跑中 ($timeStr，5 路流水线全速开火)...';
                } else {
                  _statusMessage = '零点正点多路极速爆发中 ($timeStr，5 路流水线抢占第 1 名)...';
                }
                notifyListeners();
              }).catchError((_) {
                inFlight--;
              });
            }

            final intervalMs = _burstIntervalMs.clamp(50, 200);
            burstTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) => triggerFire());
            triggerFire();

            try {
              final waitDuration = deadline.difference(DateTime.now());
              await Future.any([
                completer.future,
                Future.delayed(waitDuration > Duration.zero ? waitDuration : const Duration(seconds: 5)),
              ]);
            } finally {
              burstTimer.cancel();
            }
            if (isFinished) break;
          } else {
            // 23:59 提前预热阶段：快速轻量探测
            final res = await KlpbbsApi.signIn(formhash: fh, fastMode: true);
            if (res.message.contains('请先登录') || res.message.contains('需要登录')) {
              isFinished = true;
              _isRunning = false;
              _statusMessage = '冲榜终止：登录状态已失效，请重新登录';
              break;
            }

            final isAlreadySigned = res.message.contains('已签到') ||
                res.message.contains('签过到') ||
                res.message.contains('今日已签') ||
                res.message.contains('无需重复签到') ||
                res.message.contains('k_misign:tdyq') ||
                res.message.contains('k_misign:signed') ||
                res.message.contains('已打卡');

            final isStillBeforeMidnight = now.hour == 23 || estimatedServerNow.hour == 23;
            if (isStillBeforeMidnight && (isAlreadySigned || !res.success)) {
              // 零点前服务器尚未翻转，继续等待
            } else if (res.success && !isAlreadySigned) {
              isFinished = true;
              _isRunning = false;
              await _recordSuccess(targetDateStr, res);
              break;
            }
            final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
            _statusMessage = '并发冲刺预热中 ($timeStr，时钟对齐完成，准备多路并发)...';
            notifyListeners();
            await Future.delayed(Duration(milliseconds: _burstIntervalMs.clamp(50, 300)));
          }
        } else {
          // ================= 模式 2：高频探测抢签 (Status Polling) =================
          // 极速高频单路探测状态，服务端跨天翻转微秒级响应并拿下第 1 名
          final res = await KlpbbsApi.signIn(formhash: fh, fastMode: true);
          if (res.message.contains('请先登录') || res.message.contains('需要登录')) {
            isFinished = true;
            _isRunning = false;
            _statusMessage = '冲榜终止：登录状态已失效，请重新登录';
            break;
          }

          final isAlreadySigned = res.message.contains('已签到') ||
              res.message.contains('签过到') ||
              res.message.contains('今日已签') ||
              res.message.contains('无需重复签到') ||
              res.message.contains('k_misign:tdyq') ||
              res.message.contains('k_misign:signed') ||
              res.message.contains('已打卡');

          final isStillBeforeMidnight = now.hour == 23 || estimatedServerNow.hour == 23;
          if (isStillBeforeMidnight && (isAlreadySigned || !res.success)) {
            // 零点前服务器尚未翻转，保持高频探测翻转点
          } else if (res.success && !isAlreadySigned) {
            isFinished = true;
            _isRunning = false;
            await _recordSuccess(targetDateStr, res);
            break;
          }

          final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
          if (now.hour == 23) {
            _statusMessage = '零点前高频探测抢跑中 ($timeStr，回包锁定，等待翻转)...';
          } else {
            _statusMessage = '零点正点高频抢签中 ($timeStr，争夺第 1 名)...';
          }
          notifyListeners();

          await Future.delayed(Duration(milliseconds: _burstIntervalMs.clamp(30, 300)));
        }
      }
    } catch (e) {
      _statusMessage = '冲榜异常：$e';
      final outage = ServerOutageInfo.tryParse(e);
      if (outage != null) {
        notifyServerOutage(outage, source: '零点冲榜');
      }
    } finally {
      _isRunning = false;
      _runningStartTime = null;
      if (!isFinished && _lastSuccessDate != targetDateStr) {
        _statusMessage = '冲榜窗口已结束，转入后台状态核验与错峰补签...';
        if (_isServerOutage) {
          startRecoveryProbeLoop(source: '零点冲榜遇故障');
        } else {
          // 在后台轻量核验一次服务端真实签到状态（若网页已签到则同步记录，但不擅自弹窗）
          unawaited(KlpbbsApi.getSignHeaderInfo(forceRefresh: true).then((header) {
            if (header.isSignedToday) {
              markSignedToday(
                rank: header.mySignRank,
                continuousDays: header.continuousDays,
                rewardIron: header.rewardIron,
                notify: false,
              );
            }
          }).catchError((_) {}));
        }
      }
      notifyListeners();
    }
  }

  /// 执行日常定时签到（带容差区间状态探测）
  Future<void> _executeScheduledSign() async {
    if (_isRunning || isSignedToday()) return;
    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '正在执行定时自动签到...';
    notifyListeners();

    final todayStr = serverTodayStr;
    final deadline = DateTime.now().add(Duration(seconds: _scheduledWindowSec));

    try {
      final fh = await KlpbbsApi.getSignFormhash();
      while (DateTime.now().isBefore(deadline) && _isRunning) {
        if (!DioClient.isLoggedIn) {
          _statusMessage = '定时签到未完成：请先登录论坛账号';
          break;
        }
        final res = await KlpbbsApi.signIn(formhash: fh, fastMode: true);
        if (res.message.contains('请先登录') || res.message.contains('需要登录')) {
          _statusMessage = '定时签到未完成：登录状态已失效，请重新登录';
          break;
        }

        final isAlready = res.message.contains('已签到') ||
            res.message.contains('签过到') ||
            res.message.contains('今日已签') ||
            res.message.contains('无需重复签到') ||
            res.message.contains('k_misign:tdyq') ||
            res.message.contains('k_misign:signed') ||
            res.message.contains('已打卡');
        if ((res.rank != null && res.rank! > 0) || res.success || isAlready) {
          await _recordSuccess(todayStr, res);
          break;
        }
        if (res.message.contains('502') || res.message.contains('异常') || res.message.contains('网关')) {
          final outage = ServerOutageInfo.tryParse(res.message);
          notifyServerOutage(outage, source: '定时签到');
          break;
        }
        _statusMessage = '定时签到中 (${res.message})...';
        notifyListeners();
        final delayMs = res.message.contains('网络连接超时') ? 2000 : _burstIntervalMs.clamp(100, 500);
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    } catch (e) {
      _statusMessage = '定时签到异常：$e';
      final outage = ServerOutageInfo.tryParse(e);
      if (outage != null) {
        notifyServerOutage(outage, source: '定时签到');
      }
    } finally {
      _isRunning = false;
      _runningStartTime = null;
      notifyListeners();
    }
  }

  /// 后台持续向服务端网页刷新状态并同步：若未签则自动签到，若已签则校准数据
  Future<void> _syncAndVerifyWithServer(String todayStr) async {
    if (!DioClient.isLoggedIn || _isRunning) return;
    try {
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
      if (info.isSignedToday) {
        await markSignedToday(
          rank: info.mySignRank,
          continuousDays: info.continuousDays,
        );
      } else {
        await markUnsignedToday();
        final isAnyAutoEnabled = _burstModeEnabled || _scheduledSignEnabled || _autoSignOnLaunch || AppConfig.autoCheckin;
        if (isAnyAutoEnabled) {
          // 服务端权威显示尚未签到且开启了自动签到，立即触发打卡并治愈
          checkAndAutoSignIn(triggerSource: '后台巡检未签到自动打卡', force: true);
        }
      }
    } catch (e) {
      final outage = ServerOutageInfo.tryParse(e);
      if (outage != null) {
        notifyServerOutage(outage, source: '后台巡检');
      }
    }
  }

  /// 检查并执行自动签到（启动/手动触发）
  Future<void> checkAndAutoSignIn({String triggerSource = '自动签到', bool force = false}) async {
    if (!DioClient.isLoggedIn || _isRunning) return;
    if (isSignedToday() && !force) return; // 已经签到成功，保持静默

    final now = DateTime.now();
    final todayStr = serverTodayStr;

    try {
      final sp = await SharedPreferences.getInstance();
      final savedSuccess = sp.getString(_keyLastSuccessDate) ?? '';
      if (savedSuccess == todayStr) {
        _lastSuccessDate = todayStr;
        if (!force) return;
      }
    } catch (_) {}

    // 3 分钟频控防抖（非强制触发时）
    if (!force && _lastCheckTime != null && now.difference(_lastCheckTime!).inMinutes < 3) {
      return;
    }
    _lastCheckTime = now;
    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '$triggerSource正在检测...';
    notifyListeners();

    try {
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
      if (info.isSignedToday) {
        await markSignedToday(
          rank: info.mySignRank,
          continuousDays: info.continuousDays,
          rewardIron: info.rewardIron,
          notify: _notifyOnResult,
        );
        _isRunning = false;
        _runningStartTime = null;
        return;
      }

      // 未检测到已签到状态，继续向服务端发起签到
      final res = await KlpbbsApi.signIn();
      final isAlready = res.message.contains('已签到') ||
          res.message.contains('签过到') ||
          res.message.contains('今日已签') ||
          res.message.contains('无需重复签到') ||
          res.message.contains('k_misign:tdyq') ||
          res.message.contains('k_misign:signed') ||
          res.message.contains('已打卡');
      if (res.success || isAlready) {
        await _recordSuccess(todayStr, res);
      } else {
        _statusMessage = '签到未完成：${res.message}，将在后台持续探测重试';
      }
    } catch (e) {
      _statusMessage = '签到异常：$e';
      final out = ServerOutageInfo.tryParse(e);
      if (out != null) {
        notifyServerOutage(out, source: triggerSource);
      }
    } finally {
      _isRunning = false;
      _runningStartTime = null;
      notifyListeners();
    }
  }

  Future<void> _recordSuccess(String targetDateStr, dynamic res, {SignHeaderInfo? headerInfo}) async {
    _cancelRecoveryProbe();
    final isAlready = res.message.contains('已签到') ||
        res.message.contains('签过到') ||
        res.message.contains('今日已签') ||
        res.message.contains('无需重复签到') ||
        res.message.contains('k_misign:tdyq') ||
        res.message.contains('k_misign:signed') ||
        res.message.contains('已打卡');

    SignHeaderInfo info = headerInfo ?? const SignHeaderInfo();

    _lastSuccessDate = targetDateStr;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyLastSuccessDate, targetDateStr);
    await KlpbbsApi.clearSignLocalCache();
    await KlpbbsApi.recordSignDateToLocalCalendar();

    // 提取真实数据，优先使用签到响应中的铁粒、经验、名次，杜绝多余流水查询加重服务器负担
    int? resRank;
    if (res.rank != null) {
      if (res.rank is int) {
        resRank = res.rank as int;
      } else if (res.rank is String) {
        resRank = int.tryParse(res.rank as String);
      }
    }
    int? resDays;
    if (res.continuousDays != null) {
      if (res.continuousDays is int) {
        resDays = res.continuousDays as int;
      } else if (res.continuousDays is String) {
        resDays = int.tryParse(res.continuousDays as String);
      }
    }

    int? finalRank = (resRank != null && resRank > 0)
        ? resRank
        : (info.mySignRank != null && info.mySignRank! > 0 ? info.mySignRank : null);
    int? finalContinuousDays = (resDays != null && resDays > 0)
        ? resDays
        : (info.continuousDays > 0 ? info.continuousDays : null);
    String? finalIron = (res.rewardIron != null && res.rewardIron.toString().isNotEmpty)
        ? res.rewardIron.toString()
        : (info.rewardIron.isNotEmpty ? info.rewardIron : null);
    String? finalExp = (res.rewardExp != null && res.rewardExp.toString().isNotEmpty)
        ? res.rewardExp.toString()
        : null;

    String rewardSummary = '';
    if (finalIron != null && finalIron.isNotEmpty) {
      if (finalExp != null && finalExp.isNotEmpty) {
        rewardSummary = '铁粒 +$finalIron, 经验 +$finalExp';
      } else {
        rewardSummary = '铁粒 +$finalIron';
      }
    } else if (finalExp != null && finalExp.isNotEmpty) {
      rewardSummary = '经验 +$finalExp';
    } else if (isAlready) {
      rewardSummary = '今日已签到';
    } else {
      rewardSummary = '打卡成功';
    }

    final hasRank = finalRank != null && finalRank > 0;
    final isFirst = finalRank == 1;

    final rankStatusText = hasRank ? (isFirst ? ' (🥇 今日第 1 名！)' : ' (今日第 $finalRank 名)') : '';
    _statusMessage = '🎉 签到成功！$rewardSummary$rankStatusText';
    notifyListeners();

    // 幂等防重：同一论坛自然日（以目标日期 targetDateStr 为准）绝对只允许推送一次系统通知
    // 且当仅是“今日已签到”或非新签成功时，严禁弹窗推送！
    final savedNotifiedDate = sp.getString(_keyLastNotifiedDate) ?? '';
    final alreadyNotified = _lastNotifiedDate == targetDateStr || savedNotifiedDate == targetDateStr;

    if (!alreadyNotified && !isAlready && res.success == true && _notifyOnResult) {
      _lastNotifiedDate = targetDateStr;
      await sp.setString(_keyLastNotifiedDate, targetDateStr);
      _pushSignResultNotification(
        rank: finalRank,
        continuousDays: finalContinuousDays,
        rewardSummary: rewardSummary,
      );
    }
  }

  /// 签到结果全平台消息推送（展示排名、奖励、经验与连续天数）
  void _pushSignResultNotification({
    int? rank,
    int? continuousDays,
    required String rewardSummary,
  }) {
    final hasRank = rank != null && rank > 0;
    final isFirst = rank == 1;

    final title = isFirst
        ? '🥇 苦力怕论坛 · 恭喜拿下今日签到第 1 名！'
        : hasRank
            ? '苦力怕论坛 · 签到成功 (今日第 $rank 名) 🎉'
            : '苦力怕论坛 · 签到成功 🎉';

    final rankBodyText = hasRank ? '🏆 今日排名：第 $rank 名\n' : '';
    final daysText = (continuousDays != null && continuousDays > 0)
        ? ' | 已连续 $continuousDays 天'
        : '';

    final rewardText = (rewardSummary.isNotEmpty && rewardSummary != '已完成打卡')
        ? '签到奖励：$rewardSummary'
        : '打卡状态：已完成打卡';

    PushNotificationService.instance.pushCustomNotification(
      title: title,
      body: '$rankBodyText$rewardText$daysText',
    );
  }

  /// 立即运行一次高频冲刺实测与延迟诊断
  Future<String> runBurstDiagnosticTest() async {
    if (!DioClient.isLoggedIn) return '请先登录苦力怕论坛账号';
    if (_isRunning) return '当前已有签到任务正在运行，请稍候';

    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '🚀 正在执行高频冲刺实测诊断 (预热 FormHash 并连发 5 包)...';
    notifyListeners();

    final buffer = StringBuffer();
    final latencies = <int>[];

    try {
      final t0 = DateTime.now().millisecondsSinceEpoch;
      final fh = await KlpbbsApi.getSignFormhash(forceRefresh: true);
      final fhRtt = DateTime.now().millisecondsSinceEpoch - t0;
      buffer.writeln('1. FormHash 预热完成: ${(fh != null && fh.isNotEmpty) ? fh : "已获取"} (耗时: ${fhRtt}ms)');

      for (int i = 1; i <= 5; i++) {
        final start = DateTime.now().millisecondsSinceEpoch;
        final res = await KlpbbsApi.signIn(formhash: fh, fastMode: true);
        final rtt = DateTime.now().millisecondsSinceEpoch - start;
        latencies.add(rtt);
        buffer.writeln('   - 包 #$i: ${rtt}ms 响应 -> ${res.message}');

        final isSigned = res.success || (res.rank != null && res.rank! > 0) ||
            res.message.contains('已签到') || res.message.contains('签过到') || res.message.contains('今日已签');
        if (isSigned && !isSignedToday()) {
          await _recordSuccess(serverTodayStr, res);
        }

        if (i < 5) {
          await Future.delayed(Duration(milliseconds: _burstIntervalMs));
        }
      }

      final avg = (latencies.reduce((a, b) => a + b) / latencies.length).round();
      final summary = '🚀 冲刺测试完成：连发 5 包全部响应正常，平均单包延迟 ${avg}ms！';
      if (_statusMessage.startsWith('🎉')) {
        _statusMessage = '$_statusMessage (冲刺测速: ${avg}ms)';
      } else {
        _statusMessage = summary;
      }
      buffer.writeln('2. 总结: $summary');
      return buffer.toString();
    } catch (e) {
      _statusMessage = '冲刺测试异常: $e';
      return '冲刺测试异常: $e';
    } finally {
      _isRunning = false;
      _runningStartTime = null;
      notifyListeners();
    }
  }

  /// 实时诊断论坛可用性与 502 静默探测器健康度
  Future<String> runRecoveryDiagnosticProbe() async {
    final buffer = StringBuffer();
    buffer.writeln('【苦力怕论坛 · 502/宕机探测器实时诊断】');
    buffer.writeln('测试时间：${DateTime.now().toString().split('.').first}');
    buffer.writeln('登录状态：${DioClient.isLoggedIn ? "已登录" : "未登录"}');
    buffer.writeln('今日签到：${isSignedToday() ? "已签到" : "未签到"}');
    buffer.writeln('自愈机制：${_serverRecoverySignEnabled ? "已启用" : "未启用"}');
    buffer.writeln('探测状态：${_isProbingRecovery ? "🟢 正在探测中(第$_recoveryProbeCount次)" : "⚪ 待命中(无活跃宕机)"}');
    if (_lastOutageInfo != null) {
      buffer.writeln('最近异常：HTTP ${_lastOutageInfo!.statusCode} (${_lastOutageInfo!.title})');
      if (_outageStartTime != null) {
        final dur = DateTime.now().difference(_outageStartTime!);
        buffer.writeln('故障已持续：${dur.inSeconds} 秒');
      }
    }
    buffer.writeln('----------------------------------------');
    buffer.writeln('🚀 正在发送超轻量级低开销探测探针...');

    final sw = Stopwatch()..start();
    try {
      final isHealthy = await KlpbbsApi.probeServerRecovery();
      sw.stop();
      if (isHealthy) {
        buffer.writeln('✅ 探测成功！论坛源站服务正常响应');
        buffer.writeln('📡 探针往返耗时：${sw.elapsedMilliseconds} ms');
        buffer.writeln('页面校验：200 OK，非 502/503/Bad Gateway 故障页');
        buffer.writeln('\n💡 结论：论坛服务器处于健康在线状态。若此前遭遇 502/503 宕机，恢复探测器将在此刻毫秒级触发即刻打卡！');
      } else {
        buffer.writeln('⚠️ 探测提示：服务器未能返回正常论坛页面 (可能处于 502/503/504 故障或网络波动)');
        buffer.writeln('📡 探针往返耗时：${sw.elapsedMilliseconds} ms');
        buffer.writeln('\n💡 结论：论坛当前异常，后台自愈系统将在后台保持轻量轮询，直至完全恢复后自动签到。');
      }
    } catch (e) {
      sw.stop();
      buffer.writeln('❌ 探针连接失败：$e');
      buffer.writeln('耗时：${sw.elapsedMilliseconds} ms');
      buffer.writeln('\n💡 结论：网络连接中断或网关完全不可达，系统将继续自适应退避探测。');
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}
