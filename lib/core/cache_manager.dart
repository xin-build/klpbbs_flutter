import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    final effectiveHeaders = Map<String, String>.from(headers ?? {});
    // 若未传入鉴权头，且为论坛图片，自动补全规范防盗链与会话 Cookie
    if (!effectiveHeaders.containsKey('User-Agent')) {
      effectiveHeaders.addAll(AppConfig.imageHeadersFor(url));
    }

    final uri = Uri.tryParse(url) ?? Uri.parse(Uri.encodeFull(url));
    final req = http.Request('GET', uri);
    req.headers.addAll(effectiveHeaders);

    final httpResponse = await _httpClient.send(req);

    // 1. 若服务端返回 200 但明确声明 Content-Length 为 0，坚决拒收且不写入缓存
    if (httpResponse.statusCode == 200 && httpResponse.contentLength == 0) {
      throw HttpExceptionWithStatus(
        200,
        'Server returned empty body (0 bytes)',
        uri: Uri.parse(url),
      );
    }

    // 2. 若服务端返回 HTML 错误页面（如 Discuz 报错、502、网关拦截），坚决拒收
    final contentType = httpResponse.headers[HttpHeaders.contentTypeHeader]?.toLowerCase() ?? '';
    if (contentType.contains('text/html') || contentType.contains('text/plain')) {
      if (!url.toLowerCase().endsWith('.svg') && !contentType.contains('image/svg')) {
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
/// 严防 chunked 传输下实际下发 0 字节内容被误判为有效图片写入磁盘
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
      if (headStr.startsWith('<!doc') || headStr.startsWith('<html') || headStr.startsWith('<?php')) {
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
/// 为头像、表情、挂件、勋章、论坛图章与高频帖子配图提供 90 天长期磁盘缓存
class KlpbbsCacheManager {
  static const key = 'klpbbs_longterm_image_cache';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 90),
      maxNrOfCacheObjects: 3000,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: SafeHttpFileService(),
    ),
  );

  /// 清理磁盘与索引中已存在的损坏/0字节/HTML错误缓存文件（彻底自愈历史脏缓存）
  static Future<int> purgeCorruptedCache() async {
    var cleanedCount = 0;
    final keys = [key, 'libCachedImageData'];

    try {
      final tempDir = await getTemporaryDirectory();
      final supportDir = await getApplicationSupportDirectory();

      for (final cacheKey in keys) {
        final cacheDir = Directory('${tempDir.path}/$cacheKey');
        if (await cacheDir.exists()) {
          await for (final entity in cacheDir.list(recursive: true)) {
            if (entity is File) {
              try {
                final len = await entity.length();
                final pathLower = entity.path.toLowerCase();
                final isBad = len == 0 ||
                    len < 32 ||
                    pathLower.endsWith('.html') ||
                    pathLower.endsWith('.tmp');
                if (isBad) {
                  await entity.delete();
                  cleanedCount++;
                }
              } catch (_) {}
            }
          }
        }

        final jsonFile = File('${supportDir.path}/$cacheKey.json');
        if (await jsonFile.exists()) {
          try {
            final content = await jsonFile.readAsString();
            final decoded = jsonDecode(content);
            if (decoded is List) {
              final originalLen = decoded.length;
              decoded.removeWhere((item) {
                if (item is Map) {
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
                              relPath.toLowerCase().endsWith('.tmp'))) ||
                      fileMissing;
                  if (isBad) {
                    return true;
                  }
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

    return cleanedCount;
  }

  /// 统计磁盘持久化图片与数据缓存总字节数
  static Future<int> calculateTotalCacheBytes() async {
    var totalBytes = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              totalBytes += await entity.length();
            } catch (_) {}
          }
        }
      }
      final supportDir = await getApplicationSupportDirectory();
      if (await supportDir.exists()) {
        final cacheKeys = [key, 'libCachedImageData'];
        for (final k in cacheKeys) {
          final f = File('${supportDir.path}/$k.json');
          if (await f.exists()) {
            try {
              totalBytes += await f.length();
            } catch (_) {}
          }
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

  /// 彻底清空所有本地持久化磁盘图片缓存、临时目录、内存图片解码
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
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: false)) {
          try {
            await entity.delete(recursive: true);
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
