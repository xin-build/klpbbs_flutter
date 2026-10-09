import 'package:html/parser.dart' as html;

/// 校验导读实际选中的分类；站点忽略 view 参数时不把热门结果当作图集。
class DiscuzGuideProtocol {
  static const views = {'hot', 'new', 'newthread', 'digest', 'follow', 'sofa'};

  static String? activeView(String source) {
    final doc = html.parse(source);
    for (final link in doc.querySelectorAll(
        '.klp-home-seg a.on, .comiis_topnv .f_0 a, li.flex.f_0 a, #ct .tb .a a')) {
      final uri = Uri.tryParse(link.attributes['href'] ?? '');
      if (uri?.queryParameters['mod'] == 'guide') {
        return uri?.queryParameters['view'];
      }
    }
    return null;
  }

  static bool recognizes(String source, String expectedView) {
    if (!views.contains(expectedView)) return false;
    final doc = html.parse(source);
    if (doc.querySelector(
            '#messagetext, .alert_error, #loginform, form[id^="loginform_"]') !=
        null) {
      return false;
    }
    final active = activeView(source);
    if (active != null && active != expectedView) return false;
    return doc.querySelector(
            '.klp-feed, .comiis_forumlist, #threadlist, #ct .tl') !=
        null;
  }

  static int? nextPage(String source, String view, int currentPage, Uri base) {
    final doc = html.parse(source);
    for (final link
        in doc.querySelectorAll('.klp-feed-more, .pg a.nxt, .pg a.next')) {
      final Uri uri;
      try {
        uri = base.resolve(link.attributes['href'] ?? '');
      } on FormatException {
        continue;
      }
      if (uri.scheme != 'https' && uri.scheme != 'http') continue;
      final q = uri.queryParameters;
      final page = int.tryParse(q['page'] ?? '');
      if (uri.origin == base.origin &&
          uri.userInfo.isEmpty &&
          uri.path.endsWith('/forum.php') &&
          uri.queryParametersAll.values.every((values) => values.length == 1) &&
          q['mod'] == 'guide' &&
          q['view'] == view &&
          page != null &&
          page == currentPage + 1 &&
          recognizes(source, view)) {
        return page;
      }
    }
    return null;
  }
}
