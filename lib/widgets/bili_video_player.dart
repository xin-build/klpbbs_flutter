import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../bilibili/bili_api.dart';
import '../bilibili/bili_models.dart';

/// 内嵌 B 站播放器（免登录 1080p + 画质切换 + 封面预览）
class BiliVideoPlayer extends StatefulWidget {
  static final Map<String, Player> _players = {};
  static final Map<String, VideoController> _controllers = {};

  /// 退出帖子页时停止所有内嵌播放器
  static Future<void> stopAll() async {
    for (final p in _players.values) {
      await p.dispose();
    }
    _players.clear();
    _controllers.clear();
  }

  final String bvid;

  /// 是否在 build 前自动拉取封面/标题（widget 测试中应关闭，避免网络 Timer）
  final bool autoFetchPreview;
  const BiliVideoPlayer({
    super.key,
    required this.bvid,
    this.autoFetchPreview = true,
  });

  @override
  State<BiliVideoPlayer> createState() => _BiliVideoPlayerState();
}

class _BiliVideoPlayerState extends State<BiliVideoPlayer> {
  Player? _player;
  VideoController? _videoController;
  BiliVideoInfo? _info;
  BiliPlayUrlData? _data;
  BiliDashItem? _currentVideo;
  BiliDashItem? _currentAudio;

  bool _loading = false;
  bool _started = false;
  bool _playing = true;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  String? _error;

  double _speed = 1.0;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    final existingController = BiliVideoPlayer._controllers[widget.bvid];
    final existingPlayer = BiliVideoPlayer._players[widget.bvid];
    if (existingController != null && existingPlayer != null) {
      _videoController = existingController;
      _player = existingPlayer;
      _started = true;
      _playing = existingPlayer.state.playing;
      _speed = existingPlayer.state.rate;
    }
    if (widget.autoFetchPreview) {
      BiliApi.videoIntro(widget.bvid)
          .then((info) {
            if (mounted && info != null) setState(() => _info = info);
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  bool _isHoveringControls = false;
  bool _isDragging = false;

  void _showControlsTemporarily() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _hideTimer?.cancel();
    if (_isHoveringControls || _isDragging) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isHoveringControls && !_isDragging) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  String _edl(BiliDashItem video, BiliDashItem? audio) {
    if (audio == null || audio.baseUrl.isEmpty) return video.baseUrl;
    return 'edl://!no_clip;!no_chapters;'
        '%${video.baseUrl.length}%${video.baseUrl};'
        '!new_stream;!no_clip;!no_chapters;'
        '%${audio.baseUrl.length}%${audio.baseUrl}';
  }

  Map<String, String> get _headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Referer': 'https://www.bilibili.com',
  };

  Future<void> _start() async {
    if (_started || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = _info ?? await BiliApi.videoIntro(widget.bvid);
      if (info == null) {
        setState(() => _error = '未获取到视频信息');
        return;
      }
      _info = info;
      final data = _data ?? await BiliApi.videoUrl(widget.bvid, info.cid);
      if (data == null || data.bestVideo == null) {
        setState(() => _error = '未获取到播放地址（可能需要登录或已失效）');
        return;
      }
      _data = data;
      _currentVideo ??= data.bestVideo!;
      _currentAudio ??= data.bestAudio;

      final player = Player();
      final videoController = VideoController(player);
      await player.open(
        Media(_edl(_currentVideo!, _currentAudio), httpHeaders: _headers),
        play: true,
      );
      if (!mounted) {
        player.dispose();
        return;
      }
      BiliVideoPlayer._players[widget.bvid] = player;
      BiliVideoPlayer._controllers[widget.bvid] = videoController;
      setState(() {
        _player = player;
        _videoController = videoController;
        _started = true;
        _playing = true;
        _speed = 1.0;
      });
      _showControlsTemporarily();
    } catch (e) {
      setState(() => _error = '播放失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (_playing) {
      await player.pause();
    } else {
      await player.play();
    }
    if (mounted) {
      setState(() => _playing = !_playing);
      _showControlsTemporarily();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final player = _player;
    if (player == null) return;
    final cur = player.state.position;
    final dur = player.state.duration;
    final targetMs = (cur.inMilliseconds + seconds * 1000).clamp(0, dur.inMilliseconds);
    await player.seek(Duration(milliseconds: targetMs));
    _showControlsTemporarily();
  }

  Future<void> _setSpeed(double s) async {
    final player = _player;
    if (player == null) return;
    await player.setRate(s);
    if (mounted) {
      setState(() => _speed = s);
      _showControlsTemporarily();
    }
  }

  Future<void> _toggleMute() async {
    final player = _player;
    if (player == null) return;
    if (_isMuted) {
      await player.setVolume(100);
      if (mounted) setState(() => _isMuted = false);
    } else {
      await player.setVolume(0);
      if (mounted) setState(() => _isMuted = true);
    }
    _showControlsTemporarily();
  }

  Widget _buildProgressBar() {
    final player = _player;
    if (player == null) return const SizedBox.shrink();
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (ctx, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = player.state.duration;
        final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                _formatDuration(pos),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(ctx).copyWith(
                    trackHeight: 3,
                    activeTrackColor: Theme.of(ctx).colorScheme.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Theme.of(ctx).colorScheme.primary,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: pos.inMilliseconds.clamp(0, maxMs).toDouble(),
                    max: maxMs.toDouble(),
                    onChangeStart: (v) {
                      _isDragging = true;
                      _hideTimer?.cancel();
                      if (!_controlsVisible) {
                        setState(() => _controlsVisible = true);
                      }
                    },
                    onChanged: (v) {
                      player.seek(Duration(milliseconds: v.toInt()));
                    },
                    onChangeEnd: (v) {
                      _isDragging = false;
                      _showControlsTemporarily();
                    },
                  ),
                ),
              ),
              Text(
                _formatDuration(dur),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openFullscreen() {
    final controller = _videoController;
    if (controller == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (fullCtx) => _FullscreenBiliPlayer(
          controller: controller,
          player: _player,
          title: _info?.title ?? '哔哩哔哩视频',
          bvid: widget.bvid,
          speed: _speed,
          onSpeedChanged: _setSpeed,
          data: _data,
          currentVideo: _currentVideo,
          onQualityChanged: (video, audio) => _switchQuality(video, audio),
          formatDuration: _formatDuration,
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  Future<void> _switchQuality(BiliDashItem video, BiliDashItem? audio) async {
    final player = _player;
    if (player == null) return;
    setState(() {
      _currentVideo = video;
      _currentAudio = audio;
      _loading = true;
    });
    try {
      await player.open(
        Media(_edl(video, audio), httpHeaders: _headers),
        play: true,
      );
      if (mounted) setState(() => _playing = true);
    } catch (e) {
      if (mounted) setState(() => _error = '切画质失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;
    if (controller != null && _started) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: MouseRegion(
            onHover: (_) => _showControlsTemporarily(),
            onEnter: (_) => _showControlsTemporarily(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. 视频画面与手势
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showControlsTemporarily,
                  onDoubleTapDown: (details) {
                    final width = MediaQuery.of(context).size.width;
                    if (details.localPosition.dx < width / 3) {
                      _seekRelative(-10);
                    } else {
                      _seekRelative(10);
                    }
                  },
                  child: Video(
                    controller: controller,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                  ),
                ),

                // 2. 居中暂停指示图标
                if (!_playing && _controlsVisible)
                  Center(
                    child: GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(140),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),

                // 3. 顶部阴影与信息栏
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00AEEC).withAlpha(180),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Bilibili',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _info?.title ?? widget.bvid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '外部打开',
                              icon: const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 17),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                _openExternal(Uri.parse('https://www.bilibili.com/video/${widget.bvid}'));
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. 底部全功能现代控制栏
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: MouseRegion(
                        onEnter: (_) {
                          _isHoveringControls = true;
                          _hideTimer?.cancel();
                          if (!_controlsVisible) {
                            setState(() => _controlsVisible = true);
                          }
                        },
                        onExit: (_) {
                          _isHoveringControls = false;
                          _showControlsTemporarily();
                        },
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 4),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xE6000000), Colors.transparent],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                        _buildProgressBar(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            children: [
                              // 播放/暂停
                              IconButton(
                                tooltip: _playing ? '暂停' : '播放',
                                icon: Icon(
                                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: _togglePlay,
                              ),
                              // 快退 10s
                              IconButton(
                                tooltip: '快退 10 秒',
                                icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 19),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _seekRelative(-10),
                              ),
                              // 快进 10s
                              IconButton(
                                tooltip: '快进 10 秒',
                                icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 19),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _seekRelative(10),
                              ),
                              // 静音切换
                              IconButton(
                                tooltip: _isMuted ? '取消静音' : '静音',
                                icon: Icon(
                                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                  color: Colors.white70,
                                  size: 19,
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: _toggleMute,
                              ),

                              const Spacer(),

                              // 倍速选择
                              PopupMenuButton<double>(
                                initialValue: _speed,
                                tooltip: '播放倍速',
                                color: const Color(0xFF1E2420),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(color: Colors.white24, width: 0.6),
                                ),
                                onSelected: _setSpeed,
                                itemBuilder: (ctx) => [
                                  for (final sp in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                                    PopupMenuItem(
                                      value: sp,
                                      height: 36,
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            child: sp == _speed
                                                ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary, size: 16)
                                                : null,
                                          ),
                                          Text(
                                            '${sp}x 倍速',
                                            style: TextStyle(
                                              color: sp == _speed ? Theme.of(ctx).colorScheme.primary : Colors.white,
                                              fontSize: 12.5,
                                              fontWeight: sp == _speed ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(25),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white24, width: 0.6),
                                  ),
                                  child: Text(
                                    '${_speed}x',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),

                              // 画质切换
                              if (_data != null && _data!.videos.isNotEmpty)
                                PopupMenuButton<int>(
                                  initialValue: _currentVideo?.id ?? 0,
                                  tooltip: '选择清晰度',
                                  color: const Color(0xFF1E2420),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(color: Colors.white24, width: 0.6),
                                  ),
                                  onSelected: (id) {
                                    final video = _data!.videos.firstWhere(
                                      (e) => e.id == id,
                                      orElse: () => _currentVideo!,
                                    );
                                    final audio = _data!.bestAudio;
                                    _switchQuality(video, audio);
                                  },
                                  itemBuilder: (ctx) {
                                    final ids = _data!.videos
                                        .map((e) => e.id)
                                        .where(const {80, 64, 32, 16}.contains)
                                        .toSet();
                                    return [
                                      for (final id in ids)
                                        PopupMenuItem(
                                          value: id,
                                          height: 36,
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 20,
                                                child: id == (_currentVideo?.id ?? -1)
                                                    ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary, size: 16)
                                                    : null,
                                              ),
                                              Text(
                                                _qualityLabel(id),
                                                style: TextStyle(
                                                  color: id == (_currentVideo?.id ?? -1)
                                                      ? Theme.of(ctx).colorScheme.primary
                                                      : Colors.white,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ];
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(25),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.white24, width: 0.6),
                                    ),
                                    child: Text(
                                      _qualityLabel(_currentVideo?.id ?? 0).split(' ').first,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),

                              // 全屏
                              IconButton(
                                icon: const Icon(
                                  Icons.fullscreen_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                tooltip: '全屏播放',
                                visualDensity: VisualDensity.compact,
                                onPressed: _openFullscreen,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
}

    // 未播放：显示封面 + 播放按钮 + 标题
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: const Color(0xFF0C0E0D),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_info?.cover.isNotEmpty == true)
                CachedNetworkImage(
                  imageUrl: _info!.cover,
                  fit: BoxFit.cover,
                  httpHeaders: const {'Referer': 'https://www.bilibili.com'},
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              // 暗色渐变衬底
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black38, Colors.black87],
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(100),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: IconButton(
                    iconSize: 34,
                    color: Colors.white,
                    icon: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    onPressed: _loading ? null : _start,
                  ),
                ),
              ),
              if (_error != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    color: Colors.black87,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _start,
                              icon: const Icon(Icons.refresh, size: 14),
                              label: const Text('重试', style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _openExternal(
                                Uri.parse('https://www.bilibili.com/video/${widget.bvid}'),
                              ),
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('外部打开', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (_error == null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00AEEC),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Bilibili',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _info?.title.isNotEmpty == true
                                ? _info!.title
                                : '哔哩哔哩视频 · ${widget.bvid}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _qualityLabel(int id) {
    return switch (id) {
      127 => '8K 超高清',
      126 => '杜比视界',
      125 => 'HDR 真彩',
      120 => '4K 超清',
      116 => '1080P60 高帧率',
      112 => '1080P+ 高码率',
      80 => '1080P 高清',
      64 => '720P 高清',
      32 => '480P 清晰',
      16 => '360P 流畅',
      _ => '自动',
    };
  }

  void _openExternal(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 独立的现代化全屏 B 站播放器页面（含全功能手势与悬浮控制器）
class _FullscreenBiliPlayer extends StatefulWidget {
  final VideoController controller;
  final Player? player;
  final String title;
  final String bvid;
  final double speed;
  final ValueChanged<double> onSpeedChanged;
  final BiliPlayUrlData? data;
  final BiliDashItem? currentVideo;
  final void Function(BiliDashItem video, BiliDashItem? audio) onQualityChanged;
  final String Function(Duration) formatDuration;

  const _FullscreenBiliPlayer({
    required this.controller,
    required this.player,
    required this.title,
    required this.bvid,
    required this.speed,
    required this.onSpeedChanged,
    required this.data,
    required this.currentVideo,
    required this.onQualityChanged,
    required this.formatDuration,
  });

  @override
  State<_FullscreenBiliPlayer> createState() => _FullscreenBiliPlayerState();
}

class _FullscreenBiliPlayerState extends State<_FullscreenBiliPlayer> {
  bool _controlsVisible = true;
  Timer? _hideTimer;
  late double _speed;
  bool _playing = true;
  bool _isHoveringControls = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
    _playing = widget.player?.state.playing ?? true;
    _showControlsTemporarily();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showControlsTemporarily() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _hideTimer?.cancel();
    if (_isHoveringControls || _isDragging) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isHoveringControls && !_isDragging) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _togglePlay() async {
    if (_playing) {
      await widget.player?.pause();
    } else {
      await widget.player?.play();
    }
    if (mounted) {
      setState(() => _playing = !_playing);
      _showControlsTemporarily();
    }
  }

  void _seekRelative(int seconds) async {
    final cur = widget.player?.state.position ?? Duration.zero;
    final dur = widget.player?.state.duration ?? Duration.zero;
    final targetMs = (cur.inMilliseconds + seconds * 1000).clamp(0, dur.inMilliseconds);
    await widget.player?.seek(Duration(milliseconds: targetMs));
    _showControlsTemporarily();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onHover: (_) => _showControlsTemporarily(),
        onEnter: (_) => _showControlsTemporarily(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showControlsTemporarily,
              onDoubleTapDown: (details) {
                final w = MediaQuery.of(context).size.width;
                if (details.localPosition.dx < w / 3) {
                  _seekRelative(-10);
                } else {
                  _seekRelative(10);
                }
              },
              child: Center(
                child: Video(
                  controller: widget.controller,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // 顶部栏
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 底部栏
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: MouseRegion(
                    onEnter: (_) {
                      _isHoveringControls = true;
                      _hideTimer?.cancel();
                      if (!_controlsVisible) {
                        setState(() => _controlsVisible = true);
                      }
                    },
                    onExit: (_) {
                      _isHoveringControls = false;
                      _showControlsTemporarily();
                    },
                    child: SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.player != null)
                              StreamBuilder<Duration>(
                                stream: widget.player!.stream.position,
                                builder: (ctx, snap) {
                                  final pos = snap.data ?? Duration.zero;
                                  final dur = widget.player!.state.duration;
                                  final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
                                  return Row(
                                    children: [
                                      Text(
                                        widget.formatDuration(pos),
                                        style: const TextStyle(color: Colors.white, fontSize: 11),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value: pos.inMilliseconds.clamp(0, maxMs).toDouble(),
                                          max: maxMs.toDouble(),
                                          onChangeStart: (v) {
                                            _isDragging = true;
                                            _hideTimer?.cancel();
                                            if (!_controlsVisible) {
                                              setState(() => _controlsVisible = true);
                                            }
                                          },
                                          onChanged: (v) {
                                            widget.player!.seek(Duration(milliseconds: v.toInt()));
                                          },
                                          onChangeEnd: (v) {
                                            _isDragging = false;
                                            _showControlsTemporarily();
                                          },
                                        ),
                                      ),
                                      Text(
                                        widget.formatDuration(dur),
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: _togglePlay,
                          ),
                          IconButton(
                            icon: const Icon(Icons.replay_10_rounded, color: Colors.white70),
                            onPressed: () => _seekRelative(-10),
                          ),
                          IconButton(
                            icon: const Icon(Icons.forward_10_rounded, color: Colors.white70),
                            onPressed: () => _seekRelative(10),
                          ),
                          const Spacer(),
                          // 倍速
                          PopupMenuButton<double>(
                            initialValue: _speed,
                            tooltip: '倍速',
                            color: const Color(0xFF1E2420),
                            onSelected: (s) {
                              setState(() => _speed = s);
                              widget.onSpeedChanged(s);
                              _showControlsTemporarily();
                            },
                            itemBuilder: (ctx) => [
                              for (final sp in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                                PopupMenuItem(
                                  value: sp,
                                  child: Text('${sp}x 倍速', style: const TextStyle(color: Colors.white)),
                                ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(30),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${_speed}x',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white),
                            tooltip: '退出全屏',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  ),
),
);
  }
}
