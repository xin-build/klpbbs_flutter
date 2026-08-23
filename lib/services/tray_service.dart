import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_config.dart';
import 'push_notification_service.dart';
import 'rgb_theme_service.dart';

/// 苦力怕论坛 桌面托盘与后台挂起守护服务
class TrayService with TrayListener, WindowListener {
  static final TrayService instance = TrayService._();
  TrayService._();

  bool _initialized = false;
  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> init() async {
    if (!isSupported || _initialized) return;
    _initialized = true;

    try {
      await windowManager.ensureInitialized();
      trayManager.addListener(this);
      windowManager.addListener(this);

      // 设置窗口关闭时拦截（挂起后台到托盘）
      await windowManager.setPreventClose(true);

      // 设置托盘图标与提示
      await _updateTray();

      // 监听未读消息变化自动刷新托盘菜单
      PushNotificationService.instance.addListener(() {
        _updateTray();
      });
    } catch (_) {}
  }

  Future<void> _updateTray() async {
    if (!isSupported) return;
    try {
      // 优先设置 Windows .ico 托盘图标，若失败则回退到 .png
      try {
        if (Platform.isWindows) {
          try {
            await trayManager.setIcon('assets/app_icon.ico');
          } catch (_) {
            await trayManager.setIcon('assets/icon.png');
          }
        } else {
          await trayManager.setIcon('assets/icon.png');
        }
      } catch (_) {}

      final unread = PushNotificationService.instance.unreadCount;
      final tooltip = unread > 0
          ? '苦力怕论坛 ($unread 条未读消息)'
          : '苦力怕论坛 - 点击显示';
      await trayManager.setToolTip(tooltip);

      final menu = Menu(
        items: [
          MenuItem(
            key: 'show_window',
            label: '显示苦力怕论坛',
          ),
          if (unread > 0) ...[
            MenuItem(
              key: 'unread_notice',
              label: '🔔 未读消息: $unread 条',
            ),
          ],
          MenuItem.separator(),
          MenuItem(
            key: 'check_messages',
            label: '立即检查新消息',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit_app',
            label: '退出客户端',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (_) {}
  }

  Future<void> showWindow() async {
    if (!isSupported) return;
    try {
      final isMin = await windowManager.isMinimized();
      if (isMin) {
        await windowManager.restore();
      }
      final isVisible = await windowManager.isVisible();
      if (!isVisible) {
        await windowManager.show();
      }
      await windowManager.focus();
    } catch (_) {}
  }

  Future<void> hideToTray() async {
    if (!isSupported) return;
    try {
      await windowManager.hide();
    } catch (_) {}
  }

  Future<void> exitApp() async {
    if (!isSupported) {
      exit(0);
    }
    try {
      // 1. 立即销毁系统托盘图标，避免系统托盘残留僵尸图标
      try {
        await trayManager.destroy();
      } catch (_) {}

      // 2. 停止后台轮询服务
      PushNotificationService.instance.dispose();

      // 3. 解除关闭阻止并销毁窗口
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
      case 'unread_notice':
        showWindow();
        if (menuItem.key == 'unread_notice') {
          PushNotificationService.instance.onOpenNoticeCallback?.call();
        }
        break;
      case 'check_messages':
        PushNotificationService.instance.checkNewMessages();
        break;
      case 'exit_app':
        exitApp();
        break;
    }
  }

  @override
  void onWindowClose() async {
    if (!isSupported) return;
    if (AppConfig.minimizeToTrayOnClose) {
      await hideToTray();
    } else {
      await exitApp();
    }
  }

  @override
  void onWindowMinimize() {
    RgbThemeService.instance.pause();
  }

  @override
  void onWindowRestore() {
    RgbThemeService.instance.resume();
  }
}
