import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/write_confirm.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_nav.dart';

import '../api/klpbbs_api.dart';
import '../models/pm_models.dart';
import '../widgets/thread_card.dart';
import 'pm_detail_page.dart';
import 'user_space_page.dart';

/// 私信收件箱（会话列表）
class PmInboxPage extends StatefulWidget {
  const PmInboxPage({super.key});

  @override
  State<PmInboxPage> createState() => _PmInboxPageState();
}

class _PmInboxPageState extends State<PmInboxPage> {
  late Future<List<PmConversation>> _future;
  String _kw = '';
  List<String> _searchHistory = [];
  Set<int> _read = {};
  Set<int> _unreadOverride = {};
  Set<int> _pinned = {};
  bool _selectionMode = false;
  final Set<int> _selected = {};
  List<PmConversation> _allConvs = const [];

  @override
  void initState() {
    super.initState();
    _future = KlpbbsApi.getPmList();
    _loadRead();
    _loadPinned();
    _loadSearchHistory();
  }

  Future<void> _loadRead() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _read = (prefs.getStringList('pm_read') ?? const [])
          .map(int.parse)
          .toSet();
      _unreadOverride = (prefs.getStringList('pm_unread_override') ?? const [])
          .map(int.parse)
          .toSet();
    });
  }

  Future<void> _loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
      () => _pinned = (prefs.getStringList('pm_pin') ?? const [])
          .map(int.parse)
          .toSet(),
    );
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
      () =>
          _searchHistory = prefs.getStringList('pm_search_history') ?? const [],
    );
  }

  Future<void> _saveSearchHistory(String kw) async {
    if (kw.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('pm_search_history') ?? [];
    list.remove(kw);
    list.insert(0, kw);
    await prefs.setStringList('pm_search_history', list.take(8).toList());
    if (mounted) setState(() => _searchHistory = list.take(8).toList());
  }

  /// 日期友好化：今天/昨天/MM月dd日
  String _friendlyDate(String t) {
    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (m == null) return t;
    final y = int.tryParse(m.group(1) ?? '') ?? 0;
    final mo = int.tryParse(m.group(2) ?? '') ?? 0;
    final d = int.tryParse(m.group(3) ?? '') ?? 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(y, mo, d);
    final diff = today.difference(that).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (y == now.year) return '$mo月$d日';
    return '$y年$mo月$d日';
  }

  /// 关键词高亮（搜索匹配处主题色加粗）
  List<TextSpan> _highlight(String text, String kw) {
    if (kw.isEmpty) return [TextSpan(text: text)];
    final scheme = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = text.toLowerCase().indexOf(kw.toLowerCase(), start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + kw.length),
          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold),
        ),
      );
      start = idx + kw.length;
    }
    return spans;
  }

  /// 会话长按菜单（置顶/已读/删除）
  void _showConvMenu(PmConversation c) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                c.username,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              dense: true,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                _pinned.contains(c.touid)
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
              ),
              title: Text(_pinned.contains(c.touid) ? '取消置顶' : '置顶会话'),
              onTap: () {
                Navigator.of(ctx).pop();
                _togglePin(c.touid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('标记为已读'),
              onTap: () {
                Navigator.of(ctx).pop();
                _markRead(c.touid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.mark_email_unread_outlined),
              title: const Text('标记为未读'),
              onTap: () {
                Navigator.of(ctx).pop();
                _markUnread(c.touid);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除会话'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final messenger = ScaffoldMessenger.of(context);
                final confirmed = await confirmWrite(context, '删除会话');
                if (!confirmed || !context.mounted) return;
                try {
                  final ok = await KlpbbsApi.deletePm(c.touid);
                  if (ok && mounted) {
                    messenger.showSnackBar(const SnackBar(content: Text('已删除会话')));
                    _reload();
                  }
                } catch (_) {}
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 标记未读
  Future<void> _markUnread(int touid) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('pm_read') ?? [];
    list.remove('$touid');
    await prefs.setStringList('pm_read', list);
    final unreadList = prefs.getStringList('pm_unread_override') ?? [];
    if (!unreadList.contains('$touid')) unreadList.add('$touid');
    await prefs.setStringList('pm_unread_override', unreadList);
    if (mounted) {
      setState(() {
        _read.remove(touid);
        _unreadOverride.add(touid);
      });
    }
  }

  /// 全部已读
  Future<void> _markAllRead() async {
    final prefs = await SharedPreferences.getInstance();
    final all = await KlpbbsApi.getPmList();
    final list = prefs.getStringList('pm_read') ?? [];
    for (final c in all) {
      final id = '${c.touid}';
      if (!list.contains(id)) list.add(id);
    }
    await prefs.setStringList('pm_read', list);
    await prefs.setStringList('pm_unread_override', []);
    if (mounted) {
      setState(() {
        _read = all.map((c) => c.touid).toSet();
        _unreadOverride.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已全部标记为已读')));
    }
  }

  /// 置顶/取消置顶
  Future<void> _togglePin(int touid) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('pm_pin') ?? [];
    if (_pinned.contains(touid)) {
      list.remove('$touid');
    } else {
      list.add('$touid');
    }
    await prefs.setStringList('pm_pin', list);
    if (mounted) {
      setState(() {
        if (_pinned.contains(touid)) {
          _pinned.remove(touid);
        } else {
          _pinned.add(touid);
        }
      });
    }
  }

  /// 标记会话已读
  Future<void> _markRead(int touid) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('pm_read') ?? [];
    if (!list.contains('$touid')) {
      list.add('$touid');
      await prefs.setStringList('pm_read', list);
    }
    final unreadList = prefs.getStringList('pm_unread_override') ?? [];
    unreadList.remove('$touid');
    await prefs.setStringList('pm_unread_override', unreadList);
    if (mounted) {
      setState(() {
        _read.add(touid);
        _unreadOverride.remove(touid);
      });
    }
  }

  void _reload() {
    setState(() => _future = KlpbbsApi.getPmList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('私信收件箱'),
        actions: [
          const GlobalNavButton(),
          if (!_selectionMode)
            IconButton(
              icon: const Icon(Icons.done_all, size: 20),
              tooltip: '全部已读',
              onPressed: _markAllRead,
            ),
          IconButton(
            icon: Icon(_selectionMode ? Icons.close : Icons.checklist_outlined),
            tooltip: _selectionMode ? '退出管理' : '管理',
            onPressed: () => setState(() {
              _selectionMode = !_selectionMode;
              _selected.clear();
            }),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) {
                setState(() => _kw = v.trim());
                if (v.trim().isNotEmpty) _saveSearchHistory(v.trim());
              },
              decoration: InputDecoration(
                hintText: '搜索会话',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _kw.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _kw = ''),
                      ),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 搜索历史（空关键词且有历史时）
          if (_kw.isEmpty && _searchHistory.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                children: [
                  for (final h in _searchHistory)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(h, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _kw = h),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: FutureBuilder<List<PmConversation>>(
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
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }
                final all = snap.data!;
                _allConvs = all;
                final filtered = _kw.isEmpty
                    ? all
                    : all
                          .where(
                            (c) =>
                                c.username.contains(_kw) ||
                                c.summary.contains(_kw),
                          )
                          .toList();
                // 排序：置顶 > 未读 > 其余
                final list = [
                  ...filtered.where((c) => _pinned.contains(c.touid)),
                  ...filtered
                      .where(
                        (c) =>
                            !_pinned.contains(c.touid) &&
                            ((c.isNew && !_read.contains(c.touid)) ||
                                _unreadOverride.contains(c.touid)),
                      ),
                  ...filtered.where(
                    (c) =>
                        !_pinned.contains(c.touid) &&
                        !((c.isNew && !_read.contains(c.touid)) ||
                            _unreadOverride.contains(c.touid)),
                  ),
                ];
                if (all.isEmpty) {
                  return const EmptyView(
                    icon: Icons.mail_outline,
                    title: '暂无私信会话',
                    subtitle: '收到私信后会显示在这里',
                  );
                }
                if (list.isEmpty) {
                  return const EmptyView(
                    icon: Icons.search_off,
                    title: '未找到匹配会话',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  color: Theme.of(context).colorScheme.primary,
                  displacement: 40,
                  edgeOffset: 8,
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = list[i];
                      final unread =
                          (c.isNew && !_read.contains(c.touid)) ||
                          _unreadOverride.contains(c.touid);
                      return Dismissible(
                        key: ValueKey('pm_${c.plid}_${c.touid}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        confirmDismiss: (_) async {
                          final confirmed = await confirmWrite(context, '删除会话');
                          if (!confirmed || !context.mounted) return false;
                          try {
                            final ok = await KlpbbsApi.deletePm(c.touid);
                            if (ok) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已删除会话')),
                                );
                              }
                              return true;
                            }
                          } catch (_) {}
                          return false;
                        },
                        onDismissed: (_) {
                          _reload();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('会话已删除')),
                          );
                        },
                        child: ListTile(
                          leading: _selectionMode
                              ? Checkbox(
                                  value: _selected.contains(c.touid),
                                  onChanged: (_) => setState(() {
                                    _selected.contains(c.touid)
                                        ? _selected.remove(c.touid)
                                        : _selected.add(c.touid);
                                  }),
                                )
                              : Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(22),
                                      onTap: c.touid > 0
                                          ? () => Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    UserSpacePage(uid: c.touid),
                                              ),
                                            )
                                          : null,
                                      child: UserAvatarWidget(
                                        uid: c.touid,
                                        author: c.username,
                                        size: 44,
                                        faceUrl: c.faceUrl,
                                      ),
                                    ),
                                    if (unread)
                                      Positioned(
                                        right: -2,
                                        top: -2,
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.surface,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      fontWeight: unread
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    children: _highlight(
                                      c.username.isEmpty
                                          ? '用户${c.touid}'
                                          : c.username,
                                      _kw,
                                    ),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (unread)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '新',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onError,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: _highlight(c.summary, _kw),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (c.timeText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    _friendlyDate(c.timeText),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: c.touid > 0
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_pinned.contains(c.touid))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: Icon(
                                          Icons.push_pin,
                                          size: 15,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                    const Icon(Icons.chevron_right, size: 18),
                                  ],
                                )
                              : null,
                          onTap: () {
                            if (c.touid == 0) return;
                            if (_selectionMode) {
                              setState(() {
                                _selected.contains(c.touid)
                                    ? _selected.remove(c.touid)
                                    : _selected.add(c.touid);
                              });
                              return;
                            }
                            _markRead(c.touid);
                            Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PmDetailPage(
                                          touid: c.touid,
                                          toUsername: c.username,
                                        ),
                                  ),
                                )
                                .then((_) => _reload());
                          },
                          onLongPress: () {
                            if (c.touid == 0) return;
                            _showConvMenu(c);
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // 批量操作栏（选择模式）
      bottomNavigationBar: _selectionMode
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.select_all, size: 18),
                      label: Text('全选'),
                      onPressed: () => setState(() {
                        _selected.isEmpty
                            ? _selected.addAll(_allConvs.map((c) => c.touid))
                            : _selected.clear();
                      }),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.push_pin_outlined, size: 18),
                      label: const Text('置顶'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final prefs =
                                  await SharedPreferences.getInstance();
                              final list = prefs.getStringList('pm_pin') ?? [];
                              for (final t in _selected) {
                                if (!list.contains('$t')) list.add('$t');
                              }
                              await prefs.setStringList('pm_pin', list);
                              if (mounted) {
                                setState(() {
                                  _pinned.addAll(_selected);
                                  _selectionMode = false;
                                  _selected.clear();
                                });
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('已置顶')),
                                );
                              }
                            },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.push_pin, size: 18),
                      label: const Text('取消置顶'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final prefs =
                                  await SharedPreferences.getInstance();
                              final list = prefs.getStringList('pm_pin') ?? [];
                              list.removeWhere(
                                (x) =>
                                    _selected.contains(int.tryParse(x) ?? -1),
                              );
                              await prefs.setStringList('pm_pin', list);
                              if (mounted) {
                                setState(() {
                                  _pinned.removeAll(_selected);
                                  _selectionMode = false;
                                  _selected.clear();
                                });
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('已取消置顶')),
                                );
                              }
                            },
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.done_all, size: 18),
                      label: Text('已读 (${_selected.length})'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final prefs =
                                  await SharedPreferences.getInstance();
                              final list = prefs.getStringList('pm_read') ?? [];
                              for (final t in _selected) {
                                if (!list.contains('$t')) list.add('$t');
                              }
                              await prefs.setStringList('pm_read', list);
                              final unreadList = prefs.getStringList('pm_unread_override') ?? [];
                              unreadList.removeWhere((t) => _selected.contains(int.tryParse(t)));
                              await prefs.setStringList('pm_unread_override', unreadList);
                              if (mounted) {
                                setState(() {
                                  _read.addAll(_selected);
                                  _unreadOverride.removeAll(_selected);
                                  _selectionMode = false;
                                  _selected.clear();
                                });
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('已标记已读')),
                                );
                              }
                            },
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text('删除 (${_selected.length})'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('批量删除'),
                                  content: Text(
                                    '确认删除选中的 ${_selected.length} 个会话？此操作不可撤销。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true || !context.mounted) return;
                              // 删除进度提示
                              final messenger = ScaffoldMessenger.of(context);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '删除中（0/${_selected.length}）...',
                                  ),
                                ),
                              );
                              var okCount = 0;
                              var i = 0;
                              for (final t in _selected.toList()) {
                                final ok = await KlpbbsApi.deletePm(t);
                                if (ok) okCount++;
                                i++;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '删除中（$i/${_selected.length}）...',
                                    ),
                                  ),
                                );
                              }
                              if (!mounted) return;
                              setState(() {
                                _selectionMode = false;
                                _selected.clear();
                              });
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text('已删除 $okCount 个会话'),
                                    ],
                                  ),
                                ),
                              );
                              _reload();
                            },
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
