import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A searchable field has a labelled search action on desktop and a compact
/// touch action on mobile. Editing or clearing never refreshes its host page.
class ForumSearchField extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onSearch;
  final String hint;
  final bool compact;
  final Key? fieldKey;

  const ForumSearchField(
      {super.key,
      required this.controller,
      this.onSearch,
      this.hint = '搜索主题、资源与用户',
      this.compact = false,
      this.fieldKey});

  @override
  State<ForumSearchField> createState() => _ForumSearchFieldState();
}

class _ForumSearchFieldState extends State<ForumSearchField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) => SizedBox(
            height:
                math.max(48, MediaQuery.textScalerOf(context).scale(16) + 24),
            child: TextField(
              key: widget.fieldKey,
              controller: widget.controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted:
                  widget.onSearch == null ? null : (_) => widget.onSearch!(),
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                prefixIcon: widget.compact
                    ? IconButton(
                        tooltip: '搜索论坛',
                        onPressed: widget.onSearch,
                        icon: const Icon(Icons.search_rounded, size: 22))
                    : const Icon(Icons.search_rounded, size: 22),
                suffixIcon: value.text.isEmpty && widget.compact
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (value.text.isNotEmpty)
                            IconButton(
                                tooltip: '清空搜索',
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () {
                                  widget.controller.clear();
                                  _focus.requestFocus();
                                }),
                          if (!widget.compact)
                            TextButton(
                                onPressed: widget.onSearch,
                                child: const Text('搜索')),
                        ])),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(color: scheme.primary, width: 1.5)),
              ),
            )));
  }
}
