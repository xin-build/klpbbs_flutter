import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../widgets/thread_card.dart';
import 'user_space_page.dart';
import '../widgets/global_nav.dart';

/// 好友列表（klpbbs home.php?mod=space&do=friend，需登录）
class FriendPage extends StatefulWidget {
  final int uid;
  const FriendPage({super.key, required this.uid});

  @override
  State<FriendPage> createState() => _FriendPageState();
}

class _FriendPageState extends State<FriendPage> {
  late Future<List<({int uid, String name})>> _future;

  @override
  void initState() {
    super.initState();
    _future = KlpbbsApi.getFriends(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('好友列表'),
        actions: const [GlobalNavButton()],
      ),
      body: FutureBuilder<List<({int uid, String name})>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无好友（需登录后可见）', textAlign: TextAlign.center),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                setState(() => _future = KlpbbsApi.getFriends(widget.uid)),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final f = list[i];
                final scheme = Theme.of(context).colorScheme;
                return Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UserSpacePage(uid: f.uid),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          UserAvatarWidget(
                            uid: f.uid,
                            author: f.name,
                            size: 36,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: scheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
