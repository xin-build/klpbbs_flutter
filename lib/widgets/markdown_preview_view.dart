import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/comiis_parser.dart';
import '../core/bbcode.dart';
import '../models/post_floor.dart';
import '../models/smiley.dart';
import 'discuz_post_renderer.dart';
import 'image_viewer_dialog.dart';

/// 新 UI 风格全特性 Markdown / BBCode 智能预览组件
class MarkdownPreviewView extends StatefulWidget {
  final String content;
  final List<SmileyCategory>? customSmileys;
  final VoidCallback? onBackToEdit;
  final ValueChanged<String>? onApplyConvertedBBCode;
  final bool showHeader;
  final bool isSplitPane;

  const MarkdownPreviewView({
    super.key,
    required this.content,
    this.customSmileys,
    this.onBackToEdit,
    this.onApplyConvertedBBCode,
    this.showHeader = true,
    this.isSplitPane = false,
  });

  @override
  State<MarkdownPreviewView> createState() => _MarkdownPreviewViewState();
}

class _MarkdownPreviewViewState extends State<MarkdownPreviewView> {
  // 0: 智能混合排版 (Markdown + BBCode 自动识别与混排)
  // 1: 纯 Markdown 排版
  // 2: Discuz 原生 BBCode 效果
  int _previewMode = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = widget.content.trim();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部控制与统计栏
          if (widget.showHeader) _buildPreviewHeader(theme, text),

          // 预览正文区域
          Expanded(
            child: text.isEmpty
                ? _buildEmptyState(theme)
                : SelectionArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: _buildPreviewContent(theme, text),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 预览控制与统计顶栏（新 UI 风格）
  Widget _buildPreviewHeader(ThemeData theme, String text) {
    final colorScheme = theme.colorScheme;

    // 文档基础统计
    final charCount = text.length;
    final lineCount = text.isEmpty ? 0 : text.split('\n').length;
    final estMinutes = max(1, (charCount / 350).ceil());
    final codeBlockCount = RegExp(r'```[\s\S]*?```').allMatches(text).length;
    final imageCount = RegExp(r'!\[.*?\]\(.*?\)|\[img\].*?\[/img\]').allMatches(text).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(60),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 模式指示徽标
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 13,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '新 UI 实时排版预览',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 模式切换 Pills
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildModeChip(0, '智能混合', Icons.hub_outlined, theme),
                      const SizedBox(width: 4),
                      _buildModeChip(1, 'Markdown', Icons.article_outlined, theme),
                      const SizedBox(width: 4),
                      _buildModeChip(2, 'Discuz BBCode', Icons.forum_outlined, theme),
                    ],
                  ),
                ),
              ),

              // 右侧返回编辑或复制快捷按钮
              if (widget.onBackToEdit != null && !widget.isSplitPane) ...[
                TextButton.icon(
                  onPressed: widget.onBackToEdit,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('返回编辑', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // 下方信息胶囊统计条
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatPill(Icons.text_fields_rounded, '$charCount 字 / $lineCount 行', theme),
                const SizedBox(width: 6),
                _buildStatPill(Icons.timer_outlined, '约需 $estMinutes 分钟', theme),
                if (codeBlockCount > 0) ...[
                  const SizedBox(width: 6),
                  _buildStatPill(Icons.code_rounded, '$codeBlockCount 个代码块', theme),
                ],
                if (imageCount > 0) ...[
                  const SizedBox(width: 6),
                  _buildStatPill(Icons.image_outlined, '$imageCount 张图', theme),
                ],
                if (widget.onApplyConvertedBBCode != null && _previewMode == 1) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      final bb = markdownToBBCode(text);
                      widget.onApplyConvertedBBCode!(bb);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已将 Markdown 转换为 Discuz BBCode 插入编辑框'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer.withAlpha(120),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.transform_rounded, size: 12, color: colorScheme.secondary),
                          const SizedBox(width: 3),
                          Text('转为 BBCode', style: TextStyle(fontSize: 10.5, color: colorScheme.secondary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(int mode, String label, IconData icon, ThemeData theme) {
    final isActive = _previewMode == mode;
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: () => setState(() => _previewMode = mode),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? colorScheme.primary : colorScheme.outlineVariant.withAlpha(60),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12.5,
              color: isActive ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3.5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(IconData icon, String text, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(40),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.5, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 3.5),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.article_outlined,
            size: 48,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '编辑区暂无文本',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '支持 Markdown 标题、代码块、引用、表格以及 Discuz BBCode 语法',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 依据所选模式渲染内容
  Widget _buildPreviewContent(ThemeData theme, String text) {
    if (_previewMode == 2) {
      // 纯 Discuz BBCode 模式（调用现有 DiscuzPostRenderer）
      final html = bbcodeToHtml(text, customSmileys: widget.customSmileys);
      return DiscuzPostRenderer(
        floor: PostFloor(
          author: '我（预览）',
          contentHtml: html,
          blocks: ComiisParser.parseStructuredBlocksFromHtml(html),
        ),
        tid: 0,
      );
    }

    // 智能混合模式或纯 Markdown 模式：使用流式 Markdown 解析引擎
    return _buildCustomMarkdownTree(theme, text);
  }

  /// 流式 Markdown 解析渲染树
  Widget _buildCustomMarkdownTree(ThemeData theme, String text) {
    final lines = text.split('\n');
    final widgets = <Widget>[];

    var inCodeBlock = false;
    String? codeLang;
    final codeBuffer = StringBuffer();

    var inTable = false;
    final tableLines = <String>[];

    void flushTable() {
      if (tableLines.isNotEmpty) {
        widgets.add(_buildMarkdownTable(theme, tableLines));
        tableLines.clear();
      }
      inTable = false;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // 1. 代码块处理 ```lang
      if (trimmed.startsWith('```')) {
        if (!inCodeBlock) {
          flushTable();
          inCodeBlock = true;
          codeLang = trimmed.substring(3).trim();
          codeBuffer.clear();
        } else {
          inCodeBlock = false;
          widgets.add(_buildCodeBlock(theme, codeLang ?? '', codeBuffer.toString()));
          codeBuffer.clear();
          codeLang = null;
        }
        continue;
      }

      if (inCodeBlock) {
        codeBuffer.writeln(line);
        continue;
      }

      // 2. 表格处理 | a | b |
      if (trimmed.startsWith('|') && trimmed.endsWith('|') && trimmed.length > 2) {
        inTable = true;
        tableLines.add(trimmed);
        continue;
      } else if (inTable) {
        flushTable();
      }

      // 3. 空行
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // 4. 水平分割线 --- or ***
      if (RegExp(r'^(\-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
              thickness: 0.8,
            ),
          ),
        );
        continue;
      }

      // 5. 标题 (H1 - H6)
      if (trimmed.startsWith('#')) {
        final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
        if (headingMatch != null) {
          final level = headingMatch.group(1)!.length;
          final titleText = headingMatch.group(2)!;
          widgets.add(_buildHeading(theme, level, titleText));
          continue;
        }
      }

      // 6. 任务清单 - [ ] / - [x]
      final taskMatch = RegExp(r'^[-*+]\s+\[([ xX])\]\s+(.*)$').firstMatch(trimmed);
      if (taskMatch != null) {
        final isChecked = taskMatch.group(1)!.toLowerCase() == 'x';
        final taskText = taskMatch.group(2)!;
        widgets.add(_buildTaskItem(theme, isChecked, taskText));
        continue;
      }

      // 7. 无序列表 - / * / +
      if (RegExp(r'^[-*+]\s+(.*)$').hasMatch(trimmed)) {
        final listContent = trimmed.replaceFirst(RegExp(r'^[-*+]\s+'), '');
        widgets.add(_buildUnorderedListItem(theme, listContent));
        continue;
      }

      // 8. 有序列表 1. 2.
      final orderedMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
      if (orderedMatch != null) {
        final num = orderedMatch.group(1)!;
        final listContent = orderedMatch.group(2)!;
        widgets.add(_buildOrderedListItem(theme, num, listContent));
        continue;
      }

      // 9. 引用块 > ...
      if (trimmed.startsWith('>')) {
        final quoteContent = trimmed.replaceFirst(RegExp(r'^>+\s?'), '');
        widgets.add(_buildBlockquote(theme, quoteContent));
        continue;
      }

      // 10. 独立图片语法 ![alt](url)
      final imgMatch = RegExp(r'^!\[(.*?)\]\((https?://[^\s)]+)\)$').firstMatch(trimmed);
      if (imgMatch != null) {
        final alt = imgMatch.group(1)!;
        final url = imgMatch.group(2)!;
        widgets.add(_buildImageBlock(theme, url, alt));
        continue;
      }

      // 11. 普通段落与行内富文本
      widgets.add(_buildParagraph(theme, trimmed));
    }

    if (inCodeBlock && codeBuffer.isNotEmpty) {
      widgets.add(_buildCodeBlock(theme, codeLang ?? '', codeBuffer.toString()));
    }
    if (inTable) {
      flushTable();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// 标题渲染 (H1 ~ H6)
  Widget _buildHeading(ThemeData theme, int level, String text) {
    final colorScheme = theme.colorScheme;
    double fontSize;
    FontWeight fontWeight;
    Color? textColor;
    bool showAccentBar = false;
    bool showBottomLine = false;

    switch (level) {
      case 1:
        fontSize = 20.0;
        fontWeight = FontWeight.bold;
        textColor = colorScheme.primary;
        showAccentBar = true;
        showBottomLine = true;
        break;
      case 2:
        fontSize = 17.5;
        fontWeight = FontWeight.bold;
        textColor = colorScheme.onSurface;
        showAccentBar = true;
        showBottomLine = false;
        break;
      case 3:
        fontSize = 16.0;
        fontWeight = FontWeight.w600;
        textColor = colorScheme.onSurface;
        break;
      case 4:
        fontSize = 14.5;
        fontWeight = FontWeight.w600;
        textColor = colorScheme.onSurface;
        break;
      default:
        fontSize = 13.5;
        fontWeight = FontWeight.w600;
        textColor = colorScheme.onSurfaceVariant;
    }

    return Padding(
      padding: EdgeInsets.only(top: level == 1 ? 16 : 12, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showAccentBar) ...[
                Container(
                  width: level == 1 ? 4 : 3,
                  height: fontSize * 0.9,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
              Expanded(
                child: _buildRichInline(
                  theme,
                  text,
                  TextStyle(
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    color: textColor,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (showBottomLine)
            Container(
              margin: const EdgeInsets.only(top: 6),
              height: 0.8,
              color: colorScheme.outlineVariant.withAlpha(50),
            ),
        ],
      ),
    );
  }

  /// 引用块渲染
  Widget _buildBlockquote(ThemeData theme, String text) {
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(35),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        border: Border(
          left: BorderSide(
            color: colorScheme.primary,
            width: 3.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote_rounded,
            size: 15,
            color: colorScheme.primary.withAlpha(150),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildRichInline(
              theme,
              text,
              TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 任务清单项
  Widget _buildTaskItem(ThemeData theme, bool isChecked, String text) {
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isChecked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            size: 17,
            color: isChecked ? colorScheme.primary : colorScheme.outlineVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildRichInline(
              theme,
              text,
              TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isChecked ? colorScheme.outline : colorScheme.onSurface,
                decoration: isChecked ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 无序列表项
  Widget _buildUnorderedListItem(ThemeData theme, String text) {
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 8, right: 9),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: _buildRichInline(
              theme,
              text,
              TextStyle(
                fontSize: 14,
                height: 1.6,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 有序列表项
  Widget _buildOrderedListItem(ThemeData theme, String num, String text) {
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 17,
            height: 17,
            margin: const EdgeInsets.only(top: 2, right: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withAlpha(120),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              num,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: _buildRichInline(
              theme,
              text,
              TextStyle(
                fontSize: 14,
                height: 1.6,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 现代代码卡片（macOS 风格三色圆点 + 语言标签 + 行数 + 一键复制代码）
  Widget _buildCodeBlock(ThemeData theme, String lang, String code) {
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final displayLang = lang.isNotEmpty ? lang.toUpperCase() : 'CODE';
    final lineCount = code.trim().isEmpty ? 1 : code.trim().split('\n').length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1F29) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(60),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF282A36) : const Color(0xFFEAECEF),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                // macOS 三色小圆点
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFFF5F56), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFFFBD2E), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF27C93F), shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(
                  displayLang,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '($lineCount 行)',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制代码到剪贴板'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 12, color: isDark ? Colors.white60 : Colors.black54),
                        const SizedBox(width: 3),
                        Text(
                          '复制',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 代码正文
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Text(
              code.trimRight(),
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12.5,
                height: 1.5,
                color: isDark ? const Color(0xFFF8F8F2) : const Color(0xFF24292E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// GFM 表格排版渲染
  Widget _buildMarkdownTable(ThemeData theme, List<String> lines) {
    if (lines.length < 2) return const SizedBox.shrink();
    final colorScheme = theme.colorScheme;

    // 解析第一行为表头
    final headerCells = lines[0]
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // 过滤掉分割行 |---|---|
    final dataRows = <List<String>>[];
    for (var i = 1; i < lines.length; i++) {
      final l = lines[i];
      if (RegExp(r'^\|?(\s*:?-+:?\s*\|)+\s*$').hasMatch(l)) {
        continue;
      }
      final cells = l
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (cells.isNotEmpty) {
        dataRows.add(cells);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(60),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            for (var c = 0; c < headerCells.length; c++) c: const IntrinsicColumnWidth(),
          },
          children: [
            // 表头
            TableRow(
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(60),
              ),
              children: [
                for (final h in headerCells)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text(
                      h,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            // 数据行
            for (var r = 0; r < dataRows.length; r++)
              TableRow(
                decoration: BoxDecoration(
                  color: r % 2 == 1
                      ? colorScheme.surfaceContainerHighest.withAlpha(30)
                      : Colors.transparent,
                ),
                children: [
                  for (var c = 0; c < headerCells.length; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Text(
                        c < dataRows[r].length ? dataRows[r][c] : '',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 图片块渲染
  Widget _buildImageBlock(ThemeData theme, String url, String alt) {
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () {
                ImageViewerDialog.show(context, imageUrls: [url]);
              },
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) => Container(
                  height: 120,
                  color: colorScheme.surfaceContainerHighest.withAlpha(60),
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 60,
                  padding: const EdgeInsets.all(8),
                  color: colorScheme.errorContainer.withAlpha(50),
                  child: Row(
                    children: [
                      Icon(Icons.broken_image_rounded, size: 20, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '图片无法加载：$url',
                          style: TextStyle(fontSize: 12, color: colorScheme.error),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (alt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                alt,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colorScheme.outline,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 普通段落
  Widget _buildParagraph(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: _buildRichInline(
        theme,
        text,
        TextStyle(
          fontSize: 14,
          height: 1.65,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  /// 行内富文本解析（加粗、斜体、删除线、行内代码、超链接与表情短码）
  Widget _buildRichInline(ThemeData theme, String text, TextStyle baseStyle) {
    final colorScheme = theme.colorScheme;
    final spans = <InlineSpan>[];

    // 匹配:
    // 1. **粗体**
    // 2. *斜体*
    // 3. ~~删除线~~
    // 4. `行内代码`
    // 5. [链接文字](url)
    // 6. ![图片](url)
    final regex = RegExp(
      r'(\*\*([^*]+?)\*\*)|'
      r'(\*([^*]+?)\*)|'
      r'(~~([^~]+?)~~)|'
      r'(`([^`\n]+?)`)|'
      r'(\[([^\]]+?)\]\((https?://[^\s)]+)\))|'
      r'(!\[(.*?)\]\((https?://[^\s)]+)\))',
    );

    int lastIndex = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        final plain = text.substring(lastIndex, match.start);
        spans.addAll(_parseSmileySpans(plain, baseStyle));
      }

      final full = match.group(0)!;
      if (full.startsWith('**') && full.endsWith('**')) {
        final inner = match.group(2)!;
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (full.startsWith('*') && full.endsWith('*')) {
        final inner = match.group(4)!;
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (full.startsWith('~~') && full.endsWith('~~')) {
        final inner = match.group(6)!;
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        ));
      } else if (full.startsWith('`') && full.endsWith('`')) {
        final inner = match.group(8)!;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: colorScheme.outlineVariant.withAlpha(50),
                width: 0.5,
              ),
            ),
            child: Text(
              inner,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! * 0.9 : 12.5,
                color: colorScheme.primary,
              ),
            ),
          ),
        ));
      } else if (full.startsWith('[') && full.contains('](')) {
        final linkText = match.group(10)!;
        final linkUrl = match.group(11)!;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () {
              launchUrl(Uri.parse(linkUrl), mode: LaunchMode.externalApplication);
            },
            borderRadius: BorderRadius.circular(3),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    linkText,
                    style: baseStyle.copyWith(
                      color: colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.open_in_new_rounded, size: 11, color: colorScheme.primary),
                ],
              ),
            ),
          ),
        ));
      } else if (full.startsWith('![')) {
        final imgUrl = match.group(14)!;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () => ImageViewerDialog.show(context, imageUrls: [imgUrl]),
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(80),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 4),
                  Text('查看图片', style: TextStyle(fontSize: 11, color: colorScheme.primary)),
                ],
              ),
            ),
          ),
        ));
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      final tail = text.substring(lastIndex);
      spans.addAll(_parseSmileySpans(tail, baseStyle));
    }

    return Text.rich(
      TextSpan(children: spans),
    );
  }

  static final RegExp _smileyPattern = RegExp(r'(\[[\u4e00-\u9fa5\w~]+\]|\{:\d+_\d+:\})');

  /// 表情代码转换为图文混排 WidgetSpan（采用单次正则扫描 + 快速退出，彻底杜绝死循环与 CPU/内存跑满）
  List<InlineSpan> _parseSmileySpans(String text, TextStyle baseStyle) {
    if (text.isEmpty) return const [];
    // 快速通道：若文本中完全不含表情特征符，直接 0ms 原样返回 TextSpan
    if (!text.contains('[') && !text.contains('{:')) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final spans = <InlineSpan>[];
    final smileyMap = ComiisParser.getSmileyCodeMap(widget.customSmileys);

    int lastEnd = 0;
    for (final match in _smileyPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start), style: baseStyle));
      }
      final code = match.group(0)!;
      final imgUrl = smileyMap[code];
      if (imgUrl != null && imgUrl.isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: CachedNetworkImage(
              imageUrl: imgUrl,
              width: 22,
              height: 22,
              errorWidget: (_, __, ___) => Text(code, style: baseStyle),
            ),
          ),
        ));
      } else {
        spans.add(TextSpan(text: code, style: baseStyle));
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }

    return spans;
  }
}

/// 快速将常见 Markdown 语法转换为 Discuz 标准 BBCode
String markdownToBBCode(String md) {
  var s = md;

  // 1. 代码块 ```lang\n...\n``` -> [code]...[/code]
  s = s.replaceAllMapped(
    RegExp(r'```[a-zA-Z0-9_-]*\n([\s\S]*?)```'),
    (m) => '[code]\n${m[1]}\n[/code]',
  );

  // 2. 标题 # -> [size=5][b]...[/b][/size]
  s = s.replaceAllMapped(
    RegExp(r'^#\s+(.+)$', multiLine: true),
    (m) => '[size=5][b]${m[1]}[/b][/size]',
  );
  s = s.replaceAllMapped(
    RegExp(r'^##\s+(.+)$', multiLine: true),
    (m) => '[size=4][b]${m[1]}[/b][/size]',
  );
  s = s.replaceAllMapped(
    RegExp(r'^###\s+(.+)$', multiLine: true),
    (m) => '[size=3][b]${m[1]}[/b][/size]',
  );

  // 3. 引用块 > ... -> [quote]...[/quote]
  s = s.replaceAllMapped(
    RegExp(r'^>\s+(.+)$', multiLine: true),
    (m) => '[quote]${m[1]}[/quote]',
  );

  // 4. 粗体 **text** -> [b]text[/b]
  s = s.replaceAllMapped(
    RegExp(r'\*\*([^*]+?)\*\*'),
    (m) => '[b]${m[1]}[/b]',
  );

  // 5. 斜体 *text* -> [i]text[/i]
  s = s.replaceAllMapped(
    RegExp(r'(?<!\*)\*([^*]+?)\*(?!\*)'),
    (m) => '[i]${m[1]}[/i]',
  );

  // 6. 删除线 ~~text~~ -> [s]text[/s]
  s = s.replaceAllMapped(
    RegExp(r'~~([^~]+?)~~'),
    (m) => '[s]${m[1]}[/s]',
  );

  // 7. 图片 ![alt](url) -> [img]url[/img]
  s = s.replaceAllMapped(
    RegExp(r'!\[.*?\]\((https?://[^\s)]+)\)'),
    (m) => '[img]${m[1]}[/img]',
  );

  // 8. 链接 [text](url) -> [url=url]text[/url]
  s = s.replaceAllMapped(
    RegExp(r'\[([^\]]+?)\]\((https?://[^\s)]+)\)'),
    (m) => '[url=${m[2]}]${m[1]}[/url]',
  );

  // 9. 分割线 --- -> [hr]
  s = s.replaceAllMapped(
    RegExp(r'^\s*---\s*$', multiLine: true),
    (m) => '[hr]',
  );

  return s;
}
