/// 本版积分规则条目模型
class ForumCreditRule {
  final String action; // 动作名称，例如：发新主题、发表回复、设为精华、删帖、悬赏最佳
  final String cycle; // 奖励周期，例如：每天、一次、不限
  final String maxDaily; // 每天最高次数，例如：10次、20次、不限
  final String exp; // 经验变动，例如：+2、+1、+10、-5
  final String iron; // 铁粒变动，例如：+1、+0、+10、-3
  final String tribute; // 贡献变动，例如：+1、0

  const ForumCreditRule({
    required this.action,
    this.cycle = '不限',
    this.maxDaily = '不限',
    this.exp = '0',
    this.iron = '0',
    this.tribute = '0',
  });
}

/// 版块顶部导览、Banner、统计信息与版规/积分规则模型（1:1 精准还原 Discuz 网页版版块头部）
class ForumHeaderInfo {
  final int fid;
  final String name;
  final String? bannerUrl;
  final int todayPosts;
  final int threadsCount;
  final int rank;
  final int favCount;
  final String moderators;
  final String rulesHtml;
  final List<ForumCreditRule> creditRules;

  const ForumHeaderInfo({
    required this.fid,
    required this.name,
    this.bannerUrl,
    this.todayPosts = 0,
    this.threadsCount = 0,
    this.rank = 0,
    this.favCount = 0,
    this.moderators = '',
    this.rulesHtml = '',
    this.creditRules = const [],
  });

  bool get isEmpty =>
      (bannerUrl == null || bannerUrl!.isEmpty) &&
      todayPosts == 0 &&
      threadsCount == 0 &&
      moderators.isEmpty &&
      rulesHtml.isEmpty &&
      creditRules.isEmpty;
}
