/// 用户空间（个人中心）资料
class UserSpace {
  final int uid;
  final String username;

  /// 积分文本（如 "积分: 0"）
  final String credits;

  /// 用户组（如 "新手上路"）
  final String group;

  /// 注册时间
  final String regdate;

  /// 最后访问
  final String lastvisit;

  /// 签名（可能为空）
  final String signature;

  /// 等级徽章（如 "Lv.1"）
  final String level;

  /// 等级名（如 "新手上路"）
  final String levelName;

  /// 勋章列表（id/名称/描述/图片 URL）
  final List<({int id, String name, String desc, String img})> medals;

  /// 头像挂件（sunju_facemall）URL（空表示无）
  final String faceUrl;

  /// 空间背景/壁纸 URL（空表示默认）
  final String bgUrl;

  /// PC 版资料统计：主题数/回帖数/好友数
  final Map<String, String> stats;

  /// PC 版积分明细：经验/铁粒/铁锭/贡献/钻石
  final Map<String, String> creditsDetail;

  /// PC 版游戏与社交资料：基岩版用户名/Java版用户名/网易用户名/QQ/生日/性别/在线时间
  final Map<String, String> gameProfile;

  /// 是否当前在线（根据 Discuz ol.gif / 当前在线 标识）
  final bool isOnline;

  /// 在线状态文本描述（如 "当前在线"、"离线" 或 "最后访问: 2026-8-22"）
  final String onlineStatusText;

  const UserSpace({
    required this.uid,
    required this.username,
    this.credits = '',
    this.group = '',
    this.regdate = '',
    this.lastvisit = '',
    this.signature = '',
    this.level = '',
    this.levelName = '',
    this.medals = const [],
    this.faceUrl = '',
    this.bgUrl = '',
    this.stats = const {},
    this.creditsDetail = const {},
    this.gameProfile = const {},
    this.isOnline = false,
    this.onlineStatusText = '',
  });
}
