import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/cache_manager.dart';
import '../models/forum.dart';
import 'interactive_animations.dart';

/// Displays only children already declared by the current forum response.
/// The host owns expansion, fetching and navigation; this panel never loads.
class SubforumPanel extends StatelessWidget {
  final List<Forum> forums;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<Forum> onOpen;

  const SubforumPanel(
      {super.key,
      required this.forums,
      required this.collapsed,
      required this.onToggle,
      required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (forums.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                  key: const ValueKey('forum-children-toggle'),
                  onTap: onToggle,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(children: [
                        Icon(Icons.folder_copy_outlined,
                            color: scheme.primary, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text('子版块 · ${forums.length}',
                                style: Theme.of(context).textTheme.titleSmall)),
                        AnimatedExpandArrow(isCollapsed: collapsed, size: 24),
                      ]))),
              AnimatedCollapseSection(
                  isCollapsed: collapsed,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final largeText =
                            MediaQuery.textScalerOf(context).scale(14) > 20;
                        final columns = constraints.maxWidth >=
                                (largeText ? 1000 : 900)
                            ? 3
                            : constraints.maxWidth >= (largeText ? 640 : 540)
                                ? 2
                                : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 10) /
                                columns;
                        return Wrap(spacing: 10, runSpacing: 10, children: [
                          for (final forum in forums)
                            SizedBox(
                                width: width,
                                child: Material(
                                    color: scheme.surfaceContainerHighest
                                        .withAlpha(100),
                                    borderRadius: BorderRadius.circular(18),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                        key: ValueKey(
                                            'forum-child-${forum.fid}'),
                                        onTap: () => onOpen(forum),
                                        child: Padding(
                                            padding: const EdgeInsets.all(14),
                                            child: Row(children: [
                                              if (forum.iconUrl?.isNotEmpty ==
                                                  true)
                                                ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    child: CachedNetworkImage(
                                                        imageUrl:
                                                            forum.iconUrl!,
                                                        cacheManager:
                                                            KlpbbsCacheManager
                                                                .instance,
                                                        width: 40,
                                                        height: 40,
                                                        fit: BoxFit.contain,
                                                        errorWidget: (_, __,
                                                                ___) =>
                                                            Icon(
                                                                Icons
                                                                    .folder_outlined,
                                                                size: 32,
                                                                color: scheme
                                                                    .primary)))
                                              else
                                                Icon(Icons.folder_outlined,
                                                    size: 32,
                                                    color: scheme.primary),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    Text(forum.name,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleSmall),
                                                    if (forum.threadCount >=
                                                            0 ||
                                                        forum.topicCount >= 0 ||
                                                        forum.todayCount >=
                                                            0) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                          [
                                                            if (forum
                                                                    .topicCount >=
                                                                0)
                                                              '主题 ${forum.displayCount('topics')}',
                                                            if (forum
                                                                    .threadCount >=
                                                                0)
                                                              '帖数 ${forum.displayCount('posts')}',
                                                            if (forum
                                                                    .todayCount >=
                                                                0)
                                                              '今日 ${forum.displayCount('today')}',
                                                          ].join(' · '),
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall),
                                                    ],
                                                  ])),
                                              const SizedBox(width: 6),
                                              Icon(Icons.chevron_right_rounded,
                                                  size: 20,
                                                  color:
                                                      scheme.onSurfaceVariant),
                                            ]))))),
                        ]);
                      }))),
            ])));
  }
}
