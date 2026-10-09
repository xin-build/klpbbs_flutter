import 'package:flutter/material.dart';
import 'app_motion.dart';

/// 两个独立的惰性列表按原索引分列，卡片按内容确定高度，无需预量整页。
class SliverTwoColumnFeed extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;
  const SliverTwoColumnFeed(
      {super.key,
      required this.itemCount,
      required this.itemBuilder,
      this.spacing = 12});

  @override
  Widget build(BuildContext context) => SliverCrossAxisGroup(slivers: [
        for (var column = 0; column < 2; column++)
          SliverCrossAxisExpanded(
            flex: 1,
            sliver: SliverPadding(
              padding: EdgeInsets.only(
                  left: column == 0 ? 0 : spacing / 2,
                  right: column == 0 ? spacing / 2 : 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final sourceIndex = index * 2 + column;
                    return Padding(
                      padding: EdgeInsets.only(bottom: spacing),
                      child: AppFadeIn(
                          index: sourceIndex,
                          child: itemBuilder(context, sourceIndex)),
                    );
                  },
                  childCount:
                      column == 0 ? (itemCount + 1) ~/ 2 : itemCount ~/ 2,
                  semanticIndexCallback: (_, index) => index * 2 + column,
                ),
              ),
            ),
          ),
      ]);
}
