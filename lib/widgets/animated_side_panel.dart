import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'app_motion.dart';

/// Keep a panel at its natural width while its outer viewport opens/closes.
/// Width changes from a splitter remain immediate, and hidden content stops ticking.
class AnimatedSidePanel extends StatefulWidget {
  final bool expanded;
  final double width;
  final bool isLeft;
  final Widget child;
  final Widget splitter;
  final Widget handle;
  final double splitterWidth;
  final double collapsedWidth;

  const AnimatedSidePanel(
      {super.key,
      required this.expanded,
      required this.width,
      required this.isLeft,
      required this.child,
      required this.splitter,
      required this.handle,
      this.splitterWidth = 8,
      this.collapsedWidth = 26});

  @override
  State<AnimatedSidePanel> createState() => _AnimatedSidePanelState();
}

class _AnimatedSidePanelState extends State<AnimatedSidePanel> {
  bool _built = false;

  @override
  Widget build(BuildContext context) {
    _built = _built || widget.expanded;
    final naturalWidth = widget.width + widget.splitterWidth;
    final alignment =
        widget.isLeft ? Alignment.centerLeft : Alignment.centerRight;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.expanded ? 1 : 0),
      duration: AppMotion.duration(context, 320),
      curve: AppMotion.emphasized,
      builder: (context, progress, _) => SizedBox(
        width: lerpDouble(widget.collapsedWidth, naturalWidth, progress),
        child: ClipRect(
            child: Stack(fit: StackFit.expand, children: [
          if (_built)
            Offstage(
                offstage: progress == 0,
                child: OverflowBox(
                  alignment: alignment,
                  minWidth: naturalWidth,
                  maxWidth: naturalWidth,
                  child: IgnorePointer(
                      ignoring: !widget.expanded,
                      child: TickerMode(
                          enabled: widget.expanded,
                          child: Opacity(
                              opacity: progress,
                              child: Row(children: [
                                if (!widget.isLeft) widget.splitter,
                                SizedBox(
                                    width: widget.width,
                                    child:
                                        RepaintBoundary(child: widget.child)),
                                if (widget.isLeft) widget.splitter,
                              ])))),
                )),
          if (progress < 1)
            Align(
                alignment: alignment,
                child: IgnorePointer(
                    ignoring: widget.expanded,
                    child:
                        Opacity(opacity: 1 - progress, child: widget.handle))),
        ])),
      ),
    );
  }
}
