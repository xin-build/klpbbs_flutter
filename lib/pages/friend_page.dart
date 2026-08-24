import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../models/friend_item.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';
import 'pm_detail_page.dart';
import 'user_space_page.dart';

/// 好友与关注粉丝中心页面（1:1 对齐 Discuz 移动端 7 大 Tab 与快捷操作体系）
class FriendPage extends StatefulWidget {
  final int uid;
  final String? username;
  final int initialTabIndex;

  const FriendPage({
    super.key,
    required this.uid,
    this.username,
    this.initialTabIndex = 0,
  });

  @override
  State<FriendPage> createState() => _FriendPageState();
}

class _FriendPageState extends State<FriendPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  String _filterKeyword = '';
  int? _myUid;

  static const List<({String key, String label, IconData icon})> _tabs = [
    (key: 'me', label: '我的好友', icon: Icons.people_outline),
    (key: 'follow', label: '我的关注', icon: Icons.favorite_outline),
    (key: 'fans', label: '我的粉丝', icon: Icons.star_outline),
    (key: 'visitor', label: '最近来访', icon: Icons.visibility_outlined),
    (key: 'trace', label: '我看过谁', icon: Icons.history_outlined),
    (key: 'request', label: '好友请求', icon: Icons.person_add_outlined),
    (key: 'blacklist', label: '黑名单', icon: Icons.block_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
    );
    _searchCtrl.addListener(() {
      setState(() {
        _filterKeyword = _searchCtrl.text.trim().toLowerCase();
      });
    });
    _checkMyUid();
  }

  Future<void> _checkMyUid() async {
    if (DioClient.isLoggedIn) {
      final uid = await KlpbbsApi.getMyUid();
      if (mounted) {
        setState(() => _myUid = uid);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = DioClient.isLoggedIn && (_myUid == widget.uid);
    final title = isMe
        ? '我的好友'
        : (widget.username != null && widget.username!.isNotEmpty
            ? '${widget.username} 的好友'
            : '好友与关注');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        actions: const [
          GlobalNavButton(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: theme.colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
              tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: [
              // 顶部全局搜索过滤条 (Material 3 风格)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: '搜索好友昵称、用户组或 UID...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _filterKeyword.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant.withAlpha(80),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant.withAlpha(80),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
                  ),
                ),
              ),

              // 7 个 Tab 内容视图
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _tabs.map((tab) {
                    return _FriendTabListView(
                      uid: widget.uid,
                      view: tab.key,
                      tabTitle: tab.label,
                      filterKeyword: _filterKeyword,
                      isMe: isMe,
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个 Tab 下的好友列表子视图
class _FriendTabListView extends StatefulWidget {
  final int uid;
  final String view;
  final String tabTitle;
  final String filterKeyword;
  final bool isMe;

  const _FriendTabListView({
    required this.uid,
    required this.view,
    required this.tabTitle,
    required this.filterKeyword,
    required this.isMe,
  });

  @override
  State<_FriendTabListView> createState() => _FriendTabListViewState();
}

class _FriendTabListViewState extends State<_FriendTabListView>
    with AutomaticKeepAliveClientMixin {
  late Future<List<FriendItem>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = KlpbbsApi.getFriends(widget.uid, view: widget.view);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return FutureBuilder<List<FriendItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyView(
            icon: Icons.error_outline,
            title: '加载${widget.tabTitle}失败',
            subtitle: '${snap.error}',
            action: FilledButton.tonal(
              onPressed: _load,
              child: const Text('重试'),
            ),
          );
        }

        final allList = snap.data ?? [];
        if (allList.isEmpty) {
          return EmptyView(
            icon: _getTabEmptyIcon(widget.view),
            title: '暂无数据',
            subtitle: widget.isMe ? '您目前没有${widget.tabTitle}数据' : '暂无公开${widget.tabTitle}',
            action: FilledButton.tonal(
              onPressed: _load,
              child: const Text('刷新'),
            ),
          );
        }

        final filteredList = widget.filterKeyword.isEmpty
            ? allList
            : allList.where((f) {
                return f.username.toLowerCase().contains(widget.filterKeyword) ||
                    f.usergroup.toLowerCase().contains(widget.filterKeyword) ||
                    f.uid.toString().contains(widget.filterKeyword) ||
                    f.note.toLowerCase().contains(widget.filterKeyword);
              }).toList();

        final onlineCount = allList.where((f) => f.isOnline).length;

        return RefreshIndicator(
          onRefresh: () async => _load(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 统计信息条
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  widget.view == 'me'
                      ? '共 ${allList.length} 位好友 · $onlineCount 人在线'
                      : '共 ${allList.length} 条记录',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              Expanded(
                child: filteredList.isEmpty
                    ? Center(
                        child: Text(
                          '未找到匹配「${widget.filterKeyword}」的结果',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                        itemCount: filteredList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, idx) {
                          final f = filteredList[idx];
                          return _FriendCard(
                            item: f,
                            view: widget.view,
                            isMe: widget.isMe,
                            onChanged: _load,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getTabEmptyIcon(String view) {
    switch (view) {
      case 'follow':
        return Icons.favorite_outline;
      case 'fans':
        return Icons.star_outline;
      case 'visitor':
        return Icons.visibility_outlined;
      case 'trace':
        return Icons.history_outlined;
      case 'request':
        return Icons.person_add_outlined;
      case 'blacklist':
        return Icons.block_outlined;
      default:
        return Icons.people_outline;
    }
  }
}

/// 单个好友卡片组件（1:1 高保真对齐 Discuz 移动端布局与交互）
class _FriendCard extends StatefulWidget {
  final FriendItem item;
  final String view;
  final bool isMe;
  final VoidCallback onChanged;

  const _FriendCard({
    required this.item,
    required this.view,
    required this.isMe,
    required this.onChanged,
  });

  @override
  State<_FriendCard> createState() => _FriendCardState();
}

class _FriendCardState extends State<_FriendCard> {
  bool _isFollowing = false;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.item.isFollowing;
  }

  @override
  void didUpdateWidget(covariant _FriendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.isFollowing != widget.item.isFollowing) {
      _isFollowing = widget.item.isFollowing;
    }
  }

  Future<void> _toggleFollow() async {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    setState(() => _isActionLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    final nextState = !_isFollowing;
    final ok = nextState
        ? await KlpbbsApi.followUser(widget.item.uid)
        : await KlpbbsApi.unfollowUser(widget.item.uid);

    if (mounted) {
      setState(() {
        _isActionLoading = false;
        if (ok) _isFollowing = nextState;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? (nextState ? '已关注' : '已取消关注') : '操作失败，请重试')),
      );
    }
  }

  Future<void> _pokeUser() async {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    final pokeCtrl = TextEditingController(text: '打个招呼');
    final confirm = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('向「${widget.item.username}」打招呼'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pokeCtrl,
              decoration: const InputDecoration(
                labelText: '招呼内容',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: ['打个招呼', '握个手', '踩一下', '摸摸头'].map((s) {
                return ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  onPressed: () => pokeCtrl.text = s,
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(pokeCtrl.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );

    if (confirm != null && confirm.isNotEmpty && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await KlpbbsApi.pokeUser(widget.item.uid, confirm);
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? '已成功打招呼' : '打招呼失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final f = widget.item;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => UserSpacePage(uid: f.uid),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 头像与在线状态
              UserAvatarWidget(
                avatarUrl: f.avatarUrl,
                uid: f.uid,
                size: 46,
                isOnline: f.isOnline,
                showOnlineBadge: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UserSpacePage(uid: f.uid),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),

              // 中间信息列 (用户名、用户组、积分、在线提示)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            f.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (f.isOnline) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '在线',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (f.usergroup.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: f.usergroup.contains('禁止')
                                  ? colorScheme.errorContainer
                                  : colorScheme.primaryContainer.withAlpha(120),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              f.usergroup,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: f.usergroup.contains('禁止')
                                    ? colorScheme.error
                                    : colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        if (f.credits.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.stars_rounded, size: 13, color: Colors.amber.shade700),
                              const SizedBox(width: 2),
                              Text(
                                f.credits.contains('积分') ? f.credits : '积分:${f.credits}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (f.recentActivity.isNotEmpty &&
                        !f.recentActivity.startsWith('UID') &&
                        !f.recentActivity.contains('积分')) ...[
                      const SizedBox(height: 3),
                      Text(
                        f.recentActivity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 右侧 App 风格操作栏 (根据当前 Tab 动态展示对应操作)
              if (widget.view == 'request') ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await KlpbbsApi.acceptFriendRequest(f.uid);
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(ok ? '已通过好友申请' : '操作失败，请重试')),
                          );
                          if (ok) widget.onChanged();
                        }
                      },
                      child: const Text('同意', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await KlpbbsApi.ignoreFriendRequest(f.uid);
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(ok ? '已忽略好友申请' : '操作失败，请重试')),
                          );
                          if (ok) widget.onChanged();
                        }
                      },
                      child: const Text('忽略', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ] else if (widget.view == 'blacklist') ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.lock_open_rounded, size: 16),
                  label: const Text('移出黑名单', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await KlpbbsApi.removeFromBlacklist(f.uid);
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(ok ? '已移出黑名单' : '操作失败，请重试')),
                      );
                      if (ok) widget.onChanged();
                    }
                  },
                ),
              ] else ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. 关注 / 取消关注
                    IconButton.filledTonal(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      tooltip: _isFollowing ? '取消关注' : '关注',
                      style: IconButton.styleFrom(
                        foregroundColor: _isFollowing ? Colors.redAccent : colorScheme.onSurfaceVariant,
                        backgroundColor: _isFollowing ? Colors.red.withAlpha(25) : null,
                      ),
                      icon: _isActionLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_isFollowing ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                      onPressed: _isActionLoading ? null : _toggleFollow,
                    ),

                    // 2. 打招呼
                    IconButton.filledTonal(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      tooltip: '打招呼',
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.teal,
                        backgroundColor: Colors.teal.withAlpha(20),
                      ),
                      icon: const Icon(Icons.waving_hand_rounded),
                      onPressed: _pokeUser,
                    ),

                    // 3. 发私信
                    IconButton.filledTonal(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      tooltip: '发私信',
                      style: IconButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        backgroundColor: colorScheme.primary.withAlpha(20),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PmDetailPage(
                              touid: f.uid,
                              toUsername: f.username,
                            ),
                          ),
                        );
                      },
                    ),

                    // 4. 更多菜单 (查看空间、修改备注、删除好友、黑名单)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, size: 18),
                      tooltip: '更多操作',
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'space',
                          child: Row(
                            children: [
                              Icon(Icons.person_outline_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('个人空间'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'blacklist',
                          child: Row(
                            children: [
                              Icon(Icons.block_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('加入黑名单'),
                            ],
                          ),
                        ),
                        if (widget.isMe && widget.view == 'me')
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.person_remove_outlined, color: Colors.redAccent, size: 18),
                                SizedBox(width: 8),
                                Text('删除好友', style: TextStyle(color: Colors.redAccent)),
                              ],
                            ),
                          ),
                      ],
                      onSelected: (action) async {
                        if (action == 'space') {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => UserSpacePage(uid: f.uid),
                            ),
                          );
                        } else if (action == 'blacklist') {
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await KlpbbsApi.addToBlacklist(f.uid);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(ok ? '已加入黑名单' : '操作失败，请重试')),
                            );
                            if (ok) widget.onChanged();
                          }
                        } else if (action == 'delete') {
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await KlpbbsApi.deleteFriend(f.uid);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(ok ? '已删除好友' : '操作失败，请重试')),
                            );
                            if (ok) widget.onChanged();
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
