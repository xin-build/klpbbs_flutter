import 'package:flutter/material.dart';

import '../api/comiis_parser.dart';
import '../core/app_config.dart';
import '../models/thread_summary.dart';
import 'retry_image.dart';
import 'user_avatar_widget.dart';

export 'user_avatar_widget.dart';

/// 帖子卡片（支持 16:9 大图流、紧凑图文行与网格卡片 3 种排版）
class ThreadCard extends StatefulWidget {
  final ThreadSummary thread;
  final VoidCallback? onTap;
  final VoidCallback? onAuthorTap;
  final bool isGrid;
  final bool adaptiveHeight;
  final int? rankIndex;
  final CardStyle? cardStyle;
  final EdgeInsetsGeometry? margin;

  const ThreadCard({
    super.key,
    required this.thread,
    this.onTap,
    this.onAuthorTap,
    this.isGrid = false,
    this.adaptiveHeight = false,
    this.rankIndex,
    this.cardStyle,
    this.margin,
  });

  @override
  State<ThreadCard> createState() => _ThreadCardState();
}

class _ThreadCardState extends State<ThreadCard> {
  String? _resolvedForum;
  bool get _fixedGrid => widget.isGrid && !widget.adaptiveHeight;

  ThreadSummary get _currentThread {
    final t = widget.thread;
    if (t.excerpt != null && t.excerpt!.isNotEmpty) {
      var cleaned = ComiisParser.cleanTextSnippet(t.excerpt!, maxLen: 120);
      if (cleaned.contains('审核通过') ||
          (cleaned.contains('由') && cleaned.contains('审核'))) {
        cleaned = cleaned
            .replaceAll(ComiisParser.auditNoticeRegExp, '')
            .replaceAll(ComiisParser.auditNoticeGeneralRegExp, '')
            .trim();
      }
      final puncOnly = RegExp(r'^[\s.。,，!！?？:：;；~～\-_—…]+$');
      if (puncOnly.hasMatch(cleaned)) {
        cleaned = '';
      }
      if (cleaned != t.excerpt) {
        return t.copyWith(excerpt: cleaned.isNotEmpty ? cleaned : null);
      }
    }
    return t;
  }

  static final _tagUnicodeRegExp = RegExp(
    r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
    unicode: true,
  );
  static final _tagBracketRegExp = RegExp(r'^[\[【\s]+|[\]】\s]+$');
  @override
  void initState() {
    super.initState();
    _resolveForumFromList();
  }

  @override
  void didUpdateWidget(covariant ThreadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.thread, widget.thread)) {
      _resolveForumFromList();
    }
  }

  // 列表中的脱敏作者、零计数和缺失封面均保留网页原值。
  // 卡片只查询已有版块映射；详情请求由用户打开帖子时触发。
  void _resolveForumFromList() {
    _resolvedForum = ComiisParser.resolveForumName(
      tid: widget.thread.tid,
      fid: widget.thread.fid,
      rawForumName: widget.thread.forumName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = _currentThread;
    final cardStyle =
        widget.cardStyle ?? (_fixedGrid ? CardStyle.grid : AppConfig.cardStyle);

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

    final isDark = theme.brightness == Brightness.dark;
    final cardColor = colorScheme.surfaceContainerLow;
    final borderColor = colorScheme.outlineVariant.withAlpha(isDark ? 45 : 55);

    final cardWidget = Card(
      margin: widget.margin ??
          (widget.isGrid
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 5)),
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: borderColor,
          width: 0.6,
        ),
      ),
      clipBehavior: Clip.none,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(22),
        hoverColor: colorScheme.surfaceContainerHigh.withAlpha(120),
        splashColor: colorScheme.primary.withAlpha(25),
        highlightColor: colorScheme.primary.withAlpha(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: 16, vertical: _fixedGrid ? 11 : 15),
          child: _buildCardContent(context, cardStyle),
        ),
      ),
    );

    return RepaintBoundary(child: cardWidget);
  }

  Widget _buildCardContent(BuildContext context, CardStyle style) {
    switch (style) {
      case CardStyle.compact:
        return _buildCompactLayout(context);
      case CardStyle.grid:
        return _buildGridLayout(context);
      case CardStyle.largeCover:
        return _buildLargeCoverLayout(context);
      case CardStyle.guideMultimodal:
        return _buildGuideMultimodalLayout(context);
      case CardStyle.forumClassic:
        return _buildForumClassicLayout(context);
      case CardStyle.minimal:
        return _buildMinimalLayout(context);
      case CardStyle.magazine:
        return _buildMagazineLayout(context);
      case CardStyle.modernCard:
        return _buildModernCardLayout(context);
    }
  }

  List<String> get _cardImages {
    if (!AppConfig.showThreadListImages ||
        AppConfig.imageQuality == ImageQuality.noImage) {
      return const [];
    }
    final t = _currentThread;
    final list = <String>[];
    for (final url in t.imageUrls) {
      final trimmed = url.trim();
      if (trimmed.isNotEmpty &&
          !ComiisParser.isDividerImage(trimmed) &&
          !list.contains(trimmed)) {
        list.add(trimmed);
      }
      if (list.length >= 3) break;
    }
    if (list.isEmpty &&
        t.coverUrl != null &&
        t.coverUrl!.trim().isNotEmpty &&
        !ComiisParser.isDividerImage(t.coverUrl)) {
      list.add(t.coverUrl!.trim());
    }
    return list;
  }

  Widget _buildImagesPreview(BuildContext context, ColorScheme colorScheme) {
    final images = _cardImages;
    if (images.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: LayoutBuilder(builder: (context, constraints) {
        const gap = 6.0;
        final width = constraints.maxWidth;
        final imageWidth = (width - (images.length - 1) * gap) / images.length;
        final height = images.length == 1
            ? (width / 2.1).clamp(90.0, 180.0)
            : imageWidth.clamp(68.0, 120.0);
        return SizedBox(
          key: ValueKey('thread-images-preview-${widget.thread.tid}'),
          height: height,
          child: Row(children: [
            for (var i = 0; i < images.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(
                child: Semantics(
                  image: true,
                  label: '帖子预览图片 ${i + 1}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: RetryImage(
                      imageUrl: images[i],
                      width: imageWidth,
                      height: height,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      memCacheWidth:
                          (imageWidth * MediaQuery.devicePixelRatioOf(context))
                              .round()
                              .clamp(120, 900),
                      placeholder: (_, __) => ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: Center(
                            child: Icon(Icons.image_outlined,
                                color: colorScheme.outlineVariant, size: 24)),
                      ),
                      errorWidget: (_, __, ___) => ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: colorScheme.onSurfaceVariant, size: 24)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        );
      }),
    );
  }

  Widget _buildLargeCoverLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = _currentThread;
    final hasAuthor = thread.author.isNotEmpty;
    final rank = widget.rankIndex;
    final showMedal = rank != null && rank >= 1 && rank <= 3;
    final forumToDisplay = _resolvedForum ??
        ComiisParser.resolveForumName(
          tid: widget.thread.tid,
          fid: widget.thread.fid,
          rawForumName: widget.thread.forumName,
          title: widget.thread.title,
          typeName: widget.thread.typeName,
        );

    final showHeader = hasAuthor ||
        showMedal ||
        (forumToDisplay != null && forumToDisplay.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              if (hasAuthor) ...[
                UserAvatarWidget(
                  reserveFrameSpace: true,
                  uid: thread.uid,
                  author: thread.author,
                  size: 26,
                  faceUrl: thread.faceUrl,
                  onTap: widget.onAuthorTap,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: widget.onAuthorTap,
                        borderRadius: BorderRadius.circular(4),
                        child: Text(
                          thread.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (thread.timeText != null &&
                          thread.timeText!.isNotEmpty)
                        Text(
                          formatThreadTime(thread.timeText!),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
              ] else ...[
                // 未返回独立作者时，展示轻微骨架，等待异步详情填充真实作者，绝不再生硬显示“社区精选”
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(120),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withAlpha(140),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      if (thread.timeText != null &&
                          thread.timeText!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          formatThreadTime(thread.timeText!),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (showMedal) ...[
                _buildMedalBadge(rank),
                const SizedBox(width: 6),
              ],
              if (forumToDisplay != null && forumToDisplay.isNotEmpty)
                _buildForumPill(context, forumToDisplay),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // 标题（顶部已清晰标明版块与高光勋牌，标题区避免标签堆叠，大幅提升阅读节奏）
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: _fixedGrid ? 38 : 0),
          child: _buildTitle(
            theme,
            includeForumTag: false,
            includeRankTag: false,
            includeHotTag: false,
            maxLines: 2,
          ),
        ),

        if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            thread.excerpt!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withAlpha(220),
              height: 1.38,
              fontSize: 12.5,
            ),
          ),
        ],

        _buildImagesPreview(context, colorScheme),

        if (_fixedGrid) const Spacer() else const SizedBox(height: 10),

        _buildStatFooter(theme, showTime: false),
      ],
    );
  }

  /// 紧凑图文行布局（高信息密度）
  Widget _buildCompactLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = _currentThread;
    final images = _cardImages;
    final hasThumbnail = images.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle(theme, maxLines: 2),
              if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  thread.excerpt!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withAlpha(210),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _buildFooter(theme),
            ],
          ),
        ),
        if (hasThumbnail) ...[
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 92,
              height: 68,
              child: RetryImage(
                imageUrl: images.first,
                width: 92,
                height: 68,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.low,
                memCacheWidth: 280,
                placeholder: (_, __) => Container(
                  color: colorScheme.surfaceContainerHighest.withAlpha(60),
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: colorScheme.outlineVariant.withAlpha(120),
                      size: 20,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: colorScheme.surfaceContainerHighest.withAlpha(60),
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: colorScheme.outlineVariant.withAlpha(120),
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

  /// 版块经典风布局（左侧标签+标题+摘要+作者统计，右侧规整缩略图，纯正论坛体验）
  Widget _buildForumClassicLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = _currentThread;
    final images = _cardImages;
    final hasThumbnail = images.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧主要信息区
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle(theme,
                  maxLines: 2, includeForumTag: true, includeRankTag: true),
              if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  thread.excerpt!,
                  maxLines: hasThumbnail ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withAlpha(200),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _buildFooter(theme),
            ],
          ),
        ),
        // 右侧缩略图
        if (hasThumbnail) ...[
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 96,
              height: 70,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RetryImage(
                    imageUrl: images.first,
                    width: 96,
                    height: 70,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.low,
                    memCacheWidth: 280,
                    placeholder: (_, __) => Container(
                      color: colorScheme.surfaceContainerHighest.withAlpha(60),
                      child: Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: colorScheme.outlineVariant.withAlpha(120),
                          size: 20,
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: colorScheme.surfaceContainerHighest.withAlpha(60),
                      child: Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: colorScheme.outlineVariant.withAlpha(120),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(160),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_library_outlined,
                                size: 10, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              '${images.length}',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
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
        ],
      ],
    );
  }

  /// 导读画廊风布局（全景多图画廊、顶部作者徽章栏、醒目标题与综合互动栏）
  Widget _buildGuideMultimodalLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = _currentThread;
    final hasAuthor = thread.author.isNotEmpty;
    final forumToDisplay = _resolvedForum ??
        ComiisParser.resolveForumName(
          tid: widget.thread.tid,
          fid: widget.thread.fid,
          rawForumName: widget.thread.forumName,
          title: widget.thread.title,
          typeName: widget.thread.typeName,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 顶部作者与版块胶囊行
        Row(
          children: [
            if (hasAuthor) ...[
              UserAvatarWidget(
                reserveFrameSpace: true,
                uid: thread.uid,
                author: thread.author,
                size: 34,
                faceUrl: thread.faceUrl,
                onTap: widget.onAuthorTap,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: widget.onAuthorTap,
                      borderRadius: BorderRadius.circular(4),
                      child: Text(
                        thread.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (thread.timeText != null && thread.timeText!.isNotEmpty)
                      Text(
                        formatThreadTime(thread.timeText!),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ] else ...[
              const Spacer(),
            ],
            if (forumToDisplay != null && forumToDisplay.isNotEmpty) ...[
              _buildForumPill(context, forumToDisplay),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // 2. 标题
        _buildTitle(theme, maxLines: 2, includeForumTag: false),

        // 3. 摘要文本
        if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            thread.excerpt!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withAlpha(210),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],

        // 4. 多图画廊区域（1图大图、2图双列、3图三列画廊）
        _buildImagesPreview(context, colorScheme),

        const SizedBox(height: 10),

        // 5. 底部综合互动栏
        _buildStatFooter(theme, showTime: !hasAuthor),
      ],
    );
  }

  /// 网格/桌面卡片布局（优化排版：信息强制对齐置底，规整严谨，移除高开销 LayoutBuilder 避免布局嵌套延迟）
  Widget _buildGridLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = _currentThread;
    final images = _cardImages;
    final hasCover = images.isNotEmpty;
    final hasBoundedHeight = _fixedGrid;

    return Row(
      crossAxisAlignment: hasBoundedHeight
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        if (hasCover) ...[
          Align(
            alignment: Alignment.topLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 116,
                height: 88,
                child: RetryImage(
                  imageUrl: images.first,
                  width: 116,
                  height: 88,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.low,
                  memCacheWidth: 340,
                  placeholder: (_, __) => Container(
                    color: colorScheme.surfaceContainerHighest.withAlpha(60),
                    child: Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: colorScheme.outlineVariant.withAlpha(120),
                        size: 24,
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: colorScheme.surfaceContainerHighest.withAlpha(60),
                    child: Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: colorScheme.outlineVariant.withAlpha(120),
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle(theme, maxLines: 2),
              if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  thread.excerpt!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withAlpha(220),
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
              if (hasBoundedHeight)
                const Spacer()
              else
                const SizedBox(height: 6),
              _buildFooter(theme),
            ],
          ),
        ),
      ],
    );
  }

  /// 极简风卡片布局（去繁就简、通透留白、精致小标）
  Widget _buildMinimalLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = _currentThread;
    final images = _cardImages;
    final hasThumbnail = images.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部小作者与时间微标签
        Row(
          children: [
            UserAvatarWidget(
              reserveFrameSpace: true,
              uid: thread.uid,
              author: thread.author,
              size: 18,
              faceUrl: thread.faceUrl,
              onTap: widget.onAuthorTap,
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
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (thread.timeText != null && thread.timeText!.isNotEmpty)
              Text(
                formatThreadTime(thread.timeText!),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  color: colorScheme.outline,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),

        // 标题与缩略图（若有缩略图则右侧放置精致 68x68 方图）
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitle(theme, maxLines: 2),
                  if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      thread.excerpt!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withAlpha(200),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hasThumbnail) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: RetryImage(
                    imageUrl: images.first,
                    fit: BoxFit.cover,
                    memCacheWidth: 200,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // 极简底部状态：热度、浏览、回复与点赞
        Row(
          children: [
            if (thread.heatCount > 0 || thread.isHot) ...[
              const Icon(Icons.local_fire_department_rounded,
                  size: 12, color: Colors.deepOrangeAccent),
              const SizedBox(width: 2),
              Text(
                thread.heatCount > 0 ? '${thread.heatCount}' : '热门',
                style: const TextStyle(
                    fontSize: 10.5,
                    color: Colors.deepOrangeAccent,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 10),
            ],
            if (thread.views > 0) ...[
              Icon(Icons.visibility_outlined,
                  size: 12, color: colorScheme.outline),
              const SizedBox(width: 3),
              Text('${thread.views}',
                  style: TextStyle(fontSize: 10.5, color: colorScheme.outline)),
              const SizedBox(width: 10),
            ],
            Icon(Icons.chat_bubble_outline_rounded,
                size: 11.5, color: colorScheme.outline),
            const SizedBox(width: 3),
            Text('${thread.replies}',
                style: TextStyle(fontSize: 10.5, color: colorScheme.outline)),
            if (thread.recommendCount > 0) ...[
              const SizedBox(width: 10),
              Icon(Icons.thumb_up_outlined,
                  size: 11.5, color: colorScheme.outline),
              const SizedBox(width: 3),
              Text('${thread.recommendCount}',
                  style: TextStyle(fontSize: 10.5, color: colorScheme.outline)),
            ],
          ],
        ),
      ],
    );
  }

  /// 画报杂志风卡片布局（全景焦点大图、视觉冲击力排版与悬浮标签）
  Widget _buildMagazineLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = _currentThread;
    final images = _cardImages;
    final hasCover = images.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasCover) ...[
          // 杂志全景头图 + 悬浮类型胶囊
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 2.1,
                    child: RetryImage(
                      imageUrl: images.first,
                      fit: BoxFit.cover,
                      memCacheWidth: 800,
                    ),
                  ),
                ),
                if (_getTags(theme).isNotEmpty)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(160),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getTags(theme).first.$1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // 醒目杂志字阶标题
        Text(
          thread.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 15.5,
            letterSpacing: -0.2,
            height: 1.3,
          ),
        ),

        if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            thread.excerpt!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withAlpha(220),
              height: 1.35,
              fontSize: 12.5,
            ),
          ),
        ],

        const SizedBox(height: 10),
        // 杂志作者栏
        Row(
          children: [
            UserAvatarWidget(
              reserveFrameSpace: true,
              uid: thread.uid,
              author: thread.author,
              size: 24,
              faceUrl: thread.faceUrl,
              onTap: widget.onAuthorTap,
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: widget.onAuthorTap,
              borderRadius: BorderRadius.circular(4),
              child: Text(
                thread.author,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            if (thread.timeText != null && thread.timeText!.isNotEmpty) ...[
              Text(' · ', style: TextStyle(color: colorScheme.outline)),
              Text(
                formatThreadTime(thread.timeText!),
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(70),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_rounded,
                      size: 11, color: colorScheme.primary),
                  const SizedBox(width: 3),
                  Text(
                    '${thread.replies}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 现代微质感卡片布局（圆角 16、立体微阴影、主题侧彩带与彩色徽章）
  Widget _buildModernCardLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = _currentThread;
    final images = _cardImages;

    // Let the message column determine height once. IntrinsicHeight cannot
    // measure the responsive image strip and also doubles list layout work.
    return Stack(
      children: [
        // 左侧彩色指示条
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: 3.5,
          child: DecoratedBox(
              decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                thread.isSticky ? Colors.red : colorScheme.primary,
                thread.isDigest ? Colors.amber.shade700 : colorScheme.secondary,
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          )),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 13.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 作者信息与版块
              Row(
                children: [
                  UserAvatarWidget(
                    reserveFrameSpace: true,
                    uid: thread.uid,
                    author: thread.author,
                    size: 20,
                    faceUrl: thread.faceUrl,
                    onTap: widget.onAuthorTap,
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
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (thread.timeText != null)
                    Text(
                      formatThreadTime(thread.timeText!),
                      style:
                          TextStyle(fontSize: 10.5, color: colorScheme.outline),
                    ),
                ],
              ),
              const SizedBox(height: 6),

              _buildTitle(theme,
                  maxLines: 2, includeForumTag: false, includeRankTag: false),

              if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  thread.excerpt!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withAlpha(200),
                    fontSize: 12,
                  ),
                ),
              ],

              if (images.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildImagesPreview(context, colorScheme),
              ],

              const SizedBox(height: 8),
              // 现代胶囊状态
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.comment_outlined,
                            size: 11, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Text('${thread.replies}',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (thread.views > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_outlined,
                              size: 11, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text('${thread.views}',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                  if (thread.heatCount > 0 || thread.isHot) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withAlpha(25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department_rounded,
                              size: 10.5, color: Colors.deepOrangeAccent),
                          const SizedBox(width: 3),
                          Text(
                            thread.heatCount > 0 ? '${thread.heatCount}' : '热门',
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrangeAccent),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (thread.recommendCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.thumb_up_outlined,
                              size: 10.5, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            '${thread.recommendCount}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<(String, Color, Color)> _getTags(
    ThemeData theme, {
    bool includeForumTag = true,
    bool includeRankTag = false,
    bool includeHotTag = true,
  }) {
    final forumToDisplay = _resolvedForum ??
        ComiisParser.resolveForumName(
          tid: widget.thread.tid,
          fid: widget.thread.fid,
          rawForumName: widget.thread.forumName,
          title: widget.thread.title,
          typeName: widget.thread.typeName,
        );

    final colorScheme = theme.colorScheme;
    final thread = _currentThread;
    final tags = <(String, Color, Color)>[];
    final seenTexts = <String>{};

    void addTag(String? rawLabel, Color fg, Color bg) {
      if (rawLabel == null || rawLabel.isEmpty) return;
      final clean = rawLabel
          .replaceAll(_tagUnicodeRegExp, '')
          .replaceAll(_tagBracketRegExp, '')
          .replaceAll('来自', '')
          .trim();
      if (clean.isEmpty) return;
      // 强过滤：时间日期绝不作为标签展示（解决 Issue #6 列表时间重复问题）
      if (ComiisParser.isDateOrTime(clean)) return;

      final norm = clean.toLowerCase();
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
      addTag('精', Colors.white, const Color(0xFFD97706));
    }
    if (includeHotTag && thread.isHot) {
      addTag('热', Colors.white, const Color(0xFFF97316));
    }

    // 仅在未于 CardHeader 展示版块时添加版块标签，避免重复堆叠
    if (includeForumTag &&
        forumToDisplay != null &&
        forumToDisplay.isNotEmpty) {
      addTag(
        forumToDisplay,
        colorScheme.primary,
        colorScheme.primaryContainer.withAlpha(160),
      );
    } else if (!includeForumTag &&
        forumToDisplay != null &&
        forumToDisplay.isNotEmpty) {
      final cleanForum = forumToDisplay
          .replaceAll(_tagUnicodeRegExp, '')
          .replaceAll(_tagBracketRegExp, '')
          .replaceAll('来自', '')
          .trim()
          .toLowerCase();
      if (cleanForum.isNotEmpty) {
        seenTexts.add(cleanForum);
      }
    }

    if (thread.typeName != null && thread.typeName!.isNotEmpty) {
      addTag(
        thread.typeName!,
        colorScheme.secondary,
        colorScheme.secondaryContainer.withAlpha(160),
      );
    }

    if (thread.badge != null && thread.badge!.isNotEmpty) {
      addTag(
        thread.badge!,
        colorScheme.primary,
        colorScheme.primaryContainer.withAlpha(140),
      );
    }

    // 严选高光：仅前 3 名显示尊贵 TOP 勋标，拒绝全民 No.68 噪点堆叠
    if (includeRankTag &&
        widget.rankIndex != null &&
        widget.rankIndex! > 0 &&
        widget.rankIndex! <= 3) {
      final rank = widget.rankIndex!;
      final label = 'TOP $rank';
      final bg = rank == 1
          ? const Color(0xFFFFA000)
          : (rank == 2 ? const Color(0xFF78909C) : const Color(0xFFE65100));
      tags.insert(0, (label, Colors.white, bg));
    }

    return tags;
  }

  Widget _buildMedalBadge(int rank) {
    final (String icon, String label, Color c1, Color c2) = switch (rank) {
      1 => ('🥇', 'TOP 1', const Color(0xFFFFB300), const Color(0xFFFF6F00)),
      2 => ('🥈', 'TOP 2', const Color(0xFF90A4AE), const Color(0xFF546E7A)),
      3 => ('🥉', 'TOP 3', const Color(0xFFFF8A65), const Color(0xFFD84315)),
      _ => ('', 'TOP $rank', const Color(0xFF78909C), const Color(0xFF455A64)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c1, c2]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: c2.withAlpha(70),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon.isNotEmpty) ...[
            Text(icon, style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForumPill(BuildContext context, String forumName) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: scheme.secondaryContainer.withAlpha(120),
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(forumName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSecondaryContainer)),
        ),
      ),
    );
  }

  List<Widget> _buildCounters(ThemeData theme) {
    final thread = _currentThread;
    Widget counter(IconData icon, String label, String description,
        {Color? color}) {
      final foreground = color ?? theme.colorScheme.onSurfaceVariant;
      return Tooltip(
        message: '$description：$label',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 12, color: foreground)),
          ],
        ),
      );
    }

    return [
      if (thread.views >= 0)
        counter(
          Icons.visibility_outlined,
          thread.views > 9999
              ? '${(thread.views / 10000).toStringAsFixed(1)}w'
              : thread.views.toString(),
          '浏览',
        ),
      if (thread.replies >= 0)
        counter(
            Icons.chat_bubble_outline_rounded, thread.replies.toString(), '回复'),
      if (thread.recommendCount > 0)
        counter(
            Icons.thumb_up_outlined, thread.recommendCount.toString(), '推荐'),
      if (thread.heatCount > 0 || thread.isHot)
        counter(
          Icons.local_fire_department_rounded,
          thread.heatCount > 0 ? thread.heatCount.toString() : '热门',
          '热度',
          color: Colors.deepOrangeAccent,
        ),
    ];
  }

  Widget _buildStatFooter(ThemeData theme, {bool showTime = true}) {
    final thread = _currentThread;
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            children: _buildCounters(theme),
          ),
        ),
        if (showTime && thread.timeText?.isNotEmpty == true) ...[
          const SizedBox(width: 8),
          Flexible(child: _footerTime(theme)),
        ],
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded,
            size: 14, color: theme.colorScheme.outline),
      ],
    );
  }

  Widget _buildTitle(
    ThemeData theme, {
    int maxLines = 2,
    bool includeForumTag = true,
    bool includeRankTag = false,
    bool includeHotTag = true,
  }) {
    final thread = _currentThread;
    final tags = _getTags(
      theme,
      includeForumTag: includeForumTag,
      includeRankTag: includeRankTag,
      includeHotTag: includeHotTag,
    );

    return Text.rich(
      TextSpan(
        children: [
          for (final (cleanLabel, fg, bg) in tags)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                margin: const EdgeInsets.only(right: 5),
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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
            ),
          TextSpan(
            text: thread.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: _fixedGrid ? 14.5 : 16,
              height: 1.45,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _footerTime(ThemeData theme) {
    final time = _currentThread.timeText ?? '';
    return Tooltip(
      message: time,
      child: Text(
        formatThreadTime(time),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.5, color: theme.colorScheme.outline),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    final thread = _currentThread;
    final counters = _buildCounters(theme);
    final hasTime = thread.timeText?.isNotEmpty == true;
    final hasAuthor = thread.author.isNotEmpty;
    final forum = thread.forumName;
    if (!hasAuthor &&
        forum?.isNotEmpty != true &&
        !hasTime &&
        counters.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget identity({required bool showTime}) {
      return Row(
        children: [
          if (hasAuthor) ...[
            UserAvatarWidget(
              reserveFrameSpace: true,
              uid: thread.uid,
              author: thread.author,
              size: 18,
              faceUrl: thread.faceUrl,
              onTap: widget.onAuthorTap,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: InkWell(
              onTap: hasAuthor ? widget.onAuthorTap : null,
              borderRadius: BorderRadius.circular(4),
              child: Text(
                hasAuthor ? thread.author : (forum ?? ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (showTime && hasTime) ...[
            const SizedBox(width: 6),
            Flexible(child: _footerTime(theme)),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity(showTime: true),
              if (counters.isNotEmpty) ...[
                const SizedBox(height: 5),
                Wrap(spacing: 10, runSpacing: 3, children: counters),
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: identity(showTime: false)),
            const SizedBox(width: 8),
            Flexible(
              child: Wrap(
                spacing: 10,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                children: [
                  ...counters,
                  if (hasTime) _footerTime(theme),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String formatThreadTime(String raw) {
    if (raw.isEmpty) return '';
    final trimmed = raw.trim();
    if (trimmed.contains('前') ||
        trimmed.contains('昨天') ||
        trimmed.contains('今天') ||
        trimmed.contains('刚刚') ||
        trimmed == '近期') {
      return trimmed;
    }
    final now = DateTime.now();
    // 1. 匹配类似 2026-2-21 或 2026-02-21 或 2026-2-21 15:30
    final fullMatch =
        RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}:\d{2}))?')
            .firstMatch(trimmed);
    if (fullMatch != null) {
      final y = int.tryParse(fullMatch.group(1)!) ?? 0;
      final m = int.tryParse(fullMatch.group(2)!) ?? 0;
      final d = int.tryParse(fullMatch.group(3)!) ?? 0;
      final hm = fullMatch.group(4);
      final targetDate = DateTime(y, m, d);
      // 提升卡导致未来时间戳：统一规范显示为【已提升】
      if (targetDate.isAfter(now.add(const Duration(minutes: 5)))) {
        return '已提升';
      }
      if (y == now.year && m == now.month && d == now.day) {
        return hm != null ? '今天 $hm' : '今天';
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (y == yesterday.year && m == yesterday.month && d == yesterday.day) {
        return hm != null ? '昨天 $hm' : '昨天';
      }
      if (y == now.year) {
        return hm != null ? '$m月$d日 $hm' : '$m月$d日';
      }
      return hm != null ? '$y-$m-$d $hm' : '$y-$m-$d';
    }
    // 2. 匹配短格式 11-4 或 11-04 15:30
    final shortMatch = RegExp(r'^(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}:\d{2}))?$')
        .firstMatch(trimmed);
    if (shortMatch != null) {
      final m = int.tryParse(shortMatch.group(1)!) ?? 0;
      final d = int.tryParse(shortMatch.group(2)!) ?? 0;
      final hm = shortMatch.group(3);
      final targetDate = DateTime(now.year, m, d);
      // 提升卡导致未来时间戳：统一规范显示为【已提升】
      if (targetDate.isAfter(now.add(const Duration(minutes: 5)))) {
        return '已提升';
      }
      if (m == now.month && d == now.day) {
        return hm != null ? '今天 $hm' : '今天';
      }
      return hm != null ? '$m月$d日 $hm' : '$m月$d日';
    }
    // 3. 匹配中文格式 11月4日 或 2026年11月4日
    final cnMatch =
        RegExp(r'^(?:(\d{4})年)?(\d{1,2})月(\d{1,2})日(?:\s+(\d{1,2}:\d{2}))?')
            .firstMatch(trimmed);
    if (cnMatch != null) {
      final y = int.tryParse(cnMatch.group(1) ?? '') ?? now.year;
      final m = int.tryParse(cnMatch.group(2)!) ?? 0;
      final d = int.tryParse(cnMatch.group(3)!) ?? 0;
      final hm = cnMatch.group(4);
      final targetDate = DateTime(y, m, d);
      // 提升卡导致未来时间戳：统一规范显示为【已提升】
      if (targetDate.isAfter(now.add(const Duration(minutes: 5)))) {
        return '已提升';
      }
      if (y == now.year && m == now.month && d == now.day) {
        return hm != null ? '今天 $hm' : '今天';
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (y == yesterday.year && m == yesterday.month && d == yesterday.day) {
        return hm != null ? '昨天 $hm' : '昨天';
      }
      if (y == now.year) {
        return hm != null ? '$m月$d日 $hm' : '$m月$d日';
      }
      return hm != null ? '$y-$m-$d $hm' : '$y-$m-$d';
    }
    return trimmed;
  }
}
