import 'package:html/dom.dart';

/// A subject can contain dates, reply counts and styled text. Metadata is
/// removed by its DOM role, never by matching words in the subject itself.
class DiscuzThreadTitle {
  DiscuzThreadTitle._();

  static String clean(String value) => value
      .replaceAll(RegExp(r'[\u200b-\u200f\uFEFF]'), '')
      .replaceAll(
          RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
              unicode: true),
          '')
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String text(Element element) {
    final subject = element.querySelector('h2') ?? element;
    final copy = subject.clone(true);
    copy
        .querySelectorAll('script, style, svg, use, .comiis_font, '
            '.comiis_xifont, span.bg_0, span.bg_a, '
            '.thread-status, .feed-prefix, .k-chip, '
            '.bottom_views, .bottom_time, .list_body, .forumlist_li_tops, '
            '.comiis_wxlist_bottom')
        .forEach((node) => node.remove());
    for (final badge in copy.querySelectorAll('span, em, i')) {
      final label = clean(badge.text);
      final tooltip = badge.attributes['title'] ?? '';
      final styledStatus =
          badge.classes.any((name) => name.startsWith('bg_')) &&
              const {'精', '荐', '热', '置顶', '锁'}.contains(label);
      if (styledStatus ||
          tooltip.startsWith('热度') ||
          tooltip.startsWith('推荐')) {
        badge.remove();
      }
    }
    return clean(copy.text);
  }
}
