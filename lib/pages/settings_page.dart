import '../widgets/app_motion.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../services/auto_sign_service.dart';
import '../services/download_service.dart';
import '../services/push_notification_service.dart';
import '../services/rgb_theme_service.dart';
import '../widgets/rgb_theme_settings_panel.dart';
import '../widgets/pc_gpu_settings.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/mobile_home_customizer.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/visual_grid_canvas.dart';
import '../core/cache_manager.dart';
import '../core/preload_service.dart';
import 'package:flutter/services.dart';
import '../models/thread_summary.dart';
import '../widgets/thread_card.dart';
import 'download_manager_page.dart';

enum SettingsCategory {
  appearance(
      '外观与个性化', '色彩、深色模式、字体缩放', Icons.palette_outlined, Icons.palette_rounded),
  sign('自动签到', '当前账号、启动与定时签到', Icons.event_available_outlined,
      Icons.event_available_rounded),
  notification('消息推送与后台', '轮询探测、后台挂起、托盘守护', Icons.notifications_outlined,
      Icons.notifications_rounded),
  layout('排版与多端模式', '宽屏双栏、导航布局', Icons.devices_outlined, Icons.devices_rounded),
  download(
      '下载与存储管理', '并发线程、路径配置', Icons.download_outlined, Icons.download_rounded),
  performance(
      '动画与性能', '滚动、动效、后台解析与图片缓存', Icons.speed_outlined, Icons.speed_rounded),
  forum('论坛与阅读偏好', '剪贴板识别、阅读浏览、黑名单', Icons.forum_outlined, Icons.forum_rounded),
  about('关于与系统诊断', '版本信息、系统诊断、检查更新', Icons.info_outline, Icons.info_rounded);

  final String label;
  final String subtitle;
  final IconData icon;
  final IconData selectedIcon;
  const SettingsCategory(
      this.label, this.subtitle, this.icon, this.selectedIcon);
}

/// 高度自定义设置中心（支持 PC 宽屏双栏与移动端层级视图）
class SettingsPage extends StatefulWidget {
  final SettingsCategory? initialCategory;
  const SettingsPage({super.key, this.initialCategory});

  static Widget buildCategoryView(SettingsCategory category) {
    switch (category) {
      case SettingsCategory.appearance:
        return _AppearanceSettingsView();
      case SettingsCategory.sign:
        return _SignSettingsView();
      case SettingsCategory.notification:
        return _NotificationSettingsView();
      case SettingsCategory.layout:
        return _LayoutSettingsView();
      case SettingsCategory.download:
        return _DownloadSettingsView();
      case SettingsCategory.performance:
        return _PerformanceSettingsView();
      case SettingsCategory.forum:
        return _ForumSettingsView();
      case SettingsCategory.about:
        return _AboutSettingsView();
    }
  }

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsCategory _selectedCategory;
  final _scrollBucket = PageStorageBucket();

  bool _wide(BuildContext context) =>
      ResponsiveBreakpoints.isDesktop(context) &&
      MediaQuery.sizeOf(context).width >= 920;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? SettingsCategory.appearance;
    if (widget.initialCategory != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_wide(context)) _openCategory(widget.initialCategory!);
      });
    }
  }

  void _openCategory(SettingsCategory category) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(category.label)),
        body: _SettingsCategoryPane(category: category),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = _wide(context);
    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50,
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('系统设置'),
      ),
      body: wide
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 272,
                      child: Card.filled(
                        margin: EdgeInsets.zero,
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: Text('设置分类',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant)),
                            ),
                            for (final category in SettingsCategory.values)
                              _SettingsCategoryTile(
                                category: category,
                                selected: _selectedCategory == category,
                                onTap: () {
                                  if (_selectedCategory != category) {
                                    setState(
                                        () => _selectedCategory = category);
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: PageStorage(
                        bucket: _scrollBucket,
                        child: AnimatedSwitcher(
                          duration: AppMotion.duration(context, 300,
                              scope: MotionScope.navigation),
                          reverseDuration: AppMotion.duration(context, 140,
                              scope: MotionScope.navigation),
                          switchInCurve: AppMotion.emphasized,
                          switchOutCurve: Curves.easeOut,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                      begin: const Offset(.025, 0),
                                      end: Offset.zero)
                                  .animate(animation),
                              child: child,
                            ),
                          ),
                          child: _SettingsCategoryPane(
                            key: PageStorageKey(_selectedCategory.name),
                            category: _selectedCategory,
                            desktop: true,
                          ),
                        ),
                      ),
                    ),
                  ]),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
                  child: Text('按使用习惯调整界面、阅读与消息提醒',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                Card.filled(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (var i = 0;
                        i < SettingsCategory.values.length;
                        i++) ...[
                      if (i > 0)
                        Divider(
                            height: 1,
                            indent: 76,
                            endIndent: 20,
                            color: scheme.outlineVariant.withAlpha(70)),
                      ListTile(
                        key: ValueKey(
                            'settings-category-${SettingsCategory.values[i].name}'),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        leading: CircleAvatar(
                          backgroundColor: scheme.secondaryContainer,
                          foregroundColor: scheme.onSecondaryContainer,
                          child:
                              Icon(SettingsCategory.values[i].icon, size: 22),
                        ),
                        title: Text(SettingsCategory.values[i].label,
                            style: Theme.of(context).textTheme.titleSmall),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(SettingsCategory.values[i].subtitle),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openCategory(SettingsCategory.values[i]),
                      ),
                    ],
                  ]),
                ),
              ],
            ),
    );
  }
}

class _SettingsCategoryTile extends StatelessWidget {
  final SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;
  const _SettingsCategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          end: selected ? scheme.secondaryContainer : Colors.transparent,
        ),
        duration: AppMotion.duration(context, 180),
        curve: AppMotion.emphasized,
        builder: (context, color, child) => Material(
          color: color ?? Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
        child: ListTile(
          key: ValueKey('settings-category-${category.name}'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Icon(selected ? category.selectedIcon : category.icon,
              color: selected
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant),
          title: Text(category.label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 15,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurface)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(category.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    height: 1.35,
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant)),
          ),
          selected: selected,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _SettingsCategoryPane extends StatelessWidget {
  final SettingsCategory category;
  final bool desktop;
  const _SettingsCategoryPane({
    super.key,
    required this.category,
    this.desktop = false,
  });

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Theme(
            data: Theme.of(context).copyWith(
              cardTheme: Theme.of(context).cardTheme.copyWith(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                  ),
              listTileTheme: Theme.of(context).listTileTheme.copyWith(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    minVerticalPadding: 8,
                    titleTextStyle: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontSize: 15, height: 1.35),
                    subtitleTextStyle: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                            fontSize: 14,
                            height: 1.4,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
            ),
            child: Scaffold(
              backgroundColor: Theme.of(context).colorScheme.surface,
              body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (desktop)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(category.label,
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 6),
                            Text(category.subtitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                          ],
                        ),
                      ),
                    Expanded(child: SettingsPage.buildCategoryView(category)),
                  ]),
            ),
          ),
        ),
      );
}

/// 1. 外观与个性化
class _AppearanceSettingsView extends StatefulWidget {
  @override
  State<_AppearanceSettingsView> createState() =>
      _AppearanceSettingsViewState();
}

class _AppearanceSettingsViewState extends State<_AppearanceSettingsView> {
  late double _fontScaleValue;

  static final _previewThread = ThreadSummary(
    tid: 999999,
    fid: 52,
    title: '【1.20+】苦力怕论坛精选超清材质包 & 极致光影体验',
    author: '苦力怕小助手',
    uid: 1,
    forumName: '基岩版附加包',
    typeName: '材质光影',
    timeText: '10分钟前',
    views: 12580,
    replies: 326,
    recommendCount: 88,
    isDigest: true,
    isRecommend: true,
    isHot: true,
    excerpt: '专为移动端与桌面端深度优化的极致视觉光影材质包，带来逼真动态水面与全局光照反射效果...',
    imageUrls: const [
      'https://klpbbs.com/template/comiis_app/comiis/touch/css/img/none.png',
    ],
  );

  @override
  void initState() {
    super.initState();
    _fontScaleValue = AppConfig.fontScale;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('主题色彩'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: AppStyle.values.map((style) {
                    final isSelected = AppConfig.style == style;
                    return InkWell(
                      onTap: () => AppConfig.setStyle(style),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? style.seed.withAlpha(40)
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? style.seed
                                : colorScheme.outlineVariant.withAlpha(50),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 9,
                              backgroundColor: style == AppStyle.custom
                                  ? Color(AppConfig.customSeedColorValue)
                                  : style.seed,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              style.label,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? style.seed
                                    : colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (AppConfig.style == AppStyle.custom) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text('自定义取色 (Hex/RGB): '),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.colorize_rounded, size: 16),
                        label: const Text('选择色彩'),
                        onPressed: _showCustomColorDialog,
                      ),
                    ],
                  ),
                ],
                if (!kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.android) ...[
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('系统动态莫奈取色 (Material You)'),
                    subtitle:
                        const Text('开启后提取 Android 12+ 系统壁纸主题色，关闭则使用上方选定色彩'),
                    value: AppConfig.useSystemMonet,
                    onChanged: (v) {
                      AppConfig.setUseSystemMonet(v);
                      setState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const RgbThemeSettingsPanel(),
        const SizedBox(height: 16),
        _buildSectionHeader('暗色与深色模式'),
        Card(
          child: Column(
            children: [
              RadioListTile<ThemeMode>(
                title: const Text('跟随系统'),
                value: ThemeMode.system,
                groupValue: AppConfig.themeMode,
                onChanged: (v) => AppConfig.setThemeMode(v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('浅色模式'),
                value: ThemeMode.light,
                groupValue: AppConfig.themeMode,
                onChanged: (v) => AppConfig.setThemeMode(v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('暗色模式'),
                value: ThemeMode.dark,
                groupValue: AppConfig.themeMode,
                onChanged: (v) => AppConfig.setThemeMode(v!),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('OLED 纯黑暗色模式'),
                subtitle: const Text('暗色下使用纯黑背景（#000000），更省电与纯粹'),
                value: AppConfig.isOledDark,
                onChanged: (v) => AppConfig.setIsOledDark(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('排版细节与字体缩放'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('字体缩放比例'),
                subtitle: Text('当前：${(_fontScaleValue * 100).round()}%'),
                trailing: Text(
                  '${(_fontScaleValue * 100).round()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                    fontSize: 15,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Text(
                      '85%',
                      style:
                          TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                    Expanded(
                      child: Slider(
                        value: _fontScaleValue.clamp(0.85, 1.35),
                        min: 0.85,
                        max: 1.35,
                        onChanged: (v) {
                          setState(() => _fontScaleValue = v);
                        },
                        onChangeEnd: (v) {
                          final snapped =
                              ((v * 20).round() / 20.0).clamp(0.85, 1.35);
                          setState(() => _fontScaleValue = snapped);
                          AppConfig.setFontScale(snapped);
                        },
                      ),
                    ),
                    Text(
                      '135%',
                      style:
                          TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildScaleChip('小 (85%)', 0.85),
                    _buildScaleChip('标准 (100%)', 1.0),
                    _buildScaleChip('大 (115%)', 1.15),
                    _buildScaleChip('特大 (130%)', 1.30),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('界面视觉密度'),
                trailing: DropdownButton<AppDensity>(
                  value: AppConfig.density,
                  underline: const SizedBox(),
                  items: AppDensity.values
                      .map(
                        (d) => DropdownMenuItem(value: d, child: Text(d.label)),
                      )
                      .toList(),
                  onChanged: (v) => v != null ? AppConfig.setDensity(v) : null,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('头像形状'),
                trailing: DropdownButton<AvatarShape>(
                  value: AppConfig.avatarShape,
                  underline: const SizedBox(),
                  items: AvatarShape.values
                      .map(
                        (a) => DropdownMenuItem(value: a, child: Text(a.label)),
                      )
                      .toList(),
                  onChanged: (v) =>
                      v != null ? AppConfig.setAvatarShape(v) : null,
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.style_outlined, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          '帖子卡片排版风格',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            AppConfig.cardStyle.label
                                .split('（')[0]
                                .split(' ')[0],
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 实时交互预览区域（支持所见即所得，彻底对齐用户需求）
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHighest.withAlpha(70),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withAlpha(90),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.remove_red_eye_outlined,
                                  size: 14, color: colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                '当前风格实时预览',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ThreadCard(
                            thread: _previewThread,
                            cardStyle: AppConfig.cardStyle,
                            margin: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 风格选项选择芯片
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final style in CardStyle.values)
                          ChoiceChip(
                            label: Text(style.label),
                            selected: AppConfig.cardStyle == style,
                            onSelected: (selected) {
                              if (selected) {
                                HapticFeedback.lightImpact();
                                AppConfig.setCardStyle(style);
                                setState(() {});
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScaleChip(String label, double scale) {
    final isSelected = ((_fontScaleValue * 20).round() / 20.0) == scale;
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _fontScaleValue = scale);
        AppConfig.setFontScale(scale);
      },
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? colorScheme.primary : colorScheme.onSurface,
      ),
    );
  }

  void _showCustomColorDialog() {
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.blueGrey,
    ];

    Color currentColor = Color(AppConfig.customSeedColorValue);
    String hexString =
        '#${currentColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final textCtrl = TextEditingController(text: hexString);

    Color? parseHex(String val) {
      var s = val.replaceAll('#', '').trim();
      if (s.length == 6) s = 'FF$s';
      if (s.length == 8) {
        final v = int.tryParse(s, radix: 16);
        if (v != null) return Color(v);
      }
      return null;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final dialogTheme = Theme.of(dialogCtx);
          return AlertDialog(
            title: const Text('自定义主题色彩'),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: currentColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: dialogTheme.colorScheme.outline,
                              width: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: textCtrl,
                            decoration: const InputDecoration(
                              labelText: '16 进制色彩代码',
                              hintText: '#3BA55D 或 3BA55D',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (val) {
                              final parsed = parseHex(val);
                              if (parsed != null) {
                                setDialogState(() {
                                  currentColor = parsed;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('常用调色板：',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: colors.map((c) {
                        final isSel = currentColor.toARGB32() == c.toARGB32();
                        return InkWell(
                          onTap: () {
                            setDialogState(() {
                              currentColor = c;
                              textCtrl.text =
                                  '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
                            });
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    isSel ? Colors.white : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: isSel
                                  ? [
                                      BoxShadow(
                                        color: c.withAlpha(140),
                                        blurRadius: 6,
                                        spreadRadius: 2,
                                      )
                                    ]
                                  : null,
                            ),
                            child: isSel
                                ? const Icon(Icons.check,
                                    size: 18, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = parseHex(textCtrl.text) ?? currentColor;
                  AppConfig.setCustomSeedColor(parsed);
                  Navigator.of(ctx).pop();
                },
                child: const Text('应用色彩'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 2. 排版与多端模式
class _LayoutSettingsView extends StatefulWidget {
  @override
  State<_LayoutSettingsView> createState() => _LayoutSettingsViewState();
}

class _LayoutSettingsViewState extends State<_LayoutSettingsView> {
  late double _minimumContentWidth;

  @override
  void initState() {
    super.initState();
    _minimumContentWidth = AppConfig.mainContentMinWidth;
  }

  void _openStudio(String pageCategory) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VisualGridCanvas(
          pageCategory: pageCategory,
          initialLayout: pageCategory == 'home'
              ? AppConfig.homeDashboardLayout
              : (pageCategory == 'thread'
                  ? AppConfig.threadDashboardLayout
                  : AppConfig.guideDashboardLayout),
          onExit: () => Navigator.of(context).pop(),
          onSave: (saved) {
            setState(() {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ================= 1. 设备排版模式 =================
        _buildSectionHeader('设备排版模式'),
        Card(
          child: Column(
            children: AppLayoutMode.values.map((mode) {
              return RadioListTile<AppLayoutMode>(
                title: Text(mode.label),
                value: mode,
                groupValue: AppConfig.layoutMode,
                onChanged: (v) {
                  if (v != null) {
                    AppConfig.setLayoutMode(v);
                    setState(() {});
                  }
                },
              );
            }).toList(),
          ),
        ),

        // ================= 2. 桌面 PC 端专属：自由画布工作台与宽屏双栏配置 =================
        if (isDesktop) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('桌面布局'),
          Card.filled(
            key: const ValueKey('settings-desktop-layout'),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.dashboard_customize_rounded,
                            color: colorScheme.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '页面与卡片布局',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '调整侧栏宽度、卡片顺序和外观',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '在自由画布中拖动和调整卡片，使用页面预览检查实际窗口中的排版。',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonalIcon(
                        key: const ValueKey('settings-canvas-home'),
                        onPressed: () => _openStudio('home'),
                        icon: const Icon(Icons.home_outlined, size: 16),
                        label: const Text('首页自由画布'),
                      ),
                      FilledButton.tonalIcon(
                        key: const ValueKey('settings-canvas-guide'),
                        onPressed: () => _openStudio('guide'),
                        icon: const Icon(Icons.explore_outlined, size: 16),
                        label: const Text('导读工作台画布'),
                      ),
                      FilledButton.tonalIcon(
                        key: const ValueKey('settings-canvas-thread'),
                        onPressed: () => _openStudio('thread'),
                        icon: const Icon(Icons.article_outlined, size: 16),
                        label: const Text('帖子工作台画布'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // 主页内容最小保护宽度滑块
                  Text(
                    '首页内容最小宽度 · ${_minimumContentWidth.round()} px',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '空间不足时收起侧栏，为帖子列表留出更多空间。',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  Slider(
                    key: const ValueKey('settings-minimum-content-width'),
                    value: _minimumContentWidth.clamp(400.0, 1000.0),
                    min: 400.0,
                    max: 1000.0,
                    divisions: 12,
                    label: '${_minimumContentWidth.round()} px',
                    onChanged: (v) => setState(() => _minimumContentWidth = v),
                    onChangeEnd: AppConfig.setMainContentMinWidth,
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          await AppConfig.resetAllDashboards();
                          if (!mounted) return;
                          setState(() => _minimumContentWidth =
                              AppConfig.mainContentMinWidth);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已恢复所有页面的默认布局')),
                            );
                          }
                        },
                        icon: const Icon(Icons.restore_rounded, size: 16),
                        label: const Text('恢复全部页面默认布局',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('桌面 PC 宽屏配置'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('版块列表网格列数'),
                  subtitle: const Text('调整版块列表等宽屏页面的帖子排版'),
                  trailing: DropdownButton<int>(
                    value: AppConfig.desktopGridColumns,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('自动适应')),
                      DropdownMenuItem(value: 2, child: Text('双列 (2 列)')),
                      DropdownMenuItem(value: 3, child: Text('三列 (3 列)')),
                      DropdownMenuItem(value: 4, child: Text('四列 (4 列)')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        AppConfig.setDesktopGridColumns(v);
                        setState(() {});
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('版块列表与详情分栏'),
                  subtitle: const Text('宽屏下左侧展示帖子列表，右侧直接展示详情'),
                  value: AppConfig.isMasterDetailEnabled,
                  onChanged: (v) {
                    AppConfig.setIsMasterDetailEnabled(v);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ],

        // ================= 3. 移动端视图专属：移动端首页板块与快捷入口定制 =================
        if (!isDesktop) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('移动端首页布局与功能定制'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: colorScheme.outlineVariant.withAlpha(50),
              ),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.tune_rounded,
                    color: colorScheme.primary, size: 22),
              ),
              title: const Text(
                '移动端首页板块与快捷入口定制',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '自定义公告小喇叭、数据统计、快捷金刚区、版块导航与精华推荐流的显隐及排序',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => MobileHomeCustomizer.show(context),
            ),
          ),

          // ================= 4. 移动端导航布局 =================
          const SizedBox(height: 16),
          _buildSectionHeader('移动端导航布局'),
          Card(
            child: Column(
              children: NavLayout.values.map((l) {
                return RadioListTile<NavLayout>(
                  title: Text(l.label),
                  value: l,
                  groupValue: AppConfig.navLayout,
                  onChanged: (v) {
                    if (v != null) {
                      AppConfig.setNavLayout(v);
                      setState(() {});
                    }
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

/// 3. 下载与存储管理
class _DownloadSettingsView extends StatefulWidget {
  @override
  State<_DownloadSettingsView> createState() => _DownloadSettingsViewState();
}

class _DownloadSettingsViewState extends State<_DownloadSettingsView> {
  String _currentPath = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentPath();
  }

  Future<void> _loadCurrentPath() async {
    final path = await DownloadManager.getDownloadDirectory();
    if (mounted) setState(() => _currentPath = path);
  }

  Future<void> _pickDirectory() async {
    try {
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: '选择下载保存目录',
        initialDirectory: _currentPath.isNotEmpty ? _currentPath : null,
      );
      if (selected != null && selected.isNotEmpty) {
        await AppConfig.setDownloadPath(selected);
        setState(() => _currentPath = selected);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已设置下载保存目录: $selected')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择目录失败: $e')),
        );
      }
    }
  }

  Future<void> _resetToDefault() async {
    await AppConfig.setDownloadPath('');
    await _loadCurrentPath();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重置为系统默认下载目录')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('下载任务管理'),
        Card(
          child: ListTile(
            leading:
                Icon(Icons.download_done_rounded, color: colorScheme.primary),
            title: const Text('下载任务管理器'),
            subtitle: const Text('查看正在下载与已下载的附件文件、实时网速及进度'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DownloadManagerPage(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('存储保存位置（兼容多平台）'),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading:
                    Icon(Icons.folder_outlined, color: colorScheme.primary),
                title: const Text('下载保存目录'),
                subtitle: Text(
                  _currentPath.isNotEmpty ? _currentPath : '正在获取默认下载路径...',
                  style: const TextStyle(fontSize: 12),
                ),
                isThreeLine: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      onPressed: _pickDirectory,
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('更改目录'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      onPressed: _currentPath.isNotEmpty
                          ? () => DownloadManager.openFolder(_currentPath)
                          : null,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('打开目录'),
                    ),
                    if (AppConfig.downloadPath.isNotEmpty)
                      TextButton(
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        onPressed: _resetToDefault,
                        child: const Text('恢复系统默认'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('多线程分块并发与性能'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('多线程分块并发数'),
                subtitle: const Text('对支持 Range 的附件使用多连接分段下载加速'),
                trailing: DropdownButton<int>(
                  value: AppConfig.downloadThreads,
                  underline: const SizedBox(),
                  items: [1, 2, 3, 4, 6, 8]
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t == 1 ? '单线程 (1)' : '$t 线程并发'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      AppConfig.setDownloadThreads(v);
                      setState(() {});
                    }
                  },
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('下载完成后自动打开'),
                subtitle: const Text('附件下载成功后自动调用系统默认关联程序打开'),
                value: AppConfig.autoOpenFile,
                onChanged: (v) {
                  AppConfig.setAutoOpenFile(v);
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 6. 性能与 GPU 加速 / 缓存生命周期管理
class _PerformanceSettingsView extends StatefulWidget {
  @override
  State<_PerformanceSettingsView> createState() =>
      _PerformanceSettingsViewState();
}

class _PerformanceSettingsViewState extends State<_PerformanceSettingsView> {
  String _cacheSizeStr = '计算中...';
  bool _isCalculating = false;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  Future<void> _refreshCacheSize() async {
    if (!mounted) return;
    setState(() => _isCalculating = true);
    try {
      final bytes = await KlpbbsCacheManager.calculateTotalCacheBytes();
      if (mounted) {
        setState(() {
          _cacheSizeStr = KlpbbsCacheManager.formatBytes(bytes);
          _isCalculating = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCalculating = false);
    }
  }

  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    try {
      final freedBytes = await KlpbbsCacheManager.clearEntireCache();
      PreloadService.instance.clear();
      KlpbbsApi.clearQuickCache();
      KlpbbsApi.clearFavoriteCaches();

      if (mounted) {
        setState(() {
          _cacheSizeStr = '0.0 MB';
          _isClearing = false;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '已深度彻底清理本地缓存，释放 ${KlpbbsCacheManager.formatBytes(freedBytes)} 空间'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理缓存时发生异常：$e')),
        );
      }
    }
  }

  Future<void> _pruneExpiredCache() async {
    setState(() => _isClearing = true);
    try {
      final freedBytes =
          await KlpbbsCacheManager.purgeExpiredAndOvercapacityCache();
      await _refreshCacheSize();
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '已清理过期、坏块与超容缓存，释放 ${KlpbbsCacheManager.formatBytes(freedBytes)} 空间'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理缓存时发生异常：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.windows &&
            ResponsiveBreakpoints.isDesktop(context)) ...[
          const PcGpuSettingsPanel(),
          const SizedBox(height: 20),
        ],
        _buildSectionHeader('动画与滚动', subtitle: '调整实际的页面动效、鼠标滚动与 HTML 解析方式'),
        _buildSettingCard(
          context: context,
          children: [
            _buildSettingSwitchTile(
              context: context,
              title: '减少动画',
              subtitle: '关闭位移和展开动画，并暂停 RGB 动态颜色；同时遵循系统设置',
              icon: Icons.motion_photos_off_outlined,
              value: AppConfig.reduceMotion,
              onChanged: (v) {
                AppConfig.setReduceMotion(v);
                setState(() {});
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('动画节奏',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<MotionPace>(
                          showSelectedIcon: false,
                          segments: MotionPace.values
                              .map((pace) => ButtonSegment(
                                  value: pace, label: Text(pace.label)))
                              .toList(),
                          selected: {AppConfig.motionPace},
                          onSelectionChanged: AppConfig.reduceMotion
                              ? null
                              : (values) {
                                  AppConfig.setMotionPace(values.first);
                                  setState(() {});
                                },
                        )),
                  ]),
            ),
            for (final option in [
              (
                'animate_pages',
                '页面与标签切换',
                Icons.open_in_new_rounded,
                AppConfig.animatePageTransitions
              ),
              (
                'animate_panels',
                '侧栏、展开与按压反馈',
                Icons.view_sidebar_outlined,
                AppConfig.animatePanels
              ),
              (
                'animate_lists',
                '列表进入动画',
                Icons.view_stream_outlined,
                AppConfig.animateLists
              ),
              (
                'animate_loading',
                '加载与骨架动画',
                Icons.hourglass_top_rounded,
                AppConfig.animateLoading
              ),
              (
                'banner_auto_play',
                '霸屏自动轮播',
                Icons.view_carousel_outlined,
                AppConfig.bannerAutoPlay
              ),
            ])
              _buildSettingSwitchTile(
                context: context,
                title: option.$2,
                subtitle: option.$1 == 'banner_auto_play'
                    ? '每 5 秒切换；拖动或鼠标停留时暂停，仍可手动滑动'
                    : '按所选节奏播放，并遵循减少动画设置',
                icon: option.$3,
                value: option.$4,
                onChanged: AppConfig.reduceMotion
                    ? null
                    : (value) {
                        AppConfig.setMotionOption(option.$1, value);
                        setState(() {});
                      },
              ),
            Divider(
                height: 1,
                indent: 68,
                color: colorScheme.outlineVariant.withAlpha(40)),
            if (ResponsiveBreakpoints.isDesktop(context))
              _buildSettingSwitchTile(
                context: context,
                title: '平滑鼠标滚动',
                subtitle: '首页与版块列表的滚轮渐进滚动；触摸和触控板保留系统行为',
                icon: Icons.swap_vert_circle_outlined,
                value: AppConfig.smoothScrollPhysics,
                onChanged: AppConfig.reduceMotion
                    ? null
                    : (v) {
                        AppConfig.setSmoothScrollPhysics(v);
                        setState(() {});
                      },
              ),
            Divider(
                height: 1,
                indent: 68,
                color: colorScheme.outlineVariant.withAlpha(40)),
            _buildSettingSwitchTile(
              context: context,
              title: '后台解析页面',
              subtitle: '将较大的论坛 HTML 放到独立任务解析，减少界面线程的阻塞',
              icon: Icons.memory_rounded,
              value: AppConfig.enableMultiThreadParsing,
              onChanged: (v) {
                AppConfig.setMultiThreadParsing(v);
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. 图片质量与内存上限
        _buildSectionHeader(
          '图片质量与渲染',
          subtitle: '配置网络图片下载清晰度与运行时图片解码上限',
        ),
        _buildSettingCard(
          context: context,
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.image_outlined,
                    color: colorScheme.secondary, size: 20),
              ),
              title: const Text('图片加载质量',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: Text('控制帖子插图与附件下载清晰度',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline)),
              trailing: DropdownButton<ImageQuality>(
                value: AppConfig.imageQuality,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(12),
                items: ImageQuality.values
                    .map(
                        (q) => DropdownMenuItem(value: q, child: Text(q.label)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    AppConfig.setImageQuality(v);
                    setState(() {});
                  }
                },
              ),
            ),
            Divider(
                height: 1,
                indent: 68,
                color: colorScheme.outlineVariant.withAlpha(40)),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.pie_chart_outline_rounded,
                    color: colorScheme.primary, size: 20),
              ),
              title: const Text('运行时图片内存配额',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: Text('当前设置: ${AppConfig.imageCacheMaxMb} MB',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline)),
              trailing: DropdownButton<int>(
                value: AppConfig.imageCacheMaxMb,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(12),
                items: ({
                  100,
                  128,
                  250,
                  256,
                  500,
                  1024,
                  AppConfig.imageCacheMaxMb
                }.toList()
                      ..sort())
                    .map((mb) =>
                        DropdownMenuItem(value: mb, child: Text('$mb MB')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    AppConfig.setImageCacheMaxMb(v);
                    setState(() {});
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3. 智能缓存生命周期与磁盘管理
        _buildSectionHeader(
          '多级缓存与存储管理',
          subtitle: '兼顾离线秒开体验与原站实时权威数据对齐',
        ),
        _buildSettingCard(
          context: context,
          children: [
            // 缓存空间探测栏
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.storage_rounded,
                    color: colorScheme.tertiary, size: 20),
              ),
              title: const Text('已占用本地磁盘缓存',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: Text(
                '包含头像、勋章、附件、表情与网络快速缓存',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _cacheSizeStr,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: _isCalculating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: AppLoadingIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 19),
                    tooltip: '重新计算缓存容量',
                    visualDensity: VisualDensity.compact,
                    onPressed: _isCalculating ? null : _refreshCacheSize,
                  ),
                ],
              ),
            ),
            Divider(
                height: 1,
                indent: 68,
                color: colorScheme.outlineVariant.withAlpha(40)),

            // 缓存生命周期说明
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(100),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        const Text(
                          '智能双层缓存策略',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 静态资源规范化去重：跨 CDN 论坛图片、附件与表情合并存储，默认头像不占磁盘，彻底杜绝重复堆积。\n'
                      '• 智能生命周期与容量控制：磁盘图片 14 天过期自动修剪，超出 350MB 按 LRU 自动清理；应用启动自动静默瘦身。',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.onSurfaceVariant.withAlpha(200),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(40)),

            // 清理过期与超容缓存
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              title: const Text('清理过期与超容缓存',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text(
                  '移除超过 14 天的过期缓存、0 字节坏块并按 LRU 压降至 250MB，保留热点缓存',
                  style: TextStyle(fontSize: 12)),
              trailing: FilledButton.tonalIcon(
                icon: _isClearing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: AppLoadingIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_rounded, size: 17),
                label: Text(_isClearing ? '清理中...' : '优化清理'),
                onPressed: _isClearing ? null : _pruneExpiredCache,
              ),
            ),
            Divider(
                height: 1,
                indent: 68,
                color: colorScheme.outlineVariant.withAlpha(40)),

            // 一键深度清空缓存
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              title: const Text('彻底清除全部缓存',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text('清空所有磁盘持久化图片、临时目录、内存图片解码与运行时网络缓存',
                  style: TextStyle(fontSize: 12)),
              trailing: OutlinedButton.icon(
                icon: _isClearing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: AppLoadingIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_sweep_rounded, size: 17),
                label: Text(_isClearing ? '清理中...' : '彻底清空'),
                onPressed: _isClearing ? null : _clearCache,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 4. 论坛与阅读偏好
class _ForumSettingsView extends StatefulWidget {
  @override
  State<_ForumSettingsView> createState() => _ForumSettingsViewState();
}

class _ForumSettingsViewState extends State<_ForumSettingsView> {
  final _keywordCtrl = TextEditingController();
  final _uidCtrl = TextEditingController();

  @override
  void dispose() {
    _keywordCtrl.dispose();
    _uidCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 0. 底层网络直连与代理
        _buildSectionHeader(
          '底层网络与代理连接',
          subtitle: '控制论坛请求路由，默认直连可规避代理节点拦截与 523 报错',
        ),
        _buildSettingCard(
          context: context,
          children: [
            _buildSettingSwitchTile(
              context: context,
              title: '遵循系统代理网络 (System Proxy)',
              subtitle:
                  '默认关闭（强制 DIRECT 直连）。开启后遵循系统 VPN / 代理分流；若频繁遭遇 523 错误或 WAF 验证阻断，建议保持关闭直连。',
              icon: Icons.vpn_lock_rounded,
              value: AppConfig.useSystemProxy,
              onChanged: (v) {
                AppConfig.setUseSystemProxy(v);
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 1. 智能剪贴板跳转
        _buildSectionHeader(
          '智能剪贴板识别',
          subtitle: '从其他应用切换回论坛时，自动识别剪贴板中的链接并跳转',
        ),
        _buildSettingCard(
          context: context,
          children: [
            _buildSettingSwitchTile(
              context: context,
              title: '切换窗口时检测剪贴板',
              subtitle: '切回应用或窗口获得焦点时，自动读取剪贴板中的论坛链接',
              icon: Icons.content_paste_go_rounded,
              value: AppConfig.clipboardJumpEnabled,
              onChanged: (v) {
                AppConfig.setClipboardJumpEnabled(v);
                setState(() {});
              },
            ),
            if (AppConfig.clipboardJumpEnabled) ...[
              Divider(
                  height: 1,
                  indent: 68,
                  color: colorScheme.outlineVariant.withAlpha(40)),
              _buildSettingSwitchTile(
                context: context,
                title: '识别帖子链接',
                subtitle: '检测 thread-xxx 与 tid=xxx 格式，跳转至帖子详情',
                icon: Icons.article_outlined,
                iconBgColor: colorScheme.secondaryContainer.withAlpha(90),
                iconColor: colorScheme.secondary,
                value: AppConfig.clipboardJumpThreadEnabled,
                onChanged: (v) {
                  AppConfig.setClipboardJumpThreadEnabled(v);
                  setState(() {});
                },
              ),
              Divider(
                  height: 1,
                  indent: 68,
                  color: colorScheme.outlineVariant.withAlpha(40)),
              _buildSettingSwitchTile(
                context: context,
                title: '识别站内搜索链接',
                subtitle: '检测 search.php 链接并提取关键词，跳转至搜索页面',
                icon: Icons.search_rounded,
                iconBgColor: colorScheme.tertiaryContainer.withAlpha(90),
                iconColor: colorScheme.tertiary,
                value: AppConfig.clipboardJumpSearchEnabled,
                onChanged: (v) {
                  AppConfig.setClipboardJumpSearchEnabled(v);
                  setState(() {});
                },
              ),
              Divider(
                  height: 1,
                  indent: 68,
                  color: colorScheme.outlineVariant.withAlpha(40)),
              _buildSettingSwitchTile(
                context: context,
                title: '跳转前弹窗确认',
                subtitle: '弹出提示卡片确认后再跳转，防止打断当前阅读或编辑',
                icon: Icons.help_outline_rounded,
                iconBgColor: colorScheme.surfaceContainerHighest,
                iconColor: colorScheme.onSurfaceVariant,
                value: AppConfig.clipboardJumpConfirm,
                onChanged: (v) {
                  AppConfig.setClipboardJumpConfirm(v);
                  setState(() {});
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // 2. 阅读与浏览
        _buildSectionHeader(
          '阅读与浏览偏好',
          subtitle: '论坛界面图文展示、楼层签名与起始页面',
        ),
        _buildSettingCard(
          context: context,
          children: [
            _buildSettingSwitchTile(
              context: context,
              title: '帖子列表显示图片预览',
              subtitle: '在版块与搜索列表中显示最多 3 张附图预览（单图 16:9，多图 1:1）',
              icon: Icons.image_outlined,
              value: AppConfig.showThreadListImages,
              onChanged: (v) {
                AppConfig.setShowThreadListImages(v);
                setState(() {});
              },
            ),
            Divider(
                height: 1,
                indent: 68,
                color: colorScheme.outlineVariant.withAlpha(40)),
            _buildSettingSwitchTile(
              context: context,
              title: '显示楼层个性签名档',
              subtitle: '在帖子详情楼层底部渲染用户个性化签名',
              icon: Icons.draw_outlined,
              value: AppConfig.showFloorSignature,
              onChanged: (v) {
                AppConfig.setShowFloorSignature(v);
                setState(() {});
              },
            ),
            Divider(
                height: 1,
                indent: 68,
                color: colorScheme.outlineVariant.withAlpha(40)),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.launch_rounded,
                    color: colorScheme.primary, size: 20),
              ),
              title: const Text(
                '默认启动页',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
              ),
              subtitle: Text(
                '应用启动时默认激活的主功能标签',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant.withAlpha(190),
                ),
              ),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: colorScheme.outlineVariant.withAlpha(50),
                      width: 0.8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: AppConfig.defaultStartTab,
                    borderRadius: BorderRadius.circular(12),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('论坛首页')),
                      DropdownMenuItem(value: 1, child: Text('论坛导读')),
                      DropdownMenuItem(value: 2, child: Text('每日签到')),
                      DropdownMenuItem(value: 3, child: Text('封神榜')),
                      DropdownMenuItem(value: 4, child: Text('论坛搜索')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        AppConfig.setDefaultStartTab(v);
                        setState(() {});
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3. 屏蔽黑名单 (关键词 & 用户)
        _buildSectionHeader(
          '屏蔽黑名单',
          subtitle: '过滤指定关键词标题或特定作者 UID 发布的内容',
        ),
        _buildSettingCard(
          context: context,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '关键词屏蔽',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _keywordCtrl,
                          decoration: InputDecoration(
                            hintText: '输入屏蔽关键词...',
                            isDense: true,
                            prefixIcon:
                                const Icon(Icons.block_rounded, size: 18),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onSubmitted: (_) {
                            if (_keywordCtrl.text.trim().isNotEmpty) {
                              AppConfig.addBlockedKeyword(
                                  _keywordCtrl.text.trim());
                              _keywordCtrl.clear();
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        onPressed: () {
                          if (_keywordCtrl.text.trim().isNotEmpty) {
                            AppConfig.addBlockedKeyword(
                                _keywordCtrl.text.trim());
                            _keywordCtrl.clear();
                            setState(() {});
                          }
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('添加'),
                      ),
                    ],
                  ),
                  if (AppConfig.blockedKeywords.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: AppConfig.blockedKeywords.map((kw) {
                        return Chip(
                          label: Text(kw),
                          deleteIcon: const Icon(Icons.close_rounded, size: 16),
                          onDeleted: () {
                            AppConfig.removeBlockedKeyword(kw);
                            setState(() {});
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const Divider(height: 28),
                  Text(
                    '作者 UID 屏蔽',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _uidCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '输入屏蔽作者编号 (UID)...',
                            isDense: true,
                            prefixIcon:
                                const Icon(Icons.person_off_outlined, size: 18),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onSubmitted: (_) {
                            final uid = int.tryParse(_uidCtrl.text.trim()) ?? 0;
                            if (uid > 0) {
                              AppConfig.addBlockedUid(uid);
                              _uidCtrl.clear();
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        onPressed: () {
                          final uid = int.tryParse(_uidCtrl.text.trim()) ?? 0;
                          if (uid > 0) {
                            AppConfig.addBlockedUid(uid);
                            _uidCtrl.clear();
                            setState(() {});
                          }
                        },
                        icon: const Icon(Icons.shield_outlined, size: 18),
                        label: const Text('屏蔽'),
                      ),
                    ],
                  ),
                  if (AppConfig.blockedUids.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: AppConfig.blockedUids.map((uid) {
                        return Chip(
                          avatar:
                              const Icon(Icons.person_off_rounded, size: 16),
                          label: Text('UID: $uid'),
                          deleteIcon: const Icon(Icons.close_rounded, size: 16),
                          onDeleted: () {
                            AppConfig.removeBlockedUid(uid);
                            setState(() {});
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 5. 网络与环境安全

/// 2. 消息推送与后台设置
class _NotificationSettingsView extends StatefulWidget {
  @override
  State<_NotificationSettingsView> createState() =>
      _NotificationSettingsViewState();
}

class _NotificationSettingsViewState extends State<_NotificationSettingsView> {
  @override
  Widget build(BuildContext context) {
    final pushService = PushNotificationService.instance;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('消息推送与轮询探测'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('启用后台低功耗消息探测'),
                subtitle: const Text('采用轻量级数据报文定期探测未读消息，不耗费过多流量'),
                value: pushService.isEnabled,
                onChanged: (v) {
                  pushService.setEnabled(v);
                  setState(() {});
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('检测刷新间隔'),
                subtitle: Text('当前：${pushService.interval.label}'),
                trailing: DropdownButton<PollingInterval>(
                  value: pushService.interval,
                  underline: const SizedBox(),
                  items: PollingInterval.values
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e.label,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      pushService.setInterval(v);
                      setState(() {});
                    }
                  },
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('新消息系统提示音'),
                subtitle: const Text('收到新未读通知时播放提示音'),
                value: pushService.isSoundEnabled,
                onChanged: (v) {
                  pushService.setSound(v);
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        if (ResponsiveBreakpoints.isDesktop(context) &&
            !kIsWeb &&
            const {
              TargetPlatform.windows,
              TargetPlatform.macOS,
              TargetPlatform.linux
            }.contains(defaultTargetPlatform)) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('多平台后台挂起与托盘守护'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('关闭窗口时挂起到系统托盘后台'),
                  subtitle: const Text('点击右上角关闭按钮时自动隐藏到托盘，保持消息接收正常'),
                  value: AppConfig.minimizeToTrayOnClose,
                  onChanged: (v) {
                    AppConfig.setMinimizeToTrayOnClose(v);
                    setState(() {});
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('测试系统通知与提示'),
                  subtitle: const Text('向操作系统发送一条模拟新消息通知以验证权限与展示效果'),
                  trailing: OutlinedButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('发送测试通知'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await pushService.testNotification();
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('已触发系统测试通知')),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 8. 关于与系统诊断（含底部版本号与连续点击解锁 RGB 炫彩彩蛋）
class _AboutSettingsView extends StatefulWidget {
  @override
  State<_AboutSettingsView> createState() => _AboutSettingsViewState();
}

class _AboutSettingsViewState extends State<_AboutSettingsView> {
  int _tapCount = 0;
  DateTime? _lastTapTime;
  bool _diagnosing = false;
  String? _networkResult;
  CancelToken? _networkRequest;

  @override
  void dispose() {
    _networkRequest?.cancel();
    super.dispose();
  }

  Future<void> _diagnoseNetwork() async {
    if (_diagnosing) return;
    final cancel = CancelToken();
    _networkRequest = cancel;
    final target = Uri.parse(AppConfig.baseUrl).resolve('forum.php?mobile=no');
    final elapsed = Stopwatch()..start();
    setState(() {
      _diagnosing = true;
      _networkResult = null;
    });
    String message;
    try {
      final response = await DioClient.dio
          .get<String>(target.toString(),
              cancelToken: cancel,
              options: Options(
                  responseType: ResponseType.plain,
                  sendTimeout: const Duration(seconds: 4),
                  receiveTimeout: const Duration(seconds: 4),
                  headers: {'User-Agent': AppConfig.pcUserAgent}))
          .timeout(const Duration(seconds: 6), onTimeout: () {
        cancel.cancel();
        throw TimeoutException('network probe');
      });
      message =
          'HTTP ${response.statusCode} · ${elapsed.elapsedMilliseconds} ms';
      if ((response.data ?? '').trim().isEmpty) {
        message += ' · 响应内容为空';
      }
    } on TimeoutException {
      message = '请求超时，请检查网络或代理设置';
    } on DioException catch (error) {
      message = switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          '请求超时，请检查网络或代理设置',
        DioExceptionType.badCertificate => 'HTTPS 证书验证失败',
        DioExceptionType.badResponse =>
          '服务器返回 HTTP ${error.response?.statusCode ?? "未知"}',
        DioExceptionType.cancel => '诊断已取消',
        _ => '连接失败，请检查网络或代理设置',
      };
    } catch (_) {
      message = '未能完成诊断，请稍后重试';
    }
    if (!mounted || _networkRequest != cancel) return;
    setState(() {
      _diagnosing = false;
      _networkResult = message;
    });
  }

  void _onVersionTap() {
    final now = DateTime.now();
    if (_lastTapTime == null ||
        now.difference(_lastTapTime!).inMilliseconds < 600) {
      _tapCount++;
    } else {
      _tapCount = 1;
    }
    _lastTapTime = now;

    if (RgbThemeService.instance.isUnlocked) {
      if (_tapCount >= 5) {
        _tapCount = 0;
        final newMode = RgbThemeService.instance.mode == RgbMode.flow
            ? RgbMode.strobe
            : RgbMode.flow;
        RgbThemeService.instance.setMode(newMode);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newMode == RgbMode.strobe
                  ? '已切换至跃变色彩，更新预算保持不变'
                  : '🌈 已快速切换至【流光幻彩】平滑流动模式！',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: RgbThemeService.instance.currentColor,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🌈 当前 RGB 模式：${RgbThemeService.instance.mode.label}（连续点击 5 次可快速切换）',
            ),
            duration: const Duration(seconds: 1),
            backgroundColor: RgbThemeService.instance.currentColor,
          ),
        );
      }
      return;
    }

    if (_tapCount >= 3 && _tapCount < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('再连续点击 ${7 - _tapCount} 次解锁高级特性...'),
          duration: const Duration(milliseconds: 600),
        ),
      );
    } else if (_tapCount >= 7) {
      _tapCount = 0;
      RgbThemeService.instance.unlock();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.auto_awesome, color: Colors.amber, size: 36),
          title: const Text('已解锁 RGB 动态炫彩主题'),
          content: const Text(
            '您已成功解锁【RGB 动态炫彩主题】！\n\n包含两种模式：\n• 「流光幻彩」：连续变化的主题色\n• 「跃变色彩」：按节奏切换颜色\n\n已自动为您开启，可在「外观与个性化」中选择节能、平衡或流畅档位，并独立调节变色速度。后台与减少动画时会自动暂停。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('太酷了！'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.view_in_ar_rounded,
                  size: 38,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '苦力怕论坛 (KLPBBS)',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '浏览社区、发现资源，与玩家交流',
                style: TextStyle(color: colorScheme.outline, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.auto_awesome_rounded),
                title: Text('为你的设备调整布局'),
                subtitle: Text('在「外观与个性化」和「排版与多端模式」中调整'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.network_check_rounded),
                title: const Text('网络连接诊断'),
                subtitle: Text(_networkResult ?? '当前地址: ${AppConfig.baseUrl}'),
                trailing: OutlinedButton(
                  key: const ValueKey('settings-network-probe'),
                  onPressed: _diagnosing ? null : _diagnoseNetwork,
                  child: _diagnosing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('测试连通'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        // 版本号放置在下方，支持连续点击 7 次解锁彩蛋
        Center(
          child: InkWell(
            onTap: _onVersionTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  Text(
                    '苦力怕论坛客户端 ${AppConfig.versionDisplay}',
                    style: TextStyle(
                      color: colorScheme.outline,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Minecraft Bedrock & Java Chinese Community',
                    style: TextStyle(
                      color: colorScheme.outlineVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// 8. 自动签到设置
class _SignSettingsView extends StatefulWidget {
  @override
  State<_SignSettingsView> createState() => _SignSettingsViewState();
}

class _SignSettingsViewState extends State<_SignSettingsView> {
  bool _testingToday = false;

  Future<void> _testTodayNotification() async {
    setState(() => _testingToday = true);
    try {
      // 1. 验证登录状态
      final loginStatus = await KlpbbsApi.checkLoginStatus();
      if (!loginStatus.isLoggedIn && !DioClient.isLoggedIn) {
        PushNotificationService.instance.pushCustomNotification(
          title: '苦力怕论坛 · 今日签到数据',
          body: '当前尚未登录论坛账号，请先登录账号后再查看今日签到数据',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前尚未登录论坛账号，请先登录')),
          );
        }
        return;
      }

      // 2. 实时拉取签到头部数据
      final info = await KlpbbsApi.getSignHeaderInfo(forceRefresh: true);
      final userText = info.username.isNotEmpty
          ? '（${info.username}）'
          : (loginStatus.username != null && loginStatus.username!.isNotEmpty
              ? '（${loginStatus.username}）'
              : '');
      final continuousText =
          info.continuousDays > 0 ? ' | 连续签到 ${info.continuousDays} 天' : '';
      final totalText = info.totalDays > 0 ? ' | 累计打卡 ${info.totalDays} 天' : '';
      final rewardText =
          info.rewardIron.isNotEmpty ? ' | 奖励 +${info.rewardIron} 粒铁粒' : '';

      if (info.isSignedToday) {
        PushNotificationService.instance.pushCustomNotification(
          title: '苦力怕论坛 · 今日签到数据 📅',
          body: '今日状态：已完成打卡$userText$continuousText$totalText$rewardText',
        );
      } else {
        PushNotificationService.instance.pushCustomNotification(
          title: '苦力怕论坛 · 今日签到提醒',
          body: '今日状态：今日尚未签到$userText$continuousText$totalText | 点击前往签到打卡',
        );
      }
    } catch (e) {
      PushNotificationService.instance.pushCustomNotification(
        title: '苦力怕论坛 · 今日签到数据 📅',
        body: '今日数据获取提示：请确认网络连接或登录状态 ($e)',
      );
    } finally {
      if (mounted) {
        setState(() => _testingToday = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sign = AutoSignService.instance;
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: sign,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 顶部状态 Hero Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.surfaceContainerHigh
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border:
                    Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.event_available_rounded,
                        color: colorScheme.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '自动签到管理系统',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (sign.autoSignOnLaunch ||
                                        sign.scheduledSignEnabled ||
                                        sign.burstModeEnabled)
                                    ? colorScheme.primaryContainer
                                    : colorScheme.surfaceContainerHighest
                                        .withAlpha(120),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                (sign.autoSignOnLaunch ||
                                        sign.scheduledSignEnabled ||
                                        sign.burstModeEnabled)
                                    ? '已启用自动化'
                                    : '未启用自动化',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: (sign.autoSignOnLaunch ||
                                          sign.scheduledSignEnabled ||
                                          sign.burstModeEnabled)
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '支持启动检测、每日定时签到与跨天签到，结果可通过应用内提示查看',
                          style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 1. 基础自动签到
            _buildSectionHeader('基础自动化'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side:
                    BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHighest.withAlpha(140),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.rocket_launch_rounded,
                          color: colorScheme.primary, size: 20),
                    ),
                    title: const Text('启动时自动静默打卡',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14.5)),
                    subtitle: const Text('打开应用时自动检测今日打卡状态，未签则后台自动打卡并推送结果',
                        style: TextStyle(fontSize: 14)),
                    value: sign.autoSignOnLaunch,
                    onChanged: (v) => sign.setAutoSignOnLaunch(v),
                  ),
                  Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withAlpha(40)),
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHighest.withAlpha(140),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.notifications_active_rounded,
                          color: colorScheme.primary, size: 20),
                    ),
                    title: const Text('签到结果全平台消息推送',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14.5)),
                    subtitle: const Text(
                        '打卡成功后推送奖励铁粒、经验与连续签到天数（全平台支持系统 Toast 与应用内横幅）',
                        style: TextStyle(fontSize: 14)),
                    value: sign.notifyOnResult,
                    onChanged: (v) => sign.setNotifyOnResult(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 2. 每日定时签到
            _buildSectionHeader('每日定时签到'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side:
                    BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHighest.withAlpha(140),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.alarm_on_rounded,
                          color: colorScheme.primary, size: 20),
                    ),
                    title: const Text('开启每日定时签到',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14.5)),
                    subtitle: const Text('每天到达指定时间时自动探测服务端打卡状态并触发签到',
                        style: TextStyle(fontSize: 14)),
                    value: sign.scheduledSignEnabled,
                    onChanged: (v) => sign.setScheduledSignEnabled(v),
                  ),
                  if (sign.scheduledSignEnabled) ...[
                    Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withAlpha(40)),
                    ListTile(
                      leading: const Icon(Icons.schedule_rounded),
                      title:
                          const Text('定时执行时间', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                          '每天将在 ${sign.scheduledTimeString} 自动打卡（持续探测 ${sign.scheduledWindowSec} 秒）',
                          style: const TextStyle(fontSize: 14)),
                      trailing: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                              hour: sign.scheduledHour,
                              minute: sign.scheduledMinute,
                            ),
                          );
                          if (picked != null) {
                            sign.setScheduledTime(picked.hour, picked.minute);
                          }
                        },
                        child: Text(sign.scheduledTimeString,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                    Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withAlpha(40)),
                    ListTile(
                      leading: const Icon(Icons.timelapse_rounded),
                      title: const Text('定时容差探测区间',
                          style: TextStyle(fontSize: 14)),
                      subtitle: const Text('到达定时后持续探测状态，防止服务端产生秒级延迟',
                          style: TextStyle(fontSize: 14)),
                      trailing: DropdownButton<int>(
                        value: sign.scheduledWindowSec,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 15, child: Text('15 秒')),
                          DropdownMenuItem(value: 30, child: Text('30 秒 (推荐)')),
                          DropdownMenuItem(value: 60, child: Text('60 秒')),
                        ],
                        onChanged: (v) =>
                            v != null ? sign.setScheduledWindowSec(v) : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 3. 零点极速冲榜模式
            _buildSectionHeader('零点自动签到'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side:
                    BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withAlpha(140),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.military_tech_rounded,
                            color: colorScheme.primary, size: 20),
                      ),
                      title: const Text('开启零点自动签到',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14.5)),
                      subtitle: const Text('跨天前校准服务器时钟，跨天后为当前账号提交一次签到',
                          style: TextStyle(fontSize: 14)),
                      value: sign.burstModeEnabled,
                      onChanged: (v) => sign.setBurstModeEnabled(v),
                    ),
                    if (sign.burstModeEnabled) ...[
                      Divider(
                          height: 1,
                          color: colorScheme.outlineVariant.withAlpha(40)),
                      ListTile(
                        title:
                            const Text('签到前检查', style: TextStyle(fontSize: 14)),
                        subtitle: Text(sign.burstStrategy.label,
                            style: const TextStyle(fontSize: 14)),
                        trailing: DropdownButton<BurstStrategy>(
                          value: sign.burstStrategy,
                          underline: const SizedBox(),
                          items: BurstStrategy.values.map((s) {
                            return DropdownMenuItem(
                              value: s,
                              child: Text(s == BurstStrategy.statusPolling
                                  ? '先读取状态，再提交一次'
                                  : '零点直接提交一次'),
                            );
                          }).toList(),
                          onChanged: (v) =>
                              v != null ? sign.setBurstStrategy(v) : null,
                        ),
                      ),
                      Divider(
                          height: 1,
                          color: colorScheme.outlineVariant.withAlpha(40)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('跨天时钟检查间隔',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${sign.burstIntervalMs} ms',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Slider(
                        value: sign.burstIntervalMs.toDouble(),
                        min: 100,
                        max: 1000,
                        divisions: 18,
                        label: '${sign.burstIntervalMs} ms',
                        onChanged: (v) => sign.setBurstIntervalMs(v.round()),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildIntervalChip(sign, '100ms', 100),
                            _buildIntervalChip(sign, '200ms', 200),
                            _buildIntervalChip(sign, '300ms', 300),
                            _buildIntervalChip(sign, '500ms', 500),
                          ],
                        ),
                      ),
                      Divider(
                          height: 1,
                          color: colorScheme.outlineVariant.withAlpha(40)),

                      // 防时钟不同步时间区间
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withAlpha(80),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    colorScheme.outlineVariant.withAlpha(40)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.shield_outlined,
                                      size: 16, color: colorScheme.primary),
                                  const SizedBox(width: 6),
                                  const Text('跨天保护时间区间',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                sign.burstTimeWindowDescription,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: colorScheme.primary,
                                    height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ListTile(
                        title: const Text('提前开跑区间（防服务器时钟比本地快）',
                            style: TextStyle(fontSize: 13.5)),
                        subtitle: Text(
                            '23:59:${(60 - sign.burstPreSeconds).toString().padLeft(2, '0')} 开始进入开跑探测',
                            style: const TextStyle(fontSize: 13)),
                        trailing: DropdownButton<int>(
                          value: sign.burstPreSeconds,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 5, child: Text('提前 5 秒')),
                            DropdownMenuItem(value: 10, child: Text('提前 10 秒')),
                            DropdownMenuItem(
                                value: 15, child: Text('提前 15 秒 (推荐)')),
                            DropdownMenuItem(value: 30, child: Text('提前 30 秒')),
                            DropdownMenuItem(
                                value: 59, child: Text('提前 60 秒 (23:59:00)')),
                          ],
                          onChanged: (v) =>
                              v != null ? sign.setBurstPreSeconds(v) : null,
                        ),
                      ),
                      Divider(
                          height: 1,
                          color: colorScheme.outlineVariant.withAlpha(40)),
                      ListTile(
                        title: const Text('跨天延后区间（防服务器时钟比本地慢）',
                            style: TextStyle(fontSize: 13.5)),
                        subtitle: Text(
                            '跨过零点后持续探测 / 发包至 00:00:${sign.burstPostSeconds.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 13)),
                        trailing: DropdownButton<int>(
                          value: sign.burstPostSeconds,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 10, child: Text('延后 10 秒')),
                            DropdownMenuItem(value: 15, child: Text('延后 15 秒')),
                            DropdownMenuItem(
                                value: 20, child: Text('延后 20 秒 (默认)')),
                            DropdownMenuItem(value: 30, child: Text('延后 30 秒')),
                            DropdownMenuItem(value: 60, child: Text('延后 60 秒')),
                          ],
                          onChanged: (v) =>
                              v != null ? sign.setBurstPostSeconds(v) : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 4. 故障自愈与 502 宕机恢复即签
            _buildSectionHeader('故障自愈与 502 宕机恢复即签'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side:
                    BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHighest.withAlpha(140),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.healing_rounded,
                          color: colorScheme.primary, size: 20),
                    ),
                    title: const Text('502/宕机静默探测与恢复即签',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14.5)),
                    subtitle: const Text(
                        '当论坛出现 502 Bad Gateway / 网关超时 / 503 等异常时，进入静默轻量探测，一旦服务器恢复立即自动打卡',
                        style: TextStyle(fontSize: 14)),
                    value: sign.serverRecoverySignEnabled,
                    onChanged: (val) => sign.setServerRecoverySignEnabled(val),
                  ),
                  if (sign.serverRecoverySignEnabled) ...[
                    Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withAlpha(40)),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                sign.isProbingRecovery
                                    ? Icons.radar_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 16,
                                color: sign.isProbingRecovery
                                    ? colorScheme.tertiary
                                    : colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  sign.isProbingRecovery
                                      ? '当前正在实时探测论坛恢复状态 (已探 ${sign.recoveryProbeCount} 次)'
                                      : '当前探测状态：待命中（无活跃故障）',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: sign.isProbingRecovery
                                        ? colorScheme.tertiary
                                        : colorScheme.primary,
                                  ),
                                ),
                              ),
                              if (sign.isProbingRecovery)
                                FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 2),
                                  ),
                                  onPressed: () =>
                                      sign.startRecoveryProbeLoop(),
                                  child: const Text('立即探针',
                                      style: TextStyle(fontSize: 11)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            sign.isProbingRecovery
                                ? '自适应递增退避间隔 (2s -> 3s -> 5s -> 10s)，采用超轻量 HEAD/GET 探针，零负担捕捉服务器恢复上升沿。'
                                : '若启动检测、定时打卡或手动点击遇到 502/503 网关故障，系统会自动切换至高频探测通道，服务器恢复的第 1 秒内为您完成补签并推送通知。',
                            style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                                height: 1.4),
                          ),
                          if (sign.lastOutageInfo != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withAlpha(60),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '最近捕获异常：HTTP ${sign.lastOutageInfo?.statusCode} (${sign.lastOutageInfo?.title})',
                                style: TextStyle(
                                    fontSize: 11, color: colorScheme.outline),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 5. 后台防杀与常驻保活设置
            _buildSectionHeader('后台防杀与常驻保活指南'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side:
                    BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
              ),
              child: Column(
                children: [
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withAlpha(140),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.shield_moon_rounded,
                            color: colorScheme.primary, size: 20),
                      ),
                      title: const Text('Android 电池白名单与防杀配置教程',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14.5)),
                      subtitle: const Text(
                          '各厂商（小米/华为/OPPO/vivo/三星）后台保活、自启动与忽略电池优化设置',
                          style: TextStyle(fontSize: 14)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withAlpha(90),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    colorScheme.outlineVariant.withAlpha(50)),
                          ),
                          child: Text(
                            '提示：国内 Android 定制系统（MIUI/HyperOS/ColorOS/OriginOS/HarmonyOS）会在息屏后激进查杀后台应用。为确保定时签到准时触发，请对照您的机型完成以下 3 项设置：',
                            style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildGuideCard(
                          title: '通用第 1 步：关闭电池优化（设为无限制）',
                          content:
                              '进入【系统设置】->【应用】->【苦力怕论坛】->【电池/耗电详情】-> 设置为【无限制 / 不优化】。',
                          icon: Icons.battery_charging_full_rounded,
                        ),
                        const SizedBox(height: 10),
                        _buildGuideCard(
                          title: '通用第 2 步：开启自启动与后台活动权限',
                          content:
                              '进入【系统设置】->【权限管理】->【自启动】-> 开启【苦力怕论坛】；并允许【后台活动】。',
                          icon: Icons.power_settings_new_rounded,
                        ),
                        const SizedBox(height: 10),
                        _buildGuideCard(
                          title: '通用第 3 步：多任务卡片锁定',
                          content:
                              '打开手机多任务后台界面 -> 找到「苦力怕论坛」卡片 -> 下拉卡片或长按 -> 点击【小锁图标】锁定常驻。',
                          icon: Icons.lock_outline_rounded,
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('主流厂商详细路径说明：',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 8),
                        _buildVendorTile('小米 / Redmi / HyperOS / MIUI',
                            '手机管家 -> 应用管理 -> 权限 -> 自启动管理（开启）；电池 -> 应用省电策略 -> 设为「无限制」；多任务下拉加锁。'),
                        _buildVendorTile('华为 / 荣耀 / HarmonyOS / MagicOS',
                            '设置 -> 电池 -> 应用启动管理 -> 找到苦力怕论坛 -> 关闭「自动管理」，手动开启「允许自启动/关联启动/后台活动」；设置 -> 电池优化 -> 设为不允许。'),
                        _buildVendorTile('OPPO / 一加 / Realme / ColorOS',
                            '设置 -> 应用 -> 应用管理 -> 苦力怕论坛 -> 耗电管理 -> 开启「允许完全后台行为」与「允许应用自启动」；多任务卡片加锁。'),
                        _buildVendorTile('vivo / iQOO / OriginOS',
                            '设置 -> 电池 -> 后台高耗电 -> 开启「苦力怕论坛」；设置 -> 权限管理 -> 自启动（开启）；多任务卡片下拉锁定。'),
                        _buildVendorTile('三星 / One UI',
                            '设置 -> 应用程序 -> 苦力怕论坛 -> 电池 -> 选择「不受限制」；电池与设备维护 -> 后台限制 -> 移出深度休眠名单。'),
                      ],
                    ),
                  ),
                  Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withAlpha(40)),
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withAlpha(140),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.phone_iphone_rounded,
                            color: colorScheme.primary, size: 20),
                      ),
                      title: const Text('iOS 快捷指令唤醒设置',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14.5)),
                      subtitle: const Text('通过「快捷指令」定时打开应用，配合已启用的启动签到',
                          style: TextStyle(fontSize: 14)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withAlpha(90),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    colorScheme.outlineVariant.withAlpha(50)),
                          ),
                          child: Text(
                            'iOS 可能暂停后台应用。个人自动化可以定时打开应用；签到结果仍取决于登录状态、网络连接和论坛返回，请查看结果提示。',
                            style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildGuideCard(
                          title: '第 1 步：在 App 设置中开启启动自动打卡',
                          content: '在上方【基础自动化】中开启【启动时自动静默打卡】开关。',
                          icon: Icons.rocket_launch_rounded,
                        ),
                        const SizedBox(height: 10),
                        _buildGuideCard(
                          title: '第 2 步：打开 iPhone 的「快捷指令」App',
                          content:
                              '在 iPhone 上打开自带的「快捷指令」应用 -> 点击底部中间的【自动化】标签页。',
                          icon: Icons.touch_app_rounded,
                        ),
                        const SizedBox(height: 10),
                        _buildGuideCard(
                          title: '第 3 步：新建每日特定时间自动化',
                          content:
                              '点击右上角【+】号 -> 选择【特定时间】（如每天 08:00）-> 重复选择【每天】-> 勾选【立即运行】并关闭【运行时通知】。',
                          icon: Icons.alarm_rounded,
                        ),
                        const SizedBox(height: 10),
                        _buildGuideCard(
                          title: '第 4 步：添加执行动作「打开 App」',
                          content:
                              '点击下一步 -> 选择【打开 App】动作 -> 在应用列表中选取【苦力怕论坛】-> 点击【完成】。',
                          icon: Icons.check_circle_rounded,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withAlpha(80),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            '🎉 设置完成后，每天到达指定时间时，iPhone 会自动在后台/前台唤醒「苦力怕论坛」，应用在启动 3 秒内将自动完成打卡并推送打卡成功横幅通知！',
                            style: TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withAlpha(40)),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHighest.withAlpha(140),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.all_inclusive_rounded,
                          color: colorScheme.primary, size: 20),
                    ),
                    title: const Text('生命周期感知与错峰补签保障',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14.5)),
                    subtitle: const Text(
                        '已内置智能补签：若因关机/深度休眠错过准点，在手机解锁或唤醒时会自动立即检测补签',
                        style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 5. 引擎诊断与测试中心
            _buildSectionHeader('测试与诊断中心'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side:
                    BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHighest.withAlpha(140),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        sign.isRunning
                            ? Icons.sync_rounded
                            : Icons.info_outline_rounded,
                        color: colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: const Text('当前服务状态',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(sign.statusMessage,
                        style: const TextStyle(fontSize: 14)),
                  ),
                  if (sign.lastSuccessDate.isNotEmpty) ...[
                    Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withAlpha(40)),
                    ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: const Text('上次自动打卡成功记录',
                          style: TextStyle(fontSize: 14)),
                      subtitle: Text(sign.lastSuccessDate,
                          style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                  Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withAlpha(40)),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: sign.isRunning
                              ? null
                              : () => sign.checkAndAutoSignIn(
                                  triggerSource: '手动签到'),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('立即签到'),
                        ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed:
                              _testingToday ? null : _testTodayNotification,
                          icon: _testingToday
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: AppLoadingIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.today_rounded, size: 18),
                          label: const Text('测试推送今日签到数据'),
                        ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: sign.isRunning
                              ? null
                              : () async {
                                  final report =
                                      await sign.runBurstDiagnosticTest();
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Row(
                                          children: [
                                            Icon(Icons.bolt_rounded,
                                                color: colorScheme.primary),
                                            const SizedBox(width: 8),
                                            const Text('签到读取诊断',
                                                style: TextStyle(fontSize: 16)),
                                          ],
                                        ),
                                        content: SelectableText(
                                          report,
                                          style: const TextStyle(
                                              fontSize: 13, height: 1.4),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('知道了'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                          icon: Icon(Icons.flash_on_rounded,
                              size: 18, color: colorScheme.primary),
                          label: const Text('检查签到接口与时钟'),
                        ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            final report =
                                await sign.runRecoveryDiagnosticProbe();
                            if (context.mounted) {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Row(
                                    children: [
                                      Icon(Icons.radar_rounded,
                                          color: colorScheme.primary),
                                      const SizedBox(width: 8),
                                      const Text('502 探针与恢复诊断',
                                          style: TextStyle(fontSize: 16)),
                                    ],
                                  ),
                                  content: SelectableText(
                                    report,
                                    style: const TextStyle(
                                        fontSize: 13, height: 1.4),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('关闭'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                          icon: Icon(Icons.radar_rounded,
                              size: 18, color: colorScheme.primary),
                          label: const Text('测试 502 探针与服务器健康度'),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            PushNotificationService.instance
                                .pushCustomNotification(
                              title: '苦力怕论坛 · 签到测试通知',
                              body: '签到奖励：+15 粒铁粒 | 经验 +10 EP | 连续签到 100 天',
                            );
                          },
                          icon: const Icon(Icons.notifications_active_outlined,
                              size: 18),
                          label: const Text('测试模拟成功通知'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildIntervalChip(AutoSignService sign, String label, int ms) {
    final isSelected = sign.burstIntervalMs == ms;
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => sign.setBurstIntervalMs(ms),
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? colorScheme.primary : colorScheme.onSurface,
      ),
    );
  }

  Widget _buildGuideCard({
    required String title,
    required String content,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text(content,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorTile(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withAlpha(50),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• $title',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(desc,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.3)),
          ],
        ),
      ),
    );
  }
}

Widget _buildSectionHeader(String title, {String? subtitle}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 3.5,
                  height: 14,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                    child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                    height: 1.35,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                )),
              ],
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 11.5, top: 3),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

Widget _buildSettingCard({
  required BuildContext context,
  required List<Widget> children,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return Material(
    color: colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(
        color: colorScheme.outlineVariant.withAlpha(35),
        width: 0.8,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

Widget _buildSettingSwitchTile({
  required BuildContext context,
  required String title,
  required String subtitle,
  required IconData icon,
  required bool value,
  required ValueChanged<bool>? onChanged,
  Color? iconColor,
  Color? iconBgColor,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    secondary: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: iconBgColor ?? colorScheme.primaryContainer.withAlpha(90),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: iconColor ?? colorScheme.primary,
        size: 20,
      ),
    ),
    title: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 15,
        height: 1.35,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(
        fontSize: 14,
        color: colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    ),
    value: value,
    onChanged: onChanged,
  );
}
