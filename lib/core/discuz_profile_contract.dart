import 'discuz_form.dart';
import 'discuz_request_policy.dart';

/// 资料分类、提交地址和生日校验共用网页表单，不猜测缺失字段。
class DiscuzProfileContract {
  DiscuzProfileContract._();

  static bool matches(Uri page, Uri responseUri, DiscuzForm form, String op) {
    if (!const {'base', 'contact', 'info'}.contains(op) ||
        form.method != 'post') {
      return false;
    }
    bool expected(Uri uri) =>
        DiscuzRequestPolicy.sameOrigin(page, uri) &&
        page.path.endsWith('/home.php') &&
        uri.path == page.path &&
        uri.queryParameters['mod'] == 'spacecp' &&
        uri.queryParameters['ac'] == 'profile' &&
        (uri.queryParameters['op'] ?? 'base') == op;
    final hiddenOp = form.values['op'];
    return expected(page) &&
        expected(responseUri) &&
        expected(page.resolve(form.action)) &&
        (hiddenOp == null || hiddenOp.isEmpty || hiddenOp == op);
  }

  static Map<String, String>? merge(
      DiscuzForm form, Map<String, String> edits) {
    final merged = form.mergeEdits(edits);
    if (merged == null) return null;
    if (!edits.keys
        .any(const {'birthyear', 'birthmonth', 'birthday'}.contains)) {
      return merged;
    }

    int? number(String key, int maximum) {
      final value = merged[key] ?? '0';
      if (value.isEmpty && form.allowedValues[key]?.contains('') == true) {
        return 0;
      }
      if (!RegExp(r'^\d{1,4}$').hasMatch(value)) return null;
      final parsed = int.tryParse(value);
      return parsed != null && parsed <= maximum ? parsed : null;
    }

    final year = number('birthyear', 9999);
    final month = number('birthmonth', 12);
    final day = number('birthday', 31);
    if (year == null || month == null || day == null) return null;
    if (month != 0 && day != 0) {
      // 未填写年份时允许 2 月 29 日；填写年份后按真实闰年校验。
      final days = DateTime(year == 0 ? 2000 : year, month + 1, 0).day;
      if (day > days) return null;
    }
    return merged;
  }
}
