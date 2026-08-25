import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import 'push_notification_service.dart';

/// 零点冲榜策略
enum BurstStrategy {
  statusPolling('状态刷新探测抢签（推荐，高灵敏度低风险）'),
  burstSpam('高频极速发包冲刺（极限抢第 1 名）');

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
  bool _isRunning = false;
  DateTime? _runningStartTime; // 看门狗计时，防止卡死
  bool _isSnipingActive = false; // 是否处于 23:59 准备/冲刺阶段
  String _statusMessage = '服务未开启（等待配置）';
  Timer? _heartbeatTimer;

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

  /// 初始化自动签到引擎
  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _autoSignOnLaunch = sp.getBool(_keyAutoLaunch) ?? false;
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

      // 注册应用生命周期监听
      try {
        WidgetsBinding.instance.addObserver(this);
      } catch (_) {}

      // 启动 1 秒高精度心跳调度器
      _startHeartbeat();

      // 启动时自动检测签到
      if (_autoSignOnLaunch) {
        Future.delayed(const Duration(seconds: 3), () {
          checkAndAutoSignIn(triggerSource: '启动自动检测');
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

    // 1. 如果开启了启动自动打卡且今日未签
    if (_autoSignOnLaunch && _lastSuccessDate != todayStr && !_isRunning) {
      checkAndAutoSignIn(triggerSource: '唤醒自动检测');
      return;
    }

    // 2. 如果开启了定时打卡，且当前时间已经超过了设定的定时时间，但今日尚未签到（例如手机息屏错过了准点）
    if (_scheduledSignEnabled && _lastSuccessDate != todayStr && !_isRunning) {
      final isPastScheduled = (now.hour > _scheduledHour) ||
          (now.hour == _scheduledHour && now.minute >= _scheduledMinute);
      if (isPastScheduled) {
        checkAndAutoSignIn(triggerSource: '唤醒错峰补签');
      }
    }
  }

  // ================= 配置更新 =================

  Future<void> setAutoSignOnLaunch(bool val) async {
    _autoSignOnLaunch = val;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyAutoLaunch, val);
  }

  Future<void> setScheduledSignEnabled(bool val) async {
    _scheduledSignEnabled = val;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyScheduledEnabled, val);
  }

  Future<void> setScheduledTime(int hour, int minute) async {
    _scheduledHour = hour;
    _scheduledMinute = minute;
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _onHeartbeatTick();
    });
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

    // 1. 零点冲榜模式调度（在 23:59 开启准备、校准与时间区间探测）
    if (_burstModeEnabled) {
      if (now.hour == 23 && now.minute == 59) {
        if (!_isSnipingActive) {
          _isSnipingActive = true;
          _statusMessage = '23:59 冲榜就绪状态已激活，正在校准服务器时钟...';
          notifyListeners();
          _calibrateServerTime();
        }

        // 倒计时进入设定的提前区间（例如 23:59:45），开跑探测/发包，防止服务器时钟比本地快
        final startSecond = (60 - _burstPreSeconds).clamp(0, 59);
        if (now.second >= startSecond && !_isRunning) {
          _startMidnightSnipeLoop();
        }
      } else if (now.hour == 0 && now.minute == 0 && now.second <= _burstPostSeconds) {
        // 00:00 延后保护区间，防止服务器时钟比本地慢
        if (!_isRunning && _lastSuccessDate != todayStr) {
          _startMidnightSnipeLoop();
        }
      } else if (_isSnipingActive && now.minute >= 2) {
        // 跨天窗口完全结束，重置就绪标记
        _isSnipingActive = false;
        notifyListeners();
      }
    }

    // 2. 日常定时签到调度（准点执行 + 错峰补签保障）
    if (_scheduledSignEnabled && _lastSuccessDate != todayStr && !_isRunning) {
      // 准点容差区间触发
      if (now.hour == _scheduledHour && now.minute == _scheduledMinute && now.second <= _scheduledWindowSec) {
        _executeScheduledSign();
      } else if ((now.hour > _scheduledHour) || (now.hour == _scheduledHour && now.minute > _scheduledMinute)) {
        // 超时错峰补签（每隔 10 分钟检测一次，确保全天必签到）
        if (now.minute % 10 == 0 && now.second == 0) {
          checkAndAutoSignIn(triggerSource: '定时错峰补签');
        }
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

  /// 零点极速冲榜循环（核心）
  Future<void> _startMidnightSnipeLoop() async {
    if (_isRunning) return;
    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '🚀 跨天时间区间冲榜已启动 (${_burstStrategy.label}，间隔 ${_burstIntervalMs}ms)...';
    notifyListeners();

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final totalWindowDuration = Duration(seconds: _burstPreSeconds + _burstPostSeconds + 5);
    final deadline = DateTime.now().add(totalWindowDuration);

    try {
      if (_burstStrategy == BurstStrategy.statusPolling) {
        // 策略 A：在时间区间内以高频探测状态刷新，一旦发现服务端放开（未签状态）瞬间发起正式签到
        while (DateTime.now().isBefore(deadline) && _isRunning) {
          final isSigned = await KlpbbsApi.checkSigned();
          if (!isSigned) {
            final res = await KlpbbsApi.signIn();
            if (res.success || res.message.contains('已签到') || res.message.contains('签过到')) {
              _recordSuccess(todayStr, res);
              break;
            }
          }
          await Future.delayed(Duration(milliseconds: _burstIntervalMs));
        }
      } else {
        // 策略 B：在时间区间内持续极速发包冲刺
        while (DateTime.now().isBefore(deadline) && _isRunning) {
          final res = await KlpbbsApi.signIn();
          if (res.success || res.message.contains('已签到') || res.message.contains('签过到')) {
            _recordSuccess(todayStr, res);
            break;
          }
          await Future.delayed(Duration(milliseconds: _burstIntervalMs));
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
    _statusMessage = '正在执行定时自动签到 (时间区间持续探测)...';
    notifyListeners();

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final deadline = DateTime.now().add(Duration(seconds: _scheduledWindowSec));

    try {
      while (DateTime.now().isBefore(deadline) && _isRunning) {
        final isSigned = await KlpbbsApi.checkSigned();
        if (isSigned) {
          _lastSuccessDate = todayStr;
          _statusMessage = '今日已完成签到';
          break;
        }

        final res = await KlpbbsApi.signIn();
        if (res.success || res.message.contains('已签到') || res.message.contains('签过到')) {
          _recordSuccess(todayStr, res);
          break;
        }

        await Future.delayed(Duration(milliseconds: _burstIntervalMs.clamp(200, 1000)));
      }
    } catch (e) {
      _statusMessage = '定时签到异常：$e';
    } finally {
      _isRunning = false;
      _runningStartTime = null;
      notifyListeners();
    }
  }

  /// 检查并执行自动签到（启动/手动触发）
  Future<void> checkAndAutoSignIn({String triggerSource = '自动签到'}) async {
    if (!DioClient.isLoggedIn || _isRunning) return;

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '$triggerSource正在检测...';
    notifyListeners();

    try {
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
      if (info.isSignedToday) {
        _lastSuccessDate = todayStr;
        _statusMessage = '今日已完成签到';
        _isRunning = false;
        _runningStartTime = null;
        notifyListeners();
        return;
      }

      final res = await KlpbbsApi.signIn();
      if (res.success || res.message.contains('已签到') || res.message.contains('签过到')) {
        _recordSuccess(todayStr, res);
      } else {
        _statusMessage = '签到未完成：${res.message}';
      }
    } catch (e) {
      _statusMessage = '签到异常：$e';
    } finally {
      _isRunning = false;
      _runningStartTime = null;
      notifyListeners();
    }
  }

  void _recordSuccess(String todayStr, dynamic res) {
    _lastSuccessDate = todayStr;
    _statusMessage = '🎉 签到成功！奖励: +${res.rewardIron ?? "10"} 粒铁粒';
    SharedPreferences.getInstance().then((sp) {
      sp.setString(_keyLastSuccessDate, todayStr);
    });

    if (_notifyOnResult) {
      _pushSignResultNotification(res);
    }
  }

  /// 签到结果全平台消息推送（不包含排名，展示奖励、经验与连续天数）
  void _pushSignResultNotification(dynamic res) {
    final ironText = '+${res.rewardIron ?? "10"} 粒铁粒';
    final expText = (res.rewardExp != null && res.rewardExp.toString().isNotEmpty)
        ? ' | 经验 +${res.rewardExp} EP'
        : '';
    final daysText = (res.continuousDays != null && res.continuousDays > 0)
        ? ' | 已连续 ${res.continuousDays} 天'
        : '';

    PushNotificationService.instance.pushCustomNotification(
      title: '苦力怕论坛 · 签到成功 🎉',
      body: '签到奖励：$ironText$expText$daysText',
    );
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
