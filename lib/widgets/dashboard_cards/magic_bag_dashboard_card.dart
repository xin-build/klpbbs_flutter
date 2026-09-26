import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/magic_item.dart';
import '../../pages/magic_page.dart';
import 'dashboard_card_frame.dart';

/// 9. 我的道具背包卡片（对接真实道具箱数据，支持 GPU 隔离与 LOD 尺寸自适应）
class MagicBagDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const MagicBagDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<MagicBagDashboardCard> createState() => _MagicBagDashboardCardState();
}

class _MagicBagDashboardCardState extends State<MagicBagDashboardCard> {
  List<MagicItem> _magics = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.isPreview) {
      _magics = const [
        MagicItem(
          id: 1,
          identifier: 'bump',
          name: '提升卡',
          desc: '将主题提升至版块前列',
          img: '',
          price: 50,
          weight: 10,
          count: 3,
        ),
        MagicItem(
          id: 2,
          identifier: 'renamecard',
          name: '改名卡',
          desc: '修改自己的论坛用户名',
          img: '',
          price: 100,
          weight: 10,
          count: 1,
        ),
      ];
      _loading = false;
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    try {
      final res = await KlpbbsApi.getMyMagics();
      if (mounted) {
        setState(() {
          _magics = res.magics;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.item.rowSpan <= 1;
    final isNarrow = widget.item.colSpan <= 2;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '我的道具背包';

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MagicPage())),
        child: _loading
            ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            : (isCompact || isNarrow)
                ? _buildCompact(context, title)
                : _buildExpanded(context, title),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.indigo.shade400, Colors.deepPurple.shade700],
            ),
          ),
          child: const Icon(Icons.auto_fix_high_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                _magics.isNotEmpty
                    ? '现有 ${_magics.fold<int>(0, (s, m) => s + m.count)} 件道具'
                    : '背包空空如也 · 点击选购',
                maxLines: 1,
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.indigo.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('道具 >', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.indigo)),
        ),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_fix_high_rounded, size: 17, color: Colors.indigo.shade600),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Text('道具商城 >', style: TextStyle(fontSize: 11, color: colorScheme.primary)),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _magics.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 26, color: colorScheme.outlineVariant),
                      const SizedBox(height: 4),
                      Text('背包内暂无可用道具', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                      const SizedBox(height: 2),
                      Text('点击前往道具商城挑选', style: TextStyle(fontSize: 9.5, color: colorScheme.primary)),
                    ],
                  ),
                )
              : Row(
                  children: _magics.take(3).map((m) {
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withAlpha(15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.withAlpha(45), width: 0.8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.auto_fix_high_rounded, size: 20, color: Colors.indigo),
                            const SizedBox(height: 2),
                            Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            Text('× ${m.count}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}
