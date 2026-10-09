import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../core/rgb_theme_policy.dart';

export '../core/rgb_theme_policy.dart' show RgbMode, RgbQuality;

/// Configuration changes and hue updates have separate notification paths.
/// Only the local Theme scope and color preview listen to the hue clock.
class RgbThemeService extends ChangeNotifier with WidgetsBindingObserver {
  static final RgbThemeService instance = RgbThemeService._();
  RgbThemeService._();

  static const String _keyUnlocked = 'rgb_theme_unlocked';
  static const String _keyEnabled = 'rgb_theme_enabled';
  static const String _keySpeed = 'rgb_theme_speed';
  static const String _keyMode = 'rgb_theme_mode';
  static const String _keyQuality = 'rgb_theme_quality';
  static const int paletteAnchorCount = 24;

  final hueNotifier = ValueNotifier<int>(0);
  final _lightSchemes =
      BoundedValueCache<int, ColorScheme>(capacity: paletteAnchorCount);
  final _darkSchemes =
      BoundedValueCache<int, ColorScheme>(capacity: paletteAnchorCount);
  final _oledSchemes =
      BoundedValueCache<int, ColorScheme>(capacity: paletteAnchorCount);
  final _clock = Stopwatch();

  bool _initialized = false;
  bool _isUnlocked = false;
  bool _isEnabled = false;
  bool _manuallyPaused = false;
  bool _lifecycleVisible = true;
  bool _reducedMotion = false;
  double _speed = 1.0;
  double _phaseHue = 0;
  RgbMode _mode = RgbMode.flow;
  RgbQuality _quality = RgbQuality.balanced;
  Timer? _timer;
  Duration? _timerInterval;
  LinearGradient? _lastGradient;
  int? _gradientHue;
  ColorScheme? _lastLight;
  int? _lightHue;
  ColorScheme? _lastDark;
  int? _darkHue;
  bool? _darkOled;

  bool get isUnlocked => _isUnlocked;
  bool get isEnabled => _isEnabled;
  bool get isAnimating => _timer?.isActive ?? false;
  bool get isSuspended =>
      !_lifecycleVisible || _manuallyPaused || _reducedMotion;
  bool get reducedMotion => _reducedMotion;
  double get speed => _speed;
  RgbMode get mode => _mode;
  RgbQuality get quality => _quality;
  Duration get refreshInterval => _quality.interval;
  double get currentHue => currentHueIndex.toDouble();
  int get currentHueIndex => hueNotifier.value;
  int get schemeCacheEntries =>
      _lightSchemes.length + _darkSchemes.length + _oledSchemes.length;

  String get statusDescription {
    if (!_isEnabled) return '炫彩已关闭';
    if (_reducedMotion) return '减少动画已开启，保留当前静态颜色';
    if (!_lifecycleVisible || _manuallyPaused) return '窗口在后台，颜色更新已暂停';
    return _quality.description;
  }

  static Color _hueColor(double hue) =>
      HSVColor.fromAHSV(1, hue, .75, .95).toColor();

  Color get currentColor => _hueColor(currentHue);
  Color get secondaryColor => _hueColor((currentHue + 60) % 360);

  LinearGradient get rainbowGradient {
    if (_lastGradient == null || _gradientHue != currentHueIndex) {
      _gradientHue = currentHueIndex;
      _lastGradient = LinearGradient(
        colors: [
          currentColor,
          secondaryColor,
          _hueColor((currentHue + 120) % 360),
          _hueColor((currentHue + 180) % 360),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    return _lastGradient!;
  }

  ColorScheme _interpolatedScheme(BoundedValueCache<int, ColorScheme> cache,
      ColorScheme Function(Color seed) create) {
    const anchorDegrees = 360 / paletteAnchorCount;
    final position = currentHue / anchorDegrees;
    final lower = position.floor();
    final upper = (lower + 1) % paletteAnchorCount;
    ColorScheme anchor(int index) => cache.getOrCreate(
        index, () => create(_hueColor(index * anchorDegrees)));
    return ColorScheme.lerp(anchor(lower), anchor(upper), position - lower);
  }

  /// CAM16 seed calculations occur only at 24 reusable palette anchors.
  ColorScheme getLightColorScheme() {
    if (_lastLight == null || _lightHue != currentHueIndex) {
      _lightHue = currentHueIndex;
      _lastLight = _interpolatedScheme(
          _lightSchemes,
          (seed) => ColorScheme.fromSeed(
              seedColor: seed, brightness: Brightness.light));
    }
    return _lastLight!;
  }

  ColorScheme getDarkColorScheme({required bool isOled}) {
    if (_lastDark == null ||
        _darkHue != currentHueIndex ||
        _darkOled != isOled) {
      _darkHue = currentHueIndex;
      _darkOled = isOled;
      _lastDark =
          _interpolatedScheme(isOled ? _oledSchemes : _darkSchemes, (seed) {
        final base =
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
        return base.copyWith(
          surface: isOled ? Colors.black : const Color(0xFF151917),
          surfaceContainerLowest:
              isOled ? Colors.black : const Color(0xFF101312),
          surfaceContainerLow:
              isOled ? const Color(0xFF0C0E0D) : const Color(0xFF171B19),
          surfaceContainer:
              isOled ? const Color(0xFF141715) : const Color(0xFF1E2320),
          surfaceContainerHigh:
              isOled ? const Color(0xFF1C201E) : const Color(0xFF252B28),
          surfaceContainerHighest:
              isOled ? const Color(0xFF242927) : const Color(0xFF2D3430),
          outlineVariant:
              isOled ? const Color(0xFF323A35) : const Color(0xFF3A443E),
        );
      });
    }
    return _lastDark!;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    AppConfig.instance.addListener(_syncMotionPreference);
    _lifecycleVisible = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    try {
      final sp = await SharedPreferences.getInstance();
      _isUnlocked = sp.getBool(_keyUnlocked) ?? false;
      _isEnabled = sp.getBool(_keyEnabled) ?? false;
      _speed = RgbThemePolicy.validSpeed(sp.getDouble(_keySpeed) ?? 1.0);
      final modeName = sp.getString(_keyMode);
      _mode = RgbMode.values.firstWhere((mode) => mode.name == modeName,
          orElse: () => RgbMode.flow);
      final qualityName = sp.getString(_keyQuality);
      _quality = RgbQuality.values.firstWhere(
          (quality) => quality.name == qualityName,
          orElse: () => RgbQuality.balanced);
    } catch (_) {}
    _syncMotionPreference();
    _updateTimer();
    notifyListeners();
  }

  void _syncMotionPreference() {
    final reduced = AppConfig.reduceMotion ||
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    if (_reducedMotion == reduced) return;
    _reducedMotion = reduced;
    _updateTimer();
    notifyListeners();
  }

  @override
  void didChangeAccessibilityFeatures() => _syncMotionPreference();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (_lifecycleVisible == visible) return;
    _lifecycleVisible = visible;
    _updateTimer();
    notifyListeners();
  }

  /// The tray/window pause cannot be cleared by enabling or changing a mode.
  void pause() {
    if (_manuallyPaused) return;
    _manuallyPaused = true;
    _updateTimer();
    notifyListeners();
  }

  void resume() {
    if (!_manuallyPaused) return;
    _manuallyPaused = false;
    _updateTimer();
    notifyListeners();
  }

  Future<void> unlock() async {
    _isUnlocked = true;
    _isEnabled = true;
    _updateTimer();
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_keyUnlocked, true);
      await sp.setBool(_keyEnabled, true);
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    _updateTimer();
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_keyEnabled, enabled);
    } catch (_) {}
  }

  void _capturePhase() {
    if (_clock.isRunning) _tick();
    _phaseHue = currentHue;
    _clock.reset();
  }

  Future<void> setMode(RgbMode mode) async {
    if (_mode == mode) return;
    _capturePhase();
    _mode = mode;
    _updateTimer();
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keyMode, mode.name);
    } catch (_) {}
  }

  Future<void> setSpeed(double speed) async {
    final value = RgbThemePolicy.validSpeed(speed);
    if (_speed == value) return;
    _capturePhase();
    _speed = value;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_keySpeed, value);
    } catch (_) {}
  }

  Future<void> setQuality(RgbQuality quality) async {
    if (_quality == quality) return;
    _quality = quality;
    _updateTimer();
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keyQuality, quality.name);
    } catch (_) {}
  }

  bool get _shouldAnimate => RgbThemePolicy.shouldAnimate(
      enabled: _isEnabled,
      visible: _lifecycleVisible,
      manuallyPaused: _manuallyPaused,
      reduceMotion: _reducedMotion);

  void _updateTimer() {
    if (!_shouldAnimate) {
      _stopTimer();
      return;
    }
    if (_timer?.isActive == true && _timerInterval == refreshInterval) return;
    _timer?.cancel();
    _timerInterval = refreshInterval;
    _clock.start();
    _timer = Timer.periodic(refreshInterval, (_) => _tick());
  }

  void _tick() {
    if (!_shouldAnimate) {
      _stopTimer();
      return;
    }
    final hue = RgbThemePolicy.hueAt(
        startHue: _phaseHue,
        elapsed: _clock.elapsed,
        speed: _speed,
        mode: _mode);
    if (hue != currentHueIndex) hueNotifier.value = hue;
  }

  void stopTimer() => pause();

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _timerInterval = null;
    _clock.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppConfig.instance.removeListener(_syncMotionPreference);
    _stopTimer();
    hueNotifier.dispose();
    super.dispose();
  }
}
