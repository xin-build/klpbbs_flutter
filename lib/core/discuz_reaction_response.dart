import 'package:html/parser.dart' as html;
import 'discuz_response.dart';

/// 主题推荐与楼层投票使用不同接口；重复投票不能自动触发取消。
class DiscuzReactionResponse {
  static ({bool success, String message, bool isLiked}) parse(String response,
      {required bool support, required bool floor}) {
    final message = DiscuzResponse.message(response)?.trim() ?? '';
    final alreadyLiked = support &&
        (floor ? message.contains('已经对此回帖投过票') : message.contains('已评价过本主题'));
    final payload =
        RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(response)?.group(1) ??
            response;
    final doc = html.parse(payload);
    // 原生 recommend_succeed 返回「评价指数」及两个数字节点，并无「成功」字样。
    final nativeRecommendation = support &&
        !floor &&
        message.startsWith('评价指数') &&
        doc.querySelector('#messagetext #recommentc') != null &&
        doc.querySelector('#messagetext #recommentv') != null &&
        DiscuzResponse.isSuccess(response, acceptedMessages: const ['评价指数']);
    // 克米取消接口在完成数据库删除后 showmessage('ok')。
    final confirmedCancel = !support &&
        (message == 'ok' || response.trim() == 'ok') &&
        DiscuzResponse.isSuccess(response, acceptedMessages: const ['ok']);
    final success = alreadyLiked ||
        nativeRecommendation ||
        confirmedCancel ||
        DiscuzResponse.isSuccess(response);
    return (
      success: success,
      message: message.isNotEmpty
          ? (confirmedCancel ? '已取消点赞' : message)
          : (success ? (support ? '点赞成功' : '已取消点赞') : '服务器未确认点赞操作，请刷新后核对'),
      isLiked: success ? support : !support,
    );
  }
}
