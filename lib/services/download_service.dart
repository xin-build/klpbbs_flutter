import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/dio_client.dart';

enum DownloadStatus {
  pending('等待中'),
  downloading('下载中'),
  paused('已暂停'),
  completed('已完成'),
  failed('下载失败'),
  canceled('已取消');

  final String label;
  const DownloadStatus(this.label);
}

/// 下载任务数据模型
class DownloadTask {
  final String id;
  final String url;
  String filename;
  String savePath;
  int totalBytes;
  int downloadedBytes;
  int speed; // 字节/秒
  DownloadStatus status;
  String? error;
  int threadCount;
  final DateTime createdAt;

  DownloadTask({
    required this.id,
    required this.url,
    required this.filename,
    required this.savePath,
    this.totalBytes = -1,
    this.downloadedBytes = 0,
    this.speed = 0,
    this.status = DownloadStatus.pending,
    this.error,
    this.threadCount = 4,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;

  String get speedText {
    if (speed <= 0) return '0 B/s';
    if (speed < 1024) return '$speed B/s';
    if (speed < 1024 * 1024) return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get sizeText {
    String format(int bytes) {
      if (bytes <= 0) return '0 B';
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    if (totalBytes > 0) {
      return '${format(downloadedBytes)} / ${format(totalBytes)}';
    }
    return format(downloadedBytes);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'filename': filename,
    'savePath': savePath,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'status': status.name,
    'threadCount': threadCount,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      filename: json['filename'] as String,
      savePath: json['savePath'] as String,
      totalBytes: json['totalBytes'] as int? ?? -1,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.completed,
      ),
      threadCount: json['threadCount'] as int? ?? 4,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

/// 内置多线程下载服务与管理器
class DownloadManager extends ChangeNotifier {
  static final DownloadManager instance = DownloadManager._();
  DownloadManager._();

  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  final Map<String, _ActiveDownloader> _active = {};

  static const String _prefsKey = 'klpbbs_download_tasks_v1';

  /// 初始化并从本地存储加载历史任务
  Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(_prefsKey) ?? [];
      _tasks.clear();
      for (final item in list) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          final task = DownloadTask.fromJson(map);
          // 未完成的任务在重启后标记为已暂停
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.pending) {
            task.status = DownloadStatus.paused;
          }
          _tasks.add(task);
        } catch (_) {}
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveTasks() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = _tasks.map((t) => jsonEncode(t.toJson())).toList();
      await sp.setStringList(_prefsKey, list);
    } catch (_) {}
  }

  /// 获取指定任务
  DownloadTask? getTask(String id) {
    final idx = _tasks.indexWhere((t) => t.id == id);
    return idx >= 0 ? _tasks[idx] : null;
  }

  /// 获取指定 URL 对应的任务
  DownloadTask? getTaskByUrl(String url) {
    final idx = _tasks.indexWhere((t) => t.url == url);
    return idx >= 0 ? _tasks[idx] : null;
  }

  /// 开始新下载任务
  Future<DownloadTask> startDownload({
    required String url,
    required String filename,
    String? saveDir,
    int? threads,
  }) async {
    // 检查是否已有相同 URL 的任务
    final existing = getTaskByUrl(url);
    if (existing != null) {
      if (existing.status == DownloadStatus.completed) {
        final file = File(existing.savePath);
        if (await file.exists()) {
          return existing;
        }
      }
      // 重新启动已存在的任务
      resumeDownload(existing.id);
      return existing;
    }

    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    final targetDir = saveDir ?? await getDownloadDirectory();
    final cleanName = _sanitizeFilename(filename.isNotEmpty ? filename : 'attachment_$taskId.bin');
    final savePath = p.join(targetDir, cleanName);

    // 确保目标目录存在
    final dir = Directory(targetDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final task = DownloadTask(
      id: taskId,
      url: url,
      filename: cleanName,
      savePath: savePath,
      threadCount: threads ?? AppConfig.downloadThreads,
      status: DownloadStatus.pending,
    );

    _tasks.insert(0, task);
    notifyListeners();
    await _saveTasks();

    _runDownload(task);
    return task;
  }

  void _runDownload(DownloadTask task) {
    final downloader = _ActiveDownloader(
      task: task,
      onProgress: (downloaded, total, speed) {
        task.downloadedBytes = downloaded;
        task.totalBytes = total;
        task.speed = speed;
        task.status = DownloadStatus.downloading;
        notifyListeners();
      },
      onComplete: (actualFilename, actualPath) async {
        task.filename = actualFilename;
        task.savePath = actualPath;
        try {
          final file = File(actualPath);
          if (await file.exists()) {
            final len = await file.length();
            task.downloadedBytes = len;
            task.totalBytes = len;
          }
        } catch (_) {}
        task.status = DownloadStatus.completed;
        task.speed = 0;
        _active.remove(task.id);
        notifyListeners();
        await _saveTasks();

        if (AppConfig.autoOpenFile) {
          openFile(task.savePath);
        }
      },
      onError: (err) async {
        task.status = DownloadStatus.failed;
        task.error = err;
        task.speed = 0;
        _active.remove(task.id);
        notifyListeners();
        await _saveTasks();
      },
    );

    _active[task.id] = downloader;
    downloader.start();
  }

  /// 暂停下载
  void pauseDownload(String id) {
    final downloader = _active.remove(id);
    downloader?.cancel();
    final task = getTask(id);
    if (task != null) {
      task.status = DownloadStatus.paused;
      task.speed = 0;
      notifyListeners();
      _saveTasks();
    }
  }

  /// 恢复/重新下载
  void resumeDownload(String id) {
    final task = getTask(id);
    if (task == null) return;
    if (_active.containsKey(id)) return;

    task.status = DownloadStatus.pending;
    task.error = null;
    notifyListeners();

    _runDownload(task);
  }

  /// 取消下载
  void cancelDownload(String id) {
    final downloader = _active.remove(id);
    downloader?.cancel();
    final task = getTask(id);
    if (task != null) {
      task.status = DownloadStatus.canceled;
      task.speed = 0;
      notifyListeners();
      _saveTasks();
    }
  }

  /// 删除任务及可选删除本地文件
  Future<void> deleteTask(String id, {bool deleteFile = false}) async {
    cancelDownload(id);
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      final task = _tasks.removeAt(idx);
      if (deleteFile) {
        try {
          final file = File(task.savePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      notifyListeners();
      await _saveTasks();
    }
  }

  /// 清空已完成或已失败的任务记录
  Future<void> clearFinishedTasks() async {
    _tasks.removeWhere(
      (t) =>
          t.status == DownloadStatus.completed ||
          t.status == DownloadStatus.failed ||
          t.status == DownloadStatus.canceled,
    );
    notifyListeners();
    await _saveTasks();
  }

  /// 调用系统程序打开文件
  static Future<OpenResult> openFile(String filePath) async {
    return await OpenFilex.open(filePath);
  }

  /// 打开文件所在文件夹
  static Future<void> openFolder(String filePath) async {
    try {
      final file = File(filePath);
      final dirPath = file.parent.path;

      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dirPath]);
      } else {
        // 移动端尝试通过 url_launcher 或 open_filex
        final uri = Uri.file(dirPath);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          await OpenFilex.open(filePath);
        }
      }
    } catch (_) {
      await OpenFilex.open(filePath);
    }
  }

  /// 获取多平台默认下载目录
  static Future<String> getDownloadDirectory() async {
    // 1. 如果用户已自定义配置，优先使用自定义目录
    final customPath = AppConfig.downloadPath;
    if (customPath.isNotEmpty) {
      final d = Directory(customPath);
      if (await d.exists() || (await d.create(recursive: true)).existsSync()) {
        return customPath;
      }
    }

    // 2. 跨平台默认目录探测
    try {
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          final winDownloads = p.join(userProfile, 'Downloads');
          if (await Directory(winDownloads).exists()) return winDownloads;
        }
      }

      if (Platform.isAndroid) {
        // Android 外部主存储 Download 目录
        final extDownload = Directory('/storage/emulated/0/Download');
        if (await extDownload.exists()) return extDownload.path;
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) return extDir.path;
      }

      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads.path;

      final appDoc = await getApplicationDocumentsDirectory();
      return appDoc.path;
    } catch (_) {
      final appDoc = await getApplicationDocumentsDirectory();
      return appDoc.path;
    }
  }

  static String _sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll('\r', '')
        .replaceAll('\n', '')
        .trim();
  }
}

/// 执行单任务多线程分块下载的内部工作器
class _ActiveDownloader {
  final DownloadTask task;
  final void Function(int downloaded, int total, int speed) onProgress;
  final void Function(String filename, String savePath) onComplete;
  final void Function(String error) onError;

  bool _isCanceled = false;
  final List<CancelToken> _cancelTokens = [];

  _ActiveDownloader({
    required this.task,
    required this.onProgress,
    required this.onComplete,
    required this.onError,
  });

  void cancel() {
    _isCanceled = true;
    for (final token in _cancelTokens) {
      token.cancel();
    }
  }

  Future<void> start() async {
    _cancelTokens.clear();
    _isCanceled = false;

    try {
      var targetUrl = task.url.trim();
      if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
        targetUrl = '${AppConfig.baseUrl}/$targetUrl'.replaceAll(RegExp(r'(?<!:)/+'), '/');
      }

      final isKlpbbsUrl = targetUrl.contains('klpbbs.com') || targetUrl.contains('127.0.0.1') || targetUrl.contains('localhost');
      final headers = <String, String>{
        'User-Agent': AppConfig.userAgent,
        'Referer': 'https://klpbbs.com/forum.php',
        'Accept': '*/*',
      };
      final cookieHeader = DioClient.allCookiesHeader;
      if (cookieHeader.isNotEmpty && isKlpbbsUrl) {
        headers['Cookie'] = cookieHeader;
      }

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 45),
          headers: headers,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );

      // 1. GET 探测（支持获取 Content-Disposition 真实文件名与 Content-Length）
      final probeToken = CancelToken();
      _cancelTokens.add(probeToken);
      String? extractedFilename;

      var probeResp = await dio.get<ResponseBody>(
        targetUrl,
        cancelToken: probeToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=0-1023'},
        ),
      );

      if (_isCanceled) return;

      // 检查 Content-Type：如果是 HTML 说明 Discuz 返回了跳转页、报错页或网盘页
      var ct = probeResp.headers.value('content-type')?.toLowerCase() ?? '';
      if ((ct.contains('text/html') || ct.contains('text/plain')) &&
          !targetUrl.endsWith('.html') &&
          !targetUrl.endsWith('.htm')) {
        final chunks = <int>[];
        await for (final c in probeResp.data!.stream) {
          chunks.addAll(c);
          if (chunks.length > 500000) break;
        }
        final htmlText = utf8.decode(chunks, allowMalformed: true);

        // 1. 错误提示识别
        if (htmlText.contains('需要先登录') || htmlText.contains('未登录') || htmlText.contains('login')) {
          throw '下载失败：该附件需要登录论坛账号后下载';
        } else if (htmlText.contains('积分不足') || htmlText.contains('铁粒不足')) {
          throw '下载失败：您的铁粒/积分不足以购买此附件';
        } else if (htmlText.contains('附件不存在') || htmlText.contains('已删除') || htmlText.contains('附件文件不存在')) {
          throw '下载失败：该附件已失效或不存在';
        } else if (htmlText.contains('alert_error') || htmlText.contains('抱歉，您没有权限')) {
          final m = RegExp(r'<p[^>]*>(.*?)</p>').firstMatch(htmlText);
          throw '下载失败：${m?.group(1) ?? "论坛权限或安全策略拦截"}';
        }

        // 2. 尝试从 HTML（论坛中转页/下载票据页）中提取真实文件直链
        String? foundDirectUrl;

        // A. 提取文件名 <h1 class="file-name" ...>filename</h1>
        final h1M = RegExp(r'''<h1[^>]*class=['"][^'"]*file-name[^'"]*['"][^>]*>(.*?)</h1>''', caseSensitive: false).firstMatch(htmlText);
        if (h1M != null && h1M.group(1)!.trim().isNotEmpty) {
          extractedFilename = h1M.group(1)!.trim();
        }

        // B. 优先匹配 klpbbs 官方附件详情页的主线路 / 备用线路（primary-download / getFile.php / download-button）
        final primaryM = RegExp(r'''<a[^>]+class=['"][^'"]*(?:primary-download|download-button)[^'"]*['"][^>]+href=['"]([^'"]+)['"]''', caseSensitive: false).firstMatch(htmlText)
            ?? RegExp(r'''<a[^>]+href=['"]([^'"]+)['"][^>]+class=['"][^'"]*(?:primary-download|download-button)[^'"]*['"]''', caseSensitive: false).firstMatch(htmlText);
        if (primaryM != null) {
          foundDirectUrl = primaryM.group(1)!.replaceAll('&amp;', '&').trim();
        }

        if (foundDirectUrl == null) {
          final getFileM = RegExp(r'''href=['"]([^'"]*getFile\.php[^'"]*)['"]''', caseSensitive: false).firstMatch(htmlText);
          if (getFileM != null) {
            foundDirectUrl = getFileM.group(1)!.replaceAll('&amp;', '&').trim();
          }
        }

        // JS 重定向: window.location / location.href
        if (foundDirectUrl == null) {
          final jsM = RegExp(r'''(?:window\.)?location(?:\.href)?\s*=\s*['"]([^'"]+)['"]''').firstMatch(htmlText);
          if (jsM != null && jsM.group(1)!.isNotEmpty && !jsM.group(1)!.contains('login')) {
            foundDirectUrl = jsM.group(1)!.trim();
          }
        }

        // Meta refresh 重定向
        if (foundDirectUrl == null) {
          final metaM = RegExp(r'''<meta[^>]+http-equiv=['"]refresh['"][^>]+content=['"][^'"]*url=([^'"]+)['"]''', caseSensitive: false).firstMatch(htmlText);
          if (metaM != null && metaM.group(1)!.isNotEmpty) {
            foundDirectUrl = metaM.group(1)!.trim();
          }
        }

        // 通用下载链接提取
        if (foundDirectUrl == null) {
          final linkMatches = RegExp(r'''<a[^>]+href=['"]([^'"]+)['"][^>]*>(.*?)</a>''', caseSensitive: false).allMatches(htmlText);
          for (final lm in linkMatches) {
            final href = (lm.group(1) ?? '').replaceAll('&amp;', '&').trim();
            final text = lm.group(2) ?? '';
            if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) continue;
            if (href.contains('attach.php') || href.contains('download') || href.contains('getFile.php') ||
                href.contains('data.klpbbs.com') || href.contains('ip.klpbbs.com') || href.contains('mutool.top') ||
                href.contains('klpz.net') || RegExp(r'\.(zip|mcpack|mcaddon|apk|7z|rar|jar|tar|gz)$', caseSensitive: false).hasMatch(href)) {
              foundDirectUrl = href;
              break;
            }
            if (text.contains('高速下载') || text.contains('本地下载') || text.contains('直接下载') || text.contains('主线路') || text.contains('下载地址')) {
              foundDirectUrl = href;
              break;
            }
          }
        }

        if (foundDirectUrl == null) {
          if (htmlText.contains('pan.baidu.com') || htmlText.contains('123pan.com') ||
              htmlText.contains('lanzou') || htmlText.contains('quark.cn')) {
            throw '此附件为第三方网盘存储，请点击【网页跳转下载】在浏览器中提取';
          }
          throw '下载失败：返回了网页（可能需购买附件或权限受限），请使用【网页跳转下载】';
        }

        final originalReferer = targetUrl;
        if (!foundDirectUrl.startsWith('http://') && !foundDirectUrl.startsWith('https://')) {
          foundDirectUrl = '${AppConfig.baseUrl}/$foundDirectUrl'.replaceAll(RegExp(r'(?<!:)/+'), '/');
        }
        targetUrl = foundDirectUrl;

        // 对提取出的直链发起真实二进制探测
        final probeToken2 = CancelToken();
        _cancelTokens.add(probeToken2);
        probeResp = await dio.get<ResponseBody>(
          targetUrl,
          cancelToken: probeToken2,
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'Range': 'bytes=0-1023',
              'Referer': originalReferer,
            },
          ),
        );
        ct = probeResp.headers.value('content-type')?.toLowerCase() ?? '';
      }

      // 提取文件名（优先网页解析到的文件名，其次 Content-Disposition，其次 URL &n= 参数）
      var resolvedFilename = task.filename;
      if (extractedFilename != null && extractedFilename.isNotEmpty) {
        resolvedFilename = extractedFilename;
        task.filename = extractedFilename;
      }

      final cd = probeResp.headers.value('content-disposition');
      if (cd != null) {
        final fnM = RegExp(
          r"""filename\*?=(?:UTF-8'')?"?([^";]+)"?""",
          caseSensitive: false,
        ).firstMatch(cd);
        if (fnM != null) {
          try {
            resolvedFilename = Uri.decodeFull(fnM.group(1)!.trim());
          } catch (_) {
            resolvedFilename = fnM.group(1)!.trim();
          }
          task.filename = resolvedFilename;
        }
      } else {
        final uri = Uri.tryParse(targetUrl);
        final nParam = uri?.queryParameters['n'];
        if (nParam != null && nParam.isNotEmpty) {
          resolvedFilename = nParam;
          task.filename = nParam;
        }
      }

      resolvedFilename = DownloadManager._sanitizeFilename(resolvedFilename);
      task.filename = resolvedFilename;
      final finalSavePath = p.join(p.dirname(task.savePath), resolvedFilename);
      task.savePath = finalSavePath;

      // 提取文件大小与 Range 支持
      int totalSize = -1;
      final cl = probeResp.headers.value('content-length');
      if (cl != null) {
        totalSize = int.tryParse(cl) ?? -1;
      }
      final cr = probeResp.headers.value('content-range');
      if (cr != null) {
        final crM = RegExp(r'/(\d+)').firstMatch(cr);
        if (crM != null) {
          totalSize = int.tryParse(crM.group(1)!) ?? totalSize;
        }
      }

      final acceptRanges = probeResp.headers.value('accept-ranges') == 'bytes' ||
          probeResp.statusCode == 206;

      final threadCount = (acceptRanges && totalSize > 1024 * 1024)
          ? task.threadCount.clamp(1, 8)
          : 1;

      // 2. 分配多线程分块或单线程流式下载
      if (threadCount > 1 && totalSize > 0) {
        await _downloadMultiThread(
          dio,
          targetUrl,
          totalSize,
          threadCount,
          finalSavePath,
          resolvedFilename,
        );
      } else {
        await _downloadSingleThread(
          dio,
          targetUrl,
          totalSize,
          finalSavePath,
          resolvedFilename,
        );
      }
    } catch (e) {
      if (_isCanceled) return;
      onError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// 多线程分块并发写入
  Future<void> _downloadMultiThread(
    Dio dio,
    String targetUrl,
    int totalSize,
    int threadCount,
    String savePath,
    String filename,
  ) async {
    final file = File(savePath);
    final raf = await file.open(mode: FileMode.write);
    await raf.truncate(totalSize);

    final chunkSize = (totalSize / threadCount).ceil();
    final downloadedPerThread = List<int>.filled(threadCount, 0);

    int lastDownloaded = 0;
    int lastTime = DateTime.now().millisecondsSinceEpoch;

    final timer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final currentDownloaded = downloadedPerThread.fold<int>(0, (a, b) => a + b);
      final elapsed = (now - lastTime) / 1000.0;
      int speed = 0;
      if (elapsed > 0) {
        speed = ((currentDownloaded - lastDownloaded) / elapsed).round();
      }
      lastDownloaded = currentDownloaded;
      lastTime = now;
      onProgress(currentDownloaded, totalSize, speed);
    });

    try {
      final futures = <Future<void>>[];
      for (int i = 0; i < threadCount; i++) {
        final start = i * chunkSize;
        final end = (i == threadCount - 1) ? totalSize - 1 : (i + 1) * chunkSize - 1;

        futures.add(() async {
          final token = CancelToken();
          _cancelTokens.add(token);

          final resp = await dio.get<ResponseBody>(
            targetUrl,
            cancelToken: token,
            options: Options(
              responseType: ResponseType.stream,
              headers: {'Range': 'bytes=$start-$end'},
            ),
          );

          var writeOffset = start;
          await for (final chunk in resp.data!.stream) {
            if (_isCanceled) return;
            // 写入分块
            await raf.setPosition(writeOffset);
            await raf.writeFrom(chunk);
            writeOffset += chunk.length;
            downloadedPerThread[i] += chunk.length;
          }
        }());
      }

      await Future.wait(futures);
      timer.cancel();
      await raf.close();

      if (!_isCanceled) {
        onComplete(filename, savePath);
      }
    } catch (e) {
      timer.cancel();
      await raf.close();
      rethrow;
    }
  }

  /// 单线程平滑流式下载（动态 PHP 附件或不支持 Range 时）
  Future<void> _downloadSingleThread(
    Dio dio,
    String targetUrl,
    int totalSize,
    String savePath,
    String filename,
  ) async {
    final file = File(savePath);
    final sink = file.openWrite();

    int downloaded = 0;
    int lastDownloaded = 0;
    int lastTime = DateTime.now().millisecondsSinceEpoch;
    int resolvedTotalSize = totalSize;

    final token = CancelToken();
    _cancelTokens.add(token);

    final timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = (now - lastTime) / 1000.0;
      int speed = 0;
      if (elapsed > 0) {
        speed = ((downloaded - lastDownloaded) / elapsed).round();
      }
      lastDownloaded = downloaded;
      lastTime = now;
      final currentTotal = resolvedTotalSize > 0 ? resolvedTotalSize : downloaded;
      onProgress(downloaded, currentTotal, speed);
    });

    try {
      final resp = await dio.get<ResponseBody>(
        targetUrl,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Referer': 'https://klpbbs.com/forum.php'},
        ),
      );

      final cl = resp.headers.value('content-length');
      if (cl != null) {
        final l = int.tryParse(cl);
        if (l != null && l > 0) {
          resolvedTotalSize = l;
        }
      }

      await for (final chunk in resp.data!.stream) {
        if (_isCanceled) break;
        sink.add(chunk);
        downloaded += chunk.length;
      }

      await sink.flush();
      await sink.close();
      timer.cancel();

      if (!_isCanceled) {
        onComplete(filename, savePath);
      }
    } catch (e) {
      timer.cancel();
      await sink.close();
      rethrow;
    }
  }
}
