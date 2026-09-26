import 'dart:convert';
import 'package:dio/dio.dart';

/// 论坛服务端故障/网关异常信息模型（1:1 适配 Klpbbs 网关 502/503/504 等故障页）
class ServerOutageInfo {
  final int statusCode;
  final String statusMessage;
  final String badgeText;
  final String title;
  final String subtitleZh;
  final String descZh;
  final String descEn;
  final String clientIp;
  final String clientStatus;
  final String gatewayStatus;
  final String originStatus;
  final String originDetail;
  final String requestId;
  final String? datacenter;
  final String? serverEngine;
  final String? requestUrl;
  final Map<String, List<String>>? headers;
  final String? rawHtml;
  final DateTime timestamp;

  const ServerOutageInfo({
    required this.statusCode,
    this.statusMessage = 'Bad Gateway',
    required this.badgeText,
    required this.title,
    required this.subtitleZh,
    required this.descZh,
    required this.descEn,
    required this.clientIp,
    this.clientStatus = 'CONNECTED',
    this.gatewayStatus = 'FORWARDED',
    required this.originStatus,
    required this.originDetail,
    required this.requestId,
    this.datacenter,
    this.serverEngine,
    this.requestUrl,
    this.headers,
    this.rawHtml,
    required this.timestamp,
  });

  /// 检查 HTML 文本是否包含网关报错特征
  static bool isOutageHtml(String html) {
    if (html.isEmpty) return false;
    final lower = html.toLowerCase();
    return lower.contains('bad upstream response') ||
        lower.contains('源站返回了无法解析的响应') ||
        lower.contains('bad gateway') ||
        lower.contains('连接被拒绝或响应异常') ||
        lower.contains('gateway time-out') ||
        lower.contains('gateway timeout') ||
        lower.contains('service temporarily unavailable') ||
        lower.contains('web server is down') ||
        lower.contains('origin is unreachable') ||
        lower.contains('error 502') ||
        lower.contains('error 504') ||
        lower.contains('error 521') ||
        lower.contains('error 522') ||
        lower.contains('error 523') ||
        (html.contains('502') && (html.contains('Gateway') || html.contains('gateway')));
  }

  /// 检查 HTTP 状态码是否属于服务器端/网关宕机故障
  static bool isOutageStatusCode(int? code) {
    if (code == null) return false;
    return code == 502 ||
        code == 503 ||
        code == 504 ||
        code == 500 ||
        (code >= 520 && code <= 524);
  }

  /// 检查 DioException 是否属于服务端故障
  static bool isOutageDioException(DioException e) {
    final code = e.response?.statusCode;
    if (isOutageStatusCode(code)) return true;

    final data = e.response?.data;
    if (data is List<int>) {
      try {
        final decoded = utf8.decode(data, allowMalformed: true);
        if (isOutageHtml(decoded)) return true;
      } catch (_) {}
    } else if (data is String) {
      if (isOutageHtml(data)) return true;
    }

    final msg = e.message ?? '';
    return isOutageHtml(msg);
  }

  /// 从 HTML 与 HTTP 响应头深度解析故障诊断信息
  factory ServerOutageInfo.fromHtml(
    String html, {
    int? statusCode,
    String? statusMessage,
    String? requestUrl,
    Map<String, List<String>>? headers,
  }) {
    // 1. 状态码推导
    int code = statusCode ?? 502;
    if (code < 400 || code == 200) {
      final codeMatch = RegExp(r'<h1[^>]*>\s*(\d{3})\s*</h1>').firstMatch(html) ??
          RegExp(r'\b(502|503|504|520|521|522|523|524|500)\b').firstMatch(html);
      if (codeMatch != null) {
        code = int.tryParse(codeMatch.group(1) ?? '') ?? 502;
      }
    }

    // 辅助函数：不区分大小写匹配响应头
    String? getHeader(String name) {
      if (headers == null) return null;
      final target = name.toLowerCase();
      for (final e in headers.entries) {
        if (e.key.toLowerCase() == target) {
          return e.value.firstOrNull;
        }
      }
      return null;
    }

    // 2. Request ID 与 数据中心提取
    String? reqId;
    String? datacenter;
    final rayHeader = getHeader('cf-ray') ??
        getHeader('x-request-id') ??
        getHeader('x-edge-request-id');

    if (rayHeader != null && rayHeader.isNotEmpty) {
      if (rayHeader.contains('-')) {
        final parts = rayHeader.split('-');
        reqId = parts.first.trim();
        datacenter = parts.sublist(1).join('-').trim();
      } else {
        reqId = rayHeader.trim();
      }
    }

    if (reqId == null || reqId.isEmpty) {
      final cfRayMatch = RegExp(
        r'Cloudflare\s*Ray\s*ID:\s*(?:<[^>]+>)*([a-zA-Z0-9_\-\.]+)',
        caseSensitive: false,
      ).firstMatch(html);
      if (cfRayMatch != null) {
        final fullRay = cfRayMatch.group(1)?.trim();
        if (fullRay != null && fullRay.contains('-')) {
          final parts = fullRay.split('-');
          reqId = parts.first.trim();
          datacenter ??= parts.sublist(1).join('-').trim();
        } else {
          reqId = fullRay;
        }
      } else {
        final reqMatch = RegExp(
          r'Request\s*ID[:\s]+([a-zA-Z0-9_\-\.]+)',
          caseSensitive: false,
        ).firstMatch(html) ??
            RegExp(
              r'Ray\s*ID[:\s]+([a-zA-Z0-9_\-\.]+)',
              caseSensitive: false,
            ).firstMatch(html);
        if (reqMatch != null) {
          reqId = reqMatch.group(1)?.trim();
        }
      }
    }
    reqId ??= '${DateTime.now().millisecondsSinceEpoch}000023';

    // 3. 客户端 IP 提取
    String? clientIp = getHeader('cf-connecting-ip') ??
        getHeader('x-real-ip') ??
        getHeader('x-forwarded-for')?.split(',').firstOrNull?.trim();
    if (clientIp == null || clientIp.isEmpty) {
      final ipMatch = RegExp(
        r'Your\s*IP:\s*(?:<[^>]+>)*([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})',
        caseSensitive: false,
      ).firstMatch(html) ??
          RegExp(
            r'客户端\s*Client[\s\S]*?(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})',
          ).firstMatch(html) ??
          RegExp(
            r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})[\s\S]*?CONNECTED',
          ).firstMatch(html);
      if (ipMatch != null) {
        clientIp = ipMatch.group(1)?.trim();
      }
    }
    clientIp ??= '当前设备 / 本机网络';

    // 4. 服务端引擎
    final serverEngine = getHeader('server') ?? (html.contains('cloudflare') ? 'Cloudflare' : null);

    // 5. 根据错误码生成默认模板，并用 HTML 内提取的实际文字补充
    final template = _getTemplateByCode(code);

    return ServerOutageInfo(
      statusCode: code,
      statusMessage: statusMessage ?? (code == 502 ? 'Bad Gateway' : 'Server Outage'),
      badgeText: template.badgeText,
      title: template.title,
      subtitleZh: template.subtitleZh,
      descZh: template.descZh,
      descEn: template.descEn,
      clientIp: clientIp,
      clientStatus: 'CONNECTED',
      gatewayStatus: 'FORWARDED',
      originStatus: template.originStatus,
      originDetail: template.originDetail,
      requestId: reqId,
      datacenter: datacenter,
      serverEngine: serverEngine,
      requestUrl: requestUrl,
      headers: headers,
      rawHtml: html,
      timestamp: DateTime.now(),
    );
  }

  /// 从 DioException 深度解析构建故障模型
  factory ServerOutageInfo.fromDioException(DioException e) {
    final code = e.response?.statusCode ?? 502;
    String html = '';
    final data = e.response?.data;
    if (data is List<int>) {
      try {
        html = utf8.decode(data, allowMalformed: true);
      } catch (_) {}
    } else if (data is String) {
      html = data;
    } else if (e.message != null) {
      html = e.message!;
    }

    final reqUrl = e.requestOptions.uri.toString();
    final statusMsg = e.response?.statusMessage ?? 'Bad Gateway';

    return ServerOutageInfo.fromHtml(
      html,
      statusCode: code,
      statusMessage: statusMsg,
      requestUrl: reqUrl,
      headers: e.response?.headers.map,
    );
  }

  /// 通用安全探测解析：支持 ServerOutageException、DioException、String、Exception
  static ServerOutageInfo? tryParse(dynamic error) {
    if (error == null) return null;
    if (error is ServerOutageException) {
      return error.info;
    }
    if (error is DioException) {
      if (error.error is ServerOutageException) {
        return (error.error as ServerOutageException).info;
      }
      if (isOutageDioException(error)) {
        return ServerOutageInfo.fromDioException(error);
      }
      final code = error.response?.statusCode;
      if (code != null && code >= 500 && code <= 599) {
        return ServerOutageInfo.fromDioException(error);
      }
      return null;
    }

    final str = error.toString();
    final lower = str.toLowerCase();
    if (isOutageHtml(str) ||
        str.contains('502') ||
        str.contains('503') ||
        str.contains('504') ||
        str.contains('520') ||
        str.contains('521') ||
        str.contains('522') ||
        lower.contains('bad gateway') ||
        lower.contains('bad upstream') ||
        (lower.contains('bad response') && (str.contains('50') || str.contains('52')))) {
      int code = 502;
      final m = RegExp(r'\b(502|503|504|520|521|522|523|524|500)\b').firstMatch(str);
      if (m != null) {
        code = int.tryParse(m.group(1) ?? '') ?? 502;
      }
      return ServerOutageInfo.fromHtml(str, statusCode: code);
    }

    return null;
  }

  static ({
    String badgeText,
    String title,
    String subtitleZh,
    String descZh,
    String descEn,
    String originStatus,
    String originDetail,
  }) _getTemplateByCode(int code) {
    switch (code) {
      case 504:
        return (
          badgeText: 'GATEWAY TIMEOUT',
          title: 'Gateway Timeout',
          subtitleZh: '源站响应超时',
          descZh: '网关在等待源站响应时超时。常见原因是源站负载过高、数据库复杂查询卡死或网络中继超时。',
          descEn:
              'The gateway did not receive a timely response from the upstream server. The origin may be overloaded or timing out on heavy queries.',
          originStatus: 'TIMEOUT',
          originDetail: '源站网关响应超时 / gateway timeout',
        );
      case 503:
        return (
          badgeText: 'SERVICE UNAVAILABLE',
          title: 'Service Unavailable',
          subtitleZh: '服务暂时不可用',
          descZh: '源站服务器目前无法处理请求，可能正在临时维护或突发流量过载。请稍后刷新重试。',
          descEn:
              'The server is currently unable to handle the request due to maintenance or overload. Please try again later.',
          originStatus: 'UNAVAILABLE',
          originDetail: '源站服务临时过载或维护 / service temporarily unavailable',
        );
      case 521:
      case 522:
      case 523:
        return (
          badgeText: 'ORIGIN UNREACHABLE',
          title: 'Web Server Is Down',
          subtitleZh: '无法连接到源站服务器',
          descZh: '网关或边缘节点无法与源站建立 TCP 连接。源站服务器可能已关机、网络路由受阻或服务崩溃。',
          descEn:
              'The edge gateway could not connect to the origin web server. The server may be offline or unreachable.',
          originStatus: 'CONNECTION REFUSED',
          originDetail: '源站连接被拒绝或网络不可达 / origin unreachable',
        );
      case 500:
        return (
          badgeText: 'INTERNAL SERVER ERROR',
          title: 'Internal Server Error',
          subtitleZh: '服务器内部错误',
          descZh: 'Discuz! 核心逻辑或数据库在处理请求时抛出致命异常。',
          descEn:
              'The server encountered an internal error and was unable to complete your request.',
          originStatus: 'CRASHED',
          originDetail: '数据库或后端脚本致命异常 / internal server error',
        );
      case 502:
      default:
        return (
          badgeText: 'BAD UPSTREAM RESPONSE',
          title: 'Bad Gateway',
          subtitleZh: '源站返回了无法解析的响应',
          descZh:
              '网关已经连接到源站，但收到的响应无效——连接被拒绝、中途断开，或者返回的内容不符合 HTTP 协议。常见原因是源站服务已崩溃、端口没有监听，或反向代理指向了错误的后端。',
          descEn:
              'The gateway reached the origin server but got back an invalid response. The origin may be down, refusing connections, or misconfigured.',
          originStatus: 'INVALID REPLY',
          originDetail: '连接被拒绝或响应异常 / bad gateway response',
        );
    }
  }

  /// 导出完整格式化诊断日志（供一键复制到剪贴板）
  String toDiagnosticReport() {
    final sb = StringBuffer();
    sb.writeln('=== Klpbbs 故障诊断报告 ===');
    sb.writeln('时间: ${timestamp.toIso8601String()}');
    sb.writeln('状态码: $statusCode ($title)');
    if (requestUrl != null && requestUrl!.isNotEmpty) {
      sb.writeln('请求地址: $requestUrl');
    }
    sb.writeln('Request / Ray ID: $requestId');
    if (datacenter != null && datacenter!.isNotEmpty) {
      sb.writeln('边缘数据中心: $datacenter');
    }
    if (serverEngine != null && serverEngine!.isNotEmpty) {
      sb.writeln('网关服务器: $serverEngine');
    }
    sb.writeln('客户端 IP: $clientIp [$clientStatus]');
    sb.writeln('网关状态: [$gatewayStatus]');
    sb.writeln('源站状态: [$originStatus] $originDetail');
    sb.writeln('详细说明: $subtitleZh');
    if (headers != null && headers!.isNotEmpty) {
      sb.writeln('--- 关键响应头 ---');
      headers!.forEach((k, v) {
        final lk = k.toLowerCase();
        if (lk == 'cf-ray' ||
            lk == 'cf-connecting-ip' ||
            lk == 'server' ||
            lk == 'date' ||
            lk == 'content-type') {
          sb.writeln('$k: ${v.join(", ")}');
        }
      });
    }
    sb.writeln('===========================');
    return sb.toString();
  }
}

/// 服务端故障专属异常
class ServerOutageException implements Exception {
  final ServerOutageInfo info;

  const ServerOutageException(this.info);

  @override
  String toString() =>
      'ServerOutageException [${info.statusCode} ${info.title}]: ${info.subtitleZh} (Request ID: ${info.requestId})';
}
