import 'dart:async';

class _CacheEntry {
  final dynamic data;
  final DateTime timestamp;
  final Duration? ttl;

  _CacheEntry(this.data, {this.ttl}) : timestamp = DateTime.now();

  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(timestamp) > ttl!;
  }
}

/// 高性能内存与 SWR（Stale-While-Revalidate）预加载缓存服务
/// 为首页、版块树、帖子列表、用户主页等提供毫秒级秒开和静默更新
class PreloadService {
  PreloadService._();
  static final PreloadService instance = PreloadService._();

  // 内存 LRU 缓存，最多缓存 120 条分页/版块/用户信息数据
  final _cache = <String, _CacheEntry>{};
  static const int _maxEntries = 120;

  /// 存入预加载缓存，支持指定 TTL（有效时长）
  void set(String key, dynamic data, {Duration? ttl}) {
    if (data == null) return;
    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CacheEntry(data, ttl: ttl);
  }

  /// 获取预加载缓存（如果命中则提升至最近使用）
  /// [ignoreExpired]: 为 true 时允许返回已过期但仍可用于秒开展示的陈旧数据
  T? get<T>(String key, {bool ignoreExpired = false}) {
    if (!_cache.containsKey(key)) return null;
    final entry = _cache.remove(key)!;
    _cache[key] = entry; // 刷新 LRU 顺位
    if (!ignoreExpired && entry.isExpired) {
      return null;
    }
    final value = entry.data;
    return value is T ? value : null;
  }

  /// 检查是否已有有效缓存
  bool has(String key, {bool allowExpired = false}) {
    final entry = _cache[key];
    if (entry == null) return false;
    return allowExpired || !entry.isExpired;
  }

  /// 移除指定缓存
  void remove(String key) => _cache.remove(key);

  /// 清除指定前缀缓存或全部
  void clear([String? prefix]) {
    if (prefix == null) {
      _cache.clear();
    } else {
      _cache.removeWhere((k, _) => k.startsWith(prefix));
    }
  }

  /// SWR（Stale-While-Revalidate）优先返回缓存，后台静默联网刷新
  Future<T> getOrFetch<T>(
    String key,
    Future<T> Function() fetcher, {
    Duration? ttl,
    void Function(T data)? onBackgroundUpdated,
  }) async {
    final cached = get<T>(key, ignoreExpired: true);
    final entry = _cache[key];
    final isStale = entry == null || entry.isExpired;

    if (cached != null) {
      // 命中缓存，若缓存已过期或无 TTL，在后台静默发起网络请求更新
      if (isStale) {
        unawaited(
          fetcher().then((freshData) {
            set(key, freshData, ttl: ttl);
            onBackgroundUpdated?.call(freshData);
          }).catchError((_) {}),
        );
      }
      return cached;
    }

    // 未命中缓存，直接等待网络请求
    final freshData = await fetcher();
    set(key, freshData, ttl: ttl);
    return freshData;
  }
}
