import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'discuz_request_policy.dart';
import 'klpbbs_facemall.dart';
import 'user_avatar_presentation.dart';

/// An avatar and an optional pendant explicitly declared by an author region.
/// A null frame is unknown; an empty frame is an explicit removal.
class DiscuzAvatarDeclaration {
  final int uid;
  final String username;
  final String? avatarUrl;
  final String? faceUrl;
  const DiscuzAvatarDeclaration(
      {required this.uid, this.username = '', this.avatarUrl, this.faceUrl});
}

class DiscuzAvatarDeclarations {
  DiscuzAvatarDeclarations._();
  static const _avatarClasses = {
    'avtm',
    'avt',
    'avatar',
    'k-av',
    'kmimg',
    'postli_top_tximg',
    'wxlist_tx',
    'comiis_avatar',
    'comiis_space_tx',
    'comiis_userpic',
    'user_img',
    'comiis_tx',
    'klp-uhead-av',
    'klp-pm-av',
    'klp-msg-av',
    'replyfloor_content_avatar',
    'tsmini_horn_avatar',
    'sunju_facemall_main',
  };
  static final _regions = _avatarClasses.map((name) => '.$name').join(',');
  static const _declaredImages = 'img[src*="##SJ##"],'
      'img[data-original*="##SJ##"],img[data-src*="##SJ##"],img[data-face]';
  static final _frameClass = RegExp(
      r'''class\s*=\s*["'][^"']*\b(?:sunju_facemall(?:_main)?|sj_fm_myface_mall)\b''',
      caseSensitive: false);

  /// Script URLs alone do not warrant another full DOM parse.
  static bool mayContainFrames(String source) =>
      source.contains('##SJ##') ||
      _frameClass.hasMatch(source) ||
      RegExp(r'\bdata-face\s*=', caseSensitive: false).hasMatch(source);

  /// The mobile plugin decorates every declared avatar before displaying it.
  /// The desktop template omits the same fields, so its absence is not evidence.
  static bool usesMobileFrameTemplate(String source, Uri responseUri) {
    if (responseUri.queryParameters['mobile'] != '2') return false;
    final scripts = RegExp(r'''<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["']''',
            caseSensitive: false)
        .allMatches(source);
    for (final script in scripts) {
      try {
        final uri = responseUri.resolve(script[1]!);
        if (DiscuzRequestPolicy.sameOrigin(responseUri, uri) &&
            uri.path.endsWith(
                '/source/plugin/sunju_facemall/public/sunju_face_mobile.js')) {
          return true;
        }
      } on FormatException {
        continue;
      }
    }
    return false;
  }

  static int? uidFromProfile(String? href, Uri base) {
    if (href == null || href.isEmpty) return null;
    Uri uri;
    try {
      uri = base.resolve(href);
    } on FormatException {
      return null;
    }
    if (!DiscuzRequestPolicy.sameOrigin(base, uri)) return null;
    final seo =
        RegExp(r'(?:^|/)space-uid-(\d+)(?:\.html|$)').firstMatch(uri.path);
    if (seo != null) return _positive(seo.group(1));
    if (!uri.path.endsWith('/home.php') ||
        uri.queryParameters['mod'] != 'space') {
      return null;
    }
    return _positive(uri.queryParameters['uid']);
  }

  static int? _positive(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static int? uidFromAvatar(String? source, Uri base) {
    final avatar = UserAvatarPresentation.avatarUrl(source, base);
    if (avatar == null) return null;
    final uri = Uri.parse(avatar);
    // Only the forum's UCenter host can declare an identity via its image URL.
    if (uri.host != base.host && uri.host != 'user.${base.host}') return null;
    if (uri.path.endsWith('/avatar.php')) {
      return _positive(uri.queryParameters['uid']);
    }
    final path = RegExp(
            r'/data/avatar/(\d{3})/(\d{2})/(\d{2})/(\d{2})_avatar_(?:small|middle|big)\.[a-z0-9]+$',
            caseSensitive: false)
        .firstMatch(uri.path);
    if (path == null) return null;
    return _positive('${path[1]}${path[2]}${path[3]}${path[4]}');
  }

  static List<DiscuzAvatarDeclaration> parse(String source, Uri base) =>
      fromDocument(html.parse(source), base);

  static List<DiscuzAvatarDeclaration> fromDocument(Document doc, Uri base) {
    return _fromRegions([
      ...doc.querySelectorAll(_regions),
      ...doc
          .querySelectorAll(_declaredImages)
          .map((image) => _avatarRegion(image, base)),
    ], base);
  }

  /// List rows can reuse the website declaration rules without parsing their
  /// HTML again or accepting another user's frame from surrounding content.
  static List<DiscuzAvatarDeclaration> fromElement(Element scope, Uri base) {
    return _fromRegions([
      if (scope.classes.any(_avatarClasses.contains)) scope,
      ...scope.querySelectorAll(_regions),
      ...scope
          .querySelectorAll(_declaredImages)
          .map((image) => _avatarRegion(image, base)),
    ], base);
  }

  static Element _avatarRegion(Element image, Uri base) {
    for (Element? node = image.parent, next; node != null; node = next) {
      next = node.parent;
      if (node.classes.any(_avatarClasses.contains) ||
          (node.localName == 'a' &&
              uidFromProfile(node.attributes['href'], base) != null)) {
        return node;
      }
      // Do not enlarge an image's ownership to a whole row, body or table.
      if (node.localName != 'em' && node.localName != 'span') break;
    }
    return image.parent ?? image;
  }

  static List<DiscuzAvatarDeclaration> _fromRegions(
      List<Element> regions, Uri base) {
    final entries = <int, DiscuzAvatarDeclaration>{};
    for (final region in regions) {
      // Post bodies and quoted content can contain copied avatar markup.
      if (_inPostBody(region)) continue;
      final declaration = _region(region, base);
      if (declaration == null) continue;
      final old = entries[declaration.uid];
      entries[declaration.uid] = DiscuzAvatarDeclaration(
          uid: declaration.uid,
          username: declaration.username.isNotEmpty
              ? declaration.username
              : old?.username ?? '',
          avatarUrl: declaration.avatarUrl ?? old?.avatarUrl,
          faceUrl: declaration.faceUrl ?? old?.faceUrl);
    }
    return List.unmodifiable(entries.values);
  }

  static bool _inPostBody(Element region) {
    var nestedAvatar = false;
    int? nestedPost, authorPost;
    for (Element? node = region; node != null; node = node.parent) {
      if (node.classes.contains('replyfloor_content_avatar')) {
        nestedAvatar = true;
      }
      if (node.classes.contains('replyfloor_box')) {
        nestedPost = _positive(
            RegExp(r'^replyfloor_box_(\d+)$').firstMatch(node.id)?.group(1));
      }
      if (node.classes.contains('comiis_postli')) {
        authorPost =
            _positive(RegExp(r'^pid(\d+)$').firstMatch(node.id)?.group(1));
      }
    }
    final realNestedAvatar =
        nestedAvatar && nestedPost != null && nestedPost == authorPost;
    for (Element? node = region; node != null; node = node.parent) {
      if (node.localName == 'blockquote' ||
          node.classes.any(const {'t_f', 'quote', 'blockcode'}.contains)) {
        return true;
      }
      if (node.classes.contains('message') ||
          node.classes.contains('comiis_message')) {
        // The current mobile template adds both classes to the outer floor
        // body. Only its own, separately scoped replyfloor avatars belong here.
        final nestedOwnerBody = realNestedAvatar &&
            node.classes.contains('comiis_message') &&
            node.id == nestedPost.toString();
        if (!nestedOwnerBody) return true;
      }
    }
    return false;
  }

  static DiscuzAvatarDeclaration? _region(Element region, Uri base) {
    final images =
        region.localName == 'img' ? [region] : region.querySelectorAll('img');
    final avatar = images.where((image) =>
        !image.classes.contains('sunju_facemall') &&
        !image.classes.contains('sj_fm_myface_mall'));
    if (avatar.isEmpty) return null;
    final image = avatar.first;
    // Lazy-loaded templates keep a placeholder in src. Their actual avatar and
    // pendant declaration belongs to the deferred source, when present.
    final raw = imageSource(image);
    final imageUid = uidFromAvatar(raw, base);
    Element? owner;
    final links = <Element>[
      if (region.localName == 'a') region,
      ...region.querySelectorAll('a[href]'),
      if (region.parent?.localName == 'a') region.parent!,
    ];
    for (final link in links) {
      if (uidFromProfile(link.attributes['href'], base) != null) {
        owner = link;
        break;
      }
    }
    final linkUid = uidFromProfile(owner?.attributes['href'], base);
    if (linkUid != null && imageUid != null && linkUid != imageUid) return null;
    final uid = linkUid ?? imageUid;
    if (uid == null) return null;
    final frame = frameFromAvatar(image, base, scope: region);
    return DiscuzAvatarDeclaration(
        uid: uid,
        username: owner?.text.trim() ?? '',
        avatarUrl: UserAvatarPresentation.avatarUrl(raw, base),
        faceUrl: frame);
  }

  static String? imageSource(Element? image) {
    if (image == null) return null;
    for (final key in const ['data-original', 'data-src', 'src']) {
      final value = image.attributes[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// All templates use the same explicit declaration forms. A placeholder in
  /// src cannot hide a deferred declaration, and an empty declaration removes
  /// a previously worn pendant. Overlay searches stay in the avatar wrapper.
  static String? frameFromAvatar(Element? image, Uri base, {Element? scope}) {
    if (image == null) return null;
    if (_inPostBody(image) ||
        !_sameAvatarOwner(image, _avatarRegion(image, base), base)) {
      return null;
    }
    for (final key in const ['data-original', 'data-src', 'src']) {
      final raw = image.attributes[key];
      if (raw?.contains('##SJ##') != true) continue;
      final frame = raw!.split('##SJ##').last.trim();
      return frame.isEmpty ? '' : KlpFacemallResponse.frameUrl(frame, base);
    }
    if (image.attributes.containsKey('data-face')) {
      final frame = image.attributes['data-face']!.trim();
      return frame.isEmpty ? '' : KlpFacemallResponse.frameUrl(frame, base);
    }
    // Old PC templates place the overlay beside the profile anchor, rather
    // than inside it. Walk only the small avatar wrapper chain, never a row.
    var region = scope ?? image.parent;
    for (var depth = 0;
        region != null && depth < 3;
        depth++, region = region.parent) {
      final avatarRegion = region.classes.any(_avatarClasses.contains) ||
          (region.localName == 'a' &&
              uidFromProfile(region.attributes['href'], base) != null);
      if (!avatarRegion) {
        if (region.localName == 'span' || region.localName == 'em') continue;
        break;
      }
      if (_inPostBody(region) || !_sameAvatarOwner(image, region, base)) {
        return null;
      }
      final overlay =
          region.querySelector('img.sunju_facemall,img.sj_fm_myface_mall');
      if (overlay != null) {
        return KlpFacemallResponse.frameUrl(imageSource(overlay), base);
      }
    }
    return null;
  }

  static bool _sameAvatarOwner(Element image, Element region, Uri base) {
    final identities = <int>{};
    void add(int? uid) {
      if (uid != null) identities.add(uid);
    }

    add(uidFromAvatar(imageSource(image), base));
    if (region.localName == 'a') {
      add(uidFromProfile(region.attributes['href'], base));
    }
    if (region.parent?.localName == 'a') {
      add(uidFromProfile(region.parent?.attributes['href'], base));
    }
    for (final link in region.querySelectorAll('a[href]')) {
      add(uidFromProfile(link.attributes['href'], base));
    }
    for (final candidate in region.querySelectorAll('img')) {
      if (candidate.classes.contains('sunju_facemall') ||
          candidate.classes.contains('sj_fm_myface_mall')) {
        continue;
      }
      add(uidFromAvatar(imageSource(candidate), base));
    }
    return identities.length <= 1;
  }

  /// The exact username query is the website's lookup contract. UID links from
  /// navigation, friends, comments or a search result cannot establish ownership.
  static DiscuzAvatarDeclaration? namedSpace(String source,
      {required Uri base, required Uri responseUri, required String username}) {
    if (!DiscuzRequestPolicy.sameOrigin(base, responseUri)) return null;
    final requestedName = responseUri.queryParameters['username'];
    final directUid = uidFromProfile(responseUri.toString(), base);
    final named = responseUri.path.endsWith('/home.php') &&
        responseUri.queryParameters['mod'] == 'space' &&
        requestedName == username;
    if (!named && directUid == null) return null;
    final doc = html.parse(source);
    final ownerRegions = doc.querySelectorAll(
        '#uhd .klp-uhead-av, #uhd .avt, #uhd .avtm, .comiis_space_tx');
    final owners = ownerRegions
        .map((e) => _region(e, base))
        .whereType<DiscuzAvatarDeclaration>()
        .toList();
    if (owners.isEmpty || owners.map((e) => e.uid).toSet().length != 1) {
      return null;
    }
    final owner = owners.first;
    if (directUid != null && owner.uid != directUid) return null;
    if (!named) {
      final ownerNames = doc.querySelectorAll(
          '#uhd h2, #uhd .klp-uhead-name, .comiis_space_name');
      if (!ownerNames.any((element) => element.text.trim() == username)) {
        return null;
      }
    }
    return DiscuzAvatarDeclaration(
        uid: owner.uid,
        username: username,
        avatarUrl: owner.avatarUrl,
        faceUrl: owner.faceUrl);
  }

  /// Only the requested profile's own avatar may answer a missing appearance.
  /// Login/errors and navigation avatars cannot impersonate its owner. A valid
  /// mobile owner without a pendant is a confirmed empty result, not a failure.
  static DiscuzAvatarDeclaration? mobileSpace(String source,
      {required Uri base, required Uri responseUri, required int uid}) {
    if (uid <= 0 ||
        !DiscuzRequestPolicy.sameOrigin(base, responseUri) ||
        responseUri.queryParameters['mobile'] != '2' ||
        uidFromProfile(responseUri.toString(), base) != uid ||
        !usesMobileFrameTemplate(source, responseUri)) {
      return null;
    }
    final doc = html.parse(source);
    final owners = doc
        .querySelectorAll('.comiis_space_tx')
        .map((region) => _region(region, base))
        .whereType<DiscuzAvatarDeclaration>()
        .toList();
    if (owners.isEmpty || owners.any((owner) => owner.uid != uid)) return null;
    final owner = owners.first;
    final region = doc.querySelector('.comiis_space_tx')!;
    // Malformed, rejected or unresolved declarations must not remove a frame.
    final containsDeclaration = region.querySelectorAll('img').any((image) =>
        image.attributes.values.any((value) => value.contains('##SJ##')) ||
        image.attributes.containsKey('data-face') ||
        image.classes.contains('sunju_facemall') ||
        image.classes.contains('sj_fm_myface_mall'));
    if (owner.faceUrl == null && containsDeclaration) return null;
    return DiscuzAvatarDeclaration(
        uid: uid,
        username: owner.username,
        avatarUrl: owner.avatarUrl,
        faceUrl: owner.faceUrl ?? '');
  }
}
