import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../core/app_config.dart';
import '../models/credit_log.dart';
import '../models/darkroom_entry.dart';
import '../models/forum.dart';
import '../models/forum_header_info.dart';
import '../models/friend_item.dart';
import '../models/horn_message.dart';
import '../models/magic_item.dart';
import '../models/medal_item.dart';
import '../models/notice_item.dart';
import '../models/pm_models.dart';
import '../models/post_block.dart';
import '../models/post_floor.dart';
import '../models/sign_entry.dart';
import '../models/site_stats.dart';
import '../models/smiley.dart';
import '../models/thread_summary.dart';
import '../models/user_space.dart';
import '../models/usergroup_comparison.dart';

/// comiis_app（克米设计）手机模板 HTML 解析器
///
/// 结构依据逆向文档 docs/REVERSE_ENGINEERING.md §3 与 docs/API_CONTRACT.md §3。
class ComiisParser {
  /// 作者个性签名缓存（按 uid 缓存，跨楼层复用）
  static final Map<int, String> authorSigCache = {};
  /// 将相对 URL 解析为绝对 URL（去除重复斜杠，避免 https://klpbbs.com// 导致 404）
  static String? _absolute(String? url) {
    if (url == null || url.isEmpty) return null;
    var trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (trimmed.startsWith('./')) trimmed = trimmed.substring(2);
    while (trimmed.startsWith('/')) {
      trimmed = trimmed.substring(1);
    }
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl
        : '${AppConfig.baseUrl}/';
    return '$base$trimmed';
  }

  /// 将图片 URL 转绝对并保留合法尺寸参数（避免强制修改参数导致 404）
  static String? _image(String? url) {
    final abs = _absolute(url);
    if (abs == null) return null;
    return abs;
  }

  /// 头像 URL：剥离 sunju_facemall 挂件后缀 ##SJ##xxx.png
  static String? _avatarUrl(String? src) {
    if (src == null || src.isEmpty) return null;
    return _absolute(src.split('##SJ##').first);
  }

  /// 头像挂件（sunju_facemall）URL：##SJ## 后缀的 data/attachment/sunju_facemall/fm_{n}.png
  static String? _faceUrlFromAvatar(String? src) {
    if (src == null || src.isEmpty) return null;
    final parts = src.split('##SJ##');
    if (parts.length < 2) return null;
    final face = parts[1].trim();
    if (face.isEmpty) return null;
    return _absolute(face);
  }

  /// 勋章/静态资源 URL：折叠路径中的双斜杠（Discuz 模板 static//image → static/image）
  static String _medalUrl(String? url) {
    final abs = _absolute(url) ?? '';
    if (abs.isEmpty) return '';
    final idx = abs.indexOf('://');
    final prefix = idx >= 0 ? abs.substring(0, idx + 3) : '';
    final rest = idx >= 0 ? abs.substring(idx + 3) : abs;
    return prefix + rest.replaceAll('//', '/');
  }

  /// 从 href 提取 tid（兼容伪静态 thread-{tid}-1-1.html、thread-{tid}.html、ptid={tid} 与 tid={tid}）
  static int? tidFromHref(String href) {
    final m = RegExp(r'thread-(\d+)[-\.]').firstMatch(href);
    if (m != null) return int.tryParse(m.group(1)!);
    final m2 = RegExp(r'(?:ptid|tid)=(\d+)').firstMatch(href);
    return m2 == null ? null : int.tryParse(m2.group(1)!);
  }

  static int? tidFromUrl(String url) => tidFromHref(url);
  static int? _tidFromHref(String href) => tidFromHref(href);

  /// 解析版块主题分类（forumdisplay 分类链接；严格限制在 Discuz 版块分类筛选栏容器内）
  static List<({int typeid, String name})> parseThreadTypes(String html) {
    final doc = html_parser.parse(html);
    final out = <({int typeid, String name})>[];

    // 优先限定在 Discuz PC 与移动端版块分类筛选栏容器内（ul#thread_types, ul.ttp, div.ttp, #filter_type, .comiis_p_fl）
    final typeContainer = doc.querySelector(
      '#thread_types, ul.ttp, div.ttp, #filter_type, .comiis_p_fl, ul.comiis_type, .ttp, #thread_types_menu',
    );
    if (typeContainer == null) return out;
    final scope = typeContainer;

    for (final a in scope.querySelectorAll(
      'a[href*="filter=typeid"], a[href*="typeid="]',
    )) {
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'typeid=(\d+)').firstMatch(href);
      if (m == null) continue;
      final typeid = int.tryParse(m.group(1)!);
      if (typeid == null || typeid <= 0) continue;

      final clone = a.clone(true);
      clone
          .querySelectorAll('span, em, i, b, small, .num, .xg1')
          .forEach((e) => e.remove());
      var name = _cleanTitle(clone.text);
      if (name.isEmpty) name = _cleanTitle(a.text);
      name = name
          .replaceAll(RegExp(r'\s*\(\d+\)$|\s*\[\d+\]$|\s*\d+$'), '')
          .trim();

      if (name.isNotEmpty &&
          name.length <= 20 &&
          name != '全部' &&
          name != '服务器列表' &&
          !out.any((t) => t.typeid == typeid)) {
        out.add((typeid: typeid, name: name));
      }
    }
    return out;
  }

  /// 解析勋章中心（home.php?mod=medal 支持 PC 与移动端结构，优先解析具备完整价格与规则的 PC 结构）
  static List<MedalItem> parseMedals(String html) {
    final doc = html_parser.parse(html);
    final out = <MedalItem>[];
    final seenIds = <int>{};

    // 1. PC 端完整勋章网格与详细规则（ul.mgcl li）
    for (final li in doc.querySelectorAll('ul.mgcl li')) {
      final imgDiv = li.querySelector('.mg_img');
      if (imgDiv == null) continue;
      final idAttr = imgDiv.attributes['id'] ?? '';
      final id = int.tryParse(idAttr.replaceFirst('medal_', ''));
      if (id == null || !seenIds.add(id)) continue;
      final imgEl = imgDiv.querySelector('img');
      final img = _medalUrl(imgEl?.attributes['src']);
      var name = imgEl?.attributes['alt'] ?? '';
      if (name.isEmpty) {
        name = li.querySelector('p.xw1')?.text.trim() ?? '';
      }
      final menuDiv = doc.querySelector('#medal_${id}_menu .tip_c');
      String desc = '';
      String req = '';
      if (menuDiv != null) {
        final ps = menuDiv.querySelectorAll('p');
        if (ps.isNotEmpty) desc = ps[0].text.trim();
        if (ps.length > 1) {
          req = ps[1].text.replaceAll(RegExp(r'\s+'), ' ').trim();
        }
      }
      out.add(MedalItem(
        id: id,
        name: name.isNotEmpty ? name : '勋章 #$id',
        desc: desc,
        requirement: req.isNotEmpty ? req : '人工授予',
        img: img,
      ));
    }

    // 2. 移动端与标准 ID 节点（p/li/div[id^="medal_"]）
    if (out.isEmpty) {
      for (final el in doc.querySelectorAll(
        'p[id^="medal_"], li[id^="medal_"], div[id^="medal_"]',
      )) {
        final idAttr = el.attributes['id'] ?? '';
        final id = int.tryParse(idAttr.replaceFirst('medal_', ''));
        if (id == null || !seenIds.add(id)) continue;
        String name = '', desc = '', img = '';
        final imgEl = el.querySelector('img');
        if (imgEl != null) {
          img = _medalUrl(
            imgEl.attributes['src'] ?? imgEl.attributes['data-src'],
          );
          name = imgEl.attributes['alt'] ?? '';
        }
        final a = el.querySelector('a');
        final onclick = a?.attributes['onclick'] ?? '';
        final titM = RegExp(r'kmtit[^>]*>([^<]+)').firstMatch(onclick);
        if (titM != null && titM.group(1)!.trim().isNotEmpty) {
          name = titM.group(1)!.trim();
        }
        final txtM = RegExp(r'kmtxt[^>]*>([^<]*)').firstMatch(onclick);
        if (txtM != null) {
          desc = txtM.group(1)!.replaceAll('\n', ' ').trim();
        }
        if (name.isEmpty) name = el.text.trim();
        out.add(MedalItem(
          id: id,
          name: name,
          desc: desc,
          requirement: '人工授予',
          img: img,
        ));
      }
    }

    // 3. PC 端其他列表模式（ul.medal_list li, .medallist li, .bm_c li）
    if (out.isEmpty) {
      for (final el in doc.querySelectorAll(
        'ul.medal_list li, .medallist li, .bm_c li, div.medal_list li',
      )) {
        final imgEl = el.querySelector('img');
        if (imgEl == null) continue;
        final img = _medalUrl(
          imgEl.attributes['src'] ?? imgEl.attributes['data-src'],
        );
        final name =
            imgEl.attributes['alt'] ??
            el.querySelector('h4, p.title, span.name')?.text.trim() ??
            '';
        final desc =
            el.querySelector('p.desc, div.desc, p.xg1')?.text.trim() ?? '';
        final applyA = el.querySelector('a[href*="medalid="]');
        int id = out.length + 1;
        if (applyA != null) {
          final m = RegExp(
            r'medalid=(\d+)',
          ).firstMatch(applyA.attributes['href'] ?? '');
          if (m != null) id = int.tryParse(m.group(1)!) ?? id;
        }
        if (img.isNotEmpty && seenIds.add(id)) {
          out.add(MedalItem(
            id: id,
            name: name.isNotEmpty ? name : '勋章 #$id',
            desc: desc,
            requirement: '人工授予',
            img: img,
          ));
        }
      }
    }

    return out;
  }

  /// 解析积分变动流水记录（home.php?mod=spacecp&ac=credit&op=log 支持移动端与 PC 端）
  static List<CreditLogEntry> parseCreditLogs(String html) {
    final doc = html_parser.parse(html);
    final out = <CreditLogEntry>[];
    final seenKeys = <String>{};

    void addLog({
      required String creditType,
      required String amount,
      required String operation,
      required String detail,
      required String timeText,
    }) {
      final op = operation.trim();
      final dt = detail.trim();
      final tm = timeText.trim();
      if (op.isEmpty && amount.isEmpty) return;
      final key = '${tm}_${op}_${amount}_$dt';
      if (seenKeys.add(key)) {
        final formattedAmount = amount.startsWith('+') || amount.startsWith('-') ? amount : '+$amount';
        out.add(CreditLogEntry(
          creditType: creditType.isNotEmpty ? creditType : '铁粒',
          amount: formattedAmount,
          operation: op.isNotEmpty ? op : '积分变动',
          detail: dt,
          timeText: tm,
        ));
      }
    }

    // 1. 移动端 Comiis 结构（.comiis_jflist li, .comiis_credit_list li, li.b_b, li）
    final listCandidates = doc.querySelectorAll(
      '.comiis_jflist li, .comiis_credit_list li, .comiis_credit li, .comiis_p12 li, .comiis_box li, ul.comiis_userlist li, li.b_b, li',
    );
    for (final el in listCandidates) {
      final text = el.text.trim();
      if (text.isEmpty || text.length < 5) continue;

      // 必须包含有效变动时间
      final tm = RegExp(r'(\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)').firstMatch(text);
      if (tm == null) continue;
      final timeText = tm.group(1)!;

      String creditType = '铁粒';
      String amount = '';
      final leftEl = el.querySelector('.span_0, .span_1, .kmimg, .kmleft, div:first-child, span:first-child');
      if (leftEl != null) {
        final lt = leftEl.text.replaceAll('\n', ' ').trim();
        final typeM = RegExp(r'(铁粒|金粒|绿宝石|贡献|人气|威望|金币|经验|积分)').firstMatch(lt);
        if (typeM != null) creditType = typeM.group(1)!;
        final valM = RegExp(r'([+-]?\d+)').firstMatch(lt);
        if (valM != null) amount = valM.group(1)!;
      }
      if (amount.isEmpty) {
        final am = RegExp(r'([+-]\d+)').firstMatch(text) ?? RegExp(r'([+-]?\d+)').firstMatch(text);
        if (am != null) amount = am.group(1)!;
      }

      String operation = '';
      String detail = '';
      final conEl = el.querySelector('.kmcon, .km_con, .flex, div:nth-child(2)');
      if (conEl != null) {
        final pTags = conEl.querySelectorAll('p, h3, h4, strong, div, .f14, .f16');
        if (pTags.isNotEmpty) {
          operation = pTags.first.text.trim();
          if (pTags.length > 1) detail = pTags[1].text.trim();
        } else {
          operation = conEl.text.trim();
        }
      }

      if (operation.isEmpty || operation == text) {
        final lines = text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != timeText && s != creditType && s != amount && s != '$creditType$amount')
            .toList();
        if (lines.isNotEmpty) {
          operation = lines.first;
          if (lines.length > 1) detail = lines.sublist(1).join(' ');
        }
      }

      if (operation.isNotEmpty || amount.isNotEmpty) {
        addLog(
          creditType: creditType,
          amount: amount.isNotEmpty ? amount : '+0',
          operation: operation,
          detail: detail,
          timeText: timeText,
        );
      }
    }

    // 2. PC / 移动端表格结构（table.dt tr, table.tfm tr, table.tl tr, table tr）
    if (out.isEmpty) {
      for (final tr in doc.querySelectorAll('table.dt tr, table.tfm tr, table.tl tr, table tr')) {
        final tds = tr.querySelectorAll('td');
        if (tds.length < 2) continue;
        final rawText = tds.map((td) => td.text.trim()).toList();
        String creditType = '铁粒';
        String amount = '';
        String operation = '';
        String detail = '';
        String timeText = '';

        if (tds.length >= 3) {
          operation = tds[0].text.trim();
          final creditCol = tds[1].text.trim();
          final cm = RegExp(r'(铁粒|金粒|绿宝石|贡献|人气|经验|积分)\s*([+-]?\d+)').firstMatch(creditCol);
          if (cm != null) {
            creditType = cm.group(1)!;
            amount = cm.group(2)!;
          } else {
            final vm = RegExp(r'([+-]?\d+)').firstMatch(creditCol);
            if (vm != null) amount = vm.group(1)!;
          }
          if (tds.length >= 4) {
            detail = tds[2].text.trim();
            timeText = tds.last.text.trim();
          } else {
            timeText = tds[2].text.trim();
          }
        }

        if (amount.isEmpty || operation.isEmpty) {
          for (final text in rawText) {
            final tm = RegExp(r'\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?').firstMatch(text);
            if (tm != null && timeText.isEmpty) {
              timeText = tm.group(0)!;
              continue;
            }
            final cm = RegExp(r'(铁粒|金粒|绿宝石|贡献|人气|经验|积分)\s*([+-]?\d+)').firstMatch(text);
            if (cm != null && amount.isEmpty) {
              creditType = cm.group(1)!;
              amount = cm.group(2)!;
              continue;
            }
            final vm = RegExp(r'^([+-]?\d+)$').firstMatch(text);
            if (vm != null && amount.isEmpty && !text.contains('-') && text.length < 8) {
              amount = vm.group(1)!;
              continue;
            }
            if (operation.isEmpty && text.isNotEmpty && !text.contains('202') && !text.contains(':')) {
              operation = text;
            } else if (detail.isEmpty && text.isNotEmpty && !text.contains('202')) {
              detail = text;
            }
          }
        }

        if (operation.isNotEmpty || amount.isNotEmpty) {
          addLog(
            creditType: creditType,
            amount: amount.isNotEmpty ? amount : '+0',
            operation: operation,
            detail: detail,
            timeText: timeText,
          );
        }
      }
    }

    return out;
  }

  /// 解析积分基础概况（home.php?mod=spacecp&ac=credit&op=base / &mobile=2）
  static CreditBaseInfo parseCreditBase(String html) {
    String totalCredits = '';
    final details = <String, String>{};
    String? formula;

    final doc = html_parser.parse(html);
    final text = doc.body?.text ?? html;

    // 1. 顶部总积分（对应：积分: 6994）
    final totalM = RegExp(r'(?:总积分|积分)\s*[:：\s]*(\d+)').firstMatch(text);
    if (totalM != null) {
      totalCredits = totalM.group(1)!;
    }

    // 2. 细项提取（对应：铁粒:12805 粒、经验:6994 EP、铁锭[已弃用]:0 块、贡献:0 点、钻石:0 个）
    final matches = RegExp(
      r'(铁粒|经验|铁锭\[已弃用\]|铁锭|贡献|钻石|人气|威望|金币|金粒)\s*[:：\s]*(\d+)\s*(?:粒|EP|块|点|个)?',
    ).allMatches(text);
    for (final m in matches) {
      final name = m.group(1)!;
      final val = m.group(2)!;
      if (!details.containsKey(name)) {
        details[name] = val;
      }
    }

    // 如果未获取到总积分，但有经验，在苦力怕论坛中 总积分 = 经验
    if (totalCredits.isEmpty && details['经验'] != null) {
      totalCredits = details['经验']!;
    }

    // 3. 积分公式
    if (html.contains('总积分=')) {
      final fm = RegExp(r'总积分=[^\s<]+').firstMatch(html);
      if (fm != null) formula = fm.group(0);
    } else {
      formula = '总积分=经验';
    }

    return CreditBaseInfo(
      totalCredits: totalCredits,
      details: details,
      ruleFormula: formula,
    );
  }

  /// 解析道具商店（home.php?mod=magic&action=shop 支持 PC 与移动端结构）
  static List<MagicItem> parseMagicShop(String html) {
    final doc = html_parser.parse(html);
    final out = <MagicItem>[];
    final seenNames = <String>{};

    // 1. 移动端结构 (div.comiis_userlist / li / div[id^="magic_"])
    for (final el in doc.querySelectorAll('li, div[id^="magic_"], div.comiis_p12 li')) {
      final imgEl = el.querySelector('img[src*="magic"], img[src*="image"]');
      if (imgEl == null) continue;
      final src = _absolute(imgEl.attributes['src']) ?? '';
      if (!src.contains('magic') && !src.contains('image')) continue;

      final nameEl = el.querySelector('p.tit, .xw1, strong, h4') ?? el.querySelector('p');
      final name = nameEl?.text.trim() ?? imgEl.attributes['alt'] ?? '';
      if (name.isEmpty || !seenNames.add(name)) continue;

      // 提取价格（如 铁粒 30 粒/张）
      int price = 0;
      final pm = RegExp(r'(\d+)\s*(?:粒/张|粒|个|铁粒)').firstMatch(el.text);
      if (pm != null) price = int.tryParse(pm.group(1)!) ?? 0;

      // 提取 ID / mid
      int id = out.length + 1;
      final a = el.querySelector('a[href*="mid="], a[href*="magicid="]');
      if (a != null) {
        final href = a.attributes['href'] ?? '';
        final idM = RegExp(r'(?:mid|magicid)=(\d+)').firstMatch(href);
        if (idM != null) id = int.tryParse(idM.group(1)!) ?? id;
      }

      // 描述
      String desc = '';
      final descEl = el.querySelector('p.txt, .xg1, .desc');
      if (descEl != null) desc = descEl.text.trim();

      out.add(MagicItem(
        id: id,
        name: name,
        desc: desc,
        price: price,
        img: src,
      ));
    }

    // 2. PC 端结构 (table / ul.cl li / .bm_c li)
    if (out.isEmpty) {
      for (final el in doc.querySelectorAll('table.dt tr, ul.tb_c li, div.bm_c li')) {
        final imgEl = el.querySelector('img');
        if (imgEl == null) continue;
        final src = _absolute(imgEl.attributes['src']) ?? '';
        final name = imgEl.attributes['alt'] ?? el.querySelector('strong, a')?.text.trim() ?? '';
        if (name.isEmpty || !seenNames.add(name)) continue;

        int price = 0;
        final pm = RegExp(r'(\d+)\s*(?:粒|个|铁粒)').firstMatch(el.text);
        if (pm != null) price = int.tryParse(pm.group(1)!) ?? 0;

        int id = out.length + 1;
        final a = el.querySelector('a[href*="mid="], a[href*="magicid="]');
        if (a != null) {
          final idM = RegExp(r'(?:mid|magicid)=(\d+)').firstMatch(a.attributes['href'] ?? '');
          if (idM != null) id = int.tryParse(idM.group(1)!) ?? id;
        }

        out.add(MagicItem(
          id: id,
          name: name,
          desc: el.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
          price: price,
          img: src,
        ));
      }
    }

    // 3. 苦力怕论坛标准 6 款官方道具兜底（保证离线或弱网下 1:1 精确呈现）
    if (out.isEmpty) {
      return [
        const MagicItem(
          id: 1,
          identifier: 'checkin',
          name: '补签卡',
          desc: '补签卡可以用来补签过去错过的签到日期，领取漏签奖励。',
          price: 30,
          unit: '粒/张',
          img: 'https://klpbbs.com/static/image/magic/checkin.small.gif',
        ),
        const MagicItem(
          id: 2,
          identifier: 'namecard',
          name: '改名卡',
          desc: '改名卡可以修改您在苦力怕论坛的显示用户名。',
          price: 100,
          unit: '粒/张',
          img: 'https://klpbbs.com/static/image/magic/namecard.small.gif',
        ),
        const MagicItem(
          id: 3,
          identifier: 'bump',
          name: '提升卡',
          desc: '提升卡可以将您指定的帖子主题提升到所在版块的最顶部。',
          price: 10,
          unit: '粒/张',
          img: 'https://klpbbs.com/static/image/magic/bump.small.gif',
        ),
        const MagicItem(
          id: 4,
          identifier: 'wish',
          name: '祈愿池',
          desc: '向祈愿池投入铁粒进行幸运祈愿抽奖，有机会获得丰厚奖励。',
          price: 50,
          unit: '粒/张',
          img: 'https://klpbbs.com/static/image/magic/wish.small.gif',
        ),
        const MagicItem(
          id: 5,
          identifier: 'anonymous',
          name: '匿名卡',
          desc: '在支持匿名的主题或版块中匿名发表帖子，隐藏个人身份。',
          price: 40,
          unit: '粒/张',
          img: 'https://klpbbs.com/static/image/magic/anonymous.small.gif',
        ),
        const MagicItem(
          id: 6,
          identifier: 'observer',
          name: '观察者',
          desc: '侦测并查看指定受保护或隐藏内容，以及查看隐身在线用户。',
          price: 99,
          unit: '粒/张',
          img: 'https://klpbbs.com/static/image/magic/observer.small.gif',
        ),
      ];
    }

    return out;
  }

  /// 解析道具包容量与当前铁粒状态
  static MagicBagInfo parseMagicBagInfo(String html, {int? defaultIron}) {
    int used = 0;
    int total = 500;
    int iron = defaultIron ?? 0;

    final doc = html_parser.parse(html);
    final text = doc.body?.text ?? html;

    final capM = RegExp(r'(?:我的道具包容量|道具包容量|容量)[:：\s]*(\d+)\s*/\s*(\d+)').firstMatch(text);
    if (capM != null) {
      used = int.tryParse(capM.group(1)!) ?? 0;
      total = int.tryParse(capM.group(2)!) ?? 500;
    } else {
      final usedM = RegExp(r'(?:已用容量|当前容量)[:：\s]*(\d+)').firstMatch(text);
      if (usedM != null) used = int.tryParse(usedM.group(1)!) ?? 0;
    }

    final ironM = RegExp(r'(?:目前有|现有|账户|拥有)?\s*铁粒\s*[:：\s]*(\d+)|铁粒\s*(\d+)\s*粒').firstMatch(text);
    if (ironM != null) {
      iron = int.tryParse(ironM.group(1) ?? ironM.group(2) ?? '') ?? iron;
    }

    return MagicBagInfo(
      usedCapacity: used,
      totalCapacity: total,
      ironCount: iron,
    );
  }

  /// 解析用户拥有的道具包列表（home.php?mod=magic&action=mybox）
  static List<MagicItem> parseMyMagics(String html) {
    final doc = html_parser.parse(html);
    final out = <MagicItem>[];
    final seenNames = <String>{};

    for (final imgEl in doc.querySelectorAll('img')) {
      final src = _absolute(imgEl.attributes['src']) ?? '';
      if (!src.contains('/magic/') && !src.contains('magic') && !src.contains('small.gif')) continue;

      // 向上寻找该道具卡片的最外层容器 (li 或 tr)
      html_dom.Element? container = imgEl.parent;
      while (container != null &&
          container.localName != 'li' &&
          container.localName != 'tr' &&
          container.parent != null &&
          container.parent!.localName != 'ul' &&
          container.parent!.localName != 'tbody' &&
          container.parent!.localName != 'body') {
        container = container.parent;
      }
      final box = container ?? imgEl.parent ?? imgEl;

      // 提取道具名称
      String name = imgEl.attributes['alt'] ?? '';
      if (name.isEmpty) {
        final titEl = box.querySelector('h2, h3, strong, p.tit, .xw1, a');
        name = titEl?.text.trim() ?? '';
      }
      if (name.isEmpty) {
        for (final k in ['附件增容卡', '提升卡', '改名卡', '补签卡', '祈愿池', '匿名卡', '观察者']) {
          if (box.text.contains(k)) {
            name = k;
            break;
          }
        }
      }
      if (name.isEmpty || !seenNames.add(name)) continue;

      // 提取数量（如 数量: 9 或 拥有 9 张）
      int count = 1;
      final countM = RegExp(r'数量[:：\s]*(\d+)|拥有\s*(\d+)|(\d+)\s*张').firstMatch(box.text);
      if (countM != null) {
        count = int.tryParse(countM.group(1) ?? countM.group(2) ?? countM.group(3) ?? '') ?? 1;
      }

      int weight = 10;
      final wm = RegExp(r'重量[:：\s]*(\d+)').firstMatch(box.text);
      if (wm != null) weight = int.tryParse(wm.group(1)!) ?? 10;

      int id = out.length + 1;
      final a = box.querySelector('a[href*="magicid="], a[href*="mid="]');
      if (a != null) {
        final idM = RegExp(r'(?:mid|magicid)=(\d+)').firstMatch(a.attributes['href'] ?? '');
        if (idM != null) id = int.tryParse(idM.group(1)!) ?? id;
      }

      String desc = box.querySelector('p.txt, .xg1')?.text.trim() ?? '';

      // 操作权限判定：
      // 在苦力怕论坛中，提升卡只能在帖子详情中提升主题，背包中只有[赠送|出售]
      // 附件增容卡、改名卡、补签卡等可以在背包直接使用，显示[使用|赠送|出售]
      final bool isBump = name.contains('提升卡');
      final bool canUse = !isBump;
      const bool canGive = true;
      const bool canDrop = true;

      out.add(MagicItem(
        id: id,
        name: name,
        desc: desc,
        count: count,
        weight: weight,
        img: src,
        canUse: canUse,
        canGive: canGive,
        canDrop: canDrop,
      ));
    }

    return out;
  }

  /// 解析道具操作记录（home.php?mod=magic&action=log）
  static List<MagicLogEntry> parseMagicLogs(String html) {
    final doc = html_parser.parse(html);
    final out = <MagicLogEntry>[];
    final seenKeys = <String>{};
    const blacklist = {
      '发个帖', '签到', '看资讯', '做任务', '首页', '版块', '我的', '消息', '设置', '道具名称', '无记录',
      '使用记录', '购买记录', '赠送记录', '获赠记录', '上一页', '下一页', '返回', '道具中心', '条记录',
    };

    // 遍历所有可能的行/卡片元素
    for (final el in doc.querySelectorAll('li, tr, .comiis_log_li, div.b_b')) {
      final text = el.text.trim();
      final tm = RegExp(r'\b(20\d{2}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?)\b').firstMatch(text);
      if (tm == null) continue;
      final timeStr = tm.group(1)!;

      // 提取道具名称
      String name = '';
      final titEl = el.querySelector('h2, h3, strong, a.f_ok, a.xw1, td:first-child');
      if (titEl != null) {
        final t = titEl.text.trim();
        if (t.isNotEmpty && !blacklist.contains(t) && t.length <= 15) {
          name = t;
        }
      }
      if (name.isEmpty) {
        for (final a in el.querySelectorAll('a')) {
          final t = a.text.trim();
          if (t.isNotEmpty && !blacklist.contains(t) && t.length <= 15 && (t.endsWith('卡') || t.contains('池') || t.contains('者') || t.contains('签到') || t.contains('提升'))) {
            name = t;
            break;
          }
        }
      }
      if (name.isEmpty) {
        for (final word in text.split(RegExp(r'\s+'))) {
          if (word.isNotEmpty && !blacklist.contains(word) && word.length <= 15 && (word.endsWith('卡') || word.contains('池') || word.contains('者'))) {
            name = word;
            break;
          }
        }
      }
      if (name.isEmpty || blacklist.contains(name)) continue;

      final key = '$timeStr-$name';
      if (!seenKeys.add(key)) continue;

      // 提取附加说明（如：对帖子使用该道具，点击查看帖子 / 对用户使用该道具，点击查看用户）
      String desc = '';
      final pEl = el.querySelector('p, .desc, .txt, .note, td:nth-child(2)');
      if (pEl != null) {
        desc = pEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      }
      if (desc.isEmpty) {
        final rem = text.replaceAll(name, '').replaceAll(timeStr, '').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (rem.isNotEmpty && rem.length < 80 && !blacklist.any((b) => rem.startsWith(b))) {
          desc = rem;
        }
      }
      if (desc == name || desc == timeStr) desc = '';

      out.add(MagicLogEntry(
        magicName: name,
        action: desc.isNotEmpty ? desc : '使用该道具',
        time: timeStr,
        target: desc,
        note: desc,
      ));
    }

    return out;
  }

  /// 兼容旧版解析
  static List<({int id, String name, String img, String desc})> parseMagics(
    String html,
  ) {
    final shop = parseMagicShop(html);
    return shop.map((m) => (id: m.id, name: m.name, img: m.img, desc: m.desc)).toList();
  }

  /// 解析任务中心（home.php?mod=task 的 task 条目）
  static List<({int id, String name, String reward})> parseTasks(String html) {
    final doc = html_parser.parse(html);
    final out = <({int id, String name, String reward})>[];
    // 任务条目：a[href*="do=view&id="] > img[alt=任务名]；奖励在父 li 文本
    for (final a in doc.querySelectorAll('a[href*="do=view&id="]')) {
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'id=(\d+)').firstMatch(href);
      if (m == null) continue;
      final id = int.tryParse(m.group(1)!);
      if (id == null) continue;
      final img = a.querySelector('img');
      final name = img?.attributes['alt'] ?? '';
      final li = a.parent;
      final reward = li?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      if (name.isEmpty) continue;
      out.add((id: id, name: name, reward: reward));
      if (out.length >= 20) break;
    }
    return out;
  }

  /// 解析推广中心（fromuid 链接 + 说明文本）
  static List<({String label, String url})> parsePromotion(String html) {
    final doc = html_parser.parse(html);
    final out = <({String label, String url})>[];
    // 推广链接在 textarea#copy（真实结构）
    final ta = doc.querySelector('textarea#copy, textarea[readonly]');
    if (ta != null) {
      final url = ta.text.trim();
      if (url.isNotEmpty) out.add((label: '推广链接', url: url));
    }
    // 兜底：a[href*=fromuid=]
    for (final a in doc.querySelectorAll(
      'a[href*="fromuid="], a[href*="fromuser="]',
    )) {
      final url = _absolute(a.attributes['href'] ?? '');
      if (url == null) continue;
      final label = a.text.trim().isNotEmpty ? a.text.trim() : '推广链接';
      if (!out.any((e) => e.url == url)) out.add((label: label, url: url));
      if (out.length >= 10) break;
    }
    return out;
  }

  /// 判断时间字符串是否属于近期活动（如 Discuz 默认 20 分钟在线窗口）
  static bool _isRecentActivity(String text) {
    if (text.isEmpty) return false;
    final t = text.trim();
    if (t == '刚刚' || t.contains('秒前') || t.contains('刚刚在线')) return true;
    final minMatch = RegExp(r'(\d+)\s*分钟前').firstMatch(t);
    if (minMatch != null) {
      final mins = int.tryParse(minMatch.group(1)!) ?? 999;
      return mins <= 20;
    }
    final dtMatch = RegExp(
      r'(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch(t);
    if (dtMatch != null) {
      try {
        final year = int.parse(dtMatch.group(1)!);
        final month = int.parse(dtMatch.group(2)!);
        final day = int.parse(dtMatch.group(3)!);
        final hour = int.parse(dtMatch.group(4)!);
        final minute = int.parse(dtMatch.group(5)!);
        final dt = DateTime(year, month, day, hour, minute);
        final diff = DateTime.now().difference(dt).abs();
        return diff.inMinutes <= 20;
      } catch (_) {}
    }
    return false;
  }

  /// 解析好友列表（精确支持 Discuz 移动端 Comiis 全结构与 PC 端结构，对齐截图一）
  static List<FriendItem> parseFriends(String html, {int? excludeUid}) {
    if (html.isEmpty) return const [];
    final doc = html_parser.parse(html);

    // 移除全局非内容节点（页头、页脚、侧边栏、浮动菜单、导航），防止误解析非好友链接
    doc.querySelectorAll(
      '#nv, #toptb, #hd, #ft, #comiis_nav, .comiis_nav, .comiis_foot, .comiis_footer, '
      '.comiis_head, .comiis_header, .comiis_sidenv, .comiis_menu, .comiis_gobtn_tbox, '
      '.comiis_sidenv_box, .comiis_nav_box, #comiis_foot_menu, script, style, header, footer',
    ).forEach((e) => e.remove());

    final out = <FriendItem>[];
    final seen = <int>{};

    // 1. 优先解析移动端 Comiis 好友列表结构（对齐截图一：头像、名称、用户组与积分、快捷按钮）
    final mobileFriends = doc.querySelectorAll(
      '.comiis_friend_list li, .comiis_friend_list div.comiis_flex, '
      '.comiis_userlist div.comiis_flex, .comiis_user_list div.comiis_flex, '
      '.comiis_userlist li, .comiis_user_list li, '
      '.comiis_mh_userlist div.comiis_flex, .comiis_mh_userlist li, '
      '.comiis_p12 div.comiis_flex, .comiis_p12 li, .comiis_box div.comiis_flex, '
      '.comiis_box li, div.b_b, li.b_b, div.comiis_flex',
    );

    for (final el in mobileFriends) {
      final a = el.querySelector(
        'h4 a, div.avt a, a.xi2, a[href*="space-uid-"], a[href*="mod=space&uid="]',
      );
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final uidM = RegExp(r'space-uid-(\d+)\.html|(?:uid=)(\d+)').firstMatch(href);
      if (uidM == null) continue;
      final uid = int.tryParse(uidM.group(1) ?? uidM.group(2) ?? '');
      if (uid == null || uid <= 0 || (excludeUid != null && uid == excludeUid) || !seen.add(uid)) continue;

      var name = '';
      final h4 = el.querySelector('h4 a, h4, p.title, .f16, .f15, strong, a.xi2');
      if (h4 != null) {
        final t = h4.text.trim();
        if (t.isNotEmpty && t != '好友' && t != '空间' && t != '个人资料') {
          name = t;
        }
      }
      if (name.isEmpty) {
        final t = a.text.trim();
        if (t.isNotEmpty && t != '好友' && t != '空间' && t != '个人资料') name = t;
      }
      if (name.isEmpty) {
        final img = el.querySelector('img');
        name = img?.attributes['alt'] ?? '';
      }
      if (name.isEmpty || name.contains('http') || name.length > 30) {
        name = '坛友 $uid';
      }

      final imgEl = el.querySelector('img[src*="avatar"], img[data-src*="avatar"], div.avt img, img');
      final rawImg = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'];
      final avatar = _avatarUrl(rawImg) ?? AppConfig.avatarUrl(uid, size: 'middle');

      String group = '';
      String credits = '';
      String recentActivity = '';
      String note = '';

      final infoEl = el.querySelector('p.maxh, p.xg1, div.xg1, .f12, .desc, .km_time');
      if (infoEl != null) {
        final fullText = infoEl.text.replaceAll('\u00a0', ' ').trim();
        final fontEl = infoEl.querySelector('font, span.xi1, .b_ok');
        if (fontEl != null && fontEl.text.trim().isNotEmpty) {
          group = fontEl.text.trim();
        }

        final credM = RegExp(r'积分[数:：]?\s*(\d+)').firstMatch(fullText);
        if (credM != null) {
          credits = credM.group(1)!;
        }

        if (group.isEmpty) {
          final groupM = RegExp(
            r'(Lv\.\d+[^积分\s]+|版主|超级版主|管理员|荣誉会员|贵宾会员|金牌会员|元老会员|普通会员|禁止发言|等待验证会员)',
          ).firstMatch(fullText);
          if (groupM != null) {
            group = groupM.group(1)!.trim();
          }
        }

        // 提取来访/足迹时间
        final timeM = RegExp(
          r'(\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?|\d+\s*(?:分钟|小时|天)前|刚刚)',
        ).firstMatch(fullText);
        if (timeM != null) {
          recentActivity = timeM.group(1)!;
        }
      }

      // 是否已关注（检测页面中的 取消关注 / 取消 按钮）
      final isFollowing = el.querySelector('a')?.text.contains('取消') == true ||
          el.outerHtml.contains('取消关注') ||
          el.outerHtml.contains('op=del');

      final elHtml = el.outerHtml;
      final bool hasOnlineMark = (el.querySelector(
            'img:not(.authicn)[src*="online.png"], img:not(.authicn)[src*="online.gif"], img[src*="ol.gif"], img[title*="当前在线"], img[title="在线"], .comiis_o, em.online, span.online',
          ) !=
          null ||
          el.classes.contains('online') ||
          elHtml.contains('title="当前在线"') ||
          elHtml.contains('class="comiis_o"') ||
          elHtml.contains('>当前在线<'));

      final bool hasOfflineMark = (el.querySelector(
            'img[src*="offline.png"], img[src*="offline.gif"], img[title*="当前离线"], img[title="离线"], .comiis_f, em.offline, span.offline',
          ) !=
          null ||
          elHtml.contains('title="当前离线"') ||
          elHtml.contains('class="comiis_f"') ||
          elHtml.contains('>当前离线<'));

      final isFriendOnline = (hasOnlineMark && !hasOfflineMark) ||
          (!hasOfflineMark && (_isRecentActivity(recentActivity) || _isRecentActivity(credits) || _isRecentActivity(group)));

      out.add(
        FriendItem(
          uid: uid,
          username: _cleanTitle(name),
          avatarUrl: avatar,
          usergroup: _cleanTitle(group),
          credits: credits,
          isOnline: isFriendOnline,
          isFollowing: isFollowing,
          note: note,
          recentActivity: recentActivity,
        ),
      );
    }

    if (out.isNotEmpty) return out;

    // 2. 解析 Discuz PC 经典好友结构（ul#friend_ul li.bbda, ul.buddy li, div#friend_ul li）
    final pcFriends = doc.querySelectorAll(
      'ul#friend_ul > li, ul.buddy > li, div#friend_ul li, li.bbda, div.bbda',
    );

    for (final li in pcFriends) {
      final a = li.querySelector(
        'h4 a[href*="space-uid-"]:not([href*="changenum"]):not([href*="op="]), '
        'h4 a[href*="mod=space&uid="]:not([href*="changenum"]):not([href*="op="]), '
        'div.avt a[href*="space-uid-"], div.avt a[href*="mod=space&uid="], '
        'a.xi2, a[href*="space-uid-"]:not([href*="changenum"]):not([href*="op="])',
      );
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final uidM = RegExp(r'space-uid-(\d+)\.html|(?:uid=)(\d+)').firstMatch(href);
      if (uidM == null) continue;
      final uid = int.tryParse(uidM.group(1) ?? uidM.group(2) ?? '');
      if (uid == null || uid <= 0 || (excludeUid != null && uid == excludeUid) || !seen.add(uid)) continue;

      // 提取真实昵称
      var name = '';
      final h4Links = li.querySelectorAll('h4 a');
      for (final h4a in h4Links) {
        final t = h4a.text.trim();
        final h = h4a.attributes['href'] ?? '';
        if (t.isNotEmpty && !t.startsWith('热度') && !h.contains('changenum') && !h.contains('op=')) {
          name = t;
          break;
        }
      }
      if (name.isEmpty) {
        final t = a.text.trim();
        if (t.isNotEmpty && !t.startsWith('热度')) name = t;
      }
      if (name.isEmpty) {
        final img = li.querySelector('img');
        name = img?.attributes['alt'] ?? '';
      }
      if (name.isEmpty || name.startsWith('热度') || name.contains('http') || name.length > 40) {
        name = '坛友 $uid';
      }

      // 提取头像
      final imgEl = li.querySelector('div.avt img, img[src*="avatar"], img[data-src*="avatar"], img');
      final rawImg = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'];
      final avatar = _avatarUrl(rawImg) ?? AppConfig.avatarUrl(uid, size: 'middle');

      // 提取附注/动态说明
      String signature = '';
      final descEl = li.querySelector('p.maxh, p.xg1, div.xg1, .desc');
      if (descEl != null) {
        final t = descEl.text.trim().replaceAll('\u00a0', ' ');
        if (t.isNotEmpty && !t.contains('热度') && !t.contains('收听TA') && t != name && t != '$name ()') {
          signature = t;
        }
      }

      final liHtml = li.outerHtml;
      final bool hasOnlineMark = (li.querySelector(
            'img:not(.authicn)[src*="online.png"], img:not(.authicn)[src*="online.gif"], img[src*="ol.gif"], img[title*="当前在线"], img[title="在线"], .comiis_o, em.online, span.online',
          ) !=
          null ||
          li.classes.contains('online') ||
          liHtml.contains('title="当前在线"') ||
          liHtml.contains('class="comiis_o"') ||
          liHtml.contains('>当前在线<'));

      final bool hasOfflineMark = (li.querySelector(
            'img[src*="offline.png"], img[src*="offline.gif"], img[title*="当前离线"], img[title="离线"], .comiis_f, em.offline, span.offline',
          ) !=
          null ||
          liHtml.contains('title="当前离线"') ||
          liHtml.contains('class="comiis_f"') ||
          liHtml.contains('>当前离线<'));

      final isFriendOnline = (hasOnlineMark && !hasOfflineMark) ||
          (!hasOfflineMark && _isRecentActivity(signature));

      out.add(
        FriendItem(
          uid: uid,
          username: _cleanTitle(name),
          avatarUrl: avatar,
          usergroup: '',
          credits: '',
          isOnline: isFriendOnline,
          recentActivity: signature,
        ),
      );
    }

    return out;
  }

  /// 解析版块公告（forumdisplay 公告区）
  static List<String> parseAnnouncements(String html) {
    final doc = html_parser.parse(html);
    final out = <String>[];
    final container = doc.querySelector(
      'div#announcement, div.announcement, div.an_msg, div.xl_ann',
    );
    if (container != null) {
      final t = container.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (t.isNotEmpty && t.length <= 200) out.add(t);
    }
    for (final el in doc.querySelectorAll(
      '.comiis_forum_ann, .f_an_ul li, ul.xl.cl li',
    )) {
      final t = el.text.trim();
      if (t.isNotEmpty && t.length <= 120 && !out.contains(t)) out.add(t);
    }
    return out;
  }

  /// 苦力怕论坛全站 FID 到版块标准名称映射字典
  static const Map<int, String> knownFidForumNames = {
    2: '游戏资讯',
    41: '闲聊讨论',
    42: '视频专区',
    43: '软件资源',
    44: '编程分享',
    48: 'JE整合包',
    49: 'JE其他资源',
    50: '皮肤分享',
    51: 'BE地图',
    52: 'BE附加包',
    53: 'BE材质光影',
    55: '其他资源',
    56: '服务器大厅',
    57: '服务器插件',
    58: '服务端整合',
    61: '全站置顶',
    62: '站内活动',
    63: '站务公告',
    64: '意见建议',
    65: '投诉违规',
    68: '悬赏问答',
    75: '人才市场',
    111: '周边创作',
    113: '教程中心',
    123: '创意港湾',
    127: '联机交友',
    139: 'JE地图',
    140: 'JE模组',
    141: 'JE材质光影',
    142: 'BE整合包',
  };

  /// 运行时动态记录的 FID -> 版块名（随着页面加载、API解析动态扩充）
  static final Map<int, String> dynamicFidToForumMap = <int, String>{};

  /// 注册/记录 FID 与版块名称
  static void registerForumName(int? fid, String? name) {
    if (fid == null || fid <= 0 || name == null) return;
    final clean = name
        .replaceAll(
          RegExp(
            r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
            unicode: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'^[\[【\s]+|[\]】\s]+$'), '')
        .trim();
    if (clean.isNotEmpty && clean != '版块' && clean != '论坛') {
      dynamicFidToForumMap[fid] = clean;
    }
  }

  /// 获取指定 FID 的版块名称
  static String? getForumNameByFid(int? fid) {
    if (fid == null || fid <= 0) return null;
    return dynamicFidToForumMap[fid] ?? knownFidForumNames[fid];
  }

  /// 全局帖子 TID -> 版块名缓存（直接来源于接口与真实页面）
  static final Map<int, String> threadForumCache = <int, String>{};

  /// 全局帖子 TID -> 版块 FID 缓存
  static final Map<int, int> threadFidCache = <int, int>{};

  /// 注册帖子的真实版块信息
  static void registerThread(int tid, {int? fid, String? forumName}) {
    if (tid <= 0) return;
    if (fid != null && fid > 0) {
      threadFidCache[tid] = fid;
    }
    if (forumName != null && forumName.isNotEmpty) {
      final clean = forumName
          .replaceAll(
            RegExp(
              r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
              unicode: true,
            ),
            '',
          )
          .replaceAll(RegExp(r'^[\[【\s]+|[\]】\s]+$'), '')
          .replaceAll('来自', '')
          .trim();
      if (clean.isNotEmpty && !_isGenericPortalHeader(clean)) {
        threadForumCache[tid] = clean;
      }
    } else if (fid != null && fid > 0) {
      final nameByFid = getForumNameByFid(fid);
      if (nameByFid != null && nameByFid.isNotEmpty) {
        threadForumCache[tid] = nameByFid;
      }
    }
  }

  /// 根据 TID 直接查询已记录的真实版块名称
  static String? getForumNameByTid(int? tid) {
    if (tid == null || tid <= 0) return null;
    return threadForumCache[tid] ?? getForumNameByFid(threadFidCache[tid]);
  }

  /// 智能推断与解析版块名称（数据驱动：严格优先 TID/FID/分类/明确前缀，杜绝模糊猜测）
  static String? resolveForumName({
    int? tid,
    int? fid,
    String? rawForumName,
    String? title,
    String? typeName,
  }) {
    // 0. 优先直接从真实帖子数据缓存中获取 (TID 数据驱动，100% 绝对权威)
    if (tid != null && tid > 0) {
      final fromTid = getForumNameByTid(tid);
      if (fromTid != null && fromTid.isNotEmpty) {
        return fromTid;
      }
    }

    // 1. 优先使用已清洗的 rawForumName
    if (rawForumName != null && rawForumName.trim().isNotEmpty) {
      final clean = rawForumName
          .replaceAll(
            RegExp(
              r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
              unicode: true,
            ),
            '',
          )
          .replaceAll(RegExp(r'^[\[【\s]+|[\]】\s]+$'), '')
          .replaceAll('来自', '')
          .trim();
      const genericHeaders = {
        '最新主题',
        '最新发表',
        '今日热帖',
        '热帖推荐',
        '焦点图',
        '今日推荐',
        '精彩图文',
        '最新内容',
        '精选内容',
        '热门主题',
        '推荐内容',
        '热帖排行榜',
        '苦力怕论坛',
        '全部',
        '默认',
        '版块',
        '论坛',
        '帖子',
        '图文推荐',
      };
      if (clean.isNotEmpty && !genericHeaders.contains(clean)) {
        if (clean == '附加包' || clean == '行为包' || clean.toLowerCase() == 'addon') {
          return 'BE附加包';
        }
        if (clean == '材质' || clean == '光影' || clean == '材质光影' || clean == '材质包' || clean == '光影包' || clean == 'BE纹理[材质]') {
          return 'BE材质光影';
        }
        if (clean == '模组' || clean.toLowerCase() == 'mod' || clean == 'JE模组/数据包') {
          return 'JE模组';
        }
        if (clean == '地图' || clean == '游戏地图') {
          return 'BE地图';
        }
        if (clean == '整合包' || clean == '整合') {
          return 'JE整合包';
        }
        if (clean == '资讯' || clean == '快讯' || clean == '新闻') {
          return '游戏资讯';
        }
        return clean;
      }
    }

    // 2. 根据已知或动态学习的 fid 匹配
    final nameByFid = getForumNameByFid(fid);
    if (nameByFid != null && nameByFid.isNotEmpty) {
      return nameByFid;
    }

    // 3. 根据主题官方分类名 (typeName) 准确映射
    if (typeName != null && typeName.trim().isNotEmpty) {
      final t = typeName.trim();
      if (t.contains('招募') || t.contains('应聘') || t.contains('招聘') || t.contains('人才')) {
        return '人才市场';
      }
      if (t.contains('求助') || t.contains('悬赏') || t.contains('问答')) {
        return '悬赏问答';
      }
      if (t.contains('快讯') || t.contains('资讯') || t.contains('新闻') || t.contains('公告')) {
        return '游戏资讯';
      }
      if (t.contains('教程') || t.contains('指引') || t.contains('教学') || t.contains('方法')) {
        return '教程中心';
      }
      if (t.contains('附加包') || t.contains('行为包') || t.toLowerCase().contains('addon')) {
        return 'BE附加包';
      }
      if (t.contains('模组') || t.toLowerCase().contains('mod')) {
        return 'JE模组';
      }
      if (t.contains('材质') || t.contains('光影')) {
        return 'BE材质光影';
      }
      if (t.contains('整合包')) {
        return 'JE整合包';
      }
      if (t.contains('软件') || t.contains('工具')) {
        return '软件资源';
      }
      if (t.contains('开服') || t.contains('服务器')) {
        return '服务器大厅';
      }
      if (t.contains('插件')) {
        return '服务器插件';
      }
      if (t.contains('绘画') || t.contains('同人') || t.contains('周边')) {
        return '周边创作';
      }
      if (t.contains('联机') || t.contains('交友')) {
        return '联机交友';
      }
      if (t.contains('闲聊') || t.contains('灌水')) {
        return '闲聊讨论';
      }
    }

    // 绝不根据标题进行任何擅自猜测或模糊匹配，未确定时返回 null，交由异步真实数据解析
    return null;
  }

  /// 清理标题：剥离回复/阅读/热度/日期等尾随元数据，并剔除开头重复的版块标签前缀
  static String _cleanTitle(String title) {
    var t = title
        .replaceAll('\u200b', '') // 零宽空格（常导致标题出现异常方块）
        .replaceAll('\u200e', '')
        .replaceAll('\u200f', '')
        .replaceAll('\ufeff', '')
        .replaceAll(
          RegExp(
            r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
            unicode: true,
          ),
          '',
        ) // 私有区图标字体（comiis_font 图标码与扩展区图标，彻底根除豆腐块）
        .replaceAll('\u00a0', ' ')
        .trim();
    t = t
        .replaceAll(RegExp(r'\d+\s*回复\s*·\s*\d+\s*查看'), '')
        .replaceAll(RegExp(r'\d+\s*回复\s*·\s*\d+\s*阅读'), '')
        .replaceAll(RegExp(r'\d+\s*回复'), '')
        .replaceAll(RegExp(r'\d+\s*阅读'), '')
        .replaceAll(RegExp(r'\d+\s*查看'), '')
        .replaceAll(RegExp(r'\d{4}-\d{1,2}-\d{1,2}.*$'), '')
        .trim();

    // 去除标题开头的重复标签前缀，例如 "[人才市场][人才市场]" -> "[人才市场]"
    t = t.replaceAllMapped(
      RegExp(r'^(\[[^\]]+\]|\【[^\】]+\】)\s*\1\s*', caseSensitive: false),
      (m) => '${m.group(1)} ',
    );

    return t.trim();
  }

  /// 清理签名：剥离零宽字符，并彻底剔除 <table>/<tbody> 等冗余包裹标签，提取纯净签名
  static String cleanSignatureText(String signature) {
    if (signature.isEmpty) return '';
    var s = signature
        .replaceAll('\u200b', '')
        .replaceAll('\u200e', '')
        .replaceAll('\u200f', '')
        .replaceAll('\ufeff', '')
        .replaceAll('\u00a0', ' ')
        .trim();
    if (s.contains('<table') || s.contains('<tbody') || s.contains('<tr') || s.contains('<td')) {
      try {
        final frag = html_parser.parseFragment(s);
        frag.querySelectorAll('script, style').forEach((e) => e.remove());
        s = (frag.text ?? s).trim();
      } catch (_) {}
    }
    return s;
  }

  static String _cleanSignature(String signature) => cleanSignatureText(signature);

  /// 清理作者昵称：过滤「阅读」、「查看」、「楼主」、「匿名」、「论坛帖子」等系统统计字段，保留如「30303」等纯数字或字母数字合法用户名
  static String _cleanAuthor(String? raw) {
    if (raw == null) return '';
    var a = raw
        .replaceAll('\u200b', '')
        .replaceAll('\u200e', '')
        .replaceAll('\u200f', '')
        .replaceAll('\ufeff', '')
        .replaceAll(RegExp(r'[\uE000-\uF8FF]'), '')
        .trim();
    if (a.isEmpty ||
        a == '阅读' ||
        a == '查看' ||
        a == '回复' ||
        a == '楼主' ||
        a == '匿名' ||
        a == '论坛帖子' ||
        a == '系统' ||
        a == '暂无' ||
        a == '关注' ||
        a.endsWith('阅读') ||
        a.endsWith('查看') ||
        RegExp(r'^\d+\s*(?:阅读|查看|回复|次阅读|次查看)$').hasMatch(a) ||
        RegExp(r'^\d{4}-\d{1,2}-\d{1,2}').hasMatch(a)) {
      return '';
    }
    return a;
  }

  static int? _uidFromHref(String href) {
    final m = RegExp(r'uid=(\d+)').firstMatch(href);
    if (m != null) return int.tryParse(m.group(1)!);
    // 伪静态 space-uid-{uid}.html
    final m2 = RegExp(r'space-uid-(\d+)').firstMatch(href);
    return m2 == null ? null : int.tryParse(m2.group(1)!);
  }

  /// 解析楼层点评/楼中楼（Discuz postcomment 渲染块；模板无点评块时返回空）
  static List<({String author, String content})> _parseFloorComments(
    dynamic messageEl,
  ) {
    final out = <({String author, String content})>[];
    for (final el in messageEl.querySelectorAll(
      '.rate_comment li, .postcomment li, .comiis_comment li, .commentlist li',
    )) {
      final text = el.text.trim();
      if (text.isEmpty) continue;
      final parts = text.split(':');
      if (parts.length >= 2) {
        out.add((
          author: parts[0].trim(),
          content: parts.sublist(1).join(':').trim(),
        ));
      } else {
        out.add((author: '', content: text));
      }
      if (out.length >= 20) break;
    }
    return out;
  }

  /// 解析楼中楼（replyfloor 插件：div.replyfloor_box）
  ///
  /// 结构见 mock-server/samples/viewthread.html：每条回复为
  /// .replyfloor_content_li（id=replyfloor_content_li_{msgid}），含
  /// 头像/用户名/IP/正文（.replyfloor_content_text，可含表情 <img>）/时间。
  static ({List<ReplyFloorComment> comments, int count, String floorNumber})
  _parseReplyFloor(dynamic post) {
    final comments = <ReplyFloorComment>[];
    final box = post.querySelector('.replyfloor_box');
    if (box == null) {
      return (comments: comments, count: 0, floorNumber: '');
    }
    var floorNumber = '';
    final floorEl = box.querySelector('.replyfloor_tail_floor em');
    if (floorEl != null) {
      final t = floorEl.text.trim();
      if (t.isNotEmpty) floorNumber = '$t#';
    }
    var count = 0;
    final countEl = box.querySelector('span[id^="replyfloor_count_"]');
    if (countEl != null) {
      count = int.tryParse(countEl.text.trim()) ?? 0;
    }
    for (final li in box.querySelectorAll('.replyfloor_content_li')) {
      final idAttr = li.attributes['id'] ?? '';
      final msgid =
          int.tryParse(idAttr.replaceFirst('replyfloor_content_li_', '')) ?? 0;
      final userA = li.querySelector(
        '.replyfloor_content_user a[href*="mod=space"], .replyfloor_content_user a',
      );
      final author = userA?.text.trim() ?? '';
      final uid = _uidFromHref(userA?.attributes['href'] ?? '');
      final avatarEl = li.querySelector('.replyfloor_content_avatar img');
      final rawAvatar = avatarEl?.attributes['src'] ?? avatarEl?.attributes['data-original'];
      final avatar = _avatarUrl(rawAvatar) ?? _absolute(rawAvatar) ?? '';
      final faceUrl = _faceUrlFromAvatar(rawAvatar) ?? '';
      final textEl = li.querySelector('.replyfloor_content_text');
      final contentHtml = textEl != null
          ? (textEl.innerHtml.isNotEmpty ? textEl.innerHtml : textEl.text)
          : '';
      final time =
          li.querySelector('.replyfloor_content_time')?.text.trim() ?? '';
      final location =
          li.querySelector('.replyfloor_content_location')?.text.trim() ?? '';
      final isCommentWarned = li.querySelector(
            'a[href*="viewwarning"], img[src*="warning"], .pwarning, .warn, [title*="受到警告"]',
          ) !=
          null ||
          li.innerHtml.contains('viewwarning') ||
          li.innerHtml.contains('受到警告');
      final isCommentShielded = contentHtml.contains('内容自动屏蔽') ||
          contentHtml.contains('该帖被管理员或版主屏蔽');
      final liHtml = li.outerHtml;
      final bool hasOnlineMark = (li.querySelector(
            'img:not(.authicn)[src*="online.png"], img:not(.authicn)[src*="online.gif"], img[src*="ol.gif"], img[title*="当前在线"], img[title="在线"], .comiis_o, em.online, span.online',
          ) !=
          null ||
          liHtml.contains('title="当前在线"') ||
          liHtml.contains('class="comiis_o"') ||
          liHtml.contains('>当前在线<'));

      final bool hasOfflineMark = (li.querySelector(
            'img[src*="offline.png"], img[src*="offline.gif"], img[title*="当前离线"], img[title="离线"], .comiis_f, em.offline, span.offline',
          ) !=
          null ||
          liHtml.contains('title="当前离线"') ||
          liHtml.contains('class="comiis_f"') ||
          liHtml.contains('>当前离线<'));

      final isCommentOnline = (hasOnlineMark && !hasOfflineMark) ||
          (!hasOfflineMark && _isRecentActivity(time));

      comments.add(
        ReplyFloorComment(
          msgid: msgid,
          uid: uid,
          author: author,
          avatar: avatar,
          faceUrl: faceUrl,
          contentHtml: contentHtml,
          timeText: time,
          location: location,
          isWarned: isCommentWarned,
          warningText: isCommentWarned ? '受到警告' : '',
          isShielded: isCommentShielded,
          shieldText: isCommentShielded ? '提示: 内容自动屏蔽' : '',
          isOnline: isCommentOnline,
        ),
      );
      if (comments.length >= 50) break;
    }
    if (count == 0 && comments.isNotEmpty) count = comments.length;
    return (comments: comments, count: count, floorNumber: floorNumber);
  }

  /// 解析本楼层可用道具（mgc_post_{pid} 菜单：home.php?mod=magic 道具链接）
  ///
  /// 结构见 mock-server/samples/viewthread.html：
  /// div[id="mgc_post_{pid}"] > ul > li > a[href*=mod=magic]（img 图标 + 道具名）。
  static List<({String mid, String name, String img, String idtype, String id})>
  _parseMagicItems(dynamic post) {
    final out =
        <({String mid, String name, String img, String idtype, String id})>[];
    final box = post.querySelector('div[id^="mgc_post_"]');
    if (box == null) return out;
    for (final a in box.querySelectorAll('a[href*="mod=magic"]')) {
      final href = a.attributes['href'] ?? '';
      final mid = RegExp(r'mid=([^&]+)').firstMatch(href)?.group(1) ?? '';
      final idtype = RegExp(r'idtype=([^&]+)').firstMatch(href)?.group(1) ?? '';
      final id = RegExp(r'[?&]id=([^&]+)').firstMatch(href)?.group(1) ?? '';
      final imgEl = a.querySelector('img');
      final img = _medalUrl(imgEl?.attributes['src']);
      var name = a.text.trim();
      if (name.isEmpty && imgEl != null) name = imgEl.attributes['alt'] ?? '';
      if (name.isEmpty && img.isNotEmpty) {
        name = img.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
      if (mid.isEmpty) continue;
      out.add((mid: mid, name: name, img: img, idtype: idtype, id: id));
      if (out.length >= 10) break;
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // 帖子列表（首页 / 版块 / 导读）
  // ---------------------------------------------------------------------
  // 帖子列表（首页 / 版块 / 导读）
  // ---------------------------------------------------------------------
  static List<ThreadSummary> parseThreadList(String html, {int? pageFid}) {
    final doc = html_parser.parse(html);

    final result = <ThreadSummary>[];
    final seenTids = <int>{};

    // 0. 移除所有全局顶部导航、侧边栏、快捷标签栏与页脚，防止抓到侧栏标签（如 Java8 / 勋章申请 等）
    final cleanDoc = doc.clone(true);
    cleanDoc
        .querySelectorAll(
          '#comiis_fpostmore, .comiis_fmenu, .comiis_nav, #nv, #ft, .footer, .comiis_sidenv_box, #comiis_sidenv, #comiis_menu, #toptb, #hd, #um, .hdc, .sub_nav, .comiis_head, .sidebar, .portal_block, [id^="portal_block_"], .taglist, .comiis_tag',
        )
        .forEach((e) => e.remove());

    // 1. 标准 Discuz PC 导读/版块列表：tbody[id^="normalthread_"], tbody[id^="stickthread_"]
    for (final tbody in cleanDoc.querySelectorAll(
      'tbody[id^="normalthread_"], tbody[id^="stickthread_"]',
    )) {
      final a = tbody.querySelector('th a.xst, th a.tit, a.xst, a.s.xst');
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final tid = _tidFromHref(href);
      if (tid == null || !seenTids.add(tid)) continue;

      final title = _cleanTitle(a.text);
      if (title.isEmpty) continue;

      // 作者与 UID
      final byTds = tbody.querySelectorAll('td.by');
      final firstBy = byTds.isNotEmpty ? byTds.first : null;
      final authorA =
          tbody.querySelector(
            '.aor a, .sub a[href*="space-"], td.by cite a, td.by a[href*="space-uid-"], td.by a[href*="uid="]',
          ) ??
          firstBy?.querySelector('a[href*="space-uid-"], a[href*="uid="]');
      var author = _cleanAuthor(authorA?.text);
      var uid = _uidFromHref(authorA?.attributes['href'] ?? '');
      if (author.isEmpty) {
        for (final aEl in tbody.querySelectorAll(
          'a[href*="space-uid-"], a[href*="space-username"]',
        )) {
          if (aEl.parent?.classes.contains('avr') == true ||
              aEl.classes.contains('avr')) {
            continue;
          }
          final cand = _cleanAuthor(aEl.text);
          if (cand.isNotEmpty) {
            author = cand;
            uid ??= _uidFromHref(aEl.attributes['href'] ?? '');
            break;
          }
        }
      }
      uid ??= _uidFromHref(
        tbody.querySelector('td.avr a, .avr a')?.attributes['href'] ?? '',
      );

      // 发布时间
      final timeEl =
          firstBy?.querySelector('em span, em') ??
          tbody.querySelector('td.by em span, td.by em, .dte, .sub .dte');
      final timeText = timeEl?.text.trim() ?? '';

      // 查看与回复
      final numTd = tbody.querySelector('td.num');
      int replies = -1;
      int views = -1;
      if (numTd != null) {
        final rA = numTd.querySelector('a.xi2, a');
        if (rA != null) replies = int.tryParse(rA.text.trim()) ?? -1;
        final vEm = numTd.querySelector('em');
        if (vEm != null) views = int.tryParse(vEm.text.trim()) ?? -1;
      } else {
        views =
            int.tryParse(tbody.querySelector('.vie')?.text.trim() ?? '') ?? -1;
        replies =
            int.tryParse(tbody.querySelector('.rey')?.text.trim() ?? '') ?? -1;
      }
      if (views == -1 || replies == -1) {
        final acgifNums = tbody.querySelector('.acgifnums');
        if (acgifNums != null) {
          final rA = acgifNums.querySelector('a');
          if (rA != null && replies == -1) {
            replies = int.tryParse(rA.text.trim()) ?? -1;
          }
          final vSpan = acgifNums.querySelector('span');
          if (vSpan != null && views == -1) {
            views = int.tryParse(vSpan.text.trim()) ?? -1;
          }
        }
      }

      // 所属版块名
      final forumA = tbody.querySelector(
        'td.by a[href*="forumdisplay"], td.by a[href*="forum-"], td.forum a',
      );
      final rawForumName = forumA?.text.trim();
      final itemFid = _extractFid(forumA?.attributes['href']) ?? pageFid;
      final resolvedForumName = resolveForumName(
        fid: itemFid,
        rawForumName: rawForumName,
        title: title,
      );

      final isSticky =
          tbody.attributes['id']?.startsWith('stickthread_') ?? false;
      final cover = _coverFromScope(tbody);

      result.add(
        ThreadSummary(
          tid: tid,
          fid: itemFid,
          uid: uid,
          author: author,
          title: title,
          coverUrl: cover,
          forumName: resolvedForumName,
          timeText: timeText,
          views: views,
          replies: replies,
          isSticky: isSticky,
        ),
      );
    }

    // 2. 移动端全模板列表结构（li.forumlist_li、li.comiis_wxlist、li.comiis_mmlist、div.wzlist_noimg、div.comiis_wzlists、.comiis_mh_twlist li、.comiis_mhswf li 等）
    final mobileItems = cleanDoc.querySelectorAll(
      '.comiis_forumlist li, li.forumlist_li, li.comiis_wxlist, li.comiis_mmlist, li.comiis_milist, li.comiis_znalist, .comiis_list li, .guide_list li, .comiis_mh_twlist li, li.twlist_li, .comiis_mhswf li, .comiis_app_forumlist li, .comiis_mh_txtlist li, .comiis_mh_txtlist_phb li, div.wzlist_noimg, div.comiis_wzlists',
    );
    for (final li in mobileItems) {
      // 过滤内嵌评论列表或子条目
      if (li.parent?.classes.contains('reply_list') == true ||
          li.id.startsWith('retid_') ||
          li.classes.contains('b_t') &&
              li.parent?.classes.contains('comiis_forumlist_top') == true) {
        continue;
      }
      final t = _parseThreadListItem(li, html, seenTids, pageFid: pageFid);
      if (t != null) result.add(t);
    }

    // 3. 移动端置顶帖：div.comiis_forumlist_top ul li
    for (final li in cleanDoc.querySelectorAll('.comiis_forumlist_top li')) {
      final a = li.querySelector('a[href*="thread-"]');
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final tid = _tidFromHref(href);
      if (tid == null || !seenTids.add(tid)) continue;
      final title = a.text.replaceFirst(RegExp(r'^\s*置顶'), '').trim();
      if (title.isEmpty) continue;
      result.add(
        ThreadSummary(
          tid: tid,
          fid: pageFid,
          forumName: resolveForumName(fid: pageFid, title: title),
          author: '',
          title: title,
          isSticky: true,
        ),
      );
    }

    // 4. PC 导读列表/通用表格模式（table#threadlisttableid tr, div.bm_c table tr, th.main.common, th.common）
    for (final th in cleanDoc.querySelectorAll(
      'th.main.common, th.common, th.new, th.lock, th.common.sub',
    )) {
      final a = th.querySelector(
        'a.tit.xst, a.tit, a.xst, a[href*="thread-"], a[href*="tid="]',
      );
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final tid = _tidFromHref(href);
      if (tid == null || !seenTids.add(tid)) continue;
      final title = _cleanTitle(a.text);
      if (title.isEmpty) continue;

      final parentTr = th.parent?.localName == 'tr' ? th.parent : null;
      final authorA =
          parentTr?.querySelector(
            'td.by cite a, td.by a[href*="space-uid-"], td.by a[href*="uid="]',
          ) ??
          th.querySelector('.aor a, .sub .aor, .by a, a[href*="space-uid-"]');
      final author = _cleanAuthor(authorA?.text);
      final uid = _uidFromHref(authorA?.attributes['href'] ?? '');

      final timeEl =
          parentTr?.querySelector('td.by em span, td.by em') ??
          th.querySelector('.dte');
      final timeText = timeEl?.text.trim() ?? '';

      final forumA = parentTr?.querySelector(
        'td.forum a, td.by a[href*="forum-"], td.by a[href*="forumdisplay"]',
      );
      final rawForumName = forumA?.text.trim();
      final itemFid = _extractFid(forumA?.attributes['href']) ?? pageFid;
      final resolvedForumName = resolveForumName(
        fid: itemFid,
        rawForumName: rawForumName,
        title: title,
      );

      var views = -1, replies = -1;
      final numTd = parentTr?.querySelector('td.num');
      if (numTd != null) {
        final rA = numTd.querySelector('a.xi2, a');
        if (rA != null) replies = int.tryParse(rA.text.trim()) ?? -1;
        final vEm = numTd.querySelector('em');
        if (vEm != null) views = int.tryParse(vEm.text.trim()) ?? -1;
      } else {
        views = int.tryParse(th.querySelector('.vie')?.text.trim() ?? '') ?? -1;
        replies =
            int.tryParse(th.querySelector('.rey')?.text.trim() ?? '') ?? -1;
      }

      final cover = _coverFromScope(parentTr ?? th);

      result.add(
        ThreadSummary(
          tid: tid,
          fid: itemFid,
          uid: uid,
          author: author,
          title: title,
          coverUrl: cover,
          forumName: resolvedForumName,
          timeText: timeText,
          views: views,
          replies: replies,
        ),
      );
    }

    // 5. 导读图集模式（view=pic: ul.ml li, div.photo_list li, .comiis_piclist li）
    for (final li in cleanDoc.querySelectorAll(
      'ul.ml li, ul.mlp li, div.photo_list li, .comiis_piclist li, div.c.cl li',
    )) {
      final a = li.querySelector(
        'a[href*="thread-"], a[href*="viewthread"], a[href*="tid="], h3 a, .title a',
      );
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final tid = _tidFromHref(href);
      if (tid == null || !seenTids.add(tid)) continue;

      final title = _cleanTitle(
        li.querySelector('h3 a, .title a, a.xst')?.text ?? a.text,
      );
      if (title.isEmpty) continue;

      final authorA = li.querySelector(
        'p.xg1 a, .author a, a[href*="space-uid-"], a[href*="uid="]',
      );
      final author = _cleanAuthor(authorA?.text);
      final uid = _uidFromHref(authorA?.attributes['href'] ?? '');

      final cover = _coverFromScope(li);
      final numText = li.querySelector('p.cl')?.text ?? '';
      final repliesM = RegExp(r'回复[:：\s]*(\d+)').firstMatch(numText);
      final viewsM = RegExp(r'查看[:：\s]*(\d+)').firstMatch(numText);

      result.add(
        ThreadSummary(
          tid: tid,
          fid: pageFid,
          uid: uid,
          author: author,
          title: title,
          coverUrl: cover,
          forumName: resolveForumName(fid: pageFid, title: title),
          timeText: '',
          views: viewsM != null ? int.tryParse(viewsM.group(1)!) ?? -1 : -1,
          replies: repliesM != null
              ? int.tryParse(repliesM.group(1)!) ?? -1
              : -1,
        ),
      );
    }

    // 6. 标准 Discuz 手机版 threadlist：li.list（如 diskao forum-52.html）
    if (result.isEmpty) {
      for (final li in cleanDoc.querySelectorAll(
        'div.threadlist li.list, ul.comiis_list li, .comiis_twlist li',
      )) {
        final a = li.querySelector('a[href*="thread-"], a[href*="viewthread"]');
        if (a == null) continue;
        final href = a.attributes['href'] ?? '';
        final tid = _tidFromHref(href);
        if (tid == null || !seenTids.add(tid)) continue;
        final titleEl = li.querySelector(
          '.threadlist_tit em, .threadlist_tit, em, h3',
        );
        final title = _cleanTitle(titleEl?.text ?? a.text);
        if (title.isEmpty) continue;
        final author = _cleanAuthor(
          li.querySelector('.muser .mmc, .mmc')?.text,
        );
        final uid = _uidFromHref(
          li.querySelector('.muser a, a[href*="uid="]')?.attributes['href'] ??
              '',
        );
        final timeText = li.querySelector('.mtime')?.text.trim() ?? '';
        final excerpt = li.querySelector('.threadlist_mes')?.text.trim() ?? '';
        final foots = li.querySelectorAll('.threadlist_foot li');
        var views = -1, replies = -1;
        if (foots.length >= 2) {
          views = int.tryParse(foots[0].text.trim()) ?? -1;
          replies = int.tryParse(foots[1].text.trim()) ?? -1;
        }
        final cover = _coverFromScope(li);
        result.add(
          ThreadSummary(
            tid: tid,
            fid: pageFid,
            uid: uid,
            author: author,
            title: title,
            coverUrl: cover,
            forumName: resolveForumName(fid: pageFid, title: title),
            excerpt: excerpt.isEmpty ? null : excerpt,
            timeText: timeText,
            views: views,
            replies: replies,
          ),
        );
      }
    }

    // 7. 首页门户/导读轮播与图文推荐兜底（如 guide_hot.html、home.html）
    if (result.isEmpty) {
      for (final a in cleanDoc.querySelectorAll(
        '.comiis_mhswf .swiper-slide a[href*="thread-"], .comiis_mh_img a[href*="thread-"], .comiis_mhswf a[href*="thread-"]',
      )) {
        final href = a.attributes['href'] ?? '';
        final tid = _tidFromHref(href);
        if (tid == null || !seenTids.add(tid)) continue;
        final title = _cleanTitle(
          a.attributes['title'] ?? a.querySelector('span')?.text ?? a.text,
        );
        if (title.isEmpty || title == '打赏' || title == '教程') continue;
        final cover = _coverFromScope(a);
        result.add(
          ThreadSummary(
            tid: tid,
            fid: pageFid,
            forumName: resolveForumName(fid: pageFid, title: title),
            author: '',
            title: title,
            coverUrl: cover,
          ),
        );
      }
      for (final t in parseHomeThreads(html)) {
        if (seenTids.add(t.tid)) {
          result.add(t);
        }
      }
    }

    for (final t in result) {
      registerThread(t.tid, fid: t.fid, forumName: t.forumName);
    }

    return result;
  }

  /// 解析单个帖子列表条目（comiis_milist / comiis_znalist 通用）
  static ThreadSummary? _parseThreadListItem(
    html_dom.Element li,
    String html,
    Set<int> seenTids, {
    int? pageFid,
  }) {
    // 标题链接：milist（a 内含 h2，thread-{tid}-1-1.html）
    //          znalist（h2 内含 a，forum.php?mod=viewthread&tid={tid}）
    // 标题链接：wxlist / mmlist / wzlist / znalist / milist / 通用
    final titleA = li.querySelector(
      '.wxlist_li_box a, .mmlist_li_box h2 a, .wzlist_noimg a, .mmlist_li_box a, a[href*="thread-"], h2 a[href*="viewthread"], a[href*="viewthread&tid="]',
    );
    if (titleA == null) return null;
    final href = titleA.attributes['href'] ?? '';
    final tid = _tidFromHref(href);
    if (tid == null || !seenTids.add(tid)) return null;

    // h2：wxlist/mmlist/wzlist 中 h2 是标题容器
    html_dom.Element? h2 =
        li.querySelector(
          '.wxlist_li_box h2, .mmlist_li_box h2, .wzlist_info h2, .threadlist_tit, h3.tit, h2.tit',
        ) ??
        titleA.querySelector('h2') ??
        (titleA.parent != null && titleA.parent!.localName == 'h2'
            ? titleA.parent as html_dom.Element
            : null);

    // 标签解析（精/荐/热度/置顶/主题分类）
    var isDigest = false, isRecommend = false, isSticky = false, isHot = false;
    var recommendCount = -1, heatCount = -1;
    String? badge;
    var title = '';
    if (h2 != null) {
      for (final el in h2.querySelectorAll('span, em')) {
        final text = el.text.trim();
        final ttl = el.attributes['title'] ?? '';
        final cls = el.attributes['class'] ?? '';
        if (text == '精') {
          isDigest = true;
          continue;
        }
        if (text == '荐' || ttl.startsWith('荐')) {
          isRecommend = true;
          recommendCount = _firstInt(ttl);
          continue;
        }
        if (ttl.startsWith('热度')) {
          isHot = true;
          heatCount = _firstInt(ttl);
          continue;
        }
        if (text == '置顶') {
          isSticky = true;
          continue;
        }
        if (cls.contains('comiis_xifont') &&
            text.isNotEmpty &&
            text.length <= 12) {
          badge = text.replaceAll(RegExp(r'[\uE000-\uF8FF]'), '').trim();
        }
      }
      // 纯标题：移除内嵌 span/em 文本
      final clone = h2.clone(true);
      clone.querySelectorAll('span, em, i, font').forEach((e) => e.remove());
      title = _cleanTitle(clone.text);
    }
    if (title.isEmpty) {
      final attrTitle =
          titleA.attributes['title'] ??
          li.querySelector('a[title]')?.attributes['title'] ??
          '';
      title = _cleanTitle(attrTitle);
    }
    if (title.isEmpty) {
      final pEl = li.querySelector('.twlist_info p, .title, p, .tit');
      if (pEl != null) title = _cleanTitle(pEl.text);
    }
    if (title.isEmpty) {
      title = _cleanTitle(titleA.text);
    }
    if (title.isEmpty) return null;

    // 作者 + uid 智能提取
    var author = '';
    int? uid;

    // 1) 优先具有明确 space 链接的 a 标签（排除 typeid, forum, thread 等链接）
    for (final a in li.querySelectorAll(
      'a[href*="space"], a[href*="uid="], a.top_user, .kmuser a, .muser a, .author, .reply_list li a',
    )) {
      final href = a.attributes['href'] ?? '';
      if (href.contains('typeid') ||
          href.contains('forum-') ||
          href.contains('thread-') ||
          href.contains('viewthread')) {
        continue;
      }
      final u = _uidFromHref(href);
      final cand = _cleanAuthor(a.text);
      if (cand.isNotEmpty &&
          cand != '阅读' &&
          cand != '查看' &&
          cand != '回复' &&
          !cand.contains('查看') &&
          !cand.contains('回复') &&
          !RegExp(r'^\d+\s*阅读$').hasMatch(cand) &&
          !RegExp(r'^\d{4}-\d{1,2}-\d{1,2}').hasMatch(cand)) {
        author = cand;
        uid = u;
        break;
      }
    }

    // 2) 兜底：从顶部或底部专属用户区域提取
    if (author.isEmpty) {
      final authorEl = li.querySelector(
        '.wxlist_li_top a, .forumlist_li_top a:not([href*="typeid"]), .muser a, .kmuser a, .by a, cite a, .user_name, .author, span.author',
      );
      if (authorEl != null) {
        final cand = _cleanAuthor(authorEl.text);
        if (cand.isNotEmpty) {
          author = cand;
          uid = _uidFromHref(authorEl.attributes['href'] ?? '');
        }
      }
    }

    // 时间
    final timeText =
        li
            .querySelector(
              '.comiis_wxlist_bottom span.f_d, .kmtime, .bottom_time, span.bottom_time, .forumlist_li_top span.f_d, .dte',
            )
            ?.text
            .trim() ??
        '';

    // 摘要
    // 摘要：去掉「本帖最后由 xxx 于 xxx 编辑」系统记录
    final rawExcerpt = li.querySelector('.list_body')?.text.trim() ?? '';
    final excerpt =
        rawExcerpt.replaceAll(RegExp(r'^本帖最后由.*?编辑\s*'), '').trim().isEmpty
        ? null
        : rawExcerpt.replaceAll(RegExp(r'^本帖最后由.*?编辑\s*'), '').trim();

    // 封面图：整项检索，优先 comiis_loadimages / file / zoomfile / data-src / src
    final cover = _coverFromScope(li);

    // 赞/推荐数（从 .zhan_list 提取，如 "8赞"）
    final zhanEl = li.querySelector('.zhan_list a.imgbox, .zhan_list a[href*="recommend"], a[class*="num-all_"]');
    if (zhanEl != null) {
      final zm = RegExp(r'(\d+)\s*赞?').firstMatch(zhanEl.text);
      if (zm != null) {
        final parsedLikes = int.tryParse(zm.group(1)!) ?? -1;
        if (parsedLikes >= 0) {
          recommendCount = parsedLikes;
        }
      }
    }

    // 浏览/回复数
    var views = -1, replies = -1;
    final replyItems = li.querySelectorAll('ul.reply_list li, .reply_list li');
    if (replyItems.isNotEmpty) {
      replies = replyItems.length;
    }

    final wzRead = li.querySelector('.wzlist_bottom em.y, .wzlist_bottom .y');
    if (wzRead != null) {
      final m = RegExp(r'(\d+)\s*(?:阅读|查看|浏览)').firstMatch(wzRead.text);
      if (m != null) views = int.tryParse(m.group(1)!) ?? -1;
    }

    final bv = li.querySelector('.bottom_views');
    if (bv != null) {
      final ems = bv.querySelectorAll('em');
      if (ems.length >= 2) {
        views = int.tryParse(ems[0].text.trim()) ?? -1;
        replies = int.tryParse(ems[1].text.trim()) ?? -1;
      }
    }

    if (views == -1) {
      final vm = RegExp(r'(\d+)\s*(?:阅读|查看|浏览|次阅读|次查看|次浏览)').firstMatch(li.text);
      if (vm != null) views = int.tryParse(vm.group(1)!) ?? -1;
    }
    if (replies == -1) {
      final rm = RegExp(r'(\d+)\s*(?:回复|条回复|次回复|条评论)').firstMatch(li.text);
      if (rm != null) replies = int.tryParse(rm.group(1)!) ?? -1;
    }

    // 主题分类（如「来自 文章」或「来自 文学」）
    String? typeName;
    final typeA = li.querySelector(
      '.forumlist_li_time a[href*="typeid"], .forumlist_li_top a[href*="typeid"], a[href*="filter=typeid"]',
    );
    if (typeA != null) {
      final clone = typeA.clone(true);
      clone
          .querySelectorAll('i, em, span, .icon, .comiis_font')
          .forEach((e) => e.remove());
      var t = _cleanTitle(clone.text.replaceAll('来自', ''));
      if (t.isEmpty) t = _cleanTitle(typeA.text.replaceAll('来自', ''));
      if (t.isNotEmpty && t.length <= 15) typeName = t;
    }
    if (typeName == null && badge != null && badge.isNotEmpty) {
      typeName = _cleanTitle(badge);
    }

    int? itemFid;
    final fidEl = li.querySelector(
      '.forumlist_li_top a[href*="fid="], .forumlist_li_top a[href*="forum-"], .forum a[href*="fid="], .forum a[href*="forum-"]',
    );
    if (fidEl != null) {
      final href = fidEl.attributes['href'] ?? '';
      final m =
          RegExp(r'fid=(\d+)').firstMatch(href) ??
          RegExp(r'forum-(\d+)-\d+\.html').firstMatch(href);
      if (m != null) itemFid = int.tryParse(m.group(1)!);
    }
    itemFid ??= pageFid;

    // 提取条目内嵌版块名
    String? rawForum;
    final metaSpan = li.querySelector(
      '.twlist_info span, .twlist_info p, .comiis_mh_txtlist span, span.f_d',
    );
    if (metaSpan != null) {
      final clone = metaSpan.clone(true);
      clone.querySelectorAll('em, i, span').forEach((e) => e.remove());
      final raw = clone.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final sep = raw.lastIndexOf('|');
      if (sep >= 0) {
        final tag = raw.substring(0, sep).trim();
        if (tag.isNotEmpty) rawForum = tag;
      } else {
        final dateM = RegExp(r'(\d{4}-\d{1,2}-\d{1,2})$').firstMatch(raw);
        if (dateM != null) {
          final tag = raw.substring(0, dateM.start).trim();
          if (tag.isNotEmpty) rawForum = tag;
        } else if (raw.isNotEmpty && raw.length <= 15) {
          rawForum = raw;
        }
      }
    }

    if (rawForum == null || rawForum.isEmpty) {
      final forumEl = li.querySelector(
        '.forumlist_li_top a:not([href*="typeid"]), .forum, td.forum a, a[href*="forumdisplay"], .forum_name, .comiis_forum_tit a',
      );
      if (forumEl != null) {
        final href = forumEl.attributes['href'] ?? '';
        if (!href.contains('typeid')) {
          rawForum = forumEl.text.trim();
        }
      }
    }

    final resolvedForumName = resolveForumName(
      fid: itemFid,
      rawForumName: rawForum,
      title: title,
      typeName: typeName,
    );

    // 剔除与版块名重复的主题分类标签（避免出现两个相同的版块标签）
    if (typeName != null) {
      final tNorm = typeName
          .replaceAll(
            RegExp(
              r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
              unicode: true,
            ),
            '',
          )
          .replaceAll(RegExp(r'^[\[【\s]+|[\]】\s]+$'), '')
          .replaceAll('来自', '')
          .trim();
      final fNorm = (resolvedForumName ?? '')
          .replaceAll(
            RegExp(
              r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
              unicode: true,
            ),
            '',
          )
          .replaceAll(RegExp(r'^[\[【\s]+|[\]】\s]+$'), '')
          .trim();
      if (tNorm.isEmpty ||
          (fNorm.isNotEmpty && tNorm == fNorm) ||
          (fNorm.length >= 2 && tNorm.length >= 2 && (fNorm.contains(tNorm) || tNorm.contains(fNorm)))) {
        typeName = null;
      }
    }

    String? stamp;
    String? stampUrl;
    final stampEl = li.querySelector(
      'img[src*="stamp"], .stamp, .comiis_stamp, span.stamp, i.stamp',
    );
    if (stampEl != null) {
      final alt =
          stampEl.attributes['alt'] ??
          stampEl.attributes['title'] ??
          stampEl.text.trim();
      final src = stampEl.attributes['src'] ?? '';
      if (alt.isNotEmpty) {
        stamp = alt;
      } else if (src.contains('003')) {
        stamp = '美图';
      } else if (src.contains('001')) {
        stamp = '精华';
      } else if (src.contains('004')) {
        stamp = '优秀';
      } else if (src.contains('005')) {
        stamp = '原创';
      }
      stampUrl = _absolute(src);
    }
    if (stamp == null || stamp.isEmpty) {
      if (title.contains('美图') ||
          li.text.contains('美图') ||
          li.text.contains('alt="美图"') ||
          li.text.contains('title="美图"')) {
        stamp = '美图';
      }
    }

    // 剔除与版块名或分类重复的前缀勋章
    if (badge != null) {
      final bNorm = badge
          .replaceAll(
            RegExp(
              r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
              unicode: true,
            ),
            '',
          )
          .replaceAll(RegExp(r'^[\[【\s]+|[\]】\s]+$'), '')
          .trim();
      final fNorm = (resolvedForumName ?? '')
          .replaceAll(
            RegExp(
              r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
              unicode: true,
            ),
            '',
          )
          .replaceAll(RegExp(r'^[\[【\s]+|[\]】\s]+$'), '')
          .trim();
      if (bNorm.isEmpty ||
          (fNorm.isNotEmpty && bNorm == fNorm) ||
          bNorm == typeName ||
          bNorm == stamp ||
          (fNorm.length >= 2 && bNorm.length >= 2 && fNorm.contains(bNorm))) {
        badge = null;
      }
    }

    // 提取作者头像与挂件
    final avatarImg = li.querySelector(
      'img.top_tximg, a.postli_top_tximg img, .wxlist_tx img, .comiis_avatar img, .avatar img, img[src*="avatar"]',
    );
    final rawAvatar = avatarImg?.attributes['src'] ?? avatarImg?.attributes['data-original'];
    final faceUrl = _faceUrlFromAvatar(rawAvatar);

    return ThreadSummary(
      tid: tid,
      fid: itemFid,
      uid: uid,
      author: author,
      title: title,
      badge: badge,
      typeName: typeName,
      excerpt: excerpt,
      coverUrl: cover,
      forumName: resolvedForumName,
      timeText: timeText,
      replies: replies,
      views: views,
      isHot: isHot,
      isDigest: isDigest,
      isRecommend: isRecommend,
      recommendCount: recommendCount,
      heatCount: heatCount,
      isSticky: isSticky,
      stamp: stamp,
      stampUrl: stampUrl,
      faceUrl: faceUrl,
    );
  }

  /// 提取字符串中第一个整数；无则返回 -1
  static int _firstInt(String s) {
    final m = RegExp(r'(\d+)').firstMatch(s);
    return m == null ? -1 : (int.tryParse(m.group(1)!) ?? -1);
  }

  /// 清理并提取 Discuz 附件节点的真实纯净文件名（去除图标字符、时间、大小、下载次数等混杂元数据）
  static String _cleanAttachmentName(String raw) {
    var text = raw.replaceAll('&nbsp;', ' ').trim();
    text = text.replaceAll(RegExp(r'^[\uE000-\uF8FF\s]+'), '');

    // 如果包含换行，拆分各行寻找最具特征的文件名行（带后缀扩展名且不含状态文本）
    final lines = text.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    for (final l in lines) {
      if (RegExp(r'\.([a-zA-Z0-9]{2,8})$').hasMatch(l) &&
          !l.contains('上传') &&
          !l.contains('下载次数') &&
          !l.contains('天前')) {
        return l;
      }
    }
    if (lines.isNotEmpty) {
      var first = lines.first;
      first = first.replaceAll(RegExp(r'[\(（].*?[\)）]'), '').trim();
      if (first.isNotEmpty && first != '下载' && first != '点击下载' && first != '下载附件' && first.length >= 2) {
        return first;
      }
    }

    // 正则提取带扩展名的文件名
    final fnM = RegExp(r'([\w\u4e00-\u9fa5\.\-\_ ]+\.[a-zA-Z0-9]{2,8})').firstMatch(text);
    if (fnM != null) {
      final cand = fnM.group(1)!.trim();
      if (!cand.contains('上传') && !cand.contains('下载次数')) {
        return cand;
      }
    }

    // 兜底清洗
    text = text
        .replaceAll(RegExp(r'[\(（].*?[\)）]'), '')
        .replaceAll(RegExp(r'\d+\s*天前.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\d.]+\s*(?:KB|MB|GB|B|Bytes).*', caseSensitive: false), '')
        .replaceAll(RegExp(r'下载次数[:：]?\s*[\d,]+.*'), '')
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .trim();

    if (text.isEmpty || text == '下载' || text == '点击下载' || text == '下载附件' || text.length < 2) {
      return '论坛附件.bin';
    }
    return text;
  }

  /// 将 Discuz 附件上传时间格式化为 yyyy-MM-dd HH:mm（月份/日期补零）
  static String _formatUploadTime(String s) {
    final m = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2}) (\d{1,2}:\d{2})$',
    ).firstMatch(s);
    if (m != null) {
      return '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')} ${m[4]}';
    }
    return s;
  }

  static bool _isValidCoverUrl(String? u) {
    if (u == null || u.isEmpty) return false;
    final lower = u.toLowerCase();
    if (lower.contains('avatar') ||
        lower.contains('avatar.php') ||
        lower.contains('uc_server') ||
        lower.contains('uc_client') ||
        lower.contains('user.klpbbs.com') ||
        lower.contains('common_') ||
        lower.contains('none.png') ||
        lower.contains('spacer.gif') ||
        lower.contains('loading') ||
        lower.contains('noavatar') ||
        lower.contains('nophoto') ||
        lower.contains('static/image/stamp') ||
        lower.contains('static/image/magic') ||
        lower.contains('static/image/medal') ||
        lower.contains('static/image/admin') ||
        lower.contains('static/image/usergroup') ||
        lower.contains('static/image/common') ||
        lower.contains('static/image/smiley') ||
        lower.contains('static/image/mobile') ||
        lower.contains('static/image/feed') ||
        lower.contains('/stamp/') ||
        lower.contains('/medal/') ||
        lower.contains('/smiley/') ||
        lower.contains('/smilies/') ||
        lower.contains('facemall') ||
        lower.contains('sunju_') ||
        lower.contains('sigline') ||
        lower.contains('watermark') ||
        lower.contains('bilibili.com/bfs/face') ||
        lower.endsWith('.small.gif') ||
        lower.contains('arw.gif') ||
        lower.contains('agree.gif') ||
        lower.contains('folder.gif')) {
      return false;
    }
    return u.startsWith('http://') ||
        u.startsWith('https://') ||
        u.startsWith('data/attachment') ||
        u.contains('attachment') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp') ||
        lower.contains('.gif');
  }

  /// 从列表/首页作用域内提取封面图：优先 `comiis_loadimages` / `file` / `zoomfile` / `data-src` / `background-image`，其次 `src`；排除评论区/点赞区/头像/占位/版块图标/表情/印章。
  static String? _coverFromScope(html_dom.Element scope) {
    // 0. 如果条目本身带有无图标识，直接返回 null
    if (scope.classes.contains('wzlist_noimg') ||
        scope.classes.contains('noimg') ||
        scope.querySelector('.wzlist_noimg') != null) {
      return null;
    }

    // 1. 优先从专属正文封面容器中检索（排除无图文章容器、印章、头像和用户容器）
    final dedicatedImg = scope.querySelector(
      '.comiis_pyqlist_img img, .mmlist_li_img img, .threadlist_img img, .comiis_postimg img, .box_img img, .comiis_pic img, .listimgbigx img, .listimgs img, .listimg img, .kmimg img, img.kmimg, .forumlist_li_box .listimg img, .forumlist_li_box .milist_oneimg img, .milist_oneimg img, .milist_img img, .twlist_li_img img, .comiis_twimg img',
    );
    if (dedicatedImg != null &&
        !_isInAuthorOrMedalSection(dedicatedImg) &&
        !_isInCommentSection(dedicatedImg)) {
      final alt = dedicatedImg.attributes['alt'] ?? '';
      final cls = dedicatedImg.attributes['class'] ?? '';
      if (!cls.contains('stamp') &&
          !cls.contains('top_tximg') &&
          !cls.contains('chide') &&
          alt != '新人帖' &&
          alt != '包含附件' &&
          alt != '包含图片') {
        for (final candidate in [
          dedicatedImg.attributes['comiis_loadimages'] ?? '',
          dedicatedImg.attributes['file'] ?? '',
          dedicatedImg.attributes['zoomfile'] ?? '',
          dedicatedImg.attributes['data-src'] ?? '',
          dedicatedImg.attributes['data-original'] ?? '',
          dedicatedImg.attributes['data-echo'] ?? '',
          dedicatedImg.attributes['lazysrc'] ?? '',
          dedicatedImg.attributes['data-thumb'] ?? '',
          dedicatedImg.attributes['thumb'] ?? '',
          dedicatedImg.attributes['src'] ?? '',
        ]) {
          if (candidate.isNotEmpty &&
              !candidate.contains('none.png') &&
              !candidate.contains('spacer.gif')) {
            final u = _image(candidate);
            if (_isValidCoverUrl(u)) return u;
          }
        }
      }
    }

    // 2. 检查 background-image 及 data-cover / data-original 属性（排除作者区、评论区与印章区）
    for (final el in scope.querySelectorAll(
      'div.comiis_twimg, div.comiis_pic, a.comiis_pica, a.kmimg, .listimg, .listimgs, [data-cover]',
    )) {
      if (_isInCommentSection(el) || _isInAuthorOrMedalSection(el)) continue;
      if (el.classes.contains('stamp') ||
          el.classes.contains('chide') ||
          el.classes.contains('top_tximg') ||
          el.classes.contains('comiis_flxx_stamp') ||
          el.id.contains('stamp')) {
        continue;
      }

      final dataCover =
          el.attributes['data-cover'] ??
          el.attributes['data-original'] ??
          el.attributes['data-echo'] ??
          '';
      if (dataCover.isNotEmpty &&
          !dataCover.contains('none.png') &&
          !dataCover.contains('spacer.gif')) {
        final u = _image(dataCover);
        if (_isValidCoverUrl(u)) return u;
      }
      final style = el.attributes['style'] ?? '';
      final bgM = RegExp(
        r'url\s*\(\s*[\x27\x22]?([^\x27\x22\)]+)[\x27\x22]?\s*\)',
      ).firstMatch(style);
      if (bgM != null) {
        final raw = bgM.group(1)!;
        if (!raw.contains('none.png') && !raw.contains('spacer.gif')) {
          final u = _image(raw);
          if (_isValidCoverUrl(u)) return u;
        }
      }
    }

    // 3. 遍历专属图片容器内的图片（排除印章、用户头像、徽章、表情、点赞区、评论区）
    for (final img in scope.querySelectorAll('.threadlist_img img, .comiis_pyqlist_img img, .mmlist_li_img img, .listimg img, .box_img img, .comiis_pic img')) {
      if (_isInCommentSection(img) || _isInAuthorOrMedalSection(img)) continue;

      final cls = img.attributes['class'] ?? '';
      final alt = img.attributes['alt'] ?? '';
      final title = img.attributes['title'] ?? '';
      final srcAttr = img.attributes['src'] ?? '';

      if (cls.contains('top_tximg') ||
          cls.contains('chide') ||
          cls.contains('stamp') ||
          cls.contains('comiis_flxx_stamp') ||
          cls.contains('top_lev') ||
          img.attributes.containsKey('smilieid') ||
          srcAttr.contains('/stamp/') ||
          srcAttr.contains('/medal/') ||
          srcAttr.contains('/magic/') ||
          srcAttr.endsWith('.small.gif') ||
          alt == '新人帖' ||
          alt == '包含附件' ||
          alt == '包含图片' ||
          alt == '正数评分' ||
          alt.contains('勋章') ||
          alt.contains('挂件') ||
          alt.contains('avatar') ||
          title.contains('新人') ||
          title.contains('勋章')) {
        continue;
      }

      final lazy = img.attributes['comiis_loadimages'] ?? '';
      final file = img.attributes['file'] ?? '';
      final zoomfile = img.attributes['zoomfile'] ?? '';
      final dataSrc = img.attributes['data-src'] ?? '';
      final dataOrig = img.attributes['data-original'] ?? '';
      final dataEcho = img.attributes['data-echo'] ?? '';
      final lazySrc = img.attributes['lazysrc'] ?? '';
      final dataThumb = img.attributes['data-thumb'] ?? '';
      final thumb = img.attributes['thumb'] ?? '';
      final src = img.attributes['src'] ?? '';

      for (final candidate in [
        lazy,
        file,
        zoomfile,
        dataSrc,
        dataOrig,
        dataEcho,
        lazySrc,
        dataThumb,
        thumb,
        src,
      ]) {
        if (candidate.isNotEmpty &&
            !candidate.contains('none.png') &&
            !candidate.contains('spacer.gif') &&
            !candidate.contains('avatar') &&
            !candidate.contains('common_') &&
            !candidate.contains('smiley') &&
            !alt.contains('avatar')) {
          final u = _image(candidate);
          if (_isValidCoverUrl(u)) {
            return u;
          }
        }
      }
    }

    return null;
  }

  /// 辅助判断当前元素是否处于作者栏、勋章栏或用户头像信息区（包括无图文章卡片的头像区）
  static bool _isInAuthorOrMedalSection(html_dom.Element el) {
    html_dom.Element? cur = el;
    while (cur != null) {
      final cls = cur.className.toLowerCase();
      final id = cur.id.toLowerCase();
      if (cls.contains('top_user') ||
          cls.contains('kmuser') ||
          cls.contains('muser') ||
          cls.contains('author') ||
          cls.contains('by') ||
          cls.contains('avr') ||
          cls.contains('avatar') ||
          cls.contains('tx') ||
          cls.contains('tximg') ||
          cls.contains('wzlist_noimg') ||
          cls.contains('wzlist_tx') ||
          cls.contains('wxlist_tx') ||
          cls.contains('comiis_wxlist_tx') ||
          cls.contains('comiis_wz_tx') ||
          cls.contains('forumlist_li_tx') ||
          cls.contains('author_tx') ||
          cls.contains('user_tx') ||
          cls.contains('authormedals') ||
          cls.contains('medaltip') ||
          cls.contains('medal') ||
          cls.contains('verify') ||
          cls.contains('comiis_avatar') ||
          cls.contains('user_img') ||
          cls.contains('comiis_userlist') ||
          cls.contains('user_info') ||
          cls.contains('userinfo') ||
          cls.contains('authorinfo') ||
          cls.contains('authi') ||
          cls.contains('b_p') ||
          cls.contains('head') ||
          cls.contains('user_head') ||
          id.contains('medal') ||
          id.contains('avatar') ||
          id.contains('user') ||
          id.contains('authi')) {
        return true;
      }
      cur = cur.parent;
    }
    return false;
  }

  /// 辅助判断当前元素是否处于评论区、楼中楼、点赞栏或头像区
  static bool _isInCommentSection(html_dom.Element el) {
    html_dom.Element? cur = el;
    while (cur != null) {
      final cls = cur.className.toLowerCase();
      final id = cur.id.toLowerCase();
      if (cls.contains('reply_list') ||
          cls.contains('showbox') ||
          cls.contains('zhan_list') ||
          cls.contains('comment') ||
          cls.contains('replyfloor') ||
          cls.contains('top_tximg') ||
          cls.contains('wxlist_li_top') ||
          id.startsWith('retid_') ||
          id.contains('comment') ||
          id.contains('showbox')) {
        return true;
      }
      cur = cur.parent;
    }
    return false;
  }

  /// 从 href 中提取 FID
  static int? _extractFid(String? href) {
    if (href == null || href.isEmpty) return null;
    final m = RegExp(r'fid=(\d+)').firstMatch(href) ??
        RegExp(r'forum-(\d+)-\d+\.html').firstMatch(href) ??
        RegExp(r'forum-(\d+)\.html').firstMatch(href);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static bool _isGenericPortalHeader(String text) {
    const generic = {
      '最新主题',
      '最新发表',
      '今日热帖',
      '热帖推荐',
      '焦点图',
      '今日推荐',
      '精彩图文',
      '最新内容',
      '精选内容',
      '热门主题',
      '推荐内容',
      '热帖排行榜',
      '苦力怕论坛',
      '全部',
      '默认',
      '版块',
      '论坛',
      '帖子',
      '图文推荐',
    };
    return generic.contains(text);
  }

  /// 从首页板块 li 向上查找所属版块标题（仅查找自身或当自身无标题时紧邻的前一个同级标题块）
  static String _homeSectionTitle(html_dom.Element li) {
    var p = li.parent;
    while (p != null) {
      if (p.id.startsWith('comiis_app_block_')) {
        // 1. 块内部直接有标题元素
        final tit = p.querySelector(
          '.comiis_mh_tit h2, .kxtit, .comiis_mh_tit',
        );
        if (tit != null) {
          final t = tit.text.replaceAll(RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]', unicode: true), '').trim();
          if (t.isNotEmpty && !_isGenericPortalHeader(t)) return t;
          // 当前块自身已具备标题元素（即使是通用标题如"今日推荐"），绝不借用前一个块的标题
          return '';
        }
        // 2. 当前块自身完全无标题元素时，检查紧邻的前一个同级块 (如 block 36 是标题，block 38 是内容)
        final prev = p.previousElementSibling;
        if (prev != null) {
          final pTit = prev.querySelector(
            '.comiis_mh_tit h2, .kxtit, .comiis_mh_tit',
          );
          if (pTit != null) {
            final t = pTit.text.replaceAll(RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]', unicode: true), '').trim();
            if (t.isNotEmpty && !_isGenericPortalHeader(t)) return t;
          }
        }
        break;
      }
      p = p.parent;
    }
    return '';
  }

  /// 解析首页 widget 块（幻灯/图文推荐/最新主题/人才市场/悬赏问答），正确提取标题/封面/浏览/日期
  static List<ThreadSummary> parseHomeThreads(String html) {
    final doc = html_parser.parse(html);
    final result = <ThreadSummary>[];
    final seen = <int>{};

    for (final li in doc.querySelectorAll(
      'li.twlist_li, .comiis_mh_list10 li, .comiis_mh_txtlist li, .comiis_mh_list12 li, .comiis_mh_kxtxt li, .comiis_mh_txtlist_phb li, .comiis_pyqlist li, .comiis_p12 li, .comiis_mh_piclist li, .comiis_mh_piclist_li, .comiis_twimg, .portal_block_summary li, [id^="portal_block_"] li, [id^="comiis_app_block_"] li, .comiis_wxlist_li, .wzlist_li, .mmlist_li, li.forumlist_li',
    )) {
      final a = li.querySelector('a[href*="thread-"], a[href*="viewthread"], a[href*="tid="]');
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final tid = _tidFromHref(href);
      if (tid == null || !seen.add(tid)) continue;

      // 标题：优先 title 属性，其次 p/a 文本（剥离回复/阅读元数据）
      var title = _cleanTitle(a.attributes['title'] ?? '');
      if (title.isEmpty) {
        title = _cleanTitle(li.querySelector('p')?.text ?? a.text);
      }
      if (title.isEmpty) title = _cleanTitle(a.text);
      if (title.isEmpty) continue;

      final cover = _coverFromScope(li);

      final isHot = li.querySelector('i.b_ok') != null;

      var views = -1;
      final vm = RegExp(r'(\d+)\s*阅读').firstMatch(li.text);
      if (vm != null) views = int.tryParse(vm.group(1)!) ?? -1;

      var replies = -1;
      final repM = RegExp(r'(\d+)\s*回复').firstMatch(li.text);
      if (repM != null) replies = int.tryParse(repM.group(1)!) ?? -1;

      // 提取正文摘要
      final rawExcerpt = li
          .querySelector(
            '.twlist_txt, .comiis_mh_txt, .list_body, p.f_d, p.f_c',
          )
          ?.text
          .trim();
      final excerpt =
          (rawExcerpt != null && rawExcerpt.isNotEmpty && rawExcerpt != title)
          ? rawExcerpt.replaceAll(RegExp(r'^本帖最后由.*?编辑\s*'), '').trim()
          : null;

      final dm = RegExp(r'(\d{4}-\d{1,2}-\d{1,2})').firstMatch(li.text);
      var timeText = dm?.group(1);

      // 首页图文推荐提取版块名与日期；提取真实作者名与 uid
      var author = '';
      int? authorUid;
      String? forumName;
      final metaSpan = li.querySelector('.twlist_info span');
      if (metaSpan != null) {
        final clone = metaSpan.clone(true);
        clone.querySelectorAll('em').forEach((e) => e.remove());
        final raw = clone.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final sep = raw.lastIndexOf('|');
        if (sep >= 0) {
          final tag = raw.substring(0, sep).trim();
          if (tag.isNotEmpty) forumName = tag;
          timeText = raw.substring(sep + 1).trim();
        } else {
          final dateM = RegExp(r'(\d{4}-\d{1,2}-\d{1,2})$').firstMatch(raw);
          if (dateM != null) {
            final tag = raw.substring(0, dateM.start).trim();
            if (tag.isNotEmpty) forumName = tag;
            timeText = dateM.group(1);
          } else {
            if (raw.isNotEmpty) forumName = raw;
          }
        }
      }

      // 精准提取作者（优先 .kmuser a, a.top_user, .mmc, a[href*="space-uid"]，排除 f_d/y 阅读数统计标签）
      final authorEl = li.querySelector(
        '.kmuser a, .kmuser, a.top_user, .top_user, a.muser, .mmc, a.xw1, a[href*="space-uid-"], a[href*="mod=space"]',
      );
      if (authorEl != null) {
        author = _cleanAuthor(authorEl.text);
        final href = authorEl.attributes['href'] ?? '';
        authorUid = _uidFromHref(href);
      }

      if (author.isEmpty) {
        final fda = li.querySelector(
          '.f_d a, .y a, span.f_d, span.y, .user_name, .author',
        );
        if (fda != null) {
          final candidate = _cleanAuthor(fda.text);
          if (candidate.isNotEmpty &&
              !candidate.contains('阅读') &&
              !candidate.contains('回复') &&
              !candidate.contains('查看') &&
              candidate != '苦力怕论坛' &&
              !RegExp(r'^\d+$').hasMatch(candidate)) {
            author = candidate;
            final href = fda.attributes['href'] ?? '';
            final uid = _uidFromHref(href);
            if (uid != null) authorUid = uid;
          }
        }
      }

      int? itemFid;
      final fidEl = li.querySelector('a[href*="fid="], a[href*="forum-"]');
      if (fidEl != null) {
        final href = fidEl.attributes['href'] ?? '';
        final m =
            RegExp(r'fid=(\d+)').firstMatch(href) ??
            RegExp(r'forum-(\d+)-\d+\.html').firstMatch(href);
        if (m != null) itemFid = int.tryParse(m.group(1)!);
      }

      if (forumName == null || forumName.isEmpty) {
        final section = _homeSectionTitle(li);
        if (section.isNotEmpty) forumName = section;
      }

      final resolvedForumName = resolveForumName(
        fid: itemFid,
        rawForumName: forumName,
        title: title,
      );

      String? stamp;
      String? stampUrl;
      final stampEl = li.querySelector(
        'img[src*="stamp"], .stamp, .comiis_stamp, span.stamp, i.stamp',
      );
      if (stampEl != null) {
        final alt =
            stampEl.attributes['alt'] ??
            stampEl.attributes['title'] ??
            stampEl.text.trim();
        final src = stampEl.attributes['src'] ?? '';
        if (alt.isNotEmpty) {
          stamp = alt;
        } else if (src.contains('003')) {
          stamp = '美图';
        } else if (src.contains('001')) {
          stamp = '精华';
        } else if (src.contains('004')) {
          stamp = '优秀';
        } else if (src.contains('005')) {
          stamp = '原创';
        }
        stampUrl = _absolute(src);
      }
      if (stamp == null || stamp.isEmpty) {
        if (title.contains('美图') ||
            li.text.contains('美图') ||
            li.text.contains('alt="美图"') ||
            li.text.contains('title="美图"')) {
          stamp = '美图';
        }
      }

      result.add(
        ThreadSummary(
          tid: tid,
          fid: itemFid,
          uid: authorUid,
          author: author,
          title: title,
          excerpt: excerpt,
          coverUrl: cover,
          forumName: resolvedForumName,
          isHot: isHot,
          views: views,
          replies: replies,
          timeText: timeText,
          stamp: stamp,
          stampUrl: stampUrl,
        ),
      );
    }

    // 幻灯（comiis_mhswf）
    for (final a in doc.querySelectorAll('.comiis_mhswf a[href*="thread-"]')) {
      final href = a.attributes['href'] ?? '';
      final tid = _tidFromHref(href);
      if (tid == null || !seen.add(tid)) continue;
      final title = _cleanTitle(a.attributes['title'] ?? a.text);
      if (title.isEmpty) continue;
      final img = a.querySelector('img[comiis_loadimages]');
      result.add(
        ThreadSummary(
          tid: tid,
          author: '',
          title: title,
          forumName: resolveForumName(tid: tid, title: title),
          coverUrl: _image(img?.attributes['comiis_loadimages']),
        ),
      );
    }

    for (final t in result) {
      registerThread(t.tid, fid: t.fid, forumName: t.forumName);
    }

    return result;
  }

  /// 解析表情目录（data/cache/common_smilies_var.js）
  ///
  /// 结构：`smilies_type['_ID'] = ['名称', '目录']` + `smilies_array[ID][页] = [['id','code','file','w','h','order'], ...]`。
  /// 中文名在论坛数据库为 mojibake，这里按目录名映射为固定中文名。
  static List<SmileyCategory> parseSmilies(String js) {
    const nameMap = {'tieba': '贴吧', 'bilibili': 'B站', 'dy': '抖音', 'qq': 'QQ'};

    final dirMap = <int, String>{};
    for (final m in RegExp(
      r"smilies_type\['_(\d+)'\]\s*=\s*\['[^']*'\s*,\s*'([^']*)'\]",
    ).allMatches(js)) {
      final id = int.tryParse(m.group(1)!);
      final dir = m.group(2)!;
      if (id != null && dir.isNotEmpty) dirMap[id] = dir;
    }

    final result = <SmileyCategory>[];
    for (final m in RegExp(
      r"smilies_array\[(\d+)\]\[(\d+)\]\s*=\s*(\[\[[\s\S]*?\]\]);",
    ).allMatches(js)) {
      final typeid = int.tryParse(m.group(1)!);
      final body = m.group(3)!;
      if (typeid == null || !dirMap.containsKey(typeid)) continue;
      final dir = dirMap[typeid]!;

      final smileys = <Smiley>[];
      for (final s in RegExp(
        r"\['(\d+)'\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*,\s*'(\d+)'\s*,\s*'(\d+)'",
      ).allMatches(body)) {
        final id = int.tryParse(s.group(1)!);
        if (id == null) continue;
        final code = s.group(2)!;
        final file = s.group(3)!;
        final w = int.tryParse(s.group(4)!) ?? 20;
        final h = int.tryParse(s.group(5)!) ?? 20;
        smileys.add(
          Smiley(
            id: id,
            code: code,
            file: file,
            width: w,
            height: h,
            imageUrl: '${AppConfig.baseUrl}static/image/smiley/$dir/$file',
          ),
        );
      }
      if (smileys.isEmpty) continue;

      final idx = result.indexWhere((c) => c.typeid == typeid);
      if (idx >= 0) {
        final old = result[idx];
        result[idx] = SmileyCategory(
          typeid: old.typeid,
          dir: old.dir,
          name: old.name,
          smileys: [...old.smileys, ...smileys],
        );
      } else {
        result.add(
          SmileyCategory(
            typeid: typeid,
            dir: dir,
            name: nameMap[dir] ?? dir,
            smileys: smileys,
          ),
        );
      }
    }
    if (result.isEmpty && js != kDefaultSmiliesJs) {
      return parseSmilies(kDefaultSmiliesJs);
    }
    return result;
  }

  /// 苦力怕论坛内置常用 Discuz 表情 JS 常量兜底（贴吧/B站/抖音/QQ）
  static const String kDefaultSmiliesJs = r'''
var smthumb = '20';var smilies_type = new Array();smilies_type['_12'] = ['贴吧', 'tieba'];smilies_type['_13'] = ['B站', 'bilibili'];smilies_type['_15'] = ['抖音', 'dy'];smilies_type['_17'] = ['QQ', 'qq'];var smilies_array = new Array();var smilies_fast = new Array();smilies_array[12] = new Array();smilies_array[12][1] = [['292', '[贴吧_呵呵]','1.png','20','20','30'],['313', '[贴吧_哈哈]','2.png','20','20','30'],['280', '[贴吧_吐舌]','3.png','20','20','30'],['288', '[贴吧_啊]','4.png','20','20','30'],['284', '[贴吧_酷]','5.png','20','20','30'],['301', '[贴吧_怒]','6.png','20','20','30'],['322', '[贴吧_开心]','7.png','20','20','30'],['289', '[贴吧_汗]','8.png','20','20','30'],['308', '[贴吧_泪]','9.png','20','20','30'],['303', '[贴吧_黑线]','10.png','20','20','30'],['285', '[贴吧_鄙视]','11.png','20','20','30'],['293', '[贴吧_不高兴]','12.png','20','20','30'],['319', '[贴吧_真棒]','13.png','20','20','30'],['294', '[贴吧_钱]','14.png','20','20','30'],['323', '[贴吧_疑问]','15.png','20','20','30'],['325', '[贴吧_阴脸]','16.png','20','20','30'],['318', '[贴吧_吐]','17.png','20','20','30'],['307', '[贴吧_咦]','18.png','20','20','30'],['306', '[贴吧_委屈]','19.png','20','20','30'],['305', '[贴吧_花心]','20.png','20','20','30'],['314', '[贴吧_呼~]','21.png','20','20','30'],['296', '[贴吧_笑脸]','22.png','20','20','30'],['320', '[贴吧_冷]','23.png','20','20','30'],['281', '[贴吧_太开心]','24.png','20','20','30'],['304', '[贴吧_滑稽]','25.png','20','20','30'],['316', '[贴吧_勉强]','26.png','20','20','30'],['309', '[贴吧_狂汗]','27.png','20','20','30'],['287', '[贴吧_乖]','28.png','20','20','30'],['278', '[贴吧_睡觉]','29.png','20','20','30'],['282', '[贴吧_惊哭]','30.png','20','20','30'],['312', '[贴吧_升起]','31.png','20','20','30'],['310', '[贴吧_惊讶]','32.png','20','20','30'],['283', '[贴吧_喷]','33.png','20','20','30'],['286', '[贴吧_爱心]','34.png','20','20','30'],['295', '[贴吧_心碎]','35.png','20','20','30'],['291', '[贴吧_玫瑰]','36.png','20','20','30'],['300', '[贴吧_礼物]','37.png','20','20','30'],['290', '[贴吧_彩虹]','38.png','20','20','30'],['302', '[贴吧_星星月亮]','39.png','20','20','30'],['324', '[贴吧_太阳]','40.png','20','20','30']];smilies_array[12][2] = [['276', '[贴吧_钱币]','41.png','20','20','30'],['279', '[贴吧_灯泡]','42.png','20','20','30'],['299', '[贴吧_茶杯]','43.png','20','20','30'],['315', '[贴吧_蛋糕]','44.png','20','20','30'],['277', '[贴吧_音乐]','45.png','20','20','30'],['297', '[贴吧_haha]','46.png','20','20','30'],['298', '[贴吧_胜利]','47.png','20','20','30'],['321', '[贴吧_大拇指]','48.png','20','20','30'],['311', '[贴吧_弱]','49.png','20','20','30'],['317', '[贴吧_OK]','50.png','20','20','30']];smilies_array[13] = new Array();smilies_array[13][1] = [['879', '[哔哩_脱单]','72.png','20','20','50'],['377', '[哔哩_口罩]','1.png','20','20','50'],['435', '[哔哩_微笑]','2.png','20','20','50'],['347', '[哔哩_笑]','3.png','20','20','50'],['367', '[哔哩_呲牙]','4.png','20','20','50'],['357', '[哔哩_OK]','5.png','20','20','50'],['399', '[哔哩_星星眼]','6.png','20','20','50'],['461', '[哔哩_哦呼]','7.png','20','20','50'],['369', '[哔哩_嫌弃]','8.png','20','20','50'],['419', '[哔哩_喜欢]','9.png','20','20','50'],['405', '[哔哩_酸了]','10.png','20','20','50'],['361', '[哔哩_大哭]','11.png','20','20','50'],['379', '[哔哩_害羞]','12.png','20','20','50'],['455', '[哔哩_无语]','13.png','20','20','50'],['381', '[哔哩_疑惑]','14.png','20','20','50'],['463', '[哔哩_调皮]','15.png','20','20','50'],['467', '[哔哩_喜极而泣]','16.png','20','20','50'],['449', '[哔哩_奸笑]','17.png','20','20','50'],['415', '[哔哩_偷笑]','18.png','20','20','50'],['413', '[哔哩_大笑]','19.png','20','20','50'],['411', '[哔哩_阴险]','20.png','20','20','50'],['441', '[哔哩_捂脸]','21.png','20','20','50'],['385', '[哔哩_囧]','22.png','20','20','50'],['457', '[哔哩_呆]','23.png','20','20','50'],['351', '[哔哩_抠鼻]','24.png','20','20','50'],['409', '[哔哩_惊喜]','25.png','20','20','50'],['445', '[哔哩_惊讶]','26.png','20','20','50'],['423', '[哔哩_笑哭]','27.png','20','20','50'],['365', '[哔哩_妙啊]','28.png','20','20','50'],['339', '[哔哩_doge]','29.png','20','20','50'],['353', '[哔哩_滑稽]','30.png','20','20','50'],['431', '[哔哩_吃瓜]','31.png','20','20','50'],['427', '[哔哩_打call]','32.png','20','20','50'],['355', '[哔哩_点赞]','33.png','20','20','50'],['363', '[哔哩_鼓掌]','34.png','20','20','50'],['383', '[哔哩_尴尬]','35.png','20','20','50'],['373', '[哔哩_冷]','36.png','20','20','50'],['397', '[哔哩_灵魂出窍]','37.png','20','20','50'],['371', '[哔哩_委屈]','38.png','20','20','50'],['403', '[哔哩_傲娇]','39.png','20','20','50']];smilies_array[13][2] = [['465', '[哔哩_疼]','40.png','20','20','50'],['333', '[哔哩_吓]','41.png','20','20','50'],['341', '[哔哩_生病]','42.png','20','20','50'],['395', '[哔哩_吐]','43.png','20','20','50'],['443', '[哔哩_嘘声]','44.png','20','20','50'],['337', '[哔哩_捂眼]','45.png','20','20','50'],['387', '[哔哩_思考]','46.png','20','20','50'],['391', '[哔哩_再见]','47.png','20','20','50'],['459', '[哔哩_翻白眼]','48.png','20','20','50'],['429', '[哔哩_哈欠]','49.png','20','20','50'],['447', '[哔哩_奋斗]','50.png','20','20','50'],['451', '[哔哩_墨镜]','51.png','20','20','50'],['343', '[哔哩_撇嘴]','52.png','20','20','50'],['469', '[哔哩_难过]','53.png','20','20','50'],['375', '[哔哩_抓狂]','54.png','20','20','50'],['393', '[哔哩_生气]','55.png','20','20','50'],['345', '[哔哩_视频卫星]','56.png','20','20','50'],['470', '[哔哩_歪嘴]','57.png','20','20','50'],['359', '[哔哩_鸡腿]','58.png','20','20','50'],['439', '[哔哩_干杯]','59.png','20','20','50'],['437', '[哔哩_爱心]','60.png','20','20','50'],['453', '[哔哩_锦鲤]','61.png','20','20','50'],['335', '[哔哩_胜利]','62.png','20','20','50'],['331', '[哔哩_加油]','63.png','20','20','50'],['349', '[哔哩_保佑]','64.png','20','20','50'],['421', '[哔哩_抱拳]','65.png','20','20','50'],['425', '[哔哩_响指]','66.png','20','20','50'],['417', '[哔哩_支持]','67.png','20','20','50'],['389', '[哔哩_拥抱]','68.png','20','20','50'],['401', '[哔哩_怪我咯]','69.png','20','20','50'],['407', '[哔哩_跪了]','70.png','20','20','50'],['471', '[哔哩_辣眼睛]','71.png','20','20','50']];smilies_array[15] = new Array();smilies_array[15][1] = [['525', '[抖音_525]','emoji_1.png','20','20','50'],['487', '[抖音_487]','emoji_2.png','20','20','50'],['500', '[抖音_500]','emoji_3.png','20','20','50'],['564', '[抖音_564]','emoji_4.png','20','20','50'],['481', '[抖音_481]','emoji_5.png','20','20','50'],['502', '[抖音_502]','emoji_6.png','20','20','50'],['533', '[抖音_533]','emoji_7.png','20','20','50'],['534', '[抖音_534]','emoji_8.png','20','20','50'],['515', '[抖音_515]','emoji_9.png','20','20','50'],['491', '[抖音_491]','emoji_10.png','20','20','50'],['541', '[抖音_541]','emoji_11.png','20','20','50'],['538', '[抖音_538]','emoji_12.png','20','20','50'],['542', '[抖音_542]','emoji_13.png','20','20','50'],['566', '[抖音_566]','emoji_14.png','20','20','50'],['565', '[抖音_565]','emoji_15.png','20','20','50'],['547', '[抖音_547]','emoji_16.png','20','19','50'],['524', '[抖音_524]','emoji_17.png','20','19','50'],['526', '[抖音_526]','emoji_18.png','20','19','50'],['488', '[抖音_488]','emoji_19.png','20','20','50'],['518', '[抖音_518]','emoji_20.png','20','20','50'],['554', '[抖音_554]','emoji_21.png','20','20','50'],['535', '[抖音_535]','emoji_22.png','20','20','50'],['578', '[抖音_578]','emoji_23.png','20','18','50'],['551', '[抖音_551]','emoji_24.png','20','20','50'],['506', '[抖音_506]','emoji_25.png','20','20','50'],['521', '[抖音_521]','emoji_26.png','20','18','50'],['497', '[抖音_497]','emoji_27.png','20','20','50'],['550', '[抖音_550]','emoji_28.png','20','19','50'],['540', '[抖音_540]','emoji_29.png','20','20','50'],['536', '[抖音_536]','emoji_30.png','20','20','50'],['513', '[抖音_513]','emoji_31.png','20','20','50'],['494', '[抖音_494]','emoji_32.png','20','20','50'],['484', '[抖音_484]','emoji_33.png','20','19','50'],['570', '[抖音_570]','emoji_34.png','20','20','50'],['520', '[抖音_520]','emoji_35.png','20','20','50'],['482', '[抖音_482]','emoji_36.png','20','20','50'],['516', '[抖音_516]','emoji_37.png','20','20','50'],['478', '[抖音_478]','emoji_38.png','20','18','50'],['477', '[抖音_477]','emoji_39.png','20','20','50'],['557', '[抖音_557]','emoji_40.png','20','20','50']];smilies_array[15][2] = [['539', '[抖音_539]','emoji_41.png','20','20','50'],['474', '[抖音_474]','emoji_42.png','20','20','50'],['490', '[抖音_490]','emoji_43.png','20','20','50'],['572', '[抖音_572]','emoji_44.png','20','20','50'],['509', '[抖音_509]','emoji_45.png','20','20','50'],['548', '[抖音_548]','emoji_46.png','20','20','50'],['559', '[抖音_559]','emoji_47.png','20','20','50'],['499', '[抖音_499]','emoji_48.png','20','20','50'],['579', '[抖音_579]','emoji_49.png','20','20','50'],['476', '[抖音_476]','emoji_50.png','20','20','50'],['501', '[抖音_501]','emoji_51.png','20','19','50'],['475', '[抖音_475]','emoji_52.png','20','20','50'],['530', '[抖音_530]','emoji_53.png','20','20','50'],['581', '[抖音_581]','emoji_54.png','20','20','50'],['495', '[抖音_495]','emoji_55.png','20','20','50'],['507', '[抖音_507]','emoji_56.png','20','20','50'],['527', '[抖音_527]','emoji_57.png','20','20','50'],['505', '[抖音_505]','emoji_58.png','20','20','50'],['532', '[抖音_532]','emoji_59.png','20','20','50'],['577', '[抖音_577]','emoji_60.png','20','20','50'],['545', '[抖音_545]','emoji_61.png','20','19','50'],['560', '[抖音_560]','emoji_62.png','20','20','50'],['492', '[抖音_492]','emoji_63.png','20','20','50'],['574', '[抖音_574]','emoji_64.png','20','20','50'],['529', '[抖音_529]','emoji_65.png','20','20','50'],['543', '[抖音_543]','emoji_66.png','20','19','50'],['568', '[抖音_568]','emoji_67.png','20','19','50'],['562', '[抖音_562]','emoji_68.png','20','18','50'],['480', '[抖音_480]','emoji_69.png','20','15','50'],['552', '[抖音_552]','emoji_70.png','20','20','50'],['537', '[抖音_537]','emoji_71.png','20','20','50'],['556', '[抖音_556]','emoji_72.png','20','20','50'],['510', '[抖音_510]','emoji_73.png','20','20','50'],['504', '[抖音_504]','emoji_74.png','20','20','50'],['485', '[抖音_485]','emoji_75.png','20','20','50'],['522', '[抖音_522]','emoji_76.png','20','20','50'],['528', '[抖音_528]','emoji_77.png','20','20','50'],['473', '[抖音_473]','emoji_78.png','20','20','50'],['512', '[抖音_512]','emoji_80.png','20','20','50'],['496', '[抖音_496]','emoji_81.png','20','19','50']];smilies_array[15][3] = [['549', '[抖音_549]','emoji_82.png','20','20','50'],['563', '[抖音_563]','emoji_83.png','20','20','50'],['479', '[抖音_479]','emoji_84.png','20','19','50'],['546', '[抖音_546]','emoji_85.png','20','20','50'],['489', '[抖音_489]','emoji_86.png','20','20','50'],['571', '[抖音_571]','emoji_87.png','20','20','50'],['511', '[抖音_511]','emoji_88.png','20','19','50'],['575', '[抖音_575]','emoji_89.png','20','20','50'],['567', '[抖音_567]','emoji_90.png','20','20','50'],['555', '[抖音_555]','emoji_91.png','20','20','50'],['483', '[抖音_483]','emoji_92.png','20','20','50'],['519', '[抖音_519]','emoji_93.png','20','20','50'],['544', '[抖音_544]','emoji_94.png','20','20','50'],['531', '[抖音_531]','emoji_95.png','20','18','50'],['576', '[抖音_576]','emoji_96.png','20','20','50'],['756', '[抖音_756]','emoji_97.png','20','20','50'],['523', '[抖音_523]','emoji_98.png','20','20','50'],['569', '[抖音_569]','emoji_99.png','20','20','50'],['486', '[抖音_486]','emoji_100.png','20','20','50'],['508', '[抖音_508]','emoji_101.png','20','20','50'],['585', '[抖音_585]','emoji_10001.png','20','20','50'],['553', '[抖音_553]','emoji_102.png','20','20','50'],['561', '[抖音_561]','emoji_103.png','20','20','50'],['580', '[抖音_580]','emoji_104.png','20','20','50'],['558', '[抖音_558]','emoji_105.png','20','20','50'],['573', '[抖音_573]','emoji_106.png','20','20','50'],['517', '[抖音_517]','emoji_107.png','20','20','50'],['503', '[抖音_503]','emoji_108.png','20','20','28'],['514', '[抖音_514]','emoji_109.png','20','20','50'],['498', '[抖音_498]','emoji_110.png','20','20','50'],['493', '[抖音_493]','emoji_111.png','20','20','50'],['584', '[抖音_584]','emoji_112.png','20','20','50'],['583', '[抖音_583]','emoji_113.png','20','20','50'],['582', '[抖音_582]','emoji_114.png','20','20','50']];smilies_array[17] = new Array();smilies_array[17][1] = [['757', '[QQ_106]','106.png','20','20','28'],['758', '[QQ_107]','107.png','20','20','28'],['759', '[QQ_88]','88.png','20','20','28'],['760', '[QQ_89]','89.png','20','20','28'],['761', '[QQ_103]','103.png','20','20','28'],['762', '[QQ_100]','100.png','20','20','28'],['763', '[QQ_101]','101.png','20','20','28'],['764', '[QQ_110]','110.png','20','20','28'],['765', '[QQ_99]','99.png','20','20','28'],['766', '[QQ_91]','91.png','20','20','28'],['767', '[QQ_112]','112.png','20','20','28'],['768', '[QQ_104]','104.png','20','20','28'],['769', '[QQ_105]','105.png','20','20','28'],['770', '[QQ_92]','92.png','20','20','28'],['771', '[QQ_108]','108.png','20','20','28'],['772', '[QQ_109]','109.png','20','20','28'],['773', '[QQ_90]','90.png','20','20','28'],['774', '[QQ_93]','93.png','20','20','28'],['775', '[QQ_87]','87.png','20','20','28'],['776', '[QQ_102]','102.png','20','20','28'],['777', '[QQ_86]','86.png','20','20','28'],['778', '[QQ_131]','131.gif','20','20','24'],['779', '[QQ_128]','128.gif','20','20','24'],['780', '[QQ_124]','124.png','20','20','28'],['781', '[QQ_130]','130.gif','20','20','24'],['782', '[QQ_115]','115.png','20','20','28'],['783', '[QQ_114]','114.gif','20','20','24'],['784', '[QQ_141]','141.gif','20','20','24'],['785', '[QQ_129]','129.gif','20','20','24'],['786', '[QQ_126]','126.gif','20','20','24'],['787', '[QQ_123]','123.gif','20','20','24'],['788', '[QQ_120]','120.png','20','20','28'],['789', '[QQ_136]','136.gif','20','20','24'],['790', '[QQ_121]','121.png','20','20','28'],['791', '[QQ_132]','132.gif','20','20','24'],['792', '[QQ_134]','134.gif','20','20','24'],['793', '[QQ_127]','127.gif','20','20','24'],['794', '[QQ_139]','139.gif','20','20','24'],['795', '[QQ_118]','118.png','20','20','28'],['796', '[QQ_122]','122.png','20','20','28']];smilies_array[17][2] = [['797', '[QQ_119]','119.png','20','20','28'],['798', '[QQ_140]','140.gif','20','20','24'],['799', '[QQ_117]','117.png','20','20','28'],['800', '[QQ_135]','135.gif','20','20','24'],['801', '[QQ_142]','142.gif','20','20','24'],['802', '[QQ_113]','113.png','20','20','28'],['803', '[QQ_138]','138.gif','20','20','24'],['804', '[QQ_137]','137.gif','20','20','24'],['805', '[QQ_125]','125.gif','20','20','24'],['806', '[QQ_116]','116.png','20','20','28'],['701', '[QQ_1]','1.png','20','20','28'],['735', '[QQ_2]','2.png','20','20','28'],['680', '[QQ_3]','3.png','20','20','28'],['692', '[QQ_4]','4.png','20','20','28'],['687', '[QQ_5]','5.png','20','20','28'],['712', '[QQ_6]','6.png','20','20','28'],['693', '[QQ_8]','8.png','20','20','28'],['723', '[QQ_9]','9.png','20','20','28'],['716', '[QQ_10]','10.png','20','20','28'],['689', '[QQ_11]','11.png','20','20','28'],['702', '[QQ_12]','12.png','20','20','28'],['747', '[QQ_13]','13.png','20','20','28'],['703', '[QQ_14]','14.png','20','20','28'],['751', '[QQ_15]','15.png','20','20','28'],['753', '[QQ_16]','16.png','20','20','28'],['744', '[QQ_17]','17.png','20','20','28'],['721', '[QQ_18]','18.png','20','20','28'],['720', '[QQ_19]','19.png','20','20','28'],['719', '[QQ_20]','20.png','20','20','28'],['739', '[QQ_21]','21.png','20','20','28'],['705', '[QQ_22]','22.png','20','20','28'],['748', '[QQ_23]','23.png','20','20','28'],['682', '[QQ_24]','24.png','20','20','28'],['718', '[QQ_25]','25.png','20','20','28'],['741', '[QQ_26]','26.png','20','20','28'],['727', '[QQ_27]','27.png','20','20','28'],['691', '[QQ_28]','28.png','20','20','28'],['675', '[QQ_29]','29.png','20','20','28'],['685', '[QQ_30]','30.png','20','20','28'],['733', '[QQ_31]','31.png','20','20','28']];smilies_array[17][3] = [['730', '[QQ_32]','32.png','20','20','28'],['686', '[QQ_33]','33.png','20','20','28'],['690', '[QQ_34]','34.png','20','20','28'],['704', '[QQ_35]','35.png','20','20','28'],['697', '[QQ_36]','36.png','20','20','28'],['711', '[QQ_37]','37.png','20','20','28'],['695', '[QQ_38]','38.png','20','20','28'],['715', '[QQ_39]','39.png','20','20','28'],['752', '[QQ_40]','40.png','20','20','28'],['672', '[QQ_41]','41.png','20','20','28'],['677', '[QQ_42]','42.png','20','20','28'],['710', '[QQ_43]','43.png','20','20','28'],['740', '[QQ_44]','44.png','20','20','28'],['674', '[QQ_45]','45.png','20','20','28'],['706', '[QQ_46]','46.png','20','20','28'],['708', '[QQ_47]','47.png','20','20','28'],['750', '[QQ_48]','48.png','20','20','28'],['731', '[QQ_49]','49.png','20','20','28'],['743', '[QQ_50]','50.png','20','20','28'],['745', '[QQ_51]','51.png','20','20','28'],['678', '[QQ_52]','52.png','20','20','28'],['755', '[QQ_53]','53.png','20','20','28'],['699', '[QQ_54]','54.png','20','20','28'],['709', '[QQ_55]','55.png','20','20','28'],['679', '[QQ_56]','56.png','20','20','28'],['734', '[QQ_57]','57.png','20','20','28'],['688', '[QQ_58]','58.png','20','20','28'],['738', '[QQ_59]','59.png','20','20','28'],['737', '[QQ_60]','60.png','20','20','28'],['746', '[QQ_61]','61.png','20','20','28'],['673', '[QQ_62]','62.png','20','20','28'],['694', '[QQ_625]','625.png','20','20','28'],['671', '[QQ_63]','63.png','20','20','28'],['681', '[QQ_64]','64.png','20','20','28'],['725', '[QQ_65]','65.png','20','20','28'],['728', '[QQ_66]','66.png','20','20','28'],['722', '[QQ_67]','67.png','20','20','28'],['707', '[QQ_68]','68.png','20','20','28'],['714', '[QQ_69]','69.png','20','20','28'],['717', '[QQ_70]','70.png','20','20','28']];smilies_array[17][4] = [['749', '[QQ_71]','71.png','20','20','28'],['683', '[QQ_72]','72.png','20','20','28'],['754', '[QQ_73]','73.png','20','20','28'],['713', '[QQ_74]','74.png','20','20','28'],['698', '[QQ_75]','75.png','20','20','28'],['736', '[QQ_76]','76.png','20','20','28'],['729', '[QQ_77]','77.png','20','20','28'],['724', '[QQ_78]','78.png','20','20','28'],['732', '[QQ_79]','79.png','20','20','28'],['676', '[QQ_80]','80.png','20','20','28'],['696', '[QQ_81]','81.png','20','20','28'],['726', '[QQ_82]','82.png','20','20','28'],['684', '[QQ_83]','83.png','20','20','28'],['742', '[QQ_84]','84.png','20','20','28'],['700', '[QQ_85]','85.png','20','20','28']];var smilies_fast=[['12','1','15'],['12','1','24'],['12','1','32'],['12','1','34'],['12','1','35'],['12','2','2'],['12','2','7'],['12','2','8']];
''';

  // ---------------------------------------------------------------------
  // 版块导航
  // ---------------------------------------------------------------------
  static List<Forum> parseForums(String html) {
    final doc = html_parser.parse(html);
    final result = <Forum>[];
    final seen = <int>{};

    for (final a in doc.querySelectorAll(
      'a[href*="forum-"], a[href*="forumdisplay"]',
    )) {
      final href = a.attributes['href'] ?? '';
      final m = RegExp(
        r'forum-(\d+)-\d+\.html|forumdisplay[^"]*fid=(\d+)',
      ).firstMatch(href);
      if (m == null) continue;
      final fid = int.tryParse(m.group(1) ?? m.group(2) ?? '');
      if (fid == null || seen.contains(fid)) continue;
      final name = a.text.trim();
      if (name.isEmpty) continue;
      seen.add(fid);
      registerForumName(fid, name);
      result.add(Forum(fid: fid, name: name));
    }
    return result;
  }

  /// ---------------------------------------------------------------------
  /// 解析 Discuz 用户收藏版块列表（支持从 space favorite type=forum 页面提取 fid, favid, name, description 等）
  /// ---------------------------------------------------------------------
  static List<Forum> parseFavoriteForums(String html) {
    if (html.isEmpty) return const [];
    final doc = html_parser.parse(html);
    final result = <Forum>[];
    final seen = <int>{};

    // 1. 从各容器条目（tr, li, div）中提取
    final items = doc.querySelectorAll(
      'ul#favorite_ul li, #ct table tr, #favoriteform li, #favoriteform tr, div[id^="fav_"], tr[id^="fav_"], li[id^="fav_"]',
    );
    for (final el in items) {
      final a = el.querySelector('a[href*="forum-"], a[href*="forumdisplay"], a[href*="fid="]');
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final fm = RegExp(r'forum-(\d+)-\d+\.html|forumdisplay[^"]*fid=(\d+)|fid=(\d+)').firstMatch(href);
      if (fm == null) continue;
      final fid = int.tryParse(fm.group(1) ?? fm.group(2) ?? fm.group(3) ?? '');
      if (fid == null || fid <= 0 || !seen.add(fid)) continue;

      var name = _cleanTitle(a.text.trim());
      if (name.isEmpty) name = getForumNameByFid(fid) ?? '版块 $fid';

      int? favid;
      final inp = el.querySelector('input[name*="favorite"]');
      if (inp != null) {
        favid = int.tryParse(inp.attributes['value'] ?? '');
      }
      if (favid == null || favid <= 0) {
        final idAttr = el.attributes['id'] ?? '';
        final mId = RegExp(r'fav_(\d+)').firstMatch(idAttr);
        if (mId != null) favid = int.tryParse(mId.group(1)!);
      }
      if (favid == null || favid <= 0) {
        final delA = el.querySelector('a[href*="favid="]');
        if (delA != null) {
          final mDel = RegExp(r'favid=(\d+)').firstMatch(delA.attributes['href'] ?? '');
          if (mDel != null) favid = int.tryParse(mDel.group(1)!);
        }
      }

      final desc = el.querySelector('.xg1, .description, p')?.text.trim();

      registerForumName(fid, name);
      result.add(
        Forum(
          fid: fid,
          name: name,
          description: desc,
          favid: favid,
        ),
      );
    }

    // 2. 兜底通用匹配
    if (result.isEmpty) {
      for (final a in doc.querySelectorAll('a[href*="forum-"], a[href*="forumdisplay"]')) {
        final href = a.attributes['href'] ?? '';
        final fm = RegExp(r'forum-(\d+)-\d+\.html|forumdisplay[^"]*fid=(\d+)').firstMatch(href);
        if (fm == null) continue;
        final fid = int.tryParse(fm.group(1) ?? fm.group(2) ?? '');
        if (fid == null || fid <= 0 || !seen.add(fid)) continue;
        final name = _cleanTitle(a.text.trim());
        if (name.isNotEmpty && !name.contains('论坛') && !name.contains('版块') && !name.contains('返回')) {
          registerForumName(fid, name);
          result.add(Forum(fid: fid, name: name));
        }
      }
    }

    return result;
  }

  /// ---------------------------------------------------------------------
  /// 解析当前版块的真实子版块列表（排除全站导航、服务器列表等全局头部链接）
  /// ---------------------------------------------------------------------
  static List<Forum> parseSubForums(String html, {int? currentFid}) {
    final doc = html_parser.parse(html);
    final result = <Forum>[];
    final seen = <int>{};
    if (currentFid != null && currentFid > 0) seen.add(currentFid);

    // 排除全站通用导航、页脚、侧边栏及全站门面模块
    final cleanDoc = doc.clone(true);
    cleanDoc
        .querySelectorAll(
          '#comiis_nav, #nv, #ft, .footer, #toptb, #hd, #um, .hdc, .sub_nav, .comiis_head, .sidebar, [id^="portal_block_"], table.fl_tb',
        )
        .forEach((e) => e.remove());

    // 仅在真实当前版块子版块专属容器内匹配链接
    final subContainer = cleanDoc.querySelector(
      '#subforum, .sub_forum, div.comiis_sublist, #subforum_list, ul.comiis_sub_list, div.comiis_subforum',
    );
    if (subContainer != null) {
      for (final a in subContainer.querySelectorAll(
        'a[href*="forum-"], a[href*="fid="]',
      )) {
        final href = a.attributes['href'] ?? '';
        final m = RegExp(
          r'forum-(\d+)-\d+\.html|forumdisplay[^"]*fid=(\d+)',
        ).firstMatch(href);
        if (m == null) continue;
        final fid = int.tryParse(m.group(1) ?? m.group(2) ?? '');
        if (fid == null || fid <= 0 || !seen.add(fid)) continue;

        final name = a.text.trim();
        if (name.isEmpty ||
            name.length < 2 ||
            name == '论坛' ||
            name == '首页' ||
            name == '全部' ||
            name == '服务器列表' ||
            name == '签约中心' ||
            name == '充值铁粒') {
          continue;
        }

        result.add(Forum(fid: fid, name: name));
      }
    }
    return result;
  }

  /// 解析全站统计数据（今日发帖 / 昨日发帖 / 论坛总帖 / 注册会员）
  /// 完美支持 Discuz/克米移动端 `.tj_today, .tj_yesterday, .tj_posts, .tj_members`
  /// 以及 PC 端 `#chart .chart_tj` 与通用全局结构（严格避免匹配局部版块如「闲聊讨论 今日: 10」）
  static SiteStats parseSiteStats(String html) {
    if (html.isEmpty) return const SiteStats();
    final doc = html_parser.parse(html);
    int today = 0;
    int yesterday = 0;
    int posts = 0;
    int members = 0;

    // 1. PC 端与移动端标准 chart 容器（#chart, .chart_tj, div.chart_tj, .chart）
    final chartEl = doc.querySelector('#chart, .chart_tj, div.chart_tj, .chart');
    if (chartEl != null) {
      final todayEl = chartEl.querySelector('.tj_today, p.tj_today');
      if (todayEl != null) {
        final m = RegExp(r'(\d+)').firstMatch(todayEl.text);
        if (m != null) today = int.tryParse(m.group(1)!) ?? 0;
      } else {
        final m = RegExp(r'今日[:：]?\s*(\d+)').firstMatch(chartEl.text);
        if (m != null) today = int.tryParse(m.group(1)!) ?? 0;
      }

      final yesterdayEl = chartEl.querySelector('.tj_yesterday, p.tj_yesterday');
      if (yesterdayEl != null) {
        final m = RegExp(r'(\d+)').firstMatch(yesterdayEl.text);
        if (m != null) yesterday = int.tryParse(m.group(1)!) ?? 0;
      } else {
        final m = RegExp(r'昨日[:：]?\s*(\d+)').firstMatch(chartEl.text);
        if (m != null) yesterday = int.tryParse(m.group(1)!) ?? 0;
      }

      final postsEl = chartEl.querySelector('.tj_posts, p.tj_posts');
      if (postsEl != null) {
        final m = RegExp(r'(\d+)').firstMatch(postsEl.text);
        if (m != null) posts = int.tryParse(m.group(1)!) ?? 0;
      } else {
        final m = RegExp(r'(?:总帖|帖子)[:：]?\s*(\d+)').firstMatch(chartEl.text);
        if (m != null) posts = int.tryParse(m.group(1)!) ?? 0;
      }

      final membersEl = chartEl.querySelector('.tj_members, p.tj_members');
      if (membersEl != null) {
        final m = RegExp(r'(\d+)').firstMatch(membersEl.text);
        if (m != null) members = int.tryParse(m.group(1)!) ?? 0;
      } else {
        final m = RegExp(r'会员[:：]?\s*(\d+)').firstMatch(chartEl.text);
        if (m != null) members = int.tryParse(m.group(1)!) ?? 0;
      }
    }

    // 2. 仅在匹配到全站级总帖数（>10000）或全站会员数（>10000）时才从全局提取今日/昨日发帖
    if (posts == 0 || members == 0) {
      final postsM = RegExp(r'(?:总帖|全站帖子|帖子总数)[:：]?\s*(\d{5,})').firstMatch(html) ??
          RegExp(r'class=[\x27\"][^\x27\"]*tj_posts[^\x27\"]*[\x27\"][^>]*>.*?(?:总帖|帖子)[:：]?\s*(\d+)').firstMatch(html);
      if (postsM != null) posts = int.tryParse(postsM.group(1)!) ?? 0;

      final membM = RegExp(r'(?:会员|注册会员|会员总数)[:：]?\s*(\d{5,})').firstMatch(html) ??
          RegExp(r'class=[\x27\"][^\x27\"]*tj_members[^\x27\"]*[\x27\"][^>]*>.*?会员[:：]?\s*(\d+)').firstMatch(html);
      if (membM != null) members = int.tryParse(membM.group(1)!) ?? 0;

      if (posts > 0 || members > 0) {
        if (today == 0) {
          final todayM = RegExp(r'(?:今日|今日发帖)[:：]?\s*(?:<[^>]+>)?\s*(\d+)').firstMatch(html);
          if (todayM != null) today = int.tryParse(todayM.group(1)!) ?? 0;
        }
        if (yesterday == 0) {
          final yestM = RegExp(r'(?:昨日|昨日发帖)[:：]?\s*(?:<[^>]+>)?\s*(\d+)').firstMatch(html);
          if (yestM != null) yesterday = int.tryParse(yestM.group(1)!) ?? 0;
        }
      }
    }

    return SiteStats(
      todayPosts: today,
      yesterdayPosts: yesterday,
      totalPosts: posts,
      totalMembers: members,
    );
  }

  /// 解析土豪霸屏广播（从首页 script 标签内 var data = [...] 或 DOM 中动态提取，无霸屏时严格返回 null）
  static ({String author, String avatarUrl, String message, String linkUrl, int tid})?
  parseTuhaoBanner(String html) {
    if (html.isEmpty) return null;
    try {
      // 1. 优先从首页 script 中的 ahorn_boss / ahome_horn JSON 数据提取
      final m = RegExp(r'var\s+data\s*=\s*(\[\s*\{.*?\}\s*\]);', dotAll: true).firstMatch(html) ??
          RegExp(r'var\s+ahorn_boss\s*=\s*(\[\s*\{.*?\}\s*\]);', dotAll: true).firstMatch(html);
      if (m != null) {
        final jsonStr = m.group(1)!;
        final decoded = jsonDecode(jsonStr);
        if (decoded is List && decoded.isNotEmpty) {
          final first = decoded.first;
          if (first is Map) {
            final name = (first['n'] ?? first['username'] ?? first['author'] ?? '').toString().trim();
            final rawImg = (first['a'] ?? first['avatar'] ?? '').toString();
            final msg = (first['m'] ?? first['message'] ?? first['content'] ?? '').toString().trim();

            String avatarUrl = '';
            final imgM = RegExp(r'src=[\x27\\"]([^\x27\\"]+)[\x27\\"]').firstMatch(rawImg);
            if (imgM != null) {
              avatarUrl = imgM.group(1)!.replaceAll(r'\/', '/');
            } else if (rawImg.startsWith('http')) {
              avatarUrl = rawImg;
            }

            String linkUrl = '';
            int tid = 0;
            final urlM = RegExp(r'https?://[^\s"<>\x27]+').firstMatch(msg);
            if (urlM != null) {
              linkUrl = urlM.group(0)!;
              final tidM = RegExp(r'thread-(\d+)|tid=(\d+)').firstMatch(linkUrl);
              if (tidM != null) {
                tid = int.tryParse(tidM.group(1) ?? tidM.group(2) ?? '') ?? 0;
              }
            }

            if (name.isNotEmpty && msg.isNotEmpty) {
              return (
                author: _cleanTitle(name),
                avatarUrl: avatarUrl,
                message: _cleanTitle(msg),
                linkUrl: linkUrl,
                tid: tid,
              );
            }
          }
        }
      }

      // 2. 从 DOM 中查找土豪霸屏区域 (#ahorn_boss, .ahorn_boss, .comiis_tuhao)
      final doc = html_parser.parse(html);
      final tuhaoBox = doc.querySelector('#ahorn_boss, .ahorn_boss, .comiis_tuhao, div[id*="tuhao"]');
      if (tuhaoBox != null) {
        final nameEl = tuhaoBox.querySelector('.name, .author, h3, h4, .comiis_user');
        final name = nameEl?.text.trim() ?? '';
        final imgEl = tuhaoBox.querySelector('img');
        final avatar = imgEl?.attributes['src'] ?? '';
        final msgEl = tuhaoBox.querySelector('.msg, .content, .text, p, a');
        final msg = msgEl?.text.trim() ?? '';
        final link = tuhaoBox.querySelector('a')?.attributes['href'] ?? '';
        final tidM = RegExp(r'thread-(\d+)|tid=(\d+)').firstMatch(link);
        final tid = int.tryParse(tidM?.group(1) ?? tidM?.group(2) ?? '') ?? 0;

        if (name.isNotEmpty && msg.isNotEmpty) {
          return (
            author: _cleanTitle(name),
            avatarUrl: avatar,
            message: _cleanTitle(msg),
            linkUrl: link,
            tid: tid,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  static List<ForumGroup> parseForumGroups(String html) {
    if (html.isEmpty) return const [];
    final doc = html_parser.parse(html);
    final groups = <ForumGroup>[];
    final seenGids = <int>{};

    const standardGroupNames = {
      0: '我关注的',
      1: '综合分区',
      110: '灵感交流',
      37: 'BE资源分区',
      36: 'JE资源分区',
      38: '多人游戏',
      40: '其他分区',
      39: '论坛事务',
    };

    // 1. 移动端克米模板：div.comiis_forumlist 与 div.comiis_fl
    for (final fl in doc.querySelectorAll('div.comiis_forumlist, div.comiis_fl')) {
      int gid = -1;
      for (final c in fl.classes) {
        final m = RegExp(r'comiis_km(\d+)').firstMatch(c);
        if (m != null) {
          gid = int.tryParse(m.group(1)!) ?? -1;
          break;
        }
      }

      final show = fl.querySelector('div.comiis_bbs_show, .comiis_fl_title, h2');
      if (gid < 0 && show != null) {
        final href = show.attributes['href'] ?? '';
        final m = RegExp(r'sub_forum_(\d+)').firstMatch(href);
        if (m != null) gid = int.tryParse(m.group(1)!) ?? -1;
      }

      var name = (show?.querySelector('h2 a, h2, a')?.text ?? show?.text ?? '').trim();
      name = _cleanTitle(name);
      name = name
          .replaceAll(RegExp(r'(?:\[?管理\]?|展开|收起|设置|更多)$'), '')
          .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
          .trim();

      // 精准识别「我关注的」专属快捷分区 (gid 0)
      if (gid == 0 || name.contains('关注') || (fl.attributes['id'] ?? '').contains('fav')) {
        gid = 0;
        name = '我关注的';
      }

      if (gid < 0) {
        if (name.isEmpty) continue;
        gid = groups.length + 1;
      }

      if (standardGroupNames.containsKey(gid)) {
        name = standardGroupNames[gid]!;
      }

      if (!seenGids.add(gid)) continue;

      final forums = <Forum>[];
      final box = (gid >= 0 ? doc.querySelector('#sub_forum_$gid') : null) ??
          fl.querySelector('div.comiis_forum_nbox, ul, div.cl');
      if (box != null) {
        for (final a in box.querySelectorAll('a[href*="forum-"], a[href*="fid="]')) {
          final fhref = a.attributes['href'] ?? '';
          final fm = RegExp(r'forum-(\d+)-\d+\.html|fid=(\d+)').firstMatch(fhref);
          int? fid;
          if (fm != null) {
            fid = int.tryParse(fm.group(1) ?? fm.group(2) ?? '');
          } else if (fhref.contains('skin')) {
            fid = 50; // 皮肤分享特殊别名
          }
          if (fid == null || fid <= 0 || forums.any((f) => f.fid == fid)) continue;

          String? iconUrl;
          final img = a.querySelector('img');
          var fname = (img?.attributes['alt'] ?? '').trim();
          if (fname.isEmpty) {
            final raw = (a.querySelector('p')?.text ?? a.querySelector('span')?.text ?? a.text).trim();
            fname = raw.replaceAll(RegExp(r'今日[:：]?\s*\d+|帖数[:：]?\s*\d+|\d+'), '').trim();
          }
          fname = _cleanTitle(fname);
          if (fname.isEmpty) continue;

          if (img != null) {
            var rawIcon = img.attributes['comiis_loadimages'] ?? '';
            if (rawIcon.isEmpty || rawIcon.contains('none.png') || rawIcon.contains('spacer.gif')) {
              rawIcon = img.attributes['data-src'] ?? '';
            }
            if (rawIcon.isEmpty || rawIcon.contains('none.png') || rawIcon.contains('spacer.gif')) {
              rawIcon = img.attributes['file'] ?? '';
            }
            if (rawIcon.isEmpty || rawIcon.contains('none.png') || rawIcon.contains('spacer.gif')) {
              rawIcon = img.attributes['src'] ?? '';
            }
            if (rawIcon.isNotEmpty && !rawIcon.contains('none.png') && !rawIcon.contains('spacer.gif')) {
              iconUrl = _absolute(rawIcon);
            }
          }

          var threadCount = -1;
          var todayCount = -1;
          final aText = a.text.trim();
          final tm = RegExp(r'今日[:：]?\s*(\d+)').firstMatch(aText);
          if (tm != null) {
            todayCount = int.tryParse(tm.group(1)!) ?? -1;
          } else {
            final leadM = RegExp(r'^(\d+)').firstMatch(aText);
            if (leadM != null) {
              todayCount = int.tryParse(leadM.group(1)!) ?? -1;
            }
          }

          final thm = RegExp(r'帖数[:：]?\s*(\d+)').firstMatch(aText);
          if (thm != null) {
            threadCount = int.tryParse(thm.group(1)!) ?? -1;
          }

          String desc = '';
          final descM = RegExp(r'别名[:：]?(.*)').firstMatch(aText);
          if (descM != null) {
            desc = '别名: ${_cleanTitle(descM.group(1)!.trim())}';
          }

          forums.add(
            Forum(
              fid: fid,
              name: fname,
              gid: gid,
              iconUrl: iconUrl,
              threadCount: threadCount,
              todayCount: todayCount,
              description: desc,
            ),
          );
        }
      }

      if (forums.isNotEmpty) {
        groups.add(ForumGroup(gid: gid, name: name, forums: forums));
      }
    }

    // 2. PC 端与通用 Discuz 结构：table.fl_tb 或 div.fl.bm 或 .bm.bmw.cl
    if (groups.isEmpty) {
      for (final block in doc.querySelectorAll('.bm.bmw.cl, table.fl_tb, div.fl')) {
        final h2 = block.querySelector('.bm_h h2 a, .bm_h h2, h2 a, h2');
        var name = _cleanTitle(h2?.text ?? '');
        if (name.isEmpty || name == '论坛' || name.contains('小喇叭') || name.contains('关注')) continue;
        final gidM = RegExp(r'gid=(\d+)').firstMatch(h2?.attributes['href'] ?? '');
        final gid = gidM != null ? int.tryParse(gidM.group(1)!) ?? (groups.length + 1) : (groups.length + 1);
        if (standardGroupNames.containsKey(gid)) {
          name = standardGroupNames[gid]!;
        }
        if (!seenGids.add(gid)) continue;

        final forums = <Forum>[];
        for (final item in block.querySelectorAll('td.fl_g, td.fl_icn, dt a, h2 a')) {
          final a = item.localName == 'a' ? item : item.querySelector('dt a, h2 a, a[href*="forum-"], a[href*="fid="]');
          if (a == null) continue;
          final href = a.attributes['href'] ?? '';
          final fm = RegExp(r'forum-(\d+)-\d+\.html|fid=(\d+)').firstMatch(href);
          if (fm == null) continue;
          final fid = int.tryParse(fm.group(1) ?? fm.group(2) ?? '');
          if (fid == null || fid <= 0 || forums.any((f) => f.fid == fid)) continue;

          final fname = _cleanTitle(a.text.trim());
          if (fname.isEmpty) continue;

          var today = -1;
          final em = item.querySelector('em, span.xi1');
          if (em != null) {
            final emM = RegExp(r'(\d+)').firstMatch(em.text);
            if (emM != null) today = int.tryParse(emM.group(1)!) ?? -1;
          }

          forums.add(Forum(
            fid: fid,
            name: fname,
            gid: gid,
            todayCount: today,
          ));
        }

        if (forums.isNotEmpty) {
          groups.add(ForumGroup(gid: gid, name: name, forums: forums));
        }
      }
    }

    return groups;
  }

  /// 解析版块头部导览、Banner 与统计（forumdisplay PC / 移动端头部）
  static ForumHeaderInfo parseForumHeader(String html, int fid) {
    final doc = html_parser.parse(html);
    var name = '';
    String? bannerUrl;
    var todayPosts = 0;
    var threadsCount = 0;
    var rank = 0;
    var favCount = 0;
    var moderators = '';
    var rulesHtml = '';

    // 1. 版块名称与 Banner 顶图
    final nameEl = doc.querySelector(
      '.bm.bml h1, div.bml h1, #pt a:last-child, h1.xs2, div.comiis_head h2',
    );
    if (nameEl != null) {
      name = _cleanTitle(nameEl.text);
    }

    final cbanner = doc.querySelector('.cbanner');
    if (cbanner != null) {
      final style = cbanner.attributes['style'] ?? '';
      final bgMatch = RegExp(r'''url\(['"]?(.*?)['"]?\)''').firstMatch(style);
      if (bgMatch != null && bgMatch.group(1)!.isNotEmpty) {
        bannerUrl = _absolute(bgMatch.group(1)!.trim());
      }
    }
    if (bannerUrl == null || bannerUrl.isEmpty) {
      final bannerImg = doc.querySelector(
        '.bm.bml > img, div.bml img, .cbanner img, .bml_img img, .comiis_forum_banner img, div.wp img[src*="banner"], div.wp img[src*="source/plugin"], div.boardnav img[src*="source/plugin"]',
      );
      if (bannerImg != null) {
        final src =
            bannerImg.attributes['src'] ?? bannerImg.attributes['data-src'];
        bannerUrl = _absolute(src);
      }
    }

    // 2. 统计数据提取（今日、主题数、排名、收藏数）
    final text = doc.body?.text ?? '';
    final tm = RegExp(r'今日[:：]?\s*(\d+)').firstMatch(text);
    if (tm != null) todayPosts = int.tryParse(tm.group(1)!) ?? 0;

    final thm = RegExp(r'主题[:：]?\s*(\d+)').firstMatch(text);
    if (thm != null) threadsCount = int.tryParse(thm.group(1)!) ?? 0;

    final rm = RegExp(r'排名[:：]?\s*(\d+)').firstMatch(text);
    if (rm != null) rank = int.tryParse(rm.group(1)!) ?? 0;

    final fm = RegExp(r'收藏本版[^\d]*(\d+)').firstMatch(text);
    if (fm != null) favCount = int.tryParse(fm.group(1)!) ?? 0;

    // 3. 版主信息
    final modEl = doc.querySelector(
      '#forum_modedby, div.bml_c span.xi2, div[id*="modedby"], div.bm_c',
    );
    if (modEl != null && modEl.text.contains('版主')) {
      moderators = modEl.text
          .replaceAll('版主:', '')
          .replaceAll('版主：', '')
          .trim();
    } else {
      final mm = RegExp(r'版主[:：]\s*([^\r\n<|]+)').firstMatch(text);
      if (mm != null) moderators = mm.group(1)!.trim();
    }

    // 4. 版块导览与版规内容卡片（精确匹配 div#forum_rules_$fid / crule 容器，避开 img 标签）
    final rulesEl =
        doc.getElementById('forum_rules_$fid') ??
        doc.querySelector(
          'div#forum_rules_$fid, div.crule, div[id="forum_rules_$fid"], #forum_rules, #rules, div.ptn.xg2, div.bm_c div.xg2, div.bml_c .xg2, .comiis_fl_rules',
        );
    if (rulesEl != null) {
      final clone = rulesEl.clone(true);
      clone.querySelectorAll('script, style').forEach((e) => e.remove());
      for (final a in clone.querySelectorAll('a')) {
        final href = a.attributes['href'];
        if (href != null && href.isNotEmpty) {
          a.attributes['href'] = _absolute(href) ?? href;
        }
      }
      for (final img in clone.querySelectorAll('img')) {
        final src = img.attributes['src'] ?? img.attributes['data-src'];
        if (src != null && src.isNotEmpty) {
          img.attributes['src'] = _absolute(src) ?? src;
        }
      }
      rulesHtml = clone.innerHtml.trim();
    }

    // 5. 本版积分规则提取
    final creditRules = parseCreditRules(html);

    // 6. 是否已收藏/关注本版（Discuz 网页版状态类识别）
    final isFavorited = doc.querySelector(
          '#a_favorite.on, #a_favorite.cur, #a_favorite.fav_on, #comiis_favorite_a.on, a[href*="ac=favorite"][class*="on"], a[href*="ac=favorite"][class*="cur"], a[href*="ac=favorite"][class*="fav_on"], a[href*="op=delete"][href*="favorite"], a[href*="delfav"], a.fav_on, a.k_fav.on',
        ) !=
        null ||
        html.contains('您已收藏过本版') ||
        html.contains('取消收藏本版');

    return ForumHeaderInfo(
      fid: fid,
      name: name,
      bannerUrl: bannerUrl,
      todayPosts: todayPosts,
      threadsCount: threadsCount,
      rank: rank,
      favCount: favCount,
      moderators: moderators,
      rulesHtml: rulesHtml,
      creditRules: creditRules,
      isFavorited: isFavorited,
    );
  }

  /// 解析 Discuz 本版积分规则（forum.php?mod=misc&action=creditrule&fid=$fid 或版块页面内的积分规则表）
  static List<ForumCreditRule> parseCreditRules(String html) {
    final doc = html_parser.parse(html);
    final rules = <ForumCreditRule>[];

    final rows = doc.querySelectorAll(
      'table.dt tr, table.creditrule tr, div.creditrule tr, #creditrule tr',
    );
    for (final tr in rows) {
      final tds = tr.querySelectorAll('td');
      final th = tr.querySelector('th');
      final actionName =
          th?.text.trim() ?? (tds.isNotEmpty ? tds[0].text.trim() : '');
      if (actionName.isEmpty ||
          actionName == '动作名称' ||
          actionName == '行为' ||
          actionName == '操作') {
        continue;
      }

      if (tds.length >= 4) {
        rules.add(
          ForumCreditRule(
            action: actionName,
            cycle: tds.isNotEmpty ? tds[0].text.trim() : '每天',
            maxDaily: tds.length > 1 ? tds[1].text.trim() : '不限',
            exp: tds.length > 2 ? tds[2].text.trim() : '+0',
            iron: tds.length > 3 ? tds[3].text.trim() : '+0',
            tribute: tds.length > 4 ? tds[4].text.trim() : '0',
          ),
        );
      }
    }

    if (rules.isNotEmpty) return rules;

    // 苦力怕论坛标准默认版块积分规则
    return const [
      ForumCreditRule(
        action: '发表主题',
        cycle: '每天',
        maxDaily: '10次',
        exp: '+2',
        iron: '+1',
        tribute: '0',
      ),
      ForumCreditRule(
        action: '发表回复',
        cycle: '每天',
        maxDaily: '20次',
        exp: '+1',
        iron: '+0',
        tribute: '0',
      ),
      ForumCreditRule(
        action: '加入精华',
        cycle: '一次',
        maxDaily: '不限',
        exp: '+10',
        iron: '+5',
        tribute: '+1',
      ),
      ForumCreditRule(
        action: '采纳最佳',
        cycle: '一次',
        maxDaily: '不限',
        exp: '+3',
        iron: '+悬赏',
        tribute: '0',
      ),
      ForumCreditRule(
        action: '删除主题',
        cycle: '一次',
        maxDaily: '不限',
        exp: '-5',
        iron: '-3',
        tribute: '0',
      ),
      ForumCreditRule(
        action: '删除回复',
        cycle: '一次',
        maxDaily: '不限',
        exp: '-2',
        iron: '-1',
        tribute: '0',
      ),
    ];
  }

  // ---------------------------------------------------------------------
  // 帖子详情（楼层）
  // ---------------------------------------------------------------------
  static ({
    String title,
    List<PostFloor> floors,
    int totalPages,
    int firstAuthorCredits,
    String publishDate,
    String lastReplyDate,
    String forumName,
    int? fid,
    List<String> breadcrumbs,
    String? typeName,
    int? typeid,
    int likes,
    int favorites,
    int views,
    int replies,
    List<String> tags,
    String? stamp,
    String? stampUrl,
    String? coverUrl,
    bool isFavorited,
    bool isLiked,
    int? favid,
  })
  parseThreadDetail(String html) {
    final doc = html_parser.parse(html);
    final floors = <PostFloor>[];

    // 1. 版块名称 (forumName)、fid 与 面包屑 (breadcrumbs)：
    String forumName = '';
    int? fid;
    final breadcrumbs = <String>[];

    // a. 提取 PC 端专用面包屑容器（必须在 #pt 或 .comiis_path 内，严禁全局匹配 div.z a，避免误命中回帖按钮）
    final ptContainer = doc.querySelector('#pt, .comiis_path');
    if (ptContainer != null) {
      for (final a in ptContainer.querySelectorAll('.z a, a')) {
        final t = _cleanTitle(a.text);
        final href = a.attributes['href'] ?? '';
        if (t.isNotEmpty &&
            t != '首页' &&
            t != '论坛' &&
            t != '帖子' &&
            !href.contains('portal.php') &&
            !href.contains('mod=viewthread') &&
            !href.contains('thread-')) {
          if (!breadcrumbs.contains(t)) breadcrumbs.add(t);
          final m =
              RegExp(r'forum-(\d+)-\d+\.html').firstMatch(href) ??
              RegExp(r'fid=(\d+)').firstMatch(href);
          if (m != null) fid = int.tryParse(m.group(1)!);
        }
      }
      if (breadcrumbs.isNotEmpty) {
        forumName = breadcrumbs.last;
      }
    }

    // b. 移动端克米模板：直接从专用版块链接提取版块名与 fid
    if (forumName.isEmpty) {
      final bkSelectors = [
        'a.kmbkurl',
        '.comiis_view_header1 a[href*="forum-"]',
        '#comiis_head a.kmtit',
        '.comiis_head a.kmtit',
        '.comiis_bankuai p.bankuai_tit a',
        'a.post_tit em',
        'a[href*="mod=forumdisplay&fid="]',
      ];
      for (final sel in bkSelectors) {
        final el = doc.querySelector(sel);
        if (el != null) {
          final t = _cleanTitle(el.text);
          if (t.isNotEmpty &&
              !t.contains('返回') &&
              !t.contains('首页') &&
              !t.contains('赞') &&
              !t.contains('回复') &&
              !t.contains('道具') &&
              !t.contains('举报')) {
            forumName = t;
            if (!breadcrumbs.contains(t)) breadcrumbs.add(t);
            final href = el.attributes['href'] ?? '';
            final m =
                RegExp(r'forum-(\d+)-\d+\.html').firstMatch(href) ??
                RegExp(r'fid=(\d+)').firstMatch(href);
            if (m != null) fid = int.tryParse(m.group(1)!);
            break;
          }
        }
      }
    }

    // c. 兜底提取 fid
    if (fid == null) {
      final fidEl = doc.querySelector(
        '.comiis_view_header1 a[href*="forum-"], #comiis_head a.kmtit, .comiis_head a.kmtit, #pt a[href*="forum-"], #pt a[href*="fid="], input[name="srhfid"]',
      );
      if (fidEl != null) {
        final href =
            fidEl.attributes['href'] ?? fidEl.attributes['value'] ?? '';
        final m =
            RegExp(r'fid=(\d+)').firstMatch(href) ??
            RegExp(r'forum-(\d+)-\d+\.html').firstMatch(href);
        if (m != null) fid = int.tryParse(m.group(1)!);
      }
    }

    // 2. 主题分类 (typeName / typeid)：如 [闲聊]、[原创]、[汉化]
    String? typeName;
    int? typeid;
    final typeLink = doc.querySelector(
      '.km_tits a[href*="typeid"], a[href*="filter=typeid"], h1.ts a, .ts a, a[href*="typeid="]',
    );
    if (typeLink != null) {
      final t = typeLink.text.trim();
      if (t.isNotEmpty) typeName = t;
      final href = typeLink.attributes['href'] ?? '';
      final tm = RegExp(r'typeid=(\d+)').firstMatch(href);
      if (tm != null) typeid = int.tryParse(tm.group(1)!);
    }

    // 3. 标题 (title)：
    String title = '';
    // a. 优先从正文标题 DOM 节点提取
    final hSubject = doc.querySelector('#thread_subject');
    if (hSubject != null) {
      final clone = hSubject.clone(true);
      clone.querySelectorAll('em, span, a').forEach((e) => e.remove());
      title = _cleanTitle(clone.text);
      if (title.isEmpty) title = _cleanTitle(hSubject.text);
    }
    if (title.isEmpty) {
      final kmTits = doc.querySelector('.km_tits');
      if (kmTits != null) {
        final clone = kmTits.clone(true);
        clone.querySelectorAll('a, span, em').forEach((e) => e.remove());
        title = _cleanTitle(clone.text);
      }
    }
    if (title.isEmpty) {
      final h = doc.querySelector(
        '.comiis_viewtit h2, .comiis_viewtit h1, h1.ts, h1.ph, h1',
      );
      if (h != null) {
        final clone = h.clone(true);
        clone
            .querySelectorAll('a, span, em, .comiis_view_header1')
            .forEach((e) => e.remove());
        title = _cleanTitle(clone.text);
      }
    }

    // 4. 从 <title> 提取并校验（处理 Discuz「标题 - 版块 - 网站名」结构）
    final titleTag = doc.querySelector('title');
    if (titleTag != null) {
      var rawTitle = titleTag.text.trim();
      final siteSuffixes = [
        ' - Minecraft(我的世界)苦力怕论坛',
        ' - 苦力怕论坛',
        ' - Powered by Discuz!',
        ' - Discuz!',
        ' - klpbbs',
      ];
      for (final suf in siteSuffixes) {
        while (rawTitle.endsWith(suf)) {
          rawTitle = rawTitle.substring(0, rawTitle.length - suf.length).trim();
        }
      }

      if (forumName.isNotEmpty) {
        if (!breadcrumbs.contains(forumName)) breadcrumbs.add(forumName);
        // 若从 DOM 获得了准确版块名，且 <title> 结尾包含 " - 版块名"，则准确剥离
        if (title.isEmpty) {
          if (rawTitle.endsWith(' - $forumName')) {
            title = rawTitle
                .substring(0, rawTitle.length - (' - $forumName').length)
                .trim();
          } else {
            final parts = rawTitle.split(' - ');
            if (parts.length >= 2) {
              title = parts.sublist(0, parts.length - 1).join(' - ').trim();
            } else {
              title = parts.first.trim();
            }
          }
        }
      } else {
        // 未获得版块名时从 <title> 切分
        final parts = rawTitle.split(' - ');
        if (parts.length >= 2) {
          forumName = parts.last.trim();
          if (!breadcrumbs.contains(forumName)) breadcrumbs.add(forumName);
          if (title.isEmpty) {
            title = parts.sublist(0, parts.length - 1).join(' - ').trim();
          }
        } else if (title.isEmpty) {
          title = parts.first.trim();
        }
      }
    }

    // 楼层容器：优先 div.comiis_postli，其次 Discuz 严格 post_DIGITS 或 table[id^="pid"]
    var postElements = doc.querySelectorAll('div.comiis_postli');
    if (postElements.isEmpty) {
      postElements = doc
          .querySelectorAll('div[id^="post_"]')
          .where((el) => RegExp(r'^post_\d+$').hasMatch(el.id))
          .toList();
    }
    if (postElements.isEmpty) {
      postElements = doc
          .querySelectorAll('table[id^="pid"]')
          .where((el) => RegExp(r'^pid\d+$').hasMatch(el.id))
          .toList();
    }
    if (postElements.isEmpty) {
      postElements = doc.querySelectorAll('div[id^="pid"], .plc, .postitem');
    }
    for (final post in postElements) {
      if (post.id == 'post_new' ||
          (post.children.isEmpty && post.text.trim().isEmpty)) {
        continue;
      }
      // 内容区
      final message =
          post.querySelector(
            'div.message, td[id^="postmessage_"], .t_f, .postmessage, .message',
          ) ??
          post;

      // pid（楼层 id="pid{pid}"）
      final idAttr = post.attributes['id'] ?? '';
      final pid = int.tryParse(
        idAttr.replaceFirst('pid', '').replaceFirst('post_', ''),
      );

      // 作者 + uid
      html_dom.Element? authorEl = post.querySelector(
        'a.top_user, .kmuser a, .authi a.xw1, a.author, a[href*="space-username"]',
      );
      if (authorEl == null || authorEl.text.trim().isEmpty) {
        authorEl = post.querySelector(
          '.authi a[href*="space-uid"], a[href*="space-uid"]:not(.postli_top_tximg):not(.kmimg), a[href*="mod=space"]:not(.postli_top_tximg):not(.kmimg)',
        );
      }
      var author = authorEl?.text.trim() ?? '';
      if (author.isEmpty) {
        final authorM = RegExp(
          r'(?:space-uid-|uid=)(\d+)',
        ).firstMatch(post.innerHtml);
        if (authorM != null) author = '用户${authorM.group(1)}';
      }
      if (author.isEmpty) author = '匿名';
      final uid = _uidFromHref(authorEl?.attributes['href'] ?? '');
      // 头像挂件（sunju_facemall）：top_tximg img 的 ##SJ## 后缀
      final faceImg = post.querySelector(
        'img.top_tximg, a.postli_top_tximg img, .avatar img',
      );
      final faceUrl = _faceUrlFromAvatar(faceImg?.attributes['src']) ?? '';

      // 时间（span.kmtime 内为完整时间文本）
      String timeText = '';
      final km = post.querySelector(
        'span.kmtime, .authi em span, .authi em, .pti .authi em, .author_time',
      );
      if (km != null) {
        // 时间文本去掉 IP 归属地（ipText 单独解析，避免重复显示）
        timeText = km.text.replaceAll(RegExp(r'\s*IP[:：]\s*\S*'), '').trim();
      } else {
        for (final sp in post.querySelectorAll(
          '.comiis_postli_time span, .authi em, .pti em',
        )) {
          final t = sp.text.trim();
          if (t.isNotEmpty) {
            timeText = t;
            break;
          }
        }
      }

      // 作者等级（top_lev 徽章：Lv.x 会员等级 / 管理员 / 版主）
      String levelText = '';
      int? levelGid;
      String levelColor = '';
      final lev = post.querySelector('.top_lev, .comiis_postli_top .top_lev');
      if (lev != null) {
        levelText = lev.text.trim();
        final levHref = lev.attributes['href'] ?? '';
        final gm = RegExp(r'gid=(\d+)').firstMatch(levHref);
        if (gm != null) levelGid = int.tryParse(gm.group(1)!);
        // 管理员/版主等特殊用户组内联红/品红背景（style="background:#XXX !important"）
        final styleAttr = lev.attributes['style'] ?? '';
        final cm = RegExp(
          r'background:\s*(#[0-9a-fA-F]{3,8})',
        ).firstMatch(styleAttr);
        if (cm != null) levelColor = cm.group(1)!;
      }

      // 楼主徽章：top_lev 中文本为「楼主」的项
      var isThreadAuthor = false;
      for (final lv in post.querySelectorAll('.top_lev')) {
        if (lv.text.trim() == '楼主') {
          isThreadAuthor = true;
          break;
        }
      }

      // 认证徽章（comiis_verify：Discuz verify 实名认证，img + title + vid）
      final verifies = <({String img, String title, String vid})>[];
      final verifyBox = post.querySelector('.comiis_verify');
      if (verifyBox != null) {
        for (final a in verifyBox.querySelectorAll('a')) {
          final img = a.querySelector('img');
          final src = _absolute(img?.attributes['src']) ?? '';
          final title =
              img?.attributes['alt'] ??
              img?.attributes['title'] ??
              a.text.trim();
          final href = a.attributes['href'] ?? '';
          final vm = RegExp(r'vid=(\d+)').firstMatch(href);
          final vid = vm == null ? '' : vm.group(1)!;
          if (src.isNotEmpty || title.isNotEmpty) {
            verifies.add((img: src, title: title, vid: vid));
          }
          if (verifies.length >= 4) break;
        }
      }

      // 作者勋章（a.top_user 内 img[src*=medal] + comiis_medaltip/.medal 容器）
      final medals = <String>[];
      final userA = post.querySelector('a.top_user');
      if (userA != null) {
        for (final im in userA.querySelectorAll('img[src*="medal"]')) {
          final src = _medalUrl(im.attributes['src']);
          if (src.isNotEmpty && !medals.contains(src)) medals.add(src);
        }
      }
      final medalBox = post.querySelector(
        '.comiis_medaltip, .medal, .authormedals',
      );
      if (medalBox != null) {
        for (final im in medalBox.querySelectorAll('img')) {
          final src = _absolute(im.attributes['src']);
          if (src != null && src.isNotEmpty && !medals.contains(src)) {
            medals.add(src);
          }
        }
      }

      // 嵌入内容（iframe/video/audio src）
      final embeds = <String>[];
      for (final em in message.querySelectorAll(
        'iframe[src], video[src], audio[src], embed[src]',
      )) {
        final src = _absolute(em.attributes['src']);
        if (src != null && !embeds.contains(src)) embeds.add(src);
        if (embeds.length >= 4) break;
      }

      // 打赏记录（ratelog_{pid} 的 comiis_view_lcrate：头像/uid/用户/金额/理由）
      String rewardCount = '';
      List<
        ({String user, int? uid, String avatar, String amount, String reason})
      >
      rewards = [];
      for (final rl in post.querySelectorAll('div[id^="ratelog_"]')) {
        for (final li in rl.querySelectorAll('li[id^="rate_"]')) {
          final userA =
              li.querySelector('a.f_c') ?? li.querySelector('a.lcrate_img');
          final user = userA?.text.trim() ?? '';
          final uid = _uidFromHref(userA?.attributes['href'] ?? '');
          final avatar =
              _absolute(
                li.querySelector('.lcrate_img img')?.attributes['src'],
              ) ??
              '';
          final rawAmount = li.querySelector('span.f_a')?.text.trim() ?? '';
          var amount = _cleanRewardAmount(
            rawAmount.isNotEmpty ? rawAmount : li.text,
          );
          final reason = li.querySelector('p')?.text.trim() ?? '';
          if (user.isNotEmpty || amount.isNotEmpty) {
            rewards.add((
              user: user,
              uid: uid,
              avatar: avatar,
              amount: amount,
              reason: reason,
            ));
            if (rewards.length >= 8) break;
          }
        }
        break;
      }
      final rc = RegExp(r'(\d+)\s*人打赏').firstMatch(post.text);
      if (rc != null) rewardCount = rc.group(1)!;

      // IP 归属地（楼层时间行 "IP:xx省"）
      String ipText = '';
      final km2 = post.querySelector('span.kmtime');
      if (km2 != null) {
        final kmText = km2.text;
        final ipm = RegExp(r'IP[:：]\s*([^|]{1,20})').firstMatch(kmText);
        if (ipm != null) ipText = ipm.group(1)!.trim();
      }

      // 签名档（严格局限在当前 post 节点内提取，严禁向上遍历父节点，杜绝将楼主签名错误赋给其他楼层）
      String signature = '';
      final signEl = post.querySelector(
        '.sign, .signature, div.comiis_sign, div.comiis_qm, div.qm, div.kmqm, .comiis_authi .qm, .signtext, .comiis_mh_sign, div[id^="signature_"], div.signature_content, .user_signature, .signaturetext, div[style*="sigline"], div[style*="sigline.gif"]',
      );
      if (signEl != null) {
        signature = (signEl.innerHtml.isNotEmpty ? signEl.innerHtml : signEl.text).trim();
      }
      if (signature.isNotEmpty && uid != null && uid > 0) {
        authorSigCache[uid] = signature;
      }

      // 提取分类信息（模组/皮肤/附加包/软件资源等发布表单卡片）
      final resourceInfo = _parseResourceInfo(
        message,
        typeName: typeName ?? forumName,
      );

      // 提取最后编辑时间（.pstatus / i.pstatus / 正文中 "本帖最后由 ... 于 ... 编辑"）
      String? lastEdited;
      final pstatusEl = message.querySelector(
        '.pstatus, i.pstatus, span.pstatus, blockquote.pstatus',
      );
      if (pstatusEl != null) {
        lastEdited = pstatusEl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      }
      if (lastEdited == null || lastEdited.isEmpty) {
        final editMatch = RegExp(
          r'本帖最后由\s+([^\s]+)\s+于\s+([^\s]+(?:\s+[^\s]+)?)\s*编辑',
        ).firstMatch(message.text);
        if (editMatch != null) {
          lastEdited = editMatch.group(0)?.trim();
        }
      }

      // 提取核心正文容器，剔除 Discuz 插件与打赏点赞评分散片
      final cleanMessage = message.clone(true);
      for (final el in cleanMessage.querySelectorAll(
        '.comiis_rate, div[id^="ratelog_"], .comiis_dzhan_img, .comiis_bankuai, .replyfloor_box, .comiis_zhanv2, div[id^="mgc_post_"], .comiis_tags, .comiis_pltit, .pstatus, .comiis_flxx_stamp, .comiis_actinfo, .comiis_view_flxx, table.cptbl, table.typeoption, div.typeoption, div#typeoption, style, script, div[style*="sigline.gif"], .fwinmask, div[id^="fwin_"], form#favoriteform, form[id*="favorite"], form[action*="favorite"], div#messagetext, div.comiis_tip, div.tip',
      )) {
        el.remove();
      }

      final coreBody =
          cleanMessage.querySelector('.comiis_messages') ?? cleanMessage;
      final contentHtml = coreBody.outerHtml;
      final images = <String>[];
      for (final img in coreBody.querySelectorAll('img')) {
        var rawSrc = img.attributes['comiis_loadimages'] ?? '';
        if (rawSrc.isEmpty ||
            rawSrc.contains('none.png') ||
            rawSrc.contains('spacer.gif')) {
          rawSrc = img.attributes['file'] ?? '';
        }
        if (rawSrc.isEmpty ||
            rawSrc.contains('none.png') ||
            rawSrc.contains('spacer.gif')) {
          rawSrc = img.attributes['zoomfile'] ?? '';
        }
        if (rawSrc.isEmpty ||
            rawSrc.contains('none.png') ||
            rawSrc.contains('spacer.gif')) {
          rawSrc = img.attributes['data-src'] ?? '';
        }
        if (rawSrc.isEmpty ||
            rawSrc.contains('none.png') ||
            rawSrc.contains('spacer.gif')) {
          rawSrc = img.attributes['src'] ?? '';
        }
        if (rawSrc.isNotEmpty &&
            !rawSrc.contains('none.png') &&
            !rawSrc.contains('spacer.gif')) {
          final src = _absolute(rawSrc);
          if (src != null && !images.contains(src)) images.add(src);
        }
      }

      final replyFloor = _parseReplyFloor(post);

      // 提取楼层标识（如「楼主」、「沙发」、「板凳」、「地板」、「5#」、「11#」、「来自 20#」等）
      var floorNumber = replyFloor.floorNumber;
      if (floorNumber.isEmpty) {
        final floorEl = post.querySelector(
          '.authi li.mtit span.y, .authi .mtit span.y, .authi span.y, a.node em, a[id^="postnum"] em, .pi strong a em, .postinfo strong a, .postinfo strong, .floor, .comiis_postli_top em.y',
        );
        if (floorEl != null) {
          final t = floorEl.text.trim();
          if (t.isNotEmpty &&
              !t.contains('举报') &&
              !t.contains('道具') &&
              !t.contains('评分') &&
              !t.contains('回复') &&
              !t.contains('赞') &&
              !t.contains(':') &&
              !t.contains('：')) {
            final numM = RegExp(r'(?:来自\s*)?(\d+)\s*#?').firstMatch(t);
            if (numM != null) {
              floorNumber = '${numM.group(1)}#';
            } else if (t == '楼主' || t == '沙发' || t == '板凳' || t == '地板') {
              floorNumber = t;
              if (t == '楼主') isThreadAuthor = true;
            }
          }
        }
      }

      final magicItems = _parseMagicItems(post);
      final blocks = parseStructuredBlocks(coreBody);

      // 全面扫描楼层内所有独立附件容器（防止附件渲染在 coreBody 外部或由插件输出）
      final attachCandidates = post.querySelectorAll(
        '.comiis_attach, .pattl, .attach_nopermission, dl.tattl, div.attachlist, div[id^="attach_"], div.box_attach, a[href*="attachment"], a[href*="aid="], a[href*="klpbbs_download"], a[href*="download.php"]',
      );
      final existingAttachUrls = blocks
          .whereType<AttachmentBlock>()
          .map((b) => b.url)
          .toSet();
      for (final el in attachCandidates) {
        final parsed = parseStructuredBlocks(el);
        for (final b in parsed) {
          if (b is AttachmentBlock && existingAttachUrls.add(b.url)) {
            blocks.add(b);
          }
        }
      }

      if (resourceInfo != null && floors.isEmpty) {
        blocks.insert(0, resourceInfo);
      }

      final floorLikes = _parseFloorLikes(post);
      final floorIsLiked =
          post.querySelector(
                '.reply_liked, .supported, .comiis_yizan, a.voted, a.on, a.cur, .km_recommend_on, a[class*="voted"], a[class*="liked"], a[id^="recommend"][class*="on"]',
              ) !=
              null ||
          post.text.contains('已赞') ||
          post.text.contains('已支持') ||
          post.text.contains('已顶') ||
          post.text.contains('已评价') ||
          html.contains('您已给该楼层点过赞了') ||
          html.contains('您已评价过本主题');

      // 处罚与警告状态解析（受到警告 / 屏蔽 / 禁言 / 审核中 / 锁定）
      final warnEl = post.querySelector(
        'a[href*="viewwarning"], a[href*="mod=misc&action=viewwarning"], img[src*="warning.gif"], .pwarning, .comiis_pwarning, .warn, [title*="受到警告"]',
      );
      final isWarned = warnEl != null ||
          post.innerHtml.contains('viewwarning') ||
          post.innerHtml.contains('受到警告') ||
          post.innerHtml.contains('warning.gif');
      final warningUrl = _absolute(warnEl?.attributes['href']);
      final warningText = warnEl?.attributes['title'] ??
          warnEl?.attributes['alt'] ??
          (isWarned ? '受到警告' : '');

      final postAllText = post.text;
      final bool isBanned = postAllText.contains('作者被禁止或删除') ||
          levelText.contains('禁止发言') ||
          levelText.contains('禁止访问');
      final bool isUnderReview = postAllText.contains('正在审核中') ||
          postAllText.contains('审核中');
      final bool isShielded = isBanned ||
          postAllText.contains('内容自动屏蔽') ||
          postAllText.contains('该帖被管理员或版主屏蔽') ||
          post.querySelector('.locked, .shield, .comiis_shield') != null;
      var shieldText = '';
      if (isBanned) {
        shieldText = '提示: 作者被禁止或删除 内容自动屏蔽';
      } else if (postAllText.contains('该帖被管理员或版主屏蔽')) {
        shieldText = '提示: 该帖被管理员或版主屏蔽';
      } else if (isUnderReview) {
        shieldText = '提示: 该帖正在审核中，仅管理员可见';
      } else if (isShielded) {
        shieldText = '提示: 内容自动屏蔽';
      }

      final bool isLocked = postAllText.contains('本帖已被锁定') ||
          postAllText.contains('已被锁定');

      // 发帖者当前在线状态检测（Discuz 在线规则：明确在线标记 或 20分钟内近期发言活动）
      final postHtml = post.outerHtml;
      final bool hasOnlineMark = (post.querySelector(
            'img:not(.authicn)[src*="online.png"], img:not(.authicn)[src*="online.gif"], img[src*="ol.gif"], img[title*="当前在线"], img[title="在线"], .comiis_o, em.online, span.online',
          ) !=
          null ||
          postHtml.contains('title="当前在线"') ||
          postHtml.contains('class="comiis_o"') ||
          postHtml.contains('>当前在线<'));

      final bool hasOfflineMark = (post.querySelector(
            'img[src*="offline.png"], img[src*="offline.gif"], img[title*="当前离线"], img[title="离线"], .comiis_f, em.offline, span.offline',
          ) !=
          null ||
          postHtml.contains('title="当前离线"') ||
          postHtml.contains('class="comiis_f"') ||
          postHtml.contains('>当前离线<'));

      final bool isFloorOnline = (hasOnlineMark && !hasOfflineMark) ||
          (!hasOfflineMark && _isRecentActivity(timeText));

      floors.add(
        PostFloor(
          pid: pid,
          uid: uid,
          author: author,
          timeText: timeText,
          contentHtml: contentHtml,
          blocks: blocks,
          images: images,
          comments: _parseFloorComments(message),
          replyFloors: replyFloor.comments,
          replyFloorCount: replyFloor.count,
          floorNumber: floorNumber,
          faceUrl: faceUrl,
          ipText: ipText,
          levelText: levelText,
          levelGid: levelGid,
          levelColor: levelColor,
          verifies: verifies,
          magicItems: magicItems,
          isThreadAuthor: isThreadAuthor,
          rewardCount: rewardCount,
          rewards: rewards,
          medals: medals,
          embeds: embeds,
          signature: signature,
          isBestAnswer:
              post.querySelector(
                    '.best_answer, .ans_best, .ans_solved, em.solved, .comiis_best',
                  ) !=
                  null ||
              (post.attributes['class']?.contains('best') ?? false),
          bountyPrice: floors.isEmpty ? _extractBountyPrice(doc, html) : null,
          isBountySolved:
              html.contains('已解决') ||
              html.contains('最佳答案') ||
              html.contains('ans_best'),
          likes: floorLikes,
          isLiked: floorIsLiked,
          lastEdited: lastEdited,
          isWarned: isWarned,
          warningText: warningText,
          warningUrl: warningUrl,
          isShielded: isShielded,
          shieldText: shieldText,
          isBanned: isBanned,
          isUnderReview: isUnderReview,
          isLocked: isLocked,
          isOnline: isFloorOnline,
        ),
      );
    }

    // 若未匹配到独立楼层容器，执行全局文档级首楼保底提取
    if (floors.isEmpty) {
      final authorEl = doc.querySelector(
        'a.top_user, .kmuser a, .authi a.xw1, .authi a[href*="space-uid"], a[href*="mod=space"], a.author, a[href*="space-username"]',
      );
      var author = authorEl?.text.trim() ?? '';
      if (author.isEmpty) {
        final authorM = RegExp(r'space-uid-(\d+)').firstMatch(html);
        if (authorM != null) author = '用户${authorM.group(1)}';
      }
      final uid =
          _uidFromHref(authorEl?.attributes['href'] ?? '') ??
          int.tryParse(
            RegExp(r'space-uid-(\d+)').firstMatch(html)?.group(1) ?? '',
          );
      final timeEl = doc.querySelector(
        'span.kmtime, .comiis_postli_time span, .authi em span, .authi em, .pti .authi em',
      );
      var timeText =
          timeEl?.text.replaceAll(RegExp(r'\s*IP[:：]\s*\S*'), '').trim() ?? '';
      if (timeText.isEmpty) {
        final tm = RegExp(
          r'(\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{1,2}(?::\d{1,2})?)?)|\d+\s*(?:分钟|小时|天)前',
        ).firstMatch(html);
        if (tm != null) timeText = tm.group(0)!.trim();
      }
      final images = <String>[];
      for (final img in doc.querySelectorAll(
        '.message img, .t_f img, .comiis_messages img, img[comiis_loadimages], img[file]',
      )) {
        final src = _image(
          img.attributes['comiis_loadimages'] ??
              img.attributes['file'] ??
              img.attributes['zoomfile'] ??
              img.attributes['src'],
        );
        if (src != null &&
            !src.contains('none.png') &&
            !src.contains('spacer.gif') &&
            !images.contains(src)) {
          images.add(src);
        }
      }
      if (author.isNotEmpty || timeText.isNotEmpty || images.isNotEmpty) {
        floors.add(
          PostFloor(
            pid: 0,
            uid: uid,
            author: author.isNotEmpty ? author : '楼主',
            timeText: timeText,
            contentHtml: '',
            blocks: const [],
            images: images,
            comments: const [],
            replyFloors: const [],
            replyFloorCount: 0,
            floorNumber: '1#',
            faceUrl: '',
            ipText: '',
            levelText: '',
            levelGid: null,
            levelColor: '',
            verifies: const [],
            magicItems: const [],
            isThreadAuthor: true,
            rewardCount: '',
            rewards: const [],
            medals: const [],
            embeds: const [],
            signature: '',
            isBestAnswer: false,
          ),
        );
      }
    }

    // 总页数：取 viewthread 分页链接中最大的 page（thread-{tid}-{page}-1.html），
    // 并兜底「共 N 页」文本；旧正则 page=(\d+) 会误命中表单/custompage 的当前页
    var totalPages = 1;
    for (final m in RegExp(r'thread-\d+-(\d+)-1\.html').allMatches(html)) {
      final p = int.tryParse(m.group(1) ?? '');
      if (p != null && p > totalPages) totalPages = p;
    }
    final spanM = RegExp(r'共\s*(\d+)\s*页').firstMatch(html);
    if (spanM != null) {
      final p = int.tryParse(spanM.group(1) ?? '');
      if (p != null && p > totalPages) totalPages = p;
    }
    // 首楼作者积分（"用户组 积分: N"）
    var firstAuthorCredits = -1;
    final creditM = RegExp(r'积分:\s*(\d+)').firstMatch(html);
    if (creditM != null) {
      firstAuthorCredits = int.tryParse(creditM.group(1) ?? '') ?? -1;
    }
    // 点赞数（comiis_recommend_num / recommendv_add / recommend_add / postreview / support）
    var likes = 0;
    final likeSelectors = [
      '#recommendv_add',
      'span#recommendv_add',
      '#recommend_add',
      'span#recommend_add',
      'a.recommend_add i',
      'a.recommend_add span',
      '.comiis_recommend_num',
      '.comiis_recommend_nums',
      'span[id^="review_support_"]',
      '.support_num',
      'span[id^="recommendv_"]',
      'span[id^="recommend_"]',
      'a.voted span',
      'a.comiis_recommend span',
    ];
    for (final sel in likeSelectors) {
      final el = doc.querySelector(sel);
      if (el != null) {
        final count =
            int.tryParse(RegExp(r'\d+').firstMatch(el.text)?.group(0) ?? '') ??
            0;
        if (count > likes) likes = count;
      }
    }
    if (likes <= 0) {
      final likeM = RegExp(
        r'id="recommendv_add"[^>]*>(\d+)|id="recommend_add"[^>]*>(\d+)|id="review_support_\d+"[^>]*>(\d+)|(\d+)\s*人点赞|点赞[:：\s]*(\d+)|\+(\d+)',
      ).firstMatch(html);
      if (likeM != null) {
        likes =
            int.tryParse(
              likeM.group(1) ??
                  likeM.group(2) ??
                  likeM.group(3) ??
                  likeM.group(4) ??
                  likeM.group(5) ??
                  likeM.group(6) ??
                  '',
            ) ??
            0;
      }
    }
    if (floors.isNotEmpty && floors.first.likes > likes) {
      likes = floors.first.likes;
    }

    // 收藏数（排除版块关注数 #comiis_forum_favtimes）
    var favorites = 0;
    final favNumEl = doc.querySelector(
      '#favoritenumber, #comiis_favorite_a, .thread_favtimes',
    );
    if (favNumEl != null) {
      favorites =
          int.tryParse(
            RegExp(r'\d+').firstMatch(favNumEl.text)?.group(0) ?? '',
          ) ??
          0;
    } else {
      final favM = RegExp(
        r'本帖被收藏[:：\s]*<em>?(\d+)<em>?|(\d+)\s*次收藏',
      ).firstMatch(html);
      if (favM != null) {
        favorites = int.tryParse(favM.group(1) ?? favM.group(2) ?? '') ?? 0;
      }
    }

    // 浏览量与回复量
    var views = 0, replies = 0;
    final viewEl = doc.querySelector('.comiis_pviews, .views, .view_count');
    if (viewEl != null) {
      views =
          int.tryParse(
            RegExp(r'\d+').firstMatch(viewEl.text)?.group(0) ?? '',
          ) ??
          0;
    }
    if (views <= 0) {
      final viewM = RegExp(
        r'查看[:：\s]*<em>?(\d+)<em>?|(\d+)\s*次阅读|(\d+)\s*阅读|(\d+)\s*浏览',
      ).firstMatch(html);
      if (viewM != null) {
        views =
            int.tryParse(
              viewM.group(1) ??
                  viewM.group(2) ??
                  viewM.group(3) ??
                  viewM.group(4) ??
                  '',
            ) ??
            0;
      }
    }
    final replyEl = doc.querySelector(
      '.comiis_preplies, .replies, .reply_count',
    );
    if (replyEl != null) {
      replies =
          int.tryParse(
            RegExp(r'\d+').firstMatch(replyEl.text)?.group(0) ?? '',
          ) ??
          0;
    }
    if (replies <= 0) {
      final repM = RegExp(
        r'回复[:：\s]*<em>?(\d+)<em>?|(\d+)\s*个回复|(\d+)\s*条回复',
      ).firstMatch(html);
      if (repM != null) {
        replies =
            int.tryParse(
              repM.group(1) ?? repM.group(2) ?? repM.group(3) ?? '',
            ) ??
            0;
      }
    }
    if (replies <= 0 && floors.length > 1) {
      replies = floors.length - 1;
    }

    // 主题标签 tags
    final tags = <String>[];
    for (final tagA in doc.querySelectorAll(
      '.comiis_tags a, .ptg a, .threadtag a, a[href*="mod=tag"]',
    )) {
      final t = tagA.text
          .replaceAll(RegExp(r'[\uE000-\uF8FF\u2000-\u206F]'), '')
          .replaceAll(RegExp(r'[#\s,;，；]'), '')
          .trim();
      if (t.isNotEmpty &&
          !tags.contains(t) &&
          t != '标签' &&
          t != 'TAG' &&
          t.length <= 30) {
        tags.add(t);
      }
    }

    // 主题图章（美图/精华/荐/优秀/原创/热帖等）
    String? stamp;
    String? stampUrl;
    final stampEl = doc.querySelector(
      '#threadstamp img, .threadstamp img, .comiis_flxx_stamp img, img[src*="stamp"], .stamp img, .comiis_stamp, span.stamp, i.stamp',
    );
    if (stampEl != null) {
      final alt =
          stampEl.attributes['alt'] ??
          stampEl.attributes['title'] ??
          stampEl.text.trim();
      final src = stampEl.attributes['src'] ?? '';
      if (alt.isNotEmpty) {
        stamp = alt.trim();
      } else if (src.isNotEmpty) {
        if (src.contains('003')) {
          stamp = '美图';
        } else if (src.contains('001')) {
          stamp = '精华';
        } else if (src.contains('004')) {
          stamp = '优秀';
        } else if (src.contains('005')) {
          stamp = '原创';
        } else if (src.contains('006')) {
          stamp = '推荐';
        } else if (src.contains('002')) {
          stamp = '热帖';
        }
      }
      stampUrl = _absolute(src);
    }
    if (stamp == null || stamp.isEmpty) {
      if (tags.contains('美图') ||
          title.contains('美图') ||
          html.contains('alt="美图"') ||
          html.contains('title="美图"') ||
          html.contains('003.gif') ||
          html.contains('003.small.gif')) {
        stamp = '美图';
      }
    }

    // 点赞用户头像列表 (comiis_recommend_list_a / comiis_dzhan_img)
    final likedUsers = <({int? uid, String avatarUrl, String username})>[];
    for (final li in doc.querySelectorAll(
      'ul.comiis_recommend_list_a li, .comiis_dzhan_img li, .comiis_recommend_list li',
    )) {
      final img = li.querySelector('img');
      final a = li.querySelector('a');
      if (img != null) {
        final src = img.attributes['src'] ?? '';
        final href = a?.attributes['href'] ?? '';
        final uid = _uidFromHref(href) ?? _uidFromHref(src);
        final username = a?.attributes['title'] ?? a?.text.trim() ?? '';
        final avatar = _avatarUrl(src) ?? (uid != null ? AppConfig.avatarUrl(uid) : '');
        if (avatar.isNotEmpty) {
          likedUsers.add((uid: uid, avatarUrl: avatar, username: username));
        }
      }
    }
    if (floors.isNotEmpty && likedUsers.isNotEmpty) {
      floors[0] = floors[0].copyWith(
        likedUsers: likedUsers,
        likes: likes > floors[0].likes ? likes : floors[0].likes,
      );
    }

    final coverUrl = floors.isNotEmpty && floors.first.images.isNotEmpty
        ? floors.first.images.first
        : null;

    // 收藏与点赞状态（根据 Discuz 与 Comiis 真实 DOM/文本类识别）
    var isFavorited = false;
    final favElements = doc.querySelectorAll(
      '#k_favorite, #a_favorite, #comiis_favorite_a, a[href*="ac=favorite"], a[href*="delfav"], .thread_fav, .k_fav, a.favorite, a[id^="favorite_"]',
    );
    for (final el in favElements) {
      final href = el.attributes['href'] ?? '';
      final title = el.attributes['title'] ?? '';
      final text = el.text.trim();
      final icon = el.querySelector('i');

      final isFavEl = el.classes.contains('on') ||
          el.classes.contains('cur') ||
          el.classes.contains('fav_on') ||
          el.classes.contains('f_a') ||
          el.classes.contains('active') ||
          (icon != null && (icon.classes.contains('f_a') || icon.classes.contains('on') || icon.classes.contains('cur') || icon.classes.contains('active'))) ||
          href.contains('op=delete') ||
          href.contains('delfav') ||
          text.contains('已收藏') ||
          text.contains('取消收藏') ||
          title.contains('已收藏') ||
          title.contains('取消收藏');

      if (isFavEl) {
        isFavorited = true;
        break;
      }
    }

    if (!isFavorited) {
      isFavorited = doc.querySelector(
            '#k_favorite.on, #k_favorite.cur, #k_favorite.fav_on, #comiis_favorite_a.on, a[href*="ac=favorite"][class*="on"], a[href*="ac=favorite"][class*="cur"], a[href*="ac=favorite"][class*="fav_on"], a[href*="op=delete"][href*="favorite"], a[href*="delfav"], a.fav_on, a.k_fav.on',
          ) !=
          null ||
          html.contains('您已收藏过本主题');
    }

    final isLiked = (floors.isNotEmpty && floors.first.isLiked) ||
        doc.querySelector(
          '#recommendv_add.on, #recommend_add.on, .reply_liked, .supported, .comiis_yizan, a.voted, a.on, a.cur, .km_recommend_on, a[class*="voted"], a[class*="liked"], a[id^="recommend"][class*="on"]',
        ) !=
        null ||
        html.contains('您已给该楼层点过赞了') ||
        html.contains('您已评价过本主题') ||
        html.contains('您已赞过') ||
        html.contains('您已支持过');

    int? favid;
    for (final el in favElements) {
      final href = el.attributes['href'] ?? '';
      final m = RegExp(r'favid=(\d+)').firstMatch(href);
      if (m != null) {
        favid = int.tryParse(m.group(1)!);
        break;
      }
    }

    final tidM = RegExp(r'tid=(\d+)|thread-(\d+)-\d+').firstMatch(html);
    if (tidM != null) {
      final tid = int.tryParse(tidM.group(1) ?? tidM.group(2) ?? '');
      if (tid != null && tid > 0) {
        registerThread(tid, fid: fid, forumName: forumName);
      }
    }

    // 发布日期（首楼时间）与最近回复日期（末楼时间）
    final publishDate = floors.isNotEmpty ? floors.first.timeText : '';
    final lastReplyDate = floors.isNotEmpty ? floors.last.timeText : '';
    return (
      title: title,
      floors: floors,
      totalPages: totalPages,
      firstAuthorCredits: firstAuthorCredits,
      publishDate: publishDate,
      lastReplyDate: lastReplyDate,
      forumName: forumName,
      fid: fid,
      breadcrumbs: breadcrumbs,
      typeName: typeName,
      typeid: typeid,
      likes: likes,
      favorites: favorites,
      views: views,
      replies: replies,
      tags: tags,
      stamp: stamp,
      stampUrl: stampUrl,
      coverUrl: coverUrl,
      isFavorited: isFavorited,
      isLiked: isLiked,
      favid: favid,
    );
  }

  /// 从用户收藏页面 HTML 中提取指定 ID（tid 或 fid）的真实 favid
  static int? extractFavidFromHtml(String html, int id, {String type = 'thread'}) {
    final doc = html_parser.parse(html);
    final pattern1 = type == 'forum'
        ? (String href) => href.contains('fid=$id') || href.contains('forum-$id-') || href.contains('id=$id')
        : (String href) => href.contains('tid=$id') || href.contains('thread-$id-') || href.contains('id=$id');
    final pattern2 = type == 'forum'
        ? (String outer) => outer.contains('fid=$id') || outer.contains('forum-$id-') || outer.contains('id=$id')
        : (String outer) => outer.contains('tid=$id') || outer.contains('thread-$id-') || outer.contains('id=$id');

    // 1. 直接检索 delete 链接中的 favid
    for (final a in doc.querySelectorAll('a[href*="ac=favorite"][href*="op=delete"]')) {
      final href = a.attributes['href'] ?? '';
      if (pattern1(href) || (a.parent != null && pattern2(a.parent!.outerHtml))) {
        final m = RegExp(r'favid=(\d+)').firstMatch(href);
        if (m != null) {
          final fId = int.tryParse(m.group(1)!);
          if (fId != null) return fId;
        }
      }
    }
    // 2. 在包含当前 id 的容器节点（tr, li, div）中检索
    for (final container in doc.querySelectorAll('tr, li, div[id^="fav_"]')) {
      final outer = container.outerHtml;
      if (pattern2(outer)) {
        final idAttr = container.attributes['id'] ?? '';
        final mId = RegExp(r'fav_(\d+)').firstMatch(idAttr);
        if (mId != null) {
          final fId = int.tryParse(mId.group(1)!);
          if (fId != null) return fId;
        }
        for (final inp in container.querySelectorAll('input[name*="favorite"]')) {
          final val = inp.attributes['value'] ?? '';
          final fId = int.tryParse(val);
          if (fId != null && fId > 0) return fId;
        }
        for (final a in container.querySelectorAll('a[href*="favid="]')) {
          final href = a.attributes['href'] ?? '';
          final m = RegExp(r'favid=(\d+)').firstMatch(href);
          if (m != null) {
            final fId = int.tryParse(m.group(1)!);
            if (fId != null) return fId;
          }
        }
      }
    }
    // 3. 全局正则保底
    final reg = type == 'forum'
        ? RegExp('id=["\']fav_(\\d+)["\'].*?(?:forum-$id-|fid=$id)', dotAll: true).firstMatch(html)
        : RegExp('id=["\']fav_(\\d+)["\'].*?(?:thread-$id-|tid=$id)', dotAll: true).firstMatch(html);
    if (reg != null) {
      return int.tryParse(reg.group(1) ?? '');
    }
    return null;
  }

  static String? _extractBountyPrice(html_dom.Document doc, String html) {
    final rwdEl = doc.querySelector(
      '.rusl, .rwd, div.comiis_rwds, span.reward, table.rwd, div.rwd_c',
    );
    if (rwdEl != null) {
      final m = RegExp(
        r'(\d+)\s*(?:个)?(?:铁粒|金粒|金币|经验|贡献|积分)',
      ).firstMatch(rwdEl.text);
      if (m != null) return m.group(0);
    }
    final m2 = RegExp(
      r'悬赏[:：\s]*<em>?(\d+\s*(?:个)?(?:铁粒|金粒|金币|经验|贡献|积分))',
    ).firstMatch(html);
    if (m2 != null) return m2.group(1);
    final m3 = RegExp(
      r'\[悬赏\s*(\d+\s*(?:个)?(?:铁粒|金粒|金币|经验|贡献|积分))\]',
    ).firstMatch(html);
    if (m3 != null) return m3.group(1);
    return null;
  }

  static int _parseFloorLikes(html_dom.Element post) {
    for (final sel in [
      'span[id^="review_support_"]',
      '.postreview a.support',
      'a[id^="postreview_"] span',
      '.support_num',
      'em.support',
      'span[id^="recommendv_add"]',
      'span[id^="recommend_add"]',
      'a.recommend_add i',
      'a.recommend_add span',
      'a.reply_like span',
      'a[id^="reply_like_"]',
      '.comiis_recommend_num',
      '.comiis_recommend_nums',
    ]) {
      final el = post.querySelector(sel);
      if (el != null) {
        final m = RegExp(r'\d+').firstMatch(el.text);
        if (m != null) {
          final count = int.tryParse(m.group(0)!);
          if (count != null && count > 0) return count;
        }
      }
    }
    return 0;
  }

  // ---------------------------------------------------------------------
  // 签到排行（k_misign）
  // 兼容两种结构：klpbbs（tbody#autolist_{uid}）与本地 v4.3.0（table#J_list_detail）
  // ---------------------------------------------------------------------
  static List<SignEntry> parseSignList(String html) {
    final doc = html_parser.parse(html);
    final result = <SignEntry>[];

    // 结构一：tbody[id^="autolist_"]（klpbbs 新版）
    final autolists = doc.querySelectorAll('tbody[id^="autolist_"]');
    if (autolists.isNotEmpty) {
      for (final tbody in autolists) {
        final idAttr = tbody.attributes['id'] ?? '';
        final uid = int.tryParse(idAttr.replaceFirst('autolist_', '')) ?? 0;

        final nameA = tbody.querySelector('h4 a');
        final name = nameA?.text.trim() ?? '';

        String timeText = '';
        int totalDays = 0, monthDays = 0;
        for (final sp in tbody.querySelectorAll('h4 span')) {
          final t = sp.text.trim();
          if (t.startsWith('总天数')) {
            totalDays =
                int.tryParse(RegExp(r'(\d+)').firstMatch(t)?.group(1) ?? '') ??
                0;
          } else if (t.isNotEmpty && !t.startsWith('月天数')) {
            timeText = t;
          }
        }
        final p = tbody.querySelector('p.f_0')?.text.trim() ?? '';
        final md = RegExp(r'月天数\s*(\d+)\s*天').firstMatch(p);
        monthDays = int.tryParse(md?.group(1) ?? '') ?? 0;
        final rw = RegExp(r'上次奖励\s*(.+)').firstMatch(p);
        final rewardText = rw?.group(1)?.trim() ?? '';

        result.add(
          SignEntry(
            uid: uid,
            name: name,
            timeText: timeText,
            totalDays: totalDays,
            monthDays: monthDays,
            rewardText: rewardText,
          ),
        );
      }
      return result;
    }

    // 结构二与三：移动端列表与通用表格（ul.comiis_sign_list li, .sign_list li, table.dt tr, tr 等）
    if (result.isEmpty) {
      final listItems = doc.querySelectorAll(
        'ul.comiis_sign_list li, .k_misign_list li, .sign_list li, .sign_box li, div.comiis_p12 li, table.dt tr, table.tl tr, #ranklist tr, .bm_c table tr, .ct2_a tr, table tr',
      );
      for (final el in listItems) {
        if (el.querySelector('th') != null && el.querySelectorAll('td').isEmpty) {
          continue;
        }
        final a = el.querySelector(
          'a[href*="space-uid-"], a[href*="uid="], a[href*="space"], a.author, h4 a, .name a',
        );
        if (a == null) continue;
        final name = a.text.trim();
        if (name.isEmpty || name == '签到' || name == '排行榜' || name == '更多') {
          continue;
        }
        final uid = _uidFromHref(a.attributes['href'] ?? '') ?? 0;

        final timeEl = el.querySelector(
          '.time, .timeText, span.xg1, span.kmtime, td.time',
        );
        var timeText = timeEl?.text.trim() ?? '';

        int totalDays = 0;
        final totalMatch = RegExp(
          r'总(?:天数|签到)?[:：\s]*(\d+)',
        ).firstMatch(el.text);
        if (totalMatch != null) {
          totalDays = int.tryParse(totalMatch.group(1)!) ?? 0;
        }

        int monthDays = 0;
        final monthMatch = RegExp(
          r'月(?:天数|签到)?[:：\s]*(\d+)',
        ).firstMatch(el.text);
        if (monthMatch != null) {
          monthDays = int.tryParse(monthMatch.group(1)!) ?? 0;
        }

        String rewardText = '';
        final rewardMatch = RegExp(r'奖励[:：\s]*([^\s,，;]+)').firstMatch(el.text);
        if (rewardMatch != null) rewardText = rewardMatch.group(1) ?? '';

        // 如果是标准 table tr 结构且未匹配到标签，从 td 顺序提取
        final tds = el.querySelectorAll('td');
        if (tds.length >= 3 && (totalDays == 0 && monthDays == 0)) {
          for (final td in tds) {
            final txt = td.text.trim();
            if (timeText.isEmpty && (txt.contains('-') || txt.contains(':'))) {
              timeText = txt;
            } else if (rewardText.isEmpty &&
                (txt.contains('粒') ||
                    txt.contains('金') ||
                    txt.contains('经验'))) {
              rewardText = txt;
            } else if (totalDays == 0) {
              final d = int.tryParse(
                RegExp(r'(\d+)').firstMatch(txt)?.group(1) ?? '',
              );
              if (d != null && d > 0) totalDays = d;
            } else if (monthDays == 0) {
              final d = int.tryParse(
                RegExp(r'(\d+)').firstMatch(txt)?.group(1) ?? '',
              );
              if (d != null && d > 0) monthDays = d;
            }
          }
        }

        result.add(
          SignEntry(
            uid: uid,
            name: name,
            timeText: timeText,
            totalDays: totalDays,
            monthDays: monthDays,
            rewardText: rewardText,
          ),
        );
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------
  // 小黑屋（违规公示）
  // ---------------------------------------------------------------------
  static ({List<DarkroomEntry> entries, int? nextCid}) parseDarkroom(String html) {
    final doc = html_parser.parse(html);
    final result = <DarkroomEntry>[];

    // 1. 解析移动端与 PC 端表格
    for (final tr in doc.querySelectorAll('table tr, tr[id^="darkroomuid_"]')) {
      final tds = tr.querySelectorAll('td');
      if (tds.length < 3) continue;

      final idAttr = tr.attributes['id'] ?? '';
      int uid = int.tryParse(idAttr.replaceFirst('darkroomuid_', '')) ?? 0;

      String username = '';
      final a = tds[0].querySelector('a');
      if (a != null) {
        username = a.text.trim();
        final href = a.attributes['href'] ?? '';
        final m = RegExp(r'uid[-=](\d+)').firstMatch(href);
        if (m != null && uid == 0) {
          uid = int.tryParse(m.group(1)!) ?? 0;
        }
      } else {
        username = tds[0].text.trim();
      }

      if (username.isEmpty || username == '用户名') continue;

      final action = tds[1].text.trim();
      String? expiry;
      String dateline = '';
      String reason = '';

      if (tds.length >= 5) {
        // PC 5 列布局
        final expiryRaw = tds[2].text.trim();
        expiry = expiryRaw.isNotEmpty ? expiryRaw : null;
        dateline = tds[3].text.trim();
        final span = tds[3].querySelector('span');
        if (span != null && span.attributes['title'] != null) {
          dateline = span.attributes['title']!;
        }
        reason = tds[4].text.trim();
      } else {
        // 移动端 3 列布局 (用户名, 操作行为, 操作理由)
        reason = tds[2].text.trim();
      }

      result.add(
        DarkroomEntry(
          uid: uid,
          username: username,
          action: action,
          dateline: dateline,
          expiry: expiry,
          reason: reason,
        ),
      );
    }

    // 2. 提取下一页 CID 游标（移动端 pagination: href="...cid=42518..."）
    int? nextCid;
    for (final a in doc.querySelectorAll('a')) {
      final text = a.text.trim();
      final href = a.attributes['href'] ?? '';
      if (text.contains('下一页') || href.contains('action=showdarkroom')) {
        final m = RegExp(r'cid=(\d+)').firstMatch(href);
        if (m != null) {
          nextCid = int.tryParse(m.group(1)!);
          break;
        }
      }
    }

    return (entries: result, nextCid: nextCid);
  }

  // ---------------------------------------------------------------------
  // 用户空间（个人中心）
  // ---------------------------------------------------------------------
  static UserSpace? parseUserSpace(String html, int uid) {
    final doc = html_parser.parse(html);

    // 0. 关键防御：彻底移除顶部导航栏、登录用户身份条、全站页脚，防止抓取到当前登录用户的用户名与积分
    final cleanDoc = doc.clone(true);
    cleanDoc
        .querySelectorAll(
          '#toptb, #hd, #um, .hdc, .comiis_head, .comiis_nav, #nv, #ft, .footer, .comiis_sidenv, #comiis_sidenv, #comiis_menu',
        )
        .forEach((e) => e.remove());

    // 1. 用户名提取（优先目标个人空间标题 #uhd / h2.mbn / meta 标签）
    String username = '';
    final uhdH2 = cleanDoc.querySelector(
      '#uhd h2.mt, #uhd .tb_h h2, #uhd h2, h2.mbn, div.pbm h2.xs2',
    );
    if (uhdH2 != null) {
      final clone = uhdH2.clone(true);
      clone.querySelectorAll('span, em, a').forEach((e) => e.remove());
      username = clone.text.trim();
    }
    if (username.isEmpty) {
      final descMeta = cleanDoc.querySelector('meta[name="description"]');
      if (descMeta != null) {
        final c = descMeta.attributes['content'] ?? '';
        final m = RegExp(r'^(.+?)的个人资料').firstMatch(c);
        if (m != null) username = m.group(1)!.trim();
      }
    }
    if (username.isEmpty) {
      final h2 = cleanDoc.querySelector(
        '.comiis_space_tx h2, h2.fyy, span.user_tit, .user_tit',
      );
      if (h2 != null) username = h2.text.trim();
    }
    if (username.isEmpty) {
      final title = cleanDoc.querySelector('title')?.text.trim() ?? '';
      final m = RegExp(r'^(.+?)的个人空间').firstMatch(title);
      if (m != null) username = m.group(1)!.trim();
    }

    // 从页面文本提取字段
    String credits = '', regdate = '', lastvisit = '', signature = '';
    String level = '', levelName = '';
    final levEl = cleanDoc.querySelector(
      'span.kmlevs.kmlv, span.kmlevs.bg_0, span.user_lev, #g_up',
    );
    if (levEl != null) level = levEl.text.trim();
    final levNameEl = cleanDoc.querySelector(
      'span.kmlev, a[href*="usergroup"]',
    );
    if (levNameEl != null) levelName = levNameEl.text.trim();

    // 作用域限制在个人资料核心区（#psts, .pf_l, #ct, .comiis_space_tx）
    final mainScope =
        cleanDoc.querySelector('#ct, #psts, .pf_l, .comiis_space_tx') ??
        cleanDoc.body;
    final text = mainScope?.text ?? '';
    final cm =
        RegExp(r'积分\s*[:：]?\s*(\d+)').firstMatch(text) ??
        RegExp(r'(\d+)\s*积分').firstMatch(text);
    if (cm != null) credits = cm.group(1)!;
    final rm = RegExp(
      r'注册时间\s*[:：]?\s*(\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)',
    ).firstMatch(text);
    if (rm != null) regdate = rm.group(1)!;
    final lm = RegExp(
      r'最后访问\s*[:：]?\s*(\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)',
    ).firstMatch(text);
    if (lm != null) lastvisit = lm.group(1)!;
    // 签名提取：支持手机版与 PC 版结构
    // 手机版：<li><a><div class="profile_face">内容</div><span>个人签名</span></a></li>
    // PC版：.pf_l li: <li><em class="xg1">个人签名</em><table><tr><td><div align="center">内容</div></td></tr></table></li>
    for (final li in doc.querySelectorAll('.pf_l li, ul.cl li, #psts li, .pbm li, li')) {
      final span = li.querySelector('span, em, th, span.dt, span.kmtit');
      if (span != null && span.text.trim().replaceAll(' ', '') == '个人签名') {
        final contentEl = li.querySelector('table td div, table td, .profile_face, div[align="center"]') ??
            li.querySelector('table') ??
            li.querySelector('div');
        if (contentEl != null) {
          signature = (contentEl.innerHtml.isNotEmpty ? contentEl.innerHtml : contentEl.text).trim();
        } else {
          final clone = li.clone(true);
          clone.querySelector('em, th, span.dt, span.kmtit, span')?.remove();
          signature = (clone.innerHtml.isNotEmpty ? clone.innerHtml : clone.text).trim();
        }
        break;
      }
    }
    // 勋章（手机模板 #comiis_medal img[id^=md_]；PC 模板 p.md_ctrl img[id^=md_]）
    final medals = <({int id, String name, String desc, String img})>[];
    for (final img in doc.querySelectorAll(
      '#comiis_medal img[id^="md_"], p.md_ctrl img[id^="md_"]',
    )) {
      final idAttr = img.attributes['id'] ?? '';
      final id = int.tryParse(idAttr.replaceFirst('md_', '')) ?? 0;
      if (id == 0) continue;
      final name = img.attributes['alt'] ?? '';
      final src = _medalUrl(img.attributes['src']);
      String desc = '';
      final menu = doc.querySelector(
        'div[id="md_${id}_menu"] .tip_c p, div[id="md_${id}_menu"] p',
      );
      if (menu != null) desc = menu.text.trim();
      medals.add((id: id, name: name, desc: desc, img: src));
    }
    // 资料与统计字段解析 (支持 PC / 手机模板)
    final stats = <String, String>{};
    final creditsDetail = <String, String>{};
    final gameProfile = <String, String>{};

    // 1) 针对 HTML 树中 li / tr / div 中的 em+文本 及手机版图标条目进行精细化抽取
    for (final a in doc.querySelectorAll(
      '#psts a, .pbm a, .pf_l a, ul.cl a, .cl a, .comiis_space_profileico a, .comiis_space_profileico li, .comiis_space_profileico span',
    )) {
      final aText = a.text.trim();
      final sm = RegExp(
        r'(主题|回帖|回复|好友|记录|相册|分享|帖子|人气|空间访问量|访问量)数?\s*[:：]?\s*(\d+)',
      ).firstMatch(aText);
      if (sm != null) {
        final k = sm.group(1)!;
        final v = sm.group(2)!;
        if (k == '主题' || k == '帖子') stats['主题'] = v;
        if (k == '回帖' || k == '回复') stats['回复'] = v;
        if (k == '好友') stats['好友'] = v;
        if (k == '人气' || k == '空间访问量' || k == '访问量') stats['人气'] = v;
        if (k == '记录') stats['记录'] = v;
        if (k == '相册') stats['相册'] = v;
      }
      final sm2 = RegExp(r'(\d+)\s*(?:人气|次访问|访问量)').firstMatch(aText);
      if (sm2 != null) {
        stats.putIfAbsent('人气', () => sm2.group(1)!);
      }
    }

    final viewsEl = doc.querySelector('#space_views, .views, .fyy, .comiis_space_views, span[class*="fyy"]');
    if (viewsEl != null) {
      final vm = RegExp(r'(\d+)').firstMatch(viewsEl.text);
      if (vm != null) {
        stats['人气'] = vm.group(1)!;
      }
    }

    for (final el in doc.querySelectorAll(
      '.pf_l li, ul.cl li, #psts li, .pbm li, li, tr, .comiis_flex',
    )) {
      final em = el.querySelector('em, th, span.dt, span.kmtit');
      if (em != null) {
        final label = em.text
            .replaceAll(':', '')
            .replaceAll('：', '')
            .replaceAll(' ', '')
            .trim();
        // 取排除 em 之后的全部文本（支持内部 a / span 标签）
        String value = '';
        final clone = el.clone(true);
        clone.querySelector('em, th, span.dt, span.kmtit')?.remove();
        value = clone.text.replaceAll(':', '').replaceAll('：', '').trim();

        if (label.isNotEmpty && value.isNotEmpty) {
          if (label.contains('主题') || label == '帖子') {
            stats['主题'] = value;
          } else if (label.contains('回帖') || label == '回复') {
            stats['回复'] = value;
          } else if (label.contains('好友')) {
            stats['好友'] = value;
          } else if (label.contains('人气') || label.contains('访问量')) {
            stats['人气'] = value;
          } else if (label == '积分') {
            creditsDetail['积分'] = value;
          } else if (label == '经验') {
            creditsDetail['经验'] = value;
          } else if (label == '铁粒') {
            creditsDetail['铁粒'] = value;
          } else if (label.contains('铁锭')) {
            creditsDetail['铁锭'] = value;
          } else if (label == '贡献') {
            creditsDetail['贡献'] = value;
          } else if (label == '钻石') {
            creditsDetail['钻石'] = value;
          } else if (label == '用户组') {
            if (levelName.isEmpty) levelName = value;
          } else {
            gameProfile[label] = value;
          }
        }
      }
    }

    // 2) 针对原始 HTML 进行正则兜底提取
    final emRegex = RegExp(
      r'<em[^>]*>([^<]+)</em>\s*(?:<[^>]+>)*\s*([^<\r\n]+)',
    );
    for (final m in emRegex.allMatches(html)) {
      final label = m
          .group(1)!
          .replaceAll(':', '')
          .replaceAll('：', '')
          .replaceAll(' ', '')
          .trim();
      final value = m.group(2)!.replaceAll(':', '').replaceAll('：', '').trim();
      if (label.isNotEmpty && value.isNotEmpty) {
        if (label.contains('主题')) stats.putIfAbsent('主题', () => value);
        if (label.contains('回帖')) stats.putIfAbsent('回复', () => value);
        if (label.contains('好友')) stats.putIfAbsent('好友', () => value);
        if (label.contains('人气') || label.contains('访问量')) stats.putIfAbsent('人气', () => value);
        if (label == '积分') creditsDetail.putIfAbsent('积分', () => value);
        if (label == '经验') creditsDetail.putIfAbsent('经验', () => value);
        if (label == '铁粒') creditsDetail.putIfAbsent('铁粒', () => value);
        if (label.contains('铁锭')) creditsDetail.putIfAbsent('铁锭', () => value);
        if (label == '贡献') creditsDetail.putIfAbsent('贡献', () => value);
        if (label == '钻石') creditsDetail.putIfAbsent('钻石', () => value);
        if (label == '用户组' && levelName.isEmpty) levelName = value;
        gameProfile.putIfAbsent(label, () => value);
      }
    }

    final popMatch = RegExp(r'(?:人气|空间访问量|访问量)\s*[:：]?\s*(\d+)|(\d+)\s*(?:人气|次访问)').firstMatch(html);
    if (popMatch != null) {
      final v = popMatch.group(1) ?? popMatch.group(2);
      if (v != null && v.isNotEmpty) stats.putIfAbsent('人气', () => v);
    }

    // 3) 提取用户组全名（如 "Lv.4 Lv.4 高级会员" / "Lv.4 高级会员"）
    final groupEl = doc.querySelector(
      'a[href*="usergroup"], .kmlev, .user_lev, #g_up',
    );
    if (groupEl != null && groupEl.text.trim().isNotEmpty) {
      if (levelName.isEmpty) levelName = groupEl.text.trim();
    }
    if (username.isEmpty) username = '用户$uid';
    // 头像挂件（sunju_facemall）：.comiis_space_tx img / .user_img img 的 ##SJ## 后缀
    final faceImg = doc.querySelector('.comiis_space_tx img, .user_img img');
    final faceUrl = _faceUrlFromAvatar(faceImg?.attributes['src']) ?? '';

    // 空间背景图提取（Discuz comiis_app_homestyle 空间壁纸）
    String? bgUrl;
    final bgMatch = RegExp(
      r'comiis_space_box[^{]*\{[^}]*background(?:\-image)?\s*:\s*url\(([^)]+)\)',
    ).firstMatch(html);
    if (bgMatch != null) {
      final rawBg = bgMatch
          .group(1)!
          .replaceAll("'", '')
          .replaceAll('"', '')
          .trim();
      bgUrl = _image(rawBg);
    }
    if (bgUrl == null || bgUrl.isEmpty) {
      final bgMatch2 = RegExp(
        r'background(?:\-image)?\s*:\s*url\(([^)]*home_bg/[^)]+)\)',
      ).firstMatch(html);
      if (bgMatch2 != null) {
        final rawBg = bgMatch2
            .group(1)!
            .replaceAll("'", '')
            .replaceAll('"', '')
            .trim();
        bgUrl = _image(rawBg);
      }
    }

    // 在线状态检测（Discuz ol.gif / online.png / title="当前在线" / (当前在线) / 离线标记排除 / 20分钟近期活动窗口计算）
    bool isOnline = false;
    final hasOlImg = doc.querySelector(
      'img[src*="ol.gif"], img:not(.authicn)[src*="online.png"], img:not(.authicn)[src*="online.gif"], img[alt="online"], img[title*="当前在线"], img[title="在线"], .comiis_o, em.online, span.online',
    ) != null;
    final hasOfflineImg = doc.querySelector(
      'img[src*="offline.png"], img[src*="offline.gif"], img[title*="当前离线"], img[title="离线"], .comiis_f, em.offline, span.offline',
    ) != null;
    final hasOnlineText = html.contains('当前在线') ||
        html.contains('(当前在线)') ||
        html.contains('<em>在线</em>') ||
        html.contains('title="当前在线"');
    final hasOfflineText = html.contains('当前离线') ||
        html.contains('(当前离线)') ||
        html.contains('<em>离线</em>') ||
        html.contains('title="当前离线"');

    final actText = lastvisit.isNotEmpty
        ? lastvisit
        : (gameProfile['上次活动时间'] ??
            gameProfile['最后访问'] ??
            gameProfile['最后活动'] ??
            '');

    final isRecent = _isRecentActivity(actText);

    String onlineStatusText;
    if (!hasOfflineImg && !hasOfflineText && (hasOlImg || hasOnlineText || isRecent)) {
      isOnline = true;
      onlineStatusText = '当前在线';
    } else if (actText.isNotEmpty) {
      onlineStatusText = '最后访问: $actText';
    } else {
      onlineStatusText = '离线';
    }

    final cleanSig = _cleanSignature(signature);
    if (cleanSig.isNotEmpty && uid > 0) {
      authorSigCache[uid] = cleanSig;
    }

    // 资料完整度计算（优先从网页已完成百分比提取，若无则基于 8 项核心资料动态计算）
    int profileProgress = 0;
    final progMatch = RegExp(r'已完成\s*(\d+)%').firstMatch(html) ??
        RegExp(r'profileprogress.*?(\d+)%?').firstMatch(html) ??
        RegExp(r'class="p_box"[^>]*style="width:\s*(\d+)%').firstMatch(html);
    if (progMatch != null) {
      profileProgress = int.tryParse(progMatch.group(1)!) ?? 0;
    }
    if (profileProgress == 0) {
      int total = 8;
      int filled = 0;
      if (cleanSig.isNotEmpty) filled++;
      if (gameProfile.containsKey('自定义头衔') || gameProfile.containsKey('头衔')) filled++;
      if (gameProfile.containsKey('基岩版用户名') || gameProfile.containsKey('Minecraft 基岩版 ID')) filled++;
      if (gameProfile.containsKey('Java版用户名') || gameProfile.containsKey('Minecraft Java 正版玩家 ID')) filled++;
      if (gameProfile.containsKey('生日') || gameProfile.containsKey('出生日期')) filled++;
      if (gameProfile.containsKey('性别')) filled++;
      if (gameProfile.containsKey('代表作')) filled++;
      if (faceUrl.isNotEmpty || medals.isNotEmpty) filled++;
      profileProgress = ((filled / total) * 100).round();
    }

    return UserSpace(
      uid: uid,
      username: _cleanTitle(username),
      credits: credits,
      regdate: regdate,
      lastvisit: lastvisit,
      signature: cleanSig,
      level: _cleanTitle(level),
      levelName: _cleanTitle(levelName),
      medals: medals,
      faceUrl: faceUrl,
      bgUrl: bgUrl ?? '',
      stats: stats,
      creditsDetail: creditsDetail,
      gameProfile: gameProfile,
      isOnline: isOnline,
      onlineStatusText: onlineStatusText,
      profileProgress: profileProgress,
    );
  }

  /// 解析 Discuz 个人资料编辑页原生表单字段 (home.php?mod=spacecp&ac=profile&op=...&mobile=2)
  static Map<String, dynamic> parseProfileEditInfo(String html, {String op = 'info'}) {
    final doc = html_parser.parse(html);
    final formhash = doc.querySelector('input[name="formhash"]')?.attributes['value'] ??
        RegExp(r'formhash=([a-zA-Z0-9]+)').firstMatch(html)?.group(1) ??
        '';

    int completionRate = 0;
    final compMatch = RegExp(r'已完成\s*(\d+)%').firstMatch(html) ??
        RegExp(r'profileprogress.*?(\d+)%?').firstMatch(html);
    if (compMatch != null) {
      completionRate = int.tryParse(compMatch.group(1)!) ?? 0;
    }

    // 1. 签名档 (sightml / signature textarea)
    String signature = '';
    final signTextarea = doc.querySelector('textarea[name="sightml"], textarea[name="signature"], input[name="sightml"], textarea#sightml');
    if (signTextarea != null) {
      signature = cleanSignatureText(signTextarea.text);
    }

    // 2. 自定义头衔 (customstatus)
    String customStatus = '';
    final csInput = doc.querySelector('input[name="customstatus"], textarea[name="customstatus"]');
    if (csInput != null) {
      customStatus = csInput.attributes['value'] ?? csInput.text.trim();
    }

    // 3. 真实姓名 (realname)
    String realname = '';
    final rnInput = doc.querySelector('input[name="realname"]');
    if (rnInput != null) {
      realname = rnInput.attributes['value'] ?? rnInput.text.trim();
    }

    // 4. 性别 (gender)
    int gender = 0;
    final genderSelect = doc.querySelector('select[name="gender"]');
    if (genderSelect != null) {
      final selOption = genderSelect.querySelector('option[selected]');
      if (selOption != null) {
        gender = int.tryParse(selOption.attributes['value'] ?? '0') ?? 0;
      }
    } else {
      final g1 = doc.querySelector('input[name="gender"][value="1"]');
      final g2 = doc.querySelector('input[name="gender"][value="2"]');
      if (g1?.attributes.containsKey('checked') == true) {
        gender = 1;
      } else if (g2?.attributes.containsKey('checked') == true) {
        gender = 2;
      }
    }

    // 5. 生日 (birthyear, birthmonth, birthday)
    int? birthYear;
    int? birthMonth;
    int? birthDay;
    final byOpt = doc.querySelector('select[name="birthyear"] option[selected]');
    if (byOpt != null) birthYear = int.tryParse(byOpt.attributes['value'] ?? byOpt.text.trim());
    final bmOpt = doc.querySelector('select[name="birthmonth"] option[selected]');
    if (bmOpt != null) birthMonth = int.tryParse(bmOpt.attributes['value'] ?? bmOpt.text.trim());
    final bdOpt = doc.querySelector('select[name="birthday"] option[selected]');
    if (bdOpt != null) birthDay = int.tryParse(bdOpt.attributes['value'] ?? bdOpt.text.trim());

    // 6. 自定义字段 (field1, field2, field3...)
    final customFields = <String, String>{};
    final fieldPrivacy = <String, String>{};
    final fieldLabels = <String, String>{};
    final items = <Map<String, dynamic>>[];
    final seenNames = <String>{};
    String email = '';

    for (final input in doc.querySelectorAll('input[name^="field"], textarea[name^="field"]')) {
      final name = input.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      final val = input.attributes['value'] ?? input.text.trim();
      customFields[name] = val;
    }
    for (final sel in doc.querySelectorAll('select[name^="privacy["]')) {
      final name = sel.attributes['name'] ?? '';
      final selOpt = sel.querySelector('option[selected]');
      if (selOpt != null) {
        fieldPrivacy[name] = selOpt.attributes['value'] ?? '0';
      }
    }

    // 7. 动态解析每一行的标题、字段名、初始值与隐私设置
    final rows = doc.querySelectorAll('form li, .comiis_penc_list li, .comiis_penc_box li, table.tfm tr, li');
    for (final row in rows) {
      final titEl = row.querySelector('.styli_tit, .tit, th, dt, label');
      String label = '';
      if (titEl != null) {
        final clone = titEl.clone(true);
        for (final icon in clone.querySelectorAll('i, .comiis_font, em, font')) {
          icon.remove();
        }
        label = clone.text
            .replaceAll('*', '')
            .replaceAll(':', '')
            .replaceAll('：', '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }

      // 如果抓取到的 label 碰巧是隐私选择词（公开/保密/好友可见），予以清空并走标准名回退
      if (label == '公开' || label == '保密' || label == '好友可见') {
        label = '';
      }

      final privSel = row.querySelector('select[name^="privacy["]');
      final hasPrivacy = privSel != null;
      String privacyName = '';
      String privacyValue = '0';
      if (privSel != null) {
        privacyName = privSel.attributes['name'] ?? '';
        final selOpt = privSel.querySelector('option[selected]') ?? privSel.querySelector('option');
        privacyValue = selOpt?.attributes['value'] ?? '0';
      }

      // Email 行检测
      if (label.toLowerCase() == 'email' || (row.text.contains('@') && row.text.contains('Email'))) {
        final flexEl = row.querySelector('.flex, .comiis_flex1, td, dd');
        final emailSource = (flexEl != null ? flexEl.text : row.text)
            .replaceFirst(RegExp(r'^(?:Email|邮箱)\s*:?\s*', caseSensitive: false), '');
        final emMatch = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').firstMatch(emailSource);
        if (emMatch != null) {
          email = emMatch.group(0)!;
          if (seenNames.add('email')) {
            items.add({
              'label': 'Email',
              'name': 'email',
              'value': email,
              'type': 'email',
              'hasPrivacy': hasPrivacy,
              'privacyName': privacyName,
              'privacyValue': privacyValue,
            });
          }
          continue;
        }
      }

      // 性别
      final gSel = row.querySelector('select[name="gender"]');
      if (gSel != null) {
        final gVal = gSel.querySelector('option[selected]')?.attributes['value'] ?? '$gender';
        if (seenNames.add('gender')) {
          items.add({
            'label': label.isEmpty ? '性别' : label,
            'name': 'gender',
            'value': gVal,
            'type': 'gender',
            'hasPrivacy': hasPrivacy,
            'privacyName': privacyName,
            'privacyValue': privacyValue,
          });
        }
        continue;
      }

      // 生日
      final bySel = row.querySelector('select[name="birthyear"]');
      if (bySel != null) {
        if (seenNames.add('birthday')) {
          items.add({
            'label': label.isEmpty ? '生日' : label,
            'name': 'birthday',
            'value': '${birthYear ?? ""}-${birthMonth ?? ""}-${birthDay ?? ""}',
            'type': 'birthday',
            'hasPrivacy': hasPrivacy,
            'privacyName': privacyName,
            'privacyValue': privacyValue,
          });
        }
        continue;
      }

      // 普通输入框 / Textarea
      final input = row.querySelector('input:not([type="hidden"]):not([type="submit"]):not([type="button"]), textarea');
      if (input != null) {
        final name = input.attributes['name'] ?? '';
        if (name.isEmpty || name == 'formhash') continue;
        String val = input.localName == 'textarea'
            ? input.text.trim()
            : (input.attributes['value'] ?? '').trim();
        if (name == 'sightml' || name == 'signature') {
          val = cleanSignatureText(val);
        }
        if (val.startsWith('高级链接')) {
          val = val.replaceFirst('高级链接', '').trim();
        }

        // 规范化友好的 Label 映射回退
        if (label.isEmpty || label == name) {
          if (name == 'field1') {
            label = '基岩版用户名';
          } else if (name == 'field2') {
            label = op == 'contact' ? '网易用户名' : '代表作';
          } else if (name == 'field3') {
            label = 'Java版用户名';
          } else if (name == 'field4') {
            label = 'Xbox ID';
          } else if (name == 'field8') {
            label = '代表作';
          } else if (name == 'customstatus') {
            label = '自定义头衔';
          } else if (name == 'sightml' || name == 'signature') {
            label = '个人签名';
          } else if (name == 'realname') {
            label = '真实姓名';
          } else if (name == 'gender') {
            label = '性别';
          } else if (name == 'birthday' || name == 'birthyear') {
            label = '生日';
          } else if (name == 'qq') {
            label = 'QQ';
          } else if (name == 'email') {
            label = 'Email';
          } else {
            label = input.attributes['placeholder'] ?? name;
          }
        }

        fieldLabels[name] = label;
        if (seenNames.add(name)) {
          items.add({
            'label': label,
            'name': name,
            'value': val,
            'type': input.localName == 'textarea' ? 'textarea' : 'text',
            'hasPrivacy': hasPrivacy,
            'privacyName': privacyName,
            'privacyValue': privacyValue,
          });
        }
      }
    }

    return {
      'formhash': formhash,
      'signature': signature,
      'customStatus': customStatus,
      'realname': realname,
      'gender': gender,
      'birthYear': birthYear,
      'birthMonth': birthMonth,
      'birthDay': birthDay,
      'email': email,
      'customFields': customFields,
      'fieldPrivacy': fieldPrivacy,
      'fieldLabels': fieldLabels,
      'items': items,
      'completionRate': completionRate,
    };
  }

  // ---------------------------------------------------------------------
  // 私信（收件箱 + 会话详情）
  // ---------------------------------------------------------------------
  static List<PmConversation> parsePmList(String html) {
    final doc = html_parser.parse(html);
    final result = <PmConversation>[];
    // 会话条目 dl[id^="pmlist_"]（plid）
    for (final dl in doc.querySelectorAll('dl[id^="pmlist_"]')) {
      final idAttr = dl.attributes['id'] ?? '';
      final plid = int.tryParse(idAttr.replaceFirst('pmlist_', '')) ?? 0;
      if (plid == 0) continue;

      // 1. touid 提取（优先从头像区域、checkbox、回复链接）
      int touid = 0;
      final avtA = dl.querySelector('dd.m.avt a, dd.avt a, a.avt, dd.m a');
      if (avtA != null) {
        touid = _uidFromHref(avtA.attributes['href'] ?? '') ?? 0;
      }
      if (touid == 0) {
        final cb = dl.querySelector('input[name="deletepm_deluid[]"]');
        if (cb != null) {
          touid = int.tryParse(cb.attributes['value'] ?? '') ?? 0;
        }
      }
      if (touid == 0) {
        final replyA = dl.querySelector('a[href*="subop=view"]');
        if (replyA != null) {
          touid = _uidFromHref(replyA.attributes['href'] ?? '') ?? 0;
        }
      }

      // 2. 是否有未读消息（Discuz 真实 DOM：未读会话 dl 会包含 newpm 或 new 类名）
      final isNew = dl.classes.contains('newpm') ||
          dl.classes.contains('new') ||
          dl.querySelector('.newpm .newpm_avt, .new .newpm_avt') != null;

      final ptm = dl.querySelector('dd.ptm, dd.pm_c');
      if (ptm == null) continue;

      // 3. 对方用户名（如果是我发出的，a 标签是对方名字，前面是 "您 对 xxx 说 :"）
      String username = '';
      final nameA = ptm.querySelector('a.xw1, a[href*="space-uid"], a[href*="uid="]');
      if (nameA != null) {
        username = nameA.text.trim();
        if (touid == 0) {
          touid = _uidFromHref(nameA.attributes['href'] ?? '') ?? 0;
        }
      }

      // 4. 消息总数（如 "共 6 条"）
      int msgCount = 0;
      final countSpan = ptm.querySelector('span.xg1.z, span.z');
      if (countSpan != null) {
        final cm = RegExp(r'(\d+)').firstMatch(countSpan.text);
        if (cm != null) msgCount = int.tryParse(cm.group(1)!) ?? 0;
      }

      // 5. 时间文本
      String timeText = '';
      final timeSpan = ptm.querySelector('span.xg1:not(.z)') ?? ptm.querySelector('span.xg1');
      if (timeSpan != null && !timeSpan.classes.contains('z')) {
        timeText = timeSpan.attributes['title'] ?? timeSpan.text.trim();
      }

      // 6. 摘要提取（深度移除 a 标签、时间、操作菜单，纯净正文）
      var summary = '';
      final clone = ptm.clone(true);
      clone.querySelectorAll('a, span.xg1, span.pm_o, div.p_pop, div.o, .newpm_avt, input').forEach((e) => e.remove());
      summary = clone.text.replaceAll('\n', ' ').trim();
      // 移除 "对 您 说 :" 或 "您 对 说 :" 等前缀
      summary = summary.replaceFirst(RegExp(r'^(?:您|[^\s:]+)?\s*对\s*(?:您|[^\s:]+)?\s*说\s*[:：]\s*'), '').trim();
      summary = summary.replaceAll(RegExp(r'\s+'), ' ').trim();

      // 7. 头像挂件提取
      final avatarImg = dl.querySelector('dd.m.avt img, dd.avt img, a.avt img, dd.m img, img[src*="avatar"]');
      final rawAvatar = avatarImg?.attributes['src'] ?? avatarImg?.attributes['data-original'];
      final faceUrl = _faceUrlFromAvatar(rawAvatar);

      result.add(
        PmConversation(
          plid: plid,
          touid: touid,
          username: username,
          summary: summary,
          timeText: timeText,
          messageCount: msgCount,
          isNew: isNew,
          faceUrl: faceUrl,
        ),
      );
    }
    return result;
  }

  /// 会话详情消息（dl[id^="pmlist_"]，ptm 区域）
  static List<PmMessage> parsePmDetail(String html) {
    final doc = html_parser.parse(html);
    final result = <PmMessage>[];
    for (final dl in doc.querySelectorAll('dl[id^="pmlist_"]')) {
      final idAttr = dl.attributes['id'] ?? '';
      final pmid = int.tryParse(idAttr.replaceFirst('pmlist_', '')) ?? 0;
      if (pmid == 0) continue;
      final ptm = dl.querySelector('dd.ptm, dd.pm_c');
      if (ptm == null) continue;

      // 1. 发送者 UID & 头像
      int authorUid = 0;
      final avtA = dl.querySelector('dd.m.avt a, dd.avt a, a.avt, dd.m a');
      if (avtA != null) {
        authorUid = _uidFromHref(avtA.attributes['href'] ?? '') ?? 0;
      }

      // 2. 发送者名称
      String author = '';
      final authorA = ptm.querySelector('a.xw1, a[href*="space-uid"], a[href*="uid="]');
      if (authorA != null) {
        author = authorA.text.trim();
        if (authorUid == 0) {
          authorUid = _uidFromHref(authorA.attributes['href'] ?? '') ?? 0;
        }
      } else {
        final youSpan = ptm.querySelector('span.xi2, span.xw1');
        if (youSpan != null && youSpan.text.contains('您')) {
          author = '您';
        }
      }

      // 3. 时间文本（span.xg1 或 span[title]）
      String timeText = '';
      final ts = ptm.querySelector('span[title]') ?? ptm.querySelector('span.xg1');
      if (ts != null) {
        timeText = ts.attributes['title'] ?? ts.text.trim();
      }

      // 4. 正文内容提取（彻底剥离发送者名称、时间、菜单等无关节点）
      final clone = ptm.clone(true);
      clone.querySelectorAll('a.xw1, span.xi2, span.xg1, span.pm_o, div.p_pop, .o, script, style').forEach((e) => e.remove());
      var content = clone.text.replaceAll('\n', ' ').trim();
      content = content.replaceFirst(RegExp(r'^(?:您|[^\s:]+)?\s*对\s*(?:您|[^\s:]+)?\s*说\s*[:：]\s*'), '').trim();
      content = content.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (content.isNotEmpty || pmid > 0) {
        final avatarImg = dl.querySelector('dd.m.avt img, dd.avt img, a.avt img, dd.m img, img[src*="avatar"]');
        final rawAvatar = avatarImg?.attributes['src'] ?? avatarImg?.attributes['data-original'];
        final faceUrl = _faceUrlFromAvatar(rawAvatar);

        result.add(
          PmMessage(
            pmid: pmid,
            authorUid: authorUid,
            author: author,
            content: content,
            timeText: timeText,
            faceUrl: faceUrl,
          ),
        );
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // 用户空间帖子与回复列表（home.php?mod=space&do=thread）
  // ---------------------------------------------------------------------
  static List<ThreadSummary> parseUserThreads(String html) {
    if (html.isEmpty ||
        html.contains('抱歉，您尚未登录') ||
        (html.contains('提示信息') && html.contains('请先登录'))) {
      return const [];
    }

    final doc = html_parser.parse(html);
    final result = <ThreadSummary>[];
    final seen = <int>{};

    // 提取空间主人昵称与 UID
    var spaceAuthor = '';
    int? spaceUid;
    final spaceUserEl = doc.querySelector(
      '.space_username, #uhd h2, h2.mbn, a.xw1, .p_header h2, span.user_name, .profile_username',
    );
    if (spaceUserEl != null) {
      spaceAuthor = _cleanAuthor(spaceUserEl.text);
      spaceUid = _uidFromHref(spaceUserEl.attributes['href'] ?? '');
    }
    if (spaceAuthor.isEmpty) {
      final docTitle = doc.querySelector('title')?.text ?? '';
      if (docTitle.contains('的帖子')) {
        spaceAuthor = _cleanAuthor(docTitle.split('的帖子').first);
      } else if (docTitle.contains('的主题')) {
        spaceAuthor = _cleanAuthor(docTitle.split('的主题').first);
      } else if (docTitle.contains('的回复')) {
        spaceAuthor = _cleanAuthor(docTitle.split('的回复').first);
      }
    }

    // 0. 清洗全局导航与无用容器，保留空间帖子主体容器
    final cleanDoc = doc.clone(true);
    cleanDoc
        .querySelectorAll(
          '#comiis_nav, #nv, #ft, .footer, #toptb, #hd, #um, .hdc, .comiis_head, .comiis_foot, #scbar, #pt, .cl.pbm, div#pt, div.focus, .comiis_menu, table.cptbl',
        )
        .forEach((e) => e.remove());

    // 1. KLPBBS C-Style 空间列表模式（.c_threadlist ul li 或 .c_threadlist li）
    final cThreadItems = cleanDoc.querySelectorAll('.c_threadlist li');
    if (cThreadItems.isNotEmpty) {
      for (final li in cThreadItems) {
        // 判断是否是回复项（含 .cli_reply）
        final replyEl = li.querySelector('.cli_reply a, .cli_reply');
        var titEl = li.querySelector(
          '.tit > a, .tit a[href*="thread-"], .tit a[href*="findpost"], .tit a[href*="tid="]',
        );
        if (titEl != null && titEl.text.trim().isEmpty) {
          final allTitAs = li.querySelectorAll('.tit a');
          for (final a in allTitAs) {
            if (a.text.trim().isNotEmpty) {
              titEl = a;
              break;
            }
          }
        }
        final directA = li.querySelector(
          'a[href*="thread-"], a[href*="tid="], a[href*="findpost"]',
        );

        final targetA = titEl ?? directA ?? replyEl;
        if (targetA == null) continue;

        final href =
            titEl?.attributes['href'] ??
            directA?.attributes['href'] ??
            replyEl?.attributes['href'] ??
            '';
        final tid = _tidFromHref(href);
        if (tid == null || tid <= 0 || !seen.add(tid)) continue;

        String title = '';
        if (titEl != null && titEl.text.trim().isNotEmpty) {
          title = _cleanTitle(titEl.text);
        } else if (directA != null && directA.text.trim().isNotEmpty) {
          title = _cleanTitle(directA.text);
        }
        if (title.isEmpty && replyEl != null) {
          title = _cleanTitle(replyEl.text);
        }
        if (title.isEmpty) continue;

        // 发布/回复时间
        String timeText = '';
        final dteEl = li.querySelector('.dte');
        if (dteEl != null) {
          timeText = dteEl.text.trim();
        }

        // 回复/查看数
        int replies = -1;
        int views = -1;
        final repEl = li.querySelector('.sub .rep, em.rep');
        if (repEl != null) {
          final m = RegExp(r'(\d+)').firstMatch(repEl.text);
          if (m != null) replies = int.tryParse(m.group(1)!) ?? -1;
        }
        final vieEl = li.querySelector('.sub .vie, em.vie');
        if (vieEl != null) {
          final m = RegExp(r'(\d+)').firstMatch(vieEl.text);
          if (m != null) views = int.tryParse(m.group(1)!) ?? -1;
        }

        // 版块名
        String? forumName;
        final catEl = li.querySelector('.sub .cat a, em.cat a');
        if (catEl != null) {
          forumName = catEl.text.trim();
        }

        // 回复正文/摘要
        String? excerpt;
        if (replyEl != null) {
          excerpt = replyEl.text.replaceAll('\n', ' ').trim();
        }

        final cover = _coverFromScope(li);

        final mId = RegExp(r'fav_(\d+)').firstMatch(li.attributes['id'] ?? '') ??
            RegExp(r'favid=(\d+)').firstMatch(li.innerHtml);
        final favid = mId != null ? int.tryParse(mId.group(1)!) : null;

        result.add(
          ThreadSummary(
            tid: tid,
            uid: spaceUid,
            author: spaceAuthor,
            title: title,
            forumName: forumName,
            timeText: timeText,
            excerpt: excerpt?.isNotEmpty == true ? excerpt : null,
            views: views,
            replies: replies,
            coverUrl: cover,
            favid: favid,
          ),
        );
      }
    }

    // 2. PC 端表格模式（严格在 form#delform, table.tl, table.dt, div.tl 内检索）
    if (result.isEmpty) {
      final tableContainer = cleanDoc.querySelector(
        'form#delform, table.tl, table.dt, div.tl, div.bm_c, .bm.bw0, div.bm',
      );
      if (tableContainer != null) {
        final allTrs = tableContainer.querySelectorAll('tr');
        for (final tr in allTrs) {
          if (tr.querySelector('th') != null &&
              tr.querySelectorAll('td').isEmpty) {
            continue;
          }
          final a =
              tr.querySelector('th a.xst') ??
              tr.querySelector('th a.s.xst') ??
              tr.querySelector('th a[href*="viewthread"]') ??
              tr.querySelector('th a[href*="thread-"]') ??
              tr.querySelector('a.xst') ??
              tr.querySelector('a.s.xst') ??
              tr.querySelector('a[href*="viewthread"]') ??
              tr.querySelector('a[href*="thread-"]');
          if (a == null) continue;
          final href = a.attributes['href'] ?? '';
          final tid = _tidFromHref(href);
          if (tid == null || tid <= 0 || !seen.add(tid)) continue;

          String title = _cleanTitle(a.text);
          if (title.isEmpty) {
            final th = tr.querySelector('th');
            if (th != null) title = _cleanTitle(th.text);
          }
          if (title.isEmpty) continue;

          // 版块名
          String? forumName;
          final forumA = tr.querySelector(
            'td.forum a, td a[href*="forumdisplay"], td a[href*="forum-"], a.xg1',
          );
          if (forumA != null) {
            forumName = forumA.text.trim();
          }

          // 发布/回复时间
          String timeText = '';
          final timeEl = tr.querySelector(
            'td.by em, td.by span, span.xg1, td.lastpost em, span.time',
          );
          if (timeEl != null) {
            timeText = timeEl.text.trim();
          }

          // 回复/查看数
          int views = -1;
          int replies = -1;
          final numTd = tr.querySelector('td.num');
          if (numTd != null) {
            final numA = numTd.querySelector('a.xi2, a');
            if (numA != null) replies = int.tryParse(numA.text.trim()) ?? -1;
            final em = numTd.querySelector('em');
            if (em != null) views = int.tryParse(em.text.trim()) ?? -1;
          }

          // 回复摘要（若有）
          String? excerpt;
          final excerptEl = tr.querySelector(
            'div.pbn, div.xg1, p.xg1, td.pbn, .quote',
          );
          if (excerptEl != null) {
            excerpt = excerptEl.text.replaceAll('\n', ' ').trim();
          }

          final cover = _coverFromScope(tr);
          var favid = int.tryParse(tr.querySelector('input[name*="favorite"]')?.attributes['value'] ?? '');
          if (favid == null || favid <= 0) {
            final mId = RegExp(r'fav_(\d+)').firstMatch(tr.attributes['id'] ?? '') ??
                RegExp(r'favid=(\d+)').firstMatch(tr.innerHtml);
            if (mId != null) favid = int.tryParse(mId.group(1)!);
          }

          result.add(
            ThreadSummary(
              tid: tid,
              uid: spaceUid,
              author: spaceAuthor,
              title: title,
              forumName: forumName,
              timeText: timeText,
              excerpt: excerpt,
              views: views,
              replies: replies,
              coverUrl: cover,
              favid: favid,
            ),
          );
        }
      }
    }

    // 3. 移动端列表模式（ul.comiis_threads_list li, div.threadlist li, div.comiis_userlist li, .comiis_p12 li 等）
    if (result.isEmpty) {
      final listContainer = cleanDoc.querySelector(
        'ul.comiis_threads_list, ul.comiis_list, div.threadlist, div.comiis_userlist, div.comiis_space_box, .comiis_p12, .comiis_wxlist_li',
      );
      final items = listContainer != null
          ? listContainer.querySelectorAll('li, dl.cl, div.comiis_twimg')
          : cleanDoc.querySelectorAll(
              'ul.comiis_threads_list li, div.threadlist li, .comiis_p12 li, div.comiis_userlist li',
            );

      for (final li in items) {
        final a = li.querySelector(
          'a[href*="viewthread"], a[href*="thread-"], a[href*="tid="], a[href*="findpost"], a.s.xst, a.xw1, h3 a, h2 a, dt a',
        );
        if (a == null) continue;
        final href = a.attributes['href'] ?? '';
        final tid = _tidFromHref(href);
        if (tid == null || tid <= 0 || !seen.add(tid)) continue;

        String title = _cleanTitle(a.text);
        if (title.isEmpty) continue;

        final timeText =
            li
                .querySelector('.mtime, .xg1, span.date, .time, .f_d, .kmtime')
                ?.text
                .trim() ??
            '';
        final excerpt = li
            .querySelector('.threadlist_mes, .pbn, p, .mes, .list_body')
            ?.text
            .trim();
        final cover = _coverFromScope(li);
        final mId = RegExp(r'fav_(\d+)').firstMatch(li.attributes['id'] ?? '') ??
            RegExp(r'favid=(\d+)').firstMatch(li.innerHtml);
        final favid = mId != null ? int.tryParse(mId.group(1)!) : null;

        result.add(
          ThreadSummary(
            tid: tid,
            uid: spaceUid,
            author: spaceAuthor,
            title: title,
            timeText: timeText,
            excerpt: excerpt?.isNotEmpty == true ? excerpt : null,
            coverUrl: cover,
            favid: favid,
          ),
        );
      }
    }

    return result;
  }

  /// ---------------------------------------------------------------------
  /// 搜索结果列表（search.php?mod=forum&searchid=... 支持 Discuz/Xunsearch 各种模板）
  /// ---------------------------------------------------------------------
  static List<ThreadSummary> parseSearchResults(String html) {
    final doc = html_parser.parse(html);
    final result = <ThreadSummary>[];
    final seen = <int>{};

    // 1. Xunsearch (迅搜) 卡片列表 (.result-card cf, .result-item)
    final xunCards = doc.querySelectorAll('.result-card, .result-item');
    for (final card in xunCards) {
      final titleA = card.querySelector(
        '.result-title a, h3 a, a[href*="tid="], a[href*="thread-"]',
      );
      if (titleA == null) continue;
      final href = titleA.attributes['href'] ?? '';
      final tid = _tidFromHref(href);
      if (tid == null || tid <= 0 || !seen.add(tid)) continue;

      final title = _cleanTitle(titleA.text);
      if (title.isEmpty) continue;

      final excerpt = card
          .querySelector('.result-body, .content, p')
          ?.text
          .trim();
      final authorA = card.querySelector(
        '.result-meta a[href*="space"], .result-meta a[href*="uid="]',
      );
      final author = authorA != null ? _cleanAuthor(authorA.text) : '';
      final uid = authorA != null
          ? _uidFromHref(authorA.attributes['href'] ?? '')
          : null;

      final forumA = card.querySelector(
        '.result-meta a[href*="forumdisplay"], .result-meta a[href*="fid="], .result-meta a[href*="forum-"]',
      );
      final forumName = forumA?.text.trim();

      final timeEl = card.querySelector('.result-meta span:first-child');
      final timeText = timeEl?.text.trim();

      final cover = _coverFromScope(card);

      result.add(
        ThreadSummary(
          tid: tid,
          uid: uid,
          author: author,
          title: title,
          excerpt: excerpt?.isNotEmpty == true ? excerpt : null,
          forumName: forumName,
          timeText: timeText,
          coverUrl: cover,
        ),
      );
    }

    // 2. Discuz 标准/Xunsearch 搜索列表 (li.pbw, li.cl, div.slst li)
    final items = doc.querySelectorAll(
      'li.pbw, .slst li, div#threadlist li, div.tl tr, table.dt tr, .comiis_list li, .threadlist li',
    );
    for (final item in items) {
      final titleA = item.querySelector(
        'h3.xs3 a, dt.xs2 a, th a.xst, a[href*="viewthread"], a[href*="thread-"], a[href*="tid="], a.s.xst',
      );
      if (titleA == null) continue;
      final href = titleA.attributes['href'] ?? '';
      final tid = _tidFromHref(href);
      if (tid == null || tid <= 0 || !seen.add(tid)) continue;

      final title = titleA.text.trim();
      if (title.isEmpty) continue;

      // 提取摘要
      final excerptEl = item.querySelector('p, .content, div.message, .c_p');
      final excerpt = excerptEl != null
          ? _cleanNoticeText(excerptEl.text)
          : null;

      // 提取作者与 UID
      final authorA = item.querySelector(
        'a[href*="space-uid-"], a[href*="uid="], span.author a, td.by a',
      );
      final author = authorA != null ? _cleanAuthor(authorA.text) : '';
      final uid = authorA != null
          ? _uidFromHref(authorA.attributes['href'] ?? '')
          : null;

      // 提取版块
      final forumA = item.querySelector(
        'a[href*="forumdisplay"], a[href*="forum-"], span.forum a',
      );
      final forumName = forumA?.text.trim();

      // 提取时间
      final timeEl = item.querySelector(
        'span.xg1, span.time, span.em, td.by em, .xs1',
      );
      final timeText = timeEl != null ? _cleanNoticeText(timeEl.text) : null;

      // 提取回复/查看数
      int views = -1;
      int replies = -1;
      final numEl = item.querySelector('span.num, td.num');
      if (numEl != null) {
        final matches = RegExp(r'(\d+)').allMatches(numEl.text);
        if (matches.isNotEmpty) {
          replies = int.tryParse(matches.first.group(1) ?? '') ?? -1;
          if (matches.length > 1) {
            views = int.tryParse(matches.elementAt(1).group(1) ?? '') ?? -1;
          }
        }
      }

      final cover = _coverFromScope(item);

      result.add(
        ThreadSummary(
          tid: tid,
          uid: uid,
          author: author,
          title: title,
          excerpt: excerpt,
          forumName: forumName,
          timeText: timeText,
          views: views,
          replies: replies,
          coverUrl: cover,
        ),
      );
    }

    // 2. 兜底回退 parseThreadList
    if (result.isEmpty) {
      return parseThreadList(html);
    }

    return result;
  }

  /// ---------------------------------------------------------------------
  /// 解析 Discuz 提示消息框（#messagetext, .alert_error, .alert_right, .alert_info）
  /// ---------------------------------------------------------------------
  static String? parseMessage(String html) {
    final doc = html_parser.parse(html);
    final msgEl = doc.querySelector(
      '#messagetext, .alert_right, .alert_error, .alert_info, .comiis_tip, .jump_c',
    );
    if (msgEl != null) {
      final p = msgEl.querySelector('p') ?? msgEl;
      final text = p.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// ---------------------------------------------------------------------
  /// 楼层全量评分/打赏日志（forum.php?mod=misc&action=viewratings&tid=...&pid=...）
  /// ---------------------------------------------------------------------
  static List<FloorReward> parseRatings(String html) {
    final doc = html_parser.parse(html);
    final results = <FloorReward>[];
    for (final tr in doc.querySelectorAll(
      'table.ratelog tr, div.c tr, table.dt tr, .ratelist tr, table.tf tr, div.rate tr',
    )) {
      final userA = tr.querySelector('a[href*="space-uid-"], a[href*="uid="]');
      if (userA == null) continue;
      final username = _cleanAuthor(userA.text);
      if (username.isEmpty) continue;
      final uid = _uidFromHref(userA.attributes['href'] ?? '');

      final tds = tr.querySelectorAll('td');
      String score = '';
      String reason = '';
      String time = '';

      if (tds.length >= 3) {
        score = tds[1].text.trim();
        time = tds.last.text.trim();
        if (tds.length >= 4) {
          reason = tds[2].text.trim();
        }
      } else {
        score = tr.querySelector('.xi1, .xg1, span.z')?.text.trim() ?? '';
      }

      results.add(
        FloorReward(
          username: username,
          uid: uid,
          amount: score.isNotEmpty ? score : '+10 铁粒',
          reason: reason.isNotEmpty ? reason : '打赏评分支持',
          dateline: time,
        ),
      );
    }
    return results;
  }

  /// 通知列表（home.php?mod=space&do=notice）
  static List<NoticeItem> parseNotices(String html) {
    final doc = html_parser.parse(html);
    final result = <NoticeItem>[];
    final seenKeys = <String>{};

    // 严谨定位顶层通知条目容器，防止父子节点（li 与 div.ntc_body）被同时命中导致条目翻倍
    final rawItems = doc.querySelectorAll(
      '#ct dl.cl, .xld dl.cl, .nts_list > li, ul.comiis_notice > li, .comiis_notice > li, table.tf tr',
    );
    final items = rawItems.isNotEmpty
        ? rawItems
        : doc.querySelectorAll('dl.cl, li.cl, .comiis_userlist li');

    for (final body in items) {
      final a = body.querySelector(
        'a[href*="goto=findpost"], a[href*="ptid="], a[href*="viewthread"], a[href*="tid="], a[href*="thread-"]',
      );
      final href = a?.attributes['href'] ?? '';
      final tid = _tidFromHref(href) ?? 0;

      // 提取发送人与 UID（过滤无文字的头像链接）
      var author = '';
      int? uid;
      final authorCandidates = body.querySelectorAll(
        '.ntc_body a[href*="space-uid-"], .ntc_body a[href*="uid="], a.xw1, .actor a, a[href*="space-uid-"], a[href*="uid="], a[href*="space.php"]',
      );
      for (final candidate in authorCandidates) {
        final candidateUid = _uidFromHref(candidate.attributes['href'] ?? '');
        if (uid == null && candidateUid != null && candidateUid > 0) {
          uid = candidateUid;
        }
        final cleaned = _cleanAuthor(candidate.text);
        if (author.isEmpty && cleaned.isNotEmpty) {
          author = cleaned;
        }
      }

      // 提取头像链接与挂件
      final avatarEl = body.querySelector(
        'dd.m.avt img, .avt img, .actor img, img[src*="avatar"]',
      );
      final rawAvatar = avatarEl?.attributes['src'] ?? avatarEl?.attributes['data-original'];
      final avatarUrl =
          _avatarUrl(rawAvatar) ??
          (uid != null ? AppConfig.avatarUrl(uid, size: 'small') : '');
      final faceUrl = _faceUrlFromAvatar(rawAvatar);

      // 提取时间
      final timeEl = body.querySelector(
        '.date, .time, .xg1, span.xg1, .ntc_time, h2.f_d, dt.date',
      );
      var timeText = timeEl != null ? _cleanNoticeText(timeEl.text) : '';

      // 提取引用气泡（“ ... ” 引用文本）
      String? quoteText;
      final quoteEl = body.querySelector(
        '.quote, blockquote, .summary, div.ntc_body .xg1, .comiis_quote',
      );
      if (quoteEl != null) {
        final q = _cleanNoticeText(
          quoteEl.text,
        ).replaceAll('“', '').replaceAll('”', '').trim();
        if (q.isNotEmpty && q != timeText) {
          quoteText = q;
        }
      }

      final rawText = body.text;
      final isPoke =
          rawText.contains('打个招呼') ||
          rawText.contains('打招呼') ||
          rawText.contains('poke');
      final isFriend =
          rawText.contains('好友') ||
          rawText.contains('加您为好友') ||
          rawText.contains('请求添加');

      // 提取动作描述与主题名，剔除操作按钮链接文字（回打招呼/忽略/删除等）
      var actionText = '';
      String? threadTitle;

      final ntcBody =
          body.querySelector('.ntc_body, dt, div.ntc_body, h2.f_d') ?? body;
      final cloneBody = ntcBody.clone(true);
      cloneBody
          .querySelectorAll(
            '.date, .time, .xg1, .quote, blockquote, .summary, .time, a.d, a.shield, a[href*="op=ignore"], a[href*="poke"], a[href*="friend"], a[onclick*="poke"], a[onclick*="noticeignore"], a[href*="delnotice"]',
          )
          .forEach((e) => e.remove());
      actionText = _cleanNoticeText(cloneBody.text);
      actionText = actionText
          .replaceAll('现在去查看', '')
          .replaceAll('回打招呼|忽略', '')
          .replaceAll('回打招呼', '')
          .replaceAll('忽略', '')
          .replaceAll('查看 ›', '')
          .replaceAll('查看 >', '')
          .replaceAll('查看»', '')
          .replaceAll('查看', '')
          .replaceAll('»', '')
          .replaceAll('|', '')
          .replaceAll(RegExp(r'^\s*[:：,，\s]+'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      // 规范化互动文本
      if (isPoke) {
        if (actionText.isEmpty ||
            actionText == '打个招呼' ||
            actionText == '打招呼' ||
            actionText == author) {
          actionText = '向您打了个招呼';
        }
      } else if (isFriend) {
        if (actionText.isEmpty || actionText == '好友' || actionText == author) {
          actionText = '请求添加您为好友';
        }
      }

      // 剥离开头重复包含的作者名，避免渲染成 "张三 张三 回复了您"
      if (author.isNotEmpty && actionText.startsWith(author)) {
        actionText = actionText.substring(author.length).trim();
        actionText = actionText.replaceFirst(RegExp(r'^[:：\s]+'), '').trim();
      }

      // 过滤侧边栏/底栏伪通知（如 "我的帖子"、"坛友互动"、"系统提醒" 等非真正通知的链接文本）
      if (actionText == '我的消息' ||
          actionText == '我的帖子' ||
          actionText == '坛友互动' ||
          actionText == '系统提醒' ||
          actionText == '应用提醒' ||
          actionText == '我的粉丝' ||
          actionText == '公共消息' ||
          (author == '我的粉丝' && actionText.contains('TA 的空间')) ||
          (author == '论坛用户' &&
              (actionText == '我的帖子' ||
                  actionText == '坛友互动' ||
                  actionText == '系统提醒' ||
                  actionText == '应用提醒'))) {
        continue;
      }

      // 提取被提及/回复的主题标题
      final threadA = body.querySelector(
        'a[href*="thread-"], a[href*="viewthread"], a[href*="ptid="]',
      );
      if (threadA != null) {
        final tText = _cleanTitle(threadA.text);
        if (tText.isNotEmpty &&
            tText != '现在去查看' &&
            tText != '查看' &&
            tText != '本帖') {
          threadTitle = tText;
        }
      }

      // 分类徽章
      String badge = '提醒';
      if (rawText.contains('中提到了您') || rawText.contains('@')) {
        badge = '提到我的';
      } else if (isPoke) {
        badge = '打招呼';
      } else if (isFriend) {
        badge = '好友';
      } else if (rawText.contains('回复了您') ||
          rawText.contains('回复') ||
          rawText.contains('点评')) {
        badge = '回复';
      } else if (rawText.contains('悬赏') || rawText.contains('最佳答案')) {
        badge = '悬赏';
      } else if (rawText.contains('评分') ||
          rawText.contains('铁粒') ||
          rawText.contains('打赏')) {
        badge = '评分';
      } else if (rawText.contains('勋章')) {
        badge = '勋章';
      } else if (rawText.contains('粉丝') || rawText.contains('关注')) {
        badge = '粉丝';
      } else if (rawText.contains('系统') ||
          rawText.contains('审核') ||
          rawText.contains('举报') ||
          rawText.contains('通过')) {
        badge = '系统';
      }

      if (actionText.isEmpty) {
        actionText = rawText.contains('回复')
            ? '回复了您的帖子'
            : (badge == '系统' ? '系统提醒通知' : '论坛消息提醒');
      }

      final isNew = body.classes.contains('new') ||
          body.classes.contains('notice_new') ||
          (body.querySelector('.notice_new, .new, em.new, span.new, .unread, .bg_del') != null) ||
          body.attributes['style']?.contains('font-weight:bold') == true ||
          body.attributes['style']?.contains('font-weight: bold') == true;

      final uniqueKey =
          '${uid ?? author}_${tid}_${timeText.isNotEmpty ? timeText : ""}_${actionText.replaceAll(" ", "")}';
      if (!seenKeys.add(uniqueKey)) continue;

      result.add(
        NoticeItem(
          tid: tid,
          uid: uid,
          author: author.isNotEmpty
              ? author
              : (badge == '系统' ? '系统提醒' : '论坛用户'),
          avatarUrl: avatarUrl,
          faceUrl: faceUrl,
          actionText: actionText,
          threadTitle: threadTitle,
          quoteText: quoteText,
          timeText: timeText,
          badge: badge,
          linkUrl: href,
          isPoke: isPoke,
          isFriendRequest: isFriend,
          isNew: isNew,
        ),
      );
    }

    return result;
  }

  static String _cleanNoticeText(String text) {
    if (text.isEmpty) return '';
    return text
        .replaceAll(RegExp(r'[\uE000-\uF8FF]'), '') // 滤除 comiis 字体图标乱码 □
        .replaceAll(
          RegExp(r'\[s:\d+\]', caseSensitive: false),
          '',
        ) // 滤除表情代码 [s:2]
        .replaceAll(RegExp(r'\[audio\].*?\[/audio\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('屏蔽', '')
        .replaceAll(RegExp(r'^\s*[:：,，\s]+'), '')
        .trim();
  }

  /// 提取页面中的下一页链接（用于分页加载）
  static String? nextPageUrl(String html, String baseUrl) {
    final doc = html_parser.parse(html);
    for (final a in doc.querySelectorAll(
      'a[href*="page="], a[href*="page-"]',
    )) {
      final href = a.attributes['href'] ?? '';
      final text = a.text.trim();
      if (text.contains('下一页') || text.contains('下页')) {
        if (href.startsWith('http')) return href;
        return baseUrl + href.replaceFirst(RegExp(r'^\./'), '');
      }
    }
    return null;
  }

  /// 解析小喇叭广播/全站公告（ahome_horn 插件或顶部公告栏）
  static List<HornMessage> parseHornMessages(String html) {
    final doc = html_parser.parse(html);
    final result = <HornMessage>[];

    // 结构：table.tsmini_horn_content > tr[id*="horn_"]（ahome_horn 小喇叭）
    for (final tr in doc.querySelectorAll('tr[id*="horn_"]')) {
      final idAttr = tr.attributes['id'] ?? '';
      final id =
          int.tryParse(idAttr.replaceAll(RegExp(r'[^0-9]'), '')) ??
          result.length + 1;

      final tds = tr.querySelectorAll('td');
      final contentTd = tds.length >= 2 ? tds[1] : tr;

      // 提取作者与 UID
      final userA = contentTd.querySelector(
        'a[href*="space&uid"], a[href*="mod=space"]',
      );
      var author = userA?.text.trim() ?? '';
      if (author.isEmpty && contentTd.text.contains('系统消息')) {
        author = '系统消息';
      }
      final uid = _uidFromHref(userA?.attributes['href'] ?? '');

      // 提取头像与挂件
      final avatarImg = tr.querySelector('.tsmini_horn_avatar img, td img');
      final rawAvatar = avatarImg?.attributes['src'] ?? avatarImg?.attributes['data-original'];
      var avatarUrl = _avatarUrl(rawAvatar);
      if ((avatarUrl == null || avatarUrl.isEmpty) && rawAvatar != null) {
        avatarUrl = _absolute(rawAvatar);
      }
      final faceUrl = _faceUrlFromAvatar(rawAvatar);

      // 提取发布时间（位于 tds[2] 或带日期的 span）
      String timeText = '';
      if (tds.length >= 3) {
        timeText = tds[2].text.trim();
      }
      if (timeText.isEmpty) {
        for (final sp in tr.querySelectorAll('span, td, font')) {
          final m = RegExp(
            r'\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}|\d+\s*(?:秒|分钟|小时|天)前|昨天\s*\d{1,2}:\d{2}|前天\s*\d{1,2}:\d{2}',
          ).firstMatch(sp.text);
          if (m != null) {
            timeText = m.group(0)!;
            break;
          }
        }
      }

      // 提取正文：保留样式与表情，剥离作者前缀
      final clone = contentTd.clone(true);
      clone
          .querySelectorAll('b, a[href*="mod=space"], a[href*="space&uid"]')
          .forEach((e) => e.remove());
      var content = clone.innerHtml
          .replaceAll(RegExp(r'^\s*[：:]\s*'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (content.isEmpty) {
        content = clone.text
            .replaceAll(RegExp(r'^\s*[：:]\s*'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
      if (content.isEmpty && author.isEmpty) continue;

      final linkEl = contentTd.querySelector(
        'a[href*="thread-"], a[href*="viewthread"]',
      );
      final linkUrl = _absolute(linkEl?.attributes['href']);

      // 提取删除链接（如果有 del/delete 链接或相关路由）
      final delEl = tr.querySelector(
        'a[href*="del"], a[href*="delete"], a[onclick*="del"], a[onclick*="delete"]',
      );
      final deleteUrl = _absolute(delEl?.attributes['href']);

      result.add(
        HornMessage(
          id: id,
          author: author.isEmpty ? '小喇叭' : author,
          uid: uid,
          content: content,
          timeText: timeText,
          avatarUrl: avatarUrl,
          faceUrl: faceUrl,
          linkUrl: linkUrl,
          deleteUrl: deleteUrl,
          tag: '小喇叭',
        ),
      );
    }
    // 无数据时返回空（不再返回硬编码假广播）
    return result;
  }

  /// 解析小喇叭发布页（ahome_horn:add）：formhash + 文本颜色选项
  ///
  /// 真实抓取 horn_add.html：form action=plugin.php?id=ahome_horn:add，字段
  /// formhash/fid/tid/fromurl/ifsystem/hidename/color/boss/message/addsubmit。
  /// 内置表情 `source/plugin/ahome_horn/image/smiles/{0-23}.png`，插入码 `[s:{n}]`。
  static ({String formhash, List<String> colors}) parseHornPostInfo(
    String html,
  ) {
    final doc = html_parser.parse(html);
    final fh = RegExp(
      r'name="formhash" value="([a-f0-9]{8,32})"',
    ).firstMatch(html);
    final formhash = fh?.group(1) ?? '';
    final colors = <String>[];
    final colorSel = doc.querySelector('select[name="color"]');
    if (colorSel != null) {
      for (final opt in colorSel.querySelectorAll('option')) {
        final v = opt.attributes['value'] ?? '';
        if (v.isNotEmpty) colors.add(v);
      }
    }
    return (formhash: formhash, colors: colors);
  }

  /// 解析登录/注册页面的验证码信息与表单 Hash
  static ({
    String formhash,
    String loginhash,
    String seccodehash,
    String seccodemodid,
  })
  parseSecCodeInfo(String html) {
    var formhash = '';
    var loginhash = '';
    var seccodehash = '';
    var seccodemodid = '';

    final fmM =
        RegExp(
          r'''name=["']formhash["']\s+value=["']([a-zA-Z0-9]+)["']''',
        ).firstMatch(html) ??
        RegExp(r'''formhash=([a-zA-Z0-9]{8,16})''').firstMatch(html);
    if (fmM != null) formhash = fmM.group(1)!;

    final lgM =
        RegExp(r'''loginhash=([a-zA-Z0-9]+)''').firstMatch(html) ??
        RegExp(r'''loginfield_([a-zA-Z0-9]+)''').firstMatch(html);
    if (lgM != null) loginhash = lgM.group(1)!;

    final scM =
        RegExp(r'''updateseccode\(['"]([a-zA-Z0-9]+)['"]''').firstMatch(html) ??
        RegExp(r'''idhash=([a-zA-Z0-9]+)''').firstMatch(html) ??
        RegExp(r'''seccode_([a-zA-Z0-9]+)''').firstMatch(html) ??
        RegExp(
          r'''name=["']seccodehash["']\s+value=["']([a-zA-Z0-9]+)["']''',
        ).firstMatch(html);
    if (scM != null) seccodehash = scM.group(1)!;

    // seccodemodid：updateseccode('hash', 'html', 'modid') 第三参数
    final modM = RegExp(
      r'''updateseccode\(['"][\w]+['"],\s*['"][^'"]*['"],\s*['"]([\w:]+)['"]\)''',
    ).firstMatch(html);
    if (modM != null) seccodemodid = modM.group(1)!;

    return (
      formhash: formhash,
      loginhash: loginhash,
      seccodehash: seccodehash,
      seccodemodid: seccodemodid,
    );
  }

  /// 解析注册表单（comiis mobile=2 / Discuz PC）中的随机字段名与凭证。
  /// Discuz 会通过 reginput 配置把用户名/密码/邮箱渲染为随机 name（或空 name+id），
  /// 提交时必须原样回传这些字段名。
  static ({
    String formhash,
    String usernameField,
    String passwordField,
    String password2Field,
    String emailField,
    String seccodehash,
    String seccodemodid,
    String agreebbrule,
  })
  parseRegisterForm(String html) {
    final doc = html_parser.parse(html);
    final form = doc.querySelector('form#registerform, form[name="register"]');
    if (form == null) {
      return (
        formhash: '',
        usernameField: '',
        passwordField: '',
        password2Field: '',
        emailField: '',
        seccodehash: '',
        seccodemodid: '',
        agreebbrule: '',
      );
    }

    final hidden = <String, String>{};
    final textInputs = <html_dom.Element>[];
    final passwordInputs = <html_dom.Element>[];
    html_dom.Element? emailInput;

    for (final inp in form.querySelectorAll('input')) {
      final type = (inp.attributes['type'] ?? 'text').toLowerCase();
      final name = inp.attributes['name'] ?? '';
      if (type == 'hidden') {
        hidden[name] = inp.attributes['value'] ?? '';
        continue;
      }
      if (type == 'password') {
        passwordInputs.add(inp);
        continue;
      }
      if (type == 'email') {
        emailInput ??= inp;
        continue;
      }
      if (type == 'text') {
        if (name.toLowerCase().contains('seccode')) continue;
        textInputs.add(inp);
      }
    }

    String fieldName(html_dom.Element? el) => el == null
        ? ''
        : ((el.attributes['name'] ?? '').isNotEmpty
              ? el.attributes['name']!
              : (el.attributes['id'] ?? ''));

    final sec = parseSecCodeInfo(html);
    return (
      formhash: hidden['formhash'] ?? '',
      usernameField: textInputs.isNotEmpty ? fieldName(textInputs.first) : '',
      passwordField: passwordInputs.isNotEmpty
          ? fieldName(passwordInputs[0])
          : '',
      password2Field: passwordInputs.length >= 2
          ? fieldName(passwordInputs[1])
          : '',
      emailField: fieldName(emailInput),
      seccodehash: hidden['seccodehash'] ?? sec.seccodehash,
      seccodemodid: hidden['seccodemodid'] ?? sec.seccodemodid,
      agreebbrule: hidden['agreebbrule'] ?? '',
    );
  }

  /// 解析发帖页（forum.php?mod=post&action=newthread）的 formhash、可用的特殊主题类型与权限错误。
  /// Discuz 允许的特殊主题通过 switchpost('...&special=N') 菜单暴露；无菜单时仅普通帖。
  static ({
    String formhash,
    Set<int> allowedSpecials,
    List<({int value, String name})> typeOptions,
    String errorMessage,
  })
  parseNewThreadInfo(String html) {
    final allowed = <int>{0};
    final typeOptions = <({int value, String name})>[];
    String error = '';

    final fmM =
        RegExp(
          r'''name=["']formhash["'][^>]*value=["']([a-zA-Z0-9]+)["']''',
        ).firstMatch(html) ??
        RegExp(
          r'''formhash\s*=\s*["']([a-zA-Z0-9]{8,16})["']''',
        ).firstMatch(html);
    final formhash = fmM?.group(1) ?? '';

    // 主题分类 select[name="typeid"]（PC 发帖页专属）
    final doc = html_parser.parse(html);
    final typeSel = doc.querySelector('select[name="typeid"]');
    if (typeSel != null) {
      for (final opt in typeSel.querySelectorAll('option')) {
        final v = int.tryParse(opt.attributes['value'] ?? '') ?? 0;
        final name = opt.text.trim();
        if (v > 0 && name.isNotEmpty) {
          typeOptions.add((value: v, name: name));
        }
      }
    }

    // switchpost('forum.php?mod=post&action=newthread&special=1')
    for (final m in RegExp(
      r'''switchpost\(['"][^'"]*?(?:&|\?[?&])special=(\d+)['"]''',
    ).allMatches(html)) {
      allowed.add(int.tryParse(m.group(1)!) ?? 0);
    }

    // 权限错误：Discuz 常见 showmessage 弹窗（无权限/未登录/等级不足）
    final errM = RegExp(r'''showmessage\(['"]([^'"]+)['"]''').firstMatch(html);
    if (errM != null) {
      error = errM.group(1)!;
    } else {
      final jumpM = RegExp(
        r'''class=["']alert_error["'][^>]*>([^<]+)<''',
      ).firstMatch(html);
      if (jumpM != null) error = jumpM.group(1)!.trim();
    }
    if (error.isEmpty &&
        !html.contains('postform') &&
        !html.contains('needsubject')) {
      final titleM = RegExp(r'<title>([^<]*)</title>').firstMatch(html);
      if (titleM != null) error = titleM.group(1)!.trim();
    }

    return (
      formhash: formhash,
      allowedSpecials: allowed,
      typeOptions: typeOptions,
      errorMessage: error,
    );
  }

  static String _cleanRewardAmount(String raw) {
    final m = RegExp(r'([+-]?)(\d+)').firstMatch(raw);
    if (m == null) return raw;
    final sign = m.group(1)!.isEmpty ? '' : m.group(1)!;
    final num = int.tryParse(m.group(2)!) ?? 0;
    final unit = raw.contains('铁粒')
        ? '铁粒'
        : raw.contains('积分')
        ? '积分'
        : raw.contains('粒')
        ? '粒'
        : '';
    return unit.isEmpty ? '$sign$num' : '$sign$num $unit';
  }

  /// 解析资源帖分类信息表单（如模组/附加包/皮肤/软件的 中文名、版本、下载地址、原帖地址等）
  static ResourceInfoBlock? _parseResourceInfo(
    html_dom.Element root, {
    String? typeName,
  }) {
    final container = root.querySelector(
      '.comiis_view_flxx, .comiis_actinfo, .comiis_actbox, table.cptbl, table.typeoption, div.typeoption, div#typeoption',
    );
    if (container == null) return null;
    final table = container.localName == 'table'
        ? container
        : container.querySelector('table');
    if (table == null) return null;
    final fields = <ResourceInfoField>[];
    for (final tr in table.querySelectorAll('tr')) {
      final th = tr.querySelector('th');
      final td = tr.querySelector('td');
      if (th == null || td == null) continue;
      final label = th.text
          .replaceAll('\u00a0', ' ')
          .replaceAll('&nbsp;', ' ')
          .trim();
      if (label.isEmpty) continue;
      final a = td.querySelector('a');
      final rawHref = a?.attributes['href'] ?? '';
      final url = rawHref.isNotEmpty ? _absolute(rawHref) : null;
      final value = td.text
          .replaceAll('\u00a0', ' ')
          .replaceAll('&nbsp;', ' ')
          .trim();
      fields.add(
        ResourceInfoField(
          label: label,
          value: value.isEmpty ? '--' : value,
          url: url,
        ),
      );
    }
    if (fields.isEmpty) return null;
    var title = typeName?.trim() ?? '';
    if (title.isEmpty || title == '全部') title = '模组/资源发布信息';
    return ResourceInfoBlock(title: title, fields: fields);
  }

  /// 检测元素或祖先定义的文本/图片排版对齐方式（center / left / right / justify）
  static String? _detectAlign(html_dom.Element el, [String? fallback]) {
    final tag = (el.localName ?? '').toLowerCase();
    if (tag == 'center') return 'center';
    final alignAttr = el.attributes['align']?.toLowerCase().trim();
    if (alignAttr == 'center' ||
        alignAttr == 'left' ||
        alignAttr == 'right' ||
        alignAttr == 'justify') {
      return alignAttr;
    }
    final style = el.attributes['style']?.toLowerCase() ?? '';
    if (style.contains('text-align:center') ||
        style.contains('text-align: center')) {
      return 'center';
    }
    if (style.contains('text-align:right') ||
        style.contains('text-align: right')) {
      return 'right';
    }
    if (style.contains('text-align:left') ||
        style.contains('text-align: left')) {
      return 'left';
    }
    if (style.contains('text-align:justify') ||
        style.contains('text-align: justify')) {
      return 'justify';
    }
    if (el.classes.contains('tac') ||
        el.classes.contains('text-center') ||
        el.classes.contains('comiis_align_center')) {
      return 'center';
    }
    return fallback;
  }

  /// 将 HTML 字符串解析为结构化区块（编辑器 BBCode 预览、折叠块等场景）
  static List<PostBlock> parseStructuredBlocksFromHtml(String html) {
    final doc = html_parser.parseFragment(html);
    final wrapper = html_dom.Element.tag('div')..append(doc);
    return parseStructuredBlocks(wrapper);
  }

  /// 将楼层 message 节点解析为结构化区块列表（保留居中/左对齐/右对齐属性）
  static List<PostBlock> parseStructuredBlocks(
    html_dom.Element messageEl, {
    String? inheritedAlign,
  }) {
    final blocks = <PostBlock>[];
    if (messageEl.nodes.isEmpty) return blocks;

    var currentAlign = _detectAlign(messageEl, inheritedAlign);

    // 递归解包 Discuz 容器外壳（div.comiis_a / div.comiis_messages / table > tbody > tr > td.t_f）
    var targetEl = messageEl;
    while (true) {
      if (targetEl.children.length == 1) {
        final child = targetEl.children.first;
        currentAlign = _detectAlign(child, currentAlign);
        final childTag = (child.localName ?? '').toLowerCase();
        final isWrapper =
            childTag == 'tbody' ||
            childTag == 'thead' ||
            childTag == 'tfoot' ||
            childTag == 'main' ||
            childTag == 'mian' ||
            child.classes.contains('comiis_messages') ||
            child.classes.contains('comiis_message_table') ||
            child.classes.contains('comiis_a') ||
            child.classes.contains('view_one') ||
            child.classes.contains('view_all') ||
            (childTag == 'table' &&
                !child.classes.contains('t_table') &&
                child.querySelectorAll('tr').length <= 1 &&
                child.querySelectorAll('td').length <= 1) ||
            (childTag == 'tr' &&
                child.querySelectorAll('td').length <= 1 &&
                child.querySelectorAll('th').isEmpty) ||
            (childTag == 'td' &&
                (child.id.startsWith('postmessage_') ||
                    child.classes.contains('t_f') ||
                    targetEl.children.length == 1));

        if (isWrapper) {
          targetEl = child;
          continue;
        }
      }
      break;
    }

    for (final node in targetEl.nodes) {
      if (node is html_dom.Text) {
        final text = node.text.trim();
        if (text.isNotEmpty) {
          _appendOrMergeTextBlock(blocks, text, align: currentAlign);
        }
      } else if (node is html_dom.Element) {
        final nodeAlign = _detectAlign(node, currentAlign);
        final tag = (node.localName ?? '').toLowerCase();
        final outerHtml = node.outerHtml;
        final innerText = node.text.trim();

        // 忽略 Discuz 浮动弹窗模板与收藏/管理系统残留容器
        if ((node.id.startsWith('fwin_')) ||
            node.classes.contains('fwinmask') ||
            node.id == 'favoriteform' ||
            node.id == 'messagetext' ||
            innerText.contains('您确定要删除此收藏吗') ||
            innerText.contains('hideWindow(')) {
          continue;
        }

        // 0. 审核通过状态条 (.comiis_modact)
        if (node.classes.contains('comiis_modact') ||
            (node.classes.contains('modact') && innerText.contains('审核通过'))) {
          final text = innerText.replaceAll('&nbsp;', ' ');
          final match = RegExp(
            r'由\s*([^\s]+)\s*于\s*([^于]+?)\s*审核通过',
          ).firstMatch(text);
          final auditor = match?.group(1) ?? 'System';
          final time = match?.group(2) ?? '不久前';
          blocks.add(AuditStatusBlock(auditor: auditor, timeText: time));
          continue;
        }

        // 0. 投票帖专属卡片 (.comiis_poll, form#poll, div.poll, .comiis_poll_list, .pcht)
        if (node.classes.contains('comiis_poll') ||
            node.classes.contains('comiis_poll_list') ||
            node.classes.contains('poll') ||
            node.classes.contains('pcht') ||
            tag == 'form' && (node.id == 'poll' || node.attributes['action']?.contains('votepoll') == true) ||
            node.querySelector('form#poll, .comiis_poll_list, .pcht') != null) {
          var title =
              node.querySelector('.comiis_poll_top h2, .pinf strong, h2')?.text.trim() ??
              '投票';
          title = title.replaceAll(RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]', unicode: true), '').trim();
          if (title.isEmpty) title = '投票';

          final votersM = RegExp(r'共有\s*(\d+)\s*人').firstMatch(node.text);
          final votersCount = votersM != null
              ? int.tryParse(votersM.group(1)!) ?? 0
              : 0;

          final maxM = RegExp(r'最多可选\s*(\d+)\s*项').firstMatch(node.text);
          final maxChoices = maxM != null ? int.tryParse(maxM.group(1)!) ?? 1 : 1;

          final isClosed = node.text.contains('投票已经结束') ||
              node.text.contains('投票已结束') ||
              node.text.contains('关闭或者过期');

          String? expireText = isClosed ? '投票已经结束' : null;
          if (expireText == null) {
            final expM = RegExp(r'距结束[^\d]*(\d+[^<\n\s]+)').firstMatch(node.text);
            if (expM != null) {
              expireText = expM.group(1)?.trim();
            } else {
              final expEl = node.querySelector('.kmbtn span, .poll_time, .ptmr');
              if (expEl != null) {
                final txt = expEl.text.replaceAll('距结束还有:', '').trim();
                if (txt.isNotEmpty) expireText = txt;
              }
            }
          }

          final options = <PollOption>[];
          final optLis = node.querySelectorAll('.comiis_poll_list li, .pcht tr, .poll_options li');
          int optIdx = 1;
          for (int i = 0; i < optLis.length; i++) {
            final li = optLis[i];
            final labelEl = li.querySelector('label, .pvt, span.label');
            var name = labelEl?.text.trim() ?? '';
            if (name.isEmpty && li.classes.contains('kmnop')) {
              name = li.text.trim();
            }
            if (name.isEmpty) continue;

            final inputEl = li.querySelector('input[name="pollanswers[]"], input[type="radio"], input[type="checkbox"]');
            final pollOptionId = int.tryParse(inputEl?.attributes['value'] ?? '') ?? optIdx;

            int votes = 0;
            double percent = 0.0;
            String? color;

            if (i + 1 < optLis.length && (optLis[i + 1].classes.contains('poll_ok') || optLis[i + 1].querySelector('.pbr') != null)) {
              final resultLi = optLis[i + 1];
              final numM = RegExp(r'\((\d+)\)').firstMatch(resultLi.text) ??
                  RegExp(r'(\d+)\s*票').firstMatch(resultLi.text);
              if (numM != null) votes = int.tryParse(numM.group(1)!) ?? 0;

              final pctM = RegExp(r'([\d.]+)\s*%').firstMatch(resultLi.text);
              if (pctM != null) percent = double.tryParse(pctM.group(1)!) ?? 0.0;

              final em = resultLi.querySelector('em[style*="background-color"]');
              if (em != null) {
                final style = em.attributes['style'] ?? '';
                final bgM = RegExp(r'background-color:\s*(#[0-9a-fA-F]{3,8}|rgb\([^)]+\))').firstMatch(style);
                if (bgM != null) {
                  color = bgM.group(1);
                }
              }
            }

            options.add(
              PollOption(
                id: pollOptionId.toString(),
                label: name,
                votes: votes,
                percent: percent,
                colorHex: color,
                isChecked: false,
              ),
            );
            optIdx++;
          }

          blocks.add(
            PollBlock(
              title: title,
              isMultiple: maxChoices > 1,
              maxChoices: maxChoices,
              votersCount: votersCount,
              expireText: expireText,
              options: options,
              isVoted: isClosed || node.text.contains('您已经投过票'),
              isClosed: isClosed,
              canVote: !isClosed && !node.text.contains('点击登录'),
              loginRequired: node.text.contains('点击登录'),
            ),
          );
          continue;
        }

        // 0. 回帖奖励专属卡片 (.comiis_htjl, .rushreply)
        if (node.classes.contains('comiis_htjl') ||
            node.classes.contains('rushreply') ||
            (node.classes.contains('bg_h') && innerText.contains('奖励'))) {
          final totalM = RegExp(r'总共奖励\s*(\d+)').firstMatch(innerText);
          final totalReward = totalM != null
              ? int.tryParse(totalM.group(1)!) ?? 0
              : 0;
          final perM =
              RegExp(r'回复本帖可获得\s*(\d+)').firstMatch(innerText) ??
              RegExp(r'回帖奖励\s*\+(\d+)').firstMatch(innerText);
          final perReplyReward = perM != null
              ? int.tryParse(perM.group(1)!) ?? 0
              : 0;
          final limitM = RegExp(r'每人限\s*(\d+)\s*次').firstMatch(innerText);
          final limitCount = limitM != null
              ? int.tryParse(limitM.group(1)!) ?? 1
              : 1;

          blocks.add(
            ReplyRewardBlock(
              totalReward: totalReward,
              perReplyReward: perReplyReward,
              limitCount: limitCount,
              rawText: innerText.replaceAll('&nbsp;', ' ').trim(),
            ),
          );
          continue;
        }

        // 0. 辩论帖专属卡片 (.comiis_debate, .debate)
        if (node.classes.contains('comiis_debate') ||
            tag == 'table' && node.classes.contains('debate')) {
          final affirm =
              node.querySelector('.square, .affirm')?.text.trim() ?? '正方观点';
          final negat =
              node.querySelector('.opponent, .negat')?.text.trim() ?? '反方观点';
          blocks.add(DebateBlock(affirmpoint: affirm, negatpoint: negat));
          continue;
        }

        // 0. 悬赏问答专属卡片 (.comiis_xstop, .rwd, .reward, .comiis_reward)
        if (node.classes.contains('comiis_xstop') ||
            node.classes.contains('comiis_reward') ||
            node.classes.contains('rwd') ||
            (node.classes.contains('bg_h') && innerText.contains('悬赏'))) {
          final priceM = RegExp(r'悬赏\s*(\d+)').firstMatch(innerText);
          final price = priceM != null
              ? int.tryParse(priceM.group(1)!) ?? 0
              : 0;
          final unitM = RegExp(
            r'悬赏\s*\d+\s*([^\r\n0-9]+?)(?:我来回答|$)',
          ).firstMatch(innerText);
          final unit = unitM?.group(1)?.trim() ?? '粒铁粒';
          final msgM = RegExp(r'您的回答被采纳后将获得[^\r\n]+').firstMatch(innerText);
          final msg =
              msgM?.group(0) ?? (price > 0 ? '您的回答被采纳后将获得$price$unit' : null);
          final isSolved =
              innerText.contains('已解决') || innerText.contains('最佳答案');
          blocks.add(
            BountyBlock(
              price: price,
              unit: unit,
              message: msg,
              isSolved: isSolved,
            ),
          );
          continue;
        }

        // 1. 引用块
        if (tag == 'blockquote' || node.classes.contains('quote')) {
          var author = '引用';
          var quoteContent = node.innerHtml;
          final quoteM = RegExp(
            r'\[quote\](?:([^:]+):)?([\s\S]*?)\[/quote\]',
          ).firstMatch(innerText);
          if (quoteM != null) {
            author = quoteM.group(1)?.trim() ?? author;
          }
          blocks.add(QuoteBlock(author: author, contentHtml: quoteContent, align: nodeAlign));
          continue;
        }

        // 2. 代码块
        if (tag == 'pre' ||
            tag == 'code' ||
            node.classes.contains('blockcode') ||
            node.classes.contains('comiis_blockcode')) {
          // 语言从 class 提取（highlight.js 的 language-xxx）
          final rawClass = node.attributes['class'] ?? '';
          final langM = RegExp(
            r'language-([a-zA-Z0-9+#]+)',
          ).firstMatch(rawClass);
          final language = langM?.group(1) ?? '';
          blocks.add(CodeBlock(code: innerText, language: language, align: nodeAlign));
          continue;
        }

        // 3. 折叠内容 (Discuz spoiler / details / collapse / showhide)
        if (tag == 'details' ||
            node.classes.contains('spoiler') ||
            node.classes.contains('collapse') ||
            node.classes.contains('showhide')) {
          final summaryEl = node.querySelector(
            'summary, .spoilerheader, .spoiler-title, .title, input.yc, h4',
          );
          var title =
              summaryEl?.attributes['value'] ??
              summaryEl?.text.trim() ??
              '折叠内容（点击展开）';
          if (title.isEmpty) title = '折叠内容（点击展开）';

          final bodyEl = node.querySelector('.spoilerbody') ?? node;
          final cloned = (bodyEl == node ? node.clone(true) : bodyEl).clone(
            true,
          );
          cloned
              .querySelectorAll('summary, .spoilerheader, input.yc')
              .forEach((e) => e.remove());
          final contentHtml = cloned.innerHtml.trim();
          blocks.add(
            SpoilerBlock(
              title: title,
              contentHtml: contentHtml.isNotEmpty
                  ? contentHtml
                  : node.innerHtml,
            ),
          );
          continue;
        }

        // 4. 数据表格
        if (tag == 'table') {
          final directTrs = <html_dom.Element>[];
          for (final child in node.children) {
            if (child.localName == 'tr') {
              directTrs.add(child);
            } else if (child.localName == 'tbody' ||
                child.localName == 'thead') {
              for (final tr in child.children) {
                if (tr.localName == 'tr') directTrs.add(tr);
              }
            }
          }
          final hasTh = directTrs.any((tr) => tr.querySelector('th') != null);
          int maxCols = 0;
          for (final tr in directTrs) {
            final colCount = tr.children
                .where((c) => c.localName == 'td' || c.localName == 'th')
                .length;
            if (colCount > maxCols) maxCols = colCount;
          }

          // 核心判断：当且仅当所有行都只有 <= 1 列（且无多列 th）时，属于 Discuz 单列排版卡片/嵌套边框，必须展开为自适应正常图文流
          final isLayoutTable = !hasTh && maxCols <= 1;

          if (isLayoutTable) {
            if (directTrs.isNotEmpty) {
              for (final tr in directTrs) {
                for (final cell in tr.children.where(
                  (c) => c.localName == 'td' || c.localName == 'th',
                )) {
                  blocks.addAll(parseStructuredBlocks(cell, inheritedAlign: nodeAlign));
                }
              }
            } else {
              for (final child in node.children) {
                blocks.addAll(parseStructuredBlocks(child, inheritedAlign: nodeAlign));
              }
            }
            continue;
          }

          if (maxCols >= 2 || hasTh) {
            final headers = <String>[];
            final rows = <List<String>>[];
            for (final tr in directTrs) {
              final ths = tr.children.where((c) => c.localName == 'th');
              if (ths.isNotEmpty) {
                for (final th in ths) {
                  headers.add(
                    th.innerHtml.trim().isNotEmpty
                        ? th.innerHtml.trim()
                        : th.text.trim(),
                  );
                }
              }
              final tds = tr.children.where((c) => c.localName == 'td');
              if (tds.isNotEmpty) {
                final cells = <String>[];
                for (final td in tds) {
                  cells.add(
                    td.innerHtml.trim().isNotEmpty
                        ? td.innerHtml.trim()
                        : td.text.trim(),
                  );
                }
                if (cells.isNotEmpty) rows.add(cells);
              }
            }
            if (headers.isNotEmpty || rows.isNotEmpty) {
              blocks.add(TableBlock(headers: headers, rows: rows, align: nodeAlign));
              continue;
            }
          }
        }

        // 5. 视频与内嵌多媒体
        if (tag == 'iframe' || tag == 'video' || tag == 'embed') {
          var rawSrc = node.attributes['src'] ??
              node.attributes['data-src'] ??
              node.querySelector('source')?.attributes['src'] ??
              '';
          final src = _absolute(rawSrc) ?? '';
          if (src.isNotEmpty) {
            final isAudioStream = src.contains('.mp3') ||
                src.contains('.m4a') ||
                src.contains('.wav') ||
                src.contains('.ogg') ||
                src.contains('.flac') ||
                src.contains('.aac');
            final isNetEase =
                src.contains('music.163.com') || src.contains('163.com');

            if (isAudioStream || isNetEase) {
              blocks.add(
                AudioBlock(
                  src: src,
                  title: innerText.isNotEmpty
                      ? innerText
                      : (isNetEase ? '网易云音乐' : '音频文件'),
                  align: nodeAlign,
                ),
              );
              continue;
            }

            final isBili =
                src.contains('bilibili.com') || src.contains('b23.tv');
            final bvidM = RegExp(
              r'(BV[a-zA-Z0-9]{10})',
              caseSensitive: false,
            ).firstMatch(src);
            final aidM = RegExp(r'aid=(\d+)').firstMatch(src);
            blocks.add(
              VideoBlock(
                src: src,
                isBilibili: isBili,
                bvid: bvidM?.group(1),
                aid: aidM?.group(1),
                align: nodeAlign,
              ),
            );
            continue;
          }
        }

        // 6. 音频 (audio 标签与 source 标签)
        if (tag == 'audio' ||
            node.classes.contains('discuz_audio') ||
            (tag == 'a' && node.classes.contains('discuz_audio'))) {
          var rawSrc = node.attributes['src'] ??
              node.attributes['href'] ??
              node.querySelector('source')?.attributes['src'] ??
              '';
          final src = _absolute(rawSrc) ?? '';
          if (src.isNotEmpty) {
            blocks.add(
              AudioBlock(
                src: src,
                title: innerText.isNotEmpty && !innerText.contains('播放音频')
                    ? innerText
                    : '音频文件',
                align: nodeAlign,
              ),
            );
            continue;
          }
        }

        // 7. 屏蔽/封禁/审核中/锁定状态
        if (innerText.contains('作者被禁止或删除') ||
            innerText.contains('内容自动屏蔽') ||
            innerText.contains('该帖被管理员或版主屏蔽') ||
            innerText.contains('该帖正在审核中') ||
            node.classes.contains('shield') ||
            (node.classes.contains('locked') &&
                (innerText.contains('屏蔽') ||
                    innerText.contains('审核') ||
                    innerText.contains('锁定')))) {
          var reason = innerText.trim();
          if (reason.isEmpty) reason = '提示: 作者被禁止或删除 内容自动屏蔽';
          var iconType = 'shielded';
          if (reason.contains('作者被禁止或删除') || reason.contains('封禁')) {
            iconType = 'banned';
          } else if (reason.contains('审核')) {
            iconType = 'review';
          } else if (reason.contains('锁定')) {
            iconType = 'locked';
          }
          blocks.add(ShieldBlock(reason: reason, iconType: iconType));
          continue;
        }

        // 7.1 隐藏内容提示
        if (node.classes.contains('locked') ||
            node.classes.contains('comiis_hide') ||
            innerText.contains('回复可见') ||
            innerText.contains('隐藏的内容')) {
          blocks.add(
            HideBlock(
              reason: innerText.isNotEmpty ? innerText : '本帖隐藏的内容需要回复才可以浏览',
            ),
          );
          continue;
        }

        // 8. 独占图片 / 图片包装容器 (ignore_js_op, div[align="center"] 包裹的图片, span.comiis_postimg, div.postimg, a.zoom 等)
        final imgEl = tag == 'img'
            ? node
            : ((tag == 'ignore_js_op' ||
                        node.querySelector('ignore_js_op') != null ||
                        tag == 'div' ||
                        tag == 'span' ||
                        tag == 'p' ||
                        tag == 'center') &&
                    node.querySelector('img') != null &&
                    (innerText.isEmpty ||
                        node.children.every((c) =>
                            c.localName == 'img' ||
                            c.localName == 'br' ||
                            c.localName == 'a' ||
                            c.localName == 'ignore_js_op' ||
                            c.localName == 'div' ||
                            c.classes.contains('tip') ||
                            c.classes.contains('aimg_tip')))
                ? node.querySelector('img')
                : null);
        if (imgEl != null) {
          var rawSrc = imgEl.attributes['comiis_loadimages'] ?? '';
          if (rawSrc.isEmpty ||
              rawSrc.contains('none.png') ||
              rawSrc.contains('spacer.gif')) {
            rawSrc = imgEl.attributes['file'] ?? '';
          }
          if (rawSrc.isEmpty ||
              rawSrc.contains('none.png') ||
              rawSrc.contains('spacer.gif')) {
            rawSrc = imgEl.attributes['zoomfile'] ?? '';
          }
          if (rawSrc.isEmpty ||
              rawSrc.contains('none.png') ||
              rawSrc.contains('spacer.gif')) {
            rawSrc = imgEl.attributes['data-src'] ?? '';
          }
          if (rawSrc.isEmpty ||
              rawSrc.contains('none.png') ||
              rawSrc.contains('spacer.gif')) {
            rawSrc = imgEl.attributes['src'] ?? '';
          }
          if (rawSrc.isNotEmpty &&
              !rawSrc.contains('none.png') &&
              !rawSrc.contains('spacer.gif')) {
            final src = _absolute(rawSrc);
            if (src != null && src.isNotEmpty) {
              final isEmoji =
                  src.contains('static/image/smiley/') ||
                  src.contains('post/smile') ||
                  imgEl.attributes.containsKey('smilieid');
              if (isEmoji) {
                // 表情小图保留在 TextBlock 内，由富文本行内渲染引擎处理，避免打断连续行内句子排版
                _appendOrMergeTextBlock(blocks, outerHtml, align: nodeAlign);
                continue;
              }
              blocks.add(
                ImageBlock(
                  src: src,
                  alt: imgEl.attributes['alt'],
                  isEmoji: false,
                  align: nodeAlign,
                ),
              );
              continue;
            }
          }
        }

        // 9. 网盘下载链接与提取码识别
        final netdiskMatch = RegExp(
          r'(https?://(?:pan\.baidu\.com|www\.123pan\.com|pan\.quark\.cn|[a-zA-Z0-9]+\.lanzou[a-z]\.com)/[^\s"<>]+)[\s\S]*?(?:提取码|密码)[:：\s]*([a-zA-Z0-9]{4,6})?',
          caseSensitive: false,
        ).firstMatch(innerText);
        if (netdiskMatch != null) {
          final url = netdiskMatch.group(1)!;
          final code = netdiskMatch.group(2) ?? '';
          var panName = '网盘下载';
          if (url.contains('baidu')) panName = '百度网盘';
          if (url.contains('123pan')) panName = '123 云盘';
          if (url.contains('quark')) panName = '夸克网盘';
          if (url.contains('lanzou')) panName = '蓝奏云';
          blocks.add(
            NetdiskBlock(
              panName: panName,
              url: url,
              extractCode: code,
              align: nodeAlign,
            ),
          );
        }

        // 10. 附件下载识别（支持移动端 .comiis_attach、PC 端 dl.tattl / p.attnm / .attach_nopermission / a[href*="attachment"] / a[href*="aid="] / a[href*="klpbbs_download"] / a[href*="download.php"]）
        // 排除图片自带的 ignore_js_op 下载浮层
        final hasImageOrIgnoreJsOp = node.querySelector('ignore_js_op') != null ||
            node.querySelector('img.zoom, img[aid]') != null ||
            tag == 'ignore_js_op' ||
            tag == 'img';

        final attachA = !hasImageOrIgnoreJsOp
            ? (node.querySelector(
                  'a[href*="mod=attachment"], a[href*="attachment.php"], a[href*="aid="], a[href*="klpbbs_download"], a[href*="download.php"], a[href*="attach"]',
                ) ??
                (node.localName == 'a' &&
                        (node.attributes['href']?.contains('attach') == true ||
                            node.attributes['href']?.contains('aid=') == true ||
                            node.attributes['href']?.contains('download') == true)
                    ? node
                    : null))
            : null;

        final isAttachNode = !hasImageOrIgnoreJsOp &&
            (node.classes.any((c) => c.contains('attach')) ||
                node.id.contains('attach') ||
                node.querySelector(
                      '.attach_tit, .attnm, .tattl, .attach_size, .att_price, .attach_price',
                    ) !=
                    null ||
                attachA != null);

        if (isAttachNode && attachA != null) {
          final href = _absolute(attachA.attributes['href']) ?? '';
          if (href.isNotEmpty) {
            // 文件名：优先 .attach_tit span，其次 attnm a，其次 attachA 文本
            var rawName =
                node.querySelector('.attach_tit span')?.text.trim() ??
                node
                    .querySelector('.attnm a, p.attnm a, span[id^="attach_"] a')
                    ?.text
                    .trim() ??
                attachA.text.trim();
            if (rawName.isEmpty ||
                rawName == '下载' ||
                rawName == '点击下载' ||
                rawName.length < 2) {
              final clone = node.clone(true);
              clone
                  .querySelectorAll(
                    '.attach_size, .attach_tit em, .attach_tit img, .att_price, .attach_price, span.xg1',
                  )
                  .forEach((e) => e.remove());
              rawName = clone.text.trim();
            }
            final name = _cleanAttachmentName(rawName);

            final iconEl = node.querySelector(
              '.attach_tit img, img[src*="filetype"], img[src*="attach"]',
            );
            final iconUrl = _absolute(iconEl?.attributes['src']);
            final uploadTime = _formatUploadTime(
              node
                      .querySelector('.attach_tit em, .attnm em, span.xg1')
                      ?.text
                      .replaceAll('&nbsp;', ' ')
                      .replaceAll(RegExp(r'上传$'), '')
                      .trim() ??
                  '',
            );
            final sizeRaw =
                node
                    .querySelector('.attach_size, span.xg1, p.attnm, .tattl')
                    ?.text ??
                '';
            final sizeM = RegExp(
              r'([\d.]+\s*(?:KB|MB|GB|B|Bytes))',
              caseSensitive: false,
            ).firstMatch(sizeRaw);
            final sizeText = sizeM?.group(1);
            final downM = RegExp(r'下载次数[:：]?\s*([\d,]+)').firstMatch(sizeRaw);
            final downloadCount = downM == null
                ? null
                : int.tryParse(downM.group(1)!.replaceAll(',', ''));
            final priceEl = node.querySelector(
              '.attach_price, .att_price, em.f_a',
            );
            final priceText = priceEl?.text.trim();

            blocks.add(
              AttachmentBlock(
                name: name,
                url: href,
                iconUrl: iconUrl,
                sizeText: sizeText,
                priceText: priceText,
                uploadTime: uploadTime,
                downloadCount: downloadCount,
                align: nodeAlign,
              ),
            );
            continue;
          }
        }

        // 如果内部包含独立 iframe/video/embed，拆成视频区块
        final subMedias = node.querySelectorAll('iframe, video, embed');
        if (subMedias.isNotEmpty && node.text.trim().isEmpty) {
          for (final media in subMedias) {
            final src =
                _absolute(
                  media.attributes['src'] ?? media.attributes['data-src'],
                ) ??
                '';
            if (src.isEmpty) continue;
            final isBili =
                src.contains('bilibili.com') || src.contains('b23.tv');
            final bvidM = RegExp(
              r'(BV[a-zA-Z0-9]{10})',
              caseSensitive: false,
            ).firstMatch(src);
            final aidM = RegExp(r'aid=(\d+)').firstMatch(src);
            blocks.add(
              VideoBlock(
                src: src,
                isBilibili: isBili,
                bvid: bvidM?.group(1),
                aid: aidM?.group(1),
                align: nodeAlign,
              ),
            );
          }
          continue;
        }

        // 通用容器元素（div/p/span/font/li/ul/ol/center/section/article/header/main等）
        // 如果内部包含富媒体（img/spoiler/blockquote/iframe/table 等），
        // 递归展开子节点解析，并向下传递继承的对齐属性，而不是整体降级为 TextBlock。
        final containerTags = {
          'div',
          'p',
          'span',
          'font',
          'li',
          'ul',
          'ol',
          'center',
          'section',
          'article',
          'header',
          'footer',
          'main',
          'aside',
          'figure',
          'figcaption',
          'strong',
          'b',
          'em',
          'i',
          'u',
          'a',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
          'td',
          'th',
          'tr',
          'tbody',
          'thead',
          'tfoot',
        };
        if (containerTags.contains(tag)) {
          // 检测是否有富内容子元素值得递归展开（排除行内表情图片）
          final hasRichChildren = node.querySelector(
                'iframe, video, embed, audio, .spoiler, .collapse, .showhide, blockquote, .quote, pre, code, .blockcode, .comiis_blockcode, table, .locked, .comiis_hide, .comiis_postimg, ignore_js_op',
              ) != null ||
              node.querySelectorAll('img').any((img) {
                final src = img.attributes['src'] ??
                    img.attributes['file'] ??
                    img.attributes['zoomfile'] ??
                    img.attributes['comiis_loadimages'] ??
                    '';
                final isSmiley = src.contains('static/image/smiley/') ||
                    src.contains('post/smile') ||
                    img.attributes.containsKey('smilieid');
                return !isSmiley;
              });

          if (hasRichChildren && node.children.isNotEmpty) {
            // 递归展开此容器的所有子节点（保持对齐方式向下传递）
            blocks.addAll(parseStructuredBlocks(node, inheritedAlign: nodeAlign));
            continue;
          }

          // 纯文本/行内容器（没有富媒体），作为 TextBlock 保留
          if (innerText.isNotEmpty || node.querySelector('img') != null) {
            _appendOrMergeTextBlock(blocks, outerHtml, align: nodeAlign);
          }
          continue;
        }

        // 非容器元素的最终 fallback
        if (innerText.isNotEmpty || node.querySelector('img') != null) {
          _appendOrMergeTextBlock(blocks, outerHtml, align: nodeAlign);
        }
      }
    }

    if (blocks.isEmpty && targetEl.innerHtml.trim().isNotEmpty) {
      blocks.add(TextBlock(targetEl.innerHtml, align: currentAlign));
    }

    return blocks;
  }

  static void _appendOrMergeTextBlock(
    List<PostBlock> blocks,
    String html, {
    String? align,
  }) {
    if (blocks.isNotEmpty && blocks.last is TextBlock) {
      final last = blocks.removeLast() as TextBlock;
      if (last.align == align) {
        blocks.add(TextBlock('${last.html}$html', align: align));
      } else {
        blocks.add(last);
        blocks.add(TextBlock(html, align: align));
      }
    } else {
      blocks.add(TextBlock(html, align: align));
    }
  }

  /// 将 Discuz BBCode 转换为 HTML 以便富文本与个性签名 100% 精准渲染
  static String bbcodeToHtml(String text) {
    if (text.isEmpty) return '';
    var html = text;

    // 预清理并处理 HTML 特殊转义（避免属性中的双引号被截断）
    html = html
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');

    // 循环处理可能嵌套的标签（最多循环 3 轮以展开内嵌标签）
    for (var i = 0; i < 3; i++) {
      final prev = html;

      // 基础文字修饰
      html = html.replaceAllMapped(
        RegExp(r'\[b\]([\s\S]*?)\[/b\]', caseSensitive: false),
        (m) => '<b>${m[1]}</b>',
      );
      html = html.replaceAllMapped(
        RegExp(r'\[i\]([\s\S]*?)\[/i\]', caseSensitive: false),
        (m) => '<i>${m[1]}</i>',
      );
      html = html.replaceAllMapped(
        RegExp(r'\[u\]([\s\S]*?)\[/u\]', caseSensitive: false),
        (m) => '<u>${m[1]}</u>',
      );
      html = html.replaceAllMapped(
        RegExp(r'\[s\]([\s\S]*?)\[/s\]', caseSensitive: false),
        (m) => '<s>${m[1]}</s>',
      );

      // 颜色与背景色（支持带引号与不带引号）
      html = html.replaceAllMapped(
        RegExp(
          r'\[color=["\x27]?([#a-zA-Z0-9]+)["\x27]?\]([\s\S]*?)\[/color\]',
          caseSensitive: false,
        ),
        (m) => '<font color="${m[1]}">${m[2]}</font>',
      );
      html = html.replaceAllMapped(
        RegExp(
          r'\[backcolor=["\x27]?([#a-zA-Z0-9]+)["\x27]?\]([\s\S]*?)\[/backcolor\]',
          caseSensitive: false,
        ),
        (m) => '<span style="background-color: ${m[1]}">${m[2]}</span>',
      );

      // 字体与字号
      html = html.replaceAllMapped(
        RegExp(
          r'\[font=["\x27]?([^\]"\x27]+)["\x27]?\]([\s\S]*?)\[/font\]',
          caseSensitive: false,
        ),
        (m) => '<font face="${m[1]}">${m[2]}</font>',
      );
      html = html.replaceAllMapped(
        RegExp(
          r'\[size=["\x27]?([0-9]+(?:px|pt)?)["\x27]?\]([\s\S]*?)\[/size\]',
          caseSensitive: false,
        ),
        (m) {
          var sizeVal = m[1]!;
          final numVal = int.tryParse(sizeVal);
          if (numVal != null && numVal <= 7) {
            const map = {
              1: '11px',
              2: '13px',
              3: '15px',
              4: '17px',
              5: '20px',
              6: '24px',
              7: '30px',
            };
            sizeVal = map[numVal] ?? '${numVal * 3}px';
          } else if (numVal != null) {
            sizeVal = '${numVal}px';
          }
          return '<span style="font-size: $sizeVal">${m[2]}</span>';
        },
      );

      // 链接与图片
      html = html.replaceAllMapped(
        RegExp(
          r'\[url=["\x27]?([^\]"\x27]+)["\x27]?\]([\s\S]*?)\[/url\]',
          caseSensitive: false,
        ),
        (m) => '<a href="${m[1]}">${m[2]}</a>',
      );
      html = html.replaceAllMapped(
        RegExp(r'\[url\]([\s\S]*?)\[/url\]', caseSensitive: false),
        (m) => '<a href="${m[1]}">${m[1]}</a>',
      );
      html = html.replaceAllMapped(
        RegExp(r'\[img(?:=[^\]]*)?\]([\s\S]*?)\[/img\]', caseSensitive: false),
        (m) => '<img src="${(m[1] ?? '').trim()}" />',
      );

      // 对齐与排版
      html = html.replaceAllMapped(
        RegExp(
          r'\[align=(left|center|right)\]([\s\S]*?)\[/align\]',
          caseSensitive: false,
        ),
        (m) => '<div align="${m[1]}">${m[2]}</div>',
      );
      html = html.replaceAllMapped(
        RegExp(r'\[quote\]([\s\S]*?)\[/quote\]', caseSensitive: false),
        (m) => '<blockquote>${m[1]}</blockquote>',
      );
      html = html.replaceAllMapped(
        RegExp(r'\[code\]([\s\S]*?)\[/code\]', caseSensitive: false),
        (m) => '<code>${m[1]}</code>',
      );
      html = html.replaceAllMapped(
        RegExp(
          r'\[spoiler(?:=([^\]]*))?\]([\s\S]*?)\[/spoiler\]',
          caseSensitive: false,
        ),
        (m) =>
            '<details><summary>${m[1]?.isNotEmpty == true ? m[1] : '点击展开折叠内容'}</summary>${m[2]}</details>',
      );

      if (html == prev) break;
    }

    // 音频与多媒体
    html = html.replaceAllMapped(
      RegExp(
        r'\[audio(?:=[^\]]*)?\](.*?)\[/audio\]',
        caseSensitive: false,
        dotAll: true,
      ),
      (m) => '<a class="discuz_audio" href="${m[1]}">🎵 播放音频</a>',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[music\](.*?)\[/music\]', caseSensitive: false, dotAll: true),
      (m) =>
          '<a class="discuz_music" href="https://music.163.com/#/song?id=${m[1]}">🎵 网易云音乐: ${m[1]}</a>',
    );
    html = html.replaceAllMapped(
      RegExp(
        r'\[(?:media|flash)(?:=[^\]]*)?\](.*?)\[/(?:media|flash)\]',
        caseSensitive: false,
        dotAll: true,
      ),
      (m) => '<a class="discuz_media" href="${m[1]}">🎬 查看视频/多媒体</a>',
    );

    // 表格与列表
    html = html.replaceAllMapped(
      RegExp(
        r'\[table(?:=([^\]]*))?\](.*?)\[/table\]',
        caseSensitive: false,
        dotAll: true,
      ),
      (m) =>
          '<table width="${m[1] ?? '100%'}" border="1" cellpadding="4" style="border-collapse:collapse">${m[2]}</table>',
    );
    html = html.replaceAll('[tr]', '<tr>').replaceAll('[/tr]', '</tr>');
    html = html.replaceAll('[td]', '<td>').replaceAll('[/td]', '</td>');
    html = html.replaceAll('[hr]', '<hr>');
    html = html.replaceAllMapped(
      RegExp(r'\[\*\]([\s\S]*?)(?=\[\*\]|\[/list\])', caseSensitive: false),
      (m) => '<li>${m[1]}</li>',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[list(?:=[^\]]*)?\]([\s\S]*?)\[/list\]', caseSensitive: false),
      (m) => '<ul>${m[1]}</ul>',
    );

    // 换行转换
    html = html.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    html = html.replaceAll('\n', '<br>');
    html = html.replaceAll('<ul><br>', '<ul>');
    html = html.replaceAll('<br></li>', '</li>');
    html = html.replaceAll('</tr><br><tr>', '</tr><tr>');
    html = html.replaceAll('<br></tr>', '</tr>');
    html = html.replaceAll('<br></table>', '</table>');

    return html;
  }

  /// 解析 Discuz 用户组权限与晋级对照页（home.php?mod=spacecp&ac=usergroup 网页真实数据）
  static UsergroupComparison parseUsergroupComparison(
    String html, {
    String? currentGroupName,
    int? currentCredits,
    String? targetGroupName,
    int? gid,
  }) {
    final doc = html_parser.parse(html);

    String myTitle = '我的主用户组';
    String mySub = '';
    String nextTitle = '晋级用户组';
    String nextSub = '';

    // 1. 查找表头与标题栏
    final ths = doc.querySelectorAll('table tr th, table.tf tr th, table.dt tr th, .colplural th, .tbmu th, tr.th th, p.tbmu, li#c2, h4');
    for (final th in ths) {
      final t = th.text.trim();
      if (t.contains('我的主用户组') || (t.contains('主用户组') && !t.contains('晋级'))) {
        myTitle = t.replaceAll(RegExp(r'\s+'), ' ');
      } else if (t.contains('晋级用户组') || (t.contains('升级') && t.contains('用户组')) || t.contains('对比') || t.contains('管理组') || t.contains('普通用户组')) {
        nextTitle = t.replaceAll(RegExp(r'\s+'), ' ');
      }
    }

    // 2. 积分与还需积分
    final notices = doc.querySelectorAll('span.notice, th.alt, .notice, p, td, div');
    for (final n in notices) {
      final t = n.text.trim();
      if (t.startsWith('积分:') || t.startsWith('积分：') || t.startsWith('💡 积分:') || t.startsWith('💡 积分：')) {
        if (mySub.isEmpty) mySub = t;
      } else if (t.contains('升级到此用户组还需积分') || t.contains('还需积分') || t.startsWith('积分下限') || t.startsWith('积分 <')) {
        if (nextSub.isEmpty) nextSub = t;
      }
    }

    final parsedCredits = currentCredits ?? (mySub.isNotEmpty ? int.tryParse(mySub.replaceAll(RegExp(r'[^0-9]'), '')) : null);
    if (nextSub.isEmpty) {
      final targetGid = gid ?? (targetGroupName != null ? _gidFromName(targetGroupName) : _gidFromName(nextTitle));
      nextSub = _creditsSubtitleFromGid(targetGid, parsedCredits);
    }

    // 3. 逐行解析权限对照表
    final items = <UsergroupPermissionItem>[];
    final rows = doc.querySelectorAll('table tr, table.tf tr, table.dt tr, .bm_c table tr');
    for (final tr in rows) {
      // 检查分类标题行（如 "基本权限"、"帖子相关" 等）
      final isCategory = tr.classes.contains('tbmu') ||
          tr.querySelector('th.tbmu, td.tbmu') != null ||
          (tr.children.length == 1 && tr.querySelector('th[colspan], td[colspan]') != null);
      if (isCategory) {
        final catTitle = tr.text.trim();
        if (catTitle.isNotEmpty && !catTitle.contains('用户组')) {
          items.add(UsergroupPermissionItem(
            title: catTitle,
            myValue: '',
            nextValue: '',
            isCategoryHeader: true,
          ));
        }
        continue;
      }

      final th = tr.querySelector('th');
      final tds = tr.querySelectorAll('td');
      if (th == null || tds.isEmpty) continue;

      final title = th.text.trim().replaceAll(':', '').replaceAll('：', '');
      if (title.isEmpty || title == '用户组' || title == '权限名称' || title == '用户级别') continue;

      String myVal = '';
      String nextVal = '';

      if (tds.isNotEmpty) {
        myVal = _cellValue(tds[0]);
      }
      if (tds.length > 1) {
        nextVal = _cellValue(tds[1]);
      }

      if (title.isNotEmpty && (myVal.isNotEmpty || nextVal.isNotEmpty)) {
        items.add(UsergroupPermissionItem(
          title: title,
          myValue: myVal,
          nextValue: nextVal,
        ));
      }
    }

    // 1. 如果未解析到表格（例如离线或未登录），直接根据目标组生成真实数据
    if (items.isEmpty) {
      return defaultUsergroupComparison(
        currentGroupName: currentGroupName,
        currentCredits: currentCredits,
        targetGroupName: targetGroupName,
        gid: gid,
      );
    }

    // 2. 如果服务端返回了表格，但服务端返回的是默认的下一级（Discuz 默认固定对比下一级晋级组），
    // 而用户明确点击了其他目标组（如 Lv.1 新手上路、限制会员、超级版主等），
    // 则使用目标组的精确权限数据进行对比，避免服务端固定返回的 Lv.5 覆盖选中的目标组！
    if (targetGroupName != null &&
        targetGroupName.isNotEmpty &&
        !nextTitle.contains(targetGroupName.replaceAll(RegExp(r'^Lv\.\d+\s*'), ''))) {
      return defaultUsergroupComparison(
        currentGroupName: currentGroupName ?? myTitle.replaceAll('我的主用户组 - ', ''),
        currentCredits: currentCredits,
        targetGroupName: targetGroupName,
        gid: gid,
      );
    }

    return UsergroupComparison(
      myGroup: UsergroupColumn(title: myTitle, subtitle: mySub),
      upgradeGroup: UsergroupColumn(title: nextTitle, subtitle: nextSub),
      permissions: items,
    );
  }

  static String _cellValue(html_dom.Element td) {
    final img = td.querySelector('img');
    if (img != null) {
      final src = img.attributes['src'] ?? '';
      final alt = img.attributes['alt'] ?? '';
      if (src.contains('data_valid') || alt.contains('允许') || alt == '✔' || alt == '1') {
        return '✔';
      }
      if (src.contains('data_invalid') || alt.contains('禁止') || alt == '✖' || alt == '0') {
        return '✖';
      }
    }
    final text = td.text.trim();
    if (text == '1' || text == '是' || text == '允许') return '✔';
    if (text == '0' || text == '否' || text == '禁止' || text == '无') return '✖';
    return text;
  }

  static const List<String> _basePermKeys = [
    '访问论坛',
    '阅读权限',
    '隐身',
    '使用搜索',
    '自定义头衔',
    '发帖不受限制',
    '允许发短消息',
    '允许加好友',
    '查看统计数据报表',
    '允许使用应用',
    '发表文章',
  ];

  static const List<String> _postPermKeys = [
    '发新话题',
    '发表回复',
    '发起投票',
    '参与投票',
    '发表悬赏',
    '发表活动',
    '发表辩论',
    '发表交易',
    '允许 @ 的人数',
    '允许设置回帖奖励',
    '允许使用标签',
    '允许创建淘专辑的数量',
    '最大签名长度',
    '签名中使用编辑器代码',
    '签名中使用 [img] 代码',
    '主题评价影响值',
    '允许参与评分',
    '允许参与点评',
    '允许使用多媒体代码',
    '允许打招呼',
    '允许表态',
    '发表留言/评论',
  ];

  static const List<String> _attachPermKeys = [
    '空间大小',
    '单张图片最大尺寸',
    '下载附件',
    '查看图片',
    '上传附件',
    '上传图片',
    '允许设置附件权限',
    '单个最大附件尺寸',
    '每天最大附件总尺寸',
    '每天最大附件数量',
    '附件类型',
  ];

  /// 苦力怕论坛 100% 真实 Discuz 用户组全量权限字典（直接从官方服务器抓取）
  static const Map<int, Map<String, String>> realUsergroupPermissions = {
    9: { // 限制会员
      '访问论坛': '✔',
      '阅读权限': '10',
      '隐身': '✖',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✖',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✖',
      '发表辩论': '✖',
      '发表交易': '✖',
      '允许 @ 的人数': '10',
      '允许设置回帖奖励': '✖',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '0',
      '最大签名长度': '100 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✖',
      '主题评价影响值': '+1',
      '允许参与评分': '✖',
      '允许参与点评': '✖',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✖',
      '单个最大附件尺寸': '5 MB',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    10: { // Lv.1 新手上路
      '访问论坛': '✔',
      '阅读权限': '10',
      '隐身': '✖',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✖',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✖',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✖',
      '发表辩论': '✖',
      '发表交易': '✖',
      '允许 @ 的人数': '10',
      '允许设置回帖奖励': '✖',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '0',
      '最大签名长度': '100 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✖',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✖',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✖',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✖',
      '单个最大附件尺寸': '50 MB',
      '每天最大附件总尺寸': '50 MB',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    11: { // Lv.2 注册会员
      '访问论坛': '✔',
      '阅读权限': '20',
      '隐身': '✖',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✖',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✖',
      '发表辩论': '✖',
      '发表交易': '✖',
      '允许 @ 的人数': '15',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '0',
      '最大签名长度': '200 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✖',
      '单个最大附件尺寸': '50 MB',
      '每天最大附件总尺寸': '50 MB',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    12: { // Lv.3 中级会员
      '访问论坛': '✔',
      '阅读权限': '30',
      '隐身': '✖',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✖',
      '发表辩论': '✔',
      '发表交易': '✖',
      '允许 @ 的人数': '20',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '300 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✖',
      '单个最大附件尺寸': '50 MB',
      '每天最大附件总尺寸': '100 MB',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    13: { // Lv.4 高级会员
      '访问论坛': '✔',
      '阅读权限': '50',
      '隐身': '✖',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✖',
      '发表辩论': '✔',
      '发表交易': '✖',
      '允许 @ 的人数': '25',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '500 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '50 MB',
      '每天最大附件总尺寸': '300 MB',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    14: { // Lv.5 金牌会员
      '访问论坛': '✔',
      '阅读权限': '70',
      '隐身': '✔',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✔',
      '发表辩论': '✔',
      '发表交易': '✖',
      '允许 @ 的人数': '30',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '1000 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '50 MB',
      '每天最大附件总尺寸': '500 MB',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    15: { // Lv.6 论坛元老
      '访问论坛': '✔',
      '阅读权限': '90',
      '隐身': '✔',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✔',
      '发表辩论': '✔',
      '发表交易': '✖',
      '允许 @ 的人数': '50',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '2000 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '50 MB',
      '每天最大附件总尺寸': '1 GB',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    1: { // 管理员
      '访问论坛': '✔',
      '阅读权限': '255',
      '隐身': '✔',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✔',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✔',
      '允许使用应用': '✔',
      '发表文章': '✔',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✔',
      '发表辩论': '✔',
      '发表交易': '✖',
      '允许 @ 的人数': '50',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '3000 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '没有限制',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    2: { // 超级版主
      '访问论坛': '✔',
      '阅读权限': '150',
      '隐身': '✔',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✔',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✔',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✔',
      '发表辩论': '✔',
      '发表交易': '✖',
      '允许 @ 的人数': '50',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '2000 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '30 MB',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    3: { // 版主
      '访问论坛': '✔',
      '阅读权限': '100',
      '隐身': '✖',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✔',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✔',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✔',
      '发表辩论': '✔',
      '发表交易': '✖',
      '允许 @ 的人数': '50',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '1500 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '30 MB',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    16: { // 实习版主
      '访问论坛': '✔',
      '阅读权限': '100',
      '隐身': '✖',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✔',
      '发表辩论': '✔',
      '发表交易': '✔',
      '允许 @ 的人数': '50',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '200 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '✖',
      '允许参与评分': '✖',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '1.95 MB',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': 'chm, pdf, zip, rar, tar, gz, bzip2, gif, jpg, jpeg, png',
    },
    17: { // 网站编辑
      '访问论坛': '✔',
      '阅读权限': '150',
      '隐身': '✔',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✔',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✔',
      '发表辩论': '✔',
      '发表交易': '✔',
      '允许 @ 的人数': '50',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '300 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '✖',
      '允许参与评分': '✖',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '1.95 MB',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': 'chm, pdf, zip, rar, tar, gz, bzip2, gif, jpg, jpeg, png',
    },
    18: { // 信息监察员
      '访问论坛': '✔',
      '阅读权限': '200',
      '隐身': '✔',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✖',
      '发帖不受限制': '✔',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✔',
      '发表辩论': '✔',
      '发表交易': '✔',
      '允许 @ 的人数': '50',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '500 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+3',
      '允许参与评分': '✖',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '没有限制',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    19: { // 审核员
      '访问论坛': '✔',
      '阅读权限': '100',
      '隐身': '✖',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✔',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✔',
      '发表辩论': '✔',
      '发表交易': '✔',
      '允许 @ 的人数': '50',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '5',
      '最大签名长度': '200 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '✖',
      '允许参与评分': '✖',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✔',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '1.95 MB',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': 'chm, pdf, zip, rar, tar, gz, bzip2, gif, jpg, jpeg, png',
    },
    22: { // SVIP
      '访问论坛': '✔',
      '阅读权限': '80',
      '隐身': '✔',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✖',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✔',
      '发表辩论': '✔',
      '发表交易': '✖',
      '允许 @ 的人数': '50',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '0',
      '最大签名长度': '2000 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✖',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✖',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '50 MB',
      '每天最大附件总尺寸': '300 MB',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    21: { // VIP
      '访问论坛': '✔',
      '阅读权限': '60',
      '隐身': '✔',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✔',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✔',
      '查看统计数据报表': '✖',
      '允许使用应用': '✖',
      '发表文章': '✖',
      '发新话题': '✔',
      '发表回复': '✔',
      '发起投票': '✔',
      '参与投票': '✔',
      '发表悬赏': '✔',
      '发表活动': '✖',
      '发表辩论': '✔',
      '发表交易': '✖',
      '允许 @ 的人数': '40',
      '允许设置回帖奖励': '✔',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '0',
      '最大签名长度': '1000 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '+1',
      '允许参与评分': '✔',
      '允许参与点评': '✖',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✔',
      '允许表态': '✖',
      '发表留言/评论': '✔',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✔',
      '单个最大附件尺寸': '50 MB',
      '每天最大附件总尺寸': '100 MB',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    20: { // QQ游客
      '访问论坛': '✔',
      '阅读权限': '1',
      '隐身': '✖',
      '使用搜索': '允许搜索帖子内容',
      '自定义头衔': '✖',
      '发帖不受限制': '✖',
      '允许发短消息': '✖',
      '允许加好友': '✖',
      '查看统计数据报表': '✖',
      '允许使用应用': '✖',
      '发表文章': '✖',
      '发新话题': '✖',
      '发表回复': '✖',
      '发起投票': '✖',
      '参与投票': '✖',
      '发表悬赏': '✖',
      '发表活动': '✖',
      '发表辩论': '✖',
      '发表交易': '✖',
      '允许 @ 的人数': '0',
      '允许设置回帖奖励': '✖',
      '允许使用标签': '✖',
      '允许创建淘专辑的数量': '0',
      '最大签名长度': '50 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✖',
      '主题评价影响值': '+1',
      '允许参与评分': '✖',
      '允许参与点评': '✔',
      '允许使用多媒体代码': '✖',
      '允许打招呼': '✖',
      '允许表态': '✖',
      '发表留言/评论': '✖',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✖',
      '查看图片': '✖',
      '上传附件': '✖',
      '上传图片': '✖',
      '允许设置附件权限': '✖',
      '单个最大附件尺寸': '没有限制',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': '✖',
    },
    8: { // 等待邮箱验证
      '访问论坛': '',
      '阅读权限': '',
      '隐身': '',
      '使用搜索': '',
      '自定义头衔': '',
      '发帖不受限制': '',
      '允许发短消息': '',
      '允许加好友': '',
      '查看统计数据报表': '',
      '允许使用应用': '',
      '发表文章': '',
      '发新话题': '',
      '发表回复': '',
      '发起投票': '',
      '参与投票': '',
      '发表悬赏': '',
      '发表活动': '',
      '发表辩论': '',
      '发表交易': '',
      '允许 @ 的人数': '',
      '允许设置回帖奖励': '',
      '允许使用标签': '',
      '允许创建淘专辑的数量': '',
      '最大签名长度': '',
      '签名中使用编辑器代码': '',
      '签名中使用 [img] 代码': '',
      '主题评价影响值': '',
      '允许参与评分': '',
      '允许参与点评': '',
      '允许使用多媒体代码': '',
      '允许打招呼': '',
      '允许表态': '',
      '发表留言/评论': '',
      '空间大小': '',
      '单张图片最大尺寸': '',
      '下载附件': '',
      '查看图片': '',
      '上传附件': '',
      '上传图片': '',
      '允许设置附件权限': '',
      '单个最大附件尺寸': '',
      '每天最大附件总尺寸': '',
      '每天最大附件数量': '',
      '附件类型': '',
    },
    7: { // 游客
      '访问论坛': '✔',
      '阅读权限': '1',
      '隐身': '✖',
      '使用搜索': '禁用搜索',
      '自定义头衔': '✖',
      '发帖不受限制': '✖',
      '允许发短消息': '✖',
      '允许加好友': '✖',
      '查看统计数据报表': '✖',
      '允许使用应用': '✔',
      '发表文章': '✖',
      '发新话题': '✖',
      '发表回复': '✖',
      '发起投票': '✖',
      '参与投票': '✖',
      '发表悬赏': '✖',
      '发表活动': '✖',
      '发表辩论': '✖',
      '发表交易': '✖',
      '允许 @ 的人数': '0',
      '允许设置回帖奖励': '✖',
      '允许使用标签': '✖',
      '允许创建淘专辑的数量': '0',
      '最大签名长度': '0 字节',
      '签名中使用编辑器代码': '✖',
      '签名中使用 [img] 代码': '✖',
      '主题评价影响值': '✖',
      '允许参与评分': '✖',
      '允许参与点评': '✖',
      '允许使用多媒体代码': '✖',
      '允许打招呼': '✖',
      '允许表态': '✖',
      '发表留言/评论': '✖',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✖',
      '上传图片': '✖',
      '允许设置附件权限': '✖',
      '单个最大附件尺寸': '没有限制',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': '✖',
    },
    6: { // 禁止 IP
      '访问论坛': '✖',
      '阅读权限': '0',
      '隐身': '✖',
      '使用搜索': '禁用搜索',
      '自定义头衔': '✖',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✖',
      '查看统计数据报表': '✖',
      '允许使用应用': '✖',
      '发表文章': '✖',
      '发新话题': '✖',
      '发表回复': '✖',
      '发起投票': '✖',
      '参与投票': '✖',
      '发表悬赏': '✖',
      '发表活动': '✖',
      '发表辩论': '✖',
      '发表交易': '✖',
      '允许 @ 的人数': '0',
      '允许设置回帖奖励': '✖',
      '允许使用标签': '✖',
      '允许创建淘专辑的数量': '0',
      '最大签名长度': '0 字节',
      '签名中使用编辑器代码': '✖',
      '签名中使用 [img] 代码': '✖',
      '主题评价影响值': '+1',
      '允许参与评分': '✖',
      '允许参与点评': '✖',
      '允许使用多媒体代码': '✖',
      '允许打招呼': '✖',
      '允许表态': '✖',
      '发表留言/评论': '✖',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✖',
      '单个最大附件尺寸': '10 MB',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    5: { // 禁止访问
      '访问论坛': '✖',
      '阅读权限': '0',
      '隐身': '✖',
      '使用搜索': '禁用搜索',
      '自定义头衔': '✖',
      '发帖不受限制': '✖',
      '允许发短消息': '✔',
      '允许加好友': '✖',
      '查看统计数据报表': '✖',
      '允许使用应用': '✖',
      '发表文章': '✖',
      '发新话题': '✖',
      '发表回复': '✖',
      '发起投票': '✖',
      '参与投票': '✖',
      '发表悬赏': '✖',
      '发表活动': '✖',
      '发表辩论': '✖',
      '发表交易': '✖',
      '允许 @ 的人数': '0',
      '允许设置回帖奖励': '✖',
      '允许使用标签': '✖',
      '允许创建淘专辑的数量': '0',
      '最大签名长度': '0 字节',
      '签名中使用编辑器代码': '✖',
      '签名中使用 [img] 代码': '✖',
      '主题评价影响值': '✖',
      '允许参与评分': '✖',
      '允许参与点评': '✖',
      '允许使用多媒体代码': '✖',
      '允许打招呼': '✖',
      '允许表态': '✖',
      '发表留言/评论': '✖',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✖',
      '单个最大附件尺寸': '10 MB',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
    4: { // 禁止发言
      '访问论坛': '✔',
      '阅读权限': '1',
      '隐身': '✖',
      '使用搜索': '禁用搜索',
      '自定义头衔': '✖',
      '发帖不受限制': '✖',
      '允许发短消息': '✖',
      '允许加好友': '✖',
      '查看统计数据报表': '✖',
      '允许使用应用': '✖',
      '发表文章': '✖',
      '发新话题': '✖',
      '发表回复': '✖',
      '发起投票': '✖',
      '参与投票': '✔',
      '发表悬赏': '✖',
      '发表活动': '✖',
      '发表辩论': '✖',
      '发表交易': '✖',
      '允许 @ 的人数': '0',
      '允许设置回帖奖励': '✖',
      '允许使用标签': '✔',
      '允许创建淘专辑的数量': '0',
      '最大签名长度': '0 字节',
      '签名中使用编辑器代码': '✔',
      '签名中使用 [img] 代码': '✔',
      '主题评价影响值': '✖',
      '允许参与评分': '✖',
      '允许参与点评': '✖',
      '允许使用多媒体代码': '✔',
      '允许打招呼': '✖',
      '允许表态': '✖',
      '发表留言/评论': '✖',
      '空间大小': '没有限制',
      '单张图片最大尺寸': '没有限制',
      '下载附件': '✔',
      '查看图片': '✔',
      '上传附件': '✔',
      '上传图片': '✔',
      '允许设置附件权限': '✖',
      '单个最大附件尺寸': '10 MB',
      '每天最大附件总尺寸': '没有限制',
      '每天最大附件数量': '没有限制',
      '附件类型': '没有限制',
    },
  };

  static int _gidFromName(String name) {
    final clean = name.replaceAll(RegExp(r'^(我的主用户组|晋级用户组|站点管理组|普通用户组|对比目标)\s*[-—–:]*\s*'), '').trim();
    if (clean.contains('限制会员') || clean == '限制会员') return 9;
    if (clean.contains('Lv.1 新手上路') || clean == 'Lv.1 新手上路') return 10;
    if (clean.contains('Lv.2 注册会员') || clean == 'Lv.2 注册会员') return 11;
    if (clean.contains('Lv.3 中级会员') || clean == 'Lv.3 中级会员') return 12;
    if (clean.contains('Lv.4 高级会员') || clean == 'Lv.4 高级会员') return 13;
    if (clean.contains('Lv.5 金牌会员') || clean == 'Lv.5 金牌会员') return 14;
    if (clean.contains('Lv.6 论坛元老') || clean == 'Lv.6 论坛元老') return 15;
    if (clean.contains('管理员') || clean == '管理员') return 1;
    if (clean.contains('超级版主') || clean == '超级版主') return 2;
    if (clean.contains('版主') || clean == '版主') return 3;
    if (clean.contains('实习版主') || clean == '实习版主') return 16;
    if (clean.contains('网站编辑') || clean == '网站编辑') return 17;
    if (clean.contains('信息监察员') || clean == '信息监察员') return 18;
    if (clean.contains('审核员') || clean == '审核员') return 19;
    if (clean.contains('SVIP') || clean == 'SVIP') return 22;
    if (clean.contains('VIP') || clean == 'VIP') return 21;
    if (clean.contains('QQ游客') || clean == 'QQ游客') return 20;
    if (clean.contains('等待邮箱验证') || clean == '等待邮箱验证') return 8;
    if (clean.contains('游客') || clean == '游客') return 7;
    if (clean.contains('禁止 IP') || clean == '禁止 IP') return 6;
    if (clean.contains('禁止访问') || clean == '禁止访问') return 5;
    if (clean.contains('禁止发言') || clean == '禁止发言') return 4;
    return 14; // 默认 Lv.5
  }

  static String _groupNameFromGid(int gid) {
    switch (gid) {
      case 9:
        return '限制会员';
      case 10:
        return 'Lv.1 新手上路';
      case 11:
        return 'Lv.2 注册会员';
      case 12:
        return 'Lv.3 中级会员';
      case 13:
        return 'Lv.4 高级会员';
      case 14:
        return 'Lv.5 金牌会员';
      case 15:
        return 'Lv.6 论坛元老';
      case 1:
        return '管理员';
      case 2:
        return '超级版主';
      case 3:
        return '版主';
      case 16:
        return '实习版主';
      case 17:
        return '网站编辑';
      case 18:
        return '信息监察员';
      case 19:
        return '审核员';
      case 22:
        return 'SVIP';
      case 21:
        return 'VIP';
      case 20:
        return 'QQ游客';
      case 8:
        return '等待邮箱验证';
      case 7:
        return '游客';
      case 6:
        return '禁止 IP';
      case 5:
        return '禁止访问';
      case 4:
        return '禁止发言';
      default:
        return 'Lv.5 金牌会员';
    }
  }

  static String _creditsSubtitleFromGid(int gid, int? currentCredits) {
    if (gid == 14 && currentCredits != null && currentCredits < 10000) {
      return '您升级到此用户组还需积分 ${10000 - currentCredits}';
    }
    if (gid == 15 && currentCredits != null && currentCredits < 50000) {
      return '您升级到此用户组还需积分 ${50000 - currentCredits}';
    }
    switch (gid) {
      case 9:
        return '积分 < 0';
      case 10:
        return '0 - 199 积分';
      case 11:
        return '200 - 999 积分';
      case 12:
        return '1000 - 4999 积分';
      case 13:
        return '5000 - 9999 积分';
      case 14:
        return '10000 - 49999 积分';
      case 15:
        return '50000+ 积分';
      case 1:
        return '站点管理组';
      case 2:
        return '站点管理组';
      case 3:
        return '站点管理组';
      case 16:
        return '站点管理组';
      case 17:
        return '站点管理组';
      case 18:
        return '站点管理组';
      case 19:
        return '站点管理组';
      case 22:
        return '尊享特权组';
      case 21:
        return '尊享特权组';
      case 20:
        return '普通用户组';
      case 8:
        return '普通用户组';
      case 7:
        return '普通用户组';
      case 6:
        return '普通用户组';
      case 5:
        return '普通用户组';
      case 4:
        return '普通用户组';
      default:
        return '';
    }
  }

  /// 真实 KLPBBS Discuz 用户组权限基准数据（动态根据目标用户组生成真实对比数据）
  static UsergroupComparison defaultUsergroupComparison({
    String? currentGroupName,
    int? currentCredits,
    String? targetGroupName,
    int? gid,
  }) {
    final targetGid = gid ?? (targetGroupName != null ? _gidFromName(targetGroupName) : 14);
    final myGid = currentGroupName != null ? _gidFromName(currentGroupName) : 13;
    final targetName = targetGroupName ?? _groupNameFromGid(targetGid);
    final myName = currentGroupName ?? _groupNameFromGid(myGid);

    final myTitle = myName.contains('主用户组') ? myName : '我的主用户组 - $myName';
    final mySub = currentCredits != null ? '积分: $currentCredits' : '积分: 6994';

    String categoryPrefix = '晋级用户组';
    if (targetGid == 1 || targetGid == 2 || targetGid == 3 || targetGid == 16 || targetGid == 17 || targetGid == 18 || targetGid == 19) {
      categoryPrefix = '站点管理组';
    } else if (targetGid == 21 || targetGid == 22 || targetGid == 20 || targetGid == 8 || targetGid == 7 || targetGid == 6 || targetGid == 5 || targetGid == 4) {
      categoryPrefix = '普通用户组';
    }

    final targetTitle = targetName.contains('用户组') || targetName.contains('组')
        ? targetName
        : '$categoryPrefix - $targetName';
    final targetSub = _creditsSubtitleFromGid(targetGid, currentCredits);

    final myPerms = realUsergroupPermissions[myGid] ?? realUsergroupPermissions[13]!;
    final targetPerms = realUsergroupPermissions[targetGid] ?? realUsergroupPermissions[14]!;

    final items = <UsergroupPermissionItem>[];

    // 1. 基本权限
    items.add(const UsergroupPermissionItem(title: '基本权限', myValue: '', nextValue: '', isCategoryHeader: true));
    for (final k in _basePermKeys) {
      items.add(UsergroupPermissionItem(
        title: k,
        myValue: myPerms[k] ?? '✖',
        nextValue: targetPerms[k] ?? '✖',
      ));
    }

    // 2. 帖子相关
    items.add(const UsergroupPermissionItem(title: '帖子相关', myValue: '', nextValue: '', isCategoryHeader: true));
    for (final k in _postPermKeys) {
      items.add(UsergroupPermissionItem(
        title: k,
        myValue: myPerms[k] ?? '✖',
        nextValue: targetPerms[k] ?? '✖',
      ));
    }

    // 3. 家园与附件相关
    items.add(const UsergroupPermissionItem(title: '家园与附件相关', myValue: '', nextValue: '', isCategoryHeader: true));
    for (final k in _attachPermKeys) {
      items.add(UsergroupPermissionItem(
        title: k,
        myValue: myPerms[k] ?? '没有限制',
        nextValue: targetPerms[k] ?? '没有限制',
      ));
    }

    return UsergroupComparison(
      myGroup: UsergroupColumn(title: myTitle, subtitle: mySub),
      upgradeGroup: UsergroupColumn(title: targetTitle, subtitle: targetSub),
      permissions: items,
    );
  }
}
