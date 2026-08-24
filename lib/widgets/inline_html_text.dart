import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../core/url_helper.dart';

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

    final clean = rawHtml
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"');

    final doc = html_parser.parseFragment(clean);

    List<InlineSpan> walk(html_dom.Node node, TextStyle currentStyle, {bool insideLink = false, String? linkHref}) {
      final spans = <InlineSpan>[];
      for (final n in node.nodes) {
        if (n.nodeType == html_dom.Node.TEXT_NODE) {
          final text = _cleanContentText(n.text ?? '');
          if (text.isNotEmpty) {
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
              // 自动识别文本中的 URL
              final urlRegex = RegExp(r'(https?://[^\s<>"，。]+|www\.[^\s<>"，。]+)', caseSensitive: false);
              final matches = urlRegex.allMatches(text);
              if (matches.isNotEmpty) {
                int lastEnd = 0;
                for (final m in matches) {
                  if (m.start > lastEnd) {
                    spans.add(TextSpan(text: text.substring(lastEnd, m.start), style: currentStyle));
                  }
                  final matchedUrl = m.group(0)!;
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
                  lastEnd = m.end;
                }
                if (lastEnd < text.length) {
                  spans.add(TextSpan(text: text.substring(lastEnd), style: currentStyle));
                }
              } else {
                spans.add(TextSpan(text: text, style: currentStyle));
              }
            }
          }
        } else if (n.nodeType == html_dom.Node.ELEMENT_NODE) {
          final el = n as html_dom.Element;
          final tag = el.localName?.toLowerCase() ?? '';
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
            final linkStyle = style.copyWith(
              color: theme.colorScheme.primary,
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
                  src.contains('post/smile');

              if (isSmiley) {
                final size = emojiSize ?? 18.0;
                spans.add(
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: CachedNetworkImage(
                        imageUrl: src,
                        cacheManager: KlpbbsCacheManager.instance,
                        httpHeaders: AppConfig.imageHeadersFor(src),
                        width: size,
                        height: size,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => SizedBox(
                          width: size,
                          height: size,
                        ),
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
                          child: CachedNetworkImage(
                            imageUrl: src,
                            cacheManager: KlpbbsCacheManager.instance,
                            httpHeaders: AppConfig.imageHeadersFor(src),
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => Container(
                              padding: const EdgeInsets.all(8),
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image_outlined, size: 16, color: theme.colorScheme.outline),
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

  String _cleanContentText(String text) {
    return text.replaceAll(RegExp(r'[-​‎‏﻿]'), '');
  }

  Color _parseColor(String raw, {Brightness? brightness, bool isBackground = false}) {
    var clean = raw.toLowerCase().trim();
    Color baseColor;
    if (clean.startsWith('#')) {
      final hex = clean.substring(1);
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
        'royalblue': Color(0xFF4169E1),
        'dodgerblue': Color(0xFF1E90FF),
        'white': Colors.white,
        'black': Colors.black,
      };
      baseColor = colorMap[clean] ?? Colors.grey;
    }

    if (!isBackground) {
      if (brightness == Brightness.dark) {
        if (baseColor.computeLuminance() < 0.15 && baseColor != Colors.black) {
          return const Color(0xFFCFD8DC);
        }
      } else if (brightness == Brightness.light) {
        if (baseColor.computeLuminance() > 0.88 &&
            baseColor != Colors.amber &&
            baseColor != const Color(0xFFFFD700) &&
            baseColor != Colors.white) {
          return const Color(0xFF37474F);
        }
      }
    }
    return baseColor;
  }

  String _absolute(String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
    if (trimmed.startsWith('www.')) return 'https://$trimmed';
    var clean = trimmed;
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    return '${AppConfig.baseUrl}$clean';
  }

  void _openLink(BuildContext context, String link) {
    UrlHelper.openLink(context, link);
  }
}
