import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../core/dio_client.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/forum.dart';
import '../../pages/login_page.dart';
import '../../pages/post_page.dart';
import '../../pages/thread_detail_page.dart';
import 'dashboard_card_frame.dart';

/// 1 & 2. 快捷发帖与快捷回复仪表盘卡片（支持 GPU 隔离与高适应性 LOD 尺寸响应）
class QuickPostDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;
  final bool isReplyMode;

  const QuickPostDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
    this.isReplyMode = false,
  });

  @override
  State<QuickPostDashboardCard> createState() => _QuickPostDashboardCardState();
}

class _QuickPostDashboardCardState extends State<QuickPostDashboardCard> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  int _selectedFid = 41; // 默认闲聊讨论
  bool _submitting = false;
  List<Forum> _dynamicForums = const [];

  static const List<({int fid, String name})> _defaultForums = [
    (fid: 41, name: '闲聊讨论'),
    (fid: 52, name: 'BE附加包'),
    (fid: 140, name: 'JE模组'),
    (fid: 51, name: 'BE地图'),
    (fid: 53, name: 'BE材质光影'),
    (fid: 68, name: '悬赏问答'),
    (fid: 44, name: '编程分享'),
    (fid: 111, name: '周边创作'),
  ];

  static const List<String> _quickSmileys = ['😊', '👍', '🔥', '🎉', '👏', '⛏️', '💎', '❤️'];

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _contentCtrl = TextEditingController();
    final customFid = widget.item.customParams['targetFid'];
    if (customFid is num && customFid > 0) {
      _selectedFid = customFid.toInt();
    }
    _loadForums();
  }

  void _loadForums() {
    KlpbbsApi.getForums().then((forums) {
      if (mounted && forums.isNotEmpty) {
        setState(() {
          _dynamicForums = forums.where((f) => f.fid > 0 && f.name.isNotEmpty).toList();
        });
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _insertSmiley(String sm) {
    final text = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    if (sel.isValid) {
      final newText = text.replaceRange(sel.start, sel.end, sm);
      _contentCtrl.value = _contentCtrl.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + sm.length),
      );
    } else {
      _contentCtrl.text += sm;
    }
  }

  void _openFullEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostPage(
          fid: _selectedFid,
          editSubject: _titleCtrl.text.isNotEmpty ? _titleCtrl.text : null,
          initialMessage: _contentCtrl.text.isNotEmpty ? _contentCtrl.text : null,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (widget.isPreview) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前为编辑预览模式，固定数据已展示')),
      );
      return;
    }

    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先登录论坛账号后再发送'),
          action: SnackBarAction(
            label: '去登录',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
          ),
        ),
      );
      return;
    }

    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入内容后再提交')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      if (widget.isReplyMode) {
        // 回复模式 (若关联了 tid)
        final targetTid = (widget.item.customParams['targetTid'] as num?)?.toInt() ?? 0;
        if (targetTid > 0) {
          final success = await KlpbbsApi.replyThread(targetTid, content);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success ? '回复成功！' : '回复失败，请检查网络或登录状态'),
                action: success
                    ? SnackBarAction(
                        label: '查看帖子',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: targetTid)),
                        ),
                      )
                    : null,
              ),
            );
            if (success) _contentCtrl.clear();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('未绑定目标帖子，无法快捷回复')),
            );
          }
        }
      } else {
        // 发帖模式：若标题为空（如单行紧凑模式），自动提取正文首行作为有效标题，绝不阻断用户发帖
        var title = _titleCtrl.text.trim();
        if (title.isEmpty) {
          final clean = content.replaceAll(RegExp(r'\s+'), ' ').trim();
          title = clean.length > 25 ? '${clean.substring(0, 25)}...' : clean;
        }
        if (title.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请输入标题或内容后再发帖')),
          );
          setState(() => _submitting = false);
          return;
        }

        final newTid = await KlpbbsApi.postThread(_selectedFid, title, content);
        final success = newTid != null && newTid > 0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? '发帖成功！' : '发帖失败，请检查网络或登录状态'),
              action: success
                  ? SnackBarAction(
                      label: '查看帖子',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: newTid)),
                      ),
                    )
                  : null,
            ),
          );
          if (success) {
            _titleCtrl.clear();
            _contentCtrl.clear();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送异常: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty)
        ? customTitle
        : (widget.isReplyMode ? '快捷回复' : '快捷发帖');

    // 未登录友好占位视图
    if (!widget.isPreview && !DioClient.isLoggedIn) {
      return RepaintBoundary(
        child: DashboardCardFrame(
          item: widget.item,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isReplyMode ? Icons.reply_rounded : Icons.post_add_rounded,
                  size: 26,
                  color: colorScheme.primary.withAlpha(180),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.isReplyMode ? '登录后即可快捷回复' : '登录后即可快捷发帖',
                  style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
                ),
                const SizedBox(height: 6),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ),
                  child: const Text('去登录', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 采用 RepaintBoundary 开启 GPU 硬件光栅化隔离层
    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.maxHeight;
            final isCompact = maxHeight < 80 || widget.item.rowSpan <= 1;
            final isNarrow = constraints.maxWidth < 280 || widget.item.colSpan <= 3;

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 8 : 12,
                vertical: isCompact ? 6 : 8,
              ),
              child: isCompact
                  ? _buildCompactLayout(context, isNarrow: isNarrow)
                  : _buildExpandedLayout(
                      context,
                      isNarrow: isNarrow,
                      title: title,
                      availableHeight: maxHeight,
                    ),
            );
          },
        ),
      ),
    );
  }

  /// LOD 极简单行模式 (缩放较小时自动折叠)
  Widget _buildCompactLayout(BuildContext context, {required bool isNarrow}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          widget.isReplyMode ? Icons.reply_rounded : Icons.post_add_rounded,
          size: 18,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _contentCtrl,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.isPreview
                  ? '预览：输入内容一键互动...'
                  : (widget.isReplyMode ? '快捷发表回复...' : '快捷发布动态 (回车直接发)...'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        if (!isNarrow && !widget.isReplyMode) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: '打开完整发帖编辑器',
            icon: Icon(Icons.open_in_new_rounded, size: 16, color: colorScheme.outline),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: _openFullEditor,
          ),
        ],
        const SizedBox(width: 6),
        FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('发送', style: TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }

  /// LOD 展开多功能模式（高度适配各种 rowSpan 与屏幕尺寸）
  Widget _buildExpandedLayout(
    BuildContext context, {
    required bool isNarrow,
    required String title,
    required double availableHeight,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTight = availableHeight < 210;

    // 提取版块选项（优先动态版块，其次默认版块）
    final forumItems = _dynamicForums.isNotEmpty
        ? _dynamicForums.map((f) => (fid: f.fid, name: f.name)).toList()
        : _defaultForums;

    final currentFidValid = forumItems.any((f) => f.fid == _selectedFid);
    final effectiveFid = currentFidValid
        ? _selectedFid
        : (forumItems.isNotEmpty ? forumItems.first.fid : 41);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶栏：标题与版块选择
        Row(
          children: [
            Icon(
              widget.isReplyMode ? Icons.reply_rounded : Icons.create_rounded,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (!widget.isReplyMode) ...[
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: effectiveFid,
                    isDense: true,
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
                    items: forumItems.take(15).map((f) {
                      return DropdownMenuItem(
                        value: f.fid,
                        child: Text(
                          f.name.length > 7 ? '${f.name.substring(0, 7)}...' : f.name,
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => v != null ? setState(() => _selectedFid = v) : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '打开完整发帖编辑器',
                icon: Icon(Icons.open_in_new_rounded, size: 15, color: colorScheme.outline),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: _openFullEditor,
              ),
            ],
          ],
        ),
        SizedBox(height: isTight ? 4 : 6),

        // 标题输入框 (非回复模式下展示)
        if (!widget.isReplyMode) ...[
          SizedBox(
            height: isTight ? 30 : 34,
            child: TextField(
              controller: _titleCtrl,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: widget.isPreview ? '固定演示：苦力怕论坛自由网格工作台体验' : '输入帖子标题 (可留空自动提取)...',
                hintStyle: TextStyle(fontSize: 11, color: colorScheme.outline.withAlpha(160)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
                ),
              ),
            ),
          ),
          SizedBox(height: isTight ? 4 : 6),
        ],

        // 内容输入区（自适应充满剩余空间，零溢出风险）
        Expanded(
          child: TextField(
            controller: _contentCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: widget.isPreview
                  ? '固定演示：已启用 GPU 光栅化渲染与全自适应网格画布，点击发送可测试联动！'
                  : '随时记录您的想法、灵感或问题...',
              hintStyle: TextStyle(fontSize: 11, color: colorScheme.outline.withAlpha(160)),
              isDense: true,
              contentPadding: const EdgeInsets.all(8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
              ),
            ),
          ),
        ),
        SizedBox(height: isTight ? 4 : 6),

        // 底栏：快捷表情与提交按钮
        Row(
          children: [
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final sm in _quickSmileys)
                      InkWell(
                        onTap: () => _insertSmiley(sm),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                          child: Text(sm, style: const TextStyle(fontSize: 15)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, size: 13),
              label: Text(_submitting ? '发布中' : '发布', style: const TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
      ],
    );
  }
}
