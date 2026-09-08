/// Discuz! 用户组角色与管理权限模型
///
/// 严格映射 Discuz! X 用户组体系（common_usergroup）：
/// - 管理员 (Administrator, groupid=1, adminid=1)
/// - 超级版主 (Super Moderator, groupid=2, adminid=2)
/// - 版主 (Moderator, groupid=3, adminid=3)
/// - 实习版主 (Probationary Moderator, groupid=16, adminid=3)
/// - 禁止发言 (Muted, groupid=4)
/// - 禁止访问 (Banned, groupid=5)
/// - 禁止 IP (IP Banned, groupid=6)
class DiscuzUserRole {
  final int uid;
  final String username;
  final int groupId;
  final int adminId;
  final String groupTitle;
  String get group => groupTitle;
  final bool isAdmin;
  final bool isSuperMod;
  final bool isModerator;
  final List<int> moderatedFids;
  final bool isMuted;
  final bool isBanned;

  const DiscuzUserRole({
    this.uid = 0,
    this.username = '',
    this.groupId = 0,
    this.adminId = 0,
    this.groupTitle = '',
    this.isAdmin = false,
    this.isSuperMod = false,
    this.isModerator = false,
    this.moderatedFids = const [],
    this.isMuted = false,
    this.isBanned = false,
  });

  /// 是否属于任意管理组（拥有管理权限）
  bool get hasAnyModPermission => isAdmin || isSuperMod || isModerator;

  /// 判断对指定版块是否具备管理权限
  /// - 管理员和超级版主：全站所有版块均有权管理
  /// - 版主：管辖版块列表中包含目标 fid，或尚未指定具体版块时默认具有本版管理权
  bool canModerateFid(int? fid) {
    if (isAdmin || isSuperMod) return true;
    if (isModerator) {
      if (fid == null || fid <= 0) return true;
      if (moderatedFids.isEmpty) return true;
      return moderatedFids.contains(fid);
    }
    return false;
  }

  /// 转换为 JSON 格式
  Map<String, dynamic> toJson() => {
    'uid': uid,
    'username': username,
    'groupId': groupId,
    'adminId': adminId,
    'groupTitle': groupTitle,
    'isAdmin': isAdmin,
    'isSuperMod': isSuperMod,
    'isModerator': isModerator,
    'moderatedFids': moderatedFids,
    'isMuted': isMuted,
    'isBanned': isBanned,
  };

  /// 从 JSON 解析
  factory DiscuzUserRole.fromJson(Map<String, dynamic> json) {
    return DiscuzUserRole(
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      groupId: (json['groupId'] as num?)?.toInt() ?? 0,
      adminId: (json['adminId'] as num?)?.toInt() ?? 0,
      groupTitle: json['groupTitle']?.toString() ?? '',
      isAdmin: json['isAdmin'] as bool? ?? false,
      isSuperMod: json['isSuperMod'] as bool? ?? false,
      isModerator: json['isModerator'] as bool? ?? false,
      moderatedFids: (json['moderatedFids'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      isMuted: json['isMuted'] as bool? ?? false,
      isBanned: json['isBanned'] as bool? ?? false,
    );
  }
}
