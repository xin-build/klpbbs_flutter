import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/task_page.dart';
import '../../services/auto_sign_service.dart';
import 'dashboard_card_frame.dart';

/// 8. 每日任务中心卡片（对接真实任务列表，动态响应打卡完成状态，自适应行数与进度）
class TaskDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const TaskDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<TaskDashboardCard> createState() => _TaskDashboardCardState();
}

class _TaskDashboardCardState extends State<TaskDashboardCard> {
  List<({int id, String name, String reward})>? _tasks;
  bool _isSignedToday = false;

  @override
  void initState() {
    super.initState();
    _isSignedToday = AutoSignService.instance.isSignedToday();
    if (!widget.isPreview) {
      AutoSignService.instance.addListener(_onAutoSignChanged);
      _loadTasks();
    }
  }

  @override
  void dispose() {
    if (!widget.isPreview) {
      AutoSignService.instance.removeListener(_onAutoSignChanged);
    }
    super.dispose();
  }

  void _onAutoSignChanged() {
    if (!mounted || widget.isPreview) return;
    final nowSigned = AutoSignService.instance.isSignedToday();
    if (nowSigned != _isSignedToday) {
      setState(() {
        _isSignedToday = nowSigned;
      });
    }
  }

  Future<void> _loadTasks() async {
    try {
      final list = await KlpbbsApi.getTasks();
      if (mounted) {
        setState(() {
          _tasks = list;
          _isSignedToday = AutoSignService.instance.isSignedToday();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.item.rowSpan <= 1;
    final isNarrow = widget.item.colSpan <= 2;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '成长与每日任务';

    final taskList = _tasks ?? const [];

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TaskPage())),
        child: (isCompact || isNarrow)
            ? _buildCompact(context, title, taskList)
            : _buildExpanded(context, title, taskList),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, String title, List<({int id, String name, String reward})> tasks) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalCount = tasks.isNotEmpty ? tasks.length : 3;
    final completedCount = _isSignedToday ? 1 : 0;
    final progress = (completedCount / totalCount).clamp(0.0, 1.0);
    final countText = _isSignedToday ? '今日已签到' : '$totalCount 个任务';

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.cyan.shade400, Colors.blue.shade700],
            ),
          ),
          child: Icon(
            _isSignedToday ? Icons.task_alt_rounded : Icons.checklist_rounded,
            size: 18,
            color: Colors.white,
          ),
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
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _isSignedToday ? progress.clamp(0.33, 1.0) : 0.15,
                  minHeight: 4,
                  backgroundColor: colorScheme.outlineVariant.withAlpha(50),
                  color: _isSignedToday ? Colors.green : Colors.cyan,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (_isSignedToday ? Colors.green : Colors.cyan).withAlpha(30),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            countText,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _isSignedToday ? Colors.green.shade800 : Colors.cyan,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context, String title, List<({int id, String name, String reward})> tasks) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxCount = widget.item.rowSpan >= 3 ? 5 : 3;

    // 构建整合任务列表（注入打卡、回帖、点赞等真实任务项与状态）
    final items = <({String name, String reward, Color color, bool isCompleted, VoidCallback? onTap})>[];

    if (tasks.isNotEmpty) {
      for (final t in tasks.take(maxCount)) {
        final isSignTask = t.name.contains('签到') || t.name.contains('打卡') || t.name.contains('登录');
        final isCompleted = isSignTask && _isSignedToday;
        items.add((
          name: t.name,
          reward: isCompleted ? '已完成' : (t.reward.isNotEmpty ? t.reward : '奖励加成'),
          color: isCompleted ? Colors.green : Colors.cyan,
          isCompleted: isCompleted,
          onTap: isSignTask && !_isSignedToday ? _quickSignIn : null,
        ));
      }
    }

    if (items.isEmpty) {
      items.add((
        name: '每日登录打卡',
        reward: _isSignedToday ? '已打卡' : '领 20 铁粒',
        color: Colors.green,
        isCompleted: _isSignedToday,
        onTap: !_isSignedToday ? _quickSignIn : null,
      ));
      items.add((
        name: '回帖互动交流',
        reward: '奖 30 经验',
        color: Colors.cyan,
        isCompleted: false,
        onTap: null,
      ));
      items.add((
        name: '点赞打赏他人',
        reward: '每日成长',
        color: Colors.orange,
        isCompleted: false,
        onTap: null,
      ));
      if (maxCount >= 4) {
        items.add((
          name: '浏览热门资源',
          reward: '活跃度 +10',
          color: Colors.purple,
          isCompleted: false,
          onTap: null,
        ));
      }
      if (maxCount >= 5) {
        items.add((
          name: '分享优质内容',
          reward: '贡献加成',
          color: Colors.indigo,
          isCompleted: false,
          onTap: null,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.checklist_rounded, size: 17, color: Colors.cyan.shade700),
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
            Text('任务中心 >', style: TextStyle(fontSize: 11, color: colorScheme.primary)),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final it in items)
                _buildTaskItem(it.name, it.reward, it.color, it.isCompleted, it.onTap),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskItem(String name, String reward, Color color, bool isCompleted, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          children: [
            Icon(
              isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 14,
              color: isCompleted ? Colors.green : color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isCompleted ? FontWeight.bold : FontWeight.w500,
                  color: isCompleted ? Colors.green.shade800 : null,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: (isCompleted ? Colors.green : color).withAlpha(25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                reward,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: isCompleted ? Colors.green.shade800 : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _quickSignIn() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('正在执行每日签到打卡...'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
    try {
      await AutoSignService.instance.signIn();
      if (mounted) {
        final isSigned = AutoSignService.instance.isSignedToday();
        messenger.showSnackBar(
          SnackBar(
            content: Text(isSigned ? '签到打卡成功！' : AutoSignService.instance.statusMessage),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('签到打卡失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
