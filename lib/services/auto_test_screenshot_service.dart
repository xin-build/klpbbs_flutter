import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

import '../core/main_tab_controller.dart';
import '../pages/credit_page.dart';
import '../pages/darkroom_page.dart';
import '../pages/favorite_hub_page.dart';
import '../pages/guide_page.dart';
import '../pages/magic_page.dart';
import '../pages/notice_page.dart';
import '../pages/pm_inbox_page.dart';
import '../pages/ranklist_page.dart';
import '../pages/search_page.dart';
import '../pages/sign_rank_page.dart';
import '../pages/task_page.dart';
import '../pages/thread_detail_page.dart';
import '../pages/user_space_page.dart';
import '../api/klpbbs_api.dart';
import '../core/preload_service.dart';
import '../models/user_space.dart';

/// 全自动多端截图验证服务（内部原生捕获，规避 Windows DirectX/Impeller GDI 黑屏限制）
/// 支持 PC 桌面端 (1280x800) 与移动端 (420x860) 视口自适应切换并捕获真实渲染效果
class AutoTestScreenshotService {
  static final GlobalKey rootKey = GlobalKey();
  static bool _isRunning = false;

  static const String artifactDir = String.fromEnvironment(
    'KLPBBS_UI_AUDIT_DIR', defaultValue: r'F:\klpbbs\capture\ui_audit');

  static Timer? _pollingTimer;

  static void maybeTriggerTestingRoutine(GlobalKey<NavigatorState> navKey) {
    if (!const bool.fromEnvironment('KLPBBS_ENABLE_UI_AUDIT') || !Platform.isWindows) return;
    startListening(navKey);
  }

  static bool _isBuilding = false;

  static void startListening(GlobalKey<NavigatorState> navKey) {
    if (!const bool.fromEnvironment('KLPBBS_ENABLE_UI_AUDIT') || !Platform.isWindows) return;
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      final flagFile = File('$artifactDir\\scratch\\run_screenshot_test.flag');
      if (flagFile.existsSync() && !_isRunning) {
        _runComprehensiveCapture(navKey);
      }
      final buildFlag = File('$artifactDir\\scratch\\run_build_windows.flag');
      if (buildFlag.existsSync() && !_isBuilding) {
        _runWindowsBuild();
      }
    });
  }

  static Future<void> _runWindowsBuild() async {
    final flagFile = File('$artifactDir\\scratch\\run_build_windows.flag');
    if (_isBuilding) return;
    _isBuilding = true;
    try {
      if (flagFile.existsSync()) flagFile.deleteSync();
    } catch (_) {}

    final logFile = File('$artifactDir\\scratch\\build_windows.log');
    try {
      logFile.writeAsStringSync('[${DateTime.now()}] === 开始执行 Windows Release 全量编译 (flutter build windows --release) ===\r\n');

      final proc = await Process.start(
        'cmd.exe',
        ['/c', 'flutter', 'build', 'windows', '--release'],
        workingDirectory: r'f:\klpbbs',
        runInShell: true,
      );

      proc.stdout.transform(const SystemEncoding().decoder).listen((data) {
        try {
          logFile.writeAsStringSync(data, mode: FileMode.append);
        } catch (_) {}
      });

      proc.stderr.transform(const SystemEncoding().decoder).listen((data) {
        try {
          logFile.writeAsStringSync('[STDERR] $data', mode: FileMode.append);
        } catch (_) {}
      });

      final exitCode = await proc.exitCode;
      logFile.writeAsStringSync('\r\n[${DateTime.now()}] 编译进程退出，退出码: $exitCode\r\n', mode: FileMode.append);
      if (exitCode == 0) {
        logFile.writeAsStringSync('[${DateTime.now()}] SUCCESS: Windows Release 构建成功完成！产物位于 f:\\klpbbs\\build\\windows\\x64\\runner\\Release\\klpbbs.exe\r\n', mode: FileMode.append);
      } else {
        logFile.writeAsStringSync('[${DateTime.now()}] FAILED: 编译失败，请查阅上述日志输出\r\n', mode: FileMode.append);
      }
    } catch (e, st) {
      logFile.writeAsStringSync('\r\n[${DateTime.now()}] 触发构建异常: $e\r\n$st\r\n', mode: FileMode.append);
    } finally {
      _isBuilding = false;
    }
  }

  static Future<void> _runComprehensiveCapture(GlobalKey<NavigatorState> navKey) async {
    final flagFile = File('$artifactDir\\scratch\\run_screenshot_test.flag');
    if (_isRunning) return;
    _isRunning = true;
    try {
      if (flagFile.existsSync()) flagFile.deleteSync();
    } catch (_) {}

    final outputDir = Directory('$artifactDir\\screenshots');
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    void logStep(String msg) {
      debugPrint('[AutoTestScreenshot] $msg');
      try {
        File('$artifactDir\\scratch\\screenshot_debug.log').writeAsStringSync('[$DateTime.now] $msg\r\n', mode: FileMode.append);
      } catch (_) {}
    }

    try {
      logStep('=== 开始执行多端双视口截图捕获 ===');

      // 检查 rootKey
      final ctx = rootKey.currentContext;
      logStep('rootKey.currentContext: $ctx');
      if (ctx != null) {
        final ro = ctx.findRenderObject();
        logStep('RenderObject: $ro');
        if (ro is RenderRepaintBoundary) {
          logStep('debugNeedsPaint: ${ro.debugNeedsPaint}');
        }
      }

      // ==========================================
      // 第一阶段：PC 桌面端宽屏视口 (1280 x 800)
      // ==========================================
      try {
        logStep('设置窗口大小 1280x800...');
        await windowManager.setSize(const Size(1280, 800)).timeout(const Duration(milliseconds: 300), onTimeout: () {});
        logStep('设置窗口居中...');
        await windowManager.setAlignment(Alignment.center).timeout(const Duration(milliseconds: 300), onTimeout: () {});
      } catch (e) {
        logStep('调整 PC 窗口尺寸提示: $e');
      }
      await Future.delayed(const Duration(milliseconds: 1500));

      // 1. PC - 首页
      logStep('切换 Tab 0 (首页)...');
      mainTabIndex.value = 0;
      for (int i = 0; i < 24; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final threads = PreloadService.instance.get<List<dynamic>>('home_threads', ignoreExpired: true);
        if (threads != null && threads.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 1200));
          break;
        }
      }
      logStep('准备截取 home_pc.png...');
      final s1 = await _captureAndSave('$artifactDir\\screenshots\\home_pc.png');
      logStep('PC 首页截图完成: $s1');

      // 2. PC - 导读页 (打开 GuidePage)
      final nav = navKey.currentState;
      if (nav != null && nav.mounted) {
        unawaited(
          nav.push(MaterialPageRoute(builder: (_) => const GuidePage())),
        );
        await Future.delayed(const Duration(milliseconds: 2200));
        await _captureAndSave('$artifactDir\\screenshots\\guide_pc.png');
        debugPrint('[AutoTestScreenshot] PC 导读页截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 800));
      }

      // 2.1 PC - 个人空间 (打开 UserSpacePage)
      if (nav != null && nav.mounted) {
        logStep('开始预请求 UserSpace 354295...');
        final sw = Stopwatch()..start();
        final preloaded = await KlpbbsApi.getUserSpace(354295);
        logStep('UserSpace 354295 请求耗时: ${sw.elapsedMilliseconds}ms, 用户名: ${preloaded?.username}, 积分: ${preloaded?.credits}');
        unawaited(
          nav.push(MaterialPageRoute(builder: (_) => UserSpacePage(uid: 354295, initialUser: preloaded))),
        );
        await Future.delayed(const Duration(milliseconds: 2500));
        await _captureAndSave('$artifactDir\\screenshots\\userspace_pc.png');
        logStep('PC 个人空间截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 800));
      }

      // 3. PC - 版块大全
      mainTabIndex.value = 1;
      await Future.delayed(const Duration(milliseconds: 1500));
      await _captureAndSave('$artifactDir\\screenshots\\forums_pc.png');
      debugPrint('[AutoTestScreenshot] PC 版块页截图完成');

      // 4. PC - 勋章中心
      mainTabIndex.value = 3;
      await Future.delayed(const Duration(milliseconds: 1500));
      await _captureAndSave('$artifactDir\\screenshots\\medal_pc.png');
      debugPrint('[AutoTestScreenshot] PC 勋章页截图完成');

      // 5. PC - 个人中心
      mainTabIndex.value = 4;
      await Future.delayed(const Duration(milliseconds: 1500));
      await _captureAndSave('$artifactDir\\screenshots\\usercenter_pc.png');
      debugPrint('[AutoTestScreenshot] PC 个人中心截图完成');

      // 6. PC - 搜索页
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const SearchPage())));
        await Future.delayed(const Duration(milliseconds: 1800));
        await _captureAndSave('$artifactDir\\screenshots\\search_pc.png');
        debugPrint('[AutoTestScreenshot] PC 搜索页截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 7. PC - 消息通知
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const NoticePage())));
        await Future.delayed(const Duration(milliseconds: 1800));
        await _captureAndSave('$artifactDir\\screenshots\\notice_pc.png');
        debugPrint('[AutoTestScreenshot] PC 消息通知页截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 8. PC - 帖子详情
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const ThreadDetailPage(tid: 173229))));
        await Future.delayed(const Duration(milliseconds: 4200));
        await _captureAndSave('$artifactDir\\screenshots\\thread_pc.png');
        debugPrint('[AutoTestScreenshot] PC 帖子详情页截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 9. PC - 封神榜
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const DarkroomPage())));
        await Future.delayed(const Duration(milliseconds: 2000));
        await _captureAndSave('$artifactDir\\screenshots\\darkroom_pc.png');
        debugPrint('[AutoTestScreenshot] PC 封神榜截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 10. PC - 积分中心与记录
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 0))));
        await Future.delayed(const Duration(milliseconds: 2000));
        await _captureAndSave('$artifactDir\\screenshots\\credit_pc.png');
        debugPrint('[AutoTestScreenshot] PC 积分中心截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));

        // 10.1 PC - 积分记录
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 2))));
        await Future.delayed(const Duration(milliseconds: 2500));
        await _captureAndSave('$artifactDir\\screenshots\\credit_log_pc.png');
        debugPrint('[AutoTestScreenshot] PC 积分记录截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));

        // 10.2 PC - 道具中心 (商店与我的道具包)
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const MagicPage(initialTab: 0))));
        await Future.delayed(const Duration(milliseconds: 2500));
        await _captureAndSave('$artifactDir\\screenshots\\magic_shop_pc.png');
        debugPrint('[AutoTestScreenshot] PC 道具商店截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));

        unawaited(nav.push(MaterialPageRoute(builder: (_) => const MagicPage(initialTab: 1))));
        await Future.delayed(const Duration(milliseconds: 2500));
        await _captureAndSave('$artifactDir\\screenshots\\magic_mybox_pc.png');
        debugPrint('[AutoTestScreenshot] PC 我的道具包截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 11. PC - 排行榜
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const RanklistPage())));
        await Future.delayed(const Duration(milliseconds: 4500));
        await _captureAndSave('$artifactDir\\screenshots\\ranklist_pc.png');
        debugPrint('[AutoTestScreenshot] PC 排行榜截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 12. PC - 每日签到
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const SignRankPage())));
        await Future.delayed(const Duration(milliseconds: 3200));
        await _captureAndSave('$artifactDir\\screenshots\\sign_pc.png');
        debugPrint('[AutoTestScreenshot] PC 签到页截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 13. PC - 我的收藏
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const FavoriteHubPage(uid: 0))));
        await Future.delayed(const Duration(milliseconds: 2500));
        await _captureAndSave('$artifactDir\\screenshots\\favorite_pc.png');
        debugPrint('[AutoTestScreenshot] PC 我的收藏截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 14. PC - 任务中心
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const TaskPage())));
        await Future.delayed(const Duration(milliseconds: 3500));
        await _captureAndSave('$artifactDir\\screenshots\\task_pc.png');
        debugPrint('[AutoTestScreenshot] PC 任务中心截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 15. PC - 私信收件箱
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const PmInboxPage())));
        await Future.delayed(const Duration(milliseconds: 3500));
        await _captureAndSave('$artifactDir\\screenshots\\pminbox_pc.png');
        debugPrint('[AutoTestScreenshot] PC 私信收件箱截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // ==========================================
      // 第二阶段：移动端竖屏视口 (420 x 860)
      // ==========================================
      try {
        await windowManager.setSize(const Size(420, 860)).timeout(const Duration(milliseconds: 300), onTimeout: () {});
        await windowManager.setAlignment(Alignment.center).timeout(const Duration(milliseconds: 300), onTimeout: () {});
      } catch (e) {
        debugPrint('[AutoTestScreenshot] 调整移动端窗口尺寸提示: $e');
      }
      await Future.delayed(const Duration(milliseconds: 1800));

      // 12. 移动端 - 个人中心
      mainTabIndex.value = 4;
      await Future.delayed(const Duration(milliseconds: 1200));
      await _captureAndSave('$artifactDir\\screenshots\\usercenter_mobile.png');
      debugPrint('[AutoTestScreenshot] 移动端 个人中心截图完成');

      // 13. 移动端 - 勋章中心
      mainTabIndex.value = 3;
      await Future.delayed(const Duration(milliseconds: 1200));
      await _captureAndSave('$artifactDir\\screenshots\\medal_mobile.png');
      debugPrint('[AutoTestScreenshot] 移动端 勋章页截图完成');

      // 14. 移动端 - 版块大全
      mainTabIndex.value = 1;
      await Future.delayed(const Duration(milliseconds: 1200));
      await _captureAndSave('$artifactDir\\screenshots\\forums_mobile.png');
      debugPrint('[AutoTestScreenshot] 移动端 版块页截图完成');

      // 15. 移动端 - 导读页
      if (nav != null && nav.mounted) {
        unawaited(
          nav.push(MaterialPageRoute(builder: (_) => const GuidePage())),
        );
        await Future.delayed(const Duration(milliseconds: 2200));
        await _captureAndSave('$artifactDir\\screenshots\\guide_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 导读页截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 15.1 移动端 - 个人空间
      if (nav != null && nav.mounted) {
        final preloaded = PreloadService.instance.get<UserSpace>('user_space_354295');
        unawaited(
          nav.push(MaterialPageRoute(builder: (_) => UserSpacePage(uid: 354295, initialUser: preloaded))),
        );
        await Future.delayed(const Duration(milliseconds: 2200));
        await _captureAndSave('$artifactDir\\screenshots\\userspace_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 个人空间截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 16. 移动端 - 搜索页
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const SearchPage())));
        await Future.delayed(const Duration(milliseconds: 1600));
        await _captureAndSave('$artifactDir\\screenshots\\search_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 搜索页截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 17. 移动端 - 消息通知
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const NoticePage())));
        await Future.delayed(const Duration(milliseconds: 1600));
        await _captureAndSave('$artifactDir\\screenshots\\notice_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 消息通知页截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 18. 移动端 - 帖子详情
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const ThreadDetailPage(tid: 173229))));
        await Future.delayed(const Duration(milliseconds: 4500));
        await _captureAndSave('$artifactDir\\screenshots\\thread_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 帖子详情页截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 19. 移动端 - 封神榜
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const DarkroomPage())));
        await Future.delayed(const Duration(milliseconds: 1800));
        await _captureAndSave('$artifactDir\\screenshots\\darkroom_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 封神榜截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 20. 移动端 - 积分中心与记录
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 0))));
        await Future.delayed(const Duration(milliseconds: 1800));
        await _captureAndSave('$artifactDir\\screenshots\\credit_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 积分中心截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));

        unawaited(nav.push(MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 2))));
        await Future.delayed(const Duration(milliseconds: 2500));
        await _captureAndSave('$artifactDir\\screenshots\\credit_log_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 积分记录截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));

        // 20.1 移动端 - 道具中心
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const MagicPage(initialTab: 0))));
        await Future.delayed(const Duration(milliseconds: 2500));
        await _captureAndSave('$artifactDir\\screenshots\\magic_shop_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 道具商店截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));

        unawaited(nav.push(MaterialPageRoute(builder: (_) => const MagicPage(initialTab: 1))));
        await Future.delayed(const Duration(milliseconds: 2500));
        await _captureAndSave('$artifactDir\\screenshots\\magic_mybox_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 我的道具包截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 21. 移动端 - 排行榜
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const RanklistPage())));
        await Future.delayed(const Duration(milliseconds: 4500));
        await _captureAndSave('$artifactDir\\screenshots\\ranklist_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 排行榜截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 22. 移动端 - 每日签到
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const SignRankPage())));
        await Future.delayed(const Duration(milliseconds: 3200));
        await _captureAndSave('$artifactDir\\screenshots\\sign_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 签到页截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 23. 移动端 - 我的收藏
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const FavoriteHubPage(uid: 0))));
        await Future.delayed(const Duration(milliseconds: 2500));
        await _captureAndSave('$artifactDir\\screenshots\\favorite_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 我的收藏截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 24. 移动端 - 任务中心
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const TaskPage())));
        await Future.delayed(const Duration(milliseconds: 3500));
        await _captureAndSave('$artifactDir\\screenshots\\task_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 任务中心截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 25. 移动端 - 私信收件箱
      if (nav != null && nav.mounted) {
        unawaited(nav.push(MaterialPageRoute(builder: (_) => const PmInboxPage())));
        await Future.delayed(const Duration(milliseconds: 3500));
        await _captureAndSave('$artifactDir\\screenshots\\pminbox_mobile.png');
        debugPrint('[AutoTestScreenshot] 移动端 私信收件箱截图完成');
        if (nav.mounted && nav.canPop()) nav.pop();
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // 26. 移动端 - 首页
      mainTabIndex.value = 0;
      await Future.delayed(const Duration(milliseconds: 1200));
      await _captureAndSave('$artifactDir\\screenshots\\home_mobile.png');
      debugPrint('[AutoTestScreenshot] 移动端 首页截图完成');

      // 恢复舒适默认窗口大小 (1150 x 750)
      try {
        await windowManager.setSize(const Size(1150, 750)).timeout(const Duration(milliseconds: 300), onTimeout: () {});
      } catch (_) {}

      // 写入完成标识
      final doneFile = File('$artifactDir\\scratch\\screenshot_done.txt');
      await doneFile.writeAsString(
        'DONE: All screenshots generated at ${DateTime.now().toIso8601String()}\n',
      );
      debugPrint('[AutoTestScreenshot] === 多端双视口截图捕获全部完成 ===');
    } catch (e, stack) {
      debugPrint('[AutoTestScreenshot] 截图流程发生异常: $e\n$stack');
      final errFile = File('$artifactDir\\scratch\\screenshot_error.txt');
      await errFile.writeAsString('ERROR: $e\n$stack');
    } finally {
      _isRunning = false;
    }
  }

  static Future<bool> _captureAndSave(String filePath) async {
    void log(String m) {
      try {
        File('$artifactDir\\scratch\\screenshot_debug.log').writeAsStringSync('  [_captureAndSave] $m\r\n', mode: FileMode.append);
      } catch (_) {}
    }
    try {
      log('findRenderObject for rootKey...');
      final boundary = rootKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        log('无法获取 RenderRepaintBoundary');
        debugPrint('[AutoTestScreenshot] 无法获取 RenderRepaintBoundary');
        return false;
      }
      log('boundary found, debugNeedsPaint: ${boundary.debugNeedsPaint}');
      if (boundary.debugNeedsPaint) {
        log('waiting 500ms for repaint...');
        await Future.delayed(const Duration(milliseconds: 500));
      }
      log('calling boundary.toImage(pixelRatio: 1.0)...');
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      log('image captured (${image.width}x${image.height}), converting to PNG...');
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        log('byteData is null');
        debugPrint('[AutoTestScreenshot] 转换 PNG 失败: byteData 为空');
        return false;
      }
      log('writing ${byteData.lengthInBytes} bytes to $filePath...');
      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final file = File(filePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      await file.writeAsBytes(pngBytes, flush: true);
      log('successfully saved $filePath');
      return true;
    } catch (e, st) {
      log('Exception: $e\n$st');
      debugPrint('[AutoTestScreenshot] 保存截图异常: $e');
      return false;
    }
  }
}
