import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'discuz_request_policy.dart';

enum MedalOrderFormat { orderedCsv, indexed }

class MedalOrderItem {
  final int id;
  final String name, img, desc;
  const MedalOrderItem(
      {required this.id, this.name = '', this.img = '', this.desc = ''});
}

/// KLPBBS's published order plugin uses li[data-id] and a hidden `ordered`
/// field, not Discuz's indexed order inputs. Values stay in the caller's RAM;
/// this object has no logging, serialization, session storage or write method.
class KlpbbsMedalOrder {
  final Uri pageUri, action;
  String get method => 'post';
  final bool recognized;
  final MedalOrderFormat? format;
  final Map<String, String> values;
  final List<MedalOrderItem> medals;
  final List<int> serverIds;
  const KlpbbsMedalOrder._({
    required this.pageUri,
    required this.action,
    this.recognized = false,
    this.format,
    this.values = const {},
    this.medals = const [],
    this.serverIds = const [],
  });

  /// Only a complete permutation of the fresh server list can be sent. The
  /// actual formhash, named submit value and other successful controls survive.
  Map<String, String>? mergeEdits(List<int> permutation) {
    if (!recognized ||
        format == null ||
        permutation.isEmpty ||
        permutation.any((id) => id <= 0) ||
        permutation.length != serverIds.length ||
        permutation.toSet().length != permutation.length ||
        !permutation.toSet().containsAll(serverIds)) {
      return null;
    }
    final result = <String, String>{...values};
    switch (format!) {
      case MedalOrderFormat.orderedCsv:
        // This matches the live sortupdate handler's data('id') comma join.
        result['ordered'] = permutation.join(',');
      case MedalOrderFormat.indexed:
        for (var position = 0; position < permutation.length; position++) {
          result['order[${permutation[position]}]'] = '$position';
        }
    }
    return result;
  }

  static bool _disabled(Element node) {
    Element? current = node;
    while (current != null) {
      if (current.attributes.containsKey('disabled')) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  static String _clean(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static MedalOrderItem _medal(int id, Element? item, Uri base) {
    final image = item?.querySelector('img');
    final raw = image?.attributes['src'] ?? '';
    final target =
        raw.isEmpty ? null : Uri.tryParse(base.resolve(raw).toString());
    final itemTitle = _clean(item?.attributes['title'] ?? '');
    final title =
        itemTitle.isNotEmpty ? itemTitle : image?.attributes['alt'] ?? '';
    return MedalOrderItem(
        id: id,
        name: _clean(title),
        img: target != null && const {'http', 'https'}.contains(target.scheme)
            ? target.toString()
            : '',
        desc: _clean(image?.attributes['title'] ?? ''));
  }

  static KlpbbsMedalOrder parse(String source, Uri pageUri) {
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source);
    final document = html.parse(cdata?[1] ?? source);
    final unavailable = KlpbbsMedalOrder._(pageUri: pageUri, action: pageUri);
    for (final form in document.querySelectorAll('form')) {
      if (_disabled(form) ||
          (form.attributes['method'] ?? 'get').toLowerCase() != 'post') {
        continue;
      }
      final action = pageUri.resolve(form.attributes['action'] ?? '');
      if (!const {'http', 'https'}.contains(action.scheme) ||
          !DiscuzRequestPolicy.sameOrigin(pageUri, action) ||
          action.userInfo.isNotEmpty) {
        continue;
      }
      final controls = form
          .querySelectorAll('input[name], button[name]')
          .where((node) => !_disabled(node))
          .toList();
      final values = <String, String>{};
      var ambiguous = false;
      final orders = <({int id, int position, Element input})>[];
      for (final control in controls) {
        final name = control.attributes['name']!;
        final type = (control.attributes['type'] ??
                (control.localName == 'button' ? 'submit' : 'text'))
            .toLowerCase();
        if (const {'button', 'reset', 'password', 'file', 'image'}
            .contains(type)) {
          continue;
        }
        if (const {'checkbox', 'radio'}.contains(type) &&
            !control.attributes.containsKey('checked')) {
          continue;
        }
        // Only the ordering operation's submit is clicked; unrelated submit
        // buttons are not successful browser controls.
        if (type == 'submit' && name != 'ordersubmit') {
          continue;
        }
        if (values.containsKey(name)) {
          ambiguous = true;
          break;
        }
        final value = control.attributes['value'] ?? '';
        values[name] = value;
        final match = RegExp(r'^order\[([1-9]\d*)\]$').firstMatch(name);
        if (name.startsWith('order[') && match == null) {
          ambiguous = true;
          break;
        }
        if (match != null) {
          final id = int.tryParse(match[1]!);
          final position = int.tryParse(value);
          if (id == null || position == null || position < 0) {
            ambiguous = true;
            break;
          }
          orders.add((id: id, position: position, input: control));
        }
      }
      if (ambiguous ||
          values['formhash']?.isNotEmpty != true ||
          !values.containsKey('ordersubmit')) {
        continue;
      }
      final orderedControls = controls
          .where((node) => node.attributes['name'] == 'ordered')
          .toList();
      if (orderedControls.isNotEmpty) {
        if (form.id != 'medalorder' ||
            orderedControls.length != 1 ||
            orderedControls.single.id != 'ordered' ||
            orderedControls.single.localName != 'input' ||
            orderedControls.single.attributes['type']?.toLowerCase() !=
                'hidden' ||
            !values.containsKey('ordered') ||
            orders.isNotEmpty) {
          continue;
        }
        final lists = form.querySelectorAll('ul.medal-list');
        if (lists.length != 1) {
          continue;
        }
        final items = lists.single.children
            .where((node) => node.localName == 'li')
            .toList();
        final medals = <MedalOrderItem>[];
        final ids = <int>{};
        var invalid = false;
        for (final item in items) {
          final raw = item.attributes['data-id'] ?? '';
          final id = int.tryParse(raw);
          if (id == null || id <= 0 || raw != '$id' || !ids.add(id)) {
            invalid = true;
            break;
          }
          medals.add(_medal(id, item, pageUri));
        }
        final initial = values['ordered']!;
        if (initial.isNotEmpty) {
          final initialIds = initial.split(',').map(int.tryParse).toList();
          if (!RegExp(r'^[1-9]\d*(?:,[1-9]\d*)*$').hasMatch(initial) ||
              initialIds.any((id) => id == null) ||
              initialIds.length != ids.length ||
              initialIds.toSet().length != ids.length ||
              !initialIds.toSet().containsAll(ids)) {
            invalid = true;
          }
        }
        if (invalid) {
          continue;
        }
        return KlpbbsMedalOrder._(
            pageUri: pageUri,
            action: action,
            recognized: true,
            format: MedalOrderFormat.orderedCsv,
            values: Map.unmodifiable(values),
            medals: List.unmodifiable(medals),
            serverIds: List.unmodifiable(medals.map((medal) => medal.id)));
      }
      if (orders.isNotEmpty) {
        if (orders.map((item) => item.id).toSet().length != orders.length) {
          continue;
        }
        // Stable ties preserve the actual source order, matching browser DOM.
        final sourceIndex = {
          for (var index = 0; index < orders.length; index++)
            orders[index].id: index
        };
        orders.sort((a, b) {
          final rank = a.position.compareTo(b.position);
          return rank == 0
              ? sourceIndex[a.id]!.compareTo(sourceIndex[b.id]!)
              : rank;
        });
        final medals = [
          for (final order in orders)
            _medal(order.id, form.querySelector('[data-id="${order.id}"]'),
                pageUri)
        ];
        return KlpbbsMedalOrder._(
            pageUri: pageUri,
            action: action,
            recognized: true,
            format: MedalOrderFormat.indexed,
            values: Map.unmodifiable(values),
            medals: List.unmodifiable(medals),
            serverIds: List.unmodifiable(medals.map((medal) => medal.id)));
      }
    }
    return unavailable;
  }
}
