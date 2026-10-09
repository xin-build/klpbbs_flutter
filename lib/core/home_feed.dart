import '../models/thread_summary.dart';

enum HomeFeed {
  recommended('推荐', null),
  following('我关注的', 'follow'),
  latest('最新发表', 'newthread'),
  replies('最近回复', 'new'),
  hot('热门', 'hot'),
  digest('精华', 'digest'),
  sofa('抢沙发', 'sofa');

  final String label;
  final String? guideView;
  const HomeFeed(this.label, this.guideView);

  String get description => switch (this) {
        HomeFeed.recommended => '首页主题流',
        HomeFeed.following => '关注用户的主题动态',
        HomeFeed.latest => '按发表时间浏览新主题',
        HomeFeed.replies => '按最新回复时间浏览',
        HomeFeed.hot => '论坛热门主题',
        HomeFeed.digest => '论坛精选精华主题',
        HomeFeed.sofa => '等待首条回复的主题',
      };
}

/// Each source keeps its own pages and scroll position; preview count is not a
/// total and failed refreshes do not erase the last successfully read list.
class HomeFeedState {
  List<ThreadSummary>? initial;
  List<ThreadSummary> more = [];
  int page = 1;
  bool hasMore = true, loadingMore = false, loading = false;
  String? error;
  double scrollOffset = 0;
  Future<void>? pending;
  int revision = 0;

  /// A fresh first page invalidates earlier pagination responses, including
  /// requests that could finish during a failed refresh.
  int beginRefresh() {
    loading = true;
    loadingMore = false;
    error = null;
    return ++revision;
  }

  bool accepts(int requestRevision) => requestRevision == revision;
}
