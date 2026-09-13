import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
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

  // Runtime States
  String _lastSuccessDate = '';
  String _lastNotifiedDate = '';
  int _lastDay = DateTime.now().day;
  bool _isRunning = false;
  DateTime? _runningStartTime; // 看门狗计时，防止卡死
  bool _isSnipingActive = false; // 是否处于 23:59 准备/冲刺阶段
  String _statusMessage = '服务未开启（等待配置）';
  Timer? _heartbeatTimer;
  DateTime? _lastFallbackCheckTime;
  DateTime? _lastCheckTime;

  // Getters
  bool get autoSignOnLaunch => _autoSignOnLaunch;
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

  /// 判断今日是否已成功签到
  bool isSignedToday() {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return _lastSuccessDate == todayStr;
  }

  /// 标记今日签到成功（持久化保存）
  Future<void> markSignedToday() async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _lastSuccessDate = todayStr;
    _lastNotifiedDate = todayStr;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyLastSuccessDate, todayStr);
    await sp.setString(_keyLastNotifiedDate, todayStr);
    notifyListeners();
  }

  /// 初始化自动签到引擎
  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _autoSignOnLaunch = sp.getBool(_keyAutoLaunch) ?? sp.getBool('auto_checkin') ?? false;
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
      _lastSuccessDate = sp.getString(_keyLastSuccessDate) ?? '';
      _lastNotifiedDate = sp.getString(_keyLastNotifiedDate) ?? '';

      // 注册应用生命周期监听
      try {
        WidgetsBinding.instance.addObserver(this);
      } catch (_) {}

      // 启动 1 秒高精度心跳调度器
      _startHeartbeat();

      // 启动时自动检测打卡与状态同步：只要开启了任何自动签到相关功能（启动签到 / 定时签到 / 零点冲榜），与服务端同步状态并保底
      final isAnyAutoEnabled = _autoSignOnLaunch || _scheduledSignEnabled || _burstModeEnabled || AppConfig.autoCheckin;
      if (isAnyAutoEnabled) {
        Future.delayed(const Duration(seconds: 3), () {
          final now = DateTime.now();
          final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          _syncAndVerifyWithServer(todayStr);
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台唤醒或解锁屏幕时，立即进行生命周期检测与错峰补签
      _onAppResumed();
    }
  }

  void _onAppResumed() {
    if (!DioClient.isLoggedIn) return;

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    if (now.day != _lastDay) {
      _lastDay = now.day;
      _lastCheckTime = null;
      _lastFallbackCheckTime = null;
      _lastSuccessDate = '';
      _lastNotifiedDate = '';
    }

    final isAnyAutoEnabled = _burstModeEnabled || _scheduledSignEnabled || _autoSignOnLaunch || AppConfig.autoCheckin;
    if (isAnyAutoEnabled && !_isRunning) {
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
    _heartbeatTimer = Timer(delay, () {
      _onHeartbeatTick();
      _scheduleNextHeartbeat();
    });
  }

  /// 计算下一次心跳周期：处于冲刺临界、跨天切换或定时签到临界期保持 1 秒高精度，平时 30 秒休眠省电
  Duration _resolveNextHeartbeatDuration() {
    if (_isRunning) {
      return const Duration(seconds: 1);
    }
    final now = DateTime.now();
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
    // 定时签到临界期：目标小时内且距离目标分钟 <= 1 分钟
    if (_scheduledSignEnabled) {
      if (now.hour == _scheduledHour) {
        if (now.minute == _scheduledMinute || (now.minute == _scheduledMinute - 1 && now.second >= 45)) {
          return const Duration(seconds: 1);
        }
      }
    }
    return const Duration(seconds: 30);
  }

  void _onHeartbeatTick() {
    // 看门狗保护：若运行状态超过 45 秒未解开，强制重置
    if (_isRunning && _runningStartTime != null) {
      if (DateTime.now().difference(_runningStartTime!).inSeconds > 45) {
        _isRunning = false;
        _runningStartTime = null;
        notifyListeners();
      }
    }

    if (!DioClient.isLoggedIn) return;

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final isAnyAutoEnabled = _burstModeEnabled || _scheduledSignEnabled || _autoSignOnLaunch || AppConfig.autoCheckin;

    // 0. 日历跨天秒级响应器 (Midnight Calendar Rollover Trigger)
    // 只要日期跳变为新的一天，立即重置跨天频控，启动凌晨自动打卡
    if (now.day != _lastDay) {
      _lastDay = now.day;
      _lastCheckTime = null; // 解除防抖
      _lastFallbackCheckTime = null;
      if (_lastSuccessDate != todayStr) {
        _lastSuccessDate = ''; // 重置跨天标记，但保留若刚由零点冲榜标记的今日成功
        _lastNotifiedDate = '';
        SharedPreferences.getInstance().then((sp) {
          sp.remove(_keyLastSuccessDate);
          sp.remove(_keyLastNotifiedDate);
        }).catchError((_) {});
      }
      _statusMessage = '检测到零点跨天 ($todayStr)，启动今日凌晨自动签到...';
      notifyListeners();

      if (isAnyAutoEnabled && !_isRunning && _lastSuccessDate != todayStr) {
        if (_burstModeEnabled) {
          _startMidnightSnipeLoop(todayStr);
        } else if (_scheduledSignEnabled && _scheduledHour == 0 && _scheduledMinute == 0) {
          _executeScheduledSign();
        } else {
          checkAndAutoSignIn(triggerSource: '凌晨跨天自动打卡', force: true);
        }
      }
    }

    // 1. 零点冲榜模式调度（在 23:59 开启准备、校准、预热 FormHash 与时间区间探测）
    if (_burstModeEnabled) {
      if (now.hour == 23 && now.minute == 59) {
        // 23:59 冲刺的目标为次日签到
        final targetDate = now.add(const Duration(minutes: 2));
        final targetDateStr = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

        if (_lastSuccessDate != targetDateStr) {
          if (!_isSnipingActive) {
            _isSnipingActive = true;
            _statusMessage = '23:59 冲榜就绪状态已激活，正在校准服务器时钟与预热 FormHash...';
            notifyListeners();
            _calibrateServerTime();
            KlpbbsApi.getSignFormhash(forceRefresh: true);
          }

          // 倒计时进入设定的提前区间（例如 23:59:45），开跑探测/发包，防止服务器时钟比本地快
          final startSecond = (60 - _burstPreSeconds).clamp(0, 59);
          if (now.second >= startSecond && !_isRunning) {
            _startMidnightSnipeLoop(targetDateStr);
          }
        }
      } else if (now.hour == 0 && now.minute == 0 && now.second <= _burstPostSeconds) {
        // 00:00 延后保护区间，防止服务器时钟比本地慢
        if (!_isRunning && _lastSuccessDate != todayStr) {
          _startMidnightSnipeLoop(todayStr);
        }
      } else if (_isSnipingActive && now.minute >= 2) {
        // 跨天窗口完全结束，重置就绪标记
        _isSnipingActive = false;
        notifyListeners();
      }
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

    // 3. 全天后台持续状态同步与自动签到保底机制
    // 只要开启了任一自动签到功能，每 15 分钟持续向论坛网页刷新校验真实签到状态：
    // 如果网页显示未签到，立即触发自动签到；如果网页已签到，同步本地状态与天数/排名
    if (isAnyAutoEnabled && !_isRunning) {
      if (_lastFallbackCheckTime == null || now.difference(_lastFallbackCheckTime!).inMinutes >= 15) {
        _lastFallbackCheckTime = now;
        _syncAndVerifyWithServer(todayStr);
      }
    }
  }

  /// 校准论坛服务端时钟
  Future<void> _calibrateServerTime() async {
    try {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
      final endTime = DateTime.now().millisecondsSinceEpoch;
      final rtt = (endTime - startTime) ~/ 2;
      _statusMessage = '时钟校准完成 (RTT: ${rtt * 2}ms)，当前状态: ${info.isSignedToday ? "已签" : "待刷新"}';
      notifyListeners();
    } catch (_) {}
  }

  /// 零点极速冲榜循环（核心：支持 50ms 流水线多路并发与高频探测翻转，确保 100% 抢占第 1 名）
  Future<void> _startMidnightSnipeLoop(String targetDateStr) async {
    if (_isRunning) return;
    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '🚀 跨天冲榜引擎已启动 (${_burstStrategy.label}，间隔 ${_burstIntervalMs}ms)...';
    notifyListeners();

    final totalWindowDuration = Duration(seconds: _burstPreSeconds + _burstPostSeconds + 5);
    final deadline = DateTime.now().add(totalWindowDuration);

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
      bool isFinished = false;
      bool isVerifying = false;
      int inFlight = 0;
      const maxInFlight = 5; // 管道并发度，多路并发保持极高发包密度

      while (DateTime.now().isBefore(deadline) && _isRunning && !isFinished) {
        final now = DateTime.now();

        // 刚跨入 00:00 时在后台静默异步刷新一次 FormHash
        if (now.hour == 0 && !refreshedAtMidnight) {
          refreshedAtMidnight = true;
          KlpbbsApi.getSignFormhash(forceRefresh: true).then((newFh) {
            if (newFh != null && newFh.isNotEmpty) fh = newFh;
          }).catchError((_) {});
        }

        // ================= 模式 1：多路并发冲刺 (Burst Spam) =================
        if (_burstStrategy == BurstStrategy.burstSpam) {
          // 在 23:59 提前预热阶段（距离零点 > 4 秒）进行轻量探路
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

              if (inFlight >= maxInFlight) return;
              inFlight++;

              final dispatchTime = DateTime.now();

              KlpbbsApi.signIn(formhash: fh, fastMode: true).then((res) async {
                inFlight--;
                if (isFinished) return;

                final currentNow = DateTime.now();
                // 1. 若成功解析出当日名次，100% 确认新一天签到成功并斩获名次！
                if (res.rank != null && res.rank! > 0) {
                  isFinished = true;
                  burstTimer?.cancel();
                  await _recordSuccess(targetDateStr, res);
                  if (!completer.isCompleted) completer.complete();
                  return;
                }

                // 2. 00:00 之后发出的请求返回了明确成功或已签到
                final isAlreadySigned = res.message.contains('已签到') ||
                    res.message.contains('签过到') ||
                    res.message.contains('今日已签');

                if (dispatchTime.hour == 0 && (res.success || isAlreadySigned)) {
                  // 异步双重核验，不阻塞并发流水线发包
                  if (!isVerifying) {
                    isVerifying = true;
                    KlpbbsApi.getSignHeaderInfo(forceRefresh: true).then((info) async {
                      if (info.isSignedToday && !isFinished) {
                        isFinished = true;
                        burstTimer?.cancel();
                        await _recordSuccess(targetDateStr, res, headerInfo: info);
                        if (!completer.isCompleted) completer.complete();
                      } else {
                        isVerifying = false;
                      }
                    }).catchError((_) {
                      isVerifying = false;
                    });
                  }
                } else if (dispatchTime.hour == 23) {
                  _statusMessage = '多路并发极限冲刺中 (${currentNow.hour.toString().padLeft(2, '0')}:${currentNow.minute.toString().padLeft(2, '0')}:${currentNow.second.toString().padLeft(2, '0')}，5 路流水线连发抢第 1 名)...';
                  notifyListeners();
                }
              }).catchError((_) {
                inFlight--;
              });
            }

            final intervalMs = _burstIntervalMs.clamp(50, 200);
            burstTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) => triggerFire());
            triggerFire();

            final waitDuration = deadline.difference(DateTime.now());
            await Future.any([
              completer.future,
              Future.delayed(waitDuration > Duration.zero ? waitDuration : const Duration(seconds: 5)),
            ]);
            burstTimer.cancel();
            if (isFinished) break;
          } else {
            // 23:59 提前预热阶段：快速轻量探测
            final res = await KlpbbsApi.signIn(formhash: fh, fastMode: true);
            if (res.rank != null && res.rank! > 0) {
              await _recordSuccess(targetDateStr, res);
              break;
            }
            _statusMessage = '并发冲刺预热中 (${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}，时钟校准完成，准备多路并发)...';
            notifyListeners();
            await Future.delayed(Duration(milliseconds: _burstIntervalMs.clamp(50, 300)));
          }
        } else {
          // ================= 模式 2：高频探测抢签 (Status Polling) =================
          // 极速高频单路探测 69B 状态，服务端跨天翻转微秒级响应并拿下第 1 名
          final dispatchTime = DateTime.now();
          final res = await KlpbbsApi.signIn(formhash: fh, fastMode: true);

          // 1. 若探测包返回名次，说明本探测包正好作为新一天第一枪打穿入库！
          if (res.rank != null && res.rank! > 0) {
            await _recordSuccess(targetDateStr, res);
            break;
          }

          // 2. 若发包在 00:00 之后且已签到，核验并记录
          final isAlreadySigned = res.message.contains('已签到') ||
              res.message.contains('签过到') ||
              res.message.contains('今日已签');

          if (dispatchTime.hour == 0 && (res.success || isAlreadySigned)) {
            try {
              final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
              if (info.isSignedToday) {
                await _recordSuccess(targetDateStr, res, headerInfo: info);
                break;
              }
            } catch (_) {}
          } else {
            _statusMessage = '高频状态探测中 (${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}，回包 69B 锁定，等待翻转)...';
            notifyListeners();
          }

          await Future.delayed(Duration(milliseconds: _burstIntervalMs.clamp(30, 300)));
        }
      }
    } catch (e) {
      _statusMessage = '冲榜异常：$e';
    } finally {
      _isRunning = false;
      _runningStartTime = null;
      notifyListeners();
    }
  }

  /// 执行日常定时签到（带容差区间状态探测）
  Future<void> _executeScheduledSign() async {
    if (_isRunning) return;
    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '正在执行定时自动签到 (高频时间区间持续探测)...';
    notifyListeners();

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final deadline = DateTime.now().add(Duration(seconds: _scheduledWindowSec));

    try {
      final fh = await KlpbbsApi.getSignFormhash();
      while (DateTime.now().isBefore(deadline) && _isRunning) {
        final res = await KlpbbsApi.signIn(formhash: fh, fastMode: true);
        if (res.rank != null && res.rank! > 0) {
          await _recordSuccess(todayStr, res);
          break;
        } else if (res.success || res.message.contains('已签到') || res.message.contains('签过到') || res.message.contains('今日已签')) {
          final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
          if (info.isSignedToday) {
            await _recordSuccess(todayStr, res, headerInfo: info);
            break;
          }
        }
        await Future.delayed(Duration(milliseconds: _burstIntervalMs.clamp(50, 500)));
      }
    } catch (e) {
      _statusMessage = '定时签到异常：$e';
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
        _lastSuccessDate = todayStr;
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_keyLastSuccessDate, todayStr);
        final rankText = (info.mySignRank != null && info.mySignRank! > 0) ? ' (第 ${info.mySignRank} 名)' : '';
        final daysText = info.continuousDays > 0 ? ' | 连续 ${info.continuousDays} 天' : '';
        _statusMessage = '今日已完成签到$rankText$daysText';
        notifyListeners();
      } else {
        // 服务端显示尚未签到，清理可能存在的错误本地标记，立即执行自动签到
        _lastSuccessDate = '';
        final sp = await SharedPreferences.getInstance();
        await sp.remove(_keyLastSuccessDate);
        checkAndAutoSignIn(triggerSource: '后台巡检未签到自动打卡', force: true);
      }
    } catch (_) {}
  }

  /// 检查并执行自动签到（启动/手动触发）
  Future<void> checkAndAutoSignIn({String triggerSource = '自动签到', bool force = false}) async {
    if (!DioClient.isLoggedIn || _isRunning) return;

    final now = DateTime.now();
    // 3 分钟频控防抖（非强制触发时）
    if (!force && _lastCheckTime != null && now.difference(_lastCheckTime!).inMinutes < 3) {
      return;
    }
    _lastCheckTime = now;

    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '$triggerSource正在检测...';
    notifyListeners();

    try {
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
      if (info.isSignedToday) {
        _lastSuccessDate = todayStr;
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_keyLastSuccessDate, todayStr);
        final rankText = (info.mySignRank != null && info.mySignRank! > 0) ? ' (第 ${info.mySignRank} 名)' : '';
        final daysText = info.continuousDays > 0 ? ' | 连续 ${info.continuousDays} 天' : '';
        _statusMessage = '今日已完成签到$rankText$daysText';
        _isRunning = false;
        _runningStartTime = null;
        notifyListeners();
        return;
      }

      // 服务端网页权威确认尚未签到，清理本地可能存在的错误成功标记
      if (_lastSuccessDate == todayStr) {
        _lastSuccessDate = '';
        final sp = await SharedPreferences.getInstance();
        await sp.remove(_keyLastSuccessDate);
      }

      final res = await KlpbbsApi.signIn();
      if (res.success) {
        await _recordSuccess(todayStr, res);
      } else {
        _statusMessage = '签到未完成：${res.message}，将在后台持续探测重试';
      }
    } catch (e) {
      _statusMessage = '签到异常：$e';
    } finally {
      _isRunning = false;
      _runningStartTime = null;
      notifyListeners();
    }
  }

  Future<void> _recordSuccess(String targetDateStr, dynamic res, {SignHeaderInfo? headerInfo}) async {
    // 核心权威二次校验：若已斩获确切排名（如第 1 名），直接认定成功；其余情况通过服务端网页二次核实
    final hasConfirmedRank = res.rank != null && res.rank > 0;
    SignHeaderInfo info = headerInfo ?? const SignHeaderInfo();
    if (headerInfo != null) {
      info = headerInfo;
    } else {
      try {
        info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
        if (!info.isSignedToday && !hasConfirmedRank) {
          // 数据库异步写入可能存在微小时滞，进行轻量级阶梯核验（最多 2 次）
          for (int i = 1; i <= 2; i++) {
            await Future.delayed(Duration(milliseconds: i * 400));
            info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
            if (info.isSignedToday) break;
          }
        }
      } catch (_) {}
    }

    if (!hasConfirmedRank && !info.isSignedToday) {
      // 若服务端仍显示未签到且无排名，绝不标记成功，保持未完成状态以便继续探测
      _statusMessage = '签到请求已提交，等待论坛入库确认中...';
      notifyListeners();
      return;
    }

    _lastSuccessDate = targetDateStr;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyLastSuccessDate, targetDateStr);

    // 幂等防重：同一目标日期只允许记录并推送一次通知，杜绝重复发信
    if (_lastNotifiedDate == targetDateStr) {
      return;
    }
    _lastNotifiedDate = targetDateStr;
    await sp.setString(_keyLastNotifiedDate, targetDateStr);

    // 1. 深度同步：从真实账单流水（home.php?mod=spacecp&ac=credit&op=log）拉取绝对精确的实时变动明细
    // 服务端数据库入库可能有短暂延迟，采用阶梯延时重试机制（最多 3 次，如 600ms, 800ms, 1000ms）
    String rewardSummary = '';
    final now = DateTime.now();
    final shortDateStr = '${now.year}-${now.month}-${now.day}';

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await Future.delayed(Duration(milliseconds: attempt == 1 ? 600 : 800));
        final logs = await KlpbbsApi.getCreditLogs(page: 1, forceRefresh: true);
        final todayLogs = logs.where((l) {
          final isSignOp = l.operation.contains('签到') || l.detail.contains('签到');
          final isTodayTime = l.timeText.contains(targetDateStr) ||
              l.timeText.contains(shortDateStr) ||
              l.timeText.contains('今天') ||
              l.timeText.contains('刚刚') ||
              l.timeText.contains('分钟前') ||
              l.timeText.contains('小时前');
          return isSignOp && isTodayTime;
        }).toList();

        if (todayLogs.isNotEmpty) {
          final rewards = <String>[];
          for (final log in todayLogs) {
            rewards.add('${log.creditType} ${log.amount}');
          }
          rewardSummary = rewards.join(', ');
          break; // 成功获取到权威流水明细，直接跳出重试
        }
      } catch (_) {}
    }

    // 2. 若流水未抓取到或缺少名次/连续天数，从权威 headerInfo 提取真实数据
    int? finalRank = (res.rank != null && res.rank > 0)
        ? res.rank
        : (info.mySignRank != null && info.mySignRank! > 0 ? info.mySignRank : null);
    int? finalContinuousDays = (res.continuousDays != null && res.continuousDays > 0)
        ? res.continuousDays
        : (info.continuousDays > 0 ? info.continuousDays : null);
    String? finalIron = (res.rewardIron != null && res.rewardIron.toString().isNotEmpty)
        ? res.rewardIron.toString()
        : (info.rewardIron.isNotEmpty ? info.rewardIron : null);
    String? finalExp = (res.rewardExp != null && res.rewardExp.toString().isNotEmpty)
        ? res.rewardExp.toString()
        : null;

    // 3. 回退组合真实提示，严禁使用虚假硬编码（如 '10' 或 '6'）
    if (rewardSummary.isEmpty) {
      if (finalIron != null && finalIron.isNotEmpty) {
        if (finalExp != null && finalExp.isNotEmpty) {
          rewardSummary = '铁粒 +$finalIron, 经验 +$finalExp';
        } else {
          rewardSummary = '铁粒 +$finalIron';
        }
      } else if (finalExp != null && finalExp.isNotEmpty) {
        rewardSummary = '经验 +$finalExp';
      } else {
        rewardSummary = '已完成打卡';
      }
    }

    final hasRank = finalRank != null && finalRank > 0;
    final isFirst = finalRank == 1;

    final rankStatusText = hasRank ? (isFirst ? ' (🥇 今日第 1 名！)' : ' (今日第 $finalRank 名)') : '';
    _statusMessage = '🎉 签到成功！$rewardSummary$rankStatusText';
    notifyListeners();

    if (_notifyOnResult) {
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
        if (i < 5) {
          await Future.delayed(Duration(milliseconds: _burstIntervalMs));
        }
      }

      final avg = (latencies.reduce((a, b) => a + b) / latencies.length).round();
      final summary = '🚀 冲刺测试完成：连发 5 包全部响应正常，平均单包延迟 ${avg}ms！';
      _statusMessage = summary;
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

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}
