import 'dart:io';

class DiscuzCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;
  final DateTime? expires;

  const DiscuzCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.hostOnly = true,
    this.secure = false,
    this.expires,
  });

  String get key => '$domain|$path|$name';

  bool matches(Uri uri, DateTime now) {
    if (expires != null && !expires!.isAfter(now)) return false;
    if (secure && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (hostOnly
        ? host != domain
        : !DiscuzCookieJar.domainMatches(host, domain)) {
      return false;
    }
    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    return requestPath == path ||
        (requestPath.startsWith(path) &&
            (path.endsWith('/') ||
                (requestPath.length > path.length &&
                    requestPath[path.length] == '/')));
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'hostOnly': hostOnly,
        'secure': secure,
        'expires': expires?.toUtc().millisecondsSinceEpoch,
      };
}

/// A small RFC 6265 cookie jar. Template-selection cookies are deliberately
/// omitted so simultaneous PC and Comiis requests cannot change each other.
class DiscuzCookieJar {
  final _cookies = <String, DiscuzCookie>{};

  static bool domainMatches(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static bool isAuthCookie(String name) =>
      name == 'auth' || name.endsWith('_auth');

  static bool isTemplateCookie(String name) => const {
        'mobile',
        'dismobile',
        'dismobilemessage',
        'ordertype',
      }.any((suffix) => name == suffix || name.endsWith('_$suffix'));

  void clear() => _cookies.clear();

  List<DiscuzCookie> cookiesFor(Uri uri, {DateTime? now}) {
    final time = now ?? DateTime.now();
    _cookies.removeWhere(
      (_, cookie) => cookie.expires != null && !cookie.expires!.isAfter(time),
    );
    return _cookies.values.where((cookie) => cookie.matches(uri, time)).toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
  }

  String headerFor(Uri uri, {DateTime? now}) => cookiesFor(uri, now: now)
      .map((cookie) => '${cookie.name}=${cookie.value}')
      .join('; ');

  String? valueFor(String name, Uri uri) {
    for (final cookie in cookiesFor(uri)) {
      if (cookie.name == name) return cookie.value;
    }
    return null;
  }

  bool put(DiscuzCookie cookie, {DateTime? now}) {
    if (cookie.name.isEmpty ||
        cookie.name.contains(RegExp(r'[\s;=\r\n]')) ||
        cookie.value.contains(RegExp(r'[;\r\n]')) ||
        cookie.domain.isEmpty ||
        isTemplateCookie(cookie.name)) {
      return false;
    }
    final expired = cookie.expires != null &&
        !cookie.expires!.isAfter(now ?? DateTime.now());
    if (cookie.value.isEmpty || cookie.value == 'deleted' || expired) {
      return _cookies.remove(cookie.key) != null;
    }
    if ((cookie.name == 'sid' || cookie.name.endsWith('_sid')) &&
        cookie.value == '0') {
      return false;
    }
    final old = _cookies[cookie.key];
    if (old != null &&
        old.value == cookie.value &&
        old.secure == cookie.secure &&
        old.hostOnly == cookie.hostOnly &&
        old.expires == cookie.expires) {
      return false;
    }
    _cookies[cookie.key] = cookie;
    return true;
  }

  bool importValues(Map<String, String> values, Uri source) {
    var changed = false;
    for (final entry in values.entries) {
      changed = put(DiscuzCookie(
            name: entry.key,
            value: entry.value,
            domain: source.host.toLowerCase(),
            secure: source.scheme == 'https',
          )) ||
          changed;
    }
    return changed;
  }

  bool applyHeaders(Iterable<String> headers, Uri source, {DateTime? now}) {
    var changed = false;
    final time = now ?? DateTime.now();
    for (final header in headers) {
      final parts = header.split(';');
      final pair = parts.first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      var domain = source.host.toLowerCase();
      var hostOnly = true;
      var secure = false;
      var path = _defaultPath(source.path);
      DateTime? expires;
      int? maxAge;
      var valid = true;
      for (final rawAttribute in parts.skip(1)) {
        final attribute = rawAttribute.trim();
        final index = attribute.indexOf('=');
        final key = (index < 0 ? attribute : attribute.substring(0, index))
            .toLowerCase();
        final val = index < 0 ? '' : attribute.substring(index + 1).trim();
        switch (key) {
          case 'domain':
            domain = val.toLowerCase().replaceFirst(RegExp(r'^\.+'), '');
            hostOnly = false;
            valid = domainMatches(source.host.toLowerCase(), domain) &&
                (domain == source.host.toLowerCase() || domain.contains('.'));
          case 'path':
            if (val.startsWith('/')) path = val;
          case 'secure':
            secure = true;
          case 'max-age':
            maxAge = int.tryParse(val);
          case 'expires':
            try {
              // Cookie 日期采用 RFC 6265 的宽容语法；PHP 也会输出 04-Nov-2026。
              expires = Cookie.fromSetCookieValue('check=1; Expires=$val').expires;
            } on FormatException {
              // Invalid Expires is ignored, as it is in a browser.
            } on HttpException {
              // 无效的日期属性不应使整条 HTTP 响应失败。
            }
        }
      }
      if (!valid) continue;
      if (maxAge != null) {
        final seconds = maxAge.clamp(-1, 315360000);
        expires = time.add(Duration(seconds: seconds));
      }
      changed = put(
              DiscuzCookie(
                name: name,
                value: value,
                domain: domain,
                path: path,
                hostOnly: hostOnly,
                secure: secure,
                expires: expires,
              ),
              now: time) ||
          changed;
    }
    return changed;
  }

  static String _defaultPath(String path) {
    if (!path.startsWith('/') || path.lastIndexOf('/') <= 0) return '/';
    return path.substring(0, path.lastIndexOf('/'));
  }

  List<Map<String, Object?>> toJson() {
    final now = DateTime.now();
    _cookies.removeWhere(
      (_, cookie) => cookie.expires != null && !cookie.expires!.isAfter(now),
    );
    return _cookies.values.map((cookie) => cookie.toJson()).toList();
  }

  void restore(Iterable<dynamic> records) {
    clear();
    for (final record in records) {
      if (record is! Map) continue;
      final expires = record['expires'];
      final domain = record['domain']?.toString().toLowerCase() ?? '';
      final path = record['path']?.toString() ?? '/';
      if (!path.startsWith('/')) continue;
      put(DiscuzCookie(
        name: record['name']?.toString() ?? '',
        value: record['value']?.toString() ?? '',
        domain: domain,
        path: path,
        hostOnly: record['hostOnly'] != false,
        secure: record['secure'] == true,
        expires: expires is num
            ? DateTime.fromMillisecondsSinceEpoch(expires.toInt(), isUtc: true)
            : null,
      ));
    }
  }
}
