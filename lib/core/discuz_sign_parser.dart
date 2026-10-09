import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../models/sign_entry.dart';
import 'discuz_session_parser.dart';

class DiscuzSignCalendar {
  final bool recognized;
  final Set<int> days;
  const DiscuzSignCalendar(this.recognized, this.days);
}

/// 将页面不可用与“确实未签到”分开，零人数也是有效站点数据。
class DiscuzSignParser {
  static String _unwrap(String source) =>
      RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source)?.group(1) ??
      source;

  static int? _number(String? value) => int.tryParse(RegExp(r'\d[\d,]*')
          .firstMatch(value ?? '')
          ?.group(0)
          ?.replaceAll(',', '') ??
      '');

  static int? _uid(String? href) => _number(
      RegExp(r'(?:space-uid-|[?&]uid=)(\d+)').firstMatch(href ?? '')?.group(1));

  static SignHeaderInfo page(String source,
      {String? defaultUsername, int? defaultUid, int? serverDay}) {
    final raw = _unwrap(source);
    final identity = DiscuzSessionParser.parse(raw);
    final doc = html.parse(raw);
    doc
        .querySelectorAll('#hd, #toptb, #ft, #nv, .comiis_sidenv, .comiis_head')
        .forEach((e) => e.remove());
    final left = doc.querySelector('.qdleft, .midaben_signpanel');
    final unsigned = doc.querySelector(
        '#JD_sign, a.JD_sign, .comiis_btnbox [onclick*="ajaxsign"]');
    final visited = doc
        .querySelector('.qdleft .btnvisted, a.btnvisted, .midaben_signpanel');
    final mobile = doc.querySelector('.comiis_btnbox a, .comiis_btnbox input');
    final mobileText =
        (mobile?.attributes['value'] ?? mobile?.text ?? '').trim();
    final paiming = doc.querySelector('.paiming, .sign_paiming');
    final statusText = paiming?.text.trim() ?? '';
    final signedText =
        RegExp(r'^(?:今日已签|已签到|您今天已签到|您今天已经签过到了)$').hasMatch(mobileText) ||
            (statusText.contains('已签到') &&
                !RegExp(r'未签到|没有签到|尚未签到|还没有').hasMatch(statusText));
    final unsignedText = RegExp(r'未签到|没有签到|尚未签到|还没有签到').hasMatch(statusText);
    final loginHref = unsigned?.attributes['href'] ?? '';
    final guest = loginHref.contains('mod=logging') ||
        RegExp(r'''\b(?:discuz_uid|comiis_uid)\s*=\s*['"]?0(?:['";\s,]|$)''')
            .hasMatch(raw);
    final known = !guest &&
        (unsigned != null ||
            visited != null ||
            signedText ||
            unsignedText ||
            const {'签到', '点我签到'}.contains(mobileText));
    final signed = known && unsigned == null && (visited != null || signedText);

    final countNode = doc.querySelector(
        '.weather_p .con, .weather_p, .today_sign_num, .sign_num');
    int? count = _number(countNode?.text);
    if (count == null) {
      for (final node in doc.querySelectorAll('p, span, li')) {
        if (node.text.length > 120) continue;
        final match =
            RegExp(r'今日(?:已)?(?:签到|打卡)(?:人数)?[^\d]{0,10}(\d[\d,]*)\s*人')
                .firstMatch(node.text);
        if (match != null) {
          count = _number(match.group(1));
          break;
        }
      }
    }
    // 未签到按钮旁的隐藏值是站点人数，不能用作个人排名。
    count ??= unsigned != null && !guest
        ? _number(doc.querySelector('#qiandaobtnnum')?.attributes['value'])
        : null;
    Element? star;
    String starName = '';
    // Current PC template declares the star as plain text, sometimes with a
    // profile link. An unrelated xg1 profile must not become the daily winner.
    for (final node
        in doc.querySelectorAll('.star_user, span.xg1, .sign_star')) {
      final match =
          RegExp(r'今日签到之星\s*[：:]\s*(.+)').firstMatch(node.text.trim());
      if (match != null) {
        star = node.querySelector('a[href*="space-uid-"], a[href*="uid="]');
        starName = match.group(1)!.trim();
        break;
      }
      if (node.classes.contains('star_user')) {
        star = node.localName == 'a' ? node : node.querySelector('a');
        starName = node.text.trim();
        if (starName.isNotEmpty) break;
      }
    }
    final signScope =
        doc.querySelector('.qdright, .sign_main, .comiis_sign') ?? doc.body;
    final scopedText = signScope?.text ?? '';
    final highest = _number(
        RegExp(r'历史最高人数[：:\s]*(\d[\d,]*)').firstMatch(scopedText)?.group(1));
    final rank = signed
        ? _number(visited?.querySelector('.fnums')?.text ??
            doc.querySelector('#qiandaobtnnum')?.attributes['value'] ??
            RegExp(r'第\s*(\d+)\s*(?:个|名)').firstMatch(statusText)?.group(1))
        : null;
    int? field(String id) => _number(
        doc.querySelector('#$id, input[name="$id"]')?.attributes['value']);
    int? labeled(RegExp pattern) {
      for (final node in doc.querySelectorAll(
          '.paiming, .comiis_p12 li, .comiis_userlist li, p, li')) {
        if (node.text.length > 180) continue;
        final match = pattern.firstMatch(node.text);
        if (match != null) return _number(match.group(1));
      }
      return null;
    }

    int? mobileValue(Set<String> labels) {
      for (final node in doc.querySelectorAll('.comiis_qdinfo li')) {
        final label = node.querySelector('.comiis_tm')?.text.trim() ?? '';
        if (labels.contains(label)) {
          return _number(node.text.replaceFirst(label, ''));
        }
      }
      return null;
    }

    final continuous = field('lxdays') ??
        mobileValue({'连续签到', '连签'}) ??
        labeled(RegExp(r'(?:连续签到|已连续|连签)[^\d]{0,10}(\d+)\s*天'));
    final total = field('lxtdays') ??
        mobileValue({'累计签到', '总天数', '累计天数'}) ??
        labeled(RegExp(r'(?:累计签到|总签到|总天数|累计天数)[^\d]{0,10}(\d+)\s*天'));
    final level = doc
            .querySelector('#lxlevel, input[name="lxlevel"]')
            ?.attributes['value']
            ?.trim() ??
        '';
    final reward = doc
            .querySelector('#lxreward, input[name="lxreward"]')
            ?.attributes['value']
            ?.trim() ??
        '';
    final user =
        doc.querySelector('h3.mainCon .user a.author, .mainCon a.author');
    final bq = doc.querySelector('a[href*="k_misign_bq"][href*="bid="]');
    final tip = doc.querySelector('#magic_bq_menu .tip_c')?.text.trim() ?? '';
    final bid = _number(RegExp(r'[?&]bid=(\d+)')
        .firstMatch(bq?.attributes['href'] ?? '')
        ?.group(1));
    final retro = _number(RegExp(r'共\s*(\d+)\s*天').firstMatch(tip)?.group(1)) ??
        _number(RegExp(r'\btobqdays\s*[=:]\s*(\d+)').firstMatch(raw)?.group(1));
    return SignHeaderInfo(
      isRecognized: left != null ||
          countNode != null ||
          unsigned != null ||
          visited != null,
      hasPersonalState: known,
      hasTodaySignCount: count != null,
      hasPersonalStats: !guest && (continuous != null || total != null),
      hasContinuousDays: !guest && continuous != null,
      hasTotalDays: !guest && total != null,
      starUsername: starName,
      starUid: _uid(star?.attributes['href']),
      highestCount: highest ?? 0,
      todaySignCount: count ?? 0,
      isSignedToday: signed,
      mySignRank: signed ? (rank ?? mobileValue({'今日排名'})) : null,
      username: user?.text.trim().isNotEmpty == true
          ? user!.text.trim()
          : (identity.username ?? defaultUsername ?? ''),
      uid: identity.uid ?? defaultUid,
      continuousDays: continuous ?? 0,
      totalDays: total ?? 0,
      signLevel: guest || level.isEmpty
          ? ''
          : (level.toLowerCase().startsWith('lv') ? level : 'Lv.$level'),
      rewardIron: guest ? '' : reward,
      retroSignBid: bid,
      retroSignDays: retro ?? 0,
      retroSignTip: tip,
    );
  }

  static DiscuzSignCalendar calendar(String source, {int? year, int? month}) {
    final doc = html.parse(_unwrap(source));
    final headers = doc.querySelectorAll(
        '.calendar_header, .calendar_title, #calendar_title, caption, .cal_month, .month_title');
    for (final node in headers) {
      final match = RegExp(r'(\d{4})\s*(?:年|[-/])\s*(\d{1,2})\s*月?')
          .firstMatch(node.text);
      if (match != null &&
          year != null &&
          month != null &&
          (_number(match.group(1)) != year ||
              _number(match.group(2)) != month)) {
        return const DiscuzSignCalendar(false, {});
      }
    }
    final roots = <Element>[
      ...doc.querySelectorAll(
          '.table_calendar, .calendar, #calendar, .comiis_calendar, #calendar_body, #k_misign_calendar, .calendar_box')
    ];
    for (final table in doc.querySelectorAll('table')) {
      final text = table.text.replaceAll(RegExp(r'\s+'), '');
      if ((text.contains('一二三四五六') ||
              text.contains('日一二三四五六') ||
              text.contains('MonTueWed')) &&
          table.querySelectorAll('td').length >= 20) {
        roots.add(table);
      }
    }
    // AJAX 日历片段可能省略外框，但必须包含真实日期单元格。
    final explicit = doc.querySelectorAll(
        'td.signed, td.btnvisted, td.had_sign, td.btn_have, li.signed, p.signed, .signed_day, .cal_signed');
    if (roots.isEmpty && explicit.isNotEmpty) roots.add(doc.body!);
    if (roots.isEmpty) return const DiscuzSignCalendar(false, {});
    final hasDates = roots.any((root) => root
            .querySelectorAll('td, li, p, .signed_day, .cal_signed')
            .any((node) {
          final raw = node.attributes['data-day'] ??
              node.attributes['day'] ??
              node.text.trim();
          final match = RegExp(r'^(\d{1,2})(?:日)?$').firstMatch(raw);
          final day = match == null ? null : _number(match.group(1));
          return day != null && day >= 1 && day <= 31;
        }));
    if (!hasDates) return const DiscuzSignCalendar(false, {});
    final days = <int>{};
    for (final root in roots) {
      for (final node
          in root.querySelectorAll('td, li, p, .signed_day, .cal_signed')) {
        if (!node.classes.any((c) => const {
              'signed',
              'btnvisted',
              'had_sign',
              'btn_have',
              'signed_day',
              'cal_signed'
            }.contains(c))) {
          continue;
        }
        final text =
            (node.querySelector('a, span, em, strong')?.text ?? node.text)
                .trim();
        final day = _number(node.attributes['data-day'] ??
            node.attributes['day'] ??
            RegExp(r'^(\d{1,2})(?:日)?$').firstMatch(text)?.group(1));
        if (day != null &&
            day >= 1 &&
            day <=
                (year != null && month != null
                    ? DateTime(year, month + 1, 0).day
                    : 31)) {
          days.add(day);
        }
      }
    }
    return DiscuzSignCalendar(true, days);
  }
}
