import 'package:html/parser.dart' as html;
import '../models/site_rank_entry.dart';

/// KLPBBS 新版首页热门面板。周期与顺序沿用网站，不借用导读或积分榜替代。
class DiscuzRankings {
  static bool recognized(String source) =>
      html.parse(source).querySelector('[data-panel-group="hot"]') != null;

  static Map<String, List<SiteRankEntry>> parse(String source) {
    final doc = html.parse(source);
    final result = <String, List<SiteRankEntry>>{};
    for (final panel
        in doc.querySelectorAll('[data-panel-group="hot"] [data-panel]')) {
      final period = panel.attributes['data-panel'];
      if (!const {'day', 'week', 'month'}.contains(period)) continue;
      final entries = <SiteRankEntry>[];
      final seen = <int>{};
      for (final link in panel.querySelectorAll('a.k-list-row[href]')) {
        final href = link.attributes['href']!;
        final tid = int.tryParse(
                RegExp(r'thread-(\d+)-').firstMatch(href)?.group(1) ?? '') ??
            int.tryParse(Uri.tryParse(href)?.queryParameters['tid'] ?? '');
        final title = link.querySelector('.k-ellip')?.text.trim() ?? '';
        if (tid == null || tid <= 0 || title.isEmpty || !seen.add(tid)) {
          continue;
        }
        entries.add(SiteRankEntry(
            tid: tid,
            rank:
                int.tryParse(link.querySelector('.k-rank')?.text.trim() ?? ''),
            title: title,
            subtitle: link.querySelector('.k-meta')?.text.trim() ?? ''));
      }
      result[period!] = entries;
    }
    return result;
  }
}
