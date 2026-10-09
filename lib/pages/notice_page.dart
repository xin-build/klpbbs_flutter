import 'dart:async';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../models/notice_item.dart';
import '../services/push_notification_service.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/pagination_control.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/thread_card.dart';
import '../models/server_outage_info.dart';
import '../widgets/server_outage_view.dart';
import 'pm_inbox_page.dart';
import 'thread_detail_page.dart';
import 'user_space_page.dart';

/// 通知提醒页（100% 精准还原 Discuz 网页版：我的帖子/坛友互动/系统提醒/应用提醒/我的粉丝/公共消息）
class NoticePage extends StatefulWidget {
  const NoticePage({super.key});

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    ('mypost', '我的帖子'),
    ('interactive', '坛友互动'),
    ('system', '系统提醒'),
    ('app', '应用提醒'),
  ];

  static const _mypostSubTabs = [
    ('', '全部'),
    ('post', '帖子'),
    ('at', '提到我的'),
    ('reward', '悬赏'),
  ];

  static const _interactiveSubTabs = [
    ('', '全部'),
    ('poke', '打招呼'),
    ('friend', '好友'),
  ];

  late final TabController _tabController;
  late Future<List<NoticeItem>> _future;
  String _view = 'mypost';
  String _subType = '';
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(_onTabChanged);
    _fetch();
  }

  void _fetch() {
    _future = KlpbbsApi.getNotices(
      _view,
      type: _subType.isNotEmpty ? _subType : null,
      page: _page,
    ).then((list) {
      // Reading one category does not prove that all categories are read.
      unawaited(PushNotificationService.instance.checkNewMessages());
      return list;
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final view = _tabs[_tabController.index].$1;
    if (view != _view) {
      setState(() {
        _view = view;
        _page = 1;
        _subType = '';
        _fetch();
      });
    }
  }

  void _onSubTabChanged(String type) {
    if (_subType == type) return;
    setState(() {
      _subType = type;
      _page = 1;
      _fetch();
    });
  }

  Future<void> _markAllRead() async {
    final ok = await KlpbbsApi.ignoreNotice(view: _view);
    if (ok) unawaited(PushNotificationService.instance.checkNewMessages());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已标记全部提醒为已读' : '操作失败')),
    );
    setState(() {
      _page = 1;
      _fetch();
    });
  }

  void _goPage(int page) {
    if (page < 1) return;
    setState(() {
      _page = page;
      _fetch();
    });
  }

  List<(String, String)> get _currentSubTabs {
    if (_view == 'mypost') return _mypostSubTabs;
    if (_view == 'interactive') return _interactiveSubTabs;
    return const [];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subTabs = _currentSubTabs;

    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('消息提醒'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: '一键已读',
            onPressed: _markAllRead,
          ),
          IconButton(
            icon: const Icon(Icons.mark_email_unread_outlined),
            tooltip: '我的私信',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PmInboxPage()),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: TabBar(
                controller: _tabController,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                indicatorSize: TabBarIndicatorSize.label,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                tabs: [for (final (_, label) in _tabs) Tab(text: label)],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 1. 各分类专属二级子分类切换条（帖子/提到我的、打招呼/好友等）
          if (subTabs.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(50),
                  ),
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (typeKey, label) in subTabs) ...[
                          ChoiceChip(
                            label: Text(label),
                            selected: _subType == typeKey,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => _onSubTabChanged(typeKey),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 2. 通知列表主体 (支持平滑切换动画与大屏响应式适配)
          Expanded(
            child: FutureBuilder<List<NoticeItem>>(
              future: _future,
              builder: (context, snap) {
                final Widget content;
                if (snap.connectionState != ConnectionState.done) {
                  content = const Center(
                    key: ValueKey('loading'),
                    child: SkeletonList(itemCount: 6),
                  );
                } else if (snap.hasError) {
                  final outage = ServerOutageInfo.tryParse(snap.error);
                  if (outage != null) {
                    content = ServerOutageView(
                      key: const ValueKey('outage'),
                      outage: outage,
                      onRetry: () => _goPage(_page),
                    );
                  } else {
                    content = Center(
                      key: const ValueKey('error'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('加载失败：${snap.error}'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => _goPage(_page),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    );
                  }
                } else {
                  final list = snap.data ?? [];
                  if (list.isEmpty) {
                    content = RefreshIndicator(
                      key: ValueKey('empty_$_view-$_subType-$_page'),
                      onRefresh: () async => _goPage(1),
                      child: ListView(
                        children: [
                          const SizedBox(height: 80),
                          EmptyView(
                            icon: Icons.notifications_none,
                            title: _page > 1 ? '第 $_page 页暂无更多通知' : '暂无通知消息',
                            subtitle: _page > 1 ? '点击下方返回上一页' : '去论坛逛逛或者发帖互动吧',
                          ),
                          if (_page > 1) ...[
                            const SizedBox(height: 16),
                            Center(
                              child: FilledButton.tonal(
                                onPressed: () => _goPage(_page - 1),
                                child: const Text('返回上一页'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  } else {
                    content = RefreshIndicator(
                      key: ValueKey('list_$_view-$_subType-$_page'),
                      onRefresh: () async => _goPage(_page),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 960),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            itemCount: list.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              if (i == list.length) {
                                return PaginationControl(
                                  page: _page,
                                  hasMore: list.length >= 8,
                                  onPageChanged: _goPage,
                                );
                              }
                              final item = list[i];
                              return _NoticeWebCard(
                                notice: item,
                                onTap: () {
                                  if (item.tid > 0) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ThreadDetailPage(tid: item.tid),
                                      ),
                                    );
                                  } else if (item.uid != null &&
                                      item.uid! > 0) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            UserSpacePage(uid: item.uid!),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  }
                }

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: content,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 100% 对齐 KLPBBS 网页版的通知卡片
class _NoticeWebCard extends StatelessWidget {
  final NoticeItem notice;
  final VoidCallback? onTap;

  const _NoticeWebCard({required this.notice, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasUid = notice.uid != null && notice.uid! > 0;

    var displayAction = notice.actionText;
    if (notice.author.isNotEmpty && displayAction.startsWith(notice.author)) {
      displayAction = displayAction.substring(notice.author.length).trim();
      displayAction =
          displayAction.replaceFirst(RegExp(r'^[:：\s]+'), '').trim();
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: colorScheme.outlineVariant.withAlpha(40),
          width: 0.8,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 发送人头像
              if (hasUid)
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UserSpacePage(uid: notice.uid!),
                    ),
                  ),
                  child: UserAvatarWidget(
                    reserveFrameSpace: true,
                    uid: notice.uid,
                    author: notice.author,
                    size: 42,
                    faceUrl: notice.faceUrl,
                  ),
                )
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.admin_panel_settings_outlined,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
              const SizedBox(width: 14),

              // 2. 右侧核心内容区
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 发送时间与分类徽标
                    Row(
                      children: [
                        if (notice.timeText.isNotEmpty)
                          Text(
                            notice.timeText,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colorScheme.outline,
                            ),
                          ),
                        const Spacer(),
                        _buildCategoryTag(notice, colorScheme),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // 动作描述（如「我的世界 在主题 [苦坛停运记]... 中提到了您」或「kwlis 向您打了个招呼」）
                    RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          height: 1.4,
                          color: colorScheme.onSurface,
                        ),
                        children: [
                          TextSpan(
                            text: notice.author,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: hasUid ? colorScheme.primary : null,
                            ),
                          ),
                          TextSpan(text: ' $displayAction'),
                        ],
                      ),
                    ),

                    // 引用引文气泡（“ ... ”）
                    if (notice.quoteText != null &&
                        notice.quoteText!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color:
                              colorScheme.surfaceContainerHighest.withAlpha(50),
                          borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(8)),
                          border: Border(
                            left: BorderSide(
                              color: colorScheme.primary.withAlpha(120),
                              width: 2.5,
                            ),
                          ),
                        ),
                        child: Text(
                          '“ ${notice.quoteText!} ”',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            color: colorScheme.outline,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],

                    // 底部交互按钮组
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (notice.isPoke) ...[
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            icon:
                                const Icon(Icons.waving_hand_rounded, size: 14),
                            label: const Text('回打招呼',
                                style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              if (hasUid) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        UserSpacePage(uid: notice.uid!),
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                        ] else if (notice.isFriendRequest) ...[
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            icon:
                                const Icon(Icons.person_add_rounded, size: 14),
                            label: const Text('查看用户',
                                style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              if (hasUid) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        UserSpacePage(uid: notice.uid!),
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (notice.tid > 0) ...[
                          Text(
                            '现在去查看 ›',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ] else if (hasUid &&
                            !notice.isPoke &&
                            !notice.isFriendRequest) ...[
                          Text(
                            '访问 TA 的空间 ›',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Icon(
                          Icons.shield_outlined,
                          size: 15,
                          color: colorScheme.outlineVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTag(NoticeItem notice, ColorScheme colorScheme) {
    if (notice.isPoke) {
      return _buildMiniPill('互动', const Color(0xFFFF9800));
    }
    if (notice.actionText.contains('提到') || notice.actionText.contains('@')) {
      return _buildMiniPill('提及', const Color(0xFF1E88E5));
    }
    if (notice.actionText.contains('回复') || notice.actionText.contains('点评')) {
      return _buildMiniPill('回复', const Color(0xFF00897B));
    }
    if (notice.actionText.contains('积分') ||
        notice.actionText.contains('悬赏') ||
        notice.actionText.contains('铁粒')) {
      return _buildMiniPill('资产', const Color(0xFFF07B00));
    }
    if (notice.uid == null || notice.uid == 0) {
      return _buildMiniPill('系统', const Color(0xFF7E57C2));
    }
    return _buildMiniPill('提醒', colorScheme.primary);
  }

  Widget _buildMiniPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80), width: 0.6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
