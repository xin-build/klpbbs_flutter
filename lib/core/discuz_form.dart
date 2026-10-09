import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'discuz_control_policy.dart';

/// 使用网页实际提供的字段、当前值和提交地址，保留同一表单中未编辑的资料。
class DiscuzForm {
  final String action;
  final String method;
  final Map<String, String> values;
  final Set<String> editableNames;
  final Map<String, String> labels;
  final Map<String, Set<String>> allowedValues;
  final Set<String> checkboxNames;

  DiscuzForm._(
      this.action,
      this.method,
      Map<String, String> values,
      Set<String> editableNames,
      Map<String, String> labels,
      Map<String, Set<String>> allowedValues,
      Set<String> checkboxNames)
      : values = Map.unmodifiable(values),
        editableNames = Set.unmodifiable(editableNames),
        labels = Map.unmodifiable(labels),
        checkboxNames = Set.unmodifiable(checkboxNames),
        allowedValues = Map.unmodifiable({
          for (final entry in allowedValues.entries)
            entry.key: Set<String>.unmodifiable(entry.value),
        });

  static DiscuzForm? profile(String source) =>
      namedSubmit(source, 'profilesubmit');

  static DiscuzForm? namedSubmit(String source, String submitName) {
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source);
    final doc = html.parse(cdata?.group(1) ?? source);
    for (final form in doc.querySelectorAll('form')) {
      if (!form
              .querySelectorAll('[name]')
              .any((node) => node.attributes['name'] == submitName) ||
          form.querySelector('input[name="formhash"]') == null) {
        continue;
      }
      if (DiscuzControlPolicy.hasUnsupportedSubmission(form, doc)) continue;
      final values = <String, String>{};
      final editable = <String>{};
      final labels = <String, String>{};
      final choices = <String, Set<String>>{};
      final checkboxes = <String>{};
      for (final control in form.querySelectorAll(
          'input[name], select[name], textarea[name], button[name]')) {
        if (DiscuzControlPolicy.isDisabled(control)) continue;
        final name = control.attributes['name']!;
        final type = (control.attributes['type'] ?? 'text').toLowerCase();
        if (const {'file', 'password', 'reset', 'button'}.contains(type)) {
          continue;
        }
        if (control.localName == 'select') {
          final options = control
              .querySelectorAll('option')
              .where((option) => !DiscuzControlPolicy.isDisabled(option))
              .toList();
          if (options.isEmpty) continue;
          choices[name] = options
              .map((option) => option.attributes['value'] ?? option.text)
              .toSet();
          final selected = options
              .where((option) => option.attributes.containsKey('selected'));
          final chosen = selected.isEmpty ? options.first : selected.first;
          values[name] = chosen.attributes['value'] ?? chosen.text;
        } else if (control.localName == 'textarea') {
          values[name] = control.text;
        } else {
          if (const {'radio', 'checkbox'}.contains(type) &&
              !control.attributes.containsKey('checked')) {
            choices
                .putIfAbsent(name, () => <String>{})
                .add(control.attributes['value'] ?? 'on');
            if (type == 'checkbox') {
              checkboxes.add(name);
              choices[name]!.add('');
            }
            if (!control.attributes.containsKey('readonly')) editable.add(name);
            continue;
          }
          values[name] = control.attributes['value'] ??
              (const {'radio', 'checkbox'}.contains(type) ? 'on' : '');
          if (const {'radio', 'checkbox'}.contains(type)) {
            choices.putIfAbsent(name, () => <String>{}).add(values[name]!);
            if (type == 'checkbox') {
              checkboxes.add(name);
              choices[name]!.add('');
            }
          }
        }
        if (type != 'hidden' &&
            type != 'submit' &&
            control.localName != 'button' &&
            !control.attributes.containsKey('readonly')) {
          editable.add(name);
          final label = labelFor(control, form);
          if (label?.isNotEmpty == true) labels[name] = label!;
        }
      }
      if (values['formhash']?.isNotEmpty != true) continue;
      return DiscuzForm._(
          form.attributes['action'] ?? '',
          (form.attributes['method'] ?? 'get').toLowerCase(),
          values,
          editable,
          labels,
          choices,
          checkboxes);
    }
    return null;
  }

  static Element? rowFor(Element control, Element form) {
    for (Element? node = control.parent;
        node != null && node != form;
        node = node.parent) {
      if (const {'tr', 'li'}.contains(node.localName) ||
          node.classes.any(const {
            'klp-field',
            'klp-form-row',
            'k-field',
            'form-row',
            'form-group',
            'styli',
            'comiis_styli'
          }.contains)) {
        return node;
      }
    }
    return null;
  }

  static String? labelFor(Element control, Element form) {
    if (control.id.isNotEmpty) {
      final exact = form
          .querySelectorAll('label[for]')
          .where((label) => label.attributes['for'] == control.id);
      if (exact.isNotEmpty && exact.first.text.trim().isNotEmpty) {
        return exact.first.text.trim();
      }
    }
    final label = rowFor(control, form)?.querySelector(
        'th, .styli_tit, .tit, dt, .klp-field-label, .k-label, label');
    if (label == null) return null;
    final clone = label.clone(true);
    clone
        .querySelectorAll('input, select, textarea, button')
        .forEach((e) => e.remove());
    return clone.text.trim();
  }

  Map<String, String>? mergeEdits(Map<String, String> edits) {
    final data = {...values};
    for (final entry in edits.entries) {
      // 部分界面使用 signature 别名；标准 Discuz 表单字段为 sightml。
      final key = entry.key == 'signature' && editableNames.contains('sightml')
          ? 'sightml'
          : entry.key;
      if (!editableNames.contains(key)) {
        if (values[key] == entry.value) continue;
        return null;
      }
      // 生日的天数由网页脚本随年月生成，其他选项须在当前表单内有效。
      if (!const {'birthmonth', 'birthday'}.contains(key) &&
          allowedValues.containsKey(key) &&
          !allowedValues[key]!.contains(entry.value)) {
        return null;
      }
      if (checkboxNames.contains(key) && entry.value.isEmpty) {
        data.remove(key);
      } else {
        data[key] = entry.value;
      }
    }
    return data;
  }
}
