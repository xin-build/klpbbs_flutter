import '../core/discuz_task_protocol.dart';
import '../core/discuz_magic_protocol.dart';
import '../core/discuz_credit_log_protocol.dart';
import '../core/discuz_credit_balance.dart';
import 'dart:convert';
import '../core/discuz_site_stats.dart';
import '../core/discuz_horn_protocol.dart';
import '../core/discuz_medals.dart';
import '../core/discuz_credit_rules.dart';
import 'package:flutter/foundation.dart';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../core/discuz_usergroup_parser.dart';
import '../core/discuz_forum_parser.dart';
import '../core/discuz_forum_counters.dart';
import '../core/discuz_profile_parser.dart';
import '../core/discuz_post_metadata.dart';
import '../core/discuz_response.dart';
import '../core/discuz_sign_parser.dart';
import '../core/discuz_images.dart';
import '../core/discuz_thread_parser.dart';
import '../core/discuz_thread_title.dart';
import '../core/discuz_thread_types.dart';
import '../core/discuz_thread_access.dart';
import '../core/discuz_avatar_declaration.dart';
import '../core/bbcode.dart' as bbcode_lib;
import '../models/ai_summary.dart';
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
import '../models/post_edit_info.dart';
import '../models/post_floor.dart';
import '../models/sign_entry.dart';
import '../models/site_stats.dart';
import '../models/smiley.dart';
import '../models/thread_summary.dart';
import '../models/user_space.dart';
import '../models/usergroup_comparison.dart';
import '../models/thread_sort_model.dart';

typedef ThreadDetailParsed = ({
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
  bool hasExplicitFavState,
  bool isLiked,
  int? favid,
  AiSummaryData? aiSummary,
  bool isDescOrder,
  int? targetOrdertype,
  int? authorUid,
  String? author,
});

extension ThreadDetailParsedExtension on ThreadDetailParsed {
  ThreadDetailParsed copyWith({
    String? title,
    List<PostFloor>? floors,
    int? totalPages,
    int? firstAuthorCredits,
    String? publishDate,
    String? lastReplyDate,
    String? forumName,
    int? fid,
    List<String>? breadcrumbs,
    String? typeName,
    int? typeid,
    int? likes,
    int? favorites,
    int? views,
    int? replies,
    List<String>? tags,
    String? stamp,
    String? stampUrl,
    String? coverUrl,
    bool? isFavorited,
    bool? hasExplicitFavState,
    bool? isLiked,
    int? favid,
    AiSummaryData? aiSummary,
    bool? isDescOrder,
    int? targetOrdertype,
    int? authorUid,
    String? author,
  }) {
    return (
      title: title ?? this.title,
      floors: floors ?? this.floors,
      totalPages: totalPages ?? this.totalPages,
      firstAuthorCredits: firstAuthorCredits ?? this.firstAuthorCredits,
      publishDate: publishDate ?? this.publishDate,
      lastReplyDate: lastReplyDate ?? this.lastReplyDate,
      forumName: forumName ?? this.forumName,
      fid: fid ?? this.fid,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      typeName: typeName ?? this.typeName,
      typeid: typeid ?? this.typeid,
      likes: likes ?? this.likes,
      favorites: favorites ?? this.favorites,
      views: views ?? this.views,
      replies: replies ?? this.replies,
      tags: tags ?? this.tags,
      stamp: stamp ?? this.stamp,
      stampUrl: stampUrl ?? this.stampUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      isFavorited: isFavorited ?? this.isFavorited,
      hasExplicitFavState: hasExplicitFavState ?? this.hasExplicitFavState,
      isLiked: isLiked ?? this.isLiked,
      favid: favid ?? this.favid,
      aiSummary: aiSummary ?? this.aiSummary,
      isDescOrder: isDescOrder ?? this.isDescOrder,
      targetOrdertype: targetOrdertype ?? this.targetOrdertype,
      authorUid: authorUid ?? this.authorUid,
      author: author ?? this.author,
    );
  }
}

/// comiis_app（克米设计）手机模板 HTML 解析器
///
/// 结构依据逆向文档 docs/REVERSE_ENGINEERING.md §3 与 docs/API_CONTRACT.md §3。
class ComiisParser {
  /// 作者个性签名缓存（按 uid 缓存，跨楼层复用）
  static final Map<int, String> authorSigCache = {};

  /// 检查字符串是否属于日期、时间或相对时间格式（如 "2026-9-7"、"12:34"、"3天前"、"昨天"、"刚刚"）
  static bool isDateOrTime(String text) {
    final s = text.trim();
    if (s.isEmpty) return false;
    if (RegExp(r'^(刚刚|昨天|前天|今天|半小时前|\d+\s*(秒|分钟|小时|天|周|月|年)前)').hasMatch(s)) {
      return true;
    }
    if (RegExp(
            r'^\d{4}[-/\.]\d{1,2}([-/\.]\d{1,2})?(\s+\d{1,2}:\d{2}(:\d{2})?)?$')
        .hasMatch(s)) {
      return true;
    }
    if (RegExp(r'^\d{1,2}[-/\.]\d{1,2}(\s+\d{1,2}:\d{2}(:\d{2})?)?$')
        .hasMatch(s)) {
      return true;
    }
    if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(s)) {
      return true;
    }
    return false;
  }

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

  /// 将图片 URL 转绝对并自动去除低清缩略图后缀，提升为清晰原图
  static String? _image(String? url) {
    final abs = _absolute(url);
    if (abs == null) return null;
    return AppConfig.toHighResImageUrl(abs) ?? abs;
  }

  /// 头像 URL：剥离 sunju_facemall 挂件后缀 ##SJ##xxx.png，排除默认头像与占位图
  static String? _avatarUrl(String? src) {
    if (src == null || src.isEmpty) return null;
    final clean = src.split('##SJ##').first.trim();
    final lower = clean.toLowerCase();
    if (clean.isEmpty ||
        lower.contains('noavatar') ||
        lower.contains('none.gif') ||
        lower.contains('none.png') ||
        lower.contains('spacer.gif') ||
        lower.contains('static/image/common/none') ||
        lower.contains('smiley') ||
        lower.contains('smiles') ||
        lower.contains('ahome_horn/image') ||
        lower.contains('static/image/magic') ||
        lower.contains('static/image/stamp')) {
      return null;
    }
    return _absolute(clean);
  }

  /// 根据 UID 生成 Discuz UCenter 标准头像地址
  static String discuzAvatarUrl(int uid) {
    if (uid <= 0) return '';
    final formattedUid = uid.toString().padLeft(9, '0');
    final u1 = formattedUid.substring(0, 3);
    final u2 = formattedUid.substring(3, 5);
    final u3 = formattedUid.substring(5, 7);
    final u4 = formattedUid.substring(7, 9);
    return 'https://user.klpbbs.com/data/avatar/$u1/$u2/$u3/${u4}_avatar_big.jpg';
  }

  static html_dom.Element? _authorAvatarImage(
          html_dom.Element scope, String selectors) =>
      scope
          .querySelectorAll(selectors)
          .where((image) =>
              !image.classes.contains('sunju_facemall') &&
              !image.classes.contains('sj_fm_myface_mall'))
          .firstOrNull;

  static String? _authorAvatarSource(html_dom.Element? image) {
    return DiscuzAvatarDeclarations.imageSource(image);
  }

  static String? _authorAvatarFrame(html_dom.Element? image) {
    return DiscuzAvatarDeclarations.frameFromAvatar(
        image, Uri.parse(AppConfig.baseUrl));
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
  static List<({int typeid, String name})> parseThreadTypes(String html,
          {int? fid, int? selectedTypeid}) =>
      DiscuzThreadTypes.parse(html, Uri.parse(AppConfig.baseUrl),
          fid: fid, selectedTypeid: selectedTypeid);

  /// 解析勋章中心（home.php?mod=medal 支持 PC 与移动端结构，深度按真实容器解析）
  static List<MedalItem> parseMedals(String html) {
    final current = DiscuzMedals.parse(html, Uri.parse(AppConfig.baseUrl));
    if (current.isNotEmpty) return current;
    final doc = html_parser.parse(html);

    // 彻底移除页眉、页脚、侧边栏、快捷菜单、导航栏等非内容 DOM
    doc
        .querySelectorAll(
          '#nv, #toptb, #hd, #ft, #comiis_head, .comiis_head, .comiis_header, '
          '#comiis_nav, .comiis_nav, .comiis_foot, .comiis_footer, .comiis_menu, '
          '.comiis_sidenv, .comiis_sidenv_box, .comiis_fmenu, .comiis_gobtn, '
          '.comiis_lrmenu, .comiis_loginbox, script, style, header, footer',
        )
        .forEach((e) => e.remove());

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

    // 2. 移动端标准容器：.comiis_medal_box .comiis_userlist01 ul > li, .comiis_medal_box ul > li
    if (out.isEmpty) {
      for (final el in doc.querySelectorAll(
        '.comiis_medal_box ul > li, .comiis_medalbox ul > li, div.medal_list li',
      )) {
        final imgP = el.querySelector('p[id^="medal_"], div[id^="medal_"]');
        final idAttr = imgP?.attributes['id'] ?? el.attributes['id'] ?? '';
        final id = int.tryParse(idAttr.replaceFirst('medal_', ''));
        if (id == null || !seenIds.add(id)) continue;

        String name = '', desc = '', img = '', req = '人工授予';
        final imgEl = el.querySelector('img');
        if (imgEl != null) {
          final rawSrc = imgEl.attributes['comiis_loadimages'] ??
              imgEl.attributes['data-src'] ??
              imgEl.attributes['file'] ??
              imgEl.attributes['src'];
          img = _medalUrl(rawSrc);
          name = imgEl.attributes['alt'] ?? '';
        }
        final titEl = el.querySelector('p.tit, .tit, h3, h4');
        if (titEl != null && titEl.text.trim().isNotEmpty) {
          name = titEl.text.trim();
        }
        final descEl = el.querySelector('p.txt, .txt, .desc');
        if (descEl != null) {
          desc = descEl.text.trim();
        }
        final reqEl = el.querySelector('p.ybtn, .ybtn, .comiis_sendbtn');
        if (reqEl != null && reqEl.text.trim().isNotEmpty) {
          req = reqEl.text.trim();
        }
        if (name.isEmpty) name = '勋章 #$id';
        out.add(MedalItem(
          id: id,
          name: name,
          desc: desc,
          requirement: req,
          img: img,
        ));
      }
    }

    return out;
  }

  /// 解析积分变动流水记录（home.php?mod=spacecp&ac=credit&op=log 支持移动端与 PC 端）
  static List<CreditLogEntry> parseCreditLogs(String html) =>
      DiscuzCreditLogProtocol.parse(html);

  /// 解析积分基础概况（home.php?mod=spacecp&ac=credit&op=base / &mobile=2）
  static CreditBaseInfo parseCreditBase(String source) =>
      DiscuzCreditBalance.parse(source);

  /// 道具目录与权限只解析当前页面的真实字段。
  static List<MagicItem> parseMagicShop(String source) =>
      DiscuzMagicProtocol.shop(source, base: Uri.parse(AppConfig.baseUrl));

  static MagicBagInfo parseMagicBagInfo(String source, {int? defaultIron}) =>
      DiscuzMagicProtocol.bag(source, defaultIron: defaultIron);

  static List<MagicItem> parseMyMagics(String source) =>
      DiscuzMagicProtocol.mybox(source, base: Uri.parse(AppConfig.baseUrl));

  static List<MagicLogEntry> parseMagicLogs(String source,
          {String op = 'uselog'}) =>
      DiscuzMagicProtocol.logs(source, op: op);

  /// 兼容旧版解析
  static List<({int id, String name, String img, String desc})> parseMagics(
    String html,
  ) {
    final shop = parseMagicShop(html);
    return shop
        .map((m) => (id: m.id, name: m.name, img: m.img, desc: m.desc))
        .toList();
  }

  /// 任务 ID 与奖励取自详情链接所在的实际条目。
  static List<({int id, String name, String reward})> parseTasks(
          String source) =>
      DiscuzTaskProtocol.parse(source);

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

  /// 解析好友列表（精确支持 Discuz 移动端 Comiis 全结构与 PC 端结构，对齐网页截图）
  static List<FriendItem> parseFriends(String html, {int? excludeUid}) {
    if (html.isEmpty) return const [];
    final doc = html_parser.parse(html);

    // 1. 移除全局非内容节点（页头、页脚、侧边栏、浮动菜单、顶部导航、登录框等），防止误解析当前登录用户链接
    doc
        .querySelectorAll(
          '#nv, #toptb, #hd, #ft, #comiis_head, .comiis_head, .comiis_header, '
          '#comiis_nav, .comiis_nav, .comiis_foot, .comiis_footer, .comiis_menu, '
          '.comiis_sidenv, .comiis_sidenv_box, .comiis_fmenu, .comiis_gobtn, '
          '.comiis_lrmenu, .comiis_loginbox, script, style, header, footer',
        )
        .forEach((e) => e.remove());

    final out = <FriendItem>[];
    final seen = <int>{};

    // 2. 查找好友列表容器内的所有好友条目
    final candidateElements = <html_dom.Element>[];

    // 优先匹配标准列表项
    final listItems = doc.querySelectorAll(
      '.comiis_userlist li, .comiis_friend_list li, .comiis_mh_userlist li, '
      '.comiis_user_list li, .comiis_p12 li, .comiis_box li, '
      'ul#friend_ul > li, ul.buddy > li, li.bbda, div.bbda',
    );

    if (listItems.isNotEmpty) {
      candidateElements.addAll(listItems);
    } else {
      // 备用选择器：查找直接子 div 或 flex 项
      final divItems = doc.querySelectorAll(
        '.comiis_userlist > div, .comiis_friend_list > div, .comiis_mh_userlist > div, '
        '.comiis_user_list > div, .comiis_p12 > div, #friend_ul > div',
      );
      if (divItems.isNotEmpty) {
        candidateElements.addAll(divItems);
      } else {
        // 全局查找所有包含好友操作或好友头像的独立行
        final allFlex = doc.querySelectorAll('li, div.b_b, div.comiis_flex');
        for (final el in allFlex) {
          if (el.querySelector(
                  'a[href*="op=ignore"], a[href*="op=editnote"], a[href*="op=changegroup"], a[href*="space-uid-"], a[href*="mod=space&uid="]') !=
              null) {
            final subCount = el
                .querySelectorAll(
                    'a[href*="space-uid-"], a[href*="mod=space&uid="]')
                .length;
            if (subCount <= 6 && subCount >= 1) {
              candidateElements.add(el);
            }
          }
        }
      }
    }

    for (final el in candidateElements) {
      int? uid;

      // 从各类相关链接提取目标 UID
      final spaceLinks = el.querySelectorAll(
        'a[href*="space-uid-"], a[href*="mod=space&uid="], a[href*="op=editnote&uid="], '
        'a[href*="op=ignore&uid="], a[href*="op=changegroup&uid="], a[href*="ac=poke&op=send&uid="], '
        'a[href*="subop=view&touid="], a[href*="fuid="], a[href*="uid="]',
      );

      for (final a in spaceLinks) {
        final href = a.attributes['href'] ?? '';
        final m = RegExp(r'space-uid-(\d+)\.html|(?:[?&](?:u|to|f)?uid=)(\d+)')
            .firstMatch(href);
        if (m != null) {
          final parsed = int.tryParse(m.group(1) ?? m.group(2) ?? '');
          if (parsed != null && parsed > 0) {
            uid = parsed;
            break;
          }
        }
      }

      if (uid == null || uid <= 0) continue;
      if (excludeUid != null && uid == excludeUid) continue;
      if (!seen.add(uid)) continue;

      // 提取真实昵称
      String name = '';
      for (final a in spaceLinks) {
        final href = a.attributes['href'] ?? '';
        if (href.contains('op=') ||
            href.contains('subop=') ||
            href.contains('ac=poke') ||
            href.contains('ac=follow')) {
          continue;
        }
        final t = a.text.trim();
        if (t.isNotEmpty &&
            t != '好友' &&
            t != '空间' &&
            t != '个人资料' &&
            t != '分组' &&
            t != '关注' &&
            t != '取消' &&
            t != '打招呼' &&
            t != '发消息' &&
            t != '×' &&
            !t.startsWith('热度')) {
          name = t;
          break;
        }
      }

      if (name.isEmpty) {
        final h4 = el.querySelector(
            'h4 a, h4, p.title a, p.title, dt a, strong a, .f16, .f15, a.xi2');
        if (h4 != null) {
          final t = h4.text.trim();
          if (t.isNotEmpty && t != '好友' && t != '空间' && t != '个人资料') name = t;
        }
      }

      if (name.isEmpty) {
        final img = el.querySelector('img[alt]');
        final alt = img?.attributes['alt']?.trim() ?? '';
        if (alt.isNotEmpty &&
            !alt.startsWith('avatar') &&
            !alt.contains('http')) {
          name = alt;
        }
      }

      if (name.isEmpty || name.contains('http') || name.length > 30) {
        name = '坛友 $uid';
      }

      // 提取头像
      final imgEl = _authorAvatarImage(
          el,
          'div.avt img, .avatar img, img[src*="avatar"], '
          'img[data-original*="avatar"], img[data-src*="avatar"], img');
      final rawImg = _authorAvatarSource(imgEl);
      final avatar =
          _avatarUrl(rawImg) ?? AppConfig.avatarUrl(uid, size: 'middle');
      final faceUrl = _authorAvatarFrame(imgEl);

      // 提取用户组、积分、附注与时间
      String group = '';
      String credits = '';
      String note = '';
      String recentActivity = '';

      final fullText = el.text.replaceAll('\u00a0', ' ').trim();

      // 1. 优先从专门段落提取用户组 (PC 端结构: <p class="maxh">SVIP 积分数: 10130</p> 或移动端子行)
      final pEl = el.querySelector('p.maxh, p.xg1, p.sub, p.comiis_p, p');
      if (pEl != null) {
        final pText = pEl.text.replaceAll('\u00a0', ' ').trim();
        final mGrp = RegExp(r'^(.*?)(?:\s*积分[数\s:：]|\s*$)').firstMatch(pText);
        if (mGrp != null && mGrp.group(1)!.trim().isNotEmpty) {
          final candidate = mGrp.group(1)!.trim();
          if (!candidate.contains('查看资料') &&
              !candidate.contains('打招呼') &&
              !candidate.contains('去串个门') &&
              !candidate.contains('发送消息')) {
            group = candidate;
          }
        }
        final mCred = RegExp(r'积分[数\s:：]*(\d+)').firstMatch(pText);
        if (mCred != null) {
          credits = mCred.group(1)!;
        }
      }

      // 2. 若未从专用段落提取出用户组，则基于全文本进行智能匹配（涵盖 SVIP、VIP、认证开发者、管理组及各类会员组）
      if (group.isEmpty) {
        final groupM = RegExp(
          r'(SVIP|VIP|Lv\.\d+\s*[^积分\s\n]+|版主|超级版主|荣誉版主|实习版主|管理员|荣誉会员|贵宾会员|金牌会员|元老会员|中级会员|高级会员|注册会员|普通会员|认证开发者|创作者|特别嘉宾|禁止发言|等待验证会员)',
          caseSensitive: false,
        ).firstMatch(fullText);
        if (groupM != null) {
          group = groupM.group(1)!.trim();
        }
      }

      // 3. 积分补充匹配
      if (credits.isEmpty) {
        final credM = RegExp(r'积分[数\s:：]*(\d+)').firstMatch(fullText);
        if (credM != null) {
          credits = credM.group(1)!;
        }
      }

      // 附注/自定义备注匹配
      final noteM = RegExp(r'[(（]备注[：:]\s*([^()（）]+)[)）]').firstMatch(fullText);
      if (noteM != null) {
        note = noteM.group(1)!.trim();
      }

      // 时间匹配 (来访/足迹/申请时间)
      final timeM = RegExp(
        r'(\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?|\d+\s*(?:分钟|小时|天)前|刚刚)',
      ).firstMatch(fullText);
      if (timeM != null) {
        recentActivity = timeM.group(1)!;
      }

      // 是否已关注（检测页面中的 取消 / 取消关注 按钮）
      final elHtml = el.outerHtml;
      final isFollowing = elHtml.contains('取消') ||
          elHtml.contains('op=del') ||
          elHtml.contains('取消关注');

      // 在线状态检测
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
          (!hasOfflineMark &&
              (_isRecentActivity(recentActivity) ||
                  _isRecentActivity(credits) ||
                  _isRecentActivity(group)));

      out.add(
        FriendItem(
          uid: uid,
          username: _cleanTitle(name),
          avatarUrl: avatar,
          faceUrl: faceUrl,
          usergroup: _cleanTitle(group),
          credits: credits,
          isOnline: isFriendOnline,
          isFollowing: isFollowing,
          note: note,
          recentActivity: recentActivity,
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

  static const String _tidForumPrefsKey = 'persisted_tid_forum_map_v2';
  static bool _tidForumLoaded = false;
  static bool _saveScheduled = false;

  /// 加载本地持久化的 TID -> 版块名缓存
  static Future<void> loadTidForumCache() async {
    if (_tidForumLoaded) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(_tidForumPrefsKey) ?? const [];
      for (final item in list) {
        final idx = item.indexOf(':');
        if (idx <= 0) continue;
        final tid = int.tryParse(item.substring(0, idx)) ?? 0;
        final forum = item.substring(idx + 1).trim();
        if (tid > 0 && forum.isNotEmpty) {
          threadForumCache[tid] = forum;
        }
      }
      _tidForumLoaded = true;
    } catch (_) {}
  }

  /// 持久化 TID -> 版块名映射
  static Future<void> saveTidForumCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = threadForumCache.entries
          .where((e) => e.key > 0 && e.value.isNotEmpty)
          .take(1500)
          .map((e) => '${e.key}:${e.value}')
          .toList();
      await sp.setStringList(_tidForumPrefsKey, list);
    } catch (_) {}
  }

  static void _scheduleSaveTidForum() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    Future.delayed(const Duration(seconds: 3), () {
      _saveScheduled = false;
      saveTidForumCache();
    });
  }

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
        _scheduleSaveTidForum();
      }
    } else if (fid != null && fid > 0) {
      final nameByFid = getForumNameByFid(fid);
      if (nameByFid != null && nameByFid.isNotEmpty) {
        threadForumCache[tid] = nameByFid;
        _scheduleSaveTidForum();
      }
    }
  }

  /// 根据 TID 直接查询已记录的真实版块名称
  static String? getForumNameByTid(int? tid) {
    if (tid == null || tid <= 0) return null;
    return threadForumCache[tid] ?? getForumNameByFid(threadFidCache[tid]);
  }

  /// 只使用页面提供的名称、已记录的 FID 或 TID，不从主题分类猜版块。
  static String? resolveForumName({
    int? tid,
    int? fid,
    String? rawForumName,
    String? title,
    String? typeName,
  }) {
    if (rawForumName != null && rawForumName.trim().isNotEmpty) {
      final clean = rawForumName
          .replaceAll(
              RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
                  unicode: true),
              '')
          .replaceAll(RegExp(r'^[\[【\s]+|[\]】\s]+$'), '')
          .replaceAll(RegExp(r'^来自\s*'), '')
          .trim();
      if (clean.isNotEmpty && !_isGenericPortalHeader(clean)) return clean;
    }
    return getForumNameByFid(fid) ?? getForumNameByTid(tid);
  }

  /// Only normalize display characters. Dates and count words can be subjects.
  static String _cleanTitle(String title) => DiscuzThreadTitle.clean(title);

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
    if (s.contains('<table') ||
        s.contains('<tbody') ||
        s.contains('<tr') ||
        s.contains('<td')) {
      try {
        final body = html_parser.parse(s).body;
        if (body != null) {
          body.querySelectorAll('script, style').forEach((e) => e.remove());
          final tds = body.querySelectorAll('td');
          if (tds.isNotEmpty) {
            s = tds
                .map((td) => td.innerHtml.trim())
                .where((html) => html.isNotEmpty)
                .join('<br>');
          } else {
            for (final t
                in body.querySelectorAll('table, tbody, thead, tfoot, tr')) {
              t.replaceWith(html_dom.Element.html('<div>${t.innerHtml}</div>'));
            }
            s = body.innerHtml.trim();
          }
        }
      } catch (_) {}
    }
    return s;
  }

  static String _cleanSignature(String signature) =>
      cleanSignatureText(signature);

  /// 清理作者昵称：过滤统计字段，保留网站实际显示的匿名标签和数字昵称。
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
        a.contains('***') ||
        a == '阅读' ||
        a == '查看' ||
        a == '回复' ||
        a == '楼主' ||
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

  /// Discuz 官方系统审核与管理操作记录正则（全面支持绝对日期与“前天 20:02”、“3 天前”、“6 天前”等相对日期）
  static final auditNoticeRegExp = RegExp(
    r'(?:(?:本(?:主题|帖)?)?\s*由\s*[\S]+?(?:\s+于\s+[^，,。.\r\n]+?)?|本(?:主题|帖)\s*(?:于\s+[^，,。.\r\n]+?)?)\s*(?:审核通过|通过审核|审核|移动|置顶|高亮|关闭|加精|提升|分类|设置|解除|下沉)[:：\s]*',
    caseSensitive: false,
  );

  /// 通用全模式审核操作通知正则（涵盖跨行与紧邻正文各种边界）
  static final auditNoticeGeneralRegExp = RegExp(
    r'(?:(?:本(?:主题|帖)?)?\s*由\s*[\s\S]*?(?:于\s*[^，,。.\r\n]+?)?|本(?:主题|帖)\s*(?:于\s*[^，,。.\r\n]+?)?)\s*(?:审核通过|通过审核|审核|移动|置顶|高亮|关闭|加精|提升|分类|设置|解除|下沉)[:：\s]*',
    caseSensitive: false,
  );

  /// 从 HTML 或富文本中提取纯净紧凑的文本摘要，去除系统编辑标记、BBCode残留、审核通过/管理操作、多余换行与空格
  static String cleanTextSnippet(String? raw, {int maxLen = 120}) {
    if (raw == null || raw.isEmpty) return '';
    var text = raw;
    if (text.contains('<') && text.contains('>')) {
      try {
        final doc = html_parser.parseFragment(text);
        doc
            .querySelectorAll(
              'script, style, .pstatus, i.pstatus, .quote, blockquote, .attach, .comiis_attach, .locked, .comiis_hide, .comiis_modact, .modact, .psth, .modaction, .comiis_mod, .comiis_actinfo, .xg1, .xg1.y',
            )
            .forEach((e) => e.remove());
        doc.querySelectorAll('*').forEach((e) {
          final t = e.text.trim();
          if (t.contains('审核通过') || (t.contains('由') && t.contains('审核'))) {
            final afterClean =
                t.replaceAll(auditNoticeGeneralRegExp, '').trim();
            if (afterClean.isEmpty) {
              e.remove();
            } else {
              e.innerHtml =
                  e.innerHtml.replaceAll(auditNoticeGeneralRegExp, '');
            }
          }
        });
        text = doc.text ?? '';
      } catch (_) {
        text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
      }
    }
    text = text
        .replaceAll('\u200b', '')
        .replaceAll('\u200e', '')
        .replaceAll('\u200f', '')
        .replaceAll('\ufeff', '')
        .replaceAll(
            RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
                unicode: true),
            '')
        .replaceAll(auditNoticeRegExp, '')
        .replaceAll(auditNoticeGeneralRegExp, '')
        .replaceAll(
            RegExp(
                r'由\s*[\S]+?\s*于\s*[^，,。.\r\n]+?\s*(?:审核通过|通过审核|审核|移动|置顶|高亮|关闭|加精|提升|分类|设置|解除|下沉)[:：\s]*',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'本(?:主题|帖)最后由\s*[^，,。.\r\n]+?\s*编辑', caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\[attach\]\d+\[/attach\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[/?[a-zA-Z0-9_=\-\.\s\:\#\,]+\]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final puncOnly = RegExp(r'^[\s.。,，!！?？:：;；~～\-_—…]+$');
    if (puncOnly.hasMatch(text)) {
      return '';
    }
    if (text.length > maxLen) {
      text = '${text.substring(0, maxLen).trim()}...';
    }
    return text;
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
      final avatarEl = _authorAvatarImage(li, '.replyfloor_content_avatar img');
      final rawAvatar = _authorAvatarSource(avatarEl);
      final avatar = _avatarUrl(rawAvatar) ?? _absolute(rawAvatar) ?? '';
      final faceUrl = _authorAvatarFrame(avatarEl) ?? '';
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
      final isCommentShielded =
          contentHtml.contains('内容自动屏蔽') || contentHtml.contains('该帖被管理员或版主屏蔽');
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
          sourceLabel:
              li.querySelector('.replyfloor_content_from')?.text.trim() ?? '',
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
    for (final thread in DiscuzThreadParser.modern(
        html, Uri.parse(AppConfig.baseUrl),
        pageFid: pageFid)) {
      result.add(thread);
      seenTids.add(thread.tid);
      registerThread(thread.tid, fid: thread.fid, forumName: thread.forumName);
    }

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

      final title = DiscuzThreadTitle.text(a);
      if (title.isEmpty) continue;

      // 作者与 UID
      final byTds = tbody.querySelectorAll('td.by');
      final firstBy = byTds.isNotEmpty ? byTds.first : null;
      final authorA = tbody.querySelector(
            '.klp-trow-meta a[href*="uid="], .klp-trow-meta a[href*="space-uid-"], .aor a, .sub a[href*="space-"], td.by cite a, td.by a[href*="space-uid-"], td.by a[href*="uid="]',
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
        tbody
                .querySelector('td.icn a.k-av, td.avr a, .avr a')
                ?.attributes['href'] ??
            '',
      );

      // 发布时间
      final timeEl =
          tbody.querySelector('.klp-trow-date span, .klp-trow-date') ??
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

    // 1.5 现代 PC 端导读与版块流：article.k-card.feed-item, .klp-feed-list article, article.feed-item
    for (final article in cleanDoc.querySelectorAll(
      'article.feed-item, article.k-card, .klp-feed-list article, .klp-feed article',
    )) {
      final titleA = article
          .querySelector('h2.feed-title a, .feed-title a, a[href*="thread-"]');
      if (titleA == null) continue;
      final href = titleA.attributes['href'] ?? '';
      final tid = _tidFromHref(href);
      if (tid == null || !seenTids.add(tid)) continue;

      final title = DiscuzThreadTitle.text(titleA);
      if (title.isEmpty) continue;

      // 作者与 UID
      final authorA = article.querySelector(
          'a.feed-author, .feed-head a[href*="space-uid-"], .feed-head a[href*="uid="]');
      var author = _cleanAuthor(authorA?.text);
      var uid = _uidFromHref(authorA?.attributes['href'] ?? '');
      if (uid == null) {
        final avA = article
            .querySelector('.feed-head a.k-av, .feed-head a[href*="space"]');
        uid = _uidFromHref(avA?.attributes['href'] ?? '');
      }

      // 头像
      final avatarImg =
          _authorAvatarImage(article, '.feed-head img, a.k-av img');
      final faceUrl = _authorAvatarFrame(avatarImg);

      // 版块
      final forumA = article.querySelector(
          '.feed-head a[href*="forum-"], .feed-head a[href*="forumdisplay"]');
      final rawForumName = forumA?.text.trim();
      final itemFid = _extractFid(forumA?.attributes['href']) ?? pageFid;
      final resolvedForumName = resolveForumName(
        fid: itemFid,
        rawForumName: rawForumName,
        title: title,
      );

      // 发布时间
      final timeEl =
          article.querySelector('.feed-head time, .feed-time, time.k-meta');
      final timeText =
          timeEl?.text.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';

      // 摘要
      final excerptEl = article.querySelector('p.feed-excerpt, .feed-excerpt');
      final excerpt = excerptEl?.text.trim();

      // 封面
      final covers = DiscuzImages.covers(article, Uri.parse(AppConfig.baseUrl));
      final cover = covers.firstOrNull;

      // 统计数据：点赞、回复、查看
      int replies = -1;
      int views = -1;
      int likes = -1;
      final stats =
          article.querySelectorAll('.feed-foot .feed-stat, .feed-stat');
      for (final s in stats) {
        final svgUse = s.querySelector('use')?.attributes['href'] ?? '';
        final valText = s.querySelector('.k-mono, span')?.text.trim() ?? '';
        final val = int.tryParse(valText) ?? -1;
        if (svgUse.contains('thumb') || svgUse.contains('like')) {
          likes = val;
        } else if (svgUse.contains('mail') ||
            svgUse.contains('reply') ||
            s.attributes['href']?.contains('viewthread') == true) {
          replies = val;
        } else if (svgUse.contains('eye') || svgUse.contains('view')) {
          views = val;
        }
      }

      final summary = ThreadSummary(
        tid: tid,
        fid: itemFid,
        uid: uid,
        author: author,
        title: title,
        faceUrl: faceUrl,
        coverUrl: cover,
        imageUrls: covers,
        excerpt: excerpt,
        forumName: resolvedForumName,
        timeText: timeText,
        views: views,
        replies: replies,
        recommendCount: likes > 0 ? likes : 0,
      );

      registerThread(tid, fid: itemFid, forumName: resolvedForumName);
      result.add(summary);
    }

    // 2. 移动端全模板列表结构（li.forumlist_li、li.comiis_wxlist、li.comiis_mmlist、div.wzlist_noimg、div.comiis_wzlists、.comiis_mh_twlist li、li.twlist_li 等）
    final mobileItems = cleanDoc.querySelectorAll(
      '.comiis_forumlist li, li.forumlist_li, li.comiis_wxlist, li.comiis_mmlist, li.comiis_milist, li.comiis_znalist, .comiis_list li, .guide_list li, .comiis_mh_twlist li, li.twlist_li, .comiis_app_forumlist li, .comiis_mh_txtlist li, .comiis_mh_txtlist_phb li, div.wzlist_noimg, div.comiis_wzlists',
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
      final title = DiscuzThreadTitle.text(a);
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
      final title = DiscuzThreadTitle.text(a);
      if (title.isEmpty) continue;

      final parentTr = th.parent?.localName == 'tr' ? th.parent : null;
      final authorA = parentTr?.querySelector(
            'td.by cite a, td.by a[href*="space-uid-"], td.by a[href*="uid="]',
          ) ??
          th.querySelector('.aor a, .sub .aor, .by a, a[href*="space-uid-"]');
      final author = _cleanAuthor(authorA?.text);
      final uid = _uidFromHref(authorA?.attributes['href'] ?? '');

      final timeEl = parentTr?.querySelector('td.by em span, td.by em') ??
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

      if (replies <= 0) {
        final byTds = parentTr?.querySelectorAll('td.by');
        if (byTds != null && byTds.length >= 2) {
          final lastBy = byTds[1];
          final lastAuthor = lastBy.querySelector('cite a')?.text.trim() ?? '';
          final hasLastpostLink =
              lastBy.querySelector('a[href*="lastpost"]') != null;
          if (hasLastpostLink ||
              (lastAuthor.isNotEmpty && lastAuthor != author)) {
            replies = 1;
          }
        }
        final dotSep = (parentTr ?? th).querySelector('.klp-dot-sep');
        if (dotSep != null && dotSep.text.contains('回复')) {
          replies = 1;
        }
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
          replies:
              repliesM != null ? int.tryParse(repliesM.group(1)!) ?? -1 : -1,
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
        final title = DiscuzThreadTitle.text(titleEl ?? a);
        if (title.isEmpty) continue;
        final author = _cleanAuthor(
          li.querySelector('.muser .mmc, .mmc')?.text,
        );
        final uid = _uidFromHref(
          li.querySelector('.muser a, a[href*="uid="]')?.attributes['href'] ??
              '',
        );
        final timeText = li.querySelector('.mtime')?.text.trim() ?? '';
        final rawExcerpt =
            li.querySelector('.threadlist_mes')?.text.trim() ?? '';
        final cleanedExcerpt = cleanTextSnippet(rawExcerpt, maxLen: 120);
        final excerpt = cleanedExcerpt.isNotEmpty ? cleanedExcerpt : null;
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
            excerpt: excerpt,
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
    html_dom.Element? h2 = li.querySelector(
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
        if (ttl.contains('热度') || text.contains('热度') || text == '热') {
          isHot = true;
          final hc = _firstInt(ttl.isNotEmpty ? ttl : text);
          if (hc > 0) heatCount = hc;
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
      // Formatting spans/font/em are part of the subject; remove status nodes
      // by their declared role without deleting styled title fragments.
      title = DiscuzThreadTitle.text(h2);
    }
    if (title.isEmpty) {
      final attrTitle = titleA.attributes['title'] ??
          li.querySelector('a[title]')?.attributes['title'] ??
          '';
      title = _cleanTitle(attrTitle);
    }
    if (title.isEmpty) {
      final pEl = li.querySelector('.twlist_info p, .title, p, .tit');
      if (pEl != null) title = _cleanTitle(pEl.text);
    }
    if (title.isEmpty) {
      title = DiscuzThreadTitle.text(titleA);
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
    var timeText = li
            .querySelector(
              '.forumlist_li_time, .kmtime, .bottom_time, span.bottom_time, .forumlist_li_top span.f_d, .dte',
            )
            ?.text
            .trim() ??
        '';

    // 摘要：彻底清洗审核记录、管理操作、BBCode与系统编辑标记
    final bodyEl = li.querySelector('.list_body');
    String rawExcerpt = '';
    if (bodyEl != null) {
      final cleanEl = bodyEl.clone(true);
      cleanEl
          .querySelectorAll(
            '.comiis_modact, .modact, .psth, .modaction, .comiis_mod, .comiis_actinfo, .xg1, .xg1.y, .pstatus, script, style',
          )
          .forEach((e) => e.remove());
      cleanEl.querySelectorAll('*').forEach((e) {
        final t = e.text.trim();
        if (t.contains('审核通过') || (t.contains('由') && t.contains('审核'))) {
          final after = t.replaceAll(auditNoticeGeneralRegExp, '').trim();
          if (after.isEmpty) {
            e.remove();
          } else {
            e.innerHtml = e.innerHtml.replaceAll(auditNoticeGeneralRegExp, '');
          }
        }
      });
      for (final n in cleanEl.nodes) {
        if (n is html_dom.Text) {
          n.text = n.text.replaceAll(auditNoticeGeneralRegExp, '');
        }
      }
      rawExcerpt = cleanEl.text.replaceAll(auditNoticeGeneralRegExp, '').trim();
    }
    final cleanedExcerpt = cleanTextSnippet(rawExcerpt, maxLen: 120);
    final excerpt = cleanedExcerpt.isNotEmpty ? cleanedExcerpt : null;

    // 封面图：整项检索，优先 comiis_loadimages / file / zoomfile / data-src / src（支持提取最多 3 张）
    final covers = _coversFromScope(li);
    final cover = covers.isNotEmpty ? covers.first : null;

    // 赞/推荐数（综合 .zhan_list 容器、用户头像集合、文字描述与专属 DOM 节点提取）
    final zhanBox =
        li.querySelector('.zhan_list, .comiis_zhan, [class*="num-all_zhan"]');
    if (zhanBox != null) {
      final zm = RegExp(r'(\d+)\s*(?:赞|人赞|推荐)').firstMatch(zhanBox.text);
      if (zm != null) {
        final parsedLikes = int.tryParse(zm.group(1)!) ?? -1;
        if (parsedLikes >= 0) {
          recommendCount = parsedLikes;
        }
      } else {
        final avatarCount = zhanBox
            .querySelectorAll('a.imgbox, a[href*="space-uid"], img.avatar, img')
            .length;
        if (avatarCount > 0 && recommendCount <= 0) {
          recommendCount = avatarCount;
        }
      }
    }
    if (recommendCount <= 0) {
      final recSpan = li.querySelector(
        'span[id^="recommend_"], span[id^="recommendv_"], span#recommend_add, span#recommendv_add, .comiis_recommend_num, .support_num, a.voted span',
      );
      if (recSpan != null) {
        final parsed = int.tryParse(
                RegExp(r'\d+').firstMatch(recSpan.text)?.group(0) ?? '') ??
            -1;
        if (parsed >= 0) recommendCount = parsed;
      }
    }

    // 浏览/回复数（优先从真实统计组件提取，杜绝被截断的 5/6 条预览项误导）
    var views = -1, replies = -1;

    final bv = li.querySelector(
        '.bottom_views, .forumlist_li_tops .bottom_views, .wxlist_bottom .bottom_views');
    if (bv != null) {
      final ems = bv.querySelectorAll('em');
      if (ems.length >= 2) {
        views = int.tryParse(ems[0].text.trim()) ?? -1;
        replies = int.tryParse(ems[1].text.trim()) ?? -1;
      } else if (ems.length == 1) {
        views = int.tryParse(ems[0].text.trim()) ?? -1;
      }
    }

    final allCommentsA =
        li.querySelector('.reply_list a[href*="thread-"], .reply_list a.f_b');
    if (allCommentsA != null) {
      final allM = RegExp(r'全部\s*(\d+)\s*评论').firstMatch(allCommentsA.text);
      if (allM != null) {
        final total = int.tryParse(allM.group(1)!) ?? -1;
        if (total > 0) replies = total;
      }
    }

    if (views == -1) {
      final wzRead = li.querySelector('.wzlist_bottom em.y, .wzlist_bottom .y');
      if (wzRead != null) {
        final m = RegExp(r'(\d+)\s*(?:阅读|查看|浏览)').firstMatch(wzRead.text);
        if (m != null) views = int.tryParse(m.group(1)!) ?? -1;
      }
    }

    // 图文列表与导读列表 (em.kmr 内含「热52221阅读」) 提取
    final kmrEl =
        li.querySelector('em.kmr, .twlist_info em.kmr, .twlist_info em');
    if (kmrEl != null) {
      final kt = kmrEl.text.trim();
      if (kt.contains('热')) {
        isHot = true;
      }
      final vm = RegExp(r'(\d+)').firstMatch(kt);
      if (vm != null) {
        final parsed = int.tryParse(vm.group(1)!) ?? -1;
        if (parsed > 0) {
          if (views == -1) views = parsed;
          if (heatCount == -1) heatCount = parsed;
        }
      }
    }

    if (views == -1) {
      final vm =
          RegExp(r'(\d+)\s*(?:阅读|查看|浏览|次阅读|次查看|次浏览)').firstMatch(li.text);
      if (vm != null) views = int.tryParse(vm.group(1)!) ?? -1;
    }
    if (replies == -1) {
      final rm = RegExp(r'(\d+)\s*(?:回复|条回复|次回复|条评论|评论)').firstMatch(li.text);
      if (rm != null) replies = int.tryParse(rm.group(1)!) ?? -1;
    }
    final replyItems = li.querySelectorAll(
        'ul.reply_list li[id^="retid_"], .reply_list li[id^="retid_"]');
    if (replyItems.isNotEmpty && replyItems.length > replies) {
      replies = replyItems.length;
    }
    if (replies <= 0) {
      if (li.querySelector('.reply_list li') != null ||
          li.text.contains('最后回复')) {
        replies = 1;
      }
    }

    // 热度补充提取（部分列表项热度置于独立图标、小角标或尾部元数据中）
    if (heatCount == -1) {
      final heatEl = li.querySelector(
        '.comiis_hot, span[title*="热度"], img[title*="热度"], img[alt*="热度"], em[title*="热度"], .heat, span.xi1, .hot, i.b_ok',
      );
      if (heatEl != null) {
        final ht = heatEl.attributes['title'] ??
            heatEl.attributes['alt'] ??
            heatEl.text;
        final hm = RegExp(r'(\d+)').firstMatch(ht);
        if (hm != null) {
          final parsed = int.tryParse(hm.group(1)!) ?? -1;
          if (parsed > 0) {
            heatCount = parsed;
            isHot = true;
          }
        } else if (ht.contains('热') || heatEl.text.trim() == '热') {
          isHot = true;
        }
      }
    }
    if (heatCount == -1) {
      final hm = RegExp(r'热度[:：\s]*(\d+)').firstMatch(li.text) ??
          RegExp(r'(\d+)\s*(?:热度|点热度)').firstMatch(li.text);
      if (hm != null) {
        final parsed = int.tryParse(hm.group(1)!) ?? -1;
        if (parsed > 0) {
          heatCount = parsed;
          isHot = true;
        }
      }
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
      final m = RegExp(r'fid=(\d+)').firstMatch(href) ??
          RegExp(r'forum-(\d+)-\d+\.html').firstMatch(href);
      if (m != null) itemFid = int.tryParse(m.group(1)!);
    }
    itemFid ??= pageFid;

    // 提取条目内嵌版块名与发布日期（专门强化 .twlist_info span.f_d 结构解析）
    String? rawForum;
    final twSpan = li.querySelector('.twlist_info span.f_d');
    if (twSpan != null) {
      final dateMatch =
          RegExp(r'(\d{4}-\d{1,2}-\d{1,2})').firstMatch(twSpan.text);
      if (dateMatch != null && timeText.isEmpty) {
        timeText = dateMatch.group(1)!;
      }
      final clone = twSpan.clone(true);
      clone.querySelectorAll('em, i, span').forEach((e) => e.remove());
      final raw = clone.text
          .replaceAll(RegExp(r'\d{4}-\d{1,2}-\d{1,2}'), '')
          .replaceAll('|', '')
          .trim();
      if (raw.isNotEmpty && raw.length <= 20) {
        rawForum = raw;
      }
    }

    if (rawForum == null || rawForum.isEmpty) {
      final metaSpan = li.querySelector(
        '.twlist_info span:not(.f_d), .twlist_info p, .comiis_mh_txtlist span:not(.f_d)',
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

    // 强力过滤：若提取到的文本实质为日期或时间，必须剔除
    bool isDateOrTime(String s) {
      final t = s.trim();
      return RegExp(r'^\d{4}[-/年]\d{1,2}[-/月]\d{1,2}').hasMatch(t) ||
          RegExp(r'^\d{1,2}[-/月]\d{1,2}').hasMatch(t) ||
          RegExp(r'^\d{1,2}:\d{2}').hasMatch(t) ||
          t.contains('前') ||
          t.contains('昨天') ||
          t.contains('今天') ||
          t.contains('刚刚');
    }

    if (rawForum != null && isDateOrTime(rawForum)) {
      rawForum = null;
    }
    if (typeName != null && isDateOrTime(typeName)) {
      typeName = null;
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
          (fNorm.length >= 2 &&
              tNorm.length >= 2 &&
              (fNorm.contains(tNorm) || tNorm.contains(fNorm)))) {
        typeName = null;
      }
    }

    String? stamp;
    String? stampUrl;
    final stampEl = li.querySelector(
      'img[src*="stamp"], .stamp, .comiis_stamp, span.stamp, i.stamp',
    );
    if (stampEl != null) {
      final alt = stampEl.attributes['alt'] ??
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
    final avatarImg = _authorAvatarImage(
      li,
      'img.top_tximg, a.postli_top_tximg img, .wxlist_tx img, .comiis_avatar img, .avatar img, img[src*="avatar"]',
    );
    final faceUrl = _authorAvatarFrame(avatarImg);

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
      imageUrls: covers,
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
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
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
      if (first.isNotEmpty &&
          first != '下载' &&
          first != '点击下载' &&
          first != '下载附件' &&
          first.length >= 2) {
        return first;
      }
    }

    // 正则提取带扩展名的文件名
    final fnM = RegExp(r'([\w\u4e00-\u9fa5\.\-\_ ]+\.[a-zA-Z0-9]{2,8})')
        .firstMatch(text);
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
        .replaceAll(
            RegExp(r'[\d.]+\s*(?:KB|MB|GB|B|Bytes).*', caseSensitive: false),
            '')
        .replaceAll(RegExp(r'下载次数[:：]?\s*[\d,]+.*'), '')
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .trim();

    if (text.isEmpty ||
        text == '下载' ||
        text == '点击下载' ||
        text == '下载附件' ||
        text.length < 2) {
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

  /// 提取附件的全局唯一特征键（优先 aid，其次文件名，兜底 url）
  static String _attachmentKey(AttachmentBlock b) {
    final aidM = RegExp(r'[?&]aid=([a-zA-Z0-9%_-]+)').firstMatch(b.url);
    if (aidM != null) return 'aid_${aidM.group(1)}';
    if (b.name.isNotEmpty && b.name != '论坛附件.bin') return 'name_${b.name}';
    return 'url_${b.url}';
  }

  /// 递归遍历区块树，搜集所有已经存在的附件特征键
  static void _collectAttachmentKeys(
      List<PostBlock> blockList, Set<String> keys) {
    for (final b in blockList) {
      if (b is AttachmentBlock) {
        keys.add(_attachmentKey(b));
        keys.add(b.url);
        if (b.name.isNotEmpty) keys.add('name_${b.name}');
      } else if (b is CardContainerBlock) {
        _collectAttachmentKeys(b.children, keys);
      }
    }
  }

  /// 递归消除区块树中的重复附件
  static List<PostBlock> _deduplicateBlocks(List<PostBlock> blockList) {
    final seenKeys = <String>{};
    final result = <PostBlock>[];
    for (final b in blockList) {
      if (b is AttachmentBlock) {
        final key = _attachmentKey(b);
        if (seenKeys.add(key) && seenKeys.add(b.url)) {
          result.add(b);
        }
      } else if (b is CardContainerBlock) {
        final dedupChildren = _deduplicateBlocks(b.children);
        result.add(
          CardContainerBlock(
            children: dedupChildren,
            bgColor: b.bgColor,
            borderColor: b.borderColor,
            align: b.align,
          ),
        );
      } else {
        result.add(b);
      }
    }
    return result;
  }

  /// 判断是否为论坛装饰性分割线/分隔线图片（如 [hr] 标签生成的 hrline/line*.png、sigline.gif、fengexian 等）
  /// 严禁将分割线作为帖子封面图、缩略图或加入图片灯箱画廊
  static bool isDividerImage(String? src,
      {int? width, int? height, String? alt, String? title, String? style}) {
    if (src == null || src.trim().isEmpty) return false;
    final lower = src.toLowerCase().trim();

    // 1. Discuz 官方分割线路径与签名档分割线
    // 例如 static/image/hrline/line4.png, /static/image/hrline/, /hrline/, static/image/hrline/1.gif
    if (lower.contains('hrline') ||
        lower.contains('/hrline/') ||
        lower.contains('sigline') ||
        lower.contains('fengexian') ||
        lower.contains('fenge_xian') ||
        lower.contains('fgx.') ||
        lower.contains('_fgx') ||
        lower.contains('/separator') ||
        lower.contains('_separator') ||
        lower.contains('/divider') ||
        lower.contains('_divider') ||
        lower.contains('cutline') ||
        lower.contains('cut_line') ||
        lower.contains('splitline') ||
        lower.contains('split_line') ||
        lower.contains('dashline') ||
        lower.contains('solidline')) {
      return true;
    }

    // 2. 匹配常见分割线文件名模式 (支持 line.png, line_1.gif, line-1.png, line01.png, hr.png, fg.png, fenge.png 等)
    final cleanPath = lower.split('?').first.split('#').first;
    final fileName = cleanPath.split('/').last;
    if (RegExp(
      r'^(?:hr(?:_?line)?|feng_?xian|fgx|fg|line(?:[_\-]?\d+|_[a-z0-9]+)?|divider\d*|separator\d*|split(?:_?line)?|hengxian\d*|cut(?:ting)?_?line|border_line)\.(?:png|gif|jpg|jpeg|webp)$',
      caseSensitive: false,
    ).hasMatch(fileName)) {
      return true;
    }

    // 3. 标签/属性明确声明为分割线/分隔线 (alt, title)
    final checkAttrs = [alt, title];
    for (final attr in checkAttrs) {
      if (attr != null && attr.isNotEmpty) {
        final attrLower = attr.toLowerCase().trim();
        if (attrLower.contains('分割线') ||
            attrLower.contains('分隔线') ||
            attrLower.contains('横线') ||
            attrLower.contains('分界线') ||
            attrLower.contains('hrline') ||
            attrLower.contains('divider') ||
            attrLower.contains('separator') ||
            attrLower.contains('horizontal rule') ||
            RegExp(r'^(?:line|fgx|fenge|hr)\d*\.(?:png|gif|jpg|jpeg|webp)$',
                    caseSensitive: false)
                .hasMatch(attrLower)) {
          return true;
        }
      }
    }

    // 4. CSS style 样式明确声明高度微小 (如 height: 1px; 或 height: 2px;)
    if (style != null && style.isNotEmpty) {
      final styleLower = style.toLowerCase();
      if (RegExp(r'height\s*:\s*([1-9]|1[0-5])px').hasMatch(styleLower)) {
        return true;
      }
    }

    // 5. 极端横纵比检测：分割线高度通常极小（<= 15px），或横纵比 >= 4:1 且高度 <= 30px
    if (height != null && height > 0) {
      if (height <= 15) return true;
      if (height <= 30) {
        if (width == null || width >= 80 || (width / height) >= 4.0) {
          return true;
        }
      }
    }

    return false;
  }

  static bool _isValidCoverUrl(String? value) =>
      DiscuzImages.isContentUrl(value) && !isDividerImage(value ?? '');

  static List<String> _coversFromScope(html_dom.Element scope) =>
      DiscuzImages.covers(scope, Uri.parse(AppConfig.baseUrl));

  /// 从作用域提取首张封面图
  static String? _coverFromScope(html_dom.Element scope) {
    final list = _coversFromScope(scope);
    return list.isNotEmpty ? list.first : null;
  }

  /// 辅助判断当前元素是否处于作者栏、勋章栏或用户头像信息区（包括无图文章卡片的头像区）

  /// 辅助判断当前元素是否处于评论区、楼中楼、点赞栏或头像区

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
          final t = tit.text
              .replaceAll(
                  RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
                      unicode: true),
                  '')
              .trim();
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
            final t = pTit.text
                .replaceAll(
                    RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
                        unicode: true),
                    '')
                .trim();
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
      final a = li.querySelector(
          'a[href*="thread-"], a[href*="viewthread"], a[href*="tid="]');
      if (a == null) continue;
      final href = a.attributes['href'] ?? '';
      final tid = _tidFromHref(href);
      if (tid == null || !seen.add(tid)) continue;

      // 标题：优先 title 属性，其次 p/a 文本（剥离回复/阅读元数据）
      var title = _cleanTitle(a.attributes['title'] ?? '');
      if (title.isEmpty) {
        title = _cleanTitle(li.querySelector('p')?.text ?? a.text);
      }
      if (title.isEmpty) title = DiscuzThreadTitle.text(a);
      if (title.isEmpty) continue;

      final cover = _coverFromScope(li);

      final isHot = li.querySelector('i.b_ok') != null;

      var views = -1;
      final vm = RegExp(r'(\d+)\s*阅读').firstMatch(li.text);
      if (vm != null) views = int.tryParse(vm.group(1)!) ?? -1;

      var replies = -1;
      final repM = RegExp(r'(\d+)\s*回复').firstMatch(li.text);
      if (repM != null) replies = int.tryParse(repM.group(1)!) ?? -1;

      // 提取正文摘要（彻底清洗审核记录、管理操作、BBCode与系统编辑标记）
      final excerptEl = li.querySelector(
        '.twlist_txt, .comiis_mh_txt, .list_body, p.f_d, p.f_c',
      );
      String rawExcerpt = '';
      if (excerptEl != null) {
        final cleanEl = excerptEl.clone(true);
        cleanEl
            .querySelectorAll(
              '.comiis_modact, .modact, .psth, .modaction, .comiis_mod, .comiis_actinfo, .xg1, .xg1.y, .pstatus, script, style',
            )
            .forEach((e) => e.remove());
        cleanEl.querySelectorAll('*').forEach((e) {
          final t = e.text.trim();
          if (t.contains('审核通过') || (t.contains('由') && t.contains('审核'))) {
            e.remove();
          }
        });
        rawExcerpt = cleanEl.text.trim();
      }
      final cleaned = (rawExcerpt.isNotEmpty && rawExcerpt != title)
          ? cleanTextSnippet(rawExcerpt, maxLen: 120)
          : '';
      final excerpt = cleaned.isNotEmpty ? cleaned : null;

      final dm = RegExp(
        r'(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}-\d{1,2}|\d+\s*(?:秒|分钟|小时|天|周|月|年)前|昨天|前天|刚刚)(?:\s+\d{1,2}:\d{2})?',
      ).firstMatch(li.text);
      var timeText = dm?.group(0);

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
          final dateM = RegExp(
            r'(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}-\d{1,2}|\d+\s*(?:秒|分钟|小时|天|周|月|年)前|昨天|前天|刚刚)(?:\s+\d{1,2}:\d{2})?$',
          ).firstMatch(raw);
          if (dateM != null) {
            final tag = raw.substring(0, dateM.start).trim();
            if (tag.isNotEmpty) forumName = tag;
            timeText = dateM.group(0);
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
        final m = RegExp(r'fid=(\d+)').firstMatch(href) ??
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
        final alt = stampEl.attributes['alt'] ??
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

  static final Map<String, String> _smileyCodeToUrlMap = {};

  /// 获取表情代号 -> 图片完整 URL 映射表（供发帖实时排版预览与 BBCode 转 HTML 使用）
  static Map<String, String> getSmileyCodeMap(
      [List<SmileyCategory>? categories]) {
    if (categories != null && categories.isNotEmpty) {
      for (final cat in categories) {
        for (final s in cat.smileys) {
          if (s.code.isNotEmpty) {
            _smileyCodeToUrlMap[s.code] = s.imageUrl;
          }
          if (cat.typeid > 0 && s.id > 0) {
            _smileyCodeToUrlMap['{:${cat.typeid}_${s.id}:}'] = s.imageUrl;
          }
        }
      }
    }
    if (_smileyCodeToUrlMap.isEmpty) {
      final defaultList = parseSmilies(kDefaultSmiliesJs);
      for (final cat in defaultList) {
        for (final s in cat.smileys) {
          if (s.code.isNotEmpty) {
            _smileyCodeToUrlMap[s.code] = s.imageUrl;
          }
          if (cat.typeid > 0 && s.id > 0) {
            _smileyCodeToUrlMap['{:${cat.typeid}_${s.id}:}'] = s.imageUrl;
          }
        }
      }
    }
    _smileyCodeToUrlMap.remove('');
    return _smileyCodeToUrlMap;
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

    // 服务端明确展示「无收藏」时，直接返回空列表，绝不触发兜底误匹配
    final hasNoFavTip = doc.querySelector('.comiis_notip, p.emp') != null ||
        html.contains('您还没有收藏任何内容') ||
        html.contains('没有找到相关收藏') ||
        html.contains('no_favorite_yet');
    if (hasNoFavTip) {
      return const [];
    }

    final result = <Forum>[];
    final seen = <int>{};

    // 1. 从各容器条目中提取（支持克米移动端 .comiis_mysclist 与 Discuz PC 端 #favorite_ul）
    final items = doc.querySelectorAll(
      '.comiis_mysclist li, li.mysclist_li, ul#favorite_ul li, #ct table tr, #favoriteform li, #favoriteform tr, div[id^="fav_"], tr[id^="fav_"], li[id^="fav_"]',
    );
    for (final el in items) {
      // 提取 FID：优先通过 input[vid]（PC 端 Discuz 自带 vid="$value[id]"），再通过标题链接提取
      int? fid;
      final vidAttr = el.querySelector('input[vid]')?.attributes['vid'];
      if (vidAttr != null) {
        fid = int.tryParse(vidAttr);
      }

      final titleA = el.querySelector(
          'h2 a[href*="fid="], h2 a[href*="forum-"], a[href*="forum-"], a[href*="forumdisplay"], a[href*="fid="]');
      if (fid == null && titleA != null) {
        final href = titleA.attributes['href'] ?? '';
        final fm = RegExp(
                r'forum-(\d+)-\d+\.html|forumdisplay[^"]*fid=(\d+)|fid=(\d+)')
            .firstMatch(href);
        if (fm != null) {
          fid = int.tryParse(fm.group(1) ?? fm.group(2) ?? fm.group(3) ?? '');
        }
      }
      if (fid == null || fid <= 0 || !seen.add(fid)) continue;

      var name = '';
      if (titleA != null) {
        final h2 = titleA.querySelector('h2') ?? el.querySelector('h2');
        if (h2 != null) {
          name = _cleanTitle(h2.text.trim());
        } else {
          name = _cleanTitle(titleA.text.trim());
        }
      }
      if (name.isEmpty) name = getForumNameByFid(fid) ?? '版块 $fid';

      // 提取 FAV_ID（收藏项主键 ID）
      int? favid;
      final delA = el.querySelector('a[href*="favid="]');
      if (delA != null) {
        final mDel =
            RegExp(r'favid=(\d+)').firstMatch(delA.attributes['href'] ?? '');
        if (mDel != null) favid = int.tryParse(mDel.group(1)!);
      }
      if (favid == null || favid <= 0) {
        final inp = el.querySelector('input[name*="favorite"]');
        if (inp != null) {
          favid = int.tryParse(inp.attributes['value'] ?? '');
        }
      }
      if (favid == null || favid <= 0) {
        final idAttr = el.attributes['id'] ?? '';
        final mId = RegExp(r'fav_(\d+)').firstMatch(idAttr);
        if (mId != null) favid = int.tryParse(mId.group(1)!);
      }

      final desc = el.querySelector('.xg1, .description, p')?.text.trim();
      final counts = DiscuzForumCounters.labelled(el
          .querySelectorAll('.xg1, .k-meta, p')
          .where((node) =>
              RegExp(r'^\s*(?:主题|帖数|帖子)\s*[:：]').hasMatch(node.text)));

      registerForumName(fid, name);
      result.add(
        Forum(
          fid: fid,
          name: name,
          description: desc,
          favid: favid,
          threadCount: counts['posts'] ?? -1,
          topicCount: counts['topics'] ?? -1,
          displayValues: counts.displayValues,
        ),
      );
    }

    // 2. 仅在未发现任何条目且非明确空态时进行严格兜底
    if (result.isEmpty && !hasNoFavTip) {
      for (final a in doc.querySelectorAll(
          '.comiis_mysclist a, #favorite_ul a, #favoriteform a')) {
        final href = a.attributes['href'] ?? '';
        final fm = RegExp(r'forum-(\d+)-\d+\.html|forumdisplay[^"]*fid=(\d+)')
            .firstMatch(href);
        if (fm == null) continue;
        final fid = int.tryParse(fm.group(1) ?? fm.group(2) ?? '');
        if (fid == null || fid <= 0 || !seen.add(fid)) continue;
        final name = _cleanTitle(a.text.trim());
        if (name.isNotEmpty &&
            !name.contains('论坛') &&
            !name.contains('版块') &&
            !name.contains('返回')) {
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
    return DiscuzSiteStats.parse(html);
  }

  /// 兼容单条入口；完整轮播由 DiscuzHornProtocol.parseBanners 读取。
  static ({
    String author,
    String avatarUrl,
    String message,
    String linkUrl,
    int tid,
    int uid
  })? parseTuhaoBanner(String source) {
    final base = Uri.parse(AppConfig.baseUrl);
    final banners = DiscuzHornProtocol.parseBanners(source, base);
    if (banners.isEmpty) return null;
    final first = banners.first;
    return (
      author: first.author,
      avatarUrl: first.avatarUrl ?? '',
      message: DiscuzHornProtocol.messageText(first.content),
      linkUrl: first.linkUrl ?? '',
      tid: DiscuzHornProtocol.threadId(first.linkUrl ?? '', base) ?? 0,
      uid: first.uid ?? 0,
    );
  }

  static List<ForumGroup> parseForumGroups(String html) {
    if (html.isEmpty) return const [];
    final modern =
        DiscuzForumParser.parseModern(html, Uri.parse(AppConfig.baseUrl));
    if (modern.isNotEmpty) return modern;
    final doc = html_parser.parse(html);
    final groups = <ForumGroup>[];
    final seenGids = <int>{};

    // 1. 移动端克米模板：div.comiis_forumlist 与 div.comiis_fl
    for (final fl
        in doc.querySelectorAll('div.comiis_forumlist, div.comiis_fl')) {
      int gid = -1;
      for (final c in fl.classes) {
        final m = RegExp(r'comiis_km(\d+)').firstMatch(c);
        if (m != null) {
          gid = int.tryParse(m.group(1)!) ?? -1;
          break;
        }
      }

      final show =
          fl.querySelector('div.comiis_bbs_show, .comiis_fl_title, h2');
      if (gid < 0 && show != null) {
        final href = show.attributes['href'] ?? '';
        final m = RegExp(r'sub_forum_(\d+)').firstMatch(href);
        if (m != null) gid = int.tryParse(m.group(1)!) ?? -1;
      }

      var name =
          (show?.querySelector('h2 a, h2, a')?.text ?? show?.text ?? '').trim();
      name = _cleanTitle(name);
      name = name
          .replaceAll(RegExp(r'(?:\[?管理\]?|展开|收起|设置|更多)$'), '')
          .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
          .trim();

      // 精准识别「我关注的」专属快捷分区 (gid 0)
      if (gid == 0 ||
          name.contains('关注') ||
          (fl.attributes['id'] ?? '').contains('fav')) {
        gid = 0;
        name = '我关注的';
      }

      if (gid < 0) {
        if (name.isEmpty) continue;
        gid = groups.length + 1;
      }

      if (!seenGids.add(gid)) continue;

      final forums = <Forum>[];
      final box = (gid >= 0 ? doc.querySelector('#sub_forum_$gid') : null) ??
          fl.querySelector('div.comiis_forum_nbox, ul, div.cl');
      if (box != null) {
        for (final a
            in box.querySelectorAll('a[href*="forum-"], a[href*="fid="]')) {
          final fhref = a.attributes['href'] ?? '';
          final fid =
              DiscuzForumParser.forumId(fhref, Uri.parse(AppConfig.baseUrl));
          if (fid == null || fid <= 0 || forums.any((f) => f.fid == fid)) {
            continue;
          }

          String? iconUrl;
          final img = a.querySelector('img');
          var fname = (img?.attributes['alt'] ?? '').trim();
          if (fname.isEmpty) {
            final title = a.children
                .where((node) =>
                    node.localName == 'span' && !node.classes.contains('bg_a'))
                .firstOrNull;
            final copy = a.clone(true);
            copy
                .querySelectorAll('p, em, span.bg_a')
                .forEach((node) => node.remove());
            fname = (title?.text ?? copy.text).trim();
          }
          fname = _cleanTitle(fname);
          if (fname.isEmpty) continue;

          if (img != null) {
            var rawIcon = img.attributes['comiis_loadimages'] ?? '';
            if (rawIcon.isEmpty ||
                rawIcon.contains('none.png') ||
                rawIcon.contains('spacer.gif')) {
              rawIcon = img.attributes['data-src'] ?? '';
            }
            if (rawIcon.isEmpty ||
                rawIcon.contains('none.png') ||
                rawIcon.contains('spacer.gif')) {
              rawIcon = img.attributes['file'] ?? '';
            }
            if (rawIcon.isEmpty ||
                rawIcon.contains('none.png') ||
                rawIcon.contains('spacer.gif')) {
              rawIcon = img.attributes['src'] ?? '';
            }
            if (rawIcon.isNotEmpty &&
                !rawIcon.contains('none.png') &&
                !rawIcon.contains('spacer.gif')) {
              iconUrl = _absolute(rawIcon);
            }
          }

          final aText = a.text.trim();
          final counts = DiscuzForumCounters.mobileCard(a);

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
              threadCount: counts['posts'] ?? -1,
              topicCount: counts['topics'] ?? -1,
              todayCount: counts['today'] ?? -1,
              displayValues: counts.displayValues,
              description: desc,
            ),
          );
        }
      }

      if (forums.isNotEmpty) {
        groups.add(ForumGroup(gid: gid, name: name, forums: forums));
      }
    }

    // 2. PC 端与通用 Discuz 结构：严格按分区容器 div[id^="category_"], .bm.cbm_box 识别，杜绝子版块误升格
    if (groups.isEmpty) {
      var catElements = doc.querySelectorAll('div[id^="category_"]');
      if (catElements.isEmpty) {
        catElements = doc.querySelectorAll('.bm.cbm_box, div.fl > div.bm');
      }

      for (final catEl in catElements) {
        final parent =
            (catEl.localName == 'div' && (catEl.id).startsWith('category_'))
                ? (catEl.parent ?? catEl)
                : catEl;
        final h2 = parent.querySelector('.bm_h h2 a, .bm_h h2, h2 a, h2');
        var name = _cleanTitle(h2?.text ?? '');
        if (name.isEmpty ||
            name.contains('小喇叭') ||
            name.contains('关注') ||
            name.contains('友情链接')) {
          continue;
        }

        int gid = -1;
        final catId = catEl.id;
        final mGid = RegExp(r'category_(\d+)').firstMatch(catId);
        if (mGid != null) {
          gid = int.tryParse(mGid.group(1)!) ?? -1;
        } else if (h2 != null) {
          final h2Href = h2.attributes['href'] ??
              h2.querySelector('a')?.attributes['href'] ??
              '';
          final mH2 = RegExp(r'gid=(\d+)').firstMatch(h2Href);
          if (mH2 != null) {
            gid = int.tryParse(mH2.group(1)!) ?? -1;
          }
        }

        if (gid < 0) {
          gid = groups.length + 1;
        }

        if (!seenGids.add(gid)) continue;

        final forums = <Forum>[];
        final seenFids = <int>{};
        final table = catEl.querySelector('table.fl_tb') ?? catEl;

        for (final item
            in table.querySelectorAll('td.fl_g, td.fl_icn, dt, td')) {
          for (final a in item.querySelectorAll(
              'h2 a[href*="forum-"], dt a[href*="forum-"], a[href*="forum-"], a[href*="fid="]')) {
            final href = a.attributes['href'] ?? '';
            final fid =
                DiscuzForumParser.forumId(href, Uri.parse(AppConfig.baseUrl));
            if (fid == null || fid <= 0 || !seenFids.add(fid)) continue;

            final fname = _cleanTitle(a.text.trim());
            if (fname.isEmpty) continue;

            var today = -1;
            final em = a.querySelector('em.xi1, span.xi1');
            if (em != null) {
              today = DiscuzSiteStats.number(em.text) ?? -1;
            }
            var card = item;
            if (!item.classes.contains('fl_g')) {
              for (var parent = item.parent;
                  parent != null && parent != table;
                  parent = parent.parent) {
                if (parent.localName == 'tr' || parent.localName == 'dl') {
                  card = parent;
                  break;
                }
              }
            }
            final counts = DiscuzForumCounters.defaultCard(card);

            forums.add(Forum(
              fid: fid,
              name: fname,
              gid: gid,
              todayCount: today,
              threadCount: counts['posts'] ?? -1,
              topicCount: counts['topics'] ?? -1,
              displayValues: counts.displayValues,
            ));
          }
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
    var moderators = '';
    var rulesHtml = '';

    // 1. 版块名称与 Banner 顶图
    final nameEl = doc.querySelector(
      '.klp-fhead-title a, .klp-fhead-title, h1.klp-fhead-title, .comiis_forumlist_head .top_left h2, .bm.bml h1, div.bml h1, #pt a:last-child, h1.xs2, div.comiis_head h2',
    );
    if (nameEl != null) {
      name = _cleanTitle(nameEl.text);
    }

    final cbanner = doc.querySelector('.cbanner, [class*="banner"]');
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
    if (bannerUrl == null || bannerUrl.isEmpty) {
      bannerUrl = AppConfig.forumBannerUrl(fid);
    }

    // 2. 本版统计；网页首页的分区汇总、帖子正文和全局统计不作兜底。
    final counts = DiscuzForumCounters.header(doc);

    // 3. 版主信息（兼容 PC 端完整版主列表、#forum_modedby、div.bml_c 及移动端各类版主容器与 a 标签列表）
    final allModNames = <String>{};

    // 优先从 PC/移动端标准完整版主容器中提取全部版主
    for (final selector in [
      '#forum_modedby',
      'div.bml_c',
      'div.bml',
      'div[id*="modedby"]',
      '.forum_modedby',
      '.comiis_forumlist_bkgz',
      '.klp-fmods-list',
      '.klp-fmods',
    ]) {
      for (final container in doc.querySelectorAll(selector)) {
        for (final a in container.querySelectorAll('a')) {
          final t = a.text.trim();
          final title = a.attributes['title']?.trim() ?? '';
          final name = title.isNotEmpty ? title : t;
          if (name.isNotEmpty &&
              name != '版主' &&
              !name.startsWith('版主') &&
              !name.startsWith('+') &&
              !name.contains('详情') &&
              !name.contains('规则')) {
            allModNames.add(name);
          }
        }
      }
    }

    // 兜底扫描包含“版主”文本的容器
    if (allModNames.isEmpty) {
      for (final el in doc.querySelectorAll(
          'em, p, div.bm_c, span.xi2, .comiis_forumlist_bkgz *')) {
        if (el.text.contains('版主') && el.querySelectorAll('a').isNotEmpty) {
          for (final a in el.querySelectorAll('a')) {
            final t = a.text.trim();
            final title = a.attributes['title']?.trim() ?? '';
            final name = title.isNotEmpty ? title : t;
            if (name.isNotEmpty &&
                name != '版主' &&
                !name.startsWith('版主') &&
                !name.startsWith('+')) {
              allModNames.add(name);
            }
          }
        }
      }
    }

    if (allModNames.isNotEmpty) {
      moderators = allModNames.join(' ');
    } else {
      // 文本正则提取
      final text = doc.body?.text ?? '';
      final mm = RegExp(r'版主[:：]\s*([^\r\n<|]+)').firstMatch(text);
      if (mm != null) {
        moderators = mm.group(1)!.replaceAll(RegExp(r'\+\d+'), '').trim();
      }
    }

    // 4. 版块导览与版规内容卡片（支持现代 klp_rules_$fid 与传统 forum_rules_$fid / crule 容器）
    final rulesEl = doc.getElementById('klp_rules_$fid') ??
        doc.getElementById('forum_rules_$fid') ??
        doc.querySelector(
          '#klp_rules_$fid, section.klp-rules .klp-rules-body, .klp-rules-body, section.klp-rules, div#forum_rules_$fid, div.crule, div[id="forum_rules_$fid"], #forum_rules, #rules, div.ptn.xg2, div.bm_c div.xg2, div.bml_c .xg2, .comiis_fl_rules',
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
              '#a_favorite.fav_on, #a_favorite.km_fav_on, #comiis_favorite_a.fav_on, a[href*="op=delete"][href*="favorite"], a[href*="delfav"], a.fav_on, a.km_fav_on',
            ) !=
            null ||
        doc
                .querySelector('#a_favorite.on, #comiis_favorite_a.on')
                ?.text
                .contains('取消') ==
            true ||
        html.contains('data-off="已收藏"') ||
        html.contains('您已收藏过本版') ||
        html.contains('取消收藏本版');

    return ForumHeaderInfo(
      fid: fid,
      name: name,
      bannerUrl: bannerUrl,
      todayPosts: counts['today'],
      threadsCount: counts['topics'],
      postsCount: counts['posts'],
      rank: counts['rank'],
      favCount: counts['favorites'],
      displayValues: counts.displayValues,
      moderators: moderators,
      rulesHtml: rulesHtml,
      creditRules: creditRules,
      isFavorited: isFavorited,
    );
  }

  /// 解析 Discuz 本版积分规则（forum.php?mod=misc&action=creditrule&fid=$fid 或版块页面内的积分规则表）
  static List<ForumCreditRule> parseCreditRules(String html) {
    return DiscuzCreditRules.parse(html);
  }

  // ---------------------------------------------------------------------
  // 论坛 AI 总结 (klpbbs_aisum)
  // ---------------------------------------------------------------------
  /// 解析论坛 AI 总结数据（支持预渲染 HTML 结构与流式初始态）
  static AiSummaryData? parseAiSummary(String html, {html_dom.Document? doc}) {
    if (!html.contains('klpai')) return null;
    final d = doc ?? html_parser.parse(html);
    final root = d.querySelector('.klpai');
    if (root == null) return null;

    final streamAttr = root.attributes['data-stream'] ?? '0';
    var streamUrl = root.attributes['data-url'];
    if (streamUrl == null || streamUrl.isEmpty) {
      final scriptMatch = RegExp(
              r'''(?:fetch\s*\(\s*|streamUrl\s*=\s*|url:\s*)['"]([^'"]*klpbbs_aisum:stream[^'"]*)['"]''')
          .firstMatch(html);
      if (scriptMatch != null) {
        streamUrl = scriptMatch.group(1);
      }
    }

    final headline = root
            .querySelector('[data-role="headline"], .klpai__headline')
            ?.text
            .trim() ??
        '';
    final summary = root
            .querySelector(
                '[data-role="summary"], .klpai__panel--summary, .klpai__summary')
            ?.text
            .trim() ??
        '';
    final metaText =
        root.querySelector('.klpai__time, [data-role="meta"]')?.text.trim() ??
            root.querySelector('.klpai__meta')?.text.trim();
    final statusText = root
        .querySelector('[data-role="status"], .klpai__loading, .klpai__status')
        ?.text
        .trim();

    final notices = <String>[];
    for (final li in root.querySelectorAll(
        '[data-panel="notices"] li, [data-role="noticelist"] li, .klpai__points li, .klpai__panel--notices li')) {
      final t = li.text.trim();
      if (t.isNotEmpty && !notices.contains(t)) {
        notices.add(t);
      }
    }

    final downloadSteps = <String>[];
    for (final li in root.querySelectorAll(
        '[data-panel="download"] [data-role="downloadlist"] li, [data-role="downloadwrap"] li, .klpai__panel--download ol li, .klpai__panel--download ul li')) {
      final t = li.text.trim();
      if (t.isNotEmpty && !downloadSteps.contains(t)) {
        downloadSteps.add(t);
      }
    }

    final links = <AiSummaryLink>[];
    for (final a in root.querySelectorAll(
        '[data-role="links"] a, a.klpai__file--link, .klpai__links a, a.klpai__link')) {
      var href = a.attributes['data-href'] ?? a.attributes['href'] ?? '';
      if (href.contains('url.php?url=')) {
        try {
          final m = RegExp(r'url=([A-Za-z0-9+/=_%-]+)').firstMatch(href);
          if (m != null) {
            final raw = Uri.decodeComponent(m.group(1)!)
                .replaceAll('-', '+')
                .replaceAll('_', '/');
            final pad = (4 - (raw.length % 4)) % 4;
            final padded = raw + ('=' * pad);
            final decoded = utf8.decode(base64.decode(padded));
            if (decoded.startsWith('http')) href = decoded;
          }
        } catch (_) {}
      }
      final name =
          a.querySelector('.klpai__filename')?.text.trim() ?? a.text.trim();
      final meta = a.querySelector('.klpai__filemeta')?.text.trim() ?? '';
      var service = '';
      if (meta.contains('·')) {
        service = meta.split('·').first.trim();
      }
      if (href.isNotEmpty) {
        links.add(AiSummaryLink(
            url: href, label: name.isNotEmpty ? name : href, service: service));
      }
    }

    if (headline.isNotEmpty ||
        summary.isNotEmpty ||
        notices.isNotEmpty ||
        downloadSteps.isNotEmpty ||
        links.isNotEmpty ||
        streamAttr == '1' ||
        (streamUrl != null && streamUrl.isNotEmpty) ||
        (statusText != null && statusText.isNotEmpty)) {
      return AiSummaryData(
        headline: headline,
        summary: summary,
        notices: notices,
        downloadSteps: downloadSteps,
        links: links,
        generatedTime: metaText,
        statusText: statusText,
        isStreaming: streamAttr == '1',
        streamUrl: streamUrl,
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // 帖子详情（楼层）
  // ---------------------------------------------------------------------
  /// 异步多线程解析帖子详情页 HTML（优先在后台 Isolate 运行）
  static Future<ThreadDetailParsed> parseThreadDetailAsync(String html) async {
    if (!AppConfig.enableMultiThreadParsing) {
      return parseThreadDetail(html);
    }
    return compute(_parseThreadDetailCompute, html);
  }

  /// 解析帖子详情页 HTML（同时支持 mobile=2 克米手机版与 mobile=no Discuz 官方电脑版）。
  static ThreadDetailParsed parseThreadDetail(String html) {
    final doc = html_parser.parse(html);
    final access = DiscuzThreadAccess.fromDocument(doc);
    if (access != null) throw access;
    final floors = <PostFloor>[];
    int parsedCurrentPage = 1;
    final curPageEl = doc.querySelector(
        '.pg strong, .pages strong, .comiis_pg strong, .cur, .pg .cur');
    if (curPageEl != null) {
      final p = int.tryParse(curPageEl.text.trim());
      if (p != null && p > 0) parsedCurrentPage = p;
    }

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
          final m = RegExp(r'forum-(\d+)-\d+\.html').firstMatch(href) ??
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
            final m = RegExp(r'forum-(\d+)-\d+\.html').firstMatch(href) ??
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
        final m = RegExp(r'fid=(\d+)').firstMatch(href) ??
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

    // 提取主题全局作者信息（100% 权威，杜绝任何倒序、分页或模板 BUG 造成的作者错乱）
    int? threadAuthorUid;
    String? threadAuthor;

    // a. 优先从 Discuz 全局 JS 变量中提取 authorid (例: authorid = '254543')
    final mAid =
        RegExp(r'\bauthorid\s*=\s*[\x27\x22](\d+)[\x27\x22]').firstMatch(html);
    if (mAid != null) {
      threadAuthorUid = int.tryParse(mAid.group(1)!);
    }

    // b. 从克米移动端顶部主题作者卡片提取 (.comiis_view_topuser / .view_topuserbg)
    final topUserA =
        doc.querySelector('.comiis_view_topuser a, .view_topuserbg a');
    if (topUserA != null) {
      if (threadAuthorUid == null) {
        final href = topUserA.attributes['href'] ?? '';
        final mUid = RegExp(r'uid=(\d+)').firstMatch(href);
        if (mUid != null) threadAuthorUid = int.tryParse(mUid.group(1)!);
      }
      final nameText = topUserA.text.trim();
      if (nameText.isNotEmpty && !nameText.contains('***')) {
        threadAuthor = nameText;
      }
    }

    // c. 从全局结构化数据 JSON-LD 中提取作者名称
    if (threadAuthor == null ||
        threadAuthor.isEmpty ||
        threadAuthor.contains('***')) {
      for (final sc in doc.querySelectorAll('script[type*="json"]')) {
        final jm = RegExp(
                r'"author"\s*:\s*\{\s*"@type"\s*:\s*"Person"\s*,\s*"name"\s*:\s*"([^"]+)"')
            .firstMatch(sc.text);
        if (jm != null && !jm.group(1)!.contains('***')) {
          threadAuthor = jm.group(1);
          break;
        }
      }
    }

    // d. 从 meta description 中提取 (例: YesNewBee 发布于)
    if (threadAuthor == null ||
        threadAuthor.isEmpty ||
        threadAuthor.contains('***')) {
      final descEl = doc.querySelector('meta[name="description"]');
      final descContent = descEl?.attributes['content'] ?? '';
      final dm =
          RegExp(r'(?:版块[，,]\s*)?([^\s，,]+)\s+发布于').firstMatch(descContent);
      if (dm != null && !dm.group(1)!.contains('***')) {
        threadAuthor = dm.group(1)!.trim();
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
      // Navigation, toolbars and permission pages can contain .plc/postitem.
      // Only an actual scoped message or a shielded post is a floor.
      if (post.querySelector(
              'div.message,td[id^="postmessage_"],.t_f,.postmessage,.message,.locked,.shield,.comiis_shield') ==
          null) {
        continue;
      }
      // 内容区
      final message = post.querySelector(
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
      if (author.contains('***') &&
          uid != null &&
          uid == threadAuthorUid &&
          threadAuthor != null &&
          !threadAuthor.contains('***')) {
        author = threadAuthor;
      }
      // 头像挂件（sunju_facemall）：top_tximg img 的 ##SJ## 后缀
      final faceImg = _authorAvatarImage(
        post,
        'img.top_tximg, a.postli_top_tximg img, .avtm img, .avatar img',
      );
      final faceUrl = _authorAvatarFrame(faceImg) ?? '';

      final metadata = DiscuzPostMetadata.parse(post);
      final timeText = metadata.timeText;

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

      // 楼主与作者标识判定（以全局权威 threadAuthorUid / threadAuthor 为准，杜绝模板混乱）
      final bool isAuthorPost =
          (threadAuthorUid != null && uid != null && uid == threadAuthorUid) ||
              (threadAuthor != null &&
                  threadAuthor.isNotEmpty &&
                  author.isNotEmpty &&
                  author == threadAuthor);
      var isThreadAuthor = isAuthorPost;
      if (!isThreadAuthor) {
        for (final lv in post.querySelectorAll('.top_lev')) {
          if (lv.text.trim() == '楼主' &&
              (threadAuthorUid == null || uid == threadAuthorUid)) {
            isThreadAuthor = true;
            break;
          }
        }
      }

      // 认证徽章（comiis_verify：Discuz verify 实名认证，img + title + vid）
      final verifies = <({String img, String title, String vid})>[];
      final verifyBox = post.querySelector('.comiis_verify');
      if (verifyBox != null) {
        for (final a in verifyBox.querySelectorAll('a')) {
          final img = a.querySelector('img');
          final src = _absolute(img?.attributes['src']) ?? '';
          final title = img?.attributes['alt'] ??
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
          ({
            String user,
            int? uid,
            String avatar,
            String amount,
            String reason
          })> rewards = [];
      for (final rl in post.querySelectorAll('div[id^="ratelog_"]')) {
        for (final li in rl.querySelectorAll('li[id^="rate_"]')) {
          final userA =
              li.querySelector('a.f_c') ?? li.querySelector('a.lcrate_img');
          final user = userA?.text.trim() ?? '';
          final uid = _uidFromHref(userA?.attributes['href'] ?? '');
          final avatar = _absolute(
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
      final rc = RegExp(r'(\d+)\s*人打赏').firstMatch(post.text) ??
          RegExp(r'已有\s*(\d+)\s*人').firstMatch(post.text) ??
          RegExp(r'''<span[^>]*class="[^"]*f_a[^"]*"[^>]*>(\d+)</span>\s*人打赏''')
              .firstMatch(post.outerHtml);
      if (rc != null) rewardCount = rc.group(1)!;

      final ipText = metadata.ipText;

      // 签名档（严格局限在当前 post 节点内提取，严禁向上遍历父节点，杜绝将楼主签名错误赋给其他楼层）
      String signature = '';
      final signEl = post.querySelector(
        '.sign, .signature, div.comiis_sign, div.comiis_qm, div.qm, div.kmqm, .comiis_authi .qm, .signtext, .comiis_mh_sign, div[id^="signature_"], div.signature_content, .user_signature, .signaturetext, div[style*="sigline"], div[style*="sigline.gif"]',
      );
      if (signEl != null) {
        signature =
            (signEl.innerHtml.isNotEmpty ? signEl.innerHtml : signEl.text)
                .trim();
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

      // 提取核心正文容器，剔除 Discuz 插件、打赏点赞、管理审核残留与分散片
      final cleanMessage = message.clone(true);
      for (final el in cleanMessage.querySelectorAll(
        '.comiis_rate, div[id^="ratelog_"], .comiis_dzhan_img, .comiis_bankuai, .replyfloor_box, .comiis_zhanv2, div[id^="mgc_post_"], .comiis_tags, .comiis_pltit, .pstatus, i.pstatus, .comiis_flxx_stamp, .comiis_actinfo, .comiis_view_flxx, table.cptbl, table.typeoption, div.typeoption, div#typeoption, style, script, div[style*="sigline.gif"], .fwinmask, div[id^="fwin_"], form#favoriteform, form[id*="favorite"], form[action*="favorite"], div#messagetext, div.comiis_tip, div.tip, .comiis_modact, .modact, .psth, .modaction, .comiis_mod',
      )) {
        el.remove();
      }
      cleanMessage.querySelectorAll('*').forEach((el) {
        final t = el.text.trim();
        if (t.contains('审核通过') || (t.contains('由') && t.contains('审核'))) {
          final after = t.replaceAll(auditNoticeGeneralRegExp, '').trim();
          if (after.isEmpty) {
            el.remove();
          } else {
            el.innerHtml =
                el.innerHtml.replaceAll(auditNoticeGeneralRegExp, '');
          }
        }
      });
      // 清洗所有顶层及子级文本节点中的审核通知残留
      for (final n in cleanMessage.nodes) {
        if (n is html_dom.Text) {
          n.text = n.text.replaceAll(auditNoticeGeneralRegExp, '');
        }
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
          final isSmiley = rawSrc.contains('static/image/smiley/') ||
              rawSrc.contains('post/smile') ||
              img.attributes.containsKey('smilieid');
          final isFileTypeIcon = rawSrc.contains('/filetype/') ||
              rawSrc.contains('static/image/filetype') ||
              rawSrc.contains('image/filetype') ||
              rawSrc.contains('/common/none.gif') ||
              rawSrc.contains('/common/attach') ||
              rawSrc.contains('static/image/common/');
          final rawW = int.tryParse(img.attributes['width'] ?? '');
          final rawH = int.tryParse(img.attributes['height'] ?? '');
          final isSmallIcon = (rawW != null && rawW > 0 && rawW <= 48) ||
              (rawH != null && rawH > 0 && rawH <= 48) ||
              img.classes.contains('vm') ||
              rawSrc.contains('template/');
          final isDivider = isDividerImage(
            rawSrc,
            width: rawW,
            height: rawH,
            alt: img.attributes['alt'],
            title: img.attributes['title'],
            style: img.attributes['style'],
          );
          if (isSmiley || isFileTypeIcon || isSmallIcon || isDivider) continue;

          final src = _absolute(rawSrc);
          if (src != null && !images.contains(src)) images.add(src);
        }
      }

      final replyFloor = _parseReplyFloor(post);

      // 提取楼层标识（优先从帖子自身的顶部元素提取真实楼层号）
      var floorNumber = '';
      final floorEl = post.querySelector(
        '.comiis_postli_top h2 span.y, .comiis_postli_top span.f_d.y, .comiis_postli_top span.y, .authi li.mtit span.y, .authi .mtit span.y, .authi span.y, a.node em, a[id^="postnum"] em, a[id^="postnum"], .pi strong a em, .pi strong a, .pi strong, .postinfo strong a, .postinfo strong, .floor, .comiis_postli_top em.y',
      );
      if (floorEl != null) {
        var rawT = floorEl.text;
        for (final bad in floorEl
            .querySelectorAll('.popup, .top_guanli, .comiis_font, i')) {
          rawT = rawT.replaceFirst(bad.text, '');
        }
        final t = rawT.replaceAll(RegExp(r'[\ue000-\uf8ff\s]'), '').trim();
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
          } else if (t.contains('沙发') || t == '2#') {
            floorNumber = '沙发';
          } else if (t.contains('板凳') || t == '3#') {
            floorNumber = '板凳';
          } else if (t.contains('地板') || t == '4#') {
            floorNumber = '地板';
          } else if (t.contains('楼主')) {
            // 关键：只有当前楼层的发帖者确实是主题作者，且是第 1 页首楼，才接受「楼主」标识！
            // 其它任何处于回帖位置却被打上「楼主」标识的（如 Discuz 倒序计数递减到 1 触发的模板输出），
            // 实际上均为回帖第 1 楼（即沙发）！
            if (replyFloor.floorNumber.isEmpty) {
              if (isAuthorPost && floors.isEmpty && parsedCurrentPage == 1) {
                floorNumber = '楼主';
                threadAuthorUid ??= uid;
                if (threadAuthor == null || threadAuthor.isEmpty) {
                  threadAuthor = author;
                }
              } else if (threadAuthorUid == null &&
                  floors.isEmpty &&
                  parsedCurrentPage == 1) {
                floorNumber = '楼主';
                threadAuthorUid = uid;
                if (threadAuthor == null || threadAuthor.isEmpty) {
                  threadAuthor = author;
                }
              } else {
                floorNumber = '沙发';
              }
            }
          }
        }
      }
      // 若顶栏未提取到，才回退到 replyFloor
      if (floorNumber.isEmpty && replyFloor.floorNumber.isNotEmpty) {
        floorNumber = replyFloor.floorNumber;
      }
      // 如果当前楼层确实是作者且是首楼且没有任何序号，标记为楼主
      if (floorNumber.isEmpty &&
          (isAuthorPost || (threadAuthorUid == null && floors.isEmpty)) &&
          floors.isEmpty &&
          parsedCurrentPage == 1) {
        floorNumber = '楼主';
        threadAuthorUid ??= uid;
        if (threadAuthor == null || threadAuthor.isEmpty) {
          threadAuthor = author;
        }
      }

      final isCurrentLouzhu = floorNumber == '楼主' &&
          (isAuthorPost || (threadAuthorUid == null && floors.isEmpty)) &&
          floors.isEmpty &&
          parsedCurrentPage == 1;
      final magicItems = _parseMagicItems(post);
      final rawBlocks =
          parseStructuredBlocks(coreBody, isFirstFloor: isCurrentLouzhu);

      // 全面扫描楼层内所有独立附件容器（仅提取在 coreBody 外部的附件，防止二次重复解析）
      final existingAttachKeys = <String>{};
      _collectAttachmentKeys(rawBlocks, existingAttachKeys);

      final attachCandidates = post.querySelectorAll(
        '.comiis_attach, .pattl, .attach_nopermission, dl.tattl, div.attachlist, div[id^="attach_"], div.box_attach, a[href*="attachment"], a[href*="aid="], a[href*="klpbbs_download"], a[href*="download.php"]',
      );
      for (final el in attachCandidates) {
        // 关键防御：若该附件节点已经在 message 内部，说明上面 parseStructuredBlocks 已经解析过，坚决跳过避免双重解析
        if (message.contains(el)) continue;

        final parsed = parseStructuredBlocks(el, isFirstFloor: floors.isEmpty);
        for (final b in parsed) {
          if (b is AttachmentBlock) {
            final key = _attachmentKey(b);
            if (existingAttachKeys.add(key) && existingAttachKeys.add(b.url)) {
              rawBlocks.add(b);
            }
          }
        }
      }

      // 递归去重，保证整栋楼内同一附件仅渲染一次
      final blocks = _deduplicateBlocks(rawBlocks);

      if (resourceInfo != null && floors.isEmpty) {
        blocks.insert(0, resourceInfo);
      }

      final floorLikes = _parseFloorLikes(post);
      final likeBtn = post.querySelector(
        '.reply_liked, .supported, .comiis_yizan, a.voted, a.liked, .km_recommend_on, a.km_recommend_on',
      );
      final hotReplyBtn = post.querySelector('[id^="comiis_hotreply"]');
      final isHotReplyLiked = hotReplyBtn != null &&
          !hotReplyBtn.classes.contains('f_b') &&
          (hotReplyBtn.classes.contains('f_wb') ||
              hotReplyBtn.classes.contains('f_a') ||
              hotReplyBtn.classes.contains('on') ||
              hotReplyBtn.classes.contains('cur') ||
              hotReplyBtn.classes.contains('comiis_yizan'));
      final floorIsLiked = isHotReplyLiked ||
          likeBtn != null ||
          (post
                  .querySelector(
                      'a.reply_like, a.support, a[id^="reply_like_"]')
                  ?.text
                  .contains('已赞') ??
              false);
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
      final bool isUnderReview =
          postAllText.contains('正在审核中') || postAllText.contains('审核中');
      final bool isShielded = isBanned ||
          postAllText.contains('内容自动屏蔽') ||
          postAllText.contains('该帖被管理员或版主屏蔽') ||
          post.querySelector('.shield, .comiis_shield') != null ||
          (post.querySelector('.locked') != null &&
              (postAllText.contains('该帖被管理员或版主屏蔽') ||
                  postAllText.contains('内容自动屏蔽') ||
                  postAllText.contains('作者被禁止或删除')));
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

      final bool isLocked =
          postAllText.contains('本帖已被锁定') || postAllText.contains('已被锁定');

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

      final bool hasCanEdit = post.querySelector(
                'a[href*="action=edit"], a.editp, .comiis_post_edit, a[href*="mod=post&action=edit"]',
              ) !=
              null ||
          post.querySelectorAll('a').any((a) =>
              (a.attributes['href']?.contains('action=edit') ?? false) ||
              (a.text.trim() == '编辑' &&
                  (a.attributes['href']?.contains('mod=post') ?? false)));

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
          sourceLabel: metadata.sourceLabel,
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
          isBestAnswer: post.querySelector(
                    '.best_answer, .ans_best, .ans_solved, em.solved, .comiis_best, .rusld, [id^="bestanswer"], .modact_best',
                  ) !=
                  null ||
              (post.attributes['class']?.contains('best') ?? false) ||
              post.querySelector('img[src*="bestanswer"]') != null ||
              post.querySelector('img[alt*="最佳答案"]') != null ||
              post.querySelector('div[class*="best"]') != null,
          bountyPrice: floors.isEmpty ? _extractBountyPrice(doc, html) : null,
          isBountySolved: html.contains('已解决') ||
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
          canEdit: hasCanEdit,
        ),
      );
    }

    // 总页数：从分页 DOM 节点（.pg, .pages, .comiis_pg）中提取真实页码
    var totalPages = 1;
    for (final pageEl in doc.querySelectorAll(
        '.pg a, .pages a, .comiis_page a, .comiis_pg a, .page a, #pgt a, #fd_page_top a')) {
      final href = pageEl.attributes['href'] ?? '';
      final text = pageEl.text.trim();
      final p1 = int.tryParse(
          RegExp(r'thread-\d+-(\d+)').firstMatch(href)?.group(1) ?? '');
      final p2 =
          int.tryParse(RegExp(r'page=(\d+)').firstMatch(href)?.group(1) ?? '');
      final p3 = int.tryParse(text);
      final p = p1 ?? p2 ?? p3;
      if (p != null && p > totalPages && p < 10000) totalPages = p;
    }
    final pageTotalEl =
        doc.querySelector('.pg label span, .pages span, .comiis_pg label span');
    if (pageTotalEl != null) {
      final m =
          RegExp(r'共\s*(\d+)\s*页|\/\s*(\d+)\s*页').firstMatch(pageTotalEl.text);
      if (m != null) {
        final p = int.tryParse(m.group(1) ?? m.group(2) ?? '');
        if (p != null && p > totalPages) totalPages = p;
      }
    }

    // 首楼作者积分（从作者信息 DOM 中提取）
    var firstAuthorCredits = -1;
    final creditEl =
        doc.querySelector('.authi .xi1, .authi .credits, .kmuser .credits');
    if (creditEl != null) {
      firstAuthorCredits = int.tryParse(
              RegExp(r'\d+').firstMatch(creditEl.text)?.group(0) ?? '') ??
          -1;
    }
    // 点赞数（仅从 Discuz/Comiis 真实点赞 DOM 元素提取真实数值，不使用全文本模糊匹配）
    var likes = 0;
    final likeSelectors = [
      '#recommendv_add',
      'span#recommendv_add',
      '#recommend_add',
      'span#recommend_add',
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
        final rawText = el.text.trim();
        if (rawText.isNotEmpty) {
          final count = int.tryParse(
                  RegExp(r'\d+').firstMatch(rawText)?.group(0) ?? '') ??
              0;
          if (count > likes) likes = count;
        }
      }
    }
    if (floors.isNotEmpty && floors.first.likes > likes) {
      likes = floors.first.likes;
    }

    // 收藏数（从真实收藏 DOM 节点提取）
    var favorites = 0;
    final favNumEl = doc.querySelector(
      '.comiis_favorite_a_num, #favoritenumber, .thread_favtimes, #comiis_favorite_a span.comiis_favorite_a_num',
    );
    if (favNumEl != null && favNumEl.text.trim().isNotEmpty) {
      favorites = int.tryParse(
              RegExp(r'\d+').firstMatch(favNumEl.text)?.group(0) ?? '') ??
          0;
    } else {
      final favA = doc.querySelector('#comiis_favorite_a, #k_favorite');
      if (favA != null) {
        final m = RegExp(r'\d+').firstMatch(favA.text);
        if (m != null) favorites = int.tryParse(m.group(0)!) ?? 0;
      }
    }

    // 浏览量与回复量（全适配：克米移动端顶部 .comiis_view_header1、PC 端 #fj、底部 .bottom_views、左侧 td.pls.ptn.pbn 与全局正则）
    var views = 0, replies = 0;

    // 1. 克米移动端顶部详情条：<div class="comiis_view_header1"><span class="f_c y">8回复&nbsp;&nbsp;&nbsp;194阅读</span>
    final headerStatsEl = doc.querySelector(
        '.comiis_view_header1, .comiis_viewtit .comiis_view_header1, .comiis_viewtit span.f_c');
    if (headerStatsEl != null) {
      final text = headerStatsEl.text.replaceAll('&nbsp;', ' ');
      // 匹配 "194阅读" / "194 查看" / "194 浏览" / "阅读: 194" / "查看: 194"
      final vm =
          RegExp(r'(\d+)\s*(?:阅读|查看|浏览|次阅读|次查看|次浏览|阅)').firstMatch(text) ??
              RegExp(r'''(?:阅读|查看|浏览|阅)[:：\s]*(\d+)''').firstMatch(text);
      if (vm != null) views = int.tryParse(vm.group(1)!) ?? 0;

      // 匹配 "8回复" / "8 回帖" / "8 评论" / "回复: 8"
      final rm = RegExp(r'(\d+)\s*(?:回复|回帖|评论|回)').firstMatch(text) ??
          RegExp(r'''(?:回复|回帖|评论|回)[:：\s]*(\d+)''').firstMatch(text);
      if (rm != null) replies = int.tryParse(rm.group(1)!) ?? 0;
    }

    // 2. Discuz 官方 #fj 容器（klpbbs PC 与移动端：<div id="fj" class="y"><span class="xg1">查看:</span><span class="xi1">183</span><span class="pipe">|</span><span class="xg1">回复:</span><span class="xi1">8</span></div>）
    if (views <= 0 || replies <= 0) {
      final fjEl = doc.querySelector('#fj, .authi #fj, .pi #fj, div[id="fj"]');
      if (fjEl != null) {
        final fjHtml = fjEl.outerHtml;
        final vm =
            RegExp(r'''(?:查看|浏览|阅读)[:：\s]*</span>\s*<span[^>]*class="[^"]*xi1[^"]*"[^>]*>(\d+)</span>''')
                    .firstMatch(fjHtml) ??
                RegExp(r'''(?:查看|浏览|阅读)[:：\s]*<[^>]*>(\d+)<''')
                    .firstMatch(fjHtml) ??
                RegExp(r'(\d+)\s*(?:阅读|查看|浏览)').firstMatch(fjEl.text) ??
                RegExp(r'''(?:查看|浏览|阅读)[:：\s]*(\d+)''').firstMatch(fjEl.text);
        if (vm != null && views <= 0) views = int.tryParse(vm.group(1)!) ?? 0;

        final rm =
            RegExp(r'''(?:回复|评论)[:：\s]*</span>\s*<span[^>]*class="[^"]*xi1[^"]*"[^>]*>(\d+)</span>''')
                    .firstMatch(fjHtml) ??
                RegExp(r'''(?:回复|评论)[:：\s]*<[^>]*>(\d+)<''')
                    .firstMatch(fjHtml) ??
                RegExp(r'(\d+)\s*(?:回复|评论)').firstMatch(fjEl.text) ??
                RegExp(r'''(?:回复|评论)[:：\s]*(\d+)''').firstMatch(fjEl.text);
        if (rm != null && replies <= 0) {
          replies = int.tryParse(rm.group(1)!) ?? 0;
        }
      }
    }

    // 3. Discuz 标准 PC 左侧统计栏 td.pls.ptn.pbn (含查看/回复)
    if (views <= 0 || replies <= 0) {
      final plsNumEl =
          doc.querySelector('td.pls.ptn.pbn, .pls.ptn.pbn, td.pls.pbn');
      if (plsNumEl != null) {
        final xi1s = plsNumEl.querySelectorAll('.xi1');
        if (xi1s.length >= 2) {
          if (views <= 0) views = int.tryParse(xi1s[0].text.trim()) ?? 0;
          if (replies <= 0) replies = int.tryParse(xi1s[1].text.trim()) ?? 0;
        } else if (xi1s.length == 1 && views <= 0) {
          views = int.tryParse(xi1s[0].text.trim()) ?? 0;
        }
      }
    }

    // 4. 克米移动端底部视口 bottom_views 与 viewtit
    if (views <= 0 || replies <= 0) {
      final detailBv = doc.querySelector(
          '.bottom_views, .forumlist_li_tops .bottom_views, .comiis_viewtit .bottom_views');
      if (detailBv != null) {
        final ems = detailBv.querySelectorAll('em');
        if (ems.length >= 2) {
          if (views <= 0) views = int.tryParse(ems[0].text.trim()) ?? 0;
          if (replies <= 0) replies = int.tryParse(ems[1].text.trim()) ?? 0;
        } else if (ems.length == 1 && views <= 0) {
          views = int.tryParse(ems[0].text.trim()) ?? 0;
        }
      }
    }

    // 5. 回复数徽章
    if (replies <= 0) {
      final kmv = doc.querySelector(
          '.comiis_kmvnum, .comiis_position_key, span[class*="comiis_kmvnum"], .comiis_pltit span.f_d, .comiis_pltit h2');
      if (kmv != null) {
        final kmvVal =
            int.tryParse(RegExp(r'\d+').firstMatch(kmv.text)?.group(0) ?? '') ??
                0;
        if (kmvVal > 0) replies = kmvVal;
      }
    }

    // 6. 通用全局正则匹配（支持数字在前与数字在后）
    if (views <= 0) {
      final vm = RegExp(r'(\d+)\s*(?:阅读|次阅读|次查看|次浏览)').firstMatch(html) ??
          RegExp(r'''(?:查看|浏览|阅读|阅)[:：\s]*<[^>]*class="[^"]*xi1[^"]*"[^>]*>(\d+)<''')
              .firstMatch(html) ??
          RegExp(r'''(?:查看|浏览|阅读|阅)[:：\s]*<[^>]*>(\d+)<''').firstMatch(html) ??
          RegExp(r'''(?:查看|浏览|阅读|阅)[:：\s]+(\d+)''').firstMatch(html);
      if (vm != null) {
        views = int.tryParse(vm.group(1)!) ?? 0;
      }
    }

    if (replies <= 0) {
      final rm = RegExp(
                  r'全部评论\s*<span[^>]*class="[^"]*f_d[^"]*"[^>]*>(\d+)</span>')
              .firstMatch(html) ??
          RegExp(r'全部评论\s*<span[^>]*>(\d+)</span>').firstMatch(html) ??
          RegExp(r'全部评论\s*[:：\s]*(\d+)').firstMatch(html) ??
          RegExp(r'(\d+)\s*(?:回复|次回复|条回复|条评论)').firstMatch(html) ??
          RegExp(r'''(?:回复|回帖|评论)[:：\s]*<[^>]*class="[^"]*xi1[^"]*"[^>]*>(\d+)<''')
              .firstMatch(html) ??
          RegExp(r'''(?:回复|回帖|评论)[:：\s]*<[^>]*>(\d+)<''').firstMatch(html) ??
          RegExp(r'''(?:回复|回帖|评论)[:：\s]+(\d+)''').firstMatch(html);
      if (rm != null) {
        replies = int.tryParse(rm.group(1)!) ?? 0;
      }
    }

    if (views <= 0 || replies <= 0) {
      final vstat =
          doc.querySelector('.klp-vstat, .thread-info, .klp-thread-stats');
      if (vstat != null) {
        final text = vstat.text;
        final vm = RegExp(r'(\d+)\s*(?:阅读|查看|浏览)').firstMatch(text) ??
            RegExp(r'(?:阅读|查看|浏览)[:：\s]*(\d+)').firstMatch(text);
        if (vm != null && views <= 0) views = int.tryParse(vm.group(1)!) ?? 0;
        final rm = RegExp(r'(\d+)\s*(?:回复|回帖|评论)').firstMatch(text) ??
            RegExp(r'(?:回复|回帖|评论)[:：\s]*(\d+)').firstMatch(text);
        if (rm != null && replies <= 0) {
          replies = int.tryParse(rm.group(1)!) ?? 0;
        }
      }
    }

    final floorReplies = floors.length > 1 ? (floors.length - 1) : 0;
    if (floorReplies > replies) {
      replies = floorReplies;
    }

    if (replies > 0) {
      final calculatedPages = replies <= 9 ? 1 : 1 + ((replies - 9 + 9) ~/ 10);
      if (totalPages < calculatedPages) {
        totalPages = calculatedPages;
      }
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
      final alt = stampEl.attributes['alt'] ??
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
        final avatar =
            _avatarUrl(src) ?? (uid != null ? AppConfig.avatarUrl(uid) : '');
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

    String? coverUrl;
    if (floors.isNotEmpty) {
      for (final img in floors.first.images) {
        if (_isValidCoverUrl(img)) {
          coverUrl = img;
          break;
        }
      }
    }

    // 收藏与点赞状态（根据 Discuz 与 Comiis 真实 DOM/文本类识别）
    var isFavorited = false;
    var hasExplicitFavState = false;

    // 1. 严格锁定针对当前帖子的收藏控件（坚决排除版块关注按钮 type=forum / handlekey=forum_fav）
    final favElements = doc.querySelectorAll(
      '#comiis_favorite_a, #k_favorite, #a_favorite, a[href*="ac=favorite"], a[href*="delfav"], a[href*="handlekey=favorite_thread"], .thread_fav, .k_fav',
    );
    for (final el in favElements) {
      final href = el.attributes['href'] ?? '';
      // 绝对排除版块关注链接与用户中心通用收藏夹入口，严防将“关注版块”的 op=delete 误判为帖子已收藏
      if (href.contains('type=forum') ||
          href.contains('handlekey=forum_fav') ||
          href.contains('do=favorite&view=me') ||
          href.contains('do=favorite&type=forum') ||
          href.contains('do=favorite&type=all')) {
        continue;
      }

      final title = el.attributes['title'] ?? '';
      final text = el.text.trim();
      final icon = el.querySelector('i');

      // 明确未激活判断（克米手机版：i 或 a 明确含有 f_b 灰色默认类；或 PC 端 Discuz 默认文本为“收藏本帖”/“收藏”且无激活类）
      final isInactive = el.classes.contains('f_b') ||
          (icon != null &&
              (icon.classes.contains('f_b') ||
                  (icon.classes.contains('comiis_favorite_a_color') &&
                      icon.classes.contains('f_b'))));

      // 明确激活为已收藏（需符合 Discuz/Comiis 针对该帖子的明确激活类、反向操作链接或显式文本）
      final isFavEl = !isInactive &&
          (el.classes.contains('fav_on') ||
              el.classes.contains('km_fav_on') ||
              (icon != null &&
                  (icon.classes.contains('fav_on') ||
                      icon.classes.contains('km_fav_on') ||
                      (icon.classes.contains('comiis_favorite_a_color') &&
                          icon.classes.contains('f_a')))) ||
              (el.classes.contains('on') &&
                  (text.contains('取消') ||
                      title.contains('取消') ||
                      href.contains('delfav') ||
                      href.contains('delete') ||
                      text.contains('已收藏'))) ||
              href.contains('op=delete') ||
              href.contains('delfav') ||
              text.contains('已收藏') ||
              text.contains('取消收藏') ||
              title.contains('已收藏') ||
              title.contains('取消收藏'));

      if (isFavEl) {
        isFavorited = true;
        hasExplicitFavState = true;
        break;
      }

      // 未命中激活标记，且属于收藏按钮元素（默认状态为明确未收藏）
      if (isInactive || el.id == 'comiis_favorite_a' || el.id == 'k_favorite') {
        hasExplicitFavState = true;
      }
    }

    if (!isFavorited) {
      final secondaryFav = doc.querySelector(
        '#k_favorite.fav_on, #comiis_favorite_a.fav_on, #comiis_favorite_a.km_fav_on, a.fav_on, a.km_fav_on, a[href*="op=delete"][href*="type=thread"], a[href*="delfav"][href*="type=thread"]',
      );
      if (secondaryFav != null) {
        isFavorited = true;
        hasExplicitFavState = true;
      }
    }

    final recColor = doc.querySelector('.comiis_recommend_color');
    final isComiisRecLiked = recColor != null &&
        !recColor.classes.contains('f_b') &&
        (recColor.classes.contains('f_a') ||
            recColor.classes.contains('on') ||
            recColor.classes.contains('cur') ||
            recColor.classes.contains('comiis_yizan') ||
            recColor.classes.contains('km_recommend_on'));
    final isLiked = isComiisRecLiked ||
        doc.querySelector(
              '#recommendv_add.on, #recommend_add.on, a.comiis_recommend_addkey.on, a.comiis_recommend_addkey.km_recommend_on',
            ) !=
            null;

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

    final aiSummary = parseAiSummary(html, doc: doc);

    // 发布日期（首楼时间）与最近回复日期（末楼时间）
    final publishDate = floors.isNotEmpty ? floors.first.timeText : '';
    final lastReplyDate = floors.isNotEmpty ? floors.last.timeText : '';
    // 回帖排序方式识别（正序 / 倒序）
    bool isDescOrder = false;
    int? targetOrdertype;
    final orderLink = doc
        .querySelectorAll(
      '.comiis_ordertype a, a.show[href*="ordertype"], a[href*="ordertype"], a[href*="order="]',
    )
        .where((a) {
      final href = a.attributes['href'] ?? '';
      final t = a.text.trim();
      return href.contains('ordertype=') ||
          t.contains('正序') ||
          t.contains('倒序');
    }).firstOrNull;
    if (orderLink != null) {
      final href = orderLink.attributes['href'] ?? '';
      final t = orderLink.text.trim();
      if (href.contains('ordertype=2') || t.contains('正序')) {
        // 链接指向 ordertype=2 或显示「正序」，说明当前处于【倒序】，点击该链接将切换为【正序】
        isDescOrder = true;
        targetOrdertype = 2;
      } else if (href.contains('ordertype=1') || t.contains('倒序')) {
        // 链接指向 ordertype=1 或显示「倒序」，说明当前处于【正序】，点击该链接将切换为【倒序】
        isDescOrder = false;
        targetOrdertype = 1;
      }
    } else {
      // 保底推断：通过楼层编号序列的单调性（递增 vs 递减）严格判定排序
      // 必须排除首楼（楼主），仅比对回复楼层的单调性，避免 1# 楼主干扰
      final numFloors = <int>[];
      final startIdx = (floors.isNotEmpty &&
              (floors.first.floorNumber == '楼主' || floors.first.isThreadAuthor))
          ? 1
          : 0;
      for (int i = startIdx; i < floors.length; i++) {
        final fl = floors[i];
        final m = RegExp(r'\d+').firstMatch(fl.floorNumber);
        if (m != null) {
          final n = int.tryParse(m.group(0)!);
          if (n != null && n > 0) numFloors.add(n);
        }
      }
      if (numFloors.length >= 2) {
        int descCount = 0;
        int ascCount = 0;
        for (int i = 0; i < numFloors.length - 1; i++) {
          if (numFloors[i] > numFloors[i + 1]) descCount++;
          if (numFloors[i] < numFloors[i + 1]) ascCount++;
        }
        if (descCount > ascCount) {
          isDescOrder = true;
          targetOrdertype = 2;
        } else if (ascCount > descCount) {
          isDescOrder = false;
          targetOrdertype = 1;
        }
      } else if (parsedCurrentPage == 1 &&
          numFloors.length == 1 &&
          floors.length >= 2) {
        // 仅在第 1 页且只有一个数字楼层（如楼主 + 41# 倒序首楼回复）时
        if (numFloors.first > 3) {
          isDescOrder = true;
          targetOrdertype = 2;
        }
      }
    }

    if (threadAuthor == null ||
        threadAuthor.isEmpty ||
        threadAuthor.contains('***')) {
      if (floors.isNotEmpty &&
          floors.first.author.isNotEmpty &&
          !floors.first.author.contains('***')) {
        threadAuthor = floors.first.author;
        threadAuthorUid ??= floors.first.uid;
      }
    }

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
      hasExplicitFavState: hasExplicitFavState,
      isLiked: isLiked,
      favid: favid,
      aiSummary: aiSummary,
      isDescOrder: isDescOrder,
      targetOrdertype: targetOrdertype ?? (isDescOrder ? 2 : 1),
      authorUid: threadAuthorUid,
      author: threadAuthor,
    );
  }

  /// 从用户收藏页面 HTML 中提取指定 ID（tid 或 fid）的真实 favid
  static int? extractFavidFromHtml(String html, int id,
      {String type = 'thread'}) {
    final doc = html_parser.parse(html);
    final pattern1 = type == 'forum'
        ? (String href) =>
            href.contains('fid=$id') ||
            href.contains('forum-$id-') ||
            href.contains('id=$id')
        : (String href) =>
            href.contains('tid=$id') ||
            href.contains('thread-$id-') ||
            href.contains('id=$id');
    final pattern2 = type == 'forum'
        ? (String outer) =>
            outer.contains('fid=$id') ||
            outer.contains('forum-$id-') ||
            outer.contains('id=$id')
        : (String outer) =>
            outer.contains('tid=$id') ||
            outer.contains('thread-$id-') ||
            outer.contains('id=$id');

    // 1. 在包含当前 id 的容器节点（克米 .comiis_mysclist li, li.mysclist_li, tr, li, div[id^="fav_"]）中检索
    for (final container in doc.querySelectorAll(
        '.comiis_mysclist li, li.mysclist_li, #favorite_ul li, tr, li, div[id^="fav_"]')) {
      final outer = container.outerHtml;
      if (pattern2(outer)) {
        for (final a in container
            .querySelectorAll('a[href*="favid="], a[href*="op=delete"]')) {
          final href = a.attributes['href'] ?? '';
          final m = RegExp(r'favid=(\d+)').firstMatch(href);
          if (m != null) {
            final fId = int.tryParse(m.group(1)!);
            if (fId != null && fId > 0) return fId;
          }
        }
        for (final inp
            in container.querySelectorAll('input[name*="favorite"]')) {
          final val = inp.attributes['value'] ?? '';
          final fId = int.tryParse(val);
          if (fId != null && fId > 0) return fId;
        }
        final idAttr = container.attributes['id'] ?? '';
        final mId = RegExp(r'fav_(\d+)').firstMatch(idAttr);
        if (mId != null) {
          final fId = int.tryParse(mId.group(1)!);
          if (fId != null && fId > 0) return fId;
        }
      }
    }

    // 2. 直接检索 delete 链接中的 favid
    for (final a in doc.querySelectorAll(
        'a[href*="ac=favorite"][href*="op=delete"], a[href*="favid="]')) {
      final href = a.attributes['href'] ?? '';
      if (pattern1(href) ||
          (a.parent != null && pattern2(a.parent!.outerHtml))) {
        final m = RegExp(r'favid=(\d+)').firstMatch(href);
        if (m != null) {
          final fId = int.tryParse(m.group(1)!);
          if (fId != null && fId > 0) return fId;
        }
      }
    }

    // 3. 匹配 PC 表单中的 input[name*="favorite"] 与紧随其后的目标 a 链接
    final regInput = type == 'forum'
        ? RegExp(
                '(?:value|vid)=["\'](\\d+)["\'][^<]*<a[^>]*href=["\'][^"\']*(?:fid=$id|forum-$id-)',
                dotAll: true)
            .firstMatch(html)
        : RegExp(
                '(?:value|vid)=["\'](\\d+)["\'][^<]*<a[^>]*href=["\'][^"\']*(?:tid=$id|thread-$id-)',
                dotAll: true)
            .firstMatch(html);
    if (regInput != null) {
      final fidVal = int.tryParse(regInput.group(1) ?? '');
      if (fidVal != null && fidVal > 0) return fidVal;
    }

    // 3. 全局正则保底（双向匹配：favid 在前或在后）
    final reg1 = type == 'forum'
        ? RegExp('favid=(\\d+)[^"\'<]*?(?:forum-$id-|fid=$id)', dotAll: true)
            .firstMatch(html)
        : RegExp('favid=(\\d+)[^"\'<]*?(?:thread-$id-|tid=$id)', dotAll: true)
            .firstMatch(html);
    if (reg1 != null) {
      final fidVal = int.tryParse(reg1.group(1) ?? '');
      if (fidVal != null && fidVal > 0) return fidVal;
    }

    final reg2 = type == 'forum'
        ? RegExp('(?:forum-$id-|fid=$id)[^"\'<]*?favid=(\\d+)', dotAll: true)
            .firstMatch(html)
        : RegExp('(?:thread-$id-|tid=$id)[^"\'<]*?favid=(\\d+)', dotAll: true)
            .firstMatch(html);
    if (reg2 != null) {
      final fidVal = int.tryParse(reg2.group(1) ?? '');
      if (fidVal != null && fidVal > 0) return fidVal;
    }

    final reg3 = type == 'forum'
        ? RegExp('id=["\']fav_(\\d+)["\'].*?(?:forum-$id-|fid=$id)',
                dotAll: true)
            .firstMatch(html)
        : RegExp('id=["\']fav_(\\d+)["\'].*?(?:thread-$id-|tid=$id)',
                dotAll: true)
            .firstMatch(html);
    if (reg3 != null) {
      return int.tryParse(reg3.group(1) ?? '');
    }
    return null;
  }

  static String? _extractBountyPrice(html_dom.Document doc, String html) {
    final rwdEl = doc.querySelector(
      '.rusl, .rusld, .rwd, div.comiis_rwds, span.reward, table.rwd, div.rwd_c, .comiis_reward, .comiis_xstop, .comiis_xsda',
    );
    if (rwdEl != null) {
      final text = rwdEl.text;
      final solvedM = RegExp(
        r'(?:已解决并结束|已解决|结贴)[^\d]*\(?\s*(\d+)\s*([^)\r\n\s]+)?\)?',
      ).firstMatch(text);
      if (solvedM != null) {
        final amount = solvedM.group(1);
        final unit = solvedM.group(2)?.trim() ?? '粒铁粒';
        return '$amount $unit';
      }
      final m = RegExp(
        r'(\d+)\s*(?:个|粒)?(?:铁粒|金粒|金币|经验|贡献|积分)',
      ).firstMatch(text);
      if (m != null) return m.group(0);
    }
    final solvedM = RegExp(
      r'(?:本悬赏已解决并结束|悬赏已解决)[^\d]*\(?\s*(\d+)\s*([^)\r\n\s]+)?\)?',
    ).firstMatch(html);
    if (solvedM != null) {
      final amount = solvedM.group(1);
      final unit = solvedM.group(2)?.trim() ?? '粒铁粒';
      return '$amount $unit';
    }
    return null;
  }

  static int _parseFloorLikes(html_dom.Element post) {
    // 1. 克隆楼层元素并剔除非操作栏区域（正文、用户信息、楼层标志等），
    // 彻底防止正文字符（如“必须支持”）与楼层号（如“20#”）连缀被误识别为点赞数
    final cleanPost = post.clone(true);
    for (final sel in const [
      '.pct',
      '.pcb',
      '.t_fsz',
      '.t_f',
      '[id^="postmessage_"]',
      '.pi',
      '.pti',
      '.authi',
      '[id^="postnum"]',
      '.replyfloor_box',
      '.replyfloor_tail_floor',
      '.sign',
      '[id^="authorposton"]',
      '.pls',
      '.favatar',
      '.userinfo',
      '.modact',
      '.psth',
    ]) {
      cleanPost.querySelectorAll(sel).forEach((e) => e.remove());
    }

    // 2. 针对点赞按钮及专属容器进行精准解析
    for (final sel in const [
      'a.replyadd',
      'a.reply_like',
      'a.support',
      '.postreview a.support',
      'span[id^="comiis_recommend"]',
      'span[id^="post_support_"]',
      'span[id^="support_"]',
      'span[id^="review_support_"]',
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
      'a[href*="action=support"] span',
      'a[href*="action=support"]',
    ]) {
      for (final el in cleanPost.querySelectorAll(sel)) {
        final txt = el.text.trim();
        if (txt.isEmpty) continue;
        final m =
            RegExp(r'^(?:支持|赞|顶)?\s*[(（]?\s*(\d+)\s*[)）]?$').firstMatch(txt) ??
                RegExp(r'(?:支持|赞|顶)\s*[:：]?\s*[(（]?\s*(\d+)\s*[)）]?')
                    .firstMatch(txt);
        if (m != null) {
          final count = int.tryParse(m.group(1)!);
          if (count != null && count > 0) return count;
        } else if (RegExp(r'^\d+$').hasMatch(txt)) {
          final count = int.tryParse(txt);
          if (count != null && count > 0) return count;
        }
      }
    }

    // 3. 针对特定 ID 节点在 HTML 中的数字提取（如 id="review_support_11128108">2<）
    final postHtml = cleanPost.outerHtml;
    final idMatch = RegExp(
      r'''id=["'](?:comiis_recommend|post_support_|support_|review_support_)(\d+)["'][^>]*>\s*(\d+)\s*<''',
    ).firstMatch(postHtml);
    if (idMatch != null) {
      final count = int.tryParse(idMatch.group(2)!);
      if (count != null && count > 0) return count;
    }

    return 0;
  }

  // ---------------------------------------------------------------------
  // 签到头部与实时数据（k_misign 插件 1:1 对齐）
  // ---------------------------------------------------------------------
  static SignHeaderInfo parseSignPageData(
    String html, {
    String? defaultUsername,
    int? defaultUid,
    int? serverDay,
  }) =>
      DiscuzSignParser.page(html,
          defaultUsername: defaultUsername,
          defaultUid: defaultUid,
          serverDay: serverDay);

  // ---------------------------------------------------------------------
  // 签到排行（k_misign）
  // 兼容多种结构：klpbbs（tbody#autolist_{uid}）与本地 v4.3.0（table#J_list_detail）
  // ---------------------------------------------------------------------
  static List<SignEntry> parseSignList(String html) {
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

    final result = <SignEntry>[];

    // 结构一：tbody[id^="autolist_"]（klpbbs 新版）
    final autolists = doc.querySelectorAll('tbody[id^="autolist_"]');
    if (autolists.isNotEmpty) {
      for (final tbody in autolists) {
        final idAttr = tbody.attributes['id'] ?? '';
        final uid = int.tryParse(idAttr.replaceFirst('autolist_', '')) ?? 0;

        final nameA = tbody.querySelector('h4 a');
        final name = nameA?.text.trim() ?? '';
        if (name.isEmpty || uid <= 0) continue;

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
        final rw = RegExp(r'(?:上次奖励|总奖励)\s*(.+)').firstMatch(p);
        final rewardText = rw?.group(1)?.trim() ?? '';
        final isTotalReward = p.contains('总奖励');

        result.add(
          SignEntry(
            uid: uid,
            name: name,
            timeText: timeText,
            totalDays: totalDays,
            monthDays: monthDays,
            rewardText: rewardText,
            totalReward: isTotalReward ? rewardText : '',
          ),
        );
      }
      return result;
    }

    // 结构二与三：移动端列表与通用表格（ul.comiis_sign_list li, .ranking_list li, .sign_list li, table.dt tr 等）
    if (result.isEmpty) {
      final listItems = doc.querySelectorAll(
        'ul.comiis_sign_list li, .k_misign_list li, .ranking_list li, ul.ranking_list li, .sign_list li, .sign_box li, div.comiis_p12 li, table.dt tr, table.tl tr, #ranklist tr, .bm_c table tr, .ct2_a tr, table tr',
      );
      for (final el in listItems) {
        if (el.querySelector('th') != null &&
            el.querySelectorAll('td').isEmpty) {
          continue;
        }
        html_dom.Element? a;
        String name = '';
        for (final candidate in el.querySelectorAll(
          '.author, h4 a, .name a, .ranking_name a, a[href*="space-uid-"], a[href*="uid="], a[href*="space"]',
        )) {
          final t = candidate.text.trim();
          if (t.isNotEmpty && t != '签到' && t != '排行榜' && t != '更多') {
            a = candidate;
            name = t;
            break;
          }
        }
        if (a == null || name.isEmpty) continue;
        final uid = _uidFromHref(a.attributes['href'] ?? '') ?? 0;
        if (uid <= 0) continue;

        final timeEl = el.querySelector(
          '.time, .timeText, span.xg1, span.kmtime, td.time, .ranking_time',
        );
        var timeText = timeEl?.text.trim() ?? '';

        int totalDays = 0;
        final totalMatch = RegExp(
          r'总(?:天数|签到)?[:：\s]*(\d+)',
        ).firstMatch(el.text);
        if (totalMatch != null) {
          totalDays = int.tryParse(totalMatch.group(1)!) ?? 0;
        } else {
          final d = el.querySelector('.ranking_days, .total_days')?.text;
          if (d != null) {
            totalDays =
                int.tryParse(RegExp(r'(\d+)').firstMatch(d)?.group(1) ?? '') ??
                    0;
          }
        }

        int monthDays = 0;
        final monthMatch = RegExp(
          r'月(?:天数|签到)?[:：\s]*(\d+)',
        ).firstMatch(el.text);
        if (monthMatch != null) {
          monthDays = int.tryParse(monthMatch.group(1)!) ?? 0;
        } else {
          final d = el.querySelector('.ranking_mdays, .month_days')?.text;
          if (d != null) {
            monthDays =
                int.tryParse(RegExp(r'(\d+)').firstMatch(d)?.group(1) ?? '') ??
                    0;
          }
        }

        String rewardText = '';
        String totalReward = '';
        String levelText = '';
        final levelEl = el.querySelector('.ranking_level, .usergroup, .level');
        if (levelEl != null && levelEl.text.trim().isNotEmpty) {
          levelText = levelEl.text.trim();
        }

        final rewardMatch =
            RegExp(r'(?:上次奖励|奖励)[:：\s]*([^\s,，;]+)').firstMatch(el.text);
        if (rewardMatch != null) rewardText = rewardMatch.group(1) ?? '';
        final totalRewardMatch =
            RegExp(r'总奖励[:：\s]*([^\s,，;]+)').firstMatch(el.text);
        if (totalRewardMatch != null) {
          totalReward = totalRewardMatch.group(1) ?? '';
        }

        final rankRewardEl = el.querySelector('.ranking_reward');
        if (rankRewardEl != null && rankRewardEl.text.trim().isNotEmpty) {
          final txt = rankRewardEl.text.trim();
          if (totalReward.isEmpty) totalReward = txt;
          if (rewardText.isEmpty) rewardText = txt;
        }

        // 如果是标准 table tr 结构且未匹配到标签，从 td 顺序提取
        final tds = el.querySelectorAll('td');
        if (tds.length >= 5) {
          final tdTotal = int.tryParse(
              RegExp(r'(\d+)').firstMatch(tds[1].text)?.group(1) ?? '');
          if (tdTotal != null && tdTotal > 0) totalDays = tdTotal;
          final tdMonth = int.tryParse(
              RegExp(r'(\d+)').firstMatch(tds[2].text)?.group(1) ?? '');
          if (tdMonth != null && tdMonth >= 0) monthDays = tdMonth;
          if (timeText.isEmpty) timeText = tds[3].text.trim();
          if (levelText.isEmpty) levelText = tds[4].text.trim();
          if (tds.length >= 6) {
            final tdRew = tds[5].text.trim();
            if (tdRew.isNotEmpty) {
              totalReward = tdRew;
              rewardText = tdRew;
            }
          }
        } else if (tds.length >= 3 && (totalDays == 0 && monthDays == 0)) {
          for (final td in tds) {
            final txt = td.text.trim();
            if (txt.contains('LV.') ||
                txt.contains('[LV') ||
                txt.contains('锭') ||
                txt.contains('石') ||
                txt.contains('木')) {
              levelText = txt;
            } else if (timeText.isEmpty &&
                (txt.contains('-') || txt.contains(':'))) {
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
            usergroup: levelText,
            totalReward: totalReward.isNotEmpty
                ? totalReward
                : (rewardText.contains('总') ? rewardText : ''),
          ),
        );
      }
    }

    return result;
  }

  /// 从网页端日历 HTML 中解析已签到日期（支持 CDATA 解包、多类选择器及高精度零回溯正则双重保障）
  static Set<int> parseSignedDaysFromCalendarHtml(
    String html, {
    int? expectedYear,
    int? expectedMonth,
  }) =>
      DiscuzSignParser.calendar(html, year: expectedYear, month: expectedMonth)
          .days;

  // ---------------------------------------------------------------------
  // 小黑屋（违规公示）
  // ---------------------------------------------------------------------
  static ({List<DarkroomEntry> entries, int? nextCid}) parseDarkroom(
      String html) {
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

    // -1. 锁定、封禁或不存在空间严格检测（如被封禁、注销或锁定）
    final pageTitle = doc.querySelector('title')?.text.trim() ?? '';
    final msgBox = doc.querySelector(
        '#messagetext, .jump_c, .comiis_jump, .comiis_tip, .alert_error, .alert_info, .prompt');
    final msgBoxText = msgBox?.text.replaceAll('&nbsp;', ' ').trim() ?? '';

    final bool isLocked = ((html.contains('空间已被锁定无法访问') ||
                html.contains('抱歉，您指定的用户空间不存在') ||
                html.contains('抱歉，您访问的用户不存在或已被删除') ||
                msgBoxText.contains('已被删除') ||
                msgBoxText.contains('不存在') ||
                (pageTitle.contains('提示信息') &&
                    !pageTitle.contains('资料') &&
                    !pageTitle.contains('空间'))) &&
            !html.contains('的个人资料') &&
            !html.contains('的个人空间')) ||
        (html.contains('空间已被锁定') &&
            !html.contains('的个人资料') &&
            !html.contains('的个人空间'));

    if (isLocked) {
      String reason = '空间已被锁定无法访问，如有疑问请联系管理员';
      if (msgBoxText.isNotEmpty) {
        reason = msgBoxText.split('\n').first.trim();
      } else if (html.contains('抱歉，您指定的用户空间不存在')) {
        reason = '抱歉，您指定的用户空间不存在';
      } else if (html.contains('抱歉，您访问的用户不存在或已被删除')) {
        reason = '抱歉，您访问的用户不存在或已被删除';
      }
      return UserSpace(
        uid: uid,
        username: '',
        isLocked: true,
        lockReason: reason,
      );
    }

    // 0. 关键防御：彻底移除顶部导航栏、登录用户身份条、全站页脚，防止抓取到当前登录用户的用户名与积分
    final cleanDoc = doc.clone(true);
    cleanDoc
        .querySelectorAll(
          '#toptb, #hd, #um, .hdc, .comiis_head, .comiis_nav, #nv, #ft, .footer, .comiis_sidenv, #comiis_sidenv, #comiis_menu',
        )
        .forEach((e) => e.remove());

    // 1. 用户名提取（优先目标个人空间标题 #uhd / h2.mbn / meta 标签）
    String username =
        cleanDoc.querySelector('#uhd .klp-uhead-name')?.text.trim() ?? '';
    final descMeta = cleanDoc.querySelector('meta[name="description"]');
    if (username.isEmpty && descMeta != null) {
      final c = descMeta.attributes['content'] ?? '';
      final m = RegExp(r'^(.+?)的个人资料').firstMatch(c);
      if (m != null) username = m.group(1)!.trim();
    }
    if (username.isEmpty) {
      final title = cleanDoc.querySelector('title')?.text.trim() ?? '';
      final m = RegExp(r'^(.+?)的个人资料').firstMatch(title) ??
          RegExp(r'^(.+?)的个人空间').firstMatch(title);
      if (m != null) username = m.group(1)!.trim();
    }
    if (username.isEmpty) {
      final uhdH2 = cleanDoc.querySelector(
        '#uhd h2.mt, #uhd .tb_h h2, #uhd h2, h2.mbn, div.pbm h2.xs2',
      );
      if (uhdH2 != null) {
        final clone = uhdH2.clone(true);
        clone.querySelectorAll('span, em, a').forEach((e) => e.remove());
        username = clone.text.trim();
      }
    }
    if (username.isEmpty) {
      final h2 = cleanDoc.querySelector(
        '.comiis_space_tx h2, h2.fyy, span.user_tit, .user_tit',
      );
      if (h2 != null) username = h2.text.trim();
    }

    // 从页面文本提取字段（严格限定在被访问用户的资料区域，绝不全局抓取导致串号）
    String credits = '', regdate = '', lastvisit = '', signature = '';
    String level = '', levelName = '', group = '';
    final levEl = cleanDoc.querySelector(
      '.comiis_space_tx span.kmlevs.kmlv, .comiis_space_tx span.kmlevs.bg_0, .comiis_space_tx span.user_lev, .comiis_space_tx span.kmlevs, .comiis_space_tx span.kmlv, .comiis_space_tx [class*="level"], #uhd #g_up',
    );
    if (levEl != null) level = levEl.text.trim();
    final levNameEl = cleanDoc.querySelector(
      '.comiis_space_tx span.kmlev, .comiis_space_tx a[href*="usergroup"], .comiis_space_tx [class*="level"], #uhd a[href*="usergroup"], #psts a[href*="usergroup"]',
    );
    if (levNameEl != null) levelName = levNameEl.text.trim();

    // 作用域限制在个人资料核心区（#psts, .pf_l, #ct, .comiis_space_tx）
    final mainScope =
        cleanDoc.querySelector('#ct, #psts, .pf_l, .comiis_space_tx') ??
            cleanDoc.body;
    final text = mainScope?.text ?? '';
    final cm = RegExp(r'积分\s*[:：]?\s*(\d+)').firstMatch(text) ??
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
    for (final li
        in doc.querySelectorAll('.pf_l li, ul.cl li, #psts li, .pbm li, li')) {
      final span = li.querySelector('span, em, th, span.dt, span.kmtit');
      if (span != null && span.text.trim().replaceAll(' ', '') == '个人签名') {
        final contentEl = li.querySelector(
                'table td div, table td, .profile_face, div[align="center"]') ??
            li.querySelector('table') ??
            li.querySelector('div');
        if (contentEl != null) {
          signature = (contentEl.innerHtml.isNotEmpty
                  ? contentEl.innerHtml
                  : contentEl.text)
              .trim();
        } else {
          final clone = li.clone(true);
          clone.querySelector('em, th, span.dt, span.kmtit, span')?.remove();
          signature =
              (clone.innerHtml.isNotEmpty ? clone.innerHtml : clone.text)
                  .trim();
        }
        break;
      }
    }
    final modernSignature = cleanDoc.querySelector('#ct .klp-sig');
    if (modernSignature != null) signature = modernSignature.innerHtml.trim();
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
    for (final medal
        in cleanDoc.querySelectorAll('#ct .klp-medals .klp-medal')) {
      final img = _medalUrl(medal.querySelector('img')?.attributes['src']);
      if (img.isEmpty || medals.any((item) => item.img == img)) continue;
      final name = medal.querySelector('.k-tip b, .k-ellip')?.text.trim() ?? '';
      final desc = medal.querySelector('.k-tip > span')?.text.trim() ?? '';
      // 新模板只提供勋章图片，不提供 medalid；展示时保留未知 ID，不能用于写操作。
      medals.add((id: 0, name: name, desc: desc, img: img));
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
        r'(主题|回帖|回复|好友|记录|相册|分享|帖子|人气|空间访问量|访问量|获赞|点赞|收到的赞|被赞|支持)数?\s*[:：]?\s*(\d+)',
      ).firstMatch(aText);
      if (sm != null) {
        final k = sm.group(1)!;
        final v = sm.group(2)!;
        if (k == '主题' || k == '帖子') stats['主题'] = v;
        if (k == '回帖' || k == '回复') stats['回复'] = v;
        if (k == '好友') stats['好友'] = v;
        if (k == '人气' || k == '空间访问量' || k == '访问量') stats['人气'] = v;
        if (k == '获赞' || k == '点赞' || k == '收到的赞' || k == '被赞' || k == '支持') {
          stats['获赞'] = v;
        }
        if (k == '记录') stats['记录'] = v;
        if (k == '相册') stats['相册'] = v;
      }
      final sm2 = RegExp(r'(\d+)\s*(?:人气|次访问|访问量)').firstMatch(aText);
      if (sm2 != null) {
        stats.putIfAbsent('人气', () => sm2.group(1)!);
      }
      final smLikes =
          RegExp(r'(\d+)\s*(?:获赞|个获赞|次获赞|个赞|次被赞|人点赞|人赞)').firstMatch(aText);
      if (smLikes != null) {
        stats.putIfAbsent('获赞', () => smLikes.group(1)!);
      }
    }

    final viewsEl = doc.querySelector(
        '#space_views, .views, .fyy, .comiis_space_views, span[class*="fyy"]');
    if (viewsEl != null) {
      final vm = RegExp(r'(\d+)').firstMatch(viewsEl.text);
      if (vm != null) {
        stats['人气'] = vm.group(1)!;
      }
    }

    // 1) PC 现代版统计磁贴与头部统计 (.klp-statgrid, .klp-uhead-stats, .klp-acttile)
    for (final div in cleanDoc
        .querySelectorAll('.klp-statgrid > div, .klp-statgrid div')) {
      final b = div.querySelector('b, .k-mono');
      final s = div.querySelector('span');
      if (b != null && s != null) {
        final val = b.text.trim();
        final rawLbl = s.text.split('·').first.split('[').first.trim();
        final label = rawLbl
            .replaceAll(':', '')
            .replaceAll('：', '')
            .replaceAll(' ', '')
            .trim();
        if (label.isNotEmpty && val.isNotEmpty) {
          if (label == '积分') {
            creditsDetail['积分'] = val;
            credits = val;
          } else if (label == '经验') {
            creditsDetail['经验'] = val;
          } else if (label.contains('铁粒') || label == '金粒') {
            creditsDetail['铁粒'] = val;
          } else if (label.contains('铁锭')) {
            creditsDetail['铁锭'] = val;
          } else if (label.contains('贡献')) {
            creditsDetail['贡献'] = val;
          } else if (label.contains('钻石')) {
            creditsDetail['钻石'] = val;
          } else if (label.contains('下界之星')) {
            creditsDetail['下界之星'] = val;
          } else if (label == '火药') {
            creditsDetail[label] = val;
          } else {
            gameProfile[label] = val;
          }
        }
      }
    }

    for (final el in cleanDoc
        .querySelectorAll('.klp-uhead-stats a, .klp-uhead-stats span')) {
      final b = el.querySelector('b, .k-mono');
      final s = el.querySelector('span');
      if (b != null && s != null) {
        final val = b.text.replaceAll(',', '').trim();
        final rawLbl = s.text.split('·').first.split('[').first.trim();
        final label = rawLbl
            .replaceAll(':', '')
            .replaceAll('：', '')
            .replaceAll(' ', '')
            .trim();
        if (label.contains('主题') || label == '帖子') stats['主题'] = val;
        if (label.contains('回复') || label == '回帖') stats['回复'] = val;
        if (label.contains('好友')) stats['好友'] = val;
        if (label.contains('勋章')) stats['勋章'] = val;
        if (label.contains('获赞') ||
            label.contains('点赞') ||
            label.contains('被赞') ||
            label.contains('赞') ||
            label.contains('支持')) {
          stats['获赞'] = val;
        }
        if (label.contains('铁粒') || label.contains('金粒')) {
          creditsDetail.putIfAbsent('铁粒', () => val);
        }
      }
    }

    for (final tile
        in cleanDoc.querySelectorAll('.klp-acttile, .klp-acttile-hl')) {
      final b = tile.querySelector('b, .k-mono');
      final s = tile.querySelector('span');
      if (b != null && s != null) {
        final val = b.text.trim();
        final lbl = s.text.trim();
        if (lbl.contains('注册时间')) regdate = val;
        if (lbl.contains('最后访问')) lastvisit = val;
        if (lbl.contains('在线时间')) gameProfile['在线时间'] = val;
      }
    }
    for (final entry in cleanDoc.querySelectorAll('#ct .klp-kvlist > div')) {
      final label = entry.querySelector('dt')?.text.trim() ?? '';
      final valueNode = entry.querySelector('dd');
      final value = valueNode?.querySelector('[title]')?.attributes['title'] ??
          valueNode?.text.trim() ??
          '';
      if (label == '用户组' && value.isNotEmpty) group = value;
      if (label == '注册时间' && regdate.isEmpty) regdate = value;
      if (label == '最后访问' && lastvisit.isEmpty) lastvisit = value;
      if (label == '积分' && credits.isEmpty) credits = value.replaceAll(',', '');
      if (label == '在线时间') gameProfile.putIfAbsent(label, () => value);
      if (label == '好友') {
        stats.putIfAbsent(label, () => value.replaceAll(',', ''));
      }
    }

    // 2) 针对手机版及经典版资料区抽取 (.comiis_space_profilejf li, .profile_rs, .f_0, em+文本)
    for (final el in cleanDoc.querySelectorAll(
      '.comiis_space_profilejf li, div[class*="profile"] li, .comiis_space_info li, .comiis_space_tx li, #ct li, #psts li, .pf_l li, .comiis_p12 li, .comiis_box li, .comiis_space_profileico li, .pf_l tr, #psts tr',
    )) {
      // 兼容手机版 <div class="profile_rs ...">VALUE</div><span>LABEL</span>
      // 或 <li ...><span class="f_0">VALUE</span>LABEL</li>
      final rsVal = el.querySelector('.profile_rs, .f_0, span.f_0');
      if (rsVal != null && !rsVal.text.contains('{')) {
        String label = '';
        final rsLbl = el.querySelector(
            'span:not(.f_0):not(.profile_rs), em, th, span.dt, span.kmtit');
        if (rsLbl != null &&
            !rsLbl.text.contains('{') &&
            rsLbl.text.trim().isNotEmpty) {
          label = rsLbl.text
              .replaceAll(':', '')
              .replaceAll('：', '')
              .replaceAll(' ', '')
              .trim();
        } else {
          final clone = el.clone(true);
          clone
              .querySelectorAll(
                  '.profile_rs, .f_0, span.f_0, i, img, script, style')
              .forEach((e) => e.remove());
          label = clone.text
              .replaceAll(':', '')
              .replaceAll('：', '')
              .replaceAll(' ', '')
              .trim();
        }
        final value = rsVal.text.trim();
        if (label.isNotEmpty && value.isNotEmpty && label.length <= 15) {
          if (label == '注册时间') {
            regdate = value;
          } else if (label == '最后访问') {
            lastvisit = value;
          } else if (label == '积分') {
            creditsDetail['积分'] = value;
            if (credits.isEmpty) credits = value;
          } else if (label == '经验') {
            creditsDetail['经验'] = value;
          } else if (label.contains('铁粒') || label == '金粒') {
            creditsDetail['铁粒'] = value;
          } else if (label.contains('铁锭')) {
            creditsDetail['铁锭'] = value;
          } else if (label.contains('贡献')) {
            creditsDetail['贡献'] = value;
          } else if (label.contains('钻石')) {
            creditsDetail['钻石'] = value;
          } else if (label.contains('下界之星')) {
            creditsDetail['下界之星'] = value;
          } else if (label == '人气') {
            final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
            if (numVal != null) stats['人气'] = numVal;
          } else if (label == '回复' || label == '回帖') {
            final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
            if (numVal != null) stats['回复'] = numVal;
          } else if (label == '主题' || label == '帖子') {
            final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
            if (numVal != null) stats['主题'] = numVal;
          } else if (label.contains('获赞') ||
              label.contains('点赞') ||
              label.contains('被赞') ||
              label == '赞' ||
              label.contains('支持')) {
            final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
            if (numVal != null) stats['获赞'] = numVal;
          } else {
            gameProfile[label] = value;
          }
        }
      }

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
        value = clone.text
            .replaceFirst(RegExp(r'^[:：\s]+'), '')
            .replaceFirst(RegExp(r'[:：\s]+$'), '')
            .trim();

        if (label.isNotEmpty &&
            value.isNotEmpty &&
            label.length <= 20 &&
            !label.contains('{') &&
            !value.contains('{')) {
          if (label.contains('主题') || label == '帖子') {
            final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
            if (numVal != null) stats['主题'] = numVal;
          } else if (label.contains('回帖') || label == '回复') {
            final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
            if (numVal != null) stats['回复'] = numVal;
          } else if (label.contains('好友')) {
            final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
            if (numVal != null) stats['好友'] = numVal;
          } else if (label.contains('获赞') ||
              label.contains('点赞') ||
              label.contains('被赞') ||
              label == '赞' ||
              label.contains('支持')) {
            final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
            if (numVal != null) stats['获赞'] = numVal;
          } else if (label.contains('人气') || label.contains('访问量')) {
            final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
            if (numVal != null) stats['人气'] = numVal;
          } else if (label == '积分') {
            creditsDetail['积分'] = value;
            if (credits.isEmpty) credits = value;
          } else if (label == '经验') {
            creditsDetail['经验'] = value;
          } else if (label.contains('铁粒') || label == '金粒') {
            creditsDetail['铁粒'] = value;
          } else if (label.contains('铁锭')) {
            creditsDetail['铁锭'] = value;
          } else if (label.contains('贡献')) {
            creditsDetail['贡献'] = value;
          } else if (label.contains('钻石')) {
            creditsDetail['钻石'] = value;
          } else if (label.contains('下界之星')) {
            creditsDetail['下界之星'] = value;
          } else if (label == '用户组') {
            group = value;
            if (levelName.isEmpty) levelName = value;
          } else {
            if (label.contains('时间') || label.contains('访问')) {
              value = value.replaceAllMapped(
                RegExp(r'(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2})(\d{2})\b'),
                (m) => '${m[1]}:${m[2]}',
              );
            }
            gameProfile[label] = value;
          }
        }
      }
    }

    // 3) 针对资料核心区内容进行正则兜底提取（严禁全局正则提取误匹配 JS 脚本）
    final emRegex = RegExp(
      r'<em[^>]*>([^<]+)</em>\s*(?:<[^>]+>)*\s*([^<\r\n]+)',
    );
    final scopeHtml = mainScope?.innerHtml ?? '';
    for (final m in emRegex.allMatches(scopeHtml)) {
      final label = m
          .group(1)!
          .replaceAll(':', '')
          .replaceAll('：', '')
          .replaceAll(' ', '')
          .trim();
      var value = m
          .group(2)!
          .replaceFirst(RegExp(r'^[:：\s]+'), '')
          .replaceFirst(RegExp(r'[:：\s]+$'), '')
          .trim();
      if (label.isNotEmpty &&
          value.isNotEmpty &&
          label.length <= 16 &&
          !label.contains('{') &&
          !value.contains('{')) {
        if (label.contains('时间') || label.contains('访问')) {
          value = value.replaceAllMapped(
            RegExp(r'(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2})(\d{2})\b'),
            (m) => '${m[1]}:${m[2]}',
          );
        }
        if (label.contains('主题')) {
          final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
          if (numVal != null) stats.putIfAbsent('主题', () => numVal);
        }
        if (label.contains('回帖')) {
          final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
          if (numVal != null) stats.putIfAbsent('回复', () => numVal);
        }
        if (label.contains('好友')) {
          final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
          if (numVal != null) stats.putIfAbsent('好友', () => numVal);
        }
        if (label.contains('获赞') ||
            label.contains('点赞') ||
            label.contains('被赞') ||
            label.contains('支持')) {
          final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
          if (numVal != null) stats.putIfAbsent('获赞', () => numVal);
        }
        if (label.contains('人气') || label.contains('访问量')) {
          final numVal = RegExp(r'\d+').firstMatch(value)?.group(0);
          if (numVal != null) stats.putIfAbsent('人气', () => numVal);
        }
        if (label == '积分') creditsDetail.putIfAbsent('积分', () => value);
        if (label == '经验') creditsDetail.putIfAbsent('经验', () => value);
        if (label == '铁粒') creditsDetail.putIfAbsent('铁粒', () => value);
        if (label.contains('铁锭')) creditsDetail.putIfAbsent('铁锭', () => value);
        if (label == '贡献') creditsDetail.putIfAbsent('贡献', () => value);
        if (label == '钻石') creditsDetail.putIfAbsent('钻石', () => value);
        if (label == '用户组') {
          group = value;
          if (levelName.isEmpty) levelName = value;
        }
        gameProfile.putIfAbsent(label, () => value);
      }
    }

    final ironMatch = RegExp(r'铁粒\s*[:：]?\s*(\d+)').firstMatch(text) ??
        RegExp(r'(\d+)\s*粒\s*铁粒').firstMatch(text);
    if (ironMatch != null) {
      creditsDetail.putIfAbsent('铁粒', () => ironMatch.group(1)!);
    }
    final expMatch = RegExp(r'经验\s*[:：]?\s*(\d+)').firstMatch(text) ??
        RegExp(r'(\d+)\s*EP\s*经验').firstMatch(text);
    if (expMatch != null) {
      creditsDetail.putIfAbsent('经验', () => expMatch.group(1)!);
    }

    if (!stats.containsKey('获赞')) {
      final likeM = RegExp(
        r'(\d+)\s*(?:获赞|个获赞|次获赞|个赞|次被赞|人点赞|人赞|被赞|点赞)',
      ).firstMatch(text);
      if (likeM != null) {
        stats['获赞'] = likeM.group(1)!;
      }
    }

    // 清理可能误混入的 JS 或非法键值
    gameProfile.removeWhere((k, v) =>
        k.length > 20 ||
        k.contains('{') ||
        k.contains('}') ||
        k.contains('(') ||
        k.contains(')') ||
        k.contains(';') ||
        k.contains(r'$') ||
        k.contains('function') ||
        v.contains('{') ||
        v.contains('function') ||
        v.contains(';') ||
        v.length > 100);

    final popMatch =
        RegExp(r'(\d+)\s*(?:人气|次访问)|(?:人气|空间访问量|访问量)\s*[:：]?\s*(\d+)')
            .firstMatch(html);
    if (popMatch != null) {
      final v = popMatch.group(1) ?? popMatch.group(2);
      if (v != null && v.isNotEmpty) stats['人气'] = v;
    }

    final likeMatch =
        RegExp(r'(?:获赞|收到的赞|被赞|支持数)\s*[:：]?\s*(\d+)').firstMatch(html) ??
            RegExp(r'(\d+)\s*(?:个获赞|次获赞|个赞|次被赞|人点赞)').firstMatch(html) ??
            RegExp(r'点赞\s*[:：]?\s*(\d+)').firstMatch(html);
    if (likeMatch != null) {
      final v = likeMatch.group(1) ?? likeMatch.group(2);
      if (v != null &&
          v.isNotEmpty &&
          (stats['获赞'] == null || stats['获赞'] == '0')) {
        stats['获赞'] = v;
      }
    }

    // 3) 提取用户组全名（仅在目标用户资料区域内提取，绝不穿透全局）
    if (levelName.isEmpty) {
      final groupEl = cleanDoc.querySelector(
        '.comiis_space_tx .kmlev, .comiis_space_tx a[href*="usergroup"], .comiis_space_tx [class*="level"], #uhd a[href*="usergroup"], #psts a[href*="usergroup"]',
      );
      if (groupEl != null && groupEl.text.trim().isNotEmpty) {
        levelName = groupEl.text.trim();
      }
    }
    if (level.isNotEmpty) {
      final lm = RegExp(r'(Lv\.\d+)').firstMatch(level);
      if (lm != null) {
        final pureLvl = lm.group(1)!;
        if (levelName.isEmpty) {
          levelName = level.replaceFirst(pureLvl, '').trim();
        }
        level = pureLvl;
      }
    } else if (levelName.isNotEmpty) {
      final lm = RegExp(r'(Lv\.\d+)').firstMatch(levelName);
      if (lm != null) {
        level = lm.group(1)!;
      }
    }
    if (level.isNotEmpty && levelName.startsWith(level)) {
      levelName = levelName.replaceFirst(level, '').trim();
    }
    if (group.isEmpty) {
      group = levelName.isNotEmpty ? levelName : level;
    }
    // 头像挂件提取（仅当带有 ##SJ## 挂件时提取）
    final faceImg = _authorAvatarImage(cleanDoc.body!,
        '#uhd .klp-uhead-av img, .comiis_space_tx img, .user_img img, .avt img, #ct img[src*="avatar"]');
    final faceUrl = _authorAvatarFrame(faceImg) ?? '';

    // 空间背景图提取（支持 KLPBBS 电脑版 .klp-uhead-cover、#uhd 与手机版 .comiis_space_box / comiis_app_homestyle 空间壁纸）
    String? bgUrl;

    // 1. 优先从容器元素内联 style 或属性中提取（在 doc 和 cleanDoc 中全面检索，避免顶层移除 #hd 误伤背景）
    final coverCandidateEls = <html_dom.Element>[
      ...doc.querySelectorAll(
        '.klp-uhead-cover, .klp-uhead, #uhd, .cover, .uhead-cover, .space_banner, .fl_hd, .comiis_space_box, .space_box, #diyheader, #hd, .comiis_p12, .comiis_space_top, .space_header, #comiis_head, #wrap, .comiis_cover, div[class*="cover"], div[class*="uhead"]',
      ),
      ...cleanDoc.querySelectorAll(
        '.klp-uhead-cover, .klp-uhead, #uhd, .cover, .uhead-cover, .space_banner, .fl_hd, .comiis_space_box, .space_box, #diyheader, #hd, .comiis_p12, .comiis_space_top, .space_header, #comiis_head, #wrap, .comiis_cover, div[class*="cover"], div[class*="uhead"]',
      ),
    ];

    for (final box in coverCandidateEls) {
      // a. 从 style 的 background / background-image 中提取
      final style = box.attributes['style'] ?? '';
      if (style.isNotEmpty) {
        final m = RegExp(r'background(?:-image)?\s*:\s*url\(([^)]+)\)',
                caseSensitive: false)
            .firstMatch(style);
        if (m != null) {
          final rawBg = m
              .group(1)!
              .replaceAll('&quot;', '')
              .replaceAll('&#39;', '')
              .replaceAll('&amp;', '&')
              .replaceAll("'", '')
              .replaceAll('"', '')
              .trim();
          final candidate = _image(rawBg);
          if (candidate != null &&
              !candidate.contains('none.png') &&
              !candidate.contains('spacer.gif') &&
              !candidate.contains('noavatar')) {
            bgUrl = candidate;
            break;
          }
        }
      }

      // b. 从 data-cover / data-bg / data-src / data-original 属性提取
      for (final attr in [
        'data-cover',
        'data-bg',
        'data-src',
        'data-original'
      ]) {
        final val = box.attributes[attr]?.trim();
        if (val != null && val.isNotEmpty) {
          final candidate = _image(val);
          if (candidate != null &&
              !candidate.contains('none.png') &&
              !candidate.contains('spacer.gif')) {
            bgUrl = candidate;
            break;
          }
        }
      }
      if (bgUrl != null) break;

      // c. 从子 img.cover 或封面大图提取
      final innerImg = box.querySelector(
          'img.cover, img.banner, .cover img, img[src*="cover"], img[src*="home_bg"], img[src*="album"]');
      if (innerImg != null) {
        final imgSrc = innerImg.attributes['comiis_loadimages'] ??
            innerImg.attributes['file'] ??
            innerImg.attributes['zoomfile'] ??
            innerImg.attributes['data-original'] ??
            innerImg.attributes['data-src'] ??
            innerImg.attributes['src'];
        final candidate = _image(imgSrc);
        if (candidate != null &&
            !candidate.contains('none.png') &&
            !candidate.contains('spacer.gif') &&
            !candidate.contains('noavatar')) {
          bgUrl = candidate;
          break;
        }
      }
    }

    // 2. 从 <style> 样式表中提取 (支持 .klp-uhead, #uhd, .comiis_space_box 等全局样式规则)
    if (bgUrl == null || bgUrl.isEmpty) {
      final bgMatch = RegExp(
        r'(?:klp-uhead|uhd|comiis_space_box|diyheader|space_box|#hd|fl_hd|cover|uhead|space_header)[^{]*\{[^}]*background(?:\-image)?\s*:\s*url\(([^)]+)\)',
        caseSensitive: false,
      ).firstMatch(html);
      if (bgMatch != null) {
        final rawBg = bgMatch
            .group(1)!
            .replaceAll('&quot;', '')
            .replaceAll('&#39;', '')
            .replaceAll('&amp;', '&')
            .replaceAll("'", '')
            .replaceAll('"', '')
            .trim();
        bgUrl = _image(rawBg);
      }
    }

    // 3. 通用 home_bg、album 或 attachment 空间背景探测
    if (bgUrl == null || bgUrl.isEmpty) {
      final bgMatch2 = RegExp(
        r'background(?:\-image)?\s*:\s*url\(([^)]*(?:home_bg|attachment/album|attachment/common|cover)[^)]+)\)',
        caseSensitive: false,
      ).firstMatch(html);
      if (bgMatch2 != null) {
        final rawBg = bgMatch2
            .group(1)!
            .replaceAll('&quot;', '')
            .replaceAll('&#39;', '')
            .replaceAll('&amp;', '&')
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
        ) !=
        null;
    final hasOfflineImg = doc.querySelector(
          'img[src*="offline.png"], img[src*="offline.gif"], img[title*="当前离线"], img[title="离线"], .comiis_f, em.offline, span.offline',
        ) !=
        null;
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
    if (!hasOfflineImg &&
        !hasOfflineText &&
        (hasOlImg || hasOnlineText || isRecent)) {
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

    // Only the site's declared percentage is a profile completion statistic.
    // Missing fields, private information and pendants do not establish it.
    int profileProgress = 0;
    final progMatch = RegExp(r'已完成\s*(\d+)%').firstMatch(html) ??
        RegExp(r'profileprogress.*?(\d+)%?').firstMatch(html) ??
        RegExp(r'class="p_box"[^>]*style="width:\s*(\d+)%').firstMatch(html);
    if (progMatch != null) {
      profileProgress = int.tryParse(progMatch.group(1)!) ?? 0;
    }
    final hasProfileProgress =
        progMatch != null && profileProgress >= 0 && profileProgress <= 100;

    // 当前站点没有个人获赞总数接口，不返回历史猜测字段。
    stats.remove('获赞');

    final declaredCredits = DiscuzCreditBalance.profileValues(cleanDoc);
    if (declaredCredits != null) {
      creditsDetail
        ..clear()
        ..addAll(declaredCredits);
      gameProfile.removeWhere((label, _) => declaredCredits.containsKey(label));
      credits = declaredCredits['积分'] ?? '';
    } else {
      creditsDetail
          .updateAll((_, value) => DiscuzCreditBalance.amount(value) ?? value);
      credits = DiscuzCreditBalance.amount(credits) ?? credits;
    }

    return UserSpace(
      uid: uid,
      username: _cleanTitle(username),
      credits: credits,
      group: _cleanTitle(group),
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
      hasProfileProgress: hasProfileProgress,
    );
  }

  /// 解析用户搜索结果 (home.php?mod=spacecp&ac=search&searchsubmit=yes&username=...)
  static List<UserSpace> parseSearchUsers(String html) {
    final doc = html_parser.parse(html);
    final results = <UserSpace>[];
    final seenUids = <int>{};

    for (final li in doc.querySelectorAll('ul.buddy li, li.bbda, div.buddy')) {
      final h4A =
          li.querySelector('h4 a, a[href*="space-uid-"], a[href*="uid="]');
      if (h4A == null) continue;

      final href = h4A.attributes['href'] ?? '';
      final uidMatch = RegExp(r'space-uid-(\d+)|uid=(\d+)').firstMatch(href);
      final uid = uidMatch != null
          ? (int.tryParse(uidMatch.group(1) ?? uidMatch.group(2) ?? '') ?? 0)
          : 0;
      if (uid <= 0 || seenUids.contains(uid)) continue;
      seenUids.add(uid);

      final username = (h4A.attributes['title'] ?? h4A.text).trim();
      final avtImg = _authorAvatarImage(li, 'div.avt img, img');
      final faceUrl = _authorAvatarFrame(avtImg) ?? '';

      final descEl = li.querySelector('p.maxh, p.xg1, p');
      final descText = descEl?.text.trim() ?? '';

      // 解析用户组和积分
      String levelName = '';
      String credits = '';
      final credMatch = RegExp(r'积分数?[:：\s]*(\d+)').firstMatch(descText);
      if (credMatch != null) {
        credits = credMatch.group(1)!;
      }
      final groupMatch = RegExp(
        r'(SVIP|VIP|Lv\.\d+\s*[^积分\r\n\t]+|[^积分\d\r\n\t]+会员|版主|超级版主|管理员|荣誉版主|实习版主|认证开发者|创作者|特别嘉宾)',
        caseSensitive: false,
      ).firstMatch(descText);
      if (groupMatch != null) {
        levelName = groupMatch.group(1)!.trim();
      }

      results.add(
        UserSpace(
          uid: uid,
          username: username.isNotEmpty ? username : 'UID: $uid',
          faceUrl: faceUrl,
          levelName: levelName,
          credits: credits,
          stats: descText.isNotEmpty ? {'简介': descText} : const {},
        ),
      );
    }
    return results;
  }

  /// 解析 Discuz 个人资料编辑页原生表单字段 (home.php?mod=spacecp&ac=profile&op=...&mobile=2)
  static Map<String, dynamic> parseProfileEditInfo(String html,
          {String op = 'info'}) =>
      DiscuzProfileParser.parse(html);
  // ---------------------------------------------------------------------
  // 私信（收件箱 + 会话详情）
  // ---------------------------------------------------------------------
  static List<PmConversation> parsePmList(String html) {
    final doc = html_parser.parse(html);
    final result = <PmConversation>[];
    // 会话条目 dl[id^="pmlist_"] / li[id^="pmlist_"] / div[id^="pmlist_"]（plid）
    for (final dl in doc.querySelectorAll(
        'dl[id^="pmlist_"], li[id^="pmlist_"], div[id^="pmlist_"]')) {
      final idAttr = dl.attributes['id'] ?? dl.attributes['data-plid'] ?? '';
      if (idAttr.endsWith('_a')) continue; // 跳过类似 pmlist_19081_a 的快捷跳转 anchor
      final plid = int.tryParse(idAttr.replaceFirst('pmlist_', '')) ?? 0;
      if (plid == 0) continue;

      // 1. touid 提取（优先从头像区域、checkbox、回复链接）
      int touid = 0;
      final avtA = dl.querySelector(
          '.klp-pm-av, dd.m.avt a, dd.avt a, a.avt, dd.m a, .avatar a');
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
        final replyA = dl.querySelector('a[href*="subop=view"], a.klp-pm-link');
        if (replyA != null) {
          touid = _uidFromHref(replyA.attributes['href'] ?? '') ?? 0;
        }
      }

      // 2. 是否有未读消息（Discuz 真实 DOM：未读会话 dl 会包含 newpm 或 new 类名）
      final isNew = dl.classes.contains('newpm') ||
          dl.classes.contains('new') ||
          dl.classes.contains('is-unread') ||
          dl.querySelector('.newpm, .new, .is-unread') != null;

      final ptm = dl.querySelector(
              'dd.ptm, dd.pm_c, div.pm_c, div.cl, .c_pm, .klp-pm-body') ??
          dl;

      // 3. 对方用户名（精准选择，彻底避开空文本的头像 a 标签）
      String username = '';
      final nameA = dl.querySelector('a.klp-pm-name, .klp-pm-hd a, a.xw1');
      if (nameA != null && nameA.text.trim().isNotEmpty) {
        username = nameA.text.trim();
        if (touid == 0) {
          touid = _uidFromHref(nameA.attributes['href'] ?? '') ?? 0;
        }
      }
      if (username.isEmpty) {
        for (final a in dl.querySelectorAll('a')) {
          if (a.classes.any((c) => c.contains('av'))) continue;
          final t = a.text.trim();
          final href = a.attributes['href'] ?? '';
          if (t.isNotEmpty &&
              (href.contains('space-uid') || href.contains('uid='))) {
            username = t;
            if (touid == 0) touid = _uidFromHref(href) ?? 0;
            break;
          }
        }
      }

      // 4. 消息总数（如 "共 6 条" 或 span.klp-pm-num）
      int msgCount = 0;
      final countSpan = dl.querySelector('.klp-pm-num, span.xg1.z, span.z');
      if (countSpan != null) {
        final cm = RegExp(r'(\d+)').firstMatch(countSpan.text);
        if (cm != null) msgCount = int.tryParse(cm.group(1)!) ?? 0;
      }

      // 5. 时间文本
      String timeText = '';
      final timeSpan =
          dl.querySelector('.klp-pm-time, .k-meta, span.xg1:not(.z), span.xg1');
      if (timeSpan != null && !timeSpan.classes.contains('z')) {
        timeText = timeSpan.attributes['title'] ?? timeSpan.text.trim();
      }

      // 6. 摘要提取
      var summary = '';
      final sumEl = dl.querySelector('.klp-pm-sum, .pm_c, dd.ptm');
      if (sumEl != null) {
        final clone = sumEl.clone(true);
        clone
            .querySelectorAll(
                'a, span.xg1, span.pm_o, div.p_pop, div.o, .newpm_avt, input')
            .forEach((e) => e.remove());
        summary = clone.text.replaceAll('\n', ' ').trim();
      } else {
        final clone = ptm.clone(true);
        clone
            .querySelectorAll(
                'a, span.xg1, span.pm_o, div.p_pop, div.o, .newpm_avt, input, .klp-pm-ops, .k-menu')
            .forEach((e) => e.remove());
        summary = clone.text.replaceAll('\n', ' ').trim();
      }
      summary = summary
          .replaceFirst(
              RegExp(r'^(?:您|[^\s:]+)?\s*对\s*(?:您|[^\s:]+)?\s*说\s*[:：]\s*'), '')
          .trim();
      summary = summary.replaceAll(RegExp(r'\s+'), ' ').trim();

      // 7. 头像挂件提取
      final avatarImg = _authorAvatarImage(dl,
          '.klp-pm-av img, dd.m.avt img, dd.avt img, a.avt img, dd.m img, img[src*="avatar"]');
      final faceUrl = _authorAvatarFrame(avatarImg);

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

  /// 会话详情消息（div.klp-msg 或 dl[id^="pmlist_"]）
  static List<PmMessage> parsePmDetail(String html) {
    final doc = html_parser.parse(html);
    final result = <PmMessage>[];
    for (final dl in doc.querySelectorAll(
        'div.klp-msg, dl[id^="pmlist_"], li[id^="pmlist_"], div[id^="pmlist_"]')) {
      final idAttr = dl.attributes['id'] ?? '';
      if (idAttr.endsWith('_a')) continue;
      final pmid = int.tryParse(idAttr.replaceFirst('pmlist_', '')) ?? 0;
      if (pmid == 0 && !dl.classes.contains('klp-msg')) continue;

      final isMe = dl.classes.contains('is-me');

      // 1. 发送者 UID & 头像
      int authorUid = 0;
      final avtA = dl
          .querySelector('.klp-msg-av a, dd.m.avt a, dd.avt a, a.avt, dd.m a');
      if (avtA != null) {
        authorUid = _uidFromHref(avtA.attributes['href'] ?? '') ?? 0;
      }

      // 2. 发送者名称
      String author = '';
      if (isMe) {
        author = '我';
      } else {
        final authorA = dl.querySelector(
            '.klp-msg-hd a, a.xw1, a[href*="space-uid"], a[href*="uid="]');
        if (authorA != null && authorA.text.trim().isNotEmpty) {
          author = authorA.text.trim();
          if (authorUid == 0) {
            authorUid = _uidFromHref(authorA.attributes['href'] ?? '') ?? 0;
          }
        } else {
          final youSpan = dl.querySelector('span.xi2, span.xw1');
          if (youSpan != null && youSpan.text.contains('您')) {
            author = '您';
          }
        }
      }

      // 3. 时间文本（.k-meta, span.xg1 或 span[title]）
      String timeText = '';
      final ts =
          dl.querySelector('.k-meta, .klp-msg-hd span, span[title], span.xg1');
      if (ts != null) {
        timeText = ts.attributes['title'] ?? ts.text.trim();
      }

      // 4. 正文内容提取（.klp-msg-bubble 或 ptm / pm_c）
      final bubble =
          dl.querySelector('.klp-msg-bubble, dd.ptm, dd.pm_c, .pm_c');
      var content = '';
      if (bubble != null) {
        final clone = bubble.clone(true);
        clone
            .querySelectorAll(
                '.klp-msg-ops, .k-menu, a.xw1, span.xi2, span.xg1, span.pm_o, div.p_pop, .o, script, style')
            .forEach((e) => e.remove());
        content = clone.text.replaceAll('\n', ' ').trim();
        content = content
            .replaceFirst(
                RegExp(r'^(?:您|[^\s:]+)?\s*对\s*(?:您|[^\s:]+)?\s*说\s*[:：]\s*'),
                '')
            .trim();
        content = content.replaceAll(RegExp(r'\s+'), ' ').trim();
      }

      if (content.isNotEmpty || pmid > 0) {
        final avatarImg = _authorAvatarImage(dl,
            '.klp-msg-av img, dd.m.avt img, dd.avt img, a.avt img, dd.m img, img[src*="avatar"]');
        final faceUrl = _authorAvatarFrame(avatarImg);

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
      '.space_username, #uhd h2, h2.mbn, a.xw1, .p_header h2, span.user_name, .profile_username, .comiis_space_info h2, h2.fyy, a.top_user',
    );
    if (spaceUserEl != null) {
      final name = _cleanAuthor(spaceUserEl.text);
      if (name.isNotEmpty && name != '我') {
        spaceAuthor = name;
        spaceUid = _uidFromHref(spaceUserEl.attributes['href'] ?? '');
      }
    }
    if (spaceAuthor.isEmpty) {
      final docTitle = doc.querySelector('title')?.text ?? '';
      if (docTitle.contains('的帖子') && !docTitle.startsWith('我的帖子')) {
        spaceAuthor = _cleanAuthor(docTitle.split('的帖子').first);
      } else if (docTitle.contains('的主题') && !docTitle.startsWith('我的主题')) {
        spaceAuthor = _cleanAuthor(docTitle.split('的主题').first);
      } else if (docTitle.contains('的回复') && !docTitle.startsWith('我的回复')) {
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

    // 0. 优先检测 Discuz 空间收藏列表模式（#favorite_ul li, .fav_list li, li[id^="fav_"], .comiis_mysclist li）
    final favItems = cleanDoc.querySelectorAll(
      '#favorite_ul > li, ul#favorite_ul li, .fav_list li, form[action*="do=favorite"] li, li[id^="fav_"], .comiis_mysclist li, li.mysclist_li',
    );
    if (favItems.isNotEmpty) {
      for (final li in favItems) {
        final delA = li.querySelector(
            'a[href*="op=delete"], a[href*="delfav"], a[id^="a_delete_"]');
        final allAs = li.querySelectorAll('a');
        html_dom.Element? titleA;
        for (final a in allAs) {
          if (a == delA) continue;
          final href = a.attributes['href'] ?? '';
          if (href.contains('thread-') ||
              href.contains('viewthread') ||
              href.contains('tid=')) {
            if (DiscuzThreadTitle.text(a).isNotEmpty) {
              titleA = a;
              break;
            }
          }
        }
        if (titleA == null) continue;

        final title = DiscuzThreadTitle.text(titleA);
        if (title.isEmpty) continue;

        final href = titleA.attributes['href'] ?? '';
        final inputVid = li.querySelector('input[vid]')?.attributes['vid'];
        final tid = int.tryParse(inputVid ?? '') ?? _tidFromHref(href);
        if (tid == null || tid <= 0 || !seen.add(tid)) continue;

        final timeText =
            li.querySelector('.xg1, .date, .time, span.time')?.text.trim() ??
                '';
        final excerptEl = li.querySelector(
            'blockquote#quote_preview, blockquote, .quote, .description, p');
        final excerpt = excerptEl?.text.replaceAll('\n', ' ').trim();

        final mId =
            RegExp(r'fav_(\d+)').firstMatch(li.attributes['id'] ?? '') ??
                RegExp(r'favid=(\d+)').firstMatch(li.innerHtml);
        final inputFav =
            li.querySelector('input[name*="favorite"]')?.attributes['value'];
        final favid = (inputFav != null && int.tryParse(inputFav) != null)
            ? int.parse(inputFav)
            : (mId != null ? int.tryParse(mId.group(1)!) : null);

        final cover = _coverFromScope(li);

        result.add(
          ThreadSummary(
            tid: tid,
            uid: null,
            author: '',
            title: title,
            timeText: timeText,
            excerpt: excerpt?.isNotEmpty == true ? excerpt : null,
            coverUrl: cover,
            favid: favid,
          ),
        );
      }
    }

    // 1. KLPBBS C-Style 空间列表模式（.c_threadlist ul li 或 .c_threadlist li）
    final cThreadItems = cleanDoc.querySelectorAll('.c_threadlist li');
    if (cThreadItems.isNotEmpty) {
      for (final li in cThreadItems) {
        // 判断是否是回复项（含 .cli_reply）
        final replyEl = li.querySelector('.cli_reply a, .cli_reply');
        var titEl = li.querySelector(
          '.tit > a, .tit a[href*="thread-"], .tit a[href*="findpost"], .tit a[href*="tid="]',
        );
        if (titEl == null || _cleanTitle(titEl.text).isEmpty) {
          final allTitAs = li.querySelectorAll('.tit a');
          for (final a in allTitAs) {
            if (DiscuzThreadTitle.text(a).isNotEmpty) {
              titEl = a;
              break;
            }
          }
        }
        final directA = li.querySelector(
          'a[href*="thread-"], a[href*="tid="], a[href*="findpost"]',
        );

        final targetA = (titEl != null && _cleanTitle(titEl.text).isNotEmpty)
            ? titEl
            : (directA != null && _cleanTitle(directA.text).isNotEmpty)
                ? directA
                : replyEl;
        if (targetA == null) continue;

        String title = '';
        if (titEl != null && _cleanTitle(titEl.text).isNotEmpty) {
          title = _cleanTitle(titEl.text);
        } else if (directA != null && _cleanTitle(directA.text).isNotEmpty) {
          title = _cleanTitle(directA.text);
        }
        if (title.isEmpty && replyEl != null) {
          title = _cleanTitle(replyEl.text);
        }
        if (title.isEmpty) continue;

        final href = titEl?.attributes['href'] ??
            directA?.attributes['href'] ??
            replyEl?.attributes['href'] ??
            '';
        final tid = _tidFromHref(href);
        if (tid == null || tid <= 0 || !seen.add(tid)) continue;

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
        if (views == -1) {
          final vm =
              RegExp(r'(?:查看|阅读|浏览)\s*[:：]?\s*(\d+)').firstMatch(li.text) ??
                  RegExp(r'(\d+)\s*(?:次)?(?:查看|阅读|浏览)').firstMatch(li.text);
          if (vm != null) views = int.tryParse(vm.group(1)!) ?? -1;
        }
        if (replies == -1) {
          final rm = RegExp(r'(?:回复|评论)\s*[:：]?\s*(\d+)').firstMatch(li.text) ??
              RegExp(r'(\d+)\s*(?:条)?(?:回复|评论)').firstMatch(li.text);
          if (rm != null) replies = int.tryParse(rm.group(1)!) ?? -1;
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
          final cleaned = cleanTextSnippet(replyEl.text);
          if (cleaned.isNotEmpty) excerpt = cleaned;
        }

        final cover = _coverFromScope(li);

        final mId =
            RegExp(r'fav_(\d+)').firstMatch(li.attributes['id'] ?? '') ??
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

    // 2. PC 端表格模式（检索 #threadlist tr, .c_threadlist tr, tbody[id^="normalthread_"] tr 等）
    if (result.isEmpty) {
      final allTrs = cleanDoc.querySelectorAll(
        '#threadlist tr, .c_threadlist tr, tbody[id^="normalthread_"] tr, tbody[id^="stickthread_"] tr, form#delform tr, table.tl tr, table.dt tr',
      );
      for (final tr in allTrs) {
        if (tr.querySelector('th') != null &&
            tr.querySelectorAll('td').isEmpty) {
          continue;
        }
        final a = tr.querySelector('th a.xst') ??
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
        if (tid == null || tid <= 0) continue;

        String title = DiscuzThreadTitle.text(a);
        if (title.isEmpty) {
          final th = tr.querySelector('th');
          if (th != null) title = _cleanTitle(th.text);
        }
        if (title.isEmpty) continue;
        if (!seen.add(tid)) continue;

        // 版块名
        String? forumName;
        final forumA = tr.querySelector(
          'td.forum a, td a[href*="forumdisplay"], td a[href*="forum-"], a.xg1',
        );
        if (forumA != null) {
          forumName = forumA.text.trim();
        }

        // 作者与 UID
        var itemAuthor = spaceAuthor;
        int? itemUid = spaceUid;
        final authorA =
            tr.querySelector('.sub .aor a, td.by a[href*="space"], .avr a');
        if (authorA != null) {
          final cleanA = _cleanAuthor(authorA.text);
          if (cleanA.isNotEmpty && cleanA != '我') itemAuthor = cleanA;
          final u = _uidFromHref(authorA.attributes['href'] ?? '');
          if (u != null) itemUid = u;
        }

        // 发布/回复时间
        String timeText = '';
        final timeEl = tr.querySelector(
          'td.by em, td.by span, span.xg1, td.lastpost em, span.time, .sub .dte, em.dte',
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
        if (views == -1) {
          final vieEl = tr.querySelector('.sub .vie, em.vie');
          if (vieEl != null) {
            final m = RegExp(r'(\d+)').firstMatch(vieEl.text);
            if (m != null) views = int.tryParse(m.group(1)!) ?? -1;
          }
        }
        if (replies == -1) {
          final repEl = tr.querySelector('.sub .rey, em.rey, a.xi2 em');
          if (repEl != null) {
            final m = RegExp(r'(\d+)').firstMatch(repEl.text);
            if (m != null) replies = int.tryParse(m.group(1)!) ?? -1;
          }
        }
        if (views == -1) {
          final vm =
              RegExp(r'(?:查看|阅读|浏览)\s*[:：]?\s*(\d+)').firstMatch(tr.text) ??
                  RegExp(r'(\d+)\s*(?:次)?(?:查看|阅读|浏览)').firstMatch(tr.text);
          if (vm != null) views = int.tryParse(vm.group(1)!) ?? -1;
        }
        if (replies == -1) {
          final rm = RegExp(r'(?:回复|评论)\s*[:：]?\s*(\d+)').firstMatch(tr.text) ??
              RegExp(r'(\d+)\s*(?:条)?(?:回复|评论)').firstMatch(tr.text);
          if (rm != null) replies = int.tryParse(rm.group(1)!) ?? -1;
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
        var favid = int.tryParse(
            tr.querySelector('input[name*="favorite"]')?.attributes['value'] ??
                '');
        if (favid == null || favid <= 0) {
          final mId =
              RegExp(r'fav_(\d+)').firstMatch(tr.attributes['id'] ?? '') ??
                  RegExp(r'favid=(\d+)').firstMatch(tr.innerHtml);
          if (mId != null) favid = int.tryParse(mId.group(1)!);
        }

        result.add(
          ThreadSummary(
            tid: tid,
            uid: itemUid,
            author: itemAuthor,
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

    // 3. 移动端列表模式（.comiis_forumlist li, li.forumlist_li, .comiis_znalist, ul.comiis_threads_list li 等）
    if (result.isEmpty) {
      final listContainer = cleanDoc.querySelector(
        '.comiis_forumlist, .comiis_xznlist, ul.comiis_threads_list, ul.comiis_list, div.threadlist, .comiis_p12, .comiis_wxlist_li',
      );
      var items =
          listContainer?.querySelectorAll('li, dl.cl, div.comiis_twimg') ??
              const [];
      if (items.isEmpty) {
        items = cleanDoc.querySelectorAll(
          '.comiis_forumlist li, li.forumlist_li, .comiis_znalist, ul.comiis_threads_list li, div.threadlist li, .comiis_p12 li, div.comiis_twimg',
        );
      }

      for (final li in items) {
        // 优先在正文/标题区中查找非空链接，避开顶部用户信息区中的关注/用户链接
        html_dom.Element? a = li.querySelector(
          '.mmlist_li_box h2 a, .mmlist_li_box a[href*="thread-"], .mmlist_li_box a[href*="tid="], h2.thread_title a, h3 a, dt a, .tit a',
        );
        if (a == null || DiscuzThreadTitle.text(a).isEmpty) {
          final candidates = li.querySelectorAll(
            'a[href*="thread-"], a[href*="viewthread"], a[href*="tid="], a[href*="findpost"], a.s.xst, a.xw1',
          );
          for (final cand in candidates) {
            final t = DiscuzThreadTitle.text(cand);
            if (t.isNotEmpty &&
                !cand.classes.contains('user_gz') &&
                !cand.classes.contains('top_user')) {
              a = cand;
              break;
            }
          }
        }
        if (a == null) continue;

        String title = DiscuzThreadTitle.text(a);
        if (title.isEmpty) continue;

        final href = a.attributes['href'] ?? '';
        final tid = _tidFromHref(href);
        if (tid == null || tid <= 0 || !seen.add(tid)) continue;

        // 提取作者与 UID（若卡片中有明确标出）
        var itemAuthor = spaceAuthor;
        int? itemUid = spaceUid;
        final authorA = li.querySelector(
            'a.top_user, .forumlist_li_top a.top_user, a.user_name');
        if (authorA != null) {
          final cleanA = _cleanAuthor(authorA.text);
          if (cleanA.isNotEmpty && cleanA != '我') itemAuthor = cleanA;
          final u = _uidFromHref(authorA.attributes['href'] ?? '');
          if (u != null) itemUid = u;
        }
        if (itemUid == null) {
          final avatarA = li.querySelector('.wblist_tximg, a.top_tximg');
          final u = _uidFromHref(avatarA?.attributes['href'] ?? '');
          if (u != null) itemUid = u;
        }

        // 发布/回复时间
        final timeText = li
                .querySelector(
                    '.forumlist_li_time .f_d, .forumlist_li_time, .mtime, .xg1, span.date, .time, .f_d, .kmtime')
                ?.text
                .trim() ??
            '';

        // 版块名
        String? forumName;
        final forumEl =
            li.querySelector('.comiis_xznalist_bk a, .cat a, .forum a');
        if (forumEl != null) {
          final cloned = forumEl.clone(true);
          cloned
              .querySelectorAll('i, .comiis_font, em')
              .forEach((e) => e.remove());
          final cleaned =
              cloned.text.replaceAll(RegExp(r'[\uE000-\uF8FF]'), '').trim();
          forumName = cleaned.isNotEmpty
              ? cleaned
              : forumEl.text.replaceAll(RegExp(r'[\uE000-\uF8FF]'), '').trim();
        }

        // 回复与查看数
        int replies = -1;
        int views = -1;
        final repEl = li.querySelector(
            '.comiis_xznalist_bottom li a[href*="thread-"] .comiis_tm, .reply_num, .rep');
        if (repEl != null) {
          final m = RegExp(r'(\d+)').firstMatch(repEl.text);
          if (m != null) replies = int.tryParse(m.group(1)!) ?? -1;
        }
        final vieEl = li.querySelector(
            '.comiis_xznalist_bottom li:last-child .comiis_tm, .view_num, .vie');
        if (vieEl != null) {
          final m = RegExp(r'(\d+)').firstMatch(vieEl.text);
          if (m != null) views = int.tryParse(m.group(1)!) ?? -1;
        }
        if (views == -1) {
          final vm =
              RegExp(r'(?:查看|阅读|浏览)\s*[:：]?\s*(\d+)').firstMatch(li.text) ??
                  RegExp(r'(\d+)\s*(?:次)?(?:查看|阅读|浏览)').firstMatch(li.text);
          if (vm != null) views = int.tryParse(vm.group(1)!) ?? -1;
        }
        if (replies == -1) {
          final rm = RegExp(r'(?:回复|评论)\s*[:：]?\s*(\d+)').firstMatch(li.text) ??
              RegExp(r'(\d+)\s*(?:条)?(?:回复|评论)').firstMatch(li.text);
          if (rm != null) replies = int.tryParse(rm.group(1)!) ?? -1;
        }

        final rawExcerpt = li
            .querySelector('.threadlist_mes, .pbn, p, .mes, .list_body')
            ?.text;
        final cleanedExcerpt = cleanTextSnippet(rawExcerpt);
        final excerpt = cleanedExcerpt.isNotEmpty ? cleanedExcerpt : null;
        final cover = _coverFromScope(li);
        final mId =
            RegExp(r'fav_(\d+)').firstMatch(li.attributes['id'] ?? '') ??
                RegExp(r'favid=(\d+)').firstMatch(li.innerHtml);
        final favid = mId != null ? int.tryParse(mId.group(1)!) : null;

        result.add(
          ThreadSummary(
            tid: tid,
            uid: itemUid,
            author: itemAuthor,
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

      final title = DiscuzThreadTitle.text(titleA);
      if (title.isEmpty) continue;

      final excerpt =
          card.querySelector('.result-body, .content, p')?.text.trim();
      final authorA = card.querySelector(
        '.result-meta a[href*="space"], .result-meta a[href*="uid="]',
      );
      final meta = card.querySelectorAll('.result-meta > span:not(.sep)');
      final author =
          _cleanAuthor(authorA?.text ?? (meta.length >= 2 ? meta[1].text : ''));
      final uid = authorA != null
          ? _uidFromHref(authorA.attributes['href'] ?? '')
          : null;

      final forumA = card.querySelector(
        '.result-meta a[href*="forumdisplay"], .result-meta a[href*="fid="], .result-meta a[href*="forum-"]',
      );
      final forumName = forumA?.text.trim() ??
          (meta.length >= 3 ? meta[2].text.trim() : null);
      final fid = _extractFid(forumA?.attributes['href']);

      final timeEl = card.querySelector('.result-meta span:first-child');
      final timeText = timeEl?.text.trim();

      final cover = _coverFromScope(card);

      result.add(
        ThreadSummary(
          tid: tid,
          fid: fid,
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
      final excerpt =
          excerptEl != null ? cleanTextSnippet(excerptEl.text) : null;

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

    return result;
  }

  /// ---------------------------------------------------------------------
  /// 解析 Discuz 提示消息框（#messagetext, .alert_error, .alert_right, .alert_info）
  /// ---------------------------------------------------------------------
  static String? parseMessage(String html) {
    return DiscuzResponse.message(html);
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

      if (tds.length >= 4) {
        if (tds[0].contains(userA)) {
          score = tds[1].text.trim();
          time = tds[2].text.trim();
          reason = tds[3].text.trim();
        } else {
          score = tds[0].text.trim();
          time = tds[2].text.trim();
          reason = tds[3].text.trim();
        }
      } else if (tds.length == 3) {
        if (tds[0].contains(userA)) {
          score = tds[1].text.trim();
          time = tds[2].text.trim();
        } else {
          score = tds[0].text.trim();
          time = tds[2].text.trim();
        }
      } else if (tds.length == 2) {
        score =
            tds[0].contains(userA) ? tds[1].text.trim() : tds[0].text.trim();
      } else {
        score =
            tr.querySelector('.xi1, .xg1, span.z, span.f_a')?.text.trim() ?? '';
      }

      // 规范化积分金额展示（如 "铁粒 +1 粒" -> "+1 铁粒"）
      var cleanedScore = score;
      final scoreMatch = RegExp(r'([+\-]?\s*\d+)').firstMatch(score);
      if (scoreMatch != null) {
        var val = scoreMatch.group(1)!.replaceAll(' ', '');
        if (!val.startsWith('+') && !val.startsWith('-')) {
          val = '+$val';
        }
        var unit = '铁粒';
        if (score.contains('金粒')) {
          unit = '金粒';
        } else if (score.contains('贡献')) {
          unit = '贡献';
        } else if (score.contains('人气')) {
          unit = '人气';
        }
        cleanedScore = '$val $unit';
      }

      results.add(
        FloorReward(
          username: username,
          uid: uid,
          amount: cleanedScore.isNotEmpty ? cleanedScore : '+10 铁粒',
          reason: reason.isNotEmpty ? reason : '评分支持',
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
      final avatarEl = _authorAvatarImage(
        body,
        'dd.m.avt img, .avt img, .actor img, img[src*="avatar"]',
      );
      final rawAvatar = _authorAvatarSource(avatarEl);
      final avatarUrl = _avatarUrl(rawAvatar) ??
          (uid != null ? AppConfig.avatarUrl(uid, size: 'small') : '');
      final faceUrl = _authorAvatarFrame(avatarEl);

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
      final isPoke = rawText.contains('打个招呼') ||
          rawText.contains('打招呼') ||
          rawText.contains('poke');
      final isFriend = rawText.contains('好友') ||
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
          (body.querySelector(
                  '.notice_new, .new, em.new, span.new, .unread, .bg_del') !=
              null) ||
          body.attributes['style']?.contains('font-weight:bold') == true ||
          body.attributes['style']?.contains('font-weight: bold') == true;

      final uniqueKey =
          '${uid ?? author}_${tid}_${timeText.isNotEmpty ? timeText : ""}_${actionText.replaceAll(" ", "")}';
      if (!seenKeys.add(uniqueKey)) continue;

      result.add(
        NoticeItem(
          tid: tid,
          uid: uid,
          author:
              author.isNotEmpty ? author : (badge == '系统' ? '系统提醒' : '论坛用户'),
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

    // 保留服务器完整霸屏列表、原文、表情与头像，不只取第一条。
    result.addAll(DiscuzHornProtocol.parseBanners(
        html, Uri.parse(AppConfig.baseUrl),
        document: doc));

    // 结构：table.tsmini_horn_content > tr[id*="horn_"]（ahome_horn 小喇叭）
    for (final tr in doc.querySelectorAll('tr[id*="horn_"]')) {
      final idAttr = tr.attributes['id'] ?? '';
      final id = int.tryParse(idAttr.replaceAll(RegExp(r'[^0-9]'), '')) ??
          result.length + 1;

      final tds = tr.querySelectorAll('td');
      final contentTd = tds.length >= 2 ? tds[1] : tr;

      // 提取作者与 UID
      final userA = contentTd.querySelector(
            'a[href*="space&uid"], a[href*="mod=space"], a[href*="space-uid"], a[href*="uid="]',
          ) ??
          tr.querySelector(
              'a[href*="space&uid"], a[href*="mod=space"], a[href*="space-uid"], a[href*="uid="]');
      var author = userA?.text.trim() ?? '';
      if (author.isEmpty && contentTd.text.contains('系统消息')) {
        author = '系统消息';
      }
      final uid = _uidFromHref(userA?.attributes['href'] ?? '');

      // 提取头像与挂件（限定第一列或专用头像容器，坚决排除消息内容中的表情图片）
      final avatarImg = _authorAvatarImage(
          tr, '.tsmini_horn_avatar img, td:first-child img, .avatar img');
      final rawAvatar = _authorAvatarSource(avatarImg);
      var avatarUrl = _avatarUrl(rawAvatar);
      if ((avatarUrl == null || avatarUrl.isEmpty) &&
          rawAvatar != null &&
          !rawAvatar.contains('smiles') &&
          !rawAvatar.contains('horn.')) {
        avatarUrl = _absolute(rawAvatar);
      }
      if ((avatarUrl == null || avatarUrl.isEmpty) && uid != null && uid > 0) {
        avatarUrl = AppConfig.avatarUrl(uid, size: 'middle');
      }
      final faceUrl = _authorAvatarFrame(avatarImg);

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
    bool hasSecCode,
  }) parseSecCodeInfo(String html) {
    var formhash = '';
    var loginhash = '';
    var seccodehash = '';
    var seccodemodid = '';

    final fmM = RegExp(
          r'''name=["']formhash["']\s+value=["']([a-zA-Z0-9]+)["']''',
        ).firstMatch(html) ??
        RegExp(r'''formhash=([a-zA-Z0-9]{8,16})''').firstMatch(html);
    if (fmM != null) formhash = fmM.group(1)!;

    final lgM = RegExp(r'''loginhash=([a-zA-Z0-9]+)''').firstMatch(html) ??
        RegExp(r'''loginfield_([a-zA-Z0-9]+)''').firstMatch(html);
    if (lgM != null) loginhash = lgM.group(1)!;

    final scM = RegExp(r'''updateseccode\(['"]([a-zA-Z0-9]+)['"]''')
            .firstMatch(html) ??
        RegExp(r'''idhash=([a-zA-Z0-9]+)''').firstMatch(html) ??
        RegExp(r'''seccode_([a-zA-Z0-9]+)''').firstMatch(html) ??
        RegExp(
          r'''name=["']seccodehash["']\s+value=["']([a-zA-Z0-9]+)["']''',
        ).firstMatch(html) ??
        RegExp(r'''seccheck_tpl\[['"]([a-zA-Z0-9]+)['"]\]''').firstMatch(html);
    if (scM != null) seccodehash = scM.group(1)!;

    // seccodemodid：updateseccode('hash', 'html', 'modid') 第三参数
    final modM = RegExp(
      r'''updateseccode\(['"][\w]+['"],\s*['"][^'"]*['"],\s*['"]([\w:]+)['"]\)''',
    ).firstMatch(html);
    if (modM != null) seccodemodid = modM.group(1)!;

    // 严谨检测页面是否确实渲染了验证码输入或刷新控件
    final hasRealSecCode = html.contains('updateseccode(') ||
        html.contains('name="seccodeverify"') ||
        html.contains("name='seccodeverify'") ||
        html.contains('id="vseccode_') ||
        html.contains('id="seccode_') ||
        html.contains('seccheck_tpl');

    // 只有在明确检测到需要验证码时才激活 seccodehash
    if (hasRealSecCode && seccodehash.isEmpty) {
      seccodehash = 'cS0';
    }

    return (
      formhash: formhash,
      loginhash: loginhash,
      seccodehash: seccodehash,
      seccodemodid: seccodemodid,
      hasSecCode: hasRealSecCode,
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
  }) parseRegisterForm(String html) {
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
      passwordField:
          passwordInputs.isNotEmpty ? fieldName(passwordInputs[0]) : '',
      password2Field:
          passwordInputs.length >= 2 ? fieldName(passwordInputs[1]) : '',
      emailField: fieldName(emailInput),
      seccodehash: hidden['seccodehash'] ?? sec.seccodehash,
      seccodemodid: hidden['seccodemodid'] ?? sec.seccodemodid,
      agreebbrule: hidden['agreebbrule'] ?? '',
    );
  }

  /// 解析发帖/编辑页中的分类信息与发帖模板（threadsorts / sortid / typeoption）
  static ThreadSortInfo? parseThreadSortInfo(String html) {
    if (!html.contains('sortid') &&
        !html.contains('typeoption') &&
        !html.contains('forum_optionlist')) {
      return null;
    }

    final doc = html_parser.parse(html);

    // 1. 查找所有可用的模板 Tab（如：模组发布 / 地图发布 / 插件发布）
    final availableSorts = <SortTabItem>[];
    for (final a in doc.querySelectorAll('a')) {
      final onclick = a.attributes['onclick'] ?? '';
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'sortid=(\d+)').firstMatch('$onclick $href');
      if (m != null) {
        final sid = int.tryParse(m.group(1)!) ?? 0;
        final name = a.text.trim();
        if (sid > 0 &&
            name.isNotEmpty &&
            !availableSorts.any((s) => s.sortid == sid)) {
          availableSorts.add(SortTabItem(sortid: sid, name: name));
        }
      }
    }

    // 亦可从 select[name="sortid"] 中寻找
    final sortSel = doc.querySelector('select[name="sortid"]');
    if (sortSel != null) {
      for (final opt in sortSel.querySelectorAll('option')) {
        final sid = int.tryParse(opt.attributes['value'] ?? '') ?? 0;
        final name = opt.text.trim();
        if (sid > 0 &&
            name.isNotEmpty &&
            !availableSorts.any((s) => s.sortid == sid)) {
          availableSorts.add(SortTabItem(sortid: sid, name: name));
        }
      }
    }

    // 2. 确定当前激活的 sortid
    int currentSortid = 0;
    final hiddenSort = doc.querySelector('input[name="sortid"]') ??
        doc.querySelector('input[name="selectsortid"]');
    if (hiddenSort != null) {
      currentSortid = int.tryParse(hiddenSort.attributes['value'] ?? '') ?? 0;
    }
    if (currentSortid <= 0) {
      final m =
          RegExp(r"var\s+sortid\s*=\s*parseInt\('(\d+)'\)").firstMatch(html);
      if (m != null) {
        currentSortid = int.tryParse(m.group(1)!) ?? 0;
      }
    }
    if (currentSortid <= 0 && availableSorts.isNotEmpty) {
      currentSortid = availableSorts.first.sortid;
    }

    // 是否为版块强制必填（sortrequired = 1）
    bool sortrequired = false;
    final reqM = RegExp(r"var\s+sortrequired\s*=\s*parseInt\('(\d+)'\)")
        .firstMatch(html);
    if (reqM != null) {
      sortrequired = reqM.group(1) == '1';
    }

    String sortName = '';
    final activeTab =
        availableSorts.where((s) => s.sortid == currentSortid).firstOrNull;
    if (activeTab != null) {
      sortName = activeTab.name;
    } else {
      sortName = '分类信息';
    }

    // 3. 解析字段列表（主：XML 解析；备：DOM 解析）
    final fields = <SortOptionField>[];

    // 3.1 尝试从 XML 结构中解析
    final xmlM =
        RegExp(r"var\s+forum_optionlist\s*=\s*'([^']+)'").firstMatch(html);
    if (xmlM != null) {
      try {
        final xmlStr = xmlM.group(1)!;
        final frag = html_parser.parseFragment(xmlStr);
        final optionList = frag.querySelector('forum_optionlist');
        final nodes = optionList?.children ?? frag.children;
        for (final node in nodes) {
          if (!node.localName!.startsWith('s') || node.localName == 'span') {
            continue;
          }
          final identifier =
              node.querySelector('sidentifier')?.text.trim() ?? '';
          if (identifier.isEmpty) continue;

          final title = node.querySelector('stitle')?.text.trim() ?? identifier;
          final type =
              node.querySelector('stype')?.text.trim().toLowerCase() ?? 'text';
          final required = node.querySelector('srequired')?.text.trim() == '1';
          final description =
              node.querySelector('sdescription')?.text.trim() ?? '';
          final unit = node.querySelector('sunit')?.text.trim() ?? '';
          final maxLen =
              int.tryParse(node.querySelector('smaxlength')?.text.trim() ?? '');
          final defaultVal = node.querySelector('sdefaultvalue')?.text.trim();

          final choices = <String, String>{};
          final choicesNode = node.querySelector('schoices');
          if (choicesNode != null) {
            for (final c in choicesNode.children) {
              final ctag = c.localName ?? '';
              final key = ctag.startsWith('s') ? ctag.substring(1) : ctag;
              choices[key] = c.text.trim();
            }
          }

          // 从当前页面 DOM 中读取已填写的初始值
          dynamic initialValue = defaultVal;
          if (type == 'checkbox') {
            final checkedVals = <String>[];
            for (final inp in doc
                .querySelectorAll('input[name="typeoption[$identifier][]"]')) {
              if (inp.attributes.containsKey('checked')) {
                checkedVals.add(inp.attributes['value'] ?? '');
              }
            }
            if (checkedVals.isNotEmpty) {
              initialValue = checkedVals;
            }
          } else if (type == 'radio') {
            for (final inp in doc
                .querySelectorAll('input[name="typeoption[$identifier]"]')) {
              if (inp.attributes.containsKey('checked')) {
                initialValue = inp.attributes['value'];
                break;
              }
            }
          } else if (type == 'select') {
            final sel =
                doc.querySelector('select[name="typeoption[$identifier]"]');
            final selOpt = sel?.querySelector('option[selected]');
            if (selOpt != null) {
              initialValue = selOpt.attributes['value'];
            }
          } else if (type == 'textarea') {
            final ta =
                doc.querySelector('textarea[name="typeoption[$identifier]"]');
            if (ta != null && ta.text.trim().isNotEmpty) {
              initialValue = ta.text.trim();
            }
          } else {
            final inp =
                doc.querySelector('input[name="typeoption[$identifier]"]');
            if (inp != null && (inp.attributes['value'] ?? '').isNotEmpty) {
              initialValue = inp.attributes['value'];
            }
          }

          fields.add(SortOptionField(
            identifier: identifier,
            title: title,
            type: type,
            required: required,
            description: description,
            unit: unit,
            maxlength: maxLen,
            choices: choices,
            initialValue: initialValue,
          ));
        }
      } catch (_) {}
    }

    // 3.2 备用方案：如果 XML 为空但 DOM 中有 table.tfm 或 #threadsorts
    if (fields.isEmpty) {
      for (final row in doc.querySelectorAll('tr, div.p_opt')) {
        final inputs = row.querySelectorAll(
            'input[name^="typeoption["], select[name^="typeoption["], textarea[name^="typeoption["]');
        if (inputs.isEmpty) continue;

        final firstInput = inputs.first;
        final nameAttr = firstInput.attributes['name'] ?? '';
        final idM =
            RegExp(r'typeoption\[([a-zA-Z0-9_]+)\]').firstMatch(nameAttr);
        if (idM == null) continue;
        final identifier = idM.group(1)!;
        if (fields.any((f) => f.identifier == identifier)) continue;

        final th = row.querySelector('th, span.p_title, label');
        var title = th?.text.replaceAll('*', '').trim() ?? identifier;
        final required = th?.querySelector('.rq') != null ||
            (th?.text.contains('*') ?? false);
        final descEl = row.querySelector('.xg2, span[id^="check"], p.xg2');
        final description = descEl?.text.trim() ?? '';

        final tag = firstInput.localName;
        final itype = firstInput.attributes['type']?.toLowerCase() ?? '';
        String fieldType = 'text';
        final choices = <String, String>{};
        dynamic initialValue;

        if (tag == 'select') {
          fieldType = 'select';
          for (final opt in firstInput.querySelectorAll('option')) {
            final v = opt.attributes['value'] ?? '';
            final t = opt.text.trim();
            if (v.isNotEmpty) {
              choices[v] = t;
              if (opt.attributes.containsKey('selected')) {
                initialValue = v;
              }
            }
          }
        } else if (tag == 'textarea') {
          fieldType = 'textarea';
          initialValue = firstInput.text.trim();
        } else if (itype == 'radio') {
          fieldType = 'radio';
          for (final inp in inputs) {
            final v = inp.attributes['value'] ?? '';
            final lbl = inp.parent?.text.trim() ?? v;
            choices[v] = lbl;
            if (inp.attributes.containsKey('checked')) {
              initialValue = v;
            }
          }
        } else if (itype == 'checkbox') {
          fieldType = 'checkbox';
          final checkedVals = <String>[];
          for (final inp in inputs) {
            final v = inp.attributes['value'] ?? '';
            final lbl = inp.parent?.text.trim() ?? v;
            choices[v] = lbl;
            if (inp.attributes.containsKey('checked')) {
              checkedVals.add(v);
            }
          }
          if (checkedVals.isNotEmpty) {
            initialValue = checkedVals;
          }
        } else {
          if (row.text.contains('年') &&
                  row.text.contains('月') &&
                  row.text.contains('日') ||
              firstInput.attributes['id']?.contains('calendar') == true) {
            fieldType = 'calendar';
          } else if (nameAttr.contains('url') ||
              nameAttr.contains('dz') ||
              firstInput.attributes['id']?.contains('url') == true) {
            fieldType = 'url';
          } else {
            fieldType = 'text';
          }
          initialValue = firstInput.attributes['value'] ?? '';
        }

        fields.add(SortOptionField(
          identifier: identifier,
          title: title,
          type: fieldType,
          required: required,
          description: description,
          choices: choices,
          initialValue: initialValue,
        ));
      }
    }

    if (currentSortid <= 0 && fields.isEmpty && availableSorts.isEmpty) {
      return null;
    }

    return ThreadSortInfo(
      sortid: currentSortid,
      name: sortName,
      sortrequired: sortrequired,
      availableSorts: availableSorts,
      fields: fields,
    );
  }

  static PostOptionAttribute _parseOptionAttr(
    html_dom.Document doc,
    String name, {
    bool defaultChecked = false,
    bool defaultDisabled = false,
  }) {
    final el = doc.querySelector('input[name="$name"], input#$name');
    if (el == null) {
      return PostOptionAttribute(
        available: false,
        checked: defaultChecked,
        disabled: defaultDisabled,
      );
    }
    final isChecked = el.attributes.containsKey('checked') ||
        el.attributes['checked'] == 'checked' ||
        el.attributes['checked'] == 'true';
    final isDisabled = el.attributes.containsKey('disabled') ||
        el.attributes['disabled'] == 'disabled' ||
        el.attributes['disabled'] == 'true';
    return PostOptionAttribute(
      available: true,
      checked: isChecked,
      disabled: isDisabled,
    );
  }

  /// 解析发帖页（forum.php?mod=post&action=newthread）的 formhash、可用的特殊主题类型与权限错误。
  /// Discuz 允许的特殊主题通过 switchpost('...&special=N') 菜单暴露；无菜单时仅普通帖。
  static ({
    String formhash,
    Set<int> allowedSpecials,
    List<({int value, String name})> typeOptions,
    ThreadSortInfo? threadSortInfo,
    List<PostAttachmentItem> unusedAttachments,
    String errorMessage,
    PostEditorAttributes editorAttributes,
  }) parseNewThreadInfo(String html) {
    final doc = html_parser.parse(html);
    final editorPresent = doc.querySelector('form [name="message"]') != null;
    final allowed = <int>{if (editorPresent) 0};
    final typeOptions = <({int value, String name})>[];
    final unusedAttachments = <PostAttachmentItem>[];
    String error = '';

    final fmM = RegExp(
          r'''name=["']formhash["'][^>]*value=["']([a-zA-Z0-9]+)["']''',
        ).firstMatch(html) ??
        RegExp(
          r'''formhash\s*=\s*["']([a-zA-Z0-9]{8,16})["']''',
        ).firstMatch(html);
    final formhash = editorPresent ? fmM?.group(1) ?? '' : '';

    // 主题分类 select[name="typeid"]（PC 发帖页专属）
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

    // 分类信息发帖模板解析（threadsorts / sortid / typeoption）
    final threadSortInfo = parseThreadSortInfo(html);

    // 1. 特殊主题精准识别（Discuz 3.4 规范）：
    // 只有在版块后台开启该特殊功能时，Discuz 发帖导航栏 (ul.tb, #specialposts, .comiis_post_type 等) 才会输出对应入口
    for (final el in doc.querySelectorAll(
      'ul.tb li a, #specialposts a, .comiis_post_type a, #post_special a, .nav_p a, .post_special_tabs a, a[onclick*="switchpost"]',
    )) {
      final onclick = el.attributes['onclick'] ?? '';
      final href = el.attributes['href'] ?? '';
      final combined = '$onclick $href';
      final m = RegExp(r'[?&]special=(\d+)').firstMatch(combined);
      if (m != null) {
        final s = int.tryParse(m.group(1)!) ?? 0;
        if (s > 0) allowed.add(s);
      }
    }

    // 全文正则匹配 switchpost('...special=X')
    for (final m in RegExp(
      r'''switchpost\(['"][^'"]*?(?:&|\?[?&])special=(\d+)['"]''',
    ).allMatches(html)) {
      final s = int.tryParse(m.group(1)!) ?? 0;
      if (s > 0) allowed.add(s);
    }

    // 检查表单隐藏域 input[name="special"]
    final specialInput = doc.querySelector('input[name="special"]');
    if (specialInput != null) {
      final s = int.tryParse(specialInput.attributes['value'] ?? '') ?? 0;
      if (s > 0) allowed.add(s);
    }

    // Discuz 3.4 专属模板特殊主题选项卡与设置容器（仅当元素存在于 DOM 时才判定支持）
    if (doc.querySelector(
            '#extra_poll_c, #extra_poll_b, li#postspecialcss_1, li#special_1') !=
        null) {
      allowed.add(1);
    }
    if (doc.querySelector(
            '#extra_trade_c, #extra_trade_b, li#postspecialcss_2, li#special_2') !=
        null) {
      allowed.add(2);
    }
    if (doc.querySelector(
            '#extra_reward_c, #extra_reward_b, li#postspecialcss_3, li#special_3') !=
        null) {
      allowed.add(3);
    }
    if (doc.querySelector(
            '#extra_activity_c, #extra_activity_b, li#postspecialcss_4, li#special_4') !=
        null) {
      allowed.add(4);
    }
    if (doc.querySelector(
            '#extra_debate_c, #extra_debate_b, li#postspecialcss_5, li#special_5') !=
        null) {
      allowed.add(5);
    }

    // 2. 未使用的附件解析（未插入正文的上传附件）
    for (final el in doc.querySelectorAll(
      'tr[id^="unused_"], div[id^="unused_"], table[id^="unused_"], #unusedlist tr, #unusedattachlist tr, #unusedimgattachlist tr, #unusedlist_attach tr, #unusedlist_img tr, #unusedattachlist div, #unusedimglist div, .attachentry',
    )) {
      final input = el.querySelector(
          'input[name="unused[]"], input[name^="attachnew"], input[name^="unused"]');
      var aid = int.tryParse(input?.attributes['value'] ?? '') ?? 0;
      if (aid == 0) {
        final idAttr = el.attributes['id'] ?? '';
        final idM = RegExp(r'unused_(\d+)').firstMatch(idAttr);
        if (idM != null) {
          aid = int.tryParse(idM.group(1)!) ?? 0;
        }
      }
      if (aid == 0) {
        final onclick = el
                .querySelector(
                    '[onclick*="insertAttachTag"], [onclick*="delattach"]')
                ?.attributes['onclick'] ??
            '';
        final m = RegExp(r'\d+').firstMatch(onclick);
        if (m != null) {
          aid = int.tryParse(m.group(0)!) ?? 0;
        }
      }
      if (aid > 0 && !unusedAttachments.any((a) => a.aid == aid)) {
        final nameEl = el.querySelector('a, span.filename, .xw1, .px') ?? el;
        var name = nameEl.text.trim();
        name = name.replaceAll(RegExp(r'(?:查看|使用|删除|插入)\s*$'), '').trim();
        if (name.isEmpty) name = '附件 $aid';
        final isImage = name.toLowerCase().endsWith('.png') ||
            name.toLowerCase().endsWith('.jpg') ||
            name.toLowerCase().endsWith('.jpeg') ||
            name.toLowerCase().endsWith('.gif') ||
            name.toLowerCase().endsWith('.webp') ||
            el.querySelector('img') != null;
        unusedAttachments.add(PostAttachmentItem(
          aid: aid,
          filename: name,
          filesize: 0,
          isImage: isImage,
        ));
      }
    }

    // 备用正则扫描（应对部分模板未将附件列表完整展开为 DOM 树的情况）
    if (unusedAttachments.isEmpty) {
      for (final m in RegExp(
              r'''(?:name=["']unused\[\]["'][^>]*value=["'](\d+)["']|id=["']unused_(\d+)["']|attachnew\[(\d+)\])''')
          .allMatches(html)) {
        final aid =
            int.tryParse(m.group(1) ?? m.group(2) ?? m.group(3) ?? '') ?? 0;
        if (aid > 0 && !unusedAttachments.any((a) => a.aid == aid)) {
          unusedAttachments.add(PostAttachmentItem(
            aid: aid,
            filename: '未使用的附件 $aid',
            filesize: 0,
            isImage: false,
          ));
        }
      }
    }

    // 导航中的 formhash 不能清除手机绑定、用户组或版块限制。
    error = !editorPresent ||
            doc.querySelector(
                    '#messagetext, .alert_error, .comiis_password_top') !=
                null
        ? DiscuzResponse.message(html) ?? ''
        : '';
    if (!editorPresent) {
      allowed.clear();
      if (error.isEmpty) error = '当前账号无法取得发帖或回复表单';
    }

    // 4. 网页端附加选项与权限实时解析 (Web post_editor_attribute.htm)
    final usesig = _parseOptionAttr(doc, 'usesig', defaultChecked: true);
    final isanonymous =
        _parseOptionAttr(doc, 'isanonymous', defaultChecked: false);
    final hiddenreplies =
        _parseOptionAttr(doc, 'hiddenreplies', defaultChecked: false);
    final ordertype = _parseOptionAttr(doc, 'ordertype', defaultChecked: false);
    final allownoticeauthor =
        _parseOptionAttr(doc, 'allownoticeauthor', defaultChecked: true);

    final htmlon = _parseOptionAttr(doc, 'htmlon', defaultChecked: false);
    final allowimgcode =
        _parseOptionAttr(doc, 'allowimgcode', defaultChecked: true);
    final allowimgurl =
        _parseOptionAttr(doc, 'allowimgurl', defaultChecked: true);
    final parseurloff =
        _parseOptionAttr(doc, 'parseurloff', defaultChecked: false);
    final smileyoff = _parseOptionAttr(doc, 'smileyoff', defaultChecked: false);
    final bbcodeoff = _parseOptionAttr(doc, 'bbcodeoff', defaultChecked: false);
    final imgcontent =
        _parseOptionAttr(doc, 'imgcontent', defaultChecked: false);

    // 用户组阅读权限下拉 (select[name="readperm"])
    final readPermOptions = <({int value, String name})>[];
    final readPermSel = doc.querySelector('select[name="readperm"]');
    if (readPermSel != null) {
      for (final opt in readPermSel.querySelectorAll('option')) {
        final v = int.tryParse(opt.attributes['value'] ?? '') ?? 0;
        final n = opt.text.trim();
        if (n.isNotEmpty) {
          readPermOptions.add((value: v, name: n));
        }
      }
    }

    // 5. 管理用户组专属发帖特性解析 (Discuz post_editor_extra.htm & post_editpost.htm)
    final stickTopicOptions = <({int value, String name})>[];
    final stickSel =
        doc.querySelector('select[name="sticktopic"], select#sticktopic');
    if (stickSel != null) {
      for (final opt in stickSel.querySelectorAll('option')) {
        final v = int.tryParse(opt.attributes['value'] ?? '') ?? 0;
        final n = opt.text.trim();
        if (n.isNotEmpty) {
          stickTopicOptions.add((value: v, name: n));
        }
      }
    }

    final addDigestOptions = <({int value, String name})>[];
    final digestSel =
        doc.querySelector('select[name="adddigest"], select#adddigest');
    if (digestSel != null) {
      for (final opt in digestSel.querySelectorAll('option')) {
        final v = int.tryParse(opt.attributes['value'] ?? '') ?? 0;
        final n = opt.text.trim();
        if (n.isNotEmpty) {
          addDigestOptions.add((value: v, name: n));
        }
      }
    }

    final canCloseThread =
        doc.querySelector('input[name="closed"], input#closed') != null;
    final canDeletePost =
        doc.querySelector('input[name="delete"], input#delete') != null;

    final editorAttributes = PostEditorAttributes(
      useSig: usesig,
      isAnonymous: isanonymous,
      hiddenReplies: hiddenreplies,
      orderType: ordertype,
      allowNoticeAuthor: allownoticeauthor,
      htmlOn: htmlon,
      allowImgCode: allowimgcode,
      allowImgUrl: allowimgurl,
      parseUrlOff: parseurloff,
      smileyOff: smileyoff,
      bbcodeOff: bbcodeoff,
      imgContent: imgcontent,
      readPermOptions: readPermOptions,
      stickTopicOptions: stickTopicOptions,
      addDigestOptions: addDigestOptions,
      canCloseThread: canCloseThread,
      canDeletePost: canDeletePost,
    );

    return (
      formhash: formhash,
      allowedSpecials: allowed,
      typeOptions: typeOptions,
      threadSortInfo: threadSortInfo,
      unusedAttachments: unusedAttachments,
      errorMessage: error,
      editorAttributes: editorAttributes,
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
      final label =
          th.text.replaceAll('\u00a0', ' ').replaceAll('&nbsp;', ' ').trim();
      if (label.isEmpty) continue;
      final a = td.querySelector('a');
      final rawHref = a?.attributes['href'] ?? '';
      final url = rawHref.isNotEmpty ? _absolute(rawHref) : null;
      final value =
          td.text.replaceAll('\u00a0', ' ').replaceAll('&nbsp;', ' ').trim();
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

  /// 清洗投票选项文本（去除 Discuz 选项自带的图标码、□、○、[ ]、序号等前置占位符号）
  static String cleanPollOptionLabel(String raw) {
    // 1. 剥离 Unicode 私有区与扩展区图标字体（comiis_font \uE000-\uF8FF 等）
    var s = raw
        .replaceAll(
          RegExp(
            r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
            unicode: true,
          ),
          '',
        )
        .trim();
    // 2. 移除开头的方块、单选圆圈、选择框、多选框、Unicode 特殊符号以及多余标点
    s = s.replaceAll(
      RegExp(
          r'^[\u25A0-\u25FF\u2600-\u26FF\u2700-\u27BF\uFEFF\u00A0\s\[\]\(\)（）○●□■▪▫▲▼◇◆]+\s*'),
      '',
    );
    // 3. 移除开头的类似 "1. □", "1、□" 带有序号加符号的杂质
    s = s.replaceAll(
      RegExp(
          r'^\d+[\.、\s]+[\u25A0-\u25FF\u2600-\u26FF\u2700-\u27BF\uFEFF\u00A0\s\[\]\(\)（）○●□■▪▫▲▼◇◆]+\s*'),
      '',
    );
    return s.trim();
  }

  /// 异步多线程将 HTML 字符串解析为结构化区块
  static Future<List<PostBlock>> parseStructuredBlocksFromHtmlAsync(
      String html) async {
    if (!AppConfig.enableMultiThreadParsing) {
      return parseStructuredBlocksFromHtml(html);
    }
    return compute(_parseStructuredBlocksCompute, html);
  }

  /// 解析与解构视频链接，全面剥离 klpbbs web 播放器包装 (player.klpbbs.com / klpbbs.com/player.php / dplayer / 插件)，
  /// 提取纯净的 B 站 BV 号 / AV 号 / 直链视频地址直接由本地播放器播放
  static ({String resolvedSrc, bool isBilibili, String? bvid, String? aid})
      _resolveVideoMedia(String rawSrc) {
    var src = rawSrc.trim();
    if (src.isEmpty) {
      return (resolvedSrc: '', isBilibili: false, bvid: null, aid: null);
    }

    if (src.startsWith('//')) {
      src = 'https:$src';
    }

    String? bvid;
    String? aid;
    bool isBili = false;

    // 1. 递归解包播放器外层包装（彻底剥离 klpbbs 慢速代理、player.php、dplayer、ckplayer、iframe 等）
    for (int peel = 0; peel < 3; peel++) {
      try {
        final uri = Uri.tryParse(src);
        if (uri == null) break;

        final qp = uri.queryParameters;
        if (qp['bili'] == 'true' ||
            qp['bili'] == '1' ||
            qp['site'] == 'bilibili') {
          isBili = true;
        }
        if (qp.containsKey('bvid') && qp['bvid']!.isNotEmpty) {
          bvid = qp['bvid'];
          isBili = true;
        }
        if (qp.containsKey('aid') && qp['aid']!.isNotEmpty) {
          aid = qp['aid'];
          isBili = true;
        }

        // 检查常见参数中的实际视频直链或 BV / AV
        final targetParam = qp['url'] ??
            qp['src'] ??
            qp['v'] ??
            qp['vid'] ??
            qp['file'] ??
            qp['link'] ??
            qp['video'] ??
            qp['path'];

        if (targetParam != null && targetParam.trim().isNotEmpty) {
          var unwrapped = targetParam.trim();
          // 处理多重 URL 编码（如 %252F -> %2F -> /）
          for (int i = 0; i < 2; i++) {
            if (unwrapped.contains('%')) {
              try {
                final decoded = Uri.decodeComponent(unwrapped);
                if (decoded != unwrapped) {
                  unwrapped = decoded;
                } else {
                  break;
                }
              } catch (_) {
                break;
              }
            }
          }

          if (unwrapped.startsWith('//')) {
            unwrapped = 'https:$unwrapped';
          }

          if (unwrapped.startsWith('BV') || unwrapped.startsWith('bv')) {
            bvid = unwrapped;
            isBili = true;
            src = unwrapped;
            break;
          } else if (unwrapped.startsWith('av') || unwrapped.startsWith('AV')) {
            aid = unwrapped.substring(2);
            isBili = true;
            src = unwrapped;
            break;
          } else if (unwrapped.startsWith('http://') ||
              unwrapped.startsWith('https://')) {
            src = unwrapped;
            // 继续下一轮循环看是否嵌套了其他播放器
            continue;
          }
        }
      } catch (_) {}
      break;
    }

    // 2. 全局探测 B 站 BV 号 (BV1xxxxxxxxx) 与 aid
    final bvidM =
        RegExp(r'(BV[a-zA-Z0-9]{10})', caseSensitive: false).firstMatch(src);
    if (bvidM != null) {
      bvid = bvidM.group(1);
      isBili = true;
    }
    final aidM =
        RegExp(r'(?:aid=|/av|^av)(\d+)', caseSensitive: false).firstMatch(src);
    if (aidM != null) {
      aid = aidM.group(1);
      isBili = true;
    }

    if (src.contains('bilibili.com') || src.contains('b23.tv')) {
      isBili = true;
    }

    return (resolvedSrc: src, isBilibili: isBili, bvid: bvid, aid: aid);
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
    bool isFirstFloor = true,
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
        final isWrapper = child.classes.contains('comiis_messages') ||
            child.classes.contains('comiis_message_table') ||
            child.classes.contains('comiis_a') ||
            child.classes.contains('view_one') ||
            child.classes.contains('view_all') ||
            child.id.startsWith('postmessage_') ||
            child.classes.contains('t_f') ||
            ((childTag == 'table' ||
                    childTag == 'tbody' ||
                    childTag == 'thead' ||
                    childTag == 'tfoot' ||
                    childTag == 'tr' ||
                    childTag == 'td' ||
                    childTag == 'main' ||
                    childTag == 'mian') &&
                (targetEl.classes.contains('comiis_message_table') ||
                    targetEl.classes.contains('comiis_messages') ||
                    targetEl.classes.contains('view_one') ||
                    targetEl.classes.contains('view_all') ||
                    targetEl.id.startsWith('postmessage_') ||
                    targetEl.classes.contains('t_f') ||
                    targetEl.classes.contains('message') ||
                    child.querySelector(
                          '.comiis_message_table, .comiis_messages, .comiis_a, td.t_f, td[id^="postmessage_"]',
                        ) !=
                        null));

        if (isWrapper) {
          targetEl = child;
          continue;
        }
      }
      break;
    }

    for (final node in targetEl.nodes) {
      if (node is html_dom.Text) {
        final text = node.text
            .replaceAll(auditNoticeRegExp, '')
            .replaceAll(auditNoticeGeneralRegExp, '')
            .replaceAll(
                RegExp(r'本(?:主题|帖)最后由\s*.*?\s*编辑', caseSensitive: false), '')
            .trim();
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

        // 换行标签 <br>（严格保留，防止段落坍塌黏连）
        if (tag == 'br') {
          _appendOrMergeTextBlock(blocks, '<br>', align: currentAlign);
          continue;
        }

        // 分割线标签 <hr> 或分割线容器
        if (tag == 'hr' || node.classes.contains('hrline')) {
          blocks.add(const DividerBlock());
          continue;
        }

        // 识别纯分割线图片容器（例如 <p><img file="static/image/hrline/line4.png" /></p> 或 <div align="center"><img ...></div>）
        final allImgsInNode = node.querySelectorAll('img');
        if (allImgsInNode.length == 1 &&
            (tag == 'p' || tag == 'div' || tag == 'center' || tag == 'span') &&
            node.text.trim().isEmpty) {
          final singleImg = allImgsInNode.first;
          final s = singleImg.attributes['file'] ??
              singleImg.attributes['zoomfile'] ??
              singleImg.attributes['data-src'] ??
              singleImg.attributes['comiis_loadimages'] ??
              singleImg.attributes['src'] ??
              '';
          final rawW = int.tryParse(singleImg.attributes['width'] ?? '');
          final rawH = int.tryParse(singleImg.attributes['height'] ?? '');
          if (isDividerImage(
            s,
            width: rawW,
            height: rawH,
            alt: singleImg.attributes['alt'],
            title: singleImg.attributes['title'],
            style: singleImg.attributes['style'],
          )) {
            blocks.add(const DividerBlock());
            continue;
          }
        }

        // 0. 管理/审核状态条 (.comiis_modact / .modact / 审核通过记录)
        // 彻底过滤 Discuz 系统审核与管理操作记录，严禁作为帖子正文内容解析
        if (node.classes.contains('comiis_modact') ||
            node.classes.contains('modact') ||
            node.classes.contains('psth') ||
            node.classes.contains('modaction') ||
            innerText.contains('审核通过') ||
            (innerText.contains('由') && innerText.contains('审核'))) {
          final remaining = innerText
              .replaceAll(auditNoticeRegExp, '')
              .replaceAll(auditNoticeGeneralRegExp, '')
              .trim();
          if (remaining.isEmpty) {
            continue;
          }
          // 若当前节点同时包含真实帖子正文，绝不能跳过丢弃！剔除审核通知后继续向下解析！
          node.innerHtml = node.innerHtml
              .replaceAll(auditNoticeRegExp, '')
              .replaceAll(auditNoticeGeneralRegExp, '');
        }

        // 0. 投票帖专属卡片 (.comiis_poll, form#poll, div.poll, .comiis_poll_list, .pcht)
        if (node.classes.contains('comiis_poll') ||
            node.classes.contains('comiis_poll_list') ||
            node.classes.contains('poll') ||
            node.classes.contains('pcht') ||
            (tag == 'form' &&
                (node.id == 'poll' ||
                    node.attributes['action']?.contains('votepoll') == true)) ||
            (tag == 'div' && node.id == 'poll')) {
          var title = node
                  .querySelector('.comiis_poll_top h2, .pinf strong, h2')
                  ?.text
                  .trim() ??
              '投票';
          title = title
              .replaceAll(
                  RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF\u{F0000}-\u{10FFFF}]',
                      unicode: true),
                  '')
              .trim();
          if (title.isEmpty) title = '投票';

          final votersM = RegExp(r'共有\s*(\d+)\s*人').firstMatch(node.text);
          final votersCount =
              votersM != null ? int.tryParse(votersM.group(1)!) ?? 0 : 0;

          final maxM = RegExp(r'最多可选\s*(\d+)\s*项').firstMatch(node.text);
          final maxChoices =
              maxM != null ? int.tryParse(maxM.group(1)!) ?? 1 : 1;

          final isClosed = node.text.contains('投票已经结束') ||
              node.text.contains('投票已结束') ||
              node.text.contains('关闭或者过期');

          String? expireText = isClosed ? '投票已经结束' : null;
          if (expireText == null) {
            final expM =
                RegExp(r'距结束[^\d]*(\d+[^<\n\s]+)').firstMatch(node.text);
            if (expM != null) {
              expireText = expM.group(1)?.trim();
            } else {
              final expEl =
                  node.querySelector('.kmbtn span, .poll_time, .ptmr');
              if (expEl != null) {
                final txt = expEl.text.replaceAll('距结束还有:', '').trim();
                if (txt.isNotEmpty) expireText = txt;
              }
            }
          }

          final options = <PollOption>[];
          final optLis = node.querySelectorAll(
              '.comiis_poll_list li, .pcht tr, .poll_options li');
          int optIdx = 1;
          for (int i = 0; i < optLis.length; i++) {
            final li = optLis[i];
            final labelEl = li.querySelector('label, .pvt, span.label');
            var name = labelEl?.text.trim() ?? '';
            if (name.isEmpty && li.classes.contains('kmnop')) {
              name = li.text.trim();
            }
            name = cleanPollOptionLabel(name);
            if (name.isEmpty) continue;

            final inputEl = li.querySelector(
                'input[name="pollanswers[]"], input[type="radio"], input[type="checkbox"]');
            final pollOptionId =
                int.tryParse(inputEl?.attributes['value'] ?? '') ?? optIdx;

            int votes = 0;
            double percent = 0.0;
            String? color;

            if (i + 1 < optLis.length &&
                (optLis[i + 1].classes.contains('poll_ok') ||
                    optLis[i + 1].querySelector('.pbr') != null)) {
              final resultLi = optLis[i + 1];
              final numM = RegExp(r'\((\d+)\)').firstMatch(resultLi.text) ??
                  RegExp(r'(\d+)\s*票').firstMatch(resultLi.text);
              if (numM != null) votes = int.tryParse(numM.group(1)!) ?? 0;

              final pctM = RegExp(r'([\d.]+)\s*%').firstMatch(resultLi.text);
              if (pctM != null) {
                percent = double.tryParse(pctM.group(1)!) ?? 0.0;
              }

              final em =
                  resultLi.querySelector('em[style*="background-color"]');
              if (em != null) {
                final style = em.attributes['style'] ?? '';
                final bgM = RegExp(
                        r'background-color:\s*(#[0-9a-fA-F]{3,8}|rgb\([^)]+\))')
                    .firstMatch(style);
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
          final totalReward =
              totalM != null ? int.tryParse(totalM.group(1)!) ?? 0 : 0;
          final perM = RegExp(r'回复本帖可获得\s*(\d+)').firstMatch(innerText) ??
              RegExp(r'回帖奖励\s*\+(\d+)').firstMatch(innerText);
          final perReplyReward =
              perM != null ? int.tryParse(perM.group(1)!) ?? 0 : 0;
          final limitM = RegExp(r'每人限\s*(\d+)\s*次').firstMatch(innerText);
          final limitCount =
              limitM != null ? int.tryParse(limitM.group(1)!) ?? 1 : 1;

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

        // 1. 引用块优先匹配 (.comiis_quote, blockquote, .quote, .flw_quote)
        final isQuoteNode = tag != 'table' &&
            (tag == 'blockquote' ||
                node.classes.contains('quote') ||
                node.classes.contains('comiis_quote') ||
                node.classes.contains('flw_quote') ||
                (tag == 'div' &&
                    node.children.length == 1 &&
                    (node.children.first.localName == 'blockquote' ||
                        node.children.first.classes.contains('quote') ||
                        node.children.first.classes.contains('comiis_quote'))));

        if (isQuoteNode) {
          var author = '引用';
          final bq = tag == 'blockquote'
              ? node
              : (node.querySelector('blockquote') ?? node);
          var quoteContent = bq.innerHtml;

          // 尝试从引用头中提取发言人和时间：
          // Discuz 典型格式 1: <font color="#999999">username 发表于 2024-4-15 11:21</font>
          // Discuz 典型格式 2: <a ...><font color="#999999">username 发表于 2024-4-15 11:21</font></a>
          // Discuz 典型格式 3: <span class="f_d">username 发表于 2024-4-15 11:21</span>
          final metaFont = bq.querySelector(
            'font[color*="999999"], font[color*="grey"], font[color*="gray"], font[color*="888888"], font[color*="aaa"], span.f_d, a[href*="findpost"]',
          );
          if (metaFont != null && metaFont.text.contains('发表于')) {
            author = metaFont.text.trim().replaceAll(RegExp(r'\s+'), ' ');
            final parent = metaFont.parent;
            if (parent != null &&
                (parent.localName == 'a' || parent.localName == 'font')) {
              parent.remove();
            } else {
              metaFont.remove();
            }
            quoteContent = bq.innerHtml;
          } else {
            final textHeader = bq.text.trim();
            final headerM = RegExp(r'^([^\n\r]+?\s*发表于\s*[^\n\r<]+)')
                .firstMatch(textHeader);
            if (headerM != null) {
              author = headerM.group(1)!.trim();
              quoteContent =
                  quoteContent.replaceFirst(headerM.group(1)!, '').trim();
            } else {
              final quoteM = RegExp(
                r'\[quote\](?:([^:]+):)?([\s\S]*?)\[/quote\]',
              ).firstMatch(innerText);
              if (quoteM != null && quoteM.group(1) != null) {
                author = quoteM.group(1)!.trim();
                quoteContent = quoteM.group(2)?.trim() ?? quoteContent;
              }
            }
          }
          quoteContent = quoteContent.replaceFirst(
              RegExp(r'^(?:\s*<br\s*/?>\s*)+', caseSensitive: false), '');
          blocks.add(QuoteBlock(
              author: author, contentHtml: quoteContent, align: nodeAlign));
          continue;
        }

        // 0. 悬赏问答专属卡片 (.comiis_xstop, .comiis_xsda, .comiis_reward, .rwd, .rusld)
        // 严格遵循：仅在首楼 (isFirstFloor) 且存在真实 Discuz 悬赏结构容器时解析；非首楼回复严禁生成悬赏卡片！
        final isBountyCard = isFirstFloor &&
            (node.classes.contains('comiis_xstop') ||
                node.classes.contains('comiis_xsda') ||
                node.classes.contains('comiis_reward') ||
                node.classes.contains('rusld') ||
                (tag == 'div' &&
                    node.classes.contains('rwd') &&
                    !node.classes.contains('quote')));

        if (isBountyCard) {
          final isSolved = innerText.contains('已解决') ||
              innerText.contains('最佳答案') ||
              innerText.contains('已结束') ||
              innerText.contains('已结贴');

          int price = 0;
          String unit = '粒铁粒';

          // 1. 如果已解决，优先从 "本悬赏已解决并结束 ( 10 粒铁粒 )" 或 "已解决... (10 粒铁粒)" 中提取
          final solvedM = RegExp(
            r'(?:已解决并结束|已解决|已结束|最佳答案|结贴)[^\d]*\(?\s*(\d+)\s*([^)\r\n\s]+)?\)?',
          ).firstMatch(innerText);
          if (solvedM != null) {
            price = int.tryParse(solvedM.group(1)!) ?? 0;
            if (solvedM.group(2) != null &&
                solvedM.group(2)!.trim().isNotEmpty) {
              unit = solvedM.group(2)!.trim();
            }
          }

          // 2. 如果未提取到有效金额，从标准悬赏文案中提取 "悬赏 10 粒铁粒"
          if (price <= 0) {
            final priceM = RegExp(r'悬赏\s*(\d+)').firstMatch(innerText);
            if (priceM != null) {
              price = int.tryParse(priceM.group(1)!) ?? 0;
            }
          }

          // 3. 提取货币单位
          final unitM = RegExp(
            r'(?:悬赏\s*\d+\s*|(?:\(|\（)\s*\d+\s*)([^\r\n0-9\(\)\（\）]+?)(?:我来回答|\)|\）|$)',
          ).firstMatch(innerText);
          if (unitM != null && unitM.group(1)!.trim().isNotEmpty) {
            unit = unitM.group(1)!.trim();
          }

          // 4. 再次兜底检查类似 "( 10 粒铁粒 )"
          if (price <= 0) {
            final bracketM = RegExp(r'\(?\s*(\d+)\s*(粒铁粒|铁粒|金粒|金币|积分|贡献)\s*\)?')
                .firstMatch(innerText);
            if (bracketM != null) {
              price = int.tryParse(bracketM.group(1)!) ?? 0;
              unit = bracketM.group(2)!;
            }
          }

          final msgM = RegExp(r'您的回答被采纳后将获得[^\r\n]+').firstMatch(innerText);
          final msg = isSolved
              ? (price > 0
                  ? '本悬赏已圆满结贴，最佳答案已产生并获得奖励 ($price $unit)'
                  : '本悬赏已圆满结贴，最佳答案已产生并获得奖励')
              : (msgM?.group(0) ??
                  (price > 0 ? '您的回答被采纳后将获得$price$unit' : null));

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

        // 1.5 飞行动画文字区块 (Discuz [fly] / <marquee class="discuz_fly">)
        if (tag == 'marquee' ||
            tag == 'fly' ||
            node.classes.contains('discuz_fly') ||
            node.classes.contains('fly')) {
          blocks.add(
            FlyBlock(
              node.innerHtml.isNotEmpty ? node.innerHtml : innerText,
              align: nodeAlign,
            ),
          );
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

          final cloned = node.clone(true);
          cloned
              .querySelectorAll('em, .copycode, a.copy, span.copy')
              .forEach((e) => e.remove());
          final lis = cloned.querySelectorAll('li');
          String codeText;
          if (lis.isNotEmpty) {
            codeText = lis.map((e) => e.text).join('\n');
          } else {
            codeText = cloned.text.trim();
          }
          blocks.add(
              CodeBlock(code: codeText, language: language, align: nodeAlign));
          continue;
        }

        // 3. 折叠内容 (Discuz spoiler / details / collapse / showhide / fold)
        if (tag == 'details' ||
            node.classes.any((c) =>
                c.contains('spoiler') ||
                c.contains('collapse') ||
                c.contains('showhide') ||
                c.contains('fold'))) {
          final summaryEl = node.querySelector(
            'summary, .spoilerheader, .spoiler-title, .title, input.yc, h4',
          );
          var title = summaryEl?.attributes['value'] ??
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
              contentHtml:
                  contentHtml.isNotEmpty ? contentHtml : node.innerHtml,
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
          // 仅检测直接挂在 directTrs 下的 th，严禁深度搜索子嵌套表格的 th
          final hasDirectTh = directTrs
              .any((tr) => tr.children.any((c) => c.localName == 'th'));
          int maxDirectCols = 0;
          for (final tr in directTrs) {
            final colCount = tr.children
                .where((c) => c.localName == 'td' || c.localName == 'th')
                .length;
            if (colCount > maxDirectCols) maxDirectCols = colCount;
          }

          // 核心判断：当且仅当所有直接行都只有 <= 1 列且无直接 th 时，属于 Discuz 单列排版卡片/嵌套包装表格
          final isLayoutTable = !hasDirectTh && maxDirectCols <= 1;

          if (isLayoutTable) {
            final rawStyle = node.attributes['style'] ?? '';
            var rawBg = node.attributes['bgcolor'] ??
                _extractCssProperty(rawStyle, 'background-color') ??
                _extractCssProperty(rawStyle, 'background');
            var rawBorderColor = node.attributes['bordercolor'] ??
                _extractCssProperty(rawStyle, 'border-color') ??
                _extractCssProperty(rawStyle, 'border');
            final hasBorderAttr = (node.attributes['border'] != null &&
                node.attributes['border'] != '0');
            if (rawBorderColor == null && hasBorderAttr) {
              rawBorderColor = '#e0e0e0';
            }

            final cellBlocks = <PostBlock>[];
            if (directTrs.isNotEmpty) {
              for (final tr in directTrs) {
                final trStyle = tr.attributes['style'] ?? '';
                final trBg = tr.attributes['bgcolor'] ??
                    _extractCssProperty(trStyle, 'background-color') ??
                    _extractCssProperty(trStyle, 'background');
                if (rawBg == null || rawBg.isEmpty) rawBg = trBg;

                for (final cell in tr.children.where(
                  (c) => c.localName == 'td' || c.localName == 'th',
                )) {
                  final cellStyle = cell.attributes['style'] ?? '';
                  final cellBg = cell.attributes['bgcolor'] ??
                      _extractCssProperty(cellStyle, 'background-color') ??
                      _extractCssProperty(cellStyle, 'background');
                  if (rawBg == null || rawBg.isEmpty) rawBg = cellBg;

                  cellBlocks.addAll(
                      parseStructuredBlocks(cell, inheritedAlign: nodeAlign));
                }
              }
            } else {
              for (final child in node.children) {
                cellBlocks.addAll(
                    parseStructuredBlocks(child, inheritedAlign: nodeAlign));
              }
            }

            final isFrameworkWrapper = node.querySelector(
                    'main.comiis_a, .comiis_message_table, .comiis_vrx, .comiis_message, #postlist') !=
                null;
            final hasExplicitStyling = !isFrameworkWrapper &&
                ((rawBg != null &&
                        rawBg.isNotEmpty &&
                        rawBg != 'none' &&
                        rawBg != 'transparent') ||
                    (rawBorderColor != null && rawBorderColor.isNotEmpty) ||
                    hasBorderAttr);

            if (hasExplicitStyling) {
              blocks.add(
                CardContainerBlock(
                  children: cellBlocks,
                  bgColor: rawBg,
                  borderColor: rawBorderColor,
                  align: nodeAlign,
                ),
              );
            } else {
              // 普通无修饰布局包装表格（如移动端框架 table wrapper），直接解包子区块，避免添加多余外框
              blocks.addAll(cellBlocks);
            }
            continue;
          }

          if (maxDirectCols >= 2 || hasDirectTh) {
            final headers = <String>[];
            final rows = <List<String>>[];
            for (final tr in directTrs) {
              final ths = tr.children.where((c) => c.localName == 'th');
              final tds = tr.children.where((c) => c.localName == 'td');
              if (ths.isNotEmpty && tds.isEmpty) {
                for (final th in ths) {
                  headers.add(
                    th.innerHtml.trim().isNotEmpty
                        ? th.innerHtml.trim()
                        : th.text.trim(),
                  );
                }
              } else {
                final cells = <String>[];
                for (final cell in tr.children
                    .where((c) => c.localName == 'td' || c.localName == 'th')) {
                  cells.add(
                    cell.innerHtml.trim().isNotEmpty
                        ? cell.innerHtml.trim()
                        : cell.text.trim(),
                  );
                }
                if (cells.isNotEmpty) rows.add(cells);
              }
            }
            if (headers.isNotEmpty || rows.isNotEmpty) {
              blocks.add(
                  TableBlock(headers: headers, rows: rows, align: nodeAlign));
              continue;
            }
          }
        }

        // 5. 视频与内嵌多媒体（iframe、video、embed 与 a.discuz_media）
        if (tag == 'iframe' ||
            tag == 'video' ||
            tag == 'embed' ||
            (tag == 'a' && node.classes.contains('discuz_media'))) {
          var rawSrc = node.attributes['src'] ??
              node.attributes['href'] ??
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

            final mediaInfo = _resolveVideoMedia(src);
            blocks.add(
              VideoBlock(
                src: mediaInfo.resolvedSrc,
                isBilibili: mediaInfo.isBilibili,
                bvid: mediaInfo.bvid,
                aid: mediaInfo.aid,
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

        // 7.0 评论复审中提示卡片 (Discuz 评论复审中... 编号: 10465735)
        if (innerText.contains('评论复审中') ||
            (innerText.contains('复审中') && innerText.contains('编号'))) {
          final idM = RegExp(r'编号[:：\s]*(\d+)').firstMatch(innerText);
          final reviewId = idM?.group(1);
          blocks.add(ReviewStatusBlock(status: '评论复审中...', reviewId: reviewId));
          continue;
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
        final isDedicatedHide = node.classes.contains('locked') ||
            node.classes.contains('comiis_hide') ||
            node.classes.contains('locked_hide');
        final isShortTextHide =
            (node.children.isEmpty || node.children.length == 1) &&
                innerText.length < 120 &&
                (innerText.contains('回复可见') ||
                    innerText.contains('隐藏的内容') ||
                    innerText.contains('查看本帖隐藏内容请回复'));

        if (isDedicatedHide || isShortTextHide) {
          blocks.add(
            HideBlock(
              reason: innerText.isNotEmpty ? innerText : '本帖隐藏的内容需要回复才可以浏览',
            ),
          );
          continue;
        }

        // 8. 附件下载识别（优先于独立图片解析，防止附件文件类型小图标被错误识别为独立帖子图片）
        // 支持移动端 .comiis_attach、PC 端 dl.tattl / p.attnm / .attach_nopermission / a[href*="attachment"] / a[href*="aid="] / a[href*="klpbbs_download"] / a[href*="download.php"]
        final hasRealContentImage = node.querySelector(
                'img.zoom, img[aid], img[file], img[zoomfile], img.comiis_poster') !=
            null;

        final attachA = !hasRealContentImage
            ? (node.querySelector(
                  'a[href*="mod=attachment"], a[href*="attachment.php"], a[href*="aid="], a[href*="klpbbs_download"], a[href*="download.php"], a[href*="attach"]',
                ) ??
                (node.localName == 'a' &&
                        (node.attributes['href']?.contains('attach') == true ||
                            node.attributes['href']?.contains('aid=') == true ||
                            node.attributes['href']?.contains('download') ==
                                true)
                    ? node
                    : null))
            : null;

        // 专有独立附件容器（移动端 .comiis_attach、.attach_nopermission、.box_attach、PC 端 dl.tattl / p.attnm）
        final isDedicatedAttachNode = node.classes.contains('comiis_attach') ||
            node.classes.contains('attach_nopermission') ||
            node.classes.contains('box_attach') ||
            (tag == 'dl' && node.classes.contains('tattl')) ||
            (tag == 'p' && node.classes.contains('attnm'));

        // 关键安全修复：不能将包含丰富图文或多段落内容的复合容器误判为单一附件节点（TID 133669）
        // 专有附件节点（如 .comiis_attach）天生包含 attach_tit/attach_size/图标，严禁被误杀判定为复合容器
        final isCompositeContainer =
            !isDedicatedAttachNode &&
                (tag == 'div' ||
                    tag == 'center' ||
                    tag == 'p' ||
                    tag == 'table') &&
                (node
                            .querySelectorAll(
                                'p:not(.attach_tit):not(.attach_size), table, blockquote, h1, h2, h3, h4, hr')
                            .length >
                        1 ||
                    node
                            .querySelectorAll(
                                '.comiis_attach, dl.tattl, .attach_nopermission')
                            .length >
                        1 ||
                    node.text.trim().length > 120);

        final isAttachNode = !hasRealContentImage &&
            (isDedicatedAttachNode ||
                (!isCompositeContainer &&
                    (node.classes.any((c) => c.contains('attach')) ||
                        node.id.contains('attach') ||
                        node.querySelector(
                              '.attach_tit, .attnm, .tattl, .attach_size, .att_price, .attach_price',
                            ) !=
                            null ||
                        (tag == 'a' && attachA != null))));

        if (isAttachNode && attachA != null) {
          final href = _absolute(attachA.attributes['href']) ?? '';
          if (href.isNotEmpty) {
            // 文件名：优先 .attach_tit span，其次 attnm a，其次 attachA 文本
            var rawName = node.querySelector('.attach_tit span')?.text.trim() ??
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
              '.attach_tit img, img[src*="filetype"], img[src*="attach"], img.vm',
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
            final sizeRaw = node
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

        // 9. 独占图片 / 图片包装容器 (ignore_js_op, div[align="center"] 包裹的图片, span.comiis_postimg, div.postimg, a.zoom 等)
        final isAttachContainer = node.classes
                .any((c) => c.contains('attach')) ||
            node.id.contains('attach') ||
            node.querySelector(
                    '.comiis_attach, .attach_tit, .tattl, .attnm, .attach_size') !=
                null ||
            node.querySelector(
                    'a[href*="mod=attachment"], a[href*="attachment.php"], a[href*="aid="], a[href*="klpbbs_download"], a[href*="download.php"]') !=
                null;

        // 核心安全防御：复合容器（包含音视频/表格/代码/折叠/引用/多张图片）严禁作为单一图片容器直接截断，必须交由后方通用容器展开递归解析
        final hasOtherRichMedia = node.querySelector(
              'audio, video, iframe, embed, table, .spoiler, .collapse, .showhide, blockquote, .quote, pre, code, .blockcode, .comiis_blockcode, hr',
            ) !=
            null;

        final contentImages = node.querySelectorAll('img').where((img) {
          final src = img.attributes['src'] ??
              img.attributes['file'] ??
              img.attributes['zoomfile'] ??
              img.attributes['comiis_loadimages'] ??
              '';
          final isSmiley = src.contains('static/image/smiley/') ||
              src.contains('post/smile') ||
              img.attributes.containsKey('smilieid');
          final isFileTypeIcon = src.contains('/filetype/') ||
              src.contains('static/image/filetype') ||
              src.contains('image/filetype') ||
              src.contains('/common/none.gif') ||
              src.contains('/common/attach');
          final rawW = int.tryParse(img.attributes['width'] ?? '');
          final rawH = int.tryParse(img.attributes['height'] ?? '');
          final isSmallIcon = (rawW != null && rawW > 0 && rawW <= 36) ||
              (rawH != null && rawH > 0 && rawH <= 36) ||
              img.classes.contains('vm') ||
              src.contains('/common/') ||
              src.contains('template/');
          final isDivider = isDividerImage(
            src,
            width: rawW,
            height: rawH,
            alt: img.attributes['alt'],
            title: img.attributes['title'],
            style: img.attributes['style'],
          );
          return !isSmiley && !isFileTypeIcon && !isSmallIcon && !isDivider;
        }).toList();

        html_dom.Element? imgEl;
        if (!isAttachContainer) {
          if (tag == 'img') {
            imgEl = node;
          } else if ((tag == 'ignore_js_op' ||
                  node.querySelector('ignore_js_op') != null ||
                  tag == 'div' ||
                  tag == 'span' ||
                  tag == 'p' ||
                  tag == 'center') &&
              !hasOtherRichMedia &&
              contentImages.length == 1) {
            final cloneForText = node.clone(true);
            cloneForText
                .querySelectorAll('.tip, .aimg_tip, .popup, em.xg1')
                .forEach((e) => e.remove());
            final pureText = cloneForText.text.trim();
            final isSimpleWrapper = pureText.isEmpty ||
                node.children.every((c) {
                  if (c.localName == 'img' ||
                      c.localName == 'br' ||
                      c.localName == 'a' ||
                      c.localName == 'ignore_js_op' ||
                      c.classes.contains('tip') ||
                      c.classes.contains('aimg_tip')) {
                    return true;
                  }
                  if (c.localName == 'div') {
                    if (c.classes.contains('tip') ||
                        c.classes.contains('aimg_tip')) {
                      return true;
                    }
                    return c.children.every((gc) =>
                        gc.localName == 'img' ||
                        gc.localName == 'a' ||
                        gc.localName == 'ignore_js_op');
                  }
                  return false;
                });
            if (isSimpleWrapper) {
              imgEl = contentImages.first;
            }
          }
        }
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
              final rawW = int.tryParse(imgEl.attributes['width'] ?? '');
              final rawH = int.tryParse(imgEl.attributes['height'] ?? '');
              final isDivider = isDividerImage(
                src,
                width: rawW,
                height: rawH,
                alt: imgEl.attributes['alt'],
                title: imgEl.attributes['title'],
                style: imgEl.attributes['style'],
              );
              if (isDivider) {
                blocks.add(const DividerBlock());
                continue;
              }
              final isEmoji = src.contains('static/image/smiley/') ||
                  src.contains('post/smile') ||
                  imgEl.attributes.containsKey('smilieid');
              final isFileTypeIcon = src.contains('/filetype/') ||
                  src.contains('static/image/filetype') ||
                  src.contains('image/filetype') ||
                  src.contains('/common/none.gif') ||
                  src.contains('/common/attach');
              final isSmallIcon = (rawW != null && rawW > 0 && rawW <= 36) ||
                  (rawH != null && rawH > 0 && rawH <= 36) ||
                  imgEl.classes.contains('vm') ||
                  src.contains('/common/') ||
                  src.contains('template/');
              if (isEmoji || isSmallIcon) {
                // 表情小图与行内图标保留在 TextBlock 内，由富文本行内渲染引擎处理，避免打断连续行内句子排版
                _appendOrMergeTextBlock(blocks, outerHtml, align: nodeAlign);
                continue;
              }
              if (isFileTypeIcon) {
                // 附件类型图标小图标，不作为独立帖子插图渲染
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

        // 10. 网盘下载链接与提取码识别
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

        // 如果内部包含独立 iframe/video/embed，拆成视频/音频区块
        final subMedias = node.querySelectorAll('iframe, video, embed');
        if (subMedias.isNotEmpty && node.text.trim().isEmpty) {
          for (final media in subMedias) {
            final src = _absolute(
                  media.attributes['src'] ?? media.attributes['data-src'],
                ) ??
                '';
            if (src.isEmpty) continue;
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
                  title: isNetEase ? '网易云音乐' : '音频文件',
                  align: nodeAlign,
                ),
              );
              continue;
            }
            final mediaInfo = _resolveVideoMedia(src);
            blocks.add(
              VideoBlock(
                src: mediaInfo.resolvedSrc,
                isBilibili: mediaInfo.isBilibili,
                bvid: mediaInfo.bvid,
                aid: mediaInfo.aid,
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
          'dl',
          'dd',
          'dt',
          'ignore_js_op',
        };
        if (containerTags.contains(tag)) {
          // 检测是否有富内容子元素值得递归展开（排除行内表情图片）
          final hasRichChildren = node.querySelector(
                    'iframe, video, embed, audio, details, [class*="spoiler"], [class*="collapse"], .showhide, blockquote, .quote, .comiis_quote, .flw_quote, pre, code, .blockcode, .comiis_blockcode, table, .locked, .comiis_hide, .comiis_postimg, .comiis_attach, .pattl, dl.tattl, .attach_nopermission, .box_attach, div.attachlist, .attach_tit, .attnm, a[href*="mod=attachment"], a[href*="attachment.php"], a[href*="aid="], a[href*="klpbbs_download"], a[href*="download.php"]',
                  ) !=
                  null ||
              node.querySelectorAll('img').any((img) {
                final src = img.attributes['src'] ??
                    img.attributes['file'] ??
                    img.attributes['zoomfile'] ??
                    img.attributes['comiis_loadimages'] ??
                    '';
                final isSmiley = src.contains('static/image/smiley/') ||
                    src.contains('post/smile') ||
                    img.attributes.containsKey('smilieid');
                final isFileTypeIcon = src.contains('/filetype/') ||
                    src.contains('static/image/filetype') ||
                    src.contains('image/filetype') ||
                    src.contains('/common/none.gif') ||
                    src.contains('/common/attach');
                final rawW = int.tryParse(img.attributes['width'] ?? '');
                final rawH = int.tryParse(img.attributes['height'] ?? '');
                final isSmallIcon = (rawW != null && rawW > 0 && rawW <= 36) ||
                    (rawH != null && rawH > 0 && rawH <= 36) ||
                    img.classes.contains('vm') ||
                    src.contains('/common/') ||
                    src.contains('template/');
                return !isSmiley && !isFileTypeIcon && !isSmallIcon;
              });

          if (hasRichChildren && node.children.isNotEmpty) {
            // 递归展开此容器的所有子节点（保持对齐方式向下传递）
            blocks
                .addAll(parseStructuredBlocks(node, inheritedAlign: nodeAlign));
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

  static String? _extractCssProperty(String style, String property) {
    if (style.isEmpty) return null;
    final regex = RegExp(
      '(?:^|;)\\s*${RegExp.escape(property)}\\s*:\\s*([^;]+)',
      caseSensitive: false,
    );
    final match = regex.firstMatch(style);
    return match?.group(1)?.trim();
  }

  static void _appendOrMergeTextBlock(
    List<PostBlock> blocks,
    String html, {
    String? align,
  }) {
    if (blocks.isNotEmpty && blocks.last is TextBlock) {
      final last = blocks.removeLast() as TextBlock;
      // 当累积文本长度超过 2000 字符时，拆分为独立 TextBlock，避免单个段落生成上万像素超大图层导致 GPU 显存爆满卡顿
      if (last.align == align && last.html.length < 2000) {
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
  static String bbcodeToHtml(String text,
      {List<SmileyCategory>? customSmileys, bool escapeHtml = true}) {
    return bbcode_lib.bbcodeToHtml(text,
        customSmileys: customSmileys, escapeHtml: escapeHtml);
  }

  /// 仅展示服务器返回的权限，不使用本地用户组字典补齐。
  static UsergroupComparison parseUsergroupComparison(
    String html, {
    String? currentGroupName,
    int? currentCredits,
    String? targetGroupName,
    int? gid,
  }) =>
      DiscuzUsergroupParser.parse(html);
}

/// 后台 Isolate 并发解析帖子详情顶级函数
ThreadDetailParsed _parseThreadDetailCompute(String html) {
  return ComiisParser.parseThreadDetail(html);
}

/// 后台 Isolate 并发解析结构化区块顶级函数
List<PostBlock> _parseStructuredBlocksCompute(String html) {
  return ComiisParser.parseStructuredBlocksFromHtml(html);
}
