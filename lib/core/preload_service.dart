import 'dart:async';

class PreloadCacheChange {
  final Set<String> keys;
  final bool clearsAll;
  PreloadCacheChange(Iterable<String> keys, {this.clearsAll = false})
      : keys = Set.unmodifiable(keys);
}

class _CacheEntry {
  dynamic data;
  final DateTime timestamp;
  final Duration? ttl;

  _CacheEntry(this.data, {this.ttl}) : timestamp = DateTime.now();

  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(timestamp) > ttl!;
  }
}

/// 高性能内存与 SWR（Stale-While-Revalidate）预加载缓存服务
/// 为首页、版块树、帖子列表、用户主页等提供毫秒级秒开和静默更新（兼顾长期离线缓存与主动刷新实时性）
class PreloadService {
  PreloadService._();
  static final PreloadService instance = PreloadService._();

  // 内存 LRU 缓存，最多缓存 350 条分页/版块/用户信息数据
  final _cache = <String, _CacheEntry>{};
  final _inFlight = <String, Future<dynamic>>{};
  final _changes = StreamController<PreloadCacheChange>.broadcast();

  /// Preview cards subscribe to their own data keys; live pages keep their
  /// current scroll/tab state and are never globally refreshed by this stream.
  Stream<PreloadCacheChange> get changes => _changes.stream;
  int _generation = 0;
  static const int _maxEntries = 350;

  // 跨页面共享的 ThreadSummary 实体池（导读、版块、搜索、详情页复用，杜绝重复抓取）
  final _threadSummaryPool = <int, dynamic>{};

  /// 注册/更新共享帖子元数据（将帖子信息存入全局缓存池）
  void saveThreadSummary(int tid, dynamic summary) {
    if (tid <= 0 || summary == null) return;
    if (_threadSummaryPool.length >= 600) {
      _threadSummaryPool.remove(_threadSummaryPool.keys.first);
    }
    _threadSummaryPool[tid] = summary;
  }

  /// 获取共享帖子元数据
  T? getThreadSummary<T>(int tid) {
    final s = _threadSummaryPool[tid];
    return s is T ? s : null;
  }

  /// 存入预加载缓存，支持指定 TTL（有效时长）
  void set(String key, dynamic data, {Duration? ttl}) {
    if (data == null) return;
    final previous = _cache[key]?.data;
    _cache.remove(key);
    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CacheEntry(data, ttl: ttl ?? const Duration(minutes: 5));
    if (!identical(previous, data)) _changes.add(PreloadCacheChange([key]));
  }

  /// Enrich a cached record without extending its original freshness window.
  /// A separately resolved avatar must not refresh old personal sign state.
  bool update<T>(String key, T Function(T value) updater) {
    final entry = _cache[key];
    if (entry == null || entry.data is! T) return false;
    entry.data = updater(entry.data as T);
    _changes.add(PreloadCacheChange([key]));
    return true;
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
  void remove(String key) {
    _generation++;
    _cache.remove(key);
    _inFlight.remove(key);
    _changes.add(PreloadCacheChange([key]));
  }

  /// 清除指定前缀缓存或全部
  void clear([String? prefix]) {
    _generation++;
    final affected = _cache.keys
        .where((key) => prefix == null || key.startsWith(prefix))
        .toList();
    _inFlight.removeWhere((key, _) => prefix == null || key.startsWith(prefix));
    if (prefix == null) {
      _cache.clear();
      _threadSummaryPool.clear();
    } else {
      _cache.removeWhere((k, _) => k.startsWith(prefix));
    }
    // Cards may retain an expired snapshot after LRU eviction. An explicit
    // full clear must also invalidate those snapshots, including absent keys.
    _changes.add(PreloadCacheChange(affected, clearsAll: prefix == null));
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
        final generation = _generation;
        unawaited(
          _fetchOnce<T>(key, fetcher, ttl: ttl).then((freshData) {
            if (generation == _generation && has(key)) {
              onBackgroundUpdated?.call(freshData);
            }
          }).catchError((_) {}),
        );
      }
      return cached;
    }

    // 未命中缓存，直接等待网络请求
    return _fetchOnce<T>(key, fetcher, ttl: ttl);
  }

  Future<T> _fetchOnce<T>(String key, Future<T> Function() fetcher,
      {Duration? ttl}) async {
    final pending = _inFlight[key];
    if (pending != null) return await pending as T;
    final generation = _generation;
    final future = Future<T>.sync(fetcher);
    _inFlight[key] = future;
    try {
      final data = await future;
      if (generation == _generation) set(key, data, ttl: ttl);
      return data;
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }
}
