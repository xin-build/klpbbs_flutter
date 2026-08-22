import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';

/// 苦力怕论坛 专属帖子/楼层举报弹窗（100% 还原 Discuz 原站举报规范）
class ReportDialog extends StatefulWidget {
  final int tid;
  final int pid;
  final String author;
  final int floorIndex;

  const ReportDialog({
    super.key,
    required this.tid,
    required this.pid,
    required this.author,
    this.floorIndex = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required int tid,
    required int pid,
    required String author,
    int floorIndex = 0,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ReportDialog(
        tid: tid,
        pid: pid,
        author: author,
        floorIndex: floorIndex,
      ),
    );
  }

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  static const _reasons = [
    ('广告垃圾', '垃圾营销、广告外链或商业推广'),
    ('违规内容', '有害信息、低俗色情、违反版规与国家法律法规'),
    ('恶意灌水', '纯表情、乱码复制、无意义刷屏或恶意抢楼'),
    ('重复发帖', '重复发布、未经许可搬运或侵犯他人版权'),
    ('辱骂攻击', '人身攻击、挑衅引战、不友善言论或诋毁他人'),
    ('其他原因', '其他违反苦力怕论坛社区规章的行为'),
  ];

  String _selectedReason = '广告垃圾';
  final _msgCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录论坛账号后再提交举报')),
      );
      return;
    }

    final detail = _msgCtrl.text.trim();
    final fullMessage = detail.isNotEmpty
        ? '[$_selectedReason] $detail'
        : _selectedReason;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      final ok = await KlpbbsApi.reportPost(
        widget.tid,
        widget.pid,
        fullMessage,
        reason: _selectedReason,
      );
      if (mounted) {
        nav.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(ok ? '已成功提交举报，感谢您维护论坛氛围！' : '提交举报失败（可能已被举报或无权限）'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        messenger.showSnackBar(SnackBar(content: Text('提交举报异常：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 渐变标题头
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withAlpha(50),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.flag_rounded, color: colorScheme.error, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '举报内容',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.floorIndex == 0
                                ? '举报主题帖 · 发布者 @${widget.author}'
                                : '举报 ${widget.floorIndex + 1} 楼 · 发布者 @${widget.author}',
                            style: TextStyle(fontSize: 12, color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // 举报原因选项列表
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '请选择违规类型：',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

              for (final (rTitle, rDesc) in _reasons)
                RadioListTile<String>(
                  value: rTitle,
                  groupValue: _selectedReason,
                  dense: true,
                  activeColor: colorScheme.error,
                  title: Text(
                    rTitle,
                    style: TextStyle(
                      fontWeight: _selectedReason == rTitle ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    rDesc,
                    style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
                  ),
                  onChanged: _submitting ? null : (v) => setState(() => _selectedReason = v ?? _selectedReason),
                ),

              const SizedBox(height: 6),

              // 详细补充说明输入框
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _msgCtrl,
                  maxLines: 3,
                  enabled: !_submitting,
                  decoration: InputDecoration(
                    hintText: '可在此填写具体违规说明或证据链接（选填）...',
                    hintStyle: TextStyle(fontSize: 12.5, color: colorScheme.outline),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withAlpha(50),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),

              const SizedBox(height: 16),

              // 底部动作栏
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                      ),
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(_submitting ? '提交中...' : '提交举报'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
