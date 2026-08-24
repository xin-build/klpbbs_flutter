/// 好友/关注/粉丝/访客条目模型
class FriendItem {
  final int uid;
  final String username;
  final String avatarUrl;
  final String usergroup;
  final String credits;

  /// 是否当前在线
  final bool isOnline;

  /// 是否已关注
  final bool isFollowing;

  /// 附注/自定义备注
  final String note;

  /// 最近来访时间或动态说明
  final String recentActivity;

  const FriendItem({
    required this.uid,
    required this.username,
    this.avatarUrl = '',
    this.usergroup = '',
    this.credits = '',
    this.isOnline = false,
    this.isFollowing = false,
    this.note = '',
    this.recentActivity = '',
  });

  FriendItem copyWith({
    int? uid,
    String? username,
    String? avatarUrl,
    String? usergroup,
    String? credits,
    bool? isOnline,
    bool? isFollowing,
    String? note,
    String? recentActivity,
  }) =>
      FriendItem(
        uid: uid ?? this.uid,
        username: username ?? this.username,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        usergroup: usergroup ?? this.usergroup,
        credits: credits ?? this.credits,
        isOnline: isOnline ?? this.isOnline,
        isFollowing: isFollowing ?? this.isFollowing,
        note: note ?? this.note,
        recentActivity: recentActivity ?? this.recentActivity,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'username': username,
        'avatarUrl': avatarUrl,
        'usergroup': usergroup,
        'credits': credits,
        'isOnline': isOnline,
        'isFollowing': isFollowing,
        'note': note,
        'recentActivity': recentActivity,
      };

  factory FriendItem.fromJson(Map<String, dynamic> json) => FriendItem(
        uid: json['uid'] as int? ?? 0,
        username: json['username'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String? ?? '',
        usergroup: json['usergroup'] as String? ?? '',
        credits: json['credits'] as String? ?? '',
        isOnline: json['isOnline'] as bool? ?? false,
        isFollowing: json['isFollowing'] as bool? ?? false,
        note: json['note'] as String? ?? '',
        recentActivity: json['recentActivity'] as String? ?? '',
      );
}
