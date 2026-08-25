import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../models/thread_summary.dart';
import '../widgets/empty_view.dart';
import '../widgets/favorite_dialog.dart';
import '../widgets/global_nav.dart';
import '../widgets/pagination_control.dart';
import '../widgets/thread_card.dart';
import 'login_page.dart';
import 'thread_detail_page.dart';

/// 用户主题/回复/收藏列表（支持分类切换与分页，对齐 KLPBBS 移动端与时间线回复架构）
class UserThreadsPage extends StatefulWidget {
  final int uid;
  final String type; // thread | reply | favorite
  final String title;
  final bool showAppBar;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const UserThreadsPage({
    super.key,
    required this.uid,
    required this.type,
    required this.title,
    this.showAppBar = true,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  State<UserThreadsPage> createState() => _UserThreadsPageState();
}

class _UserThreadsPageState extends State<UserThreadsPage> {
  late String _currentType;
  int _page = 1;
  late Future<List<ThreadSummary>> _future;
  bool _sortByName = false;
  String _selectedTag = '全部';
  List<String> _favTags = ['全部'];

  @override
  void initState() {
    super.initState();
    _currentType = widget.type;
    _fetch();
    if (_currentType == 'favorite') {
      _loadTags();
    }
  }

  Future<void> _loadTags() async {
    try {
      final tags = await KlpbbsApi.getFavoriteTags();
      if (mounted && tags.isNotEmpty) {
        setState(() {
          _favTags = ['全部', ...tags];
        });
      }
    } catch (_) {}
  }

  void _fetch() {
    if (_currentType == 'favorite') {
      _future = KlpbbsApi.getFavorites(
        widget.uid,
        page: _page,
        tag: _selectedTag == '全部' ? null : _selectedTag,
      ).then((threads) {
        SharedPreferences.getInstance().then((prefs) {
          final list = (prefs.getStringList('fav_tids') ?? []).toSet();
          bool changed = false;
          for (final t in threads) {
            if (list.add('${t.tid}')) changed = true;
          }
          if (changed) prefs.setStringList('fav_tids', list.toList());
        }).catchError((_) {});
        return threads;
      });
    } else {
      _future = KlpbbsApi.getUserThreads(widget.uid, type: _currentType, page: _page);
    }
  }

  void _switchType(String newType) {
    if (_currentType == newType) return;
    setState(() {
      _currentType = newType;
      _page = 1;
      _fetch();
    });
  }

  void _switchTag(String tag) {
    if (_selectedTag == tag) return;
    setState(() {
      _selectedTag = tag;
      _page = 1;
      _fetch();
    });
  }

  void _goPage(int p) {
    if (p < 1) return;
    setState(() {
      _page = p;
      _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final typeSelector = widget.type != 'favorite'
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withAlpha(50),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'thread',
                      label: Text('发表的主题'),
                      icon: Icon(Icons.article_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: 'reply',
                      label: Text('发表的回复'),
                      icon: Icon(Icons.forum_outlined, size: 16),
                    ),
                  ],
                  selected: {_currentType},
                  onSelectionChanged: (s) => _switchType(s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const Spacer(),
                Text(
                  '第 $_page 页',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        : (_favTags.length > 1
            ? Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withAlpha(50),
                      width: 0.8,
                    ),
                  ),
                ),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _favTags.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, idx) {
                    final tag = _favTags[idx];
                    final isSel = _selectedTag == tag;
                    return ChoiceChip(
                      label: Text(tag),
                      selected: isSel,
                      visualDensity: VisualDensity.compact,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) => _switchTag(tag),
                    );
                  },
                ),
              )
            : const SizedBox.shrink());

    final listWidget = FutureBuilder<List<ThreadSummary>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ));
        }
        if (snap.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('加载失败：${snap.error}'),
          ));
        }
        var list = snap.data ?? [];
        if (_sortByName && _currentType == 'favorite') {
          list = List.of(list)..sort((a, b) => a.title.compareTo(b.title));
        }
        if (list.isEmpty) {
          final isNotLoggedIn = !DioClient.isLoggedIn;
          return EmptyView(
            icon: _currentType == 'favorite'
                ? Icons.bookmark_border
                : Icons.article_outlined,
            title: isNotLoggedIn
                ? '需要登录论坛账号'
                : (_currentType == 'favorite'
                    ? '暂无收藏'
                    : (_currentType == 'reply' ? '暂未发表任何回复' : '暂未发表任何主题')),
            subtitle: isNotLoggedIn
                ? '苦力怕论坛要求登录账号后才可查阅用户的空间帖子与回复记录'
                : (_currentType == 'favorite'
                    ? '在帖子详情中收藏的帖子将显示在此处'
                    : '该用户尚未发表公开的${_currentType == 'reply' ? '回复' : '主题'}'),
            action: isNotLoggedIn
                ? FilledButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                      if (mounted) setState(() => _fetch());
                    },
                    icon: const Icon(Icons.login_rounded, size: 16),
                    label: const Text('立即登录'),
                  )
                : null,
          );
        }
        final listView = ListView.separated(
          shrinkWrap: widget.shrinkWrap,
          physics: widget.physics ?? (widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: list.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == list.length) {
              return PaginationControl(
                page: _page,
                hasMore: list.length >= 8,
                onPageChanged: _goPage,
              );
            }
            final t = list[i];
            final fallbackAuthor = widget.title
                .replaceAll(' 的主题', '')
                .replaceAll(' 的回复', '')
                .replaceAll(' 的收藏', '')
                .replaceAll('我', '');
            final filledThread = t.copyWith(
              author: t.author.isNotEmpty ? t.author : fallbackAuthor,
              uid: t.uid ?? widget.uid,
            );
            if (_currentType == 'reply') {
              return _buildReplyTimelineTile(filledThread, colorScheme);
            }
            return GestureDetector(
              onLongPress: _currentType == 'favorite'
                  ? () async {
                      final res = await FavoriteDialog.show(
                        context,
                        tid: filledThread.tid,
                        title: filledThread.title,
                        isFavorited: true,
                        favid: filledThread.favid,
                      );
                      if (res == false && mounted) {
                        setState(() => _fetch());
                      }
                    }
                  : null,
              child: ThreadCard(
                thread: filledThread,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ThreadDetailPage(tid: filledThread.tid),
                    ),
                  );
                  if (_currentType == 'favorite' && mounted) {
                    setState(() => _fetch());
                  }
                },
              ),
            );
          },
        );

        if (widget.shrinkWrap) {
          return listView;
        }

        return RefreshIndicator(
          onRefresh: () async => setState(() => _fetch()),
          child: listView,
        );
      },
    );

    final body = Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        typeSelector,
        if (widget.shrinkWrap)
          listWidget
        else
          Expanded(
            child: listWidget,
          ),
      ],
    );

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          const GlobalNavButton(),
          if (widget.type == 'favorite')
            IconButton(
              icon: Icon(_sortByName ? Icons.sort_by_alpha : Icons.access_time),
              tooltip: _sortByName ? '按名称排序' : '按时间排序',
              onPressed: () => setState(() => _sortByName = !_sortByName),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildReplyTimelineTile(ThreadSummary t, ColorScheme colorScheme) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: t.tid)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧时间线节点
            Column(
              children: [
                const SizedBox(height: 3),
                Icon(Icons.access_time_filled, size: 14, color: colorScheme.primary),
                if (t.timeText != null && t.timeText!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    t.timeText!,
                    style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 12),
            // 右侧回复气泡与出处
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 对应的主题标题
                  Row(
                    children: [
                      if (t.forumName != null && t.forumName!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withAlpha(120),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            t.forumName!,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 回复正文气泡
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(70),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withAlpha(60),
                        width: 0.5,
                      ),
                    ),
                    child: _buildReplyContent(t.excerpt ?? t.title, colorScheme),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyContent(String raw, ColorScheme colorScheme) {
    final hasAttach = raw.contains('[attach]') || raw.contains('attachimg') || raw.contains('[附件]');
    String? quoteText;
    String mainText = raw;
    final quoteMatch = RegExp(r'\[quote\](.*?)\[/quote\]', dotAll: true).firstMatch(raw);
    if (quoteMatch != null) {
      quoteText = quoteMatch.group(1)?.replaceAll(RegExp(r'\[.*?\]'), '').trim();
      mainText = raw.replaceAll(RegExp(r'\[quote\].*?\[/quote\]', dotAll: true), '').trim();
    }
    mainText = mainText
        .replaceAll(RegExp(r'\[attach\]\d+\[/attach\]'), '')
        .replaceAll(RegExp(r'\[/?[a-zA-Z0-9_=#]+\]'), '')
        .trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (quoteText != null && quoteText.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(50),
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: colorScheme.primary, width: 3)),
            ),
            child: Text(
              '引用: $quoteText',
              style: TextStyle(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: colorScheme.outline,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Text(
          mainText.isNotEmpty ? mainText : '发表了回复',
          style: const TextStyle(fontSize: 13, height: 1.35),
        ),
        if (hasAttach) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attach_file, size: 13, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                '包含附件/图片',
                style: TextStyle(fontSize: 10.5, color: colorScheme.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
