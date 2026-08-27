import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../models/magic_item.dart';
import '../widgets/app_back_button.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_nav.dart';
import 'credit_page.dart';
import 'login_page.dart';

/// 苦力怕论坛 道具中心（1:1 精确像素级还原官方移动端与完整道具系统）
class MagicPage extends StatefulWidget {
  final int initialTab; // 0: 道具商店, 1: 我的道具, 2: 道具记录

  const MagicPage({super.key, this.initialTab = 0});

  @override
  State<MagicPage> createState() => _MagicPageState();
}

class _MagicPageState extends State<MagicPage> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // 道具商店状态
  Future<({List<MagicItem> magics, MagicBagInfo bag})>? _shopFuture;

  // 我的道具包状态
  Future<({List<MagicItem> magics, MagicBagInfo bag})>? _myboxFuture;

  // 道具记录状态
  Future<List<MagicLogEntry>>? _logFuture;
  String _selectedLogOp = 'uselog';

  MagicBagInfo _currentBag = const MagicBagInfo(usedCapacity: 110, totalCapacity: 500, ironCount: 0);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _tabCtrl.addListener(_onTabChanged);
    _loadTab(widget.initialTab);
  }

  void _onTabChanged() {
    if (!_tabCtrl.indexIsChanging && mounted) {
      _loadTab(_tabCtrl.index);
      setState(() {});
    }
  }

  void _loadTab(int index) {
    if (index == 0 && _shopFuture == null) {
      _reloadShop();
    } else if (index == 1 && _myboxFuture == null) {
      _reloadMybox();
    } else if (index == 2 && _logFuture == null) {
      _reloadLogs();
    }
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _loadAll() {
    _reloadShop();
    _reloadMybox();
    _reloadLogs();
  }

  void _reloadShop() {
    setState(() {
      _shopFuture = KlpbbsApi.getMagicShop().then((res) {
        if (mounted) setState(() => _currentBag = res.bag);
        return res;
      });
    });
  }

  void _reloadMybox() {
    setState(() {
      _myboxFuture = KlpbbsApi.getMyMagics().then((res) {
        var bag = res.bag;
        if (bag.usedCapacity == 0 && res.magics.isNotEmpty) {
          final calculatedUsed = res.magics.fold<int>(
            0,
            (sum, item) => sum + item.count * (item.weight > 0 ? item.weight : 10),
          );
          bag = MagicBagInfo(
            usedCapacity: calculatedUsed,
            totalCapacity: bag.totalCapacity > 0 ? bag.totalCapacity : 500,
            ironCount: bag.ironCount,
          );
        }
        if (mounted) setState(() => _currentBag = bag);
        return (magics: res.magics, bag: bag);
      });
    });
  }

  void _reloadLogs() {
    setState(() {
      _logFuture = KlpbbsApi.getMagicLogs(op: _selectedLogOp);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('道具中心'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              if (_tabCtrl.index == 0) {
                _reloadShop();
              } else if (_tabCtrl.index == 1) {
                _reloadMybox();
              } else {
                _reloadLogs();
              }
            },
          ),
          const GlobalNavButton(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            color: colorScheme.surface,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.outline,
              indicatorColor: colorScheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              tabs: const [
                Tab(text: '道具商店'),
                Tab(text: '我的道具'),
                Tab(text: '道具记录'),
              ],
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              // 顶部道具包容量与铁粒资产条（1:1 还原官方移动端头部）
              _buildHeaderStats(colorScheme),
              const Divider(height: 1, thickness: 0.8),

              // 核心 Tab 视图
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildShopTab(colorScheme),
                    _buildMyboxTab(colorScheme),
                    _buildLogsTab(colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部道具包容量与铁粒资产条
  Widget _buildHeaderStats(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colorScheme.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                '我的道具包容量: ',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '${_currentBag.usedCapacity}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF07B00),
                ),
              ),
              Text(
                ' / ${_currentBag.totalCapacity}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreditPage()),
              ).then((_) => _loadAll());
            },
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 15),
            label: const Text('我的积分', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: 道具商店
  // ---------------------------------------------------------------------------
  Widget _buildShopTab(ColorScheme colorScheme) {
    return FutureBuilder<({List<MagicItem> magics, MagicBagInfo bag})>(
      future: _shopFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError && (!snap.hasData || snap.data!.magics.isEmpty)) {
          return EmptyView(
            icon: Icons.error_outline,
            title: '加载商店失败',
            subtitle: '${snap.error}',
            action: FilledButton.tonal(
              onPressed: _reloadShop,
              child: const Text('重试'),
            ),
          );
        }

        final list = snap.data?.magics ?? const [];
        if (list.isEmpty) {
          return const EmptyView(
            icon: Icons.inventory_2_outlined,
            title: '暂无可购买道具',
            subtitle: '请稍后再来看看',
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reloadShop(),
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisExtent: 175,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final item = list[i];
              return _buildShopItemCard(item, colorScheme);
            },
          ),
        );
      },
    );
  }

  /// 道具商店卡片（1:1 像素级还原官方移动端卡片）
  Widget _buildShopItemCard(MagicItem item, ColorScheme colorScheme) {
    const greenBtnColor = Color(0xFF78C252);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(80),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              onTap: () => _showMagicDescDialog(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 图标展示容器（居中灰色圆角外框）
                    Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withAlpha(80),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withAlpha(60),
                          width: 1,
                        ),
                      ),
                      child: item.img.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: item.img,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.auto_fix_high,
                                color: colorScheme.primary,
                                size: 26,
                              ),
                            )
                          : Icon(
                              Icons.auto_fix_high,
                              color: colorScheme.primary,
                              size: 26,
                            ),
                    ),
                    const SizedBox(height: 6),
                    // 道具名称
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // 道具价格（数字橙色）
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '铁粒 ',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF888888),
                          ),
                        ),
                        Text(
                          '${item.price}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF07B00),
                          ),
                        ),
                        Text(
                          ' ${item.unit.contains('/') ? item.unit : '粒/张'}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 底部绿色双按钮横条（购买 | 赠送）
          Container(
            height: 30,
            decoration: const BoxDecoration(
              color: greenBtnColor,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(7)),
                    onTap: () => _showBuyDialog(item),
                    child: const Center(
                      child: Text(
                        '购买',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 14,
                  color: Colors.white.withAlpha(120),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.only(bottomRight: Radius.circular(7)),
                    onTap: () => _showGiveDialog(item),
                    child: const Center(
                      child: Text(
                        '赠送',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: 我的道具
  // ---------------------------------------------------------------------------
  Widget _buildMyboxTab(ColorScheme colorScheme) {
    if (!DioClient.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('查看我的道具包需要登录论坛账号', style: TextStyle(fontSize: 15)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ).then((_) => _loadAll());
                },
                child: const Text('立即登录'),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<({List<MagicItem> magics, MagicBagInfo bag})>(
      future: _myboxFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyView(
            icon: Icons.error_outline,
            title: '加载道具包失败',
            subtitle: '${snap.error}',
            action: FilledButton.tonal(
              onPressed: _reloadMybox,
              child: const Text('重试'),
            ),
          );
        }

        final list = snap.data?.magics ?? const [];
        if (list.isEmpty) {
          return EmptyView(
            icon: Icons.work_outline,
            title: '道具包空空如也',
            subtitle: '前往道具商店挑选心仪的道具吧',
            action: FilledButton.tonal(
              onPressed: () => _tabCtrl.animateTo(0),
              child: const Text('前往道具商店'),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reloadMybox(),
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisExtent: 175,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final item = list[i];
              return _buildMyboxItemCard(item, colorScheme);
            },
          ),
        );
      },
    );
  }

  /// 我的道具卡片（使用 | 赠送 | 出售）
  Widget _buildMyboxItemCard(MagicItem item, ColorScheme colorScheme) {
    const greenBtnColor = Color(0xFF78C252);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(80),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              onTap: () => _showMagicDescDialog(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withAlpha(80),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withAlpha(60),
                          width: 1,
                        ),
                      ),
                      child: item.img.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: item.img,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.auto_fix_high,
                                color: colorScheme.primary,
                                size: 26,
                              ),
                            )
                          : Icon(
                              Icons.auto_fix_high,
                              color: colorScheme.primary,
                              size: 26,
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '数量: ',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF888888),
                          ),
                        ),
                        Text(
                          '${item.count}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF07B00),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 底部操作横条（使用 | 赠送 | 出售）
          Container(
            height: 30,
            decoration: const BoxDecoration(
              color: greenBtnColor,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
            ),
            child: Row(
              children: [
                if (item.canUse) ...[
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(7)),
                      onTap: () => _showUseDialog(item),
                      child: const Center(
                        child: Text(
                          '使用',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 14, color: Colors.white.withAlpha(120)),
                ],
                Expanded(
                  child: InkWell(
                    borderRadius: !item.canUse ? const BorderRadius.only(bottomLeft: Radius.circular(7)) : BorderRadius.zero,
                    onTap: () => _showGiveDialog(item),
                    child: const Center(
                      child: Text(
                        '赠送',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(width: 1, height: 14, color: Colors.white.withAlpha(120)),
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.only(bottomRight: Radius.circular(7)),
                    onTap: () => _showDropDialog(item),
                    child: const Center(
                      child: Text(
                        '出售',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: 道具记录
  // ---------------------------------------------------------------------------
  Widget _buildLogsTab(ColorScheme colorScheme) {
    if (!DioClient.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('查看道具记录需要登录论坛账号', style: TextStyle(fontSize: 15)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ).then((_) => _loadAll());
                },
                child: const Text('立即登录'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // 记录子分类筛选栏（1:1 还原 Image 2: 使用记录 / 购买记录 / 赠送记录 / 获赠记录）
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: colorScheme.surface,
          child: Row(
            children: [
              _buildLogTextTab('使用记录', 'uselog', colorScheme),
              _buildLogTabDivider(colorScheme),
              _buildLogTextTab('购买记录', 'buylog', colorScheme),
              _buildLogTabDivider(colorScheme),
              _buildLogTextTab('赠送记录', 'givelog', colorScheme),
              _buildLogTabDivider(colorScheme),
              _buildLogTextTab('获赠记录', 'receivelog', colorScheme),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.8),

        // 记录列表
        Expanded(
          child: FutureBuilder<List<MagicLogEntry>>(
            future: _logFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done && !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return EmptyView(
                  icon: Icons.error_outline,
                  title: '加载记录失败',
                  subtitle: '${snap.error}',
                  action: FilledButton.tonal(
                    onPressed: _reloadLogs,
                    child: const Text('重试'),
                  ),
                );
              }

              final logs = snap.data ?? const [];
              if (logs.isEmpty) {
                return const EmptyView(
                  icon: Icons.receipt_long_outlined,
                  title: '暂无相关道具记录',
                  subtitle: '在道具商店购买或使用道具后将在这里生成记录',
                );
              }

              return RefreshIndicator(
                onRefresh: () async => _reloadLogs(),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.6),
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      color: colorScheme.surface,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                log.magicName,
                                style: const TextStyle(
                                  color: Color(0xFF1890FF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                log.time,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                          if (log.action.isNotEmpty && log.action != log.magicName) ...[
                            const SizedBox(height: 5),
                            Text(
                              log.action,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogTabDivider(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '/',
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.outlineVariant,
        ),
      ),
    );
  }

  Widget _buildLogTextTab(String title, String op, ColorScheme colorScheme) {
    final isSelected = _selectedLogOp == op;
    return InkWell(
      onTap: () {
        if (_selectedLogOp != op) {
          setState(() {
            _selectedLogOp = op;
            _reloadLogs();
          });
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFF1890FF) : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }



  // ---------------------------------------------------------------------------
  // 弹窗逻辑：道具介绍、购买、赠送、使用、回收
  // ---------------------------------------------------------------------------

  /// 道具介绍详情弹窗
  void _showMagicDescDialog(MagicItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            if (item.img.isNotEmpty)
              CachedNetworkImage(
                imageUrl: item.img,
                width: 24,
                height: 24,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) => const Icon(Icons.auto_fix_high, size: 24),
              ),
            const SizedBox(width: 8),
            Text(item.name),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.desc.isNotEmpty ? item.desc : '该道具暂无详细说明。',
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('售价: ${item.price} 铁粒/张', style: const TextStyle(fontSize: 12)),
                  Text('重量: ${item.weight}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showBuyDialog(item);
            },
            child: const Text('立即购买'),
          ),
        ],
      ),
    );
  }

  /// 购买道具弹窗
  void _showBuyDialog(MagicItem item) {
    if (!DioClient.isLoggedIn) {
      _showNeedLoginDialog();
      return;
    }

    int count = 1;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totalCost = item.price * count;
          final canAfford = _currentBag.ironCount >= totalCost;

          return AlertDialog(
            title: Text('购买「${item.name}」'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('道具单价:'),
                    Text('${item.price} 铁粒/张', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('购买数量:'),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: count > 1 ? () => setDialogState(() => count--) : null,
                        ),
                        Container(
                          width: 48,
                          alignment: Alignment.center,
                          child: Text(
                            '$count',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setDialogState(() => count++),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('所需铁粒:'),
                    Text(
                      '$totalCost 粒',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF07B00),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('当前拥有:'),
                    Text(
                      '${_currentBag.ironCount} 粒',
                      style: TextStyle(
                        fontSize: 12,
                        color: canAfford ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (!canAfford)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '抱歉，您的铁粒余额不足',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: (!canAfford || submitting)
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(ctx);
                        setDialogState(() => submitting = true);
                        final res = await KlpbbsApi.buyMagic(item.id, count: count);
                        if (mounted) {
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(res.message),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          if (res.success) {
                            _loadAll();
                          }
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('确认购买'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 赠送道具弹窗
  void _showGiveDialog(MagicItem item) {
    if (!DioClient.isLoggedIn) {
      _showNeedLoginDialog();
      return;
    }

    final userCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    int count = 1;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('赠送「${item.name}」'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: userCtrl,
                    decoration: const InputDecoration(
                      labelText: '接收人用户名',
                      hintText: '请输入对方论坛用户名',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('赠送数量:'),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: count > 1 ? () => setDialogState(() => count--) : null,
                          ),
                          Container(
                            width: 48,
                            alignment: Alignment.center,
                            child: Text(
                              '$count',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => setDialogState(() => count++),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: '赠言留言（可选）',
                      hintText: '送你一张道具卡，请查收~',
                      prefixIcon: Icon(Icons.chat_bubble_outline),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        final username = userCtrl.text.trim();
                        if (username.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('请输入接收人用户名')),
                          );
                          return;
                        }

                        final messenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(ctx);
                        setDialogState(() => submitting = true);
                        final res = await KlpbbsApi.giveMagic(
                          item.id,
                          username: username,
                          count: count,
                          message: noteCtrl.text.trim(),
                        );
                        if (mounted) {
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(res.message),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          if (res.success) {
                            _loadAll();
                          }
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('确认赠送'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 使用道具弹窗
  void _showUseDialog(MagicItem item) {
    final tidCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    bool submitting = false;

    final isBump = item.name.contains('提升') || item.identifier == 'bump';
    final isNamecard = item.name.contains('改名') || item.identifier == 'namecard';
    final isAnonymous = item.name.contains('匿名') || item.identifier == 'anonymous';
    final isObserver = item.name.contains('观察') || item.identifier == 'observer';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('使用「${item.name}」'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.desc.isNotEmpty ? item.desc : '确定要使用一张「${item.name}」吗？',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                if (isBump || isAnonymous)
                  TextField(
                    controller: tidCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '目标主题 ID (TID)',
                      hintText: '例如 123456',
                      prefixIcon: Icon(Icons.article_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (isNamecard)
                  TextField(
                    controller: userCtrl,
                    decoration: const InputDecoration(
                      labelText: '新用户名',
                      hintText: '请输入修改后的新用户名',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (isObserver)
                  TextField(
                    controller: userCtrl,
                    decoration: const InputDecoration(
                      labelText: '目标用户名',
                      hintText: '请输入要查看的用户',
                      prefixIcon: Icon(Icons.person_search_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        final tid = int.tryParse(tidCtrl.text.trim());
                        final target = userCtrl.text.trim();

                        final messenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(ctx);
                        setDialogState(() => submitting = true);
                        final res = await KlpbbsApi.useMagic(
                          item.id,
                          tid: tid,
                          targetUsername: isObserver ? target : null,
                          newUsername: isNamecard ? target : null,
                        );
                        if (mounted) {
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(res.message),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          if (res.success) {
                            _loadAll();
                          }
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('确认使用'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 回收/丢弃道具弹窗
  void _showDropDialog(MagicItem item) {
    int count = 1;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('回收「${item.name}」'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('确定要回收该道具吗？回收后将腾出道具包空间。', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('回收数量:'),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: count > 1 ? () => setDialogState(() => count--) : null,
                        ),
                        Container(
                          width: 48,
                          alignment: Alignment.center,
                          child: Text(
                            '$count',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: count < item.count ? () => setDialogState(() => count++) : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: submitting
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(ctx);
                        setDialogState(() => submitting = true);
                        final res = await KlpbbsApi.dropMagic(item.id, count: count);
                        if (mounted) {
                          nav.pop();
                          messenger.showSnackBar(
                            SnackBar(content: Text(res.message)),
                          );
                          if (res.success) {
                            _loadAll();
                          }
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('确认回收'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showNeedLoginDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要登录'),
        content: const Text('购买或赠送道具需要先登录苦力怕论坛账号。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              ).then((_) => _loadAll());
            },
            child: const Text('去登录'),
          ),
        ],
      ),
    );
  }
}
