import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/dio_client.dart';
import '../../core/preload_service.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/site_stats.dart';
import '../../models/thread_summary.dart';
import 'credit_log_dashboard_card.dart';
import 'darkroom_dashboard_card.dart';
import 'forum_feed_dashboard_card.dart';
import 'forum_nav_dashboard_card.dart';
import 'horn_dashboard_card.dart';
import 'hot_threads_dashboard_card.dart';
import 'magic_bag_dashboard_card.dart';
import 'medal_dashboard_card.dart';
import 'messages_dashboard_card.dart';
import 'page_portal_dashboard_card.dart';
import 'papa_ai_dashboard_card.dart';
import 'quick_post_dashboard_card.dart';
import 'ranklist_dashboard_card.dart';
import 'server_status_dashboard_card.dart';
import 'sign_calendar_dashboard_card.dart';
import 'sign_fortune_dashboard_card.dart';
import 'task_dashboard_card.dart';
import 'tuhao_stats_dashboard_card.dart';
import 'user_profile_dashboard_card.dart';
import 'dashboard_card_frame.dart';

/// 全站卡片工厂（根据 cardType 统一构建对应卡片，支持 GPU 光栅化隔离与参数透传）
class DashboardCardFactory {
  static Widget buildCard({
    required DashboardGridItem item,
    required bool isPreview,
    List<ThreadSummary>? threads,
    String? threadsCacheKey,
    SiteStats? stats,
    bool suppressDefaultStats = false,
  }) {
    return ValueListenableBuilder<int>(
        valueListenable: DioClient.sessionChanges,
        builder: (_, version, __) {
          Widget card() => _buildCard(
              item: item,
              isPreview: isPreview,
              hasScopedThreads: threadsCacheKey != null,
              threads: isPreview && threadsCacheKey != null
                  ? PreloadService.instance.get<List<ThreadSummary>>(
                          threadsCacheKey,
                          ignoreExpired: true) ??
                      threads
                  : threads,
              stats: isPreview
                  ? PreloadService.instance
                          .get<SiteStats>('site_stats', ignoreExpired: true) ??
                      stats
                  : stats,
              suppressDefaultStats: suppressDefaultStats);
          return KeyedSubtree(
              key: ValueKey((
                version,
                item.id,
                item.cardType,
                isPreview,
                item.customParams['targetFid'],
                item.customParams['item'],
                item.customParams['starSource']
              )),
              child: isPreview
                  ? _PreviewCardSnapshot(
                      item: item,
                      threadsCacheKey: threadsCacheKey,
                      buildCard: card)
                  : card());
        });
  }

  static Widget _buildCard(
      {required DashboardGridItem item,
      required bool isPreview,
      bool hasScopedThreads = false,
      List<ThreadSummary>? threads,
      SiteStats? stats,
      bool suppressDefaultStats = false}) {
    switch (item.cardType) {
      case 'quick_post':
        return QuickPostDashboardCard(
            item: item, isPreview: isPreview, isReplyMode: false);
      case 'quick_reply':
        return QuickPostDashboardCard(
            item: item, isPreview: isPreview, isReplyMode: true);
      case 'medal_wall':
        return MedalDashboardCard(item: item, isPreview: isPreview);
      case 'credit_log':
        return CreditLogDashboardCard(item: item, isPreview: isPreview);
      case 'tuhao_stats':
        return TuhaoStatsDashboardCard(
            item: item,
            isPreview: isPreview,
            realStats: stats,
            suppressDefaultStats: suppressDefaultStats);
      case 'horn_banner':
        return HornDashboardCard(item: item, isPreview: isPreview);
      case 'sign_fortune':
        return SignFortuneDashboardCard(item: item, isPreview: isPreview);
      case 'sign_calendar':
        return SignInCalendarDashboardCard(item: item, isPreview: isPreview);
      case 'task_box':
        return TaskDashboardCard(item: item, isPreview: isPreview);
      case 'magic_bag':
        return MagicBagDashboardCard(item: item, isPreview: isPreview);
      case 'papa_ai_quick':
        return PapaAiDashboardCard(item: item, isPreview: isPreview);
      case 'forum_feed':
        return ForumFeedDashboardCard(item: item, isPreview: isPreview);
      case 'forum_nav':
        return ForumNavDashboardCard(item: item, isPreview: isPreview);
      case 'hot_threads':
        return HotThreadsDashboardCard(
            item: item,
            isPreview: isPreview,
            threads: threads ??
                (isPreview && !hasScopedThreads
                    ? PreloadService.instance.get<List<ThreadSummary>>(
                        'home_threads',
                        ignoreExpired: true)
                    : null));
      case 'user_profile':
        return UserProfileDashboardCard(item: item, isPreview: isPreview);
      case 'messages_brief':
        return MessagesDashboardCard(item: item, isPreview: isPreview);
      case 'darkroom_log':
        return DarkroomDashboardCard(item: item, isPreview: isPreview);
      case 'ranklist_card':
        return RanklistDashboardCard(item: item, isPreview: isPreview);
      case 'page_portal':
        return PagePortalDashboardCard(item: item, isPreview: isPreview);
      case 'server_status':
        return ServerStatusDashboardCard(item: item, isPreview: isPreview);
      case 'toc_outline':
      case 'floor_compass':
      case 'reader_tuning':
      case 'rating_hub':
      case 'media_gallery':
      case 'thread_search':
      case 'author_card':
      case 'forum_list':
        return _threadContextCard(item);
      default:
        return UserProfileDashboardCard(item: item, isPreview: isPreview);
    }
  }

  static Widget _threadContextCard(DashboardGridItem item) {
    final definition = CardRegistry.get(item.cardType);
    return Builder(builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return DashboardCardFrame(
          item: item,
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
              builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(definition.icon,
                              color: scheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(definition.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)))
                        ]),
                        if (constraints.maxHeight > 42) ...[
                          const SizedBox(height: 8),
                          Expanded(
                              child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Text('打开帖子后查看对应内容与工具',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant)))),
                        ],
                      ])));
    });
  }
}

/// A preview reads the same already loaded collection as the real card. Cache
/// changes rebuild only that preview, with no account writes or network refresh.
class _PreviewCardSnapshot extends StatefulWidget {
  final DashboardGridItem item;
  final Widget Function() buildCard;
  final String? threadsCacheKey;
  const _PreviewCardSnapshot(
      {required this.item, required this.buildCard, this.threadsCacheKey});
  @override
  State<_PreviewCardSnapshot> createState() => _PreviewCardSnapshotState();
}

class _PreviewCardSnapshotState extends State<_PreviewCardSnapshot> {
  StreamSubscription<PreloadCacheChange>? _subscription;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _subscription = PreloadService.instance.changes.listen((change) {
      if (mounted && (change.clearsAll || change.keys.any(_usesKey))) {
        setState(() => _revision++);
      }
    });
  }

  bool _usesKey(String key) => switch (widget.item.cardType) {
        'tuhao_stats' => key == 'site_stats' ||
            key.contains('sign_header_') ||
            key == 'horn_messages',
        'horn_banner' => key == 'horn_messages',
        'server_status' => key == 'server_status',
        'forum_nav' || 'quick_post' || 'quick_reply' => key == 'forum_groups',
        'user_profile' => key.startsWith('user_space_'),
        'sign_calendar' || 'sign_fortune' => key.contains('sign_header_'),
        'magic_bag' => key == 'magic_collection_mybox_1',
        'credit_log' =>
          key == 'credit_logs__1' || key.startsWith('user_space_'),
        'darkroom_log' => key == 'darkroom_null_1',
        'medal_wall' => key == 'my_medals',
        'forum_feed' => key == 'forum_groups' ||
            (widget.item.customParams['targetFid'] == null
                ? key.startsWith('thread_list_')
                : key.startsWith(
                    'thread_list_${widget.item.customParams['targetFid']}_')),
        'hot_threads' => key == (widget.threadsCacheKey ?? 'home_threads'),
        'task_box' => key.contains('task_list_'),
        _ => false,
      };

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
      key: ValueKey(_revision),
      child: widget.item.cardType == 'tuhao_stats'
          ? widget.buildCard()
          : IgnorePointer(child: widget.buildCard()));
}
