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
          if (list.isNotEmpty) {
            SharedPreferences.getInstance().then((prefs) {
              final set = (prefs.getStringList('fav_forums') ?? []).toSet();
              bool changed = false;
              for (final f in list) {
                if (set.add('${f.fid}')) changed = true;
              }
              if (changed) prefs.setStringList('fav_forums', set.toList());
            }).catchError((_) {});
          }
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.star_border,
              title: '暂无收藏版块',
              subtitle: '长按首页版块可收藏',
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
                  trailing: const Icon(Icons.chevron_right),
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
