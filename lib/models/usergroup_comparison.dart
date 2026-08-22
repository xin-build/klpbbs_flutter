/// Discuz 用户组权限与晋级对照模型（对应 home.php?mod=spacecp&ac=usergroup 网页真实数据）
class UsergroupPermissionItem {
  final String title;
  final String myValue;
  final String nextValue;
  final bool isCategoryHeader;

  const UsergroupPermissionItem({
    required this.title,
    required this.myValue,
    this.nextValue = '',
    this.isCategoryHeader = false,
  });

  bool get isMyBool => myValue == '✔' || myValue == '✖' || myValue == 'true' || myValue == 'false';
  bool get isNextBool => nextValue == '✔' || nextValue == '✖' || nextValue == 'true' || nextValue == 'false';

  bool get isMyAllowed =>
      myValue == '✔' ||
      myValue == 'true' ||
      myValue == '1' ||
      myValue.contains('允许') ||
      myValue.contains('有') ||
      (int.tryParse(myValue) != null && int.parse(myValue) > 0);

  bool get isNextAllowed =>
      nextValue == '✔' ||
      nextValue == 'true' ||
      nextValue == '1' ||
      nextValue.contains('允许') ||
      nextValue.contains('有') ||
      (int.tryParse(nextValue) != null && int.parse(nextValue) > 0);
}

class UsergroupColumn {
  final String title;
  final String subtitle;
  final String? iconUrl;

  const UsergroupColumn({
    required this.title,
    required this.subtitle,
    this.iconUrl,
  });
}

class UsergroupComparison {
  final UsergroupColumn myGroup;
  final UsergroupColumn? upgradeGroup;
  final List<UsergroupPermissionItem> permissions;

  const UsergroupComparison({
    required this.myGroup,
    this.upgradeGroup,
    required this.permissions,
  });

  /// 苦力怕论坛真实用户组分类全集（100% 对齐 home.php?mod=spacecp&ac=usergroup 网页端）
  static const List<KlpbbsUserGroupMeta> allGroups = [
    // 晋级用户组
    KlpbbsUserGroupMeta(name: '限制会员', category: '晋级用户组', gid: 9, credits: '积分 < 0'),
    KlpbbsUserGroupMeta(name: 'Lv.1 新手上路', category: '晋级用户组', gid: 10, credits: '0 - 199 积分'),
    KlpbbsUserGroupMeta(name: 'Lv.2 注册会员', category: '晋级用户组', gid: 11, credits: '200 - 999 积分'),
    KlpbbsUserGroupMeta(name: 'Lv.3 中级会员', category: '晋级用户组', gid: 12, credits: '1000 - 4999 积分'),
    KlpbbsUserGroupMeta(name: 'Lv.4 高级会员', category: '晋级用户组', gid: 13, credits: '5000 - 9999 积分'),
    KlpbbsUserGroupMeta(name: 'Lv.5 金牌会员', category: '晋级用户组', gid: 14, credits: '10000 - 49999 积分'),
    KlpbbsUserGroupMeta(name: 'Lv.6 论坛元老', category: '晋级用户组', gid: 15, credits: '50000+ 积分'),

    // 站点管理组
    KlpbbsUserGroupMeta(name: '管理员', category: '站点管理组', gid: 1, credits: '管理组'),
    KlpbbsUserGroupMeta(name: '超级版主', category: '站点管理组', gid: 2, credits: '管理组'),
    KlpbbsUserGroupMeta(name: '版主', category: '站点管理组', gid: 3, credits: '管理组'),
    KlpbbsUserGroupMeta(name: '实习版主', category: '站点管理组', gid: 16, credits: '管理组'),
    KlpbbsUserGroupMeta(name: '网站编辑', category: '站点管理组', gid: 17, credits: '管理组'),
    KlpbbsUserGroupMeta(name: '信息监察员', category: '站点管理组', gid: 18, credits: '管理组'),
    KlpbbsUserGroupMeta(name: '审核员', category: '站点管理组', gid: 19, credits: '管理组'),

    // 普通用户组
    KlpbbsUserGroupMeta(name: 'SVIP', category: '普通用户组', gid: 22, credits: '特殊组'),
    KlpbbsUserGroupMeta(name: 'VIP', category: '普通用户组', gid: 21, credits: '特殊组'),
    KlpbbsUserGroupMeta(name: 'QQ游客', category: '普通用户组', gid: 20, credits: '特殊组'),
    KlpbbsUserGroupMeta(name: '等待邮箱验证', category: '普通用户组', gid: 8, credits: '特殊组'),
    KlpbbsUserGroupMeta(name: '游客', category: '普通用户组', gid: 7, credits: '特殊组'),
    KlpbbsUserGroupMeta(name: '禁止 IP', category: '普通用户组', gid: 6, credits: '特殊组'),
    KlpbbsUserGroupMeta(name: '禁止访问', category: '普通用户组', gid: 5, credits: '特殊组'),
    KlpbbsUserGroupMeta(name: '禁止发言', category: '普通用户组', gid: 4, credits: '特殊组'),
  ];
}

class KlpbbsUserGroupMeta {
  final int? gid;
  final String name;
  final String category;
  final String credits;

  const KlpbbsUserGroupMeta({
    this.gid,
    required this.name,
    required this.category,
    this.credits = '',
  });
}
