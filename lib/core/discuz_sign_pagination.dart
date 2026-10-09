import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// The rank table and its own pager are authoritative. A sign-page counter
/// can lag behind this list, and a missing pager is not proof of page 1.
class DiscuzSignPagination {
  final bool recognized;
  final int currentPage;
  final int? totalPages, nextPage;

  const DiscuzSignPagination({
    required this.recognized,
    required this.currentPage,
    this.totalPages,
    this.nextPage,
  });

  static String operation(String value) {
    final op = value.isEmpty || value == 'today'
        ? 'today'
        : value == 'reward'
            ? 'rewardlist'
            : value;
    if (!const {'today', 'month', 'zong', 'rewardlist'}.contains(op)) {
      throw ArgumentError('无效的签到排行分类');
    }
    return op;
  }

  static int pagesForCount(int count, {int pageSize = 10}) {
    if (count < 0 || pageSize < 1) throw ArgumentError('无效的排行数量');
    return count == 0 ? 1 : (count + pageSize - 1) ~/ pageSize;
  }

  static DiscuzSignPagination parse(
    String source, {
    required String op,
    required int requestedPage,
    required Uri base,
  }) {
    final operationName = operation(op);
    final payload =
        RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source)?[1] ?? source;
    final doc = html.parse(payload);
    doc
        .querySelectorAll('#hd, #ft, #nv, #toptb, .comiis_sidenv, '
            '.comiis_head, body > header, body > footer, script, style')
        .forEach((node) => node.remove());
    final restricted = doc.querySelector('#messagetext, #loginform, '
            'form[id^="loginform_"], .comiis_password_top, .alert_error') !=
        null;
    final table = doc.querySelectorAll('table').any((table) {
      final first = table.querySelector('tr');
      final labels = first?.children.map((cell) => cell.text.trim()).toSet() ??
          const <String>{};
      return labels.contains('昵称') &&
          (labels.contains('总天数') || labels.contains('总奖励'));
    });
    final recognized = !restricted &&
        (table ||
            doc.querySelector(
                    'tbody[id^="autolist_"], .comiis_sign_list, .k_misign_list, '
                    '.ranking_list, .sign_list') !=
                null);
    if (!recognized) {
      return DiscuzSignPagination(
          recognized: false, currentPage: requestedPage);
    }

    int? linkPage(Element link) {
      final raw = link.attributes['href'];
      if (raw == null || raw.isEmpty) return null;
      final Uri target;
      try {
        target = base.resolve(raw);
      } on FormatException {
        return null;
      }
      final q = target.queryParameters;
      final isSignPage = target.path.endsWith('/k_misign-sign.html') ||
          (target.path.endsWith('/plugin.php') && q['id'] == 'k_misign:sign');
      if (target.origin != base.origin ||
          !isSignPage ||
          q['operation'] != 'list' ||
          (q['op']?.isNotEmpty == true &&
              q['op'] != operationName &&
              !(operationName == 'rewardlist' && q['op'] == 'reward'))) {
        return null;
      }
      final page = int.tryParse(q['page'] ?? q['pp'] ?? '');
      return page != null && page > 0 ? page : null;
    }

    var current = requestedPage;
    int? total, next;
    for (final pager in doc.querySelectorAll('.pg, .comiis_page, .pages')) {
      final links = pager.querySelectorAll('a[href]');
      if (links.isNotEmpty && !links.any((link) => linkPage(link) != null)) {
        continue;
      }
      final selected = int.tryParse(
          pager.querySelector('strong, .current, .active')?.text.trim() ?? '');
      if (selected != null && selected > 0) current = selected;
      for (final node in pager.querySelectorAll('span[title], span')) {
        final declaration = '${node.attributes['title'] ?? ''} ${node.text}';
        final match = RegExp(r'(?:共|/)\s*(\d+)\s*页').firstMatch(declaration);
        final declared = int.tryParse(match?[1] ?? '');
        if (declared != null && declared > 0) total = declared;
      }
      for (final link in links) {
        final page = linkPage(link);
        if (page == null) continue;
        if (link.classes.contains('last')) total ??= page;
        if (link.classes.any((name) => const {'nxt', 'next'}.contains(name)) &&
            page > current) {
          next = page;
        }
      }
    }
    if (total != null && next != null && next > total) next = null;
    return DiscuzSignPagination(
        recognized: true,
        currentPage: current,
        totalPages: total,
        nextPage: next);
  }
}
