/// 论坛勋章模型
class MedalItem {
  final int id;
  final String name;
  final String desc;
  final String requirement; // 获取条件/价格，例如 "有效期 7 天, 铁粒 100 粒", "人工授予", "注册时间 ≤ 2026-3-1"
  final String img;
  final String actionUrl;
  final String status;
  final String actionLabel;

  const MedalItem({
    required this.id,
    required this.name,
    required this.desc,
    required this.requirement,
    required this.img,
    this.actionUrl = '',
    this.status = '',
    this.actionLabel = '',
  });

  /// 是否为人工授予勋章
  bool get isManual =>
      requirement.contains('人工授予') ||
      (!isBuyable && !isApplyable);

  /// 是否为可自主购买勋章（需消耗铁粒）
  bool get isBuyable => price != null || actionLabel.contains('购买');

  /// 是否为可自主申请勋章（如满足注册天数）
  bool get isApplyable =>
      requirement.contains('注册时间') ||
      requirement.contains('在线申请') ||
      requirement.contains('自主申请') ||
      requirement.contains('自动发放') ||
      actionUrl.isNotEmpty ||
      actionLabel.contains('申请') || actionLabel.contains('领取');

  bool get isOwned => status.contains('已拥有') || status.contains('已经拥有') || status.contains('已购买');
  bool get isPending => status.contains('已申请') || status.contains('审核中');

  /// 提取价格，如 "100 铁粒" 或 "5 粒"
  String? get price {
    final m = RegExp(r'铁粒\s*(\d+)\s*粒?').firstMatch(requirement);
    if (m != null) return '${m.group(1)} 铁粒';
    final m2 = RegExp(r'(\d+)\s*粒').firstMatch(requirement);
    if (m2 != null) return '${m2.group(1)} 铁粒';
    final other = RegExp(r'(钻石|贡献|经验|火药|下界之星)\s*([\d,，]+)').firstMatch(requirement);
    if (other != null) return '${other[2]} ${other[1]}';
    return null;
  }

  /// 提取有效期，如 "有效期 7 天"
  String? get period {
    final m = RegExp(r'有效期\s*\d+\s*天').firstMatch(requirement);
    if (m != null) return m.group(0);
    return null;
  }

  /// 格式化为条件展示行（如拆分为有效期与价格）
  List<String> get requirementLines {
    if (requirement.isEmpty) return const [];
    return requirement
        .split(RegExp(r'[,，\r\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
