import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'discuz_request_policy.dart';
import 'discuz_response.dart';
import 'discuz_avatar_protocol.dart';
import 'discuz_control_policy.dart';
import 'discuz_permission_cell.dart';
import 'discuz_usergroup_parser.dart';
import 'discuz_forum_parser.dart';

enum DiscuzFieldKind {
  text,
  password,
  number,
  email,
  date,
  multiline,
  select,
  radio,
  checkbox,
  file
}

class DiscuzChoice {
  final String value, label;
  const DiscuzChoice(this.value, this.label);
}

class DiscuzNativeField {
  final String name, label;
  final DiscuzFieldKind kind;
  final List<String> initialValues;
  final List<DiscuzChoice> choices;
  final bool required, readOnly, multiple;
  final int? minLength, maxLength;
  final double? minimum, maximum;
  final String? pattern, accept;
  DiscuzNativeField({
    required this.name,
    required this.label,
    required this.kind,
    List<String> initialValues = const [],
    List<DiscuzChoice> choices = const [],
    this.required = false,
    this.readOnly = false,
    this.multiple = false,
    this.minLength,
    this.maxLength,
    this.minimum,
    this.maximum,
    this.pattern,
    this.accept,
  })  : initialValues = List.unmodifiable(initialValues),
        choices = List.unmodifiable(choices);

  String? validate(List<String> values) {
    if (required &&
        (values.isEmpty || values.every((value) => value.trim().isEmpty))) {
      return '请填写$label';
    }
    if (!multiple && values.length > 1) return '$label只能选择一项';
    if (choices.isNotEmpty &&
        values
            .any((value) => !choices.any((choice) => choice.value == value))) {
      return '$label的选项已变化，请刷新';
    }
    for (final value in values) {
      if (value.isNotEmpty && minLength != null && value.length < minLength!) {
        return '$label至少 $minLength 个字符';
      }
      // HTML minlength/maxlength count UTF-16 code units, including emoji.
      if (maxLength != null && value.length > maxLength!) {
        return '$label最多 $maxLength 个字符';
      }
      if (kind == DiscuzFieldKind.number && value.isNotEmpty) {
        final number = double.tryParse(value);
        if (number == null ||
            !number.isFinite ||
            (name == 'days' && number % 1 != 0) ||
            (minimum != null && number < minimum!) ||
            (maximum != null && number > maximum!)) {
          return '$label不在允许范围内';
        }
      }
      if (pattern?.isNotEmpty == true && value.isNotEmpty) {
        try {
          if (!RegExp('^(?:$pattern)\$').hasMatch(value)) {
            return '$label格式不符合要求';
          }
        } on FormatException {
          // 浏览器扩展正则由服务端最终校验。
        }
      }
    }
    return null;
  }

  bool acceptsFileName(String filename) {
    if (accept == null || accept!.trim().isEmpty) return true;
    final extension = filename.toLowerCase().split('.').last;
    const image = {'gif', 'png', 'apng', 'jpg', 'jpeg', 'webp', 'bmp', 'avif'};
    const types = {
      'image/gif': {'gif'},
      'image/png': {'png', 'apng'},
      'image/apng': {'apng', 'png'},
      'image/jpeg': {'jpg', 'jpeg'},
      'image/webp': {'webp'},
      'application/pdf': {'pdf'},
      'video/mp4': {'mp4'},
      'audio/mpeg': {'mp3'},
    };
    return accept!.toLowerCase().split(',').any((entry) {
      final type = entry.trim();
      if (type == '*/*') return true;
      if (type.startsWith('.')) return extension == type.substring(1);
      if (type == 'image/*') return image.contains(extension);
      if (types.containsKey(type)) return types[type]!.contains(extension);
      // 不认识的媒体类型交给网站校验，不猜测扩展名。
      return true;
    });
  }
}

class DiscuzSubmitButton {
  final String key, label;
  final String? name;
  final String value;
  const DiscuzSubmitButton(
      {required this.key, required this.label, this.name, this.value = ''});
}

class DiscuzNativeForm {
  final String key, title, description, method, enctype;
  final String captchaHash, captchaModid;
  final double? unitPrice;
  final String priceUnit, quantityField;
  final Uri action;
  final List<DiscuzNativeField> fields;
  final List<DiscuzSubmitButton> buttons;
  final List<MapEntry<String, String>> hiddenValues;
  DiscuzNativeForm({
    required this.key,
    required this.title,
    required this.description,
    required this.action,
    required this.method,
    required this.enctype,
    required List<DiscuzNativeField> fields,
    required List<DiscuzSubmitButton> buttons,
    required List<MapEntry<String, String>> hiddenValues,
    this.captchaHash = '',
    this.captchaModid = '',
    this.unitPrice,
    this.priceUnit = '',
    this.quantityField = '',
  })  : fields = List.unmodifiable(fields),
        buttons = List.unmodifiable(buttons),
        hiddenValues = List.unmodifiable(hiddenValues);

  bool get hasCsrf => hiddenValues
      .any((entry) => entry.key == 'formhash' && entry.value.isNotEmpty);
  bool get hasFiles =>
      fields.any((field) => field.kind == DiscuzFieldKind.file);
  bool get hasCaptcha => fields.any(
      (field) => const {'seccodeverify', 'secanswer'}.contains(field.name));
  String hidden(String name) =>
      hiddenValues.where((entry) => entry.key == name).lastOrNull?.value ?? '';

  double? totalPrice(Map<String, List<String>> values) {
    final quantity = double.tryParse(values[quantityField]?.firstOrNull ?? '');
    return unitPrice == null ||
            quantity == null ||
            !quantity.isFinite ||
            quantity < 0
        ? null
        : unitPrice! * quantity;
  }

  /// 成功控件规则：未选复选框不发送，重复名称保留，密码不从网页回填。
  List<MapEntry<String, String>> submission(
      Map<String, List<String>> edits, String buttonKey) {
    final button =
        buttons.where((button) => button.key == buttonKey).firstOrNull;
    if (button == null) throw const FormatException('提交操作已变化，请刷新');
    final known = fields.map((field) => field.name).toSet();
    if (edits.keys.any((name) => !known.contains(name))) {
      throw const FormatException('不能修改当前表单未提供的字段');
    }
    final values = [...hiddenValues];
    for (final field in fields) {
      if (field.kind == DiscuzFieldKind.file) continue;
      final supplied = edits[field.name] ?? field.initialValues;
      if (field.readOnly && !_sameValues(supplied, field.initialValues)) {
        throw FormatException('${field.label}不能修改');
      }
      final invalid = field.validate(supplied);
      if (invalid != null) throw FormatException(invalid);
      for (final value in supplied) {
        values.add(MapEntry(field.name, value));
      }
    }
    if (button.name?.isNotEmpty == true) {
      // 点击的具名按钮应位于同名默认值之后，符合 PHP 表单最后值规则。
      values.add(MapEntry(button.name!, button.value));
    }
    return values;
  }

  /// A refreshed CSRF value can rotate; the operation and visible contract
  /// must still match what the user reviewed.
  bool sameContractAs(DiscuzNativeForm other) {
    if (key != other.key ||
        action != other.action ||
        method != other.method ||
        enctype != other.enctype ||
        title != other.title ||
        description != other.description ||
        unitPrice != other.unitPrice ||
        priceUnit != other.priceUnit ||
        quantityField != other.quantityField ||
        fields.length != other.fields.length ||
        buttons.length != other.buttons.length) {
      return false;
    }
    for (var index = 0; index < fields.length; index++) {
      final a = fields[index], b = other.fields[index];
      if (a.name != b.name ||
          a.label != b.label ||
          a.kind != b.kind ||
          a.required != b.required ||
          a.readOnly != b.readOnly ||
          a.multiple != b.multiple ||
          a.minLength != b.minLength ||
          a.maxLength != b.maxLength ||
          a.minimum != b.minimum ||
          a.maximum != b.maximum ||
          a.pattern != b.pattern ||
          a.accept != b.accept ||
          !_sameValues(a.initialValues, b.initialValues) ||
          a.choices.length != b.choices.length) {
        return false;
      }
      for (var option = 0; option < a.choices.length; option++) {
        if (a.choices[option].value != b.choices[option].value ||
            a.choices[option].label != b.choices[option].label) {
          return false;
        }
      }
    }
    for (var index = 0; index < buttons.length; index++) {
      final a = buttons[index], b = other.buttons[index];
      if (a.key != b.key ||
          a.name != b.name ||
          a.value != b.value ||
          a.label != b.label) {
        return false;
      }
    }
    final a = hiddenValues.where((entry) => entry.key != 'formhash').toList();
    final b =
        other.hiddenValues.where((entry) => entry.key != 'formhash').toList();
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].key != b[index].key || a[index].value != b[index].value) {
        return false;
      }
    }
    return true;
  }

  static bool _sameValues(List<String> a, List<String> b) =>
      a.length == b.length &&
      List.generate(a.length, (index) => a[index] == b[index])
          .every((equal) => equal);
  static String encode(Iterable<MapEntry<String, String>> pairs) => pairs
      .map((entry) =>
          '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
      .join('&');
}

enum DiscuzLinkKind { navigation, pagination, content, action }

class DiscuzPageLink {
  final String label;
  final Uri uri;
  final bool changesData;
  final DiscuzLinkKind kind;
  const DiscuzPageLink(this.label, this.uri,
      {this.changesData = false, this.kind = DiscuzLinkKind.navigation});
}

class DiscuzDataTable {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final Map<int, DiscuzPageLink> rowLinks;
  DiscuzDataTable(this.title, List<String> headers, List<List<String>> rows,
      {Map<int, DiscuzPageLink> rowLinks = const {}})
      : headers = List.unmodifiable(headers),
        rowLinks = Map.unmodifiable(rowLinks),
        rows = List.unmodifiable(
            rows.map((row) => List<String>.unmodifiable(row)));
}

class DiscuzPageImage {
  final Uri uri;
  final String label;
  const DiscuzPageImage(this.uri, this.label);
}

/// 仅提取数据与声明式表单；不执行网页脚本，也不承接网站的布局样式。
class DiscuzNativePage {
  final Uri uri;
  final List<DiscuzNativeForm> forms;
  final List<DiscuzPageLink> links;

  /// Actions declared in the comparison header, kept with that comparison.
  final List<DiscuzPageLink> headerActions;
  final List<DiscuzDataTable> tables;
  final List<String> information;
  final List<DiscuzPageImage> images;
  final String? message;
  final String? emptyTitle, emptyDescription;
  final bool requiresLogin, avatarPage, hasFlashAvatar;
  final DiscuzAvatarDescriptor? avatarDescriptor;
  DiscuzNativePage({
    required this.uri,
    List<DiscuzNativeForm> forms = const [],
    List<DiscuzPageLink> links = const [],
    List<DiscuzPageLink> headerActions = const [],
    List<DiscuzDataTable> tables = const [],
    List<String> information = const [],
    List<DiscuzPageImage> images = const [],
    this.message,
    this.emptyTitle,
    this.emptyDescription,
    this.requiresLogin = false,
    this.avatarPage = false,
    this.hasFlashAvatar = false,
    this.avatarDescriptor,
  })  : forms = List.unmodifiable(forms),
        links = List.unmodifiable(links),
        headerActions = List.unmodifiable(headerActions),
        tables = List.unmodifiable(tables),
        information = List.unmodifiable(information),
        images = List.unmodifiable(images);

  static bool changesData(Uri target) {
    final parameters = target.queryParameters;
    if (target.path.endsWith('search.php')) return false;
    if (parameters['operation'] == 'qiandao' ||
        parameters['action'] == 'logout' ||
        parameters['action'] == 'deleteattach') {
      return true;
    }
    return parameters.containsKey('formhash') &&
        (const {
              'delete',
              'del',
              'clear',
              'apply',
              'draw',
              'cancel',
              'switch',
              'exit',
              'ignore',
              'receive',
              'buy',
              'give',
              'use',
              'send',
              'add',
              'accept'
            }.any((operation) => [
                  parameters['action'],
                  parameters['operation'],
                  parameters['do'],
                  parameters['op']
                ].contains(operation)) ||
            parameters.keys
                .any((name) => name.toLowerCase().endsWith('submit')));
  }

  static bool _visible(Element node) {
    Element? ancestor = node;
    while (ancestor != null) {
      if (ancestor.attributes.containsKey('hidden') ||
          ancestor.attributes['aria-hidden'] == 'true' ||
          RegExp(r'display\s*:\s*none|visibility\s*:\s*hidden',
                  caseSensitive: false)
              .hasMatch(ancestor.attributes['style'] ?? '')) {
        return false;
      }
      ancestor = ancestor.parent;
    }
    return true;
  }

  static bool _disabled(Element node) {
    if (node.attributes.containsKey('disabled')) return true;
    Element? ancestor = node.parent;
    while (ancestor != null) {
      if ((ancestor.localName == 'fieldset' ||
              ancestor.localName == 'optgroup') &&
          ancestor.attributes.containsKey('disabled')) {
        return true;
      }
      ancestor = ancestor.parent;
    }
    return false;
  }

  static String _text(Element element) => DiscuzPermissionCell.text(element);

  static bool _within(Element element, String className) {
    Element? parent = element;
    while (parent != null) {
      if (parent.classes.contains(className)) return true;
      parent = parent.parent;
    }
    return false;
  }

  static String _label(Element control, Element form, Document document) {
    final id = control.id;
    final explicit = document
        .querySelectorAll('label[for]')
        .where((node) => id.isNotEmpty && node.attributes['for'] == id)
        .firstOrNull;
    if (explicit != null && _text(explicit).isNotEmpty) return _text(explicit);
    Element? node = control.parent;
    while (node != null && node != form) {
      if (node.localName == 'label' && _text(node).isNotEmpty) {
        return _text(node);
      }
      if (const {'tr', 'li', 'dl'}.contains(node.localName)) {
        final heading = node.querySelector('th, .styli_tit, .tit, dt, label');
        final text = heading == null ? _text(node) : _text(heading);
        if (text.isNotEmpty) {
          return text.length > 150 ? text.substring(0, 150) : text;
        }
      }
      node = node.parent;
    }
    return control.attributes['aria-label'] ??
        control.attributes['placeholder'] ??
        const {
          'magicnum': '数量',
          'tousername': '接收用户名',
          'givemessage': '赠送留言',
          'tid': '主题 ID',
          'pid': '回复 ID',
          'bid': '签到记录 ID',
          'newusername': '新用户名',
          'oldpassword': '当前密码',
          'newpassword': '新密码',
          'newpassword2': '确认新密码',
          'password': '密码',
          'email': '邮箱',
          'questionidnew': '安全提问',
          'answernew': '安全答案',
          'seccodeverify': '验证码',
          'secanswer': '验证问题答案',
          'days': '购买天数',
          'reason': '处理原因',
          'message': '内容',
          'username': '用户名',
          'searchsubmit': '查询',
        }[control.attributes['name']] ??
        control.attributes['name'] ??
        '';
  }

  static DiscuzNativePage parse(String source, Uri uri,
      {bool avatarReadOnly = false}) {
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source);
    final payload = cdata?.group(1) ?? source;
    final document = html.parse(payload);
    final root = document.querySelector('.klp-cp-main') ??
        document.querySelector('.klp-cp-card') ??
        document.querySelector(
            '#ct .mn, #ct, #main, .comiis_spacecp, .comiis_magic') ??
        document.body!;
    final login =
        document.querySelector('#loginform, form[name="login"]') != null ||
            RegExp(r'请先登录|尚未登录').hasMatch(DiscuzResponse.message(source) ?? '');
    final avatar = avatarReadOnly ||
        uri.queryParameters['ac'] == 'avatar' ||
        const {'saya_avatarverify:index', 'uploadavatarpc:avatar'}
            .contains(uri.queryParameters['id']) ||
        document.querySelector('input[name="avatar1"]') != null;
    final forms = <DiscuzNativeForm>[];
    var unsupportedSubmission = false;
    for (final form in root.querySelectorAll('form')) {
      if (!_visible(form) ||
          const {'scbar_form', 'lsform', 'loginform'}.contains(form.id)) {
        continue;
      }
      final action = uri.resolve(form.attributes['action'] ?? '');
      if (!const {'http', 'https'}.contains(action.scheme) ||
          !DiscuzRequestPolicy.sameOrigin(uri, action)) {
        continue;
      }
      if (DiscuzControlPolicy.hasUnsupportedSubmission(form, document)) {
        unsupportedSubmission = true;
        continue;
      }
      final fields = <DiscuzNativeField>[];
      final hidden = <MapEntry<String, String>>[];
      final buttons = <DiscuzSubmitButton>[];
      final controls = form.querySelectorAll('input, select, textarea, button');
      for (final control in controls) {
        if (_disabled(control)) continue;
        final name = control.attributes['name'] ?? '';
        final type = (control.attributes['type'] ??
                (control.localName == 'button' ? 'submit' : 'text'))
            .toLowerCase();
        if (type == 'hidden') {
          if (name.isNotEmpty) {
            hidden.add(MapEntry(name, control.attributes['value'] ?? ''));
          }
          continue;
        }
        if (!_visible(control) ||
            const {'reset', 'button', 'image'}.contains(type)) {
          continue;
        }
        if (type == 'submit') {
          final label = control.localName == 'button'
              ? _text(control)
              : control.attributes['value'] ?? '';
          buttons.add(DiscuzSubmitButton(
            key: '${name.isEmpty ? "submit" : name}:${buttons.length}',
            name: name.isEmpty ? null : name,
            value: control.attributes['value'] ?? '',
            label: label.isEmpty ? '提交' : label,
          ));
          continue;
        }
        if (name.isEmpty) continue;
        final membershipDays =
            name == 'days' && action.queryParameters['ac'] == 'usergroup';
        final kind = membershipDays
            ? DiscuzFieldKind.number
            : control.localName == 'textarea'
                ? DiscuzFieldKind.multiline
                : control.localName == 'select'
                    ? DiscuzFieldKind.select
                    : switch (type) {
                        'password' => DiscuzFieldKind.password,
                        'number' => DiscuzFieldKind.number,
                        'email' => DiscuzFieldKind.email,
                        'date' => DiscuzFieldKind.date,
                        'radio' => DiscuzFieldKind.radio,
                        'checkbox' => DiscuzFieldKind.checkbox,
                        'file' => DiscuzFieldKind.file,
                        _ => DiscuzFieldKind.text,
                      };
        if (fields.any((field) => field.name == name)) continue;
        final grouped = controls
            .where((node) =>
                node.attributes['name'] == name &&
                !_disabled(node) &&
                (node.attributes['type'] ?? '').toLowerCase() == type &&
                _visible(node))
            .toList();
        final choices = <DiscuzChoice>[];
        final selected = <String>[];
        final multiple = control.attributes.containsKey('multiple') ||
            kind == DiscuzFieldKind.checkbox;
        if (kind == DiscuzFieldKind.select) {
          final options = control
              .querySelectorAll('option')
              .where((option) => !_disabled(option))
              .toList();
          for (final option in options) {
            final value = option.attributes['value'] ?? option.text;
            choices.add(DiscuzChoice(value, option.text.trim()));
            if (option.attributes.containsKey('selected')) selected.add(value);
          }
          if (selected.isEmpty && !multiple && choices.isNotEmpty) {
            selected.add(choices.first.value);
          }
        } else if (kind == DiscuzFieldKind.radio ||
            kind == DiscuzFieldKind.checkbox) {
          for (final option in grouped) {
            final value = option.attributes['value'] ?? 'on';
            choices.add(DiscuzChoice(value, _label(option, form, document)));
            if (option.attributes.containsKey('checked')) selected.add(value);
          }
        } else if (kind != DiscuzFieldKind.file) {
          selected.add(kind == DiscuzFieldKind.password
              ? ''
              : kind == DiscuzFieldKind.multiline
                  ? control.text
                  : control.attributes['value'] ?? '');
        }
        fields.add(DiscuzNativeField(
          name: name,
          label: _label(control, form, document),
          kind: kind,
          initialValues: selected,
          choices: choices,
          multiple: multiple,
          readOnly: control.attributes.containsKey('readonly'),
          required: membershipDays ||
              control.attributes.containsKey('required') ||
              grouped.any((node) => node.attributes.containsKey('required')),
          minLength: int.tryParse(control.attributes['minlength'] ?? ''),
          maxLength: int.tryParse(control.attributes['maxlength'] ?? ''),
          minimum: membershipDays
              ? double.tryParse(control.attributes['min'] ??
                  control.attributes['value'] ??
                  '1')
              : double.tryParse(control.attributes['min'] ?? ''),
          maximum: double.tryParse(control.attributes['max'] ?? ''),
          pattern: control.attributes['pattern'],
          accept: control.attributes['accept'],
        ));
      }
      if (fields.isEmpty && buttons.isEmpty) continue;
      // KLPBBS renders a Save button even when no verification type is open.
      // It is not a usable application form without editable fields.
      if (uri.queryParameters['ac'] == 'profile' &&
          uri.queryParameters['op'] == 'verify' &&
          fields.every((field) => field.readOnly)) {
        continue;
      }
      final heading = form.querySelector('h1, h2, h3, .flb em, legend');
      final description = _text(form);
      final captcha = RegExp(
              r'''updateseccode\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*['"]([^'"]*)['"])?''')
          .firstMatch(form.outerHtml);
      final captchaHash = hidden
              .where((entry) => entry.key == 'seccodehash')
              .lastOrNull
              ?.value ??
          captcha?[1] ??
          '';
      final captchaModid = hidden
              .where((entry) => entry.key == 'seccodemodid')
              .lastOrNull
              ?.value ??
          captcha?[2] ??
          '';
      final priceMatch = action.queryParameters['ac'] == 'usergroup' &&
              fields.any((field) => field.name == 'days')
          ? RegExp(r'\bvar\s+dailyprice\s*=\s*(\d+(?:\.\d+)?)\s*;')
              .firstMatch(form.innerHtml)
          : null;
      var priceUnit = '';
      for (final row in form.querySelectorAll('tr')) {
        final cells = row.children
            .where((cell) => const {'td', 'th'}.contains(cell.localName))
            .toList();
        if (cells.length >= 2 &&
            RegExp(r'每日价格|购买价格').hasMatch(_text(cells.first))) {
          priceUnit =
              _text(cells[1]).replaceFirst(RegExp(r'^\s*[\d.,]+\s*'), '');
          break;
        }
      }
      forms.add(DiscuzNativeForm(
        key: form.id.isNotEmpty
            ? form.id
            : form.attributes['name'] ?? 'form${forms.length}',
        title: heading == null ? '' : _text(heading),
        description: description.length > 1200
            ? description.substring(0, 1200)
            : description,
        action: action,
        method: (form.attributes['method'] ?? 'get').toUpperCase(),
        enctype:
            form.attributes['enctype'] ?? 'application/x-www-form-urlencoded',
        fields: fields,
        buttons: buttons,
        hiddenValues: hidden,
        captchaHash: captchaHash,
        captchaModid: captchaModid,
        unitPrice: double.tryParse(priceMatch?[1] ?? ''),
        priceUnit: priceUnit,
        quantityField: priceMatch == null ? '' : 'days',
      ));
    }
    final tables = <DiscuzDataTable>[];
    final tableRowLinks = <String>{};
    final representedPermissionLinks = <Element>{};
    final headerActions = <DiscuzPageLink>[];
    final permissionColumns = uri.queryParameters['ac'] == 'usergroup' &&
        root.querySelector('.tdats') != null;
    if (permissionColumns) {
      final comparison = DiscuzUsergroupParser.parse(source);
      for (final anchor in root.querySelectorAll('.tdats a[href]')) {
        representedPermissionLinks.add(anchor);
        if (!_visible(anchor)) continue;
        final target = uri.resolve(anchor.attributes['href']!);
        final query = target.queryParameters;
        // This GET opens the website-declared purchase form. It does not buy.
        if (comparison.upgradeGroup != null &&
            DiscuzRequestPolicy.sameOrigin(uri, target) &&
            const {'http', 'https'}.contains(target.scheme) &&
            target.path.split('/').last == 'home.php' &&
            query['mod'] == 'spacecp' &&
            query['ac'] == 'usergroup' &&
            query['do'] == 'buy' &&
            int.tryParse(query['gid'] ?? '') != null &&
            (uri.queryParameters['gid'] == null ||
                query['gid'] == uri.queryParameters['gid']) &&
            !changesData(target) &&
            !headerActions.any((action) => action.uri == target)) {
          headerActions.add(DiscuzPageLink('购买该用户组', target));
        }
      }
      var title = '';
      var rows = <List<String>>[];
      final headers = [
        '权限',
        comparison.myGroup.title,
        if (comparison.upgradeGroup != null) comparison.upgradeGroup!.title
      ];
      void finishCategory() {
        if (rows.isNotEmpty) {
          tables.add(DiscuzDataTable(title, headers, rows));
        }
        rows = [];
      }

      for (final permission in comparison.permissions) {
        if (permission.isCategoryHeader) {
          finishCategory();
          title = permission.title;
        } else {
          rows.add([
            permission.title,
            permission.myValue,
            if (comparison.upgradeGroup != null) permission.nextValue
          ]);
        }
      }
      finishCategory();
    }
    for (final table in root.querySelectorAll('table')) {
      if (!_visible(table) ||
          table.querySelector('table') != null ||
          (permissionColumns && _within(table, 'tdats'))) {
        continue;
      }
      final hasControls =
          table.querySelector('input, select, textarea') != null;
      final hasHeadings =
          table.querySelector('thead, tr.alt, th[scope="col"]') != null ||
              table.querySelectorAll('tr').any((row) =>
                  row.children.length > 1 &&
                  row.children.every((cell) => cell.localName == 'th'));
      if (hasControls && !hasHeadings) continue;
      final rows = <List<String>>[], headers = <String>[];
      final rowLinks = <int, DiscuzPageLink>{};
      final forumPermissionTable = table.classes.contains('ftb') &&
          uri.queryParameters['ac'] == 'usergroup' &&
          uri.queryParameters['do'] == 'forum';
      for (final row in table.querySelectorAll('tr')) {
        final cells = row.children
            .where((node) => node.localName == 'td' || node.localName == 'th')
            .toList();
        if (cells.isEmpty || !_visible(row)) continue;
        final values = <String>[];
        for (final cell in cells) {
          values.add(_text(cell));
          final span = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
          for (var extra = 1; extra < span.clamp(1, 50); extra++) {
            values.add('');
          }
        }
        if (values.every((value) => value.isEmpty)) continue;
        final isHeading = row.parent?.localName == 'thead' ||
            row.classes.contains('alt') ||
            cells.every((cell) => cell.localName == 'th') ||
            cells.any((cell) => cell.attributes['scope'] == 'col');
        if (rows.isEmpty && headers.isEmpty && isHeading) {
          headers.addAll(values);
        } else {
          final anchor = cells.first.querySelector('a[href]');
          final target =
              anchor == null ? null : uri.resolve(anchor.attributes['href']!);
          if (target != null &&
              DiscuzRequestPolicy.sameOrigin(uri, target) &&
              const {'http', 'https'}.contains(target.scheme) &&
              (forumPermissionTable ||
                  DiscuzForumParser.forumId(target.toString(), uri) != null) &&
              !changesData(target) &&
              values.first.isNotEmpty) {
            rowLinks[rows.length] = DiscuzPageLink(values.first, target);
            tableRowLinks.add(target.toString());
          }
          rows.add(values);
        }
      }
      if (rows.isNotEmpty) {
        if (forumPermissionTable) {
          // Even alias routes already belong to a displayed permission row.
          // Flattening them again creates the stray forum card at page bottom.
          representedPermissionLinks.addAll(table.querySelectorAll('a[href]'));
        }
        tables.add(DiscuzDataTable(
            table.querySelector('caption')?.text.trim() ?? '', headers, rows,
            rowLinks: rowLinks));
      }
    }
    final links = <DiscuzPageLink>[];
    final seenLinks = <String>{};
    for (final anchor in root.querySelectorAll('a[href]')) {
      if (!_visible(anchor) || representedPermissionLinks.contains(anchor)) {
        continue;
      }
      final href = anchor.attributes['href']?.trim() ?? '';
      if (href.isEmpty || href.startsWith('#')) continue;
      final target = uri.resolve(href);
      final label = _text(anchor);
      if (!const {'http', 'https'}.contains(target.scheme) ||
          !DiscuzRequestPolicy.sameOrigin(uri, target) ||
          label.isEmpty ||
          tableRowLinks.contains(target.toString()) ||
          target == uri ||
          !seenLinks.add(target.toString())) {
        continue;
      }
      final mutation = changesData(target);
      var kind = mutation ? DiscuzLinkKind.action : DiscuzLinkKind.content;
      Element? ancestor = anchor;
      while (!mutation && ancestor != null && ancestor != root.parent) {
        if (ancestor.classes.any((name) =>
            const {'pg', 'pgb', 'pages', 'comiis_page'}.contains(name))) {
          kind = DiscuzLinkKind.pagination;
          break;
        }
        if (ancestor.classes.any((name) => const {
              'tb',
              'tbn',
              'nav',
              'klp-cp-nav',
              'klp-cp-sidebar',
              'klp-cp-tabs',
              'k-ul-tabs',
              'comiis_user_nav'
            }.contains(name))) {
          kind = DiscuzLinkKind.navigation;
        }
        ancestor = ancestor.parent;
      }
      links.add(
          DiscuzPageLink(label, target, changesData: mutation, kind: kind));
    }
    final information = <String>[], seenText = <String>{};
    if (unsupportedSubmission) {
      information.add('当前操作的提交规则尚未适配，暂时无法在应用内执行。');
    }
    for (final node in root.querySelectorAll(
        'p, .tbmu, .alert_info, .alert_error, .notice, .comiis_tip, .knapi-alert')) {
      if (!_visible(node) ||
          node.classes.any((name) =>
              const {'knapi-empty-t', 'knapi-empty-d'}.contains(name)) ||
          node.querySelector('form, input, select, textarea') != null) {
        continue;
      }
      final text = _text(node);
      if (text.isNotEmpty && text.length <= 1200 && seenText.add(text)) {
        information.add(text);
      }
    }
    final images = <DiscuzPageImage>[];
    for (final image in root.querySelectorAll('img[src]')) {
      if (!_visible(image)) continue;
      final source = image.attributes['src'] ?? '';
      final label = image.attributes['alt'] ?? image.attributes['title'] ?? '';
      if (!(avatar && source.contains('avatar')) &&
          !RegExp(r'二维码|收款|qrcode|qr_code', caseSensitive: false)
              .hasMatch('$label $source')) {
        continue;
      }
      final target = uri.resolve(source);
      if (const {'http', 'https'}.contains(target.scheme)) {
        images.add(DiscuzPageImage(target, label));
      }
    }
    final verificationShell = root.querySelectorAll('form').any((form) {
      final action = uri.resolve(form.attributes['action'] ?? '');
      return action.queryParameters['ac'] == 'profile' &&
          action.queryParameters['op'] == 'verify';
    });
    final noVerification = !login &&
        verificationShell &&
        uri.queryParameters['ac'] == 'profile' &&
        uri.queryParameters['op'] == 'verify' &&
        forms.isEmpty &&
        links.where((link) => link.kind == DiscuzLinkKind.navigation).isEmpty;
    if (noVerification) {
      information.removeWhere((text) => text.contains('以下信息通过审核后'));
      // The empty desktop form repeats the account username as a table row.
      // Keep real status/history tables, but avoid a redundant account table
      // above the no-project state.
      tables.removeWhere((table) =>
          table.title.isEmpty &&
          table.headers.isEmpty &&
          table.rows.length == 1 &&
          table.rows.single.length == 2 &&
          table.rows.single.first == '用户名');
    }
    final emptyAuth = uri.queryParameters['id'] == 'klpbbs_new_api:myauth'
        ? root.querySelector('.knapi-empty')
        : null;
    return DiscuzNativePage(
      uri: uri,
      forms: forms,
      tables: tables,
      links: links,
      headerActions: headerActions,
      information: information,
      images: images,
      message: DiscuzResponse.message(source),
      emptyTitle: noVerification
          ? '当前暂无可申请的认证'
          : emptyAuth?.querySelector('.knapi-empty-t')?.text.trim(),
      emptyDescription: noVerification
          ? '论坛当前没有为此账号开放认证项目。开放后会在这里显示申请条件与表单。'
          : emptyAuth?.querySelector('.knapi-empty-d')?.text.trim(),
      requiresLogin: login,
      avatarPage: avatar,
      avatarDescriptor:
          avatar ? DiscuzAvatarDescriptor.parse(payload, uri) : null,
      hasFlashAvatar: avatar &&
          RegExp(r'uc_avatarflash|AC_FL_RunContent|(?:avatar|camera)\.swf',
                  caseSensitive: false)
              .hasMatch(payload),
    );
  }
}

class DiscuzNativePageReceipt {
  final DiscuzNativePage page;
  final String session;
  final DateTime loadedAt;
  const DiscuzNativePageReceipt(this.page, this.session, this.loadedAt);
}

class DiscuzNativeSubmitResult {
  final bool success;
  final String message;
  final DiscuzNativePageReceipt? nextPage;
  const DiscuzNativeSubmitResult(this.success, this.message, {this.nextPage});
}
