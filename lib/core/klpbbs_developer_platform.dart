import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'discuz_native_page.dart';
import 'discuz_request_policy.dart';
import 'discuz_response.dart';

enum DeveloperPlatformView { applications, documentation, application }

enum DeveloperBlockKind { paragraph, heading, notice, code, list, table }

class DeveloperDocumentBlock {
  final DeveloperBlockKind kind;
  final String text;
  final List<String> headers;
  final List<List<String>> rows;
  const DeveloperDocumentBlock(this.kind, this.text,
      {this.headers = const [], this.rows = const []});

  String get searchableText => '$text ${headers.join(' ')} '
      '${rows.map((row) => row.join(' ')).join(' ')}';
}

class DeveloperDocumentSection {
  final String id, title;
  final List<DeveloperDocumentBlock> blocks;
  const DeveloperDocumentSection(this.id, this.title, this.blocks);

  bool matches(String query) =>
      '$title ${blocks.map((block) => block.searchableText).join(' ')}'
          .toLowerCase()
          .contains(query.trim().toLowerCase());
}

class DeveloperPlatformLink {
  final String label;
  final Uri uri;
  const DeveloperPlatformLink(this.label, this.uri);
}

/// The platform has its own responsive template. Documentation is parsed as
/// structured sections rather than flattened into the forum's settings page.
/// No script is executed and no OAuth/API endpoint is automatically called.
class KlpbbsDeveloperPlatform {
  final Uri uri;
  final DeveloperPlatformView view;
  final String title;
  final String? emptyTitle, emptyDescription, message;
  final bool recognized, requiresLogin;
  final List<String> notices;
  final List<DeveloperDocumentSection> sections;
  final List<DeveloperPlatformLink> links;
  final DiscuzNativePage nativePage;
  const KlpbbsDeveloperPlatform({
    required this.uri,
    required this.view,
    required this.title,
    required this.nativePage,
    this.recognized = false,
    this.requiresLogin = false,
    this.emptyTitle,
    this.emptyDescription,
    this.message,
    this.notices = const [],
    this.sections = const [],
    this.links = const [],
  });

  static String pathFor(DeveloperPlatformView view) => switch (view) {
        DeveloperPlatformView.applications => 'klpbbs_new_api-console.html',
        DeveloperPlatformView.documentation => 'klpbbs_new_api-docs.html',
        DeveloperPlatformView.application =>
          'plugin.php?id=klpbbs_new_api:console&ac=apply',
      };

  /// Only the three published read-only destinations are intercepted. Routes
  /// containing app IDs, mutation parameters or credentials stay out of here.
  static DeveloperPlatformView? viewFor(Uri uri) {
    final query = uri.queryParameters;
    final file = uri.path.split('/').last;
    if (query.keys.any((key) => !const {'id', 'ac', 'mobile'}.contains(key))) {
      return null;
    }
    if (file == 'klpbbs_new_api-console.html' &&
        !query.containsKey('id') &&
        !query.containsKey('ac')) {
      return DeveloperPlatformView.applications;
    }
    if (file == 'klpbbs_new_api-docs.html' &&
        !query.containsKey('id') &&
        !query.containsKey('ac')) {
      return DeveloperPlatformView.documentation;
    }
    if (file != 'plugin.php') return null;
    if (query['id'] == 'klpbbs_new_api:docs' && !query.containsKey('ac')) {
      return DeveloperPlatformView.documentation;
    }
    if (query['id'] == 'klpbbs_new_api:console') {
      if (!query.containsKey('ac')) return DeveloperPlatformView.applications;
      if (query['ac'] == 'apply') return DeveloperPlatformView.application;
    }
    return null;
  }

  static String _text(Element element, {bool preserveLines = false}) {
    final copy = element.clone(true);
    copy
        .querySelectorAll('script, style, svg, input, button')
        .forEach((node) => node.remove());
    return preserveLines
        ? copy.text.trim()
        : copy.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _visible(Element node) {
    Element? current = node;
    while (current != null) {
      if (current.attributes.containsKey('hidden') ||
          current.attributes['aria-hidden'] == 'true' ||
          RegExp(r'display\s*:\s*none|visibility\s*:\s*hidden',
                  caseSensitive: false)
              .hasMatch(current.attributes['style'] ?? '')) {
        return false;
      }
      current = current.parent;
    }
    return true;
  }

  static bool _insideSection(Element node) {
    Element? parent = node.parent;
    while (parent != null) {
      if (parent.classes.contains('knapi-sec')) return true;
      parent = parent.parent;
    }
    return false;
  }

  static List<DeveloperDocumentBlock> _blocks(Element section) {
    final result = <DeveloperDocumentBlock>[];
    void visit(Element node) {
      if (!_visible(node) ||
          const {'script', 'style', 'svg', 'h2'}.contains(node.localName)) {
        return;
      }
      final text = _text(node);
      if (node.localName == 'table') {
        final headers = node
                .querySelectorAll('tr')
                .firstOrNull
                ?.querySelectorAll('th')
                .map(_text)
                .toList() ??
            <String>[];
        final rows = node
            .querySelectorAll('tr')
            .where((row) => row.querySelector('td') != null)
            .map((row) => row.querySelectorAll('td').map(_text).toList())
            .where((row) => row.any((cell) => cell.isNotEmpty))
            .toList();
        if (headers.isNotEmpty || rows.isNotEmpty) {
          result.add(DeveloperDocumentBlock(DeveloperBlockKind.table, '',
              headers: headers, rows: rows));
        }
      } else if (node.localName == 'pre' ||
          node.classes.contains('knapi-pre')) {
        final code = _text(node, preserveLines: true);
        if (code.isNotEmpty) {
          result.add(DeveloperDocumentBlock(DeveloperBlockKind.code, code));
        }
      } else if (node.classes.contains('knapi-alert')) {
        if (text.isNotEmpty) {
          result.add(DeveloperDocumentBlock(DeveloperBlockKind.notice, text));
        }
      } else if (node.localName == 'h3' || node.localName == 'h4') {
        if (text.isNotEmpty) {
          result.add(DeveloperDocumentBlock(DeveloperBlockKind.heading, text));
        }
      } else if (node.localName == 'ol' || node.localName == 'ul') {
        final items = node.children
            .where((child) => child.localName == 'li')
            .map(_text)
            .where((item) => item.isNotEmpty)
            .toList();
        if (items.isNotEmpty) {
          result.add(DeveloperDocumentBlock(
              DeveloperBlockKind.list,
              [
                for (var i = 0; i < items.length; i++)
                  '${node.localName == 'ol' ? '${i + 1}.' : '•'} ${items[i]}'
              ].join('\n')));
        }
      } else if (const {'p', 'dl'}.contains(node.localName) ||
          node.classes.contains('knapi-ep')) {
        if (text.isNotEmpty) {
          result
              .add(DeveloperDocumentBlock(DeveloperBlockKind.paragraph, text));
        }
      } else {
        for (final child in node.children) {
          visit(child);
        }
      }
    }

    for (final child in section.children) {
      visit(child);
    }
    return result;
  }

  static KlpbbsDeveloperPlatform parse(String source, Uri uri,
      {required DeveloperPlatformView view}) {
    final document = html.parse(source);
    final native = DiscuzNativePage.parse(source, uri);
    final root = document.querySelector('.knapi-wrap') ??
        document.querySelector('.knapi-embed');
    final sections = <DeveloperDocumentSection>[];
    final ids = <String>{};
    if (root != null) {
      for (final section in root.querySelectorAll('.knapi-sec')) {
        if (!_visible(section)) continue;
        final titleNode = section.querySelector('h2');
        final title = titleNode == null ? '' : _text(titleNode);
        if (title.isEmpty) continue;
        final id =
            section.id.isEmpty ? 'section-${sections.length}' : section.id;
        if (ids.add(id)) {
          sections.add(DeveloperDocumentSection(id, title, _blocks(section)));
        }
      }
    }
    final links = <DeveloperPlatformLink>[];
    final destinations = <String>{};
    for (final anchor in root?.querySelectorAll('a[href]') ?? <Element>[]) {
      if (!_visible(anchor)) continue;
      final target = uri.resolve(anchor.attributes['href']!);
      // Authorization/token/API endpoints are examples, never navigation.
      final isDocumentedThread = RegExp(r'^thread-\d+-\d+-\d+\.html$')
              .hasMatch(target.path.split('/').last) &&
          target.query.isEmpty;
      if (!DiscuzRequestPolicy.sameOrigin(uri, target) ||
          (viewFor(target) == null && !isDocumentedThread)) {
        continue;
      }
      final label = _text(anchor);
      if (label.isNotEmpty && destinations.add(target.toString())) {
        links.add(DeveloperPlatformLink(label, target));
      }
    }
    final notices = root
            ?.querySelectorAll('.knapi-alert')
            .where(_visible)
            .where((node) => !_insideSection(node))
            .map(_text)
            .where((text) => text.isNotEmpty)
            .toList() ??
        <String>[];
    final empty = root?.querySelector('.knapi-empty');
    final heading = root?.querySelector('h1');
    return KlpbbsDeveloperPlatform(
      uri: uri,
      view: view,
      nativePage: native,
      recognized: root != null,
      requiresLogin: native.requiresLogin,
      title: heading == null
          ? (view == DeveloperPlatformView.documentation ? '开发文档' : '开发者控制台')
          : _text(heading),
      emptyTitle: empty?.querySelector('.knapi-empty-t')?.text.trim(),
      emptyDescription: empty?.querySelector('.knapi-empty-d')?.text.trim(),
      message: DiscuzResponse.message(source),
      notices: notices,
      sections: sections,
      links: links,
    );
  }
}

class DeveloperPlatformReceipt {
  final KlpbbsDeveloperPlatform platform;
  final String session;
  final DateTime loadedAt;
  const DeveloperPlatformReceipt(this.platform, this.session, this.loadedAt);
  DiscuzNativePageReceipt get nativeReceipt =>
      DiscuzNativePageReceipt(platform.nativePage, session, loadedAt);
}
