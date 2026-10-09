/// 苦力怕论坛全站统计数据模型（今日发帖 / 昨日发帖 / 全站总帖 / 注册会员）
class SiteStats {
  final int todayPosts;
  final int yesterdayPosts;
  final int totalPosts;
  final int totalMembers;
  final bool hasTodayPosts;
  final bool hasYesterdayPosts;
  final bool hasTotalPosts;
  final bool hasTotalMembers;
  final Map<String, String> displayValues;
  final DateTime? fetchedAt;

  const SiteStats({
    int? todayPosts,
    int? yesterdayPosts,
    int? totalPosts,
    int? totalMembers,
    this.displayValues = const {},
    this.fetchedAt,
  }) : todayPosts = todayPosts ?? 0,
       yesterdayPosts = yesterdayPosts ?? 0,
       totalPosts = totalPosts ?? 0,
       totalMembers = totalMembers ?? 0,
       hasTodayPosts = todayPosts != null,
       hasYesterdayPosts = yesterdayPosts != null,
       hasTotalPosts = totalPosts != null,
       hasTotalMembers = totalMembers != null;

  /// 是否为包含全部指标的完整统计数据（避免将版块局部今日帖数误判为全站统计）
  bool get isComplete =>
      hasTodayPosts && hasYesterdayPosts && hasTotalPosts && hasTotalMembers;

  bool get isEmpty =>
      !hasTodayPosts && !hasYesterdayPosts && !hasTotalPosts && !hasTotalMembers;

  bool get isFresh => fetchedAt != null &&
      DateTime.now().difference(fetchedAt!) < const Duration(minutes: 5) &&
      fetchedAt!.year == DateTime.now().year &&
      fetchedAt!.month == DateTime.now().month &&
      fetchedAt!.day == DateTime.now().day;

  String display(String metric) {
    final value = switch (metric) {
      'todayPosts' => hasTodayPosts ? todayPosts : null,
      'yesterdayPosts' => hasYesterdayPosts ? yesterdayPosts : null,
      'totalPosts' => hasTotalPosts ? totalPosts : null,
      'totalMembers' => hasTotalMembers ? totalMembers : null,
      _ => null,
    };
    return value == null ? '—' : (displayValues[metric] ?? '$value');
  }

  Map<String, dynamic> toJson() => {
    'format': 2,
    'todayPosts': hasTodayPosts ? todayPosts : null,
    'yesterdayPosts': hasYesterdayPosts ? yesterdayPosts : null,
    'totalPosts': hasTotalPosts ? totalPosts : null,
    'totalMembers': hasTotalMembers ? totalMembers : null,
    'displayValues': displayValues,
    'fetchedAt': fetchedAt?.toIso8601String(),
  };

  factory SiteStats.fromJson(Map<String, dynamic> json) => json['format'] != 2
      ? const SiteStats()
      : SiteStats(
          todayPosts: json['todayPosts'] as int?,
          yesterdayPosts: json['yesterdayPosts'] as int?,
          totalPosts: json['totalPosts'] as int?,
          totalMembers: json['totalMembers'] as int?,
          displayValues: Map<String, String>.from(json['displayValues'] as Map? ?? {}),
          fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? ''),
        );

  @override
  String toString() =>
      'SiteStats(today: $todayPosts, yesterday: $yesterdayPosts, posts: $totalPosts, members: $totalMembers)';
}
