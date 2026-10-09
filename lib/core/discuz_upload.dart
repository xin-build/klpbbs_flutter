import 'dart:convert';

class DiscuzUploadResponse {
  /// Discuz forum_upload::uploadmsg 的三种输出格式。
  static int? attachmentId(String source) {
    final value = source.trim();
    if (value.startsWith('DISCUZUPLOAD|')) {
      final parts = value.split('|');
      final simpleTwo = parts.length >= 8;
      final status =
          int.tryParse(parts.length > 2 ? parts[simpleTwo ? 2 : 1] : '');
      final aid =
          int.tryParse(parts.length > 3 ? parts[simpleTwo ? 3 : 2] : '');
      return status == 0 && aid != null && aid > 0 ? aid : null;
    }
    final number = int.tryParse(value);
    if (number != null) return number > 0 ? number : null;
    try {
      final data = jsonDecode(value);
      if (data is Map && data['errorcode'] == 0) {
        final aid = int.tryParse('${data['aid']}');
        return aid != null && aid > 0 ? aid : null;
      }
    } catch (_) {}
    return null;
  }
}

class DiscuzAvatarProtocol {
  /// HTML5 编辑器从网页签发的 camera URL 构造 UCenter rectavatar 请求。
  static Uri? target(String source, Uri page) {
    final match = RegExp(
            r'''(?:https?://|/)?[^\s"',<>]*images/camera\.swf\?[^\s"',<>]+''')
        .firstMatch(source);
    if (match == null) return null;
    final camera = page.resolve(match.group(0)!.replaceAll('&amp;', '&'));
    if (camera.queryParameters['input']?.isNotEmpty != true ||
        camera.queryParameters['agent']?.isNotEmpty != true) {
      return null;
    }
    final parameters = {...camera.queryParameters}..remove('inajax');
    parameters.addAll({'m': 'user', 'a': 'rectavatar', 'base64': 'yes'});
    return camera.replace(
        path: camera.path.replaceFirst('images/camera.swf', 'index.php'),
        queryParameters: parameters);
  }

  static bool saved(String source) =>
      RegExp(r'''(?:window\.)?parent\.postMessage\(\s*['"]success['"]\s*,''')
          .hasMatch(source) &&
      !RegExp(r'''postMessage\(\s*['"]failure['"]''').hasMatch(source);
}
