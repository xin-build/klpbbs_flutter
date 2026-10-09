import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../core/dio_client.dart';
import '../../models/dashboard_card_model.dart';
import '../../pages/func_list_page.dart';
import '../../pages/task_page.dart';
import 'dashboard_card_frame.dart';

/// 当前账号的实际任务分类；读取失败、站点关闭与确认空列表分开显示。
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
  String? _error;
  bool _loading = false;
  int _generation = 0;

  String get _item {
    final value = widget.item.customParams['item'] as String? ?? 'doing';
    return const {'new', 'doing', 'done', 'failed'}.contains(value)
        ? value
        : 'doing';
  }

  void _readCache() {
    _tasks = KlpbbsApi.cachedTasks(_item, ignoreExpired: widget.isPreview);
    _error = DioClient.isLoggedIn ? null : '登录后查看任务';
  }

  Future<void> _openTask({int? id, String? title}) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => id == null
            ? TaskPage(initialItem: _item)
            : FuncListPage(
                title: title ?? '任务详情',
                path: 'home.php?mod=task&do=view&id=$id&mobile=no')));
    if (mounted && !widget.isPreview) _loadTasks(forceRefresh: true);
  }

  void _onAccountChanged() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _loading = false;
      _readCache();
    });
    if (!widget.isPreview) _loadTasks();
  }

  @override
  void initState() {
    super.initState();
    _readCache();
    if (!widget.isPreview) {
      DioClient.sessionChanges.addListener(_onAccountChanged);
      _loadTasks();
    }
  }

  @override
  void dispose() {
    if (!widget.isPreview) {
      DioClient.sessionChanges.removeListener(_onAccountChanged);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TaskDashboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.customParams['item'] !=
        widget.item.customParams['item']) {
      _generation++;
      _readCache();
      if (!widget.isPreview) _loadTasks();
    }
  }

  Future<void> _loadTasks({bool forceRefresh = false}) async {
    if (!DioClient.isLoggedIn || widget.isPreview) return;
    final session = DioClient.sessionKey;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await KlpbbsApi.getTasks(item: _item, forceRefresh: forceRefresh);
      if (mounted &&
          session == DioClient.sessionKey &&
          generation == _generation) {
        setState(() {
          _tasks = list;
        });
      }
    } catch (error) {
      if (mounted &&
          session == DioClient.sessionKey &&
          generation == _generation) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted &&
          session == DioClient.sessionKey &&
          generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = widget.item.rowSpan <= 1;
    final isNarrow = widget.item.colSpan <= 2;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty)
        ? customTitle
        : '成长与每日任务';

    final taskList = _tasks ?? const [];

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        onTap: _openTask,
        child: (isCompact || isNarrow)
            ? _buildCompact(context, title, taskList)
            : _buildExpanded(context, title, taskList),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, String title,
      List<({int id, String name, String reward})> tasks) {
    final colorScheme = Theme.of(context).colorScheme;
    final countText = _error != null
        ? (DioClient.isLoggedIn ? '暂不可用' : '需登录')
        : _tasks == null
            ? (_loading ? '加载中' : '待确认')
            : (tasks.isEmpty ? '暂无任务' : '${tasks.length} 个任务');

    final accent = DashboardCardTheme.of(context).accentColor;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [accent, accent.withAlpha(200)],
            ),
          ),
          child: Icon(
            _item == 'done' ? Icons.task_alt_rounded : Icons.checklist_rounded,
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
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text('以任务中心的进度和奖励为准',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10, color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: accent.withAlpha(30),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            countText,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context, String title,
      List<({int id, String name, String reward})> tasks) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = DashboardCardTheme.of(context).accentColor;
    final maxCount = widget.item.rowSpan >= 3 ? 5 : 3;

    // 只显示任务接口返回的任务；签到状态不能代替任务完成状态。
    final items = <({
      String name,
      String reward,
      Color color,
      bool isCompleted,
      VoidCallback? onTap
    })>[];

    if (tasks.isNotEmpty) {
      for (final t in tasks.take(maxCount)) {
        items.add((
          name: t.name,
          reward: t.reward.isNotEmpty ? t.reward : '查看任务',
          color: accent,
          isCompleted: _item == 'done',
          onTap: () => _openTask(id: t.id, title: t.name),
        ));
      }
    }

    if (items.isEmpty) {
      items.add((
        name: _error != null
            ? (!DioClient.isLoggedIn
                ? '登录后查看任务'
                : _error!.contains('任务关闭')
                    ? '站点任务已关闭'
                    : '任务暂不可用')
            : _tasks == null
                ? (_loading ? '正在读取任务' : '任务状态待确认')
                : '当前分类暂无任务',
        reward: _error == null ? '任务中心' : '查看详情',
        color: colorScheme.onSurfaceVariant,
        isCompleted: false,
        onTap: _openTask,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.checklist_rounded,
                size: 17, color: Colors.cyan.shade700),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            )),
            Text('任务中心 >',
                style: TextStyle(fontSize: 11, color: colorScheme.primary)),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final it in items)
                _buildTaskItem(
                    it.name, it.reward, it.color, it.isCompleted, it.onTap),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskItem(String name, String reward, Color color,
      bool isCompleted, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          children: [
            Icon(
              isCompleted
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
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
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: (isCompleted ? Colors.green : color).withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    reward,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: isCompleted ? Colors.green.shade800 : color,
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
