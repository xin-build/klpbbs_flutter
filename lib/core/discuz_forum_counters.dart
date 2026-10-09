import 'package:html/dom.dart';
import '../models/forum.dart';
import '../models/forum_header_info.dart';
import 'discuz_site_stats.dart';

/// Separate topic, total-post and daily counts, including their precision.
/// Only explicitly declared statistic containers are read; post bodies,
/// descriptions, user names and the site's global chart are never fallbacks.
class DiscuzForumCounts {
  final Map<String, int> values;
  final Map<String, String> displayValues;
  DiscuzForumCounts(Map<String, int> values, Map<String, String> displayValues)
      : values = Map.unmodifiable(values),
        displayValues = Map.unmodifiable(displayValues);

  int? operator [](String key) => values[key];

  static DiscuzForumCounts prefer(
      DiscuzForumCounts primary, DiscuzForumCounts fallback) {
    final values = <String, int>{}, displays = <String, String>{};
    for (final key in {...primary.values.keys, ...fallback.values.keys}) {
      final selected = primary[key] != null &&
              (!primary.displayValues.containsKey(key) ||
                  fallback[key] == null ||
                  fallback.displayValues.containsKey(key))
          ? primary
          : fallback;
      final value = selected[key];
      if (value == null) continue;
      values[key] = value;
      if (selected.displayValues.containsKey(key)) {
        displays[key] = selected.displayValues[key]!;
      }
    }
    return DiscuzForumCounts(values, displays);
  }

  factory DiscuzForumCounts.fromForum(Forum forum) => DiscuzForumCounts({
        if (forum.topicCount >= 0) 'topics': forum.topicCount,
        if (forum.threadCount >= 0) 'posts': forum.threadCount,
        if (forum.todayCount >= 0) 'today': forum.todayCount,
      }, forum.displayValues);

  factory DiscuzForumCounts.fromHeader(ForumHeaderInfo header) =>
      DiscuzForumCounts({
        if (header.hasThreadsCount) 'topics': header.threadsCount,
        if (header.hasPostsCount) 'posts': header.postsCount,
        if (header.hasTodayPosts) 'today': header.todayPosts,
        if (header.hasRank) 'rank': header.rank,
        if (header.hasFavCount) 'favorites': header.favCount,
      }, header.displayValues);
}

class DiscuzForumCounters {
  static const _numberToken = r'\d[\d,，]*(?:\.\d+)?[万亿]?';
  static const _labels = {
    '主题': 'topics',
    '帖数': 'posts',
    '帖子': 'posts',
    '今日': 'today',
    '排名': 'rank',
    '关注': 'favorites',
    '收藏': 'favorites',
  };

  static int? _number(String source) {
    final token = source.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^(?:\d+|\d{1,3}(?:[,，]\d{3})+)(?:\.\d+)?[万亿]?$')
        .hasMatch(token)) {
      return null;
    }
    // Fractional posts without a 万/亿 multiplier are not an integer count.
    if (token.contains('.') && !token.contains('万') && !token.contains('亿')) {
      return null;
    }
    return DiscuzSiteStats.number(token);
  }

  static bool _visible(Element element) {
    for (Element? node = element; node != null; node = node.parent) {
      if (node.attributes.containsKey('hidden') ||
          node.attributes['aria-hidden'] == 'true' ||
          RegExp(r'display\s*:\s*none|visibility\s*:\s*hidden',
                  caseSensitive: false)
              .hasMatch(node.attributes['style'] ?? '')) {
        return false;
      }
    }
    return true;
  }

  static String _statText(Element element) {
    final copy = element.clone(true);
    copy
        .querySelectorAll('script, style, input, select, textarea, button')
        .forEach((node) => node.remove());
    copy
        .querySelectorAll('*')
        .where((node) => !_visible(node))
        .toList()
        .forEach((node) => node.remove());
    // Titles containing dates, user names or descriptive text aren't numbers.
    for (final node in [copy, ...copy.querySelectorAll('[title]')]) {
      final title = node.attributes['title'];
      if (title == null ||
          _number(title) == null ||
          title.contains('万') ||
          title.contains('亿')) {
        continue;
      }
      final matches = RegExp(_numberToken).allMatches(node.text).toList();
      if (matches.length == 1 && node.children.isEmpty) {
        node.text = node.text
            .replaceRange(matches.single.start, matches.single.end, title);
      }
    }
    return copy.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static DiscuzForumCounts labelled(Iterable<Element> elements) {
    final values = <String, int>{}, displays = <String, String>{};
    void add(String key, String token) {
      final number = _number(token);
      if (number == null) return;
      final abbreviated = token.contains('万') || token.contains('亿');
      if (values.containsKey(key) &&
          !displays.containsKey(key) &&
          abbreviated) {
        return;
      }
      values[key] = number;
      if (abbreviated) {
        displays[key] = token.trim();
      } else {
        displays.remove(key);
      }
    }

    for (final element in elements.where(_visible)) {
      final text = _statText(element);
      for (final label in _labels.entries) {
        final match =
            RegExp('${label.key}\\s*[:：]?\\s*($_numberToken)(?![\\d.,，万亿])')
                .firstMatch(text);
        if (match != null) add(label.value, match[1]!);
      }
    }
    return DiscuzForumCounts(values, displays);
  }

  static DiscuzForumCounts modernCard(Element card) {
    final counts = labelled(card.querySelectorAll('.klp-fcard-t .k-meta'));
    final today = card.querySelector('.klp-today');
    final token = today == null || !_visible(today)
        ? ''
        : _statText(today)
            .replaceFirst(RegExp(r'^\s*(?:今日\s*[:：]?\s*)?\+?\s*'), '');
    final value = _number(token);
    return DiscuzForumCounts({
      ...counts.values,
      if (value != null) 'today': value
    }, {
      ...counts.displayValues,
      if (value != null && (token.contains('万') || token.contains('亿')))
        'today': token
    });
  }

  static DiscuzForumCounts mobileCard(Element link) {
    final counters = link.children.where((node) =>
        node.localName == 'p' &&
        RegExp(r'^\s*(?:今日|帖数|帖子|主题|关注)\s*[:：]').hasMatch(node.text));
    final result = labelled(counters);
    final badge = link.children
        .where((node) =>
            node.localName == 'span' &&
            node.classes.contains('bg_a') &&
            node.classes.contains('f_f'))
        .firstOrNull;
    final token = badge == null || !_visible(badge) ? '' : _statText(badge);
    final value = _number(token);
    return DiscuzForumCounts({
      ...result.values,
      if (result['today'] == null && value != null) 'today': value
    }, {
      ...result.displayValues,
      if (result['today'] == null &&
          value != null &&
          (token.contains('万') || token.contains('亿')))
        'today': token
    });
  }

  static DiscuzForumCounts defaultCard(Element card) {
    final cell = card.querySelector('.fl_i');
    if (cell != null) {
      final labelledCounts = labelled([cell]);
      if (labelledCounts['topics'] != null || labelledCounts['posts'] != null) {
        return labelledCounts;
      }
      final text = _statText(cell);
      final pair = RegExp('^\\s*($_numberToken)\\s*/\\s*($_numberToken)\\s*\$')
          .firstMatch(text);
      if (pair != null) {
        final topic = _number(pair[1]!);
        final posts = _number(pair[2]!);
        return DiscuzForumCounts({
          if (topic != null) 'topics': topic,
          if (posts != null) 'posts': posts
        }, {
          if (pair[1]!.contains('万') || pair[1]!.contains('亿'))
            'topics': pair[1]!,
          if (pair[2]!.contains('万') || pair[2]!.contains('亿'))
            'posts': pair[2]!,
        });
      }
    }
    return labelled(card
        .querySelectorAll('p')
        .where((p) => RegExp(r'^\s*(?:主题|帖数|帖子)\s*[:：]').hasMatch(p.text)));
  }

  static DiscuzForumCounts header(Document document) {
    final counts = labelled(document.querySelectorAll(
        '.klp-fhead-stats > span, '
        '.comiis_forumlist_head .top_left p, #forumhd .xs1, .bm.bml h1 .xs1'));
    final values = {...counts.values}, displays = {...counts.displayValues};
    for (final element in document.querySelectorAll(
        '.klp-fhead #number_favorite_num, .klp-fhead #number_favorite, '
        '#forumhd #number_favorite_num, .bm.bml #number_favorite_num, '
        '.klp-fhead [data-fav-count]')) {
      if (!_visible(element)) continue;
      final token = element.attributes['data-fav-count'] ?? _statText(element);
      final number = _number(token);
      if (number == null) continue;
      values['favorites'] = number;
      if (token.contains('万') || token.contains('亿')) {
        displays['favorites'] = token;
      } else {
        displays.remove('favorites');
      }
    }
    return DiscuzForumCounts(values, displays);
  }

  /// Both inputs describe this exact forum, never the directory aggregate.
  static ForumHeaderInfo mergeHeaders(
      ForumHeaderInfo primary, ForumHeaderInfo fallback) {
    if (primary.fid != fallback.fid) throw const FormatException('版块统计不属于同一版块');
    final counts = DiscuzForumCounts.prefer(
        DiscuzForumCounts.fromHeader(primary),
        DiscuzForumCounts.fromHeader(fallback));
    return primary.copyWith(
        todayPosts: counts['today'],
        threadsCount: counts['topics'],
        postsCount: counts['posts'],
        rank: counts['rank'],
        favCount: counts['favorites'],
        displayValues: counts.displayValues);
  }
}
