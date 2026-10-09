import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';

/// 图片加载失败自动重试（默认最多 3 次，延迟递增），并提供 SVG 矢量图渲染、高清抗锯齿与防拉伸支持
class RetryImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final int maxAttempts;

  const RetryImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.memCacheWidth,
    this.memCacheHeight,
    this.placeholder,
    this.errorWidget,
    this.maxAttempts = 3,
  });

  @override
  State<RetryImage> createState() => _RetryImageState();
}

class _RetryImageState extends State<RetryImage> {
  int _attempt = 0;

  static String _sanitize(String raw) {
    var url = raw.trim();
    if (url.startsWith('//')) {
      url = 'https:$url';
    }
    try {
      return Uri.encodeFull(url);
    } catch (_) {
      return url;
    }
  }

  static bool _isSvg(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.svg') ||
        lower.contains('.svg?') ||
        lower.contains('count.getloli.com') ||
        lower.contains('img.shields.io') ||
        lower.contains('badgen.net');
  }

  static final Set<String> _cleanedCacheKeys = <String>{};

  @override
  Widget build(BuildContext context) {
    final rawUrl = AppConfig.toHighResImageUrl(widget.imageUrl) ?? widget.imageUrl;
    final effectiveUrl = _sanitize(rawUrl);

    // 针对 SVG 格式或 Moe-Counter 计数器使用 SvgPicture 渲染
    if (_isSvg(effectiveUrl)) {
      return SvgPicture.network(
        effectiveUrl,
        headers: AppConfig.imageHeadersFor(effectiveUrl),
        width: widget.width,
        height: widget.height,
        fit: widget.fit ?? BoxFit.contain,
        alignment: widget.alignment,
        placeholderBuilder: (ctx) =>
            widget.placeholder?.call(ctx, effectiveUrl) ??
            Container(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(80),
              child: Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 20,
                  color: Theme.of(ctx).colorScheme.outlineVariant.withAlpha(120),
                ),
              ),
            ),
      );
    }

    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    // 关键防拉伸与GPU显存暴涨防御：
    // 1. 仅计算单边最大内存缓存尺寸，保持原图宽高比解码，彻底杜绝变形
    // 2. 为未指定尺寸的正文插图增加 1080px 安全上限，防止桌面/移动端原图 4K/8K 解码占用几十兆显存造成卡顿与发热
    final int calculatedMemWidth = widget.memCacheWidth ??
        (widget.width != null && widget.width! > 0
            ? (widget.width! * dpr).clamp(32, 1080).toInt()
            : (widget.height != null && widget.height! > 0
                ? (widget.height! * dpr * 1.5).clamp(48, 1080).toInt()
                : (960 * dpr).clamp(480, 1080).toInt()));

    final normCacheKey = KlpbbsCacheManager.normalizeCacheKey(effectiveUrl);

    return CachedNetworkImage(
      key: ValueKey('$normCacheKey#$_attempt'),
      imageUrl: effectiveUrl,
      cacheKey: normCacheKey.isNotEmpty ? normCacheKey : effectiveUrl,
      cacheManager: KlpbbsCacheManager.instance,
      httpHeaders: AppConfig.imageHeadersFor(effectiveUrl),
      width: widget.width,
      height: widget.height,
      fit: widget.fit ?? BoxFit.contain,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      memCacheWidth: calculatedMemWidth,
      placeholder: widget.placeholder ??
          (_, __) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
                child: Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.outlineVariant.withAlpha(120),
                  ),
                ),
              ),
      errorWidget: (ctx, url, err) {
        if (!_cleanedCacheKeys.contains(normCacheKey)) {
          _cleanedCacheKeys.add(normCacheKey);
          _cleanedCacheKeys.add(effectiveUrl);
          KlpbbsCacheManager.instance.removeFile(normCacheKey).catchError((_) {});
          KlpbbsCacheManager.instance.removeFile(effectiveUrl).catchError((_) {});
          DefaultCacheManager().removeFile(effectiveUrl).catchError((_) {});
        }

        final errStr = err.toString().toLowerCase();
        final isPermanent = errStr.contains('404') ||
            errStr.contains('521') ||
            errStr.contains('502') ||
            errStr.contains('500') ||
            errStr.contains('503') ||
            errStr.contains('not found') ||
            effectiveUrl.contains('nb-data.klpbbs.com');

        if (!isPermanent && _attempt < widget.maxAttempts) {
          Future.delayed(Duration(milliseconds: 400 * (_attempt + 1)), () {
            if (mounted) setState(() => _attempt++);
          });
          return widget.placeholder?.call(ctx, url) ??
              Container(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(60),
                child: Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 20,
                    color: Theme.of(ctx).colorScheme.outlineVariant.withAlpha(120),
                  ),
                ),
              );
        }
        return widget.errorWidget?.call(ctx, url, err) ??
            Container(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(60),
              child: Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 24,
                  color: Theme.of(ctx).colorScheme.outlineVariant.withAlpha(140),
                ),
              ),
            );
      },
    );
  }
}