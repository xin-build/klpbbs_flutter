import '../widgets/app_motion.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/write_confirm.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../models/pm_models.dart';
import '../models/server_outage_info.dart';
import '../services/push_notification_service.dart';
import '../widgets/server_outage_view.dart';
import '../widgets/thread_card.dart';
import 'login_page.dart';
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
  final Set<int> _deletedTouids = {};
  final Set<int> _deletingTouids = {};
  final Map<int, String> _successfulDismissals = {};
  bool _batchDeleting = false;
  List<PmConversation> _allConvs = const [];
  int? _selectedTouid;
  String? _selectedUsername;

  @override
  void initState() {
    super.initState();
    _future = KlpbbsApi.getPmList();
    _future.ignore();
    DioClient.sessionChanges.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.instance.clearPm();
    });
    _loadRead();
    _loadPinned();
    _loadSearchHistory();
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _deletedTouids.clear();
      _deletingTouids.clear();
      _successfulDismissals.clear();
      _batchDeleting = false;
      _selected.clear();
      _selectionMode = false;
      _selectedTouid = null;
      _selectedUsername = null;
      _allConvs = const [];
      _future = KlpbbsApi.getPmList();
      _future.ignore();
    });
  }

  void _removeDeletedConversation(int touid) {
    setState(() {
      _deletedTouids.add(touid);
      _deletingTouids.remove(touid);
      _selected.remove(touid);
      if (_selectedTouid == touid) {
        _selectedTouid = null;
        _selectedUsername = null;
      }
    });
  }

  Future<bool> _deleteConversation(int touid,
      {bool removeImmediately = true, bool notifyFailure = true}) async {
    if (!mounted ||
        touid <= 0 ||
        _deletingTouids.contains(touid) ||
        _deletedTouids.contains(touid)) {
      return false;
    }
    final session = DioClient.sessionKey;
    setState(() => _deletingTouids.add(touid));
    var succeeded = false;
    try {
      succeeded = await KlpbbsApi.deletePm(touid);
      if (!mounted || session != DioClient.sessionKey) return false;
      if (!succeeded) {
        if (notifyFailure) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('删除失败，会话仍保留。')));
        }
        return false;
      }
      if (removeImmediately) {
        _removeDeletedConversation(touid);
      } else {
        // Dismissible stays mounted until its resize animation completes.
        _successfulDismissals[touid] = session;
      }
      return true;
    } catch (_) {
      if (mounted && session == DioClient.sessionKey && notifyFailure) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，会话仍保留。')));
      }
      return false;
    } finally {
      if (mounted &&
          session == DioClient.sessionKey &&
          (removeImmediately || !succeeded)) {
        setState(() => _deletingTouids.remove(touid));
      }
    }
  }

  Future<void> _loadRead() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _read =
          (prefs.getStringList('pm_read') ?? const []).map(int.parse).toSet();
      _unreadOverride = (prefs.getStringList('pm_unread_override') ?? const [])
          .map(int.parse)
          .toSet();
    });
  }

  Future<void> _loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
      () => _pinned =
          (prefs.getStringList('pm_pin') ?? const []).map(int.parse).toSet(),
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
    if (_deletingTouids.contains(c.touid) || _batchDeleting) {
      return;
    }
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
              key: ValueKey('pm-delete-menu-${c.touid}'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除会话'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final session = DioClient.sessionKey;
                final confirmed = await confirmWrite(context, '删除会话');
                if (!confirmed || !mounted || session != DioClient.sessionKey) {
                  return;
                }
                final ok = await _deleteConversation(c.touid);
                if (ok && mounted && session == DioClient.sessionKey) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('已删除会话')));
                  _reload();
                }
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
    PushNotificationService.instance.clearPm();
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
    if (!mounted) return;
    setState(() {
      _future = KlpbbsApi.getPmList();
      _future.ignore();
    });
  }

  Widget _buildSearchField() {
    return TextField(
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
    );
  }

  Widget _buildSearchHistoryChips() {
    return SizedBox(
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
    );
  }

  Widget _buildEmptyDetailPlaceholder(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Container(
      color: colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.surfaceContainerHighest.withAlpha(120),
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 52,
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '选择左侧会话开始聊天',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '与论坛好友随时畅聊，支持快捷短语与表情回复',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList({required bool isWide}) {
    if (!DioClient.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withAlpha(120),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '请先登录论坛账号',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '登录后即可查看与回复私信会话',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context)
                      .push(
                    MaterialPageRoute(
                      builder: (_) => const LoginPage(),
                    ),
                  )
                      .then((_) {
                    if (mounted) _reload();
                  });
                },
                icon: const Icon(Icons.login, size: 18),
                label: const Text('立即登录'),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<List<PmConversation>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: AppLoadingIndicator());
        }
        if (snap.hasError) {
          final outage = ServerOutageInfo.tryParse(snap.error);
          if (outage != null) {
            return ServerOutageView(
              outage: outage,
              onRetry: _reload,
            );
          }
          final isAuthError = snap.error.toString().contains('未登录') ||
              snap.error.toString().contains('过期');
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withAlpha(120),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isAuthError
                          ? Icons.lock_outline_rounded
                          : Icons.error_outline_rounded,
                      size: 32,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isAuthError ? '登录状态已失效' : '私信加载失败',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.outline),
                  ),
                  const SizedBox(height: 14),
                  if (isAuthError)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context)
                            .push(
                          MaterialPageRoute(
                            builder: (_) => const LoginPage(),
                          ),
                        )
                            .then((_) {
                          if (mounted) _reload();
                        });
                      },
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('重新登录'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重试'),
                    ),
                ],
              ),
            ),
          );
        }
        final rawAll = snap.data!;
        final all =
            rawAll.where((c) => !_deletedTouids.contains(c.touid)).toList();
        _allConvs = all;
        final filtered = _kw.isEmpty
            ? all
            : all
                .where(
                  (c) => c.username.contains(_kw) || c.summary.contains(_kw),
                )
                .toList();
        // 排序：置顶 > 未读 > 其余
        final list = [
          ...filtered.where((c) => _pinned.contains(c.touid)),
          ...filtered.where(
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

        // 宽屏模式下若未选会话且列表非空，自动选中首项
        if (isWide && _selectedTouid == null && list.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedTouid == null && list.isNotEmpty) {
              setState(() {
                _selectedTouid = list.first.touid;
                _selectedUsername = list.first.username;
              });
            }
          });
        }

        if (all.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withAlpha(120),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mail_outline_rounded,
                      size: 32,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '暂无私信会话',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '收到新私信后会在这里显示',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('刷新会话'),
                  ),
                ],
              ),
            ),
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
              final unread = (c.isNew && !_read.contains(c.touid)) ||
                  _unreadOverride.contains(c.touid);
              final isSelected = isWide && _selectedTouid == c.touid;
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
                  if (_batchDeleting || _deletingTouids.contains(c.touid)) {
                    return false;
                  }
                  final session = DioClient.sessionKey;
                  final confirmed = await confirmWrite(context, '删除会话');
                  if (!confirmed ||
                      !mounted ||
                      session != DioClient.sessionKey) {
                    return false;
                  }
                  return _deleteConversation(c.touid, removeImmediately: false);
                },
                onDismissed: (_) {
                  final session = _successfulDismissals.remove(c.touid);
                  if (!mounted || session != DioClient.sessionKey) return;
                  _removeDeletedConversation(c.touid);
                  _reload();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已删除会话')),
                  );
                },
                child: ListTile(
                  selected: isSelected,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withAlpha(70),
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
                                reserveFrameSpace: true,
                                uid: c.touid,
                                author: c.username,
                                size: 30,
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
                                  : (isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            children: _highlight(
                              c.username.isEmpty ? '用户${c.touid}' : c.username,
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
                            if (!isWide)
                              const Icon(Icons.chevron_right, size: 18),
                          ],
                        )
                      : null,
                  onTap: () {
                    if (_deletingTouids.contains(c.touid) || _batchDeleting) {
                      return;
                    }
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
                    if (isWide) {
                      setState(() {
                        _selectedTouid = c.touid;
                        _selectedUsername = c.username;
                      });
                    } else {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => PmDetailPage(
                                touid: c.touid,
                                toUsername: c.username,
                              ),
                            ),
                          )
                          .then((_) => _reload());
                    }
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
    );
  }

  Widget _buildBatchActionBar() {
    return SafeArea(
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
        child: Wrap(
          spacing: 4,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              key: const ValueKey('pm-select-all'),
              icon: const Icon(Icons.select_all, size: 18),
              label: const Text('全选'),
              onPressed: _batchDeleting
                  ? null
                  : () => setState(() {
                        _selected.isEmpty
                            ? _selected.addAll(_allConvs.map((c) => c.touid))
                            : _selected.clear();
                      }),
            ),
            TextButton.icon(
              icon: const Icon(Icons.push_pin_outlined, size: 18),
              label: const Text('置顶'),
              onPressed: _selected.isEmpty || _batchDeleting
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final prefs = await SharedPreferences.getInstance();
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
              onPressed: _selected.isEmpty || _batchDeleting
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final prefs = await SharedPreferences.getInstance();
                      final list = prefs.getStringList('pm_pin') ?? [];
                      list.removeWhere(
                        (x) => _selected.contains(int.tryParse(x) ?? -1),
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
            TextButton.icon(
              icon: const Icon(Icons.done_all, size: 18),
              label: Text('已读 (${_selected.length})'),
              onPressed: _selected.isEmpty || _batchDeleting
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final prefs = await SharedPreferences.getInstance();
                      final list = prefs.getStringList('pm_read') ?? [];
                      for (final t in _selected) {
                        if (!list.contains('$t')) list.add('$t');
                      }
                      await prefs.setStringList('pm_read', list);
                      final unreadList =
                          prefs.getStringList('pm_unread_override') ?? [];
                      unreadList.removeWhere(
                          (t) => _selected.contains(int.tryParse(t)));
                      await prefs.setStringList(
                          'pm_unread_override', unreadList);
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
            TextButton.icon(
              key: const ValueKey('pm-delete-selected'),
              icon: _batchDeleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: AppLoadingIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline, size: 18),
              label: Text('删除 (${_selected.length})'),
              onPressed: _selected.isEmpty || _batchDeleting
                  ? null
                  : () async {
                      final session = DioClient.sessionKey;
                      final toDelete = _selected.toList();
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('批量删除'),
                          content:
                              Text('确认删除选中的 ${toDelete.length} 个会话？此操作不可撤销。'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('取消')),
                            FilledButton(
                                key: const ValueKey(
                                    'pm-confirm-delete-selected'),
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('删除')),
                          ],
                        ),
                      );
                      if (confirmed != true ||
                          !mounted ||
                          session != DioClient.sessionKey ||
                          _batchDeleting) {
                        return;
                      }
                      if (!await confirmWrite(context, '批量删除会话') ||
                          !mounted ||
                          session != DioClient.sessionKey) {
                        return;
                      }
                      setState(() => _batchDeleting = true);
                      var okCount = 0;
                      try {
                        for (final uid in toDelete) {
                          if (!mounted || session != DioClient.sessionKey) {
                            return;
                          }
                          if (await _deleteConversation(uid,
                              notifyFailure: false)) {
                            okCount++;
                          }
                        }
                        if (!mounted || session != DioClient.sessionKey) return;
                        setState(() {
                          _selectionMode = _selected.isNotEmpty;
                        });
                        final failed = toDelete.length - okCount;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(failed == 0
                                ? '已删除 $okCount 个会话'
                                : '已删除 $okCount 个，$failed 个删除失败并保留。')));
                        _reload();
                      } finally {
                        if (mounted && session == DioClient.sessionKey) {
                          setState(() => _batchDeleting = false);
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideMasterDetail(
      BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final leftWidth =
        math.min(380.0, math.max(300.0, constraints.maxWidth * 0.35));

    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      body: Row(
        children: [
          SizedBox(
            width: leftWidth,
            child: Scaffold(
              appBar: AppBar(
                leading: const GlobalNavLeading(),
                leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
                title: const Text('私信'),
                actions: [
                  if (!_selectionMode)
                    IconButton(
                      icon: const Icon(Icons.done_all, size: 20),
                      tooltip: '全部已读',
                      onPressed: _markAllRead,
                    ),
                  IconButton(
                    key: const ValueKey('pm-toggle-management'),
                    icon: Icon(_selectionMode
                        ? Icons.close
                        : Icons.checklist_outlined),
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
                    child: _buildSearchField(),
                  ),
                ),
              ),
              body: Column(
                children: [
                  if (_kw.isEmpty && _searchHistory.isNotEmpty)
                    _buildSearchHistoryChips(),
                  Expanded(
                    child: _buildConversationList(isWide: true),
                  ),
                ],
              ),
              bottomNavigationBar:
                  _selectionMode ? _buildBatchActionBar() : null,
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
          Expanded(
            child: _selectedTouid != null && _selectedTouid! > 0
                ? PmDetailPage(
                    key: ValueKey('pm_detail_$_selectedTouid'),
                    touid: _selectedTouid!,
                    toUsername: _selectedUsername,
                    isEmbedded: true,
                    onMessageSent: _reload,
                  )
                : _buildEmptyDetailPlaceholder(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSinglePane(BuildContext context) {
    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('私信收件箱'),
        actions: [
          if (!_selectionMode)
            IconButton(
              icon: const Icon(Icons.done_all, size: 20),
              tooltip: '全部已读',
              onPressed: _markAllRead,
            ),
          IconButton(
            key: const ValueKey('pm-toggle-management'),
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _buildSearchField(),
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              if (_kw.isEmpty && _searchHistory.isNotEmpty)
                _buildSearchHistoryChips(),
              Expanded(
                child: _buildConversationList(isWide: false),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _selectionMode ? _buildBatchActionBar() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return _buildWideMasterDetail(context, constraints);
        }
        return _buildMobileSinglePane(context);
      },
    );
  }
}
