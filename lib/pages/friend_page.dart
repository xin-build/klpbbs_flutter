import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../models/friend_item.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';
import 'pm_detail_page.dart';
import 'user_space_page.dart';

/// 好友与关注粉丝中心页面（深度统一 App Material 3 现代视觉与操作体系）
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
      if (mounted && uid != null) {
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
    final isMe = DioClient.isLoggedIn && (_myUid == widget.uid || widget.uid <= 0);
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
              // 顶部全局搜索过滤条 (统一 Material 3 风格)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: '搜索好友昵称、用户组或 UID...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    suffixIcon: _filterKeyword.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.cancel_rounded, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant.withAlpha(60),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant.withAlpha(60),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
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
  final TextEditingController _blacklistAddCtrl = TextEditingController();
  bool _isAddingBlacklist = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _blacklistAddCtrl.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _future = KlpbbsApi.getFriends(widget.uid, view: widget.view);
    });
  }

  Future<void> _addBlacklist() async {
    final name = _blacklistAddCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _isAddingBlacklist = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await KlpbbsApi.addToBlacklistByUsername(name);
    if (mounted) {
      setState(() => _isAddingBlacklist = false);
      if (ok) {
        _blacklistAddCtrl.clear();
        messenger.showSnackBar(
          SnackBar(content: Text('已将「$name」加入黑名单')),
        );
        _load();
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('添加失败，请确认用户名是否存在或网络正常')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // 黑名单 Tab 顶部现代 Material 提示框与添加栏
        if (widget.view == 'blacklist') ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.tertiaryContainer.withAlpha(50)
                    : const Color(0xFFFFF8E1),
                border: Border.all(
                  color: isDark
                      ? theme.colorScheme.tertiary.withAlpha(60)
                      : const Color(0xFFFFE082),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: isDark
                        ? theme.colorScheme.tertiary
                        : const Color(0xFFF57F17),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '加入到黑名单的用户，将会从您的好友列表中删除。同时，对方将不能进行与您相关的打招呼、踩日志、加好友、评论、留言、短消息等互动行为。',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? theme.colorScheme.onSurface
                            : const Color(0xFF5D4037),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _blacklistAddCtrl,
                    decoration: InputDecoration(
                      hintText: '输入需要添加黑名单的用户名',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant.withAlpha(80),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: _isAddingBlacklist
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.person_add_disabled_rounded, size: 16),
                  label: const Text('添加', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  ),
                  onPressed: _isAddingBlacklist ? null : _addBlacklist,
                ),
              ],
            ),
          ),
        ],

        Expanded(
          child: FutureBuilder<List<FriendItem>>(
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
                  title: widget.view == 'blacklist' ? '没有相关用户列表' : '暂无数据',
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

              return RefreshIndicator(
                onRefresh: () async => _load(),
                child: filteredList.isEmpty
                    ? Center(
                        child: Text(
                          '未找到匹配「${widget.filterKeyword}」的结果',
                          style: TextStyle(color: theme.colorScheme.outline),
                        ),
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filteredList.length,
                        itemBuilder: (context, index) {
                          final item = filteredList[index];
                          return _FriendCard(
                            key: ValueKey('${widget.view}_${item.uid}'),
                            item: item,
                            view: widget.view,
                            isMe: widget.isMe,
                            onChanged: _load,
                          );
                        },
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getTabEmptyIcon(String view) {
    switch (view) {
      case 'follow':
        return Icons.favorite_border;
      case 'fans':
        return Icons.star_border;
      case 'visitor':
        return Icons.visibility_off_outlined;
      case 'trace':
        return Icons.history;
      case 'request':
        return Icons.person_add_disabled_outlined;
      case 'blacklist':
        return Icons.block_outlined;
      default:
        return Icons.people_outline;
    }
  }
}

/// 单个好友/用户条目卡片 (精细打磨的 Material 3 风格)
class _FriendCard extends StatefulWidget {
  final FriendItem item;
  final String view;
  final bool isMe;
  final VoidCallback onChanged;

  const _FriendCard({
    super.key,
    required this.item,
    required this.view,
    required this.isMe,
    required this.onChanged,
  });

  @override
  State<_FriendCard> createState() => _FriendCardState();
}

class _FriendCardState extends State<_FriendCard> {
  late bool _isFollowing;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.item.isFollowing;
  }

  Future<void> _toggleFollow() async {
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
        SnackBar(
          content: Text(
            ok
                ? (nextState ? '已关注「${widget.item.username}」' : '已取消关注「${widget.item.username}」')
                : '操作失败，请重试',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      if (ok) widget.onChanged();
    }
  }

  Future<void> _editNote() async {
    final ctrl = TextEditingController(text: widget.item.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('修改「${widget.item.username}」备注'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入好友备注（如真实姓名、联系方式）',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      final newNote = ctrl.text.trim();
      final messenger = ScaffoldMessenger.of(context);
      final res = await KlpbbsApi.editFriendNote(widget.item.uid, newNote);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(res ? '备注已更新' : '更新备注失败，请重试'),
            duration: const Duration(seconds: 2),
          ),
        );
        if (res) widget.onChanged();
      }
    }
    ctrl.dispose();
  }

  Future<void> _showGroupPicker() async {
    const groups = [
      (0, '特别关注'),
      (1, '认识的人'),
      (2, '朋友'),
      (3, '网友'),
      (4, '同事'),
      (5, '家人'),
    ];

    final selected = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '选择好友「${widget.item.username}」分组',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Divider(height: 1),
              for (final g in groups)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(g.$2),
                  onTap: () => Navigator.of(ctx).pop(g.$1),
                ),
            ],
          ),
        );
      },
    );

    if (selected != null && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await KlpbbsApi.changeFriendGroup(widget.item.uid, selected);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ok ? '分组修改成功' : '修改分组失败，请重试'),
            duration: const Duration(seconds: 2),
          ),
        );
        if (ok) widget.onChanged();
      }
    }
  }

  Future<void> _pokeUser() async {
    const pokes = [
      '打了个招呼',
      '握了个手',
      '踩了一下',
      '摸了摸头',
      '比了个心',
      '抛了个媚眼',
    ];

    final msg = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('向「${widget.item.username}」打招呼'),
        children: pokes.map((p) {
          return SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () => Navigator.of(ctx).pop(p),
            child: Text(p, style: const TextStyle(fontSize: 14.5)),
          );
        }).toList(),
      ),
    );

    if (msg != null && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await KlpbbsApi.pokeUser(widget.item.uid, msg);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ok ? '已向「${widget.item.username}」$msg' : '打招呼失败，请重试'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _deleteFriend() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定要删除好友「${widget.item.username}」吗？此操作不可逆。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await KlpbbsApi.deleteFriend(widget.item.uid);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ok ? '已删除好友「${widget.item.username}」' : '删除失败，请重试'),
            duration: const Duration(seconds: 2),
          ),
        );
        if (ok) widget.onChanged();
      }
    }
  }

  Future<void> _addToBlacklist() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入黑名单'),
        content: Text(
          '确定要将「${widget.item.username}」加入黑名单吗？该用户将从好友列表中移除，且无法与您互动。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认拉黑'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await KlpbbsApi.addToBlacklist(widget.item.uid);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(ok ? '已将「${widget.item.username}」加入黑名单' : '操作失败，请重试'),
            duration: const Duration(seconds: 2),
          ),
        );
        if (ok) widget.onChanged();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final f = widget.item;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(45)),
      ),
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surfaceContainerLowest,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (f.uid > 0) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => UserSpacePage(uid: f.uid)),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // 1. 头像区（带在线指示徽标）
              UserAvatarWidget(
                uid: f.uid,
                avatarUrl: f.avatarUrl,
                author: f.username,
                size: 44,
                isOnline: f.isOnline,
                showOnlineBadge: true,
              ),
              const SizedBox(width: 12),

              // 2. 用户核心信息区
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            f.username,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (f.note.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '（${f.note}）',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: f.usergroup.contains('禁止')
                                  ? colorScheme.errorContainer
                                  : colorScheme.primaryContainer.withAlpha(120),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              f.usergroup,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
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
                                f.credits.contains('积分') ? f.credits : '积分: ${f.credits}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (f.recentActivity.isNotEmpty &&
                        !f.recentActivity.startsWith('UID') &&
                        !f.recentActivity.contains('积分')) ...[
                      const SizedBox(height: 2),
                      Text(
                        f.recentActivity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 6),

              // 3. 右侧 Material 3 快捷操作组
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
                    // 发消息 (Chat)
                    IconButton.filledTonal(
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      tooltip: '发消息',
                      visualDensity: VisualDensity.compact,
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
                    const SizedBox(width: 4),

                    // 打招呼 (Poke)
                    IconButton.filledTonal(
                      icon: Icon(
                        Icons.waving_hand_rounded,
                        size: 18,
                        color: isDark ? Colors.tealAccent : const Color(0xFF00897B),
                      ),
                      tooltip: '打招呼',
                      visualDensity: VisualDensity.compact,
                      onPressed: _pokeUser,
                    ),
                    const SizedBox(width: 4),

                    // 关注 / 取消 (Follow / Unfollow)
                    IconButton.filledTonal(
                      icon: _isActionLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _isFollowing ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 18,
                              color: _isFollowing ? const Color(0xFFE53935) : colorScheme.onSurfaceVariant,
                            ),
                      tooltip: _isFollowing ? '取消关注' : '关注',
                      visualDensity: VisualDensity.compact,
                      onPressed: _isActionLoading ? null : _toggleFollow,
                    ),

                    // 更多操作 (分组、备注、空间、拉黑、删除)
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 18,
                        color: colorScheme.outline,
                      ),
                      tooltip: '更多操作',
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case 'group':
                            _showGroupPicker();
                            break;
                          case 'note':
                            _editNote();
                            break;
                          case 'space':
                            if (f.uid > 0) {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => UserSpacePage(uid: f.uid)),
                              );
                            }
                            break;
                          case 'blacklist':
                            _addToBlacklist();
                            break;
                          case 'delete':
                            _deleteFriend();
                            break;
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'group',
                          child: Row(
                            children: [
                              Icon(Icons.folder_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('好友分组'),
                            ],
                          ),
                        ),
                        if (widget.isMe && widget.view == 'me')
                          const PopupMenuItem(
                            value: 'note',
                            child: Row(
                              children: [
                                Icon(Icons.edit_note_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('修改备注'),
                              ],
                            ),
                          ),
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
                              Icon(Icons.block_outlined, size: 18, color: Colors.orange),
                              SizedBox(width: 8),
                              Text('加入黑名单', style: TextStyle(color: Colors.orange)),
                            ],
                          ),
                        ),
                        if (widget.isMe && widget.view == 'me')
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.person_remove_outlined, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('删除好友', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                      ],
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

