import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/thread_list_page.dart';
import '../interactive_animations.dart';
import 'dashboard_card_frame.dart';

/// 12. 常用版块导航网格卡片（支持 GPU 隔离与 LOD 尺寸自适应）
class ForumNavDashboardCard extends StatelessWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const ForumNavDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  static const List<({int fid, String name, IconData icon, Color color})> _forums = [
    (fid: 41, name: '闲聊讨论', icon: Icons.chat_bubble_outline_rounded, color: Colors.blue),
    (fid: 52, name: 'BE附加包', icon: Icons.extension_rounded, color: Colors.green),
    (fid: 140, name: 'JE模组', icon: Icons.view_in_ar_rounded, color: Colors.teal),
    (fid: 53, name: 'BE材质光影', icon: Icons.wb_sunny_outlined, color: Colors.amber),
    (fid: 51, name: 'BE地图', icon: Icons.map_outlined, color: Colors.deepOrange),
    (fid: 56, name: '服务器大厅', icon: Icons.dns_rounded, color: Colors.purple),
  ];

  @override
  Widget build(BuildContext context) {
    final customTitle = item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '快捷版块';

    final rawDataStyle = item.customParams['dataStyle'] as String? ?? 'auto';
    final String dataStyle;
    if (rawDataStyle == 'auto') {
      final isCompact = item.rowSpan <= 1;
      final isNarrow = item.colSpan <= 2;
      dataStyle = (isCompact || isNarrow) ? 'chips' : 'grid';
    } else {
      dataStyle = rawDataStyle;
    }

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: item,
        padding: const EdgeInsets.all(12),
        child: dataStyle == 'chips'
            ? _buildCompact(context, title)
            : _buildExpanded(context, title),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: _forums.take(4).map((f) {
        return PressScaleEffect(
          scaleDown: 0.92,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ThreadListPage(fid: f.fid, title: f.name)),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(f.icon, size: 20, color: f.color),
                  const SizedBox(height: 2),
                  Text(f.name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExpanded(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.grid_view_rounded, size: 17, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final crossCount = constraints.maxWidth > 280 ? 3 : 2;
              final maxItems = (crossCount == 2 && item.rowSpan <= 2) ? 4 : _forums.length;
              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 2.2,
                ),
                itemCount: math.min(_forums.length, maxItems),
                itemBuilder: (context, idx) {
                  final f = _forums[idx];
                  return PressScaleEffect(
                    scaleDown: 0.94,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ThreadListPage(fid: f.fid, title: f.name)),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: f.color.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: f.color.withAlpha(50), width: 0.8),
                        ),
                        child: Row(
                          children: [
                            Icon(f.icon, size: 18, color: f.color),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
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
