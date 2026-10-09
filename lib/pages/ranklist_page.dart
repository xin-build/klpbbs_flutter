import '../widgets/app_motion.dart';
import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../models/site_rank_entry.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/smooth_scroll_controller.dart';
import 'thread_detail_page.dart';

/// 读取 KLPBBS 首页实际的三个热门周期。
class RanklistPage extends StatefulWidget {
  final String initialPeriod;
  const RanklistPage({super.key, this.initialPeriod = 'day'});
  @override
  State<RanklistPage> createState() => _RanklistPageState();
}

class _RanklistPageState extends State<RanklistPage>
    with SingleTickerProviderStateMixin {
  static const _periods = [('day', '日热门'), ('week', '周热门'), ('month', '月热门')];
  late final TabController _tabs;
  late Future<Map<String, List<SiteRankEntry>>> _future;
  Map<String, List<SiteRankEntry>>? _loaded;
  String? _refreshError;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    final index =
        _periods.indexWhere((item) => item.$1 == widget.initialPeriod);
    _tabs = TabController(
        length: 3, vsync: this, initialIndex: index < 0 ? 0 : index);
    _load();
    DioClient.sessionChanges.addListener(_sessionChanged);
  }

  void _load({bool forceRefresh = false}) {
    final generation = ++_generation, session = DioClient.sessionKey;
    bool current() =>
        mounted && generation == _generation && session == DioClient.sessionKey;
    _refreshError = null;
    _future =
        KlpbbsApi.getSiteHotRankings(forceRefresh: forceRefresh).then((data) {
      if (current()) _loaded = data;
      return data;
    }, onError: (Object error, StackTrace stack) {
      if (current() && _loaded != null) {
        _refreshError = '刷新失败，已保留上次排行';
        return _loaded!;
      }
      Error.throwWithStackTrace(error, stack);
    });
    // Keep a fast or superseded failure observed before the next build.
    _future.ignore();
  }

  void _refresh() {
    if (mounted) setState(() => _load(forceRefresh: true));
  }

  void _sessionChanged() {
    if (!mounted) return;
    setState(() {
      _loaded = null;
      _load();
    });
  }

  @override
  void dispose() {
    _generation++;
    DioClient.sessionChanges.removeListener(_sessionChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const GlobalAppDrawer(),
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('热门排行'),
        actions: [
          IconButton(
              onPressed: _refresh,
              tooltip: '同步网站排行',
              icon: const Icon(Icons.refresh))
        ],
        bottom: TabBar(
            controller: _tabs,
            tabs: [for (final item in _periods) Tab(text: item.$2)]),
      ),
      body: FutureBuilder<Map<String, List<SiteRankEntry>>>(
        key: ValueKey(DioClient.sessionKey),
        initialData: _loaded,
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: AppLoadingIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 40),
                        const SizedBox(height: 16),
                        Text(snapshot.error.toString(),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                            onPressed: _refresh, child: const Text('重新同步')),
                      ],
                    )));
          }
          return Column(children: [
            if (snapshot.connectionState != ConnectionState.done)
              const AppLoadingBar(),
            if (_refreshError != null)
              MaterialBanner(content: Text(_refreshError!), actions: [
                TextButton(onPressed: _refresh, child: const Text('重试'))
              ]),
            Expanded(
                key: const ValueKey('rank-periods'),
                child: TabBarView(controller: _tabs, children: [
                  for (final item in _periods)
                    _RankingList(
                        key: ValueKey(item.$1),
                        entries: snapshot.data?[item.$1] ?? const [],
                        periodLabel: item.$2),
                ])),
          ]);
        },
      ),
    );
  }
}

class _RankingList extends StatefulWidget {
  final List<SiteRankEntry> entries;
  final String periodLabel;
  const _RankingList(
      {super.key, required this.entries, required this.periodLabel});
  @override
  State<_RankingList> createState() => _RankingListState();
}

class _RankingListState extends State<_RankingList> {
  final _scroll = SmoothScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000 ? 2 : 1;
      return CustomScrollView(controller: _scroll, slivers: [
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Text('网站首页 · ${widget.periodLabel} · 保持网站顺序',
                    style: TextStyle(color: scheme.onSurfaceVariant)))),
        if (widget.entries.isEmpty)
          const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('网站当前未提供此周期的热门内容')))
        else
          SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              sliver: SliverGrid.builder(
                itemCount: widget.entries.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 124,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14),
                itemBuilder: (context, index) {
                  final item = widget.entries[index];
                  return Card.outlined(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    ThreadDetailPage(tid: item.tid))),
                        child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(children: [
                              Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                      color: scheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(13)),
                                  alignment: Alignment.center,
                                  child: Text(
                                      item.rank?.toString().padLeft(2, '0') ??
                                          '·',
                                      style: TextStyle(
                                          color: scheme.onSecondaryContainer,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700))),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(item.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            height: 1.4)),
                                    if (item.subtitle.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(item.subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.onSurfaceVariant)),
                                    ],
                                  ])),
                              const SizedBox(width: 8),
                              Icon(Icons.chevron_right,
                                  size: 20, color: scheme.outline),
                            ])),
                      ));
                },
              )),
      ]);
    });
  }
}
