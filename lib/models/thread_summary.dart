/// 帖子条目（列表页 / 首页推荐 / 导读）
class ThreadSummary {
  final int tid;
  final int? fid;
  final int? uid;
  final String author;
  final String title;

  /// 标题前缀标签，如「原创」「转载」
  final String? badge;

  /// 摘要文本
  final String? excerpt;

  /// 封面图（相对 URL 已由解析器拼接为绝对 URL；无图时为 null）
  final String? coverUrl;

  /// 所属版块名，如「BE附加包」「闲聊讨论」
  final String? forumName;

  /// 主题分类名，如「文章」
  final String? typeName;

  /// 相对时间文本，如「4 天前」
  final String? timeText;

  /// 回复数/浏览量（-1 表示未知）
  final int replies;
  final int views;

  /// 是否热门（带热度图标/热度值）
  final bool isHot;

  /// 是否精华（「精」）
  final bool isDigest;

  /// 是否推荐（「荐」）
  final bool isRecommend;

  /// 推荐数（-1 表示无；0 表示有荐但无数值）
  final int recommendCount;

  /// 热度值（-1 表示无）
  final int heatCount;

  /// 是否置顶
  final bool isSticky;

  /// 主题图章（如「美图」「原创」「优秀」「精」「荐」）
  final String? stamp;

  /// 主题图章图标 URL（若有）
  final String? stampUrl;

  /// 作者头像挂件 URL（若有）
  final String? faceUrl;

  /// 收藏项 ID（我的收藏列表中使用）
  final int? favid;

  const ThreadSummary({
    required this.tid,
    this.fid,
    this.uid,
    required this.author,
    required this.title,
    this.badge,
    this.excerpt,
    this.coverUrl,
    this.forumName,
    this.typeName,
    this.timeText,
    this.replies = -1,
    this.views = -1,
    this.isHot = false,
    this.isDigest = false,
    this.isRecommend = false,
    this.recommendCount = -1,
    this.heatCount = -1,
    this.isSticky = false,
    this.stamp,
    this.stampUrl,
    this.faceUrl,
    this.favid,
  });

  ThreadSummary copyWith({
    int? tid,
    int? fid,
    int? uid,
    String? author,
    String? title,
    String? badge,
    String? excerpt,
    String? coverUrl,
    String? forumName,
    String? typeName,
    String? timeText,
    int? replies,
    int? views,
    bool? isHot,
    bool? isDigest,
    bool? isRecommend,
    int? recommendCount,
    int? heatCount,
    bool? isSticky,
    String? stamp,
    String? stampUrl,
    String? faceUrl,
    int? favid,
  }) {
    return ThreadSummary(
      tid: tid ?? this.tid,
      fid: fid ?? this.fid,
      uid: uid ?? this.uid,
      author: author ?? this.author,
      title: title ?? this.title,
      badge: badge ?? this.badge,
      excerpt: excerpt ?? this.excerpt,
      coverUrl: coverUrl ?? this.coverUrl,
      forumName: forumName ?? this.forumName,
      typeName: typeName ?? this.typeName,
      timeText: timeText ?? this.timeText,
      replies: replies ?? this.replies,
      views: views ?? this.views,
      isHot: isHot ?? this.isHot,
      isDigest: isDigest ?? this.isDigest,
      isRecommend: isRecommend ?? this.isRecommend,
      recommendCount: recommendCount ?? this.recommendCount,
      heatCount: heatCount ?? this.heatCount,
      isSticky: isSticky ?? this.isSticky,
      stamp: stamp ?? this.stamp,
      stampUrl: stampUrl ?? this.stampUrl,
      faceUrl: faceUrl ?? this.faceUrl,
      favid: favid ?? this.favid,
    );
  }
}
