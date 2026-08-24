import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/comiis_parser.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../models/thread_summary.dart';
import 'retry_image.dart';

/// 自定义形状头像组件
class UserAvatarWidget extends StatelessWidget {
  final int? uid;
  final String author;
  final String? avatarUrl;
  final double size;

  /// 头像挂件（sunju_facemall）URL，空表示无
  final String? faceUrl;

  /// 是否在线
  final bool? isOnline;

  /// 是否显示在线状态角标（默认 false）
  final bool showOnlineBadge;

  /// 点击回调
  final VoidCallback? onTap;

  const UserAvatarWidget({
    super.key,
    this.uid,
    this.author = '',
    this.avatarUrl,
    this.size = 20,
    this.faceUrl,
    this.isOnline,
    this.showOnlineBadge = false,
    this.onTap,
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
    final effectiveUid = (uid != null && uid! > 0) ? uid : KlpbbsApi.getCachedAuthorUid(author);
    final hasUid = effectiveUid != null && effectiveUid > 0;
    final resolvedUrl = (avatarUrl != null && avatarUrl!.isNotEmpty)
        ? avatarUrl
        : (hasUid ? AppConfig.avatarUrl(effectiveUid, size: size >= 40 ? 'middle' : 'small') : null);

    Widget imageContent;
    if (resolvedUrl != null && AppConfig.imageQuality != ImageQuality.noImage) {
      imageContent = CachedNetworkImage(
        imageUrl: resolvedUrl,
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
        color: theme.colorScheme.primaryContainer,
        width: size,
        height: size,
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimaryContainer,
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

    final Widget? onlineBadge = (showOnlineBadge && isOnline == true)
        ? Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size >= 36 ? 10.5 : (size >= 24 ? 8.5 : 7.0),
              height: size >= 36 ? 10.5 : (size >= 24 ? 8.5 : 7.0),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: size >= 36 ? 2.0 : 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          )
        : null;

    final hasDecoration =
        (cleanUrl != null && cleanUrl.isNotEmpty) || onlineBadge != null;

    Widget result;
    // 头像挂件（sunju_facemall）与在线状态角标
    if (hasDecoration) {
      final faceSize = size * 1.75;
      result = SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            avatar,
            if (cleanUrl != null && cleanUrl.isNotEmpty)
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
            if (onlineBadge != null) onlineBadge,
          ],
        ),
      );
    } else {
      result = avatar;
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: result);
    }
    return result;
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
  String? _resolvedForum;

  @override
  void initState() {
    super.initState();
    _checkAndResolveForum();
  }

  @override
  void didUpdateWidget(covariant ThreadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thread.tid != widget.thread.tid ||
        oldWidget.thread.fid != widget.thread.fid ||
        oldWidget.thread.forumName != widget.thread.forumName) {
      _checkAndResolveForum();
    }
  }

  void _checkAndResolveForum() {
    _resolvedForum = ComiisParser.resolveForumName(
      tid: widget.thread.tid,
      fid: widget.thread.fid,
      rawForumName: widget.thread.forumName,
      title: widget.thread.title,
      typeName: widget.thread.typeName,
    );
    if (_resolvedForum == null || _resolvedForum!.isEmpty) {
      KlpbbsApi.resolveThreadForumAsync(widget.thread.tid).then((forum) {
        if (mounted && forum != null && forum.isNotEmpty) {
          setState(() {
            _resolvedForum = forum;
          });
        }
      });
    }
  }

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

  /// 标题下方标签行（置顶/精/荐/热/版块分类），保证每个帖子均有版块标识并彻底去重
  Widget _buildTagRow(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final thread = widget.thread;
    final tags = <(String, Color, Color)>[];
    final seenTexts = <String>{};

    void addTag(String? rawLabel, Color fg, Color bg) {
      if (rawLabel == null || rawLabel.isEmpty) return;
      final clean = rawLabel
          .replaceAll(
            RegExp(
              r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
              unicode: true,
            ),
            '',
          )
          .replaceAll(RegExp(r'^[\[【\s]+|[\]】\s]+$'), '')
          .replaceAll('来自', '')
          .trim();
      if (clean.isEmpty) return;
      final norm = clean.toLowerCase();

      // 去重检查：防止相同或包含关系的版块/分类标签重复出现（例如 [人才市场] 与 人才市场，或 BE附加包 与 附加包）
      for (final existing in seenTexts) {
        if (existing == norm) return;
        if (existing.length >= 2 && norm.length >= 2) {
          if (existing.contains(norm) || norm.contains(existing)) return;
        }
      }

      seenTexts.add(norm);
      tags.add((clean, fg, bg));
    }

    if (thread.isSticky) {
      addTag('置顶', Colors.white, const Color(0xFFE53935));
    }
    if (thread.stamp != null && thread.stamp!.isNotEmpty) {
      if (thread.stamp == '美图') {
        addTag('美图', Colors.white, const Color(0xFFE91E63));
      } else if (thread.stamp == '原创') {
        addTag('原创', Colors.white, const Color(0xFF8E24AA));
      } else if (thread.stamp == '优秀') {
        addTag('优秀', Colors.white, const Color(0xFF00ACC1));
      } else if (!thread.isDigest && !thread.isRecommend && !thread.isSticky) {
        addTag(thread.stamp!, Colors.white, const Color(0xFF43A047));
      }
    }
    if (thread.isDigest) {
      addTag('精', Colors.white, const Color(0xFFF59E0B));
    }
    if (thread.isRecommend) {
      addTag(
        thread.recommendCount > 0 ? '荐${thread.recommendCount}' : '荐',
        Colors.white,
        const Color(0xFFFF6B35),
      );
    }
    if (thread.isHot) {
      addTag('热', Colors.white, const Color(0xFFFF7043));
    }

    // 确保每个帖子均展示 100% 准确的版块识别标签
    final forumToDisplay = _resolvedForum ??
        ComiisParser.resolveForumName(
          tid: thread.tid,
          fid: thread.fid,
          rawForumName: thread.forumName,
          title: thread.title,
          typeName: thread.typeName,
        );

    if (forumToDisplay != null && forumToDisplay.isNotEmpty) {
      addTag(
        forumToDisplay,
        colorScheme.secondary,
        colorScheme.secondaryContainer.withAlpha(150),
      );
    }

    if (thread.typeName != null && thread.typeName!.isNotEmpty) {
      addTag(
        thread.typeName!,
        colorScheme.primary,
        colorScheme.primaryContainer.withAlpha(120),
      );
    }

    if (thread.badge != null && thread.badge!.isNotEmpty) {
      addTag(
        thread.badge!,
        colorScheme.primary,
        colorScheme.primaryContainer,
      );
    }

    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        children: [
          for (final (cleanLabel, fg, bg) in tags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                cleanLabel,
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
