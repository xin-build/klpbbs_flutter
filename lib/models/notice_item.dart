/// 论坛消息提醒条目（精准还原 Discuz 网页版 home.php?mod=space&do=notice）
class NoticeItem {
  final int tid;
  final int? pid;
  final int? uid;
  final String author;
  final String avatarUrl;

  /// 动作描述行，如「在主题 [苦坛停运记] 中提到了您」或「回复了您的帖子」
  final String actionText;

  /// 被提及或回复的主题标题
  final String? threadTitle;

  /// 引用回复/正文摘要气泡（网页中的 “ ... ” 引用文本）
  final String? quoteText;

  /// 发生时间，如「2024-8-29 18:52」或「10 分钟前」
  final String timeText;

  /// 提醒分类标签，如「提到我的」「回复」「悬赏」「评分」「系统」「应用」
  final String badge;

  /// 跳转目标链接（如 goto=findpost）
  final String linkUrl;

  /// 是否为打招呼提醒
  final bool isPoke;

  /// 是否为好友申请提醒
  final bool isFriendRequest;

  /// 是否为未读新提醒
  final bool isNew;

  /// 头像挂件 URL（若有）
  final String? faceUrl;

  const NoticeItem({
    required this.tid,
    this.pid,
    this.uid,
    required this.author,
    this.avatarUrl = '',
    this.faceUrl,
    required this.actionText,
    this.threadTitle,
    this.quoteText,
    required this.timeText,
    this.badge = '提醒',
    this.linkUrl = '',
    this.isPoke = false,
    this.isFriendRequest = false,
    this.isNew = false,
  });
}
