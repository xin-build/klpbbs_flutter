import 'package:html/dom.dart';

/// 列表缩略图只取图片节点的一种来源，头像、表情、勋章不作为正文封面。
class DiscuzImages {
  static bool isContentUrl(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    if (const {'null', 'undefined', '0', '#', 'about:blank'}
        .contains(value.trim().toLowerCase())) {
      return false;
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !const {'https', 'http', ''}.contains(uri.scheme)) {
      return false;
    }
    final path = uri.path.toLowerCase().replaceAll('//', '/');
    if (const [
      'none.png',
      'spacer.gif',
      'loading.gif',
      'loading.png',
      'noavatar_small.gif',
      'noavatar_middle.gif'
    ].any(path.endsWith)) {
      return false;
    }
    if (path.contains('/avatar/') ||
        path.endsWith('/avatar.php') ||
        RegExp(r'_avatar_(?:small|middle|big)\.(?:jpg|png|gif)$')
            .hasMatch(path) ||
        RegExp(r'/common_\d+_icon\.').hasMatch(path) ||
        const [
          '/static/image/common/',
          '/static/image/smiley/',
          '/static/image/stamp/',
          '/static/image/medal/',
          '/static/image/magic/',
          '/static/image/usergroup/',
          '/static/image/admin/',
          '/static/image/mobile/',
          '/static/image/feed/',
          '/smiley/',
          '/smilies/',
          '/smiles/',
          '/filetype/',
          '/bfs/face/'
        ].any((segment) => '/$path'.contains(segment)) ||
        path.contains('facemall') ||
        path.contains('/sunju_') ||
        path.contains('sigline')) {
      return false;
    }
    if (RegExp(
            r'(?:^|/)(?:divider|sigline|signature_line|line)[_\d-]*\.(?:png|gif|jpg)$')
        .hasMatch(path)) {
      return false;
    }
    return true;
  }

  static bool isInterfaceSection(Element element, {Element? stop}) {
    Element? node = element;
    while (node != null && node != stop) {
      if (node.classes.any((name) => const {
                'feed-head',
                'feed-foot',
                'k-av',
                'avt',
                'avr',
                'avatar',
                'by',
                'authi',
                'pls',
                'top_user',
                'top_tximg',
                'kmuser',
                'muser',
                'wzlist_tx',
                'wxlist_tx',
                'comiis_wxlist_tx',
                'comiis_wz_tx',
                'forumlist_li_tx',
                'author_tx',
                'user_tx',
                'authormedals',
                'medaltip',
                'medal',
                'userinfo',
                'authorinfo',
                'user_info',
                'comiis_avatar',
                'comiis_userlist',
                'comiis_postuserinfo',
                'user_img',
                'stamp',
                'comiis_flxx_stamp',
                'reply_list',
                'comment_list',
                'comiis_comments',
              }.contains(name)) ||
          node.id.startsWith('medal_') ||
          node.id.startsWith('retid_')) {
        return true;
      }
      final href = node.attributes['href'] ?? '';
      if (node.localName == 'a' &&
          (RegExp(r'space-uid-\d+').hasMatch(href) ||
              href.contains('mod=space') && href.contains('uid='))) {
        return true;
      }
      node = node.parent;
    }
    return false;
  }

  static String? source(Element node, Uri base, {bool thumbnail = true}) {
    if (node.attributes.containsKey('smilieid') ||
        node.classes.contains('smilie') ||
        node.classes.contains('stamp') ||
        node.classes.contains('top_lev')) {
      return null;
    }
    final width = double.tryParse(node.attributes['width'] ?? '');
    final height = double.tryParse(node.attributes['height'] ?? '');
    final attachment = node.attributes.containsKey('aid') ||
        (node.id.startsWith('aimg_')) ||
        node.attributes.values.any((value) =>
            value.contains('/attachment/') ||
            value.contains('mod=image') && value.contains('aid='));
    if (!attachment &&
        width != null &&
        height != null &&
        width > 0 &&
        height > 0 &&
        width <= 48 &&
        height <= 48) {
      return null;
    }
    if (width != null && height != null && height <= 12 && width >= height * 8) {
      return null;
    }
    final candidates = [
      if (thumbnail) ...['data-thumb', 'thumb', 'comiis_loadimages'],
      'data-src',
      'lazysrc',
      'data-echo',
      'data-original',
      'file',
      'zoomfile',
      'src',
    ];
    for (final attribute in candidates) {
      final candidate = node.attributes[attribute]?.trim();
      if (!isContentUrl(candidate)) continue;
      return base.resolve(candidate!).toString();
    }
    return null;
  }

  static String _identity(String url) {
    final uri = Uri.parse(url);
    final aid = uri.queryParameters['aid'];
    if (aid != null && uri.queryParameters['mod'] == 'image') {
      return '${uri.host}:aid=$aid';
    }
    return '${uri.host}${uri.path.replaceFirstMapped(RegExp(r'\.thumb\.(jpg|png|gif|webp)$'), (match) => '.${match.group(1)}')}';
  }

  static List<String> covers(Element scope, Uri base, {int limit = 3}) {
    if (scope.classes.contains('wzlist_noimg') ||
        scope.classes.contains('noimg')) {
      return const [];
    }
    final seen = <String>{};
    final result = <String>[];
    for (final node in scope.querySelectorAll('img')) {
      if (isInterfaceSection(node, stop: scope)) continue;
      final url = source(node, base);
      if (url != null && seen.add(_identity(url))) result.add(url);
      if (result.length >= limit) return result;
    }
    for (final node in scope.querySelectorAll(
        '[data-cover], .comiis_twimg, .listimg, .listimgs, .comiis_pic')) {
      if (isInterfaceSection(node, stop: scope)) continue;
      final value = node.attributes['data-cover'] ??
          RegExp(r'''url\(\s*['"]?([^'"\)]+)''')
              .firstMatch(node.attributes['style'] ?? '')
              ?.group(1);
      if (!isContentUrl(value)) continue;
      final url = base.resolve(value!).toString();
      if (seen.add(_identity(url))) result.add(url);
      if (result.length >= limit) break;
    }
    return result;
  }
}
