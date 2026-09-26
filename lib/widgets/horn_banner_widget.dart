import 'dart:async';

import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/preload_service.dart';
import '../core/url_helper.dart';
import '../models/horn_message.dart';
import '../widgets/inline_html_text.dart';
import '../widgets/thread_card.dart';
import '../pages/horn_post_page.dart';
import '../pages/thread_detail_page.dart';
import '../pages/user_space_page.dart';
import 'tuhao_banner_widget.dart';

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
    final candidate = m.linkUrl ?? '';
    final reg = RegExp(r'thread-(\d+)|(?:mod=viewthread[^\s]*tid=|tid=)(\d+)').firstMatch(candidate);
    if (reg != null) {
      final tid = int.tryParse(reg.group(1) ?? reg.group(2) ?? '');
      if (tid != null && tid > 0) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: tid)),
        );
        return;
      }
    }

    // 若 linkUrl 为空，尝试从正文中提取包含的帖子地址
    if (candidate.isEmpty && m.content.isNotEmpty) {
      final contentReg = RegExp(r'thread-(\d+)|(?:mod=viewthread[^\s]*tid=|tid=)(\d+)').firstMatch(m.content);
      if (contentReg != null) {
        final tid = int.tryParse(contentReg.group(1) ?? contentReg.group(2) ?? '');
        if (tid != null && tid > 0) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: tid)),
          );
          return;
        }
      }
    }

    // 其他类型链接交由全局 UrlHelper 处理
    if (candidate.isNotEmpty) {
      UrlHelper.openLink(context, candidate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayMessages = _messages.where((m) => m.tag != '土豪').toList();

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 完美还原网页端：小喇叭容器顶部直接挂载土豪霸屏横幅（#ahorn_boss）
            const TuhaoBannerWidget(showStatsBar: false),
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
                        children: [
                          Icon(Icons.edit_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text('发布', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _loading ? null : () => _load(silent: false),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        children: [
                          if (_loading)
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          else
                            Icon(Icons.refresh_rounded, size: 14, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            _loading ? '刷新中' : '刷新',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading && displayMessages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withAlpha(160),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 90,
                            height: 11,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withAlpha(160),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            height: 12,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withAlpha(160),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else if (displayMessages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.campaign_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '暂无全站小喇叭广播，点击右上角发布一条吧~',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: displayMessages.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 14,
                    endIndent: 14,
                    color: theme.colorScheme.outlineVariant.withAlpha(40),
                  ),
                  itemBuilder: (context, i) => _HornCard(
                  message: displayMessages[i],
                  canDelete: _myUid != null && (displayMessages[i].uid == _myUid || _myUid == 1),
                  onAuthorTap: () => _openUserSpace(displayMessages[i]),
                  onContentTap: () => _openLink(displayMessages[i]),
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
                    final target = displayMessages[i];
                    setState(() {
                      _messages.removeWhere((m) => m.id == target.id && m.content == target.content);
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
          UserAvatarWidget(
            uid: message.uid,
            author: message.author,
            avatarUrl: message.avatarUrl,
            faceUrl: UserAvatarWidget.sanitizeFaceUrl(message.faceUrl),
            size: 34,
            onTap: onAuthorTap,
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