import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../widgets/empty_view.dart';
import '../models/forum.dart';
import 'thread_list_page.dart';
import '../widgets/global_nav.dart';

/// 收藏版块列表
class FavoriteForumsPage extends StatefulWidget {
  final int uid;

  const FavoriteForumsPage({super.key, required this.uid});

  @override
  State<FavoriteForumsPage> createState() => _FavoriteForumsPageState();
}

class _FavoriteForumsPageState extends State<FavoriteForumsPage> {
  late Future<List<Forum>> _future;

  @override
  void initState() {
    super.initState();
    _future = KlpbbsApi.getFavoriteForums(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏版块'),
        actions: const [GlobalNavButton()],
      ),
      body: FutureBuilder<List<Forum>>(
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
            return const EmptyView(
              icon: Icons.star_border,
              title: '暂无收藏版块',
              subtitle: '长按首页版块或在版块内可收藏',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() {
              _future = KlpbbsApi.getFavoriteForums(widget.uid);
            }),
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final f = list[i];
                return ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: Text(f.name),
                  subtitle: f.description != null && f.description!.isNotEmpty
                      ? Text(f.description!, maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.star, color: Colors.amber),
                    tooltip: '取消收藏',
                    onPressed: () async {
                      // 立即本地移除
                      final prefs = await SharedPreferences.getInstance();
                      final set = (prefs.getStringList('fav_forums') ?? []).toSet();
                      set.remove('${f.fid}');
                      await prefs.setStringList('fav_forums', set.toList());

                      final res = await KlpbbsApi.unfavoriteForum(f.fid, favid: f.favid);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res.message.isNotEmpty ? res.message : '已取消收藏「${f.name}」'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        setState(() {
                          _future = KlpbbsApi.getFavoriteForums(widget.uid);
                        });
                      }
                    },
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ThreadListPage(fid: f.fid, title: f.name),
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
