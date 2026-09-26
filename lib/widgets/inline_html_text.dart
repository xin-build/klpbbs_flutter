import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../core/app_config.dart';
import '../core/url_helper.dart';
import 'retry_image.dart';

/// 行内富文本渲染（表情 / 链接 / 加粗 / 颜色 / 换行）。
///
/// 用于楼中楼（replyfloor）、楼中楼点评等短 HTML 片段；区别于
/// [DiscuzPostRenderer] 的结构化正文引擎，本组件只做单段 RichText。
class InlineHtmlText extends StatelessWidget {
  final String html;
  final TextStyle? baseStyle;
  final double? emojiSize;
  final TextAlign? textAlign;

  const InlineHtmlText({
    super.key,
    required this.html,
    this.baseStyle,
    this.emojiSize,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    if (html.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final defaultStyle = DefaultTextStyle.of(context).style;
    final base = baseStyle ??
        theme.textTheme.bodyMedium ??
        defaultStyle;

    final spans = _htmlToSpans(context, html, base, theme);
    if (spans.isEmpty) return const SizedBox.shrink();

    final effectiveAlign = textAlign ??
        (html.contains('align="center"') ||
                html.contains('align=center') ||
                html.contains('<center>')
            ? TextAlign.center
            : TextAlign.start);

    return Text.rich(
      TextSpan(children: spans),
      style: base,
      textAlign: effectiveAlign,
    );
  }

  List<InlineSpan> _htmlToSpans(
    BuildContext context,
    String rawHtml,
    TextStyle base,
    ThemeData theme,
  ) {
    if (rawHtml.isEmpty) return const [];

    var clean = rawHtml
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"');

    // 将 ahome_horn 插件表情码 [s:0]~[s:23] 替换为标准表情图片，防止被纯文本截断
    clean = clean.replaceAllMapped(RegExp(r'\[s:(\d+)\]'), (m) {
      final idx = m.group(1)!;
      return '<img src="${AppConfig.baseUrl}source/plugin/ahome_horn/image/smiles/$idx.png" smilieid="$idx" border="0" />';
    });

    final doc = html_parser.parseFragment(clean);

    List<InlineSpan> walk(html_dom.Node node, TextStyle currentStyle, {bool insideLink = false, String? linkHref}) {
      final spans = <InlineSpan>[];
      for (final n in node.nodes) {
        if (n.nodeType == html_dom.Node.TEXT_NODE) {
          final text = _cleanContentText(n.text ?? '');
          if (text.isNotEmpty) {
            // 检查文本是否包含「💰 土豪」或「[💰 土豪]」
            final bossRegex = RegExp(r'\[?💰\s*土豪\]?');
            final bossMatch = bossRegex.firstMatch(text);
            if (bossMatch != null) {
              final before = text.substring(0, bossMatch.start);
              final after = text.substring(bossMatch.end);
              if (before.isNotEmpty) {
                spans.addAll(_processTextWithUrls(context, before, currentStyle, theme, insideLink: insideLink, linkHref: linkHref));
              }
              spans.add(
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _buildTuhaoBadge(theme),
                ),
              );
              if (after.isNotEmpty) {
                spans.addAll(_processTextWithUrls(context, after, currentStyle, theme, insideLink: insideLink, linkHref: linkHref));
              }
              continue;
            }

            spans.addAll(_processTextWithUrls(context, text, currentStyle, theme, insideLink: insideLink, linkHref: linkHref));
          }
        } else if (n.nodeType == html_dom.Node.ELEMENT_NODE) {
          final el = n as html_dom.Element;
          final tag = el.localName?.toLowerCase() ?? '';

          // 拦截「土豪」或「土豪霸屏」徽章元素（1:1 还原网页端金黄徽章，杜绝灰色背景块）
          final trimmedText = el.text.trim();
          final isBossEl = el.classes.contains('boss') ||
              el.classes.contains('ahorn_boss') ||
              el.classes.contains('tuhao') ||
              (el.attributes['style']?.contains('ahorn') ?? false) ||
              trimmedText == '💰 土豪' ||
              trimmedText == '💰土豪' ||
              trimmedText == '[💰 土豪]' ||
              trimmedText == '[💰土豪]';
          if (isBossEl) {
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _buildTuhaoBadge(theme),
              ),
            );
            continue;
          }

          TextStyle? style = currentStyle;

          // 样式解析
          switch (tag) {
            case 'b':
            case 'strong':
              style = style.copyWith(fontWeight: FontWeight.bold);
              break;
            case 'i':
            case 'em':
              style = style.copyWith(fontStyle: FontStyle.italic);
              break;
            case 'u':
              style = style.copyWith(decoration: TextDecoration.underline);
              break;
            case 's':
            case 'del':
            case 'strike':
              style = style.copyWith(decoration: TextDecoration.lineThrough);
              break;
            case 'font':
              final color = el.attributes['color'];
              if (color != null && color.isNotEmpty) {
                style = style.copyWith(color: _parseColor(color, brightness: theme.brightness));
              }
              final size = el.attributes['size'];
              if (size != null) {
                final s = double.tryParse(size);
                if (s != null) {
                  const sizeMap = {
                    1: 11.0,
                    2: 13.0,
                    3: 15.0,
                    4: 17.5,
                    5: 21.0,
                    6: 25.0,
                    7: 32.0,
                  };
                  final resolvedSize = sizeMap[s.toInt()] ?? (base.fontSize != null ? base.fontSize! * (0.8 + s * 0.1) : 13.5);
                  style = style.copyWith(fontSize: resolvedSize);
                }
              }
              break;
          }

          // 行内 style 属性
          final styleAttr = el.attributes['style'];
          if (styleAttr != null && styleAttr.isNotEmpty) {
            final bgM = RegExp(r'background(?:-color)?\s*:\s*([^;]+)', caseSensitive: false).firstMatch(styleAttr);
            if (bgM != null) {
              final bgStr = bgM.group(1)!.trim();
              if (bgStr.isNotEmpty && bgStr != 'none' && bgStr != 'transparent') {
                style = style.copyWith(
                  backgroundColor: _parseColor(bgStr, brightness: theme.brightness, isBackground: true),
                );
              }
            }
            final colorM = RegExp(r'(?:^|;|\s)color\s*:\s*([^;]+)', caseSensitive: false).firstMatch(styleAttr);
            if (colorM != null) {
              style = style.copyWith(color: _parseColor(colorM.group(1)!.trim(), brightness: theme.brightness));
            }
            final weightM = RegExp(r'font-weight\s*:\s*bold', caseSensitive: false).firstMatch(styleAttr);
            if (weightM != null) {
              style = style.copyWith(fontWeight: FontWeight.bold);
            }
            final sizeM = RegExp(r'font-size\s*:\s*([^;]+)', caseSensitive: false).firstMatch(styleAttr);
            if (sizeM != null) {
              final sizeStr = sizeM.group(1)!.trim();
              final numVal = double.tryParse(sizeStr.replaceAll(RegExp(r'[^0-9.]'), ''));
              if (numVal != null) {
                style = style.copyWith(fontSize: numVal);
              }
            }
          }

          // 特殊标签处理
          if (tag == 'a') {
            final href = el.attributes['href'] ?? '';
            final link = _absolute(href);
            final linkColor = style.color ?? theme.colorScheme.primary;
            final linkStyle = style.copyWith(
              color: linkColor,
              decoration: TextDecoration.underline,
            );
            if (href.isNotEmpty) {
              final childSpans = walk(n, linkStyle, insideLink: true, linkHref: link);
              spans.addAll(childSpans);
            } else {
              spans.addAll(walk(n, linkStyle));
            }
          } else if (tag == 'img') {
            var rawSrc = el.attributes['src'] ?? el.attributes['file'] ?? el.attributes['data-src'] ?? '';
            if (rawSrc.isNotEmpty && !rawSrc.contains('none.png') && !rawSrc.contains('spacer.gif')) {
              final src = _absolute(rawSrc);
              final isSmiley = el.attributes['smilieid'] != null ||
                  src.contains('smiley') ||
                  src.contains('post/smile') ||
                  src.contains('smiles') ||
                  src.contains('ahome_horn') ||
                  src.contains('image/smiles');

              if (isSmiley) {
                final size = emojiSize ?? 18.0;
                spans.add(
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: RetryImage(
                        imageUrl: src,
                        width: size,
                        height: size,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => SizedBox(width: size, height: size),
                        errorWidget: (_, __, ___) => SizedBox(width: size, height: size),
                      ),
                    ),
                  ),
                );
              } else {
                spans.add(
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () => _openLink(context, src),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        constraints: const BoxConstraints(maxHeight: 220, maxWidth: 420),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: RetryImage(
                            imageUrl: src,
                            fit: BoxFit.contain,
                            placeholder: (_, __) => Container(
                              width: 80,
                              height: 36,
                              color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                              child: const Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 1.5),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image_outlined, size: 14, color: theme.colorScheme.outline),
                                  const SizedBox(width: 4),
                                  Text('图片加载失败', style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
            }
          } else {
            spans.addAll(walk(n, style, insideLink: insideLink, linkHref: linkHref));
            if (tag == 'br') spans.add(const TextSpan(text: '\n'));
            if (tag == 'p' || tag == 'div') {
              spans.add(const TextSpan(text: '\n'));
            }
          }
        }
      }
      return spans;
    }

    return walk(doc, base);
  }

  /// 1:1 对齐 Discuz 网页版小喇叭「💰 土豪」徽章
  Widget _buildTuhaoBadge(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(left: 6, right: 3, top: 1, bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x33FFA000) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? const Color(0xFFFFB300) : const Color(0xFFFFC107),
          width: 0.9,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('💰', style: TextStyle(fontSize: 11, height: 1.0)),
          const SizedBox(width: 3),
          Text(
            '土豪',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFFFFD54F) : const Color(0xFFD97706),
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  /// 处理文本中的 URL 自动识别与点击跳转
  List<InlineSpan> _processTextWithUrls(
    BuildContext context,
    String text,
    TextStyle currentStyle,
    ThemeData theme, {
    bool insideLink = false,
    String? linkHref,
  }) {
    final spans = <InlineSpan>[];
    if (insideLink && linkHref != null && linkHref.isNotEmpty) {
      spans.add(
        TextSpan(
          text: text,
          style: currentStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => _openLink(context, linkHref),
        ),
      );
    } else {
      final urlRegex = RegExp(r'(https?://[^\s<>"，。]+|www\.[^\s<>"，。]+)', caseSensitive: false);
      final matches = urlRegex.allMatches(text);
      if (matches.isNotEmpty) {
        int lastEnd = 0;
        for (final m in matches) {
          if (m.start > lastEnd) {
            spans.add(TextSpan(text: text.substring(lastEnd, m.start), style: currentStyle));
          }
          var matchedUrl = m.group(0)!;
          var trailingPunct = '';
          while (matchedUrl.isNotEmpty &&
              RegExp(r'[)）\]】}>》;；,，.。!！?？:：]$').hasMatch(matchedUrl)) {
            trailingPunct = matchedUrl[matchedUrl.length - 1] + trailingPunct;
            matchedUrl = matchedUrl.substring(0, matchedUrl.length - 1);
          }
          final linkStyle = currentStyle.copyWith(
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
          if (trailingPunct.isNotEmpty) {
            spans.add(TextSpan(text: trailingPunct, style: currentStyle));
          }
          lastEnd = m.end;
        }
        if (lastEnd < text.length) {
          spans.add(TextSpan(text: text.substring(lastEnd), style: currentStyle));
        }
      } else {
        spans.add(TextSpan(text: text, style: currentStyle));
      }
    }
    return spans;
  }

  String _cleanContentText(String text) {
    return text.replaceAll(RegExp(r'[-​‎‏﻿]'), '');
  }

  Color _parseColor(String raw, {Brightness? brightness, bool isBackground = false}) {
    var clean = raw.trim().toLowerCase();
    // 移除单双引号、分号与首尾空白 (例如 [color='deepskyblue'] 或 style="color: red;")
    clean = clean.replaceAll(RegExp(r'''['";\s]'''), '');
    if (clean.isEmpty) return Colors.grey;

    Color baseColor;
    final hexCandidate = clean.startsWith('#') ? clean.substring(1) : clean;
    if (RegExp(r'^[0-9a-f]{6}$').hasMatch(hexCandidate)) {
      baseColor = Color(int.parse('FF$hexCandidate', radix: 16));
    } else if (RegExp(r'^[0-9a-f]{3}$').hasMatch(hexCandidate)) {
      final full = hexCandidate.split('').map((c) => '$c$c').join();
      baseColor = Color(int.parse('FF$full', radix: 16));
    } else if (RegExp(r'^[0-9a-f]{8}$').hasMatch(hexCandidate)) {
      baseColor = Color(int.parse(hexCandidate, radix: 16));
    } else if (clean.startsWith('rgb(') || clean.startsWith('rgba(')) {
      final nums = RegExp(r'\d+').allMatches(clean).map((m) => int.tryParse(m.group(0) ?? '') ?? 0).toList();
      if (nums.length >= 3) {
        baseColor = Color.fromARGB(255, nums[0], nums[1], nums[2]);
      } else {
        baseColor = Colors.grey;
      }
    } else {
      const colorMap = <String, Color>{
        'red': Colors.red,
        'blue': Colors.blue,
        'green': Colors.green,
        'yellow': Colors.amber,
        'orange': Colors.orange,
        'purple': Colors.purple,
        'gray': Colors.grey,
        'grey': Colors.grey,
        'yellowgreen': Color(0xFF9ACD32),
        'pink': Color(0xFFFFC0CB),
        'deeppink': Color(0xFFFF1493),
        'hotpink': Color(0xFFFF69B4),
        'lightpink': Color(0xFFFFB6C1),
        'limegreen': Color(0xFF32CD32),
        'lime': Color(0xFF00FF00),
        'darkgreen': Color(0xFF006400),
        'forestgreen': Color(0xFF228B22),
        'seagreen': Color(0xFF2E8B57),
        'cyan': Color(0xFF00FFFF),
        'aqua': Color(0xFF00FFFF),
        'magenta': Color(0xFFFF00FF),
        'fuchsia': Color(0xFFFF00FF),
        'violet': Color(0xFFEE82EE),
        'darkorange': Color(0xFFFF8C00),
        'gold': Color(0xFFFFD700),
        'teal': Color(0xFF008080),
        'navy': Color(0xFF000080),
        'indigo': Color(0xFF4B0082),
        'brown': Color(0xFFA52A2A),
        'maroon': Color(0xFF800000),
        'crimson': Color(0xFFDC143C),
        'coral': Color(0xFFFF7F50),
        'salmon': Color(0xFFFA8072),
        'tomato': Color(0xFFFF6347),
        'silver': Color(0xFFC0C0C0),
        'olive': Color(0xFF808000),
        'khaki': Color(0xFFF0E68C),
        'deepskyblue': Color(0xFF00BFFF),
        'skyblue': Color(0xFF87CEEB),
        'lightskyblue': Color(0xFF87CEFA),
        'powderblue': Color(0xFFB0E0E6),
        'royalblue': Color(0xFF4169E1),
        'dodgerblue': Color(0xFF1E90FF),
        'mediumpurple': Color(0xFF9370DB),
        'orchid': Color(0xFFDA70D6),
        'plum': Color(0xFFDDA0DD),
        'sandybrown': Color(0xFFF4A460),
        'sienna': Color(0xFFA0522D),
        'darkslategray': Color(0xFF2F4F4F),
        'white': Colors.white,
        'black': Colors.black,
      };
      baseColor = colorMap[clean] ?? (isBackground ? Colors.transparent : Colors.grey);
    }

    if (!isBackground && brightness != null) {
      final hsl = HSLColor.fromColor(baseColor);
      if (brightness == Brightness.dark) {
        // 深色模式下：如果纯黑或极暗灰（无彩度），调整为银白色
        if (hsl.saturation < 0.12 && hsl.lightness < 0.35) {
          return const Color(0xFFE2E8F0);
        }
        // 如果是有色彩倾向但偏暗（如深蓝、墨绿），保留其色相与饱和度，提升明度至可读区间
        if (hsl.lightness < 0.52) {
          return hsl.withLightness(0.68).toColor();
        }
      } else {
        // 浅色模式下：如果纯白或极浅灰，调整为深青灰色
        if (hsl.saturation < 0.12 && hsl.lightness > 0.82) {
          return const Color(0xFF1E293B);
        }
        // 如果是有色彩倾向但偏浅亮（如浅黄、浅青），保留其色相，压低明度保证对比度
        if (hsl.lightness > 0.72) {
          return hsl.withLightness(0.42).toColor();
        }
      }
    }
    return baseColor;
  }

  String _absolute(String href) {
    var trimmed = href.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('//')) {
      trimmed = 'https:$trimmed';
    } else if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      if (trimmed.startsWith('www.')) {
        trimmed = 'https://$trimmed';
      } else {
        var clean = trimmed;
        while (clean.startsWith('/')) {
          clean = clean.substring(1);
        }
        trimmed = '${AppConfig.baseUrl}$clean';
      }
    }
    try {
      return Uri.encodeFull(trimmed);
    } catch (_) {
      return trimmed;
    }
  }

  void _openLink(BuildContext context, String link) {
    UrlHelper.openLink(context, link);
  }
}
