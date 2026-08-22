import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';

/// 图片加载失败自动重试（默认最多 3 次，延迟递增），最后一次失败走 errorWidget
class RetryImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final int maxAttempts;

  const RetryImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
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

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.errorWidget?.call(context, widget.imageUrl, 'error') ??
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

    return CachedNetworkImage(
      key: ValueKey('${widget.imageUrl}#$_attempt'),
      imageUrl: widget.imageUrl,
      cacheManager: KlpbbsCacheManager.instance,
      httpHeaders: AppConfig.imageHeadersFor(widget.imageUrl),
      width: widget.width,
      height: widget.height,
      fit: widget.fit ?? BoxFit.contain,
      placeholder: widget.placeholder ??
          (_, __) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
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