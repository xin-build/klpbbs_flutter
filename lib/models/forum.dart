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

  const Forum({
    required this.fid,
    required this.name,
    this.description,
    this.gid,
    this.iconUrl,
    this.threadCount = -1,
    this.todayCount = -1,
  });

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

  @override
  String toString() => 'ForumGroup(gid: $gid, name: $name, forums: ${forums.length})';
}
