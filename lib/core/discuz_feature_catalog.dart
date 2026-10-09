import 'package:html/parser.dart' as html;

import '../models/site_feature.dart';

/// 站点导航按当前登录人的权限生成；不猜测插件标识、管理权限或会员组 ID。
class DiscuzFeatureCatalog {
  static String _destinationKey(String link, Uri base) {
    final uri = base.resolve(link.replaceAll('&amp;', '&'));
    final parameters = Map.of(uri.queryParametersAll)
      ..remove('mobile')
      ..remove('handlekey');
    final names = parameters.keys.toList()..sort();
    final query = names.map((name) {
      final values = parameters[name]!.map(Uri.encodeQueryComponent).join(',');
      return '${Uri.encodeQueryComponent(name)}=$values';
    }).join('&');
    return '${uri.origin}${uri.path}?$query#${uri.fragment}';
  }

  /// 路径和完整查询共同标识入口，避免无参数的管理后台被任意其他功能去重。
  static bool sameDestination(String first, String second, Uri base) {
    try {
      return _destinationKey(first, base) == _destinationKey(second, base);
    } on FormatException {
      return false;
    }
  }

  static Uri? navigationUri(String? link, Uri base,
      {bool allowExternal = false}) {
    if (link == null || link.trim().isEmpty) return null;
    final uri = base.resolve(link.replaceAll('&amp;', '&'));
    if (!const {'http', 'https'}.contains(uri.scheme) ||
        (uri.origin != base.origin &&
            (!allowExternal || uri.scheme != 'https')) ||
        uri.queryParameters.containsKey('formhash') ||
        uri.fragment.isNotEmpty && uri.path == base.path) {
      return null;
    }
    if (const {'logout', 'delete', 'apply', 'qiandao', 'accept'}
            .contains(uri.queryParameters['action']) ||
        uri.queryParameters['operation'] == 'qiandao' ||
        uri.queryParameters.containsKey('to')) {
      return null;
    }
    return uri;
  }

  static String category(Uri uri, String title) {
    if (uri.path.endsWith('admin.php') ||
        uri.queryParameters['mod'] == 'modcp') {
      return '管理';
    }
    if (uri.queryParameters['ac'] == 'usergroup' ||
        RegExp(r'VIP|SVIP|会员|充值|赞助', caseSensitive: false).hasMatch(title)) {
      return '积分与会员';
    }
    if (uri.queryParameters['mod'] == 'spacecp') {
      if (const {'credit', 'promotion'}.contains(uri.queryParameters['ac'])) {
        return '积分与会员';
      }
      if (uri.queryParameters['ac'] == 'plugin') return '站点扩展';
      return '账号与隐私';
    }
    if (uri.queryParameters['mod'] == 'space' ||
        uri.queryParameters['view'] == 'my') {
      return '我的';
    }
    return '社区';
  }

  static List<SiteFeature> parse(String source, Uri base) {
    final doc = html.parse(source);
    final result = <SiteFeature>[];
    final seen = <String>{};
    final externalLinks =
        doc.querySelectorAll('#nv a[href], #toptb a[href]').toSet();
    final nodesById = {
      for (final node in doc.querySelectorAll('[id]')) node.id: node,
    };
    // Discuz 把导航下拉菜单放在 #nv 之外，按导航 ID 关联，避免漏掉站点工具。
    for (final nav in doc.querySelectorAll('#nv a[id], #toptb a[id]')) {
      final menu = nodesById['${nav.id}_menu'];
      if (menu != null) externalLinks.addAll(menu.querySelectorAll('a[href]'));
    }
    externalLinks.addAll(doc.querySelectorAll('.klp-rail-foot a[href]'));
    final links = doc.querySelectorAll(
        '.klp-cp-nav a[href], #nv a[href], #klp-me-menu a[href], .comiis_sidenv a[href], '
        '.comiis_usernav a[href], #toptb a[href], .modcp_nav a[href], .appl a[href], '
        '#ct .tb a[href], #ct a[href*="vip"], #ct a[href*="svip"]');
    for (final link in {...links, ...externalLinks}) {
      final uri = navigationUri(link.attributes['href'], base,
          allowExternal: externalLinks.contains(link));
      if (uri == null) continue;
      final copy = link.clone(true);
      copy
          .querySelectorAll('svg, img, .k-meta, .k-mono')
          .forEach((node) => node.remove());
      var title = copy.text
          .replaceAll(RegExp(r'[\uE000-\uF8FF]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty || title.length > 48) continue;
      if (const {'手机版', '电脑版', '触屏版', 'Archiver'}.contains(title)) continue;
      if (uri.queryParameters['ac'] == 'usergroup' &&
          (link.id == 'g_upmine' ||
              title == '用户组' ||
              title.startsWith('用户组:'))) {
        title = '用户组与会员';
      }
      final key = _destinationKey(uri.toString(), base);
      if (!seen.add(key)) continue;
      result.add(SiteFeature(
          title: title,
          url: uri.toString(),
          category: uri.origin == base.origin ? category(uri, title) : '站点工具'));
    }
    return result;
  }

  static List<MembershipOffer> memberships(String source, Uri base) {
    final doc = html.parse(source);
    final result = <MembershipOffer>[];
    final seen = <int>{};
    for (final row in doc.querySelectorAll(
        '#ct table tr, .klp-cp-main table tr, .klp-group-card, .comiis_usergroup li')) {
      final links = row.querySelectorAll('a[href*="ac=usergroup"]');
      Uri? route(String operation) {
        for (final link in links) {
          final uri = navigationUri(link.attributes['href'], base);
          if (uri?.queryParameters['do'] == operation) return uri;
        }
        return null;
      }

      final buy = route('buy'), change = route('switch'), exit = route('exit');
      final nameLink =
          row.querySelector('a[href*="ac=usergroup"][href*="gid="]');
      final groupId = int.tryParse(
          (buy ?? change ?? exit)?.queryParameters['groupid'] ??
              Uri.tryParse(nameLink?.attributes['href'] ?? '')
                  ?.queryParameters['gid'] ??
              '');
      if (groupId == null || !seen.add(groupId)) continue;
      final name = nameLink?.text.trim() ??
          row.querySelector('th, td')?.text.trim() ??
          '';
      if (name.isEmpty) continue;
      final details = row.clone(true);
      details
          .querySelectorAll('a, script, style')
          .forEach((element) => element.remove());
      result.add(MembershipOffer(
          groupId: groupId,
          title: name,
          details: details.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
          buyUrl: buy?.toString(),
          switchUrl: change?.toString(),
          exitUrl: exit?.toString(),
          permissionsUrl:
              navigationUri(nameLink?.attributes['href'], base)?.toString()));
    }
    return result;
  }
}
