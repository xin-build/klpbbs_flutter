import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
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
    return _lastSuccessDate == todayStr || _lastNotifiedDate == todayStr;
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

      // 启动时自动检测签到
      if (_autoSignOnLaunch || AppConfig.autoCheckin) {
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

    final isAnyAutoEnabled = _burstModeEnabled || _scheduledSignEnabled || _autoSignOnLaunch || AppConfig.autoCheckin;
    if (isAnyAutoEnabled && _lastSuccessDate != todayStr && !_isRunning) {
      checkAndAutoSignIn(triggerSource: '唤醒自动检测');
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

  /// 计算下一次心跳周期：处于冲刺临界或定时签到临界期保持 1 秒高精度，平时 30 秒休眠省电
  Duration _resolveNextHeartbeatDuration() {
    if (_isRunning) {
      return const Duration(seconds: 1);
    }
    final now = DateTime.now();
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

    // 1. 零点冲榜模式调度（在 23:59 开启准备、校准、预热 FormHash 与时间区间探测）
    if (_burstModeEnabled) {
      if (now.hour == 23 && now.minute == 59) {
        // 23:59 冲刺的目标为次日签到
        final targetDate = now.add(const Duration(minutes: 2));
        final targetDateStr = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

        if (_lastSuccessDate != targetDateStr && _lastNotifiedDate != targetDateStr) {
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
        if (!_isRunning && _lastSuccessDate != todayStr && _lastNotifiedDate != todayStr) {
          _startMidnightSnipeLoop(todayStr);
        }
      } else if (_isSnipingActive && now.minute >= 2) {
        // 跨天窗口完全结束，重置就绪标记
        _isSnipingActive = false;
        notifyListeners();
      }
    }

    // 2. 日常定时签到调度（准点执行 + 错峰补签保障）
    if (_scheduledSignEnabled && _lastSuccessDate != todayStr && _lastNotifiedDate != todayStr && !_isRunning) {
      if (now.hour == _scheduledHour && now.minute == _scheduledMinute && now.second <= _scheduledWindowSec) {
        _executeScheduledSign();
      } else if ((now.hour > _scheduledHour) || (now.hour == _scheduledHour && now.minute > _scheduledMinute)) {
        if (now.minute % 10 == 0) {
          checkAndAutoSignIn(triggerSource: '定时错峰补签');
        }
      }
    }

    // 3. 全天未签自动保底与错峰补签机制（15 分钟频率防抖，杜绝频繁唤醒）
    final isAnyAutoEnabled = _burstModeEnabled || _scheduledSignEnabled || _autoSignOnLaunch || AppConfig.autoCheckin;
    if (isAnyAutoEnabled && _lastSuccessDate != todayStr && _lastNotifiedDate != todayStr && !_isRunning) {
      if (_lastFallbackCheckTime == null || now.difference(_lastFallbackCheckTime!).inMinutes >= 15) {
        _lastFallbackCheckTime = now;
        checkAndAutoSignIn(triggerSource: '全天未签自动保底');
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

  /// 零点极速冲榜循环（核心：支持 50ms 流水线非阻塞并发发包，确保 100% 抢占第 1 名）
  Future<void> _startMidnightSnipeLoop(String targetDateStr) async {
    if (_isRunning) return;
    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '🚀 跨天时间区间冲榜已启动 (${_burstStrategy.label}，间隔 ${_burstIntervalMs}ms)...';
    notifyListeners();

    final totalWindowDuration = Duration(seconds: _burstPreSeconds + _burstPostSeconds + 5);
    final deadline = DateTime.now().add(totalWindowDuration);

    try {
      // 预先获取 FormHash 避免每次请求阻塞
      var fh = await KlpbbsApi.getSignFormhash();
      bool refreshedAtMidnight = false;
      bool isFinished = false;
      int inFlight = 0;
      const maxInFlight = 4; // 管道并发度，防止网络拥塞同时保持极高发包密度

      while (DateTime.now().isBefore(deadline) && _isRunning && !isFinished) {
        final now = DateTime.now();

        // 刚跨入 00:00 时在后台静默异步刷新一次 FormHash
        if (now.hour == 0 && !refreshedAtMidnight) {
          refreshedAtMidnight = true;
          KlpbbsApi.getSignFormhash(forceRefresh: true).then((newFh) {
            if (newFh != null && newFh.isNotEmpty) fh = newFh;
          }).catchError((_) {});
        }

        // 核心临界期判定：23:59:58 ~ 00:00:03（这是抢第一名的核心黄金秒数）
        final isCriticalWindow = (now.hour == 23 && now.minute == 59 && now.second >= 58) ||
            (now.hour == 0 && now.minute == 0 && now.second <= 3);

        if (isCriticalWindow) {
          // 黄金 5 秒：启用非阻塞流水线发包 (Pipelined Burst)
          // 按照 _burstIntervalMs (如 50ms) 持续投递发包，不被网络 RTT 延迟阻塞
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

            KlpbbsApi.signIn(formhash: fh).then((res) async {
              inFlight--;
              if (isFinished) return;

              final currentNow = DateTime.now();
              if (res.success || (res.rank != null && res.rank! > 0)) {
                isFinished = true;
                burstTimer?.cancel();
                await _recordSuccess(targetDateStr, res);
                if (!completer.isCompleted) completer.complete();
                return;
              }

              final isAlreadySignedMsg = res.message.contains('已签到') ||
                  res.message.contains('签过到') ||
                  res.message.contains('今日已签');

              if (isAlreadySignedMsg) {
                if (currentNow.hour == 0) {
                  // 已经跨入 00:00:xx 收到已签到，说明抢榜请求已成功录入系统
                  isFinished = true;
                  burstTimer?.cancel();
                  await _recordSuccess(targetDateStr, res);
                  if (!completer.isCompleted) completer.complete();
                } else {
                  // 仍在 23:59:xx 提前发包区间，此时的“今日已签”属于当天白天的旧记录，绝不能退出抢榜！
                  _statusMessage = '零点冲刺预热中 (${currentNow.hour.toString().padLeft(2, '0')}:${currentNow.minute.toString().padLeft(2, '0')}:${currentNow.second.toString().padLeft(2, '0')}，等待 00:00 跨天生效)...';
                  notifyListeners();
                }
              }
            }).catchError((err) {
              inFlight--;
            });
          }

          final intervalMs = _burstIntervalMs.clamp(50, 500);
          burstTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) => triggerFire());
          triggerFire(); // 立即发射第 1 发

          await Future.any([
            completer.future,
            Future.delayed(const Duration(seconds: 5)),
          ]);
          burstTimer.cancel();

          if (isFinished) break;
        } else {
          // 临界期之外（23:59:45 ~ 23:59:58 或 00:00:04 之后）：平稳探测
          if (_burstStrategy == BurstStrategy.statusPolling && now.hour == 23) {
            final isSigned = await KlpbbsApi.checkSigned();
            if (!isSigned) {
              final res = await KlpbbsApi.signIn(formhash: fh);
              if (res.success || (res.rank != null && res.rank! > 0) || (now.hour == 0 && (res.message.contains('已签到') || res.message.contains('今日已签')))) {
                await _recordSuccess(targetDateStr, res);
                break;
              }
            }
          } else {
            final res = await KlpbbsApi.signIn(formhash: fh);
            if (res.success || (res.rank != null && res.rank! > 0)) {
              await _recordSuccess(targetDateStr, res);
              break;
            }

            final isAlreadySignedMsg = res.message.contains('已签到') ||
                res.message.contains('签过到') ||
                res.message.contains('今日已签');

            if (isAlreadySignedMsg) {
              if (now.hour == 0) {
                await _recordSuccess(targetDateStr, res);
                break;
              } else {
                _statusMessage = '零点冲刺预热中 (${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}，等待 00:00 跨天生效)...';
                notifyListeners();
              }
            }
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
      final fh = await KlpbbsApi.getSignFormhash();
      while (DateTime.now().isBefore(deadline) && _isRunning) {
        final res = await KlpbbsApi.signIn(formhash: fh);
        if (res.success || res.message.contains('已签到') || res.message.contains('签过到') || res.message.contains('今日已签')) {
          await _recordSuccess(todayStr, res);
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
  Future<void> checkAndAutoSignIn({String triggerSource = '自动签到', bool force = false}) async {
    if (!DioClient.isLoggedIn || _isRunning) return;

    final now = DateTime.now();
    // 5 分钟频控防抖（非强制触发时）
    if (!force && _lastCheckTime != null && now.difference(_lastCheckTime!).inMinutes < 5) {
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
        _lastNotifiedDate = todayStr;
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_keyLastSuccessDate, todayStr);
        await sp.setString(_keyLastNotifiedDate, todayStr);
        _statusMessage = '今日已完成签到';
        _isRunning = false;
        _runningStartTime = null;
        notifyListeners();
        return;
      }

      final res = await KlpbbsApi.signIn();
      if (res.success || res.message.contains('已签到') || res.message.contains('签过到') || res.message.contains('今日已签')) {
        await _recordSuccess(todayStr, res);
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

  Future<void> _recordSuccess(String targetDateStr, dynamic res) async {
    // 幂等防重：同一目标日期只允许记录并推送一次通知，杜绝重复发信
    if (_lastNotifiedDate == targetDateStr) {
      return;
    }
    _lastSuccessDate = targetDateStr;
    _lastNotifiedDate = targetDateStr;

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyLastSuccessDate, targetDateStr);
    await sp.setString(_keyLastNotifiedDate, targetDateStr);

    // 深度同步：从真实账单流水（home.php?mod=spacecp&ac=credit&op=log）拉取绝对精确的实时变动明细
    String rewardSummary = '';
    try {
      await Future.delayed(const Duration(milliseconds: 600));
      final logs = await KlpbbsApi.getCreditLogs(page: 1);
      final todayLogs = logs.where((l) {
        final isSignOp = l.operation.contains('签到') || l.detail.contains('签到');
        final isTodayTime = l.timeText.contains(targetDateStr) ||
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
      }
    } catch (_) {}

    // 若流水未抓取到，回退使用接口解析结果
    if (rewardSummary.isEmpty) {
      final iron = res.rewardIron ?? '6';
      final exp = res.rewardExp;
      if (exp != null && exp.toString().isNotEmpty) {
        rewardSummary = '铁粒 +$iron, 经验 +$exp';
      } else {
        rewardSummary = '铁粒 +$iron';
      }
    }

    final rank = res.rank;
    final hasRank = rank != null && rank > 0;
    final isFirst = rank == 1;

    final rankStatusText = hasRank ? (isFirst ? ' (🥇 今日第 1 名！)' : ' (今日第 $rank 名)') : '';
    _statusMessage = '🎉 签到成功！$rewardSummary$rankStatusText';
    notifyListeners();

    if (_notifyOnResult) {
      _pushSignResultNotification(res, rewardSummary);
    }
  }

  /// 签到结果全平台消息推送（展示排名、奖励、经验与连续天数）
  void _pushSignResultNotification(dynamic res, String rewardSummary) {
    final rank = res.rank;
    final hasRank = rank != null && rank > 0;
    final isFirst = rank == 1;

    final title = isFirst
        ? '🥇 苦力怕论坛 · 恭喜拿下今日签到第 1 名！'
        : hasRank
            ? '苦力怕论坛 · 签到成功 (今日第 $rank 名) 🎉'
            : '苦力怕论坛 · 签到成功 🎉';

    final rankBodyText = hasRank ? '🏆 今日排名：第 $rank 名\n' : '';
    final daysText = (res.continuousDays != null && res.continuousDays > 0)
        ? ' | 已连续 ${res.continuousDays} 天'
        : '';

    PushNotificationService.instance.pushCustomNotification(
      title: title,
      body: '$rankBodyText签到奖励：$rewardSummary$daysText',
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
        final res = await KlpbbsApi.signIn(formhash: fh);
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
