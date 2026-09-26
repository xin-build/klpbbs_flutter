import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';
import '../interactive_animations.dart';

/// 卡片质感风格预设
enum DashboardCardStyle {
  modern('现代立体', Icons.auto_awesome_rounded, '精致微阴影与主题彩带'),
  gradient('极光流光', Icons.gradient_rounded, '沉浸式流光渐变背景'),
  glass('晶透毛玻璃', Icons.blur_on_rounded, '半透明拟物高斯模糊'),
  creeper('苦力怕工坊', Icons.grid_view_rounded, '经典黑曜石与荧光绿'),
  minimal('极简无界', Icons.crop_square_rounded, '高信息密度纯净线条'),
  elevated('悬浮高光', Icons.layers_rounded, '深邃弥散外发光微阴影');

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
    if (this == DashboardCardAccent.auto || colorLight == null || colorDark == null) {
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
    final inherited = context.dependOnInheritedWidgetOfExactType<DashboardCardTheme>();
    if (inherited != null) return inherited.data;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DashboardCardThemeData(
      style: DashboardCardStyle.modern,
      accentColor: Theme.of(context).colorScheme.primary,
      isDark: isDark,
    );
  }

  @override
  bool updateShouldNotify(DashboardCardTheme oldWidget) => data != oldWidget.data;
}

/// 全站统一网格仪表盘卡片外框容器
/// 统一承载卡片风格、阴影、微质感渐变、毛玻璃与强调色，彻底消除卡片样式单一和边框冲突问题
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
    this.borderRadius = 14.0,
    this.showAccentIndicator = true,
    this.onTap,
  });

  /// 根据卡片分类推断自然契合的默认强调色
  static Color getNaturalCategoryAccent(String cardType, BuildContext context) {
    final def = CardRegistry.get(cardType);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (def.category) {
      case DashboardCardCategory.content:
        return isDark ? const Color(0xFFFF7043) : const Color(0xFFE64A19);
      case DashboardCardCategory.user:
        return isDark ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32);
      case DashboardCardCategory.stats:
        return isDark ? const Color(0xFF29B6F6) : const Color(0xFF0288D1);
      case DashboardCardCategory.tool:
        return isDark ? const Color(0xFFBA68C8) : const Color(0xFF7B1FA2);
      case DashboardCardCategory.social:
        return isDark ? const Color(0xFF26A69A) : const Color(0xFF00796B);
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

    // 回退渲染风格：采用干净纯粹的标准 Material / 论坛原生卡片质感
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      color: colorScheme.surfaceContainerLowest,
      border: Border.all(
        color: colorScheme.outlineVariant.withAlpha(isDark ? 55 : 45),
        width: 0.8,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 20 : 6),
          blurRadius: 4,
          offset: const Offset(0, 1.5),
        ),
      ],
    );

    final Widget content = Padding(
      padding: padding,
      child: child,
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
      child: onTap != null
          ? HoverScaleElevationEffect(
              translateY: -2.0,
              duration: const Duration(milliseconds: 160),
              child: cardWidget,
            )
          : cardWidget,
    );
  }
}
