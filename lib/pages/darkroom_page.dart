import 'package:flutter/material.dart';

import '../widgets/app_back_button.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';

import '../api/klpbbs_api.dart';
import '../models/darkroom_entry.dart';
import 'user_space_page.dart';

/// 小黑屋（违规公示，只读）
class DarkroomPage extends StatefulWidget {
  const DarkroomPage({super.key});

  @override
  State<DarkroomPage> createState() => _DarkroomPageState();
}

class _DarkroomPageState extends State<DarkroomPage> {
  int _page = 1;
  final Map<int, int?> _pageCidMap = {1: null};
  int? _nextCid;
  List<DarkroomEntry> _entries = [];
  bool _loading = true;
  String? _error;
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPage(1);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPage(int page) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cid = _pageCidMap[page];
      final res = await KlpbbsApi.getDarkroom(cid: cid, page: page);
      if (!mounted) return;
      setState(() {
        _page = page;
        _entries = res.entries;
        _nextCid = res.nextCid;
        if (res.nextCid != null) {
          _pageCidMap[page + 1] = res.nextCid;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _reload() {
    _loadPage(_page);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyword = _searchCtrl.text.trim().toLowerCase();
    final displayedEntries = keyword.isEmpty
        ? _entries
        : _entries
            .where((e) =>
                e.username.toLowerCase().contains(keyword) ||
                e.reason.toLowerCase().contains(keyword) ||
                e.action.toLowerCase().contains(keyword))
            .toList();

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '搜索用户名 / 理由...',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Text('封神榜'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search_rounded),
            tooltip: _isSearching ? '取消搜索' : '搜索违规公示',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchCtrl.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新当前页',
            onPressed: _loading ? null : _reload,
          ),
          const GlobalNavButton(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: SizedBox(
          height: 62,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant.withAlpha(60),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _page > 1 && !_loading ? () => _loadPage(_page - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  label: const Text('上一页'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '第 $_page 页',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!_loading && _entries.isNotEmpty)
                      Text(
                        '本页 ${_entries.length} 位违规公示',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 20),
                FilledButton.tonalIcon(
                  onPressed: _nextCid != null && !_loading ? () => _loadPage(_page + 1) : null,
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  label: const Text('下一页'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
                        const SizedBox(height: 12),
                        Text('加载失败：$_error', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _reload, child: const Text('重新加载')),
                      ],
                    ),
                  ),
                )
              : displayedEntries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.gavel_outlined, size: 56, color: theme.colorScheme.outline),
                          const SizedBox(height: 12),
                          const Text('暂无违规公示用户'),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => _loadPage(1),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                        itemCount: displayedEntries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final e = displayedEntries[i];
                          final isBanAccess = e.action.contains('禁止访问');
                          final actionColor = isBanAccess
                              ? theme.colorScheme.error
                              : (theme.brightness == Brightness.dark ? Colors.orange.shade300 : Colors.orange.shade800);

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant.withAlpha(60),
                                width: 0.8,
                              ),
                            ),
                            child: InkWell(
                              onTap: e.uid > 0
                                  ? () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => UserSpacePage(
                                            uid: e.uid,
                                          ),
                                        ),
                                      )
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        UserAvatarWidget(
                                          uid: e.uid,
                                          author: e.username,
                                          size: 36,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                e.username,
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14.5,
                                                ),
                                              ),
                                              if (e.uid > 0)
                                                Text(
                                                  'UID: ${e.uid}',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: theme.colorScheme.outline,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: actionColor.withAlpha(24),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: actionColor.withAlpha(60),
                                              width: 0.6,
                                            ),
                                          ),
                                          child: Text(
                                            e.action,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: actionColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if (e.reason.isNotEmpty)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surfaceContainerHighest
                                              .withAlpha(90),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '处理理由：${e.reason}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.35,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    if (e.dateline.isNotEmpty || e.expiry != null) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          if (e.dateline.isNotEmpty)
                                            Text(
                                              '封禁时间：${e.dateline}',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: theme.colorScheme.outline,
                                              ),
                                            ),
                                          if (e.expiry != null)
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.timer_outlined,
                                                  size: 13,
                                                  color: theme.colorScheme.outline,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '到期：${e.expiry ?? '永久'}',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: theme.colorScheme.outline,
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
                        },
                      ),
                    ),
    );
  }
}
