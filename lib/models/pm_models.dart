/// 私信会话（收件箱条目）
class PmConversation {
  final int plid;
  final int touid;
  final String username;

  /// 最后消息摘要
  final String summary;

  /// 时间文本
  final String timeText;

  /// 消息总数
  final int messageCount;

  /// 是否包含未读消息
  final bool isNew;

  /// 头像挂件 URL（若有）
  final String? faceUrl;

  const PmConversation({
    required this.plid,
    required this.touid,
    required this.username,
    this.summary = '',
    this.timeText = '',
    this.messageCount = 0,
    this.isNew = false,
    this.faceUrl,
  });
}

/// 私信消息（会话详情条目）
class PmMessage {
  final int pmid;
  final int authorUid;
  final String author;
  final String content;
  final String timeText;

  /// 头像挂件 URL（若有）
  final String? faceUrl;

  const PmMessage({
    required this.pmid,
    required this.authorUid,
    required this.author,
    required this.content,
    this.timeText = '',
    this.faceUrl,
  });
}
