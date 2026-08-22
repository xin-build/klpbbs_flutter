import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/write_confirm.dart';
import '../widgets/global_nav.dart';

/// 苦力怕论坛勋章中心（深度复刻图四：勋章中心 / 我的勋章 / 勋章排序，统一 Material 3 主题）
class MedalPage extends StatefulWidget {
  final int initialIndex;
  const MedalPage({super.key, this.initialIndex = 0});

  @override
  State<MedalPage> createState() => _MedalPageState();
}

class _MedalPageState extends State<MedalPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<List<({int id, String name, String desc, String img})>> _allMedalsFuture;
  List<({int id, String name, String desc, String img})> _myMedals = [];
  bool _loadingMyMedals = true;
  bool _savingOrder = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialIndex.clamp(0, 2));
    _allMedalsFuture = KlpbbsApi.getMedals();
    _loadMyMedals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMyMedals() async {
    try {
      final myUid = await KlpbbsApi.getMyUid();
      if (myUid != null) {
        final space = await KlpbbsApi.getUserSpace(myUid);
        if (space != null && space.medals.isNotEmpty) {
          if (mounted) {
            setState(() {
              _myMedals = List.from(space.medals);
              _loadingMyMedals = false;
            });
            return;
          }
        }
      }
      // fallback to all medals for display if empty
      final all = await _allMedalsFuture;
      if (mounted) {
        setState(() {
          _myMedals = all.take(10).toList();
          _loadingMyMedals = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMyMedals = false);
    }
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _myMedals.removeAt(index);
      _myMedals.insert(index - 1, item);
    });
  }

  void _moveDown(int index) {
    if (index >= _myMedals.length - 1) return;
    setState(() {
      final item = _myMedals.removeAt(index);
      _myMedals.insert(index + 1, item);
    });
  }

  Future<void> _saveOrder() async {
    final confirmed = await confirmWrite(context, '修改勋章排序（消耗 20 铁粒）');
    if (!confirmed || !mounted) return;

    setState(() => _savingOrder = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ids = _myMedals.map((m) => m.id).toList();
      final ok = await KlpbbsApi.saveMedalOrder(ids);
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? '勋章排序已保存生效' : '保存已提交'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('保存异常：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  void _showMedalDetailDialog(({int id, String name, String desc, String img}) m) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            CachedNetworkImage(
              imageUrl: m.img,
              httpHeaders: AppConfig.imageHeaders,
              width: 32,
              height: 32,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(Icons.military_tech, color: Colors.amber),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                m.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.desc.isNotEmpty ? m.desc : '苦力怕论坛特色成就勋章。',
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              '勋章 ID: ${m.id}',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final confirmed = await confirmWrite(context, '申请/购买勋章「${m.name}」');
              if (!confirmed || !mounted) return;
              final res = await KlpbbsApi.applyMedal(m.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('「${m.name}」: ${res.message}'),
                    backgroundColor: res.success ? null : Theme.of(context).colorScheme.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                if (res.success) {
                  _loadMyMedals();
                }
              }
            },
            child: const Text('立即购买/申请'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('勋章中心'),
        centerTitle: true,
        actions: const [GlobalNavButton()],
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          indicatorColor: theme.colorScheme.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          tabs: const [
            Tab(text: '勋章中心'),
            Tab(text: '我的勋章'),
            Tab(text: '勋章排序'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: 勋章中心
              _buildAllMedalsTab(),

              // Tab 2: 我的勋章
              _buildMyMedalsTab(),

              // Tab 3: 勋章排序 (图四深度复刻)
              _buildMedalOrderTab(),
            ],
          ),
        ),
      ),
    );
  }

  /// 判断勋章类型：人工授予 / 自主购买 / 达标申请
  static ({bool isManual, bool isBuyable, String actionLabel}) _getMedalActionType(
    ({int id, String name, String desc, String img}) m,
  ) {
    final d = m.desc.toLowerCase();
    if (d.contains('价格') || d.contains('个铁粒') || d.contains('售价') || m.name == '空气' || m.name == '五周年' || m.name == '炫富专用' || m.name.contains('铁粒回收')) {
      return (isManual: false, isBuyable: true, actionLabel: '购买');
    }
    if (d.contains('人工') || d.contains('官方授予') || d.contains('版主') || d.contains('管理') || d.contains('特殊贡献') || m.name.contains('周年') && !d.contains('价格')) {
      return (isManual: true, isBuyable: false, actionLabel: '人工授予');
    }
    if (d.contains('申请') || d.contains('条件') || d.contains('发帖') || d.contains('积分')) {
      return (isManual: false, isBuyable: false, actionLabel: '申请');
    }
    return (isManual: false, isBuyable: true, actionLabel: '购买/申请');
  }

  Future<void> _handleMedalAction(({int id, String name, String desc, String img}) m) async {
    final actionType = _getMedalActionType(m);
    if (actionType.isManual) return;

    final actionName = actionType.isBuyable ? '购买' : '申请';
    final confirmed = await confirmWrite(context, '$actionName勋章「${m.name}」');
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 10),
            Text('正在提交「${m.name}」$actionName请求...'),
          ],
        ),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final res = await KlpbbsApi.applyMedal(m.id);
    if (mounted) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.success ? '🎉「${m.name}」: ${res.message}' : '⚠️「${m.name}」: ${res.message}'),
          backgroundColor: res.success ? Colors.green.shade700 : Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      if (res.success) {
        _loadMyMedals();
      }
    }
  }

  /// Tab 1: 勋章中心列表
  Widget _buildAllMedalsTab() {
    final theme = Theme.of(context);
    return FutureBuilder<List<({int id, String name, String desc, String img})>>(
      future: _allMedalsFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const Center(child: Text('暂无勋章数据'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final m = list[i];
            final actionType = _getMedalActionType(m);

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CachedNetworkImage(
                      imageUrl: m.img,
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            m.desc.isNotEmpty ? m.desc : '勋章 ID: ${m.id}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (actionType.isManual)
                      FilledButton.tonal(
                        onPressed: null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                          disabledForegroundColor: theme.colorScheme.outline.withAlpha(120),
                        ),
                        child: const Text('人工授予', style: TextStyle(fontSize: 12)),
                      )
                    else if (actionType.isBuyable)
                      FilledButton(
                        onPressed: () => _handleMedalAction(m),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('购买', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    else
                      FilledButton.tonal(
                        onPressed: () => _handleMedalAction(m),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('申请', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Tab 2: 我的勋章列表
  Widget _buildMyMedalsTab() {
    final theme = Theme.of(context);
    if (_loadingMyMedals) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_myMedals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.military_tech_outlined, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            const Text('暂未佩戴任何勋章'),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => _tabController.animateTo(0),
              child: const Text('去勋章中心看看'),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: _myMedals.length,
      itemBuilder: (ctx, i) {
        final m = _myMedals[i];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _showMedalDetailDialog(m),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CachedNetworkImage(
                    imageUrl: m.img,
                    httpHeaders: AppConfig.imageHeaders,
                    width: 42,
                    height: 42,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const Icon(Icons.star, color: Colors.amber, size: 36),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${m.id}',
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Tab 3: 勋章排序 (图四完整复刻)
  Widget _buildMedalOrderTab() {
    final theme = Theme.of(context);
    if (_loadingMyMedals) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_myMedals.isEmpty) {
      return const Center(child: Text('您暂无可用勋章进行排序'));
    }

    return Column(
      children: [
        // 顶部说明提示栏 (图四)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(50)),
            ),
          ),
          child: Text(
            '您可以在这里修改您的勋章显示排序。\n每次修改勋章排序需要消耗 铁粒 20 粒。',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant, height: 1.4),
          ),
        ),

        // 小副标题栏 (图四: 勋章显示顺序  用 上移 / 下移 调整顺序)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Text(
                '勋章显示顺序',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '用 上移 / 下移 调整顺序',
                style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),

        // 勋章排序列表 (图四)
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _myMedals.length,
            separatorBuilder: (_, __) => Divider(height: 1, indent: 68, color: theme.colorScheme.outlineVariant.withAlpha(50)),
            itemBuilder: (ctx, i) {
              final m = _myMedals[i];
              return Container(
                color: theme.colorScheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    // 勋章图标
                    CachedNetworkImage(
                      imageUrl: m.img,
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
                        child: const Icon(Icons.military_tech, color: Colors.amber),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 勋章名称 + ID (图四)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: theme.colorScheme.onSurface),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '勋章 ID: ${m.id}',
                            style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                    ),

                    // 上移 按钮 (图四: 橙色线框)
                    SizedBox(
                      height: 30,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF57C00),
                          side: const BorderSide(color: Color(0xFFF57C00), width: 1),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: i > 0 ? () => _moveUp(i) : null,
                        child: const Text('上移', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 下移 按钮 (图四: 橙色线框)
                    SizedBox(
                      height: 30,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF57C00),
                          side: const BorderSide(color: Color(0xFFF57C00), width: 1),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: i < _myMedals.length - 1 ? () => _moveDown(i) : null,
                        child: const Text('下移', style: TextStyle(fontSize: 12)),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: _savingOrder ? null : _saveOrder,
                child: _savingOrder
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        '保 存',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
