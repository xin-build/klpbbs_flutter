import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'discuz_native_page.dart';
import 'discuz_request_policy.dart';
import 'discuz_response.dart';
import 'klpbbs_developer_platform.dart';

/// A link is actionable only when the current plugin explicitly declares its
/// confirmation and CSRF. A label containing "revoke" is never an endpoint.
class AuthorizationAction {
  final String label, confirmation;
  final Uri uri;
  const AuthorizationAction(this.label, this.confirmation, this.uri);

  static String _identity(Uri uri) {
    final entries = uri.queryParametersAll.entries
        .where((entry) => entry.key != 'formhash')
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return uri.replace(queryParameters: {
      for (final entry in entries) entry.key: entry.value,
    }).toString();
  }

  bool sameContractAs(AuthorizationAction other) =>
      label == other.label &&
      confirmation == other.confirmation &&
      _identity(uri) == _identity(other.uri);
}

class KlpbbsAuthorizations {
  static const path =
      'home.php?mod=spacecp&ac=plugin&id=klpbbs_new_api:myauth&mobile=no';
  final Uri uri;
  final bool recognized, requiresLogin;
  final String? message, emptyTitle, emptyDescription;
  final List<String> notices;
  final List<String> details;
  final List<DeveloperPlatformLink> developerLinks;
  final List<AuthorizationAction> actions;
  final DiscuzNativePage nativePage;

  KlpbbsAuthorizations(
      {required this.uri,
      required this.nativePage,
      this.recognized = false,
      this.requiresLogin = false,
      this.message,
      this.emptyTitle,
      this.emptyDescription,
      List<String> notices = const [],
      List<String> details = const [],
      List<DeveloperPlatformLink> developerLinks = const [],
      List<AuthorizationAction> actions = const []})
      : notices = List.unmodifiable(notices),
        details = List.unmodifiable(details),
        developerLinks = List.unmodifiable(developerLinks),
        actions = List.unmodifiable(actions);

  static bool isPage(Uri uri) =>
      uri.path.split('/').last == 'home.php' &&
      uri.queryParameters['mod'] == 'spacecp' &&
      uri.queryParameters['ac'] == 'plugin' &&
      uri.queryParameters['id'] == 'klpbbs_new_api:myauth';

  static bool isListPage(Uri uri) =>
      isPage(uri) &&
      uri.userInfo.isEmpty &&
      uri.fragment.isEmpty &&
      uri.queryParameters.keys.every(
          (key) => const {'mod', 'ac', 'id', 'mobile', 'uid'}.contains(key)) &&
      uri.queryParametersAll.values.every((values) => values.length == 1);

  List<DiscuzPageLink> get unresolvedLinks => nativePage.links
      .where((link) =>
          !developerLinks.any((known) => known.uri == link.uri) &&
          !actions.any((known) => known.uri == link.uri))
      .toList(growable: false);

  bool get isExplicitlyEmpty =>
      emptyTitle?.isNotEmpty == true &&
      nativePage.tables.isEmpty &&
      nativePage.forms.isEmpty &&
      actions.isEmpty &&
      details.isEmpty &&
      unresolvedLinks.isEmpty;

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

  static String _text(Element node) {
    final copy = node.clone(true);
    copy
        .querySelectorAll('script, style, input, button, textarea, select')
        .forEach((element) => element.remove());
    return copy.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static KlpbbsAuthorizations parse(String source, Uri uri) {
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source);
    final document = html.parse(cdata?.group(1) ?? source);
    final full = DiscuzNativePage.parse(source, uri);
    final root =
        document.querySelectorAll('.knapi').where(_visible).firstOrNull;
    final recognized = isPage(uri) && root != null && !full.requiresLogin;
    if (!recognized) {
      return KlpbbsAuthorizations(
          uri: uri,
          nativePage: full,
          requiresLogin: full.requiresLogin,
          message: DiscuzResponse.message(source));
    }
    // Scope records to the actual plugin; the settings sidebar and header are
    // not applications or authorization operations.
    final native = DiscuzNativePage.parse(root.outerHtml, uri);
    final empty =
        root.querySelectorAll('.knapi-empty').where(_visible).firstOrNull;
    final notices = root
        .querySelectorAll('.knapi-alert')
        .where(_visible)
        .map(_text)
        .where((text) => text.isNotEmpty)
        .toSet()
        .toList();
    final links = <DeveloperPlatformLink>[], actions = <AuthorizationAction>[];
    final seen = <String>{};
    for (final anchor in root.querySelectorAll('a[href]').where(_visible)) {
      final label = _text(anchor), href = anchor.attributes['href']!.trim();
      if (label.isEmpty || href.isEmpty) continue;
      final target = uri.resolve(href);
      if (!DiscuzRequestPolicy.sameOrigin(uri, target) ||
          target.userInfo.isNotEmpty ||
          target.fragment.isNotEmpty ||
          target.queryParametersAll.values
              .any((values) => values.length != 1)) {
        continue;
      }
      final view = KlpbbsDeveloperPlatform.viewFor(target);
      if (view != null && seen.add(target.toString())) {
        links.add(DeveloperPlatformLink(label, target));
        continue;
      }
      final confirmation =
          anchor.attributes['data-knapi-confirm']?.trim() ?? '';
      if (confirmation.isNotEmpty &&
          isPage(target) &&
          target.queryParameters['formhash']?.isNotEmpty == true &&
          seen.add(target.toString())) {
        actions.add(AuthorizationAction(label, confirmation, target));
      }
    }
    final details =
        native.information.where((text) => !notices.contains(text)).toList();
    return KlpbbsAuthorizations(
        uri: uri,
        nativePage: native,
        recognized: true,
        notices: notices,
        details: details,
        developerLinks: links,
        actions: actions,
        message: DiscuzResponse.message(source),
        emptyTitle: empty?.querySelector('.knapi-empty-t')?.text.trim(),
        emptyDescription: empty?.querySelector('.knapi-empty-d')?.text.trim());
  }
}

class AuthorizationsReceipt {
  final KlpbbsAuthorizations page;
  final String session;
  final DateTime loadedAt;
  const AuthorizationsReceipt(this.page, this.session, this.loadedAt);

  DiscuzNativePageReceipt get nativeReceipt =>
      DiscuzNativePageReceipt(page.nativePage, session, loadedAt);
}
