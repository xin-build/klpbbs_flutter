import 'package:flutter/material.dart';

import 'app_config.dart';
import 'dio_client.dart';

/// 写操作前置检查与风险确认
///
/// 返回 true 表示可以执行写操作；false 表示取消（未登录/未确认）。
/// - 未登录：提示先登录
/// - 真实论坛（klpbbs）：弹风险确认框（写操作可能触发风控导致禁言/警告）
/// - 本地测试：直接放行
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
  if (AppConfig.needRealWriteConfirm) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('风险确认'),
        content: Text(
          '即将在真实论坛（klpbbs）执行「$action」。\n\n'
          '论坛管理机制严格，该操作可能导致账号被禁言/警告。\n'
          '是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认执行'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
  return true;
}
