import 'package:html/parser.dart' as html;
import '../models/user_role.dart';
import 'discuz_session_parser.dart';

class DiscuzRoleParser {
  static DiscuzUserRole parseOwnProfile(String source, int expectedUid) {
    final session = DiscuzSessionParser.parse(source);
    if (expectedUid <= 0 || session.uid != expectedUid) {
      return const DiscuzUserRole();
    }
    final doc = html.parse(source);
    final profile = doc.querySelector('#ct .u_profile, #ct .bm_c');
    if (profile == null) return DiscuzUserRole(uid: expectedUid);
    final identityText = doc.querySelector('#uhd .klp-uhead-meta')?.text ??
        profile.querySelector('h2')?.text ?? '';
    final identity = RegExp(r'UID\s*[:：]?\s*(\d+)', caseSensitive: false)
        .firstMatch(identityText);
    // 网页导航中的登录 UID 和正文里的被查看 UID 必须都匹配本人。
    if (int.tryParse(identity?.group(1) ?? '') != expectedUid) {
      return DiscuzUserRole(uid: expectedUid);
    }
    var groupId = 0;
    var adminId = 0;
    var groupTitle = '';
    for (final link in profile.querySelectorAll('.klp-profile-groups a[href*="ac=usergroup"]')) {
      final match = RegExp(r'^(用户组|管理组)\s*·\s*(.+)$').firstMatch(link.text.trim());
      if (match == null) continue;
      final gid = int.tryParse(Uri.tryParse(link.attributes['href'] ?? '')?.queryParameters['gid'] ?? '') ?? 0;
      if (match.group(1) == '用户组') {
        groupId = gid;
        groupTitle = match.group(2)!.trim();
      } else if (const {1, 2, 3}.contains(gid)) {
        adminId = gid;
      }
    }
    for (final item in profile.querySelectorAll('li')) {
      final label =
          item.querySelector('em')?.text.replaceAll(RegExp(r'\s+'), '') ?? '';
      if (label != '用户组' && label != '管理组') continue;
      final link = item.querySelector('a[href*="ac=usergroup"]');
      final uri = Uri.tryParse(link?.attributes['href'] ?? '');
      final gid = int.tryParse(uri?.queryParameters['gid'] ?? '') ?? 0;
      if (label == '用户组') {
        groupId = gid;
        groupTitle = link?.text.trim() ?? '';
      } else if (const {1, 2, 3}.contains(gid)) {
        adminId = gid;
      }
    }
    // 标准系统管理组 ID 是 Discuz 的固定协议；自定义组名称不能授予管理权。
    if (adminId == 0 && const {1, 2, 3}.contains(groupId)) adminId = groupId;
    final fids = <int>{};
    for (final heading in doc.querySelectorAll('#ct h2')) {
      if (heading.text.trim() != '管理以下版块') continue;
      var section = heading.parent;
      while (section?.parent != null && section?.localName != 'section' && section?.parent?.id != 'ct') {
        section = section!.parent;
      }
      // 旧版标题与版块链接是同级；新版标题包在 k-card-h 内。
      if (section?.localName != 'section') section = heading.parent;
      for (final link in section?.querySelectorAll('a[href]') ?? []) {
        final href = link.attributes['href'] ?? '';
        final uri = Uri.tryParse(href);
        final fid = int.tryParse(uri?.queryParameters['fid'] ?? '') ??
            int.tryParse(
                RegExp(r'forum-(\d+)-').firstMatch(href)?.group(1) ?? '');
        if (fid != null && fid > 0) fids.add(fid);
      }
    }
    return DiscuzUserRole(
      uid: expectedUid,
      username: session.username ?? doc.querySelector('#uhd .klp-uhead-name')?.text.trim() ?? '',
      groupId: groupId,
      adminId: adminId,
      groupTitle: groupTitle,
      isAdmin: adminId == 1,
      isSuperMod: adminId == 2,
      isModerator: adminId == 3 || fids.isNotEmpty,
      moderatedFids: fids.toList(),
      isMuted: groupId == 4,
      isBanned: groupId == 5 || groupId == 6,
    );
  }
}
