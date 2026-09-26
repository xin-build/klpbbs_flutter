import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/app_config.dart';
import '../widgets/visual_grid_canvas.dart';

/// 全自动截图验证服务（内部原生捕获，规避 Windows DirectX/Impeller GDI 黑屏限制）
class AutoTestScreenshotService {
  static final GlobalKey rootKey = GlobalKey();
  static bool _isRunning = false;

  static const String artifactDir =
      r'C:\Users\Administrator\.gemini\antigravity\brain\73d98d9c-d2df-4dc8-b72e-f0efcc07e6c5';

  static Timer? _pollingTimer;

  static void maybeTriggerTestingRoutine(GlobalKey<NavigatorState> navKey) async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    // 仅在明确存在标志位时触发，不保持高频 1s 轮询以彻底消除 CPU 与磁盘 IO 唤醒
    final flagFile = File('$artifactDir\\scratch\\run_screenshot_test.flag');
    if (!flagFile.existsSync()) return;
      if (_isRunning) return;
      _isRunning = true;
      try {
        flagFile.deleteSync();
      } catch (_) {}

      try {
        debugPrint('[AutoTestScreenshot] === 开始执行自动化截图自测 ===');

        // 1. 截取首页包含服务器状态监控卡片的完整视图（等待网络请求与动画就绪）
        await Future.delayed(const Duration(milliseconds: 2000));
        final p1 = '$artifactDir\\test_screen_home_dashboard.png';
        final s1 = await _captureAndSave(p1);
        debugPrint('[AutoTestScreenshot] 1. 首页截图: $s1 -> $p1');

        // 2. 打开并截取自由网格工作台 VisualGridCanvas (首页类别)
        final nav = navKey.currentState;
        if (nav != null && nav.mounted) {
          unawaited(
            nav.push(
              MaterialPageRoute(
                builder: (ctx) => VisualGridCanvas(
                  initialLayout: AppConfig.homeDashboardLayout,
                  pageCategory: 'home',
                  onExit: () => Navigator.of(ctx).pop(),
                  onSave: (items) {
                    AppConfig.homeDashboardLayout = items;
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 2500));
          final p2 = '$artifactDir\\test_screen_canvas_home.png';
          final s2 = await _captureAndSave(p2);
          debugPrint('[AutoTestScreenshot] 2. 画布工作台(首页)截图: $s2 -> $p2');

          // 返回首页
          if (nav.mounted && nav.canPop()) {
            nav.pop();
          }
          await Future.delayed(const Duration(milliseconds: 1000));

          // 3. 打开并截取自由网格工作台 VisualGridCanvas (帖子详情类别，含左侧边栏与帖子流)
          unawaited(
            nav.push(
              MaterialPageRoute(
                builder: (ctx) => VisualGridCanvas(
                  initialLayout: const [],
                  pageCategory: 'thread',
                  onExit: () => Navigator.of(ctx).pop(),
                  onSave: (items) {
                    AppConfig.threadRightModules = items.map((e) => e.cardType).toList();
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 2500));
          final p3 = '$artifactDir\\test_screen_canvas_thread.png';
          final s3 = await _captureAndSave(p3);
          debugPrint('[AutoTestScreenshot] 3. 画布工作台(帖子详情)截图: $s3 -> $p3');

          // 4. 打开并截取自由网格工作台 VisualGridCanvas (导读类别，只支持右侧工作台卡片与导读流)
          unawaited(
            nav.push(
              MaterialPageRoute(
                builder: (ctx) => VisualGridCanvas(
                  initialLayout: AppConfig.guideDashboardLayout,
                  pageCategory: 'guide',
                  onExit: () => Navigator.of(ctx).pop(),
                  onSave: (items) {
                    AppConfig.setGuideDashboardLayout(items);
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 2500));
          final p4 = '$artifactDir\\test_screen_canvas_guide.png';
          final s4 = await _captureAndSave(p4);
          debugPrint('[AutoTestScreenshot] 4. 画布工作台(导读)截图: $s4 -> $p4');

          // 返回首页
          if (nav.mounted && nav.canPop()) {
            nav.pop();
          }
          await Future.delayed(const Duration(milliseconds: 1000));
        }

        // 写入完成标识
        final doneFile = File('$artifactDir\\scratch\\screenshot_test_done.txt');
        await doneFile.writeAsString(
          'SUCCESS: Screenshots generated at ${DateTime.now().toIso8601String()}\n'
          '1: $artifactDir\\test_screen_home_dashboard.png\n'
          '2: $artifactDir\\test_screen_canvas_home.png\n'
          '3: $artifactDir\\test_screen_canvas_thread.png\n'
          '4: $artifactDir\\test_screen_canvas_guide.png\n',
        );
        debugPrint('[AutoTestScreenshot] === 自动化截图自测全部完成 ===');
      } catch (e, stack) {
        debugPrint('[AutoTestScreenshot] 截图流程发生异常: $e\n$stack');
        final errFile = File('$artifactDir\\scratch\\screenshot_test_error.txt');
        await errFile.writeAsString('ERROR: $e\n$stack');
      } finally {
        _isRunning = false;
      }
  }

  static Future<bool> _captureAndSave(String filePath) async {
    try {
      final boundary = rootKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('[AutoTestScreenshot] 无法获取 RenderRepaintBoundary');
        return false;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 1.25);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('[AutoTestScreenshot] 转换 PNG 失败: byteData 为空');
        return false;
      }
      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final file = File(filePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      await file.writeAsBytes(pngBytes, flush: true);
      return true;
    } catch (e) {
      debugPrint('[AutoTestScreenshot] 保存截图异常: $e');
      return false;
    }
  }
}
