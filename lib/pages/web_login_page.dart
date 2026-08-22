import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';

/// 苦力怕论坛 - 内嵌网页登录与授权中心
///
/// 通过应用内嵌入式浏览器打开论坛官方登录页（支持手机版与电脑版登录界面、扫码、第三方及滑动验证），
/// 并实时监听与捕获登录 Cookies（如 auth, saltkey, sid 等），实现无缝自动同步登录。
class WebLoginPage extends StatefulWidget {
  final bool initialPcMode;

  const WebLoginPage({
    super.key,
    this.initialPcMode = false,
  });

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  InAppWebViewController? _webViewController;
  double _progress = 0.0;
  bool _isLoading = true;
  bool _isPcMode = false;
  bool _isSyncing = false;
  bool _hasLoggedIn = false;
  String _currentUrl = '';
  Timer? _cookiePollTimer;

  String get _mobileLoginUrl =>
      '${AppConfig.baseUrl}member.php?mod=logging&action=login&mobile=2';
  String get _pcLoginUrl =>
      '${AppConfig.baseUrl}member.php?mod=logging&action=login';

  String get _targetUrl => _isPcMode ? _pcLoginUrl : _mobileLoginUrl;

  @override
  void initState() {
    super.initState();
    _isPcMode = widget.initialPcMode;
    _currentUrl = _targetUrl;
    _startCookiePolling();
  }

  @override
  void dispose() {
    _cookiePollTimer?.cancel();
    super.dispose();
  }

  void _startCookiePolling() {
    // 定时（每 1.5 秒）轮询 WebView Cookie，以便在用户点击登录或扫码成功的第一时间捕获 Auth
    _cookiePollTimer?.cancel();
    _cookiePollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted && !_hasLoggedIn && !_isSyncing) {
        _checkAndSyncCookies(silent: true);
      }
    });
  }

  /// 检查并同步 WebView 中的登录 Cookies
  Future<bool> _checkAndSyncCookies({bool silent = false}) async {
    if (_hasLoggedIn) return true;
    try {
      final cookieManager = CookieManager.instance();
      final uri = WebUri(AppConfig.baseUrl);
      final cookies = await cookieManager.getCookies(url: uri);

      final cookieMap = <String, String>{};
      bool foundAuth = false;

      for (final c in cookies) {
        if (c.name.isNotEmpty && c.value.isNotEmpty && c.value != 'deleted') {
          cookieMap[c.name] = c.value;
          if (c.name.endsWith('auth') && c.name != 'activationauth' && c.value.length > 10) {
            foundAuth = true;
          }
        }
      }

      // 如果通过 CookieManager 获取为空（例如部分平台受限），尝试通过 JS document.cookie 提取
      if (!foundAuth && _webViewController != null) {
        final jsCookies = await _webViewController?.evaluateJavascript(
          source: 'document.cookie',
        );
        if (jsCookies != null && jsCookies is String && jsCookies.isNotEmpty) {
          final pairs = jsCookies.split(';');
          for (final p in pairs) {
            final idx = p.indexOf('=');
            if (idx > 0) {
              final k = p.substring(0, idx).trim();
              final v = p.substring(idx + 1).trim();
              if (k.isNotEmpty && v.isNotEmpty && v != 'deleted') {
                cookieMap[k] = v;
                if (k.endsWith('auth') && k != 'activationauth' && v.length > 10) {
                  foundAuth = true;
                }
              }
            }
          }
        }
      }

      if (foundAuth && cookieMap.isNotEmpty) {
        _hasLoggedIn = true;
        _cookiePollTimer?.cancel();
        if (mounted) setState(() => _isSyncing = true);

        // 导入并持久化到 DioClient
        await DioClient.importCookies(cookieMap);

        // 校验登录状态
        final status = await KlpbbsApi.checkLoginStatus();

        if (mounted) {
          setState(() => _isSyncing = false);
          final uname = (status.username != null && status.username!.isNotEmpty)
              ? status.username!
              : '坛友';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('网页登录成功！欢迎回来，$uname'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF2E7D32),
            ),
          );
          Navigator.of(context).pop(true);
        }
        return true;
      } else if (!silent) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('尚未检测到登录成功凭证，请在页面完成登录后再同步'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步 Cookie 出现异常: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    return false;
  }

  void _togglePcMode() {
    setState(() {
      _isPcMode = !_isPcMode;
      _currentUrl = _targetUrl;
    });
    _webViewController?.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(_currentUrl),
        headers: {
          'User-Agent': _isPcMode ? AppConfig.pcUserAgent : AppConfig.mobileUserAgent,
        },
      ),
    );
  }

  void _showManualCookieDialog() {
    final textCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动导入 Cookie / 会话凭证'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '如因特殊验证码或双重认证导致无法自动获取，可直接将浏览器的 Cookie 字符串粘贴在下方：',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '如: k2U_2132_auth=xxxx; k2U_2132_saltkey=yyyy; ...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = textCtrl.text.trim();
              if (raw.isEmpty) return;
              Navigator.of(ctx).pop();
              await DioClient.importCookieString(raw);
              final status = await KlpbbsApi.checkLoginStatus();
              if (mounted) {
                if (status.isLoggedIn || DioClient.isLoggedIn) {
                  final uname = (status.username != null && status.username!.isNotEmpty)
                      ? status.username!
                      : '已登录';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Cookie 导入成功！已识别为「$uname」'),
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                  );
                  Navigator.of(context).pop(true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cookie 已保存，但未能识别有效登录态，请检查是否包含 auth 字段'),
                    ),
                  );
                }
              }
            },
            child: const Text('导入并登录'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '苦力怕论坛 - 网页内嵌登录',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              _isPcMode ? '电脑版模式' : '手机版模式',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant.withAlpha(200),
              ),
            ),
          ],
        ),
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2.5),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 2.5,
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              )
            : null,
        actions: [
          // 切换手机版 / 电脑版
          TextButton.icon(
            onPressed: _togglePcMode,
            icon: Icon(
              _isPcMode ? Icons.phone_android : Icons.desktop_windows,
              size: 18,
            ),
            label: Text(_isPcMode ? '切换手机版' : '切换电脑版'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新页面',
            onPressed: () => _webViewController?.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined),
            tooltip: '手动粘贴 Cookie',
            onPressed: _showManualCookieDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(_targetUrl),
              headers: {
                'User-Agent': _isPcMode ? AppConfig.pcUserAgent : AppConfig.mobileUserAgent,
              },
            ),
            initialSettings: InAppWebViewSettings(
              useShouldOverrideUrlLoading: true,
              mediaPlaybackRequiresUserGesture: false,
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: true,
              supportMultipleWindows: true,
              userAgent: _isPcMode ? AppConfig.pcUserAgent : AppConfig.mobileUserAgent,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              cacheEnabled: true,
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStart: (controller, url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _currentUrl = url?.toString() ?? '';
                });
              }
            },
            onProgressChanged: (controller, progress) {
              if (mounted) {
                setState(() {
                  _progress = progress / 100;
                  if (progress >= 100) _isLoading = false;
                });
              }
              _checkAndSyncCookies(silent: true);
            },
            onLoadStop: (controller, url) async {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _currentUrl = url?.toString() ?? '';
                });
              }
              await _checkAndSyncCookies(silent: true);
            },
            onReceivedError: (controller, request, error) {
              if (mounted) {
                setState(() => _isLoading = false);
              }
            },
          ),
          if (_isSyncing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        SizedBox(width: 16),
                        Text(
                          '正在同步登录凭证...',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withAlpha(50),
            ),
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                tooltip: '后退',
                onPressed: () async {
                  if (await _webViewController?.canGoBack() ?? false) {
                    await _webViewController?.goBack();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                tooltip: '前进',
                onPressed: () async {
                  if (await _webViewController?.canGoForward() ?? false) {
                    await _webViewController?.goForward();
                  }
                },
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '已开启凭证自动嗅探',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _checkAndSyncCookies(silent: false),
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('一键同步凭证'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
