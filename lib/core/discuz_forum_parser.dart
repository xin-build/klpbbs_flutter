import 'package:html/parser.dart' as html;
import '../models/forum.dart';
import 'discuz_site_stats.dart';
import 'discuz_forum_counters.dart';

/// KLPBBS 新版 PC 分区卡片；所有名称和计数来自当前网页。
class DiscuzForumParser {
  /// Canonical forum-display routes and the verified KLPBBS skin alias.
  /// User/profile, last-post redirects and off-site links are not forums.
  static int? forumId(String href, Uri base) {
    final uri = _resolve(href, base);
    if (uri == null || uri.origin != base.origin || uri.userInfo.isNotEmpty) {
      return null;
    }
    final rewrite = RegExp(r'^/forum-(\d+)-\d+\.html$').firstMatch(uri.path);
    if (rewrite != null) {
      return int.tryParse(rewrite.group(1)!)?.takePositive();
    }
    // The live site's forum-skin route is board 54, not the JE redirect 50.
    // Its directory icon and both forum templates were checked against fid=54.
    final skin = RegExp(r'^/forum-skin-([1-9]\d*)\.html$').hasMatch(uri.path);
    if (base.host == 'klpbbs.com' && skin) return 54;
    if (!uri.path.endsWith('/forum.php') ||
        uri.queryParametersAll['mod']?.length != 1 ||
        uri.queryParameters['mod'] != 'forumdisplay' ||
        uri.queryParametersAll['fid']?.length != 1) {
      return null;
    }
    return int.tryParse(uri.queryParameters['fid'] ?? '')?.takePositive();
  }

  /// Discuz default and Comiis explicitly declared child-forum containers.
  /// A generic forum box is accepted only beside its 子版块 heading.
  static List<Forum> parseSubForums(String source, Uri base,
      {required int currentFid}) {
    if (currentFid <= 0 || !recognizesPage(source)) return const [];
    final doc = html.parse(source);
    final containers = doc
        .querySelectorAll('#subforum_$currentFid, #subforum, '
            '#subforum_list, .sub_forum, .comiis_sublist, '
            '.comiis_sub_list, .comiis_subforum, #comiis_sub_icobox, .comiis_forum_box')
        .where((box) {
      if (!box.classes.contains('comiis_forum_box')) return true;
      final heading = box.previousElementSibling;
      return heading?.classes.contains('comiis_gosx_tit') == true &&
          RegExp(r'子版[块塊]').hasMatch(heading!.text);
    });
    final seen = <int>{};
    final forums = <Forum>[];
    for (final container in containers) {
      final defaultTemplate = container.id == 'subforum_$currentFid';
      final links = defaultTemplate
          ? container.querySelectorAll('dt a[href], h2 a[href]')
          : container.querySelectorAll('a[href]');
      for (final link in links) {
        final fid = forumId(link.attributes['href'] ?? '', base);
        final title = (link.querySelector('p')?.text ?? link.text).trim();
        if (fid == null ||
            fid == currentFid ||
            title.isEmpty ||
            !seen.add(fid)) {
          continue;
        }
        var card = link;
        for (var parent = link.parent;
            parent != null && parent != container;
            parent = parent.parent) {
          if (parent.localName == 'li' ||
              parent.localName == 'tr' ||
              (parent.localName == 'td' && parent.classes.contains('fl_g'))) {
            card = parent;
            break;
          }
        }
        final image = card.querySelector('img');
        final src = image?.attributes['src'];
        final description = card.querySelector('p.xg2')?.text.trim();
        final counts = DiscuzForumCounters.defaultCard(card);
        final today = card.querySelector('em.xi1')?.text;
        forums.add(Forum(
            fid: fid,
            name: title,
            description: description,
            iconUrl: src == null ? null : _resolve(src, base)?.toString(),
            threadCount: counts['posts'] ?? -1,
            topicCount: counts['topics'] ?? -1,
            todayCount: _number(today) ?? -1,
            displayValues: counts.displayValues));
      }
    }
    return List.unmodifiable(forums);
  }

  static List<Forum> mergeSubForums(List<Forum> mobile, List<Forum> pc) {
    final pcById = {for (final f in pc) f.fid: f};
    final seen = <int>{};
    return List.unmodifiable([
      for (final f in mobile)
        if (seen.add(f.fid))
          _mergeCounts(f, pcById[f.fid]).copyWith(
              description: f.description?.isNotEmpty == true
                  ? f.description
                  : pcById[f.fid]?.description,
              iconUrl: f.iconUrl?.isNotEmpty == true
                  ? f.iconUrl
                  : pcById[f.fid]?.iconUrl),
      for (final f in pc)
        if (seen.add(f.fid)) f,
    ]);
  }

  static Forum _mergeCounts(Forum mobile, Forum? pc) {
    if (pc == null) return mobile;
    final counts = DiscuzForumCounts.prefer(
        DiscuzForumCounts.fromForum(pc), DiscuzForumCounts.fromForum(mobile));
    return mobile.copyWith(
        threadCount: counts['posts'] ?? -1,
        topicCount: counts['topics'] ?? -1,
        todayCount: counts['today'] ?? -1,
        displayValues: counts.displayValues);
  }

  /// A next-page button must retain the forum and both active filters.
  /// The native pager requests consecutive pages, so skipped-page links
  /// cannot be represented as a fabricated `hasMore` value.
  static int? forumNextPage(String source, int fid, int currentPage, Uri base,
      {int? typeid, String? orderby}) {
    if (!recognizesPage(source)) return null;
    final doc = html.parse(source);
    for (final link in doc.querySelectorAll('.pg a.nxt, .pg a.next, '
        '.comiis_page a.next, .comiis_page a.nxt, a#comiis_nextpage')) {
      final uri = _resolve(link.attributes['href'] ?? '', base);
      if (uri == null) continue;
      if (forumId(uri.toString(), base) != fid) continue;
      final q = uri.queryParameters;
      if (uri.queryParametersAll.values.any((values) => values.length != 1)) {
        continue;
      }
      final rewrite =
          RegExp(r'^/forum-(?:\d+|skin)-(\d+)\.html$').firstMatch(uri.path);
      final page = int.tryParse(q['page'] ?? rewrite?.group(1) ?? '');
      final actualType = int.tryParse(q['typeid'] ?? '') ?? 0;
      if (page == currentPage + 1 &&
          actualType == (typeid ?? 0) &&
          (q['orderby'] ?? '') == (orderby ?? '') &&
          (actualType == 0 || q['filter'] == 'typeid')) {
        return page;
      }
    }
    return null;
  }

  /// Discuz `multi()` renders the selected number as `.pg strong`.
  /// Missing, non-numeric or conflicting markers remain unknown; a next
  /// link or a requested URL is never used to invent the current page.
  static int? actualCurrentPage(String source) {
    final doc = html.parse(source);
    if (doc.querySelector('#messagetext, .alert_error, #loginform, '
            'form[id^="loginform_"]') !=
        null) {
      return null;
    }
    final numbers = <int>{};
    for (final marker
        in doc.querySelectorAll('.pg strong, .pg [aria-current="page"]')) {
      final text = marker.text.trim();
      if (!RegExp(r'^\d+$').hasMatch(text)) continue;
      final page = int.tryParse(text);
      if (page != null && page > 0) numbers.add(page);
    }
    return numbers.length == 1 ? numbers.single : null;
  }

  static int? _number(String? value) => DiscuzSiteStats.number(
      RegExp(r'[\d,，]+(?:\.\d+)?[万亿]?').firstMatch(value ?? '')?.group(0) ??
          '');

  static Uri? _resolve(String href, Uri base) {
    try {
      final uri = base.resolve(href);
      return uri.scheme == 'https' || uri.scheme == 'http' ? uri : null;
    } on FormatException {
      return null;
    }
  }

  static bool recognizesPage(String source) {
    final doc = html.parse(source);
    if (doc.querySelector('#messagetext, .alert_error, .comiis_password_top, '
            '#loginform, form[id^="loginform_"]') !=
        null) {
      return false;
    }
    return doc.querySelector(
            '.klp-fhead, #forumhd, #threadlist, .comiis_forumlist, '
            '.comiis_forumlist_head, .comiis_forumlist_heads, '
            'div[id^="subforum_"] > table.fl_tb') !=
        null;
  }

  /// Both template reads must refer to the same page and filtering operation.
  static String pagePath(int fid,
          {required String mobile,
          int page = 1,
          int? typeid,
          String? orderby}) =>
      Uri(path: 'forum.php', queryParameters: {
        'mod': 'forumdisplay',
        'fid': '$fid',
        if (typeid != null && typeid > 0) 'filter': 'typeid',
        if (typeid != null && typeid > 0) 'typeid': '$typeid',
        if (orderby?.isNotEmpty == true) 'orderby': orderby!,
        'page': '$page',
        'mobile': mobile,
      }).toString();

  /// Mobile supplies its higher-resolution icons; PC exposes exact counters
  /// and may declare additional forums for the current account's permissions.
  static List<ForumGroup> mergeGroups(
      List<ForumGroup> mobileGroups, List<ForumGroup> pcGroups) {
    final pcMap = {
      for (final g in pcGroups)
        for (final f in g.forums) f.fid: f
    };
    final result = <ForumGroup>[];
    final seen = <int>{};
    for (final group in mobileGroups.where((g) => g.gid != 0)) {
      final forums = <Forum>[];
      for (final mobile in group.forums) {
        if (mobile.fid <= 0 || !seen.add(mobile.fid)) continue;
        final pc = pcMap[mobile.fid];
        forums.add(_mergeCounts(mobile, pc).copyWith(
            gid: group.gid,
            description: mobile.description?.isNotEmpty == true
                ? mobile.description
                : pc?.description,
            iconUrl: mobile.iconUrl?.isNotEmpty == true
                ? mobile.iconUrl
                : pc?.iconUrl));
      }
      for (final pcGroup in pcGroups.where((g) => g.gid == group.gid)) {
        forums
            .addAll(pcGroup.forums.where((f) => f.fid > 0 && seen.add(f.fid)));
      }
      if (forums.isNotEmpty) {
        result
            .add(ForumGroup(gid: group.gid, name: group.name, forums: forums));
      }
    }
    for (final group in pcGroups.where((g) => g.gid != 0)) {
      final forums =
          group.forums.where((f) => f.fid > 0 && seen.add(f.fid)).toList();
      if (forums.isNotEmpty) {
        result
            .add(ForumGroup(gid: group.gid, name: group.name, forums: forums));
      }
    }
    return result;
  }

  static List<ForumGroup> parseModern(String source, Uri base) {
    final doc = html.parse(source);
    final groups = <ForumGroup>[];
    final seen = <int>{};
    for (final category in doc.querySelectorAll('#klp-forums .klp-cat')) {
      final heading = category.querySelector('.klp-cat-h h2 a');
      final gid = int.tryParse(Uri.tryParse(heading?.attributes['href'] ?? '')
              ?.queryParameters['gid'] ??
          '');
      final name = heading?.text.trim() ?? '';
      if (gid == null || name.isEmpty || !seen.add(gid)) continue;
      final forums = <Forum>[];
      for (final card
          in category.querySelectorAll('.klp-cat-grid > .klp-fcard')) {
        final link = card.querySelector('.klp-fname a[href]');
        final href = link?.attributes['href'] ?? '';
        final icon = card.querySelector('.klp-ficon img')?.attributes['src'];
        final fid = forumId(href, base);
        final title = link?.text.trim() ?? '';
        if (fid == null || title.isEmpty) continue;
        final counts = DiscuzForumCounters.modernCard(card);
        forums.add(Forum(
            fid: fid,
            name: title,
            gid: gid,
            description: card.querySelector('.klp-fdesc')?.text.trim(),
            iconUrl: icon == null ? null : base.resolve(icon).toString(),
            threadCount: counts['posts'] ?? -1,
            topicCount: counts['topics'] ?? -1,
            todayCount: counts['today'] ?? -1,
            displayValues: counts.displayValues));
      }
      if (forums.isNotEmpty) {
        groups.add(ForumGroup(gid: gid, name: name, forums: forums));
      }
    }
    return groups;
  }
}

extension on int {
  int? takePositive() => this > 0 ? this : null;
}
