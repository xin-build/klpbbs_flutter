import 'package:html/parser.dart' as html;

import 'discuz_response.dart';

typedef DiscuzSignResult = ({
  bool success,
  String message,
  String? rewardIron,
  String? rewardExp,
  int? rank,
  int? continuousDays,
});

extension DiscuzSignResultState on DiscuzSignResult {
  // 此文字只由协议解析和服务端状态核验产生，普通失败消息不能靠子串通过。
  bool get alreadySigned =>
      !success &&
      const {
        '今日已签到，无需重复签到',
        '今日已签到',
      }.contains(message);
  bool get confirmed => success || alreadySigned;
}

enum DiscuzSignStatus { success, alreadySigned, rejected, unknown }

class DiscuzSignResponse {
  final DiscuzSignStatus status;
  final String message;
  final String? rewardIron;
  final String? rewardExp;
  final int? rank;
  final int? continuousDays;

  const DiscuzSignResponse(
    this.status,
    this.message, {
    this.rewardIron,
    this.rewardExp,
    this.rank,
    this.continuousDays,
  });

  static DiscuzSignResponse parse(String source) {
    final payload =
        RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source)?[1] ?? source;
    final doc = html.parse(payload);
    doc.querySelectorAll('script, style').forEach((node) => node.remove());
    final error = doc.querySelector('.alert_error');
    final alert =
        doc.querySelector('#messagetext p, .alert_info, .alert_right');
    final receipt = doc.querySelector('#JD_win, .signsuccess');
    final receiptVisible = receipt != null &&
        !RegExp(r'display\s*:\s*none', caseSensitive: false)
            .hasMatch(receipt.attributes['style'] ?? '');
    final message = (error?.text ??
            alert?.text ??
            (receiptVisible ? receipt.text : null) ??
            DiscuzResponse.message(payload) ??
            doc.body?.text ??
            '')
        .trim();
    final text = (doc.body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final already = RegExp(
            r'^(?:抱歉[，,。]?\s*)?(?:(?:您)?(?:今天|今日)(?:已经|已)(?:签过到(?:了)?|签到(?:了)?|签过(?:了)?|签)|请勿重复签到|k_misign:tdyq)[！!。]?$')
        .hasMatch(message);
    final signedButton = doc.querySelector('#JD_sign.visted, .btnvisted');
    final fresh = error == null &&
        (receiptVisible &&
                RegExp(r'^(?:恭喜您)?签到成功[！!]?$', caseSensitive: false)
                    .hasMatch(receipt.querySelector('h3')?.text.trim() ?? '') ||
            alert != null && RegExp(r'^(?:恭喜[^。]*?)?签到成功').hasMatch(message) ||
            !payload.contains('<') &&
                RegExp(r'^(?:恭喜您)?签到成功').hasMatch(message));
    final state = fresh
        ? DiscuzSignStatus.success
        : already || signedButton != null && error == null
            ? DiscuzSignStatus.alreadySigned
            : error != null
                ? DiscuzSignStatus.rejected
                : DiscuzSignStatus.unknown;
    final rewardText = receiptVisible ? receipt.text : message;
    final confirmed = state == DiscuzSignStatus.success ||
        state == DiscuzSignStatus.alreadySigned;
    final iron = confirmed
        ? RegExp(r'(?:获得|奖励|\+)?\s*(\d+)\s*(?:粒)?铁粒')
            .firstMatch(rewardText)
            ?.group(1)
        : null;
    final exp = confirmed
        ? RegExp(r'(?:获得|奖励|\+)?\s*(\d+)\s*(?:点|EP)?经验')
            .firstMatch(rewardText)
            ?.group(1)
        : null;
    final rank = int.tryParse(
        doc.querySelector('#qiandaobtnnum')?.attributes['value'] ??
            RegExp(r'(?:今日第|第)\s*(\d+)\s*(?:名|位|个签到)').firstMatch(text)?[1] ??
            '');
    final days = int.tryParse(
        doc.querySelector('#lxdays')?.attributes['value'] ??
            RegExp(r'(?:连续签到|已连续|连签)\s*(\d+)\s*天').firstMatch(text)?[1] ??
            '');
    return DiscuzSignResponse(
        state,
        switch (state) {
          DiscuzSignStatus.success =>
            rank == null ? '签到成功' : '签到成功（今日第 $rank 名）',
          DiscuzSignStatus.alreadySigned => '今日已签到，无需重复签到',
          DiscuzSignStatus.rejected => message,
          DiscuzSignStatus.unknown => '尚未取得可确认的签到结果，请刷新状态',
        },
        rewardIron: iron,
        rewardExp: exp,
        rank: confirmed ? rank : null,
        continuousDays: confirmed ? days : null);
  }
}
