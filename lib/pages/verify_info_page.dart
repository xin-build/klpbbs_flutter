import 'package:flutter/material.dart';
import '../models/user_space.dart';
import 'func_list_page.dart';

/// 认证类型、申请表和当前审核状态由论坛配置决定。
class VerifyInfoPage extends StatelessWidget {
  final UserSpace? userSpace;
  const VerifyInfoPage({super.key, this.userSpace});

  @override
  Widget build(BuildContext context) => const FuncListPage(
        title: '认证信息',
        path: 'home.php?mod=spacecp&ac=profile&op=verify&mobile=no',
      );
}
