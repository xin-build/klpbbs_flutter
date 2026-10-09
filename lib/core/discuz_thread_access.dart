import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

enum DiscuzThreadAccessKind {
  authorOnly,
  loginRequired,
  passwordRequired,
  underReview,
  notFound,
  restricted,
  unavailable,
}

/// A page-level server response, never a post or a synthetic author.
class DiscuzThreadAccessException implements Exception {
  final DiscuzThreadAccessKind kind;
  final String message;
  final int? returnFid;

  const DiscuzThreadAccessException(this.kind, this.message, {this.returnFid});

  String get title => switch (kind) {
        DiscuzThreadAccessKind.authorOnly => '仅楼主可查看',
        DiscuzThreadAccessKind.loginRequired => '请先登录',
        DiscuzThreadAccessKind.passwordRequired => '帖子需要访问密码',
        DiscuzThreadAccessKind.underReview => '帖子正在审核',
        DiscuzThreadAccessKind.notFound => '帖子不存在或已被删除',
        DiscuzThreadAccessKind.restricted => '当前账号无法查看',
        DiscuzThreadAccessKind.unavailable => '暂时无法读取帖子',
      };

  @override
  String toString() => message;
}

/// Discuz PC and Comiis mobile use different showmessage containers.
/// Inspect visible page-level declarations before extracting any thread data.
class DiscuzThreadAccess {
  DiscuzThreadAccess._();

  static DiscuzThreadAccessException? parse(String source, {Uri? pageUri}) =>
      fromDocument(html.parse(source), pageUri: pageUri);

  static bool _visible(Element node) {
    for (Element? current = node; current != null; current = current.parent) {
      if (current.attributes.containsKey('hidden') ||
          current.attributes['aria-hidden'] == 'true' ||
          RegExp(r'display\s*:\s*none|visibility\s*:\s*hidden',
                  caseSensitive: false)
              .hasMatch(current.attributes['style'] ?? '')) {
        return false;
      }
    }
    return true;
  }

  static bool _insidePost(Element node) {
    for (Element? parent = node; parent != null; parent = parent.parent) {
      if (RegExp(r'^(?:post_|pid|postmessage_)\d+$').hasMatch(parent.id) ||
          parent.classes.contains('comiis_postli') ||
          parent.classes.contains('postitem') ||
          parent.classes.contains('t_f') ||
          parent.classes.contains('message')) {
        return true;
      }
    }
    return false;
  }

  static String _text(Element node) {
    final copy = node.clone(true);
    copy
        .querySelectorAll(
            'script,style,i,.comiis_password_ico,.alert_btnleft,[hidden],[aria-hidden="true"]')
        .forEach((child) => child.remove());
    for (final child in copy.querySelectorAll('*').toList()) {
      if (!_visible(child)) child.remove();
    }
    return copy.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static DiscuzThreadAccessKind? _kind(String message) {
    if (RegExp(r'只能楼主|仅(?:楼主|作者).*可见|只(?:有|允许).*作者.*查看').hasMatch(message)) {
      return DiscuzThreadAccessKind.authorOnly;
    }
    if (RegExp(r'请先登录|尚未登录|未登录|登录后.*(?:查看|访问)|需要.*登录').hasMatch(message)) {
      return DiscuzThreadAccessKind.loginRequired;
    }
    if (RegExp(r'密码').hasMatch(message)) {
      return DiscuzThreadAccessKind.passwordRequired;
    }
    if (RegExp(r'不存在|已(?:被)?删除|主题不存在|主题已被移除').hasMatch(message)) {
      return DiscuzThreadAccessKind.notFound;
    }
    if (RegExp(r'审核').hasMatch(message)) {
      return DiscuzThreadAccessKind.underReview;
    }
    if (RegExp(r'权限|用户组|无权|禁止访问|无(?:法|权).*(?:查看|访问)|阅读权限|绑定|验证|抱歉')
        .hasMatch(message)) {
      return DiscuzThreadAccessKind.restricted;
    }
    return null;
  }

  static int? _returnFid(Document doc, Element message, Uri base) {
    final candidates = <Element>[
      ...message.querySelectorAll('a[href]'),
      ...doc.querySelectorAll('.comiis_password_form a[href]'),
    ];
    for (final anchor in candidates) {
      final Uri uri;
      try {
        uri = base.resolve(anchor.attributes['href'] ?? '');
      } on FormatException {
        continue;
      }
      if (!const {'http', 'https'}.contains(uri.scheme) ||
          uri.origin != base.origin) {
        continue;
      }
      final staticForum =
          RegExp(r'^/forum-(\d+)-\d+\.html$').firstMatch(uri.path);
      final fid = staticForum != null
          ? int.tryParse(staticForum.group(1)!)
          : uri.path.endsWith('/forum.php') &&
                  uri.queryParameters['mod'] == 'forumdisplay'
              ? int.tryParse(uri.queryParameters['fid'] ?? '')
              : null;
      if (fid != null && fid > 0) return fid;
    }
    return null;
  }

  static DiscuzThreadAccessException? fromDocument(Document doc,
      {Uri? pageUri}) {
    final base = pageUri ?? Uri.parse('https://klpbbs.com/');
    final hasPosts = doc
        .querySelectorAll(
            '[id^="postmessage_"],.comiis_postli .message,.comiis_postli .locked,.postitem .postmessage')
        .any((node) =>
            _visible(node) &&
            (RegExp(r'^postmessage_\d+$').hasMatch(node.id) ||
                _insidePost(node)));
    if (hasPosts) return null;

    final pageTitle = doc.querySelector('title')?.text.trim() ?? '';
    final isMessagePage =
        pageTitle.startsWith('提示信息') || pageTitle.startsWith('错误信息');
    for (final selector in const [
      '#messagetext',
      '.comiis_password_top',
      '.alert_error',
      '.jump_c,.comiis_jump,.comiis_tip,.tip_c,.alert_info,.alert_notice',
    ]) {
      for (final node in doc.querySelectorAll(selector)) {
        if (!_visible(node) || _insidePost(node)) continue;
        final firstParagraph = node.querySelectorAll('p').where(_visible);
        final message =
            firstParagraph.isEmpty ? _text(node) : _text(firstParagraph.first);
        if (message.isEmpty) continue;
        final kind = _kind(message);
        final explicit = node.id == 'messagetext' ||
            node.classes.contains('comiis_password_top') ||
            node.classes.contains('alert_error');
        if (kind == null && !explicit && !isMessagePage) continue;
        return DiscuzThreadAccessException(
            kind ?? DiscuzThreadAccessKind.unavailable, message,
            returnFid: _returnFid(doc, node, base));
      }
    }
    if (isMessagePage) {
      for (final node in doc.querySelectorAll('.comiis_bodybox p,#ct p')) {
        if (!_visible(node) || _insidePost(node)) continue;
        final message = _text(node);
        final kind = _kind(message);
        if (kind != null) {
          return DiscuzThreadAccessException(kind, message,
              returnFid: _returnFid(doc, node, base));
        }
      }
      return const DiscuzThreadAccessException(
          DiscuzThreadAccessKind.unavailable, '论坛未返回可阅读的帖子内容，请刷新后重试。');
    }
    return null;
  }
}
