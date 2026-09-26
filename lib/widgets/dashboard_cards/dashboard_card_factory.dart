import 'package:flutter/material.dart';
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
    SiteStats? stats,
  }) {
    switch (item.cardType) {
      case 'quick_post':
        return QuickPostDashboardCard(item: item, isPreview: isPreview, isReplyMode: false);
      case 'quick_reply':
        return QuickPostDashboardCard(item: item, isPreview: isPreview, isReplyMode: true);
      case 'medal_wall':
        return MedalDashboardCard(item: item, isPreview: isPreview);
      case 'credit_log':
        return CreditLogDashboardCard(item: item, isPreview: isPreview);
      case 'tuhao_stats':
        return TuhaoStatsDashboardCard(item: item, isPreview: isPreview, realStats: stats);
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
        return HotThreadsDashboardCard(item: item, isPreview: isPreview, threads: threads);
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
        return _buildTocOutlineCard(item);
      case 'floor_compass':
        return _buildFloorCompassCard(item);
      case 'reader_tuning':
        return _buildReaderTuningCard(item);
      case 'rating_hub':
        return _buildRatingHubCard(item);
      case 'media_gallery':
        return _buildMediaGalleryCard(item);
      case 'thread_search':
        return _buildThreadSearchCard(item);
      case 'author_card':
        return _buildAuthorCard(item);
      case 'forum_list':
        return _buildForumListCard(item);
      default:
        return UserProfileDashboardCard(item: item, isPreview: isPreview);
    }
  }

  // ================= 帖子工作台高保真卡片 (1:1 对齐 ThreadLayoutWorkbench 真实表现) =================

  /// 1. 打赏评分筛选大厅 (1:1 对齐 Image 1 真实工作台)
  static Widget _buildRatingHubCard(DashboardGridItem item) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return DashboardCardFrame(
          item: item,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.card_giftcard_rounded, size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 6),
                  Text(
                    '评分与打赏大厅',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                  ),
                  const Spacer(),
                  Text(
                    '5 条记录',
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(60),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '支持多币种汇总、实时模糊搜索与大额正向加分筛选',
                  style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant.withAlpha(200)),
                ),
              ),
              const SizedBox(height: 7),
              FilledButton.tonalIcon(
                onPressed: () {},
                icon: const Icon(Icons.filter_list_rounded, size: 14),
                label: const Text('打开全功能筛选面板', style: TextStyle(fontSize: 11.5)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 30),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (item.rowSpan >= 2) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildCurrencyBadge('金粒', '+120', Colors.amber.shade700),
                    _buildCurrencyBadge('铁粒', '+18', Colors.teal.shade700),
                    _buildCurrencyBadge('人气', '+15', Colors.purple.shade700),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 2. 帖内内容快速检索速查 (1:1 对齐 Image 1 真实工作台)
  static Widget _buildThreadSearchCard(DashboardGridItem item) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return DashboardCardFrame(
          item: item,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.search_rounded, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    '帖内搜索',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '实时检索',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(70),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 15, color: colorScheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '搜索本帖楼层、内容、作者...',
                        style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.rowSpan >= 2) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildSmallChip('只看楼主', color: colorScheme.primary),
                    _buildSmallChip('带图楼层'),
                    _buildSmallChip('热门回复'),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 3. 楼层精准罗盘 (1:1 对齐 ThreadLayoutWorkbench)
  static Widget _buildFloorCompassCard(DashboardGridItem item) {
    return _InteractiveFloorCompassCard(item: item);
  }

  /// 4. 阅读排版调谐器 (1:1 对齐 ThreadLayoutWorkbench)
  static Widget _buildReaderTuningCard(DashboardGridItem item) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return DashboardCardFrame(
          item: item,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.tune_rounded, size: 16, color: Colors.indigo),
                  const SizedBox(width: 6),
                  Text('阅读排版调谐器', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('字号: 15 pt', style: TextStyle(fontSize: 11.5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: 0.5,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('行距: 1.6x', style: TextStyle(fontSize: 11.5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: 0.6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 5. 文章大纲目录树 (TOC)
  static Widget _buildTocOutlineCard(DashboardGridItem item) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        const nodes = [
          '主帖 · 楼主正文',
          '★ 最佳答案',
          '2# 沙发 · 机制探讨',
          '3# 板凳 · 常见问题解答',
        ];
        return DashboardCardFrame(
          item: item,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.format_list_bulleted_rounded, size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  Text('文章大纲目录', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface)),
                  const Spacer(),
                  Text('${nodes.length} 节点', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                ],
              ),
              const SizedBox(height: 6),
              ...nodes.take(item.rowSpan >= 3 ? 4 : 2).map((t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(
                  children: [
                    Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.primary)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t, style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant), maxLines: 1)),
                  ],
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  /// 6. 楼主名片与作者档案
  static Widget _buildAuthorCard(DashboardGridItem item) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return DashboardCardFrame(
          item: item,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 17,
                    backgroundColor: Color(0xFF3BA55D),
                    child: Text('Y', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('YesNewBee', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: Colors.amber.withAlpha(35), borderRadius: BorderRadius.circular(4)),
                              child: Text('楼主', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('UID: 1024 · 坛龄 3 年', style: TextStyle(fontSize: 10, color: colorScheme.outline)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.person_outline, size: 13),
                      label: const Text('个人空间', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('复制 UID', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 7. 全帖媒体画廊
  static Widget _buildMediaGalleryCard(DashboardGridItem item) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return DashboardCardFrame(
          item: item,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.photo_library_rounded, size: 16, color: Colors.purple),
                  const SizedBox(width: 6),
                  Text('全帖媒体画廊', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface)),
                  const Spacer(),
                  Text('8 张图', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(3, (i) => Expanded(
                  child: Container(
                    height: 52,
                    margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(120),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colorScheme.outlineVariant.withAlpha(40)),
                    ),
                    child: Icon(Icons.image_outlined, size: 20, color: colorScheme.primary.withAlpha(150)),
                  ),
                )),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 8. 版块主题速览
  static Widget _buildForumListCard(DashboardGridItem item) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return DashboardCardFrame(
          item: item,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.list_alt_rounded, size: 16, color: Colors.teal.shade700),
                  const SizedBox(width: 6),
                  Text('闲聊讨论 · 速览', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface)),
                ],
              ),
              const SizedBox(height: 6),
              Text('• 包板块·老友回归，新人启程 (YesNewBee)', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant), maxLines: 1),
              const SizedBox(height: 3),
              Text('• 主世界月刊——2026.8月刊 (采矿与合成)', style: TextStyle(fontSize: 11, color: colorScheme.outline), maxLines: 1),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildCurrencyBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(width: 3),
          Text(value, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  static Widget _buildSmallChip(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withAlpha(25),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: color != null ? FontWeight.bold : FontWeight.normal)),
    );
  }
}

class _InteractiveFloorCompassCard extends StatefulWidget {
  final DashboardGridItem item;
  const _InteractiveFloorCompassCard({required this.item});

  @override
  State<_InteractiveFloorCompassCard> createState() => _InteractiveFloorCompassCardState();
}

class _InteractiveFloorCompassCardState extends State<_InteractiveFloorCompassCard> {
  late final TextEditingController _ctrl;
  String _selectedFloor = '1#';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onJump(String val) {
    final text = val.trim();
    if (text.isEmpty) return;
    final num = int.tryParse(text.replaceAll(RegExp(r'[^\d]'), ''));
    final label = num != null ? '$num#' : text;
    setState(() => _selectedFloor = label);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已锚定至 $label 楼层'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DashboardCardFrame(
      item: widget.item,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.explore_rounded, size: 16, color: Colors.teal),
              const SizedBox(width: 6),
              Text('楼层罗盘', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface)),
              const Spacer(),
              Text('锚定: $_selectedFloor', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              InkWell(
                onTap: () => _onJump('1'),
                borderRadius: BorderRadius.circular(4),
                child: DashboardCardFactory._buildSmallChip('1# 楼主', color: Colors.amber.shade800),
              ),
              InkWell(
                onTap: () => _onJump('2'),
                borderRadius: BorderRadius.circular(4),
                child: DashboardCardFactory._buildSmallChip('2# 沙发'),
              ),
              InkWell(
                onTap: () => _onJump('3'),
                borderRadius: BorderRadius.circular(4),
                child: DashboardCardFactory._buildSmallChip('3# 板凳'),
              ),
              InkWell(
                onTap: () => _onJump('最新'),
                borderRadius: BorderRadius.circular(4),
                child: DashboardCardFactory._buildSmallChip('最新回复'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 11.5),
                    decoration: InputDecoration(
                      hintText: '直达楼层号 (如 5)',
                      hintStyle: TextStyle(fontSize: 11, color: colorScheme.outline),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onSubmitted: _onJump,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.tonal(
                onPressed: () => _onJump(_ctrl.text),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('跳转', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
