import 'dart:io';
import 'package:html/parser.dart' as html;

/// 只解析 topicadmin_getip 模板的 IP 字段，拒绝导航、JS 版本号和错误页。
class DiscuzIpResponse {
  static ({String ip, String location})? parse(String response) {
    final payload =
        RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(response)?.group(1) ??
            response;
    final doc = html.parse(payload);
    if (doc.querySelector('.alert_error, #messagetext, #loginform') != null) {
      return null;
    }
    for (final bold in doc.querySelectorAll('b')) {
      final text = bold.text.trim();
      final ipv4 =
          RegExp(r'^((?:\d{1,3}\.){3}\d{1,3})(?::\d+)?$').firstMatch(text);
      final address = ipv4?.group(1) ?? text.replaceAll(RegExp(r'^\[|\]$'), '');
      if (InternetAddress.tryParse(address) == null) continue;
      final container = bold.parent?.clone(true);
      for (final node
          in container?.querySelectorAll('b, a, script, style') ?? []) {
        node.remove();
      }
      final location =
          container?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      return (ip: address, location: location.length <= 160 ? location : '');
    }
    return null;
  }
}
