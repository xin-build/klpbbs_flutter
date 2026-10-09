import 'package:html/parser.dart' as html;

import '../models/thread_summary.dart';
import 'discuz_images.dart';
import 'discuz_thread_title.dart';
import 'discuz_avatar_declaration.dart';

/// 当前 KLPBBS PC 列表的专用解析器；作者、分类、计数均限制在同一条目内。
class DiscuzThreadParser {
  /// Both validated templates describe the same requested page. Desktop
  /// supplies the complete table/order; mobile can supply previews and extra
  /// global pins. A nonempty mobile pin list is not a complete topic list.
  static List<ThreadSummary> mergeTemplates(
      List<ThreadSummary> mobile, List<ThreadSummary> desktop) {
    final mobileById = {for (final item in mobile) item.tid: item};
    final seen = <int>{};
    final result = <ThreadSummary>[];
    for (final pc in desktop) {
      if (!seen.add(pc.tid)) continue;
      final m = mobileById[pc.tid];
      if (m == null) {
        result.add(pc);
        continue;
      }
      // Desktop has the complete subject and creation metadata. Mobile
      // timestamps can instead describe the latest reply to the same thread.
      // Use one author/time pair, and enrich it with the actual mobile previews.
      result.add(pc.copyWith(
        views: pc.views >= 0 ? pc.views : m.views,
        replies: pc.replies >= 0 ? pc.replies : m.replies,
        author: pc.author.isNotEmpty
            ? pc.author
            : (pc.uid == null || pc.uid == m.uid ? m.author : ''),
        uid: pc.uid ??
            (pc.author.isEmpty || pc.author == m.author ? m.uid : null),
        title: pc.title.isNotEmpty ? pc.title : m.title,
        fid: m.fid ?? pc.fid,
        forumName: m.forumName ?? pc.forumName,
        typeName: pc.typeName ?? m.typeName,
        timeText: pc.timeText?.isNotEmpty == true ? pc.timeText : m.timeText,
        imageUrls: m.imageUrls.isNotEmpty ? m.imageUrls : pc.imageUrls,
        coverUrl: m.coverUrl ?? pc.coverUrl,
        excerpt: m.excerpt ?? pc.excerpt,
        faceUrl: pc.faceUrl ??
            (pc.uid != null
                ? (pc.uid == m.uid ? m.faceUrl : null)
                : (pc.author.isEmpty || pc.author == m.author
                    ? m.faceUrl
                    : null)),
        badge: m.badge ?? pc.badge,
        stamp: m.stamp ?? pc.stamp,
        stampUrl: m.stampUrl ?? pc.stampUrl,
        isSticky: m.isSticky || pc.isSticky,
        isDigest: m.isDigest || pc.isDigest,
        isHot: m.isHot || pc.isHot,
        isRecommend: m.isRecommend || pc.isRecommend,
        heatCount: m.heatCount >= 0 ? m.heatCount : pc.heatCount,
        recommendCount:
            m.recommendCount >= 0 ? m.recommendCount : pc.recommendCount,
      ));
    }
    for (final item in mobile) {
      if (seen.add(item.tid)) result.add(item);
    }
    return [
      ...result.where((item) => item.isSticky),
      ...result.where((item) => !item.isSticky),
    ];
  }

  static int? _id(String? value, String name) => int.tryParse(
      RegExp('(?:[?&]$name=|${name == 'tid' ? 'thread' : name == 'uid' ? 'space-uid' : 'forum'}-)(\\d+)')
              .firstMatch(value ?? '')
              ?.group(1) ??
          '');
  static int _count(String? value) =>
      int.tryParse((value ?? '').trim().replaceAll(',', '')) ?? -1;

  static List<ThreadSummary> modern(String source, Uri base, {int? pageFid}) {
    final doc = html.parse(source);
    final result = <ThreadSummary>[];
    final seen = <int>{};
    final pageName = doc
        .querySelector('.klp-fhead h1, #forumhd h1, .klp-forum-title, h1')
        ?.text
        .trim();
    for (final row in doc.querySelectorAll(
        'tbody[id^="normalthread_"], tbody[id^="stickthread_"]')) {
      if (row.querySelector('.klp-trow') == null) continue;
      final title = row.querySelector('a.s.xst, a.xst');
      final tid = _id(title?.attributes['href'], 'tid');
      if (tid == null || title == null || !seen.add(tid)) continue;
      final author = row.querySelector(
          '.klp-trow-meta a[href*="uid="], .klp-trow-meta a[href*="space-uid-"]');
      final type = row.querySelector('.klp-trow-meta em a[href*="typeid="]');
      final date = row.querySelector('.klp-trow-date span, .klp-trow-date');
      final images = DiscuzImages.covers(row, base);
      result.add(ThreadSummary(
          tid: tid,
          fid: pageFid,
          uid: _id(author?.attributes['href'], 'uid'),
          author: author?.text.trim() ?? '',
          title: DiscuzThreadTitle.text(title),
          typeName: type?.text.trim(),
          forumName: pageName,
          timeText: date == null
              ? null
              : DiscuzThreadTitle.clean(date.text)
                  .replaceFirst(RegExp(r'^[·•]\s*'), ''),
          replies: _count(row.querySelector('td.num a')?.text),
          views: _count(row.querySelector('td.num em')?.text),
          imageUrls: images,
          coverUrl: images.firstOrNull,
          isSticky: row.id.startsWith('stickthread_')));
    }
    for (final article
        in doc.querySelectorAll('article.feed-item, article.klp-fl-item')) {
      final title = article.querySelector('.feed-title a, .klp-fl-title a');
      final tid = _id(title?.attributes['href'], 'tid');
      if (tid == null || title == null || !seen.add(tid)) continue;
      final author = article.querySelector(
          'a.feed-author, .feed-head a[href*="space-uid-"]:not(.k-av), .feed-head a[href*="uid="]:not(.k-av), .klp-fl-why a[href*="space-uid-"], .klp-fl-why a[href*="uid="]');
      final forum = article
          .querySelectorAll(
              '.feed-head a[href*="forum-"], .feed-head a[href*="forumdisplay"], '
              '.klp-fl-why a[href*="forum-"], .klp-fl-why a[href*="forumdisplay"], '
              'a.klp-fl-badge[href]')
          .where((link) => DiscuzThreadTitle.clean(link.text).isNotEmpty)
          .firstOrNull;
      final images = DiscuzImages.covers(article, base);
      var replies = -1, views = -1, likes = -1;
      for (final stat in article.querySelectorAll('.feed-foot .feed-stat')) {
        final icon = stat.querySelector('use')?.attributes['href'] ?? '';
        final count = _count(stat.querySelector('.k-mono')?.text);
        if (icon.contains('eye')) views = count;
        if (icon.contains('reply') ||
            icon.contains('mail') ||
            icon.contains('chat')) {
          replies = count;
        }
        if (icon.contains('thumb') || icon.contains('like')) likes = count;
      }
      final authorUid = _id(author?.attributes['href'], 'uid');
      final appearance = DiscuzAvatarDeclarations.fromElement(article, base)
          .where((declaration) => declaration.uid == authorUid)
          .firstOrNull;
      result.add(ThreadSummary(
          tid: tid,
          fid: _id(forum?.attributes['href'], 'fid') ?? pageFid,
          uid: authorUid,
          author: author?.text.trim() ?? '',
          title: DiscuzThreadTitle.text(title),
          forumName: forum == null ? null : DiscuzThreadTitle.clean(forum.text),
          timeText: article
              .querySelector('.feed-time, .feed-head time, .klp-fl-why time')
              ?.text
              .trim(),
          excerpt: article
              .querySelector('.feed-excerpt, .klp-fl-excerpt')
              ?.text
              .trim(),
          replies: replies,
          views: views,
          recommendCount: likes,
          imageUrls: images,
          coverUrl: images.firstOrNull,
          faceUrl: appearance?.faceUrl));
    }
    return result;
  }
}
