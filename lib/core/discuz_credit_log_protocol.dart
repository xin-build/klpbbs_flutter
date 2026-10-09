import 'package:html/parser.dart' as html;

import '../models/credit_log.dart';
import 'discuz_response.dart';

/// 筛选地址、奖励列的币种与流水数额均来自当前页面。
class DiscuzCreditLogProtocol {
  static Uri? rewardPage(String source, Uri page) {
    final doc = html.parse(source);
    for (final link in doc.querySelectorAll(
        '#ct a[href], .klp-cp-main a[href], .comiis_credit a[href], .comiis_jflist a[href], .comiis_topnv a[href]')) {
      final uri = page.resolve(link.attributes['href']!);
      final q = uri.queryParameters;
      if (uri.origin != page.origin ||
          q['mod'] != 'spacecp' ||
          q['ac'] != 'credit' ||
          q['op'] != 'log') {
        continue;
      }
      if (q['suboperation'] == 'creditrulelog' ||
          q['subop'] == 'creditrulelog' ||
          q['subop'] == 'reward' ||
          RegExp(r'系统奖励|奖励记录').hasMatch(link.text)) {
        return uri;
      }
    }
    return null;
  }

  static bool recognized(String source) {
    final message = DiscuzResponse.message(source) ?? '';
    if (RegExp(r'抱歉|权限不足|请先登录|尚未登录|请先绑定').hasMatch(message)) {
      return false;
    }
    final doc = html.parse(source);
    if (doc.querySelector('#loginform, form[name="login"]') != null) {
      return false;
    }
    return doc.querySelector(
                'table.dt, .comiis_jflist, .comiis_credit_list, .comiis_credit, .klp-credit-log') !=
            null ||
        doc
            .querySelectorAll('#ct .emp, .klp-cp-main .emp, .comiis_notip')
            .any((node) => RegExp(r'暂无记录|没有.*记录|无.*记录').hasMatch(node.text));
  }

  static final _time = RegExp(
      r'\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?|(?:今天|昨天|前天)(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?|\d+\s*(?:秒|分钟|小时|天)前|刚刚');
  static const _currency = '铁粒|金粒|绿宝石|贡献|人气|威望|金币|经验|钻石|积分';

  static String _number(String text) {
    final value = text.trim().replaceAll(',', '').replaceAll('−', '-');
    if (!RegExp(r'^[+-]?\d+$').hasMatch(value)) return '—';
    return value.startsWith('+') || value.startsWith('-') ? value : '+$value';
  }

  static List<({String currency, String amount})> _amounts(String text) {
    final cleaned = text.replaceAll(_time, '').trim();
    final amounts = <({String currency, String amount})>[];
    final seen = <String>{};
    final pattern = RegExp(
        '($_currency)\\s*([+-]?\\d[\\d,]*)|([+-]?\\d[\\d,]*)\\s*($_currency)');
    for (final match in pattern.allMatches(cleaned)) {
      final currency = match.group(1) ?? match.group(4)!;
      final amount = _number(match.group(2) ?? match.group(3)!);
      if (seen.add('$currency:$amount')) {
        amounts.add((currency: currency, amount: amount));
      }
    }
    if (amounts.isEmpty) {
      final match = RegExp(r'[+-]\d[\d,]*').firstMatch(cleaned);
      final amount =
          match == null ? _number(cleaned) : _number(match.group(0)!);
      if (amount != '—') amounts.add((currency: '积分', amount: amount));
    }
    return amounts;
  }

  static List<CreditLogEntry> parse(String source) {
    if (!recognized(source)) return const [];
    final doc = html.parse(source);
    final out = <CreditLogEntry>[];
    final seen = <String>{};
    void add(String operation, String detail, String time, String currency,
        String amount) {
      operation = operation.trim();
      if (operation.isEmpty) return;
      final key = '$operation|$detail|$time|$currency|$amount';
      if (seen.add(key)) {
        out.add(CreditLogEntry(
            creditType: currency,
            amount: amount,
            operation: operation,
            detail: detail.trim(),
            timeText: time.trim()));
      }
    }

    for (final table in doc.querySelectorAll('table.dt')) {
      final headers = table
              .querySelectorAll('tr')
              .firstOrNull
              ?.querySelectorAll('th')
              .map((node) => node.text.trim())
              .toList() ??
          const <String>[];
      final ruleLog =
          headers.any((text) => RegExp(r'总次数|周期次数|周期内次数').hasMatch(text));
      for (final row in table.querySelectorAll('tr')) {
        final cells =
            row.children.where((node) => node.localName == 'td').toList();
        if (cells.length < 3 || row.querySelector('select, input') != null) {
          continue;
        }
        if (ruleLog && cells.length >= 5 && headers.length == cells.length) {
          final time = cells.last.text.trim();
          final detail =
              '总次数：${cells[1].text.trim()} · 周期次数：${cells[2].text.trim()}';
          for (var i = 3; i < cells.length - 1; i++) {
            add(cells.first.text, detail, time.isEmpty ? '—' : time,
                headers[i].isEmpty ? '积分' : headers[i], _number(cells[i].text));
          }
        } else if (!ruleLog && cells.length >= 3) {
          final time = cells.last.text.trim();
          if (!_time.hasMatch(time)) continue;
          final amounts = _amounts(cells[1].text);
          final detail = cells.length >= 4 ? cells[2].text : '';
          if (amounts.isEmpty) {
            add(cells.first.text, detail, time, '积分', '—');
          } else {
            for (final value in amounts) {
              add(cells.first.text, detail, time, value.currency, value.amount);
            }
          }
        }
      }
    }
    if (out.isNotEmpty) return out;

    for (final item in doc.querySelectorAll(
        '.comiis_jflist li, .comiis_credit_list li, .comiis_credit li')) {
      final timeNode = item.querySelector('span.y, .time, .f12.xg1, span.xg1');
      final time = _time.firstMatch(timeNode?.text ?? '')?.group(0) ??
          _time.firstMatch(item.text)?.group(0);
      if (time == null) continue;
      final heading =
          item.querySelector('h2, h3, .kmcon, .km_con')?.clone(true);
      heading
          ?.querySelectorAll(
              '.y, .f_d, .money, .credit, .cre_mun, script, style')
          .forEach((node) => node.remove());
      final operation = (heading?.text ?? '').replaceAll(_time, '').trim();
      if (operation.isEmpty) continue;
      final detail = item.querySelector('p.f_b, p.desc, p.xg1')?.text ?? '';
      final creditNode = item.querySelector(
          '.cre_mun, .span_0, .span_1, .kmimg, .kmleft, .money, .credit');
      final amounts =
          _amounts(creditNode?.text ?? item.text.replaceAll(_time, ''));
      if (amounts.isEmpty) {
        add(operation, detail, time, '积分', '—');
      } else {
        for (final value in amounts) {
          add(operation, detail, time, value.currency, value.amount);
        }
      }
    }
    return out;
  }
}
