import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/post_copy_document.dart';

Future<void> showPostCopySheet(BuildContext context,
        {required String html, required String title}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 800),
      builder: (_) => PostCopySheet(html: html, title: title),
    );

class PostCopySheet extends StatefulWidget {
  final String html;
  final String title;
  const PostCopySheet({super.key, required this.html, required this.title});
  @override
  State<PostCopySheet> createState() => _PostCopySheetState();
}

class _PostCopySheetState extends State<PostCopySheet> {
  late PostCopyDocument _document;
  TextSelection _selection = const TextSelection.collapsed(offset: 0);
  final Set<int> _chosen = {};
  bool _paragraphMode = false;
  bool _links = false;
  @override
  void initState() {
    super.initState();
    _document = PostCopyDocument.fromHtml(widget.html);
  }

  String get _selectedText {
    if (_paragraphMode) {
      final sorted = _chosen.toList()..sort();
      return sorted.map((index) => _document.paragraphs[index]).join('\n\n');
    }
    final text = _document.plainText;
    if (!_selection.isValid ||
        _selection.isCollapsed ||
        _selection.start < 0 ||
        _selection.end > text.length) {
      return '';
    }
    return text.substring(_selection.start, _selection.end);
  }

  Future<void> _copy(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制 ${text.runes.length} 个字符')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _document.plainText;
    return SafeArea(
        child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .84,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('仅包含网页已返回的正文文字；长按或拖动选择，也可按段组合。',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, children: [
              ChoiceChip(
                  label: const Text('自由选字'),
                  selected: !_paragraphMode,
                  onSelected: (_) => setState(() => _paragraphMode = false)),
              ChoiceChip(
                  label: const Text('按段选择'),
                  selected: _paragraphMode,
                  onSelected: (_) => setState(() => _paragraphMode = true)),
              FilterChip(
                  label: const Text('附带链接地址'),
                  selected: _links,
                  onSelected: (value) => setState(() {
                        _links = value;
                        _document = PostCopyDocument.fromHtml(widget.html,
                            includeLinkTargets: value);
                        _selection = const TextSelection.collapsed(offset: 0);
                        _chosen.clear();
                      })),
            ]),
            const SizedBox(height: 10),
            if (_paragraphMode)
              Wrap(spacing: 8, children: [
                TextButton.icon(
                    onPressed: () => setState(() {
                          _chosen.addAll(List.generate(
                              _document.paragraphs.length, (index) => index));
                        }),
                    icon: const Icon(Icons.select_all),
                    label: const Text('选中全部段落')),
                TextButton(
                    onPressed: () => setState(() => _chosen.clear()),
                    child: const Text('清空选择')),
              ]),
            Expanded(
                child: text.isEmpty
                    ? const Center(child: Text('这个楼层没有可复制的文字'))
                    : _paragraphMode
                        ? ListView.separated(
                            itemCount: _document.paragraphs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) => Card.filled(
                                margin: EdgeInsets.zero,
                                child: CheckboxListTile(
                                  value: _chosen.contains(index),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: Text(_document.paragraphs[index],
                                      style: theme.textTheme.bodyMedium),
                                  onChanged: (value) => setState(() {
                                    if (value == true) {
                                      _chosen.add(index);
                                    } else {
                                      _chosen.remove(index);
                                    }
                                  }),
                                )))
                        : SingleChildScrollView(
                            child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: SelectableText(text,
                                key: ValueKey(_links),
                                onSelectionChanged: (selection, cause) =>
                                    setState(() => _selection = selection),
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(height: 1.6)),
                          ))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                  key: const ValueKey('post-copy-selected'),
                  onPressed:
                      _selectedText.isEmpty ? null : () => _copy(_selectedText),
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(
                      _paragraphMode ? '复制所选 ${_chosen.length} 段' : '复制所选文字')),
              OutlinedButton.icon(
                  onPressed: text.isEmpty ? null : () => _copy(text),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('复制全部正文')),
            ]),
          ])),
    ));
  }
}
