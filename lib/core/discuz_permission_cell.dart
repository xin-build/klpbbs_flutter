import 'package:html/dom.dart';

/// Discuz permission images encode a value, while their alt names are asset
/// identifiers. Preserve text/numeric limits and translate only declared flags.
class DiscuzPermissionCell {
  static String? imageValue(Element image) {
    final path = Uri.tryParse(image.attributes['src'] ?? '')?.path ?? '';
    final file = path.split('/').last.toLowerCase();
    final flag =
        RegExp(r'^(data_valid|data_invalid|yes|no)\.(gif|png|svg|webp)$')
            .firstMatch(file)?[1];
    return switch (flag) {
      'data_valid' || 'yes' => '✔',
      'data_invalid' || 'no' => '✖',
      _ => null,
    };
  }

  static String text(Element element) {
    final clone = element.clone(true);
    clone
        .querySelectorAll('script, style, input, select, textarea, button')
        .forEach((node) => node.remove());
    for (final image in clone.querySelectorAll('img')) {
      final flag = imageValue(image);
      final label =
          (image.attributes['alt'] ?? image.attributes['title'] ?? '').trim();
      image.replaceWith(Text(flag ?? label));
    }
    return clone.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
