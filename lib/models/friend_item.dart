/// 好友条目模型
class FriendItem {
  final int uid;
  final String username;
  final String avatarUrl;
  final String usergroup;
  final String credits;

  const FriendItem({
    required this.uid,
    required this.username,
    this.avatarUrl = '',
    this.usergroup = '',
    this.credits = '',
  });

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'username': username,
    'avatarUrl': avatarUrl,
    'usergroup': usergroup,
    'credits': credits,
  };

  factory FriendItem.fromJson(Map<String, dynamic> json) => FriendItem(
    uid: json['uid'] as int? ?? 0,
    username: json['username'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String? ?? '',
    usergroup: json['usergroup'] as String? ?? '',
    credits: json['credits'] as String? ?? '',
  );
}
