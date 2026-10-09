import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'discuz_cookie_jar.dart';
import 'discuz_request_policy.dart';
import '../models/server_outage_info.dart';

/// 页面模板、会话范围及 HTTP 重定向由同一请求入口管理。
class DioClient {
  DioClient._();

  static final Dio dio = _build();
  static final _jar = DiscuzCookieJar();
  static const _cookiePrefsKey = 'session_cookies_v2';
  static const _legacyCookiePrefsKey = 'session_cookies_v1';
  static Future<void> _pendingSave = Future.value();
  static final sessionChanges = ValueNotifier<int>(0);
  static String? _lastSessionKey;
  static Uri get _forum => Uri.parse(AppConfig.baseUrl);

  static String? cookie(String name) => _jar.valueFor(name, _forum);
  static String get allCookiesHeader => cookiesForUrl(AppConfig.baseUrl);
  static String cookiesForUrl(String url) =>
      _jar.headerFor(_forum.resolve(url));
  static List<DiscuzCookie> browserCookiesFor(String url) =>
      _jar.cookiesFor(_forum.resolve(url)).toList();

  /// 只包含源站和认证身份的摘要，避免 SID 轮换使所有页面缓存失效。
  static String get sessionKey {
    final auth = _jar
        .cookiesFor(_forum)
        .where((cookie) => DiscuzCookieJar.isAuthCookie(cookie.name))
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .toList()
      ..sort();
    return sha256
        .convert(utf8.encode('${_forum.origin}|${auth.join(';')}'))
        .toString();
  }

  /// Discuz 用 saltkey 派生 auth 加密密钥；并发的首次响应不能互相替换它。
  /// 此标识只保护请求，不触发页面重建或缓存清空。
  static String get cookieStateKey {
    final identity = _jar
        .cookiesFor(_forum)
        .where((cookie) =>
            DiscuzCookieJar.isAuthCookie(cookie.name) ||
            cookie.name == 'saltkey' ||
            cookie.name.endsWith('_saltkey'))
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .toList()
      ..sort();
    return sha256
        .convert(utf8.encode('${_forum.origin}|${identity.join(';')}'))
        .toString();
  }

  static void _notifySession() {
    final key = sessionKey;
    if (_lastSessionKey == key) return;
    _lastSessionKey = key;
    sessionChanges.value++;
  }

  static void setCookie(String name, String value) {
    _jar.importValues({name: value}, _forum);
    _notifySession();
  }

  static Future<void> saveCookies() {
    final snapshot = jsonEncode(_jar.toJson());
    _pendingSave = _pendingSave.then((_) async {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_cookiePrefsKey, snapshot);
      await sp.remove(_legacyCookiePrefsKey);
    }).catchError((Object error) {
      debugPrint('保存论坛会话失败: ${error.runtimeType}');
    });
    return _pendingSave;
  }

  static Future<void> loadCookies() async {
    final sp = await SharedPreferences.getInstance();
    final scoped = sp.getString(_cookiePrefsKey);
    if (scoped != null) {
      try {
        final records = jsonDecode(scoped);
        if (records is List) _jar.restore(records);
      } on FormatException {
        _jar.clear();
      }
    } else {
      // 旧版无域信息，仅迁移到当前配置的论坛，不能广播给其他站点。
      final values = <String, String>{};
      for (final pair
          in sp.getStringList(_legacyCookiePrefsKey) ?? <String>[]) {
        final index = pair.indexOf('=');
        if (index > 0) {
          values[pair.substring(0, index).trim()] =
              pair.substring(index + 1).trim();
        }
      }
      _jar.importValues(values, _forum);
      await saveCookies();
    }
    _notifySession();
  }

  static Future<void> importCookies(Map<String, String> cookies) async {
    _jar.importValues(cookies, _forum);
    _notifySession();
    await saveCookies();
  }

  static Future<void> importCookieString(String rawCookieHeader) async {
    final values = <String, String>{};
    for (final pair in rawCookieHeader.split(';')) {
      final index = pair.indexOf('=');
      if (index > 0) {
        values[pair.substring(0, index).trim()] =
            pair.substring(index + 1).trim();
      }
    }
    await importCookies(values);
  }

  static Future<void> Function()? onSessionCleared;

  static Future<void> clearCookies() async {
    _jar.clear();
    _notifySession();
    await saveCookies();
    final sp = await SharedPreferences.getInstance();
    for (final key in [
      'fav_forums',
      'fav_tids',
      'liked_tids',
      'liked_pids',
      'cached_forum_groups_json'
    ]) {
      await sp.remove(key);
    }
    await onSessionCleared?.call();
  }

  static bool get isLoggedIn {
    return _jar
        .cookiesFor(_forum)
        .any((cookie) => DiscuzCookieJar.isAuthCookie(cookie.name));
  }

  static bool updateCookiesFromHeaders(List<String>? headers,
      {Uri? source, String? requestSession, String? requestCookieState}) {
    // 账号切换后，旧请求中的认证删除或续期不能覆盖新账号。
    if (requestSession != null && requestSession != sessionKey) return false;
    if (requestCookieState != null && requestCookieState != cookieStateKey) {
      return false;
    }
    if (headers == null || headers.isEmpty) return true;
    final uri = source ?? _forum;
    // CDN 和外链不能设置论坛认证状态。
    if (!DiscuzCookieJar.domainMatches(uri.host, _forum.host)) return true;
    if (_jar.applyHeaders(headers, uri)) {
      _notifySession();
      unawaited(saveCookies());
    }
    return true;
  }

  static String? _header(Map<String, dynamic> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value?.toString();
      }
    }
    return null;
  }

  static void _removeHeader(Map<String, dynamic> headers, String name) {
    DiscuzRequestPolicy.removeHeader(headers, name);
  }

  static String userAgentFor(Uri uri, {Map<String, String>? headers}) =>
      DiscuzRequestPolicy.userAgentFor(
        uri,
        mobileUserAgent: AppConfig.mobileUserAgent,
        desktopUserAgent: AppConfig.pcUserAgent,
        composerUserAgent: AppConfig.userAgent,
        explicitUserAgent:
            headers == null ? null : _header(headers, 'User-Agent'),
        referer: headers == null ? null : _header(headers, 'Referer'),
      );

  static Dio _build() {
    AppConfig.getCookieHeader = () => allCookiesHeader;
    AppConfig.getCookieHeaderForUrl = cookiesForUrl;
    AppConfig.onForumChanged = _notifySession;
    final d = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.timeout,
      receiveTimeout: AppConfig.timeout,
      sendTimeout: AppConfig.timeout,
      followRedirects: false,
      headers: {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      },
    ));
    if (!kIsWeb) {
      d.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) => AppConfig.useSystemProxy
            ? HttpClient.findProxyFromEnvironment(uri)
            : 'DIRECT';
        return client;
      });
    }
    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.baseUrl = AppConfig.baseUrl;
        final expected = options.extra['discuz.expectedSession'];
        if (expected != null && expected != sessionKey) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            error: StateError('账号已变化，请重新打开表单'),
          ));
          return;
        }
        _notifySession();
        options.extra['discuz.session'] = sessionKey;
        options.extra['discuz.cookieState'] = cookieStateKey;
        final suppliedUa = _header(options.headers, 'User-Agent');
        final generatedUa = options.extra['discuz.generatedUa'];
        final ua = DiscuzRequestPolicy.userAgentFor(
          options.uri,
          mobileUserAgent: AppConfig.mobileUserAgent,
          desktopUserAgent: AppConfig.pcUserAgent,
          composerUserAgent: AppConfig.userAgent,
          explicitUserAgent: suppliedUa == generatedUa ? null : suppliedUa,
          referer: _header(options.headers, 'Referer'),
        );
        if (suppliedUa == null || suppliedUa == generatedUa) {
          options.extra['discuz.generatedUa'] = ua;
        }
        _removeHeader(options.headers, 'User-Agent');
        options.headers['User-Agent'] = ua;
        final chrome = RegExp(r'Chrome/(\d+)').firstMatch(ua);
        for (final header in [
          'Sec-Ch-Ua',
          'Sec-Ch-Ua-Mobile',
          'Sec-Ch-Ua-Platform'
        ]) {
          _removeHeader(options.headers, header);
        }
        if (chrome != null) {
          options.headers['Sec-Ch-Ua'] =
              '"Chromium";v="${chrome.group(1)}", "Google Chrome";v="${chrome.group(1)}", "Not_A Brand";v="99"';
          options.headers['Sec-Ch-Ua-Mobile'] =
              ua.contains('Mobile') ? '?1' : '?0';
          final platform = ua.contains('Android')
              ? 'Android'
              : ua.contains('Windows')
                  ? 'Windows'
                  : ua.contains('Macintosh')
                      ? 'macOS'
                      : 'Linux';
          options.headers['Sec-Ch-Ua-Platform'] = '"$platform"';
        }
        options.headers['Referer'] ??= AppConfig.baseUrl;
        // Redirects reuse RequestOptions. A header generated for inajax must
        // not become a caller's explicit XHR declaration on the next hop.
        final explicitAjax = options.extra['discuz.generatedAjax'] != true &&
            _header(options.headers, 'X-Requested-With')
                    ?.trim()
                    .toLowerCase() ==
                'xmlhttprequest';
        final ajax = explicitAjax ||
            const {'1', 'yes', 'true'}
                .contains(options.uri.queryParameters['inajax']);
        if (ajax && !explicitAjax) {
          options.extra['discuz.generatedAjax'] = true;
        } else {
          options.extra.remove('discuz.generatedAjax');
        }
        options.headers['Sec-Fetch-Dest'] = ajax ? 'empty' : 'document';
        options.headers['Sec-Fetch-Mode'] = ajax ? 'cors' : 'navigate';
        options.headers['Sec-Fetch-Site'] =
            DiscuzRequestPolicy.sameOrigin(options.uri, _forum)
                ? 'same-origin'
                : 'cross-site';
        _removeHeader(options.headers, 'X-Requested-With');
        if (ajax) options.headers['X-Requested-With'] = 'XMLHttpRequest';
        if (!ReadWritePolicy.isAllowed(
            options.method, options.uri.toString())) {
          handler.reject(
              DioException(requestOptions: options, message: '请求目标不允许此操作'));
          return;
        }
        _removeHeader(options.headers, 'Cookie');
        final cookies = _jar.headerFor(options.uri);
        if (cookies.isNotEmpty) options.headers['Cookie'] = cookies;
        handler.next(options);
      },
      onResponse: (response, handler) async {
        final request = response.requestOptions;
        request.extra['discuz.cookiesAccepted'] = updateCookiesFromHeaders(
            response.headers['set-cookie'],
            source: request.uri,
            requestSession: request.extra['discuz.session'] as String?,
            requestCookieState: request.extra['discuz.cookieState'] as String?);
        final code = response.statusCode ?? 0;
        if (!const {301, 302, 303, 307, 308}.contains(code)) {
          handler.next(response);
          return;
        }
        final depth = request.extra['discuz.redirects'] as int? ?? 0;
        final location = response.headers.value('location');
        if (depth >= 5 || location == null || location.trim().isEmpty) {
          handler.reject(DioException(
              requestOptions: request,
              response: response,
              message: depth >= 5 ? '重定向次数过多' : '重定向缺少 Location'));
          return;
        }
        final target = request.uri.resolve(location);
        final method = DiscuzRequestPolicy.redirectMethod(code, request.method);
        if (!ReadWritePolicy.isAllowed(method, target.toString())) {
          handler.reject(
              DioException(requestOptions: request, message: '重定向目标不允许此操作'));
          return;
        }
        final next = request.copyWith(
            path: target.toString(),
            method: method,
            queryParameters: <String, dynamic>{},
            headers: Map<String, dynamic>.from(request.headers),
            extra: {...request.extra, 'discuz.redirects': depth + 1});
        if (method != request.method.toUpperCase()) {
          next.data = null;
          _removeHeader(next.headers, 'Content-Type');
          _removeHeader(next.headers, 'Content-Length');
        }
        if (!DiscuzRequestPolicy.sameOrigin(request.uri, target)) {
          for (final name in [
            'Authorization',
            'Cookie',
            'Origin',
            'X-Requested-With'
          ]) {
            _removeHeader(next.headers, name);
          }
        }
        try {
          handler.resolve(await d.fetch<dynamic>(next));
        } on DioException catch (error) {
          handler.reject(error);
        } catch (error) {
          handler.reject(DioException(requestOptions: next, error: error));
        }
      },
      onError: (error, handler) {
        updateCookiesFromHeaders(error.response?.headers['set-cookie'],
            source: error.requestOptions.uri,
            requestSession:
                error.requestOptions.extra['discuz.session'] as String?,
            requestCookieState:
                error.requestOptions.extra['discuz.cookieState'] as String?);
        if (ServerOutageInfo.isOutageDioException(error)) {
          error = error.copyWith(
              error: ServerOutageException(
                  ServerOutageInfo.fromDioException(error)));
        }
        handler.next(error);
      },
    ));
    return d;
  }
}

class ReadWritePolicy {
  static bool isAllowed(String method, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host.isEmpty ||
        !const {'http', 'https'}.contains(uri.scheme)) {
      return false;
    }
    if (const {'GET', 'HEAD'}.contains(method.toUpperCase())) return true;
    final host = uri.host.toLowerCase();
    final forumHost = Uri.parse(AppConfig.baseUrl).host.toLowerCase();
    final allowed = (forumHost.isNotEmpty &&
            DiscuzCookieJar.domainMatches(host, forumHost)) ||
        DiscuzCookieJar.domainMatches(host, 'klpbbs.com') ||
        host == 'localhost' ||
        host == '127.0.0.1';
    return allowed && AppConfig.allowWrite;
  }
}
