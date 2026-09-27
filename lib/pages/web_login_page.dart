import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/preload_service.dart';
import '../main.dart' show appWebViewEnvironment;
import '../widgets/app_back_button.dart';

/// 苦力怕论坛 - 内嵌网页登录与授权中心
///
/// 通过应用内嵌入式浏览器打开论坛官方登录页（支持手机版与电脑版登录界面、扫码、第三方及滑动验证），
/// 并实时监听与捕获登录 Cookies（如 auth, saltkey, sid 等），实现无缝自动同步登录。
class WebLoginPage extends StatefulWidget {
  final bool initialPcMode;
  final String? initialUrl;
  final String? customTitle;
  final bool switchAccount;

  const WebLoginPage({
    super.key,
    this.initialPcMode = false,
    this.initialUrl,
    this.customTitle,
    this.switchAccount = false,
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

  String get _targetUrl => widget.initialUrl ?? (_isPcMode ? _pcLoginUrl : _mobileLoginUrl);

  @override
  void initState() {
    super.initState();
    _isPcMode = widget.initialPcMode;
    _currentUrl = widget.initialUrl ?? _targetUrl;
    if (widget.switchAccount) {
      _clearWebSession();
    }
    _startCookiePolling();
  }

  Future<void> _clearWebSession() async {
    try {
      final cookieManager = (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows && appWebViewEnvironment != null)
          ? CookieManager.instance(webViewEnvironment: appWebViewEnvironment)
          : CookieManager.instance();
      await cookieManager.deleteAllCookies();
      await _webViewController?.clearCache();
    } catch (_) {}
    await DioClient.clearCookies();
  }

  @override
  void dispose() {
    _cookiePollTimer?.cancel();
    super.dispose();
  }

  void _startCookiePolling() {
    // 定时（每 1.2 秒）轮询 WebView Cookie 与登录态，以便在用户点击登录或第三方授权成功的第一时间捕获 Auth
    _cookiePollTimer?.cancel();
    _cookiePollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (mounted && !_hasLoggedIn && !_isSyncing) {
        _checkAndSyncCookies(silent: true);
      }
    });
  }

  /// 检查并同步 WebView 中的登录 Cookies 与会话状态
  Future<bool> _checkAndSyncCookies({bool silent = false}) async {
    if (_hasLoggedIn) return true;
    try {
      // 1. 获取对应运行环境的 CookieManager（Windows 必须绑定当前 appWebViewEnvironment，否则查不到 WebView2 Cookie）
      final cookieManager = (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows && appWebViewEnvironment != null)
          ? CookieManager.instance(webViewEnvironment: appWebViewEnvironment)
          : CookieManager.instance();

      // 待探测的目标 URL 列表（覆盖基准域、根路径及当前加载中的实际页面路径）
      final urlsToQuery = <WebUri>[
        WebUri(AppConfig.baseUrl),
        WebUri('https://klpbbs.com/'),
        WebUri('https://klpbbs.com'),
      ];
      if (_currentUrl.isNotEmpty && _currentUrl.startsWith('http')) {
        try {
          final cur = WebUri(_currentUrl);
          if (!urlsToQuery.any((u) => u.rawValue == cur.rawValue)) {
            urlsToQuery.add(cur);
          }
        } catch (_) {}
      }

      final cookieMap = <String, String>{};
      bool foundAuth = false;

      // 2. 从 CookieManager 检索所有目标 URL 的 Cookie
      for (final u in urlsToQuery) {
        try {
          final cookies = await cookieManager.getCookies(url: u);
          for (final c in cookies) {
            if (c.name.isNotEmpty && c.value.isNotEmpty && c.value != 'deleted') {
              cookieMap[c.name] = c.value;
              if ((c.name.endsWith('auth') && c.name != 'activationauth') || c.name == 'auth') {
                if (c.value.length > 10) {
                  foundAuth = true;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[WebLogin] getCookies for $u error: $e');
        }
      }

      // 3. 辅助通道：通过 Controller 执行 JavaScript 提取非 HttpOnly Cookie 及 DOM 登录态
      bool domLoggedIn = false;
      if (_webViewController != null) {
        try {
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
                  cookieMap.putIfAbsent(k, () => v);
                  if ((k.endsWith('auth') && k != 'activationauth') || k == 'auth') {
                    if (v.length > 10) {
                      foundAuth = true;
                    }
                  }
                }
              }
            }
          }

          // DOM 嗅探：Discuz 模板在用户登录后必定声明非 0 的 discuz_uid，或渲染退出按钮 a[href*="action=logout"]
          final domCheck = await _webViewController?.evaluateJavascript(
            source: '''
              (() => {
                try {
                  var uid = (typeof discuz_uid !== "undefined" && discuz_uid) ? String(discuz_uid) : "0";
                  var logoutLink = document.querySelector('a[href*="action=logout"]');
                  var userItem = document.querySelector('.vwmy') || document.querySelector('#myitem');
                  return JSON.stringify({
                    uid: uid,
                    hasLogout: !!logoutLink,
                    hasUserItem: !!userItem,
                    isLogged: (uid !== "0" && uid !== "") || !!logoutLink || !!userItem
                  });
                } catch(e) {
                  return JSON.stringify({uid: "0", hasLogout: false, isLogged: false});
                }
              })()
            ''',
          );
          if (domCheck != null) {
            final parsed = jsonDecode(domCheck is String ? domCheck : jsonEncode(domCheck));
            if (parsed is Map && parsed['isLogged'] == true) {
              domLoggedIn = true;
            }
          }
        } catch (_) {}
      }

      // 4. 若 DOM 明确指示已登录但尚未抓取到 Auth（可能存在微秒级异步落盘延迟），稍作延时二次拉取 Cookie
      if (domLoggedIn && !foundAuth) {
        await Future.delayed(const Duration(milliseconds: 350));
        for (final u in urlsToQuery) {
          try {
            final cookies = await cookieManager.getCookies(url: u);
            for (final c in cookies) {
              if (c.name.isNotEmpty && c.value.isNotEmpty && c.value != 'deleted') {
                cookieMap[c.name] = c.value;
                if ((c.name.endsWith('auth') && c.name != 'activationauth') || c.name == 'auth') {
                  if (c.value.length > 10) {
                    foundAuth = true;
                  }
                }
              }
            }
          } catch (_) {}
        }
      }

      // 5. 若已发现有效 Auth，或 DOM 已识别已登录且提取到了基础会话凭证
      if (foundAuth || (domLoggedIn && cookieMap.isNotEmpty)) {
        _hasLoggedIn = true;
        _cookiePollTimer?.cancel();
        if (mounted) setState(() => _isSyncing = true);

        // 导入并持久化到 DioClient
        await DioClient.importCookies(cookieMap);
        // 清除旧缓存保证数据实时性
        PreloadService.instance.clear();
        KlpbbsApi.clearQuickCache();

        // 强制刷新实时验证登录态
        final status = await KlpbbsApi.checkLoginStatus(forceRefresh: true);

        if (status.isLoggedIn || DioClient.isLoggedIn) {
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
        } else {
          // 若服务器端校验未通过，重置标记允许后续轮询或手动再次触发
          _hasLoggedIn = false;
          if (mounted) setState(() => _isSyncing = false);
          if (!silent && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已提取部分凭证，但未能通过论坛在线验证，请确认网页已成功登录'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return false;
        }
      } else if (!silent) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('尚未检测到有效登录凭证，请在页面完成登录后再同步'),
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
              PreloadService.instance.clear();
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
        leading: const AppBackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.customTitle ?? '苦力怕论坛 - 网页内嵌登录',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            icon: const Icon(Icons.open_in_browser_rounded),
            tooltip: '在系统默认浏览器中打开',
            onPressed: () {
              url_launcher.launchUrl(
                Uri.parse(_currentUrl.isNotEmpty ? _currentUrl : _targetUrl),
                mode: url_launcher.LaunchMode.externalApplication,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新页面',
            onPressed: () => _webViewController?.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.switch_account_outlined),
            tooltip: '切换账号 / 清除网页登录态',
            onPressed: () async {
              await _clearWebSession();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清除网页端会话，可输入新账号登录')),
              );
              _webViewController?.loadUrl(
                urlRequest: URLRequest(url: WebUri(_targetUrl)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined),
            tooltip: '手动粘贴 Cookie',
            onPressed: _showManualCookieDialog,
          ),
        ],
      ),
      body: defaultTargetPlatform == TargetPlatform.linux
          ? _buildLinuxFallback(theme)
          : (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows && appWebViewEnvironment == null)
              ? _buildWindowsMissingWebView2Fallback(theme)
              : Stack(
                  children: [
                    InAppWebView(
                      webViewEnvironment: appWebViewEnvironment,
                      initialUrlRequest: URLRequest(
                        url: WebUri(_currentUrl),
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
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        transparentBackground: false,
                        allowsInlineMediaPlayback: true,
                        sharedCookiesEnabled: true,
                      ),
                      onWebViewCreated: (controller) async {
                        _webViewController = controller;
                        // Windows / 桌面端兜底主动导航，防止初始化异步导致未触发首帧渲染
                        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
                          Future.delayed(const Duration(milliseconds: 100), () async {
                            final cur = await controller.getUrl();
                            if (cur == null && mounted) {
                              controller.loadUrl(
                                urlRequest: URLRequest(url: WebUri(_currentUrl)),
                              );
                            }
                          });
                        }
                      },
                      shouldOverrideUrlLoading: (controller, navigationAction) async {
                        final uri = navigationAction.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;

                        final scheme = uri.scheme.toLowerCase();
                        // 拦截第三方客户端协议（如 QQ/微信/支付宝等）并唤醒外部系统应用
                        if (scheme != 'http' && scheme != 'https' && scheme != 'about') {
                          try {
                            if (await url_launcher.canLaunchUrl(uri)) {
                              await url_launcher.launchUrl(
                                uri,
                                mode: url_launcher.LaunchMode.externalApplication,
                              );
                            }
                          } catch (_) {}
                          return NavigationActionPolicy.CANCEL;
                        }

                        // 放行所有正常的论坛网页与第三方登录回调重定向（QQ互联、微博等）
                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (controller, createWindowAction) async {
                        final req = createWindowAction.request;
                        if (req.url != null) {
                          await controller.loadUrl(urlRequest: req);
                          return true;
                        }
                        return false;
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
                        if (progress >= 100) {
                          _checkAndSyncCookies(silent: true);
                        }
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
                          setState(() {
                            _isLoading = false;
                          });
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
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
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

  Widget _buildLinuxFallback(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.language_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Linux 平台网页认证提示',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '由于 Linux 桌面底层未内置 WebKit/Chromium 渲染通道，推荐您在浏览器中登录苦力怕论坛，并通过下方「手动粘贴 Cookie」一键同步登录态。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _showManualCookieDialog,
                icon: const Icon(Icons.vpn_key_outlined),
                label: const Text('手动粘贴 Cookie 凭证'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(_currentUrl);
                  if (await url_launcher.canLaunchUrl(uri)) {
                    await url_launcher.launchUrl(
                      uri,
                      mode: url_launcher.LaunchMode.externalApplication,
                    );
                  }
                },
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('在系统浏览器中打开登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWindowsMissingWebView2Fallback(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant.withAlpha(80)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(25),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(120),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.web_asset_off_rounded,
                  size: 36,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Windows 缺少 Edge WebView2 运行时',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '当前电脑系统未检测到或未成功启动 Microsoft Edge WebView2 组件，内嵌浏览器暂时无法直接呈现网页。\n\n建议直接在电脑默认浏览器（Edge / Chrome）中打开论坛完成登录，随后点击下方同步；或者前往微软官网安装 WebView2 运行时。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  url_launcher.launchUrl(
                    Uri.parse(_targetUrl),
                    mode: url_launcher.LaunchMode.externalApplication,
                  );
                },
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('在系统浏览器中打开论坛登录'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  url_launcher.launchUrl(
                    Uri.parse('https://developer.microsoft.com/microsoft-edge/webview2/'),
                    mode: url_launcher.LaunchMode.externalApplication,
                  );
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('前往微软官网下载 WebView2 运行时'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _showManualCookieDialog,
                icon: const Icon(Icons.vpn_key_outlined),
                label: const Text('手动粘贴 Cookie 凭证直接登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
