import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../core/url_helper.dart';

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
  double _volume = 100.0;
  bool _muted = false;
  double _rate = 1.0;

  bool _showVolumeHud = false;
  Timer? _volumeHudTimer;
  bool _isHoveringVolume = false;

  StreamSubscription? _subPlaying;
  StreamSubscription? _subCompleted;
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
      _rate = existingPlayer.state.rate;
      _volume = existingPlayer.state.volume;
      _attachSubscriptions(existingPlayer);
    }
  }

  @override
  void didUpdateWidget(covariant GeneralVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src) {
      _subPlaying?.cancel();
      _subCompleted?.cancel();
      _subPos?.cancel();
      _subDur?.cancel();
      _subBuf?.cancel();
      _subErr?.cancel();
      final existingController = GeneralVideoPlayer._controllers[widget.src];
      final existingPlayer = GeneralVideoPlayer._players[widget.src];
      if (existingController != null && existingPlayer != null) {
        _videoController = existingController;
        _player = existingPlayer;
        _started = true;
        _playing = existingPlayer.state.playing;
        _position = existingPlayer.state.position;
        _duration = existingPlayer.state.duration;
        _rate = existingPlayer.state.rate;
        _volume = existingPlayer.state.volume;
        _attachSubscriptions(existingPlayer);
      } else {
        _videoController = null;
        _player = null;
        _started = false;
        _playing = false;
        _position = Duration.zero;
        _duration = Duration.zero;
      }
      setState(() {});
    }
  }

  void _attachSubscriptions(Player p) {
    _subPlaying?.cancel();
    _subCompleted?.cancel();
    _subPos?.cancel();
    _subDur?.cancel();
    _subBuf?.cancel();
    _subErr?.cancel();

    _subPlaying = p.stream.playing.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });
    _subCompleted = p.stream.completed.listen((completed) {
      if (mounted && completed) {
        setState(() {
          _playing = false;
          _controlsVisible = true;
        });
      }
    });
    _subPos = p.stream.position.listen((pos) {
      if (mounted && !_isDragging) setState(() => _position = pos);
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
    _volumeHudTimer?.cancel();
    _subPlaying?.cancel();
    _subCompleted?.cancel();
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

  Future<void> _seekRelative(int seconds) async {
    if (_player == null) return;
    final cur = _player!.state.position;
    final dur = _player!.state.duration;
    final targetMs = (cur.inMilliseconds + seconds * 1000).clamp(0, dur.inMilliseconds > 0 ? dur.inMilliseconds : 1);
    await _player!.seek(Duration(milliseconds: targetMs));
    setState(() => _position = Duration(milliseconds: targetMs));
    _showControlsTemporarily();
  }

  Future<void> _setVolume(double vol, {bool showHud = true}) async {
    final clamped = vol.clamp(0.0, 100.0);
    setState(() {
      _volume = clamped;
      if (_muted && clamped > 0) _muted = false;
      if (clamped == 0) _muted = true;
      if (showHud) _showVolumeHud = true;
    });
    await _player?.setVolume(_muted ? 0.0 : _volume);
    if (showHud) {
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }
  }

  Future<void> _toggleMute() async {
    if (_player == null) return;
    final nextMuted = !_muted;
    setState(() => _muted = nextMuted);
    await _player!.setVolume(nextMuted ? 0.0 : _volume);
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

  void _openFullscreen() {
    final controller = _videoController;
    final player = _player;
    if (controller == null || player == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => _FullscreenGeneralVideoPlayer(
          controller: controller,
          player: player,
          title: _displayTitle,
          src: widget.src,
          initialRate: _rate,
          initialVolume: _volume,
          initialMuted: _muted,
          onVolumeChanged: (vol, muted) {
            setState(() {
              _volume = vol;
              _muted = muted;
            });
          },
          onRateChanged: (rate) {
            setState(() => _rate = rate);
          },
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _playing = _player?.state.playing ?? false;
          _position = _player?.state.position ?? _position;
          _duration = _player?.state.duration ?? _duration;
          _rate = _player?.state.rate ?? _rate;
        });
        _showControlsTemporarily();
      }
    });
  }

  String _formatTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildVolumeHud(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final effectiveVol = _muted ? 0.0 : _volume;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _showVolumeHud ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(190),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primary.withAlpha(90), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(120),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _muted || effectiveVol == 0
                      ? Icons.volume_off_rounded
                      : (effectiveVol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                  color: primary,
                  size: 30,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 90,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: effectiveVol / 100.0,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(primary),
                      minHeight: 4.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _muted ? '静音' : '${effectiveVol.round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeControl(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final effectiveVol = _muted ? 0.0 : _volume;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringVolume = true),
      onExit: (_) => setState(() => _isHoveringVolume = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _muted ? '取消静音' : '静音',
            icon: Icon(
              _muted || effectiveVol == 0
                  ? Icons.volume_off_rounded
                  : (effectiveVol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
              color: Colors.white,
              size: 20,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: _toggleMute,
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isHoveringVolume ? 70 : 0,
            curve: Curves.easeOutCubic,
            child: _isHoveringVolume
                ? SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      activeTrackColor: primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: primary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
                    ),
                    child: Slider(
                      value: effectiveVol,
                      min: 0.0,
                      max: 100.0,
                      onChanged: (v) => _setVolume(v, showHud: false),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
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
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                if (event.scrollDelta.dy < 0) {
                  _setVolume(((_muted ? 0.0 : _volume) + 5.0).clamp(0.0, 100.0));
                } else if (event.scrollDelta.dy > 0) {
                  _setVolume(((_muted ? 0.0 : _volume) - 5.0).clamp(0.0, 100.0));
                }
              }
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. 视频画面与手势
                if (_started && _videoController != null)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final playerWidth = constraints.maxWidth;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _showControlsTemporarily,
                        onDoubleTapDown: (details) {
                          if (details.localPosition.dx < playerWidth / 3) {
                            _seekRelative(-10);
                          } else if (details.localPosition.dx > playerWidth * 2 / 3) {
                            _seekRelative(10);
                          } else {
                            _togglePlay();
                          }
                        },
                        onVerticalDragUpdate: (details) {
                          if (details.localPosition.dx > playerWidth / 2) {
                            final delta = -details.primaryDelta! / 1.5;
                            _setVolume(((_muted ? 0.0 : _volume) + delta).clamp(0.0, 100.0));
                          }
                        },
                        child: Video(
                          controller: _videoController!,
                          controls: NoVideoControls,
                          fit: BoxFit.contain,
                        ),
                      );
                    },
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

                // 2. 音量 HUD 指示器
                _buildVolumeHud(context),

                // 3. 加载中指示器
                if (_loading || _buffering)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),

                // 4. 错误提示与外部浏览器打开兜底
                if (_error != null)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent.withAlpha(100)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () => UrlHelper.openExternalBrowser(context, widget.src),
                            icon: const Icon(Icons.open_in_browser, size: 16),
                            label: const Text('在浏览器中播放', style: TextStyle(fontSize: 12)),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 5. 未开始或暂停时的中央播放指示按钮
                if ((!_started && !_loading) || (_started && !_playing && _controlsVisible))
                  Center(
                    child: AnimatedScale(
                      scale: (_started && !_playing) ? 1.0 : 0.95,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: IconButton(
                        iconSize: 56,
                        icon: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withAlpha(220),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(90),
                                blurRadius: 12,
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
                        onPressed: _started ? _togglePlay : _startPlayback,
                      ),
                    ),
                  ),

                // 6. 覆盖控制栏
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: (_started && _controlsVisible) ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOutCubic,
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
                                      visualDensity: VisualDensity.compact,
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
                                        // 播放/暂停
                                        IconButton(
                                          iconSize: 22,
                                          visualDensity: VisualDensity.compact,
                                          icon: AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 200),
                                            child: Icon(
                                              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                              key: ValueKey<bool>(_playing),
                                              color: Colors.white,
                                            ),
                                          ),
                                          onPressed: _togglePlay,
                                        ),
                                        // 快退 10s
                                        IconButton(
                                          tooltip: '快退 10 秒',
                                          iconSize: 18,
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.replay_10_rounded, color: Colors.white70),
                                          onPressed: () => _seekRelative(-10),
                                        ),
                                        // 快进 10s
                                        IconButton(
                                          tooltip: '快进 10 秒',
                                          iconSize: 18,
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.forward_10_rounded, color: Colors.white70),
                                          onPressed: () => _seekRelative(10),
                                        ),
                                        // 音量控制
                                        _buildVolumeControl(context),

                                        // 进度时间
                                        Padding(
                                          padding: const EdgeInsets.only(left: 4),
                                          child: Text(
                                            '${_formatTime(_position)} / ${_formatTime(_duration)}',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                              fontFeatures: [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        ),

                                        const Spacer(),

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

                                        // 全屏播放
                                        IconButton(
                                          tooltip: '全屏播放',
                                          iconSize: 20,
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                                          onPressed: _openFullscreen,
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
      ),
    );
  }
}

/// 通用视频全屏沉浸播放页面
class _FullscreenGeneralVideoPlayer extends StatefulWidget {
  final VideoController controller;
  final Player player;
  final String title;
  final String src;
  final double initialRate;
  final double initialVolume;
  final bool initialMuted;
  final void Function(double, bool)? onVolumeChanged;
  final void Function(double)? onRateChanged;

  const _FullscreenGeneralVideoPlayer({
    required this.controller,
    required this.player,
    required this.title,
    required this.src,
    required this.initialRate,
    required this.initialVolume,
    required this.initialMuted,
    this.onVolumeChanged,
    this.onRateChanged,
  });

  @override
  State<_FullscreenGeneralVideoPlayer> createState() => _FullscreenGeneralVideoPlayerState();
}

class _FullscreenGeneralVideoPlayerState extends State<_FullscreenGeneralVideoPlayer> {
  bool _playing = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _rate = 1.0;
  double _volume = 100.0;
  bool _muted = false;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isHoveringControls = false;
  bool _isDragging = false;

  bool _showVolumeHud = false;
  Timer? _volumeHudTimer;
  bool _isHoveringVolume = false;

  StreamSubscription? _subPlaying;
  StreamSubscription? _subCompleted;
  StreamSubscription? _subPos;
  StreamSubscription? _subDur;

  @override
  void initState() {
    super.initState();
    _playing = widget.player.state.playing;
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _rate = widget.initialRate;
    _volume = widget.initialVolume;
    _muted = widget.initialMuted;

    _subPlaying = widget.player.stream.playing.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });
    _subCompleted = widget.player.stream.completed.listen((completed) {
      if (mounted && completed) {
        setState(() {
          _playing = false;
          _controlsVisible = true;
        });
      }
    });
    _subPos = widget.player.stream.position.listen((pos) {
      if (mounted && !_isDragging) setState(() => _position = pos);
    });
    _subDur = widget.player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });

    _showControlsTemporarily();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _volumeHudTimer?.cancel();
    _subPlaying?.cancel();
    _subCompleted?.cancel();
    _subPos?.cancel();
    _subDur?.cancel();
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

  Future<void> _togglePlay() async {
    await widget.player.playOrPause();
    if (mounted) {
      setState(() => _playing = widget.player.state.playing);
      _showControlsTemporarily();
    }
  }

  Future<void> _seek(double valueMs) async {
    await widget.player.seek(Duration(milliseconds: valueMs.toInt()));
    _showControlsTemporarily();
  }

  Future<void> _seekRelative(int seconds) async {
    final cur = widget.player.state.position;
    final dur = widget.player.state.duration;
    final targetMs = (cur.inMilliseconds + seconds * 1000).clamp(0, dur.inMilliseconds > 0 ? dur.inMilliseconds : 1);
    await widget.player.seek(Duration(milliseconds: targetMs));
    setState(() => _position = Duration(milliseconds: targetMs));
    _showControlsTemporarily();
  }

  Future<void> _setVolume(double vol, {bool showHud = true}) async {
    final clamped = vol.clamp(0.0, 100.0);
    setState(() {
      _volume = clamped;
      if (_muted && clamped > 0) _muted = false;
      if (clamped == 0) _muted = true;
      if (showHud) _showVolumeHud = true;
    });
    await widget.player.setVolume(_muted ? 0.0 : _volume);
    widget.onVolumeChanged?.call(_volume, _muted);
    if (showHud) {
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }
  }

  Future<void> _toggleMute() async {
    final nextMuted = !_muted;
    setState(() => _muted = nextMuted);
    await widget.player.setVolume(nextMuted ? 0.0 : _volume);
    widget.onVolumeChanged?.call(_volume, nextMuted);
    _showControlsTemporarily();
  }

  Future<void> _changeRate() async {
    const rates = [1.0, 1.25, 1.5, 2.0];
    final nextIdx = (rates.indexOf(_rate) + 1) % rates.length;
    final nextRate = rates[nextIdx];
    setState(() => _rate = nextRate);
    await widget.player.setRate(nextRate);
    widget.onRateChanged?.call(nextRate);
    _showControlsTemporarily();
  }

  String _formatTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildVolumeHud(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final effectiveVol = _muted ? 0.0 : _volume;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _showVolumeHud ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(200),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: primary.withAlpha(90), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(140),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _muted || effectiveVol == 0
                      ? Icons.volume_off_rounded
                      : (effectiveVol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                  color: primary,
                  size: 36,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 110,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: effectiveVol / 100.0,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(primary),
                      minHeight: 5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _muted ? '静音' : '${effectiveVol.round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeControl(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final effectiveVol = _muted ? 0.0 : _volume;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringVolume = true),
      onExit: (_) => setState(() => _isHoveringVolume = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _muted ? '取消静音' : '静音',
            icon: Icon(
              _muted || effectiveVol == 0
                  ? Icons.volume_off_rounded
                  : (effectiveVol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
              color: Colors.white,
              size: 22,
            ),
            onPressed: _toggleMute,
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isHoveringVolume ? 90 : 0,
            curve: Curves.easeOutCubic,
            child: _isHoveringVolume
                ? SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: primary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    ),
                    child: Slider(
                      value: effectiveVol,
                      min: 0.0,
                      max: 100.0,
                      onChanged: (v) => _setVolume(v, showHud: false),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxMs = _duration.inMilliseconds.toDouble();
    final curMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onHover: (_) => _showControlsTemporarily(),
        onEnter: (_) => _showControlsTemporarily(),
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              if (event.scrollDelta.dy < 0) {
                _setVolume(((_muted ? 0.0 : _volume) + 5.0).clamp(0.0, 100.0));
              } else if (event.scrollDelta.dy > 0) {
                _setVolume(((_muted ? 0.0 : _volume) - 5.0).clamp(0.0, 100.0));
              }
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 视频画面与手势
              LayoutBuilder(
                builder: (context, constraints) {
                  final playerWidth = constraints.maxWidth;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showControlsTemporarily,
                    onDoubleTapDown: (details) {
                      if (details.localPosition.dx < playerWidth / 3) {
                        _seekRelative(-10);
                      } else if (details.localPosition.dx > playerWidth * 2 / 3) {
                        _seekRelative(10);
                      } else {
                        _togglePlay();
                      }
                    },
                    onVerticalDragUpdate: (details) {
                      if (details.localPosition.dx > playerWidth / 2) {
                        final delta = -details.primaryDelta! / 1.5;
                        _setVolume(((_muted ? 0.0 : _volume) + delta).clamp(0.0, 100.0));
                      }
                    },
                    child: Center(
                      child: Video(
                        controller: widget.controller,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),

              // 音量 HUD 指示器
              _buildVolumeHud(context),

              // 居中暂停指示图标
              if (!_playing && _controlsVisible)
                Center(
                  child: GestureDetector(
                    onTap: _togglePlay,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(140),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
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
                            IconButton(
                              tooltip: '在外部应用打开',
                              icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
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
                    ),
                  ),
                ),
              ),

              // 底部控制栏
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
                          constraints: const BoxConstraints(maxHeight: 110),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                              // 进度条与时间
                              if (maxMs > 0)
                                Row(
                                  children: [
                                    Text(
                                      _formatTime(_position),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 3,
                                          activeTrackColor: colorScheme.primary,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: colorScheme.primary,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                        ),
                                        child: Slider(
                                          value: curMs,
                                          max: maxMs,
                                          onChangeStart: (v) {
                                            setState(() => _isDragging = true);
                                            _hideTimer?.cancel();
                                            if (!_controlsVisible) {
                                              setState(() => _controlsVisible = true);
                                            }
                                          },
                                          onChanged: (v) {
                                            setState(() => _position = Duration(milliseconds: v.toInt()));
                                          },
                                          onChangeEnd: (v) {
                                            _isDragging = false;
                                            _seek(v);
                                          },
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatTime(_duration),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: _playing ? '暂停' : '播放',
                                    icon: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      child: Icon(
                                        _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        key: ValueKey<bool>(_playing),
                                        color: Colors.white,
                                        size: 28,
                                      ),
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
                                  // 音量控制
                                  _buildVolumeControl(context),

                                  const Spacer(),

                                  // 倍速
                                  InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: _changeRate,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(30),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${_rate == 1.0 ? "1.0" : _rate}x',
                                        style: TextStyle(
                                          color: _rate != 1.0 ? colorScheme.primary : Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // 退出全屏
                                  IconButton(
                                    tooltip: '退出全屏',
                                    icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 24),
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
      ),
    );
  }
}

