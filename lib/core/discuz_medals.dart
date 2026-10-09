import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import '../models/medal_item.dart';
import 'discuz_form.dart';

class DiscuzMedalConfirmation {
  final int medalId;
  final String terms;
  final DiscuzForm form;
  final String session;
  const DiscuzMedalConfirmation(
      this.medalId, this.terms, this.form, this.session);
}

/// 新版 PC 勋章卡片不总是给出 ID；按服务器返回的图片对应手机页 ID。
class DiscuzMedals {
  static bool recognized(String source) {
    final doc = html.parse(source);
    return doc.querySelector(
            '.klp-mdl-grid, ul.mgcl, .comiis_medal_box, .comiis_medalbox, div.medal_list') !=
        null;
  }

  static List<MedalItem> parse(String source, Uri base) {
    final doc = html.parse(source);
    final result = <MedalItem>[];
    final seen = <String>{};
    final elements = doc.querySelectorAll(
        '.klp-mdl-grid > .klp-mdl, ul.mgcl > li, .comiis_medal_box ul > li, .comiis_medalbox ul > li, div.medal_list li');
    for (final item in elements) {
      final image = item.querySelector(
              '.klp-mdl-ic img, .mg_img img, .medal_img img, .list02_limg img') ??
          item.querySelector('img');
      if (image == null) continue;
      final raw = image.attributes['comiis_loadimages'] ??
          image.attributes['data-src'] ??
          image.attributes['file'] ??
          image.attributes['src'] ??
          '';
      final rawUri = Uri.tryParse(raw);
      if (rawUri == null || raw.isEmpty) continue;
      final resolvedImage = base.resolveUri(rawUri);
      if (!const {'http', 'https'}.contains(resolvedImage.scheme)) continue;
      final imagePath = resolvedImage.path.toLowerCase();
      // The mobile medal panel also contains broadcast rows. Their user
      // avatars are not medals, even when the enclosing list has this class.
      if (imagePath.endsWith('/avatar.php') ||
          imagePath.contains('/uc_server/') && imagePath.contains('/avatar/') ||
          item.querySelector('.comiis_tuhao, .comiis_horn, .horn-banner') !=
              null) {
        continue;
      }
      final imageUrl =
          base.resolve(raw.replaceAll(RegExp(r'(?<!:)//+'), '/')).toString();
      final title = item
              .querySelector('.klp-mdl-name, p.xw1, p.tit, .medal_mytit')
              ?.text
              .trim() ??
          image.attributes['alt'] ??
          '';
      if (raw.isEmpty || title.isEmpty || !seen.add(imageUrl)) continue;
      final action = item
          .querySelector('a[href*="action=confirm"], a[href*="action=apply"]');
      final idNode = item.querySelector('[id^="medal_"]');
      final id = int.tryParse(RegExp(r'^medal_(\d+)$')
                  .firstMatch(idNode?.attributes['id'] ?? '')?[1] ??
              '') ??
          int.tryParse(Uri.tryParse(action?.attributes['href'] ?? '')
                  ?.queryParameters['medalid'] ??
              '') ??
          0;
      final tip = item.querySelector('.klp-mdl-tip') ??
          doc.querySelector('#medal_${id}_menu .tip_c');
      var description = tip?.querySelector('p')?.text.trim() ??
          item.querySelector('p.txt, .desc')?.text.trim() ??
          '';
      var terms = tip?.querySelector('.klp-mdl-tip-f')?.text ?? '';
      if (terms.trim().isEmpty && tip != null) {
        final paragraphs = tip.querySelectorAll('p');
        if (paragraphs.length > 1) terms = paragraphs[1].text;
      }
      if (terms.trim().isEmpty) {
        // 克米把条件放在 popup.open() 字符串里；读取 HTML 内容而非猜价格。
        for (final link in item.querySelectorAll('[onclick]')) {
          final script = link.attributes['onclick'] ?? '';
          final popup = RegExp(r"popup\.open\('([\s\S]*?)',\s*'alerts'")
              .firstMatch(script);
          if (popup == null) continue;
          final inner = html.parse(popup[1]!.replaceAll(r"\'", "'"));
          description =
              inner.querySelector('.kmtxt')?.text.trim() ?? description;
          terms = inner.querySelector('.mtn')?.text ?? '';
          if (terms.isNotEmpty) break;
        }
      }
      final status =
          item.querySelector('.klp-mdl-st, p.ybtn, .ybtn')?.text.trim() ?? '';
      final kind = action?.text.trim() ?? status;
      if (terms.trim().isEmpty &&
          const ['人工授予', '自主申请', '自动发放'].contains(status)) {
        terms = status;
      }
      result.add(MedalItem(
          id: id,
          name: title,
          desc: description,
          requirement: _clean(terms),
          img: imageUrl,
          actionUrl: action?.attributes['href'] ?? '',
          status: status,
          actionLabel: kind));
    }
    return result;
  }

  static String _clean(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static List<MedalItem> merge(
      List<MedalItem> desktop, List<MedalItem> mobile) {
    if (desktop.isEmpty) return mobile;
    final byImage = {
      for (final medal in mobile) Uri.parse(medal.img).path: medal
    };
    final byName = {for (final medal in mobile) medal.name: medal};
    final merged = desktop.map((medal) {
      final other = byImage[Uri.parse(medal.img).path] ?? byName[medal.name];
      return MedalItem(
          id: medal.id > 0 ? medal.id : other?.id ?? 0,
          name: medal.name,
          desc: medal.desc.isNotEmpty ? medal.desc : other?.desc ?? '',
          img: medal.img,
          requirement: medal.requirement.isNotEmpty
              ? medal.requirement
              : other?.requirement ?? '',
          actionUrl: medal.actionUrl.isNotEmpty
              ? medal.actionUrl
              : other?.actionUrl ?? '',
          actionLabel: medal.actionLabel.isNotEmpty
              ? medal.actionLabel
              : other?.actionLabel ?? '',
          status: medal.status.isNotEmpty ? medal.status : other?.status ?? '');
    }).toList();
    for (final medal in mobile) {
      if (!merged.any((item) =>
          Uri.parse(item.img).path == Uri.parse(medal.img).path ||
          item.name == medal.name)) {
        merged.add(medal);
      }
    }
    return merged;
  }

  static String confirmationTerms(String source) {
    final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source);
    final doc = html.parse(cdata?[1] ?? source);
    final form = doc
        .querySelectorAll('form')
        .where(
            (element) => element.querySelector('[name="medalsubmit"]') != null)
        .firstOrNull;
    if (form == null) return '';
    final clone = form.clone(true);
    clone
        .querySelectorAll('script, style, input, button, textarea')
        .forEach((Element element) => element.remove());
    return _clean(clone.text);
  }
}
