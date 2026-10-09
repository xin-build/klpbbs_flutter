import 'package:flutter/foundation.dart';

/// 全局版块收藏状态事件与通知中心
/// 用于在任何页面收藏/取消收藏版块时，通知所有相关页面（版块树、收藏列表、首页快捷、版块列表）即时刷新数据
class ForumFavoriteNotifier extends ChangeNotifier {
  ForumFavoriteNotifier._();
  static final ForumFavoriteNotifier instance = ForumFavoriteNotifier._();

  int? _lastChangedFid;
  bool? _lastIsFav;
  Set<int> _ids = {};
  Set<int> get ids => Set.unmodifiable(_ids);

  int? get lastChangedFid => _lastChangedFid;
  bool? get lastIsFav => _lastIsFav;

  void notifyFavoriteChanged(int fid, bool isFav) {
    _lastChangedFid = fid;
    _lastIsFav = isFav;
    if (isFav) { _ids.add(fid); } else { _ids.remove(fid); }
    notifyListeners();
  }

  void replace(Set<int> ids) {
    if (setEquals(_ids, ids)) return;
    _ids = Set.of(ids);
    _lastChangedFid = null;
    _lastIsFav = null;
    notifyListeners();
  }
}
