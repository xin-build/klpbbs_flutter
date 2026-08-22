/// 签到排行条目（k_misign 插件）
class SignEntry {
  final int uid;
  final String name;
  final String timeText;
  final int totalDays;
  final int monthDays;
  final String rewardText;

  const SignEntry({
    required this.uid,
    required this.name,
    this.timeText = '',
    this.totalDays = 0,
    this.monthDays = 0,
    this.rewardText = '',
  });
}
