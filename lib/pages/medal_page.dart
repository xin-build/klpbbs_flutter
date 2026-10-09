import '../widgets/app_motion.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/cache_manager.dart';
import '../core/write_confirm.dart';
import '../models/medal_item.dart';
import '../models/server_outage_info.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/server_outage_view.dart';
import '../widgets/sliver_two_column_feed.dart';
import 'credit_page.dart';

/// 苦力怕论坛勋章中心（深度复刻图四与官方移动端：勋章中心 / 我的勋章 / 勋章排序，统一 Material 3 主题）
class MedalPage extends StatefulWidget {
  final int initialIndex;
  const MedalPage({super.key, this.initialIndex = 0});

  @override
  State<MedalPage> createState() => _MedalPageState();
}

class _MedalPageState extends State<MedalPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<List<MedalItem>> _allMedalsFuture;
  List<MedalItem> _catalogMedals = const [];
  List<({int id, String name, String desc, String img})> _myMedals = [];
  bool _loadingMyMedals = true;
  bool _savingOrder = false;
  String? _myMedalsError;
  int _loadGeneration = 0, _orderGeneration = 0, _catalogGeneration = 0;
  final Set<int> _busyMedals = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        HapticFeedback.selectionClick();
      }
    });
    _allMedalsFuture = _loadCatalog();
    _loadMyMedals();
    DioClient.sessionChanges.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _loadGeneration++;
    _orderGeneration++;
    _catalogGeneration++;
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    _orderGeneration++;
    setState(() {
      _myMedals = [];
      _catalogMedals = const [];
      _myMedalsError = null;
      _savingOrder = false;
      _busyMedals.clear();
      _myIron = null;
      _loadingMyMedals = true;
      _allMedalsFuture = _loadCatalog(forceRefresh: true);
    });
    _loadMyMedals(forceRefresh: true);
  }

  int? _myIron;

  Future<List<MedalItem>> _loadCatalog({bool forceRefresh = false}) {
    final generation = ++_catalogGeneration;
    final session = DioClient.sessionKey;
    final future =
        KlpbbsApi.getMedals(forceRefresh: forceRefresh).then((medals) {
      if (!mounted ||
          generation != _catalogGeneration ||
          session != DioClient.sessionKey) {
        throw StateError('账号已切换，请重新加载勋章');
      }
      _catalogMedals = medals;
      return medals;
    });
    // A tab can be offscreen or a refresh can fail before FutureBuilder's next
    // frame subscribes. Consume unobserved errors immediately; the original
    // future still delivers them to FutureBuilder for the failure banner.
    future.ignore();
    return future;
  }

  bool _isMedalOwned(MedalItem m) {
    return m.isOwned ||
        _myMedals.any((x) =>
            (m.id > 0 && x.id > 0 && x.id == m.id) ||
            (m.name.isNotEmpty && x.name.isNotEmpty && x.name == m.name) ||
            (m.img.length > 5 &&
                x.img.length > 5 &&
                (m.img.endsWith(x.img) || x.img.endsWith(m.img))));
  }

  Future<void> _loadMyMedals({bool forceRefresh = false}) async {
    if (_savingOrder) return;
    final generation = ++_loadGeneration;
    final session = DioClient.sessionKey;
    setState(() => _loadingMyMedals = true);
    try {
      final medals =
          await KlpbbsApi.getMyMedalsList(forceRefresh: forceRefresh);
      final space = KlpbbsApi.cachedSpace;
      final value = space?.creditsDetail['铁粒'] ?? space?.stats['铁粒'];
      final iron =
          value == null ? null : int.tryParse(value.replaceAll(',', ''));
      if (mounted &&
          generation == _loadGeneration &&
          session == DioClient.sessionKey) {
        setState(() {
          _myIron = iron;
          _myMedals = List.from(medals);
          _loadingMyMedals = false;
          _myMedalsError = null;
        });
      }
    } catch (_) {
      if (mounted &&
          generation == _loadGeneration &&
          session == DioClient.sessionKey) {
        setState(() {
          _loadingMyMedals = false;
          _myMedalsError = '我的勋章读取失败，请重试';
        });
      }
    }
  }

  void _moveUp(int index) {
    if (_savingOrder || index <= 0 || index >= _myMedals.length) return;
    setState(() {
      final item = _myMedals.removeAt(index);
      _myMedals.insert(index - 1, item);
    });
  }

  void _moveDown(int index) {
    if (_savingOrder || index < 0 || index >= _myMedals.length - 1) return;
    setState(() {
      final item = _myMedals.removeAt(index);
      _myMedals.insert(index + 1, item);
    });
  }

  Future<void> _saveOrder() async {
    if (_savingOrder || _myMedalsError != null || _loadingMyMedals) return;
    final session = DioClient.sessionKey;
    final ids = List<int>.unmodifiable(_myMedals.map((m) => m.id));
    if (ids.isEmpty ||
        ids.any((id) => id <= 0) ||
        ids.toSet().length != ids.length) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('勋章标识尚未完整加载，请刷新后再排序')));
      return;
    }
    final generation = ++_orderGeneration;
    bool current() =>
        mounted &&
        generation == _orderGeneration &&
        session == DioClient.sessionKey;
    setState(() => _savingOrder = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final confirmed = await confirmWrite(context, '保存勋章排序');
      if (!confirmed || !current()) return;
      final ok = await KlpbbsApi.saveMedalOrder(ids, expectedSession: session);
      if (!mounted || !current()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? '勋章排序已保存生效' : '服务器未确认保存，请重试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!current()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('保存异常：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (current()) setState(() => _savingOrder = false);
    }
  }

  /// 勋章详情弹窗（像素级复刻官方移动端弹窗，对齐 Image 2）
  void _showMedalDetailDialog(MedalItem m) {
    final session = DioClient.sessionKey;
    final isOwned = _isMedalOwned(m);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Container(
            width: 320,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部右侧关闭图标
                Align(
                  alignment: Alignment.topRight,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 20, color: theme.colorScheme.outline),
                    ),
                  ),
                ),

                // 勋章图片
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(60),
                      width: 0.8,
                    ),
                  ),
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: m.img,
                      cacheKey: KlpbbsCacheManager.normalizeCacheKey(m.img),
                      cacheManager: KlpbbsCacheManager.instance,
                      httpHeaders: AppConfig.imageHeaders,
                      width: 44,
                      height: 44,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.military_tech,
                          color: Colors.amber,
                          size: 36),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 勋章名称
                Text(
                  m.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),

                // 勋章描述
                Text(
                  m.desc.isNotEmpty ? m.desc : '网站未提供描述',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                const Divider(height: 1),
                const SizedBox(height: 14),

                // 真实条件与价格文字（居中两行橙色）
                for (final line in m.requirementLines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.brightness == Brightness.dark
                            ? Colors.orange.shade300
                            : Colors.orange.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 20),

                // 底部操作大按钮（绿色圆角 / 灰色已拥有）
                ConstrainedBox(
                  constraints: const BoxConstraints(
                      minWidth: double.infinity, minHeight: 44),
                  child: isOwned
                      ? FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.grey.shade300,
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('已经拥有',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w500)),
                        )
                      : !m.isPending &&
                              m.id > 0 &&
                              (m.isBuyable || m.isApplyable)
                          ? FilledButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                if (session != DioClient.sessionKey) return;
                                _handleMedalAction(m);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    Theme.of(ctx).colorScheme.primary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                m.isBuyable ? '购买' : '申请',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ),
                            )
                          : FilledButton(
                              onPressed: null,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.grey.shade300,
                                disabledBackgroundColor: Colors.grey.shade300,
                                disabledForegroundColor: Colors.grey.shade600,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                  m.isPending
                                      ? '等待审核'
                                      : m.isManual
                                          ? '人工授予'
                                          : '请刷新后查看',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500)),
                            ),
                ),
              ],
            )),
          ),
        );
      },
    );
  }

  Future<void> _handleMedalAction(MedalItem m) async {
    final session = DioClient.sessionKey;
    bool current() => mounted && session == DioClient.sessionKey;
    final isOwned = _isMedalOwned(m);
    if (isOwned || m.isManual || m.isPending || !_busyMedals.add(m.id)) return;

    try {
      final info =
          await KlpbbsApi.getMedalConfirmation(m.id, expectedSession: session);
      if (!mounted || !current()) return;
      if (info.confirmation == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(info.message)));
        return;
      }

      final actionName = m.isBuyable ? '购买' : '申请';
      final req = info.confirmation!.terms.isNotEmpty
          ? info.confirmation!.terms
          : m.requirement;
      final confirmText = m.isBuyable
          ? '购买勋章「${m.name}」（需消耗 $req）'
          : '申请勋章「${m.name}」（需满足 $req）';
      if (!await confirmWrite(context, confirmText) || !mounted || !current()) {
        return;
      }
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  key: const ValueKey('medal-purchase-confirmation'),
                  scrollable: true,
                  title: Text('$actionName勋章 · ${m.name}'),
                  content: Text(req.isEmpty ? '网站未提供具体条件，请刷新勋章详情后确认。' : req),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    FilledButton(
                        key: const ValueKey('medal-purchase-confirm'),
                        onPressed: req.isEmpty
                            ? null
                            : () => Navigator.pop(context, true),
                        child: Text('确认$actionName'))
                  ]));
      if (confirmed != true || !mounted || !current()) return;

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      AppLoadingIndicator(strokeWidth: 2, color: Colors.white)),
              const SizedBox(width: 10),
              Expanded(child: Text('正在提交「${m.name}」$actionName请求...')),
            ],
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final res =
          await KlpbbsApi.applyMedal(m.id, confirmation: info.confirmation);
      if (mounted && current()) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('「${m.name}」: ${res.message}'),
            backgroundColor: res.success
                ? Colors.green.shade700
                : Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        if (res.success) {
          _loadMyMedals(forceRefresh: true);
          setState(() {
            _allMedalsFuture = _loadCatalog(forceRefresh: true);
          });
        }
      }
    } catch (e) {
      if (mounted && current()) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('勋章请求失败：$e')));
      }
    } finally {
      if (current()) _busyMedals.remove(m.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const tabLabels = ['勋章中心', '我的勋章', '勋章排序'];
    final tabStyle =
        (theme.textTheme.titleSmall ?? const TextStyle(fontSize: 14.5))
            .copyWith(fontWeight: FontWeight.bold, fontSize: 14.5);
    final tabMetrics = _medalTabMetrics(context, tabLabels, tabStyle);

    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      appBar: AppBar(
        automaticallyImplyLeading: !isDesktop,
        leading: (isDesktop && !canPop) ? null : const GlobalNavLeading(),
        leadingWidth: (isDesktop && !canPop)
            ? null
            : GlobalNavLeading.preferredLeadingWidth(context),
        title:
            const Text('勋章中心', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: '积分记录',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const CreditPage(initialTabIndex: 2)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              setState(() {
                _allMedalsFuture = _loadCatalog(forceRefresh: true);
              });
              _loadMyMedals();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(tabMetrics.height + 3),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: LayoutBuilder(builder: (context, constraints) {
                final scrollable =
                    constraints.maxWidth < tabMetrics.minimumWidth;
                return TabBar(
                  controller: _tabController,
                  isScrollable: scrollable,
                  tabAlignment:
                      scrollable ? TabAlignment.start : TabAlignment.fill,
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: colorScheme.outline,
                  indicatorColor: colorScheme.primary,
                  indicatorWeight: 3,
                  labelStyle: tabStyle,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                  tabs: [
                    for (final label in tabLabels)
                      Tab(text: label, height: tabMetrics.height),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAllMedalsTab(),
              _buildMyMedalsTab(),
              _buildMedalOrderTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllMedalsTab() {
    final theme = Theme.of(context);
    void retry() {
      if (_savingOrder) return;
      setState(() {
        _allMedalsFuture = _loadCatalog(forceRefresh: true);
      });
      _loadMyMedals(forceRefresh: true);
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (_savingOrder) return;
        retry();
        try {
          await _allMedalsFuture;
        } catch (_) {}
      },
      child: FutureBuilder<List<MedalItem>>(
        future: _allMedalsFuture,
        builder: (context, snap) {
          final waiting = snap.connectionState != ConnectionState.done;
          final list = snap.hasError || waiting
              ? _catalogMedals
              : snap.data ?? const <MedalItem>[];
          if (waiting && list.isEmpty) {
            return const Center(child: AppLoadingIndicator());
          }
          final outage =
              snap.hasError ? ServerOutageInfo.tryParse(snap.error) : null;
          if (outage != null && list.isEmpty) {
            return ServerOutageView(outage: outage, onRetry: retry);
          }
          return LayoutBuilder(builder: (context, constraints) {
            return CustomScrollView(
              key: const ValueKey('medal-catalog-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (waiting)
                  const SliverToBoxAdapter(child: LinearProgressIndicator()),
                if (snap.hasError)
                  SliverToBoxAdapter(
                      child: _loadFailureNotice(
                          list.isEmpty ? '勋章中心读取失败，请重试' : '刷新失败，保留上次已加载的勋章',
                          retry)),
                if (_myIron != null)
                  SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      sliver: SliverToBoxAdapter(
                          child: _buildIronBannerWidget(context))),
                if (list.isEmpty && !snap.hasError)
                  const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyView(
                          icon: Icons.military_tech_outlined,
                          title: '暂无勋章',
                          subtitle: '网站当前未返回可展示的勋章')),
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                    sliver: constraints.maxWidth >= 600
                        ? SliverTwoColumnFeed(
                            itemCount: list.length,
                            spacing: 10,
                            itemBuilder: (_, i) =>
                                _buildMedalCard(list[i], theme))
                        : SliverList.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _buildMedalCard(list[i], theme)))),
              ],
            );
          });
        },
      ),
    );
  }

  Widget _loadFailureNotice(String message, VoidCallback retry) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('medal-load-error'),
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Icon(Icons.cloud_off_outlined, color: scheme.onErrorContainer),
        const SizedBox(width: 12),
        Expanded(
            child: Text(message,
                style: TextStyle(color: scheme.onErrorContainer))),
        TextButton(
            onPressed: _savingOrder || _loadingMyMedals ? null : retry,
            child: const Text('重试'))
      ]),
    );
  }

  Widget _withMyMedalsStatus(Widget child) => Column(children: [
        if (_loadingMyMedals) const LinearProgressIndicator(),
        if (_myMedalsError != null)
          _loadFailureNotice(
              _myMedalsError!, () => _loadMyMedals(forceRefresh: true)),
        Expanded(child: child),
      ]);

  Widget _buildIronBannerWidget(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CreditPage(initialTabIndex: 2),
          ),
        );
      },
      child: Builder(
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final iconColor =
              isDark ? Colors.amber.shade400 : Colors.amber.shade800;
          final textPrimaryColor =
              isDark ? Colors.amber.shade300 : Colors.amber.shade900;
          final linkColor =
              isDark ? Colors.amber.shade200 : Colors.amber.shade900;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.amber.withAlpha(20)
                  : Colors.amber.shade50.withAlpha(220),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    isDark ? Colors.amber.withAlpha(60) : Colors.amber.shade200,
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.monetization_on_outlined,
                    size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                    child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: '目前有 ',
                          style:
                              TextStyle(fontSize: 13, color: textPrimaryColor)),
                      TextSpan(
                        text: '铁粒 $_myIron 粒',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: textPrimaryColor),
                      ),
                    ],
                  ),
                )),
                const SizedBox(width: 8),
                Text(
                  '明细/转账 >',
                  style: TextStyle(
                      fontSize: 12,
                      color: linkColor,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMedalCard(MedalItem m, ThemeData theme) {
    final isOwned = _isMedalOwned(m);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: InkWell(
        onTap: () => _showMedalDetailDialog(m),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 勋章图片
              CachedNetworkImage(
                imageUrl: m.img,
                cacheKey: KlpbbsCacheManager.normalizeCacheKey(m.img),
                cacheManager: KlpbbsCacheManager.instance,
                httpHeaders: AppConfig.imageHeaders,
                width: 44,
                height: 44,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.military_tech, color: Colors.amber),
                ),
              ),
              const SizedBox(width: 12),

              // 名称与描述
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      m.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      m.desc.isNotEmpty ? m.desc : '查看勋章详情',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 右侧胶囊按钮
              if (isOwned)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Text(
                    '已拥有',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                )
              else if (m.isBuyable)
                FilledButton(
                  onPressed: () => _showMedalDetailDialog(m),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28)),
                  ),
                  child: const Text('购买',
                      style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.bold)),
                )
              else if (m.isApplyable)
                FilledButton(
                  onPressed: () => _showMedalDetailDialog(m),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28)),
                  ),
                  child: const Text('申请',
                      style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.bold)),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Text(
                    m.status.isNotEmpty ? m.status : '详情',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tab 2: 我的勋章列表
  Widget _buildMyMedalsTab() {
    final theme = Theme.of(context);
    if (_loadingMyMedals && _myMedals.isEmpty) {
      return const Center(child: AppLoadingIndicator());
    }
    return _withMyMedalsStatus(RefreshIndicator(
      onRefresh: () => _loadMyMedals(forceRefresh: true),
      child: _myMedals.isEmpty && _myMedalsError != null
          ? const SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: SizedBox(height: 240))
          : _myMedals.isEmpty
              ? LayoutBuilder(
                  builder: (ctx, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: EmptyView(
                        icon: Icons.military_tech_outlined,
                        title: '暂未佩戴任何勋章',
                        subtitle: '您尚未获得或佩戴论坛勋章，快去勋章中心看看吧',
                        action: FilledButton.tonal(
                          onPressed: () => _tabController.animateTo(0),
                          child: const Text('前往勋章中心'),
                        ),
                      ),
                    ),
                  ),
                )
              : LayoutBuilder(builder: (context, constraints) {
                  final scale =
                      MediaQuery.textScalerOf(context).scale(12.5) / 12.5;
                  final available =
                      (constraints.maxWidth - 28).clamp(1.0, double.infinity);
                  final minimumCardWidth = 160 * scale.clamp(1.0, 3.0);
                  final columns = ((available + 10) / (minimumCardWidth + 10))
                      .floor()
                      .clamp(1, 5);
                  final cardWidth = (available - 10 * (columns - 1)) / columns;
                  final textWidth =
                      (cardWidth - 16).clamp(1.0, double.infinity);
                  const titleStyle =
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5);
                  final detailStyle =
                      TextStyle(fontSize: 10, color: theme.colorScheme.outline);
                  var titleHeight = 0.0, detailHeight = 0.0;
                  for (final medal in _myMedals) {
                    final title = _medalLabelHeight(
                        context, medal.name, titleStyle, textWidth);
                    final detail = _medalLabelHeight(
                        context,
                        medal.id > 0 ? 'ID: ${medal.id}' : '网站未提供编号',
                        detailStyle,
                        textWidth,
                        maxLines: null);
                    if (title > titleHeight) titleHeight = title;
                    if (detail > detailHeight) detailHeight = detail;
                  }
                  return GridView.builder(
                    key: const ValueKey('medal-owned-grid'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 74 + titleHeight + detailHeight,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _myMedals.length,
                    itemBuilder: (ctx, i) {
                      final m = _myMedals[i];
                      return Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withAlpha(80)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            // 从勋章中心里找到对应的 MedalItem 弹出详情
                            final item = MedalItem(
                              id: m.id,
                              name: m.name,
                              desc: m.desc,
                              requirement: '已经拥有',
                              img: m.img,
                            );
                            _showMedalDetailDialog(item);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CachedNetworkImage(
                                  imageUrl: m.img,
                                  cacheKey:
                                      KlpbbsCacheManager.normalizeCacheKey(
                                          m.img),
                                  cacheManager: KlpbbsCacheManager.instance,
                                  httpHeaders: AppConfig.imageHeaders,
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, __, ___) => const Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                      size: 36),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  m.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  m.id > 0 ? 'ID: ${m.id}' : '网站未提供编号',
                                  textAlign: TextAlign.center,
                                  style: detailStyle,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
    ));
  }

  /// Tab 3: 勋章排序 (图四完整复刻)
  Widget _buildMedalOrderTab() {
    final theme = Theme.of(context);
    if (_loadingMyMedals && _myMedals.isEmpty) {
      return const Center(child: AppLoadingIndicator());
    }

    return _withMyMedalsStatus(RefreshIndicator(
      onRefresh: () => _loadMyMedals(forceRefresh: true),
      child: _myMedals.isEmpty && _myMedalsError != null
          ? const SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: SizedBox(height: 240))
          : _myMedals.isEmpty
              ? LayoutBuilder(
                  builder: (ctx, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: const EmptyView(
                        icon: Icons.sort_rounded,
                        title: '您暂无可用勋章进行排序',
                        subtitle: '拥有至少一枚勋章后即可在此调整显示次序',
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    // 顶部说明提示栏
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(50),
                        border: Border(
                          bottom: BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withAlpha(50)),
                        ),
                      ),
                      child: Text(
                        '调整勋章显示顺序后保存。排序功能及积分规则以论坛当前插件为准。',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4),
                      ),
                    ),

                    // 小副标题栏 (图四: 勋章显示顺序  用 上移 / 下移 调整顺序)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          Text(
                            '勋章显示顺序',
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '用 上移 / 下移 调整顺序',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                    ),

                    // 勋章排序列表 (图四)
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _myMedals.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 68,
                            color:
                                theme.colorScheme.outlineVariant.withAlpha(50)),
                        itemBuilder: (ctx, i) {
                          final m = _myMedals[i];
                          return Container(
                            color: theme.colorScheme.surface,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                // 勋章图标
                                CachedNetworkImage(
                                  imageUrl: m.img,
                                  cacheKey:
                                      KlpbbsCacheManager.normalizeCacheKey(
                                          m.img),
                                  cacheManager: KlpbbsCacheManager.instance,
                                  httpHeaders: AppConfig.imageHeaders,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, __, ___) => Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withAlpha(30),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.military_tech,
                                        color: Colors.amber),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // 勋章名称 + ID
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.name,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5,
                                            color: theme.colorScheme.onSurface),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '勋章 ID: ${m.id}',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: theme.colorScheme.outline),
                                      ),
                                    ],
                                  ),
                                ),

                                // 上移 按钮
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minHeight: 44),
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          theme.colorScheme.primary,
                                      side: BorderSide(
                                          color: theme.colorScheme.primary,
                                          width: 1),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                    ),
                                    onPressed: !_savingOrder && i > 0
                                        ? () => _moveUp(i)
                                        : null,
                                    child: const Text('上移',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // 下移 按钮
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minHeight: 44),
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          theme.colorScheme.primary,
                                      side: BorderSide(
                                          color: theme.colorScheme.primary,
                                          width: 1),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                    ),
                                    onPressed: !_savingOrder &&
                                            i < _myMedals.length - 1
                                        ? () => _moveDown(i)
                                        : null,
                                    child: const Text('下移',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // 底部全宽保存按钮
                    Container(
                      color: theme.colorScheme.surface,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: SafeArea(
                        top: false,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              minWidth: double.infinity, minHeight: 44),
                          child: FilledButton(
                            key: const ValueKey('medal-order-save'),
                            onPressed: _savingOrder ||
                                    _loadingMyMedals ||
                                    _myMedalsError != null
                                ? null
                                : _saveOrder,
                            child: _savingOrder
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: AppLoadingIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text(
                                    '保 存',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    ));
  }
}

double _medalLabelHeight(
    BuildContext context, String label, TextStyle style, double width,
    {int? maxLines = 2}) {
  final painter = TextPainter(
      text: TextSpan(
          text: label, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: maxLines,
      ellipsis: '\u2026')
    ..layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return height;
}

({double minimumWidth, double height}) _medalTabMetrics(
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
