import 'package:flutter/material.dart';

import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';

import '../api/klpbbs_api.dart';
import '../models/darkroom_entry.dart';

/// 小黑屋（违规公示，只读）
class DarkroomPage extends StatefulWidget {
  const DarkroomPage({super.key});

  @override
  State<DarkroomPage> createState() => _DarkroomPageState();
}

class _DarkroomPageState extends State<DarkroomPage> {
  late Future<List<DarkroomEntry>> _future;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = KlpbbsApi.getDarkroom(page: _page);
  }

  void _reload() {
    setState(() => _future = KlpbbsApi.getDarkroom(page: _page));
  }

  void _goPage(int page) {
    setState(() {
      _page = page;
      _future = KlpbbsApi.getDarkroom(page: page);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('封神榜'),
        actions: const [GlobalNavButton()],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _page > 1 ? () => _goPage(_page - 1) : null,
              ),
              Text(
                '第 $_page 页',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _goPage(_page + 1),
              ),
            ],
          ),
        ),
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('加载失败：${snap.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            );
          }
          final entries = snap.data!;
          if (entries.isEmpty) {
            return const Center(child: Text('暂无违规用户'));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final e = entries[i];
                final theme = Theme.of(context);
                final isBanAccess = e.action.contains('禁止访问');
                final actionColor = isBanAccess
                    ? theme.colorScheme.error
                    : Colors.orange.shade800;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(60),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          UserAvatarWidget(
                            uid: e.uid,
                            author: e.username,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.username,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: actionColor.withAlpha(22),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              e.action,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: actionColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (e.reason.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withAlpha(120),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '理由：${e.reason}',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (e.dateline.isNotEmpty)
                            Text(
                              '封禁时间：${e.dateline}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          Row(
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 14,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '到期：${e.expiry ?? '永久'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
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
