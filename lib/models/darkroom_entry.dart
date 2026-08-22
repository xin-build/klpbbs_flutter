/// 小黑屋（违规公示）条目
class DarkroomEntry {
  final int uid;
  final String username;

  /// 违规类型（如"禁止发言"）
  final String action;

  /// 违规时间文本
  final String dateline;

  /// 到期时间（null=永久）
  final String? expiry;

  /// 违规理由
  final String reason;

  const DarkroomEntry({
    required this.uid,
    required this.username,
    this.action = '',
    this.dateline = '',
    this.expiry,
    this.reason = '',
  });
}
