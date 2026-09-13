import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bili_models.dart';

/// B 站只读播放地址 API（免登录 1080p MCP）
abstract final class BiliApi {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.bilibili.com',
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com',
      },
    ),
  );

  static const _mixinKeyEncTab = <int>[
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
  ];

  static String? _cachedKey;
  static DateTime? _cachedDay;

  static String getMixinKey(String orig) {
    final codeUnits = orig.codeUnits;
    return String.fromCharCodes(_mixinKeyEncTab.map((i) => codeUnits[i]));
  }

  static String _fileName(String url, {bool fileExt = false}) {
    final name = url.split('/').last;
    if (fileExt) return name;
    final idx = name.lastIndexOf('.');
    return idx > 0 ? name.substring(0, idx) : name;
  }

  static void encWbi(Map<String, Object> params, String mixinKey) {
    params['wts'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final keys = params.keys.toList()..sort();
    final queryStr = keys
        .map(
          (i) =>
              '${Uri.encodeComponent(i)}=${Uri.encodeComponent(params[i].toString().replaceAll(RegExp(r"[!'\(\)\*]"), ''))}',
        )
        .join('&');
    params['w_rid'] = md5.convert(utf8.encode('$queryStr$mixinKey')).toString();
  }

  static Future<String> _getWbiKeys() async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    if (_cachedKey != null && _cachedDay == day) return _cachedKey!;
    try {
      final resp = await _dio.get('/x/web-interface/nav');
      final img = resp.data['data']['wbi_img']['img_url'] as String;
      final sub = resp.data['data']['wbi_img']['sub_url'] as String;
      final mixinKey = getMixinKey(_fileName(img) + _fileName(sub));
      _cachedKey = mixinKey;
      _cachedDay = day;
      final sp = await SharedPreferences.getInstance();
      await sp.setString('bili_mixin_key', mixinKey);
      await sp.setString('bili_mixin_day', day.toIso8601String());
      return mixinKey;
    } catch (_) {
      return '';
    }
  }

  static Future<BiliVideoInfo?> videoIntro(String bvid) async {
    try {
      final resp = await _dio.get(
        '/x/web-interface/view',
        queryParameters: {'bvid': bvid},
      );
      final data = resp.data['data'];
      if (data == null) return null;
      return BiliVideoInfo(
        bvid: bvid,
        cid: (data['cid'] as num?)?.toInt() ?? 0,
        aid: (data['aid'] as num?)?.toInt() ?? 0,
        title: data['title']?.toString() ?? '',
        cover: data['pic']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<BiliPlayUrlData?> videoUrl(
    String bvid,
    int cid, {
    bool tryLook = true,
  }) async {
    try {
      final params = <String, Object>{
        'bvid': bvid,
        'cid': cid,
        'qn': 80,
        'fnval': 4048,
        'fourk': 1,
        'fnver': 0,
        'voice_balance': 0,
        'gaia_source': 'pre-load',
        'isGaiaAvoided': true,
        'web_location': 1315873,
        if (tryLook) 'try_look': 1,
        'dm_img_list': '[]',
        'dm_img_str': 'V2ViR0wgMS4w',
        'dm_cover_img_str': 'QU5HTEUg',
        'dm_img_inter': '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}',
      };
      final mixinKey = await _getWbiKeys();
      if (mixinKey.isNotEmpty) encWbi(params, mixinKey);
      final resp = await _dio.get(
        '/x/player/wbi/playurl',
        queryParameters: params,
      );
      final data = resp.data['data'];
      if (data == null) return null;
      final dash = data['dash'];
      if (dash != null) {
        final videos = <BiliDashItem>[];
        for (final v in (dash['video'] as List? ?? const [])) {
          videos.add(
            BiliDashItem(
              id: (v['id'] as num?)?.toInt() ?? 0,
              baseUrl: v['baseUrl']?.toString() ?? '',
              bandwidth: (v['bandwidth'] as num?)?.toInt() ?? 0,
              codecs: v['codecs']?.toString() ?? '',
            ),
          );
        }
        final audios = <BiliDashItem>[];
        for (final a in (dash['audio'] as List? ?? const [])) {
          audios.add(
            BiliDashItem(
              id: (a['id'] as num?)?.toInt() ?? 0,
              baseUrl: a['baseUrl']?.toString() ?? '',
              bandwidth: (a['bandwidth'] as num?)?.toInt() ?? 0,
              codecs: a['codecs']?.toString() ?? '',
            ),
          );
        }
        return BiliPlayUrlData(
          videos: videos,
          audios: audios,
          acceptQuality: (data['accept_quality'] as List? ?? const [])
              .map((e) => (e as num).toInt())
              .toList(),
        );
      }
      final durl = data['durl'];
      if (durl is List && durl.isNotEmpty) {
        return BiliPlayUrlData(
          videos: [
            BiliDashItem(
              id: (data['quality'] as num?)?.toInt() ?? 0,
              baseUrl: durl.first['url']?.toString() ?? '',
            ),
          ],
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 获取 B 站视频多语言与 AI 字幕列表
  static Future<List<BiliSubtitleMeta>> fetchSubtitles(int aid, int cid) async {
    final list = <BiliSubtitleMeta>[];
    try {
      // 优先从 dm/view 接口获取全部字幕（包括 AI 识别字幕）
      final resp = await _dio.get(
        '/x/v2/dm/view',
        queryParameters: {
          'aid': aid,
          'oid': cid,
          'type': 1,
        },
      );
      final subtitleData = resp.data?['data']?['subtitle'];
      if (subtitleData is Map) {
        final subs = subtitleData['subtitles'] as List? ?? const [];
        for (final s in subs) {
          if (s is Map) {
            var url = s['subtitle_url']?.toString() ?? '';
            if (url.startsWith('//')) url = 'https:$url';
            if (url.isNotEmpty) {
              list.add(
                BiliSubtitleMeta(
                  id: (s['id'] as num?)?.toInt() ?? 0,
                  lan: s['lan']?.toString() ?? '',
                  lanDoc: s['lan_doc']?.toString() ?? '',
                  subtitleUrl: url,
                  type: (s['type'] as num?)?.toInt() ?? 0,
                  aiType: (s['ai_type'] as num?)?.toInt() ?? 0,
                  aiStatus: (s['ai_status'] as num?)?.toInt() ?? 0,
                ),
              );
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  /// 获取特定语言的逐句字幕数据
  static Future<List<BiliSubtitleLine>> fetchSubtitleContent(String url) async {
    final list = <BiliSubtitleLine>[];
    try {
      var fetchUrl = url;
      if (fetchUrl.startsWith('//')) fetchUrl = 'https:$fetchUrl';
      final resp = await _dio.get(fetchUrl);
      var data = resp.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }
      if (data is Map) {
        final body = data['body'] as List? ?? const [];
        for (final item in body) {
          if (item is Map) {
            final from = (item['from'] as num?)?.toDouble() ?? 0.0;
            final to = (item['to'] as num?)?.toDouble() ?? 0.0;
            final content = item['content']?.toString() ?? '';
            if (content.trim().isNotEmpty) {
              list.add(BiliSubtitleLine(from: from, to: to, content: content.trim()));
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  /// 获取实时弹幕列表（免登录极速 XML 通道）
  static Future<List<BiliDanmakuItem>> fetchDanmaku(int cid) async {
    final list = <BiliDanmakuItem>[];
    try {
      final resp = await _dio.get<List<int>>(
        'https://comment.bilibili.com/$cid.xml',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Accept-Encoding': 'deflate, gzip'},
        ),
      );
      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) return list;

      List<int> unpacked;
      try {
        unpacked = ZLibDecoder(raw: true).convert(bytes);
      } catch (_) {
        try {
          unpacked = zlib.decode(bytes);
        } catch (_) {
          try {
            unpacked = gzip.decode(bytes);
          } catch (_) {
            unpacked = bytes;
          }
        }
      }

      String xmlStr;
      try {
        xmlStr = utf8.decode(unpacked);
      } catch (_) {
        xmlStr = String.fromCharCodes(unpacked);
      }

      final matches = RegExp(r'<d p="([^"]+)">([^<]*)</d>').allMatches(xmlStr);
      for (final m in matches) {
        final p = m.group(1)?.split(',') ?? [];
        if (p.length >= 5) {
          final time = double.tryParse(p[0]) ?? 0.0;
          final mode = int.tryParse(p[1]) ?? 1;
          final size = int.tryParse(p[2]) ?? 25;
          final color = int.tryParse(p[3]) ?? 0xFFFFFF;
          final dmid = p.length > 7 ? p[7] : '';
          final text = m.group(2)?.trim() ?? '';
          if (text.isNotEmpty) {
            list.add(
              BiliDanmakuItem(
                time: time,
                mode: mode,
                size: size,
                color: color,
                text: text,
                dmid: dmid,
              ),
            );
          }
        }
      }
      list.sort((a, b) => a.time.compareTo(b.time));
    } catch (_) {}
    return list;
  }

  static final Map<String, String> _transCache = {};

  /// 字幕在线自动翻译（Google GTX 通道 + 内存缓存）
  static Future<String?> translateText(String text, {String targetLang = 'zh-CN'}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final cacheKey = '$targetLang:$trimmed';
    if (_transCache.containsKey(cacheKey)) return _transCache[cacheKey];

    try {
      final url =
          'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$targetLang&dt=t&q=${Uri.encodeComponent(trimmed)}';
      final resp = await _dio.get(url);
      final data = resp.data;
      if (data is List && data.isNotEmpty && data[0] is List) {
        final buffer = StringBuffer();
        for (final item in data[0] as List) {
          if (item is List && item.isNotEmpty) {
            buffer.write(item[0]?.toString() ?? '');
          }
        }
        final result = buffer.toString().trim();
        if (result.isNotEmpty) {
          _transCache[cacheKey] = result;
          return result;
        }
      }
    } catch (_) {}
    return null;
  }
}
