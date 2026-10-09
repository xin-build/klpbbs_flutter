import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import '../models/horn_message.dart';
import 'discuz_avatar_declaration.dart';

/// ahome_horn 的霸屏列表只来自对应脚本或实际霸屏容器，不执行网页 JS。
class DiscuzHornProtocol {
  static final _assignment =
      RegExp(r'\b(?:var|let|const)\s+(?:data|ahorn_boss)\s*=\s*');
  static final _urls = RegExp(
      r'''https?://(?:www\.)?klpbbs\.(?:com|cn)/thread-\d+-\d+-\d+\.html(?:\?[A-Za-z0-9_%=&;.+:/?#~-]+)?(?:#[A-Za-z0-9_%-]+)?|https?://[A-Za-z0-9_%=&;.+:/?#@!~()*,-]+''');

  static List<HornMessage> parseBanners(String source, Uri base,
      {dom.Document? document}) {
    final doc = document ?? html.parse(source);
    final result = <HornMessage>[];
    final seen = <String>{};
    for (final script in doc.querySelectorAll('script')) {
      final code = script.text;
      if (!RegExp(r'\bahorn_boss\b|\bahorn_stage\b').hasMatch(code)) continue;
      for (final assignment in _assignment.allMatches(code)) {
        final array = _array(code, assignment.end);
        if (array == null) continue;
        try {
          final decoded = jsonDecode(array);
          if (decoded is! List) continue;
          for (final row in decoded) {
            if (row is! Map) continue;
            final name =
                (row['n'] ?? row['username'] ?? row['author'] ?? '').toString();
            final avatar = (row['a'] ?? row['avatar'] ?? '').toString();
            final message =
                (row['m'] ?? row['message'] ?? row['content'] ?? '').toString();
            final banner = _message(name, avatar, message, base,
                id: int.tryParse('${row['id'] ?? ''}') ?? 0,
                uid: int.tryParse('${row['uid'] ?? ''}'));
            if (banner != null && seen.add(identity(banner))) {
              result.add(banner);
            }
          }
        } on FormatException {
          // 非 JSON 或损坏的数据不作为有效广播。
        }
      }
    }
    if (result.isNotEmpty) return result;
    for (final box
        in doc.querySelectorAll('#ahorn_boss, .ahorn_boss, .comiis_tuhao')) {
      final name =
          box.querySelector('.ahorn_name, .name, .author, .comiis_user');
      final message = box.querySelector('.ahorn_msg, .msg, .content, .text');
      if (name == null || message == null) continue;
      final author = name.text
          .replaceFirst(RegExp(r'^\s*(?:💰)?\s*土豪\s*'), '')
          .replaceFirst(RegExp(r'\s*驾到\s*(?:💰)?\s*$'), '')
          .trim();
      final profile =
          box.querySelector('a[href*="uid="], a[href*="space-uid"]');
      final href = profile?.attributes['href'] ?? '';
      final uid = int.tryParse(Uri.tryParse(href)?.queryParameters['uid'] ??
          RegExp(r'space-uid-(\d+)').firstMatch(href)?[1] ??
          '');
      final banner = _message(author, box.querySelector('img')?.outerHtml ?? '',
          message.innerHtml, base,
          uid: uid);
      if (banner != null && seen.add(identity(banner))) result.add(banner);
    }
    return result;
  }

  static String identity(HornMessage message) =>
      '${message.id}:${message.uid}:${message.author}:${message.content}';

  static String messageText(String content) =>
      html.parseFragment(content).text?.trim() ?? '';

  /// 只把当前论坛及其正式别名的实际帖子 URL 交给原生帖子页。
  static int? threadId(String link, Uri base) {
    final uri = Uri.tryParse(_url(link, base) ?? '');
    if (uri == null ||
        !{
          base.host,
          'klpbbs.com',
          'www.klpbbs.com',
          'klpbbs.cn',
          'www.klpbbs.cn'
        }.contains(uri.host)) {
      return null;
    }
    final path = uri.pathSegments.lastOrNull ?? '';
    final match = RegExp(r'^thread-(\d+)-\d+-\d+\.html$').firstMatch(path);
    if (match != null) return int.tryParse(match[1]!);
    if (path == 'forum.php' &&
        const {'viewthread', 'redirect'}.contains(uri.queryParameters['mod'])) {
      return int.tryParse(
          uri.queryParameters['tid'] ?? uri.queryParameters['ptid'] ?? '');
    }
    return null;
  }

  static HornMessage? _message(
      String name, String avatarHtml, String raw, Uri base,
      {int id = 0, int? uid}) {
    final author = messageText(name);
    final content = html.parseFragment(raw);
    content
        .querySelectorAll('script, style, iframe, object, embed')
        .forEach((node) => node.remove());
    for (final node in content.querySelectorAll('*')) {
      node.attributes.removeWhere(
          (key, _) => key.toString().toLowerCase().startsWith('on'));
      if (node.localName == 'img') {
        final src = _url(node.attributes['src'] ?? '', base);
        if (src == null) {
          node.remove();
        } else {
          node.attributes['src'] = src;
        }
      }
      if (node.localName == 'a') {
        final link = _url(node.attributes['href'] ?? '', base);
        if (link == null) {
          node.attributes.remove('href');
        } else {
          node.attributes['href'] = link;
        }
      }
    }
    final message = content.nodes.map((node) => _render(node)).join().trim();
    if (author.isEmpty || message.isEmpty) return null;
    final avatarFragment = html.parseFragment(avatarHtml);
    final image = avatarFragment
        .querySelectorAll('img')
        .where((image) =>
            !image.classes.contains('sunju_facemall') &&
            !image.classes.contains('sj_fm_myface_mall'))
        .firstOrNull;
    final avatarSource =
        DiscuzAvatarDeclarations.imageSource(image) ?? avatarHtml.trim();
    final parts = avatarSource.split('##SJ##');
    final avatar = _url(parts.first, base);
    final declarationImage =
        image ?? (dom.Element.tag('img')..attributes['src'] = avatarSource);
    final face =
        DiscuzAvatarDeclarations.frameFromAvatar(declarationImage, base);
    uid = uid != null && uid > 0
        ? uid
        : DiscuzAvatarDeclarations.uidFromAvatar(avatar, base);
    final link = content.querySelector('a[href]')?.attributes['href'] ??
        _urls.firstMatch(content.text ?? '')?.group(0);
    return HornMessage(
      id: id,
      author: author,
      uid: uid,
      avatarUrl: avatar,
      faceUrl: face,
      content: message,
      linkUrl: link == null ? null : _url(link, base),
      tag: '土豪',
      timeText: '土豪霸屏',
    );
  }

  /// 原文中的 URL 与紧邻中文分别保留；已有 a 标签不再次包裹。
  static String _render(dom.Node node, {bool insideLink = false}) {
    if (node is dom.Text) {
      if (insideLink) return const HtmlEscape().convert(node.data);
      final result = StringBuffer();
      var end = 0;
      for (final match in _urls.allMatches(node.data)) {
        result.write(
            const HtmlEscape().convert(node.data.substring(end, match.start)));
        final value = const HtmlEscape().convert(match[0]!);
        result.write('<a href="$value">$value</a>');
        end = match.end;
      }
      result.write(const HtmlEscape().convert(node.data.substring(end)));
      return result.toString();
    }
    if (node is dom.Element) {
      final clone = node.clone(false);
      clone.innerHtml = node.nodes
          .map((child) =>
              _render(child, insideLink: insideLink || node.localName == 'a'))
          .join();
      return clone.outerHtml;
    }
    return '';
  }

  static String? _url(String value, Uri base) {
    if (value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return null;
    final resolved = base.resolveUri(uri);
    return const {'https', 'http'}.contains(resolved.scheme)
        ? resolved.toString()
        : null;
  }

  static String? _array(String code, int from) {
    var start = from;
    while (start < code.length && code[start].trim().isEmpty) {
      start++;
    }
    if (start >= code.length || code[start] != '[') return null;
    var depth = 0;
    String? quote;
    var escaped = false;
    for (var i = start; i < code.length; i++) {
      final ch = code[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '[') {
        depth++;
      } else if (ch == ']' && --depth == 0) {
        return code.substring(start, i + 1);
      }
    }
    return null;
  }
}
