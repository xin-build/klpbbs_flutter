import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
    this.filterQuality = FilterQuality.medium,
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
  bool _failed = false;

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

  @override
  Widget build(BuildContext context) {
    final rawUrl = AppConfig.toHighResImageUrl(widget.imageUrl) ?? widget.imageUrl;
    final effectiveUrl = _sanitize(rawUrl);

    if (_failed) {
      return widget.errorWidget?.call(context, effectiveUrl, 'error') ??
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(
              child: Icon(
                Icons.image_outlined,
                size: 24,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          );
    }

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
    final int? calculatedMemWidth = widget.memCacheWidth ??
        (widget.width != null && widget.width! > 0 ? (widget.width! * dpr).clamp(120, 2048).toInt() : null);
    final int? calculatedMemHeight = widget.memCacheHeight ??
        (widget.height != null && widget.height! > 0 ? (widget.height! * dpr).clamp(120, 2048).toInt() : null);

    return CachedNetworkImage(
      key: ValueKey('$effectiveUrl#$_attempt'),
      imageUrl: effectiveUrl,
      cacheManager: KlpbbsCacheManager.instance,
      httpHeaders: AppConfig.imageHeadersFor(effectiveUrl),
      width: widget.width,
      height: widget.height,
      fit: widget.fit ?? BoxFit.contain,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      memCacheWidth: calculatedMemWidth,
      memCacheHeight: calculatedMemHeight,
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
        if (_attempt < widget.maxAttempts) {
          Future.delayed(Duration(milliseconds: 350 * (_attempt + 1)), () {
            if (mounted) setState(() => _attempt++);
          });
          return widget.placeholder?.call(ctx, url) ??
              Container(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(80),
                child: Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 20,
                    color: Theme.of(ctx).colorScheme.outlineVariant.withAlpha(120),
                  ),
                ),
              );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_failed) setState(() => _failed = true);
        });
        return widget.errorWidget?.call(ctx, url, err) ??
            Container(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              child: Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 24,
                  color: Theme.of(ctx).colorScheme.outlineVariant,
                ),
              ),
            );
      },
    );
  }
}