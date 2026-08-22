import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/preload_service.dart';
import '../models/horn_message.dart';
import '../widgets/inline_html_text.dart';
import '../pages/horn_post_page.dart';
import '../pages/thread_detail_page.dart';
import '../pages/user_space_page.dart';

/// 小喇叭（ahome_horn）：仿原版显示头像 + 用户名 + 内容 + 时间，可进主页/帖子
class HornBannerWidget extends StatefulWidget {
  final List<HornMessage>? initialMessages;

  const HornBannerWidget({super.key, this.initialMessages});

  @override
  State<HornBannerWidget> createState() => _HornBannerWidgetState();
}

class _HornBannerWidgetState extends State<HornBannerWidget> {
  List<HornMessage> _messages = const [];
  bool _loading = false;
  int? _myUid;

  @override
  void initState() {
    super.initState();
    KlpbbsApi.getMyUid().then((uid) {
      if (mounted) setState(() => _myUid = uid);
    }).catchError((_) {});

    // 优先读取内存缓存与传入参数，实现 0 延迟秒开渲染，避免布局跳变
    final cached = widget.initialMessages ??
        PreloadService.instance.get<List<HornMessage>>('horn_messages');
    if (cached != null && cached.isNotEmpty) {
      _messages = cached;
      _loading = false;
      _load(silent: true); // 后台静默刷新最新数据
    } else {
      _load(silent: false);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await KlpbbsApi.getHornMessages();
      if (list.isNotEmpty) {
        PreloadService.instance.set('horn_messages', list);
      }
      if (mounted) {
        setState(() {
          _messages = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openUserSpace(HornMessage m) {
    if (m.uid == null || m.uid! <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserSpacePage(uid: m.uid!)),
    );
  }

  void _openLink(HornMessage m) {
    if (m.linkUrl == null) return;
    final reg = RegExp(r'thread-(\d+)|tid=(\d+)').firstMatch(m.linkUrl!);
    if (reg != null) {
      final tid = int.tryParse(reg.group(1) ?? reg.group(2) ?? '');
      if (tid != null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: tid)),
        );
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading && _messages.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(40)),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(40)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: Row(
              children: [
                const Icon(Icons.campaign_rounded, size: 18, color: Color(0xFFFF9800)),
                const SizedBox(width: 6),
                Text(
                  '小喇叭',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HornPostPage()),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(
                      children: const [
                        Icon(Icons.edit_outlined, size: 14, color: Color(0xFF999999)),
                        SizedBox(width: 3),
                        Text('发布', style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _load(silent: false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 3),
                        Text('刷新', style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _messages.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: theme.colorScheme.outlineVariant.withAlpha(40),
              ),
              itemBuilder: (context, i) => _HornCard(
                message: _messages[i],
                canDelete: _myUid != null && (_messages[i].uid == _myUid || _myUid == 1),
                onAuthorTap: () => _openUserSpace(_messages[i]),
                onContentTap: () => _openLink(_messages[i]),
                onDelete: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('删除广播'),
                      content: const Text('确定要删除这条小喇叭广播吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('确认删除'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true || !context.mounted) return;
                  final target = _messages[i];
                  setState(() {
                    _messages.removeAt(i);
                  });
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await KlpbbsApi.deleteHorn(
                    target.id,
                    deleteUrl: target.deleteUrl,
                  );
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text(ok ? '小喇叭已删除' : '删除失败（未登录/无权限）')),
                  );
                  _load(silent: true);
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _HornCard extends StatelessWidget {
  final HornMessage message;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onContentTap;
  final bool canDelete;
  final VoidCallback? onDelete;

  const _HornCard({
    required this.message,
    this.onAuthorTap,
    this.onContentTap,
    this.canDelete = false,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onAuthorTap,
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: AppConfig.avatarUrl(message.uid ?? 0),
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 32,
                  height: 32,
                  color: theme.colorScheme.surfaceContainerHigh,
                  child: Center(
                    child: Text(
                      message.author.isNotEmpty
                          ? message.author.characters.first
                          : '播',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onAuthorTap,
                        child: Text(
                          message.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (message.timeText.isNotEmpty)
                      Text(
                        message.timeText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    if (canDelete)
                      GestureDetector(
                        onTap: onDelete,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.delete_outline_rounded,
                              size: 14, color: Colors.redAccent),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                GestureDetector(
                  onTap: onContentTap,
                  child: InlineHtmlText(
                    html: message.content,
                    baseStyle:
                        theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    emojiSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}