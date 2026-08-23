/// 苦力怕论坛全站统计数据模型（今日发帖 / 昨日发帖 / 全站总帖 / 注册会员）
class SiteStats {
  final int todayPosts;
  final int yesterdayPosts;
  final int totalPosts;
  final int totalMembers;

  const SiteStats({
    this.todayPosts = 0,
    this.yesterdayPosts = 0,
    this.totalPosts = 0,
    this.totalMembers = 0,
  });

  /// 是否为包含全部指标的完整统计数据（避免将版块局部今日帖数误判为全站统计）
  bool get isComplete =>
      totalPosts > 0 &&
      totalMembers > 0 &&
      (todayPosts > 0 || yesterdayPosts > 0);

  bool get isEmpty =>
      todayPosts == 0 &&
      yesterdayPosts == 0 &&
      totalPosts == 0 &&
      totalMembers == 0;

  Map<String, dynamic> toJson() => {
    'todayPosts': todayPosts,
    'yesterdayPosts': yesterdayPosts,
    'totalPosts': totalPosts,
    'totalMembers': totalMembers,
  };

  factory SiteStats.fromJson(Map<String, dynamic> json) => SiteStats(
    todayPosts: json['todayPosts'] as int? ?? 0,
    yesterdayPosts: json['yesterdayPosts'] as int? ?? 0,
    totalPosts: json['totalPosts'] as int? ?? 0,
    totalMembers: json['totalMembers'] as int? ?? 0,
  );

  @override
  String toString() =>
      'SiteStats(today: $todayPosts, yesterday: $yesterdayPosts, posts: $totalPosts, members: $totalMembers)';
}
