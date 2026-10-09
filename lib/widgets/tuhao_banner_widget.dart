import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/discuz_horn_protocol.dart';
import '../core/preload_service.dart';
import '../core/url_helper.dart';
import '../models/horn_message.dart';
import '../models/site_stats.dart';
import '../pages/thread_detail_page.dart';
import '../pages/user_space_page.dart';
import 'app_motion.dart';
import 'inline_html_text.dart';
import 'thread_card.dart';

/// 保留广播原文和动图；滑动、按钮与自动轮播共用同一个原生分页器。
class TuhaoBannerWidget extends StatefulWidget {
  final List<HornMessage>? initialBanners;
  final bool isPreview;
  final int? authorUid;
  final String? authorName;
  final String? avatarUrl;
  final String? headline;
  final String? linkUrl;
  final int? tid;
  final SiteStats? stats;
  final int? todayPosts;
  final int? yesterdayPosts;
  final int? totalPosts;
  final int? totalMembers;
  final bool showStatsBar;
  final bool compact;
  final bool dismissible;
  final double? bannerHeight;
  final bool spotlight;

  const TuhaoBannerWidget({
    super.key,
    this.initialBanners,
    this.isPreview = false,
    this.authorUid,
    this.authorName,
    this.avatarUrl,
    this.headline,
    this.linkUrl,
    this.tid,
    this.stats,
    this.todayPosts,
    this.yesterdayPosts,
    this.totalPosts,
    this.totalMembers,
    this.showStatsBar = true,
    this.compact = false,
    this.dismissible = true,
    this.bannerHeight,
    this.spotlight = false,
  });

  @override
  State<TuhaoBannerWidget> createState() => _TuhaoBannerWidgetState();
}

class _TuhaoBannerWidgetState extends State<TuhaoBannerWidget>
    with WidgetsBindingObserver {
  List<HornMessage> _banners = const [];
  SiteStats? _siteStats;
  late final PageController _pager;
  Timer? _timer;
  int _index = 0, _virtualPage = 0, _generation = 0;
  bool _dismissed = false, _resumed = true, _tickerEnabled = true;
  bool _systemReduced = false, _dragging = false, _hovered = false;
  bool get _animate =>
      !AppConfig.reduceMotion && !_systemReduced && AppConfig.animatePanels;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IntProperty('carouselCount', _banners.length))
      ..add(IntProperty('carouselIndex', _index))
      ..add(DiagnosticsProperty<bool>(
          'carouselTimerActive', _timer?.isActive ?? false))
      ..add(DiagnosticsProperty<bool>('carouselResumed', _resumed))
      ..add(DiagnosticsProperty<bool>('carouselTickerEnabled', _tickerEnabled))
      ..add(DiagnosticsProperty<bool>('carouselAnimate', _animate))
      ..add(DiagnosticsProperty<bool>('carouselDragging', _dragging))
      ..add(DiagnosticsProperty<bool>('carouselHovered', _hovered))
      ..add(DiagnosticsProperty<bool>(
          'carouselAutoPlay', AppConfig.bannerAutoPlay));
  }

  List<HornMessage>? get _provided {
    if (widget.initialBanners != null) return widget.initialBanners;
    if (widget.headline?.isNotEmpty == true) {
      return [
        HornMessage(
          author: widget.authorName ?? '',
          uid: widget.authorUid,
          avatarUrl: widget.avatarUrl,
          content: const HtmlEscape().convert(widget.headline!),
          linkUrl: widget.linkUrl,
          tag: '土豪',
        )
      ];
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _banners = _provided ??
        (PreloadService.instance.get<List<HornMessage>>('horn_messages') ?? [])
            .where((message) => message.tag == '土豪')
            .toList();
    _siteStats =
        widget.stats ?? PreloadService.instance.get<SiteStats>('site_stats');
    _virtualPage = _banners.length * 1000;
    _pager = PageController(initialPage: _virtualPage);
    WidgetsBinding.instance.addObserver(this);
    AppConfig.instance.addListener(_configurationChanged);
    DioClient.sessionChanges.addListener(_sessionChanged);
    if (!widget.isPreview) {
      if (_provided == null) unawaited(_loadBanners());
      if (widget.showStatsBar && widget.stats == null) unawaited(_loadStats());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.of(context);
    _systemReduced = MediaQuery.disableAnimationsOf(context);
    _updateTimer();
  }

  @override
  void didUpdateWidget(covariant TuhaoBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stats != oldWidget.stats) _siteStats = widget.stats;
    if (_provided != null) {
      _replace(_provided!);
    } else if (oldWidget.initialBanners != null && !widget.isPreview) {
      unawaited(_loadBanners());
    }
    _updateTimer();
  }

  void _configurationChanged() {
    if (mounted) setState(() {});
    _updateTimer();
  }

  void _syncPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _banners.isEmpty) return;
      _virtualPage = _banners.length * 1000 + _index;
      if (_pager.hasClients) _pager.jumpToPage(_virtualPage);
    });
  }

  void _sessionChanged() {
    _generation++;
    if (!mounted) return;
    setState(() {
      _banners = _provided ?? [];
      _index = 0;
      _dismissed = false;
      _siteStats = widget.stats;
    });
    _syncPage();
    _updateTimer();
    if (!widget.isPreview) {
      if (_provided == null) unawaited(_loadBanners());
      if (widget.showStatsBar && widget.stats == null) unawaited(_loadStats());
    }
  }

  String _signature(List<HornMessage> list) =>
      list.map(DiscuzHornProtocol.identity).join('\n');
  void _replace(List<HornMessage> list) {
    if (_signature(list) == _signature(_banners)) return;
    final previous = _banners.isEmpty
        ? null
        : DiscuzHornProtocol.identity(_banners[_index % _banners.length]);
    _banners = list;
    final next = previous == null
        ? -1
        : list.indexWhere(
            (message) => DiscuzHornProtocol.identity(message) == previous);
    _index = _dismissed || next < 0 ? 0 : next;
    _dismissed = false;
    _syncPage();
  }

  Future<void> _loadBanners() async {
    final session = DioClient.sessionKey, generation = _generation;
    try {
      final list = await KlpbbsApi.getTuhaoBanners();
      if (!mounted ||
          session != DioClient.sessionKey ||
          generation != _generation) {
        return;
      }
      setState(() => _replace(list));
      _updateTimer();
    } catch (_) {}
  }

  Future<void> _loadStats() async {
    final session = DioClient.sessionKey, generation = _generation;
    try {
      final stats = await KlpbbsApi.getSiteStats();
      if (mounted &&
          session == DioClient.sessionKey &&
          generation == _generation) {
        setState(() => _siteStats = stats);
      }
    } catch (_) {}
  }

  void _updateTimer() {
    _timer?.cancel();
    _timer = null;
    if (!mounted ||
        _dismissed ||
        widget.isPreview ||
        !_animate ||
        !AppConfig.bannerAutoPlay ||
        !_tickerEnabled ||
        !_resumed ||
        _dragging ||
        _hovered ||
        _banners.length < 2) {
      return;
    }
    _timer = Timer(const Duration(seconds: 5), () => _select(1));
  }

  void _select(int offset) {
    if (_banners.length < 2 || !_pager.hasClients) return;
    final target =
        math.max(0, (_pager.page ?? _virtualPage.toDouble()).round() + offset);
    if (_animate) {
      _pager.animateToPage(target,
          duration: AppMotion.duration(context, 320),
          curve: AppMotion.emphasized);
    } else {
      _pager.jumpToPage(target);
    }
    _updateTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _updateTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pager.dispose();
    WidgetsBinding.instance.removeObserver(this);
    AppConfig.instance.removeListener(_configurationChanged);
    DioClient.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _open(HornMessage message) async {
    if (widget.isPreview) return;
    if (widget.tid != null && widget.tid! > 0 && widget.headline != null) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ThreadDetailPage(tid: widget.tid!)));
    } else if (message.linkUrl?.isNotEmpty == true) {
      await UrlHelper.openLink(context, message.linkUrl!);
    }
  }

  void _openAuthor(HornMessage message) {
    if (widget.isPreview || message.uid == null || message.uid! <= 0) return;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => UserSpacePage(uid: message.uid!)));
  }

  double _textHeight(String text, TextStyle style, double width,
      {int? maxLines}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
    )..layout(maxWidth: math.max(1, width));
    final height = painter.height;
    painter.dispose();
    return height;
  }

  Widget _compactBanner(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFFFF2C5) : const Color(0xFF654400);
    final height = math.max(0.0, widget.bannerHeight ?? 164.0);
    final tight = height < 110;
    final controlsHeight = height < 70
        ? 24.0
        : tight
            ? 32.0
            : 40.0;
    final avatarSize = math.min(
        tight
            ? 24.0
            : widget.spotlight
                ? 44.0
                : 32.0,
        math.max(
                0.0,
                height -
                    (_banners.length > 1 ? controlsHeight : 0) -
                    (tight ? 6 : 16)) /
            (7 / 4));
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _updateTimer();
      },
      onExit: (_) {
        _hovered = false;
        _updateTimer();
      },
      child: Listener(
        onPointerDown: (_) {
          _dragging = true;
          _updateTimer();
        },
        onPointerUp: (_) {
          _dragging = false;
          _updateTimer();
        },
        onPointerCancel: (_) {
          _dragging = false;
          _updateTimer();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF795A16), Color(0xFF574017)]
                    : const [Color(0xFFFFD45C), Color(0xFFFFEDAD)],
              )),
              child: Column(children: [
                Expanded(
                    child: ScrollConfiguration(
                  behavior:
                      ScrollConfiguration.of(context).copyWith(dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  }),
                  child: PageView.builder(
                    key: const ValueKey('tuhao-pager'),
                    controller: _pager,
                    physics: _banners.length > 1
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    onPageChanged: (page) {
                      if (!mounted || _banners.isEmpty) return;
                      setState(() {
                        _virtualPage = page;
                        _index = page % _banners.length;
                      });
                      _updateTimer();
                    },
                    itemBuilder: (context, page) {
                      final message = _banners[page % _banners.length];
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                            12, tight ? 4 : 12, 12, tight ? 2 : 4),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                UserAvatarWidget(
                                    uid: message.uid,
                                    author: message.author,
                                    avatarUrl: message.avatarUrl,
                                    faceUrl: UserAvatarWidget.sanitizeFaceUrl(
                                        message.faceUrl),
                                    size: avatarSize,
                                    reserveFrameSpace: true,
                                    onTap: widget.isPreview
                                        ? null
                                        : () => _openAuthor(message)),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        message.author.isEmpty
                                            ? '全站霸屏广播'
                                            : message.author,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                                color: foreground,
                                                fontWeight: FontWeight.w700))),
                              ]),
                              if (!tight) ...[
                                const SizedBox(height: 8),
                                Expanded(
                                    child: SingleChildScrollView(
                                        child: InkWell(
                                  onTap: widget.isPreview
                                      ? null
                                      : () => _open(message),
                                  borderRadius: BorderRadius.circular(8),
                                  child: IgnorePointer(
                                      ignoring: widget.isPreview,
                                      child: InlineHtmlText(
                                          html: message.content,
                                          emojiSize: 20,
                                          baseStyle: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                  color: foreground,
                                                  height: 1.4))),
                                ))),
                              ],
                            ]),
                      );
                    },
                  ),
                )),
                if (_banners.length > 1)
                  SizedBox(
                      height: controlsHeight,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                                key: const ValueKey('tuhao-previous'),
                                tooltip: '上一条霸屏广播',
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                color: foreground,
                                onPressed: () => _select(-1),
                                icon: const Icon(Icons.chevron_left_rounded,
                                    size: 20)),
                            Semantics(
                                value:
                                    '第 ${_index + 1} 条，共 ${_banners.length} 条',
                                child: Text(
                                    '${_index + 1} / ${_banners.length}',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(color: foreground))),
                            IconButton(
                                key: const ValueKey('tuhao-next'),
                                tooltip: '下一条霸屏广播',
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                color: foreground,
                                onPressed: () => _select(1),
                                icon: const Icon(Icons.chevron_right_rounded,
                                    size: 20)),
                          ])),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), stats = widget.stats ?? _siteStats;
    final showBanner = !_dismissed && _banners.isNotEmpty;
    return RepaintBoundary(
      child: AppAnimatedSize(
        duration: AppMotion.duration(context, 240),
        curve: AppMotion.emphasized,
        alignment: Alignment.topCenter,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (showBanner && widget.compact) _compactBanner(context),
          if (showBanner && !widget.compact)
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 680;
              final dark = theme.brightness == Brightness.dark;
              final foreground =
                  dark ? const Color(0xFFFFF2C5) : const Color(0xFF654400);
              final horizontal = constraints.maxWidth >= 320 ? 32.0 : 16.0;
              final textWidth =
                  math.max(1.0, constraints.maxWidth - horizontal * 2);
              final authorStyle = TextStyle(
                  fontSize: wide ? 16 : 14,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: foreground);
              final contentStyle = TextStyle(
                  fontSize: wide ? 20 : 16,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: foreground);
              double bodyHeight = 32, authorHeight = 20;
              for (final item in _banners) {
                final text = html
                    .parseFragment(item.content
                        .replaceAll(
                            RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
                        .replaceAll(
                            RegExp(r'<img\b[^>]*>', caseSensitive: false),
                            ' ◉ '))
                    .text;
                bodyHeight = math.max(
                    bodyHeight,
                    _textHeight(text ?? '', contentStyle, textWidth)
                            .clamp(32.0, 140.0) +
                        4);
                authorHeight = math.max(
                    authorHeight,
                    _textHeight('土豪 ${item.author} 驾到', authorStyle, textWidth,
                        maxLines: 2));
              }
              final avatarSize = wide ? 46.0 : 38.0;
              final pageHeight =
                  avatarSize * (7 / 4) + 8 + authorHeight + 8 + bodyHeight + 28;
              return MouseRegion(
                onEnter: (_) {
                  _hovered = true;
                  _updateTimer();
                },
                onExit: (_) {
                  _hovered = false;
                  _updateTimer();
                },
                child: Listener(
                  onPointerDown: (_) {
                    _dragging = true;
                    _updateTimer();
                  },
                  onPointerUp: (_) {
                    _dragging = false;
                    _updateTimer();
                  },
                  onPointerCancel: (_) {
                    _dragging = false;
                    _updateTimer();
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: dark
                            ? const [Color(0xFF795A16), Color(0xFF574017)]
                            : const [
                                Color(0xFFFFD45C),
                                Color(0xFFFFEDAD),
                                Color(0xFFFFDF78)
                              ],
                      )),
                      child: Stack(children: [
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(
                              height: pageHeight,
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(dragDevices: {
                                  PointerDeviceKind.touch,
                                  PointerDeviceKind.mouse,
                                  PointerDeviceKind.trackpad,
                                  PointerDeviceKind.stylus,
                                }),
                                child: PageView.builder(
                                  key: const ValueKey('tuhao-pager'),
                                  controller: _pager,
                                  physics: _banners.length > 1
                                      ? const PageScrollPhysics()
                                      : const NeverScrollableScrollPhysics(),
                                  onPageChanged: (page) {
                                    if (!mounted || _banners.isEmpty) return;
                                    setState(() {
                                      _virtualPage = page;
                                      _index = page % _banners.length;
                                    });
                                    _updateTimer();
                                  },
                                  itemBuilder: (context, page) {
                                    final message =
                                        _banners[page % _banners.length];
                                    return Padding(
                                      padding: EdgeInsets.fromLTRB(
                                          horizontal, 16, horizontal, 12),
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            UserAvatarWidget(
                                                uid: message.uid,
                                                author: message.author,
                                                avatarUrl: message.avatarUrl,
                                                faceUrl: UserAvatarWidget
                                                    .sanitizeFaceUrl(
                                                        message.faceUrl),
                                                size: avatarSize,
                                                reserveFrameSpace: true,
                                                onTap: widget.isPreview
                                                    ? null
                                                    : () =>
                                                        _openAuthor(message)),
                                            const SizedBox(height: 8),
                                            SizedBox(
                                                height: authorHeight,
                                                child: Center(
                                                    child: Text(
                                                        message.author.isEmpty
                                                            ? '全站霸屏广播'
                                                            : '💰 土豪 ${message.author} 驾到',
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: authorStyle))),
                                            const SizedBox(height: 8),
                                            SizedBox(
                                                height: bodyHeight,
                                                child: Center(
                                                    child:
                                                        SingleChildScrollView(
                                                  child: InkWell(
                                                    onTap: widget.isPreview ||
                                                            message.linkUrl ==
                                                                null
                                                        ? null
                                                        : () => _open(message),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    child: IgnorePointer(
                                                        ignoring:
                                                            widget.isPreview,
                                                        child: InlineHtmlText(
                                                          html: message.content,
                                                          textAlign:
                                                              TextAlign.center,
                                                          emojiSize: 22,
                                                          baseStyle:
                                                              contentStyle,
                                                        )),
                                                  ),
                                                ))),
                                          ]),
                                    );
                                  },
                                ),
                              )),
                          if (_banners.length > 1)
                            Padding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                        key: const ValueKey('tuhao-previous'),
                                        tooltip: '上一条霸屏广播',
                                        onPressed: () => _select(-1),
                                        color: foreground,
                                        icon: const Icon(
                                            Icons.chevron_left_rounded,
                                            size: 20)),
                                    Semantics(
                                        value:
                                            '第 ${_index + 1} 条，共 ${_banners.length} 条',
                                        child: Text(
                                            '${_index + 1} / ${_banners.length}',
                                            style: TextStyle(
                                                color: foreground,
                                                fontSize: 12))),
                                    IconButton(
                                        key: const ValueKey('tuhao-next'),
                                        tooltip: '下一条霸屏广播',
                                        onPressed: () => _select(1),
                                        color: foreground,
                                        icon: const Icon(
                                            Icons.chevron_right_rounded,
                                            size: 20)),
                                  ],
                                )),
                        ]),
                        if (widget.dismissible)
                          Positioned(
                              right: 2,
                              top: 2,
                              child: IconButton(
                                key: const ValueKey('tuhao-close'),
                                tooltip: '关闭霸屏广播',
                                color: foreground,
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () {
                                  setState(() => _dismissed = true);
                                  _updateTimer();
                                },
                              )),
                      ]),
                    ),
                  ),
                ),
              );
            }),
          if (widget.showStatsBar && stats != null && !stats.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  _stat(
                      '今日',
                      widget.todayPosts?.toString() ??
                          stats.display('todayPosts'),
                      theme),
                  _stat(
                      '昨日',
                      widget.yesterdayPosts?.toString() ??
                          stats.display('yesterdayPosts'),
                      theme),
                  _stat(
                      '帖子',
                      widget.totalPosts?.toString() ??
                          stats.display('totalPosts'),
                      theme),
                  _stat(
                      '会员',
                      widget.totalMembers?.toString() ??
                          stats.display('totalMembers'),
                      theme),
                ])),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, ThemeData theme) => Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 3),
          Text(value,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ]),
      );
}
