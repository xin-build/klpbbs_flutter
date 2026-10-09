enum RgbMode {
  flow('流光幻彩', '颜色连续流动，适合日常使用'),
  strobe('跃变色彩', '按节奏切换颜色，减少动画时保持静态');

  final String label;
  final String description;
  const RgbMode(this.label, this.description);
}

/// These are theme update budgets, not screen frame-rate guarantees.
enum RgbQuality {
  powerSaving('节能', 250, '每秒最多 4 次主题更新，适合省电或多任务'),
  balanced('平衡', 125, '每秒最多 8 次主题更新，兼顾变化与开销'),
  smooth('流畅', 67, '每秒约 15 次主题更新，开销更高');

  final String label;
  final int intervalMilliseconds;
  final String description;
  const RgbQuality(this.label, this.intervalMilliseconds, this.description);

  Duration get interval => Duration(milliseconds: intervalMilliseconds);
}

class RgbThemePolicy {
  RgbThemePolicy._();

  static double validSpeed(double value) =>
      value.isFinite ? value.clamp(.2, 3.0) : 1.0;

  static bool shouldAnimate({
    required bool enabled,
    required bool visible,
    required bool manuallyPaused,
    required bool reduceMotion,
  }) =>
      enabled && visible && !manuallyPaused && !reduceMotion;

  /// A monotonic active-time clock keeps speed independent of update cadence.
  /// Suspended time is excluded by the caller's paused Stopwatch.
  static int hueAt({
    required double startHue,
    required Duration elapsed,
    required double speed,
    required RgbMode mode,
  }) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final progress = mode == RgbMode.flow
        ? seconds * 24 * validSpeed(speed)
        : (seconds * 4 * validSpeed(speed)).floor() * 137;
    return ((startHue + progress) % 360).floor();
  }
}

/// Small caches evict the least recently used entry rather than growing with
/// every hue, custom seed, density or system color scheme ever encountered.
class BoundedValueCache<K, V> {
  final int capacity;
  final Map<K, V> _entries = {};

  BoundedValueCache({required this.capacity}) : assert(capacity > 0);

  int get length => _entries.length;

  V getOrCreate(K key, V Function() create) {
    if (_entries.containsKey(key)) {
      final value = _entries.remove(key) as V;
      _entries[key] = value;
      return value;
    }
    final value = create();
    _entries[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return value;
  }

  void clear() => _entries.clear();
}
