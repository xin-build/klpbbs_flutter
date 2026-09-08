import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/klpbbs_api.dart';

/// Discuz 楼层回帖管理操作弹窗（管理员 / 版主专用）
/// 支持：屏蔽单楼 (banpost)、警告回帖 (warnpost)、删除单楼 (delpost)、查询真实发帖 IP (getip)
class FloorAdminDialog extends StatefulWidget {
  final int fid;
  final int tid;
  final int pid;
  final int floorIndex;
  final String author;
  final String snippet;
  final bool isBanned;
  final bool isWarned;

  const FloorAdminDialog({
    super.key,
    required this.fid,
    required this.tid,
    required this.pid,
    required this.floorIndex,
    required this.author,
    required this.snippet,
    this.isBanned = false,
    this.isWarned = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int fid,
    required int tid,
    required int pid,
    required int floorIndex,
    required String author,
    required String snippet,
    bool isBanned = false,
    bool isWarned = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FloorAdminDialog(
        fid: fid,
        tid: tid,
        pid: pid,
        floorIndex: floorIndex,
        author: author,
        snippet: snippet,
        isBanned: isBanned,
        isWarned: isWarned,
      ),
    );
  }

  @override
  State<FloorAdminDialog> createState() => _FloorAdminDialogState();
}

class _FloorAdminDialogState extends State<FloorAdminDialog> {
  final TextEditingController _reasonCtrl =
      TextEditingController(text: '版主管理楼层');
  bool _submitting = false;

  // IP 查询状态
  bool _queryingIp = false;
  String? _ipResult;
  String? _ipLocation;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _queryIp() async {
    setState(() {
      _queryingIp = true;
      _ipResult = null;
      _ipLocation = null;
    });
    try {
      final res = await KlpbbsApi.getFloorIp(
        fid: widget.fid,
        tid: widget.tid,
        pid: widget.pid,
      );
      if (mounted) {
        setState(() {
          _queryingIp = false;
          if (res.success) {
            _ipResult = res.ip;
            _ipLocation = res.location;
          } else {
            _ipResult = res.message;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _queryingIp = false;
          _ipResult = '查询失败：$e';
        });
      }
    }
  }

  Future<void> _executeAction(String action) async {
    final reason = _reasonCtrl.text.trim().isEmpty
        ? '版主管理楼层'
        : _reasonCtrl.text.trim();

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      ({bool success, String message}) res;
      switch (action) {
        case 'ban':
          res = await KlpbbsApi.moderateBanFloor(
            fid: widget.fid,
            tid: widget.tid,
            pid: widget.pid,
            banned: !widget.isBanned,
            reason: reason,
          );
          break;
        case 'warn':
          res = await KlpbbsApi.moderateWarnFloor(
            fid: widget.fid,
            tid: widget.tid,
            pid: widget.pid,
            warned: !widget.isWarned,
            reason: reason,
          );
          break;
        case 'delete':
          res = await KlpbbsApi.moderateDeleteFloor(
            fid: widget.fid,
            tid: widget.tid,
            pid: widget.pid,
            reason: reason,
          );
          break;
        default:
          res = (success: false, message: '未知操作');
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(res.success ? '操作成功：${res.message}' : '操作失败：${res.message}'),
        ),
      );

      if (res.success && mounted) {
        navigator.pop(true);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('管理操作异常：$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  Icon(Icons.shield_outlined,
                      color: colorScheme.primary, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '楼层管理 · ${widget.floorIndex + 1} 楼',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '发布者 @${widget.author} · PID ${widget.pid}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),

            // 楼层内容预览
            if (widget.snippet.isNotEmpty)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withAlpha(50),
                  ),
                ),
                child: Text(
                  widget.snippet,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),

            // 操作选项卡组
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // 屏蔽单楼
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      widget.isBanned
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: widget.isBanned ? Colors.orange : Colors.blueGrey,
                    ),
                    title: Text(widget.isBanned ? '解除屏蔽本楼' : '屏蔽此楼层内容'),
                    subtitle: Text(
                      widget.isBanned
                          ? '恢复此楼层内容的正常展示'
                          : '屏蔽后将以“提示: 该帖被管理员或版主屏蔽”显示',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed:
                          _submitting ? null : () => _executeAction('ban'),
                      child: Text(widget.isBanned ? '解屏蔽' : '屏蔽'),
                    ),
                  ),
                  const Divider(height: 1),

                  // 警告回帖
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.warning_amber_rounded,
                      color: widget.isWarned ? Colors.deepOrange : Colors.amber,
                    ),
                    title: Text(widget.isWarned ? '撤销警告' : '警告该回帖作者'),
                    subtitle: Text(
                      widget.isWarned
                          ? '撤销此前对该楼层作者的违规警告'
                          : '记一次警告并发送系统通知（多次警告将自动禁言）',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed:
                          _submitting ? null : () => _executeAction('warn'),
                      child: Text(widget.isWarned ? '撤警告' : '警告'),
                    ),
                  ),
                  const Divider(height: 1),

                  // 查询真实 IP
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.wifi_find_rounded,
                        color: Colors.teal),
                    title: const Text('查询真实发帖 IP'),
                    subtitle: _queryingIp
                        ? const Text('正在查询服务器日志...',
                            style: TextStyle(fontSize: 11))
                        : (_ipResult != null
                            ? SelectableText(
                                'IP: $_ipResult ${_ipLocation ?? ''}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              )
                            : const Text('获取发帖客户端原始 IP 与物理归属地',
                                style: TextStyle(fontSize: 11))),
                    trailing: _ipResult != null
                        ? IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: '复制 IP',
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: _ipResult!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制发帖 IP')),
                              );
                            },
                          )
                        : OutlinedButton(
                            onPressed: (_submitting || _queryingIp)
                                ? null
                                : _queryIp,
                            child: const Text('查IP'),
                          ),
                  ),
                  const Divider(height: 1),

                  // 删除单楼
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline,
                        color: colorScheme.error),
                    title: Text('删除该楼层回帖',
                        style: TextStyle(color: colorScheme.error)),
                    subtitle: const Text('永久删除此楼回复，此操作不可撤销',
                        style: TextStyle(fontSize: 11)),
                    trailing: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                      ),
                      onPressed: _submitting
                          ? null
                          : () => _executeAction('delete'),
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 操作理由
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _reasonCtrl,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: '管理删帖/屏蔽理由',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),

            if (_submitting) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
