import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_config.dart';
import '../main.dart';
import '../pages/search_page.dart';
import '../pages/thread_detail_page.dart';

/// 剪贴板跳转目标类型
enum ClipboardJumpType {
  thread,
  search,
}

/// 剪贴板跳转目标对象
class ClipboardJumpTarget {
  final ClipboardJumpType type;
  final int? tid;
  final String? keyword;
  final String rawText;
  final String displayTitle;
  final String displaySubtitle;

  const ClipboardJumpTarget({
    required this.type,
    this.tid,
    this.keyword,
    required this.rawText,
    required this.displayTitle,
    required this.displaySubtitle,
  });
}

/// 苦力怕论坛 智能剪贴板跳转服务（仅在切回应用窗口时触发）
class ClipboardJumpService with WindowListener, WidgetsBindingObserver {
  static final ClipboardJumpService instance = ClipboardJumpService._();
  ClipboardJumpService._();

  bool _initialized = false;
  bool _isChecking = false;
  bool _isPromptShowing = false;
  DateTime? _lastCheckTime;
  String? _lastHandledText;

  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 初始化监听器
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);
    if (isDesktop) {
      try {
        windowManager.addListener(this);
      } catch (_) {}
    }
  }

  /// 释放监听器
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (isDesktop) {
      try {
        windowManager.removeListener(this);
      } catch (_) {}
    }
    _initialized = false;
  }

  // ================= 窗口与生命周期事件 =================

  /// Desktop: 用户点击激活或通过 Alt+Tab / 任务栏切回应用窗口
  @override
  void onWindowFocus() {
    checkClipboard(source: 'window_focus');
  }

  /// Mobile & 全平台: 应用前后台切换
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkClipboard(source: 'lifecycle_resumed');
    }
  }

  /// 执行剪贴板检测与跳转
  Future<void> checkClipboard({String source = 'manual'}) async {
    if (!AppConfig.clipboardJumpEnabled) return;

    // 冷却防抖：800ms 内不重复检测（避免 onWindowFocus 与 resumed 连续触发）
    final now = DateTime.now();
    if (_lastCheckTime != null &&
        now.difference(_lastCheckTime!).inMilliseconds < 800) {
      return;
    }
    _lastCheckTime = now;

    if (_isChecking || _isPromptShowing) return;
    _isChecking = true;

    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = clipboardData?.text?.trim();
      if (raw == null || raw.isEmpty) return;

      // 若当前剪贴板内容与上次已处理的内容完全一致，不再重复打扰
      if (raw == _lastHandledText) return;

      final target = parseClipboardContent(raw);
      if (target == null) {
        // 非论坛目标链接，记为已处理，避免后续每次切回反复空查无用文本
        _lastHandledText = raw;
        return;
      }

      // 检查子开关
      if (target.type == ClipboardJumpType.thread &&
          !AppConfig.clipboardJumpThreadEnabled) {
        _lastHandledText = raw;
        return;
      }
      if (target.type == ClipboardJumpType.search &&
          !AppConfig.clipboardJumpSearchEnabled) {
        _lastHandledText = raw;
        return;
      }

      _lastHandledText = raw;

      final context = appNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;

      if (AppConfig.clipboardJumpConfirm) {
        _isPromptShowing = true;
        try {
          await _showJumpDialog(context, target);
        } finally {
          _isPromptShowing = false;
        }
      } else {
        _performJump(context, target);
      }
    } catch (e) {
      debugPrint('剪贴板跳转检测异常: $e');
    } finally {
      _isChecking = false;
    }
  }

  /// 解析剪贴板内容是否为苦力怕论坛帖子或站内搜索
  ClipboardJumpTarget? parseClipboardContent(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // 1. 检测帖子链接 (thread-12345 或 mod=viewthread&tid=12345)
    final threadRegex = RegExp(
      r'(?:thread-(\d+)|(?:mod=viewthread[^\s]*tid=|tid=)(\d+))',
      caseSensitive: false,
    );
    final tMatch = threadRegex.firstMatch(trimmed);
    if (tMatch != null) {
      final tidStr = tMatch.group(1) ?? tMatch.group(2);
      final tid = int.tryParse(tidStr ?? '');
      if (tid != null && tid > 0) {
        // 保证是苦力怕论坛或标准格式
        final isForumRelated = trimmed.contains('klpbbs') ||
            trimmed.contains('klpz.net') ||
            trimmed.contains('thread-') ||
            trimmed.contains('viewthread') ||
            trimmed.contains('苦力怕论坛');
        if (isForumRelated) {
          return ClipboardJumpTarget(
            type: ClipboardJumpType.thread,
            tid: tid,
            rawText: trimmed,
            displayTitle: '检测到帖子链接',
            displaySubtitle: '帖子编号：#$tid',
          );
        }
      }
    }

    // 2. 检测站内搜索链接 (search.php 或 /search)
    final isSearchRelated = (trimmed.contains('klpbbs') ||
            trimmed.contains('klpz.net') ||
            trimmed.startsWith('/') ||
            trimmed.startsWith('http')) &&
        (trimmed.contains('search.php') || trimmed.contains('/search'));
    if (isSearchRelated) {
      final uri = Uri.tryParse(trimmed);
      String? kw;
      if (uri != null) {
        kw = uri.queryParameters['srchtxt'] ??
            uri.queryParameters['keyword'] ??
            uri.queryParameters['kw'] ??
            uri.queryParameters['q'];
      }
      if (kw == null) {
        final kwM = RegExp(r'(?:srchtxt|keyword|kw|q)=([^&\s]+)').firstMatch(trimmed);
        if (kwM != null) {
          try {
            kw = Uri.decodeQueryComponent(kwM.group(1)!);
          } catch (_) {
            try {
              kw = Uri.decodeComponent(kwM.group(1)!);
            } catch (_) {
              kw = kwM.group(1);
            }
          }
        }
      }
      return ClipboardJumpTarget(
        type: ClipboardJumpType.search,
        keyword: kw,
        rawText: trimmed,
        displayTitle: '检测到站内搜索链接',
        displaySubtitle: (kw != null && kw.isNotEmpty)
            ? '搜索关键词：「$kw」'
            : '前往苦力怕论坛搜索',
      );
    }

    return null;
  }

  /// 弹出跳转确认对话框
  Future<void> _showJumpDialog(
    BuildContext context,
    ClipboardJumpTarget target,
  ) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isThread = target.type == ClipboardJumpType.thread;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: colorScheme.surface,
          elevation: 6,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部标题与图标
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isThread
                              ? colorScheme.primaryContainer.withAlpha(160)
                              : colorScheme.secondaryContainer.withAlpha(160),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isThread
                              ? Icons.article_rounded
                              : Icons.search_rounded,
                          color: isThread
                              ? colorScheme.primary
                              : colorScheme.secondary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              target.displayTitle,
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '从剪贴板读取到相关链接',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant.withAlpha(180),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 内容信息卡片
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withAlpha(60),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          target.displaySubtitle,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isThread
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          target.rawText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant.withAlpha(160),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(false),
                        child: Text(
                          '忽略',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(dialogCtx).pop(true),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(isThread ? '前往帖子' : '立即搜索'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (result == true && context.mounted) {
      _performJump(context, target);
    }
  }

  /// 执行导航跳转
  void _performJump(BuildContext context, ClipboardJumpTarget target) {
    if (target.type == ClipboardJumpType.thread && target.tid != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ThreadDetailPage(tid: target.tid!),
        ),
      );
    } else if (target.type == ClipboardJumpType.search) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SearchPage(initialKeyword: target.keyword),
        ),
      );
    }
  }
}
