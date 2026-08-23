/// 签到排行条目（k_misign 插件）
class SignEntry {
  final int uid;
  final String name;
  final String timeText;
  final int totalDays;
  final int monthDays;
  final String rewardText;
  final String usergroup;

  const SignEntry({
    required this.uid,
    required this.name,
    this.timeText = '',
    this.totalDays = 0,
    this.monthDays = 0,
    this.rewardText = '',
    this.usergroup = '',
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
