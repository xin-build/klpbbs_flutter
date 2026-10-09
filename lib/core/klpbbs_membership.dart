import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../models/site_feature.dart';
import 'discuz_control_policy.dart';
import 'discuz_request_policy.dart';
import 'discuz_response.dart';

enum MembershipOperation {
  buy('buy'),
  switchGroup('switch'),
  exit('exit');

  final String queryValue;
  const MembershipOperation(this.queryValue);
}

class MembershipPlan extends MembershipOffer {
  final String priceText, expiryText, buyLabel;
  final double? dailyPrice;
  final String priceUnit;
  final int? affordableDays;
  final bool isCurrent, isOwned, isExpired;

  const MembershipPlan({
    required super.groupId,
    required super.title,
    super.details,
    super.buyUrl,
    super.switchUrl,
    super.exitUrl,
    super.permissionsUrl,
    this.priceText = '',
    this.dailyPrice,
    this.priceUnit = '',
    this.expiryText = '',
    this.buyLabel = '',
    this.affordableDays,
    this.isCurrent = false,
    this.isOwned = false,
    this.isExpired = false,
  });

  String? route(MembershipOperation operation) => switch (operation) {
        MembershipOperation.buy => buyUrl,
        MembershipOperation.switchGroup => switchUrl,
        MembershipOperation.exit => exitUrl,
      };

  bool sameAvailabilityAs(MembershipPlan other) =>
      groupId == other.groupId &&
      title == other.title &&
      dailyPrice == other.dailyPrice &&
      priceUnit == other.priceUnit &&
      expiryText == other.expiryText &&
      isCurrent == other.isCurrent &&
      isOwned == other.isOwned &&
      isExpired == other.isExpired &&
      buyLabel == other.buyLabel &&
      buyUrl == other.buyUrl &&
      switchUrl == other.switchUrl &&
      exitUrl == other.exitUrl;
}

class MembershipCenter {
  final Uri uri;
  final bool recognized;
  final String currentGroup, balanceText;
  final List<MembershipPlan> plans;
  MembershipCenter({
    required this.uri,
    required this.recognized,
    required this.currentGroup,
    required this.balanceText,
    required List<MembershipPlan> plans,
  }) : plans = List.unmodifiable(plans);
}

class MembershipCenterReceipt {
  final MembershipCenter center;
  final String session;
  final DateTime loadedAt;
  const MembershipCenterReceipt(this.center, this.session, this.loadedAt);
}

class MembershipActionReceipt {
  final MembershipCenterReceipt centerReceipt;
  final MembershipPlan plan;
  final MembershipActionContract contract;
  final DateTime loadedAt;
  const MembershipActionReceipt(
      this.centerReceipt, this.plan, this.contract, this.loadedAt);
  String get session => centerReceipt.session;
}

class MembershipActionResult {
  final bool success, needsRefresh;
  final String message;
  const MembershipActionResult(this.success, this.message,
      {this.needsRefresh = false});
}

/// Actual KLPBBS desktop list and Comiis mobile list. Missing fields stay
/// unknown; prices, owned groups and expiry are never inferred from a UID.
class KlpbbsMembership {
  static String text(Element? node) {
    if (node == null) return '';
    final copy = node.clone(true);
    copy.querySelectorAll('script, style').forEach((n) => n.remove());
    return copy.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Uri? route(String? value, Uri base,
      {MembershipOperation? operation, int? groupId}) {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null || value?.trim().isEmpty != false) return null;
    final target = base.resolveUri(uri);
    final q = target.queryParameters;
    if (!DiscuzRequestPolicy.sameOrigin(base, target) ||
        target.userInfo.isNotEmpty ||
        target.fragment.isNotEmpty ||
        !target.path.endsWith('/home.php') ||
        q['mod'] != 'spacecp' ||
        q['ac'] != 'usergroup' ||
        q.keys.any((key) => !const {
              'mod',
              'ac',
              'do',
              'gid',
              'groupid',
              'handlekey',
              'mobile',
              'inajax',
              'infloat',
              'ajaxmenu'
            }.contains(key)) ||
        target.queryParametersAll.values.any((values) => values.length != 1)) {
      return null;
    }
    if (operation != null) {
      final id = int.tryParse(q['groupid'] ?? '');
      if (q['do'] != operation.queryValue ||
          id == null ||
          id <= 0 ||
          (groupId != null && id != groupId)) {
        return null;
      }
    } else if (q['do'] != null ||
        int.tryParse(q['gid'] ?? '') == null ||
        int.parse(q['gid']!) <= 0 ||
        (groupId != null && int.parse(q['gid']!) != groupId)) {
      return null;
    }
    return target;
  }

  static ({double? amount, String unit}) price(String value) {
    final cleaned = value.trim().replaceFirst(RegExp(r'\s*/\s*天\s*$'), '');
    if (cleaned == '免费') return (amount: 0, unit: '');
    final match =
        RegExp(r'^([0-9]+(?:\.[0-9]+)?)\s*([^\d\s.].*)$').firstMatch(cleaned);
    final amount = double.tryParse(match?[1] ?? '');
    return (
      amount: amount?.isFinite == true ? amount : null,
      unit: match?[2]?.trim() ?? ''
    );
  }

  static MembershipCenter parse(String source, Uri uri) {
    final document = html.parse(source);
    final plans = <MembershipPlan>[];
    final seen = <int>{};
    var recognized = false;
    String currentGroup = '', balanceText = '';
    final summary = document.querySelector('#ct p.tbmu, .klp-cp-card p.tbmu');
    if (summary != null) {
      balanceText = text(summary.querySelector('.y .xi1'));
      final copy = summary.clone(true);
      copy.querySelectorAll('.y').forEach((n) => n.remove());
      currentGroup =
          RegExp(r'当前用户组\s*[:：]\s*(.+)$').firstMatch(text(copy))?[1]?.trim() ??
              '';
    } else {
      currentGroup = RegExp(r'(?:我的等级|当前用户组)\s*[:：]\s*(.+)$')
              .firstMatch(
                  text(document.querySelector('.comiis_levhead h2')))?[1]
              ?.trim() ??
          '';
      balanceText = text(document.querySelector('.comiis_p12'))
          .replaceFirst(RegExp(r'^您目前有\s*'), '');
    }

    MembershipPlan? plan(Element row, String title, String priceText,
        String expiry, String daysText, Element? operations) {
      final nameLink =
          row.querySelector('a[href*="ac=usergroup"][href*="gid="]');
      final permission = route(nameLink?.attributes['href'], uri);
      final id = int.tryParse(permission?.queryParameters['gid'] ?? '');
      if (id == null || id <= 0 || title.isEmpty || !seen.add(id)) return null;
      final actions = <MembershipOperation, Uri>{};
      var buyLabel = '';
      for (final link in row.querySelectorAll('a[href]')) {
        for (final operation in MembershipOperation.values) {
          final target = route(link.attributes['href'], uri,
              operation: operation, groupId: id);
          if (target == null) continue;
          if (actions[operation] != null && actions[operation] != target) {
            return null;
          }
          actions[operation] = target;
          if (operation == MembershipOperation.buy) buyLabel = text(link);
        }
      }
      final actualPrice = price(priceText);
      // "设为主用户组" declares a switch action, not the current group. Read
      // static status separately from action controls. Group titles need not
      // be unique and cannot establish which group ID is the primary group.
      final status = operations?.clone(true);
      status
          ?.querySelectorAll(
              'a, button, input, select, textarea, script, style')
          .forEach((node) => node.remove());
      final current = !actions.containsKey(MembershipOperation.switchGroup) &&
          RegExp(r'^(?:主用户组|当前用户组)$').hasMatch(text(status));
      final expired = nameLink?.querySelector('s, del') != null;
      final owned = current ||
          actions.containsKey(MembershipOperation.switchGroup) ||
          actions.containsKey(MembershipOperation.exit) ||
          buyLabel.contains('续费') ||
          expiry.isNotEmpty;
      return MembershipPlan(
        groupId: id,
        title: title,
        priceText: priceText,
        dailyPrice: actualPrice.amount,
        priceUnit: actualPrice.unit,
        expiryText: expiry,
        buyLabel: buyLabel,
        affordableDays:
            int.tryParse(RegExp(r'^(\d+)\s*天$').firstMatch(daysText)?[1] ?? ''),
        isCurrent: current,
        isOwned: owned,
        isExpired: expired,
        buyUrl: actions[MembershipOperation.buy]?.toString(),
        switchUrl: actions[MembershipOperation.switchGroup]?.toString(),
        exitUrl: actions[MembershipOperation.exit]?.toString(),
        permissionsUrl: permission?.toString(),
      );
    }

    for (final table
        in document.querySelectorAll('#ct table.dt, .klp-cp-card table.dt')) {
      final rows = table.querySelectorAll('tr');
      final headings = rows
          .where((row) =>
              row.children.length >= 4 &&
              row.children.every((cell) => cell.localName == 'th'))
          .firstOrNull;
      if (headings == null) continue;
      final headers = headings.children.map(text).toList();
      final nameIndex = headers.indexOf('用户组');
      final priceIndex =
          headers.indexWhere((label) => label == '日价格' || label == '每日价格');
      final expiryIndex = headers.indexOf('到期时间');
      final daysIndex = headers.indexWhere((label) => label.contains('目前可以购买'));
      if (nameIndex < 0 || priceIndex < 0 || expiryIndex < 0 || daysIndex < 0) {
        continue;
      }
      recognized = true;
      for (final row in rows) {
        if (row == headings) continue;
        final cells =
            row.children.where((cell) => cell.localName == 'td').toList();
        if (cells.length != headers.length) continue;
        final item = plan(row, text(cells[nameIndex]), text(cells[priceIndex]),
            text(cells[expiryIndex]), text(cells[daysIndex]), cells.last);
        if (item != null) plans.add(item);
      }
    }
    final mobileList = document.querySelector('.comiis_userlist01');
    if (mobileList != null) {
      recognized = true;
      for (final row in mobileList.querySelectorAll('li')) {
        final detail = text(row.querySelector('p.txt'));
        final priceText = detail.split(RegExp(r'[,，]')).first.trim();
        final expiry = text(row.querySelector('p.txt .f_wb'))
            .replaceFirst(RegExp(r'\s*到期$'), '');
        final dayMatch = RegExp(r'可购买\s*(\d+)\s*天').firstMatch(detail);
        final item = plan(
            row,
            text(row.querySelector('p.tit')),
            priceText,
            expiry,
            dayMatch == null ? '' : '${dayMatch[1]} 天',
            row.querySelector('p.ybtn'));
        if (item != null) plans.add(item);
      }
    }
    if (!recognized &&
        currentGroup.isNotEmpty &&
        document.querySelector('#ct p.emp, .comiis_notip') != null) {
      recognized = true;
    }
    return MembershipCenter(
        uri: uri,
        recognized: recognized,
        currentGroup: currentGroup,
        balanceText: balanceText,
        plans: List.unmodifiable(plans));
  }
}

/// A current server-declared POST confirmation. CSRF stays in memory and may
/// rotate; visible terms and all other successful controls must remain equal.
class MembershipActionContract {
  final Uri pageUri, action;
  final MembershipOperation operation;
  final int groupId;
  final String formId, priceUnit, title;
  final Map<String, String> values;
  final List<String> explanations;
  final double? dailyPrice;
  final int? minimumDays, maximumDays;
  final bool requiresDays;
  MembershipActionContract(
      {required this.pageUri,
      required this.action,
      required this.operation,
      required this.groupId,
      required this.formId,
      required Map<String, String> values,
      required List<String> explanations,
      required this.dailyPrice,
      required this.priceUnit,
      required this.minimumDays,
      required this.maximumDays,
      required this.requiresDays,
      required this.title})
      : values = Map.unmodifiable(values),
        explanations = List.unmodifiable(explanations);

  bool get canSubmit =>
      values['formhash']?.isNotEmpty == true &&
      (operation != MembershipOperation.buy ||
          (dailyPrice != null &&
              (dailyPrice == 0 || priceUnit.isNotEmpty) &&
              (!requiresDays || (minimumDays != null && minimumDays! > 0))));

  static MembershipActionContract parse(String source, Uri uri,
      MembershipOperation operation, MembershipPlan plan) {
    final payload =
        RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source)?[1] ?? source;
    final document = html.parse(payload);
    final formId =
        '${operation == MembershipOperation.switchGroup ? 'switchgroupform' : 'buygroupform'}_${plan.groupId}';
    final form = document.querySelector('form[id="$formId"]');
    final action = KlpbbsMembership.route(form?.attributes['action'], uri,
        operation: operation, groupId: plan.groupId);
    if (form == null ||
        action == null ||
        (form.attributes['method'] ?? '').toLowerCase() != 'post') {
      throw StateError(DiscuzResponse.message(source) ?? '论坛当前没有提供此会员操作的确认表单');
    }
    if (DiscuzControlPolicy.hasUnsupportedSubmission(form, document)) {
      throw StateError('论坛会员表单使用了尚未适配的提交方式，请刷新或等待接口适配');
    }
    final values = <String, String>{};
    Element? days;
    for (final control
        in form.querySelectorAll('input, button, select, textarea')) {
      if (control.attributes.containsKey('disabled')) continue;
      final name = control.attributes['name'] ?? '';
      final type = (control.attributes['type'] ??
              (control.localName == 'button' ? 'submit' : 'text'))
          .toLowerCase();
      if (type == 'button' || type == 'reset') continue;
      if (name.isEmpty ||
          values.containsKey(name) ||
          !const {
            'referer',
            'buysubmit',
            'groupsubmit',
            'gid',
            'handlekey',
            'formhash',
            'days',
            'editsubmit_btn'
          }.contains(name) ||
          (name == 'days' && operation != MembershipOperation.buy) ||
          (name != 'days' &&
              type != 'hidden' &&
              !(name == 'editsubmit_btn' && type == 'submit'))) {
        throw StateError('论坛会员表单字段已变化，请刷新后重试');
      }
      values[name] = control.attributes['value'] ?? '';
      if (name == 'days') days = control;
    }
    final submitName = operation == MembershipOperation.switchGroup
        ? 'groupsubmit'
        : 'buysubmit';
    if (values['formhash']?.isNotEmpty != true ||
        values[submitName]?.isNotEmpty != true ||
        values['editsubmit_btn']?.isNotEmpty != true ||
        values.containsKey(operation == MembershipOperation.switchGroup
            ? 'buysubmit'
            : 'groupsubmit')) {
      throw StateError('会员操作凭证不完整，请刷新后重试');
    }
    String priceText = '', maxText = '';
    final explanations = <String>[];
    for (final row in form.querySelectorAll('tr, .tip_txt, .bg_h')) {
      final cells = row.localName == 'tr'
          ? row.children
              .where((n) => n.localName == 'td' || n.localName == 'th')
              .toList()
          : row.children.toList();
      final label = cells.isEmpty ? '' : KlpbbsMembership.text(cells.first);
      if (cells.length >= 2 && (label == '日价格' || label == '每日价格')) {
        priceText = KlpbbsMembership.text(cells[1]);
      } else if (cells.length >= 2 && label.contains('目前可以购买')) {
        maxText = KlpbbsMembership.text(cells[1]);
      }
      if (RegExp(r'^说明\s*[:：]').hasMatch(KlpbbsMembership.text(row))) {
        explanations.add(KlpbbsMembership.text(row));
      }
    }
    final fromText = KlpbbsMembership.price(priceText);
    final priceValues = RegExp(
            r'\b(?:var|let|const)\s+dailyprice\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*;')
        .allMatches(form.innerHtml)
        .map((m) => double.parse(m[1]!))
        .toSet();
    if (priceValues.length > 1) {
      throw StateError('会员价格声明不一致，请刷新后重试');
    }
    double? amount =
        priceValues.length == 1 ? priceValues.single : fromText.amount;
    if (amount != null &&
        (!amount.isFinite ||
            amount < 0 ||
            (fromText.amount != null && fromText.amount != amount))) {
      throw StateError('会员价格声明不一致，请刷新后重试');
    }
    if (operation == MembershipOperation.buy && days == null) {
      if (plan.dailyPrice == 0 && KlpbbsMembership.text(form).contains('免费')) {
        amount = 0;
      } else {
        throw StateError('当前购买期限或价格尚无法确认，请稍后刷新');
      }
    }
    final minimum = days == null
        ? null
        : int.tryParse(
            days.attributes['min'] ?? days.attributes['value'] ?? '');
    final declaredMaximum =
        days == null ? null : int.tryParse(days.attributes['max'] ?? '');
    final affordable =
        int.tryParse(RegExp(r'^(\d+)\s*天$').firstMatch(maxText)?[1] ?? '');
    final maximum = declaredMaximum == null
        ? affordable
        : affordable == null
            ? declaredMaximum
            : (declaredMaximum < affordable ? declaredMaximum : affordable);
    return MembershipActionContract(
        pageUri: uri,
        action: action,
        operation: operation,
        groupId: plan.groupId,
        formId: formId,
        values: Map.unmodifiable(values),
        title:
            KlpbbsMembership.text(document.querySelector('.flb em, .tip_tit')),
        explanations: List.unmodifiable(explanations),
        dailyPrice: amount,
        priceUnit: fromText.unit.isNotEmpty ? fromText.unit : plan.priceUnit,
        minimumDays: minimum,
        maximumDays: maximum,
        requiresDays: days != null);
  }

  String? validateDays(int? days) {
    if (!canSubmit) return '会员价格或期限未完整加载，请重新读取报价';
    if (!requiresDays) return days == null ? null : '当前表单没有提供购买期限';
    if (days == null || days < minimumDays!) return '购买期限至少 $minimumDays 天';
    if (maximumDays != null && days > maximumDays!) {
      return '当前余额或表单最多允许购买 $maximumDays 天';
    }
    return null;
  }

  double? totalPrice(int? days) =>
      dailyPrice == null || (requiresDays && days == null)
          ? null
          : dailyPrice! * (requiresDays ? days! : 1);

  Map<String, String> submission(int? days) {
    final error = validateDays(days);
    if (error != null) throw FormatException(error);
    return {...values, if (requiresDays) 'days': days.toString()};
  }

  bool sameTermsAs(MembershipActionContract other) {
    if (pageUri != other.pageUri ||
        action != other.action ||
        operation != other.operation ||
        groupId != other.groupId ||
        formId != other.formId ||
        dailyPrice != other.dailyPrice ||
        priceUnit != other.priceUnit ||
        minimumDays != other.minimumDays ||
        maximumDays != other.maximumDays ||
        requiresDays != other.requiresDays ||
        title != other.title ||
        explanations.length != other.explanations.length) {
      return false;
    }
    for (var i = 0; i < explanations.length; i++) {
      if (explanations[i] != other.explanations[i]) return false;
    }
    final a = {...values}..remove('formhash');
    final b = {...other.values}..remove('formhash');
    return a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
  }
}
