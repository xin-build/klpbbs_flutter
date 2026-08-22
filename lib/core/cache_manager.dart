import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 苦力怕论坛长期图片缓存管理器
/// 为头像、表情、挂件、勋章、论坛图章与高频帖子配图提供 90 天长期磁盘缓存
class KlpbbsCacheManager {
  static const key = 'klpbbs_longterm_image_cache';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 90),
      maxNrOfCacheObjects: 3000,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
}
