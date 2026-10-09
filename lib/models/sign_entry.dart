/// 签到排行条目（k_misign 插件）
class SignEntry {
  final int uid;
  final String name;
  final String timeText;
  final int totalDays;
  final int monthDays;
  final String rewardText;
  final String usergroup;
  final String totalReward;

  const SignEntry({
    required this.uid,
    required this.name,
    this.timeText = '',
    this.totalDays = 0,
    this.monthDays = 0,
    this.rewardText = '',
    this.usergroup = '',
    this.totalReward = '',
  });

  /// 提取等级/用户组称号（如 [LV.5]金锭）
  String get displayLevel {
    if (usergroup.isNotEmpty) return usergroup;
    if (rewardText.contains('LV.') ||
        rewardText.contains('[LV') ||
        rewardText.contains('金锭') ||
        rewardText.contains('青金石') ||
        rewardText.contains('合金') ||
        rewardText.contains('钻石') ||
        rewardText.contains('红石') ||
        rewardText.contains('绿宝石') ||
        rewardText.contains('会员') ||
        rewardText.contains('版主') ||
        rewardText.contains('管理')) {
      return rewardText;
    }
    return '';
  }

  /// 真正的签到奖励文本（去除等级称号误判）
  String get displayReward {
    if (displayLevel.isNotEmpty && displayLevel == rewardText) return '';
    return rewardText;
  }
}

/// 签到页面头部统计与个人实时数据模型（1:1 对齐官方 k_misign 页面）
class SignHeaderInfo {
  final bool isRecognized;
  final bool hasPersonalState;
  final bool hasTodaySignCount;
  final bool hasPersonalStats;
  final bool hasContinuousDays;
  final bool hasTotalDays;
  final String starUsername;
  final int? starUid;
  final String? starAvatarUrl;
  final String? starFaceUrl;
  final int highestCount;
  final int todaySignCount;
  final bool isSignedToday;
  final int? mySignRank;
  final String username;
  final int? uid;
  final int continuousDays;
  final String signLevel;
  final String rewardIron;
  final int totalDays;
  final int? retroSignBid;
  final int retroSignDays;
  final String retroSignTip;

  const SignHeaderInfo({
    this.isRecognized = false,
    this.hasPersonalState = false,
    this.hasTodaySignCount = false,
    this.hasPersonalStats = false,
    this.hasContinuousDays = false,
    this.hasTotalDays = false,
    this.starUsername = '',
    this.starUid,
    this.starAvatarUrl,
    this.starFaceUrl,
    this.highestCount = 0,
    this.todaySignCount = 0,
    this.isSignedToday = false,
    this.mySignRank,
    this.username = '',
    this.uid,
    this.continuousDays = 0,
    this.signLevel = '',
    this.rewardIron = '',
    this.totalDays = 0,
    this.retroSignBid,
    this.retroSignDays = 0,
    this.retroSignTip = '',
  });

  SignHeaderInfo copyWith({
    bool? isRecognized,
    bool? hasPersonalState,
    bool? hasTodaySignCount,
    bool? hasPersonalStats,
    bool? hasContinuousDays,
    bool? hasTotalDays,
    String? starUsername,
    int? starUid,
    String? starAvatarUrl,
    String? starFaceUrl,
    bool clearStarIdentity = false,
    int? highestCount,
    int? todaySignCount,
    bool? isSignedToday,
    int? mySignRank,
    bool clearMySignRank = false,
    String? username,
    int? uid,
    int? continuousDays,
    String? signLevel,
    String? rewardIron,
    int? totalDays,
    int? retroSignBid,
    int? retroSignDays,
    String? retroSignTip,
  }) {
    final resetStar = clearStarIdentity ||
        (starUsername != null && starUsername != this.starUsername);
    return SignHeaderInfo(
      isRecognized: isRecognized ?? this.isRecognized,
      hasPersonalState: hasPersonalState ?? this.hasPersonalState,
      hasTodaySignCount: hasTodaySignCount ?? this.hasTodaySignCount,
      hasPersonalStats: hasPersonalStats ?? this.hasPersonalStats,
      hasContinuousDays: hasContinuousDays ?? this.hasContinuousDays,
      hasTotalDays: hasTotalDays ?? this.hasTotalDays,
      starUsername: starUsername ?? this.starUsername,
      starUid: starUid ?? (resetStar ? null : this.starUid),
      starAvatarUrl: starAvatarUrl ?? (resetStar ? null : this.starAvatarUrl),
      starFaceUrl: starFaceUrl ?? (resetStar ? null : this.starFaceUrl),
      highestCount: highestCount ?? this.highestCount,
      todaySignCount: todaySignCount ?? this.todaySignCount,
      isSignedToday: isSignedToday ?? this.isSignedToday,
      mySignRank: clearMySignRank ? null : mySignRank ?? this.mySignRank,
      username: username ?? this.username,
      uid: uid ?? this.uid,
      continuousDays: continuousDays ?? this.continuousDays,
      signLevel: signLevel ?? this.signLevel,
      rewardIron: rewardIron ?? this.rewardIron,
      totalDays: totalDays ?? this.totalDays,
      retroSignBid: retroSignBid ?? this.retroSignBid,
      retroSignDays: retroSignDays ?? this.retroSignDays,
      retroSignTip: retroSignTip ?? this.retroSignTip,
    );
  }
}
