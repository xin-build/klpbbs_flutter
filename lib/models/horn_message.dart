/// 小喇叭广播消息模型（ahome_horn / 论坛顶部公告）
class HornMessage {
  final int id;
  final String author;
  final int? uid;
  final String content;
  final String timeText;
  final String? avatarUrl;
  final String? faceUrl;
  final String? linkUrl;
  final String? deleteUrl;
  final String? tag; // 标签，例如 "官方公告"、"全站广播"

  const HornMessage({
    this.id = 0,
    required this.author,
    this.uid,
    required this.content,
    this.timeText = '',
    this.avatarUrl,
    this.faceUrl,
    this.linkUrl,
    this.deleteUrl,
    this.tag,
  });

  factory HornMessage.fromJson(Map<String, dynamic> json) {
    return HornMessage(
      id: json['id'] as int? ?? 0,
      author: json['author'] as String? ?? '系统广播',
      uid: json['uid'] as int?,
      content: json['content'] as String? ?? '',
      timeText: json['timeText'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      faceUrl: json['faceUrl'] as String?,
      linkUrl: json['linkUrl'] as String?,
      deleteUrl: json['deleteUrl'] as String?,
      tag: json['tag'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'uid': uid,
        'content': content,
        'timeText': timeText,
        'avatarUrl': avatarUrl,
        'faceUrl': faceUrl,
        'linkUrl': linkUrl,
        'deleteUrl': deleteUrl,
        'tag': tag,
      };
}
