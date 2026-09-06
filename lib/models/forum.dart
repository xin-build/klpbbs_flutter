/// 版块（论坛分类）
class Forum {
  final int fid;
  final String name;
  final String? description;

  /// 所属分区 gid（版块树用；null 表示未归类）
  final int? gid;

  /// 版块图标 URL（社区版块树）
  final String? iconUrl;

  /// 帖数（-1 表示未知）
  final int threadCount;

  /// 今日帖数（-1 表示未知）
  final int todayCount;

  /// 收藏 ID（Discuz space favorite favid）
  final int? favid;

  const Forum({
    required this.fid,
    required this.name,
    this.description,
    this.gid,
    this.iconUrl,
    this.threadCount = -1,
    this.todayCount = -1,
    this.favid,
  });

  Map<String, dynamic> toJson() => {
        'fid': fid,
        'name': name,
        'description': description,
        'gid': gid,
        'iconUrl': iconUrl,
        'threadCount': threadCount,
        'todayCount': todayCount,
        'favid': favid,
      };

  factory Forum.fromJson(Map<String, dynamic> json) => Forum(
        fid: json['fid'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        gid: json['gid'] as int?,
        iconUrl: json['iconUrl'] as String?,
        threadCount: json['threadCount'] as int? ?? -1,
        todayCount: json['todayCount'] as int? ?? -1,
        favid: json['favid'] as int?,
      );

  Forum copyWith({
    int? fid,
    String? name,
    String? description,
    int? gid,
    String? iconUrl,
    int? threadCount,
    int? todayCount,
    int? favid,
  }) => Forum(
    fid: fid ?? this.fid,
    name: name ?? this.name,
    description: description ?? this.description,
    gid: gid ?? this.gid,
    iconUrl: iconUrl ?? this.iconUrl,
    threadCount: threadCount ?? this.threadCount,
    todayCount: todayCount ?? this.todayCount,
    favid: favid ?? this.favid,
  );

  @override
  String toString() => 'Forum(fid: $fid, name: $name)';
}

/// 分区（含下属版块列表）——社区「完整分区」结构
class ForumGroup {
  final int gid;
  final String name;
  final List<Forum> forums;

  const ForumGroup({
    required this.gid,
    required this.name,
    this.forums = const [],
  });

  Map<String, dynamic> toJson() => {
        'gid': gid,
        'name': name,
        'forums': forums.map((f) => f.toJson()).toList(),
      };

  factory ForumGroup.fromJson(Map<String, dynamic> json) => ForumGroup(
        gid: json['gid'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        forums: (json['forums'] as List<dynamic>?)
                ?.map((e) => Forum.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  String toString() => 'ForumGroup(gid: $gid, name: $name, forums: ${forums.length})';
}
