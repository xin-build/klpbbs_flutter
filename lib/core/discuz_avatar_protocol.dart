import 'dart:convert';
import 'dart:typed_data';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import 'discuz_request_policy.dart';
import 'discuz_response.dart';
import 'discuz_session_parser.dart';

/// Read-only description of the currently declared upload flow.
/// A review hook always takes precedence over the legacy Flash declaration.
class DiscuzAvatarDescriptor {
  final Uri? declaredUpload;
  final List<String> fieldNames;
  final bool hasFlash, hasLegacyCropper, requiresReview;
  final int? uid;
  final String formhash, statusMessage;
  final Uri? phoneBindingUri;
  const DiscuzAvatarDescriptor({
    this.declaredUpload,
    this.fieldNames = const [],
    this.hasFlash = false,
    this.hasLegacyCropper = false,
    this.requiresReview = false,
    this.uid,
    this.formhash = '',
    this.statusMessage = '',
    this.phoneBindingUri,
  });

  bool get canUpload =>
      uid != null &&
      uid! > 0 &&
      formhash.isNotEmpty &&
      declaredUpload != null &&
      hasLegacyCropper &&
      const {'Filedata', 'avatar1', 'avatar2', 'avatar3'}
          .every(fieldNames.contains);

  bool get useBase64 => declaredUpload?.queryParameters['base64'] == 'yes';

  bool sameContractAs(DiscuzAvatarDescriptor other) {
    Uri? withoutHash(Uri? uri) {
      if (uri == null) return null;
      final query = {...uri.queryParameters}..remove('formhash');
      return uri.replace(queryParameters: query);
    }

    return canUpload &&
        other.canUpload &&
        uid == other.uid &&
        requiresReview == other.requiresReview &&
        useBase64 == other.useBase64 &&
        withoutHash(declaredUpload) == withoutHash(other.declaredUpload);
  }

  static DiscuzAvatarDescriptor parse(String source, Uri page) {
    final doc = html.parse(source);
    final form = doc.querySelector('#avatarform');
    final names = (form?.querySelectorAll('input[name], textarea[name]') ?? [])
        .where((node) => !node.attributes.containsKey('disabled'))
        .map((node) => node.attributes['name']!)
        .where((name) => const {
              'Filedata',
              'avatar1',
              'avatar2',
              'avatar3',
              'formhash',
              'savesubmit',
              'input',
              'agent',
              'base64'
            }.contains(name))
        .toSet()
        .toList();
    final declaration = RegExp(
        r'''(?:var\s+)?thirduploadurl\s*=\s*(['"])((?:\\.|(?!\1)[^\\])*)\1\s*;''');
    final formHook = RegExp(
        r'''\$\(\s*['"]avatarform['"]\s*\)\.action\s*=\s*(['"])((?:\\.|(?!\1)[^\\])*)\1\s*;''');
    Uri? upload;
    var reviewDeclared = false;
    for (final script in doc.querySelectorAll('script:not([src])')) {
      if (!const {
        '',
        'text/javascript',
        'application/javascript',
        'module',
        'text/ecmascript',
        'application/ecmascript'
      }.contains((script.attributes['type'] ?? '').toLowerCase())) {
        continue;
      }
      for (final hook in formHook.allMatches(script.text)) {
        final literal = _literal(hook[2]!);
        final parsed = literal == null ? null : Uri.tryParse(literal);
        if (parsed == null) continue;
        final target = page.resolveUri(parsed);
        reviewDeclared |= target.userInfo.isEmpty &&
            DiscuzRequestPolicy.sameOrigin(page, target) &&
            target.queryParameters['id'] == 'saya_avatarverify:index';
      }
      // Visible page text is not an executable upload declaration. The last
      // declaration wins, just as it does in the cropper's browser flow.
      for (final match in declaration.allMatches(script.text)) {
        upload = null;
        final decoded = _literal(match[2]!);
        final resolved = decoded == null ? null : Uri.tryParse(decoded);
        if (resolved != null && decoded!.isNotEmpty) {
          final target = page.resolveUri(resolved);
          if (const {'http', 'https'}.contains(target.scheme) &&
              target.userInfo.isEmpty &&
              DiscuzRequestPolicy.sameOrigin(page, target)) {
            upload = target;
            reviewDeclared |=
                target.queryParameters['id'] == 'saya_avatarverify:index';
          }
        }
      }
    }
    // Never restore a legacy target after a review endpoint was declared.
    if (reviewDeclared &&
        upload?.queryParameters['id'] != 'saya_avatarverify:index') {
      upload = null;
    }
    return DiscuzAvatarDescriptor(
      declaredUpload: upload,
      fieldNames: List.unmodifiable(names),
      hasFlash: RegExp(
              r'uc_avatarflash|AC_FL_RunContent|(?:avatar|camera)\.swf',
              caseSensitive: false)
          .hasMatch(source),
      hasLegacyCropper: doc.querySelectorAll('script[src]').any((script) {
        final scriptUri = Uri.tryParse(script.attributes['src']!);
        if (scriptUri == null) return false;
        final resolved = page.resolveUri(scriptUri);
        return resolved.userInfo.isEmpty &&
            DiscuzRequestPolicy.sameOrigin(page, resolved) &&
            resolved.path
                .endsWith('/source/plugin/uploadavatarpc/js/avatar.js');
      }),
      requiresReview: reviewDeclared,
      uid: DiscuzSessionParser.parse(source).uid,
      formhash: form?.attributes['method']?.toLowerCase() == 'post'
          ? (form
                      ?.querySelector('input[name="formhash"]')
                      ?.attributes['value'] ??
                  '')
              .trim()
          : '',
      statusMessage: DiscuzResponse.message(source) ?? '',
      phoneBindingUri: DiscuzResponse.phoneBindingUri(source, page),
    );
  }

  // Decode string literals only. Never evaluate scripts or concatenate code.
  static String? _literal(String text) {
    final result = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (text[i] != r'\') {
        result.write(text[i]);
        continue;
      }
      if (++i >= text.length) return null;
      final escape = text[i];
      if (const {'\\', '/', '"', "'"}.contains(escape)) {
        result.write(escape);
      } else if (escape == 'u' || escape == 'x') {
        final count = escape == 'u' ? 4 : 2;
        if (i + count >= text.length) return null;
        final value =
            int.tryParse(text.substring(i + 1, i + count + 1), radix: 16);
        if (value == null) return null;
        result.writeCharCode(value);
        i += count;
      } else if (escape == 'n') {
        result.write('\n');
      } else if (escape == 'r') {
        result.write('\r');
      } else if (escape == 't') {
        result.write('\t');
      } else {
        return null;
      }
    }
    return result.toString();
  }
}

class DiscuzAvatarReceipt {
  final DiscuzAvatarDescriptor descriptor;
  final Uri pageUri;
  final String session;
  final DateTime loadedAt;
  const DiscuzAvatarReceipt(
      this.descriptor, this.pageUri, this.session, this.loadedAt);
}

class DiscuzAvatarResult {
  final bool success, pendingReview;
  final String message;
  const DiscuzAvatarResult(this.success, this.message,
      {this.pendingReview = false});

  static DiscuzAvatarResult parse(String source,
      {required bool requiresReview}) {
    try {
      final document = XmlDocument.parse(source.trim());
      if (document.children.whereType<XmlDoctype>().isNotEmpty) {
        return const DiscuzAvatarResult(false, '无法确认上传结果，请刷新头像页面查看');
      }
      final root = document.rootElement;
      final faces = root.findElements('face').toList();
      if (root.name.local == 'root' &&
          root.name.prefix == null &&
          root.getAttribute('xmlns') == null &&
          root.childElements.length == 1 &&
          faces.length == 1 &&
          faces.single.name.prefix == null &&
          faces.single.getAttribute('xmlns') == null &&
          faces.single.childElements.isEmpty &&
          faces.single.innerText.trim().isEmpty &&
          root.descendants.whereType<XmlCDATA>().isEmpty &&
          root.innerText.trim().isEmpty &&
          root.children
              .whereType<XmlText>()
              .every((text) => text.value.trim().isEmpty)) {
        final success = faces.single.getAttribute('success');
        if (success == '1') {
          return DiscuzAvatarResult(
              true, requiresReview ? '头像已提交，请等待论坛审核' : '头像上传成功',
              pendingReview: requiresReview);
        }
        if (success == '0') {
          return const DiscuzAvatarResult(false, '论坛未接受此头像，请更换图片后重试');
        }
      }
    } on XmlException {
      // Login, permission and maintenance HTML is not an upload receipt.
    }
    return DiscuzAvatarResult(
        false, DiscuzResponse.message(source) ?? '无法确认上传结果，请刷新头像页面查看');
  }
}

/// The stock Flash/avatar.js transport is a byte encoding, not an image
/// conversion. This offline codec does not call an upload endpoint.
class DiscuzAvatarByteCodec {
  DiscuzAvatarByteCodec._();
  static String encodeHex(List<int> bytes) {
    const digits = '0123456789ABCDEF';
    final result = StringBuffer();
    for (final byte in bytes) {
      if (byte < 0 || byte > 255) {
        throw const FormatException('头像数据包含无效字节');
      }
      result
        ..write(digits[byte >> 4])
        ..write(digits[byte & 15]);
    }
    return result.toString();
  }

  static Uint8List decode(String value, {bool useBase64 = false}) {
    if (useBase64) return base64.decode(value);
    if (value.length.isOdd || !RegExp(r'^[0-9A-Fa-f]*$').hasMatch(value)) {
      throw const FormatException('头像编码不完整');
    }
    return Uint8List.fromList([
      for (var index = 0; index < value.length; index += 2)
        int.parse(value.substring(index, index + 2), radix: 16)
    ]);
  }
}
