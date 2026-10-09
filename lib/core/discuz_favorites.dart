import 'package:html/parser.dart' as html;
import '../models/forum.dart';
import 'discuz_form.dart';
import 'discuz_response.dart';

class DiscuzForumFavoritesPage {
  final bool recognized;
  final List<Forum> forums;
  final int? nextPage;
  const DiscuzForumFavoritesPage(this.recognized, this.forums, this.nextPage);
}

/// 收藏列表必须有实际列表容器或收藏项主键；导航里的 do=favorite 不算数据。
class DiscuzFavorites {
  static bool isFavoriteGroup(ForumGroup group) =>
      group.gid == 0 ||
      const {'我关注的', '我关注的版块', '我的收藏', '收藏版块', '我收藏的', '我收藏的版块'}
          .contains(group.name.trim());

  /// 个性化分组只来自当前账号已确认的收藏 ID；旧分组及空收藏不生成默认版块。
  static List<ForumGroup> groupsWithSavedForums(
      List<ForumGroup> groups, Set<int> ids,
      {Iterable<Forum> knownForums = const []}) {
    final publicGroups =
        groups.where((group) => !isFavoriteGroup(group)).toList();
    final known = {
      for (final group in publicGroups)
        for (final forum in group.forums) forum.fid: forum,
      for (final forum in knownForums) forum.fid: forum,
    };
    final saved = ids
        .where((fid) => fid > 0)
        .map((fid) =>
            (known[fid] ?? Forum(fid: fid, name: '版块 $fid')).copyWith(gid: 0))
        .toList();
    return [
      if (saved.isNotEmpty) ForumGroup(gid: 0, name: '我收藏的版块', forums: saved),
      ...publicGroups,
    ];
  }

  static bool isAlreadySaved(String source) {
    if (DiscuzForm.namedSubmit(source, 'favoritesubmit') != null) return false;
    final payload =
        RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source)?.group(1) ??
            source;
    final message = DiscuzResponse.message(source) ??
        html.parse(payload).body?.text.trim() ??
        '';
    return message.length < 160 &&
        RegExp(r'favorite_repeat|您已收藏|已收藏过|请勿重复收藏').hasMatch(message);
  }

  static bool recognizesThreads(String source) {
    final message = DiscuzResponse.message(source) ?? '';
    if (RegExp(r'抱歉|权限不足|请先登录|尚未登录|请先绑定').hasMatch(message)) return false;
    final doc = html.parse(source);
    if (doc.querySelector('#loginform, form[name="login"]') != null) {
      return false;
    }
    final roots = doc.querySelectorAll(
        '.comiis_mysclist, #favorite_ul, #favoriteform, #delform');
    if (roots.any((root) =>
        root.querySelector(
            'a[href*="thread-"], a[href*="mod=viewthread"], a[href*="tid="]') !=
        null)) {
      return true;
    }
    return doc
        .querySelectorAll(
            '#ct .emp, .comiis_mysclist .comiis_notip, #favorite_ul .emp')
        .any((node) => RegExp(r'暂无收藏|没有收藏|没有.*收藏|还没有.*收藏|no_favorite_yet')
            .hasMatch(node.text));
  }

  static int? nextPage(String source, String type) {
    final doc = html.parse(source);
    for (final link in doc.querySelectorAll(
        '.pg a.nxt, .comiis_pgs a, .comiis_page a, .comiis_pg a')) {
      final uri = Uri.tryParse(link.attributes['href'] ?? '');
      if (uri?.queryParameters['do'] != 'favorite' ||
          uri?.queryParameters['type'] != type) {
        continue;
      }
      if (link.classes.contains('nxt') ||
          RegExp(r'下(?:一)?页').hasMatch(link.text)) {
        return int.tryParse(uri!.queryParameters['page'] ?? '');
      }
    }
    return null;
  }

  static DiscuzForumFavoritesPage parseForums(String source) {
    final message = DiscuzResponse.message(source) ?? '';
    if (RegExp(r'抱歉|权限不足|请先登录|尚未登录|请先绑定').hasMatch(message)) {
      return const DiscuzForumFavoritesPage(false, [], null);
    }
    final doc = html.parse(source);
    final roots = doc.querySelectorAll(
        '.comiis_mysclist, #favorite_ul, #favoriteform, #delform');
    if (roots.isEmpty) {
      final empty = doc.querySelector('#ct p.emp');
      return DiscuzForumFavoritesPage(
          empty != null && empty.text.contains('收藏'), const [], null);
    }
    final result = <Forum>[];
    final seen = <int>{};
    for (final root in roots) {
      for (final item in root.querySelectorAll('li, tr, [id^="fav_"]')) {
        final link = item.querySelector(
            'h2 a[href*="forum-"], h2 a[href*="fid="], a[href*="forum-"], a[href*="forumdisplay"]');
        if (link == null) continue;
        final href = link.attributes['href'] ?? '';
        final uri = Uri.tryParse(href);
        final fid =
            int.tryParse(RegExp(r'forum-(\d+)-').firstMatch(href)?[1] ?? '') ??
                int.tryParse(uri?.queryParameters['fid'] ?? '');
        if (fid == null || fid <= 0 || !seen.add(fid)) continue;
        final deletion = item.querySelector('a[href*="favid="]');
        final favid = int.tryParse(
                Uri.tryParse(deletion?.attributes['href'] ?? '')
                        ?.queryParameters['favid'] ??
                    '') ??
            int.tryParse(item
                    .querySelector('input[name="favorite[]"]')
                    ?.attributes['value'] ??
                '') ??
            int.tryParse(RegExp(r'^fav_(\d+)$')
                    .firstMatch(item.attributes['id'] ?? '')?[1] ??
                '');
        final name = link.text.trim();
        if (name.isEmpty) continue;
        result.add(Forum(
            fid: fid,
            name: name,
            favid: favid,
            description:
                item.querySelector('.description, p.xg1')?.text.trim()));
      }
    }
    // 下一页只能来自收藏页分页，不能将帖子链接里的 page 误当列表分页。
    int? nextPage;
    for (final link in doc.querySelectorAll(
        '.pg a.nxt, .comiis_pgs a, .comiis_page a, .comiis_pg a')) {
      final uri = Uri.tryParse(link.attributes['href'] ?? '');
      if (uri?.queryParameters['do'] != 'favorite' ||
          uri?.queryParameters['type'] != 'forum') {
        continue;
      }
      if (link.classes.contains('nxt') ||
          link.text.contains('下一页') ||
          link.text.trim() == '下页') {
        nextPage = int.tryParse(uri!.queryParameters['page'] ?? '');
        break;
      }
    }
    final empty = roots.any((root) =>
        root.querySelector('.comiis_notip, .emp') != null ||
        RegExp(r'暂无收藏|没有收藏|没有.*收藏|no_favorite_yet').hasMatch(root.text));
    return DiscuzForumFavoritesPage(
        result.isNotEmpty || empty, result, nextPage);
  }
}
