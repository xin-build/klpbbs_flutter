import 'package:flutter/material.dart';

/// 精简 B 站播放模型
class BiliVideoInfo {
  final String bvid;
  final int cid;
  final int aid;
  final String title;
  final String cover;
  const BiliVideoInfo({
    required this.bvid,
    required this.cid,
    this.aid = 0,
    this.title = '',
    this.cover = '',
  });
}

class BiliDashItem {
  final int id;
  final String baseUrl;
  final int bandwidth;
  final String codecs;
  const BiliDashItem({
    required this.id,
    this.baseUrl = '',
    this.bandwidth = 0,
    this.codecs = '',
  });
}

class BiliPlayUrlData {
  final List<BiliDashItem> videos;
  final List<BiliDashItem> audios;
  final List<int> acceptQuality;
  const BiliPlayUrlData({
    this.videos = const [],
    this.audios = const [],
    this.acceptQuality = const [],
  });

  /// 针对指定清晰度 ID，优先选择兼容性最强的 AVC/H.264 编码，避免 Windows ANGLE/DirectX 硬件解码失败出现灰绿块
  BiliDashItem? getBestVideoForQuality(int id) {
    final matches = videos.where((e) => e.id == id).toList();
    if (matches.isEmpty) return null;
    final avc = matches.where((v) => v.codecs.toLowerCase().startsWith('avc1'));
    if (avc.isNotEmpty) return avc.first;
    final hevc = matches.where((v) => v.codecs.toLowerCase().startsWith('hev1'));
    if (hevc.isNotEmpty) return hevc.first;
    return matches.first;
  }

  /// 优先最高清晰度且硬件兼容性最稳定的 AVC 视频流
  BiliDashItem? get bestVideo {
    if (videos.isEmpty) return null;
    final topQuality = videos.first.id;
    return getBestVideoForQuality(topQuality) ?? videos.first;
  }

  BiliDashItem? get bestAudio => audios.isNotEmpty ? audios.first : null;
}

/// 弹幕条目数据模型
class BiliDanmakuItem {
  final double time; // 出现秒数
  final int mode; // 1/2/3/6: 滚动, 4: 底部, 5: 顶部, 7: 高级
  final int size; // 字号
  final int color; // 颜色 0xRRGGBB
  final String text; // 弹幕文字
  final String dmid; // 弹幕唯一 ID
  int track; // 分配的轨道索引

  BiliDanmakuItem({
    required this.time,
    required this.mode,
    required this.size,
    required this.color,
    required this.text,
    required this.dmid,
    this.track = 0,
  });

  bool get isScroll => mode == 1 || mode == 2 || mode == 3 || mode == 6;
  bool get isTop => mode == 5;
  bool get isBottom => mode == 4;
  bool get isColor => (color & 0xFFFFFF) != 0xFFFFFF && (color & 0xFFFFFF) != 0;

  Color get displayColor {
    final rgb = color & 0xFFFFFF;
    if (rgb == 0 || rgb == 0xFFFFFF) return Colors.white;
    return Color(0xFF000000 | rgb);
  }
}

/// 弹幕配置与屏蔽规则
class BiliDanmakuConfig {
  bool enabled;
  double opacity;
  double fontSize;
  double speed;
  double area; // 0.25, 0.5, 0.75, 1.0
  bool hideTop;
  bool hideBottom;
  bool hideScroll;
  bool hideColor;
  List<String> blockedKeywords;

  BiliDanmakuConfig({
    this.enabled = true,
    this.opacity = 0.85,
    this.fontSize = 14.0,
    this.speed = 1.0,
    this.area = 0.5,
    this.hideTop = false,
    this.hideBottom = false,
    this.hideScroll = false,
    this.hideColor = false,
    List<String>? blockedKeywords,
  }) : blockedKeywords = blockedKeywords ?? [];

  BiliDanmakuConfig clone() {
    return BiliDanmakuConfig(
      enabled: enabled,
      opacity: opacity,
      fontSize: fontSize,
      speed: speed,
      area: area,
      hideTop: hideTop,
      hideBottom: hideBottom,
      hideScroll: hideScroll,
      hideColor: hideColor,
      blockedKeywords: List<String>.from(blockedKeywords),
    );
  }

  /// 判断指定弹幕是否被当前配置屏蔽
  bool isBlocked(BiliDanmakuItem item) {
    if (hideTop && item.isTop) return true;
    if (hideBottom && item.isBottom) return true;
    if (hideScroll && item.isScroll) return true;
    if (hideColor && item.isColor) return true;

    final lowerText = item.text.toLowerCase();
    for (final kw in blockedKeywords) {
      final trimmed = kw.trim().toLowerCase();
      if (trimmed.isEmpty) continue;
      if (lowerText.contains(trimmed)) return true;
    }
    return false;
  }
}

/// 字幕元信息模型
class BiliSubtitleMeta {
  final int id;
  final String lan;
  final String lanDoc;
  final String subtitleUrl;
  final int type; // 0: CC, 1: AI
  final int aiType;
  final int aiStatus;

  const BiliSubtitleMeta({
    required this.id,
    required this.lan,
    required this.lanDoc,
    required this.subtitleUrl,
    this.type = 0,
    this.aiType = 0,
    this.aiStatus = 0,
  });

  bool get isAi => type == 1 || aiType > 0 || aiStatus > 0;
}

/// 单句字幕模型
class BiliSubtitleLine {
  final double from;
  final double to;
  final String content;
  String? translation;

  BiliSubtitleLine({
    required this.from,
    required this.to,
    required this.content,
    this.translation,
  });
}
