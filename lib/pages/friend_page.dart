import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../models/friend_item.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';
import 'pm_detail_page.dart';
import 'user_space_page.dart';

/// 好友列表页（完美还原 Discuz 空间好友系统）
class FriendPage extends StatefulWidget {
  final int uid;
  final String? username;

  const FriendPage({super.key, required this.uid, this.username});

  @override
  State<FriendPage> createState() => _FriendPageState();
}

class _FriendPageState extends State<FriendPage> {
  late Future<List<FriendItem>> _future;
  final TextEditingController _searchCtrl = TextEditingController();
  String _filterKeyword = '';
  int? _myUid;

  @override
  void initState() {
    super.initState();
    _future = KlpbbsApi.getFriends(widget.uid);
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
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = KlpbbsApi.getFriends(widget.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = DioClient.isLoggedIn && (_myUid == widget.uid);
    final title = isMe
        ? '我的好友'
        : (widget.username != null && widget.username!.isNotEmpty
            ? '${widget.username} 的好友'
            : '好友列表');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _reload,
          ),
          const GlobalNavButton(),
        ],
      ),
      body: FutureBuilder<List<FriendItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EmptyView(
              icon: Icons.error_outline,
              title: '加载好友列表失败',
              subtitle: '${snap.error}',
              action: FilledButton.tonal(
                onPressed: _reload,
                child: const Text('重试'),
              ),
            );
          }

          final allList = snap.data ?? [];
          if (allList.isEmpty) {
            return EmptyView(
              icon: Icons.people_outline,
              title: '暂无好友',
              subtitle: isMe ? '您目前还没有添加任何好友' : '该用户暂无公开好友',
              action: FilledButton.tonal(
                onPressed: _reload,
                child: const Text('刷新'),
              ),
            );
          }

          final filteredList = _filterKeyword.isEmpty
              ? allList
              : allList.where((f) {
                  return f.username.toLowerCase().contains(_filterKeyword) ||
                      f.usergroup.toLowerCase().contains(_filterKeyword) ||
                      f.uid.toString().contains(_filterKeyword);
                }).toList();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: Column(
              children: [
                // 搜索过滤栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: '搜索好友昵称、用户组或 UID...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _filterKeyword.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant.withAlpha(80),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant.withAlpha(60),
                        ),
                      ),
                    ),
                  ),
                ),

                // 好友统计提示
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '共 ${allList.length} 位好友',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      if (_filterKeyword.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(匹配到 ${filteredList.length} 位)',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 列表内容
                Expanded(
                  child: filteredList.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('未找到匹配的好友'),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          itemCount: filteredList.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final f = filteredList[i];
                            return _buildFriendCard(context, f, theme);
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFriendCard(BuildContext context, FriendItem f, ThemeData theme) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(50),
          width: 0.8,
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UserSpacePage(uid: f.uid)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // 用户头像
              UserAvatarWidget(
                uid: f.uid,
                author: f.username,
                size: 44,
              ),
              const SizedBox(width: 14),

              // 昵称 + 用户组 + 积分
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
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (f.usergroup.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withAlpha(160),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              f.usergroup,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'UID: ${f.uid}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        if (f.credits.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(
                            '积分: ${f.credits}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // 快捷私信按钮
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                tooltip: '发私信',
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

              // 更多操作
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                tooltip: '更多操作',
                onSelected: (val) async {
                  if (val == 'space') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UserSpacePage(uid: f.uid),
                      ),
                    );
                  } else if (val == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('解除好友关系'),
                        content: Text('确定要将「${f.username}」从好友列表中移除吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                            ),
                            child: const Text('解除'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      final messenger = ScaffoldMessenger.of(context);
                      final ok = await KlpbbsApi.deleteFriend(f.uid);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(ok ? '已解除好友关系' : '操作失败，请重试'),
                        ),
                      );
                      if (ok) _reload();
                    }
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'space',
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 18),
                        SizedBox(width: 8),
                        Text('查看空间'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.person_remove_outlined, size: 18, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text('解除好友', style: TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
