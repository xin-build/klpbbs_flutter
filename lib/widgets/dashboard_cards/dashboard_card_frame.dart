import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';

/// 卡片质感风格预设
enum DashboardCardStyle {
  modern('Material 柔和', Icons.auto_awesome_rounded, '柔和的主题容器与圆角'),
  gradient('主题渐变', Icons.gradient_rounded, '轻柔的双色渐变背景'),
  glass('半透明层次', Icons.opacity_rounded, '半透明的主题底色'),
  creeper('苦力怕工坊', Icons.grid_view_rounded, '绿色强调与清晰轮廓'),
  minimal('简洁描边', Icons.crop_square_rounded, '纯净底色与细描边'),
  elevated('悬浮层次', Icons.layers_rounded, '适度阴影的高层级卡片');

  final String label;
  final IconData icon;
  final String description;

  const DashboardCardStyle(this.label, this.icon, this.description);

  static DashboardCardStyle fromString(String? key) {
    if (key == null) return DashboardCardStyle.modern;
    for (final s in DashboardCardStyle.values) {
      if (s.name == key) return s;
    }
    return DashboardCardStyle.modern;
  }
}

/// 卡片主题强调色
enum DashboardCardAccent {
  auto('智能匹配', null, null),
  sakura('樱花粉', Color(0xFFFA7298), Color(0xFFFF80AB)),
  emerald('苦力怕绿', Color(0xFF2E7D32), Color(0xFF4CAF50)),
  blue('钻石天蓝', Color(0xFF1565C0), Color(0xFF42A5F5)),
  amber('金粒耀金', Color(0xFFE65100), Color(0xFFFFB300)),
  purple('末影幻紫', Color(0xFF6A1B9A), Color(0xFFAB47BC)),
  coral('熔岩赤红', Color(0xFFC62828), Color(0xFFFF5252)),
  teal('潮涌幽青', Color(0xFF00695C), Color(0xFF26A69A)),
  indigo('星界深蓝', Color(0xFF283593), Color(0xFF5C6BC0));

  final String label;
  final Color? colorLight;
  final Color? colorDark;

  const DashboardCardAccent(this.label, this.colorLight, this.colorDark);

  Color resolve(BuildContext context, {Color? fallback}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (this == DashboardCardAccent.auto ||
        colorLight == null ||
        colorDark == null) {
      return fallback ?? Theme.of(context).colorScheme.primary;
    }
    return isDark ? colorDark! : colorLight!;
  }

  static DashboardCardAccent fromString(String? key) {
    if (key == null) return DashboardCardAccent.auto;
    for (final a in DashboardCardAccent.values) {
      if (a.name == key) return a;
    }
    return DashboardCardAccent.auto;
  }
}

/// 卡片主题数据环境
class DashboardCardThemeData {
  final DashboardCardStyle style;
  final Color accentColor;
  final bool isDark;

  const DashboardCardThemeData({
    required this.style,
    required this.accentColor,
    required this.isDark,
  });
}

/// 卡片主题继承组件（子组件可通过它读取卡片当前强调色和风格）
class DashboardCardTheme extends InheritedWidget {
  final DashboardCardThemeData data;

  const DashboardCardTheme({
    super.key,
    required this.data,
    required super.child,
  });

  static DashboardCardThemeData of(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<DashboardCardTheme>();
    if (inherited != null) return inherited.data;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DashboardCardThemeData(
      style: DashboardCardStyle.modern,
      accentColor: Theme.of(context).colorScheme.primary,
      isDark: isDark,
    );
  }

  @override
  bool updateShouldNotify(DashboardCardTheme oldWidget) =>
      data.style != oldWidget.data.style ||
      data.accentColor != oldWidget.data.accentColor ||
      data.isDark != oldWidget.data.isDark;
}

/// 全站统一网格仪表盘卡片外框容器
/// 风格预设在首页与画布中共用，不为半透明效果引入逐帧背景模糊。
class DashboardCardFrame extends StatelessWidget {
  final DashboardGridItem item;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool showAccentIndicator;
  final VoidCallback? onTap;

  const DashboardCardFrame({
    super.key,
    required this.item,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 24,
    this.showAccentIndicator = true,
    this.onTap,
  });

  /// 使用主题色对应卡片分类。
  static Color getNaturalCategoryAccent(String cardType, BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final def = CardRegistry.get(cardType);
    switch (def.category) {
      case DashboardCardCategory.user:
      case DashboardCardCategory.social:
        return colorScheme.primary;
      case DashboardCardCategory.content:
        return colorScheme.tertiary;
      case DashboardCardCategory.stats:
        return colorScheme.secondary;
      case DashboardCardCategory.tool:
        return colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final styleKey = item.customParams['cardStyle'] as String?;
    final accentKey = item.customParams['cardAccent'] as String?;

    final style = DashboardCardStyle.fromString(styleKey);
    final accentEnum = DashboardCardAccent.fromString(accentKey);
    final naturalAccent = getNaturalCategoryAccent(item.cardType, context);
    final accentColor = accentEnum.resolve(context, fallback: naturalAccent);

    final themeData = DashboardCardThemeData(
      style: style,
      accentColor: accentColor,
      isDark: isDark,
    );

    final base = switch (style) {
      DashboardCardStyle.glass => colorScheme.surfaceContainer.withAlpha(210),
      DashboardCardStyle.creeper => Color.alphaBlend(
          const Color(0xFF4CAF50).withAlpha(isDark ? 15 : 9),
          colorScheme.surfaceContainerLow),
      DashboardCardStyle.minimal => colorScheme.surface,
      DashboardCardStyle.elevated => colorScheme.surfaceContainerHigh,
      _ => colorScheme.surfaceContainerLow,
    };
    final border = switch (style) {
      DashboardCardStyle.minimal => colorScheme.outlineVariant.withAlpha(160),
      DashboardCardStyle.creeper => const Color(0xFF4CAF50).withAlpha(75),
      DashboardCardStyle.glass => colorScheme.outlineVariant.withAlpha(65),
      _ => Colors.transparent,
    };
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      color: base,
      gradient: style == DashboardCardStyle.gradient
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                  Color.alphaBlend(accentColor.withAlpha(28), base),
                  Color.alphaBlend(colorScheme.tertiary.withAlpha(14), base),
                ])
          : null,
      border: Border.all(color: border, width: .8),
      boxShadow: style == DashboardCardStyle.elevated
          ? [
              BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 36 : 16),
                  blurRadius: 20,
                  offset: const Offset(0, 5))
            ]
          : null,
    );

    final Widget content = Stack(
      fit: StackFit.passthrough,
      children: [
        Padding(padding: padding, child: child),
        if (showAccentIndicator && style != DashboardCardStyle.minimal)
          Positioned(
            left: borderRadius,
            top: 0,
            width: 32,
            height: 3,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: accentColor.withAlpha(180),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(3)))),
          ),
      ],
    );

    final Widget cardWidget = Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(borderRadius),
                hoverColor: accentColor.withAlpha(12),
                splashColor: accentColor.withAlpha(25),
                child: content,
              )
            : content,
      ),
    );

    return DashboardCardTheme(
      data: themeData,
      child: RepaintBoundary(child: cardWidget),
    );
  }
}
