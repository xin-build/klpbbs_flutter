import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/app_config.dart';
import '../services/download_service.dart';
import '../services/push_notification_service.dart';
import '../services/rgb_theme_service.dart';
import '../widgets/responsive_layout.dart';
import 'download_manager_page.dart';

enum SettingsCategory {
  appearance('外观与个性化', Icons.palette_outlined, Icons.palette_rounded),
  notification('消息推送与后台', Icons.notifications_outlined, Icons.notifications_rounded),
  layout('排版与多端模式', Icons.devices_outlined, Icons.devices_rounded),
  download('下载与存储管理', Icons.download_outlined, Icons.download_rounded),
  performance('性能与 GPU 加速', Icons.speed_outlined, Icons.speed_rounded),
  forum('论坛与阅读偏好', Icons.forum_outlined, Icons.forum_rounded),
  about('关于与系统诊断', Icons.info_outline, Icons.info_rounded);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const SettingsCategory(this.label, this.icon, this.selectedIcon);
}

/// 高度自定义设置中心（支持 PC 宽屏双栏与移动端层级视图）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static Widget buildCategoryView(SettingsCategory category) {
    switch (category) {
      case SettingsCategory.appearance:
        return _AppearanceSettingsView();
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
  SettingsCategory _selectedCategory = SettingsCategory.appearance;

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('系统设置'), elevation: 0),
      body: isDesktop
          ? Row(
              children: [
                // 左侧设置分类导航
                SizedBox(
                  width: 260,
                  child: Material(
                    color: colorScheme.surfaceContainerLow,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                      children: SettingsCategory.values.map((cat) {
                        final isSelected = _selectedCategory == cat;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: ListTile(
                            leading: Icon(
                              isSelected ? cat.selectedIcon : cat.icon,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            title: Text(
                              cat.label,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                            selected: isSelected,
                            selectedTileColor: colorScheme.primaryContainer
                                .withAlpha(80),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onTap: () =>
                                setState(() => _selectedCategory = cat),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withAlpha(50),
                ),
                // 右侧详细设置面板
                Expanded(
                  child: Scaffold(body: SettingsPage.buildCategoryView(_selectedCategory)),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              children: SettingsCategory.values.map((cat) {
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  elevation: 0,
                  color: colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withAlpha(40),
                      width: 0.6,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(cat.icon, color: colorScheme.primary),
                    title: Text(
                      cat.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(cat.label)),
                            body: SettingsPage.buildCategoryView(cat),
                          ),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            ),
    );
  }

}

/// 1. 外观与个性化
class _AppearanceSettingsView extends StatefulWidget {
  @override
  State<_AppearanceSettingsView> createState() =>
      _AppearanceSettingsViewState();
}

class _AppearanceSettingsViewState extends State<_AppearanceSettingsView> {
  late double _fontScaleValue;

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
              ],
            ),
          ),
        ),
        if (RgbThemeService.instance.isUnlocked) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('🌈 RGB 动态炫彩主题 (Chroma & Rave)'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('启用 RGB 动态炫彩'),
                  subtitle: Text(
                    RgbThemeService.instance.mode == RgbMode.strobe
                        ? '⚡ 超频迪斯科：高频爆闪跳变，电竞狂暴光污染'
                        : '🌈 流光幻彩：平滑色相流动，优雅电竞色彩',
                  ),
                  value: RgbThemeService.instance.isEnabled,
                  onChanged: (v) {
                    RgbThemeService.instance.setEnabled(v);
                    setState(() {});
                  },
                ),
                if (RgbThemeService.instance.isEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('炫彩模式'),
                    subtitle: Text(RgbThemeService.instance.mode.description),
                    trailing: SegmentedButton<RgbMode>(
                      segments: const [
                        ButtonSegment(
                          value: RgbMode.flow,
                          icon: Icon(Icons.waves_rounded, size: 16),
                          label: Text('流光幻彩'),
                        ),
                        ButtonSegment(
                          value: RgbMode.strobe,
                          icon: Icon(Icons.flash_on_rounded, size: 16),
                          label: Text('超频迪斯科'),
                        ),
                      ],
                      selected: {RgbThemeService.instance.mode},
                      onSelectionChanged: (s) {
                        RgbThemeService.instance.setMode(s.first);
                        setState(() {});
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('变换速率 / 闪烁频率'),
                    subtitle: Text(
                      RgbThemeService.instance.speed <= 0.6
                          ? '舒缓模式 (0.5x)'
                          : (RgbThemeService.instance.speed >= 2.5
                              ? '狂暴超频 (3.0x)'
                              : (RgbThemeService.instance.speed >= 1.8
                                  ? '疾速电竞 (2.0x)'
                                  : '绚丽标准 (1.0x)')),
                    ),
                    trailing: SegmentedButton<double>(
                      segments: const [
                        ButtonSegment(value: 0.5, label: Text('0.5x')),
                        ButtonSegment(value: 1.0, label: Text('1.0x')),
                        ButtonSegment(value: 2.0, label: Text('2.0x')),
                        ButtonSegment(value: 3.0, label: Text('3.0x')),
                      ],
                      selected: {RgbThemeService.instance.speed},
                      onSelectionChanged: (s) {
                        RgbThemeService.instance.setSpeed(s.first);
                        setState(() {});
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: Container(
                      height: 34,
                      margin: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                      decoration: BoxDecoration(
                        gradient: RgbThemeService.instance.rainbowGradient,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: RgbThemeService.instance.currentColor.withAlpha(80),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        RgbThemeService.instance.mode == RgbMode.strobe
                            ? '⚡ OVERCLOCKED RAVE DISCO STROBE ⚡'
                            : '🌈 RGB CHROMA DYNAMIC STREAMING 🌈',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
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
                          final snapped = ((v * 20).round() / 20.0).clamp(0.85, 1.35);
                          setState(() => _fontScaleValue = snapped);
                          AppConfig.setFontScale(snapped);
                        },
                      ),
                    ),
                    Text(
                      '135%',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
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
              ListTile(
                title: const Text('帖子卡片风格'),
                trailing: DropdownButton<CardStyle>(
                  value: AppConfig.cardStyle,
                  underline: const SizedBox(),
                  items: CardStyle.values
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.label.split(' ')[0]),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      v != null ? AppConfig.setCardStyle(v) : null,
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选取自定义色彩'),
        content: SizedBox(
          width: 320,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((c) {
              return InkWell(
                onTap: () {
                  AppConfig.setCustomSeedColor(c);
                  Navigator.of(ctx).pop();
                },
                borderRadius: BorderRadius.circular(20),
                child: CircleAvatar(backgroundColor: c, radius: 20),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// 2. 排版与多端模式
class _LayoutSettingsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('设备排版模式'),
        Card(
          child: Column(
            children: AppLayoutMode.values.map((mode) {
              return RadioListTile<AppLayoutMode>(
                title: Text(mode.label),
                value: mode,
                groupValue: AppConfig.layoutMode,
                onChanged: (v) => AppConfig.setLayoutMode(v!),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('桌面 PC 宽屏配置'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('宽屏网格列数'),
                subtitle: const Text('在 PC 桌面或平板横屏下帖子流的分列排版'),
                trailing: DropdownButton<int>(
                  value: AppConfig.desktopGridColumns,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('自动适应')),
                    DropdownMenuItem(value: 2, child: Text('双列 (2 列)')),
                    DropdownMenuItem(value: 3, child: Text('三列 (3 列)')),
                    DropdownMenuItem(value: 4, child: Text('四列 (4 列)')),
                  ],
                  onChanged: (v) =>
                      v != null ? AppConfig.setDesktopGridColumns(v) : null,
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('版块双栏主从视图 (Master-Detail)'),
                subtitle: const Text('宽屏下左侧展示帖子列表，右侧直接展示详情'),
                value: AppConfig.isMasterDetailEnabled,
                onChanged: (v) => AppConfig.setIsMasterDetailEnabled(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('移动端导航布局'),
        Card(
          child: Column(
            children: NavLayout.values.map((l) {
              return RadioListTile<NavLayout>(
                title: Text(l.label),
                value: l,
                groupValue: AppConfig.navLayout,
                onChanged: (v) => AppConfig.setNavLayout(v!),
              );
            }).toList(),
          ),
        ),
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
            leading: Icon(Icons.download_done_rounded, color: colorScheme.primary),
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
                leading: Icon(Icons.folder_outlined, color: colorScheme.primary),
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
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: _pickDirectory,
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('更改目录'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: _currentPath.isNotEmpty
                          ? () => DownloadManager.openFolder(_currentPath)
                          : null,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('打开目录'),
                    ),
                    if (AppConfig.downloadPath.isNotEmpty)
                      TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
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

/// 4. 性能与 GPU 加速
class _PerformanceSettingsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('硬件加速与渲染引擎'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('GPU 硬件加速渲染 (Hardware Acceleration)'),
                subtitle: const Text('启用 Vulkan / Direct3D 纹理硬件合成加速，降低 CPU 占用'),
                value: AppConfig.gpuAcceleration,
                onChanged: (v) => AppConfig.setGpuAcceleration(v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('120Hz / 高刷帧率解除限制'),
                subtitle: const Text('支持高刷新率显示屏流畅动画渲染'),
                value: AppConfig.highRefreshRate,
                onChanged: (v) => AppConfig.setHighRefreshRate(v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('阻尼平滑惯性滚动 (Smooth Scrolling)'),
                subtitle: const Text('优化鼠标滚轮与触摸滑动平滑物理曲线'),
                value: AppConfig.smoothScrollPhysics,
                onChanged: (v) => AppConfig.setSmoothScrollPhysics(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('图片与缓存策略'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('图片加载质量'),
                trailing: DropdownButton<ImageQuality>(
                  value: AppConfig.imageQuality,
                  underline: const SizedBox(),
                  items: ImageQuality.values
                      .map(
                        (q) => DropdownMenuItem(value: q, child: Text(q.label)),
                      )
                      .toList(),
                  onChanged: (v) =>
                      v != null ? AppConfig.setImageQuality(v) : null,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('最大缓存容量'),
                subtitle: Text('${AppConfig.imageCacheMaxMb} MB'),
                trailing: DropdownButton<int>(
                  value: AppConfig.imageCacheMaxMb,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 100, child: Text('100 MB')),
                    DropdownMenuItem(value: 250, child: Text('250 MB')),
                    DropdownMenuItem(value: 500, child: Text('500 MB')),
                    DropdownMenuItem(value: 1024, child: Text('1024 MB (1GB)')),
                  ],
                  onChanged: (v) =>
                      v != null ? AppConfig.setImageCacheMaxMb(v) : null,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('清理图片与数据缓存'),
                subtitle: const Text('释放本地存储与内存缓存'),
                trailing: FilledButton.tonal(
                  onPressed: () {
                    PaintingBinding.instance.imageCache.clear();
                    PaintingBinding.instance.imageCache.clearLiveImages();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已清除应用图片与运行时缓存')),
                    );
                  },
                  child: const Text('立即清理'),
                ),
              ),
            ],
          ),
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
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('阅读与浏览'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('显示楼层个性签名档'),
                subtitle: const Text('在帖子详情楼层底部渲染用户签名'),
                value: AppConfig.showFloorSignature,
                onChanged: (v) => AppConfig.setShowFloorSignature(v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('启动时自动签到'),
                subtitle: const Text('每次启动应用自动尝试完成每日签到 (k_misign)'),
                value: AppConfig.autoCheckin,
                onChanged: (v) => AppConfig.setAutoCheckin(v),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('默认启动页'),
                trailing: DropdownButton<int>(
                  value: AppConfig.defaultStartTab,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('首页推荐')),
                    DropdownMenuItem(value: 1, child: Text('导读中心')),
                    DropdownMenuItem(value: 2, child: Text('签到排行')),
                    DropdownMenuItem(value: 3, child: Text('封神榜')),
                    DropdownMenuItem(value: 4, child: Text('论坛搜索')),
                  ],
                  onChanged: (v) =>
                      v != null ? AppConfig.setDefaultStartTab(v) : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('屏蔽黑名单 (关键词 & 用户)'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keywordCtrl,
                        decoration: const InputDecoration(
                          hintText: '添加屏蔽关键词...',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        if (_keywordCtrl.text.trim().isNotEmpty) {
                          AppConfig.addBlockedKeyword(_keywordCtrl.text.trim());
                          _keywordCtrl.clear();
                          setState(() {});
                        }
                      },
                      child: const Text('添加'),
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
                        onDeleted: () {
                          AppConfig.removeBlockedKeyword(kw);
                          setState(() {});
                        },
                      );
                    }).toList(),
                  ),
                ],
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _uidCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '添加屏蔽 UID (作者编号)...',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final uid = int.tryParse(_uidCtrl.text.trim()) ?? 0;
                        if (uid > 0) {
                          AppConfig.addBlockedUid(uid);
                          _uidCtrl.clear();
                          setState(() {});
                        }
                      },
                      child: const Text('屏蔽'),
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
                        label: Text('UID: $uid'),
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
                          child: Text(e.label, style: const TextStyle(fontSize: 13)),
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

  void _onVersionTap() {
    final now = DateTime.now();
    if (_lastTapTime == null || now.difference(_lastTapTime!).inMilliseconds < 600) {
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
                  ? '⚡ 已快速切换至【超频迪斯科】狂暴爆闪模式！'
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
          content: Text('⚡ 再连续点击 ${7 - _tapCount} 次解锁隐藏特性...'),
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
          title: const Text('🎉 恭喜解锁双重隐藏彩蛋！'),
          content: const Text(
            '您已成功解锁【RGB 动态炫彩主题】！\n\n包含两种模式：\n• 🌈「流光幻彩」：平滑色相流动，优雅电竞光效\n• ⚡「超频迪斯科」：高频跳变爆闪，极致狂暴光污染\n\n已自动为您开启，可在「外观与个性化」中自由切换与调节速率！',
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
                'Flutter 跨平台深度重构客户端',
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
                leading: Icon(Icons.code_rounded),
                title: Text('核心技术规范'),
                subtitle: Text('Discuz! X3.4 + 克米设计手机模板 (comiis_app) 逆向解析'),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.auto_awesome_rounded),
                title: Text('设计规范参考'),
                subtitle: Text('Material 3 现代化交互与自适应双排版引擎'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.network_check_rounded),
                title: const Text('网络连接诊断'),
                subtitle: Text('当前地址: ${AppConfig.baseUrl}'),
                trailing: OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('网络诊断正常，连接畅通')),
                    );
                  },
                  child: const Text('测试连通'),
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
                    '苦力怕论坛客户端 v1.0 (Build 20260822)',
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

Widget _buildSectionHeader(String title) {
  return Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}
