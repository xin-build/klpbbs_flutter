/// 轻量级内存预加载服务
/// 仅预加载并缓存结构化数据或文本，不加载图片资源
class PreloadService {
  PreloadService._();
  static final PreloadService instance = PreloadService._();

  // 内存 LRU 缓存，最多缓存 60 条分页数据
  final _cache = <String, dynamic>{};
  static const int _maxEntries = 60;

  /// 存入预加载缓存
  void set(String key, dynamic data) {
    if (data == null) return;
    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = data;
  }

  /// 获取预加载缓存（如果命中则返回并提升至最近使用）
  T? get<T>(String key) {
    if (!_cache.containsKey(key)) return null;
    final value = _cache.remove(key);
    _cache[key] = value;
    return value is T ? value : null;
  }

  /// 检查是否已有缓存
  bool has(String key) => _cache.containsKey(key);

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
}
