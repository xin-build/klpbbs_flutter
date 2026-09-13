import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bilibili/bili_api.dart';
import '../bilibili/bili_models.dart';

/// B站标志性粉色高光强调色（用于已激活开关与高亮标记，基础色遵循应用主题）
const Color _kBiliPink = Color(0xFFFB7299);

/// 内嵌 B 站播放器（免登录 1080p + 画质切换 + 封面预览）
class BiliVideoPlayer extends StatefulWidget {
  static final Map<String, Player> _players = {};
  static final Map<String, VideoController> _controllers = {};
  static final Map<String, BiliVideoInfo> _infoCache = {};
  static final Map<String, List<BiliDanmakuItem>> _danmakuCache = {};
  static final Map<String, List<BiliSubtitleMeta>> _subtitlesCache = {};

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

class _BiliVideoPlayerState extends State<BiliVideoPlayer> with TickerProviderStateMixin {
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
  double _volume = 100.0;
  bool _showVolumeHud = false;
  Timer? _volumeHudTimer;
  bool _isHoveringVolume = false;

  Ticker? _ticker;
  Duration _lastPosition = Duration.zero;
  DateTime _lastPositionTime = DateTime.now();
  StreamSubscription<Duration>? _subPosition;
  StreamSubscription<bool>? _subPlaying;
  StreamSubscription<bool>? _subCompleted;

  final BiliDanmakuConfig _danmakuConfig = BiliDanmakuConfig();
  List<BiliDanmakuItem> _danmakus = [];
  List<BiliSubtitleMeta> _subtitles = [];
  BiliSubtitleMeta? _selectedSubtitle;
  List<BiliSubtitleLine> _subtitleLines = [];
  bool _subEnabled = true;
  bool _transEnabled = false;
  String _transLang = 'zh-CN';
  final Set<double> _translatingFrom = {};

  double get _currentSec {
    final p = _player;
    if (p == null) return 0.0;
    if (!_playing || !p.state.playing) {
      return p.state.position.inMilliseconds / 1000.0;
    }
    final elapsedMs = DateTime.now().difference(_lastPositionTime).inMilliseconds;
    if (elapsedMs < 0 || elapsedMs > 500) {
      return p.state.position.inMilliseconds / 1000.0;
    }
    final current = (_lastPosition.inMilliseconds + elapsedMs * _speed) / 1000.0;
    final dur = p.state.duration.inMilliseconds / 1000.0;
    if (dur > 0 && current > dur) return dur;
    return current.clamp(0.0, double.infinity);
  }

  void _checkTicker() {
    final shouldTick = _started && _playing && (_danmakuConfig.enabled || _selectedSubtitle != null);
    if (shouldTick) {
      if (_ticker == null) {
        _ticker = createTicker((_) {
          if (mounted) setState(() {});
        });
        _ticker!.start();
      } else if (!_ticker!.isTicking) {
        _ticker!.start();
      }
    } else {
      if (_ticker?.isTicking == true) {
        _ticker!.stop();
      }
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _volume = sp.getDouble('bili_player_volume') ?? 100.0;
        _danmakuConfig.enabled = sp.getBool('bili_dm_enabled') ?? true;
        _danmakuConfig.opacity = sp.getDouble('bili_dm_opacity') ?? 0.85;
        _danmakuConfig.fontSize = sp.getDouble('bili_dm_font_size') ?? 14.0;
        _danmakuConfig.speed = sp.getDouble('bili_dm_speed') ?? 1.0;
        _danmakuConfig.area = sp.getDouble('bili_dm_area') ?? 0.5;
        _danmakuConfig.hideTop = sp.getBool('bili_dm_hide_top') ?? false;
        _danmakuConfig.hideBottom = sp.getBool('bili_dm_hide_bottom') ?? false;
        _danmakuConfig.hideScroll = sp.getBool('bili_dm_hide_scroll') ?? false;
        _danmakuConfig.hideColor = sp.getBool('bili_dm_hide_color') ?? false;
        _danmakuConfig.blockedKeywords = sp.getStringList('bili_dm_blocked_keywords') ?? [];

        _subEnabled = sp.getBool('bili_sub_enabled') ?? true;
        _transEnabled = sp.getBool('bili_sub_trans_enabled') ?? false;
        _transLang = sp.getString('bili_sub_trans_lang') ?? 'zh-CN';
      });
      _player?.setVolume(_isMuted ? 0.0 : _volume);
      _checkTicker();
    } catch (_) {}
  }

  Future<void> _saveDanmakuConfig() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('bili_dm_enabled', _danmakuConfig.enabled);
      await sp.setDouble('bili_dm_opacity', _danmakuConfig.opacity);
      await sp.setDouble('bili_dm_font_size', _danmakuConfig.fontSize);
      await sp.setDouble('bili_dm_speed', _danmakuConfig.speed);
      await sp.setDouble('bili_dm_area', _danmakuConfig.area);
      await sp.setBool('bili_dm_hide_top', _danmakuConfig.hideTop);
      await sp.setBool('bili_dm_hide_bottom', _danmakuConfig.hideBottom);
      await sp.setBool('bili_dm_hide_scroll', _danmakuConfig.hideScroll);
      await sp.setBool('bili_dm_hide_color', _danmakuConfig.hideColor);
      await sp.setStringList('bili_dm_blocked_keywords', _danmakuConfig.blockedKeywords);
    } catch (_) {}
  }

  Future<void> _saveSubtitleConfig() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('bili_sub_enabled', _subEnabled);
      await sp.setBool('bili_sub_trans_enabled', _transEnabled);
      await sp.setString('bili_sub_trans_lang', _transLang);
    } catch (_) {}
  }

  Future<void> _loadDanmakuAndSubtitles() async {
    final info = _info;
    if (info == null) return;

    // 异步获取弹幕
    BiliApi.fetchDanmaku(info.cid).then((dms) {
      assignDanmakuTracks(dms);
      BiliVideoPlayer._danmakuCache[widget.bvid] = dms;
      if (mounted) {
        setState(() => _danmakus = dms);
        _checkTicker();
      }
    }).catchError((_) {});

    // 异步获取字幕
    BiliApi.fetchSubtitles(info.aid, info.cid).then((subs) {
      BiliVideoPlayer._subtitlesCache[widget.bvid] = subs;
      if (mounted) {
        setState(() => _subtitles = subs);
        if (subs.isNotEmpty && _subEnabled && _selectedSubtitle == null) {
          BiliSubtitleMeta? best;
          for (final s in subs) {
            if (s.lan == 'zh-CN' || s.lan == 'ai-zh') {
              best = s;
              break;
            }
          }
          best ??= subs.first;
          _selectSubtitle(best);
        }
      }
    }).catchError((_) {});
  }

  Future<void> _selectSubtitle(BiliSubtitleMeta? sub) async {
    setState(() {
      _selectedSubtitle = sub;
      _subtitleLines = [];
    });
    _checkTicker();
    if (sub == null) return;
    try {
      final lines = await BiliApi.fetchSubtitleContent(sub.subtitleUrl);
      if (mounted && _selectedSubtitle?.id == sub.id) {
        setState(() => _subtitleLines = lines);
        _checkTicker();
      }
    } catch (_) {}
  }

  BiliSubtitleLine? _findActiveSubtitle(double currentSec) {
    if (_selectedSubtitle == null || _subtitleLines.isEmpty) return null;
    for (final line in _subtitleLines) {
      if (line.from <= currentSec && currentSec <= line.to) {
        if (_transEnabled && (line.translation == null || line.translation!.isEmpty)) {
          _triggerTranslation(line);
        }
        return line;
      }
    }
    return null;
  }

  void _triggerTranslation(BiliSubtitleLine line) {
    if (_translatingFrom.contains(line.from)) return;
    _translatingFrom.add(line.from);
    BiliApi.translateText(line.content, targetLang: _transLang).then((trans) {
      if (trans != null && mounted) {
        setState(() => line.translation = trans);
      }
    }).catchError((_) {}).whenComplete(() {
      _translatingFrom.remove(line.from);
    });
  }

  void _shareTimestampLink() {
    final sec = _currentSec.toInt();
    final link = 'https://www.bilibili.com/video/${widget.bvid}?t=$sec';
    final durStr = _formatDuration(Duration(seconds: sec));
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制视频进度链接（时间戳 $durStr）：$link'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '浏览器打开',
          onPressed: () => _openExternal(Uri.parse(link)),
        ),
      ),
    );
    _showControlsTemporarily();
  }

  void _openDanmakuSettings(BuildContext context) {
    showDanmakuSettingsDialog(
      context,
      config: _danmakuConfig,
      onChanged: () {
        setState(() {});
        _checkTicker();
      },
      onSave: _saveDanmakuConfig,
    );
  }

  void _openSubtitleSettings(BuildContext context) {
    showSubtitleSettingsDialog(
      context,
      subtitles: _subtitles,
      selectedSubtitle: _selectedSubtitle,
      transEnabled: _transEnabled,
      transLang: _transLang,
      onSelectSubtitle: (sub) {
        _selectSubtitle(sub);
        _subEnabled = sub != null;
        _saveSubtitleConfig();
      },
      onToggleTrans: (val) {
        setState(() => _transEnabled = val);
        _saveSubtitleConfig();
      },
      onChangeTransLang: (lang) {
        setState(() => _transLang = lang);
        for (final l in _subtitleLines) {
          l.translation = null;
        }
        _saveSubtitleConfig();
      },
      onSave: _saveSubtitleConfig,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();

    final cachedInfo = BiliVideoPlayer._infoCache[widget.bvid];
    if (cachedInfo != null) {
      _info = cachedInfo;
    }
    final cachedDanmakus = BiliVideoPlayer._danmakuCache[widget.bvid];
    if (cachedDanmakus != null) {
      _danmakus = cachedDanmakus;
    }
    final cachedSubtitles = BiliVideoPlayer._subtitlesCache[widget.bvid];
    if (cachedSubtitles != null) {
      _subtitles = cachedSubtitles;
    }

    final existingController = BiliVideoPlayer._controllers[widget.bvid];
    final existingPlayer = BiliVideoPlayer._players[widget.bvid];
    if (existingController != null && existingPlayer != null) {
      _videoController = existingController;
      _player = existingPlayer;
      _started = true;
      _playing = existingPlayer.state.playing;
      _speed = existingPlayer.state.rate;
      _lastPosition = existingPlayer.state.position;
      _lastPositionTime = DateTime.now();
      _subPosition = existingPlayer.stream.position.listen((pos) {
        _lastPosition = pos;
        _lastPositionTime = DateTime.now();
      });
      _subPlaying = existingPlayer.stream.playing.listen((playing) {
        if (mounted) {
          setState(() => _playing = playing);
          _checkTicker();
        }
      });
      _subCompleted = existingPlayer.stream.completed.listen((completed) {
        if (mounted && completed) {
          setState(() => _playing = false);
          _checkTicker();
          _showControlsTemporarily();
        }
      });
      _checkTicker();
    }
    if (widget.autoFetchPreview && _info == null) {
      BiliApi.videoIntro(widget.bvid)
          .then((info) {
            if (mounted && info != null) {
              BiliVideoPlayer._infoCache[widget.bvid] = info;
              setState(() => _info = info);
              _loadDanmakuAndSubtitles();
            }
          })
          .catchError((_) {});
    } else if (_info != null && (_danmakus.isEmpty || _subtitles.isEmpty)) {
      _loadDanmakuAndSubtitles();
    }
  }

  @override
  void didUpdateWidget(covariant BiliVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bvid != widget.bvid) {
      _subPosition?.cancel();
      _subPlaying?.cancel();
      _subCompleted?.cancel();
      final existingController = BiliVideoPlayer._controllers[widget.bvid];
      final existingPlayer = BiliVideoPlayer._players[widget.bvid];
      if (existingController != null && existingPlayer != null) {
        _videoController = existingController;
        _player = existingPlayer;
        _started = true;
        _playing = existingPlayer.state.playing;
        _speed = existingPlayer.state.rate;
        _lastPosition = existingPlayer.state.position;
        _lastPositionTime = DateTime.now();
        _subPosition = existingPlayer.stream.position.listen((pos) {
          _lastPosition = pos;
          _lastPositionTime = DateTime.now();
        });
        _subPlaying = existingPlayer.stream.playing.listen((playing) {
          if (mounted) {
            setState(() => _playing = playing);
            _checkTicker();
          }
        });
        _subCompleted = existingPlayer.stream.completed.listen((completed) {
          if (mounted && completed) {
            setState(() => _playing = false);
            _checkTicker();
            _showControlsTemporarily();
          }
        });
        _checkTicker();
      } else {
        _videoController = null;
        _player = null;
        _started = false;
        _playing = false;
        if (_ticker?.isTicking == true) _ticker!.stop();
      }
      _info = BiliVideoPlayer._infoCache[widget.bvid];
      _danmakus = BiliVideoPlayer._danmakuCache[widget.bvid] ?? [];
      _subtitles = BiliVideoPlayer._subtitlesCache[widget.bvid] ?? [];
      if (_info == null && widget.autoFetchPreview) {
        BiliApi.videoIntro(widget.bvid).then((info) {
          if (mounted && info != null) {
            BiliVideoPlayer._infoCache[widget.bvid] = info;
            setState(() => _info = info);
            _loadDanmakuAndSubtitles();
          }
        }).catchError((_) {});
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _volumeHudTimer?.cancel();
    _subPosition?.cancel();
    _subPlaying?.cancel();
    _subCompleted?.cancel();
    _ticker?.dispose();
    _ticker = null;
    _hideTimer?.cancel();
    super.dispose();
  }

  bool _isHoveringControls = false;
  bool _isDragging = false;
  double? _dragValue;

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
      try {
        final platform = player.platform as dynamic;
        await platform.setProperty(
          'http-header-fields',
          'Referer: https://www.bilibili.com\r\n'
          'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36\r\n',
        );
        await platform.setProperty('referrer', 'https://www.bilibili.com');
        await platform.setProperty(
          'user-agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        );
      } catch (e) {
        debugPrint('Failed to set mpv properties: $e');
      }

      final videoController = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          hwdec: 'auto-safe',
        ),
      );
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

      _subPosition?.cancel();
      _subPosition = player.stream.position.listen((pos) {
        _lastPosition = pos;
        _lastPositionTime = DateTime.now();
      });
      _subPlaying?.cancel();
      _subPlaying = player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _playing = playing;
            _lastPosition = player.state.position;
            _lastPositionTime = DateTime.now();
          });
          _checkTicker();
        }
      });
      _subCompleted?.cancel();
      _subCompleted = player.stream.completed.listen((completed) {
        if (mounted && completed) {
          setState(() => _playing = false);
          _checkTicker();
          _showControlsTemporarily();
        }
      });

      setState(() {
        _player = player;
        _videoController = videoController;
        _started = true;
        _playing = true;
        _speed = 1.0;
        _lastPosition = Duration.zero;
        _lastPositionTime = DateTime.now();
      });
      await player.setVolume(_isMuted ? 0.0 : _volume);
      _loadDanmakuAndSubtitles();
      _checkTicker();
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
    await player.playOrPause();
    if (mounted) {
      setState(() {
        _playing = player.state.playing;
        _lastPosition = player.state.position;
        _lastPositionTime = DateTime.now();
      });
      _checkTicker();
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
    _lastPosition = Duration(milliseconds: targetMs);
    _lastPositionTime = DateTime.now();
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

  Future<void> _setVolume(double vol, {bool showHud = true}) async {
    final clamped = vol.clamp(0.0, 100.0);
    setState(() {
      _volume = clamped;
      if (_isMuted && clamped > 0) _isMuted = false;
      if (clamped == 0) _isMuted = true;
      if (showHud) _showVolumeHud = true;
    });
    await _player?.setVolume(_isMuted ? 0.0 : _volume);
    if (showHud) {
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('bili_player_volume', _volume);
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    if (_isMuted) {
      final target = _volume > 0 ? _volume : 100.0;
      await _setVolume(target, showHud: true);
    } else {
      setState(() {
        _isMuted = true;
        _showVolumeHud = true;
      });
      await _player?.setVolume(0.0);
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }
    _showControlsTemporarily();
  }

  Widget _buildVolumeControl(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final effectiveVol = _isMuted ? 0.0 : _volume;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringVolume = true),
      onExit: (_) => setState(() => _isHoveringVolume = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _isMuted ? '取消静音' : '静音',
            icon: Icon(
              _isMuted || effectiveVol == 0
                  ? Icons.volume_off_rounded
                  : (effectiveVol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
              color: Colors.white70,
              size: 19,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: _toggleMute,
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isHoveringVolume ? 72 : 0,
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

  Widget _buildVolumeHud(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final effectiveVol = _isMuted ? 0.0 : _volume;
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
                  _isMuted || effectiveVol == 0
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
                  _isMuted ? '静音' : '${effectiveVol.round()}%',
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

  Widget _buildProgressBar() {
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

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SliderTheme(
            data: SliderTheme.of(ctx).copyWith(
              trackHeight: 2.5,
              activeTrackColor: Theme.of(ctx).colorScheme.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: Theme.of(ctx).colorScheme.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: pos.inMilliseconds.clamp(0, maxMs).toDouble(),
              max: maxMs.toDouble(),
              onChangeStart: (v) {
                setState(() {
                  _isDragging = true;
                  _dragValue = v;
                });
                _hideTimer?.cancel();
                if (!_controlsVisible) {
                  setState(() => _controlsVisible = true);
                }
              },
              onChanged: (v) {
                setState(() => _dragValue = v);
              },
              onChangeEnd: (v) {
                player.seek(Duration(milliseconds: v.toInt()));
                setState(() {
                  _isDragging = false;
                  _dragValue = null;
                  _lastPosition = Duration(milliseconds: v.toInt());
                  _lastPositionTime = DateTime.now();
                });
                _showControlsTemporarily();
              },
            ),
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
          initialVolume: _volume,
          initialMuted: _isMuted,
          onVolumeChanged: (vol, muted) {
            setState(() {
              _volume = vol;
              _isMuted = muted;
            });
          },
          onSpeedChanged: _setSpeed,
          data: _data,
          currentVideo: _currentVideo,
          onQualityChanged: (video, audio) => _switchQuality(video, audio),
          formatDuration: _formatDuration,
          danmakus: _danmakus,
          danmakuConfig: _danmakuConfig,
          subtitles: _subtitles,
          selectedSubtitle: _selectedSubtitle,
          subtitleLines: _subtitleLines,
          transEnabled: _transEnabled,
          transLang: _transLang,
          onSubtitleSelected: (sub) => _selectSubtitle(sub),
          onTransEnabledChanged: (v) {
            setState(() => _transEnabled = v);
            _saveSubtitleConfig();
          },
          onTransLangChanged: (lang) {
            setState(() => _transLang = lang);
            for (final l in _subtitleLines) {
              l.translation = null;
            }
            _saveSubtitleConfig();
          },
          onConfigChanged: () {
            setState(() {});
            _checkTicker();
            _saveDanmakuConfig();
          },
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _playing = _player?.state.playing ?? false;
          _lastPosition = _player?.state.position ?? Duration.zero;
          _lastPositionTime = DateTime.now();
        });
        _checkTicker();
      }
    });
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
    final currentPos = player.state.position;
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
      if (currentPos > Duration.zero) {
        await player.seek(currentPos);
      }
      if (mounted) {
        setState(() {
          _playing = true;
          _lastPosition = currentPos;
          _lastPositionTime = DateTime.now();
        });
        _checkTicker();
      }
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
      final theme = Theme.of(context);
      final popupBg = theme.colorScheme.surfaceContainerHigh;
      final outline = theme.colorScheme.outlineVariant;

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: MouseRegion(
            onHover: (_) => _showControlsTemporarily(),
            onEnter: (_) => _showControlsTemporarily(),
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  if (event.scrollDelta.dy < 0) {
                    _setVolume(((_isMuted ? 0.0 : _volume) + 5.0).clamp(0.0, 100.0));
                  } else if (event.scrollDelta.dy > 0) {
                    _setVolume(((_isMuted ? 0.0 : _volume) - 5.0).clamp(0.0, 100.0));
                  }
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. 视频画面与手势
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
                            _setVolume(((_isMuted ? 0.0 : _volume) + delta).clamp(0.0, 100.0));
                          }
                        },
                        child: Video(
                          controller: controller,
                          controls: NoVideoControls,
                          fit: BoxFit.contain,
                        ),
                      );
                    },
                  ),

                  // 2. 弹幕层（在视频画面之上，手势穿透）
                  if (_danmakuConfig.enabled && _danmakus.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: BiliDanmakuPainter(
                            danmakus: _danmakus,
                            currentSec: _currentSec,
                            config: _danmakuConfig,
                          ),
                        ),
                      ),
                    ),

                  // 3. 字幕层（在视频画面之上，手势穿透）
                  if (_selectedSubtitle != null)
                    Positioned(
                      bottom: _controlsVisible ? 78.0 : 16.0,
                      left: 14.0,
                      right: 14.0,
                      child: IgnorePointer(
                        child: BiliSubtitleView(
                          activeLine: _findActiveSubtitle(_currentSec),
                          transEnabled: _transEnabled,
                        ),
                      ),
                    ),

                  // 音量 HUD 指示器
                  _buildVolumeHud(context),

                  // 4. 居中暂停指示图标
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

                  // 5. 顶部阴影与信息栏
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
                                  color: _kBiliPink,
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

                  // 6. 底部全功能现代控制栏
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
                            constraints: const BoxConstraints(maxHeight: 90),
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
                                        icon: AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 200),
                                          child: Icon(
                                            _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                            key: ValueKey<bool>(_playing),
                                            color: Colors.white,
                                            size: 24,
                                          ),
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
                                      // 音量调节（含滑块与静音）
                                      _buildVolumeControl(context),

                                      // 播放时间进度
                                      StreamBuilder<Duration>(
                                        stream: _player?.stream.position,
                                        builder: (ctx, snap) {
                                          final pos = _isDragging && _dragValue != null
                                              ? Duration(milliseconds: _dragValue!.toInt())
                                              : (snap.data ?? Duration.zero);
                                          final dur = _player?.state.duration ?? Duration.zero;
                                          return Padding(
                                            padding: const EdgeInsets.only(left: 6),
                                            child: Text(
                                              '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                fontFeatures: [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          );
                                        },
                                      ),

                                      const Spacer(),

                                      // 弹幕开关
                                      IconButton(
                                        tooltip: _danmakuConfig.enabled ? '关闭弹幕' : '开启弹幕',
                                        icon: Icon(
                                          _danmakuConfig.enabled ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                                          color: _danmakuConfig.enabled ? _kBiliPink : Colors.white70,
                                          size: 19,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setState(() {
                                            _danmakuConfig.enabled = !_danmakuConfig.enabled;
                                          });
                                          _checkTicker();
                                          _saveDanmakuConfig();
                                          _showControlsTemporarily();
                                        },
                                      ),
                                      // 弹幕设置
                                      IconButton(
                                        tooltip: '弹幕设置',
                                        icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 19),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _openDanmakuSettings(context),
                                      ),
                                      // 字幕与智能翻译
                                      IconButton(
                                        tooltip: _selectedSubtitle != null ? '字幕与翻译（已开启）' : '字幕与翻译（已关闭）',
                                        icon: Icon(
                                          _selectedSubtitle != null ? Icons.closed_caption_rounded : Icons.closed_caption_disabled_rounded,
                                          color: _selectedSubtitle != null ? _kBiliPink : Colors.white70,
                                          size: 21,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _openSubtitleSettings(context),
                                      ),
                                      // 分享当前进度链接
                                      IconButton(
                                        tooltip: '分享带时间戳链接',
                                        icon: const Icon(Icons.share_rounded, color: Colors.white70, size: 18),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: _shareTimestampLink,
                                      ),

                                      // 倍速选择
                                      PopupMenuButton<double>(
                                        initialValue: _speed,
                                        tooltip: '播放倍速',
                                        color: popupBg,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          side: BorderSide(color: outline.withAlpha(60), width: 0.6),
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
                                                        ? const Icon(Icons.check_rounded, color: _kBiliPink, size: 16)
                                                        : null,
                                                  ),
                                                  Text(
                                                    '${sp}x 倍速',
                                                    style: TextStyle(
                                                      color: sp == _speed ? _kBiliPink : Colors.white,
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
                                          color: popupBg,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                            side: BorderSide(color: outline.withAlpha(60), width: 0.6),
                                          ),
                                          onSelected: (id) {
                                            final video = _data?.getBestVideoForQuality(id) ??
                                                _data!.videos.firstWhere(
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
                                                            ? const Icon(Icons.check_rounded, color: _kBiliPink, size: 16)
                                                            : null,
                                                      ),
                                                      Text(
                                                        _qualityLabel(id),
                                                        style: TextStyle(
                                                          color: id == (_currentVideo?.id ?? -1)
                                                              ? _kBiliPink
                                                              : Colors.white,
                                                          fontSize: 12.5,
                                                          fontWeight: id == (_currentVideo?.id ?? -1) ? FontWeight.bold : FontWeight.normal,
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
                            color: _kBiliPink,
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

/// 为弹幕列表智能分配轨道以避免文字重叠
void assignDanmakuTracks(List<BiliDanmakuItem> items, {int trackCount = 10}) {
  if (items.isEmpty || trackCount <= 0) return;
  final trackEndTime = List<double>.filled(trackCount, 0.0);
  final topEndTime = List<double>.filled(4, 0.0);
  final bottomEndTime = List<double>.filled(4, 0.0);

  for (final item in items) {
    if (item.isScroll) {
      int bestTrack = 0;
      double minEnd = double.infinity;
      for (int i = 0; i < trackCount; i++) {
        if (trackEndTime[i] <= item.time) {
          bestTrack = i;
          break;
        }
        if (trackEndTime[i] < minEnd) {
          minEnd = trackEndTime[i];
          bestTrack = i;
        }
      }
      item.track = bestTrack;
      // 预估约 1.8 秒后弹幕尾部完全滑入屏幕
      trackEndTime[bestTrack] = item.time + 1.8;
    } else if (item.isTop) {
      int bestTrack = 0;
      for (int i = 0; i < 4; i++) {
        if (topEndTime[i] <= item.time) {
          bestTrack = i;
          break;
        }
      }
      item.track = bestTrack;
      topEndTime[bestTrack] = item.time + 4.0;
    } else if (item.isBottom) {
      int bestTrack = 0;
      for (int i = 0; i < 4; i++) {
        if (bottomEndTime[i] <= item.time) {
          bestTrack = i;
          break;
        }
      }
      item.track = bestTrack;
      bottomEndTime[bestTrack] = item.time + 4.0;
    }
  }
}

/// 弹幕高性能 Canvas 渲染引擎
class BiliDanmakuPainter extends CustomPainter {
  final List<BiliDanmakuItem> danmakus;
  final double currentSec;
  final BiliDanmakuConfig config;

  BiliDanmakuPainter({
    required this.danmakus,
    required this.currentSec,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!config.enabled || danmakus.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }

    final double availableHeight = size.height * config.area;
    final double lineHeight = (config.fontSize * 1.45).clamp(16.0, 38.0);
    final int maxTracks = (availableHeight / lineHeight).floor().clamp(1, 24);

    final double scrollDuration = (6.0 / config.speed).clamp(2.0, 15.0);
    const double fixedDuration = 4.0;

    final double maxWindow = scrollDuration > fixedDuration ? scrollDuration : fixedDuration;
    final double minTime = currentSec - maxWindow;
    final double maxTime = currentSec;

    int startIndex = _lowerBound(danmakus, minTime);
    if (startIndex < 0) startIndex = 0;

    for (int i = startIndex; i < danmakus.length; i++) {
      final dm = danmakus[i];
      if (dm.time > maxTime) break;
      if (config.isBlocked(dm)) continue;

      if (dm.isScroll) {
        final double elapsed = currentSec - dm.time;
        if (elapsed < 0 || elapsed > scrollDuration) continue;
        final double progress = elapsed / scrollDuration; // 0.0 -> 1.0

        final tp = _createTextPainter(dm.text, dm.displayColor, config.fontSize, config.opacity);
        tp.layout();

        final double x = size.width - progress * (size.width + tp.width);
        final int track = dm.track % maxTracks;
        final double y = track * lineHeight + 4.0;

        _drawTextWithStroke(canvas, tp, Offset(x, y), config.fontSize, config.opacity);
      } else if (dm.isTop) {
        final double elapsed = currentSec - dm.time;
        if (elapsed < 0 || elapsed > fixedDuration) continue;

        final tp = _createTextPainter(dm.text, dm.displayColor, config.fontSize, config.opacity);
        tp.layout();

        final double x = (size.width - tp.width) / 2;
        final int track = dm.track % (maxTracks > 3 ? 3 : maxTracks);
        final double y = track * lineHeight + 6.0;

        _drawTextWithStroke(canvas, tp, Offset(x, y), config.fontSize, config.opacity);
      } else if (dm.isBottom) {
        final double elapsed = currentSec - dm.time;
        if (elapsed < 0 || elapsed > fixedDuration) continue;

        final tp = _createTextPainter(dm.text, dm.displayColor, config.fontSize, config.opacity);
        tp.layout();

        final double x = (size.width - tp.width) / 2;
        final int track = dm.track % (maxTracks > 3 ? 3 : maxTracks);
        final double y = size.height - (track + 1) * lineHeight - 32.0;

        _drawTextWithStroke(canvas, tp, Offset(x, y), config.fontSize, config.opacity);
      }
    }
  }

  static int _lowerBound(List<BiliDanmakuItem> list, double time) {
    int low = 0;
    int high = list.length - 1;
    int ans = list.length;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (list[mid].time >= time) {
        ans = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return ans;
  }

  TextPainter _createTextPainter(String text, Color color, double fontSize, double opacity) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withOpacity((opacity * color.opacity).clamp(0.0, 1.0)),
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
  }

  void _drawTextWithStroke(Canvas canvas, TextPainter tp, Offset offset, double fontSize, double opacity) {
    final strokeTp = TextPainter(
      text: TextSpan(
        text: (tp.text as TextSpan).text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = Colors.black.withOpacity((opacity * 0.9).clamp(0.0, 1.0)),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    strokeTp.layout();
    strokeTp.paint(canvas, offset);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant BiliDanmakuPainter oldDelegate) {
    return oldDelegate.currentSec != currentSec ||
        oldDelegate.config.opacity != config.opacity ||
        oldDelegate.config.fontSize != config.fontSize ||
        oldDelegate.config.speed != config.speed ||
        oldDelegate.config.area != config.area ||
        oldDelegate.config.enabled != config.enabled ||
        oldDelegate.danmakus != danmakus;
  }
}

/// 优雅的悬浮字幕展示组件（支持双语对照与主题融合）
class BiliSubtitleView extends StatelessWidget {
  final BiliSubtitleLine? activeLine;
  final bool transEnabled;

  const BiliSubtitleView({
    super.key,
    required this.activeLine,
    required this.transEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final line = activeLine;
    if (line == null || line.content.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final transColor = cs.primaryContainer.withAlpha(240);

    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Container(
          key: ValueKey<double>(line.from),
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(165),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                line.content,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
              ),
              if (transEnabled && line.translation != null && line.translation!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  line.translation!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: transColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹幕配置与屏蔽词管理对话框
void showDanmakuSettingsDialog(
  BuildContext context, {
  required BiliDanmakuConfig config,
  required VoidCallback onChanged,
  required VoidCallback onSave,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final keywordController = TextEditingController();

          return AlertDialog(
            backgroundColor: theme.dialogTheme.backgroundColor ?? cs.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withAlpha(60), width: 1),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            title: Row(
              children: [
                Icon(Icons.tune_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  '弹幕设置与屏蔽',
                  style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      config.opacity = 0.85;
                      config.fontSize = 14.0;
                      config.speed = 1.0;
                      config.area = 0.5;
                      config.hideTop = false;
                      config.hideBottom = false;
                      config.hideScroll = false;
                      config.hideColor = false;
                    });
                    onChanged();
                    onSave();
                  },
                  child: Text('恢复默认', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 不透明度
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('不透明度', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        Text('${(config.opacity * 100).toInt()}%',
                            style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(dialogCtx).copyWith(
                        activeTrackColor: cs.primary,
                        inactiveTrackColor: cs.outlineVariant.withAlpha(80),
                        thumbColor: cs.primary,
                      ),
                      child: Slider(
                        value: config.opacity,
                        min: 0.1,
                        max: 1.0,
                        divisions: 18,
                        onChanged: (v) {
                          setDialogState(() => config.opacity = v);
                          onChanged();
                          onSave();
                        },
                      ),
                    ),

                    // 字体大小
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('弹幕字号', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        Text('${config.fontSize.toInt()} px',
                            style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(dialogCtx).copyWith(
                        activeTrackColor: cs.primary,
                        inactiveTrackColor: cs.outlineVariant.withAlpha(80),
                        thumbColor: cs.primary,
                      ),
                      child: Slider(
                        value: config.fontSize,
                        min: 10.0,
                        max: 24.0,
                        divisions: 14,
                        onChanged: (v) {
                          setDialogState(() => config.fontSize = v);
                          onChanged();
                          onSave();
                        },
                      ),
                    ),

                    // 弹幕速度
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('飘字速度', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        Text('${config.speed}x',
                            style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(dialogCtx).copyWith(
                        activeTrackColor: cs.primary,
                        inactiveTrackColor: cs.outlineVariant.withAlpha(80),
                        thumbColor: cs.primary,
                      ),
                      child: Slider(
                        value: config.speed,
                        min: 0.5,
                        max: 2.0,
                        divisions: 6,
                        onChanged: (v) {
                          setDialogState(() => config.speed = v);
                          onChanged();
                          onSave();
                        },
                      ),
                    ),

                    const SizedBox(height: 6),
                    Text('显示区域', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final areaItem in [
                          (0.25, '1/4 屏'),
                          (0.5, '半屏'),
                          (0.75, '3/4 屏'),
                          (1.0, '全屏'),
                        ])
                          ChoiceChip(
                            label: Text(areaItem.$2),
                            selected: (config.area - areaItem.$1).abs() < 0.05,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: (config.area - areaItem.$1).abs() < 0.05 ? cs.onPrimary : cs.onSurfaceVariant,
                            ),
                            selectedColor: cs.primary,
                            backgroundColor: cs.surfaceContainerHighest.withAlpha(120),
                            onSelected: (sel) {
                              if (sel) {
                                setDialogState(() => config.area = areaItem.$1);
                                onChanged();
                                onSave();
                              }
                            },
                          ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Divider(color: cs.outlineVariant.withAlpha(50), height: 1),
                    const SizedBox(height: 12),

                    Text('弹幕类型屏蔽', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilterChip(
                          label: const Text('屏蔽滚动'),
                          selected: config.hideScroll,
                          selectedColor: cs.errorContainer,
                          backgroundColor: cs.surfaceContainerHighest.withAlpha(120),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: config.hideScroll ? cs.onErrorContainer : cs.onSurfaceVariant,
                          ),
                          onSelected: (val) {
                            setDialogState(() => config.hideScroll = val);
                            onChanged();
                            onSave();
                          },
                        ),
                        FilterChip(
                          label: const Text('屏蔽顶部'),
                          selected: config.hideTop,
                          selectedColor: cs.errorContainer,
                          backgroundColor: cs.surfaceContainerHighest.withAlpha(120),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: config.hideTop ? cs.onErrorContainer : cs.onSurfaceVariant,
                          ),
                          onSelected: (val) {
                            setDialogState(() => config.hideTop = val);
                            onChanged();
                            onSave();
                          },
                        ),
                        FilterChip(
                          label: const Text('屏蔽底部'),
                          selected: config.hideBottom,
                          selectedColor: cs.errorContainer,
                          backgroundColor: cs.surfaceContainerHighest.withAlpha(120),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: config.hideBottom ? cs.onErrorContainer : cs.onSurfaceVariant,
                          ),
                          onSelected: (val) {
                            setDialogState(() => config.hideBottom = val);
                            onChanged();
                            onSave();
                          },
                        ),
                        FilterChip(
                          label: const Text('屏蔽彩色'),
                          selected: config.hideColor,
                          selectedColor: cs.errorContainer,
                          backgroundColor: cs.surfaceContainerHighest.withAlpha(120),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: config.hideColor ? cs.onErrorContainer : cs.onSurfaceVariant,
                          ),
                          onSelected: (val) {
                            setDialogState(() => config.hideColor = val);
                            onChanged();
                            onSave();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Divider(color: cs.outlineVariant.withAlpha(50), height: 1),
                    const SizedBox(height: 12),

                    Text('关键词屏蔽', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: keywordController,
                            style: TextStyle(color: cs.onSurface, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: '输入要屏蔽的词语...',
                              hintStyle: TextStyle(color: cs.onSurfaceVariant.withAlpha(140), fontSize: 12.5),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              filled: true,
                              fillColor: cs.surfaceContainerHighest.withAlpha(120),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: cs.outlineVariant.withAlpha(80)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: cs.outlineVariant.withAlpha(80)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: cs.primary, width: 1.6),
                              ),
                            ),
                            onSubmitted: (val) {
                              final trimmed = val.trim();
                              if (trimmed.isNotEmpty && !config.blockedKeywords.contains(trimmed)) {
                                setDialogState(() {
                                  config.blockedKeywords.add(trimmed);
                                  keywordController.clear();
                                });
                                onChanged();
                                onSave();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: () {
                            final trimmed = keywordController.text.trim();
                            if (trimmed.isNotEmpty && !config.blockedKeywords.contains(trimmed)) {
                              setDialogState(() {
                                config.blockedKeywords.add(trimmed);
                                keywordController.clear();
                              });
                              onChanged();
                              onSave();
                            }
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('添加', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (config.blockedKeywords.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '暂无屏蔽词，支持精确词或模糊关键词',
                          style: TextStyle(color: cs.onSurfaceVariant.withAlpha(140), fontSize: 11.5),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final kw in config.blockedKeywords)
                            Chip(
                              label: Text(kw, style: TextStyle(fontSize: 12, color: cs.onSurface)),
                              backgroundColor: cs.surfaceContainerHighest,
                              deleteIcon: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
                              side: BorderSide(color: cs.outlineVariant.withAlpha(60), width: 0.6),
                              onDeleted: () {
                                setDialogState(() {
                                  config.blockedKeywords.remove(kw);
                                });
                                onChanged();
                                onSave();
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// 字幕与智能翻译配置对话框
void showSubtitleSettingsDialog(
  BuildContext context, {
  required List<BiliSubtitleMeta> subtitles,
  required BiliSubtitleMeta? selectedSubtitle,
  required bool transEnabled,
  required String transLang,
  required ValueChanged<BiliSubtitleMeta?> onSelectSubtitle,
  required ValueChanged<bool> onToggleTrans,
  required ValueChanged<String> onChangeTransLang,
  required VoidCallback onSave,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: theme.dialogTheme.backgroundColor ?? cs.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant.withAlpha(60), width: 1),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            title: Row(
              children: [
                Icon(Icons.closed_caption_rounded, color: cs.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  '字幕与翻译设置',
                  style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('选择字幕语言', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (subtitles.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withAlpha(120),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '该视频未提供官方或 AI 识别字幕',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      RadioListTile<int?>(
                        value: null,
                        groupValue: selectedSubtitle?.id,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: cs.primary,
                        title: Text('关闭字幕', style: TextStyle(color: cs.onSurface, fontSize: 13)),
                        onChanged: (_) {
                          setDialogState(() {
                            selectedSubtitle = null;
                          });
                          onSelectSubtitle(null);
                          onSave();
                        },
                      ),
                      for (final sub in subtitles)
                        RadioListTile<int?>(
                          value: sub.id,
                          groupValue: selectedSubtitle?.id,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: cs.primary,
                          title: Row(
                            children: [
                              Text(
                                sub.lanDoc.isNotEmpty ? sub.lanDoc : sub.lan,
                                style: TextStyle(color: cs.onSurface, fontSize: 13),
                              ),
                              if (sub.isAi) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withAlpha(30),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: cs.primary.withAlpha(120), width: 0.6),
                                  ),
                                  child: Text(
                                    'AI识别',
                                    style: TextStyle(
                                      color: cs.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          onChanged: (_) {
                            setDialogState(() {
                              selectedSubtitle = sub;
                            });
                            onSelectSubtitle(sub);
                            onSave();
                          },
                        ),
                    ],

                    const SizedBox(height: 12),
                    Divider(color: cs.outlineVariant.withAlpha(50), height: 1),
                    const SizedBox(height: 12),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('开启双语对照翻译', style: TextStyle(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('在原字幕下方同步展示 AI / GTX 实时翻译', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5)),
                      activeColor: cs.primary,
                      value: transEnabled,
                      onChanged: (val) {
                        setDialogState(() => transEnabled = val);
                        onToggleTrans(val);
                        onSave();
                      },
                    ),

                    if (transEnabled) ...[
                      const SizedBox(height: 8),
                      Text('翻译目标语言：', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final lang in [
                            ('zh-CN', '简体中文'),
                            ('en', '英语'),
                            ('ja', '日语'),
                            ('ko', '韩语'),
                            ('zh-TW', '繁体中文'),
                            ('fr', '法语'),
                            ('de', '德语'),
                            ('ru', '俄语'),
                          ])
                            ChoiceChip(
                              label: Text(lang.$2),
                              selected: transLang == lang.$1,
                              selectedColor: cs.primary,
                              backgroundColor: cs.surfaceContainerHighest.withAlpha(120),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                color: transLang == lang.$1 ? cs.onPrimary : cs.onSurfaceVariant,
                              ),
                              onSelected: (sel) {
                                if (sel) {
                                  setDialogState(() => transLang = lang.$1);
                                  onChangeTransLang(lang.$1);
                                  onSave();
                                }
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// 独立的现代化全屏 B 站播放器页面（含全功能弹幕、字幕、手势与悬浮控制器）
class _FullscreenBiliPlayer extends StatefulWidget {
  final VideoController controller;
  final Player? player;
  final String title;
  final String bvid;
  final double speed;
  final double initialVolume;
  final bool initialMuted;
  final void Function(double volume, bool isMuted)? onVolumeChanged;
  final ValueChanged<double> onSpeedChanged;
  final BiliPlayUrlData? data;
  final BiliDashItem? currentVideo;
  final void Function(BiliDashItem video, BiliDashItem? audio) onQualityChanged;
  final String Function(Duration) formatDuration;
  final List<BiliDanmakuItem> danmakus;
  final BiliDanmakuConfig danmakuConfig;
  final List<BiliSubtitleMeta> subtitles;
  final BiliSubtitleMeta? selectedSubtitle;
  final List<BiliSubtitleLine> subtitleLines;
  final bool transEnabled;
  final String transLang;
  final ValueChanged<BiliSubtitleMeta?> onSubtitleSelected;
  final ValueChanged<bool> onTransEnabledChanged;
  final ValueChanged<String> onTransLangChanged;
  final VoidCallback onConfigChanged;

  const _FullscreenBiliPlayer({
    required this.controller,
    required this.player,
    required this.title,
    required this.bvid,
    required this.speed,
    this.initialVolume = 100.0,
    this.initialMuted = false,
    this.onVolumeChanged,
    required this.onSpeedChanged,
    required this.data,
    required this.currentVideo,
    required this.onQualityChanged,
    required this.formatDuration,
    required this.danmakus,
    required this.danmakuConfig,
    required this.subtitles,
    required this.selectedSubtitle,
    required this.subtitleLines,
    required this.transEnabled,
    required this.transLang,
    required this.onSubtitleSelected,
    required this.onTransEnabledChanged,
    required this.onTransLangChanged,
    required this.onConfigChanged,
  });

  @override
  State<_FullscreenBiliPlayer> createState() => _FullscreenBiliPlayerState();
}

class _FullscreenBiliPlayerState extends State<_FullscreenBiliPlayer> with TickerProviderStateMixin {
  bool _controlsVisible = true;
  Timer? _hideTimer;
  late double _speed;
  bool _playing = true;
  bool _isHoveringControls = false;
  bool _isDragging = false;
  double? _dragValue;
  StreamSubscription? _subPlaying;
  StreamSubscription? _subCompleted;
  StreamSubscription? _subPosition;

  late double _volume;
  late bool _isMuted;
  bool _showVolumeHud = false;
  Timer? _volumeHudTimer;
  bool _isHoveringVolume = false;

  Ticker? _ticker;
  Duration _lastPosition = Duration.zero;
  DateTime _lastPositionTime = DateTime.now();

  late BiliDanmakuConfig _danmakuConfig;
  late List<BiliDanmakuItem> _danmakus;
  late List<BiliSubtitleMeta> _subtitles;
  BiliSubtitleMeta? _selectedSubtitle;
  late List<BiliSubtitleLine> _subtitleLines;
  late bool _transEnabled;
  late String _transLang;
  final Set<double> _translatingFrom = {};

  double get _currentSec {
    final p = widget.player;
    if (p == null) return 0.0;
    if (!_playing || !p.state.playing) {
      return p.state.position.inMilliseconds / 1000.0;
    }
    final elapsedMs = DateTime.now().difference(_lastPositionTime).inMilliseconds;
    if (elapsedMs < 0 || elapsedMs > 500) {
      return p.state.position.inMilliseconds / 1000.0;
    }
    final current = (_lastPosition.inMilliseconds + elapsedMs * _speed) / 1000.0;
    final dur = p.state.duration.inMilliseconds / 1000.0;
    if (dur > 0 && current > dur) return dur;
    return current.clamp(0.0, double.infinity);
  }

  void _checkTicker() {
    final shouldTick = _playing && (_danmakuConfig.enabled || _selectedSubtitle != null);
    if (shouldTick) {
      if (_ticker == null) {
        _ticker = createTicker((_) {
          if (mounted) setState(() {});
        });
        _ticker!.start();
      } else if (!_ticker!.isTicking) {
        _ticker!.start();
      }
    } else {
      if (_ticker?.isTicking == true) {
        _ticker!.stop();
      }
    }
  }

  BiliSubtitleLine? _findActiveSubtitle(double currentSec) {
    if (_selectedSubtitle == null || _subtitleLines.isEmpty) return null;
    for (final line in _subtitleLines) {
      if (line.from <= currentSec && currentSec <= line.to) {
        if (_transEnabled && (line.translation == null || line.translation!.isEmpty)) {
          _triggerTranslation(line);
        }
        return line;
      }
    }
    return null;
  }

  void _triggerTranslation(BiliSubtitleLine line) {
    if (_translatingFrom.contains(line.from)) return;
    _translatingFrom.add(line.from);
    BiliApi.translateText(line.content, targetLang: _transLang).then((trans) {
      if (trans != null && mounted) {
        setState(() => line.translation = trans);
      }
    }).catchError((_) {}).whenComplete(() {
      _translatingFrom.remove(line.from);
    });
  }

  void _shareTimestampLink() {
    final sec = _currentSec.toInt();
    final link = 'https://www.bilibili.com/video/${widget.bvid}?t=$sec';
    final durStr = widget.formatDuration(Duration(seconds: sec));
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制视频进度链接（时间戳 $durStr）：$link'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '浏览器打开',
          onPressed: () => _openExternal(Uri.parse(link)),
        ),
      ),
    );
    _showControlsTemporarily();
  }

  void _openExternal(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
    _volume = widget.initialVolume;
    _isMuted = widget.initialMuted;
    _playing = widget.player?.state.playing ?? true;
    _lastPosition = widget.player?.state.position ?? Duration.zero;
    _lastPositionTime = DateTime.now();

    _danmakuConfig = widget.danmakuConfig;
    _danmakus = widget.danmakus;
    _subtitles = widget.subtitles;
    _selectedSubtitle = widget.selectedSubtitle;
    _subtitleLines = List.from(widget.subtitleLines);
    _transEnabled = widget.transEnabled;
    _transLang = widget.transLang;

    _subPosition = widget.player?.stream.position.listen((pos) {
      _lastPosition = pos;
      _lastPositionTime = DateTime.now();
    });
    _subPlaying = widget.player?.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _playing = playing;
          _lastPosition = widget.player?.state.position ?? _lastPosition;
          _lastPositionTime = DateTime.now();
        });
        _checkTicker();
      }
    });
    _subCompleted = widget.player?.stream.completed.listen((completed) {
      if (mounted && completed) {
        setState(() => _playing = false);
        _checkTicker();
        _showControlsTemporarily();
      }
    });

    _checkTicker();
    _showControlsTemporarily();
  }

  @override
  void dispose() {
    _volumeHudTimer?.cancel();
    _subPosition?.cancel();
    _subPlaying?.cancel();
    _subCompleted?.cancel();
    _ticker?.dispose();
    _ticker = null;
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

  Future<void> _togglePlay() async {
    final player = widget.player;
    if (player == null) return;
    await player.playOrPause();
    if (mounted) {
      setState(() {
        _playing = player.state.playing;
        _lastPosition = player.state.position;
        _lastPositionTime = DateTime.now();
      });
      _checkTicker();
      _showControlsTemporarily();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final cur = widget.player?.state.position ?? Duration.zero;
    final dur = widget.player?.state.duration ?? Duration.zero;
    final targetMs = (cur.inMilliseconds + seconds * 1000).clamp(0, dur.inMilliseconds);
    await widget.player?.seek(Duration(milliseconds: targetMs));
    _lastPosition = Duration(milliseconds: targetMs);
    _lastPositionTime = DateTime.now();
    _showControlsTemporarily();
  }

  Future<void> _setVolume(double vol, {bool showHud = true}) async {
    final clamped = vol.clamp(0.0, 100.0);
    setState(() {
      _volume = clamped;
      if (_isMuted && clamped > 0) _isMuted = false;
      if (clamped == 0) _isMuted = true;
      if (showHud) _showVolumeHud = true;
    });
    await widget.player?.setVolume(_isMuted ? 0.0 : _volume);
    widget.onVolumeChanged?.call(_volume, _isMuted);
    if (showHud) {
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('bili_player_volume', _volume);
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    if (_isMuted) {
      final target = _volume > 0 ? _volume : 100.0;
      await _setVolume(target, showHud: true);
    } else {
      setState(() {
        _isMuted = true;
        _showVolumeHud = true;
      });
      await widget.player?.setVolume(0.0);
      widget.onVolumeChanged?.call(_volume, _isMuted);
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }
    _showControlsTemporarily();
  }

  Widget _buildVolumeControl(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final effectiveVol = _isMuted ? 0.0 : _volume;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringVolume = true),
      onExit: (_) => setState(() => _isHoveringVolume = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _isMuted ? '取消静音' : '静音',
            icon: Icon(
              _isMuted || effectiveVol == 0
                  ? Icons.volume_off_rounded
                  : (effectiveVol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
              color: Colors.white70,
              size: 22,
            ),
            onPressed: _toggleMute,
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isHoveringVolume ? 80 : 0,
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

  Widget _buildVolumeHud(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final effectiveVol = _isMuted ? 0.0 : _volume;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _showVolumeHud ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(190),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: primary.withAlpha(90), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(140),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isMuted || effectiveVol == 0
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
                  _isMuted ? '静音' : '${effectiveVol.round()}%',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final popupBg = theme.colorScheme.surfaceContainerHigh;
    final outline = theme.colorScheme.outlineVariant;

    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onHover: (_) => _showControlsTemporarily(),
        onEnter: (_) => _showControlsTemporarily(),
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              if (event.scrollDelta.dy < 0) {
                _setVolume(((_isMuted ? 0.0 : _volume) + 5.0).clamp(0.0, 100.0));
              } else if (event.scrollDelta.dy > 0) {
                _setVolume(((_isMuted ? 0.0 : _volume) - 5.0).clamp(0.0, 100.0));
              }
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
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
                        _setVolume(((_isMuted ? 0.0 : _volume) + delta).clamp(0.0, 100.0));
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

              // 弹幕层（全屏）
              if (_danmakuConfig.enabled && _danmakus.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: BiliDanmakuPainter(
                        danmakus: _danmakus,
                        currentSec: _currentSec,
                        config: _danmakuConfig,
                      ),
                    ),
                  ),
                ),

              // 字幕层（全屏）
              if (_selectedSubtitle != null)
                Positioned(
                  bottom: _controlsVisible ? 88.0 : 20.0,
                  left: 20.0,
                  right: 20.0,
                  child: IgnorePointer(
                    child: BiliSubtitleView(
                      activeLine: _findActiveSubtitle(_currentSec),
                      transEnabled: _transEnabled,
                    ),
                  ),
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kBiliPink,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Bilibili',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
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
                              tooltip: '外部打开',
                              icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
                              onPressed: () => _openExternal(Uri.parse('https://www.bilibili.com/video/${widget.bvid}')),
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
                          constraints: const BoxConstraints(maxHeight: 110),
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
                                    final pos = _isDragging && _dragValue != null
                                        ? Duration(milliseconds: _dragValue!.toInt())
                                        : (snap.data ?? Duration.zero);
                                    final dur = widget.player!.state.duration;
                                    final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
                                    return Row(
                                      children: [
                                        Text(
                                          widget.formatDuration(pos),
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
                                              activeTrackColor: primary,
                                              inactiveTrackColor: Colors.white24,
                                              thumbColor: primary,
                                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                            ),
                                            child: Slider(
                                              value: pos.inMilliseconds.clamp(0, maxMs).toDouble(),
                                              max: maxMs.toDouble(),
                                              onChangeStart: (v) {
                                                setState(() {
                                                  _isDragging = true;
                                                  _dragValue = v;
                                                });
                                                _hideTimer?.cancel();
                                                if (!_controlsVisible) {
                                                  setState(() => _controlsVisible = true);
                                                }
                                              },
                                              onChanged: (v) {
                                                setState(() => _dragValue = v);
                                              },
                                              onChangeEnd: (v) {
                                                widget.player?.seek(Duration(milliseconds: v.toInt()));
                                                setState(() {
                                                  _isDragging = false;
                                                  _dragValue = null;
                                                  _lastPosition = Duration(milliseconds: v.toInt());
                                                  _lastPositionTime = DateTime.now();
                                                });
                                                _showControlsTemporarily();
                                              },
                                            ),
                                          ),
                                        ),
                                        Text(
                                          widget.formatDuration(dur),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontFeatures: [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
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

                                  // 弹幕开关
                                  IconButton(
                                    tooltip: _danmakuConfig.enabled ? '关闭弹幕' : '开启弹幕',
                                    icon: Icon(
                                      _danmakuConfig.enabled ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                                      color: _danmakuConfig.enabled ? _kBiliPink : Colors.white70,
                                      size: 21,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _danmakuConfig.enabled = !_danmakuConfig.enabled;
                                      });
                                      _checkTicker();
                                      widget.onConfigChanged();
                                      _showControlsTemporarily();
                                    },
                                  ),

                                  // 弹幕设置
                                  IconButton(
                                    tooltip: '弹幕设置',
                                    icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 21),
                                    onPressed: () {
                                      showDanmakuSettingsDialog(
                                        context,
                                        config: _danmakuConfig,
                                        onChanged: () {
                                          setState(() {});
                                          _checkTicker();
                                          widget.onConfigChanged();
                                        },
                                        onSave: widget.onConfigChanged,
                                      );
                                    },
                                  ),

                                  // 字幕与智能翻译
                                  IconButton(
                                    tooltip: _selectedSubtitle != null ? '字幕与翻译（已开启）' : '字幕与翻译（已关闭）',
                                    icon: Icon(
                                      _selectedSubtitle != null ? Icons.closed_caption_rounded : Icons.closed_caption_disabled_rounded,
                                      color: _selectedSubtitle != null ? _kBiliPink : Colors.white70,
                                      size: 23,
                                    ),
                                    onPressed: () {
                                      showSubtitleSettingsDialog(
                                        context,
                                        subtitles: _subtitles,
                                        selectedSubtitle: _selectedSubtitle,
                                        transEnabled: _transEnabled,
                                        transLang: _transLang,
                                        onSelectSubtitle: (sub) async {
                                          setState(() {
                                            _selectedSubtitle = sub;
                                            _subtitleLines = [];
                                          });
                                          widget.onSubtitleSelected(sub);
                                          if (sub != null) {
                                            try {
                                              final lines = await BiliApi.fetchSubtitleContent(sub.subtitleUrl);
                                              if (mounted && _selectedSubtitle?.id == sub.id) {
                                                setState(() => _subtitleLines = lines);
                                              }
                                            } catch (_) {}
                                          }
                                        },
                                        onToggleTrans: (val) {
                                          setState(() => _transEnabled = val);
                                          widget.onTransEnabledChanged(val);
                                        },
                                        onChangeTransLang: (lang) {
                                          setState(() => _transLang = lang);
                                          for (final l in _subtitleLines) {
                                            l.translation = null;
                                          }
                                          widget.onTransLangChanged(lang);
                                        },
                                        onSave: widget.onConfigChanged,
                                      );
                                    },
                                  ),

                                  // 分享带时间戳链接
                                  IconButton(
                                    tooltip: '分享带时间戳链接',
                                    icon: const Icon(Icons.share_rounded, color: Colors.white70, size: 20),
                                    onPressed: _shareTimestampLink,
                                  ),

                                  const SizedBox(width: 4),

                                  // 画质切换
                                  if (widget.data != null && widget.data!.videos.isNotEmpty)
                                    PopupMenuButton<int>(
                                      initialValue: widget.currentVideo?.id ?? 0,
                                      tooltip: '选择清晰度',
                                      color: popupBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(color: outline.withAlpha(60), width: 0.6),
                                      ),
                                      onSelected: (id) {
                                        final video = widget.data?.getBestVideoForQuality(id) ??
                                            widget.data!.videos.firstWhere(
                                              (e) => e.id == id,
                                              orElse: () => widget.currentVideo!,
                                            );
                                        final audio = widget.data!.bestAudio;
                                        widget.onQualityChanged(video, audio);
                                      },
                                      itemBuilder: (ctx) {
                                        final ids = widget.data!.videos
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
                                                    child: id == (widget.currentVideo?.id ?? -1)
                                                        ? const Icon(Icons.check_rounded, color: _kBiliPink, size: 16)
                                                        : null,
                                                  ),
                                                  Text(
                                                    _qualityLabel(id),
                                                    style: TextStyle(
                                                      color: id == (widget.currentVideo?.id ?? -1)
                                                          ? _kBiliPink
                                                          : Colors.white,
                                                      fontSize: 12.5,
                                                      fontWeight: id == (widget.currentVideo?.id ?? -1)
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ];
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        margin: const EdgeInsets.symmetric(horizontal: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(25),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.white24, width: 0.6),
                                        ),
                                        child: Text(
                                          _qualityLabel(widget.currentVideo?.id ?? 0).split(' ').first,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),

                                  const SizedBox(width: 4),

                                  // 倍速
                                  PopupMenuButton<double>(
                                    initialValue: _speed,
                                    tooltip: '倍速',
                                    color: popupBg,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(color: outline.withAlpha(60), width: 0.6),
                                    ),
                                    onSelected: (s) {
                                      setState(() => _speed = s);
                                      widget.onSpeedChanged(s);
                                      _showControlsTemporarily();
                                    },
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
                                                    ? const Icon(Icons.check_rounded, color: _kBiliPink, size: 16)
                                                    : null,
                                              ),
                                              Text(
                                                '${sp}x 倍速',
                                                style: TextStyle(
                                                  color: sp == _speed ? _kBiliPink : Colors.white,
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
      ),
    );
  }
}
