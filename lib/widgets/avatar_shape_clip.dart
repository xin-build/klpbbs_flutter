import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../core/app_config.dart';

/// The user's display preference clips the avatar, never its pendant layer.
/// Upload previews use this same shape without changing the uploaded pixels.
class AvatarShapeClip extends StatelessWidget {
  static final _frameScales = <AvatarShape, double>{};

  /// The website pendant has a circular opening. Enlarge its native artwork
  /// enough to enclose the selected outline, without clipping the avatar's
  /// corners or stretching the PNG. Calculated once for each display shape.
  static double frameOutlineScale(AvatarShape shape) =>
      _frameScales.putIfAbsent(shape, () {
        if (shape == AvatarShape.circle) return 1;
        if (shape == AvatarShape.roundedRect) {
          return 2 * (math.sqrt2 * .25 + .25);
        }
        final path = Path()
          ..addRSuperellipse(RSuperellipse.fromRectAndRadius(
              const Rect.fromLTWH(0, 0, 1, 1), const Radius.circular(.32)));
        var radius = .5;
        for (final metric in path.computeMetrics()) {
          for (var index = 0; index < 128; index++) {
            final point = metric
                .getTangentForOffset(metric.length * index / 128)
                ?.position;
            if (point != null) {
              radius =
                  math.max(radius, (point - const Offset(.5, .5)).distance);
            }
          }
        }
        return radius * 2 + .002;
      });
  final Widget child;
  final double size;
  final AvatarShape? shape;

  const AvatarShapeClip({
    super.key,
    required this.child,
    required this.size,
    this.shape,
  });

  @override
  Widget build(BuildContext context) => shape != null
      ? _clip(shape!)
      : ListenableBuilder(
          listenable: AppConfig.instance,
          builder: (context, _) => _clip(AppConfig.avatarShape));

  Widget _clip(AvatarShape selected) {
    const behavior = Clip.antiAlias;
    return SizedBox(
        width: size,
        height: size,
        child: switch (selected) {
          AvatarShape.circle => ClipOval(clipBehavior: behavior, child: child),
          AvatarShape.roundedRect => ClipRRect(
              clipBehavior: behavior,
              borderRadius: BorderRadius.circular(size * .25),
              child: child),
          AvatarShape.squircle => ClipRSuperellipse(
              clipBehavior: behavior,
              borderRadius: BorderRadius.circular(size * .32),
              child: child),
        });
  }
}

/// Legacy helper kept for existing saved-preview tooling; display shapes use
/// the round continuous corners above.
class AvatarHexagonClipper extends CustomClipper<Path> {
  const AvatarHexagonClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .25, 0)
    ..lineTo(size.width * .75, 0)
    ..lineTo(size.width, size.height * .5)
    ..lineTo(size.width * .75, size.height)
    ..lineTo(size.width * .25, size.height)
    ..lineTo(0, size.height * .5)
    ..close();

  @override
  bool shouldReclip(AvatarHexagonClipper oldClipper) => false;
}
