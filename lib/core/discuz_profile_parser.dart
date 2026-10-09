import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'discuz_form.dart';
import 'discuz_control_policy.dart';

/// 表单是字段、隐私选项和可编辑状态的唯一来源。
class DiscuzProfileParser {
  static Map<String, dynamic> parse(String source) {
    final contract = DiscuzForm.profile(source);
    if (contract == null) throw const FormatException('资料编辑表单不可用');
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source);
    final document = html.parse(cdata?.group(1) ?? source);
    final form = document.querySelectorAll('form').firstWhere((element) =>
        element.querySelector('[name="profilesubmit"]') != null &&
        element.querySelector('[name="formhash"]') != null);
    final items = <Map<String, dynamic>>[];
    final seen = <String>{};
    final fieldLabels = <String, String>{};
    final customFields = <String, String>{};
    final privacy = <String, String>{};

    List<Map<String, String>> options(Element select) {
      final unique = <String, Map<String, String>>{};
      for (final option in select.querySelectorAll('option')) {
        if (DiscuzControlPolicy.isDisabled(option)) continue;
        final value = option.attributes['value'] ?? option.text;
        unique.putIfAbsent(
            value, () => {'value': value, 'label': option.text.trim()});
      }
      return unique.values.toList();
    }

    for (final control
        in form.querySelectorAll('input[name], textarea[name], select[name]')) {
      final name = control.attributes['name']!;
      final inputType = (control.attributes['type'] ?? 'text').toLowerCase();
      if (DiscuzControlPolicy.isDisabled(control) ||
          const {'hidden', 'submit', 'button', 'reset', 'password', 'file'}
              .contains(inputType) ||
          name.startsWith('privacy[') ||
          !seen.add(name)) {
        continue;
      }
      if (const {'birthmonth', 'birthday'}.contains(name) &&
          form.querySelector('[name="birthyear"]') != null) {
        continue;
      }
      final expectedPrivacy =
          'privacy[${name == 'birthyear' ? 'birthday' : name}]';
      final exactPrivacy = form.querySelectorAll('select[name]').where((e) =>
          e.attributes['name'] == expectedPrivacy &&
          !DiscuzControlPolicy.isDisabled(e));
      // 相邻字段共用一行时，也只绑定当前字段自己的隐私控件。
      final privacySelect = exactPrivacy.isNotEmpty ? exactPrivacy.first : null;
      final privacyName = privacySelect?.attributes['name'] ?? '';
      final privacyValue = contract.values[privacyName] ?? '';
      if (privacyName.isNotEmpty) privacy[privacyName] = privacyValue;
      final title = (DiscuzForm.labelFor(control, form) ??
              contract.labels[name] ??
              control.attributes['placeholder'] ??
              name)
          .replaceAll(RegExp(r'[\s*：:]+'), ' ')
          .trim();
      final value = contract.values[name] ?? '';
      fieldLabels[name] = title;
      if (name.startsWith('field')) customFields[name] = value;
      var type = control.localName == 'textarea' ? 'textarea' : 'text';
      var fieldName = name;
      if (control.localName == 'select') type = 'select';
      if (inputType == 'radio') type = 'choice';
      if (inputType == 'checkbox') type = 'checkbox';
      if (name == 'gender') type = 'gender';
      if (name == 'birthyear') {
        type = 'birthday';
        fieldName = 'birthday';
      }
      if (name == 'email') type = 'email';
      items.add({
        'name': fieldName,
        'label': title,
        'value': value,
        'type': type,
        'readOnly': !contract.editableNames.contains(name) ||
            (inputType == 'checkbox' &&
                form
                        .querySelectorAll('input[name]')
                        .where((e) => e.attributes['name'] == name)
                        .length >
                    1),
        'maxLength': switch (
            int.tryParse(control.attributes['maxlength'] ?? '')) {
          final int length when length > 0 => length,
          _ => null,
        },
        'required': control.attributes.containsKey('required'),
        'hasPrivacy': privacySelect != null,
        'privacyName': privacyName,
        'privacyValue': privacyValue,
        'privacyOptions': privacySelect == null
            ? <Map<String, String>>[]
            : options(privacySelect),
        'options': control.localName == 'select'
            ? options(control)
            : const {'radio', 'checkbox'}.contains(inputType)
                ? form
                    .querySelectorAll('input[name]')
                    .where((e) =>
                        e.attributes['name'] == name &&
                        !DiscuzControlPolicy.isDisabled(e))
                    .map((e) => {
                          'value': e.attributes['value'] ?? 'on',
                          'label': (e.parent?.localName == 'label'
                                  ? e.parent?.text.trim()
                                  : DiscuzForm.labelFor(e, form)) ??
                              e.attributes['value'] ??
                              '选中'
                        })
                    .toList()
                : <Map<String, String>>[],
        if (type == 'birthday') ...{
          'birthYear': int.tryParse(contract.values['birthyear'] ?? ''),
          'birthMonth': int.tryParse(contract.values['birthmonth'] ?? ''),
          'birthDay': int.tryParse(contract.values['birthday'] ?? ''),
          'birthYearOptions': options(control),
          'birthMonthOptions':
              form.querySelector('select[name="birthmonth"]') == null
                  ? <Map<String, String>>[]
                  : options(form.querySelector('select[name="birthmonth"]')!),
          'birthDayOptions':
              form.querySelector('select[name="birthday"]') == null
                  ? <Map<String, String>>[]
                  : options(form.querySelector('select[name="birthday"]')!),
        },
      });
    }
    return {
      'formhash': contract.values['formhash'],
      'formAction': contract.action,
      'signature':
          contract.values['sightml'] ?? contract.values['signature'] ?? '',
      'customStatus': contract.values['customstatus'] ?? '',
      'realname': contract.values['realname'] ?? '',
      'gender': int.tryParse(contract.values['gender'] ?? ''),
      'birthYear': int.tryParse(contract.values['birthyear'] ?? ''),
      'birthMonth': int.tryParse(contract.values['birthmonth'] ?? ''),
      'birthDay': int.tryParse(contract.values['birthday'] ?? ''),
      'email': contract.values['email'] ?? '',
      'customFields': customFields,
      'fieldPrivacy': privacy,
      'fieldLabels': fieldLabels,
      'items': items,
    };
  }
}
