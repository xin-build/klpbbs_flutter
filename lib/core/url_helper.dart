import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../main.dart';
import '../pages/thread_detail_page.dart';
import '../pages/thread_list_page.dart';
import '../pages/user_space_page.dart';
import 'app_config.dart';

/// 全局链接安全跳转与分流辅助工具
class UrlHelper {
  /// 规整与补全 URL 路径（剥除外层引号、中文标点、补齐协议）
  static String normalizeUrl(String rawLink) {
    var trimmed = rawLink
        .trim()
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#38;', '&')
        .replaceAll('&#34;', '"')
        .replaceAll('&#39;', "'");

    // 剥离两端包裹的单双引号、括号与书名号
    while (trimmed.isNotEmpty &&
        (trimmed.startsWith('"') ||
            trimmed.startsWith("'") ||
            trimmed.startsWith('“') ||
            trimmed.startsWith('‘') ||
            trimmed.startsWith('(') ||
            trimmed.startsWith('（') ||
            trimmed.startsWith('[') ||
            trimmed.startsWith('【') ||
            trimmed.startsWith('<') ||
            trimmed.startsWith('《'))) {
      trimmed = trimmed.substring(1).trim();
    }
    while (trimmed.isNotEmpty &&
        (trimmed.endsWith('"') ||
            trimmed.endsWith("'") ||
            trimmed.endsWith('”') ||
            trimmed.endsWith('’') ||
            trimmed.endsWith(')') ||
            trimmed.endsWith('）') ||
            trimmed.endsWith(']') ||
            trimmed.endsWith('】') ||
            trimmed.endsWith('>') ||
            trimmed.endsWith('》') ||
            trimmed.endsWith(';') ||
            trimmed.endsWith('；'))) {
      trimmed = trimmed.substring(0, trimmed.length - 1).trim();
    }

    if (trimmed.isEmpty) return '';

    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    } else if (trimmed.startsWith('/')) {
      var path = trimmed;
      while (path.startsWith('/')) {
        path = path.substring(1);
      }
      return '${AppConfig.baseUrl}$path';
    } else if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      if (trimmed.contains('forum.php') ||
          trimmed.contains('thread-') ||
          trimmed.contains('space-') ||
          trimmed.contains('mod=')) {
        var path = trimmed;
        while (path.startsWith('/')) {
          path = path.substring(1);
        }
        return '${AppConfig.baseUrl}$path';
      } else {
        return 'https://$trimmed';
      }
    }
    return trimmed;
  }

  /// 将字符串解析为有效 Uri
  static Uri? resolveUri(String rawLink) {
    final normalized = normalizeUrl(rawLink);
    if (normalized.isEmpty) return null;
    return Uri.tryParse(Uri.encodeFull(normalized)) ?? Uri.tryParse(normalized);
  }

  /// 判断是否是苦力怕论坛站内链接
  static bool isInternalUrl(String url) {
    if (url.startsWith('/')) return true;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host.isEmpty ||
        host == 'klpbbs.com' ||
        host == 'www.klpbbs.com' ||
        host == 'klpbbs.cn' ||
        host == 'www.klpbbs.cn' ||
        host == 'klpz.net' ||
        host == 'localhost' ||
        host == '127.0.0.1';
  }

  /// 打开链接：站内帖子/版块/用户空间走应用内导航，外部链接唤起系统外部浏览器
  static Future<bool> openLink(BuildContext? context, String rawLink) async {
    if (rawLink.trim().isEmpty) return false;
    final trimmed = normalizeUrl(rawLink);
    if (trimmed.isEmpty) return false;

    final targetContext = (context != null && context.mounted)
        ? context
        : appNavigatorKey.currentContext;

    // 只有站内链接才尝试应用内路由分发
    if (isInternalUrl(trimmed)) {
      // 1. 站内帖子跳转
      final tReg = RegExp(r'thread-(\d+)|(?:mod=viewthread[^\s]*tid=|tid=)(\d+)');
      final tM = tReg.firstMatch(trimmed);
      if (tM != null && targetContext != null && targetContext.mounted) {
        final tid = int.tryParse(tM.group(1) ?? tM.group(2) ?? '');
        if (tid != null && tid > 0) {
          Navigator.of(targetContext).push(
            MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: tid)),
          );
          return true;
        }
      }

      // 2. 站内部版块跳转
      final fReg = RegExp(r'forum-(\d+)|(?:mod=forumdisplay[^\s]*fid=|fid=)(\d+)');
      final fM = fReg.firstMatch(trimmed);
      if (fM != null && targetContext != null && targetContext.mounted) {
        final fid = int.tryParse(fM.group(1) ?? fM.group(2) ?? '');
        if (fid != null && fid > 0) {
          Navigator.of(targetContext).push(
            MaterialPageRoute(builder: (_) => ThreadListPage(fid: fid, title: '版块')),
          );
          return true;
        }
      }

      // 3. 站内用户空间跳转
      final uReg = RegExp(r'space[^\s]*uid=(\d+)|space-uid-(\d+)');
      final uM = uReg.firstMatch(trimmed);
      if (uM != null && targetContext != null && targetContext.mounted) {
        final uid = int.tryParse(uM.group(1) ?? uM.group(2) ?? '');
        if (uid != null && uid > 0) {
          Navigator.of(targetContext).push(
            MaterialPageRoute(builder: (_) => UserSpacePage(uid: uid)),
          );
          return true;
        }
      }
    }

    // 4. 系统外部应用/浏览器打开（站外链接或未匹配到的站内页面）
    Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      uri = Uri.tryParse(Uri.encodeFull(trimmed));
    }
    if (uri != null) {
      // 模式 1: externalApplication
      try {
        final launched = await url_launcher.launchUrl(
          uri,
          mode: url_launcher.LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {}

      // 模式 2: platformDefault
      try {
        final fallbackLaunched = await url_launcher.launchUrl(
          uri,
          mode: url_launcher.LaunchMode.platformDefault,
        );
        if (fallbackLaunched) return true;
      } catch (_) {}

      // 模式 3: inAppBrowserView
      try {
        final inAppLaunched = await url_launcher.launchUrl(
          uri,
          mode: url_launcher.LaunchMode.inAppBrowserView,
        );
        if (inAppLaunched) return true;
      } catch (_) {}

      // 模式 4: 系统底层原生进程兜底唤起默认浏览器
      try {
        if (!kIsWeb) {
          if (Platform.isWindows) {
            await Process.run('cmd', ['/c', 'start', '', trimmed], runInShell: true);
            return true;
          } else if (Platform.isMacOS) {
            await Process.run('open', [trimmed]);
            return true;
          } else if (Platform.isLinux) {
            await Process.run('xdg-open', [trimmed]);
            return true;
          }
        }
      } catch (_) {}
    }

    // 无法唤起时复制到剪贴板并提示
    Clipboard.setData(ClipboardData(text: trimmed));
    if (targetContext != null && targetContext.mounted) {
      ScaffoldMessenger.of(targetContext).showSnackBar(
        SnackBar(content: Text('已复制链接到剪贴板：$trimmed')),
      );
    }
    return false;
  }
}
