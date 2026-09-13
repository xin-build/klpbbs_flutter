import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:url_launcher/url_launcher.dart';

/// 歌词行数据模型（包含时间戳、原文、可选翻译）
class LyricLine {
  final Duration time;
  final String text;
  final String? translation;

  const LyricLine({
    required this.time,
    required this.text,
    this.translation,
  });
}

class _NetEaseSongMeta {
  final String title;
  final String artist;
  final String cover;
  const _NetEaseSongMeta({
    required this.title,
    required this.artist,
    required this.cover,
  });
}

/// 网易云音乐内嵌播放（通过 outer/url 直链 + media_kit）
class NetEaseMusicPlayer extends StatefulWidget {
  static final Map<String, Player> _players = {};
  static final Map<String, _NetEaseSongMeta> _metaCache = {};
  static final Map<String, List<LyricLine>> _lyricsCache = {};

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

  double _volume = 100.0;
  bool _muted = false;
  double _speed = 1.0;

  List<LyricLine>? _lyrics;
  bool _loadingLyrics = false;
  bool _showLyrics = false;
  bool _largeLyrics = false;
  int _activeLyricIndex = -1;
  final ScrollController _lyricScrollController = ScrollController();

  late final AnimationController _rotateController;
  late final AnimationController _waveController;
  StreamSubscription? _subPlaying;
  StreamSubscription? _subCompleted;
  StreamSubscription? _subPosition;
  StreamSubscription? _subDuration;
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

    final cachedMeta = NetEaseMusicPlayer._metaCache[widget.songId];
    if (cachedMeta != null) {
      _title = cachedMeta.title;
      _artist = cachedMeta.artist;
      _cover = cachedMeta.cover;
    }
    final cachedLyrics = NetEaseMusicPlayer._lyricsCache[widget.songId];
    if (cachedLyrics != null) {
      _lyrics = cachedLyrics;
    }

    if (widget.autoFetchMeta) {
      if (cachedMeta == null) _loadMeta();
      if (cachedLyrics == null) _loadLyrics();
    }
    final existing = NetEaseMusicPlayer._players[widget.songId];
    if (existing != null) {
      _player = existing;
      _playing = existing.state.playing;
      _volume = existing.state.volume;
      _speed = existing.state.rate;
      _attachPlayer(existing);
      if (_playing) {
        if (!_rotateController.isAnimating) _rotateController.repeat();
        if (!_waveController.isAnimating) _waveController.repeat(reverse: true);
      }
    }
  }

  @override
  void didUpdateWidget(covariant NetEaseMusicPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _subPlaying?.cancel();
      _subCompleted?.cancel();
      _subPosition?.cancel();
      _subDuration?.cancel();
      _player = NetEaseMusicPlayer._players[widget.songId];
      if (_player != null) {
        _playing = _player!.state.playing;
        _volume = _player!.state.volume;
        _speed = _player!.state.rate;
        _attachPlayer(_player!);
        if (_playing) {
          if (!_rotateController.isAnimating) _rotateController.repeat();
          if (!_waveController.isAnimating) _waveController.repeat(reverse: true);
        } else {
          _rotateController.stop();
          _waveController.stop();
        }
      } else {
        _playing = false;
        _rotateController.stop();
        _waveController.stop();
      }
      final cachedMeta = NetEaseMusicPlayer._metaCache[widget.songId];
      if (cachedMeta != null) {
        _title = cachedMeta.title;
        _artist = cachedMeta.artist;
        _cover = cachedMeta.cover;
      } else {
        _title = '';
        _artist = '';
        _cover = '';
        if (widget.autoFetchMeta) _loadMeta();
      }
      final cachedLyrics = NetEaseMusicPlayer._lyricsCache[widget.songId];
      if (cachedLyrics != null) {
        _lyrics = cachedLyrics;
      } else {
        _lyrics = null;
        if (widget.autoFetchMeta) _loadLyrics();
      }
      setState(() {});
    }
  }

  void _attachPlayer(Player p) {
    _subPlaying?.cancel();
    _subCompleted?.cancel();
    _subPosition?.cancel();
    _subDuration?.cancel();
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
    _subPosition = p.stream.position.listen((pos) {
      _updateActiveLyric(pos);
    });
    _subDuration = p.stream.duration.listen((dur) {
      if (mounted) setState(() {});
    });
  }

  void _updateActiveLyric(Duration pos) {
    if (_lyrics == null || _lyrics!.isEmpty) return;
    final list = _lyrics!;
    int idx = -1;
    for (int i = 0; i < list.length; i++) {
      if (pos >= list[i].time) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx != _activeLyricIndex) {
      _activeLyricIndex = idx;
      if (mounted && _showLyrics) {
        setState(() {});
        _scrollToActiveLyric();
      }
    }
  }

  void _scrollToActiveLyric() {
    if (!_lyricScrollController.hasClients || _activeLyricIndex < 0) return;
    final lyrics = _lyrics;
    final hasAnyTranslation = lyrics != null &&
        lyrics.any((l) => l.translation != null && l.translation!.isNotEmpty);
    final itemHeight = hasAnyTranslation ? 42.0 : 32.0;
    final containerHeight = _largeLyrics
        ? 200.0
        : (hasAnyTranslation ? 64.0 : 52.0);
    // 将当前激活行垂直精准居中
    final targetOffset =
        (_activeLyricIndex * itemHeight) - (containerHeight / 2 - itemHeight / 2);
    final maxScroll = _lyricScrollController.position.maxScrollExtent;
    final clamped = targetOffset.clamp(0.0, maxScroll);
    _lyricScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleLyrics() {
    setState(() {
      _showLyrics = !_showLyrics;
    });
    if (_showLyrics && _lyrics == null) {
      _loadLyrics();
    }
    if (_showLyrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveLyric();
      });
    }
  }

  @override
  void dispose() {
    _subPlaying?.cancel();
    _subCompleted?.cancel();
    _subPosition?.cancel();
    _subDuration?.cancel();
    _lyricScrollController.dispose();
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
            NetEaseMusicPlayer._metaCache[widget.songId] = _NetEaseSongMeta(
              title: _title,
              artist: _artist,
              cover: _cover,
            );
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
        if (_title.isNotEmpty || _artist.isNotEmpty || _cover.isNotEmpty) {
          NetEaseMusicPlayer._metaCache[widget.songId] = _NetEaseSongMeta(
            title: _title,
            artist: _artist,
            cover: _cover,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _loadLyrics() async {
    if (_lyrics != null || _loadingLyrics) return;
    if (mounted) setState(() => _loadingLyrics = true);

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Referer': 'https://music.163.com/',
          'Cookie':
              'os=pc; osver=Microsoft-Windows-10-Professional-build-19045-64bit; appver=2.9.7;',
        },
      ),
    );

    String? rawLrc;
    String? rawTrans;

    // 1. 尝试网易云官方歌词接口
    try {
      final resp = await dio.get(
        'https://music.163.com/api/song/lyric',
        queryParameters: {
          'id': widget.songId,
          'lv': '1',
          'kv': '1',
          'tv': '1',
        },
      );
      var data = resp.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }
      if (data is Map) {
        rawLrc = data['lrc']?['lyric']?.toString();
        rawTrans = data['tlyric']?['lyric']?.toString();
      }
    } catch (_) {}

    // 2. 备用 Meting 歌词解析接口
    if (rawLrc == null || rawLrc.isEmpty) {
      try {
        final resp = await dio.get(
          'https://api.injahow.cn/meting/',
          queryParameters: {
            'type': 'lrc',
            'id': widget.songId,
          },
        );
        if (resp.data is String && resp.data.toString().isNotEmpty) {
          rawLrc = resp.data.toString();
        }
      } catch (_) {}
    }

    if (rawLrc != null && rawLrc.isNotEmpty) {
      final parsed = _parseLrc(rawLrc, rawTrans);
      NetEaseMusicPlayer._lyricsCache[widget.songId] = parsed;
      if (mounted) {
        setState(() {
          _lyrics = parsed;
        });
      }
    } else {
      NetEaseMusicPlayer._lyricsCache[widget.songId] = const [];
      if (mounted) {
        setState(() {
          _lyrics = const [];
        });
      }
    }

    if (mounted) setState(() => _loadingLyrics = false);
  }

  List<LyricLine> _parseLrc(String lrcContent, [String? transContent]) {
    final Map<int, String> transMap = {};
    if (transContent != null && transContent.isNotEmpty) {
      for (final line in transContent.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final matches = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]')
            .allMatches(trimmed);
        final text = trimmed
            .replaceAll(RegExp(r'\[\d{1,2}:\d{1,2}(?:\.\d{1,3})?\]'), '')
            .trim();
        if (text.isEmpty) continue;
        for (final m in matches) {
          final min = int.tryParse(m.group(1) ?? '0') ?? 0;
          final sec = int.tryParse(m.group(2) ?? '0') ?? 0;
          var msStr = m.group(3) ?? '0';
          if (msStr.length == 1) msStr = '${msStr}00';
          if (msStr.length == 2) msStr = '${msStr}0';
          final ms = int.tryParse(msStr) ?? 0;
          final totalMs = min * 60000 + sec * 1000 + ms;
          final key = (totalMs / 100).round();
          transMap[key] = text;
        }
      }
    }

    final List<LyricLine> list = [];
    for (final line in lrcContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final matches = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]')
          .allMatches(trimmed);
      if (matches.isEmpty) continue;
      final text = trimmed
          .replaceAll(RegExp(r'\[\d{1,2}:\d{1,2}(?:\.\d{1,3})?\]'), '')
          .trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final min = int.tryParse(m.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(m.group(2) ?? '0') ?? 0;
        var msStr = m.group(3) ?? '0';
        if (msStr.length == 1) msStr = '${msStr}00';
        if (msStr.length == 2) msStr = '${msStr}0';
        final ms = int.tryParse(msStr) ?? 0;
        final totalMs = min * 60000 + sec * 1000 + ms;
        final key = (totalMs / 100).round();
        final trans =
            transMap[key] ?? transMap[key - 1] ?? transMap[key + 1];
        list.add(LyricLine(
          time: Duration(milliseconds: totalMs),
          text: text,
          translation: trans,
        ));
      }
    }

    list.sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  Future<void> _setVolume(double vol) async {
    final clamped = vol.clamp(0.0, 100.0);
    setState(() {
      _volume = clamped;
      if (_muted && clamped > 0) _muted = false;
      if (clamped == 0) _muted = true;
    });
    await _player?.setVolume(_muted ? 0.0 : _volume);
  }

  Future<void> _toggleMute() async {
    final nextMuted = !_muted;
    setState(() => _muted = nextMuted);
    await _player?.setVolume(nextMuted ? 0.0 : _volume);
  }

  Future<void> _seekRelative(int seconds) async {
    final p = _player;
    if (p == null) return;
    final cur = p.state.position;
    final dur = p.state.duration;
    final targetMs = (cur.inMilliseconds + seconds * 1000).clamp(0, dur.inMilliseconds > 0 ? dur.inMilliseconds : 1);
    await p.seek(Duration(milliseconds: targetMs));
  }

  Future<void> _changeSpeed() async {
    final p = _player;
    if (p == null) return;
    const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
    final nextIdx = (speeds.indexOf(_speed) + 1) % speeds.length;
    final nextSpeed = speeds[nextIdx];
    setState(() => _speed = nextSpeed);
    await p.setRate(nextSpeed);
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
      await p.setVolume(_muted ? 0.0 : _volume);
      await p.setRate(_speed);
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
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          if (event.scrollDelta.dy < 0) {
            _setVolume(((_muted ? 0.0 : _volume) + 5.0).clamp(0.0, 100.0));
          } else if (event.scrollDelta.dy > 0) {
            _setVolume(((_muted ? 0.0 : _volume) - 5.0).clamp(0.0, 100.0));
          }
        }
      },
      child: Container(
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
                    Text(
                      _title.isNotEmpty ? _title : '网易云音乐',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: _playing
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildWaveBars(theme),
                                    const SizedBox(width: 6),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                        Expanded(
                          child: Text(
                            _artist.isNotEmpty ? _artist : '歌曲 ID: ${widget.songId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
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
              // 歌词显示切换按钮
              Container(
                decoration: BoxDecoration(
                  color: _showLyrics
                      ? theme.colorScheme.primary.withAlpha(28)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  tooltip: _showLyrics ? '收起歌词' : '显示歌词',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _toggleLyrics,
                  icon: Icon(
                    _showLyrics ? Icons.lyrics_rounded : Icons.lyrics_outlined,
                    size: 18,
                    color: _showLyrics
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: '在浏览器打开',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
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
          _buildCompactLyrics(theme),
        ],
      ),
    ),
  );
}

  /// 紧凑型/大范围自适应滚动歌词条（上下带平滑渐隐虚化边缘，支持自由展开与收起）
  Widget _buildCompactLyrics(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final lyrics = _lyrics;
    final hasAnyTranslation = lyrics != null &&
        lyrics.any((l) => l.translation != null && l.translation!.isNotEmpty);
    final containerHeight = _largeLyrics
        ? 200.0
        : (hasAnyTranslation ? 64.0 : 52.0);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      child: _showLyrics
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(
                          height: 1,
                          thickness: 0.8,
                          color: colorScheme.outlineVariant.withAlpha(50),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          setState(() => _largeLyrics = !_largeLyrics);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scrollToActiveLyric();
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _largeLyrics
                                    ? Icons.unfold_less_rounded
                                    : Icons.unfold_more_rounded,
                                size: 13,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                _largeLyrics ? '紧凑' : '展开',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: containerHeight,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ShaderMask(
                      shaderCallback: (rect) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black,
                            Colors.black,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.22, 0.78, 1.0],
                        ).createShader(rect);
                      },
                      blendMode: BlendMode.dstIn,
                      child: _buildLyricsContent(theme, hasAnyTranslation),
                    ),
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildLyricsContent(ThemeData theme, bool hasAnyTranslation) {
    final colorScheme = theme.colorScheme;

    if (_loadingLyrics) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '歌词载入中...',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    final lyrics = _lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return Center(
        child: Text(
          '🎵 纯音乐，请欣赏',
          style: TextStyle(
            fontSize: 11.5,
            color: colorScheme.outline.withAlpha(180),
          ),
        ),
      );
    }

    final itemHeight = hasAnyTranslation ? 42.0 : 32.0;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        controller: _lyricScrollController,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: lyrics.length,
        itemExtent: itemHeight,
        itemBuilder: (ctx, i) {
          final line = lyrics[i];
          final isActive = i == _activeLyricIndex;
          final timeStr = _formatTime(line.time);

          return InkWell(
            onTap: () {
              _player?.seek(line.time);
            },
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: isActive
                            ? colorScheme.primary.withAlpha(220)
                            : colorScheme.outline.withAlpha(120),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isActive ? 12.5 : 11,
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.normal,
                              color: isActive
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant.withAlpha(150),
                            ),
                          ),
                          if (line.translation != null &&
                              line.translation!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              line.translation!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isActive ? 10.0 : 9.5,
                                color: isActive
                                    ? colorScheme.primary.withAlpha(200)
                                    : colorScheme.outline.withAlpha(130),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgress(ThemeData theme) {
    final player = _player;
    if (player == null) return const SizedBox.shrink();
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (ctx, snap) {
        final pos = _isDragging && _dragValue != null
            ? Duration(milliseconds: _dragValue!.toInt())
            : (snap.data ?? Duration.zero);
        final dur = player.state.duration;
        final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
        final curMs = pos.inMilliseconds.clamp(0, maxMs).toDouble();

        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
              Padding(
                padding: const EdgeInsets.only(top: 1, bottom: 2),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '快退 5 秒',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      icon: Icon(Icons.replay_5_rounded, color: theme.colorScheme.onSurfaceVariant),
                      onPressed: () => _seekRelative(-5),
                    ),
                    IconButton(
                      tooltip: '快进 5 秒',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      icon: Icon(Icons.forward_5_rounded, color: theme.colorScheme.onSurfaceVariant),
                      onPressed: () => _seekRelative(5),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: _changeSpeed,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        child: Text(
                          '${_speed == 1.0 ? "1.0" : _speed}x',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: _speed != 1.0 ? theme.colorScheme.primary : theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    _buildVolumeControl(theme),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVolumeControl(ThemeData theme) {
    final effectiveVol = _muted ? 0.0 : _volume;
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: _muted ? '取消静音' : '静音',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          icon: Icon(
            _muted || effectiveVol == 0
                ? Icons.volume_off_rounded
                : (effectiveVol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
            size: 17,
            color: _muted ? colorScheme.error : colorScheme.onSurfaceVariant,
          ),
          onPressed: _toggleMute,
        ),
        SizedBox(
          width: 62,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.outlineVariant.withAlpha(80),
              thumbColor: colorScheme.primary,
            ),
            child: Slider(
              value: effectiveVol,
              min: 0.0,
              max: 100.0,
              onChanged: (v) => _setVolume(v),
            ),
          ),
        ),
        Text(
          _muted ? '静音' : '${effectiveVol.round()}%',
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.outline,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
