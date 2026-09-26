import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/medal_page.dart';
import 'dashboard_card_frame.dart';

/// 3. 勋章展示墙卡片（深度支持多阶 LOD 尺寸缩放自适应与 GPU 图层光栅化）
class MedalDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const MedalDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<MedalDashboardCard> createState() => _MedalDashboardCardState();
}

class _MedalDashboardCardState extends State<MedalDashboardCard> {
  List<({int id, String name, String desc, String img})> _medals = [];
  bool _loading = true;

  // 预览占位数据（真实论坛风格名称，无失效外链）
  static const List<({int id, String name, String desc, String img})> _fixedPreviewMedals = [
    (id: 1, name: '开荒先锋', desc: '论坛资深活跃开荒者', img: ''),
    (id: 2, name: '红石爱好者', desc: '精通机械与红石工程', img: ''),
    (id: 3, name: '资源达人', desc: '优质资源分享者', img: ''),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isPreview) {
      _medals = _fixedPreviewMedals;
      _loading = false;
    } else {
      _loadRealMedals();
    }
  }

  Future<void> _loadRealMedals() async {
    try {
      final list = await KlpbbsApi.getMyMedalsList();
      if (mounted) {
        setState(() {
          _medals = list; // 真实数据，绝不无中生有乱填
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _medals = [];
          _loading = false;
        });
      }
    }
  }

  void _openMedalPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MedalPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompact = widget.item.rowSpan <= 1;
    final isNarrow = widget.item.colSpan <= 2;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '荣誉勋章墙';

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        onTap: _openMedalPage,
        child: _loading
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                ),
              )
            : (isCompact || isNarrow)
                ? _buildCompactLOD(context, title: title)
                : _buildFullLOD(context, title: title),
      ),
    );
  }

  /// 缩放较小（2x1）时的极简自适应外观
  Widget _buildCompactLOD(BuildContext context, {required String title}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.amber.shade400, Colors.orange.shade700],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withAlpha(80),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.military_tech_rounded, size: 20, color: Colors.white),
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
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              Text(
                _medals.isNotEmpty ? '已佩戴 ${_medals.length} 枚荣誉勋章' : '暂未佩戴勋章 · 点击前往中心',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.amber.withAlpha(35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.withAlpha(90), width: 0.8),
          ),
          child: Text(
            '${_medals.length} 枚',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amber.shade800),
          ),
        ),
      ],
    );
  }

  /// 展开多列网格时的丰富陈列室
  Widget _buildFullLOD(BuildContext context, {required String title}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.military_tech_rounded, size: 16, color: Colors.amber.shade700),
            ),
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
            Text(
              _medals.isNotEmpty ? '共 ${_medals.length} 枚 >' : '勋章中心 >',
              style: TextStyle(fontSize: 11, color: colorScheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _medals.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.military_tech_outlined, size: 26, color: colorScheme.outlineVariant),
                      const SizedBox(height: 4),
                      Text('暂未佩戴勋章', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                      const SizedBox(height: 2),
                      Text('点击前往勋章中心挑选与佩戴', style: TextStyle(fontSize: 9.5, color: colorScheme.primary)),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (ctx, constraints) {
                    final count = constraints.maxWidth > 300 ? 4 : 3;
                    return GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: count,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: _medals.take(count * 2).length,
                      itemBuilder: (context, idx) {
                        final m = _medals[idx];
                        return Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withAlpha(90),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.amber.withAlpha(45),
                              width: 0.8,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (m.img.isNotEmpty)
                                Expanded(
                                  child: CachedNetworkImage(
                                    imageUrl: m.img,
                                    fit: BoxFit.contain,
                                    errorWidget: (_, __, ___) => const Icon(Icons.military_tech, size: 22, color: Colors.amber),
                                  ),
                                )
                              else
                                const Icon(Icons.military_tech, size: 22, color: Colors.amber),
                              const SizedBox(height: 2),
                              Text(
                                m.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
