import 'app_motion.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../pages/login_page.dart';

/// 苦力怕论坛 专属帖子自由收藏弹窗（支持自定义备注、标签分类、选择已有标签、取消收藏）
class FavoriteDialog extends StatefulWidget {
  final int tid;
  final String title;
  final String author;
  final bool isFavorited;
  final int? favid;
  final ValueChanged<bool>? onFavoritedChanged;

  const FavoriteDialog({
    super.key,
    required this.tid,
    required this.title,
    this.author = '',
    this.isFavorited = false,
    this.favid,
    this.onFavoritedChanged,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int tid,
    required String title,
    String author = '',
    bool isFavorited = false,
    int? favid,
    ValueChanged<bool>? onFavoritedChanged,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => FavoriteDialog(
        tid: tid,
        title: title,
        author: author,
        isFavorited: isFavorited,
        favid: favid,
        onFavoritedChanged: onFavoritedChanged,
      ),
    );
  }

  @override
  State<FavoriteDialog> createState() => _FavoriteDialogState();
}

class _FavoriteDialogState extends State<FavoriteDialog> {
  static const _defaultPresetTags = [
    '教程攻略',
    '模组插件',
    '材质光影',
    '皮肤装扮',
    '建筑存档',
    '精选推荐',
    '待看标记',
    '灵感交流',
  ];

  final _descCtrl = TextEditingController();
  final _tagInputCtrl = TextEditingController();
  final _selectedTags = <String>{};
  List<String> _userTags = [];
  bool _loadingTags = true;
  bool _supportsDescription = false;
  bool _supportsTags = false;
  String? _formError;
  bool _submitting = false;
  bool _expired = false;
  final String _sessionAtOpen = DioClient.sessionKey;

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_onSessionChanged);
    _loadUserTags();
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    _descCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _expired = true;
      _submitting = false;
    });
  }

  Future<void> _loadUserTags() async {
    if (widget.isFavorited) {
      _loadingTags = false;
      return;
    }
    try {
      final options = await KlpbbsApi.getThreadFavoriteOptions(widget.tid);
      final tags =
          options.tags ? await KlpbbsApi.getFavoriteTags() : const <String>[];
      if (!mounted || _sessionAtOpen != DioClient.sessionKey) return;
      setState(() {
        _supportsDescription = options.description;
        _supportsTags = options.tags;
        _userTags = tags;
        _loadingTags = false;
      });
    } catch (error) {
      if (!mounted || _sessionAtOpen != DioClient.sessionKey) return;
      setState(() {
        _formError = error.toString();
        _loadingTags = false;
      });
    }
  }

  void _addCustomTag() {
    final text = _tagInputCtrl.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _selectedTags.add(text);
        _tagInputCtrl.clear();
      });
    }
  }

  Future<void> _submitFavorite() => _submit(false);
  Future<void> _submitUnfavorite() => _submit(true);

  Future<void> _submit(bool remove) async {
    if (_submitting || _expired || _sessionAtOpen != DioClient.sessionKey) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (!DioClient.isLoggedIn) {
      final navigator = Navigator.of(context);
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: const Text('请先登录论坛账号后再进行收藏'),
        action: SnackBarAction(
            label: '去登录',
            onPressed: () => navigator
                .push(MaterialPageRoute(builder: (_) => const LoginPage()))),
      ));
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = remove
          ? await KlpbbsApi.unfavoriteThread(widget.tid, favid: widget.favid)
          : await KlpbbsApi.favoriteThread(widget.tid,
              description: _descCtrl.text.trim(),
              favtag: _selectedTags.join(' '));
      if (!mounted || _sessionAtOpen != DioClient.sessionKey) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      if (result.success) {
        widget.onFavoritedChanged?.call(!remove);
        Navigator.of(context).pop(!remove);
      }
    } catch (error) {
      if (!mounted || _sessionAtOpen != DioClient.sessionKey) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text('收藏操作失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allAvailableTags = <String>{
      ..._defaultPresetTags,
      ..._userTags,
      ..._selectedTags,
    }.toList();

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            widget.isFavorited ? Icons.star : Icons.star_border,
            color: Colors.amber.shade700,
            size: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.isFavorited ? '管理收藏' : '添加收藏',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_expired)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text('登录状态已改变，请关闭此窗口后重新操作',
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              // 帖子标题预览
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withAlpha(60),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title.isNotEmpty
                            ? widget.title
                            : '帖子 #${widget.tid}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (_loadingTags) const AppLoadingBar(),
              if (_formError != null)
                Text(_formError!,
                    style: TextStyle(color: theme.colorScheme.error)),
              if (widget.isFavorited) const Text('已收藏，可到收藏列表查看。'),
              if (_supportsTags) ...[
                // 收藏分类/标签选择
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '选择分类标签',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (_loadingTags)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: AppLoadingIndicator(strokeWidth: 1.5),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // 标签 Chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: allAvailableTags.map((tag) {
                    final isSelected = _selectedTags.contains(tag);
                    return FilterChip(
                      label: Text(tag),
                      selected: isSelected,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      selectedColor:
                          theme.colorScheme.primaryContainer.withAlpha(120),
                      backgroundColor: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(60),
                      checkmarkColor: theme.colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedTags.add(tag);
                          } else {
                            _selectedTags.remove(tag);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),

                // 自定义标签输入
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagInputCtrl,
                        decoration: InputDecoration(
                          hintText: '输入自定义标签...',
                          hintStyle: TextStyle(
                              fontSize: 12, color: theme.colorScheme.outline),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: theme.colorScheme.outlineVariant),
                          ),
                        ),
                        onSubmitted: (_) => _addCustomTag(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _addCustomTag,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('添加', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (_supportsDescription) ...[
                // 收藏备注输入框
                Text(
                  '收藏备注（可选）',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _descCtrl,
                  maxLines: 2,
                  maxLength: 100,
                  decoration: InputDecoration(
                    hintText: '记录备忘或心得（如：3楼有配置、优质教程）',
                    hintStyle: TextStyle(
                        fontSize: 12, color: theme.colorScheme.outline),
                    isDense: true,
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.isFavorited)
          TextButton.icon(
            onPressed: _submitting || _expired ? null : _submitUnfavorite,
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
            label: const Text('取消收藏',
                style: TextStyle(color: Colors.red, fontSize: 13)),
          ),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(fontSize: 13)),
        ),
        if (!widget.isFavorited)
          FilledButton.icon(
            onPressed:
                _submitting || _expired || _loadingTags || _formError != null
                    ? null
                    : _submitFavorite,
            icon: _submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: AppLoadingIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, size: 16),
            label: Text(
              '确认收藏',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}
