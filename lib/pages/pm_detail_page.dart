import 'package:flutter/material.dart';

import 'user_space_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../api/klpbbs_api.dart';
import '../core/write_confirm.dart';
import '../widgets/thread_card.dart';
import '../models/pm_models.dart';
import '../widgets/app_back_button.dart';
import '../widgets/global_nav.dart';

/// 私信会话详情（消息列表 + 回复输入 + 在线状态显示）
class PmDetailPage extends StatefulWidget {
  final int touid;
  final String? toUsername;
  final bool? isOnline;
  final String? onlineStatusText;

  const PmDetailPage({
    super.key,
    required this.touid,
    this.toUsername,
    this.isOnline,
    this.onlineStatusText,
  });

  @override
  State<PmDetailPage> createState() => _PmDetailPageState();
}

class _PmDetailPageState extends State<PmDetailPage> {
  final _msgCtrl = TextEditingController();
  late Future<List<PmMessage>> _future;
  bool _sending = false;
  bool _showEmoji = false;
  String _toUsername = '';
  bool _isOnline = false;
  String _onlineStatusText = '';
  static const _emojis = [
    '😀',
    '😄',
    '😂',
    '🤣',
    '😊',
    '😍',
    '🤔',
    '😎',
    '😭',
    '😡',
    '👍',
    '👎',
    '👏',
    '🙏',
    '💪',
    '❤️',
    '🔥',
    '⭐',
    '🎉',
    '✨',
    '📌',
    '💡',
    '❓',
    '✅',
  ];

  @override
  void initState() {
    super.initState();
    _toUsername = widget.toUsername ?? '';
    _isOnline = widget.isOnline ?? false;
    _onlineStatusText = widget.onlineStatusText ?? (_isOnline ? '当前在线' : '');
    _future = KlpbbsApi.getPmDetail(widget.touid);
    _fetchTargetUserSpace();
    _restoreDraft();
    _msgCtrl.addListener(_saveDraft);
  }

  Future<void> _fetchTargetUserSpace() async {
    try {
      final user = await KlpbbsApi.getUserSpace(widget.touid);
      if (user != null && mounted) {
        setState(() {
          if (user.username.isNotEmpty && (_toUsername.isEmpty || _toUsername.startsWith('用户'))) {
            _toUsername = user.username;
          }
          _isOnline = user.isOnline;
          _onlineStatusText = user.onlineStatusText.isNotEmpty
              ? user.onlineStatusText
              : (user.isOnline ? '当前在线' : (user.lastvisit.isNotEmpty ? '最后访问: ${user.lastvisit}' : '离线'));
        });
      }
    } catch (_) {}
  }

  static const _draftKey = 'pm_draft';

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final t = _msgCtrl.text.trim();
    if (t.isEmpty) {
      await prefs.remove(_draftKey);
      return;
    }
    await prefs.setStringList(_draftKey, ['${widget.touid}', t]);
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getStringList(_draftKey) ?? const [];
    if (draft.length >= 2 && draft[0] == '${widget.touid}' && mounted) {
      _msgCtrl.text = draft[1];
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  void _reload() {
    setState(() => _future = KlpbbsApi.getPmDetail(widget.touid));
  }

  /// 提取日期（yyyy-MM-dd），无日期返回 ''
  String _dateOf(String t) {
    final m = RegExp(r'(\d{4}-\d{1,2}-\d{1,2})').firstMatch(t);
    return m?.group(1) ?? '';
  }

  /// 日期友好化：今天/昨天/MM月dd日
  String _friendlyDate(String t) {
    final d = _dateOf(t);
    if (d.isEmpty) return '';
    final parts = d.split('-');
    if (parts.length != 3) return d;
    final y = int.tryParse(parts[0]) ?? 0;
    final mo = int.tryParse(parts[1]) ?? 0;
    final day = int.tryParse(parts[2]) ?? 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(y, mo, day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (y == now.year) return '$mo月$day日';
    return '$y年$mo月$day日';
  }

  Future<void> _send() async {
    final content = _msgCtrl.text.trim();
    if (content.isEmpty) return;
    final confirmed = await confirmWrite(context, '发送私信');
    if (!confirmed || !mounted) return;
    setState(() => _sending = true);
    final ok = await KlpbbsApi.sendPm(widget.touid, content);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _msgCtrl.clear();
      _clearDraft();
      _reload();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('发送失败')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (_showEmoji) {
          setState(() => _showEmoji = false);
        } else {
          Navigator.of(context).maybePop();
        }
      },
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: FocusScope(
        child: Scaffold(
          appBar: AppBar(
            leading: const AppBackButton(),
            titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UserSpacePage(uid: widget.touid)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                UserAvatarWidget(
                  uid: widget.touid,
                  author: _toUsername,
                  size: 36,
                  isOnline: _isOnline,
                  showOnlineBadge: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _toUsername.isNotEmpty ? _toUsername : '私信会话',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      Row(
                        children: [
                          Container(
                            width: 6.5,
                            height: 6.5,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isOnline ? const Color(0xFF4CAF50) : const Color(0xFF9E9E9E),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              _isOnline
                                  ? '当前在线'
                                  : (_onlineStatusText.isNotEmpty ? _onlineStatusText : '离线'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: _isOnline
                                    ? const Color(0xFF4CAF50)
                                    : theme.colorScheme.outline,
                                fontWeight: _isOnline ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: const [GlobalNavButton()],
      ),
      body: FutureBuilder<List<PmMessage>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final msgs = snap.data!;
          return Column(
            children: [
              Expanded(
                child: msgs.isEmpty
                    ? const Center(child: Text('暂无消息'))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: msgs.length,
                        itemBuilder: (context, i) {
                          final m = msgs[msgs.length - 1 - i];
                          // 对方 uid 是 widget.touid；authorUid != touid 或 author == '您' 即当前用户所发
                          final isMe = (m.authorUid > 0 && widget.touid > 0 && m.authorUid != widget.touid) || m.author == '您';
                          // 日期分组头（今天/昨天/日期）
                          final prev = i > 0 ? msgs[msgs.length - i] : null;
                          final showDate =
                              prev == null ||
                              _dateOf(m.timeText) != _dateOf(prev.timeText);
                          return Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (showDate)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _friendlyDate(m.timeText),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: isMe
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    // 对方头像（左侧）
                                    if (!isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6,
                                        ),
                                        child: GestureDetector(
                                          onTap: () =>
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => UserSpacePage(
                                                    uid: widget.touid,
                                                  ),
                                                ),
                                              ),
                                          child: UserAvatarWidget(
                                            uid: m.authorUid,
                                            author: m.author,
                                            size: 28,
                                            faceUrl: m.faceUrl,
                                          ),
                                        ),
                                      ),
                                    Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 3,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 9,
                                      ),
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.of(context).size.width *
                                            0.75,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                        // 微信式不对称圆角
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(12),
                                          topRight: const Radius.circular(12),
                                          bottomLeft: Radius.circular(
                                            isMe ? 12 : 4,
                                          ),
                                          bottomRight: Radius.circular(
                                            isMe ? 4 : 12,
                                          ),
                                        ),
                                      ),
                                      child: GestureDetector(
                                        onLongPress: () {
                                          Clipboard.setData(
                                            ClipboardData(text: m.content),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('消息已复制'),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          m.content,
                                          style: const TextStyle(height: 1.4),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isMe && m.author.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 34),
                                  child: Text(
                                    m.author,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                ),
                              if (m.timeText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(text: m.timeText),
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(content: Text('时间已复制')),
                                      );
                                    },
                                    child: Text(
                                      m.timeText,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // emoji 面板
                    if (_showEmoji)
                      Container(
                        height: 110,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant.withAlpha(80),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: GridView.count(
                          crossAxisCount: 8,
                          children: [
                            for (final e in _emojis)
                              InkWell(
                                onTap: () {
                                  final t = _msgCtrl.text;
                                  _msgCtrl.text = '$t$e';
                                  _msgCtrl.selection = TextSelection.collapsed(
                                    offset: _msgCtrl.text.length,
                                  );
                                },
                                child: Center(
                                  child: Text(
                                    e,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    // 快捷语（动态快捷输入）
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (final phrase in const [
                            '你好 👋',
                            '在吗？',
                            '感谢分享！',
                            '好的，谢谢 👍',
                            '链接：',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: Text(
                                  phrase,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  final t = _msgCtrl.text;
                                  _msgCtrl.text = '$t$phrase ';
                                  _msgCtrl.selection = TextSelection.collapsed(
                                    offset: _msgCtrl.text.length,
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _msgCtrl,
                              autofocus: true,
                              decoration: const InputDecoration(
                                hintText: '输入消息...',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _showEmoji
                                  ? Icons.keyboard_alt_outlined
                                  : Icons.emoji_emotions_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _showEmoji = !_showEmoji),
                          ),
                          const SizedBox(width: 4),
                          IconButton.filled(
                            onPressed: _sending ? null : _send,
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
    ),
    );
  }
}
