import 'package:flutter/material.dart';
import '../models/post_draft.dart';

/// Device-local drafts. The caller supplies operations for one captured owner.
class LocalDraftSheet extends StatefulWidget {
  final Future<List<PostDraft>> Function() read;
  final Future<bool> Function(PostDraft) remove;
  final Future<bool> Function(PostDraft) save;
  final Future<List<PostDraft>> Function() legacy;
  final Future<bool> Function(PostDraft) importLegacy;
  final Future<void> Function() saveCurrent;
  final bool Function(PostDraft) compatible;
  final void Function(PostDraft) restore;
  final Listenable sessionChanges;
  final bool Function() isCurrent;
  const LocalDraftSheet(
      {super.key,
      required this.read,
      required this.remove,
      required this.save,
      required this.legacy,
      required this.importLegacy,
      required this.saveCurrent,
      required this.compatible,
      required this.restore,
      required this.sessionChanges,
      required this.isCurrent});

  @override
  State<LocalDraftSheet> createState() => _LocalDraftSheetState();
}

class _LocalDraftSheetState extends State<LocalDraftSheet> {
  final _search = TextEditingController();
  List<PostDraft> _drafts = const [];
  String? _error;
  bool _loading = true;
  bool _busy = false;
  int _kind = 0;
  @override
  void initState() {
    super.initState();
    widget.sessionChanges.addListener(_sessionChanged);
    _refresh();
  }

  void _sessionChanged() {
    if (mounted && !widget.isCurrent()) setState(() => _drafts = const []);
  }

  @override
  void dispose() {
    widget.sessionChanges.removeListener(_sessionChanged);
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!widget.isCurrent()) return;
    try {
      final drafts = await widget.read();
      if (mounted && widget.isCurrent()) {
        setState(() {
          _drafts = drafts;
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '读取失败，原有草稿保留在本机';
          _loading = false;
        });
      }
    }
  }

  Future<void> _delete(PostDraft draft) async {
    if (_busy || !widget.isCurrent()) return;
    setState(() => _busy = true);
    bool removed = false;
    try {
      removed = await widget.remove(draft);
    } catch (_) {}
    if (!mounted || !widget.isCurrent()) return;
    setState(() => _busy = false);
    if (!removed) {
      setState(() => _error = '未能删除草稿，请重试');
      return;
    }
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('草稿已删除'),
      action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            if (!widget.isCurrent()) return;
            try {
              await widget.save(draft);
            } catch (_) {}
            if (mounted) await _refresh();
          }),
    ));
  }

  Future<void> _showLegacy() async {
    if (_busy || !widget.isCurrent()) return;
    final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('查看旧版未归属草稿'),
              content: const Text(
                  '旧版草稿没有账号标记，可能来自本机其他账号。确认是你的内容后，可逐份复制到当前账号。旧文件不会被删除。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('查看历史草稿'))
              ],
            ));
    if (open != true || !mounted || !widget.isCurrent()) return;
    List<PostDraft> legacy;
    try {
      legacy = await widget.legacy();
    } catch (_) {
      if (mounted) setState(() => _error = '旧版数据无法读取，原始文件已保留');
      return;
    }
    if (!mounted || !widget.isCurrent()) return;
    await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => AnimatedBuilder(
            animation: widget.sessionChanges,
            builder: (_, __) => !widget.isCurrent()
                ? const SizedBox(
                    height: 220, child: Center(child: Text('账号已切换，请重新打开草稿箱')))
                : SafeArea(
                    child: SizedBox(
                    height: MediaQuery.sizeOf(ctx).height * .65,
                    child: Column(children: [
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('旧版未归属草稿 · 逐份确认后导入')),
                      Expanded(
                          child: legacy.isEmpty
                              ? const Center(child: Text('没有旧版草稿'))
                              : ListView.builder(
                                  itemCount: legacy.length,
                                  itemBuilder: (_, index) {
                                    final draft = legacy[index];
                                    return ListTile(
                                        title: Text(
                                            draft.subject.isEmpty
                                                ? '无标题草稿'
                                                : draft.subject,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                        subtitle: Text(draft.content,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                        trailing: TextButton(
                                            onPressed: () async {
                                              if (!widget.isCurrent()) return;
                                              bool imported = false;
                                              try {
                                                imported = await widget
                                                    .importLegacy(draft);
                                              } catch (_) {}
                                              if (!ctx.mounted ||
                                                  !widget.isCurrent()) {
                                                return;
                                              }
                                              ScaffoldMessenger.of(ctx)
                                                  .showSnackBar(SnackBar(
                                                      content: Text(imported
                                                          ? '已复制到当前账号草稿箱，旧版原件保留'
                                                          : '导入失败，请检查本地存储或草稿数量')));
                                              if (mounted) await _refresh();
                                            },
                                            child: const Text('导入')));
                                  })),
                    ]),
                  ))));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCurrent()) {
      return const SafeArea(
          child: SizedBox(
              height: 220, child: Center(child: Text('账号已切换，请重新打开草稿箱'))));
    }
    final theme = Theme.of(context);
    final query = _search.text.trim().toLowerCase();
    final visible = _drafts
        .where((draft) =>
            (_kind == 0 ||
                (_kind == 1 && !draft.isReply && !draft.isEdit) ||
                (_kind == 2 && draft.isReply) ||
                (_kind == 3 && draft.isEdit)) &&
            (query.isEmpty ||
                '${draft.subject}\n${draft.content}\n${draft.forumName ?? ""}'
                    .toLowerCase()
                    .contains(query)))
        .toList();
    return SafeArea(
        child: ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .86),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('本地草稿箱', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('当前账号 · 仅保存在这台设备 · ${_drafts.length}/50',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    hintText: '搜索标题、正文或板块',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            }),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final item in [(0, '全部'), (1, '主题'), (2, '回复'), (3, '编辑')])
                ChoiceChip(
                    label: Text(item.$2),
                    selected: _kind == item.$1,
                    onSelected: (_) => setState(() => _kind = item.$1)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await widget.saveCurrent();
                          } finally {
                            if (mounted) {
                              setState(() => _busy = false);
                              await _refresh();
                            }
                          }
                        },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存当前')),
              TextButton.icon(
                  onPressed: _busy ? null : _showLegacy,
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('旧版草稿')),
            ]),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Expanded(
                        child: Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error))),
                    TextButton(onPressed: _refresh, child: const Text('重试'))
                  ])),
            const SizedBox(height: 8),
            Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : visible.isEmpty
                        ? Center(
                            child:
                                Text(query.isEmpty ? '这个分类还没有草稿' : '没有匹配的草稿'))
                        : ListView.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) {
                              final draft = visible[index];
                              final time = draft.updatedAt;
                              final timeText =
                                  '${time.month}/${time.day} ${time.hour.toString().padLeft(2, "0")}:${time.minute.toString().padLeft(2, "0")}';
                              return Card.filled(
                                  margin: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              draft.subject.isEmpty
                                                  ? '无标题草稿'
                                                  : draft.subject,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  theme.textTheme.titleSmall),
                                          const SizedBox(height: 4),
                                          Text(draft.content,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall),
                                          const SizedBox(height: 8),
                                          Text(
                                              '${draft.isEdit ? "编辑" : draft.isReply ? "回复 #${draft.tid ?? 0}" : draft.forumName ?? "主题"} · $timeText · ${draft.content.runes.length}字',
                                              style:
                                                  theme.textTheme.labelSmall),
                                          const SizedBox(height: 8),
                                          Wrap(
                                              spacing: 8,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                FilledButton.tonalIcon(
                                                    onPressed: !_busy &&
                                                            widget.compatible(
                                                                draft)
                                                        ? () => widget
                                                            .restore(draft)
                                                        : null,
                                                    icon: const Icon(
                                                        Icons
                                                            .restore_page_outlined,
                                                        size: 18),
                                                    label: const Text('载入')),
                                                IconButton(
                                                    onPressed: _busy
                                                        ? null
                                                        : () => _delete(draft),
                                                    icon: const Icon(Icons
                                                        .delete_outline_rounded),
                                                    tooltip: '删除草稿（可撤销）'),
                                                if (!widget.compatible(draft))
                                                  Text('请在对应帖子编辑器中载入',
                                                      style: theme
                                                          .textTheme.bodySmall),
                                              ]),
                                        ]),
                                  ));
                            })),
          ])),
    ));
  }
}
