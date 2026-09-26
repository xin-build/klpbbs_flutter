import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../models/post_floor.dart';
import '../pages/user_space_page.dart';
import 'thread_card.dart';

/// 全功能评分与打赏筛选大厅（支持 2000+ 条超长数据虚拟化流畅滚动、多币种动态胶囊、实时搜索与多维过滤）
class RatingFilterHall extends StatefulWidget {
  final int tid;
  final int pid;
  final List<FloorReward> fallbackRewards;

  const RatingFilterHall({
    super.key,
    required this.tid,
    required this.pid,
    this.fallbackRewards = const [],
  });

  /// 静态弹出方法（自动根据桌面/移动端展示对应形态）
  static Future<void> show(
    BuildContext context, {
    required int tid,
    required int pid,
    List<FloorReward> fallbackRewards = const [],
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 720;

    if (isDesktop) {
      return showDialog(
        context: context,
        barrierColor: Colors.black45,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
            child: RatingFilterHall(
              tid: tid,
              pid: pid,
              fallbackRewards: fallbackRewards,
            ),
          ),
        ),
      );
    } else {
      return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.82,
            child: RatingFilterHall(
              tid: tid,
              pid: pid,
              fallbackRewards: fallbackRewards,
            ),
          ),
        ),
      );
    }
  }

  @override
  State<RatingFilterHall> createState() => _RatingFilterHallState();
}

enum RatingSortMode {
  timeDesc('时间最新'),
  amountDesc('金额最大'),
  amountAsc('金额最小');

  final String label;
  const RatingSortMode(this.label);
}

class _RatingFilterHallState extends State<RatingFilterHall> {
  bool _loading = true;
  List<FloorReward> _allRewards = [];
  String _searchQuery = '';
  String _selectedCurrency = '全部';
  bool _onlyPositive = false;
  RatingSortMode _sortMode = RatingSortMode.timeDesc;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRatings() async {
    setState(() => _loading = true);
    try {
      if (widget.pid > 0) {
        final list = await KlpbbsApi.getRatings(widget.tid, widget.pid);
        if (mounted) {
          setState(() {
            _allRewards = list.isNotEmpty ? list : widget.fallbackRewards;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _allRewards = widget.fallbackRewards;
        _loading = false;
      });
    }
  }

  // 提取可用币种列表及其条数
  Map<String, int> get _currencyCounts {
    final counts = <String, int>{'全部': _allRewards.length};
    for (final r in _allRewards) {
      final c = r.currency;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return counts;
  }

  // 计算多币种汇总统计
  Map<String, int> get _currencySums {
    final sums = <String, int>{};
    for (final r in _allRewards) {
      final c = r.currency;
      sums[c] = (sums[c] ?? 0) + r.numericAmount;
    }
    return sums;
  }

  // 过滤与排序后的展示列表
  List<FloorReward> get _filteredList {
    var list = _allRewards.where((r) {
      if (_searchQuery.isNotEmpty && !r.matches(_searchQuery)) {
        return false;
      }
      if (_selectedCurrency != '全部' && r.currency != _selectedCurrency) {
        return false;
      }
      if (_onlyPositive && !r.isPositive) {
        return false;
      }
      return true;
    }).toList();

    switch (_sortMode) {
      case RatingSortMode.timeDesc:
        // 保持原序即为最新时间倒序
        break;
      case RatingSortMode.amountDesc:
        list.sort((a, b) => b.numericAmount.compareTo(a.numericAmount));
        break;
      case RatingSortMode.amountAsc:
        list.sort((a, b) => a.numericAmount.compareTo(b.numericAmount));
        break;
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyCounts = _currencyCounts;
    final currencySums = _currencySums;
    final displayList = _filteredList;

    return Column(
      children: [
        // 1. 顶部标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  size: 20,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '评分与打赏大厅',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_allRewards.length} 条',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '支持实时模糊过滤、多币种统计与大额排序',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withAlpha(180),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: '重新加载',
                  onPressed: _loadRatings,
                ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        // 2. 动态多币种汇总胶囊徽章（高信息密度横向滚动）
        if (_allRewards.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 参与人数药丸
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withAlpha(160),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_alt_rounded, size: 14, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${_allRewards.length} 人参与',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 各币种累计数额胶囊
                  for (final entry in currencySums.entries) ...[
                    Builder(builder: (ctx) {
                      final c = entry.key;
                      final sum = entry.value;
                      final isIron = c.contains('铁粒');
                      final isContribute = c.contains('贡献');
                      final isPopular = c.contains('人气');

                      Color bg = const Color(0xFF10B981).withAlpha(30);
                      Color fg = const Color(0xFF059669);
                      IconData icon = Icons.monetization_on_rounded;

                      if (isIron) {
                        bg = const Color(0xFFD97706).withAlpha(30);
                        fg = const Color(0xFFB45309);
                        icon = Icons.attach_money_rounded;
                      } else if (isContribute) {
                        bg = const Color(0xFF3B82F6).withAlpha(30);
                        fg = const Color(0xFF1D4ED8);
                        icon = Icons.thumb_up_alt_rounded;
                      } else if (isPopular) {
                        bg = const Color(0xFF8B5CF6).withAlpha(30);
                        fg = const Color(0xFF6D28D9);
                        icon = Icons.local_fire_department_rounded;
                      }

                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: fg.withAlpha(50), width: 0.6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 13, color: fg),
                            const SizedBox(width: 4),
                            Text(
                              '$c ${sum >= 0 ? '+$sum' : '$sum'}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: fg,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),

        const Divider(height: 1),

        // 3. 实时模糊搜索框与排序栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              // 搜索输入框
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '搜索用户名或评分理由...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline.withAlpha(180),
                      ),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withAlpha(60),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: colorScheme.outlineVariant.withAlpha(45),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: colorScheme.outlineVariant.withAlpha(45),
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      setState(() => _searchQuery = v.trim());
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 排序模式下拉菜单
              PopupMenuButton<RatingSortMode>(
                initialValue: _sortMode,
                tooltip: '选择排序方式',
                onSelected: (m) => setState(() => _sortMode = m),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(60),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant.withAlpha(45)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sort_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        _sortMode.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
                itemBuilder: (_) => [
                  for (final m in RatingSortMode.values)
                    PopupMenuItem(
                      value: m,
                      child: Text(m.label, style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ],
          ),
        ),

        // 4. 币种筛选 ChoiceChips 与正向加分开关
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final entry in currencyCounts.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              '${entry.key} (${entry.value})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: _selectedCurrency == entry.key
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            selected: _selectedCurrency == entry.key,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onSelected: (sel) {
                              if (sel) {
                                setState(() => _selectedCurrency = entry.key);
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('仅看加分 (+)', style: TextStyle(fontSize: 11)),
                selected: _onlyPositive,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (v) => setState(() => _onlyPositive = v),
              ),
            ],
          ),
        ),

        const Divider(height: 12),

        // 5. 虚拟化流畅列表（ListView.builder，即便 2000+ 条超长数据也是满帧 0 卡顿）
        Expanded(
          child: _loading && _allRewards.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : displayList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.filter_list_off_rounded,
                            size: 38,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isNotEmpty ? '未找到符合条件的评分记录' : '暂无评分打赏记录',
                            style: TextStyle(fontSize: 13, color: colorScheme.outline),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                      itemCount: displayList.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 8,
                        indent: 44,
                        color: colorScheme.outlineVariant.withAlpha(35),
                      ),
                      itemBuilder: (ctx, idx) {
                        final item = displayList[idx];
                        return _buildListItem(context, item);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildListItem(BuildContext context, FloorReward r) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPos = r.isPositive;

    final badgeBg = isPos
        ? const Color(0xFF10B981).withAlpha(25)
        : const Color(0xFFEF4444).withAlpha(25);
    final badgeFg = isPos ? const Color(0xFF059669) : const Color(0xFFDC2626);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: r.uid != null && r.uid! > 0
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => UserSpacePage(uid: r.uid!)),
              );
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            UserAvatarWidget(
              uid: r.uid,
              author: r.username,
              size: 32,
              faceUrl: null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      if (r.dateline.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          r.dateline,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.outline.withAlpha(150),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.reason.isNotEmpty ? r.reason : '未填写理由',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: badgeFg.withAlpha(50), width: 0.5),
              ),
              child: Text(
                r.amount,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: badgeFg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
