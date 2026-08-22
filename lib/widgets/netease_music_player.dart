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

class _NetEaseMusicPlayerState extends State<NetEaseMusicPlayer> {
  Player? _player;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  String _title = '';
  String _artist = '';
  String _cover = '';

  @override
  void initState() {
    super.initState();
    if (widget.autoFetchMeta) _loadMeta();
    final existing = NetEaseMusicPlayer._players[widget.songId];
    if (existing != null) {
      _player = existing;
      _playing = existing.state.playing;
    }
  }

  @override
  void dispose() {
    // 不销毁：滚动出屏幕后继续播放
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
      setState(() => _playing = !_playing);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = Player();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(70),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 40,
                  height: 40,
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
                              size: 22,
                            ),
                          ),
                        )
                      : Container(
                          color: const Color(0xFFE53935),
                          child: const Icon(
                            Icons.music_note_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title.isNotEmpty ? _title : '网易云音乐',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
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
              IconButton(
                tooltip: _playing ? '暂停' : '播放',
                onPressed: _loading ? null : _toggle,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        color: theme.colorScheme.primary,
                        size: 32,
                      ),
              ),
              IconButton(
                tooltip: '在浏览器打开',
                visualDensity: VisualDensity.compact,
                onPressed: _openExternal,
                icon: Icon(
                  Icons.open_in_new,
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
        final pos = snap.data ?? Duration.zero;
        final dur = player.state.duration;
        final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
        return SliderTheme(
          data: SliderTheme.of(ctx).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
          ),
          child: Slider(
            value: pos.inMilliseconds.clamp(0, maxMs).toDouble(),
            max: maxMs.toDouble(),
            onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
          ),
        );
      },
    );
  }
}
