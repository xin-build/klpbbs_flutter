import '../widgets/app_motion.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../core/dio_client.dart';
import '../models/magic_item.dart';
import '../models/server_outage_info.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/server_outage_view.dart';
import '../widgets/smooth_scroll_controller.dart';
import 'credit_page.dart';
import 'func_list_page.dart';
import 'login_page.dart';

typedef _MagicCollection = ({List<MagicItem> magics, MagicBagInfo bag});

class MagicPage extends StatefulWidget {
  final int initialTab;
  const MagicPage({super.key, this.initialTab = 0});

  @override
  State<MagicPage> createState() => _MagicPageState();
}

class _MagicPageState extends State<MagicPage>
    with SingleTickerProviderStateMixin {
  static const _logTypes = [
    ('uselog', '使用'),
    ('buylog', '购买'),
    ('givelog', '赠送'),
    ('receivelog', '获赠'),
  ];
  late final TabController _tabs;
  final _scrolls = List.generate(3, (_) => SmoothScrollController());
  final _loads = <int, int>{};
  final _pages = {0: 1, 1: 1};
  Future<_MagicCollection>? _shopFuture;
  Future<_MagicCollection>? _boxFuture;
  Future<List<MagicLogEntry>>? _logFuture;
  final _logFutures = <String, Future<List<MagicLogEntry>>>{};
  final _logEntries = <String, List<MagicLogEntry>>{};
  final _logFetchedAt = <String, DateTime>{};
  final _logPages = <String, int>{};
  MagicBagInfo _bag = const MagicBagInfo();
  String _logOp = 'uselog';
  int _logPage = 1, _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
        length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2))
      ..addListener(_tabChanged);
    _selectedTab = _tabs.index;
    DioClient.sessionChanges.addListener(_accountChanged);
    _load(_tabs.index, force: false);
  }

  void _tabChanged() {
    if (!mounted || _selectedTab == _tabs.index) return;
    _selectedTab = _tabs.index;
    final missing = switch (_tabs.index) {
      0 => _shopFuture == null,
      1 => _boxFuture == null,
      _ => _logFuture == null,
    };
    if (missing) _load(_tabs.index, force: false);
    setState(() {});
  }

  void _accountChanged() {
    if (!mounted) return;
    setState(() {
      _loads.clear();
      _shopFuture = null;
      _boxFuture = null;
      _logFuture = null;
      _logFutures.clear();
      _logEntries.clear();
      _logFetchedAt.clear();
      _logPages.clear();
      _bag = const MagicBagInfo();
      _logPage = 1;
      _pages.updateAll((_, __) => 1);
      _load(_tabs.index);
    });
  }

  void _load(int index, {bool force = true}) {
    if (!DioClient.isLoggedIn) return;
    final session = DioClient.sessionKey;
    final load = (_loads[index] ?? 0) + 1;
    _loads[index] = load;
    if (index == 2) {
      _logPages[_logOp] = _logPage;
      final key = '$_logOp:$_logPage',
          fetched = _logFetchedAt['$_logOp:$_logPage'];
      if (!force &&
          _logFutures.containsKey(key) &&
          (fetched == null ||
              DateTime.now().difference(fetched) <
                  const Duration(minutes: 2))) {
        _logFuture = _logFutures[key];
        return;
      }
      late final Future<List<MagicLogEntry>> future;
      future = KlpbbsApi.getMagicLogs(
              op: _logOp, page: _logPage, forceRefresh: force)
          .then((entries) {
        if (mounted &&
            session == DioClient.sessionKey &&
            identical(_logFutures[key], future)) {
          _logEntries[key] = entries;
          _logFetchedAt[key] = DateTime.now();
        }
        return entries;
      }).catchError((Object error, StackTrace stack) {
        if (identical(_logFutures[key], future)) _logFutures.remove(key);
        Error.throwWithStackTrace(error, stack);
      });
      _logFutures[key] = future;
      _logFuture = future;
      future.ignore();
      return;
    }
    final future = (index == 0
            ? KlpbbsApi.getMagicShop(page: _pages[index]!, forceRefresh: force)
            : KlpbbsApi.getMyMagics(page: _pages[index]!, forceRefresh: force))
        .then((result) {
      if (mounted && session == DioClient.sessionKey && _loads[index] == load) {
        setState(() => _bag = result.bag.copyWith(
              usedCapacity: result.bag.usedCapacity >= 0
                  ? result.bag.usedCapacity
                  : _bag.usedCapacity,
              totalCapacity: result.bag.totalCapacity >= 0
                  ? result.bag.totalCapacity
                  : _bag.totalCapacity,
              unlimitedCapacity:
                  result.bag.totalCapacity >= 0 || result.bag.unlimitedCapacity
                      ? result.bag.unlimitedCapacity
                      : _bag.unlimitedCapacity,
              ironCount: result.bag.ironCount >= 0
                  ? result.bag.ironCount
                  : _bag.ironCount,
            ));
      }
      return result;
    });
    future.ignore();
    if (index == 0) {
      _shopFuture = future;
    } else {
      _boxFuture = future;
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final index = _tabs.index;
    setState(() {
      _load(index);
    });
    try {
      if (index == 0) {
        await _shopFuture;
      } else if (index == 1) {
        await _boxFuture;
      } else {
        await _logFuture;
      }
    } catch (_) {
      // FutureBuilder 显示错误并保留原生操作入口。
    }
  }

  Future<void> _operation({String? path, String? title}) async {
    final route = path ??
        Uri(path: 'home.php', queryParameters: {
          'mod': 'magic',
          'action': const ['shop', 'mybox', 'log'][_tabs.index],
          'mobile': 'no',
          if (_tabs.index < 2) 'page': _pages[_tabs.index]!.toString(),
          if (_tabs.index == 2) ...{
            'operation': _logOp,
            'page': _logPage.toString(),
          },
        }).toString();
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FuncListPage(title: title ?? '道具中心', path: route)));
    if (mounted) await _refresh();
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_accountChanged);
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const tabLabels = ['道具商店', '我的道具', '操作记录'];
    final tabStyle =
        Theme.of(context).textTheme.titleSmall ?? const TextStyle(fontSize: 14);
    final tabMetrics = _magicTabMetrics(context, tabLabels, tabStyle);
    return Scaffold(
      drawer: const GlobalAppDrawer(),
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('道具中心'),
        actions: [
          IconButton(
              onPressed: _operation,
              icon: const Icon(Icons.open_in_browser),
              tooltip: '道具操作与说明'),
          IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新道具'),
        ],
        bottom: PreferredSize(
            preferredSize: Size.fromHeight(tabMetrics.height + 2),
            child: LayoutBuilder(builder: (context, constraints) {
              final scrollable = constraints.maxWidth < tabMetrics.minimumWidth;
              return TabBar(
                  controller: _tabs,
                  labelStyle: tabStyle,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                  isScrollable: scrollable,
                  tabAlignment:
                      scrollable ? TabAlignment.start : TabAlignment.fill,
                  tabs: [
                    for (final label in tabLabels)
                      Tab(text: label, height: tabMetrics.height)
                  ]);
            })),
      ),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: !DioClient.isLoggedIn
            ? _login()
            : Column(children: [
                _header(),
                Expanded(
                    child: TabBarView(controller: _tabs, children: [
                  _collection(_shopFuture, 0),
                  _collection(_boxFuture, 1),
                  _logs(),
                ])),
              ]),
      )),
    );
  }

  Widget _login() => EmptyView(
        icon: Icons.lock_outline,
        title: '登录后使用道具中心',
        subtitle: '查看当前用户组可购买的道具、背包和操作记录',
        action: FilledButton(
            onPressed: () async {
              await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const LoginPage()));
              if (mounted) _accountChanged();
            },
            child: const Text('登录')),
      );

  String _known(int value) => value < 0 ? '—' : value.toString();

  Widget _header() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
                avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                label: Text(
                    '容量 ${_known(_bag.usedCapacity)} / ${_bag.unlimitedCapacity ? '不限' : _known(_bag.totalCapacity)}')),
            Chip(
                avatar: const Icon(Icons.toll_outlined, size: 18),
                label: Text('铁粒 ${_known(_bag.ironCount)}'),
                backgroundColor: scheme.secondaryContainer),
            TextButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreditPage()));
                  if (mounted) await _refresh();
                },
                icon:
                    const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: const Text('我的积分')),
          ],
        ));
  }

  Widget _error(Object? error) {
    final outage = ServerOutageInfo.tryParse(error);
    if (outage != null) {
      return ServerOutageView(outage: outage, onRetry: _refresh);
    }
    return EmptyView(
        icon: Icons.error_outline,
        title: '读取失败',
        subtitle: error?.toString() ?? '暂时无法读取道具页面',
        action: Wrap(spacing: 8, children: [
          FilledButton.tonal(onPressed: _refresh, child: const Text('重试')),
          TextButton(onPressed: _operation, child: const Text('道具操作与说明')),
        ]));
  }

  Widget _collection(Future<_MagicCollection>? future, int index) {
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<_MagicCollection>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: AppLoadingIndicator());
          }
          if (snapshot.hasError) return _error(snapshot.error);
          final items = snapshot.data?.magics ?? const <MagicItem>[];
          if (items.isEmpty && _pages[index] == 1) {
            return EmptyView(
                icon: Icons.inventory_2_outlined,
                title: index == 0 ? '暂无道具' : '背包内暂无道具',
                action: TextButton(
                    onPressed: _operation, child: const Text('道具操作与说明')));
          }
          return LayoutBuilder(builder: (context, constraints) {
            final page = _pages[index]!;
            final next = KlpbbsApi.magicCollectionNextPage(
                index == 0 ? 'shop' : 'mybox', page);
            final scaler = MediaQuery.textScalerOf(context);
            final cardMinimum = 160 * (scaler.scale(14) / 14).clamp(1.0, 2.5);
            final columns = ((constraints.maxWidth - 20) / (cardMinimum + 12))
                .floor()
                .clamp(1, 4);
            final titleHeight = scaler.scale(14) * 3;
            final headerHeight = titleHeight > 56 ? titleHeight : 56.0;
            final actionHeight = scaler.scale(14) * 1.5 + 16;
            final cardHeight = 28 +
                headerHeight +
                16 +
                scaler.scale(14) * 1.5 +
                scaler.scale(12) * 4.5 +
                (actionHeight > 48 ? actionHeight : 48);
            return RefreshIndicator(
                onRefresh: _refresh,
                child: CustomScrollView(
                    controller: _scrolls[index],
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisExtent: cardHeight,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12),
                              itemCount: items.length,
                              itemBuilder: (context, position) =>
                                  _card(items[position], index == 0))),
                      if (page > 1 || next != null)
                        SliverToBoxAdapter(
                            child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                          tooltip: '上一页',
                                          icon: const Icon(Icons.chevron_left),
                                          onPressed: page > 1
                                              ? () => setState(() {
                                                    _pages[index] = page - 1;
                                                    _load(index);
                                                  })
                                              : null),
                                      Text('第 $page 页'),
                                      IconButton(
                                          tooltip: '下一页',
                                          icon: const Icon(Icons.chevron_right),
                                          onPressed: next == null
                                              ? null
                                              : () => setState(() {
                                                    _pages[index] = next;
                                                    _load(index);
                                                  })),
                                    ]))),
                    ]));
          });
        });
  }

  Widget _image(MagicItem item, {double size = 44}) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
        width: size,
        height: size,
        child: item.img.isEmpty
            ? Icon(Icons.auto_fix_high_outlined, color: scheme.primary)
            : CachedNetworkImage(
                imageUrl: item.img,
                cacheKey: KlpbbsCacheManager.normalizeCacheKey(item.img),
                cacheManager: KlpbbsCacheManager.instance,
                httpHeaders: AppConfig.imageHeadersFor(item.img),
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) =>
                    Icon(Icons.auto_fix_high_outlined, color: scheme.primary)));
  }

  static const _operationLabels = {
    'buy': '购买',
    'use': '使用',
    'give': '赠送',
    'sell': '出售',
    'drop': '丢弃',
  };

  void _operate(MagicItem item, String operation) {
    final path = item.operations[operation];
    if (path != null) {
      _operation(
          path: path,
          title: '${_operationLabels[operation] ?? '道具'} · ${item.name}');
    }
  }

  Widget _card(MagicItem item, bool shop) {
    final scheme = Theme.of(context).colorScheme;
    final preferred = shop ? 'buy' : 'use';
    final operations = item.operations.keys.toList();
    final primary =
        operations.contains(preferred) ? preferred : operations.firstOrNull;
    final additional =
        operations.where((operation) => operation != primary).toList();
    return Card.outlined(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  DecoratedBox(
                      decoration: BoxDecoration(
                          color: scheme.secondaryContainer.withAlpha(100),
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: _image(item))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 10),
                Text(
                    shop
                        ? (item.priceLabel.isEmpty ? '查看购买条件' : item.priceLabel)
                        : (item.count < 0 ? '持有数量未提供' : '持有 ${item.count} 张'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: scheme.primary, fontWeight: FontWeight.w600)),
                if (shop && item.stock >= 0)
                  Text('库存 ${item.stock}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant))
                else if (!shop && item.totalWeight >= 0)
                  Text('总重量 ${item.totalWeight}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                Expanded(
                    child: Text(item.desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant))),
                Row(children: [
                  if (primary != null)
                    Expanded(
                        child: FilledButton.tonal(
                      onPressed: () => _operate(item, primary),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10)),
                      child:
                          Text(_operationLabels[primary] ?? '查看', maxLines: 1),
                    ))
                  else
                    Expanded(
                        child: TextButton(
                            onPressed: () => _description(item),
                            child: const Text('查看说明'))),
                  if (additional.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: '更多道具操作',
                      onSelected: (operation) => _operate(item, operation),
                      itemBuilder: (_) => [
                        for (final operation in additional)
                          PopupMenuItem(
                              value: operation,
                              child: Text(
                                  _operationLabels[operation] ?? operation)),
                      ],
                    )
                  else
                    IconButton(
                        onPressed: () => _description(item),
                        tooltip: '道具说明',
                        icon: const Icon(Icons.info_outline, size: 20)),
                ]),
              ],
            )));
  }

  void _description(MagicItem item) {
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(item.name),
              scrollable: true,
              content: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: _image(item, size: 64)),
                      const SizedBox(height: 16),
                      Text(item.desc.isEmpty ? '网站暂未提供道具说明' : item.desc),
                      if (item.priceLabel.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(item.priceLabel),
                      ],
                      if (item.count >= 0) Text('持有数量：${item.count}'),
                      if (item.totalWeight >= 0)
                        Text('总重量：${item.totalWeight}')
                      else if (item.weight >= 0)
                        Text('单个重量：${item.weight}'),
                      if (item.stock >= 0) Text('库存：${item.stock}'),
                    ],
                  )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'))
              ],
            ));
  }

  Widget _logs() {
    return Column(children: [
      Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final type in _logTypes)
                ChoiceChip(
                    key: ValueKey('magic-log-op-${type.$1}'),
                    label: Text(type.$2),
                    selected: _logOp == type.$1,
                    onSelected: (selected) {
                      if (!selected || _logOp == type.$1) return;
                      setState(() {
                        _logOp = type.$1;
                        _logPage = _logPages[_logOp] ?? 1;
                        _load(2, force: false);
                      });
                    }),
            ],
          )),
      Expanded(
          child: FutureBuilder<List<MagicLogEntry>>(
        future: _logFuture,
        builder: (context, snapshot) {
          if (_logFuture == null) return const SizedBox.shrink();
          final pending = snapshot.connectionState != ConnectionState.done;
          final logs = pending || snapshot.hasError
              ? _logEntries['$_logOp:$_logPage'] ?? const <MagicLogEntry>[]
              : snapshot.data ?? const <MagicLogEntry>[];
          final next = KlpbbsApi.magicLogNextPage(_logOp, _logPage);
          return Column(children: [
            if (pending && logs.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2),
            if (snapshot.hasError && logs.isNotEmpty)
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(children: [
                    const Expanded(child: Text('刷新失败，保留上次加载的记录')),
                    TextButton(onPressed: _refresh, child: const Text('重试')),
                  ])),
            Expanded(
                child: logs.isEmpty
                    ? pending
                        ? const Center(child: AppLoadingIndicator())
                        : snapshot.hasError
                            ? _error(snapshot.error)
                            : const EmptyView(
                                icon: Icons.receipt_long_outlined,
                                title: '暂无相关记录')
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          controller: _scrolls[2],
                          padding: const EdgeInsets.all(16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: logs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final log = logs[index];
                            return Card.outlined(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  leading: const Icon(Icons.history_outlined),
                                  title: Text(log.magicName.trim().isEmpty
                                      ? '道具名称未提供'
                                      : log.magicName),
                                  subtitle: Text([
                                    log.action,
                                    if (log.amount >= 0) '${log.amount} 张',
                                    if (log.target.isNotEmpty) log.target,
                                    if (log.note.isNotEmpty) log.note,
                                    log.time,
                                  ].join(' · ')),
                                ));
                          },
                        ))),
            if (_logPage > 1 || next != null)
              Padding(
                  key: const ValueKey('magic-log-pagination'),
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                          tooltip: '上一页',
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _logPage > 1
                              ? () => setState(() {
                                    _logPage--;
                                    _load(2, force: false);
                                  })
                              : null),
                      Text('第 $_logPage 页'),
                      IconButton(
                          tooltip: '下一页',
                          icon: const Icon(Icons.chevron_right),
                          onPressed:
                              next == null || pending || snapshot.hasError
                                  ? null
                                  : () => setState(() {
                                        _logPage = next;
                                        _load(2, force: false);
                                      })),
                    ],
                  )),
          ]);
        },
      )),
    ]);
  }
}

({double minimumWidth, double height}) _magicTabMetrics(
    BuildContext context, Iterable<String> labels, TextStyle style) {
  var longest = 0.0, tallest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1)
      ..layout();
    if (painter.width > longest) longest = painter.width;
    if (painter.height > tallest) tallest = painter.height;
    painter.dispose();
  }
  final height = tallest + 16;
  return (
    minimumWidth: labels.length * (longest + 40),
    height: height > 46 ? height : 46,
  );
}
