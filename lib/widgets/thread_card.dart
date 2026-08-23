import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../models/thread_summary.dart';
import 'retry_image.dart';

/// 自定义形状头像组件
class UserAvatarWidget extends StatelessWidget {
  final int? uid;
  final String author;
  final double size;

  /// 头像挂件（sunju_facemall）URL，空表示无
  final String? faceUrl;

  const UserAvatarWidget({
    super.key,
    this.uid,
    required this.author,
    this.size = 20,
    this.faceUrl,
  });

  /// 规范化与清洗挂件 URL（自动处理 ##SJ## 分隔符、相对路径并映射到原站真实附件路径）
  static String? sanitizeFaceUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    var url = rawUrl.trim();
    if (url.contains('##SJ##')) {
      final parts = url.split('##SJ##');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        url = parts[1].trim();
      } else {
        return null;
      }
    }
    if (url.isEmpty || url == 'none' || url == '0') return null;

    // 智能映射：苦力怕论坛 sunju_facemall 挂件真实存储路径为 data/attachment/sunju_facemall/...
    if (url.contains('keishi_klp_') || url.contains('sunju_facemall/')) {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        final base = AppConfig.baseUrl.endsWith('/') ? AppConfig.baseUrl : '${AppConfig.baseUrl}/';
        return '$base${url.startsWith('/') ? url.substring(1) : url}';
      }
      return url;
    }

    final m = RegExp(r'(?:template/img/|img/|fm_)?(\d+)\.png$', caseSensitive: false).firstMatch(url);
    if (m != null) {
      final id = m.group(1)!;
      return '${AppConfig.baseUrl}data/attachment/sunju_facemall/fm_$id.png';
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final base = AppConfig.baseUrl.endsWith('/') ? AppConfig.baseUrl : '${AppConfig.baseUrl}/';
      url = '$base${url.startsWith('/') ? url.substring(1) : url}';
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = author.isNotEmpty ? author.characters.first : '?';
    final hasUid = uid != null && uid! > 0;
    final avatarUrl = hasUid
        ? AppConfig.avatarUrl(uid!, size: size >= 40 ? 'middle' : 'small')
        : null;

    Widget imageContent;
    if (avatarUrl != null && AppConfig.imageQuality != ImageQuality.noImage) {
      imageContent = CachedNetworkImage(
        imageUrl: avatarUrl,
        cacheManager: KlpbbsCacheManager.instance,
        httpHeaders: AppConfig.imageHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                fontSize: size * 0.45,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                fontSize: size * 0.45,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      );
    } else {
      imageContent = Container(
        width: size,
        height: size,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    Widget avatar;
    switch (AppConfig.avatarShape) {
      case AvatarShape.circle:
        avatar = ClipOval(child: imageContent);
        break;
      case AvatarShape.roundedRect:
        avatar = ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.25),
          child: imageContent,
        );
        break;
      case AvatarShape.hexagon:
        avatar = ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.35),
          child: imageContent,
        );
        break;
    }

    // 解析挂件有效 URL（若组件未直接传入且为「我」，则自动使用全局设置的挂件）
    final cleanUrl = sanitizeFaceUrl(
      faceUrl ?? (author == '我' ? AppConfig.myFaceUrl : null),
    );

    // 头像挂件（sunju_facemall）：按官方 7/4 (1.75x) 比例居中叠放真实挂件图
    if (cleanUrl != null && cleanUrl.isNotEmpty) {
      final faceSize = size * 1.75;
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            avatar,
            Positioned(
              width: faceSize,
              height: faceSize,
              child: IgnorePointer(
                child: CachedNetworkImage(
                  imageUrl: cleanUrl,
                  cacheManager: KlpbbsCacheManager.instance,
                  httpHeaders: AppConfig.imageHeaders,
                  width: faceSize,
                  height: faceSize,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return avatar;
  }
}

/// 帖子卡片（支持 16:9 大图流、紧凑图文行与网格卡片 3 种排版）
class ThreadCard extends StatefulWidget {
  final ThreadSummary thread;
  final VoidCallback? onTap;
  final VoidCallback? onAuthorTap;
  final bool isGrid;

  const ThreadCard({
    super.key,
    required this.thread,
    this.onTap,
    this.onAuthorTap,
    this.isGrid = false,
  });

  @override
  State<ThreadCard> createState() => _ThreadCardState();
}

class _ThreadCardState extends State<ThreadCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = widget.thread;
    final cardStyle = widget.isGrid ? CardStyle.grid : AppConfig.cardStyle;

    // 检查是否有屏蔽词或屏蔽UID
    if (AppConfig.blockedUids.contains(thread.uid)) {
      return const SizedBox.shrink();
    }
    for (final kw in AppConfig.blockedKeywords) {
      if (thread.title.contains(kw) ||
          (thread.excerpt?.contains(kw) ?? false)) {
        return const SizedBox.shrink();
      }
    }

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Card(
          margin: widget.isGrid
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          color: _isHovered
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surfaceContainerLowest,
          elevation: _isHovered ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _isHovered
                  ? colorScheme.primary.withAlpha(120)
                  : colorScheme.outlineVariant.withAlpha(45),
              width: _isHovered ? 1.2 : 0.8,
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _buildCardContent(context, cardStyle),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent(BuildContext context, CardStyle style) {
    switch (style) {
      case CardStyle.compact:
        return _buildCompactLayout(context);
      case CardStyle.grid:
        return _buildGridLayout(context);
      case CardStyle.largeCover:
        return _buildLargeCoverLayout(context);
    }
  }

  /// 16:9 大图流布局
  Widget _buildLargeCoverLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = widget.thread;
    final hasCover =
        thread.coverUrl != null &&
        thread.coverUrl!.isNotEmpty &&
        AppConfig.imageQuality != ImageQuality.noImage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasCover) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  Container(
                    color: colorScheme.surfaceContainerHighest.withAlpha(80),
                  ),
                  RetryImage(
                    imageUrl: thread.coverUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: colorScheme.surfaceContainerHighest.withAlpha(80),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  if (thread.isHot)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withAlpha(220),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              color: Colors.white,
                              size: 12,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'HOT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        // 标题
        _buildTitle(theme),
        _buildTagRow(theme),
        if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            thread.excerpt!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.outline,
              height: 1.35,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 10),
        // 底部作者与统计信息
        _buildFooter(theme),
      ],
    );
  }

  /// 紧凑图文行布局（高信息密度）
  Widget _buildCompactLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = widget.thread;
    final hasCover =
        thread.coverUrl != null &&
        thread.coverUrl!.isNotEmpty &&
        AppConfig.imageQuality != ImageQuality.noImage;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle(theme),
              _buildTagRow(theme),
              if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  thread.excerpt!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _buildFooter(theme),
            ],
          ),
        ),
        if (hasCover) ...[
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 84,
              height: 64,
              child: RetryImage(
                imageUrl: thread.coverUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: colorScheme.surfaceContainerHighest.withAlpha(60),
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: colorScheme.outlineVariant.withAlpha(80),
                      size: 20,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: colorScheme.surfaceContainerHighest.withAlpha(60),
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: colorScheme.outlineVariant.withAlpha(80),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 网格/桌面卡片布局：自适应图文卡片（有真实封面则显示首图，无图则展示整洁的纯文本卡片）
  Widget _buildGridLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = widget.thread;
    final hasCover =
        thread.coverUrl != null &&
        thread.coverUrl!.trim().isNotEmpty &&
        AppConfig.imageQuality != ImageQuality.noImage;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasCover) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 108,
              height: 92,
              child: RetryImage(
                imageUrl: thread.coverUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: colorScheme.surfaceContainerHighest.withAlpha(60),
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: colorScheme.outlineVariant.withAlpha(80),
                      size: 24,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: colorScheme.surfaceContainerHighest.withAlpha(60),
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: colorScheme.outlineVariant.withAlpha(80),
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        // 主要信息区
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitle(theme, maxLines: 2),
                  _buildTagRow(theme),
                  if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      thread.excerpt!,
                      maxLines: hasCover ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              _buildFooter(theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTitle(ThemeData theme, {int maxLines = 2}) {
    final thread = widget.thread;
    return Text(
      thread.title,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 14.5,
        height: 1.35,
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  /// 标题下方标签行（置顶/精/荐/热/版块分类），无标签时返回空
  Widget _buildTagRow(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final thread = widget.thread;
    final tags = <(String, Color, Color)>[];

    if (thread.isSticky) {
      tags.add(('置顶', Colors.white, const Color(0xFFE53935)));
    }
    if (thread.stamp != null && thread.stamp!.isNotEmpty) {
      if (thread.stamp == '美图') {
        tags.add(('美图', Colors.white, const Color(0xFFE91E63)));
      } else if (thread.stamp == '原创') {
        tags.add(('原创', Colors.white, const Color(0xFF8E24AA)));
      } else if (thread.stamp == '优秀') {
        tags.add(('优秀', Colors.white, const Color(0xFF00ACC1)));
      } else if (!thread.isDigest && !thread.isRecommend && !thread.isSticky) {
        tags.add((thread.stamp!, Colors.white, const Color(0xFF43A047)));
      }
    }
    if (thread.isDigest) {
      tags.add(('精', Colors.white, const Color(0xFFF59E0B)));
    }
    if (thread.isRecommend) {
      tags.add((
        thread.recommendCount > 0 ? '荐${thread.recommendCount}' : '荐',
        Colors.white,
        const Color(0xFFFF6B35),
      ));
    }
    if (thread.isHot) {
      tags.add(('热', Colors.white, const Color(0xFFFF7043)));
    }
    if (thread.forumName != null && thread.forumName!.isNotEmpty) {
      tags.add((
        thread.forumName!,
        colorScheme.secondary,
        colorScheme.secondaryContainer.withAlpha(150),
      ));
    }
    if (thread.typeName != null &&
        thread.typeName!.isNotEmpty &&
        thread.typeName != thread.forumName) {
      tags.add((
        thread.typeName!,
        colorScheme.primary,
        colorScheme.primaryContainer.withAlpha(120),
      ));
    }
    if (thread.badge != null &&
        thread.badge!.isNotEmpty &&
        thread.badge != thread.forumName &&
        thread.badge != thread.typeName) {
      tags.add((
        thread.badge!,
        colorScheme.primary,
        colorScheme.primaryContainer,
      ));
    }
    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        children: [
          for (final (rawLabel, fg, bg) in tags)
            if (rawLabel.replaceAll(RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]', unicode: true), '').trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  rawLabel.replaceAll(RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]', unicode: true), '').trim(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    height: 1.2,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final thread = widget.thread;
    final hasAuthor = thread.author.isNotEmpty;
    final hasStats = thread.views > 0 || thread.replies > 0 || (thread.timeText != null && thread.timeText!.isNotEmpty);

    if (!hasAuthor && !hasStats) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (hasAuthor) ...[
          UserAvatarWidget(
            uid: thread.uid,
            author: thread.author,
            size: 18,
            faceUrl: thread.faceUrl,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: widget.onAuthorTap,
              borderRadius: BorderRadius.circular(4),
              child: Text(
                thread.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ] else ...[
          const Spacer(),
        ],
        if (thread.views > 0) ...[
          Icon(
            Icons.visibility_outlined,
            size: 13,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 3),
          Text(
            thread.views > 9999
                ? '${(thread.views / 10000).toStringAsFixed(1)}w'
                : '${thread.views}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (thread.replies > 0) ...[
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 12,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 3),
          Text(
            '${thread.replies}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (thread.recommendCount > 0) ...[
          Icon(
            Icons.thumb_up_outlined,
            size: 12,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 3),
          Text(
            '${thread.recommendCount}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (thread.timeText != null && thread.timeText!.isNotEmpty)
          Text(
            thread.timeText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
              fontSize: 11,
            ),
          ),
      ],
    );
  }
}
