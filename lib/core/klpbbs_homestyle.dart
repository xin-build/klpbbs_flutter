import 'package:html/parser.dart' as html;

import 'discuz_form.dart';

typedef KlpHomeStyleCategory = ({String id, String name});
typedef KlpHomeStyle = ({String id, String name, String url});

/// The plugin changes its JavaScript handler name and category IDs. Read the
/// declarations and the generated form without executing any JavaScript.
class KlpHomeStyleCatalog {
  final List<KlpHomeStyleCategory> categories;
  final List<KlpHomeStyle> items;
  final String category;
  final DiscuzForm? saveForm;
  final bool recognized;

  const KlpHomeStyleCatalog({
    this.categories = const [],
    this.items = const [],
    this.category = '',
    this.saveForm,
    this.recognized = false,
  });

  static String _clean(String text) => text
      .replaceAll(RegExp(r'[\uE000-\uF8FF]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static KlpHomeStyleCatalog parse(String source, Uri base,
      {String category = ''}) {
    final doc = html.parse(source);
    if (doc.querySelector('#messagetext, .alert_error, #loginform, '
            'form[id^="loginform_"]') !=
        null) {
      return KlpHomeStyleCatalog(category: category);
    }
    final categories = <KlpHomeStyleCategory>[];
    final categoryIds = <String>{};
    for (final link in doc
        .querySelectorAll('.swiper-slide a[href], .comiis_topnv li a[href]')) {
      final uri = base.resolve(link.attributes['href']!);
      if (uri.origin != base.origin ||
          uri.queryParameters['id'] != 'comiis_app_homestyle') {
        continue;
      }
      final id = uri.queryParameters['smod'] ?? '';
      final name = _clean(link.text);
      if (name.isNotEmpty && categoryIds.add(id)) {
        categories.add((id: id, name: name));
      }
    }
    final items = <KlpHomeStyle>[];
    final ids = <String>{};
    final handlers = <String>{};
    for (final node in doc.querySelectorAll('[onclick]')) {
      final call = RegExp(
              r'''^\s*(comiis_home\w+)\s*\(\s*this\s*,\s*['"]([^'"]+)['"]\s*,\s*['"](\d+)['"]\s*\)\s*;?\s*$''')
          .firstMatch(node.attributes['onclick']!);
      if (call == null || !ids.add(call[3]!)) continue;
      final uri = base.resolve(call[2]!);
      if (!const {'http', 'https'}.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty ||
          uri.host.isEmpty) {
        continue;
      }
      handlers.add(call[1]!);
      final image = node.querySelector('img');
      final name = _clean(node.attributes['title'] ??
          image?.attributes['alt'] ??
          image?.attributes['title'] ??
          '');
      items.add((id: call[3]!, name: name, url: uri.toString()));
    }
    DiscuzForm? form = DiscuzForm.namedSubmit(source, 'homesubmit');
    final script =
        doc.querySelectorAll('script').map((node) => node.text).join('\n');
    if (form == null) {
      for (final handler in handlers) {
        final body = _function(script, handler);
        if (body == null) continue;
        for (final call
            in RegExp(r'\b(comiis_post_\w+)\s*\(\s*id\s*\)').allMatches(body)) {
          final builder = _function(script, call[1]!);
          if (builder == null) continue;
          // Literal fragments contain the form action and hidden fields. The
          // chosen ID is supplied below, so concatenating its empty slot is safe.
          final markup = RegExp(r'''(['"])(?:\\.|(?!\1)[\s\S])*?\1''')
              .allMatches(builder)
              .map((match) => match[0]!
                  .substring(1, match[0]!.length - 1)
                  .replaceAll(r'\"', '"')
                  .replaceAll(r"\'", "'"))
              .join();
          form = DiscuzForm.namedSubmit(markup, 'homesubmit');
          if (form != null) break;
        }
        if (form != null) break;
      }
    }
    return KlpHomeStyleCatalog(
        categories: List.unmodifiable(categories),
        items: List.unmodifiable(items),
        category: category,
        saveForm: _validForm(form, base) ? form : null,
        recognized: categories.isNotEmpty && categoryIds.contains(category));
  }

  static bool _validForm(DiscuzForm? form, Uri base) {
    if (form == null ||
        form.method != 'post' ||
        form.values['formhash']?.isNotEmpty != true ||
        form.values['homesubmit']?.isNotEmpty != true ||
        !form.values.containsKey('styleid')) {
      return false;
    }
    final action = base.resolve(form.action);
    return action.origin == base.origin &&
        action.path == base.resolve('plugin.php').path &&
        action.queryParameters['id'] == 'comiis_app_homestyle' &&
        action.queryParameters.keys.every(
            const {'id', 'mobile', 'smod', 'inajax', 'infloat'}.contains) &&
        form.values.keys
            .every(const {'formhash', 'homesubmit', 'styleid'}.contains);
  }

  Map<String, String>? saveValues(String id) =>
      saveForm != null && items.any((item) => item.id == id)
          ? {...saveForm!.values, 'styleid': id}
          : null;

  static String? _function(String source, String name) {
    final match =
        RegExp('function\\s+$name\\s*\\([^)]*\\)\\s*\\{').firstMatch(source);
    if (match == null) return null;
    var braces = 1, escape = false;
    String? quote;
    for (var i = match.end; i < source.length; i++) {
      final char = source[i];
      if (quote != null) {
        if (escape) {
          escape = false;
        } else if (char == r'\') {
          escape = true;
        } else if (char == quote) {
          quote = null;
        }
      } else if (const {"'", '"', '`'}.contains(char)) {
        quote = char;
      } else if (char == '{') {
        braces++;
      } else if (char == '}' && --braces == 0) {
        return source.substring(match.start, i + 1);
      }
    }
    return null;
  }
}
