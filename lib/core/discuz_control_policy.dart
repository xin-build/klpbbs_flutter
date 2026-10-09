import 'package:html/dom.dart';

/// The native editor currently submits the form's own declared action/method.
/// Button overrides and externally associated controls require their own
/// contract, so they cannot be silently sent using the parent form's rules.
class DiscuzControlPolicy {
  static bool isDisabled(Element node) {
    for (Element? current = node; current != null; current = current.parent) {
      if (current.attributes.containsKey('disabled') &&
          (current == node ||
              const {'fieldset', 'optgroup'}.contains(current.localName))) {
        if (current != node && current.localName == 'fieldset') {
          final legends =
              current.children.where((e) => e.localName == 'legend');
          if (legends.isNotEmpty &&
              (legends.first == node ||
                  legends.first.querySelectorAll('*').contains(node))) {
            continue;
          }
        }
        return true;
      }
    }
    return false;
  }

  static bool hasUnsupportedSubmission(Element form, Document document) {
    final controls = form.querySelectorAll('input, select, textarea, button');
    for (final control in controls.where((node) => !isDisabled(node))) {
      if (control.attributes.containsKey('form') &&
          control.attributes['form'] != form.id) {
        return true;
      }
      if (const {'formaction', 'formmethod', 'formenctype'}
          .any(control.attributes.containsKey)) {
        return true;
      }
    }
    if (form.id.isNotEmpty &&
        document
            .querySelectorAll('[form]')
            .where((node) =>
                !isDisabled(node) && node.attributes['form'] == form.id)
            .any((node) => !controls.contains(node))) {
      return true;
    }
    return false;
  }
}
