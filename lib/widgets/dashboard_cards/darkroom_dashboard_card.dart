import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../models/darkroom_entry.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/darkroom_page.dart';
import 'dashboard_card_frame.dart';

/// 16. 小黑屋动态卡片（对接真实全站封禁公示数据，支持 GPU 隔离与 LOD 尺寸自适应）
class DarkroomDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const DarkroomDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<DarkroomDashboardCard> createState() => _DarkroomDashboardCardState();
}

class _DarkroomDashboardCardState extends State<DarkroomDashboardCard> {
  List<DarkroomEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.isPreview) {
      _entries = const [
        DarkroomEntry(uid: 10001, username: '违规推广账号', reason: '发布批量违规推广信息', action: '永久封禁', dateline: '今天 12:30'),
        DarkroomEntry(uid: 10002, username: '社区违规灌水', reason: '短时间内无意义恶意刷帖', action: '禁言 7 天', dateline: '今天 09:15'),
      ];
      _loading = false;
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    try {
      final res = await KlpbbsApi.getDarkroom(page: 1);
      if (mounted) {
        setState(() {
          _entries = res.entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.item.rowSpan <= 1;
    final isNarrow = widget.item.colSpan <= 2;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '小黑屋公示';

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DarkroomPage())),
        child: _loading
            ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            : (isCompact || isNarrow)
                ? _buildCompact(context, title)
                : _buildExpanded(context, title),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    final first = _entries.isNotEmpty ? _entries.first : null;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withAlpha(30),
          ),
          child: const Icon(Icons.gavel_rounded, size: 18, color: Colors.red),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              Text(
                first != null ? '${first.username} · ${first.action}' : '全站最新违规处罚公示',
                maxLines: 1,
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.outline),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.gavel_rounded, size: 17, color: Colors.red),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Text('查看公示 >', style: TextStyle(fontSize: 11, color: colorScheme.primary)),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _entries.isEmpty
              ? Center(
                  child: Text(
                    '近期暂无违规公示记录',
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                )
              : ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _entries.take(widget.item.rowSpan > 2 ? 4 : 2).length,
                  separatorBuilder: (_, __) => const Divider(height: 8),
                  itemBuilder: (context, idx) {
                    final e = _entries[idx];
                    return _buildBanRecord(e.username, e.reason, e.action);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBanRecord(String user, String reason, String action) {
    return Row(
      children: [
        const Icon(Icons.person_off_rounded, size: 14, color: Colors.red),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$user · $reason',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.red.withAlpha(25),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(action, style: const TextStyle(fontSize: 9.5, color: Colors.red, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
