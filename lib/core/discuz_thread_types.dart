import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'discuz_request_policy.dart';

typedef DiscuzThreadType = ({int typeid, String name});

/// A category menu describes the forum, not the current page of its feed.
/// KLPBBS removes href from the selected PC chip; the requested type identifies
/// that declared active chip. Counts and decorative icons are separate roles.
class DiscuzThreadTypes {
  static const _containers = '#thread_types, ul.ttp, div.ttp, #filter_type, '
      '.comiis_p_fl, ul.comiis_type, #thread_types_menu, .swiper-wrapper';

  static List<DiscuzThreadType> parse(String source, Uri base,
      {int? fid, int? selectedTypeid}) {
    final document = html.parse(source);
    final result = <DiscuzThreadType>[];
    for (final container in document.querySelectorAll(_containers)) {
      // Swiper also hosts banners. A category swiper must declare a forum
      // category link; a post/image carousel never becomes a category menu.
      if (container.classes.contains('swiper-wrapper') &&
          !container
              .querySelectorAll('a[href]')
              .any((link) => _typeFromLink(link, base, fid: fid) != null)) {
        continue;
      }
      for (final node in container.querySelectorAll('a, strong')) {
        var typeid = _typeFromLink(node, base, fid: fid);
        if (typeid == null &&
            (selectedTypeid ?? 0) > 0 &&
            _isActive(node) &&
            (node.attributes['href']?.trim().isEmpty ?? true)) {
          typeid = selectedTypeid;
        }
        if (typeid == null || typeid <= 0) continue;
        final name = _name(node);
        if (name.isEmpty || name == '全部' || name.length > 80) continue;
        if (!result.any((item) => item.typeid == typeid)) {
          result.add((typeid: typeid, name: name));
        }
      }
    }
    return List.unmodifiable(result);
  }

  static int? _typeFromLink(Element node, Uri base, {int? fid}) {
    final href = node.attributes['href']?.trim() ?? '';
    if (href.isEmpty || href.startsWith('#')) return null;
    final target = Uri.tryParse(href);
    if (target == null) return null;
    final uri = base.resolveUri(target), query = uri.queryParameters;
    if (!DiscuzRequestPolicy.sameOrigin(base, uri) ||
        uri.path.split('/').last != 'forum.php' ||
        query['mod'] != 'forumdisplay' ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        (fid != null && int.tryParse(query['fid'] ?? '') != fid)) {
      return null;
    }
    final typeid = int.tryParse(query['typeid'] ?? '');
    return typeid != null && typeid > 0 ? typeid : null;
  }

  static bool _isActive(Element node) =>
      node.localName == 'strong' ||
      node.attributes['aria-current'] == 'true' ||
      node.classes
          .any(const {'k-chip-acc', 'a', 'on', 'active', 'f_a'}.contains) ||
      (node.parent?.classes.any(const {'a', 'on', 'active'}.contains) ?? false);

  static String _name(Element node) {
    final clone = node.clone(true);
    clone
        .querySelectorAll('script, style, .klp-chip-n, .num, .xg1, '
            '.iconfont, .comiis_font, svg')
        .forEach((child) => child.remove());
    for (final count in clone.querySelectorAll('em, small')) {
      if (clone.text.trim() != count.text.trim() &&
          RegExp(r'^\s*[([]?\s*\d[\d,]*\s*[)\]]?\s*$').hasMatch(count.text)) {
        count.remove();
      }
    }
    return clone.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Updating a filtered feed cannot delete the forum's other categories.
  static List<DiscuzThreadType> merge(
      Iterable<DiscuzThreadType> previous, Iterable<DiscuzThreadType> current) {
    final byId = <int, DiscuzThreadType>{};
    for (final item in [...previous, ...current]) {
      if (item.typeid > 0 && item.name.isNotEmpty) byId[item.typeid] = item;
    }
    return List.unmodifiable(byId.values);
  }
}
