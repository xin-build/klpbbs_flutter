import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'discuz_response.dart';

/// sunju_facemall 当前网页和内联脚本提供的数据。
class KlpFacemallCatalog {
  final String? myFaceUrl;
  final String? userAvatarUrl;
  final String? formhash;
  final List<(int, String)> categories;
  final int? selectedCategory;
  final List<Map<String, dynamic>> initialItems;
  final int? minimumDays;
  final List<int> dayOptions;
  final int? userIronPoints;

  const KlpFacemallCatalog(
      {required this.myFaceUrl,
      required this.userAvatarUrl,
      required this.formhash,
      required this.categories,
      required this.selectedCategory,
      required this.initialItems,
      required this.minimumDays,
      required this.dayOptions,
      required this.userIronPoints});

  static KlpFacemallCatalog parse(String source, Uri base, {String? formhash}) {
    final doc = html.parse(source);
    if (doc.querySelector('#sj_fm_catelist') == null ||
        doc.querySelector('#sj_fm_facelist') == null) {
      throw StateError(DiscuzResponse.message(source) ?? '网站未返回头像挂件商城');
    }
    final categories = <(int, String)>[];
    int? selected;
    for (final node in doc.querySelectorAll('#sj_fm_catelist [data-id]')) {
      final id = int.tryParse(node.attributes['data-id'] ?? '');
      final name = node.text.trim();
      if (id == null ||
          id <= 0 ||
          name.isEmpty ||
          categories.any((c) => c.$1 == id)) {
        continue;
      }
      categories.add((id, name));
      if (node.classes.contains('cur')) selected = id;
    }
    final items = <Map<String, dynamic>>[];
    for (final node in doc
        .querySelectorAll('#sj_fm_facelist .sj_fm_facelist_wp[data-id]')) {
      final id = node.attributes['data-id'] ?? '';
      final title =
          node.querySelector('.sj_fm_facelist_title')?.text.trim() ?? '';
      if ((int.tryParse(id) ?? 0) <= 0 || title.isEmpty) continue;
      final image = node.querySelector('img[data="pendant"]');
      items.add({
        'id': id,
        'title': title,
        'img': KlpFacemallResponse.frameUrl(
                image?.attributes['src'] ?? image?.attributes['data-src'],
                base) ??
            '',
        'price': node.attributes['data-price'] ?? ''
      });
    }
    final drop = doc.querySelector('#sj_fm_drop');
    final hasFrame =
        drop != null && !drop.classes.any((c) => c.endsWith('drop_not'));
    final avatar = doc
        .querySelector('#sj_fm_myface .sj_fm_myface_face')
        ?.attributes['src'];
    final frame = doc
        .querySelector('#sj_fm_myface .sj_fm_myface_mall')
        ?.attributes['src'];
    final dayOptions = doc
        .querySelectorAll('#sj_fm_open .sj_fm_price_box_sel li[data-id]')
        .map((node) => int.tryParse(node.attributes['data-id'] ?? '') ?? 0)
        .where((day) => day > 0)
        .toSet()
        .toList();
    int? setting(String name) => int.tryParse(
        RegExp('\\b$name\\s*=\\s*(\\d+)').firstMatch(source)?.group(1) ?? '');
    return KlpFacemallCatalog(
        myFaceUrl: hasFrame ? KlpFacemallResponse.frameUrl(frame, base) : null,
        userAvatarUrl: avatar == null ? null : base.resolve(avatar).toString(),
        formhash: formhash,
        categories: categories,
        selectedCategory: selected,
        initialItems: items,
        minimumDays: setting('SJ_MIN'),
        dayOptions: dayOptions,
        userIronPoints: setting('SJ_HAS'));
  }
}

class KlpFacemallResponse {
  /// Current PC and mobile templates omit the equip action for use 1/2/3.
  /// Preserve that contract without guessing the meaning of disabled states.
  static bool canEquip(Map<String, dynamic> item) =>
      !const {'1', '2', '3'}.contains(item['use']?.toString()) &&
      (int.tryParse(item['s_fid']?.toString() ?? '') ?? 0) > 0;

  /// 网站实际使用 data.code > 0；激活记录使用 layui 的 code == 0。
  static bool succeeded(Map<String, dynamic> data) {
    final code = num.tryParse('${data['code']}');
    return code != null && code.isFinite && code > 0;
  }

  static Map<String, dynamic> decode(String source) {
    try {
      final value = jsonDecode(source);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // HTML 登录页、权限页和超时页不能作为插件成功响应。
    }
    throw StateError(DiscuzResponse.message(source) ?? '网站未返回挂件操作结果，请刷新查看');
  }

  static String? frameUrl(String? source, Uri base) {
    if (source == null) return null;
    final value = source.contains('##SJ##')
        ? source.split('##SJ##').last.trim()
        : source.trim();
    if (value.isEmpty ||
        value.contains('{') ||
        value.contains('}') ||
        value.contains(r'$')) {
      return null;
    }
    final Uri uri;
    try {
      uri = base.resolve(value);
    } on FormatException {
      return null;
    }
    if (!const {'http', 'https'}.contains(uri.scheme)) return null;
    final path = uri.path.toLowerCase();
    if (path.contains('/avatar/') ||
        path.contains('_avatar_') ||
        path.contains('noavatar') ||
        path.endsWith('avatar.php')) {
      return null;
    }
    if (!RegExp(r'\.(?:png|gif|webp|apng)$').hasMatch(path)) return null;
    return uri.toString();
  }

  static List<Map<String, dynamic>> items(Map<String, dynamic> data, Uri base) {
    if (!succeeded(data) || data['data'] is! List) {
      throw StateError(data['msg']?.toString() ?? '无法取得挂件列表');
    }
    final items = <Map<String, dynamic>>[];
    for (final item in data['data'] as List) {
      if (item is! Map ||
          (int.tryParse('${item['id']}') ?? 0) <= 0 ||
          (item['s_title']?.toString().trim() ?? '').isEmpty) {
        // A malformed response must not turn into an apparently empty category
        // or expose a purchase button with an undeclared item identifier.
        throw StateError('论坛返回的挂件列表不完整，请刷新商城');
      }
      items.add(<String, dynamic>{
        'id': item['id'].toString(),
        'title': item['s_title'].toString().trim(),
        'img': frameUrl(item['s_img']?.toString(), base) ?? '',
        'price': item['s_price']?.toString() ?? '',
      });
    }
    return items;
  }
}

/// The current layui record endpoint uses code == 0 and a total count, unlike
/// facelist/mylist. Keep pagination metadata rather than guessing from rows.
class FacemallPayListPage {
  final int page, limit;
  final int? totalCount;
  final List<Map<String, dynamic>> items;
  const FacemallPayListPage({
    required this.page,
    required this.limit,
    required this.totalCount,
    required this.items,
  });

  bool get hasPrevious => page > 1;
  bool get hasNext =>
      totalCount == null ? items.length >= limit : page * limit < totalCount!;

  static FacemallPayListPage parse(Map<String, dynamic> data, Uri base,
      {required int page, int limit = 20}) {
    final code = num.tryParse('${data['code']}');
    final count =
        data['count'] == null ? null : int.tryParse(data['count'].toString());
    if (page < 1 || limit < 1 || limit > 100) {
      throw const FormatException('挂件记录分页参数无效');
    }
    if (code == null || !code.isFinite || code != 0 || data['data'] is! List) {
      throw StateError(data['msg']?.toString() ?? '无法取得挂件激活记录');
    }
    if (data['count'] != null && (count == null || count < 0)) {
      throw StateError('论坛返回的挂件记录总数无效，请刷新查看');
    }
    final items = <Map<String, dynamic>>[];
    for (final item in data['data'] as List) {
      if (item is! Map) {
        throw StateError('论坛返回的挂件记录不完整，请刷新查看');
      }
      final pendant = item['s_fid'] is Map ? item['s_fid'] as Map : item;
      items.add(<String, dynamic>{
        'id': item['id']?.toString() ?? '',
        'title': pendant['s_title']?.toString() ?? '',
        'img':
            KlpFacemallResponse.frameUrl(pendant['s_img']?.toString(), base) ??
                '',
        'day': item['s_payday']?.toString() ?? '',
        'price': item['s_prop']?.toString() ?? '',
        'time': item['s_paytime']?.toString() ?? '',
      });
    }
    return FacemallPayListPage(
        page: page, limit: limit, totalCount: count, items: items);
  }
}
