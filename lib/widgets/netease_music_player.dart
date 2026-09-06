import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:url_launcher/url_launcher.dart';

/// 网易云音乐内嵌播放（通过 outer/url 直链 + media_kit）
class NetEaseMusicPlayer extends StatefulWidget {
  static final Map<String, Player> _players = {};

  /// 是否自动拉取歌曲封面/名称（widget 测试中关闭，避免网络 Timer）
  final bool autoFetchMeta;

  /// 退出帖子页时停止所有内嵌音乐播放器
  static Future<void> stopAll() async {
    for (final p in _players.values) {
      await p.dispose();
    }
    _players.clear();
  }

  final String songId;
  const NetEaseMusicPlayer({
    super.key,
    required this.songId,
    this.autoFetchMeta = true,
  });

  @override
  State<NetEaseMusicPlayer> createState() => _NetEaseMusicPlayerState();
}

class _NetEaseMusicPlayerState extends State<NetEaseMusicPlayer>
    with TickerProviderStateMixin {
  Player? _player;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  String _title = '';
  String _artist = '';
  String _cover = '';

  late final AnimationController _rotateController;
  late final AnimationController _waveController;
  StreamSubscription? _subPlaying;
  StreamSubscription? _subCompleted;
  bool _isDragging = false;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    if (widget.autoFetchMeta) _loadMeta();
    final existing = NetEaseMusicPlayer._players[widget.songId];
    if (existing != null) {
      _player = existing;
      _playing = existing.state.playing;
      _attachPlayer(existing);
      if (_playing) {
        _rotateController.repeat();
        _waveController.repeat(reverse: true);
      }
    }
  }

  void _attachPlayer(Player p) {
    _subPlaying?.cancel();
    _subCompleted?.cancel();
    _subPlaying = p.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _playing = playing);
        if (playing) {
          if (!_rotateController.isAnimating) _rotateController.repeat();
          if (!_waveController.isAnimating) _waveController.repeat(reverse: true);
        } else {
          _rotateController.stop();
          _waveController.stop();
        }
      }
    });
    _subCompleted = p.stream.completed.listen((completed) {
      if (mounted && completed) {
        setState(() => _playing = false);
        _rotateController.stop();
        _waveController.stop();
      }
    });
  }

  @override
  void dispose() {
    _subPlaying?.cancel();
    _subCompleted?.cancel();
    _rotateController.dispose();
    _waveController.dispose();
    // 播放器自身不销毁：滚动出屏幕后继续播放
    super.dispose();
  }

  String get _url =>
      'https://music.163.com/song/media/outer/url?id=${widget.songId}.mp3';

  Future<void> _loadMeta() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Referer': 'https://music.163.com/',
          'Accept': 'application/json, text/plain, */*',
          'Cookie':
              'os=pc; osver=Microsoft-Windows-10-Professional-build-19045-64bit; appver=2.9.7;',
        },
      ),
    );

    // 1. 尝试网易云官方 API
    try {
      final resp = await dio.get(
        'https://music.163.com/api/song/detail',
        queryParameters: {
          'id': widget.songId,
          'ids': '[${widget.songId}]',
        },
      );
      var data = resp.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }
      if (data is Map) {
        final songs = data['songs'];
        if (songs is List && songs.isNotEmpty) {
          final s = songs.first as Map;
          final artists = s['artists'];
          String artist = '';
          if (artists is List && artists.isNotEmpty) {
            artist = artists
                .map((a) => (a as Map)['name']?.toString() ?? '')
                .where((n) => n.isNotEmpty)
                .join(' / ');
          }
          final album = s['album'];
          String cover = '';
          if (album is Map) {
            cover =
                (album['picUrl'] ?? album['blurPicUrl'])?.toString() ?? '';
          }
          if (cover.startsWith('http://')) {
            cover = cover.replaceFirst('http://', 'https://');
          }
          if (mounted) {
            setState(() {
              _title = s['name']?.toString() ?? '';
              _artist = artist;
              _cover = cover;
            });
            return;
          }
        }
      }
    } catch (_) {}

    // 2. 备用 Meting 音乐解析接口
    try {
      final resp = await dio.get(
        'https://api.injahow.cn/meting/',
        queryParameters: {
          'type': 'song',
          'id': widget.songId,
        },
      );
      var data = resp.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }
      if (data is Map && mounted) {
        String cover = (data['pic'] ?? data['cover'])?.toString() ?? '';
        if (cover.startsWith('http://')) {
          cover = cover.replaceFirst('http://', 'https://');
        }
        setState(() {
          if (_title.isEmpty) {
            _title = (data['name'] ?? data['title'])?.toString() ?? '';
          }
          if (_artist.isEmpty) {
            _artist = (data['artist'] ?? data['author'])?.toString() ?? '';
          }
          if (_cover.isEmpty) {
            _cover = cover;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _toggle() async {
    final player = _player;
    if (player != null) {
      if (_playing) {
        await player.pause();
      } else {
        await player.play();
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = Player();
      _attachPlayer(p);
      await p.open(
        Media(
          _url,
          httpHeaders: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Referer': 'https://music.163.com',
          },
        ),
        play: true,
      );
      if (!mounted) {
        p.dispose();
        return;
      }
      NetEaseMusicPlayer._players[widget.songId] = p;
      setState(() {
        _player = p;
        _playing = true;
      });
      _rotateController.repeat();
      _waveController.repeat(reverse: true);
    } catch (e) {
      setState(() => _error = '播放失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openExternal() async {
    final uri = Uri.parse('https://music.163.com/#/song?id=${widget.songId}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildVinylCover(ThemeData theme) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF161616),
        border: Border.all(color: const Color(0xFF303030), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white10, width: 0.8),
            ),
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white12, width: 0.6),
            ),
          ),
          ClipOval(
            child: SizedBox(
              width: 24,
              height: 24,
              child: _cover.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _cover,
                      fit: BoxFit.cover,
                      httpHeaders: const {
                        'Referer': 'https://music.163.com',
                      },
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFFE53935),
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    )
                  : Container(
                      color: const Color(0xFFE53935),
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
            ),
          ),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withAlpha(230),
              border: Border.all(color: Colors.black54, width: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveBars(ThemeData theme) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, _) {
        final v = _waveController.value;
        final heights = _playing
            ? [
                4.0 + 8.0 * ((v * 1.3) % 1.0),
                3.0 + 10.0 * (((v + 0.4) * 1.5) % 1.0),
                5.0 + 7.0 * (((v + 0.7) * 1.2) % 1.0),
                3.0 + 9.0 * (((v + 0.2) * 1.7) % 1.0),
              ]
            : [3.0, 3.0, 3.0, 3.0];
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < heights.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Container(
                width: 2.5,
                height: heights[i],
                decoration: BoxDecoration(
                  color: _playing
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _playing
              ? colorScheme.primary.withAlpha(120)
              : theme.colorScheme.outlineVariant.withAlpha(70),
          width: _playing ? 1.2 : 0.8,
        ),
        boxShadow: [
          if (_playing)
            BoxShadow(
              color: colorScheme.primary.withAlpha(20),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 黑胶旋转唱片
              GestureDetector(
                onTap: _loading ? null : _toggle,
                child: RotationTransition(
                  turns: _rotateController,
                  child: _buildVinylCover(theme),
                ),
              ),
              const SizedBox(width: 12),
              // 歌曲与作者信息 + 动态声波
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _title.isNotEmpty ? _title : '网易云音乐',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildWaveBars(theme),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _artist.isNotEmpty ? _artist : '歌曲 ID: ${widget.songId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 11,
                      ),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // 播放 / 暂停平滑微交互按钮
              IconButton(
                tooltip: _playing ? '暂停' : '播放',
                onPressed: _loading ? null : _toggle,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, anim) {
                          return ScaleTransition(
                            scale: anim,
                            child: FadeTransition(opacity: anim, child: child),
                          );
                        },
                        child: Icon(
                          _playing
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                          key: ValueKey<bool>(_playing),
                          color: theme.colorScheme.primary,
                          size: 34,
                        ),
                      ),
              ),
              IconButton(
                tooltip: '在浏览器打开',
                visualDensity: VisualDensity.compact,
                onPressed: _openExternal,
                icon: Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_player != null) _buildProgress(theme),
        ],
      ),
    );
  }

  Widget _buildProgress(ThemeData theme) {
    final player = _player;
    if (player == null) return const SizedBox.shrink();
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (ctx, snap) {
        final pos = _isDragging && _dragValue != null
            ? Duration(milliseconds: _dragValue!.toInt())
            : (snap.data ?? Duration.zero);
        final dur = player.state.duration;
        final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
        final curMs = pos.inMilliseconds.clamp(0, maxMs).toDouble();

        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                _formatTime(pos),
                style: TextStyle(
                  fontSize: 10.5,
                  color: theme.colorScheme.outline,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(ctx).copyWith(
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor: theme.colorScheme.outlineVariant.withAlpha(80),
                    thumbColor: theme.colorScheme.primary,
                  ),
                  child: Slider(
                    value: curMs,
                    max: maxMs.toDouble(),
                    onChangeStart: (v) {
                      setState(() {
                        _isDragging = true;
                        _dragValue = v;
                      });
                    },
                    onChanged: (v) {
                      setState(() => _dragValue = v);
                    },
                    onChangeEnd: (v) {
                      player.seek(Duration(milliseconds: v.toInt()));
                      setState(() {
                        _isDragging = false;
                        _dragValue = null;
                      });
                    },
                  ),
                ),
              ),
              Text(
                _formatTime(dur),
                style: TextStyle(
                  fontSize: 10.5,
                  color: theme.colorScheme.outline,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
