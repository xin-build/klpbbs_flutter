import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../core/klpbbs_facemall.dart';
import 'app_motion.dart';

/// 苦力怕论坛 sunju_facemall 头像挂件组件
/// 严格从官方附件 CDN 加载原生高清透明 PNG 挂件贴图；
/// 绝不绘制低质生硬的自定义矢量简笔画，加载失败或占位时保持优雅透明
class FacemallFrameWidget extends StatelessWidget {
  final String frameIdOrUrl;
  final double size;

  const FacemallFrameWidget({
    super.key,
    required this.frameIdOrUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cleanUrl = KlpFacemallResponse.frameUrl(
        frameIdOrUrl, Uri.parse(AppConfig.baseUrl));
    if (cleanUrl == null || cleanUrl.isEmpty) {
      return SizedBox(width: size, height: size);
    }

    final memSize = (size * 2.5).clamp(32, 256).toInt();

    return SizedBox(
      width: size,
      height: size,
      child: CachedNetworkImage(
        imageUrl: cleanUrl,
        cacheManager: KlpbbsCacheManager.instance,
        cacheKey: KlpbbsCacheManager.normalizeCacheKey(cleanUrl),
        httpHeaders: AppConfig.imageHeadersFor(cleanUrl),
        width: size,
        height: size,
        fit: BoxFit.contain,
        memCacheWidth: memSize,
        fadeInDuration:
            AppMotion.duration(context, 140, scope: MotionScope.loading),
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => SizedBox(width: size, height: size),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}
