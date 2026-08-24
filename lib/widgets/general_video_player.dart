import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

/// 通用内嵌视频播放器组件（基于 media_kit 与 media_kit_video，支持多平台与全屏沉浸播放）
class GeneralVideoPlayer extends StatefulWidget {
  static final Map<String, Player> _players = {};
  static final Map<String, VideoController> _controllers = {};

  /// 退出帖子详情页时停止所有正在播放的视频
  static Future<void> stopAll() async {
    for (final p in _players.values) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _players.clear();
    _controllers.clear();
  }

  final String src;
  final String title;

  const GeneralVideoPlayer({
    super.key,
    required this.src,
    this.title = '视频播放',
  });

  @override
  State<GeneralVideoPlayer> createState() => _GeneralVideoPlayerState();
}

class _GeneralVideoPlayerState extends State<GeneralVideoPlayer> {
  Player? _player;
  VideoController? _videoController;

  bool _started = false;
  bool _playing = false;
  bool _loading = false;
  bool _buffering = false;
  String? _error;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isHoveringControls = false;
  bool _isDragging = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final double _volume = 1.0;
  bool _muted = false;
  double _rate = 1.0;

  StreamSubscription? _subPlaying;
  StreamSubscription? _subPos;
  StreamSubscription? _subDur;
  StreamSubscription? _subBuf;
  StreamSubscription? _subErr;

  String get _displayTitle {
    if (widget.title.isNotEmpty && widget.title != '视频播放' && widget.title != '内嵌视频播放') {
      return widget.title;
    }
    try {
      final uri = Uri.parse(widget.src);
      final lastSeg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (lastSeg.isNotEmpty) {
        return Uri.decodeComponent(lastSeg);
      }
    } catch (_) {}
    return '视频播放';
  }

  @override
  void initState() {
    super.initState();
    final existingController = GeneralVideoPlayer._controllers[widget.src];
    final existingPlayer = GeneralVideoPlayer._players[widget.src];
    if (existingController != null && existingPlayer != null) {
      _videoController = existingController;
      _player = existingPlayer;
      _started = true;
      _playing = existingPlayer.state.playing;
      _position = existingPlayer.state.position;
      _duration = existingPlayer.state.duration;
      _attachSubscriptions(existingPlayer);
    }
  }

  void _attachSubscriptions(Player p) {
    _subPlaying?.cancel();
    _subPos?.cancel();
    _subDur?.cancel();
    _subBuf?.cancel();
    _subErr?.cancel();

    _subPlaying = p.stream.playing.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });
    _subPos = p.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _subDur = p.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _subBuf = p.stream.buffering.listen((buf) {
      if (mounted) setState(() => _buffering = buf);
    });
    _subErr = p.stream.error.listen((err) {
      if (mounted && err.isNotEmpty) {
        setState(() {
          _error = err;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _subPlaying?.cancel();
    _subPos?.cancel();
    _subDur?.cancel();
    _subBuf?.cancel();
    _subErr?.cancel();
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

  Future<void> _startPlayback() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = Player();
      final c = VideoController(p);
      _attachSubscriptions(p);
      await p.open(Media(widget.src), play: true);
      GeneralVideoPlayer._players[widget.src] = p;
      GeneralVideoPlayer._controllers[widget.src] = c;
      if (mounted) {
        setState(() {
          _player = p;
          _videoController = c;
          _started = true;
          _loading = false;
          _playing = true;
        });
        _showControlsTemporarily();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '播放失败：$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _togglePlay() async {
    if (!_started) {
      await _startPlayback();
      return;
    }
    if (_player != null) {
      if (_playing) {
        await _player!.pause();
      } else {
        await _player!.play();
      }
      _showControlsTemporarily();
    }
  }

  Future<void> _seek(double valueMs) async {
    if (_player != null) {
      await _player!.seek(Duration(milliseconds: valueMs.toInt()));
      _showControlsTemporarily();
    }
  }

  Future<void> _toggleMute() async {
    if (_player == null) return;
    final nextMuted = !_muted;
    setState(() => _muted = nextMuted);
    await _player!.setVolume(nextMuted ? 0.0 : _volume * 100.0);
    _showControlsTemporarily();
  }

  Future<void> _changeRate() async {
    if (_player == null) return;
    const rates = [1.0, 1.25, 1.5, 2.0];
    final nextIdx = (rates.indexOf(_rate) + 1) % rates.length;
    final nextRate = rates[nextIdx];
    setState(() => _rate = nextRate);
    await _player!.setRate(nextRate);
    _showControlsTemporarily();
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxMs = _duration.inMilliseconds.toDouble();
    final curMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(80),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: MouseRegion(
          onHover: (_) => _showControlsTemporarily(),
          onEnter: (_) => _showControlsTemporarily(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. 视频画面
              if (_started && _videoController != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showControlsTemporarily,
                  child: Video(
                    controller: _videoController!,
                    controls: NoVideoControls,
                  ),
                )
              else
                Container(
                  color: const Color(0xFF181818),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.smart_display_rounded,
                        size: 48,
                        color: colorScheme.primary.withAlpha(200),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 2. 加载中指示器
              if (_loading || _buffering)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),

              // 3. 错误提示
              if (_error != null)
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                ),

              // 4. 未开始时的中央播放大按钮
              if (!_started && !_loading)
                Center(
                  child: IconButton(
                    iconSize: 56,
                    icon: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withAlpha(220),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(80),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    onPressed: _startPlayback,
                  ),
                ),

              // 5. 覆盖控制栏
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: (_started && _controlsVisible) ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_started || !_controlsVisible,
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
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black54,
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black87,
                            ],
                            stops: [0.0, 0.25, 0.7, 1.0],
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 顶部条（标题 + 外部打开）
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.white70),
                                    tooltip: '在外部应用打开',
                                    onPressed: () async {
                                      final uri = Uri.tryParse(widget.src);
                                      if (uri != null) {
                                        await url_launcher.launchUrl(
                                          uri,
                                          mode: url_launcher.LaunchMode.externalApplication,
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),

                            // 底部控制栏
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 进度滑块
                                  if (maxMs > 0)
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 2.5,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                        activeTrackColor: colorScheme.primary,
                                        inactiveTrackColor: Colors.white24,
                                        thumbColor: colorScheme.primary,
                                      ),
                                      child: Slider(
                                        min: 0.0,
                                        max: maxMs,
                                        value: curMs,
                                        onChangeStart: (val) {
                                          _isDragging = true;
                                          _hideTimer?.cancel();
                                          if (!_controlsVisible) {
                                            setState(() => _controlsVisible = true);
                                          }
                                        },
                                        onChanged: (val) {
                                          setState(() => _position = Duration(milliseconds: val.toInt()));
                                        },
                                        onChangeEnd: (val) {
                                          _isDragging = false;
                                          _showControlsTemporarily();
                                          _seek(val);
                                        },
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      IconButton(
                                        iconSize: 22,
                                        padding: EdgeInsets.zero,
                                        icon: Icon(
                                          _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                        ),
                                        onPressed: _togglePlay,
                                      ),
                                      Text(
                                        '${_formatTime(_position)} / ${_formatTime(_duration)}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                      const Spacer(),
                                      // 静音
                                      IconButton(
                                        iconSize: 18,
                                        padding: EdgeInsets.zero,
                                        icon: Icon(
                                          _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                          color: Colors.white70,
                                        ),
                                        onPressed: _toggleMute,
                                      ),
                                      // 倍速
                                      InkWell(
                                        borderRadius: BorderRadius.circular(4),
                                        onTap: _changeRate,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          child: Text(
                                            '${_rate == 1.0 ? "1.0" : _rate}x',
                                            style: TextStyle(
                                              color: _rate != 1.0 ? colorScheme.primary : Colors.white70,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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
}
