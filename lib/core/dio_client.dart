import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Dio 单例：统一 UA、超时、Cookie 会话管理与环境感知写策略
class DioClient {
  DioClient._();

  static final Dio dio = _build();

  /// 会话 cookie 存储（登录后持久化）
  static final Map<String, String> _cookies = {};

  /// 获取会话 cookie
  static String? cookie(String name) => _cookies[name];

  /// 获取完整 Cookie 请求头字符串
  static String get allCookiesHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// 手动设置会话 cookie
  static void setCookie(String name, String value) {
    _cookies[name] = value;
  }

  static const String _cookiePrefsKey = 'session_cookies_v1';

  /// 持久化当前会话 cookie（登录成功/导入 Cookie 后调用）
  static Future<void> saveCookies() async {
    if (_cookies.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(
        _cookiePrefsKey,
        _cookies.entries.map((e) => '${e.key}=${e.value}').toList(),
      );
    } catch (_) {}
  }

  /// 从本地恢复会话 cookie（App 启动时调用）
  static Future<void> loadCookies() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getStringList(_cookiePrefsKey) ?? const [];
      for (final item in raw) {
        final idx = item.indexOf('=');
        if (idx <= 0) continue;
        final name = item.substring(0, idx).trim();
        final value = item.substring(idx + 1).trim();
        if (name.isNotEmpty && value.isNotEmpty && value != 'deleted') {
          _cookies[name] = value;
        }
      }
    } catch (_) {}
  }

  /// 导入 Cookie 键值对 Map 并持久化
  static Future<void> importCookies(Map<String, String> cookies) async {
    for (final e in cookies.entries) {
      if (e.key.isNotEmpty && e.value.isNotEmpty && e.value != 'deleted') {
        _cookies[e.key] = e.value;
      }
    }
    await saveCookies();
  }

  /// 导入完整 Cookie 字符串（如 "k2U_2132_auth=xxx; k2U_2132_saltkey=yyy"）
  static Future<void> importCookieString(String rawCookieHeader) async {
    final pairs = rawCookieHeader.split(';');
    for (final pair in pairs) {
      final idx = pair.indexOf('=');
      if (idx <= 0) continue;
      final name = pair.substring(0, idx).trim();
      final value = pair.substring(idx + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty && value != 'deleted') {
        _cookies[name] = value;
      }
    }
    await saveCookies();
  }

  /// 清空会话（登出/测试隔离），并移除本地持久化
  static Future<void> clearCookies() async {
    _cookies.clear();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_cookiePrefsKey);
    } catch (_) {}
  }

  /// 是否已登录（存在 auth cookie，Discuz 的 auth cookie 名带 cookiepre 前缀）
  static bool get isLoggedIn =>
      _cookies.entries
          .where((e) => (e.key.endsWith('auth') && e.key != 'activationauth') || e.key == 'auth')
          .any((e) => e.value.isNotEmpty && !e.value.startsWith('deleted'));

  /// 手动重定向最大深度
  static const int _maxRedirects = 5;

  /// 从 set-cookie 列表中解析并更新内存与本地持久化 Cookie
  static void updateCookiesFromHeaders(List<String>? setCookies) {
    if (setCookies == null || setCookies.isEmpty) return;
    var changed = false;
    for (final sc in setCookies) {
      final parts = sc.split(';');
      if (parts.isEmpty) continue;
      final first = parts.first.trim();
      final eqIdx = first.indexOf('=');
      if (eqIdx > 0) {
        final name = first.substring(0, eqIdx).trim();
        final value = first.substring(eqIdx + 1).trim();
        if (name.isNotEmpty) {
          if (value == 'deleted' || value.isEmpty) {
            _cookies.remove(name);
          } else {
            _cookies[name] = value;
          }
          changed = true;
        }
      }
    }
    if (changed) {
      saveCookies();
    }
  }

  static Dio _build() {
    final d = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.timeout,
        receiveTimeout: AppConfig.timeout,
        sendTimeout: AppConfig.timeout,
        followRedirects: false,
        headers: {
          'User-Agent': AppConfig.userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Referer': AppConfig.baseUrl,
          'Sec-Fetch-Site': 'same-origin',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Dest': 'document',
          'Sec-Ch-Ua': '"Not A(Brand";v="99", "Chromium";v="120", "Google Chrome";v="120"',
          'Sec-Ch-Ua-Mobile': AppConfig.usePcUa ? '?0' : '?1',
          'Sec-Ch-Ua-Platform': AppConfig.usePcUa ? '"Windows"' : '"Android"',
        },
      ),
    );

    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // 动态同步最新 UA 与 Referer（保留显式传入的自定义 UA，如 pcUserAgent）
          options.headers['User-Agent'] ??= AppConfig.userAgent;
          options.headers['Referer'] ??= AppConfig.baseUrl;
          if (options.path.contains('inajax=1') ||
              options.uri.queryParameters['inajax'] == '1') {
            options.headers['X-Requested-With'] = 'XMLHttpRequest';
            options.headers['Sec-Fetch-Dest'] = 'empty';
            options.headers['Sec-Fetch-Mode'] = 'cors';
          }

          // 环境感知策略：本地测试允许写，真实论坛写操作校验域名
          if (!ReadWritePolicy.isAllowed(
            options.method,
            options.uri.toString(),
          )) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                message: '[策略拦截] ${options.method} ${options.uri}',
              ),
            );
            return;
          }
          // 附加会话 cookie
          if (_cookies.isNotEmpty) {
            final cookieHeader = _cookies.entries
                .where((e) => e.value.isNotEmpty && e.value != 'deleted')
                .map((e) => '${e.key}=${e.value}')
                .join('; ');
            if (cookieHeader.isNotEmpty) {
              options.headers['Cookie'] = cookieHeader;
            }
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          // 保存 Set-Cookie
          updateCookiesFromHeaders(response.headers['set-cookie']);
          final code = response.statusCode ?? 0;
          if (code >= 300 && code < 400) {
            final loc = response.headers.value('location');
            if (loc == null) {
              handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  type: DioExceptionType.badResponse,
                  message: '重定向缺少 Location',
                ),
              );
              return;
            }
            final resolved = response.requestOptions.uri
                .resolve(loc)
                .toString();
            if (!ReadWritePolicy.isAllowed('GET', resolved)) {
              handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  type: DioExceptionType.badResponse,
                  message: '重定向被策略拦截: $resolved',
                ),
              );
              return;
            }
            try {
              // 重定向跟随使用 GET（POST 提交后 302 → GET 目标页）
              final next = await _followRedirects(
                d,
                response.requestOptions.copyWith(path: resolved, method: 'GET'),
                1,
              );
              handler.resolve(next);
            } on DioException catch (e) {
              handler.reject(e);
            }
            return;
          }
          handler.next(response);
        },
      ),
    );
    return d;
  }

  static Future<Response<dynamic>> _followRedirects(
    Dio d,
    RequestOptions options,
    int depth,
  ) async {
    if (depth > _maxRedirects) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        message: '重定向次数过多',
      );
    }
    if (_cookies.isNotEmpty) {
      final cookieHeader = _cookies.entries
          .where((e) => e.value.isNotEmpty && e.value != 'deleted')
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      if (cookieHeader.isNotEmpty) {
        options.headers['Cookie'] = cookieHeader;
      }
    }
    final resp = await d.fetch<dynamic>(options);
    updateCookiesFromHeaders(resp.headers['set-cookie']);
    final code = resp.statusCode ?? 0;
    if (code >= 300 && code < 400) {
      final loc = resp.headers.value('location');
      if (loc == null) {
        throw DioException(
          requestOptions: resp.requestOptions,
          type: DioExceptionType.badResponse,
          message: '重定向缺少 Location',
        );
      }
      final resolved = resp.requestOptions.uri.resolve(loc).toString();
      if (!ReadWritePolicy.isAllowed('GET', resolved)) {
        throw DioException(
          requestOptions: resp.requestOptions,
          type: DioExceptionType.badResponse,
          message: '重定向被策略拦截: $resolved',
        );
      }
      return _followRedirects(d, options.copyWith(path: resolved), depth + 1);
    }
    return resp;
  }
}

/// 访问策略
///
/// 允许 GET 浏览 + POST 写操作（登录/发帖/回复/私信/签到），
/// 适用于本地测试与真实 klpbbs（风险由用户在 UI 确认承担）。
class ReadWritePolicy {

  static bool _isHostAllowed(String host) {
    final h = host.toLowerCase();
    final base = Uri.parse(AppConfig.baseUrl);
    final baseHost = base.host.toLowerCase();
    if (h == baseHost || h.endsWith('.$baseHost')) return true;
    if (h.endsWith('.klpbbs.com') || h == 'klpbbs.com') return true;
    if (h == 'localhost' || h == '127.0.0.1') return true;
    return false;
  }

  static bool isAllowed(String method, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    final m = method.toUpperCase();

    // GET / HEAD：放行所有合法 HTTP/HTTPS 浏览、图片 CDN、资源及附件/网盘下载
    if (m == 'GET' || m == 'HEAD') return true;

    // POST / 其他写操作：校验目标主机是否为官方论坛或本地测试域名
    if (!_isHostAllowed(uri.host)) return false;

    // 登录操作在任意模式下放行
    final u = url.toLowerCase();
    if (u.contains('mod=logging&action=login')) return true;

    // 其余写操作遵循 AppConfig.allowWrite
    return AppConfig.allowWrite;
  }
}
