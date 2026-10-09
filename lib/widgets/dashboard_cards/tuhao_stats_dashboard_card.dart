import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../core/dio_client.dart';
import '../../core/preload_service.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/horn_message.dart';
import '../../models/site_stats.dart';
import '../../models/sign_entry.dart';
import '../../pages/sign_rank_page.dart';
import '../app_motion.dart';
import '../tuhao_banner_widget.dart';
import '../today_sign_star.dart';
import 'dashboard_card_frame.dart';

/// 首页、画布和移动布局共享同一个霸屏分页器，不另外维护单条轮播。
class TuhaoStatsDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;
  final SiteStats? realStats;
  final bool suppressDefaultStats;

  const TuhaoStatsDashboardCard(
      {super.key,
      required this.item,
      this.isPreview = false,
      this.realStats,
      this.suppressDefaultStats = false});

  @override
  State<TuhaoStatsDashboardCard> createState() =>
      _TuhaoStatsDashboardCardState();
}

class _TuhaoStatsDashboardCardState extends State<TuhaoStatsDashboardCard> {
  SiteStats? _stats;
  List<HornMessage> _banners = const [];
  SignHeaderInfo? _starHeader;
  int _generation = 0;
  bool _loading = false, _failed = false;
  late String _lastSource;

  String get _source {
    final declared = widget.item.customParams['starSource'] as String?;
    return declared == 'tuhao' ? 'tuhao' : 'sign_star';
  }

  @override
  void initState() {
    super.initState();
    _lastSource = _source;
    _stats = widget.realStats ??
        PreloadService.instance
            .get<SiteStats>('site_stats', ignoreExpired: true);
    _starHeader = KlpbbsApi.cachedTodaySignHeader;
    if (_source != 'sign_star') {
      // 画布只展示已加载数据；广播短缓存过期不应抹掉当前预览。
      _banners = (PreloadService.instance.get<List<HornMessage>>(
                  'horn_messages',
                  ignoreExpired: widget.isPreview) ??
              [])
          .where((message) => message.tag == '土豪')
          .toList();
    }
    DioClient.sessionChanges.addListener(_sessionChanged);
    KlpbbsApi.signHeaderChanges.addListener(_starChanged);
    if (!widget.isPreview) unawaited(_loadData());
  }

  @override
  void didUpdateWidget(covariant TuhaoStatsDashboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.realStats != oldWidget.realStats) _stats = widget.realStats;
    if (_lastSource != _source) {
      _lastSource = _source;
      _generation++;
      _banners = _source == 'sign_star'
          ? const []
          : (PreloadService.instance.get<List<HornMessage>>('horn_messages',
                      ignoreExpired: widget.isPreview) ??
                  [])
              .where((message) => message.tag == '土豪')
              .toList();
      _starHeader = KlpbbsApi.cachedTodaySignHeader;
      if (!widget.isPreview) unawaited(_loadData());
    }
  }

  void _sessionChanged() {
    _generation++;
    if (!mounted) return;
    setState(() {
      _stats = widget.realStats;
      _banners = const [];
      _starHeader = null;
      _failed = false;
    });
    if (!widget.isPreview) unawaited(_loadData());
  }

  void _starChanged() {
    if (mounted && _source == 'sign_star') {
      setState(() => _starHeader = KlpbbsApi.cachedTodaySignHeader);
    }
  }

  @override
  void dispose() {
    _generation++;
    DioClient.sessionChanges.removeListener(_sessionChanged);
    KlpbbsApi.signHeaderChanges.removeListener(_starChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    final generation = ++_generation, session = DioClient.sessionKey;
    bool current() =>
        mounted && generation == _generation && session == DioClient.sessionKey;
    setState(() {
      _loading = true;
      _failed = false;
    });
    var failed = false;
    await Future.wait<void>([
      if (_stats == null)
        (() async {
          try {
            final stats = await KlpbbsApi.getSiteStats();
            if (current()) setState(() => _stats = stats);
          } catch (_) {
            failed = true;
          }
        })(),
      if (_source != 'sign_star')
        (() async {
          try {
            final banners = await KlpbbsApi.getTuhaoBanners();
            if (current()) setState(() => _banners = banners);
          } catch (_) {
            failed = true;
          }
        })(),
      if (_source == 'sign_star')
        (() async {
          try {
            final sign = await KlpbbsApi.getSignHeaderInfo(forceRefresh: false);
            if (current()) setState(() => _starHeader = sign);
          } catch (_) {
            failed = true;
          }
        })(),
    ]);
    if (!current()) return;
    if (_source != 'tuhao' && _source != 'sign_star' && _banners.isEmpty) {
      try {
        final sign = await KlpbbsApi.getSignHeaderInfo(forceRefresh: false);
        if (current()) {
          setState(() => _starHeader = sign);
        }
      } catch (_) {
        failed = true;
      }
    }
    if (current()) {
      setState(() {
        _failed = failed;
        _loading = false;
      });
    }
  }

  void _openRanks() {
    if (!widget.isPreview) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SignRankPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = widget.realStats ?? _stats ?? const SiteStats();
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = customTitle?.isNotEmpty == true
        ? customTitle!
        : _source == 'tuhao'
            ? '土豪霸屏'
            : '签到动态';
    final dataStyle =
        widget.item.customParams['dataStyle'] as String? ?? 'auto';
    final raw = widget.item.customParams['metrics'];
    final metrics = raw is List
        ? raw
            .map((value) => value.toString())
            .where(_labels.containsKey)
            .toList()
        : widget.suppressDefaultStats && raw == null
            ? const <String>[]
            : const ['todayPosts', 'yesterdayPosts', 'totalMembers'];
    return DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(builder: (context, constraints) {
          final short = constraints.maxHeight < 130;
          final scaler = MediaQuery.textScalerOf(context);
          final headerHeight = (scaler.scale(14) * 1.45).clamp(40.0, 80.0) + 6;
          final starMinimum = scaler.scale(14) * 1.45 + 20;
          final rowMetricsHeight =
              scaler.scale(14) * 1.45 + scaler.scale(11) * 1.45 + 2;
          final availableMetricsHeight = constraints.maxHeight -
              (short ? 0 : headerHeight) -
              starMinimum -
              10;
          final useList = dataStyle == 'list' &&
              availableMetricsHeight >=
                  metrics.take(4).length * (scaler.scale(12) * 1.45 + 4);
          final showMetrics = !short &&
              metrics.isNotEmpty &&
              availableMetricsHeight >= rowMetricsHeight;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!short) ...[
                  Row(children: [
                    Icon(Icons.workspace_premium_rounded,
                        size: 18, color: scheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600))),
                    IconButton(
                        tooltip: '签到排行',
                        onPressed: _openRanks,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.leaderboard_outlined, size: 18)),
                  ]),
                  const SizedBox(height: 6),
                ],
                Expanded(
                    child: _banners.isNotEmpty
                        ? LayoutBuilder(
                            builder: (_, box) => TuhaoBannerWidget(
                                key: const ValueKey('tuhao-dashboard-carousel'),
                                initialBanners: _banners,
                                isPreview: widget.isPreview,
                                compact: true,
                                dismissible: false,
                                showStatsBar: false,
                                spotlight: dataStyle == 'podium',
                                bannerHeight: box.maxHeight))
                        : _source == 'sign_star'
                            ? TodaySignStar(
                                info: _starHeader,
                                loading: _loading,
                                isPreview: widget.isPreview,
                                compact: true,
                                onRetry: _loadData)
                            : Center(
                                child: _loading
                                    ? const AppLoadingIndicator()
                                    : TextButton.icon(
                                        onPressed:
                                            widget.isPreview ? null : _loadData,
                                        icon: const Icon(Icons.refresh_rounded,
                                            size: 18),
                                        label: Text(
                                            _failed ? '读取失败，重试' : '暂无霸屏广播')))),
                if (showMetrics) ...[
                  const SizedBox(height: 10),
                  if (useList)
                    Column(children: [
                      for (final metric in metrics.take(4))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Expanded(
                                child: Text(_labels[metric]!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                            color: scheme.onSurfaceVariant))),
                            Text(stats.display(metric),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(color: scheme.primary)),
                          ]),
                        ),
                    ])
                  else
                    Row(children: [
                      for (final metric in metrics.take(4))
                        Expanded(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Text(stats.display(metric),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(color: scheme.primary)),
                              const SizedBox(height: 2),
                              Text(_labels[metric]!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant)),
                            ]))
                    ]),
                ],
              ]);
        }));
  }

  static const _labels = {
    'todayPosts': '今日新帖',
    'yesterdayPosts': '昨日发帖',
    'totalPosts': '总帖子',
    'totalMembers': '会员'
  };
}
