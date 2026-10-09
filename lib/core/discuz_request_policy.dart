/// The response template is a property of the endpoint, not the app layout.
/// Discuz X3.4 still checks the UA when `mobile=2` is supplied.
enum DiscuzTemplate { mobile, desktop, composer }

class DiscuzRequestPolicy {
  DiscuzRequestPolicy._();

  /// Dio 使用带自定义比较器的 Map；逐个 remove 避免 Dart 开发版的 removeWhere 问题。
  static void removeHeader(Map<String, dynamic> headers, String name) {
    final keys = headers.keys
        .where((key) => key.toLowerCase() == name.toLowerCase())
        .toList();
    for (final key in keys) {
      headers.remove(key);
    }
  }

  static DiscuzTemplate templateFor(Uri uri) {
    final query = {
      for (final entry in uri.queryParameters.entries)
        entry.key.toLowerCase(): entry.value.toLowerCase(),
    };
    final mobile = query['mobile'];
    if (mobile == 'no') return DiscuzTemplate.desktop;
    if (const {'1', '2', '3', 'yes'}.contains(mobile)) {
      return DiscuzTemplate.mobile;
    }

    final file = uri.path.split('/').last.toLowerCase();
    final mod = query['mod'];
    final action = query['action'];
    if (file == 'forum.php' && mod == 'post') {
      return DiscuzTemplate.composer;
    }
    if (file == 'admin.php' ||
        (file == 'member.php' && mod == 'logging') ||
        (file == 'misc.php' && mod == 'seccode') ||
        (file == 'forum.php' &&
            (mod == 'modcp' ||
                mod == 'topicadmin' ||
                (mod == 'misc' &&
                    const {'rate', 'viewratings'}.contains(action)))) ||
        (file == 'home.php' &&
            (mod == 'magic' ||
                (mod == 'medal' && action == 'order') ||
                (mod == 'spacecp' &&
                    (query['ac'] == 'usergroup' ||
                        (query['ac'] == 'credit' &&
                            query['op'] == 'transfer'))))) ||
        file == 'k_misign-sign.html' ||
        file == 'klpbbs_medal_order-order.html' ||
        (file == 'plugin.php' &&
            ((query['id'] ?? '').startsWith('klpbbs_ai') ||
                query['id'] == 'k_misign:sign'))) {
      return DiscuzTemplate.desktop;
    }
    return DiscuzTemplate.mobile;
  }

  static String userAgentFor(
    Uri uri, {
    required String mobileUserAgent,
    required String desktopUserAgent,
    required String composerUserAgent,
    String? explicitUserAgent,
    String? referer,
  }) {
    if (explicitUserAgent != null && explicitUserAgent.trim().isNotEmpty) {
      return explicitUserAgent;
    }
    var template = templateFor(uri);
    // A captcha must use the same template as the form that requested it.
    if (uri.path.endsWith('misc.php') &&
        uri.queryParameters['mod'] == 'seccode' &&
        referer != null) {
      final formUri = Uri.tryParse(referer);
      if (formUri != null) template = templateFor(formUri);
    }
    return switch (template) {
      DiscuzTemplate.mobile => mobileUserAgent,
      DiscuzTemplate.desktop => desktopUserAgent,
      DiscuzTemplate.composer => composerUserAgent,
    };
  }

  static bool isCacheable(Uri uri) {
    final query = uri.queryParameters;
    final file = uri.path.split('/').last;
    // 编辑凭证、验证码和账号绑定状态必须来自当前页面。
    if (file == 'forum.php' && query['mod'] == 'post' ||
        file == 'misc.php' && query['mod'] == 'seccode' ||
        file == 'member.php' && query['mod'] == 'logging' ||
        file == 'home.php' &&
            query['mod'] == 'spacecp' &&
            const {'profile', 'avatar'}.contains(query['ac']) ||
        query['id'] == 'klpbbs_pnbind:my_bind' ||
        (query['id'] ?? '').startsWith('klpbbs_new_api:') ||
        file == 'klpbbs_new_api-console.html') {
      return false;
    }
    if (query.containsKey('formhash') ||
        query.containsKey('ignore') ||
        const {'1', 'yes', 'true'}.contains(query['inajax'])) {
      return false;
    }
    if (query.keys.any((key) => key.toLowerCase().endsWith('submit'))) {
      return false;
    }
    return !const {
      'logout',
      'delete',
      'del',
      'clear',
      'send',
      'add',
      'apply',
      'qiandao',
      'buy',
      'give',
      'use',
      'receive',
      'draw',
      'ignore',
      'switch',
      'exit',
      'deleteattach',
    }.any((action) => [
          query['action'],
          query['operation'],
          query['do'],
          query['op']
        ].contains(action));
  }

  static String redirectMethod(int status, String method) {
    final upper = method.toUpperCase();
    if ((status == 303 && upper != 'HEAD') ||
        ((status == 301 || status == 302) && upper == 'POST')) {
      return 'GET';
    }
    return upper;
  }

  static bool sameOrigin(Uri first, Uri second) =>
      first.scheme == second.scheme &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      first.port == second.port;
}
