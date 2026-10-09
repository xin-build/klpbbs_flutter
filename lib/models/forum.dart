/// 版块（论坛分类）
class Forum {
  final int fid;
  final String name;
  final String? description;

  /// 所属分区 gid（版块树用；null 表示未归类）
  final int? gid;

  /// 版块图标 URL（社区版块树）
  final String? iconUrl;

  /// 帖数，包含主题与回复（历史字段名；-1 表示未知）。
  /// 目录使用网页目录的汇总口径，不用本版页的计数覆盖它。
  final int threadCount;

  /// 主题数，与帖数分别保存（-1 表示未知）。
  final int topicCount;

  /// 今日帖数（-1 表示未知）
  final int todayCount;
  final Map<String, String> displayValues;

  /// 收藏 ID（Discuz space favorite favid）
  final int? favid;

  const Forum({
    required this.fid,
    required this.name,
    this.description,
    this.gid,
    this.iconUrl,
    this.threadCount = -1,
    this.topicCount = -1,
    this.todayCount = -1,
    this.displayValues = const {},
    this.favid,
  });

  Map<String, dynamic> toJson() => {
        'fid': fid,
        'name': name,
        'description': description,
        'gid': gid,
        'iconUrl': iconUrl,
        'threadCount': threadCount,
        'topicCount': topicCount,
        'todayCount': todayCount,
        'counterFormat': 2,
        'displayValues': displayValues,
        'favid': favid,
      };

  factory Forum.fromJson(Map<String, dynamic> json) => Forum(
        fid: json['fid'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        gid: json['gid'] as int?,
        iconUrl: json['iconUrl'] as String?,
        // Earlier caches mixed a favorite's topic count into total posts.
        // Keep the directory and favorite IDs, but refresh ambiguous counters.
        threadCount:
            json['counterFormat'] == 2 ? json['threadCount'] as int? ?? -1 : -1,
        topicCount:
            json['counterFormat'] == 2 ? json['topicCount'] as int? ?? -1 : -1,
        todayCount:
            json['counterFormat'] == 2 ? json['todayCount'] as int? ?? -1 : -1,
        displayValues: json['counterFormat'] == 2
            ? Map<String, String>.from(
                json['displayValues'] as Map? ?? const {})
            : const {},
        favid: json['favid'] as int?,
      );

  Forum copyWith({
    int? fid,
    String? name,
    String? description,
    int? gid,
    String? iconUrl,
    int? threadCount,
    int? topicCount,
    int? todayCount,
    Map<String, String>? displayValues,
    int? favid,
  }) {
    final displays = displayValues ?? {...this.displayValues};
    if (displayValues == null) {
      if (threadCount != null) displays.remove('posts');
      if (topicCount != null) displays.remove('topics');
      if (todayCount != null) displays.remove('today');
    }
    return Forum(
        fid: fid ?? this.fid,
        name: name ?? this.name,
        description: description ?? this.description,
        gid: gid ?? this.gid,
        iconUrl: iconUrl ?? this.iconUrl,
        threadCount: threadCount ?? this.threadCount,
        topicCount: topicCount ?? this.topicCount,
        todayCount: todayCount ?? this.todayCount,
        displayValues: displays,
        favid: favid ?? this.favid,
      );
  }

  String displayCount(String metric) {
    final value = switch (metric) {
      'topics' => topicCount,
      'posts' => threadCount,
      'today' => todayCount,
      _ => -1,
    };
    return value < 0 ? '—' : displayValues[metric] ?? '$value';
  }

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
  String toString() =>
      'ForumGroup(gid: $gid, name: $name, forums: ${forums.length})';
}
