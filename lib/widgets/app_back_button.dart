import 'package:flutter/material.dart';
import '../core/main_tab_controller.dart';

/// 统一移动端/全平台导航返回按钮
/// 1. 如果当前页面处于 Navigator 栈顶（canPop == true），点击返回上一级页面
/// 2. 如果当前页面是主底部导航 Tab（如签到、版块、勋章、个人中心），点击平滑切回「首页」
/// 3. 如果 fallbackToHome 为 false 且 canPop 为 false，则隐藏该按钮
class AppBackButton extends StatelessWidget {
  final bool fallbackToHome;
  final VoidCallback? onBack;
  final Color? color;

  const AppBackButton({
    super.key,
    this.fallbackToHome = true,
    this.onBack,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    if (!canPop && !fallbackToHome) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: canPop ? '返回' : '返回首页',
      color: color,
      onPressed: () {
        if (onBack != null) {
          onBack!();
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).maybePop();
        } else if (fallbackToHome) {
          mainTabIndex.value = 0;
        }
      },
    );
  }
}
