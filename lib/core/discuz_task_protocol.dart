import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

typedef DiscuzTaskSummary = ({int id, String name, String reward});

class DiscuzTaskProtocol {
  static const categories = {'new', 'doing', 'done', 'failed'};
  static dom.Element? _root(dom.Document doc) =>
      doc.querySelector('#klp-task-box, .comiis_task_box, .comiis_task_list, '
          '#ct .mn .bm, .klp-cp-main');

  static bool recognizes(String source, String category) {
    final doc = html.parse(source);
    if (doc.querySelector('#messagetext, .alert_error, #loginform, '
            'form[id^="loginform_"]') !=
        null) {
      return false;
    }
    if (!categories.contains(category)) return false;
    for (final link
        in doc.querySelectorAll('#klp-task-box .klp-tasks-tabs a.on, '
            '#ct .appl li.a a, '
            '.klp-cp-main .k-seg.on, .comiis_topnv li.f_0 a')) {
      final query =
          Uri.tryParse(link.attributes['href'] ?? '')?.queryParameters;
      if (query?['mod'] == 'task' && query?['item'] != category) return false;
    }
    final root = _root(doc);
    return root != null &&
        (root.querySelector(
                    '.klp-tasks-empty, .emp, .task-empty, .comiis_notip') !=
                null ||
            parse(source).isNotEmpty);
  }

  static List<DiscuzTaskSummary> parse(String source) {
    final doc = html.parse(source);
    doc
        .querySelectorAll('#hd, #ft, #nv, header, footer, script, style, '
            '.comiis_head, .comiis_footer, .comiis_sidenv')
        .forEach((node) => node.remove());
    if (doc.querySelector('#messagetext, .alert_error, #loginform') != null) {
      return const [];
    }
    final result = <DiscuzTaskSummary>[];
    final seen = <int>{};
    final root = _root(doc) ?? doc.body;
    for (final link in root?.querySelectorAll('a[href]') ?? <dom.Element>[]) {
      final q = Uri.tryParse(link.attributes['href'] ?? '')?.queryParameters;
      final id = int.tryParse(q?['id'] ?? '');
      if (q?['mod'] != 'task' || q?['do'] != 'view' || id == null || id <= 0) {
        continue;
      }
      final name = link.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (name.isEmpty ||
          RegExp(r'^\d+$').hasMatch(name) ||
          const {'查看', '详情', '申请任务', '领取奖励'}.contains(name) ||
          !seen.add(id)) {
        continue;
      }
      var row = link.parent;
      while (row?.parent != null &&
          !const {'tr', 'li'}.contains(row!.localName) &&
          !row.classes.contains('task-item')) {
        row = row.parent;
      }
      var reward = '';
      if (row != null) {
        final value = row.querySelector(
            '.klp-task-prize, .klp-task-reward, td.xi1, .task-reward, .reward, .ntc_bodys, .f_d.f12');
        reward = value?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      }
      result.add((id: id, name: name, reward: reward));
    }
    return result;
  }
}
