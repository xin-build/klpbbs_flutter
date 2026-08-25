import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../api/comiis_parser.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/url_helper.dart';
import '../models/post_block.dart';
import '../models/post_floor.dart';
import '../services/download_service.dart';
import '../widgets/skeleton_list.dart';
import 'bili_video_player.dart';
import 'general_audio_player.dart';
import 'general_video_player.dart';
import 'inline_html_text.dart';
import 'klpbbs_download_dialog.dart';
import 'netease_music_player.dart';
import 'retry_image.dart';

/// Discuz 帖子流式富媒体排版引擎
/// 完美还原原帖顺序结构：图文混排、代码块高亮与复制、引用、折叠、表格、视频与网盘提取码
class DiscuzPostRenderer extends StatelessWidget {
  final PostFloor floor;
  final int tid;
  final VoidCallback? onQuoteReply;
  final VoidCallback? onQuickReply;

  const DiscuzPostRenderer({
    super.key,
    required this.floor,
    this.tid = 0,
    this.onQuoteReply,
    this.onQuickReply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = floor.blocks;

    if (blocks.isEmpty) {
      // 兜底退化为旧式 HTML spans 解析
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (floor.lastEdited != null && floor.lastEdited!.isNotEmpty)
            _buildLastEditedNotice(theme, floor.lastEdited!),
          SelectableText.rich(
            TextSpan(
              children: _htmlToSpans(floor.contentHtml, theme, context: context),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (floor.lastEdited != null && floor.lastEdited!.isNotEmpty)
          _buildLastEditedNotice(theme, floor.lastEdited!),
        for (int i = 0; i < blocks.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _buildBlock(context, theme, blocks[i]),
          ),
      ],
    );
  }

  Widget _buildLastEditedNotice(ThemeData theme, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(40),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_note_rounded,
            size: 16,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlock(BuildContext context, ThemeData theme, PostBlock block) {
    return switch (block) {
      ResourceInfoBlock() => _buildResourceInfoBlock(context, theme, block),
      TextBlock(:final html, :final align) =>
        _buildTextBlock(context, theme, html, align: align),
      ImageBlock(
        :final src,
        :final alt,
        :final caption,
        :final isEmoji,
        :final align,
      ) =>
        _buildImageBlock(
          context,
          theme,
          src,
          alt: alt,
          caption: caption,
          isEmoji: isEmoji,
          align: align,
        ),
      QuoteBlock(:final author, :final contentHtml, :final align) =>
        _buildQuoteBlock(
          context,
          theme,
          author,
          contentHtml,
          align: align,
        ),
      CodeBlock(:final code, :final language, :final align) =>
        _buildCodeBlock(
          context,
          theme,
          code,
          language: language,
          align: align,
        ),
      SpoilerBlock(:final title, :final contentHtml) => _buildSpoilerBlock(
        context,
        theme,
        title,
        contentHtml,
      ),
      TableBlock(:final headers, :final rows, :final align) =>
        _buildTableBlock(
          context,
          theme,
          headers,
          rows,
          align: align,
        ),
      VideoBlock(
        :final src,
        :final isBilibili,
        :final bvid,
        :final aid,
        :final align,
      ) =>
        _buildVideoBlock(
          context,
          theme,
          src,
          isBilibili,
          bvid,
          aid,
          align: align,
        ),
      AudioBlock(:final src, :final title, :final align) => _buildAudioBlock(
        context,
        theme,
        src,
        title,
        align: align,
      ),
      AttachmentBlock(
        :final name,
        :final url,
        :final sizeText,
        :final priceText,
        :final iconUrl,
        :final uploadTime,
        :final downloadCount,
        :final align,
      ) =>
        _buildAttachmentBlock(
          context,
          theme,
          name,
          url,
          sizeText,
          priceText,
          iconUrl,
          uploadTime,
          downloadCount,
          align: align,
        ),
      BountyBlock() => _buildBountyBlock(context, theme, block),
      PollBlock() => _buildPollBlock(context, theme, block),
      ReplyRewardBlock() => _buildReplyRewardBlock(context, theme, block),
      DebateBlock() => _buildDebateBlock(context, theme, block),
      AuditStatusBlock() => _buildAuditStatusBlock(context, theme, block),
      NetdiskBlock(:final panName, :final url, :final extractCode, :final align) =>
        _buildNetdiskBlock(
          context,
          theme,
          panName,
          url,
          extractCode,
          align: align,
        ),
      HideBlock(:final reason) => _buildHideBlock(context, theme, reason),
      ShieldBlock(:final title, :final reason, :final iconType) =>
        _buildShieldBlock(context, theme, title, reason, iconType),
    };
  }

  // 0.1 处罚/屏蔽/封禁/审核状态提示卡片（Discuz 提示: 作者被禁止或删除 内容自动屏蔽 等）
  Widget _buildShieldBlock(
    BuildContext context,
    ThemeData theme,
    String title,
    String reason,
    String? iconType,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final isBanned = iconType == 'banned' || reason.contains('禁止') || reason.contains('删除');
    final isReview = iconType == 'review' || reason.contains('审核');
    final isLocked = iconType == 'locked' || reason.contains('锁定');

    final Color primaryColor = isBanned
        ? (isDark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F))
        : isReview
            ? (isDark ? const Color(0xFFFFB74D) : const Color(0xFFF57C00))
            : isLocked
                ? (isDark ? const Color(0xFF90CAF9) : const Color(0xFF1976D2))
                : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100));

    final Color bgColor = isDark
        ? primaryColor.withAlpha(25)
        : primaryColor.withAlpha(15);

    final Color borderColor = primaryColor.withAlpha(80);

    final IconData iconData = isBanned
        ? Icons.block_rounded
        : isReview
            ? Icons.hourglass_empty_rounded
            : isLocked
                ? Icons.lock_outline_rounded
                : Icons.visibility_off_outlined;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(iconData, size: 20, color: primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reason.isNotEmpty ? reason : '提示: 内容自动屏蔽',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: primaryColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 0. 悬赏问答专属卡片（完全还原网页版：黄底金边、悬赏金额、我来回答按钮与金币袋，完美适配深浅主题）
  Widget _buildBountyBlock(BuildContext context, ThemeData theme, BountyBlock bounty) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2210) : const Color(0xFFFFFDF0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF7A5910) : const Color(0xFFFFE082),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.monetization_on_rounded, color: Color(0xFFFFA000), size: 20),
                    const SizedBox(width: 6),
                    Text(
                      '悬赏',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFFE082) : Colors.brown[800],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${bounty.price}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFF8F00),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      bounty.unit,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? const Color(0xFFFFD54F) : Colors.brown[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: onQuickReply,
                      child: const Text('我来回答', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bounty.message ?? '您的回答被采纳后将获得${bounty.price}粒铁粒',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9800).withAlpha(60),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  // 0. 投票帖专属卡片（支持单选/多选交互、倒计时、选项列表、投票提交、投票数与占比进度条）
  Widget _buildPollBlock(BuildContext context, ThemeData theme, PollBlock poll) {
    return _InteractivePollCard(poll: poll, tid: tid);
  }

  // 0. 回帖奖励专属卡片（红包/金币袋视觉，深浅主题自适应）
  Widget _buildReplyRewardBlock(BuildContext context, ThemeData theme, ReplyRewardBlock rwd) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2008) : const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF7A5410) : const Color(0xFFFFD54F),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.redeem_rounded, color: Color(0xFFF57C00), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      rwd.totalReward > 0 ? '总共奖励 ${rwd.totalReward} ${rwd.unit}' : '回帖奖励',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  rwd.perReplyReward > 0
                      ? '回复本帖可获得 ${rwd.perReplyReward} ${rwd.unit}奖励! 每人限 ${rwd.limitCount} 次'
                      : rwd.rawText,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white70 : Colors.brown[700],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFFF9800),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.card_giftcard, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  // 0. 辩论帖卡片
  Widget _buildDebateBlock(BuildContext context, ThemeData theme, DebateBlock debate) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('正方观点', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  const SizedBox(height: 4),
                  Text(debate.affirmpoint, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('反方观点', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 4),
                  Text(debate.negatpoint, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 0. 审核通过状态条
  Widget _buildAuditStatusBlock(BuildContext context, ThemeData theme, AuditStatusBlock audit) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '本主题由 ${audit.auditor} 于 ${audit.timeText} 审核通过',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }

  // 1. 纯文本与富文本段落
  Widget _buildTextBlock(
    BuildContext context,
    ThemeData theme,
    String html, {
    String? align,
  }) {
    TextAlign? textAlign;
    if (align == 'center') {
      textAlign = TextAlign.center;
    } else if (align == 'right') {
      textAlign = TextAlign.right;
    } else if (align == 'justify') {
      textAlign = TextAlign.justify;
    } else if (align == 'left') {
      textAlign = TextAlign.left;
    }

    return SizedBox(
      width: double.infinity,
      child: Text.rich(
        TextSpan(
          children: _htmlToSpans(
            html,
            theme,
            context: context,
            defaultAlign: textAlign,
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.55,
            fontSize: 14.5,
          ),
        ),
        textAlign: textAlign ?? TextAlign.start,
      ),
    );
  }

  // 2. 行内/独占图片（高分辨率、灯箱画廊、右键复制与保存）
  Widget _buildImageBlock(
    BuildContext context,
    ThemeData theme,
    String src, {
    String? alt,
    String? caption,
    bool isEmoji = false,
    String? align,
  }) {
    if (AppConfig.imageQuality == ImageQuality.noImage) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 16,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Text(
              '图片已在无图省流模式下隐藏 [点击查看]',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    // 表情小图：按原始比例（约 20px）渲染，不放大、不进灯箱
    if (isEmoji) {
      const size = 22.0;
      final emojiWidget = Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: CachedNetworkImage(
          imageUrl: _absolute(src),
          httpHeaders: AppConfig.imageHeaders,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => const SizedBox(width: size, height: size),
        ),
      );
      if (align == 'center') {
        return Center(child: emojiWidget);
      } else if (align == 'right') {
        return Align(alignment: Alignment.centerRight, child: emojiWidget);
      }
      return emojiWidget;
    }

    final imageUrl = _absolute(src);
    final isCentered = align == 'center';
    final isRight = align == 'right';

    final imageWidget = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _openLightbox(context, imageUrl),
          onSecondaryTapDown: (details) =>
              _showImageContextMenu(context, details.globalPosition, imageUrl),
          child: RepaintBoundary(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isCentered
                  ? CrossAxisAlignment.center
                  : (isRight
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 700,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: RetryImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const PulsePlaceholder(
                        width: 280,
                        height: 180,
                        radius: BorderRadius.all(Radius.circular(8)),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withAlpha(80),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withAlpha(60),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              size: 20,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '图片加载失败（点击重试或查看原图）',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (caption != null && caption.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (isCentered) {
      return Center(child: imageWidget);
    } else if (isRight) {
      return Align(alignment: Alignment.centerRight, child: imageWidget);
    }
    return imageWidget;
  }

  // 3. 引用块
  Widget _buildQuoteBlock(
    BuildContext context,
    ThemeData theme,
    String author,
    String contentHtml, {
    String? align,
  }) {
    final quoteWidget = Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(70),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.format_quote_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '$author 说道：',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText.rich(
            TextSpan(
              children: _htmlToSpans(contentHtml, theme, context: context),
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.normal,
              height: 1.5,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );

    if (align == 'center') {
      return Center(child: quoteWidget);
    } else if (align == 'right') {
      return Align(alignment: Alignment.centerRight, child: quoteWidget);
    }
    return quoteWidget;
  }

  // 4. 代码块（带行号与一键复制按钮）
  Widget _buildCodeBlock(
    BuildContext context,
    ThemeData theme,
    String code, {
    String? language,
    String? align,
  }) {
    final lines = code.split('\n');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFF2D3139),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(40),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 代码头信息栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(40),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.code_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  language != null && language.isNotEmpty
                      ? language
                      : '代码 · ${lines.length} 行',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'Consolas',
                    fontFamilyFallback: ['monospace', 'Courier New'],
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制全部代码到剪贴板'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: Colors.white70,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '复制代码',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 代码内容区（横向可滚动，纵向超过 360 可滚动，避免长代码撑爆楼层）
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 行号列
                    SelectableText(
                      List.generate(
                        lines.length,
                        (i) => '${i + 1}'.padLeft(3),
                      ).join('\n'),
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontFamilyFallback: [
                          'monospace',
                          'Courier New',
                          'PingFang SC',
                          'Microsoft YaHei',
                        ],
                        fontSize: 13,
                        color: Color(0xFF7A7F8C),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SelectableText.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontFamilyFallback: [
                            'monospace',
                            'Courier New',
                            'PingFang SC',
                            'Microsoft YaHei',
                            'Noto Color Emoji',
                            'Apple Color Emoji',
                            'Segoe UI Emoji',
                          ],
                          fontSize: 13,
                          color: Color(0xFFD4D4D4),
                          height: 1.5,
                        ),
                        children: _highlightCode(code),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 资源帖分类信息卡片（模组/附加包/皮肤/软件等分类表单）
  Widget _buildResourceInfoBlock(
    BuildContext context,
    ThemeData theme,
    ResourceInfoBlock block,
  ) {
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withAlpha(70),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 卡片标题头（分类名 + 属性统计）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withAlpha(120),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.primary.withAlpha(40),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  block.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${block.fields.length} 项参数',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 属性列表
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (int i = 0; i < block.fields.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 12,
                      thickness: 0.5,
                      color: colorScheme.outlineVariant.withAlpha(60),
                    ),
                  _buildResourceFieldRow(context, theme, block.fields[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceFieldRow(
    BuildContext context,
    ThemeData theme,
    ResourceInfoField field,
  ) {
    final colorScheme = theme.colorScheme;
    final hasUrl = field.url != null && field.url!.isNotEmpty;
    final isDownloadOrSource =
        field.label.contains('下载') ||
        field.label.contains('原帖') ||
        field.label.contains('地址') ||
        field.label.contains('链接');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 属性标签
        SizedBox(
          width: 85,
          child: Text(
            field.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.outline,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 属性值（支持超链接跳转、复制、高亮）
        Expanded(
          child: hasUrl
              ? Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    InkWell(
                      onTap: () => _openLink(context, field.url!),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDownloadOrSource
                              ? colorScheme.primary.withAlpha(25)
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDownloadOrSource
                                ? colorScheme.primary.withAlpha(80)
                                : colorScheme.outlineVariant.withAlpha(80),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isDownloadOrSource
                                  ? Icons.download_rounded
                                  : Icons.open_in_new_rounded,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                field.value.startsWith('http')
                                    ? _shortDisplayUrl(field.value)
                                    : field.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      visualDensity: VisualDensity.compact,
                      tooltip: '复制链接',
                      color: colorScheme.outline,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: field.url!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已复制「${field.label}」链接到剪贴板'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                )
              : SelectableText(
                  field.value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    height: 1.35,
                    color: colorScheme.onSurface,
                    fontWeight: field.label.contains('版本') ||
                            field.label.contains('名称') ||
                            field.label.contains('中文名')
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
        ),
      ],
    );
  }

  // 5. 折叠 / Spoiler 块
  Widget _buildSpoilerBlock(
    BuildContext context,
    ThemeData theme,
    String title,
    String contentHtml,
  ) {
    final subBlocks = ComiisParser.parseStructuredBlocksFromHtml(contentHtml);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          backgroundColor: theme.colorScheme.surfaceContainerLow.withAlpha(50),
          collapsedBackgroundColor: theme.colorScheme.surfaceContainerLow
              .withAlpha(25),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Icon(
            Icons.visibility_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: subBlocks.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final b in subBlocks)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: _buildBlock(context, theme, b),
                          ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: Text.rich(
                        TextSpan(
                          children: _htmlToSpans(
                            contentHtml,
                            theme,
                            context: context,
                          ),
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.55,
                          fontSize: 14.0,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 6. 表格渲染（增强版：支持无表头自适应、单元格等长补齐与水平流畅滚动）
  Widget _buildTableBlock(
    BuildContext context,
    ThemeData theme,
    List<String> headers,
    List<List<String>> rows, {
    String? align,
  }) {
    if (headers.isEmpty && rows.isEmpty) return const SizedBox.shrink();

    // 确定最大列数
    int maxCols = headers.length;
    for (final row in rows) {
      if (row.length > maxCols) maxCols = row.length;
    }
    if (maxCols == 0) return const SizedBox.shrink();

    // 当无表头且有大于1行数据时，第一行作为表头高亮展示
    List<String> actualHeaders = List.from(headers);
    List<List<String>> actualRows = List.from(rows);
    if (actualHeaders.isEmpty && actualRows.length > 1) {
      actualHeaders = actualRows.removeAt(0);
    }

    final tableRows = <TableRow>[];

    // 1) 表头行
    if (actualHeaders.isNotEmpty) {
      final headerCells = <Widget>[];
      for (int c = 0; c < maxCols; c++) {
        final cellHtml = c < actualHeaders.length ? actualHeaders[c] : '';
        headerCells.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: theme.colorScheme.primaryContainer.withAlpha(80),
            child: InlineHtmlText(
              html: cellHtml,
              baseStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.0,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      tableRows.add(TableRow(children: headerCells));
    }

    // 2) 数据行
    for (int r = 0; r < actualRows.length; r++) {
      final row = actualRows[r];
      final rowCells = <Widget>[];
      for (int c = 0; c < maxCols; c++) {
        final cellHtml = c < row.length ? row[c] : '';
        rowCells.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: r.isEven
                ? theme.colorScheme.surface
                : theme.colorScheme.surfaceContainerHighest.withAlpha(35),
            child: InlineHtmlText(
              html: cellHtml,
              baseStyle: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        );
      }
      tableRows.add(TableRow(children: rowCells));
    }

    final tableWidget = Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(
            color: theme.colorScheme.outlineVariant.withAlpha(60),
            width: 0.8,
          ),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: tableRows,
        ),
      ),
    );

    if (align == 'center') {
      return Center(child: tableWidget);
    } else if (align == 'right') {
      return Align(alignment: Alignment.centerRight, child: tableWidget);
    }
    return tableWidget;
  }

  // 7. 视频 / Bilibili 内嵌播放卡片
  Widget _buildVideoBlock(
    BuildContext context,
    ThemeData theme,
    String src,
    bool isBilibili,
    String? bvid,
    String? aid, {
    String? align,
  }) {
    final isNetEase = src.contains('music.163.com') || src.contains('163.com');
    final title = isBilibili
        ? (bvid != null ? '哔哩哔哩视频 ($bvid)' : '哔哩哔哩视频')
        : isNetEase
        ? '网易云音乐'
        : '内嵌视频播放';

    Widget videoWidget;
    if (isBilibili && bvid != null) {
      videoWidget = Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(70),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.smart_display_outlined,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '在浏览器打开',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openLink(
                      context,
                      'https://www.bilibili.com/video/$bvid',
                    ),
                    icon: Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BiliVideoPlayer(bvid: bvid),
              ),
            ),
          ],
        ),
      );
    } else if (isNetEase) {
      final nid = RegExp(r'id=(\d+)').firstMatch(src)?.group(1);
      if (nid != null) {
        videoWidget = Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: NetEaseMusicPlayer(songId: nid),
        );
      } else {
        videoWidget = Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: GeneralVideoPlayer(src: src, title: title),
        );
      }
    } else {
      videoWidget = Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: GeneralVideoPlayer(src: src, title: title),
      );
    }

    if (align == 'center') {
      return Center(child: videoWidget);
    } else if (align == 'right') {
      return Align(alignment: Alignment.centerRight, child: videoWidget);
    }
    return videoWidget;
  }

  // 8. 音频播放条
  Widget _buildAudioBlock(
    BuildContext context,
    ThemeData theme,
    String src,
    String title, {
    String? align,
  }) {
    final isNetEase = src.contains('music.163.com') || src.contains('163.com');
    Widget audioWidget;
    if (isNetEase) {
      final nid = RegExp(r'id=(\d+)').firstMatch(src)?.group(1) ??
          RegExp(r'song/(\d+)').firstMatch(src)?.group(1);
      if (nid != null) {
        audioWidget = Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: NetEaseMusicPlayer(songId: nid),
        );
      } else {
        audioWidget = Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: GeneralAudioPlayer(src: src, title: title),
        );
      }
    } else {
      audioWidget = Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: GeneralAudioPlayer(src: src, title: title),
      );
    }

    if (align == 'center') {
      return Center(child: audioWidget);
    } else if (align == 'right') {
      return Align(alignment: Alignment.centerRight, child: audioWidget);
    }
    return audioWidget;
  }

  // 9. 附件下载卡片
  Widget _buildAttachmentBlock(
    BuildContext context,
    ThemeData theme,
    String name,
    String url,
    String? sizeText,
    String? priceText,
    String? iconUrl,
    String? uploadTime,
    int? downloadCount, {
    String? align,
  }) {
    final attachWidget = _AttachmentCardWidget(
      name: name,
      url: url,
      sizeText: sizeText,
      priceText: priceText,
      iconUrl: iconUrl,
      uploadTime: uploadTime,
      downloadCount: downloadCount,
    );

    if (align == 'center') {
      return Center(child: attachWidget);
    } else if (align == 'right') {
      return Align(alignment: Alignment.centerRight, child: attachWidget);
    }
    return attachWidget;
  }

  // 10. 网盘与提取码卡片
  Widget _buildNetdiskBlock(
    BuildContext context,
    ThemeData theme,
    String panName,
    String url,
    String extractCode, {
    String? align,
  }) {
    final netdiskWidget = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.secondary.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_download_rounded,
            color: theme.colorScheme.secondary,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  panName,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  extractCode.isNotEmpty ? '提取码: $extractCode' : '无提取码',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () {
              final clipText = extractCode.isNotEmpty
                  ? '$url 提取码: $extractCode'
                  : url;
              Clipboard.setData(ClipboardData(text: clipText));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('已复制 $panName 链接与提取码')));
            },
            icon: const Icon(Icons.copy_rounded, size: 15),
            label: const Text('复制链接与密码'),
          ),
        ],
      ),
    );

    if (align == 'center') {
      return Center(child: netdiskWidget);
    } else if (align == 'right') {
      return Align(alignment: Alignment.centerRight, child: netdiskWidget);
    }
    return netdiskWidget;
  }

  // 11. 隐藏内容提示
  Widget _buildHideBlock(BuildContext context, ThemeData theme, String reason) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            color: theme.colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onQuickReply != null)
            TextButton.icon(
              onPressed: onQuickReply,
              icon: const Icon(Icons.reply_rounded, size: 16),
              label: const Text('去回复'),
            ),
        ],
      ),
    );
  }

  // 弹出全屏图片画廊
  void _openLightbox(BuildContext context, String imageUrl) {
    final images = floor.images.isNotEmpty ? floor.images : [imageUrl];
    final initIndex = images.indexOf(imageUrl).clamp(0, images.length - 1);

    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(230),
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            PageView.builder(
              itemCount: images.length,
              controller: PageController(initialPage: initIndex),
              itemBuilder: (ctx, i) => Center(
                child: InteractiveViewer(
                  maxScale: 6,
                  minScale: 0.5,
                  child: CachedNetworkImage(
                    imageUrl: images[i],
                    httpHeaders: AppConfig.imageHeaders,
                    width: MediaQuery.of(ctx).size.width,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.copy_rounded,
                          color: Colors.white,
                        ),
                        tooltip: '复制图片链接',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: imageUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制图片直链')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        tooltip: '关闭 (Esc)',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 右键上下文菜单
  void _showImageContextMenu(
    BuildContext context,
    Offset position,
    String imageUrl,
  ) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          onTap: () {
            Clipboard.setData(ClipboardData(text: imageUrl));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已复制图片直链')));
          },
          child: const Row(
            children: [
              Icon(Icons.copy_rounded, size: 16),
              SizedBox(width: 8),
              Text('复制图片链接'),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => _openLightbox(context, imageUrl),
          child: const Row(
            children: [
              Icon(Icons.zoom_in_rounded, size: 16),
              SizedBox(width: 8),
              Text('全屏查看'),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () async {
            final uri = Uri.tryParse(imageUrl);
            if (uri != null) {
              await url_launcher.launchUrl(
                uri,
                mode: url_launcher.LaunchMode.externalApplication,
              );
            }
          },
          child: const Row(
            children: [
              Icon(Icons.open_in_browser_rounded, size: 16),
              SizedBox(width: 8),
              Text('在浏览器中打开'),
            ],
          ),
        ),
      ],
    );
  }

  // 内部 HTML TextSpan 解析
  /// 打开链接：站内帖子/版块/用户空间走应用内跳转，外部链接走系统浏览器
  void _openLink(BuildContext? context, String link) {
    UrlHelper.openLink(context, link);
  }

  List<InlineSpan> _htmlToSpans(
    String html,
    ThemeData theme, {
    BuildContext? context,
    TextAlign? defaultAlign,
  }) {
    if (html.isEmpty) return const [];

    final doc = html_parser.parseFragment(html);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      height: 1.55,
      fontSize: 14.5,
    );

    List<InlineSpan> walk(
      dynamic node,
      TextStyle? parent, {
      bool insideLink = false,
      String? linkHref,
    }) {
      final spans = <InlineSpan>[];
      final nodes = node is List ? node : (node.nodes ?? const []);
      for (final n in nodes) {
        if (n is html_dom.Text) {
          final text = _cleanContentText(n.text);
          if (text.isNotEmpty) {
            if (insideLink && linkHref != null && linkHref.isNotEmpty) {
              spans.add(
                TextSpan(
                  text: text,
                  style: parent,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => _openLink(context, linkHref),
                ),
              );
            } else {
              final urlRegex = RegExp(
                r'(https?://[^\s<>"，。]+|www\.[^\s<>"，。]+)',
                caseSensitive: false,
              );
              final matches = urlRegex.allMatches(text);
              if (matches.isNotEmpty) {
                int lastEnd = 0;
                for (final m in matches) {
                  if (m.start > lastEnd) {
                    spans.add(
                      TextSpan(
                        text: text.substring(lastEnd, m.start),
                        style: parent,
                      ),
                    );
                  }
                  final matchedUrl = m.group(0)!;
                  final linkStyle = (parent ?? baseStyle)?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  );
                  spans.add(
                    TextSpan(
                      text: matchedUrl,
                      style: linkStyle,
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _openLink(context, matchedUrl),
                    ),
                  );
                  lastEnd = m.end;
                }
                if (lastEnd < text.length) {
                  spans.add(
                    TextSpan(
                      text: text.substring(lastEnd),
                      style: parent,
                    ),
                  );
                }
              } else {
                spans.add(TextSpan(text: text, style: parent));
              }
            }
          }
        } else if (n is html_dom.Element) {
          final tag = n.localName ?? '';
          TextStyle? style = parent;
          switch (tag) {
            case 'b':
            case 'strong':
              style = (style ?? baseStyle)?.copyWith(
                fontWeight: FontWeight.bold,
              );
            case 'i':
            case 'em':
              style = (style ?? baseStyle)?.copyWith(
                fontStyle: FontStyle.italic,
              );
            case 'u':
              style = (style ?? baseStyle)?.copyWith(
                decoration: TextDecoration.underline,
              );
            case 's':
            case 'strike':
            case 'del':
              style = (style ?? baseStyle)?.copyWith(
                decoration: TextDecoration.lineThrough,
              );
            case 'font':
              final color = n.attributes['color'];
              if (color != null && color.isNotEmpty) {
                style = (style ?? baseStyle)?.copyWith(
                  color: _parseColor(
                    color,
                    brightness: theme.brightness,
                  ),
                );
              }
              final size = n.attributes['size'];
              if (size != null) {
                final s = double.tryParse(size);
                if (s != null) {
                  final cur = style?.fontSize ?? baseStyle?.fontSize ?? 14.5;
                  style = (style ?? baseStyle)?.copyWith(
                    fontSize: cur * (0.8 + s * 0.1),
                  );
                }
              }
          }

          // 通用 CSS 行内 style 属性解析（background-color, color, font-size, font-weight 等）
          final styleAttr = n.attributes['style'] ?? '';
          if (styleAttr.isNotEmpty) {
            final bgM = RegExp(
              r'background(?:-color)?\s*:\s*([^;]+)',
              caseSensitive: false,
            ).firstMatch(styleAttr);
            if (bgM != null) {
              final bgStr = bgM.group(1)!.trim();
              if (bgStr.isNotEmpty && bgStr != 'none' && bgStr != 'transparent') {
                final bgColor = _parseColor(
                  bgStr,
                  brightness: theme.brightness,
                  isBackground: true,
                );
                style = (style ?? baseStyle)?.copyWith(
                  backgroundColor: bgColor,
                );
              }
            }
            final colorM = RegExp(
              r'(?:^|;|\s)color\s*:\s*([^;]+)',
              caseSensitive: false,
            ).firstMatch(styleAttr);
            if (colorM != null) {
              final colorStr = colorM.group(1)!.trim();
              if (colorStr.isNotEmpty) {
                style = (style ?? baseStyle)?.copyWith(
                  color: _parseColor(
                    colorStr,
                    brightness: theme.brightness,
                  ),
                );
              }
            }
            final sizeM = RegExp(
              r'font-size\s*:\s*([^;]+)',
              caseSensitive: false,
            ).firstMatch(styleAttr);
            if (sizeM != null) {
              final sizeStr = sizeM.group(1)!.trim();
              final numVal = double.tryParse(
                sizeStr.replaceAll(RegExp(r'[^0-9.]'), ''),
              );
              if (numVal != null) {
                style = (style ?? baseStyle)?.copyWith(fontSize: numVal);
              }
            }
            final weightM = RegExp(
              r'font-weight\s*:\s*bold',
              caseSensitive: false,
            ).firstMatch(styleAttr);
            if (weightM != null) {
              style = (style ?? baseStyle)?.copyWith(
                fontWeight: FontWeight.bold,
              );
            }
          }

          if (tag == 'table') {
            final directTrs = <html_dom.Element>[];
            for (final child in n.children) {
              if (child.localName == 'tr') {
                directTrs.add(child);
              } else if (child.localName == 'tbody' ||
                  child.localName == 'thead') {
                for (final tr in child.children) {
                  if (tr.localName == 'tr') directTrs.add(tr);
                }
              }
            }
            final hasTh = n.querySelector('th') != null;
            final isLayoutTable = !hasTh &&
                (directTrs.isEmpty ||
                    directTrs.every(
                      (tr) =>
                          tr.children
                              .where((c) => c.localName == 'td')
                              .length <=
                          1,
                    ));
            // 布局表格（无 th 且每行最多 1 个 td）：扁平化展开子节点
            if (isLayoutTable) {
              spans.addAll(walk(n, style ?? baseStyle, insideLink: insideLink, linkHref: linkHref));
              continue;
            }
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _buildInlineTable(n, theme, context: context),
              ),
            );
            continue;
          }

          final align = _parseTextAlign(n) ?? defaultAlign;
          if (align != null && (tag == 'div' || tag == 'p' || tag == 'center')) {
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox(
                  width: double.infinity,
                  child: Text.rich(
                    TextSpan(
                      children: walk(n, style ?? baseStyle, insideLink: insideLink, linkHref: linkHref),
                      style: style ?? baseStyle,
                    ),
                    textAlign: align,
                  ),
                ),
              ),
            );
            continue;
          }

          if (tag == 'br') {
            spans.add(const TextSpan(text: '\n'));
          } else if (tag == 'a') {
            final href = n.attributes['href'] ?? '';
            if (href.isNotEmpty) {
              final link = _absolute(href);
              final linkStyle = (style ?? baseStyle)?.copyWith(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              );
              final childSpans = walk(
                n,
                linkStyle,
                insideLink: true,
                linkHref: link,
              );
              spans.addAll(childSpans);
            } else {
              spans.addAll(walk(n, style ?? baseStyle));
            }
          } else if (tag == 'img') {
            var rawSrc = n.attributes['comiis_loadimages'] ?? '';
            if (rawSrc.isEmpty ||
                rawSrc.contains('none.png') ||
                rawSrc.contains('spacer.gif')) {
              rawSrc = n.attributes['file'] ?? '';
            }
            if (rawSrc.isEmpty) {
              rawSrc = n.attributes['src'] ?? '';
            }
            if (rawSrc.isNotEmpty &&
                !rawSrc.contains('none.png') &&
                !rawSrc.contains('spacer.gif')) {
              final src = _absolute(rawSrc);
              final isEmoji =
                  src.contains('static/image/smiley/') ||
                  n.attributes.containsKey('smilieid');
              if (isEmoji) {
                const size = 20.0;
                spans.add(
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: CachedNetworkImage(
                      imageUrl: src,
                      httpHeaders: AppConfig.imageHeaders,
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) =>
                          const SizedBox(width: size, height: size),
                    ),
                  ),
                );
              }
            }
          } else {
            if (tag == 'li') {
              spans.add(const TextSpan(text: '• ')); // 列表项项目符号
            }
            spans.addAll(walk(n, style ?? baseStyle, insideLink: insideLink, linkHref: linkHref));
            if (tag == 'br') spans.add(const TextSpan(text: '\n'));
            if (tag == 'p' ||
                tag == 'div' ||
                tag == 'li' ||
                tag == 'ul' ||
                tag == 'ol') {
              spans.add(const TextSpan(text: '\n'));
            }
          }
        }
      }
      return spans;
    }

    return walk(doc, baseStyle);
  }

  List<TextSpan> _highlightCode(String code) {
    const keywordSet = {
      'if',
      'else',
      'for',
      'while',
      'return',
      'class',
      'void',
      'int',
      'double',
      'bool',
      'String',
      'var',
      'final',
      'const',
      'new',
      'true',
      'false',
      'null',
      'function',
      'def',
      'import',
      'package',
      'public',
      'private',
      'static',
      'switch',
      'case',
      'break',
      'continue',
      'try',
      'catch',
      'finally',
      'throw',
      'extends',
      'implements',
      'with',
      'enum',
      'async',
      'await',
      'print',
    };
    final colorDefault = const Color(0xFFD4D4D4);
    final colorKeyword = const Color(0xFF569CD6);
    final colorString = const Color(0xFFCE9178);
    final colorComment = const Color(0xFF6A9955);
    final colorNumber = const Color(0xFFB5CEA8);

    final spans = <TextSpan>[];
    final re = RegExp(
      r'(?:if|else|for|while|return|class|void|int|double|bool|String|var|final|const|new|true|false|null|function|def|import|package|public|private|static|switch|case|break|continue|try|catch|finally|throw|extends|implements|with|enum|async|await|print)|\d+(?:\.\d+)?',
      caseSensitive: false,
    );
    var last = 0;
    for (final m in re.allMatches(code)) {
      if (m.start > last) {
        spans.add(
          TextSpan(
            text: code.substring(last, m.start),
            style: const TextStyle(color: Color(0xFFD4D4D4)),
          ),
        );
      }
      final tok = m.group(0)!;
      Color color;
      if (tok.startsWith('//') || tok.startsWith('#')) {
        color = colorComment;
      } else if (tok.startsWith('"') || tok.startsWith("'")) {
        color = colorString;
      } else if (RegExp(r'^\d').hasMatch(tok)) {
        color = colorNumber;
      } else if (keywordSet.contains(tok)) {
        color = colorKeyword;
      } else {
        color = colorDefault;
      }
      spans.add(
        TextSpan(
          text: tok,
          style: TextStyle(color: color),
        ),
      );
      last = m.end;
    }
    if (last < code.length) {
      spans.add(
        TextSpan(
          text: code.substring(last),
          style: const TextStyle(color: Color(0xFFD4D4D4)),
        ),
      );
    }
    return spans;
  }

  Widget _buildInlineTable(
    html_dom.Element table,
    ThemeData theme, {
    BuildContext? context,
  }) {
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12.5,
      height: 1.4,
    );
    final rawRows = <List<Widget>>[];
    int maxCols = 0;
    for (final tr in table.querySelectorAll('tr')) {
      final cells = <Widget>[];
      for (final cell in tr.children.where(
        (c) => c.localName == 'td' || c.localName == 'th',
      )) {
        final isTh = cell.localName == 'th';
        cells.add(
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text.rich(
              TextSpan(
                children: _htmlToSpans(
                  cell.innerHtml,
                  theme,
                  context: context,
                ),
                style: (baseStyle ?? const TextStyle()).copyWith(
                  fontWeight: isTh ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }
      if (cells.isNotEmpty) {
        if (cells.length > maxCols) maxCols = cells.length;
        rawRows.add(cells);
      }
    }
    if (rawRows.isEmpty || maxCols == 0) return const SizedBox.shrink();

    final rows = <TableRow>[];
    for (final r in rawRows) {
      while (r.length < maxCols) {
        r.add(const Padding(padding: EdgeInsets.all(8), child: SizedBox.shrink()));
      }
      rows.add(TableRow(children: r));
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
            width: 0.5,
          ),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: rows,
        ),
      ),
    );
  }

  TextAlign? _parseTextAlign(html_dom.Element n) {
    final tag = (n.localName ?? '').toLowerCase();
    if (tag == 'center') return TextAlign.center;
    final a = (n.attributes['align'] ?? '').toLowerCase().trim();
    if (a == 'left' || a == 'start') return TextAlign.left;
    if (a == 'center') return TextAlign.center;
    if (a == 'right' || a == 'end') return TextAlign.right;
    if (a == 'justify') return TextAlign.justify;
    final style = n.attributes['style'] ?? '';
    final m = RegExp(
      r'text-align\s*:\s*(left|center|right|justify)',
      caseSensitive: false,
    ).firstMatch(style);
    if (m != null) {
      return switch (m.group(1)!.toLowerCase()) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'justify' => TextAlign.justify,
        _ => TextAlign.left,
      };
    }
    if (n.classes.contains('tac') ||
        n.classes.contains('text-center') ||
        n.classes.contains('comiis_align_center')) {
      return TextAlign.center;
    }
    return null;
  }

  Color _parseColor(
    String colorStr, {
    Brightness? brightness,
    bool isBackground = false,
  }) {
    Color baseColor;
    final trimmed = colorStr.trim().toLowerCase();
    if (trimmed.startsWith('#')) {
      final hex = trimmed.replaceFirst('#', '');
      if (hex.length == 6) {
        baseColor = Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 3) {
        final full = hex.split('').map((c) => '$c$c').join();
        baseColor = Color(int.parse('FF$full', radix: 16));
      } else if (hex.length == 8) {
        baseColor = Color(int.parse(hex, radix: 16));
      } else {
        baseColor = Colors.grey;
      }
    } else {
      const colorMap = {
        'red': Colors.red,
        'blue': Colors.blue,
        'green': Colors.green,
        'yellow': Colors.amber,
        'orange': Colors.orange,
        'purple': Colors.purple,
        'gray': Colors.grey,
        'grey': Colors.grey,
        'black': Colors.black,
        'white': Colors.white,
        'cyan': Colors.cyan,
        'pink': Colors.pink,
        'lime': Colors.lime,
        'indigo': Colors.indigo,
        'teal': Colors.teal,
        'brown': Colors.brown,
      };
      baseColor = colorMap[trimmed] ?? Colors.grey;
    }
    if (!isBackground) {
      final lum = baseColor.computeLuminance();
      if (brightness == Brightness.dark) {
        // 深色模式下：如果字体太暗（如纯黑 #000000、深灰、深蓝），自动提升为高对比度银白色
        if (lum < 0.28) {
          return const Color(0xFFE2E8F0);
        }
      } else if (brightness == Brightness.light) {
        // 浅色模式下：如果字体太亮（如纯白 #FFFFFF、极浅灰、浅黄），自动调整为高对比度深色
        if (lum > 0.82) {
          return const Color(0xFF1E293B);
        }
      }
    }
    return baseColor;
  }

  String _cleanContentText(String text) {
    return text.replaceAll(RegExp(r'[-​‎‏﻿]'), '');
  }

  String _shortDisplayUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    var path = uri.path;
    if (path.length > 30) {
      path = '${path.substring(0, 27)}...';
    }
    final query = uri.hasQuery ? '?...' : '';
    return '${uri.host}$path$query';
  }

  String _absolute(String href) {
    if (href.startsWith('http')) return href;
    var clean = href;
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    return '${AppConfig.baseUrl}$clean';
  }
}

/// 附件下载与进度卡片组件
class _AttachmentCardWidget extends StatefulWidget {
  final String name;
  final String url;
  final String? sizeText;
  final String? priceText;
  final String? iconUrl;
  final String? uploadTime;
  final int? downloadCount;

  const _AttachmentCardWidget({
    required this.name,
    required this.url,
    this.sizeText,
    this.priceText,
    this.iconUrl,
    this.uploadTime,
    this.downloadCount,
  });

  @override
  State<_AttachmentCardWidget> createState() => _AttachmentCardWidgetState();
}

class _AttachmentCardWidgetState extends State<_AttachmentCardWidget> {
  Color _fileBadgeColor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'zip' || 'rar' || '7z':
        return const Color(0xFFF57C00);
      case 'apk':
        return const Color(0xFF43A047);
      case 'pdf':
        return const Color(0xFFE53935);
      case 'doc' || 'docx':
        return const Color(0xFF1E88E5);
      case 'txt' || 'md':
        return const Color(0xFF5E35B1);
      case 'png' || 'jpg' || 'jpeg' || 'gif' || 'webp':
        return const Color(0xFF00BCD4);
      case 'mcpack' || 'mcaddon' || 'mcworld' || 'mcmeta':
        return const Color(0xFF7CB342);
      default:
        return const Color(0xFF757575);
    }
  }

  String _fileBadgeText(String name) {
    final ext = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : 'FILE';
    return ext.length > 6 ? ext.substring(0, 6) : ext;
  }

  String _absolute(String href) {
    if (href.startsWith('http')) return href;
    var clean = href;
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    return '${AppConfig.baseUrl}$clean';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final badgeColor = _fileBadgeColor(widget.name);

    return ListenableBuilder(
      listenable: DownloadManager.instance,
      builder: (context, _) {
        final task = DownloadManager.instance.getTaskByUrl(widget.url);
        final isDownloading = task?.status == DownloadStatus.downloading;
        final isCompleted = task?.status == DownloadStatus.completed;
        final isPaused = task?.status == DownloadStatus.paused;
        final isFailed = task?.status == DownloadStatus.failed;

        final icon = Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badgeColor.withAlpha(28),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: badgeColor.withAlpha(50), width: 0.6),
          ),
          child: widget.iconUrl != null && widget.iconUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: _absolute(widget.iconUrl!),
                  httpHeaders: AppConfig.imageHeaders,
                  width: 26,
                  height: 26,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => _fileBadge(widget.name, badgeColor),
                  errorWidget: (_, __, ___) => _fileBadge(widget.name, badgeColor),
                )
              : _fileBadge(widget.name, badgeColor),
        );

        Widget meta(IconData ic, String text, {Color? color}) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(70),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ic,
                  size: 11,
                  color: color ?? colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: color ?? colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(36),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDownloading
                  ? colorScheme.primary.withAlpha(120)
                  : colorScheme.outlineVariant.withAlpha(60),
              width: isDownloading ? 1.2 : 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(5),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (widget.sizeText != null && widget.sizeText!.isNotEmpty)
                              meta(Icons.sd_storage_outlined, widget.sizeText!),
                            if (widget.uploadTime != null && widget.uploadTime!.isNotEmpty)
                              meta(Icons.schedule_rounded, widget.uploadTime!),
                            if (widget.downloadCount != null)
                              meta(
                                Icons.download_rounded,
                                "${widget.downloadCount} 次",
                                color: colorScheme.primary,
                              ),
                            if (widget.priceText != null && widget.priceText!.isNotEmpty)
                              meta(
                                Icons.paid_rounded,
                                widget.priceText!,
                                color: const Color(0xFFE6A23C),
                              ),
                            if (isCompleted)
                              meta(
                                Icons.check_circle_rounded,
                                '已下载到本地',
                                color: const Color(0xFF43A047),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isDownloading || isPaused) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (task != null && task.totalBytes > 0) ? task.progress : null,
                    minHeight: 5,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      task?.sizeText ?? '',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                    ),
                    const Spacer(),
                    if (isDownloading && task != null && task.speed > 0)
                      Text(
                        task.speedText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isCompleted && task != null) ...[
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => DownloadManager.openFile(task.savePath),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('打开文件'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => DownloadManager.openFolder(task.savePath),
                      icon: const Icon(Icons.folder_open_rounded, size: 15),
                      label: const Text('打开目录'),
                    ),
                  ] else if (isDownloading && task != null) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => DownloadManager.instance.pauseDownload(task.id),
                      icon: const Icon(Icons.pause_rounded, size: 15),
                      label: const Text('暂停'),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => DownloadManager.instance.cancelDownload(task.id),
                      child: const Text('取消'),
                    ),
                  ] else if ((isPaused || isFailed) && task != null) ...[
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => DownloadManager.instance.resumeDownload(task.id),
                      icon: const Icon(Icons.play_arrow_rounded, size: 15),
                      label: const Text('继续下载'),
                    ),
                  ] else ...[
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () {
                        KlpbbsDownloadDialog.show(
                          context,
                          filename: widget.name,
                          url: widget.url,
                          sizeText: widget.sizeText,
                          priceText: widget.priceText,
                        );
                      },
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('下载'),
                    ),
                  ],
                  IconButton(
                    tooltip: '在浏览器中打开跳转下载页',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest.withAlpha(80),
                    ),
                    onPressed: () async {
                      var targetUrl = widget.url.trim();
                      if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
                        targetUrl = '${AppConfig.baseUrl}/$targetUrl'.replaceAll(RegExp(r'(?<!:)/+'), '/');
                      }
                      final uri = Uri.tryParse(targetUrl);
                      if (uri != null) {
                        await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '复制下载直链',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest.withAlpha(80),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('下载链接已复制')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _fileBadge(String name, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _fileBadgeText(name),
          maxLines: 1,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// 交互式投票卡片（支持单选/多选交互、选项状态切换与投票提交）
class _InteractivePollCard extends StatefulWidget {
  final PollBlock poll;
  final int tid;

  const _InteractivePollCard({
    required this.poll,
    this.tid = 0,
  });

  @override
  State<_InteractivePollCard> createState() => _InteractivePollCardState();
}

class _InteractivePollCardState extends State<_InteractivePollCard> {
  final Set<int> _selectedIds = {};
  bool _submitting = false;
  bool _isVoted = false;

  static const List<Color> _defaultBarColors = [
    Color(0xFFE92725), // 红色
    Color(0xFFF27B21), // 橙色
    Color(0xFFF2A61F), // 琥珀黄
    Color(0xFF5AAF4A), // 绿色
    Color(0xFF2196F3), // 蓝色
    Color(0xFF9C27B0), // 紫色
    Color(0xFF00BCD4), // 青色
    Color(0xFFFF4081), // 粉红
  ];

  static Color _parseBarColor(String? hex, int index) {
    if (hex != null && hex.isNotEmpty) {
      try {
        var str = hex.replaceAll('#', '').trim();
        if (str.length == 6) str = 'FF$str';
        if (str.length == 8) return Color(int.parse(str, radix: 16));
      } catch (_) {}
    }
    return _defaultBarColors[index % _defaultBarColors.length];
  }

  @override
  void initState() {
    super.initState();
    _isVoted = widget.poll.isVoted;
    for (var i = 0; i < widget.poll.options.length; i++) {
      final opt = widget.poll.options[i];
      if (opt.isChecked) {
        final optId = int.tryParse(opt.id) ?? (i + 1);
        _selectedIds.add(optId);
      }
    }
  }

  void _toggleOption(int optId) {
    if (_isVoted || widget.poll.isClosed || !widget.poll.canVote) return;
    setState(() {
      if (widget.poll.isMultiple) {
        if (_selectedIds.contains(optId)) {
          _selectedIds.remove(optId);
        } else {
          if (widget.poll.maxChoices <= 1 || _selectedIds.length < widget.poll.maxChoices) {
            _selectedIds.add(optId);
          }
        }
      } else {
        _selectedIds.clear();
        _selectedIds.add(optId);
      }
    });
  }

  Future<void> _submitVote() async {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再参与投票')),
      );
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择至少一个投票选项')),
      );
      return;
    }
    setState(() => _submitting = true);
    final ok = await KlpbbsApi.submitPoll(
      tid: widget.tid,
      optionIds: _selectedIds.toList(),
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (ok) _isVoted = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '投票成功！' : '投票失败，可能已过期或权限不足')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final poll = widget.poll;
    final showResults = _isVoted || poll.isClosed || !poll.canVote || poll.options.any((o) => o.votes > 0 || o.percent > 0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(80),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 投票头部
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 橙色圆形投票图标 (1:1 对齐网页)
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF9800),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        poll.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '共有 ${poll.votersCount} 人参与投票${poll.isMultiple ? ' (多选, 最多可选 ${poll.maxChoices} 项)' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (poll.expireText != null && poll.expireText!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(120),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      poll.expireText!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 14, endIndent: 14),

          // 投票选项列表 (1:1 像素级对齐网页)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: poll.options.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (ctx, i) {
              final opt = poll.options[i];
              final optId = int.tryParse(opt.id) ?? (i + 1);
              final isSelected = _selectedIds.contains(optId);
              final barColor = _parseBarColor(opt.colorHex, i);
              final cleanLabel = ComiisParser.cleanPollOptionLabel(opt.label);

              if (showResults) {
                // 结果展示模式：标题 + 彩色进度条 + 百分比 (票数)
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 选项名称
                      Text(
                        cleanLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 彩色进度条与票数
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                height: 9,
                                color: colorScheme.surfaceContainerHighest.withAlpha(120),
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: (opt.percent / 100).clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: barColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${opt.percent.toStringAsFixed(2)}% (${opt.votes})',
                            style: TextStyle(
                              fontSize: 12,
                              color: barColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              // 投票选择模式：Radio / Checkbox + 选项名称
              return InkWell(
                onTap: () => _toggleOption(optId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        poll.isMultiple
                            ? (isSelected ? Icons.check_box : Icons.check_box_outline_blank)
                            : (isSelected ? Icons.radio_button_checked : Icons.radio_button_off),
                        size: 20,
                        color: isSelected ? const Color(0xFFFF9800) : colorScheme.outline,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cleanLabel,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // 底部提示框或投票提交按钮 (1:1 对齐网页)
          if (poll.tipText != null && poll.tipText!.isNotEmpty)
            Builder(
              builder: (ctx) {
                final isDark = Theme.of(ctx).brightness == Brightness.dark;
                return Container(
                  margin: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2E2612) : const Color(0xFFFFFBE6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isDark ? const Color(0xFF6B4D16) : const Color(0xFFFFE58F)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: isDark ? const Color(0xFFFFA940) : const Color(0xFFFA8C16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          poll.tipText!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? const Color(0xFFFFD591) : const Color(0xFFD46B08),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          else if (!showResults && poll.canVote)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submitVote,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.how_to_vote_outlined, size: 16),
                  label: Text(_submitting ? '提交中...' : '提交投票'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9800),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

