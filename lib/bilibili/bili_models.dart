/// 精简 B 站播放模型（仅 MCP 所需字段）
class BiliVideoInfo {
  final String bvid;
  final int cid;
  final String title;
  final String cover;
  const BiliVideoInfo({
    required this.bvid,
    required this.cid,
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

  BiliDashItem? get bestVideo => videos.isNotEmpty ? videos.first : null;
  BiliDashItem? get bestAudio => audios.isNotEmpty ? audios.first : null;
}
