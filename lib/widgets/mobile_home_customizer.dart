import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_config.dart';

/// 移动端首页轻量组件元数据
class MobileSectionMeta {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const MobileSectionMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

/// 快捷金刚区元数据
class QuickActionMeta {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final int tabIndex;

  const QuickActionMeta({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.tabIndex,
  });
}

/// 移动端首页定制器（专为手机小屏打造的极简优雅设置面板，避免 PC 风格复杂网格的拥挤与繁杂）
class MobileHomeCustomizer extends StatefulWidget {
  const MobileHomeCustomizer({super.key});

  /// 呼出底部面板或弹窗
  static Future<void> show(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 700;
    if (isDesktop) {
      return showDialog(
        context: context,
        builder: (_) => const Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: SizedBox(
            width: 520,
            child: MobileHomeCustomizer(),
          ),
        ),
      );
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MobileBottomSheetWrapper(
        child: MobileHomeCustomizer(),
      ),
    );
  }

  /// 所有支持的首页组件元数据字典
  static const Map<String, MobileSectionMeta> allSections = {
    'horn_banner': MobileSectionMeta(
      id: 'horn_banner',
      title: '全站小喇叭公告',
      subtitle: '置顶广播与社区通知跑马灯',
      icon: Icons.campaign_rounded,
      color: Color(0xFFE91E63),
    ),
    'stats': MobileSectionMeta(
      id: 'stats',
      title: '站点数据统计',
      subtitle: '今日/昨日发帖、帖子总数与会员数',
      icon: Icons.analytics_outlined,
      color: Color(0xFF2196F3),
    ),
    'quick_actions': MobileSectionMeta(
      id: 'quick_actions',
      title: '快捷金刚区',
      subtitle: '高频功能快捷入口（支持 4~8 项）',
      icon: Icons.grid_view_rounded,
      color: Color(0xFF00BCD4),
    ),
    'forum_nav': MobileSectionMeta(
      id: 'forum_nav',
      title: '原版版块导航',
      subtitle: '各大分区版块横向分类与收藏管理',
      icon: Icons.category_outlined,
      color: Color(0xFFFF9800),
    ),
    'carousel': MobileSectionMeta(
      id: 'carousel',
      title: '精华推荐轮播',
      subtitle: '精选精华帖子大图轮播展示',
      icon: Icons.view_carousel_outlined,
      color: Color(0xFF9C27B0),
    ),
  };

  /// 所有可选的快捷功能
  static const List<QuickActionMeta> allQuickActions = [
    QuickActionMeta(
      id: 'papa_ai',
      label: '帕帕 AI',
      icon: Icons.smart_toy_rounded,
      color: Color(0xFF008AC5),
      tabIndex: 15,
    ),
    QuickActionMeta(
      id: 'forum_nav',
      label: '版块导航',
      icon: Icons.forum_outlined,
      color: Color(0xFF00A2FF),
      tabIndex: 1,
    ),
    QuickActionMeta(
      id: 'checkin',
      label: '今日签到',
      icon: Icons.event_available,
      color: Color(0xFF4CAF50),
      tabIndex: 2,
    ),
    QuickActionMeta(
      id: 'medals',
      label: '勋章中心',
      icon: Icons.military_tech,
      color: Color(0xFF9C27B0),
      tabIndex: 3,
    ),
    QuickActionMeta(
      id: 'guide',
      label: '导读精选',
      icon: Icons.local_fire_department,
      color: Color(0xFFFF7043),
      tabIndex: 10,
    ),
    QuickActionMeta(
      id: 'search',
      label: '全站搜索',
      icon: Icons.search,
      color: Color(0xFF00ACC1),
      tabIndex: 11,
    ),
    QuickActionMeta(
      id: 'rank_god',
      label: '封神榜',
      icon: Icons.gavel,
      color: Colors.redAccent,
      tabIndex: 12,
    ),
    QuickActionMeta(
      id: 'rank_board',
      label: '排行榜',
      icon: Icons.leaderboard,
      color: Color(0xFF7E57C2),
      tabIndex: 13,
    ),
    QuickActionMeta(
      id: 'favorites',
      label: '我的收藏',
      icon: Icons.star_rounded,
      color: Color(0xFFFFA000),
      tabIndex: 17,
    ),
    QuickActionMeta(
      id: 'my_threads',
      label: '我的主题',
      icon: Icons.article_outlined,
      color: Color(0xFF00897B),
      tabIndex: 18,
    ),
    QuickActionMeta(
      id: 'tasks',
      label: '任务中心',
      icon: Icons.assignment_turned_in_outlined,
      color: Color(0xFF3949AB),
      tabIndex: 16,
    ),
    QuickActionMeta(
      id: 'post_new',
      label: '发布新帖',
      icon: Icons.edit_note_rounded,
      color: Color(0xFF009688),
      tabIndex: 19,
    ),
  ];

  @override
  State<MobileHomeCustomizer> createState() => _MobileHomeCustomizerState();
}

class _MobileBottomSheetWrapper extends StatelessWidget {
  final Widget child;

  const _MobileBottomSheetWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final maxSheetHeight = media.size.height * 0.88;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖拽手柄
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class _MobileHomeCustomizerState extends State<MobileHomeCustomizer> {
  late List<String> _sections;
  late List<String> _quickActions;

  @override
  void initState() {
    super.initState();
    _loadFromConfig();
  }

  void _loadFromConfig() {
    _sections = List.from(AppConfig.mobileHomeSections);
    // 确保包含全部模块（未启用的排在后方）
    for (final key in MobileHomeCustomizer.allSections.keys) {
      if (!_sections.contains(key)) {
        _sections.add(key);
      }
    }
    _quickActions = List.from(AppConfig.mobileQuickActions);
  }

  bool _isSectionActive(String id) {
    return AppConfig.mobileHomeSections.contains(id);
  }

  void _toggleSection(String id) {
    HapticFeedback.lightImpact();
    setState(() {
      final current = List<String>.from(AppConfig.mobileHomeSections);
      if (current.contains(id)) {
        if (current.length <= 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('至少保留一个首页组件以保证正常浏览'),
              duration: Duration(milliseconds: 1500),
            ),
          );
          return;
        }
        current.remove(id);
      } else {
        current.add(id);
      }
      AppConfig.setMobileHomeSections(current);
    });
  }

  void _moveSection(int index, int delta) {
    final targetIndex = index + delta;
    if (targetIndex < 0 || targetIndex >= _sections.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      final item = _sections.removeAt(index);
      _sections.insert(targetIndex, item);
      // 同步只保留当前启用的顺序
      final newActive = _sections.where((id) => _isSectionActive(id)).toList();
      AppConfig.setMobileHomeSections(newActive);
    });
  }

  void _toggleQuickAction(String id) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_quickActions.contains(id)) {
        if (_quickActions.length <= 4) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('金刚区最少保留 4 个快捷功能'),
              duration: Duration(milliseconds: 1500),
            ),
          );
          return;
        }
        _quickActions.remove(id);
      } else {
        if (_quickActions.length >= 8) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('金刚区最多容纳 8 个快捷功能，保持屏幕清爽'),
              duration: Duration(milliseconds: 1500),
            ),
          );
          return;
        }
        _quickActions.add(id);
      }
      AppConfig.setMobileQuickActions(_quickActions);
    });
  }

  Future<void> _applyPreset(String key) async {
    HapticFeedback.mediumImpact();
    await AppConfig.applyMobileHomePreset(key);
    if (!mounted) return;
    setState(() {
      _loadFromConfig();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已应用所选首页预设方案'),
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  Future<void> _resetDefault() async {
    HapticFeedback.lightImpact();
    await AppConfig.resetMobileHomeConfig();
    if (!mounted) return;
    setState(() => _loadFromConfig());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复移动端默认布局')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题与操作栏
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.phone_android_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '移动端首页自定义',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '轻量定制组件与金刚区，保持简洁优雅',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _resetDefault,
                child: const Text('恢复默认'),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: '完成',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 预设模式快捷切换
          Text(
            '常用预设方案',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip('classic', '🌟 标准全能', '全部组件 + 8个快捷功能'),
              _buildPresetChip('minimal', '⚡ 极简流畅', '仅金刚区与推荐，轻快省流'),
              _buildPresetChip('nav', '📖 导航优先', '喇叭公告 + 4快捷 + 版块导航'),
            ],
          ),
          const SizedBox(height: 18),

          // 区域一：首页组件启闭与次序
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '首页组件显隐与排序',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              Text(
                '上下箭头调整顺序',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(90),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withAlpha(80),
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sections.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 52,
                color: colorScheme.outlineVariant.withAlpha(50),
              ),
              itemBuilder: (context, index) {
                final id = _sections[index];
                final meta = MobileHomeCustomizer.allSections[id];
                if (meta == null) return const SizedBox.shrink();
                final isActive = _isSectionActive(id);

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isActive ? meta.color.withAlpha(25) : colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      meta.icon,
                      size: 20,
                      color: isActive ? meta.color : colorScheme.outline,
                    ),
                  ),
                  title: Text(
                    meta.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive ? colorScheme.onSurface : colorScheme.outline,
                    ),
                  ),
                  subtitle: Text(
                    meta.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.outline,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 上下调整次序按钮
                      IconButton(
                        icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        tooltip: '上移',
                        onPressed: index > 0 ? () => _moveSection(index, -1) : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward_rounded, size: 17),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        tooltip: '下移',
                        onPressed: index < _sections.length - 1 ? () => _moveSection(index, 1) : null,
                      ),
                      const SizedBox(width: 4),
                      Switch(
                        value: isActive,
                        onChanged: (_) => _toggleSection(id),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // 区域二：金刚区快捷功能挑选
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '金刚区快捷功能（4 ~ 8 项）',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _quickActions.length == 4
                      ? Colors.teal.withAlpha(30)
                      : colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _quickActions.length == 4
                      ? '已选 4 项 (极简单行)'
                      : '已选 ${_quickActions.length}/8 项 (舒展双行)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _quickActions.length == 4
                        ? Colors.teal
                        : colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '提示：选择 4 个功能时将以单行展示，节省宝贵纵向屏幕空间；5~8 个功能展示双行。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),

          // 快捷功能 Chip 矩阵
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: MobileHomeCustomizer.allQuickActions.map((action) {
              final isSelected = _quickActions.contains(action.id);
              return FilterChip(
                label: Text(action.label),
                avatar: Icon(
                  action.icon,
                  size: 16,
                  color: isSelected ? action.color : colorScheme.outline,
                ),
                selected: isSelected,
                selectedColor: action.color.withAlpha(35),
                checkmarkColor: action.color,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                ),
                onSelected: (_) => _toggleQuickAction(action.id),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String key, String title, String subtitle) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ActionChip(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      avatar: const Icon(Icons.auto_awesome_rounded, size: 14),
      label: Text(title),
      tooltip: subtitle,
      backgroundColor: colorScheme.surfaceContainerHigh,
      onPressed: () => _applyPreset(key),
    );
  }
}
