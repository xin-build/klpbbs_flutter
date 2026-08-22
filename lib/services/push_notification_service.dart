import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';

/// 消息轮询间隔选项
enum PollingInterval {
  seconds30('30 秒 (高频即时)', 30),
  minute1('1 分钟 (标准轮询)', 60),
  minute2('2 分钟 (推荐平衡)', 120),
  minute5('5 分钟 (智能省流)', 300),
  minute10('10 分钟 (极简省电)', 600),
  minute15('15 分钟 (超低功耗)', 900),
  disabled('关闭后台轮询', 0);

  final String label;
  final int seconds;
  const PollingInterval(this.label, this.seconds);

  static PollingInterval fromSeconds(int sec) {
    return PollingInterval.values.firstWhere(
      (e) => e.seconds == sec,
      orElse: () => PollingInterval.minute2,
    );
  }
}

/// 苦力怕论坛 低功耗消息推送与后台监听服务
class PushNotificationService extends ChangeNotifier {
  static final PushNotificationService instance =
      PushNotificationService._();
  PushNotificationService._();

  static const String _keyInterval = 'msg_push_interval';
  static const String _keyEnabled = 'msg_push_enabled';
  static const String _keySound = 'msg_push_sound';

  PollingInterval _interval = PollingInterval.minute2;
  bool _enabled = true;
  bool _sound = true;
  int _lastUnreadCount = 0;
  int _currentUnreadCount = 0;
  Timer? _timer;
  bool _isChecking = false;

  int get unreadCount => _currentUnreadCount;
  bool get isEnabled => _enabled;
  bool get isSoundEnabled => _sound;
  PollingInterval get interval => _interval;

  VoidCallback? onOpenNoticeCallback;

  /// 清除当前未读计数（在进入消息提醒页或点击全部已读后调用）
  void clearUnread() {
    _currentUnreadCount = 0;
    _lastUnreadCount = 0;
    notifyListeners();
  }

  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final sec = sp.getInt(_keyInterval) ?? 120;
      _interval = PollingInterval.fromSeconds(sec);
      _enabled = sp.getBool(_keyEnabled) ?? true;
      _sound = sp.getBool(_keySound) ?? true;

      // 初始化桌面端系统通知接口
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        try {
          await localNotifier.setup(
            appName: '苦力怕论坛',
            shortcutPolicy: ShortcutPolicy.requireCreate,
          );
        } catch (_) {}
      }

      if (_enabled && _interval.seconds > 0) {
        _startTimer();
      }
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (_enabled && _interval.seconds > 0) {
      _startTimer();
    } else {
      _stopTimer();
    }
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_keyEnabled, enabled);
    } catch (_) {}
  }

  Future<void> setInterval(PollingInterval interval) async {
    _interval = interval;
    if (_enabled && _interval.seconds > 0) {
      _startTimer();
    } else {
      _stopTimer();
    }
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_keyInterval, interval.seconds);
    } catch (_) {}
  }

  Future<void> setSound(bool sound) async {
    _sound = sound;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_keySound, sound);
    } catch (_) {}
  }

  void _startTimer() {
    _stopTimer();
    if (_interval.seconds <= 0) return;
    _timer = Timer.periodic(Duration(seconds: _interval.seconds), (_) {
      checkNewMessages();
    });
    // 启动时立即执行一次静默探测
    checkNewMessages();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 执行低功耗增量检查（仅探测未读通知与短消息计数，不消耗大量流量，不强制置为已读）
  Future<int> checkNewMessages() async {
    if (_isChecking || !DioClient.isLoggedIn) return _currentUnreadCount;
    _isChecking = true;

    try {
      final summary = await KlpbbsApi.getUnreadSummary();
      _currentUnreadCount = summary.unreadNotices;
      notifyListeners();

      // 如果有新的未读消息且多于上次记录，触发系统级推送通知
      if (_currentUnreadCount > _lastUnreadCount && _currentUnreadCount > 0) {
        final newDiff = _currentUnreadCount - _lastUnreadCount;
        _dispatchSystemNotification(
          title: '苦力怕论坛 - 新消息提醒',
          body: newDiff > 0
              ? '您收到了 $newDiff 条新的论坛消息/提醒通知'
              : '您有 $_currentUnreadCount 条未读消息待查阅',
        );
      }
      _lastUnreadCount = _currentUnreadCount;
    } catch (_) {
    } finally {
      _isChecking = false;
    }

    return _currentUnreadCount;
  }

  /// 发送系统级原生通知
  Future<void> _dispatchSystemNotification({
    required String title,
    required String body,
  }) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        final notification = LocalNotification(
          title: title,
          body: body,
          silent: !_sound,
        );

        notification.onClick = () {
          onOpenNoticeCallback?.call();
        };

        await notification.show();
      } catch (_) {}
    }
  }

  /// 手动测试系统通知
  Future<void> testNotification() async {
    await _dispatchSystemNotification(
      title: '苦力怕论坛 - 测试通知',
      body: '系统消息推送功能正常，将以低功耗间歇式接收未读通知！',
    );
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
