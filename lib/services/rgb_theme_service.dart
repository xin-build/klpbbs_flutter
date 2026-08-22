import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 隐藏 RGB 动态炫彩主题服务（彩蛋解锁，平滑色相流动）
class RgbThemeService extends ChangeNotifier {
  static final RgbThemeService instance = RgbThemeService._();
  RgbThemeService._();

  static const String _keyUnlocked = 'rgb_theme_unlocked';
  static const String _keyEnabled = 'rgb_theme_enabled';
  static const String _keySpeed = 'rgb_theme_speed';

  bool _isUnlocked = false;
  bool _isEnabled = false;
  double _speed = 1.0; // 0.5 ~ 3.0
  double _currentHue = 0.0;
  Timer? _timer;

  bool get isUnlocked => _isUnlocked;
  bool get isEnabled => _isEnabled;
  double get speed => _speed;
  double get currentHue => _currentHue;

  Color get currentColor =>
      HSVColor.fromAHSV(1.0, _currentHue, 0.75, 0.95).toColor();

  Color get secondaryColor =>
      HSVColor.fromAHSV(1.0, (_currentHue + 60) % 360, 0.75, 0.95).toColor();

  LinearGradient get rainbowGradient => LinearGradient(
        colors: [
          HSVColor.fromAHSV(1.0, _currentHue, 0.8, 0.95).toColor(),
          HSVColor.fromAHSV(1.0, (_currentHue + 60) % 360, 0.8, 0.95).toColor(),
          HSVColor.fromAHSV(1.0, (_currentHue + 120) % 360, 0.8, 0.95).toColor(),
          HSVColor.fromAHSV(1.0, (_currentHue + 180) % 360, 0.8, 0.95).toColor(),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _isUnlocked = sp.getBool(_keyUnlocked) ?? false;
      _isEnabled = sp.getBool(_keyEnabled) ?? false;
      _speed = sp.getDouble(_keySpeed) ?? 1.0;
      if (_isEnabled) {
        _startTimer();
      }
    } catch (_) {}
  }

  Future<void> unlock() async {
    _isUnlocked = true;
    _isEnabled = true;
    _startTimer();
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_keyUnlocked, true);
      await sp.setBool(_keyEnabled, true);
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    if (_isEnabled) {
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

  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.2, 3.0);
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_keySpeed, _speed);
    } catch (_) {}
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _currentHue = (_currentHue + (_speed * 3.6)) % 360;
      notifyListeners();
    });
  }

  void stopTimer() => _stopTimer();

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
