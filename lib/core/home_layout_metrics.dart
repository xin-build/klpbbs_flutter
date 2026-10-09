import 'dart:math' as math;

/// 首页和画布页面预览共用的桌面分栏规则，尺寸均为逻辑像素。
class HomeLayoutMetrics {
  final bool showLeft;
  final bool showRight;
  final double leftWidth;
  final double rightWidth;
  final double centerWidth;

  const HomeLayoutMetrics._(this.showLeft, this.showRight, this.leftWidth,
      this.rightWidth, this.centerWidth);

  /// 同一张卡片在首页和页面预览中使用相同的实际高度。
  static double sidebarCardHeight({
    required String type,
    required int rows,
    required double width,
  }) {
    // The selected row span is the saved height, not a hint. Per-card minima
    // previously made 1/2/3-row cards identical after leaving the workshop.
    final effectiveRows = math.max(1, rows);
    return effectiveRows * 88.0 + (effectiveRows - 1) * 8.0;
  }

  factory HomeLayoutMetrics.calculate({
    required double width,
    required bool desktop,
    required bool leftEnabled,
    required bool rightEnabled,
    required double preferredLeft,
    required double preferredRight,
    double minimumCenterWidth = 620,
  }) {
    var showRight = desktop && width >= 850 && rightEnabled;
    var showLeft =
        desktop && width >= 850 && leftEnabled && (width >= 1150 || !showRight);
    final centerMinimum = minimumCenterWidth.isFinite
        ? minimumCenterWidth.clamp(400.0, 1000.0)
        : 620.0;
    // 限制侧栏前先折叠不适合当前窗口的列，避免强行保留两列后压缩正文。
    if (showLeft && showRight && width < centerMinimum + 360 + 16) {
      showLeft = false;
    }
    if ((showLeft || showRight) &&
        !(showLeft && showRight) &&
        width < centerMinimum + 180 + 8 + 26) {
      showLeft = false;
      showRight = false;
    }
    var left =
        preferredLeft.isFinite ? preferredLeft.clamp(180.0, 360.0) : 240.0;
    var right =
        preferredRight.isFinite ? preferredRight.clamp(180.0, 360.0) : 280.0;
    final edgeSpace =
        desktop ? (showLeft ? 0.0 : 26.0) + (showRight ? 0.0 : 26.0) : 0.0;
    final gutters = (showLeft ? 8.0 : 0.0) + (showRight ? 8.0 : 0.0);
    final sidebarSpace =
        math.max(0.0, width - centerMinimum - edgeSpace - gutters);
    if (showLeft && showRight && left + right > sidebarSpace) {
      final extra = left + right - 360;
      final scale = extra > 0 ? (sidebarSpace - 360) / extra : 0.0;
      left = 180 + (left - 180) * scale;
      right = 180 + (right - 180) * scale;
    } else if (showLeft) {
      left = math.min(left, sidebarSpace);
    } else if (showRight) {
      right = math.min(right, sidebarSpace);
    }
    final center = math.max(
        0.0,
        width -
            edgeSpace -
            gutters -
            (showLeft ? left : 0) -
            (showRight ? right : 0));
    return HomeLayoutMetrics._(showLeft, showRight, left, right, center);
  }
}
