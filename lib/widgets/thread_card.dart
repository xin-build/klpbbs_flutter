import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/comiis_parser.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../models/thread_summary.dart';
import 'facemall_frame_widget.dart';
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

  /// 规范化与清洗挂件 URL（自动处理 ##SJ## 分隔符、相对路径并映射到原站真实附件路径，且严禁将用户头像作为挂件渲染）
  static String? sanitizeFaceUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    var url = rawUrl.trim();
    if (url.isEmpty || url == 'none' || url == '0' || url == 'null' || url == 'false') return null;

    // 1. 优先提取 ##SJ## 挂件分隔符后方内容（Discuz sunju_facemall 插件规范：avatar_middle.jpg##SJ##fm_1.png）
    if (url.contains('##SJ##')) {
      final parts = url.split('##SJ##');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        url = parts[1].trim();
      } else {
        return null;
      }
    }
    if (url.isEmpty || url == 'none' || url == '0' || url == 'null' || url == 'false') return null;

    // 2. 挂件安全过滤：用户纯头像 URL（avatar/noavatar/jpg/jpeg/avatar.php）绝不是挂件！
    if (url.contains('/avatar/') ||
        url.contains('noavatar') ||
        url.contains('_avatar_') ||
        url.contains('avatar.php') ||
        url.toLowerCase().endsWith('.jpg') ||
        url.toLowerCase().endsWith('.jpeg')) {
      return null;
    }

    // 3. 智能映射：苦力怕论坛 sunju_facemall 挂件真实存储路径为 data/attachment/sunju_facemall/...
    if (url.contains('keishi_klp_') || url.contains('sunju_facemall/')) {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        final base = AppConfig.baseUrl.endsWith('/') ? AppConfig.baseUrl : '${AppConfig.baseUrl}/';
        return '$base${url.startsWith('/') ? url.substring(1) : url}';
      }
      return url;
    }

    // 4. 支持纯数字 ID（如 '1', '2'）或 fm_{id}（如 'fm_1', 'fm_1.png'）
    final numMatch = RegExp(r'^(?:template/img/|img/|fm_)?(\d+)(?:\.png)?$', caseSensitive: false).firstMatch(url);
    if (numMatch != null) {
      final id = numMatch.group(1)!;
      return '${AppConfig.baseUrl}data/attachment/sunju_facemall/fm_$id.png';
    }

    // 5. 支持内置官方挂件名称标识（供 FacemallFrameWidget 矢量直接绘制）
    final lower = url.toLowerCase();
    if (lower.contains('killer_seven') ||
        lower.contains('seven') ||
        lower.contains('yotsuba') ||
        lower.contains('christmas') ||
        lower.contains('xueba') ||
        lower.contains('aotu') ||
        lower.contains('brother_take') ||
        lower.contains('girls_frontline') ||
        lower.contains('experiment_family') ||
        lower.contains('haruhara') ||
        lower.contains('melon') ||
        lower.contains('creeper') ||
        lower.contains('myanee') ||
        lower.contains('diamond') ||
        lower.contains('dragon') ||
        lower.contains('netherite') ||
        lower.contains('wither') ||
        lower.contains('klee') ||
        lower.contains('cat') ||
        lower.contains('galaxy') ||
        lower.contains('刺客伍六七') ||
        lower.contains('中野四叶') ||
        lower.contains('圣诞节快乐') ||
        lower.contains('圣诞') ||
        lower.contains('学霸') ||
        lower.contains('凹凸世界') ||
        lower.contains('快把我哥带走') ||
        lower.contains('少女前线') ||
        lower.contains('实验品家庭') ||
        lower.contains('春原庄') ||
        lower.contains('吃瓜') ||
        lower.contains('苦力怕') ||
        lower.contains('喵内') ||
        lower.contains('钻石剑') ||
        lower.contains('末影龙') ||
        lower.contains('下界合金') ||
        lower.contains('凋灵') ||
        lower.contains('可莉') ||
        lower.contains('猫耳') ||
        lower.contains('星空')) {
      return url;
    }

    // 6. 仅当包含 attachment 或 facemall 且以 .png 结尾时才允许作为自定义挂件
    if ((url.contains('attachment') || url.contains('facemall')) && url.toLowerCase().endsWith('.png')) {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        final base = AppConfig.baseUrl.endsWith('/') ? AppConfig.baseUrl : '${AppConfig.baseUrl}/';
        return '$base${url.startsWith('/') ? url.substring(1) : url}';
      }
      return url;
    }

    if ((url.startsWith('http://') || url.startsWith('https://')) && url.toLowerCase().endsWith('.png')) {
      return url;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = author.isNotEmpty ? author.characters.first : '?';
    final effectiveUid = (uid != null && uid! > 0) ? uid : KlpbbsApi.getCachedAuthorUid(author);
    final hasUid = effectiveUid != null && effectiveUid > 0;
    final resolvedUrl = (avatarUrl != null && avatarUrl!.isNotEmpty)
        ? avatarUrl
        : (hasUid ? AppConfig.avatarUrl(effectiveUid, size: size >= 32 ? 'middle' : 'small') : null);

    Widget imageContent;
    if (resolvedUrl != null && AppConfig.imageQuality != ImageQuality.noImage) {
      final avatarMemSize = (size * 2.5).clamp(48, 256).toInt();
      imageContent = CachedNetworkImage(
        imageUrl: resolvedUrl,
        cacheManager: KlpbbsCacheManager.instance,
        httpHeaders: AppConfig.imageHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        memCacheWidth: avatarMemSize,
        memCacheHeight: avatarMemSize,
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

    final clipMode = size <= 28 ? Clip.hardEdge : Clip.antiAlias;
    Widget avatar;
    switch (AppConfig.avatarShape) {
      case AvatarShape.circle:
        avatar = ClipOval(clipBehavior: clipMode, child: imageContent);
        break;
      case AvatarShape.roundedRect:
        avatar = ClipRRect(
          clipBehavior: clipMode,
          borderRadius: BorderRadius.circular(size * 0.25),
          child: imageContent,
        );
        break;
      case AvatarShape.hexagon:
        avatar = ClipRRect(
          clipBehavior: clipMode,
          borderRadius: BorderRadius.circular(size * 0.35),
          child: imageContent,
        );
        break;
    }

    // 解析挂件有效 URL（若组件未直接传入且为当前登录用户，则自动使用全局设置的挂件）
    final myUid = KlpbbsApi.currentCachedMyUid;
    final myUsername = KlpbbsApi.currentCachedMyUsername;
    final isMe = author == '我' ||
        (uid != null && uid! > 0 && myUid != null && uid == myUid) ||
        (author.isNotEmpty && myUsername != null && author == myUsername);

    final rawFace = (faceUrl != null && faceUrl!.isNotEmpty)
        ? faceUrl
        : (isMe ? (AppConfig.myFaceUrl ?? KlpbbsApi.cachedSpace?.faceUrl) : null);

    final cleanUrl = sanitizeFaceUrl(rawFace);

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
      Widget? pendantWidget;
      if (cleanUrl != null && cleanUrl.isNotEmpty) {
        if (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://')) {
          pendantWidget = CachedNetworkImage(
            imageUrl: cleanUrl,
            cacheManager: KlpbbsCacheManager.instance,
            httpHeaders: AppConfig.imageHeaders,
            width: faceSize,
            height: faceSize,
            fit: BoxFit.contain,
            placeholder: (_, __) => FacemallFrameWidget(
              frameIdOrUrl: cleanUrl,
              size: faceSize,
            ),
            errorWidget: (_, __, ___) => FacemallFrameWidget(
              frameIdOrUrl: cleanUrl,
              size: faceSize,
            ),
          );
        } else {
          pendantWidget = FacemallFrameWidget(
            frameIdOrUrl: cleanUrl,
            size: faceSize,
          );
        }
      }

      result = SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            avatar,
            if (pendantWidget != null)
              Positioned(
                width: faceSize,
                height: faceSize,
                child: IgnorePointer(child: pendantWidget),
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
  String? _resolvedForum;
  List<(String, Color, Color)>? _cachedTags;
  int? _cachedTagsTid;
  String? _cachedTagsForum;
  Brightness? _cachedTagsBrightness;

  static final _tagUnicodeRegExp = RegExp(
    r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
    unicode: true,
  );
  static final _tagBracketRegExp = RegExp(r'^[\[【\s]+|[\]】\s]+$');

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
    if (_resolvedForum == null &&
        widget.thread.tid > 0 &&
        (widget.thread.forumName == null || widget.thread.forumName!.isEmpty)) {
      // 方案 C：异步轻量补全版块（仅在真正缺失且未推断时触发）
      KlpbbsApi.resolveThreadForumAsync(widget.thread.tid).then((res) {
        if (mounted && res != null && res.isNotEmpty && res != _resolvedForum) {
          setState(() {
            _resolvedForum = res;
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

    final cardWidget = Card(
      margin: widget.isGrid
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: colorScheme.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withAlpha(45),
          width: 0.8,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: colorScheme.surfaceContainerHigh,
        splashColor: colorScheme.primary.withAlpha(25),
        highlightColor: colorScheme.primary.withAlpha(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
      case CardStyle.minimal:
        return _buildMinimalLayout(context);
      case CardStyle.magazine:
        return _buildMagazineLayout(context);
      case CardStyle.modernCard:
        return _buildModernCardLayout(context);
    }
  }

  List<String> get _cardImages {
    if (!AppConfig.showThreadListImages || AppConfig.imageQuality == ImageQuality.noImage) {
      return const [];
    }
    final list = <String>[];
    for (final url in widget.thread.imageUrls) {
      final trimmed = url.trim();
      if (trimmed.isNotEmpty && !list.contains(trimmed)) {
        list.add(trimmed);
      }
      if (list.length >= 3) break;
    }
    if (list.isEmpty && widget.thread.coverUrl != null && widget.thread.coverUrl!.trim().isNotEmpty) {
      list.add(widget.thread.coverUrl!.trim());
    }
    return list;
  }

  Widget _buildImagesPreview(BuildContext context, ColorScheme colorScheme) {
    final images = _cardImages;
    if (images.isEmpty) return const SizedBox.shrink();

    if (images.length == 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: RetryImage(
              imageUrl: images[0],
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.low,
              memCacheWidth: 720,
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
              errorWidget: (_, __, ___) => Container(
                color: colorScheme.surfaceContainerHighest.withAlpha(80),
                child: Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: colorScheme.outlineVariant.withAlpha(120),
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (images.length == 2) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: RetryImage(
                    imageUrl: images[0],
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.low,
                    memCacheWidth: 400,
                    placeholder: (_, __) => Container(
                      color: colorScheme.surfaceContainerHighest.withAlpha(80),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: colorScheme.surfaceContainerHighest.withAlpha(80),
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
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: RetryImage(
                    imageUrl: images[1],
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.low,
                    memCacheWidth: 400,
                    placeholder: (_, __) => Container(
                      color: colorScheme.surfaceContainerHighest.withAlpha(80),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: colorScheme.surfaceContainerHighest.withAlpha(80),
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
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          for (int i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: RetryImage(
                    imageUrl: images[i],
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.low,
                    memCacheWidth: 320,
                    placeholder: (_, __) => Container(
                      color: colorScheme.surfaceContainerHighest.withAlpha(80),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: colorScheme.surfaceContainerHighest.withAlpha(80),
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
            ),
          ],
        ],
      ),
    );
  }

  /// 16:9 大图流 / 标准卡片布局
  Widget _buildLargeCoverLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = widget.thread;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle(theme),
        if (thread.excerpt != null && thread.excerpt!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            thread.excerpt!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withAlpha(220),
              height: 1.38,
              fontSize: 13,
            ),
          ),
        ],
        _buildImagesPreview(context, colorScheme),
        const SizedBox(height: 8),
        _buildFooter(theme),
      ],
    );
  }

  /// 紧凑图文行布局（高信息密度）
  Widget _buildCompactLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = widget.thread;
    final images = _cardImages;
    final hasThumbnail = images.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle(theme),
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
              const SizedBox(height: 6),
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

  /// 网格/桌面卡片布局（优化排版：信息强制对齐置底，规整严谨，移除高开销 LayoutBuilder 避免布局嵌套延迟）
  Widget _buildGridLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thread = widget.thread;
    final images = _cardImages;
    final hasCover = images.isNotEmpty;
    final hasBoundedHeight = widget.isGrid;

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
    final thread = widget.thread;
    final images = _cardImages;
    final hasThumbnail = images.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部小作者与时间微标签
        Row(
          children: [
            UserAvatarWidget(
              uid: thread.uid,
              author: thread.author,
              size: 18,
              faceUrl: thread.faceUrl,
            ),
            const SizedBox(width: 6),
            Expanded(
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

        // 极简底部状态：点赞、浏览与回复
        Row(
          children: [
            if (thread.views > 0) ...[
              Icon(Icons.visibility_outlined, size: 12, color: colorScheme.outline),
              const SizedBox(width: 3),
              Text('${thread.views}', style: TextStyle(fontSize: 10.5, color: colorScheme.outline)),
              const SizedBox(width: 10),
            ],
            Icon(Icons.chat_bubble_outline_rounded, size: 11.5, color: colorScheme.outline),
            const SizedBox(width: 3),
            Text('${thread.replies}', style: TextStyle(fontSize: 10.5, color: colorScheme.outline)),
            if (thread.recommendCount > 0) ...[
              const SizedBox(width: 10),
              Icon(Icons.thumb_up_outlined, size: 11.5, color: colorScheme.outline),
              const SizedBox(width: 3),
              Text('${thread.recommendCount}', style: TextStyle(fontSize: 10.5, color: colorScheme.outline)),
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
    final thread = widget.thread;
    final images = _cardImages;
    final hasCover = images.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasCover) ...[
          // 杂志全景头图 + 悬浮类型胶囊
          Stack(
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              uid: thread.uid,
              author: thread.author,
              size: 24,
              faceUrl: thread.faceUrl,
            ),
            const SizedBox(width: 8),
            Text(
              thread.author,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
                  Icon(Icons.chat_bubble_rounded, size: 11, color: colorScheme.primary),
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
    final thread = widget.thread;
    final images = _cardImages;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧彩色指示条
          Container(
            width: 3.5,
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
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 作者信息与版块
                Row(
                  children: [
                    UserAvatarWidget(
                      uid: thread.uid,
                      author: thread.author,
                      size: 20,
                      faceUrl: thread.faceUrl,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        thread.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (thread.timeText != null)
                      Text(
                        formatThreadTime(thread.timeText!),
                        style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                _buildTitle(theme, maxLines: 2),

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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.comment_outlined, size: 11, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text('${thread.replies}', style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (thread.views > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.visibility_outlined, size: 11, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 3),
                            Text('${thread.views}', style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                    if (thread.recommendCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.thumb_up_rounded, size: 10.5, color: Colors.orange.shade800),
                            const SizedBox(width: 3),
                            Text('${thread.recommendCount}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
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
      ),
    );
  }

  List<(String, Color, Color)> _getTags(ThemeData theme) {
    final forumToDisplay = _resolvedForum ??
        ComiisParser.resolveForumName(
          tid: widget.thread.tid,
          fid: widget.thread.fid,
          rawForumName: widget.thread.forumName,
          title: widget.thread.title,
          typeName: widget.thread.typeName,
        );

    if (_cachedTags != null &&
        _cachedTagsTid == widget.thread.tid &&
        _cachedTagsForum == forumToDisplay &&
        _cachedTagsBrightness == theme.brightness) {
      return _cachedTags!;
    }

    final colorScheme = theme.colorScheme;
    final thread = widget.thread;
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
    if (thread.isRecommend) {
      addTag(
        thread.recommendCount > 0 ? '荐${thread.recommendCount}' : '荐',
        Colors.white,
        const Color(0xFFEA580C),
      );
    }
    if (thread.isHot) {
      addTag('热', Colors.white, const Color(0xFFF97316));
    }

    if (forumToDisplay != null && forumToDisplay.isNotEmpty) {
      addTag(
        forumToDisplay,
        colorScheme.primary,
        colorScheme.primaryContainer.withAlpha(160),
      );
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

    _cachedTags = tags;
    _cachedTagsTid = thread.tid;
    _cachedTagsForum = forumToDisplay;
    _cachedTagsBrightness = theme.brightness;
    return tags;
  }

  Widget _buildTitle(ThemeData theme, {int maxLines = 2}) {
    final thread = widget.thread;
    final tags = _getTags(theme);

    return Text.rich(
      TextSpan(
        children: [
          for (final (cleanLabel, fg, bg) in tags)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                margin: const EdgeInsets.only(right: 5),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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
              fontSize: 14.5,
              height: 1.35,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
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
            color: colorScheme.onSurfaceVariant.withAlpha(180),
          ),
          const SizedBox(width: 3),
          Text(
            thread.views > 9999
                ? '${(thread.views / 10000).toStringAsFixed(1)}w'
                : '${thread.views}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withAlpha(200),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (thread.replies > 0) ...[
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 12,
            color: colorScheme.onSurfaceVariant.withAlpha(180),
          ),
          const SizedBox(width: 3),
          Text(
            '${thread.replies}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withAlpha(200),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (thread.recommendCount > 0) ...[
          Icon(
            Icons.thumb_up_outlined,
            size: 12,
            color: colorScheme.onSurfaceVariant.withAlpha(180),
          ),
          const SizedBox(width: 3),
          Text(
            '${thread.recommendCount}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withAlpha(200),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (thread.timeText != null && thread.timeText!.isNotEmpty)
          Text(
            formatThreadTime(thread.timeText!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withAlpha(200),
              fontSize: 11.5,
            ),
          ),
      ],
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
    final fullMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}:\d{2}))?').firstMatch(trimmed);
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
    final shortMatch = RegExp(r'^(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}:\d{2}))?$').firstMatch(trimmed);
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
    final cnMatch = RegExp(r'^(?:(\d{4})年)?(\d{1,2})月(\d{1,2})日(?:\s+(\d{1,2}:\d{2}))?').firstMatch(trimmed);
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
