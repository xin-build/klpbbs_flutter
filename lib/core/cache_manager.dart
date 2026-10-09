import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

/// 具有健全性校验的安全 HTTP 文件拉取服务
/// 严禁将 0 字节、HTML 报错页或损坏的非图片数据写入磁盘持久化缓存
class SafeHttpFileService extends FileService {
  final http.Client _httpClient;

  SafeHttpFileService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    // 0. 拒绝缓存默认头像与空白占位图（节约磁盘空间与网络开销，本地矢量优先）
    final lower = url.toLowerCase();
    if (lower.contains('noavatar') ||
        lower.contains('none.png') ||
        lower.contains('none.gif') ||
        lower.contains('spacer.gif') ||
        lower.contains('static/image/common/none')) {
      throw HttpExceptionWithStatus(
        200,
        'Default avatar or spacer ignored from cache',
        uri: Uri.parse(url),
      );
    }

    final effectiveHeaders = Map<String, String>.from(headers ?? {});
    // 若未传入鉴权头，且为论坛图片，自动补全规范防盗链与会话 Cookie
    if (!effectiveHeaders.containsKey('User-Agent')) {
      effectiveHeaders.addAll(AppConfig.imageHeadersFor(url));
    }
    // 旧调用方可能传入主站的通用请求头，Cookie 仍需按目标图片域名与路径筛选。
    for (final name in effectiveHeaders.keys
        .where((name) => name.toLowerCase() == 'cookie')
        .toList()) {
      effectiveHeaders.remove(name);
    }
    final scopedCookie = AppConfig.imageHeadersFor(url)['Cookie'];
    if (scopedCookie != null && scopedCookie.isNotEmpty) {
      effectiveHeaders['Cookie'] = scopedCookie;
    }

    final uri = Uri.tryParse(url) ?? Uri.parse(Uri.encodeFull(url));
    final req = http.Request('GET', uri);
    req.headers.addAll(effectiveHeaders);

    final httpResponse = await _httpClient.send(req);

    // 1. 若重定向至默认头像或占位图，坚决不写入持久化缓存
    final redirectedUrl =
        httpResponse.request?.url.toString().toLowerCase() ?? '';
    if (redirectedUrl.contains('noavatar') ||
        redirectedUrl.contains('none.gif') ||
        redirectedUrl.contains('none.png') ||
        redirectedUrl.contains('spacer.gif')) {
      throw HttpExceptionWithStatus(
        200,
        'Redirected to default avatar/spacer, ignored from cache',
        uri: Uri.parse(url),
      );
    }

    // 图片大小、ETag 时间戳不能区分默认头像与自定义 GIF/APNG。
    // 仅按明确的占位图 URL 排除默认头像，保留服务器返回的原始图片。
    // 若服务端返回 200 但明确声明 Content-Length 为 0，拒收且不写入缓存。
    if (httpResponse.statusCode == 200 && httpResponse.contentLength == 0) {
      throw HttpExceptionWithStatus(
        200,
        'Server returned empty body (0 bytes)',
        uri: Uri.parse(url),
      );
    }

    // 4. 若服务端返回 HTML 错误页面（如 Discuz 报错、502、网关拦截），坚决拒收
    final contentType =
        httpResponse.headers[HttpHeaders.contentTypeHeader]?.toLowerCase() ??
            '';
    if (contentType.contains('text/html') ||
        contentType.contains('text/plain')) {
      if (!url.toLowerCase().endsWith('.svg') &&
          !contentType.contains('image/svg')) {
        throw HttpExceptionWithStatus(
          200,
          'Server returned non-image content-type: $contentType',
          uri: Uri.parse(url),
        );
      }
    }

    return SafeHttpGetResponse(httpResponse, url);
  }
}

/// 包装 HttpGetResponse，在数据流完全拉取时检查真实总字节数，
/// 严防 chunked 传输下实际下发 0 字节内容或默认头像被误判为有效图片写入磁盘
class SafeHttpGetResponse extends HttpGetResponse {
  final String _reqUrl;

  SafeHttpGetResponse(super.response, this._reqUrl);

  @override
  Stream<List<int>> get content async* {
    var totalBytes = 0;
    final firstChunk = <int>[];

    await for (final chunk in super.content) {
      if (chunk.isNotEmpty) {
        totalBytes += chunk.length;
        if (firstChunk.length < 16) {
          firstChunk.addAll(chunk.take(16 - firstChunk.length));
        }
        yield chunk;
      }
    }

    // 若全流结束未收到任何字节，抛出异常阻断缓存持久化
    if (totalBytes == 0) {
      throw HttpExceptionWithStatus(
        200,
        'Stream completed with 0 bytes downloaded',
        uri: Uri.parse(_reqUrl),
      );
    }

    // 针对非图片特征（如开头为 <!DOCTYPE 或 <html）做二次拦截
    if (firstChunk.isNotEmpty && !_reqUrl.toLowerCase().endsWith('.svg')) {
      final headStr = String.fromCharCodes(firstChunk).toLowerCase().trim();
      if (headStr.startsWith('<!doc') ||
          headStr.startsWith('<html') ||
          headStr.startsWith('<?php')) {
        throw HttpExceptionWithStatus(
          200,
          'Downloaded content appears to be HTML/PHP, not image',
          uri: Uri.parse(_reqUrl),
        );
      }
    }
  }
}

/// 苦力怕论坛长期图片缓存管理器
/// 为头像、表情、挂件、勋章、论坛图章与高频帖子配图提供 7 天长期磁盘缓存与自动容量控制
class KlpbbsCacheManager {
  static const key = 'klpbbs_longterm_image_cache';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 400,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: SafeHttpFileService(),
    ),
  );

  /// 对 URL 进行规范化，使用安全哈希生成唯一缓存键（按哈希值检测是否为同一资源）：
  /// 1. 默认头像/空白占位图（noavatar/none.gif 等）返回空字符串，不产生磁盘缓存
  /// 2. 统一网络协议 http -> https
  /// 3. 滤除与资源内容无关的临时追踪/防盗链查询参数（_t, random, noupdate, timestamp 等）
  /// 4. 针对多镜像 CDN 统一主机名（如 ip.klpbbs.com -> klpbbs.com）
  /// 5. 最终通过 MD5 哈希生成标准安全键 klp_res_${md5}，彻底杜绝不同用户头像或不同尺寸资源的串号复用 bug
  static String normalizeCacheKey(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return '';
    var url = rawUrl.trim();

    final lower = url.toLowerCase();
    // 默认头像与占位图不参与缓存
    if (lower.contains('noavatar') ||
        lower.contains('none.gif') ||
        lower.contains('none.png') ||
        lower.contains('spacer.gif') ||
        lower.contains('static/image/common/none')) {
      return '';
    }

    // 统一协议
    if (url.startsWith('http://')) {
      url = 'https://${url.substring(7)}';
    }

    // 滤除无关动态查询参数与规整通用 URL
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final params = Map<String, String>.from(uri.queryParameters);
      const ephemeralKeys = {
        '_t',
        'random',
        'noupdate',
        'extra',
        'from',
        'ref',
        '_',
        't',
        'zoomfile',
        'lazyloadthumb',
        'mobile',
        'version',
      };
      var changed = false;
      for (final k in ephemeralKeys) {
        if (params.containsKey(k)) {
          params.remove(k);
          changed = true;
        }
      }
      var host = uri.host;
      if (host == 'www.klpbbs.com' || host == 'ip.klpbbs.com') {
        host = 'klpbbs.com';
        changed = true;
      }
      if (changed) {
        final sortedKeys = params.keys.toList()..sort();
        final newQuery = sortedKeys.map((k) => '$k=${params[k]}').join('&');
        url = uri
            .replace(
              host: host,
              query: newQuery.isNotEmpty ? newQuery : null,
            )
            .toString();
      }
    }

    // 生成基于规范化 URL 的唯一哈希键，绝对保证不同资源不发生冲突
    final hash = md5.convert(utf8.encode(url)).toString();
    return 'klp_res_$hash';
  }

  /// 智能清理：过期缓存、超容缓存、重复/坏块缓存一键清理与容量控制
  /// 1. 清理 0 字节、损坏的 HTML 错误页及临时文件
  /// 2. 清理明确包含 noavatar 命名的占位图；不按字节数误删自定义头像
  /// 3. 清理已超过 maxAge（默认 7 天）的过期缓存
  /// 4. 若总磁盘缓存超过 maxBytes（默认 200 MB），按 LRU（最后修改时间从旧到新）淘汰多余文件直到降至 targetBytes（默认 120 MB）
  /// 5. 同步修正 json 索引库，保持数据库与真实磁盘文件严格一致
  static Future<int> purgeExpiredAndOvercapacityCache({
    int maxBytes = 200 * 1024 * 1024,
    int targetBytes = 120 * 1024 * 1024,
    Duration maxAge = const Duration(days: 7),
  }) async {
    var freedBytes = 0;
    const keys = [key, 'libCachedImageData', 'cached_network_image_ce'];
    final now = DateTime.now();

    try {
      final tempDir = await getTemporaryDirectory();
      final supportDir = await getApplicationSupportDirectory();

      final validFiles =
          <({File file, int size, DateTime modified, String cacheKey})>[];

      for (final cacheKey in keys) {
        final cacheDir = Directory('${tempDir.path}/$cacheKey');
        if (await cacheDir.exists()) {
          await for (final entity in cacheDir.list(recursive: true)) {
            if (entity is File) {
              try {
                final stat = await entity.stat();
                final len = stat.size;
                final modified = stat.modified;
                final pathLower = entity.path.toLowerCase();

                final isCorrupt = len < 32 ||
                    pathLower.endsWith('.html') ||
                    pathLower.endsWith('.tmp') ||
                    pathLower.contains('noavatar') ||
                    pathLower.contains('avatar_uid_000') ||
                    pathLower.contains('avatar_uid_001');
                final isExpired = now.difference(modified) > maxAge;

                if (isCorrupt || isExpired) {
                  await entity.delete();
                  freedBytes += len;
                } else {
                  validFiles.add((
                    file: entity,
                    size: len,
                    modified: modified,
                    cacheKey: cacheKey,
                  ));
                }
              } catch (_) {}
            }
          }
        }
      }

      // 统计当前有效缓存总大小
      var currentTotalBytes = validFiles.fold<int>(0, (sum, f) => sum + f.size);

      // 若超过预设上限，按 LRU（最后修改时间升序）逐步清理淘汰
      if (currentTotalBytes > maxBytes) {
        validFiles.sort((a, b) => a.modified.compareTo(b.modified));
        for (final item in validFiles) {
          try {
            await item.file.delete();
            freedBytes += item.size;
            currentTotalBytes -= item.size;
            if (currentTotalBytes <= targetBytes) {
              break;
            }
          } catch (_) {}
        }
      }

      // 修正 JsonCacheInfoRepository 索引库
      for (final cacheKey in keys) {
        final jsonFile = File('${supportDir.path}/$cacheKey.json');
        final cacheDir = Directory('${tempDir.path}/$cacheKey');
        if (await jsonFile.exists()) {
          try {
            final content = await jsonFile.readAsString();
            final decoded = jsonDecode(content);
            if (decoded is List) {
              final originalLen = decoded.length;
              decoded.removeWhere((item) {
                if (item is Map) {
                  final k = (item['key'] as String?) ?? '';
                  // 坚决彻底清除旧版遗留的非哈希合成键（如 avatar_uid_000 导致的全员串号），杜绝坏缓存持续复用
                  if (k.startsWith('avatar_uid_') ||
                      k.startsWith('klpbbs_aid_') ||
                      k.startsWith('klpbbs_forum_') ||
                      k.startsWith('klpbbs_smiley_') ||
                      k.startsWith('klpbbs_medal_') ||
                      k.startsWith('klpbbs_stamp_') ||
                      k.startsWith('klpbbs_facemall_') ||
                      k.startsWith('klpbbs_magic_') ||
                      k.startsWith('klpbbs_homestyle_')) {
                    final relPath = item['relativePath'] as String?;
                    if (relPath != null) {
                      try {
                        final oldFile = File('${cacheDir.path}/$relPath');
                        if (oldFile.existsSync()) oldFile.deleteSync();
                      } catch (_) {}
                    }
                    return true;
                  }
                  final len = item['length'];
                  final relPath = item['relativePath'] as String?;
                  final targetFile = (relPath != null)
                      ? File('${cacheDir.path}/$relPath')
                      : null;
                  final fileMissing =
                      targetFile != null && !targetFile.existsSync();
                  final isBad = len == null ||
                      (len is num && len < 32) ||
                      (relPath != null &&
                          (relPath.toLowerCase().endsWith('.html') ||
                              relPath.toLowerCase().endsWith('.tmp') ||
                              relPath.toLowerCase().contains('noavatar'))) ||
                      fileMissing;
                  return isBad;
                }
                return false;
              });
              if (decoded.length != originalLen) {
                await jsonFile.writeAsString(jsonEncode(decoded));
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    return freedBytes;
  }

  /// 后台自动巡检与清理：限频 1 小时最多执行 1 次，严禁阻碍前台交互与滑动
  static DateTime? _lastAutoPurgeTime;
  static void autoPurgeInBackground() {
    final now = DateTime.now();
    if (_lastAutoPurgeTime != null &&
        now.difference(_lastAutoPurgeTime!).inMinutes < 60) {
      return;
    }
    _lastAutoPurgeTime = now;
    unawaited(purgeExpiredAndOvercapacityCache());
  }

  /// 清理磁盘与索引中已存在的损坏/0字节/HTML错误与过期超容缓存文件（自愈与瘦身）
  static Future<int> purgeCorruptedCache() async {
    return purgeExpiredAndOvercapacityCache();
  }

  /// 仅统计论坛专属持久化图片缓存（严禁全盘扫描系统 Temp 目录造成统计偏高与卡顿）
  static Future<int> calculateTotalCacheBytes() async {
    var totalBytes = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      final supportDir = await getApplicationSupportDirectory();
      const klpbbsCacheDirs = [
        key,
        'libCachedImageData',
        'cached_network_image_ce',
      ];

      for (final k in klpbbsCacheDirs) {
        final dir = Directory('${tempDir.path}/$k');
        if (await dir.exists()) {
          await for (final entity
              in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              try {
                totalBytes += await entity.length();
              } catch (_) {}
            }
          }
        }
        final f = File('${supportDir.path}/$k.json');
        if (await f.exists()) {
          try {
            totalBytes += await f.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return totalBytes;
  }

  /// 格式化缓存字节为人类可读字符串 (e.g. 58.6 MB, 420 KB)
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0.0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 0.1) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(1)} KB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// 彻底清空论坛全部持久化磁盘图片缓存、索引数据库与内存解码缓存
  static Future<int> clearEntireCache() async {
    final beforeBytes = await calculateTotalCacheBytes();
    try {
      await instance.emptyCache();
    } catch (_) {}
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}

    try {
      final tempDir = await getTemporaryDirectory();
      final supportDir = await getApplicationSupportDirectory();
      const klpbbsCacheDirs = [
        key,
        'libCachedImageData',
        'cached_network_image_ce',
      ];

      for (final k in klpbbsCacheDirs) {
        final dir = Directory('${tempDir.path}/$k');
        if (await dir.exists()) {
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        }
        final jsonF = File('${supportDir.path}/$k.json');
        if (await jsonF.exists()) {
          try {
            await jsonF.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}

    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    return beforeBytes;
  }
}
