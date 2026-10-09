import '../app_motion.dart';
import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/magic_item.dart';
import '../../core/dio_client.dart';
import '../../core/preload_service.dart';
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
  bool _failed = false;
  bool _known = false;

  @override
  void initState() {
    super.initState();
    final cached = PreloadService.instance
        .get<({List<MagicItem> magics, MagicBagInfo bag})>(
            'magic_collection_mybox_1',
            ignoreExpired: true);
    _magics = cached?.magics ?? [];
    _known = cached != null;
    _loading = !widget.isPreview && !_known;
    if (widget.isPreview) {
      _loading = false;
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final session = DioClient.sessionKey;
    try {
      final res = await KlpbbsApi.getMyMagics();
      if (mounted && session == DioClient.sessionKey) {
        setState(() {
          _magics = res.magics;
          _known = true;
          _failed = false;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && session == DioClient.sessionKey) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.item.rowSpan <= 1;
    final isNarrow = widget.item.colSpan <= 2;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty)
        ? customTitle
        : '我的道具背包';

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MagicPage(initialTab: 1))),
        child: _loading
            ? const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: AppLoadingIndicator(strokeWidth: 2)))
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
          child: const Icon(Icons.auto_fix_high_rounded,
              size: 18, color: Colors.white),
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
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                _failed
                    ? '暂时无法读取背包 · 点击查看'
                    : _magics.isNotEmpty
                        ? '本页 ${_magics.length} 种道具'
                        : !_known
                            ? '尚未载入背包数据'
                            : '背包内暂无道具',
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
          child: const Text('道具 >',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo)),
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
            Icon(Icons.auto_fix_high_rounded,
                size: 17, color: Colors.indigo.shade600),
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
            Text('道具商城 >',
                style: TextStyle(fontSize: 11, color: colorScheme.primary)),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _magics.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 26, color: colorScheme.outlineVariant),
                      const SizedBox(height: 4),
                      Text(
                          _failed
                              ? '背包暂时无法读取'
                              : !_known
                                  ? '尚未载入背包数据'
                                  : '背包内暂无道具',
                          style: TextStyle(
                              fontSize: 11, color: colorScheme.outline)),
                      const SizedBox(height: 2),
                      Text('点击前往道具商城挑选',
                          style: TextStyle(
                              fontSize: 9.5, color: colorScheme.primary)),
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
                          border: Border.all(
                              color: Colors.indigo.withAlpha(45), width: 0.8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.auto_fix_high_rounded,
                                size: 20, color: Colors.indigo),
                            const SizedBox(height: 2),
                            Text(m.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold)),
                            Text(m.count < 0 ? '数量未提供' : '× ${m.count}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo)),
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
