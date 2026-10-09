/// 本版积分规则条目模型
class ForumCreditRule {
  final String action; // 动作名称，例如：发新主题、发表回复、设为精华、删帖、悬赏最佳
  final String cycle; // 奖励周期，例如：每天、一次、不限
  final String maxDaily; // 每天最高次数，例如：10次、20次、不限
  final String exp; // 经验变动，例如：+2、+1、+10、-5
  final String iron; // 铁粒变动，例如：+1、+0、+10、-3
  final String tribute; // 贡献变动，例如：+1、0
  /// 按网站实际表头顺序保留所有列，包含站点新增的积分类型。
  final Map<String, String> columns;

  const ForumCreditRule({
    required this.action,
    this.cycle = '',
    this.maxDaily = '',
    this.exp = '',
    this.iron = '',
    this.tribute = '',
    this.columns = const {},
  });
}

/// 版块顶部导览、Banner、统计信息与版规/积分规则模型（1:1 精准还原 Discuz 网页版版块头部）
class ForumHeaderInfo {
  final int fid;
  final String name;
  final String? bannerUrl;
  final int todayPosts;
  final int threadsCount;
  final int postsCount;
  final int rank;
  final int favCount;
  final bool hasTodayPosts,
      hasThreadsCount,
      hasPostsCount,
      hasRank,
      hasFavCount;
  final Map<String, String> displayValues;
  final String moderators;
  final String rulesHtml;
  final List<ForumCreditRule> creditRules;
  final bool isFavorited;

  const ForumHeaderInfo({
    required this.fid,
    required this.name,
    this.bannerUrl,
    int? todayPosts,
    int? threadsCount,
    int? postsCount,
    int? rank,
    int? favCount,
    this.displayValues = const {},
    this.moderators = '',
    this.rulesHtml = '',
    this.creditRules = const [],
    this.isFavorited = false,
  })  : todayPosts = todayPosts ?? 0,
        threadsCount = threadsCount ?? 0,
        postsCount = postsCount ?? 0,
        rank = rank ?? 0,
        favCount = favCount ?? 0,
        hasTodayPosts = todayPosts != null,
        hasThreadsCount = threadsCount != null,
        hasPostsCount = postsCount != null,
        hasRank = rank != null,
        hasFavCount = favCount != null;

  String displayCount(String metric) {
    final value = switch (metric) {
      'today' => hasTodayPosts ? todayPosts : null,
      'topics' => hasThreadsCount ? threadsCount : null,
      'posts' => hasPostsCount ? postsCount : null,
      'rank' => hasRank ? rank : null,
      'favorites' => hasFavCount ? favCount : null,
      _ => null,
    };
    return value == null ? '—' : displayValues[metric] ?? '$value';
  }

  bool get isEmpty =>
      (bannerUrl == null || bannerUrl!.isEmpty) &&
      !hasTodayPosts &&
      !hasThreadsCount &&
      !hasPostsCount &&
      moderators.isEmpty &&
      rulesHtml.isEmpty &&
      creditRules.isEmpty;

  ForumHeaderInfo copyWith({
    int? fid,
    String? name,
    String? bannerUrl,
    int? todayPosts,
    int? threadsCount,
    int? postsCount,
    int? rank,
    int? favCount,
    Map<String, String>? displayValues,
    String? moderators,
    String? rulesHtml,
    List<ForumCreditRule>? creditRules,
    bool? isFavorited,
  }) {
    final displays = displayValues ?? {...this.displayValues};
    if (displayValues == null) {
      if (todayPosts != null) displays.remove('today');
      if (threadsCount != null) displays.remove('topics');
      if (postsCount != null) displays.remove('posts');
      if (rank != null) displays.remove('rank');
      if (favCount != null) displays.remove('favorites');
    }
    return ForumHeaderInfo(
      fid: fid ?? this.fid,
      name: name ?? this.name,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      todayPosts: todayPosts ?? (hasTodayPosts ? this.todayPosts : null),
      threadsCount:
          threadsCount ?? (hasThreadsCount ? this.threadsCount : null),
      postsCount: postsCount ?? (hasPostsCount ? this.postsCount : null),
      rank: rank ?? (hasRank ? this.rank : null),
      favCount: favCount ?? (hasFavCount ? this.favCount : null),
      displayValues: displays,
      moderators: moderators ?? this.moderators,
      rulesHtml: rulesHtml ?? this.rulesHtml,
      creditRules: creditRules ?? this.creditRules,
      isFavorited: isFavorited ?? this.isFavorited,
    );
  }
}
