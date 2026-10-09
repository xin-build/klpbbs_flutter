import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'discuz_response.dart';

typedef DiscuzReport = ({
  int id,
  String url,
  String message,
  String uName,
  String dateline
});

class DiscuzModcp {
  static List<DiscuzReport> reports(String source) {
    final doc = html.parse(source);
    final form = doc.querySelector('#reportform');
    if (form == null) {
      final content = doc.querySelector('.modcp, #ct .mn, #ct')?.text ?? '';
      if (RegExp(r'没有.*举报|暂无.*举报|无.*举报|没有.*报告').hasMatch(content) &&
          doc.querySelector(
                  'input[name="reportsubmit"], input[name="password"]') ==
              null) {
        return const [];
      }
      throw FormatException(
          DiscuzResponse.message(source) ?? '管理中心需要验证，或当前用户组没有举报处理权限');
    }
    final result = <DiscuzReport>[];
    for (final row in form.querySelectorAll('tr')) {
      final id = int.tryParse(
          row.querySelector('input[name="reportids[]"]')?.attributes['value'] ??
              '');
      if (id == null || id <= 0) continue;
      final target = row.querySelector('a[target="_blank"]');
      final user =
          row.querySelector('a[href*="mod=space"], a[href*="space-uid-"]');
      // html's nth-child implementation counts whitespace text nodes. Use the
      // actual cell order so indented and compressed forum templates agree.
      final cells =
          row.children.where((cell) => cell.localName == 'td').toList();
      final content = cells.length > 1 ? cells[1].clone(true) : null;
      for (final br in content?.querySelectorAll('br') ?? <Element>[]) {
        br.replaceWith(Text('\n'));
      }
      final text = content?.text ?? '';
      result.add((
        id: id,
        url: target?.attributes['href'] ?? '',
        uName: user?.text.trim() ?? '',
        message: RegExp(r'(?:举报理由|举报原因|理由|原因)[：:]\s*([^\n]+)')
                .firstMatch(text)
                ?.group(1)
                ?.trim() ??
            text.trim(),
        dateline: RegExp(r'(\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?)')
                .firstMatch(text)
                ?.group(1) ??
            ''
      ));
    }
    return result;
  }
}
