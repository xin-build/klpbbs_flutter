import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'discuz_request_policy.dart';
import 'discuz_response.dart';

/// Contract declared by KLPBBS's current desktop phone-binding plugin.
/// The desktop template renders binding status directly; its inputs are not
/// inside a HTML form, so the generic Discuz form parser cannot submit them.
class KlpbbsPhoneBinding {
  final Uri pageUri, sendUri, verifyUri;
  final String formhash, maskedPhone, boundAt;
  final List<String> help;
  final int codeLength, resendSeconds;
  const KlpbbsPhoneBinding({
    required this.pageUri,
    required this.sendUri,
    required this.verifyUri,
    required this.formhash,
    required this.maskedPhone,
    required this.boundAt,
    required this.help,
    required this.codeLength,
    required this.resendSeconds,
  });

  bool get isBound => maskedPhone.isNotEmpty;

  static String maskPhone(String value) {
    final phone = value.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      return '${phone.substring(0, 3)}****${phone.substring(7)}';
    }
    return RegExp(r'^1[3-9][\d*•●xX]{9}$').hasMatch(phone) ? phone : '';
  }

  static KlpbbsPhoneBinding parse(String source, Uri uri) {
    final document = html.parse(source);
    final root = document.querySelector('.klp-pnbind');
    if (root == null || document.querySelector('#loginform') != null) {
      throw StateError(
          DiscuzResponse.message(source) ?? '手机绑定页面暂时无法读取，请刷新或重新登录');
    }
    Uri declared(String id) {
      // Never infer an action from a button caption. Require its current
      // plugin script to declare the exact action and the expected origin.
      final pattern = RegExp(
          "['\"]([^'\"]*plugin\\.php\\?id=klpbbs_pnbind:$id(?:&[^'\"]*)?)['\"]");
      final match = pattern.firstMatch(source);
      final action = match == null
          ? null
          : uri.resolve(match.group(1)!.replaceAll('&amp;', '&'));
      if (action == null ||
          !DiscuzRequestPolicy.sameOrigin(uri, action) ||
          action.queryParameters['id'] != 'klpbbs_pnbind:$id') {
        throw StateError('论坛手机绑定接口已变化，请刷新后重试');
      }
      return action;
    }

    final hash = document
            .querySelector('input[name="formhash"]')
            ?.attributes['value'] ??
        RegExp(r'''\b(?:hash|formhash)\s*[:=]\s*['"]([a-zA-Z0-9]{8,32})['"]''')
            .firstMatch(source)
            ?.group(1) ??
        '';
    if (hash.isEmpty ||
        root.querySelector('#bind_phone') == null ||
        root.querySelector('#bind_verify') == null ||
        root.querySelector('#get_code') == null ||
        root.querySelector('#code_btn') == null) {
      throw StateError('当前手机号验证表单尚未完整加载');
    }
    var boundAt = '';
    for (final row in root.querySelectorAll('tr')) {
      if (row.querySelector('th')?.text.trim() == '绑定时间') {
        boundAt = row.querySelector('td')?.text.trim() ?? '';
      }
    }
    final codeLength = int.tryParse(
            root.querySelector('#bind_verify')?.attributes['maxlength'] ??
                '') ??
        6;
    final wait = int.tryParse(
            RegExp(r'\bWAIT\s*=\s*(\d+)').firstMatch(source)?.group(1) ?? '') ??
        60;
    return KlpbbsPhoneBinding(
      pageUri: uri,
      sendUri: declared('send'),
      verifyUri: declared('code_check'),
      formhash: hash,
      maskedPhone: maskPhone(root.querySelector('.klp-pnb-num')?.text ?? ''),
      boundAt: boundAt,
      help: root
          .querySelectorAll('.klp-pnb-help p')
          .map((node) => node.text.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      codeLength: codeLength.clamp(4, 8),
      resendSeconds: wait.clamp(30, 300),
    );
  }

  bool sameActionsAs(KlpbbsPhoneBinding other) =>
      pageUri == other.pageUri &&
      sendUri == other.sendUri &&
      verifyUri == other.verifyUri &&
      codeLength == other.codeLength &&
      resendSeconds == other.resendSeconds &&
      maskedPhone == other.maskedPhone &&
      boundAt == other.boundAt;

  String? validatePhone(String value) =>
      RegExp(r'^1[3-9]\d{9}$').hasMatch(value) ? null : '请输入 11 位中国大陆手机号';
  String? validateCode(String value) =>
      RegExp('^\\d{$codeLength}\$').hasMatch(value)
          ? null
          : '请输入 $codeLength 位短信验证码';
}

class PhoneBindingReceipt {
  final KlpbbsPhoneBinding binding;
  final String session;
  final DateTime loadedAt;
  const PhoneBindingReceipt(this.binding, this.session, this.loadedAt);
}

class PhoneBindingResult {
  final bool success;
  final String message;
  const PhoneBindingResult(this.success, this.message);

  static PhoneBindingResult parse(String source) {
    try {
      final result = jsonDecode(source.trim());
      if (result is Map && result['success'] is bool) {
        final message = html
                .parseFragment(result['message']?.toString() ?? '')
                .text
                ?.trim() ??
            '';
        return PhoneBindingResult(
            result['success'] == true,
            message.isEmpty
                ? (result['success'] == true ? '操作成功' : '论坛未接受此操作')
                : message);
      }
    } on FormatException {
      // Discuz may return an HTML login or maintenance response instead.
    }
    return PhoneBindingResult(
        false, DiscuzResponse.message(source) ?? '论坛返回的验证结果无法识别，请刷新绑定状态');
  }
}
