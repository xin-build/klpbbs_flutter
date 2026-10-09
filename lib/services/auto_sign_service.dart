import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/discuz_sign_response.dart';
import '../core/sign_account_proof.dart';
import '../core/sign_proof_revision.dart';
import '../models/server_outage_info.dart';
import '../models/sign_entry.dart';
import 'push_notification_service.dart';

/// 零点冲榜策略
enum BurstStrategy {
  statusPolling('跨天后先刷新状态，再提交签到'),
  burstSpam('跨天后直接提交一次签到');

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
  String get _keyLastSuccessDate => _stateKey('auto_sign_last_success_date');
  String get _keyLastNotifiedDate => _stateKey('auto_sign_last_notified_date');
  String? _accountProofScope;
  String _stateKey(String name) =>
      '$name:${_accountProofScope ?? DioClient.sessionKey}';
  static const String _keyRecoverySignEnabled = 'auto_sign_recovery_on_502';

  // Config States
  bool _autoSignOnLaunch = false;
  bool _scheduledSignEnabled = false;
  int _scheduledHour = 0;
  int _scheduledMinute = 0;
  int _scheduledWindowSec = 30; // 定时签到容差探测区间（秒）

  bool _burstModeEnabled = false;
  BurstStrategy _burstStrategy = BurstStrategy.statusPolling;
  int _burstIntervalMs = 200; // 默认 200ms 本地时钟检查，可在 100ms ~ 1000ms 调节
  int _burstPreSeconds = 15; // 提前开跑区间（23:59:45 开始），防服务器时钟比本地快
  int _burstPostSeconds = 20; // 跨天延后区间（00:00:20 结束），防服务器时钟比本地慢
  bool _notifyOnResult = true;

  // 502 / 网关宕机故障实时静默探测与恢复即签机制
  bool _serverRecoverySignEnabled = false;
  bool _isServerOutage = false;
  bool _isProbingRecovery = false;
  int _recoveryProbeCount = 0;
  DateTime? _outageStartTime;
  ServerOutageInfo? _lastOutageInfo;
  Timer? _recoveryProbeTimer;

  // Runtime States
  String _lastSuccessDate = '';
  String _stateSession = '';
  String _lastUnsignedDate = '';
  String _lastNotifiedDate = '';
  int _continuousDays = 0;
  String _continuousDaysDate = '';
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
  String? _launchCheckedSession;
  String? _launchCheckedDay;
  Future<void>? _launchCheck;
  final _signProofRevision = SignProofRevision();

  // Getters
  bool get autoSignOnLaunch => _autoSignOnLaunch;
  int get signWriteRevision => _signProofRevision.value;
  int get serverClockOffsetMs => _serverClockOffsetMs;

  bool _isCurrentStateRead(String session, int revision) =>
      DioClient.isLoggedIn &&
      session == DioClient.sessionKey &&
      _signProofRevision.acceptsRead(revision);

  /// 论坛官方服务端当前精准时间（以东八区北京时间为基准，叠加毫秒级网络偏差校准）
  DateTime get estimatedServerNow {
    final utc = DateTime.now()
        .toUtc()
        .add(Duration(milliseconds: _serverClockOffsetMs));
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
  int? get currentContinuousDays => DioClient.isLoggedIn &&
          _stateSession == DioClient.sessionKey &&
          _continuousDaysDate == serverTodayStr
      ? _continuousDays
      : null;
  bool? get confirmedTodayState =>
      !DioClient.isLoggedIn || _stateSession != DioClient.sessionKey
          ? null
          : isSignedToday()
              ? true
              : _lastUnsignedDate == serverTodayStr
                  ? false
                  : null;
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
    return DioClient.isLoggedIn &&
        _stateSession == DioClient.sessionKey &&
        _lastSuccessDate == sToday;
  }

  void _resetProofsForSession(String session) {
    _stateSession = session;
    _accountProofScope = null;
    _lastSuccessDate = '';
    _lastUnsignedDate = '';
    _lastNotifiedDate = '';
    _continuousDays = 0;
    _continuousDaysDate = '';
    _lastRank = 0;
  }

  Future<bool> _restoreAccountProofs(String session) async {
    if (!DioClient.isLoggedIn || session != DioClient.sessionKey) return false;
    if (_stateSession != session) _resetProofsForSession(session);
    if (_accountProofScope != null) return true;
    int? uid;
    try {
      uid = await KlpbbsApi.getMyUid();
    } catch (_) {
      return false;
    }
    if (uid == null || uid <= 0 || session != DioClient.sessionKey) {
      return false;
    }
    final scope = SignAccountProof.scope(Uri.parse(AppConfig.baseUrl), uid);
    final sp = await SharedPreferences.getInstance();
    if (session != DioClient.sessionKey || !DioClient.isLoggedIn) return false;
    if (_accountProofScope != null) return true;
    // Only migrate this verified live account's old fingerprint keys.
    String value(String name) =>
        sp.getString('$name:$scope') ?? sp.getString('$name:$session') ?? '';
    int number(String name) =>
        sp.getInt('$name:$scope') ?? sp.getInt('$name:$session') ?? 0;
    _accountProofScope = scope;
    _lastSuccessDate = value('auto_sign_last_success_date');
    _lastNotifiedDate = value('auto_sign_last_notified_date');
    _continuousDays = number('auto_sign_continuous_days');
    _continuousDaysDate = value('auto_sign_continuous_days_date');
    _lastRank = number('auto_sign_last_rank');
    return true;
  }

  /// 手动触发签到
  Future<void> signIn() =>
      checkAndAutoSignIn(triggerSource: '手动点击打卡', force: true);

  /// 标记今日签到成功（持久化保存并同步本地缓存与日历，支持同步服务端最新名次与连续天数，默认静默不打扰用户）
  Future<void> markSignedToday({
    int? rank,
    int? continuousDays,
    String? rewardIron,
    String? rewardExp,
    bool notify = false,
    String? expectedSession,
    String? expectedDay,
    bool submittedSuccessfully = false,
    int? expectedWriteRevision,
  }) async {
    final targetDay = expectedDay ?? serverTodayStr;
    final session = expectedSession ?? DioClient.sessionKey;
    if (!DioClient.isLoggedIn ||
        session != DioClient.sessionKey ||
        targetDay != serverTodayStr) {
      return;
    }
    // A success receipt is distinct from a read-only signed page and from the
    // notification preference. Invalidate older reads even with alerts disabled.
    if (!submittedSuccessfully &&
        expectedWriteRevision != null &&
        !_signProofRevision.acceptsRead(expectedWriteRevision)) {
      return;
    }
    _signProofRevision.recordSubmission(success: submittedSuccessfully);
    final revision = signWriteRevision;
    bool current() =>
        _isCurrentStateRead(session, revision) && targetDay == serverTodayStr;
    if (_stateSession != session) _resetProofsForSession(session);
    await _restoreAccountProofs(session);
    if (!current()) return;
    final successKey = _keyLastSuccessDate;
    final notifiedKey = _keyLastNotifiedDate;
    final daysKey = _stateKey('auto_sign_continuous_days');
    final daysDateKey = _stateKey('auto_sign_continuous_days_date');
    final rankKey = _stateKey('auto_sign_last_rank');
    final todayStr = targetDay;
    final bool wasAlreadySigned = _lastSuccessDate == todayStr;
    final rankText = (rank != null && rank > 0) ? ' (第 $rank 名)' : '';
    final daysText = (continuousDays != null && continuousDays > 0)
        ? ' | 连续 $continuousDays 天'
        : '';
    final newStatus = (rankText.isNotEmpty || daysText.isNotEmpty)
        ? '今日已完成签到$rankText$daysText'
        : '今日已完成签到';

    if (wasAlreadySigned &&
        _statusMessage == newStatus &&
        (rank == null || _lastRank == rank) &&
        (continuousDays == null || _continuousDays == continuousDays) &&
        (continuousDays == null || _continuousDaysDate == todayStr) &&
        (!notify || !_notifyOnResult || _lastNotifiedDate == todayStr)) {
      // 状态完全一致无变更，阻断重复磁盘写入与下游监听器级联风暴
      return;
    }

    _lastSuccessDate = todayStr;
    _lastUnsignedDate = '';
    _statusMessage = newStatus;

    final sp = await SharedPreferences.getInstance();
    if (!current()) return;
    await sp.setString(successKey, todayStr);
    if (!current()) return;
    if (continuousDays != null && continuousDays >= 0) {
      _continuousDays = continuousDays;
      _continuousDaysDate = todayStr;
      await sp.setInt(daysKey, continuousDays);
      if (!current()) return;
      await sp.setString(daysDateKey, todayStr);
    }
    if (!current()) return;
    if (rank != null && rank > 0) {
      _lastRank = rank;
      await sp.setInt(rankKey, rank);
    }
    if (!current()) return;
    await KlpbbsApi.recordSignDateToLocalCalendar(
        expectedSession: session, expectedDay: targetDay);
    if (!current()) return;

    _cancelRecoveryProbe();
    notifyListeners();
    if (!current()) return;

    final savedNotifiedDate = sp.getString(notifiedKey) ?? '';
    final alreadyNotified =
        _lastNotifiedDate == todayStr || savedNotifiedDate == todayStr;

    if (SignAccountProof.shouldNotify(
        submittedSuccessfully: notify,
        enabled: _notifyOnResult,
        today: todayStr,
        lastNotifiedDay: alreadyNotified ? todayStr : '')) {
      _lastNotifiedDate = todayStr;
      await sp.setString(notifiedKey, todayStr);
      if (!current()) return;
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
  Future<void> markUnsignedToday(
      {bool resetNotification = false,
      String? expectedSession,
      int? expectedWriteRevision}) async {
    if (expectedSession != null && expectedSession != DioClient.sessionKey) {
      return;
    }
    final session = DioClient.sessionKey;
    final revision = expectedWriteRevision ?? signWriteRevision;
    if (!_isCurrentStateRead(session, revision)) return;
    if (_stateSession != session) _resetProofsForSession(session);
    await _restoreAccountProofs(session);
    if (!_isCurrentStateRead(session, revision)) return;
    final successKey = _keyLastSuccessDate;
    final notifiedKey = _keyLastNotifiedDate;
    final sToday = serverTodayStr;
    final alreadyVerifiedUnsigned = _lastUnsignedDate == sToday;
    _lastUnsignedDate = sToday;
    final sn = estimatedServerNow;
    final monthKey = KlpbbsApi.signCalendarKey(sn.year, sn.month);
    final now = DateTime.now();
    final localToday =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final wasSigned =
        _lastSuccessDate == sToday || _lastSuccessDate == localToday;
    if (!wasSigned &&
        alreadyVerifiedUnsigned &&
        _statusMessage == '今日尚未签到' &&
        !resetNotification) {
      // 状态已是未签到，阻断冗余 notifyListeners 级联触发
      return;
    }

    if (_lastSuccessDate == sToday || _lastSuccessDate == localToday) {
      _lastSuccessDate = '';
    }
    final sp = await SharedPreferences.getInstance();
    if (!_isCurrentStateRead(session, revision)) return;
    await sp.remove(successKey);

    if (!_isCurrentStateRead(session, revision)) return;
    if (resetNotification) {
      if (_lastNotifiedDate == sToday || _lastNotifiedDate == localToday) {
        _lastNotifiedDate = '';
      }
      await sp.remove(notifiedKey);
    }

    // 从本地日历缓存中移除今日
    if (!_isCurrentStateRead(session, revision)) return;
    final list = sp.getStringList(monthKey);
    if (list != null && list.contains('${sn.day}')) {
      final updated = list.where((d) => d != '${sn.day}').toList();
      await sp.setStringList(monthKey, updated);
    }
    if (!_isCurrentStateRead(session, revision)) return;
    _statusMessage = '今日尚未签到';
    notifyListeners();
  }

  /// 切换账号时重置签到状态并重新与服务端同步
  Future<void> onAccountSwitched() async {
    final session = DioClient.sessionKey;
    _resetProofsForSession(session);
    _lastCheckTime = null;
    _lastFallbackCheckTime = null;
    _continuousDays = 0;
    _continuousDaysDate = '';
    _lastRank = 0;
    _launchCheckedSession = null;
    _launchCheckedDay = null;
    _launchCheck = null;
    _isRunning = false;
    _runningStartTime = null;
    _cancelRecoveryProbe();
    _statusMessage = '账号已切换，正在与服务端对齐签到状态...';
    try {
      if (session != DioClient.sessionKey) return;
      await _restoreAccountProofs(session);
    } catch (_) {}
    notifyListeners();
    if (DioClient.isLoggedIn && session == DioClient.sessionKey) {
      if (isSignedToday()) {
        _statusMessage = '今日已完成签到';
        notifyListeners();
      } else {
        unawaited(checkOnAppLaunch());
      }
    }
  }

  /// 初始化自动签到引擎
  Future<void> init() async {
    _resetProofsForSession(DioClient.sessionKey);
    try {
      final sp = await SharedPreferences.getInstance();
      _autoSignOnLaunch =
          sp.getBool(_keyAutoLaunch) ?? sp.getBool('auto_checkin') ?? false;
      _scheduledSignEnabled = sp.getBool(_keyScheduledEnabled) ?? false;
      _scheduledHour = sp.getInt(_keyScheduledHour) ?? 0;
      _scheduledMinute = sp.getInt(_keyScheduledMinute) ?? 0;
      _scheduledWindowSec = sp.getInt(_keyScheduledWindowSec) ?? 30;

      _burstModeEnabled = sp.getBool(_keyBurstEnabled) ?? false;
      final strategyIdx = sp.getInt(_keyBurstStrategy) ?? 0;
      _burstStrategy =
          (strategyIdx >= 0 && strategyIdx < BurstStrategy.values.length)
              ? BurstStrategy.values[strategyIdx]
              : BurstStrategy.statusPolling;
      _burstIntervalMs = sp.getInt(_keyBurstInterval) ?? 200;
      _burstPreSeconds = sp.getInt(_keyBurstPreSeconds) ?? 15;
      _burstPostSeconds = sp.getInt(_keyBurstPostSeconds) ?? 20;

      _notifyOnResult = sp.getBool(_keyNotifyResult) ?? true;
      // 净化旧版本提前写入 _keyLastNotifiedDate 导致今日通知被静默吞没的脏数据
      final hasNotifySanitized =
          sp.getBool('sign_notify_sanitized_v3') ?? false;
      if (!hasNotifySanitized) {
        await sp.remove(_keyLastNotifiedDate);
        _lastNotifiedDate = '';
        await sp.setBool('sign_notify_sanitized_v3', true);
      } else {
        _lastNotifiedDate = sp.getString(_keyLastNotifiedDate) ?? '';
      }
      _lastSuccessDate = sp.getString(_keyLastSuccessDate) ?? '';
      _continuousDays = sp.getInt(_stateKey('auto_sign_continuous_days')) ?? 0;
      _continuousDaysDate =
          sp.getString(_stateKey('auto_sign_continuous_days_date')) ?? '';
      _lastRank = sp.getInt(_stateKey('auto_sign_last_rank')) ?? 0;
      _serverRecoverySignEnabled = sp.getBool(_keyRecoverySignEnabled) ?? false;

      // 注册应用生命周期监听
      try {
        WidgetsBinding.instance.addObserver(this);
      } catch (_) {}

      // 启动 1 秒高精度心跳调度器
      _startHeartbeat();
    } catch (_) {}
  }

  /// 应用启动时直接抓取网页实时数据检测签到状态，若未签到直接签到
  Future<void> checkOnAppLaunch() async {
    final session = DioClient.sessionKey;
    if (!DioClient.isLoggedIn ||
        (_launchCheckedSession == session &&
            _launchCheckedDay == serverTodayStr)) {
      return;
    }
    await _restoreAccountProofs(session);
    if (session != DioClient.sessionKey) return;
    if (isSignedToday()) {
      _launchCheckedSession = session;
      _launchCheckedDay = serverTodayStr;
      return;
    }
    if (_launchCheck != null) return _launchCheck;
    final future = _checkLaunch(session);
    _launchCheck = future;
    try {
      await future;
    } finally {
      if (identical(_launchCheck, future)) _launchCheck = null;
    }
  }

  Future<void> _checkLaunch(String session) async {
    if (!DioClient.isLoggedIn || _isRunning) return;
    final readRevision = signWriteRevision;
    try {
      // 1. 抓取网页实时数据（统一使用 PC UA，强刷无缓存）
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
      if (!_isCurrentStateRead(session, readRevision)) return;
      if (!info.hasPersonalState) return;
      _launchCheckedSession = session;
      _launchCheckedDay = serverTodayStr;
      if (info.isSignedToday) {
        await markSignedToday(
          rank: info.mySignRank,
          continuousDays: info.hasContinuousDays ? info.continuousDays : null,
          rewardIron: info.rewardIron,
          notify: false,
          expectedSession: session,
          expectedWriteRevision: readRevision,
        );
      } else {
        await markUnsignedToday(
            expectedSession: session, expectedWriteRevision: readRevision);
        if (!_isCurrentStateRead(session, readRevision)) return;
        // 2. 网页显示未签到，直接触发自动打卡闭环！
        if (_autoSignOnLaunch) {
          await checkAndAutoSignIn(triggerSource: '启动自动签到', force: true);
        }
      }
      if (!_isCurrentStateRead(session, readRevision)) return;
      // 3. 检查断签挽回与智能补签
      if (info.retroSignDays > 0) {
        unawaited(_handleRetroSignOpportunity(info,
            expectedSession: session, expectedWriteRevision: readRevision));
      }
    } catch (e) {
      if (!_isCurrentStateRead(session, readRevision)) return;
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
    final session = DioClient.sessionKey;
    if (!DioClient.isLoggedIn) return;
    await _restoreAccountProofs(session);
    if (session != DioClient.sessionKey || !DioClient.isLoggedIn) return;
    final todayStr = serverTodayStr;
    final serverDay = estimatedServerNow.day;

    try {
      final sp = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey || !DioClient.isLoggedIn) return;
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
    if (!DioClient.isLoggedIn || session != DioClient.sessionKey) return;

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

    final isAnyAutoEnabled = _burstModeEnabled ||
        _scheduledSignEnabled ||
        _autoSignOnLaunch ||
        AppConfig.autoCheckin;

    // 零点跨天保护守护：只要开启任何自动化，23:59:40 ~ 00:00:30 全程保持 1 秒高频，确保 00:00:01 准点触发
    if (isAnyAutoEnabled) {
      if ((now.hour == 23 && now.minute == 59 && now.second >= 40) ||
          (now.hour == 0 && now.minute == 0 && now.second <= 30)) {
        return const Duration(seconds: 1);
      }
    }

    // 零点冲榜临界期：23:58 ~ 次日 00:02
    if (_burstModeEnabled) {
      if ((now.hour == 23 && now.minute >= 58) ||
          (now.hour == 0 && now.minute <= 2)) {
        return const Duration(seconds: 1);
      }
    }
    // 定时签到临界期：目标签到时间前 15 秒 ~ 容差探测区间内，保持 1 秒高精度调度
    if (_scheduledSignEnabled && !isSignedToday()) {
      final scheduledToday = DateTime(
          now.year, now.month, now.day, _scheduledHour, _scheduledMinute);
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
      final isAnyAutoEnabled = _burstModeEnabled ||
          _scheduledSignEnabled ||
          _autoSignOnLaunch ||
          AppConfig.autoCheckin;

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
            } else if (_scheduledSignEnabled &&
                _scheduledHour == 0 &&
                _scheduledMinute == 0) {
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
          final targetDateStr =
              '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

          // 纠偏保护：23:58 绝不可能提前完成明天的签到。如果本地留存了明天的伪成功标记，立即纠偏清除！
          if (_lastSuccessDate == targetDateStr) {
            _lastSuccessDate = '';
            SharedPreferences.getInstance()
                .then((sp) => sp.remove(_keyLastSuccessDate))
                .catchError((_) => false);
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
        } else if (now.hour == 0 &&
            now.minute == 0 &&
            now.second <= _burstPostSeconds) {
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
      if (_scheduledSignEnabled &&
          _lastSuccessDate != todayStr &&
          !_isRunning) {
        if (now.hour == _scheduledHour &&
            now.minute == _scheduledMinute &&
            now.second <= _scheduledWindowSec) {
          _executeScheduledSign();
        } else if ((now.hour > _scheduledHour) ||
            (now.hour == _scheduledHour && now.minute > _scheduledMinute)) {
          if (now.minute % 10 == 0) {
            checkAndAutoSignIn(triggerSource: '定时错峰补签');
          }
        }
      }

      // 3. 全天后台持续状态同步与自动签到保底机制（仅在今日未签到时工作）
      if (isAnyAutoEnabled && !_isRunning && _lastSuccessDate != todayStr) {
        if (_lastFallbackCheckTime == null ||
            now.difference(_lastFallbackCheckTime!).inMinutes >= 15) {
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

    final codeStr =
        info != null ? '${info.statusCode} ${info.title}' : '502 网关故障';
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

    final elapsed =
        DateTime.now().difference(_outageStartTime ?? DateTime.now());
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
    final session = DioClient.sessionKey;
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
      if (session != DioClient.sessionKey || !_serverRecoverySignEnabled) {
        return;
      }
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

  /// 按用户启用的恢复选项提交一次签到，结果由正式接口核验。
  Future<void> _executeRecoverySignIn() async {
    if (!_serverRecoverySignEnabled ||
        !DioClient.isLoggedIn ||
        isSignedToday()) {
      return;
    }
    await checkAndAutoSignIn(triggerSource: '服务器恢复后签到', force: false);
  }

  /// 对齐论坛服务端精准时钟（通过 HTTP Date 头部毫秒级计算偏差）
  Future<void> _calibrateServerTime() async {
    try {
      final offset = await KlpbbsApi.pingServerTime();
      if (offset != null) {
        _serverClockOffsetMs = offset.clamp(-600000, 600000);
        _statusMessage =
            '时钟对齐完成 (服务端时钟偏差: ${_serverClockOffsetMs >= 0 ? "+$_serverClockOffsetMs" : "$_serverClockOffsetMs"}ms)';
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 零点任务只在服务端日期到达目标日后提交；同一会话一次写操作。
  Future<void> _startMidnightSnipeLoop(String targetDateStr) async {
    if (_isRunning || !_burstModeEnabled || !DioClient.isLoggedIn) return;
    final session = DioClient.sessionKey;
    _isRunning = true;
    _runningStartTime = DateTime.now();
    _statusMessage = '正在等待论坛进入目标签到日...';
    notifyListeners();
    final deadline = DateTime.now()
        .add(Duration(seconds: _burstPreSeconds + _burstPostSeconds + 5));
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (session != DioClient.sessionKey ||
            !DioClient.isLoggedIn ||
            !_burstModeEnabled) {
          return;
        }
        if (serverTodayStr.compareTo(targetDateStr) < 0) {
          await Future<void>.delayed(
              Duration(milliseconds: _burstIntervalMs.clamp(100, 1000)));
          continue;
        }
        if (serverTodayStr != targetDateStr) return;
        if (_burstStrategy == BurstStrategy.statusPolling) {
          final readRevision = signWriteRevision;
          final header = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
          if (!_isCurrentStateRead(session, readRevision) ||
              serverTodayStr != targetDateStr) {
            return;
          }
          if (header.hasPersonalState && header.isSignedToday) {
            await markSignedToday(
              rank: header.mySignRank,
              continuousDays:
                  header.hasContinuousDays ? header.continuousDays : null,
              rewardIron: header.rewardIron,
              notify: false,
              expectedSession: session,
              expectedWriteRevision: readRevision,
            );
            return;
          }
        }
        final result = await KlpbbsApi.signIn();
        if (session != DioClient.sessionKey ||
            serverTodayStr != targetDateStr) {
          return;
        }
        if (result.confirmed) {
          await _recordSuccess(targetDateStr, result, expectedSession: session);
        } else {
          _statusMessage = '零点签到未完成：${result.message}';
        }
        return;
      }
      _statusMessage = '零点签到等待窗口结束，请刷新当前状态';
    } catch (error) {
      if (session != DioClient.sessionKey) return;
      _statusMessage = '零点签到暂不可用：$error';
      final outage = ServerOutageInfo.tryParse(error);
      if (outage != null) notifyServerOutage(outage, source: '零点签到');
    } finally {
      if (session == DioClient.sessionKey) {
        _isRunning = false;
        _runningStartTime = null;
        notifyListeners();
      }
    }
  }

  Future<void> _executeScheduledSign() =>
      checkAndAutoSignIn(triggerSource: '定时签到', force: false);

  /// 后台持续向服务端网页刷新状态并同步：若未签则自动签到，若已签则校准数据
  Future<void> _syncAndVerifyWithServer(String todayStr,
      {bool allowAuto = true}) async {
    if (!DioClient.isLoggedIn || _isRunning) return;
    final session = DioClient.sessionKey;
    final readRevision = signWriteRevision;
    try {
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
      if (!_isCurrentStateRead(session, readRevision)) return;
      if (!info.hasPersonalState) return;
      if (info.isSignedToday) {
        await markSignedToday(
          rank: info.mySignRank,
          continuousDays: info.hasContinuousDays ? info.continuousDays : null,
          rewardIron: info.rewardIron,
          notify: false,
          expectedSession: session,
          expectedWriteRevision: readRevision,
        );
      } else {
        await markUnsignedToday(
            expectedSession: session, expectedWriteRevision: readRevision);
        if (!_isCurrentStateRead(session, readRevision)) return;
        if (allowAuto && _autoSignOnLaunch) {
          // 定时与零点任务由各自的调度器执行；同步状态不提前执行它们。
          checkAndAutoSignIn(triggerSource: '后台巡检未签到自动打卡', force: true);
        }
      }
      if (!_isCurrentStateRead(session, readRevision)) return;
      if (info.retroSignDays > 0) {
        unawaited(_handleRetroSignOpportunity(info,
            expectedSession: session, expectedWriteRevision: readRevision));
      }
    } catch (e) {
      if (!_isCurrentStateRead(session, readRevision)) return;
      final outage = ServerOutageInfo.tryParse(e);
      if (outage != null) {
        notifyServerOutage(outage, source: '后台巡检');
      }
    }
  }

  /// 检查并执行自动签到（启动/手动触发）
  Future<void> checkAndAutoSignIn(
      {String triggerSource = '自动签到', bool force = false}) async {
    if (!DioClient.isLoggedIn || _isRunning || (isSignedToday() && !force)) {
      return;
    }
    final session = DioClient.sessionKey;
    final readRevision = signWriteRevision;
    final now = DateTime.now();
    if (!force &&
        _lastCheckTime != null &&
        now.difference(_lastCheckTime!).inMinutes < 3) {
      return;
    }
    _lastCheckTime = now;
    _isRunning = true;
    _runningStartTime = now;
    _statusMessage = '$triggerSource正在检测...';
    notifyListeners();
    try {
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: false);
      if (!_isCurrentStateRead(session, readRevision)) return;
      if (!info.hasPersonalState) throw StateError('未取得账号签到状态，请稍后刷新');
      if (info.isSignedToday) {
        await markSignedToday(
            rank: info.mySignRank,
            continuousDays: info.hasContinuousDays ? info.continuousDays : null,
            rewardIron: info.rewardIron,
            notify: false,
            expectedSession: session,
            expectedWriteRevision: readRevision);
        return;
      }
      final targetDate = serverTodayStr;
      final result = await KlpbbsApi.signIn(fastMode: true);
      if (session != DioClient.sessionKey) return;
      if (targetDate != serverTodayStr) {
        _statusMessage = '日期已变更，请刷新签到状态';
        return;
      }
      if (result.confirmed) {
        await _recordSuccess(targetDate, result,
            headerInfo: info, expectedSession: session);
      } else {
        _statusMessage = '签到未完成：${result.message}';
      }
    } catch (error) {
      if (session != DioClient.sessionKey) return;
      _statusMessage = '签到暂不可用：$error';
      final outage = ServerOutageInfo.tryParse(error);
      if (outage != null) notifyServerOutage(outage, source: triggerSource);
    } finally {
      if (session == DioClient.sessionKey) {
        _isRunning = false;
        _runningStartTime = null;
        notifyListeners();
      }
    }
  }

  Future<void> _recordSuccess(
    String targetDateStr,
    DiscuzSignResult result, {
    SignHeaderInfo? headerInfo,
    String? expectedSession,
  }) async {
    final session = expectedSession ?? DioClient.sessionKey;
    if (!result.confirmed ||
        session != DioClient.sessionKey ||
        !DioClient.isLoggedIn ||
        targetDateStr != serverTodayStr) {
      return;
    }
    int? number(dynamic value) =>
        value is int ? value : int.tryParse(value?.toString() ?? '');
    await markSignedToday(
      rank: number(result.rank) ?? headerInfo?.mySignRank,
      continuousDays: number(result.continuousDays),
      rewardIron: result.rewardIron?.toString(),
      rewardExp: result.rewardExp?.toString(),
      notify: result.success && _notifyOnResult,
      submittedSuccessfully: result.success,
      expectedSession: session,
      expectedDay: targetDateStr,
    );
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

    final rankBodyText = hasRank ? '今日排名：第 $rank 名\n' : '';
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

  /// 检查读取接口与时钟；诊断不执行签到。
  Future<String> runBurstDiagnosticTest() async {
    if (!DioClient.isLoggedIn) return '请先登录苦力怕论坛账号';
    if (_isRunning) return '当前已有签到任务正在运行，请稍候';
    final session = DioClient.sessionKey;
    final stopwatch = Stopwatch()..start();
    try {
      final header = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
      if (session != DioClient.sessionKey) return '账号已切换，请重新诊断';
      final latency = stopwatch.elapsedMilliseconds;
      final offset = await KlpbbsApi.pingServerTime();
      if (session != DioClient.sessionKey) return '账号已切换，请重新诊断';
      final state = !header.hasPersonalState
          ? '网站未提供可确认的个人状态'
          : header.isSignedToday
              ? '今日已签到'
              : '今日未签到';
      return '签到页面读取：${latency}ms\n状态：$state\n论坛时钟偏差：${offset?.toString() ?? '未知'}ms\n诊断完成，未执行签到操作。';
    } catch (error) {
      return '读取诊断失败：$error';
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
    buffer.writeln(
        '探测状态：${_isProbingRecovery ? "🟢 正在探测中(第$_recoveryProbeCount次)" : "⚪ 待命中(无活跃宕机)"}');
    if (_lastOutageInfo != null) {
      buffer.writeln(
          '最近异常：HTTP ${_lastOutageInfo!.statusCode} (${_lastOutageInfo!.title})');
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
        buffer.writeln(
            '\n💡 结论：论坛服务器处于健康在线状态。若此前遭遇 502/503 宕机，恢复探测器将在此刻毫秒级触发即刻打卡！');
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

  /// 自动检测补签机会并主动提醒用户（绝不自动消耗用户的补签卡，交由用户自主支配）
  Future<void> _handleRetroSignOpportunity(SignHeaderInfo info,
      {required String expectedSession,
      required int expectedWriteRevision}) async {
    final session = expectedSession;
    if (info.retroSignDays <= 0 ||
        !_isCurrentStateRead(session, expectedWriteRevision)) {
      return;
    }
    final warningKey = _stateKey('retro_sign_last_warn_date');
    try {
      // 仅向用户推送断签提醒通知，绝不自动消耗道具，由用户完全自主决定是否使用补签卡
      final todayStr = serverTodayStr;
      final sp = await SharedPreferences.getInstance();
      if (!_isCurrentStateRead(session, expectedWriteRevision)) return;
      final lastWarnDate = sp.getString(warningKey) ?? '';
      if (lastWarnDate != todayStr && _notifyOnResult) {
        await sp.setString(warningKey, todayStr);
        if (!_isCurrentStateRead(session, expectedWriteRevision)) return;
        PushNotificationService.instance.pushCustomNotification(
          title: '⚠️ 苦力怕论坛 · 断签提醒',
          body: '检测到您有 ${info.retroSignDays} 天断签可补签！前往签到中心可使用【补签卡】挽回连续天数。',
        );
      }
    } catch (_) {}
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
