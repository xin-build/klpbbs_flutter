import 'package:flutter/material.dart';
import '../../models/dashboard_card_model.dart';
import '../../core/preload_service.dart';
import '../../models/forum.dart';
import 'dashboard_card_frame.dart';

/// 卡片高级参数配置弹窗（可指定版块、跳转子页面、排序、视觉风格与主题色等）
class CardSettingsDialog extends StatefulWidget {
  final DashboardGridItem item;
  final ValueChanged<DashboardGridItem> onSave;

  const CardSettingsDialog({
    super.key,
    required this.item,
    required this.onSave,
  });

  static Future<void> show(
    BuildContext context, {
    required DashboardGridItem item,
    required ValueChanged<DashboardGridItem> onSave,
  }) {
    return showDialog(
      context: context,
      builder: (_) => CardSettingsDialog(item: item, onSave: onSave),
    );
  }

  @override
  State<CardSettingsDialog> createState() => _CardSettingsDialogState();
}

class _CardSettingsDialogState extends State<CardSettingsDialog> {
  late Map<String, dynamic> _params;
  late TextEditingController _titleCtrl;
  late int _targetFid;
  late String _targetPage;
  late String _sortOrder;
  late int _colSpan;
  late int _rowSpan;
  late String _cardStyle;
  late String _cardAccent;
  late String _dataStyle;
  late String _starSource;
  late List<String> _selectedMetrics;
  late int _filterFid;
  late String _rankType;

  List<({int fid, String name})> get _availableForums {
    final groups = PreloadService.instance
            .get<List<ForumGroup>>('forum_groups', ignoreExpired: true) ??
        const [];
    final entries = <int, String>{};
    for (final forum in groups.expand((group) => group.forums)) {
      if (forum.fid > 0 && forum.name.isNotEmpty) {
        entries[forum.fid] = forum.name;
      }
    }
    if (_targetFid > 0) {
      entries.putIfAbsent(_targetFid, () => '版块 ID: $_targetFid');
    }
    if (_filterFid > 0) {
      entries.putIfAbsent(_filterFid, () => '版块 ID: $_filterFid');
    }
    return entries.entries
        .map((entry) => (fid: entry.key, name: entry.value))
        .toList();
  }

  static const List<({String id, String name, IconData icon})> _availablePages =
      [
    (id: 'medal', name: '勋章中心', icon: Icons.military_tech_rounded),
    (id: 'magic', name: '道具中心', icon: Icons.auto_fix_high_rounded),
    (id: 'credit', name: '积分资产', icon: Icons.account_balance_wallet_rounded),
    (id: 'darkroom', name: '小黑屋', icon: Icons.gavel_rounded),
    (id: 'ranklist', name: '全站排行榜', icon: Icons.emoji_events_rounded),
    (id: 'facemall', name: '装扮商城', icon: Icons.face_rounded),
    (id: 'papa_ai', name: '帕帕 AI 助手', icon: Icons.smart_toy_rounded),
    (id: 'task', name: '成长任务', icon: Icons.checklist_rounded),
    (id: 'sign_rank', name: '签到风云榜', icon: Icons.event_available_rounded),
    (id: 'pm', name: '私信收件箱', icon: Icons.mail_rounded),
  ];

  static List<({String key, String label, IconData icon, String desc})>
      getDataStylesForCard(String cardType) {
    switch (cardType) {
      case 'hot_threads':
      case 'forum_feed':
        return const [
          (
            key: 'auto',
            label: '智能自适应',
            icon: Icons.auto_awesome_rounded,
            desc: '根据卡片尺寸自动选择最佳排版'
          ),
          (
            key: 'leaderboard',
            label: '热度排行榜',
            icon: Icons.local_fire_department_rounded,
            desc: '金银铜前三徽章、热度值与阅评统计'
          ),
          (
            key: 'compact',
            label: '紧凑图文行',
            icon: Icons.view_compact_rounded,
            desc: '高密度图文排版，左侧摘要右侧缩略图'
          ),
          (
            key: 'magazine',
            label: '画报大图焦点',
            icon: Icons.view_carousel_rounded,
            desc: '头条 16:9 全景大图焦点 + 精品列表'
          ),
          (
            key: 'minimal',
            label: '极简文字流',
            icon: Icons.format_list_bulleted_rounded,
            desc: '无图纯净文本，极致信息空间利用'
          ),
        ];
      case 'sign_calendar':
        return const [
          (
            key: 'auto',
            label: '智能自适应',
            icon: Icons.auto_awesome_rounded,
            desc: '跟随卡片尺寸动态呈现'
          ),
          (
            key: 'calendar',
            label: '月度日历网格',
            icon: Icons.calendar_month_rounded,
            desc: '按实际月份显示已确认的签到记录'
          ),
          (
            key: 'streak',
            label: '连续签到详情',
            icon: Icons.military_tech_rounded,
            desc: '显示网页返回的连续天数和今日签到状态'
          ),
          (
            key: 'week',
            label: '7天周打卡胶囊',
            icon: Icons.view_week_rounded,
            desc: '横向 7 天圆环打卡流，轻巧灵动'
          ),
          (
            key: 'minimal',
            label: '极简打卡条',
            icon: Icons.horizontal_rule_rounded,
            desc: '单行极简状态栏与一键快捷签到'
          ),
        ];
      case 'sign_fortune':
        return const [
          (
            key: 'auto',
            label: '智能自适应',
            icon: Icons.auto_awesome_rounded,
            desc: '跟随尺寸自适应呈现'
          ),
          (
            key: 'fortune_card',
            label: '游戏提示详情',
            icon: Icons.style_rounded,
            desc: '本地游戏提示与当前账号的签到状态'
          ),
          (
            key: 'compact',
            label: '紧凑游戏提示',
            icon: Icons.view_headline_rounded,
            desc: '单行运势胶囊与快捷签到'
          ),
        ];
      case 'user_profile':
        return const [
          (
            key: 'auto',
            label: '智能自适应',
            icon: Icons.auto_awesome_rounded,
            desc: '跟随尺寸自适应呈现'
          ),
          (
            key: 'detailed',
            label: '全能资料大卡',
            icon: Icons.badge_rounded,
            desc: '头像挂件、用户组、三维资产与升级经验'
          ),
          (
            key: 'compact',
            label: '紧凑名片行',
            icon: Icons.person_rounded,
            desc: '头像昵称与核心资产快速行'
          ),
        ];
      case 'server_status':
        return const [
          (
            key: 'auto',
            label: '智能自适应',
            icon: Icons.auto_awesome_rounded,
            desc: '跟随尺寸自适应呈现'
          ),
          (
            key: 'detailed',
            label: '多节点监控仪表',
            icon: Icons.dns_rounded,
            desc: '各服延迟、TPS、在线人数指标'
          ),
          (
            key: 'simple',
            label: '简易状态指示胶囊',
            icon: Icons.sensors_rounded,
            desc: '在线状态灯与综合人数'
          ),
        ];
      case 'forum_nav':
        return const [
          (
            key: 'auto',
            label: '智能自适应',
            icon: Icons.auto_awesome_rounded,
            desc: '跟随尺寸自适应呈现'
          ),
          (
            key: 'grid',
            label: '图标网格矩阵',
            icon: Icons.grid_view_rounded,
            desc: '高识别度板块大图标网格'
          ),
          (
            key: 'chips',
            label: '紧凑胶囊标签流',
            icon: Icons.label_outline_rounded,
            desc: '自适应流动胶囊标签'
          ),
        ];
      case 'ranklist_card':
        return const [
          (
            key: 'auto',
            label: '智能自适应',
            icon: Icons.auto_awesome_rounded,
            desc: '跟随尺寸自适应呈现'
          ),
          (
            key: 'podium',
            label: '领奖台高光大卡',
            icon: Icons.emoji_events_rounded,
            desc: '冠亚季军高光台座 + 榜单列表'
          ),
          (
            key: 'list',
            label: '经典序号排行榜',
            icon: Icons.format_list_numbered_rounded,
            desc: '规整序号排名列表'
          ),
        ];
      case 'tuhao_stats':
        return const [
          (
            key: 'auto',
            label: '自适应轮播',
            icon: Icons.auto_awesome_rounded,
            desc: '广播轮播与横向统计'
          ),
          (
            key: 'podium',
            label: '焦点轮播',
            icon: Icons.emoji_events_rounded,
            desc: '突出作者头像与广播内容'
          ),
          (
            key: 'list',
            label: '紧凑列表',
            icon: Icons.view_list_rounded,
            desc: '紧凑轮播与逐行统计'
          ),
        ];
      default:
        return const [];
    }
  }

  @override
  void initState() {
    super.initState();
    _params = Map<String, dynamic>.from(widget.item.customParams);
    _titleCtrl =
        TextEditingController(text: _params['customTitle'] as String? ?? '');
    _targetFid = (_params['targetFid'] as num?)?.toInt() ?? 0;
    _targetPage = _params['targetPage'] as String? ?? 'medal';
    _sortOrder = _params['sortOrder'] as String? ??
        (widget.item.cardType == 'hot_threads' ? 'hot' : 'lastpost');
    _colSpan = widget.item.colSpan;
    _rowSpan = widget.item.rowSpan;
    _cardStyle =
        DashboardCardStyle.fromString(_params['cardStyle'] as String?).name;
    _cardAccent =
        DashboardCardAccent.fromString(_params['cardAccent'] as String?).name;
    _dataStyle = _params['dataStyle'] as String? ?? 'auto';
    _starSource = _params['starSource'] as String? ?? 'auto';
    final rawMetrics = _params['metrics'];
    if (rawMetrics is List && rawMetrics.isNotEmpty) {
      _selectedMetrics = List<String>.from(rawMetrics.map((e) => e.toString()));
    } else {
      _selectedMetrics = ['todayPosts', 'yesterdayPosts', 'totalMembers'];
    }
    _filterFid = (_params['filterFid'] as num?)?.toInt() ?? 0;
    _rankType = _params['rankType'] as String? ?? 'auto';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final def = CardRegistry.get(widget.item.cardType);
    final availableDataStyles = getDataStylesForCard(widget.item.cardType);

    return AlertDialog(
      key: const ValueKey('card-settings-dialog'),
      title: Row(
        children: [
          Icon(def.icon, color: colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text('配置卡片 · ${def.name}', style: theme.textTheme.titleMedium),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 自定义标题覆盖
              TextField(
                controller: _titleCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '卡片自定义标题（选填）',
                  hintText: '默认使用: ${def.name}',
                  prefixIcon: const Icon(Icons.title_rounded, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),

              Text('卡片外观', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              DashboardCardFrame(
                key: const ValueKey('card-appearance-preview'),
                item: widget.item.copyWith(customParams: {
                  ..._params,
                  'cardStyle': _cardStyle,
                  'cardAccent': _cardAccent,
                }),
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(def.icon,
                      color: DashboardCardAccent.fromString(_cardAccent)
                          .resolve(context,
                              fallback:
                                  DashboardCardFrame.getNaturalCategoryAccent(
                                      widget.item.cardType, context))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        _titleCtrl.text.trim().isNotEmpty
                            ? _titleCtrl.text.trim()
                            : def.name,
                        style: theme.textTheme.titleSmall),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final style in DashboardCardStyle.values)
                    Tooltip(
                      message: style.description,
                      child: ChoiceChip(
                        key: ValueKey('card-style-${style.name}'),
                        label: Text(style.label),
                        selected: _cardStyle == style.name,
                        onSelected: (_) =>
                            setState(() => _cardStyle = style.name),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('强调色', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final accent in DashboardCardAccent.values)
                    ChoiceChip(
                      key: ValueKey('card-accent-${accent.name}'),
                      avatar: accent == DashboardCardAccent.auto
                          ? const Icon(Icons.palette_outlined, size: 18)
                          : CircleAvatar(
                              radius: 8,
                              backgroundColor: accent.resolve(context)),
                      label: Text(accent.label),
                      selected: _cardAccent == accent.name,
                      onSelected: (_) =>
                          setState(() => _cardAccent = accent.name),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // 2. 如果是指定版块流卡片或发帖卡片 -> 允许选择指定版块
              if (widget.item.cardType == 'forum_feed' ||
                  widget.item.cardType == 'quick_post') ...[
                Text(
                  '指定关联展示版块',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value:
                      _availableForums.any((forum) => forum.fid == _targetFid)
                          ? _targetFid
                          : null,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.forum_outlined, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  items: _availableForums.map((f) {
                    return DropdownMenuItem(
                      value: f.fid,
                      child: Text(f.name),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _targetFid = v);
                  },
                ),
                const SizedBox(height: 14),
                // 排序模式
                Text(
                  '帖子流排序规则',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('最新回复')),
                        selected: _sortOrder == 'lastpost',
                        onSelected: (s) =>
                            setState(() => _sortOrder = 'lastpost'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('最新发布')),
                        selected: _sortOrder == 'dateline',
                        onSelected: (s) =>
                            setState(() => _sortOrder = 'dateline'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('全站精华')),
                        selected: _sortOrder == 'digest',
                        onSelected: (s) =>
                            setState(() => _sortOrder = 'digest'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // 3. 如果是自选传送门卡片 -> 允许选择跳转的目标页面
              if (widget.item.cardType == 'page_portal') ...[
                Text(
                  '传送门目标页面',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _targetPage,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.launch_rounded, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  items: _availablePages.map((p) {
                    return DropdownMenuItem(
                      value: p.id,
                      child: Row(
                        children: [
                          Icon(p.icon, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(p.name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _targetPage = v);
                  },
                ),
                const SizedBox(height: 14),
              ],

              // 4. 今日之星与全站统计卡片专属数据配置
              if (widget.item.cardType == 'tuhao_stats') ...[
                Text(
                  '榜首数据展示来源',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('智能推荐')),
                        selected: _starSource == 'auto',
                        onSelected: (s) => setState(() => _starSource = 'auto'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('签到之星')),
                        selected: _starSource == 'sign_star',
                        onSelected: (s) =>
                            setState(() => _starSource = 'sign_star'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('全站广播')),
                        selected: _starSource == 'tuhao',
                        onSelected: (s) =>
                            setState(() => _starSource = 'tuhao'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '展示核心统计指标 (最多选3项)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in const [
                      ('todayPosts', '今日新帖'),
                      ('yesterdayPosts', '昨日发帖'),
                      ('totalPosts', '全站总帖'),
                      ('totalMembers', '总会员数'),
                    ])
                      FilterChip(
                        label: Text(entry.$2),
                        selected: _selectedMetrics.contains(entry.$1),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              if (_selectedMetrics.length < 3) {
                                _selectedMetrics.add(entry.$1);
                              }
                            } else {
                              if (_selectedMetrics.length > 1) {
                                _selectedMetrics.remove(entry.$1);
                              }
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // 5. 全站热帖榜数据与排序维度配置
              if (widget.item.cardType == 'hot_threads') ...[
                Text(
                  '帖子排序与榜单维度',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('互动排序')),
                        selected: _sortOrder == 'hot',
                        onSelected: (s) => setState(() => _sortOrder = 'hot'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('最多回复')),
                        selected: _sortOrder == 'replies',
                        onSelected: (s) =>
                            setState(() => _sortOrder = 'replies'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('最高阅读')),
                        selected: _sortOrder == 'views',
                        onSelected: (s) => setState(() => _sortOrder = 'views'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '筛选版块范围',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: _filterFid,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.filter_list_rounded, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('当前列表的全部版块')),
                    ..._availableForums.map((f) =>
                        DropdownMenuItem(value: f.fid, child: Text(f.name))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _filterFid = v);
                  },
                ),
                const SizedBox(height: 14),
              ],

              // 6. 签到风云榜分类选择
              if (widget.item.cardType == 'ranklist_card') ...[
                Text(
                  '榜单分类展示',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('签到风云榜 (推荐)'),
                      selected: _rankType == 'auto' || _rankType == 'sign',
                      onSelected: (s) => setState(() => _rankType = 'sign'),
                    ),
                    ChoiceChip(
                      label: const Text('发帖排行榜'),
                      selected: _rankType == 'posts',
                      onSelected: (s) => setState(() => _rankType = 'posts'),
                    ),
                    ChoiceChip(
                      label: const Text('积分财富榜'),
                      selected: _rankType == 'credits',
                      onSelected: (s) => setState(() => _rankType = 'credits'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // 2. 数据展示样式（根据卡片类型展示专属可选排版）
              if (availableDataStyles.isNotEmpty) ...[
                Text(
                  '卡片数据展示样式',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Column(
                  children: availableDataStyles.map((s) {
                    final isSelected = _dataStyle == s.key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        onTap: () => setState(() => _dataStyle = s.key),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: isSelected
                                ? colorScheme.primary.withAlpha(20)
                                : colorScheme.surfaceContainerHighest
                                    .withAlpha(50),
                            border: Border.all(
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant.withAlpha(70),
                              width: isSelected ? 1.5 : 0.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(s.icon,
                                  size: 20,
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.label,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? colorScheme.primary
                                            : colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      s.desc,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: colorScheme.outline),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    size: 18, color: colorScheme.primary),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],

              // 3. 卡片尺寸调节
              Text(
                '卡片占用尺寸',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    // 宽度调节
                    Row(
                      children: [
                        const Icon(Icons.swap_horiz_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              '宽度: $_colSpan 列 (范围: ${def.minColSpan} ~ ${def.maxColSpan})',
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.remove, size: 14),
                          visualDensity: VisualDensity.compact,
                          onPressed: _colSpan > def.minColSpan
                              ? () => setState(() => _colSpan--)
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('$_colSpan',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.add, size: 14),
                          visualDensity: VisualDensity.compact,
                          onPressed: _colSpan < def.maxColSpan
                              ? () => setState(() => _colSpan++)
                              : null,
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    // 高度调节
                    Row(
                      children: [
                        const Icon(Icons.swap_vert_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              '高度: $_rowSpan 行 (范围: ${def.minRowSpan} ~ ${def.maxRowSpan})',
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.remove, size: 14),
                          visualDensity: VisualDensity.compact,
                          onPressed: _rowSpan > def.minRowSpan
                              ? () => setState(() => _rowSpan--)
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('$_rowSpan',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.add, size: 14),
                          visualDensity: VisualDensity.compact,
                          onPressed: _rowSpan < def.maxRowSpan
                              ? () => setState(() => _rowSpan++)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text('应用设置'),
          onPressed: () {
            final forumMatch = _availableForums.firstWhere(
              (f) => f.fid == _targetFid,
              orElse: () => (
                fid: _targetFid,
                name: _targetFid > 0 ? '版块 ID: $_targetFid' : '请选择版块'
              ),
            );
            final pageMatch = _availablePages.firstWhere(
              (p) => p.id == _targetPage,
              orElse: () => (
                id: 'medal',
                name: '勋章中心',
                icon: Icons.military_tech_rounded
              ),
            );

            _params['customTitle'] = _titleCtrl.text.trim();
            _params['targetFid'] = _targetFid;
            _params['forumName'] = forumMatch.name;
            _params['targetPage'] = _targetPage;
            _params['pageName'] = pageMatch.name;
            _params['sortOrder'] = _sortOrder;
            _params['cardStyle'] = _cardStyle;
            _params['cardAccent'] = _cardAccent;
            _params['dataStyle'] = _dataStyle;
            _params['starSource'] = _starSource;
            _params['metrics'] = _selectedMetrics;
            _params['filterFid'] = _filterFid;
            _params['rankType'] = _rankType;

            final updated = widget.item.copyWith(
              colSpan: _colSpan,
              rowSpan: _rowSpan,
              customParams: _params,
            );
            widget.onSave(updated);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
