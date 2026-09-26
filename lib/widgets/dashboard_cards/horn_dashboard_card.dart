import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../core/preload_service.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/horn_message.dart';
import '../../pages/horn_post_page.dart';
import '../../pages/thread_detail_page.dart';
import 'dashboard_card_frame.dart';

/// 6. 全站小喇叭跑马灯卡片（支持 GPU 隔离与 LOD 尺寸自适应）
class HornDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const HornDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<HornDashboardCard> createState() => _HornDashboardCardState();
}

class _HornDashboardCardState extends State<HornDashboardCard> {
  List<HornMessage> _messages = [];
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.isPreview) {
      final cached = PreloadService.instance.get<List<HornMessage>>('horn_messages');
      if (cached != null && cached.isNotEmpty) {
        _messages = cached;
      }
      _fetchMessages();
    }
  }

  Future<void> _fetchMessages() async {
    try {
      final list = await KlpbbsApi.getHornMessages();
      if (mounted && list.isNotEmpty) {
        setState(() {
          _messages = list;
        });
        _startTimer();
      }
    } catch (_) {}
  }

  void _startTimer() {
    _timer?.cancel();
    if (_messages.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % _messages.length;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleTap(HornMessage? msg) {
    if (msg == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HornPostPage()),
      );
      return;
    }
    if (msg.linkUrl != null) {
      final reg = RegExp(r'thread-(\d+)|tid=(\d+)').firstMatch(msg.linkUrl!);
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HornPostPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '全站小喇叭';

    final currentMsg = _messages.isNotEmpty ? _messages[_currentIndex] : null;

    final isMultiRow = widget.item.rowSpan >= 2;

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: isMultiRow ? 10 : 6),
        onTap: () => _handleTap(currentMsg),
        child: isMultiRow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.amber.withAlpha(30),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.campaign_rounded, size: 18, color: Colors.amber),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            title,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          if (_messages.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withAlpha(120),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_currentIndex + 1}/${_messages.length}',
                                style: TextStyle(fontSize: 10, color: colorScheme.outline),
                              ),
                            ),
                          const SizedBox(width: 6),
                          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: colorScheme.outline),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: widget.isPreview
                            ? Text(
                                '📢 [小喇叭] 欢迎来到苦力怕论坛！记得每日签到领取铁粒奖励，优质原创模组与资源火热征集中！',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, height: 1.4, color: colorScheme.onSurface),
                              )
                            : (currentMsg != null
                                ? AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: Column(
                                      key: ValueKey<int>(_currentIndex),
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (currentMsg.author.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 2),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (currentMsg.tag == '土豪')
                                                  Container(
                                                    margin: const EdgeInsets.only(right: 6),
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Colors.amber.shade700,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Text(
                                                      '💰 土豪霸屏',
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                Text(
                                                  '${currentMsg.author} 广播说：',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: currentMsg.tag == '土豪'
                                                        ? Colors.amber.shade900
                                                        : colorScheme.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            currentMsg.content
                                                .replaceAll(RegExp(r'<[^>]*>'), '')
                                                .replaceAll('&nbsp;', ' ')
                                                .trim(),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 12, height: 1.4, color: colorScheme.onSurface),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      '暂无最新广播消息，点击发布我的小喇叭',
                                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                                    ),
                                  )),
                      ),
                      if (currentMsg != null && currentMsg.timeText.isNotEmpty)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text(
                            currentMsg.timeText,
                            style: TextStyle(fontSize: 10, color: colorScheme.outline),
                          ),
                        ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.amber.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.campaign_rounded, size: 18, color: Colors.amber),
                      ),
                      const SizedBox(width: 8),
                      if (widget.item.colSpan > 4) ...[
                        Text(
                          title,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(width: 1, height: 16, color: colorScheme.outlineVariant.withAlpha(80)),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: widget.isPreview
                            ? Text(
                                '📢 [小喇叭] 欢迎来到苦力怕论坛！记得每日签到领取铁粒奖励！',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                              )
                            : (currentMsg != null
                                ? AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: Row(
                                      key: ValueKey<int>(_currentIndex),
                                      children: [
                                        if (currentMsg.tag == '土豪') ...[
                                          Container(
                                            margin: const EdgeInsets.only(right: 5),
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade700,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              '💰 土豪',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (currentMsg.author.isNotEmpty) ...[
                                          Text(
                                            '${currentMsg.author}: ',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: currentMsg.tag == '土豪'
                                                  ? Colors.amber.shade900
                                                  : colorScheme.primary,
                                            ),
                                          ),
                                        ],
                                        Expanded(
                                          child: Text(
                                            currentMsg.content
                                                .replaceAll(RegExp(r'<[^>]*>'), '')
                                                .replaceAll('&nbsp;', ' ')
                                                .trim(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                                          ),
                                        ),
                                        if (currentMsg.timeText.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text(
                                            currentMsg.timeText,
                                            style: TextStyle(fontSize: 10, color: colorScheme.outline),
                                          ),
                                        ],
                                      ],
                                    ),
                                  )
                                : Text(
                                    '暂无最新广播消息，点击发布',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                                  )),
                      ),
                    ],
                  ),
      ),
    );
  }
}
