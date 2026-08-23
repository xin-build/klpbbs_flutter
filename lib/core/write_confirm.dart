import 'package:flutter/material.dart';

import 'app_config.dart';
import 'dio_client.dart';

/// 写操作前置检查（已移除风控警告弹窗）
///
/// 返回 true 表示可以执行写操作；false 表示不可执行（未登录/环境受限）。
/// - 未登录：提示先登录
/// - 正常状态：直接放行
Future<bool> confirmWrite(BuildContext context, String action) async {
  if (!AppConfig.allowWrite) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('当前环境不允许写操作')));
    return false;
  }
  if (!DioClient.isLoggedIn) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('请先登录')));
    return false;
  }
  return true;
}
