import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RefreshIntent extends Intent {
  const RefreshIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class NewPostIntent extends Intent {
  const NewPostIntent();
}

class EscapeIntent extends Intent {
  const EscapeIntent();
}

/// 桌面端全局与页面级快捷键包装组件 (F5, Ctrl+R, Ctrl+F, Ctrl+N, Escape)
class DesktopShortcutsWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback? onRefresh;
  final VoidCallback? onSearch;
  final VoidCallback? onNewPost;
  final VoidCallback? onEscape;

  const DesktopShortcutsWrapper({
    super.key,
    required this.child,
    this.onRefresh,
    this.onSearch,
    this.onNewPost,
    this.onEscape,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // F5 刷新
        const SingleActivator(LogicalKeyboardKey.f5): const RefreshIntent(),
        // Ctrl+R 刷新
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            const RefreshIntent(),
        // Ctrl+F 搜索
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const SearchIntent(),
        // Ctrl+N 新建发帖
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            const NewPostIntent(),
        // Escape 关闭/后退
        const SingleActivator(LogicalKeyboardKey.escape): const EscapeIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          RefreshIntent: CallbackAction<RefreshIntent>(
            onInvoke: (_) {
              onRefresh?.call();
              return null;
            },
          ),
          SearchIntent: CallbackAction<SearchIntent>(
            onInvoke: (_) {
              onSearch?.call();
              return null;
            },
          ),
          NewPostIntent: CallbackAction<NewPostIntent>(
            onInvoke: (_) {
              onNewPost?.call();
              return null;
            },
          ),
          EscapeIntent: CallbackAction<EscapeIntent>(
            onInvoke: (_) {
              if (onEscape != null) {
                onEscape!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: child,
        ),
      ),
    );
  }
}
