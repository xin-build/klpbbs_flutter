import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Current KLPBBS twpx_xunsearch declarations, separate from Discuz forms.
class KlpSearchProtocol {
  KlpSearchProtocol._();

  static bool recognizes(String source) {
    final page = html.parse(source);
    return page.querySelector('.search-hero #q-input[name="q"]') != null &&
        page.querySelector('.sidebar select[name="f"]') != null &&
        page.querySelector('.sidebar select[name="s"]') != null;
  }

  static Uri request(
    String source, {
    required String keyword,
    String scope = 'title',
    String orderby = 'dateline',
    String direction = 'desc',
    List<int> fids = const [],
    int page = 1,
  }) {
    if (!recognizes(source)) throw const FormatException('未取得站点搜索表单');
    final doc = html.parse(source);
    final field = switch (scope) {
      'title' => 'subject',
      'fulltext' => '_all',
      'author' => 'author',
      _ => throw StateError('网站不支持此搜索范围'),
    };
    final sort = switch (orderby) {
      'relevance' => 'relevance',
      'dateline' => direction == 'asc' ? 'dateline_ASC' : 'dateline_DESC',
      _ => throw StateError('网站搜索接口不支持此排序，请使用相关性或发表时间'),
    };
    bool declares(String name, String value) => doc
        .querySelectorAll('select[name="$name"] option')
        .any((node) => node.attributes['value'] == value);
    if (!declares('f', field) || !declares('s', sort)) {
      throw StateError('网站当前未提供所选的搜索范围或排序');
    }
    final allowedFids = doc
        .querySelectorAll('input[name="fid[]"]')
        .map((node) => int.tryParse(node.attributes['value'] ?? ''))
        .whereType<int>()
        .toSet();
    if (fids.any((fid) => !allowedFids.contains(fid))) {
      throw StateError('所选版块不在网站当前可搜索的范围内');
    }
    final parameters = <String, dynamic>{
      'id': 'twpx_xunsearch',
      'mod': 'forum',
      'mobile': 'no',
      'q': keyword.trim(),
      'f': field,
      's': sort,
      'p': '${page < 1 ? 1 : page}',
      if (fids.isNotEmpty) 'fid[]': fids.map((fid) => '$fid').toSet().toList(),
    };
    for (final control in doc.querySelectorAll(
        '.sidebar input[name="m"], .sidebar input[name="syn"]')) {
      // Honor the page's current defaults; never invent checkbox values.
      parameters[control.attributes['name']!] =
          control.attributes.containsKey('checked')
              ? control.attributes['value'] ?? 'on'
              : '0';
    }
    return Uri(path: 'plugin.php', queryParameters: parameters);
  }

  static int pages(Document doc, int current) {
    var maximum = current;
    for (final link in doc
        .querySelectorAll('.pg a[href], .pagination a[href], .pager a[href], '
            '.pagination-wrap a[href]')) {
      final values = Uri.tryParse(link.attributes['href']!)?.queryParameters;
      final value = int.tryParse(values?['p'] ?? values?['page'] ?? '');
      if (value != null && value > maximum) maximum = value;
    }
    final declaredMax = int.tryParse(
        doc.querySelector('.pagination-wrap input[max]')?.attributes['max'] ??
            '');
    if (declaredMax != null && declaredMax > maximum) maximum = declaredMax;
    return maximum;
  }
}
