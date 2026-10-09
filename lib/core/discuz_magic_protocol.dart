import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../models/magic_item.dart';

/// 道具标识、价格和操作权限来自当前页面，插件名称不用于猜测接口。
class DiscuzMagicProtocol {
  static final _defaultBase = Uri.parse('https://klpbbs.com/');
  static const logOperations = {'uselog', 'buylog', 'givelog', 'receivelog'};

  static Document _document(String source) {
    final payload =
        RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source)?[1] ?? source;
    final doc = html.parse(payload);
    doc
        .querySelectorAll(
            'script, style, body > header, body > footer, #hd, #ft, #nv, '
            '#toptb, .comiis_head, .comiis_footer, .comiis_sidenv, .comiis_fmenu')
        .forEach((node) => node.remove());
    return doc;
  }

  static String _text(Element node) =>
      node.text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _restricted(Document doc) =>
      doc.querySelector(
          '#messagetext, .alert_error, #loginform, form[id^="loginform_"]') !=
      null;

  static bool recognizes(String source, String action) {
    final doc = _document(source);
    if (_restricted(doc)) return false;
    if (action == 'log') {
      if (_emptyLogs(doc)) return true;
      if (doc.querySelector('.comiis_magic_box .comiis_credits_log li.xtlist, '
              '.comiis_log_li') !=
          null) {
        return true;
      }
      return doc
          .querySelectorAll(
              '#ct table.dt, .klp-cp-main table, table.klp-mg-table')
          .any((table) {
        final header = table.querySelector('tr');
        if (header == null) return false;
        final fields = header.children.map(_text);
        return fields.any((name) => name == '名称' || name.contains('道具')) &&
            fields.any((name) => name.contains('时间') || name.contains('日期'));
      });
    }
    if (doc.querySelector(
            '.mgcl, .klp-mg-grid, .comiis_magic_box, .comiis_magic_list') !=
        null) {
      return true;
    }
    final root = doc.querySelector('#ct .mn, .klp-cp-main, .comiis_magic');
    if (root == null) return false;
    if (root.querySelector('.emp, .magic-empty, .comiis_notip') == null &&
        (action != 'log' ||
            root.querySelector('table.dt, .klp-mg-table, .comiis_log_li') ==
                null)) {
      return false;
    }
    return root.querySelectorAll('a[href]').any((link) {
      final q = Uri.tryParse(link.attributes['href'] ?? '')?.queryParameters;
      return q?['mod'] == 'magic' && q?['action'] == action;
    });
  }

  static bool _emptyLogs(Document doc) => doc
      .querySelectorAll('#ct .mn .emp, .klp-cp-main .k-empty, '
          '.comiis_magic_box .comiis_notip, .comiis_magic .magic-empty')
      .any((node) => RegExp(r'暂无|没有|无记录|尚无').hasMatch(_text(node)));

  static bool hasExplicitEmptyLogs(String source) {
    final doc = _document(source);
    return !_restricted(doc) && _emptyLogs(doc);
  }

  static Uri? _operationLink(Element link, Uri base, String action) {
    var raw = link.attributes['href'] ?? '';
    if (raw.isEmpty || raw.startsWith('javascript:')) {
      raw = RegExp(r'''['"]([^'"]*home\.php\?[^'"]+)['"]''')
              .firstMatch(link.attributes['onclick'] ?? '')?[1] ??
          '';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || raw.isEmpty) return null;
    final target = base.resolveUri(uri);
    final q = target.queryParameters;
    if (target.origin != base.origin ||
        !target.path.endsWith('/home.php') ||
        q['mod'] != 'magic' ||
        q['action'] != action ||
        q.keys.any((key) => const {
              'usesubmit',
              'operatesubmit',
              'buysubmit',
              'givesubmit',
            }.contains(key))) {
      return null;
    }
    if (q['mid']?.isNotEmpty != true &&
        int.tryParse(q['magicid'] ?? '') == null) {
      return null;
    }
    return target;
  }

  static List<MagicItem> shop(String source, {Uri? base}) =>
      _items(source, 'shop', base ?? _defaultBase);

  static List<MagicItem> mybox(String source, {Uri? base}) =>
      _items(source, 'mybox', base ?? _defaultBase);

  static List<MagicItem> _items(String source, String action, Uri base) {
    final doc = _document(source);
    if (_restricted(doc)) return const [];
    final result = <MagicItem>[];
    final seen = <String>{};
    final nodesById = {
      for (final node in doc.querySelectorAll('[id]')) node.id: node,
    };
    for (final row in doc.querySelectorAll(
        'ul.mgcl > li, .klp-mg-grid > .klp-mdl, .comiis_magic_box ul > li, '
        '.comiis_medalbox ul > li, .comiis_magic_list li, #ct table.dt tr')) {
      final image = row.querySelector('img');
      final rawImage = image?.attributes['comiis_loadimages'] ??
          image?.attributes['data-src'] ??
          image?.attributes['file'] ??
          image?.attributes['src'] ??
          '';
      final operations = <String, String>{};
      String identifier = '';
      var id = int.tryParse(row.attributes['data-magicid'] ?? '') ?? 0;
      for (final link in row.querySelectorAll('a')) {
        final target = _operationLink(link, base, action);
        if (target == null) continue;
        final q = target.queryParameters;
        final numeric = int.tryParse(q['magicid'] ?? '');
        if (numeric != null && numeric > 0) id = numeric;
        final mid = q['mid'];
        if (mid?.isNotEmpty == true) identifier = mid!;
        final operation = q['operation'];
        if (const {'buy', 'give', 'use', 'sell', 'drop'}.contains(operation)) {
          operations[operation!] = target.toString();
        }
      }
      for (final node in [row, ...row.querySelectorAll('[id^="magic_"]')]) {
        final attribute = node.attributes['id'] ?? '';
        if (!attribute.startsWith('magic_') || attribute.endsWith('_menu')) {
          continue;
        }
        final value = attribute.substring(6);
        if (identifier.isEmpty && RegExp(r'^[a-zA-Z0-9_:]+$').hasMatch(value)) {
          identifier = value;
        }
      }
      if (operations.isEmpty &&
          identifier.isEmpty &&
          !rawImage.contains('/magic/')) {
        continue;
      }
      var name = image?.attributes['alt']?.trim() ?? '';
      if (name.isEmpty) {
        final title =
            row.querySelector('.klp-mdl-name, p.tit, p.f14 a, h2, h3, h4, '
                'p > strong, .magic-name, .magic_name');
        name = title == null ? '' : _text(title);
      }
      if (name.isEmpty || const {'购买', '使用', '赠送', '出售', '丢弃'}.contains(name)) {
        continue;
      }
      final key = identifier.isNotEmpty
          ? identifier
          : id > 0
              ? '$id'
              : name;
      if (!seen.add(key)) continue;
      final tip = identifier.isEmpty
          ? null
          : nodesById['magic_${identifier}_menu']?.querySelector('.tip_c');
      final descriptionNode = tip ??
          row.querySelector(
              '.klp-mdl-tip > p, p.txt, .desc, .magic-desc, p.xg2');
      final description = descriptionNode == null ? '' : _text(descriptionNode);
      var price = -1;
      var priceLabel = '';
      var currency = '';
      var unit = '';
      // 价格段落与道具说明分开，说明中的限量、使用周期不是价格或数量。
      for (final paragraph in row.querySelectorAll('p, .magic-price, .price')) {
        var parent = paragraph.parent;
        var inDescription = false;
        while (parent != null && parent != row) {
          if (parent.classes.contains('klp-mdl-tip')) {
            inDescription = true;
            break;
          }
          parent = parent.parent;
        }
        if (inDescription) continue;
        if (paragraph.classes
                .any((value) => const {'txt', 'desc', 'xg2'}.contains(value)) ||
            paragraph.querySelector('.tip_c') != null) {
          continue;
        }
        final clone = paragraph.clone(true);
        clone.querySelectorAll('.xg1, em').forEach((node) => node.remove());
        final value = _text(clone);
        final match = RegExp(r'^(.*?)\s*(\d[\d,]*)\s*([^\d]*?)/([^\s]+)$')
            .firstMatch(value);
        if (match == null) continue;
        price = int.tryParse(match[2]!.replaceAll(',', '')) ?? -1;
        priceLabel = value;
        currency = match[1]!.replaceFirst(RegExp(r'^售价[:：]?\s*'), '').trim();
        if (currency.isEmpty) currency = match[3]!.trim();
        unit = '${match[3]!.trim()}/${match[4]!}';
        break;
      }
      // 只从正文属性段读取数量、重量和库存，隐藏说明里的数字不能计入背包。
      final properties = row.clone(true);
      final declaredProperties =
          row.querySelector('.klp-mdl-tip-f')?.text ?? '';
      properties
          .querySelectorAll('.tip, .tip_c, .klp-mdl-tip, p.txt, .desc, p.xg2')
          .forEach((node) => node.remove());
      final text =
          '${_text(properties)} ${declaredProperties.replaceAll(RegExp(r'\s+'), ' ').trim()}';
      final count = int.tryParse(row.attributes['data-count'] ??
              RegExp(r'(?:数量|拥有数量|持有数量)[:：\s]*(\d+)').firstMatch(text)?[1] ??
              '') ??
          -1;
      final totalWeight =
          int.tryParse(RegExp(r'总重量[:：\s]*(\d+)').firstMatch(text)?[1] ?? '') ??
              -1;
      final weight = int.tryParse(
              RegExp(r'(?:^|[,\s，])(?:单个重量|单重|重量)[:：\s]*(\d+)')
                      .firstMatch(text)?[1] ??
                  '') ??
          -1;
      var stock = int.tryParse(
              RegExp(r'(?:库存|剩余数量)[:：\s]*(\d+)').firstMatch(text)?[1] ?? '') ??
          -1;
      if (stock < 0 && RegExp(r'售罄|暂无库存|已售完').hasMatch(text)) stock = 0;
      final imageUri = Uri.tryParse(rawImage);
      final resolvedImage = rawImage.isNotEmpty && imageUri != null
          ? base.resolveUri(imageUri)
          : null;
      result.add(MagicItem(
        id: id,
        identifier: identifier,
        name: name,
        desc: description,
        img: resolvedImage != null &&
                const {'http', 'https'}.contains(resolvedImage.scheme)
            ? resolvedImage.toString()
            : '',
        price: price,
        priceLabel: priceLabel,
        currency: currency,
        unit: unit,
        count: count,
        weight: weight,
        totalWeight: totalWeight,
        stock: stock,
        operations: Map.unmodifiable(operations),
        canUse: operations.containsKey('use'),
        canGive: operations.containsKey('give'),
        canDrop:
            operations.containsKey('sell') || operations.containsKey('drop'),
      ));
    }
    return result;
  }

  static int? balanceValue(String? value) {
    if (value == null) return null;
    final match =
        RegExp(r'^\s*(\d[\d,]*)\s*(?:粒|个|点|块|EP)?\s*$').firstMatch(value);
    return match == null ? null : int.tryParse(match[1]!.replaceAll(',', ''));
  }

  static MagicBagInfo bag(String source, {int? defaultIron}) {
    final doc = _document(source);
    if (_restricted(doc)) return const MagicBagInfo();
    doc
        .querySelectorAll(
            '.mgcl li, .klp-mg-grid, .comiis_magic_box li, .comiis_magic_list li')
        .forEach((node) => node.remove());
    final text = doc.body?.text.replaceAll(RegExp(r'\s+'), ' ') ?? '';
    final capacityNode = doc.querySelector('.klp-mg-cap');
    // The current template also shortens this labelled field to “容量”.
    // Accept that shorthand only inside its declared capacity element.
    final capacity = capacityNode == null
        ? RegExp(
                r'(?:我的)?(?:道具包|道具背包|背包)容量[:：\s]*([\d,]+)\s*/\s*([\d,]+|不限|无限|无上限)')
            .firstMatch(text)
        : RegExp(
                r'^(?:(?:我的)?(?:道具包|道具背包|背包))?容量[:：\s]*([\d,]+)\s*/\s*([\d,]+|不限|无限|无上限)')
            .firstMatch(_text(capacityNode));
    final iron = RegExp(r'铁粒\s*[:：]\s*(\d[\d,]*)').firstMatch(text)?[1] ??
        RegExp(r'(?:当前拥有|当前余额|现有|账户余额)[:：\s]*(\d[\d,]*)\s*(?:粒)?铁粒')
            .firstMatch(text)?[1];
    return MagicBagInfo(
      usedCapacity:
          int.tryParse((capacity?[1] ?? '').replaceAll(',', '')) ?? -1,
      totalCapacity:
          int.tryParse((capacity?[2] ?? '').replaceAll(',', '')) ?? -1,
      unlimitedCapacity: const {'不限', '无限', '无上限'}.contains(capacity?[2]),
      ironCount: iron == null
          ? defaultIron ?? -1
          : int.tryParse(iron.replaceAll(',', '')) ?? -1,
    );
  }

  static List<MagicLogEntry> logs(String source, {String op = 'uselog'}) {
    if (!logOperations.contains(op)) return const [];
    final doc = _document(source);
    if (_restricted(doc)) return const [];
    final result = <MagicLogEntry>[];
    final label = const {
      'uselog': '使用',
      'buylog': '购买',
      'givelog': '赠送',
      'receivelog': '获赠',
    }[op]!;
    for (final table in doc.querySelectorAll(
        '#ct table.dt, .klp-cp-main table, table.klp-mg-table')) {
      final rows = table.querySelectorAll('tr');
      if (rows.isEmpty) continue;
      final headers = rows.first.children
          .where((node) => const {'td', 'th'}.contains(node.localName))
          .map(_text)
          .toList();
      final nameColumn =
          headers.indexWhere((name) => name.contains('道具') || name == '名称');
      final timeColumn = headers
          .indexWhere((name) => name.contains('时间') || name.contains('日期'));
      final countColumn = headers.indexWhere((name) => name.contains('数量'));
      final priceColumn = headers
          .indexWhere((name) => name.contains('价格') || name.contains('售价'));
      final targetColumn = headers.indexWhere((name) =>
          name.contains('对象') ||
          name.contains('目标') ||
          name.contains('受赠') ||
          name.contains('赠送人'));
      if (nameColumn < 0 || timeColumn < 0) continue;
      for (final row in rows.skip(1)) {
        final cells =
            row.children.where((node) => node.localName == 'td').toList();
        String field(int column) =>
            column >= 0 && column < cells.length ? _text(cells[column]) : '';
        final name = field(nameColumn);
        final time = field(timeColumn);
        if (name.isEmpty || time.isEmpty) continue;
        final target = field(targetColumn);
        var action = label;
        if (op == 'uselog' && const {'出售', '丢弃'}.contains(target)) {
          action = target;
        }
        result.add(MagicLogEntry(
          magicName: name,
          time: time,
          amount: int.tryParse(RegExp(r'^\s*(\d[\d,]*)\s*(?:张|个|件)?\s*$')
                      .firstMatch(field(countColumn))?[1]
                      ?.replaceAll(',', '') ??
                  '') ??
              -1,
          action: action,
          target: target,
          note: field(priceColumn),
        ));
      }
    }
    // 移动模板只接收明确的名称、时间和说明节点；无法识别的模板可打开完整网页。
    for (final row in doc.querySelectorAll('.comiis_log_li')) {
      final title = row.querySelector('h2, h3, .magic-name, .magic_name');
      final time = row.querySelector('time, .time, .date');
      if (title == null || time == null) continue;
      final note = row.querySelector('.note, .desc');
      result.add(MagicLogEntry(
          magicName: _text(title),
          time: _text(time),
          amount: balanceValue(row.attributes['data-count']) ?? -1,
          action: label,
          note: note == null ? '' : _text(note)));
    }
    for (final row in doc
        .querySelectorAll('.comiis_magic_box .comiis_credits_log li.xtlist')) {
      final title = row.querySelector('h2 .f_0');
      final time = row.querySelector('h2 .y');
      final details = row.querySelector('p');
      // Old/deleted magic entries can retain a valid dated history row while
      // the template leaves its name empty. Keep that row and its amount.
      if (title == null || time == null) continue;
      final detail = details == null ? '' : _text(details);
      final quantity =
          RegExp(r'(?:购买|赠送)?数量[:：\s]*(\d[\d,]*)').firstMatch(detail)?[1];
      final price =
          RegExp(r'(?:购买)?价格[:：\s]*(.+)$').firstMatch(detail)?[1]?.trim();
      final target = op == 'buylog'
          ? ''
          : detail.replaceFirst(RegExp(r'^(?:使用对象|赠送对象|受赠者|赠送人)[:：\s]*'), '');
      result.add(MagicLogEntry(
          magicName: _text(title),
          time: _text(time),
          amount: int.tryParse(quantity?.replaceAll(',', '') ?? '') ?? -1,
          action: op == 'uselog' && const {'出售', '丢弃'}.contains(target)
              ? target
              : label,
          target: target,
          note: price ?? ''));
    }
    return result;
  }

  static int? nextLogPage(String source, String op, int page, Uri base) {
    return nextPage(source, 'log', page, base, operation: op);
  }

  static int? nextPage(String source, String action, int page, Uri base,
      {String? operation}) {
    final doc = _document(source);
    for (final link in doc.querySelectorAll('.pg a.nxt, .pg a.next')) {
      final target = base.resolve(link.attributes['href'] ?? '');
      final q = target.queryParameters;
      final next = int.tryParse(q['page'] ?? '');
      if (target.origin == base.origin &&
          q['mod'] == 'magic' &&
          q['action'] == action &&
          (operation == null || q['operation'] == operation) &&
          next != null &&
          next > page) {
        return next;
      }
    }
    return null;
  }
}
