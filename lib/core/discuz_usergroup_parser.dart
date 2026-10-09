import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import '../models/usergroup_comparison.dart';
import 'discuz_permission_cell.dart';

/// Discuz X3.4 的 tdats 由权限名称、本人和目标组三张平行表组成。
class DiscuzUsergroupParser {
  static UsergroupComparison parse(String source) {
    final doc = html.parse(source);
    final container = doc.querySelector('.tdats');
    if (container == null) throw const FormatException('服务器未返回用户组权限表，请检查登录状态');
    final labels = container.querySelector('table.tdat:not(.tfx):not(.tfxf)');
    final mine = container.querySelector('table.tfx, table.tfxf');
    final target = container.querySelector('.tscr table.tdat');
    if (labels == null || mine == null) {
      throw const FormatException('用户组权限表结构不完整');
    }
    final items = <UsergroupPermissionItem>[];
    const categories = {'ca': '基本权限', 'cb': '帖子相关', 'cc': '空间相关', 'cd': '附件相关'};
    for (final category in categories.entries) {
      final names = labels.querySelectorAll('tbody.${category.key} tr td');
      final myValues = mine.querySelectorAll('tbody.${category.key} tr td');
      final nextValues =
          target?.querySelectorAll('tbody.${category.key} tr td') ??
              <Element>[];
      // ca 的名称首行是用户星级，星级数值在正文外，不可使所有权限错一行。
      final offset =
          category.key == 'ca' && names.length == myValues.length + 1 ? 1 : 0;
      if (names.length - offset != myValues.length ||
          (target != null && nextValues.length != myValues.length)) {
        throw FormatException('${category.value}权限列未对齐');
      }
      if (myValues.isEmpty) continue;
      items.add(UsergroupPermissionItem(
          title: category.value, myValue: '', isCategoryHeader: true));
      if (offset == 1) {
        String rank(Element? table) =>
            RegExp(r'^Rank:\s*(\d+)$').firstMatch(
                table?.querySelector('img[alt^="Rank:"]')?.attributes['alt'] ??
                    '')?[1] ??
            '';
        items.add(UsergroupPermissionItem(
            title: names.first.text.trim(),
            myValue: rank(mine),
            nextValue: rank(target)));
      }
      for (var index = 0; index < myValues.length; index++) {
        items.add(UsergroupPermissionItem(
          title: names[index + offset].text.trim(),
          myValue: cellValue(myValues[index]),
          nextValue: target == null ? '' : cellValue(nextValues[index]),
        ));
      }
    }
    if (items.isEmpty) throw const FormatException('服务器未返回权限明细');
    String heading(Element? element, String fallback) {
      final value = element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
      return value.isEmpty ? fallback : value;
    }

    final groups = <KlpbbsUserGroupMeta>[];
    for (final category in const {
      'gupgrade_menu': '晋级用户组',
      'gadmin_menu': '站点管理组',
      'guser_menu': '普通用户组',
      'gmy_menu': '我的用户组'
    }.entries) {
      for (final link in doc.querySelectorAll('#${category.key} a[href]')) {
        final uri = Uri.tryParse(
            (link.attributes['href'] ?? '').replaceAll('&amp;', '&'));
        final gid = int.tryParse(uri?.queryParameters['gid'] ?? '');
        final name = link.text.trim();
        if (gid != null &&
            name.isNotEmpty &&
            !groups.any((group) => group.gid == gid)) {
          groups.add(KlpbbsUserGroupMeta(
              gid: gid, name: name, category: category.value));
        }
      }
    }
    return UsergroupComparison(
      myGroup: UsergroupColumn(
          title: heading(
              mine.querySelector('h4') ?? mine.querySelector('th.c0'),
              '我的主用户组'),
          subtitle: mine.querySelector('.notice')?.text.trim() ?? ''),
      upgradeGroup: target == null
          ? null
          : UsergroupColumn(
              title: heading(
                  container.querySelector('#tba li.a, #tba li.active') ??
                      container
                          .querySelector('#tba li[aria-selected="true"]') ??
                      container.querySelector('#tba li'),
                  '对比用户组'),
              subtitle: target.querySelector('.notice')?.text.trim() ?? ''),
      permissions: items,
      groups: groups,
    );
  }

  static String cellValue(Element cell) => DiscuzPermissionCell.text(cell);
}
