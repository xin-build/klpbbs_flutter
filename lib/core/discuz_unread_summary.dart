import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'discuz_session_parser.dart';

/// Counts declared by account navigation, without opening a message list.
/// Null means the template did not provide an exact count, rather than zero.
class DiscuzUnreadSummary {
  final int? unreadNotices;
  final int? unreadPm;
  const DiscuzUnreadSummary({this.unreadNotices, this.unreadPm});

  static DiscuzUnreadSummary? parse(String source, Uri base,
      {int? expectedUid}) {
    final uid = DiscuzSessionParser.parse(source).uid;
    if (uid == null || (expectedUid != null && uid != expectedUid)) return null;
    final doc = html.parse(source);
    final result = DiscuzUnreadSummary(
        unreadNotices: _count(doc.querySelector('a#myprompt'), 'notice', base),
        unreadPm: _count(doc.querySelector('a#pm_ntc'), 'pm', base));
    return result.unreadNotices == null && result.unreadPm == null
        ? null
        : result;
  }

  static int? _count(dom.Element? link, String destination, Uri base) {
    if (link == null) return null;
    final declared = Uri.tryParse(link.attributes['href'] ?? '');
    if (declared == null) return null;
    final uri = base.resolveUri(declared);
    if (uri.origin != base.origin ||
        uri.userInfo.isNotEmpty ||
        !uri.path.endsWith('/home.php') ||
        uri.queryParametersAll['mod']?.length != 1 ||
        uri.queryParameters['mod'] != 'space' ||
        uri.queryParametersAll['do']?.length != 1 ||
        uri.queryParameters['do'] != destination ||
        uri.queryParameters.containsKey('ignore')) {
      return null;
    }
    final badges = <int>{};
    var ambiguous = false;
    for (final node in link.querySelectorAll('em, span, b')) {
      final text = node.text.trim();
      if (text.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(text)) {
        badges.add(int.parse(text));
      } else {
        // "99+", dots and an unread flag do not declare an exact count.
        ambiguous = true;
      }
    }
    if (badges.length == 1 && !ambiguous) return badges.single;
    if (badges.isNotEmpty || ambiguous || link.classes.contains('new')) {
      return null;
    }
    // Both current KLPBBS PC icons and Discuz navigation omit the badge at
    // zero. Require a known account icon, not an arbitrary link in a post.
    final label = link.text.trim();
    return label.isEmpty || const {'提醒', '通知', '消息', '私信'}.contains(label)
        ? 0
        : null;
  }
}
