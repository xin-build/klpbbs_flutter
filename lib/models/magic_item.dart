/// 论坛道具模型
class MagicItem {
  final int id;
  final String identifier; // 如 checkin, namecard, bump, wish, anonymous, observer
  final String name;
  final String desc;
  final int price;
  final String unit; // 如 "粒/张"
  final String img;
  final int weight;
  final int count; // 拥有数量（我的道具包中有效）
  final int stock; // 商店库存
  final bool canUse; // 是否可在背包直接使用（如提升卡仅支持帖子内使用或赠送/出售）
  final bool canGive; // 是否可赠送
  final bool canDrop; // 是否可出售/回收

  const MagicItem({
    required this.id,
    this.identifier = '',
    required this.name,
    this.desc = '',
    this.price = 0,
    this.unit = '粒/张',
    required this.img,
    this.weight = 1,
    this.count = 0,
    this.stock = 999,
    this.canUse = true,
    this.canGive = true,
    this.canDrop = true,
  });

  MagicItem copyWith({
    int? id,
    String? identifier,
    String? name,
    String? desc,
    int? price,
    String? unit,
    String? img,
    int? weight,
    int? count,
    int? stock,
    bool? canUse,
    bool? canGive,
    bool? canDrop,
  }) {
    return MagicItem(
      id: id ?? this.id,
      identifier: identifier ?? this.identifier,
      name: name ?? this.name,
      desc: desc ?? this.desc,
      price: price ?? this.price,
      unit: unit ?? this.unit,
      img: img ?? this.img,
      weight: weight ?? this.weight,
      count: count ?? this.count,
      stock: stock ?? this.stock,
      canUse: canUse ?? this.canUse,
      canGive: canGive ?? this.canGive,
      canDrop: canDrop ?? this.canDrop,
    );
  }
}

/// 道具包容量与资产状态模型
class MagicBagInfo {
  final int usedCapacity;
  final int totalCapacity;
  final int ironCount;

  const MagicBagInfo({
    this.usedCapacity = 0,
    this.totalCapacity = 500,
    this.ironCount = 0,
  });
}

/// 道具流水记录模型
class MagicLogEntry {
  final String magicName;
  final String time;
  final int amount;
  final String action; // 购买 / 使用 / 赠送 / 获赠 / 回收
  final String target; // 目标主题 / 目标用户
  final String note;

  const MagicLogEntry({
    required this.magicName,
    required this.time,
    this.amount = 1,
    required this.action,
    this.target = '',
    this.note = '',
  });
}
