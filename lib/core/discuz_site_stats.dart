import 'package:html/parser.dart' as html;
import '../models/site_stats.dart';

/// 只从全站统计容器读取；保留站点的缩写，避免把 233.6万解析成 233。
class DiscuzSiteStats {
  static int? number(String source) {
    final value = source.replaceAll(RegExp(r'[,，\s]'), '');
    final match = RegExp(r'^(\d+(?:\.\d+)?)([万亿]?)$').firstMatch(value);
    if (match == null) return null;
    final multiplier =
        switch (match[2]) { '万' => 10000, '亿' => 100000000, _ => 1 };
    return (double.parse(match[1]!) * multiplier).round();
  }

  static SiteStats parse(String source) {
    final doc = html.parse(source);
    final values = <String, int>{};
    final displays = <String, String>{};
    const labels = {
      '今日': 'todayPosts',
      '今日发帖': 'todayPosts',
      '昨日': 'yesterdayPosts',
      '昨日发帖': 'yesterdayPosts',
      '帖子': 'totalPosts',
      '总帖': 'totalPosts',
      '全站总帖': 'totalPosts',
      '会员': 'totalMembers',
      '注册会员': 'totalMembers',
      '会员总数': 'totalMembers',
    };
    void add(String key, String text) {
      final numeric = number(text);
      if (numeric == null) return;
      values[key] = numeric;
      if (text.contains('万') || text.contains('亿')) displays[key] = text.trim();
    }

    for (final entry in doc.querySelectorAll(
        '#chart.klp-stat-grid > div, .comiis_forum_tj .kmzrtj > li')) {
      final label =
          entry.querySelector('span')?.text.replaceAll(RegExp(r'[:：\s]'), '');
      final key = labels[label];
      final node = entry.querySelector('b, em');
      if (key != null && node != null) {
        add(key, node.attributes['title'] ?? node.text);
      }
    }
    for (final chart
        in doc.querySelectorAll('#chart, .chart_tj, .comiis_forum_tj')) {
      for (final metric in const {
        'tj_today': 'todayPosts',
        'tj_yesterday': 'yesterdayPosts',
        'tj_posts': 'totalPosts',
        'tj_members': 'totalMembers',
      }.entries) {
        final node = chart.querySelector('.${metric.key}');
        if (node == null || values.containsKey(metric.value)) continue;
        final value = node.querySelector('em, b, strong')?.text ??
            RegExp(r'[\d,，]+(?:\.\d+)?[万亿]?').firstMatch(node.text)?.group(0) ??
            '';
        add(metric.value, value);
      }
      // 原生 Discuz #chart 文本，显式标签及冒号防止匹配局部版块。
      for (final label in labels.entries) {
        if (values.containsKey(label.value)) continue;
        final match =
            RegExp('${label.key}\\s*[:：]\\s*([\\d,，]+(?:\\.\\d+)?[万亿]?)')
                .firstMatch(chart.text);
        if (match != null) add(label.value, match[1]!);
      }
    }
    return SiteStats(
      todayPosts: values['todayPosts'],
      yesterdayPosts: values['yesterdayPosts'],
      totalPosts: values['totalPosts'],
      totalMembers: values['totalMembers'],
      displayValues: displays,
      fetchedAt: DateTime.now(),
    );
  }

  /// 手机页有完整整数，PC 页有四舍五入缩写时优先采用整数。
  static SiteStats merge(SiteStats mobile, SiteStats desktop) {
    final result = <String, int>{};
    final display = <String, String>{};
    for (final key in const [
      'todayPosts',
      'yesterdayPosts',
      'totalPosts',
      'totalMembers'
    ]) {
      final source =
          mobile.display(key) != '—' && !mobile.displayValues.containsKey(key)
              ? mobile
              : desktop.display(key) != '—'
                  ? desktop
                  : mobile;
      if (source.display(key) == '—') continue;
      result[key] = switch (key) {
        'todayPosts' => source.todayPosts,
        'yesterdayPosts' => source.yesterdayPosts,
        'totalPosts' => source.totalPosts,
        _ => source.totalMembers,
      };
      if (source.displayValues.containsKey(key)) {
        display[key] = source.displayValues[key]!;
      }
    }
    return SiteStats(
        todayPosts: result['todayPosts'],
        yesterdayPosts: result['yesterdayPosts'],
        totalPosts: result['totalPosts'],
        totalMembers: result['totalMembers'],
        displayValues: display,
        fetchedAt: DateTime.now());
  }
}
