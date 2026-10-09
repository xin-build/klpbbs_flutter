import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;

/// Copy only the HTML returned for this reader; never fetch concealed content.
/// DOM parsing preserves paragraph boundaries and decoded entities.
class PostCopyDocument {
  final List<String> paragraphs;
  const PostCopyDocument._(this.paragraphs);
  String get plainText => paragraphs.join('\n\n');

  factory PostCopyDocument.fromHtml(String html,
      {bool includeLinkTargets = false}) {
    final fragment = parseFragment(html);
    fragment
        .querySelectorAll('script, style, noscript, input, button, select, '
            'textarea, [hidden], [aria-hidden="true"], .aimg_tip')
        .forEach((node) => node.remove());
    const blocks = {
      'p',
      'div',
      'section',
      'article',
      'blockquote',
      'pre',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'tr',
      'ul',
      'ol',
      'dl',
      'dt',
      'dd'
    };
    final buffer = StringBuffer();
    void walk(Node node, {bool pre = false}) {
      if (node is Text) {
        buffer.write(
            pre ? node.data : node.data.replaceAll(RegExp(r'[\t\r\n ]+'), ' '));
      } else if (node is Element) {
        final tag = node.localName;
        if (tag == 'br') {
          buffer.write('\n');
          return;
        }
        if (tag == 'img') {
          final src = node.attributes['src'] ?? '';
          if (src.contains('/smiley/') || node.classes.contains('smiley')) {
            buffer.write(node.attributes['alt'] ?? '');
          }
          return;
        }
        if (blocks.contains(tag)) buffer.write('\n\n');
        if (tag == 'li') buffer.write('• ');
        if (tag == 'td' || tag == 'th') buffer.write('\t');
        for (final child in node.nodes) {
          walk(child, pre: pre || tag == 'pre');
        }
        if (tag == 'a' && includeLinkTargets) {
          final href = node.attributes['href']?.trim();
          if (href != null &&
              href.isNotEmpty &&
              !RegExp(r'^(javascript|data|vbscript):', caseSensitive: false)
                  .hasMatch(href) &&
              href != node.text.trim()) {
            buffer.write(' ($href)');
          }
        }
        if (blocks.contains(tag)) buffer.write('\n\n');
      } else {
        for (final child in node.nodes) {
          walk(child, pre: pre);
        }
      }
    }

    walk(fragment);
    final paragraphs = buffer
        .toString()
        .replaceAll('\u00a0', ' ')
        .split(RegExp(r'\n[ \t]*\n+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return PostCopyDocument._(List<String>.unmodifiable(paragraphs));
  }
}
