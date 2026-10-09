import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import '../models/forum_header_info.dart';

class DiscuzCreditRules {
  static const _actionLabels = {'动作名称', '行为', '操作'};
  static const _ruleLabels = {
    '周期范围',
    '奖励周期',
    '周期内最多奖励次数',
    '周期内奖励次数',
    '经验',
    '铁粒',
    '贡献',
    '火药',
    '钻石',
    '铁锭[已弃用]',
  };

  static String label(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').trim();
  static String _text(Element node) {
    final copy = node.clone(true);
    for (final child in copy.querySelectorAll('script, style')) {
      child.remove();
    }
    return copy.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<Element> _cells(Element row) => row.children
      .where((node) => const {'td', 'th'}.contains(node.localName))
      .toList();

  static Iterable<({Element table, Element header, List<String> labels})>
      _tables(String source) sync* {
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source);
    final document = html.parse(cdata?[1] ?? source);
    for (final table in document.querySelectorAll(
        'table.dt, table.creditrule, .creditrule table, #creditrule table, table#creditrule')) {
      for (final row in table.querySelectorAll('tr')) {
        final labels = _cells(row).map(_text).toList();
        final normalized = labels.map(label).toList();
        if (normalized.any(_actionLabels.contains) &&
            normalized.any(_ruleLabels.contains) &&
            normalized.toSet().length == normalized.length) {
          yield (table: table, header: row, labels: labels);
          break;
        }
      }
    }
  }

  /// An explicit table with its actual rule headers may be a valid empty list;
  /// an unrelated dt table or a missing page is not an empty rule contract.
  static bool recognized(String source) => _tables(source).isNotEmpty;

  static String _value(Map<String, String> values, Set<String> labels) {
    for (final entry in values.entries) {
      if (labels.contains(label(entry.key))) return entry.value;
    }
    return '';
  }

  /// Preserve all server column labels, including currencies that are absent
  /// from the legacy convenience fields. Missing values remain unknown.
  static List<ForumCreditRule> parse(String source) {
    final result = <ForumCreditRule>[];
    for (final contract in _tables(source)) {
      final actionIndex = contract.labels
          .indexWhere((value) => _actionLabels.contains(label(value)));
      var afterHeader = false;
      for (final row in contract.table.querySelectorAll('tr')) {
        if (identical(row, contract.header)) {
          afterHeader = true;
          continue;
        }
        if (!afterHeader) continue;
        final cells = _cells(row);
        if (cells.length <= actionIndex ||
            cells.length < 2 ||
            cells.any((cell) =>
                (int.tryParse(cell.attributes['colspan'] ?? '1') ?? 1) > 1)) {
          continue;
        }
        final action = _text(cells[actionIndex]);
        if (action.isEmpty || _actionLabels.contains(label(action))) continue;
        final values = <String, String>{
          for (var index = 0;
              index < contract.labels.length && index < cells.length;
              index++)
            if (contract.labels[index].isNotEmpty)
              contract.labels[index]: _text(cells[index]),
        };
        result.add(ForumCreditRule(
          action: _value(values, _actionLabels),
          cycle: _value(values, const {'周期范围', '奖励周期'}),
          maxDaily: _value(values, const {'周期内最多奖励次数', '周期内奖励次数'}),
          exp: _value(values, const {'经验'}),
          iron: _value(values, const {'铁粒'}),
          tribute: _value(values, const {'贡献'}),
          columns: Map.unmodifiable(values),
        ));
      }
    }
    return List.unmodifiable(result);
  }
}
