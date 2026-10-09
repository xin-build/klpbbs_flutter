import 'package:html/dom.dart';

/// KLPBBS 返回的楼层元数据；不能用当前浏览器 UA 推测历史发帖设备。
class DiscuzPostMetadata {
  static ({String timeText, String sourceLabel, String ipText}) parse(
      Element post) {
    final header = post.querySelector('.comiis_postli_time') ??
        post.querySelector('.klp-floor-meta') ??
        post.querySelector('.pti .authi, .authi, .author_time');
    if (header == null) return (timeText: '', sourceLabel: '', ipText: '');
    final source =
        header.querySelector('.klp_appfrom, .klp-floor-from')?.text.trim() ??
            '';
    final rawLocation =
        header.querySelector('.comiis_iplocality')?.text.trim() ?? '';
    var location = rawLocation
        .replaceFirst(RegExp(r'^IP\s*[:：]\s*', caseSensitive: false), '')
        .trim();
    if (const {'0', '未知', 'unknown'}.contains(location.toLowerCase())) {
      location = '';
    }
    final clone = header.clone(true);
    for (final item in clone.querySelectorAll(
        '.klp_appfrom, .klp-floor-from, .comiis_iplocality, .klp-floor-hook')) {
      item.remove();
    }
    final time = clone
            .querySelector('span.kmtime, em[id^="authorposton"], .authi em, em')
            ?.text ??
        clone.text;
    return (
      timeText: time.replaceAll(RegExp(r'\s+'), ' ').trim(),
      sourceLabel: source,
      ipText: location
    );
  }
}
