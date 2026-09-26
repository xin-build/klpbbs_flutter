import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/notice_page.dart';
import '../../pages/pm_inbox_page.dart';
import '../../services/push_notification_service.dart';
import 'dashboard_card_frame.dart';

/// 15. 私信与系统通知简报卡片（支持 GPU 隔离与 LOD 尺寸自适应）
class MessagesDashboardCard extends StatelessWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const MessagesDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = item.rowSpan <= 1;
    final isNarrow = item.colSpan <= 2;
    final customTitle = item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '消息与通知';

    final unreadPm = isPreview ? 2 : PushNotificationService.instance.unreadPm;
    final unreadNotice = isPreview ? 5 : PushNotificationService.instance.unreadNotices;

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: item,
        padding: const EdgeInsets.all(12),
        child: (isCompact || isNarrow)
            ? _buildCompact(context, unreadPm, unreadNotice, title)
            : _buildExpanded(context, unreadPm, unreadNotice, title),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, int unreadPm, int unreadNotice, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalUnread = unreadPm + unreadNotice;

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoticePage())),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.withAlpha(30),
            ),
            child: const Icon(Icons.notifications_rounded, size: 18, color: Colors.blue),
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
                  totalUnread > 0 ? '$totalUnread 条未读动态' : '暂无新消息',
                  maxLines: 1,
                  style: TextStyle(fontSize: 10, color: colorScheme.outline),
                ),
              ],
            ),
          ),
          if (totalUnread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$totalUnread',
                style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, int unreadPm, int unreadNotice, String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.mail_rounded, size: 17, color: colorScheme.primary),
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
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PmInboxPage())),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withAlpha(60), width: 0.8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, color: Colors.blue, size: 20),
                        const SizedBox(height: 3),
                        const Text('私信', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('$unreadPm 未读', style: TextStyle(fontSize: 10, color: unreadPm > 0 ? Colors.red : Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoticePage())),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withAlpha(60), width: 0.8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.notifications_active_outlined, color: Colors.amber, size: 20),
                        const SizedBox(height: 3),
                        const Text('提醒', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('$unreadNotice 新提醒', style: TextStyle(fontSize: 10, color: unreadNotice > 0 ? Colors.red : Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
