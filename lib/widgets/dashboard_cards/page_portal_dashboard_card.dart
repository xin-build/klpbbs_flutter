import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/credit_page.dart';
import '../../pages/darkroom_page.dart';
import '../../pages/facemall_page.dart';
import '../../pages/magic_page.dart';
import '../../pages/medal_page.dart';
import '../../pages/notice_page.dart';
import '../../pages/papa_ai_chat_page.dart';
import '../../pages/pm_inbox_page.dart';
import '../../pages/ranklist_page.dart';
import '../../pages/sign_rank_page.dart';
import '../../pages/task_page.dart';
import 'dashboard_card_frame.dart';

/// 18. 自选页面传送门卡片（可自定义任意跳转目标，支持 GPU 隔离与 LOD 尺寸自适应）
class PagePortalDashboardCard extends StatelessWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const PagePortalDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  void _navigate(BuildContext context, String targetPage) {
    Widget? page;
    switch (targetPage) {
      case 'medal':
        page = const MedalPage();
        break;
      case 'magic':
        page = const MagicPage();
        break;
      case 'credit':
        page = const CreditPage();
        break;
      case 'darkroom':
        page = const DarkroomPage();
        break;
      case 'ranklist':
        page = const RanklistPage();
        break;
      case 'facemall':
        page = const FacemallPage();
        break;
      case 'papa_ai':
        page = const PapaAiChatPage();
        break;
      case 'task':
        page = const TaskPage();
        break;
      case 'sign_rank':
        page = const SignRankPage();
        break;
      case 'pm':
        page = const PmInboxPage();
        break;
      case 'notice':
        page = const NoticePage();
        break;
      default:
        page = const MedalPage();
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final targetPage = item.customParams['targetPage'] as String? ?? 'medal';
    final pageName = item.customParams['pageName'] as String? ?? '勋章中心';
    final customTitle = item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : pageName;

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: item,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () => _navigate(context, targetPage),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(120),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.open_in_new_rounded, size: 18, color: colorScheme.primary),
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
                    '传送门 · 直达 $pageName',
                    maxLines: 1,
                    style: TextStyle(fontSize: 10, color: colorScheme.outline),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
