import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// 视频内嵌播放页（现代化沉浸式播放器）
class VideoPlayerPage extends StatefulWidget {
  final String url;
  const VideoPlayerPage({super.key, required this.url});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _ctrl;
  bool _ready = false;
  bool _fullscreen = false;
  String? _error;
  double _speed = 1.0;
  bool _isMuted = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _ctrl.initialize().then((_) {
      if (mounted) {
        setState(() => _ready = true);
        _ctrl.setLooping(false);
        _ctrl.play();
        _ctrl.addListener(() {
          if (mounted) setState(() {});
        });
        _showControlsTemporarily();
      }
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _showControlsTemporarily() {
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _togglePlay() {
    if (_ctrl.value.isPlaying) {
      _ctrl.pause();
    } else {
      _ctrl.play();
    }
    _showControlsTemporarily();
  }

  void _seekRelative(int seconds) {
    final cur = _ctrl.value.position;
    final dur = _ctrl.value.duration;
    final targetMs = (cur.inMilliseconds + seconds * 1000).clamp(0, dur.inMilliseconds);
    _ctrl.seekTo(Duration(milliseconds: targetMs));
    _showControlsTemporarily();
  }

  void _setSpeed(double s) {
    _ctrl.setPlaybackSpeed(s);
    setState(() => _speed = s);
    _showControlsTemporarily();
  }

  void _toggleMute() {
    if (_isMuted) {
      _ctrl.setVolume(1.0);
      setState(() => _isMuted = false);
    } else {
      _ctrl.setVolume(0.0);
      setState(() => _isMuted = true);
    }
    _showControlsTemporarily();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pos = _ctrl.value.position;
    final dur = _ctrl.value.duration;
    final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_fullscreen,
        bottom: !_fullscreen,
        child: Center(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        '视频加载失败\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('返回'),
                      ),
                    ],
                  ),
                )
              : !_ready
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // 1. 视频渲染与手势交互
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
                            child: AspectRatio(
                              aspectRatio: _ctrl.value.aspectRatio > 0 ? _ctrl.value.aspectRatio : 16 / 9,
                              child: VideoPlayer(_ctrl),
                            ),
                          ),
                        ),

                        // 2. 居中暂停大图标
                        if (!_ctrl.value.isPlaying && _controlsVisible)
                          Center(
                            child: GestureDetector(
                              onTap: _togglePlay,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(140),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white30, width: 1.5),
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 42,
                                ),
                              ),
                            ),
                          ),

                        // 3. 顶部导航栏与标题
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
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
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      '视频播放',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // 4. 底部全功能控制栏
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                                  // 进度条
                                  Row(
                                    children: [
                                      Text(
                                        _formatDuration(pos),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            trackHeight: 3,
                                            activeTrackColor: theme.colorScheme.primary,
                                            inactiveTrackColor: Colors.white24,
                                            thumbColor: theme.colorScheme.primary,
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                          ),
                                          child: Slider(
                                            value: pos.inMilliseconds.clamp(0, maxMs).toDouble(),
                                            max: maxMs.toDouble(),
                                            onChanged: (v) {
                                              _showControlsTemporarily();
                                              _ctrl.seekTo(Duration(milliseconds: v.toInt()));
                                            },
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(dur),
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  // 底部按钮栏
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          _ctrl.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                        onPressed: _togglePlay,
                                      ),
                                      IconButton(
                                        tooltip: '快退 10 秒',
                                        icon: const Icon(Icons.replay_10_rounded, color: Colors.white70),
                                        onPressed: () => _seekRelative(-10),
                                      ),
                                      IconButton(
                                        tooltip: '快进 10 秒',
                                        icon: const Icon(Icons.forward_10_rounded, color: Colors.white70),
                                        onPressed: () => _seekRelative(10),
                                      ),
                                      IconButton(
                                        tooltip: _isMuted ? '取消静音' : '静音',
                                        icon: Icon(
                                          _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                          color: Colors.white70,
                                        ),
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
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 20,
                                                    child: sp == _speed
                                                        ? const Icon(Icons.check_rounded, color: Color(0xFF4ADE80), size: 16)
                                                        : null,
                                                  ),
                                                  Text(
                                                    '${sp}x 倍速',
                                                    style: TextStyle(
                                                      color: sp == _speed ? const Color(0xFF4ADE80) : Colors.white,
                                                      fontWeight: sp == _speed ? FontWeight.bold : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withAlpha(30),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.white24, width: 0.6),
                                          ),
                                          child: Text(
                                            '${_speed}x',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // 全屏切换
                                      IconButton(
                                        icon: Icon(
                                          _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        tooltip: _fullscreen ? '退出全屏' : '全屏',
                                        onPressed: () {
                                          setState(() => _fullscreen = !_fullscreen);
                                          SystemChrome.setEnabledSystemUIMode(
                                            _fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
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
}
