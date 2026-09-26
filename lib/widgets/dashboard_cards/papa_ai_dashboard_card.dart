import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/papa_ai_chat_page.dart';
import 'dashboard_card_frame.dart';

/// 10. 帕帕 AI 助手卡片（支持 GPU 隔离与 LOD 尺寸自适应）
class PapaAiDashboardCard extends StatelessWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const PapaAiDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = item.rowSpan <= 1;
    final isNarrow = item.colSpan <= 2;
    final customTitle = item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '帕帕 AI 智能助手';

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: item,
        padding: const EdgeInsets.all(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PapaAiChatPage())),
        child: (isCompact || isNarrow)
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
              colors: [Colors.teal.shade400, const Color(0xFF10B981)],
            ),
          ),
          child: const Icon(Icons.smart_toy_rounded, size: 18, color: Colors.white),
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
                'AI 算力充足 · 点击向我提问',
                maxLines: 1,
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.teal.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('对话 >', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.teal)),
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
            Icon(Icons.smart_toy_rounded, size: 17, color: Colors.teal.shade600),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '站内智能助手',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(90),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '🤖 “你好！我是帕帕，可以帮你检索站内帖子与解答游戏问题”',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: [
                          _buildChip('找附加包'),
                          _buildChip('红石指令'),
                          _buildChip('游戏求助'),
                        ],
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PapaAiChatPage())),
                  child: const Text('开始对话', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.teal.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.teal)),
    );
  }
}
