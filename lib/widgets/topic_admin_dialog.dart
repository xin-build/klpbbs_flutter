import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';

/// Discuz 主题管理操作弹窗（管理员 / 版主专用）
/// 支持：置顶、加精、高亮变色、锁定/开启、移动版块、盖图章、管理删帖
class TopicAdminDialog extends StatefulWidget {
  final int fid;
  final int tid;
  final String threadTitle;

  const TopicAdminDialog({
    super.key,
    required this.fid,
    required this.tid,
    required this.threadTitle,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int fid,
    required int tid,
    required String threadTitle,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TopicAdminDialog(
        fid: fid,
        tid: tid,
        threadTitle: threadTitle,
      ),
    );
  }

  @override
  State<TopicAdminDialog> createState() => _TopicAdminDialogState();
}

class _TopicAdminDialogState extends State<TopicAdminDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _reasonController =
      TextEditingController(text: '版主管理操作');
  bool _submitting = false;

  // 置顶选项：0=取消, 1=本版, 2=分区, 3=全局
  int _stickLevel = 1;

  // 加精选项：0=取消, 1=精华I, 2=精华II, 3=精华III
  int _digestLevel = 1;

  // 高亮选项
  String _highlightColor = '1';
  bool _highlightBold = true;
  bool _highlightItalic = false;
  bool _highlightUnderline = false;

  // 锁定选项
  bool _closeThread = true;

  // 移动目标 fid
  final TextEditingController _moveFidController = TextEditingController();

  // 图章编号 (0=撤销, 1~10)
  int _stampId = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reasonController.dispose();
    _moveFidController.dispose();
    super.dispose();
  }

  Future<void> _submitAction(String action) async {
    final reason = _reasonController.text.trim().isEmpty
        ? '版主管理操作'
        : _reasonController.text.trim();

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      ({bool success, String message}) res;
      switch (action) {
        case 'stick':
          res = await KlpbbsApi.moderateStickThread(
            fid: widget.fid,
            tid: widget.tid,
            stickLevel: _stickLevel,
            reason: reason,
          );
          break;
        case 'digest':
          res = await KlpbbsApi.moderateDigestThread(
            fid: widget.fid,
            tid: widget.tid,
            digestLevel: _digestLevel,
            reason: reason,
          );
          break;
        case 'highlight':
          res = await KlpbbsApi.moderateHighlightThread(
            fid: widget.fid,
            tid: widget.tid,
            color: _highlightColor,
            bold: _highlightBold,
            italic: _highlightItalic,
            underline: _highlightUnderline,
            reason: reason,
          );
          break;
        case 'close':
          res = await KlpbbsApi.moderateCloseThread(
            fid: widget.fid,
            tid: widget.tid,
            close: _closeThread,
            reason: reason,
          );
          break;
        case 'move':
          final targetFid = int.tryParse(_moveFidController.text.trim());
          if (targetFid == null || targetFid <= 0) {
            messenger.showSnackBar(
              const SnackBar(content: Text('请输入有效的目标版块 FID')),
            );
            setState(() => _submitting = false);
            return;
          }
          res = await KlpbbsApi.moderateMoveThread(
            fid: widget.fid,
            tid: widget.tid,
            targetFid: targetFid,
            reason: reason,
          );
          break;
        case 'stamp':
          res = await KlpbbsApi.moderateStampThread(
            fid: widget.fid,
            tid: widget.tid,
            stampId: _stampId,
            reason: reason,
          );
          break;
        case 'delete':
          res = await KlpbbsApi.moderateDeleteThread(
            fid: widget.fid,
            tid: widget.tid,
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
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          children: [
            // 顶栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  Icon(Icons.admin_panel_settings_rounded,
                      color: colorScheme.primary, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '主题管理 (TopicAdmin)',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.threadTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

            // Tab 切换
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              tabs: const [
                Tab(text: '置顶与加精'),
                Tab(text: '高亮变色'),
                Tab(text: '锁定与移动'),
                Tab(text: '盖图章'),
                Tab(text: '管理删帖'),
              ],
            ),

            // 内容区
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildStickAndDigestTab(colorScheme),
                  _buildHighlightTab(colorScheme),
                  _buildLockAndMoveTab(colorScheme),
                  _buildStampTab(colorScheme),
                  _buildDeleteTab(colorScheme),
                ],
              ),
            ),

            // 底部理由输入栏与状态
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant.withAlpha(50),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _reasonController,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: '管理理由 / 日志备注',
                      hintText: '输入操作原因，记录进版主日志',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (_submitting) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 置顶与加精 Tab
  Widget _buildStickAndDigestTab(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('置顶级别 (Stick)',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: colorScheme.primary)),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('取消')),
            ButtonSegment(value: 1, label: Text('本版')),
            ButtonSegment(value: 2, label: Text('分区')),
            ButtonSegment(value: 3, label: Text('全局')),
          ],
          selected: {_stickLevel},
          onSelectionChanged: (set) => setState(() => _stickLevel = set.first),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: _submitting ? null : () => _submitAction('stick'),
            icon: const Icon(Icons.vertical_align_top_rounded, size: 18),
            label: const Text('执行置顶变更'),
          ),
        ),
        const Divider(height: 32),
        Text('加精级别 (Digest)',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: colorScheme.primary)),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('取消')),
            ButtonSegment(value: 1, label: Text('精华 I')),
            ButtonSegment(value: 2, label: Text('精华 II')),
            ButtonSegment(value: 3, label: Text('精华 III')),
          ],
          selected: {_digestLevel},
          onSelectionChanged: (set) => setState(() => _digestLevel = set.first),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: _submitting ? null : () => _submitAction('digest'),
            icon: const Icon(Icons.star_rounded, size: 18),
            label: const Text('执行加精变更'),
          ),
        ),
      ],
    );
  }

  /// 高亮变色 Tab
  Widget _buildHighlightTab(ColorScheme colorScheme) {
    final colors = [
      ('1', '深红', const Color(0xFFEE1B2E)),
      ('2', '橙黄', const Color(0xFFEE5023)),
      ('3', '明黄', const Color(0xFF996600)),
      ('4', '翠绿', const Color(0xFF3C9D40)),
      ('5', '天青', const Color(0xFF2897C5)),
      ('6', '海蓝', const Color(0xFF2B65B7)),
      ('7', '深紫', const Color(0xFF8F2A90)),
      ('8', '神秘灰', const Color(0xFF666666)),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('选择高亮颜色',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: colorScheme.primary)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((c) {
            final isSel = _highlightColor == c.$1;
            return ChoiceChip(
              avatar: CircleAvatar(backgroundColor: c.$3, radius: 8),
              label: Text(c.$2),
              selected: isSel,
              onSelected: (_) => setState(() => _highlightColor = c.$1),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text('文字样式附加',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: colorScheme.primary)),
        CheckboxListTile(
          title: const Text('加粗 (Bold)'),
          value: _highlightBold,
          dense: true,
          onChanged: (v) => setState(() => _highlightBold = v ?? false),
        ),
        CheckboxListTile(
          title: const Text('斜体 (Italic)'),
          value: _highlightItalic,
          dense: true,
          onChanged: (v) => setState(() => _highlightItalic = v ?? false),
        ),
        CheckboxListTile(
          title: const Text('下划线 (Underline)'),
          value: _highlightUnderline,
          dense: true,
          onChanged: (v) => setState(() => _highlightUnderline = v ?? false),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _submitting ? null : () => _submitAction('highlight'),
          icon: const Icon(Icons.format_paint_rounded, size: 18),
          label: const Text('应用高亮'),
        ),
      ],
    );
  }

  /// 锁定与移动 Tab
  Widget _buildLockAndMoveTab(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('帖子锁定状态',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: colorScheme.primary)),
        const SizedBox(height: 8),
        SwitchListTile(
          title: Text(_closeThread ? '当前设定为：锁定（禁止任何人回复）' : '当前设定为：开启（允许正常回复）'),
          value: _closeThread,
          onChanged: (v) => setState(() => _closeThread = v),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: _submitting ? null : () => _submitAction('close'),
            icon: Icon(_closeThread ? Icons.lock_outline : Icons.lock_open,
                size: 18),
            label: Text(_closeThread ? '确认锁定主题' : '解除锁定'),
          ),
        ),
        const Divider(height: 32),
        Text('移动主题至其他版块',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: colorScheme.primary)),
        const SizedBox(height: 8),
        TextField(
          controller: _moveFidController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '目标版块 FID',
            hintText: '输入要移动到的目标版块 ID（如 2、38、45）',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: _submitting ? null : () => _submitAction('move'),
            icon: const Icon(Icons.drive_file_move_outlined, size: 18),
            label: const Text('执行移动'),
          ),
        ),
      ],
    );
  }

  /// 盖图章 Tab
  Widget _buildStampTab(ColorScheme colorScheme) {
    final stamps = [
      (0, '取消图章'),
      (1, '精华'),
      (2, '热帖'),
      (3, '置顶'),
      (4, '原创'),
      (5, '推荐'),
      (6, '优秀'),
      (7, '美图'),
      (8, '已解决'),
      (9, '锁定'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('选择图章标识 (Stamp)',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: colorScheme.primary)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: stamps.map((s) {
            final isSel = _stampId == s.$1;
            return ChoiceChip(
              label: Text(s.$2),
              selected: isSel,
              onSelected: (_) => setState(() => _stampId = s.$1),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _submitting ? null : () => _submitAction('stamp'),
          icon: const Icon(Icons.approval_rounded, size: 18),
          label: const Text('加盖/撤销图章'),
        ),
      ],
    );
  }

  /// 管理删帖 Tab
  Widget _buildDeleteTab(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withAlpha(80),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '警告：管理删帖将彻底删除该主题帖及所有楼层，并记录入版主后台操作日志。',
                  style: TextStyle(color: colorScheme.error, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: _submitting ? null : () => _submitAction('delete'),
          icon: const Icon(Icons.delete_forever_rounded, size: 18),
          label: const Text('确认管理删帖'),
        ),
      ],
    );
  }
}
