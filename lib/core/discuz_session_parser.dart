import 'package:html/parser.dart' as html;

/// 只从站点会话变量或账号导航提取身份，页面中的作者/空间 UID 不代表登录人。
class DiscuzSessionParser {
  static ({int? uid, String? username}) parse(String source) {
    final doc = html.parse(source);
    int? uid;
    for (final script in doc.querySelectorAll('script')) {
      final match = RegExp(r'''\b(?:discuz_uid|comiis_uid)\s*=\s*['"]?(\d+)''')
          .firstMatch(script.text);
      if (match != null) {
        final value = int.tryParse(match.group(1)!);
        if (value == 0) return (uid: null, username: null);
        uid = value;
        break;
      }
    }
    final account = doc.querySelector(
        '#um a[title="访问我的空间"], #um .vwmy a, #myitem a[title="访问我的空间"]');
    if (uid == null && account != null) {
      final link = account.attributes['href'] ?? '';
      final match = RegExp(r'(?:[?&]uid=|space-uid-)(\d+)').firstMatch(link);
      uid = match == null ? null : int.tryParse(match.group(1)!);
    }
    final name = account?.text.trim();
    return (
      uid: uid != null && uid > 0 ? uid : null,
      username: name?.isNotEmpty == true ? name : null
    );
  }
}
