/// 单个表情（Discuz 内置 smilies）
class Smiley {
  final int id;

  /// 表情码（如 `[贴吧_呵呵]`，可能含论坛数据库编码残留）
  final String code;

  /// 文件名，如 `67.png`
  final String file;

  final int width;
  final int height;

  /// 图片绝对 URL（`static/image/smiley/{dir}/{file}`）
  final String imageUrl;

  const Smiley({
    required this.id,
    required this.code,
    required this.file,
    this.width = 20,
    this.height = 20,
    required this.imageUrl,
  });

  @override
  String toString() => 'Smiley(id: $id, file: $file)';
}

/// 表情分类（如 贴吧/B站/抖音/QQ）
class SmileyCategory {
  final int typeid;

  /// 目录名（如 `bilibili`）
  final String dir;

  /// 显示名（如 `B站`）
  final String name;

  final List<Smiley> smileys;

  const SmileyCategory({
    required this.typeid,
    required this.dir,
    required this.name,
    this.smileys = const [],
  });

  @override
  String toString() => 'SmileyCategory($dir, ${smileys.length} 个)';
}
