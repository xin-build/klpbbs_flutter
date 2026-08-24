import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

/// 通用音频播放器组件（支持 .mp3, .m4a, .wav, .ogg, .flac 等原生流式播放）
class GeneralAudioPlayer extends StatefulWidget {
  static final Map<String, Player> _players = {};

  /// 退出帖子详情页时停止所有正在播放的通用音频
  static Future<void> stopAll() async {
    for (final p in _players.values) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _players.clear();
  }

  final String src;
  final String title;

  const GeneralAudioPlayer({
    super.key,
    required this.src,
    this.title = '音频文件',
  });

  @override
  State<GeneralAudioPlayer> createState() => _GeneralAudioPlayerState();
}

class _GeneralAudioPlayerState extends State<GeneralAudioPlayer> {
  Player? _player;
  bool _playing = false;
  bool _loading = false;
  bool _buffering = false;
  String? _error;
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
    if (widget.title.isNotEmpty && widget.title != '音频文件') {
      return widget.title;
    }
    try {
      final uri = Uri.parse(widget.src);
      final lastSeg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (lastSeg.isNotEmpty) {
        return Uri.decodeComponent(lastSeg);
      }
    } catch (_) {}
    return '音频播放';
  }

  @override
  void initState() {
    super.initState();
    final existing = GeneralAudioPlayer._players[widget.src];
    if (existing != null) {
      _player = existing;
      _playing = existing.state.playing;
      _position = existing.state.position;
      _duration = existing.state.duration;
      _attachSubscriptions(existing);
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
    _subPlaying?.cancel();
    _subPos?.cancel();
    _subDur?.cancel();
    _subBuf?.cancel();
    _subErr?.cancel();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_player == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final p = Player();
        _attachSubscriptions(p);
        await p.open(Media(widget.src), play: true);
        GeneralAudioPlayer._players[widget.src] = p;
        if (mounted) {
          setState(() {
            _player = p;
            _loading = false;
            _playing = true;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = '播放失败：$e';
            _loading = false;
          });
        }
      }
      return;
    }

    try {
      if (_playing) {
        await _player!.pause();
      } else {
        await _player!.play();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '播放失败：$e');
    }
  }

  Future<void> _seek(double valueMs) async {
    if (_player != null) {
      await _player!.seek(Duration(milliseconds: valueMs.toInt()));
    }
  }

  Future<void> _toggleMute() async {
    if (_player == null) return;
    final nextMuted = !_muted;
    setState(() => _muted = nextMuted);
    await _player!.setVolume(nextMuted ? 0.0 : _volume * 100.0);
  }

  Future<void> _changeRate() async {
    if (_player == null) return;
    const rates = [1.0, 1.25, 1.5, 2.0];
    final nextIdx = (rates.indexOf(_rate) + 1) % rates.length;
    final nextRate = rates[nextIdx];
    setState(() => _rate = nextRate);
    await _player!.setRate(nextRate);
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
    final isDark = theme.brightness == Brightness.dark;

    final maxMs = _duration.inMilliseconds.toDouble();
    final curMs = _position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest.withAlpha(80)
            : colorScheme.primaryContainer.withAlpha(45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _playing
              ? colorScheme.primary.withAlpha(140)
              : colorScheme.outlineVariant.withAlpha(70),
          width: _playing ? 1.2 : 0.8,
        ),
        boxShadow: [
          if (_playing)
            BoxShadow(
              color: colorScheme.primary.withAlpha(25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏 + 播放/暂停 + 倍速/外部链接
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _playing
                      ? colorScheme.primary
                      : colorScheme.primary.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: _loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _playing ? Colors.white : colorScheme.primary,
                          ),
                        )
                      : Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: _playing ? Colors.white : colorScheme.primary,
                        ),
                  onPressed: _togglePlay,
                  tooltip: _playing ? '暂停' : '播放',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _error != null
                          ? _error!
                          : _buffering
                              ? '缓冲中...'
                              : '${_formatTime(_position)} / ${_formatTime(_duration)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: _error != null
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_player != null) ...[
                // 静音切换
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: _muted ? '取消静音' : '静音',
                  icon: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: _muted ? colorScheme.error : colorScheme.outline,
                  ),
                  onPressed: _toggleMute,
                ),
                // 倍速切换
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _changeRate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      '${_rate == 1.0 ? "1.0" : _rate}x',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _rate != 1.0 ? colorScheme.primary : colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ],
              // 外部浏览器打开
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                tooltip: '外部打开 / 下载直链',
                icon: Icon(
                  Icons.open_in_new_rounded,
                  color: colorScheme.outline,
                ),
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
          // 进度条 Slider
          if (maxMs > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: colorScheme.primary,
                  inactiveTrackColor: colorScheme.outlineVariant.withAlpha(80),
                  thumbColor: colorScheme.primary,
                ),
                child: Slider(
                  min: 0.0,
                  max: maxMs,
                  value: curMs,
                  onChanged: (val) {
                    setState(() => _position = Duration(milliseconds: val.toInt()));
                  },
                  onChangeEnd: _seek,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
