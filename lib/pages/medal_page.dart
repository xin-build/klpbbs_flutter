import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/write_confirm.dart';
import '../models/medal_item.dart';
import '../widgets/app_back_button.dart';
import '../widgets/global_nav.dart';
import 'credit_page.dart';

/// 苦力怕论坛勋章中心（深度复刻图四与官方移动端：勋章中心 / 我的勋章 / 勋章排序，统一 Material 3 主题）
class MedalPage extends StatefulWidget {
  final int initialIndex;
  const MedalPage({super.key, this.initialIndex = 0});

  @override
  State<MedalPage> createState() => _MedalPageState();
}

class _MedalPageState extends State<MedalPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<List<MedalItem>> _allMedalsFuture;
  List<({int id, String name, String desc, String img})> _myMedals = [];
  bool _loadingMyMedals = true;
  bool _savingOrder = false;

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
    _allMedalsFuture = KlpbbsApi.getMedals();
    _loadMyMedals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int? _myIron;

  bool _isMedalOwned(MedalItem m) {
    return _myMedals.any((x) =>
        (m.id > 0 && x.id == m.id) ||
        (m.name.isNotEmpty && x.name == m.name) ||
        (m.img.isNotEmpty && x.img.isNotEmpty && (m.img.endsWith(x.img) || x.img.endsWith(m.img))));
  }

  Future<void> _loadMyMedals() async {
    try {
      final myUid = await KlpbbsApi.getMyUid();
      if (myUid != null && myUid > 0) {
        final space = await KlpbbsApi.getUserSpace(myUid);
        if (space != null) {
          int? iron;
          final ironStr = space.creditsDetail['铁粒'] ?? space.stats['铁粒'];
          if (ironStr != null) {
            iron = int.tryParse(ironStr);
          } else {
            iron = int.tryParse(space.credits);
          }
          if (mounted) {
            setState(() {
              _myIron = iron;
              _myMedals = List.from(space.medals);
              _loadingMyMedals = false;
            });
            return;
          }
        }
      }
      final medals = await KlpbbsApi.getMyMedalsList();
      if (mounted) {
        setState(() {
          _myMedals = medals;
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

  /// 勋章详情弹窗（像素级复刻官方移动端弹窗，对齐 Image 2）
  void _showMedalDetailDialog(MedalItem m) {
    final isOwned = _isMedalOwned(m);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Container(
            width: 320,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                      child: Icon(Icons.close, size: 20, color: theme.colorScheme.outline),
                    ),
                  ),
                ),

                // 勋章图片
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(60),
                      width: 0.8,
                    ),
                  ),
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: m.img,
                    httpHeaders: AppConfig.imageHeaders,
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const Icon(Icons.military_tech, color: Colors.amber, size: 36),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 勋章名称
              Text(
                m.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),

              // 勋章描述
              Text(
                m.desc.isNotEmpty ? m.desc : '苦力怕论坛特色成就勋章。',
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
              SizedBox(
                width: double.infinity,
                height: 44,
                child: isOwned
                    ? FilledButton(
                        onPressed: null,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('已经拥有', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      )
                    : (m.isBuyable || m.isApplyable)
                        ? FilledButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _handleMedalAction(m);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF8BC34A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(
                              m.isBuyable ? '购买' : '申请',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          )
                        : FilledButton(
                            onPressed: null,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.grey.shade300,
                              disabledBackgroundColor: Colors.grey.shade300,
                              disabledForegroundColor: Colors.grey.shade600,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('人工授予', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                          ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  Future<void> _handleMedalAction(MedalItem m) async {
    final isOwned = _isMedalOwned(m);
    if (isOwned || m.isManual) return;

    final actionName = m.isBuyable ? '购买' : '申请';
    final req = m.requirement;
    final confirmText = m.isBuyable
        ? '购买勋章「${m.name}」（需消耗 $req）'
        : '申请勋章「${m.name}」（需满足 $req）';
    final confirmed = await confirmWrite(context, confirmText);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('勋章中心', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: '积分记录',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 2)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              setState(() {
                _allMedalsFuture = KlpbbsApi.getMedals();
              });
              _loadMyMedals();
            },
          ),
          const GlobalNavButton(),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.outline,
          indicatorColor: colorScheme.primary,
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

  /// Tab 1: 勋章中心列表（像素级复刻官方移动端列表，对齐 Image 2）
  Widget _buildAllMedalsTab() {
    final theme = Theme.of(context);
    return FutureBuilder<List<MedalItem>>(
      future: _allMedalsFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const Center(child: Text('暂无勋章数据'));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
          itemCount: list.length + (_myIron != null ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (_myIron != null && i == 0) {
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
                    final iconColor = isDark ? Colors.amber.shade400 : Colors.amber.shade800;
                    final textPrimaryColor = isDark ? Colors.amber.shade300 : Colors.amber.shade900;
                    final linkColor = isDark ? Colors.amber.shade200 : Colors.amber.shade900;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.amber.withAlpha(20) : Colors.amber.shade50.withAlpha(220),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.amber.withAlpha(60) : Colors.amber.shade200,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.monetization_on_outlined, size: 18, color: iconColor),
                          const SizedBox(width: 8),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '目前有 ', style: TextStyle(fontSize: 13, color: textPrimaryColor)),
                                TextSpan(
                                  text: '铁粒 $_myIron 粒',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimaryColor),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '明细/转账 >',
                            style: TextStyle(fontSize: 12, color: linkColor, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            }

            final m = list[_myIron != null ? i - 1 : i];
            final isOwned = _isMedalOwned(m);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                ),
                child: InkWell(
                  onTap: () => _showMedalDetailDialog(m),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // 勋章图片
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

                        // 名称与描述
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
                        const SizedBox(width: 10),

                        // 右侧胶囊按钮（对齐 Image 2）
                        if (isOwned)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '已经拥有',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          )
                        else if (m.isBuyable)
                          FilledButton(
                            onPressed: () => _showMedalDetailDialog(m),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('立即购买', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        else if (m.isApplyable)
                          FilledButton(
                            onPressed: () => _showMedalDetailDialog(m),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('在线申请', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '人工授予',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.military_tech_outlined, size: 56, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              const Text('暂未佩戴任何勋章', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                '您尚未获得或佩戴论坛勋章，快去勋章中心看看吧',
                style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: () => _tabController.animateTo(0),
                child: const Text('前往勋章中心'),
              ),
            ],
          ),
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
        // 顶部说明提示栏
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

                    // 勋章名称 + ID
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

                    // 上移 按钮
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

                    // 下移 按钮
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
