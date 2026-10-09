import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/credit_log.dart';

/// Balance fields are declarations, not computed totals or default currencies.
class DiscuzCreditBalance {
  DiscuzCreditBalance._();

  static String? amount(String value) =>
      RegExp(r'^\s*([+-]?\d[\d,]*)\s*(?:[a-zA-Z]+|[\u4e00-\u9fff]{1,4})?\s*$')
          .firstMatch(value)?[1]
          ?.replaceAll(',', '');

  /// Responsive profile grids declare balances separately from storage usage.
  /// Null means a legacy template needs its own fallback, not an empty balance.
  static Map<String, String>? profileValues(Document doc) {
    final desktop = doc.querySelectorAll('#ct .klp-statgrid > div');
    final mobile = doc.querySelectorAll('.comiis_space_profilejf li');
    if (desktop.isEmpty && mobile.isEmpty) return null;
    final values = <String, String>{};
    for (final row in [...desktop, ...mobile]) {
      final label =
          (row.querySelector('span:not(.f_0):not(.profile_rs), em')?.text ?? '')
              .split('·')
              .first
              .split('[')
              .first
              .replaceAll(RegExp(r'[:：]'), '')
              .trim();
      if (label.isEmpty || const {'已用空间', '空间使用', '存储空间'}.contains(label)) {
        continue;
      }
      final value = row.querySelector('b, .k-mono, .profile_rs, .f_0')?.text;
      final number = value == null ? null : amount(value);
      if (number != null) values[label] = number;
    }
    return values;
  }

  static CreditBaseInfo parse(String html) {
    String totalCredits = '';
    final details = <String, String>{};
    String? formula;

    final doc = html_parser.parse(html);

    // 彻底移除页眉、页脚、侧边栏、快捷菜单、导航栏等非内容 DOM
    doc
        .querySelectorAll(
          '#nv, #toptb, #hd, #ft, #comiis_head, .comiis_head, .comiis_header, '
          '#comiis_nav, .comiis_nav, .comiis_foot, .comiis_footer, .comiis_menu, '
          '.comiis_sidenv, .comiis_sidenv_box, .comiis_fmenu, .comiis_gobtn, '
          '.comiis_lrmenu, .comiis_loginbox, script, style, header, footer, '
          '#comiis_foot, #comiis_menu',
        )
        .forEach((e) => e.remove());

    // Current mobile balances declare the label in a span and the amount in
    // its sibling text. Preserve new currencies only when that row exists.
    for (final row in doc.querySelectorAll('.comiis_creditl li')) {
      final labelNode = row.querySelector('span, em, strong');
      if (labelNode == null) continue;
      final label = labelNode.text.replaceAll(RegExp(r'[:：]'), '').trim();
      final copy = row.clone(true);
      copy
          .querySelectorAll('span, em, strong')
          .forEach((node) => node.remove());
      final amount = RegExp(r'^\s*([+-]?[\d,]+)').firstMatch(copy.text)?[1];
      if (label.isNotEmpty && amount != null) {
        details[label] = amount.replaceAll(',', '');
      }
    }

    // 1. 结构化 DOM 遍历：查找含有积分标签的行或网格节点（避免直接正则文本导致缺失）
    for (final el in doc.querySelectorAll(
      'ul.creditl li, table.tfm tr, .comiis_p12 li, .comiis_jflist li, .comiis_credit li, .comiis_flex',
    )) {
      final labelEl = el.querySelector('em, th, span.dt, span.kmtit, strong');
      final label = (labelEl?.text ?? el.text)
          .replaceAll(':', '')
          .replaceAll('：', '')
          .trim();
      for (final creditName in [
        '铁粒',
        '经验',
        '铁锭[已弃用]',
        '铁锭',
        '贡献',
        '钻石',
        '人气',
        '威望',
        '金币',
        '金粒',
        '火药',
        '下界之星',
      ]) {
        if (creditName == '铁锭' && label.contains('铁锭[已弃用]')) continue;
        if (label.contains(creditName) && !details.containsKey(creditName)) {
          final valM = RegExp(r'([+-]?[\d,]+)')
              .firstMatch(el.text.replaceFirst(creditName, ''));
          if (valM != null) {
            details[creditName] = valM.group(1)!.replaceAll(',', '');
          }
        }
      }
    }

    final text =
        doc.querySelector('.comiis_credit_box, #ct .mn, .klp-cp-main')?.text ??
            doc.body?.text ??
            html;

    // 2. 顶部总积分（对应：积分: 6994）
    final totalM =
        RegExp(r'(?:总积分|积分)\s*[:：\s]*([+-]?[\d,]+)').firstMatch(text);
    if (totalM != null) {
      totalCredits = totalM.group(1)!.replaceAll(',', '');
    }

    // 3. 细项提取兜底（对应：铁粒:12805 粒、经验:6994 EP、铁锭[已弃用]:0 块、贡献:0 点、钻石:0 个）
    final matches = RegExp(
      r'(铁粒|经验|铁锭\[已弃用\]|铁锭|贡献|钻石|人气|威望|金币|金粒|火药|下界之星)\s*[:：\s]*([+-]?[\d,]+)\s*(?:粒|EP|块|点|个)?',
    ).allMatches(text);
    for (final m in matches) {
      final name = m.group(1)!;
      final val = m.group(2)!.replaceAll(',', '');
      if (!details.containsKey(name)) {
        details[name] = val;
      }
    }

    // 只有页面明确给出公式时才展示，经验与总积分不能互相代替。
    final formulaMatch = RegExp(r'总积分\s*=[^<\n]+').firstMatch(text);
    formula = formulaMatch?.group(0)?.trim();

    return CreditBaseInfo(
      totalCredits: totalCredits,
      details: details,
      ruleFormula: formula,
    );
  }
}
