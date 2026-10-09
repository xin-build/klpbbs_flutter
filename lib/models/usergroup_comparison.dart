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

  bool get isMyAllowed => _isAllowed(myValue);

  bool get isNextAllowed => _isAllowed(nextValue);

  static bool _isAllowed(String value) {
    final text = value.trim();
    if (const {'✖', 'false', '0', '否', '禁止', '不允许', '无', '没有'}.contains(text)) return false;
    return const {'✔', 'true', '1', '是', '允许', '有'}.contains(text) || (int.tryParse(text) ?? 0) > 0;
  }
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
  final List<KlpbbsUserGroupMeta> groups;

  const UsergroupComparison({
    required this.myGroup,
    this.upgradeGroup,
    required this.permissions,
    this.groups = const [],
  });

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
