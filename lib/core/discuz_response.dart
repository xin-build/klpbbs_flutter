import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';

/// Discuz 的 HTTP 200 也可能包含登录表单、验证码失败或权限提示。
class DiscuzResponse {
  static bool _visible(Element node) {
    Element? current = node;
    while (current != null) {
      if (current.attributes.containsKey('hidden') ||
          current.attributes['aria-hidden'] == 'true' ||
          RegExp(r'display\s*:\s*none|visibility\s*:\s*hidden',
                  caseSensitive: false)
              .hasMatch(current.attributes['style'] ?? '') ||
          current.id == 'main_succeed') {
        return false;
      }
      current = current.parent;
    }
    return true;
  }

  static String? message(String response) {
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(response);
    final payload = cdata?.group(1) ?? response;
    final doc = html.parse(payload);
    for (final selector in const [
      '#messagetext',
      '.comiis_password_top',
      '.alert_error, .form_error',
      '.alert_right, .alert_info, .comiis_tip, .jump_c'
    ]) {
      for (final node in doc.querySelectorAll(selector)) {
        if (!_visible(node)) continue;
        final copy = (node.querySelector('p') ?? node).clone(true);
        copy
            .querySelectorAll('script, style')
            .forEach((element) => element.remove());
        final text = copy.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isNotEmpty) return text;
      }
    }
    if (doc.querySelector('form') != null) return null;
    final match = RegExp(
            r'''(?:showmessage|showDialog|showError|errorhandle_[a-zA-Z0-9_]+)\s*\(\s*['"]([^'"]+)['"]''')
        .firstMatch(payload);
    return match?.group(1)?.trim();
  }

  /// 只采用提示页面实际给出的同站绑定入口。
  static Uri? phoneBindingUri(String response, Uri page) {
    final doc = html.parse(response);
    for (final anchor in doc.querySelectorAll(
        '#messagetext a[href], .comiis_password_form a[href]')) {
      final uri = page.resolve(anchor.attributes['href']!);
      if (const {'http', 'https'}.contains(uri.scheme) &&
          uri.origin == page.origin &&
          uri.queryParameters['id'] == 'klpbbs_pnbind:my_bind') {
        return uri;
      }
    }
    return null;
  }

  static bool isSuccess(String response,
      {Iterable<String> acceptedMessages = const []}) {
    if (response.trim().isEmpty) return false;
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(response);
    final payload = cdata?.group(1) ?? response;
    final doc = html.parse(payload);
    final message = DiscuzResponse.message(response) ??
        doc.querySelector('.tip, .comiis_tip_box')?.text.trim() ??
        '';
    if (RegExp(r'失败|不成功|未成功|无权限|权限不足|抱歉|错误|请先登录|尚未登录|请先绑定|未绑定手机号|请先验证')
        .hasMatch(message)) {
      return false;
    }
    if (doc.querySelector(
            '.alert_error, .form_error, #loginform, form[name="login"]') !=
        null) {
      return false;
    }
    if (RegExp(r'''(?:showError|parent\.show_error|errorhandle_\w+)\s*\(''')
        .hasMatch(payload)) {
      return false;
    }
    for (final success
        in doc.querySelectorAll('.alert_right, .alert_correct')) {
      if (_visible(success) && success.text.trim().isNotEmpty) return true;
    }
    if (doc.querySelector('form') != null) return false;
    if (RegExp(r'''parent\.show_success\s*\(''').hasMatch(payload)) return true;
    // 只接受调用，网页内的 succeedhandle 函数定义不代表操作完成。
    for (final match
        in RegExp(r'\bsucceedhandle_\w+\s*\(').allMatches(payload)) {
      final before = payload.substring(0, match.start).trimRight();
      if (!before.endsWith('function')) return true;
    }
    if (message.isNotEmpty &&
        !RegExp(r'失败|不成功|未成功|无权限|权限不足|抱歉|错误').hasMatch(message)) {
      return message.contains('成功') || acceptedMessages.any(message.contains);
    }
    // 部分插件只返回短文本消息。
    for (final node
        in doc.querySelectorAll('script, style, [hidden], #main_succeed')) {
      node.remove();
    }
    final text = doc.body?.text.trim() ?? '';
    return text.length < 160 &&
        text.isNotEmpty &&
        !RegExp(r'失败|不成功|未成功|无权限|权限不足|抱歉|错误').hasMatch(text) &&
        (text.contains('成功') || acceptedMessages.any(text.contains));
  }
}
