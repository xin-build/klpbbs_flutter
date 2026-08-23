import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RGB 运行模式
enum RgbMode {
  flow('流光幻彩', '色相平滑旋转流动，优雅自然'),
  strobe('超频迪斯科', '高频跳变爆闪，电竞狂暴光污染');

  final String label;
  final String description;
  const RgbMode(this.label, this.description);
}

/// 隐藏 RGB 动态炫彩主题服务（高性能优化版：零动态计算 + 360°颜色表缓存 + 双模式）
class RgbThemeService extends ChangeNotifier with WidgetsBindingObserver {
  static final RgbThemeService instance = RgbThemeService._();
  RgbThemeService._();

  static const String _keyUnlocked = 'rgb_theme_unlocked';
  static const String _keyEnabled = 'rgb_theme_enabled';
  static const String _keySpeed = 'rgb_theme_speed';
  static const String _keyMode = 'rgb_theme_mode';

  // 1. 预计算 360 度 HSV 颜色表（零浮点运算与零对象分配）
  static final List<Color> _hsvColors = List.generate(
    360,
    (h) => HSVColor.fromAHSV(1.0, h.toDouble(), 0.75, 0.95).toColor(),
    growable: false,
  );

  // 2. 渐变缓存池（360 个槽位，按需惰性生成并永久复用）
  static final List<LinearGradient?> _gradientCache = List.filled(360, null);

  // 3. ColorScheme 缓存池（360 个槽位，按需惰性生成并永久复用，避免循环调用昂贵的 Cam16 算法）
  static final List<ColorScheme?> _lightSchemeCache = List.filled(360, null);
  static final List<ColorScheme?> _darkBaseSchemeCache = List.filled(360, null);
  static final List<ColorScheme?> _darkNormalSchemeCache = List.filled(360, null);
  static final List<ColorScheme?> _darkOledSchemeCache = List.filled(360, null);

  bool _isUnlocked = false;
  bool _isEnabled = false;
  bool _isSuspended = false;
  double _speed = 1.0; // 0.5 ~ 3.0
  RgbMode _mode = RgbMode.flow;
  int _currentHueIndex = 0; // 0 ~ 359
  Timer? _timer;

  bool get isUnlocked => _isUnlocked;
  bool get isEnabled => _isEnabled;
  double get speed => _speed;
  RgbMode get mode => _mode;
  double get currentHue => _currentHueIndex.toDouble();
  int get currentHueIndex => _currentHueIndex;

  Color get currentColor => _hsvColors[_currentHueIndex];

  Color get secondaryColor => _hsvColors[(_currentHueIndex + 60) % 360];

  LinearGradient get rainbowGradient =>
      _gradientCache[_currentHueIndex] ??= LinearGradient(
        colors: [
          _hsvColors[_currentHueIndex],
          _hsvColors[(_currentHueIndex + 60) % 360],
          _hsvColors[(_currentHueIndex + 120) % 360],
          _hsvColors[(_currentHueIndex + 180) % 360],
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// 获取经过缓存的浅色 ColorScheme（零 CPU 消耗）
  ColorScheme getLightColorScheme() {
    return _lightSchemeCache[_currentHueIndex] ??= ColorScheme.fromSeed(
      seedColor: _hsvColors[_currentHueIndex],
      brightness: Brightness.light,
    );
  }

  /// 获取经过缓存的暗色/OLED ColorScheme（零 CPU 消耗）
  ColorScheme getDarkColorScheme({required bool isOled}) {
    if (isOled) {
      return _darkOledSchemeCache[_currentHueIndex] ??= () {
        final base = _darkBaseSchemeCache[_currentHueIndex] ??=
            ColorScheme.fromSeed(
          seedColor: _hsvColors[_currentHueIndex],
          brightness: Brightness.dark,
        );
        return base.copyWith(
          surface: Colors.black,
          surfaceContainerLowest: Colors.black,
          surfaceContainerLow: const Color(0xFF0C0E0D),
          surfaceContainer: const Color(0xFF141715),
          surfaceContainerHigh: const Color(0xFF1C201E),
          surfaceContainerHighest: const Color(0xFF242927),
          outlineVariant: const Color(0xFF323A35),
        );
      }();
    } else {
      return _darkNormalSchemeCache[_currentHueIndex] ??= () {
        final base = _darkBaseSchemeCache[_currentHueIndex] ??=
            ColorScheme.fromSeed(
          seedColor: _hsvColors[_currentHueIndex],
          brightness: Brightness.dark,
        );
        return base.copyWith(
          surface: const Color(0xFF151917),
          surfaceContainerLowest: const Color(0xFF101312),
          surfaceContainerLow: const Color(0xFF171B19),
          surfaceContainer: const Color(0xFF1E2320),
          surfaceContainerHigh: const Color(0xFF252B28),
          surfaceContainerHighest: const Color(0xFF2D3430),
          outlineVariant: const Color(0xFF3A443E),
        );
      }();
    }
  }

  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _isUnlocked = sp.getBool(_keyUnlocked) ?? false;
      _isEnabled = sp.getBool(_keyEnabled) ?? false;
      _speed = sp.getDouble(_keySpeed) ?? 1.0;
      final modeStr = sp.getString(_keyMode);
      if (modeStr != null) {
        _mode = RgbMode.values.firstWhere(
          (m) => m.name == modeStr,
          orElse: () => RgbMode.flow,
        );
      }

      // 注册系统生命周期监听，后台或息屏时挂起定时器
      WidgetsBinding.instance.addObserver(this);

      if (_isEnabled) {
        _startTimer();
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      pause();
    } else if (state == AppLifecycleState.resumed) {
      resume();
    }
  }

  /// 挂起 RGB 定时器（用于窗口最小化、托盘隐藏或处于后台时，实现 0% CPU 占用）
  void pause() {
    if (_isSuspended) return;
    _isSuspended = true;
    _stopTimer();
  }

  /// 恢复 RGB 定时器
  void resume() {
    _isSuspended = false;
    if (_isEnabled) {
      _startTimer();
    }
  }

  Future<void> unlock() async {
    _isUnlocked = true;
    _isEnabled = true;
    _isSuspended = false;
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
      _isSuspended = false;
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

  Future<void> setMode(RgbMode mode) async {
    _mode = mode;
    if (_isEnabled && !_isSuspended) {
      _startTimer();
    }
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keyMode, _mode.name);
    } catch (_) {}
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.2, 3.0);
    if (_isEnabled && !_isSuspended) {
      _startTimer();
    }
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_keySpeed, _speed);
    } catch (_) {}
  }

  void _startTimer() {
    _stopTimer();
    if (!_isEnabled || _isSuspended) return;

    if (_mode == RgbMode.strobe) {
      // 超频迪斯科模式：高频闪烁跳变（80ms 刷新周期，每次跳变 137° 黄金角色彩，产生极致震撼的爆闪视觉）
      final intervalMs = (100 / _speed).round().clamp(40, 200);
      _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
        _currentHueIndex = (_currentHueIndex + 137) % 360;
        notifyListeners();
      });
    } else {
      // 流光幻彩模式：平滑色相旋转流动（60ms 刷新周期，平滑步进）
      final intervalMs = (60 / _speed).round().clamp(30, 150);
      const step = 2;
      _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
        _currentHueIndex = (_currentHueIndex + step) % 360;
        notifyListeners();
      });
    }
  }

  void stopTimer() => _stopTimer();

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    super.dispose();
  }
}
