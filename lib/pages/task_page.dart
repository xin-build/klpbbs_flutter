import '../widgets/app_motion.dart';
import 'package:flutter/material.dart';
import '../widgets/sliver_two_column_feed.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../models/server_outage_info.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/server_outage_view.dart';
import '../widgets/smooth_scroll_controller.dart';
import 'func_list_page.dart';
import 'login_page.dart';

typedef TaskSummary = ({int id, String name, String reward});

class TaskPage extends StatefulWidget {
  final String initialItem;
  const TaskPage({super.key, this.initialItem = 'new'});
  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage>
    with SingleTickerProviderStateMixin {
  static const _categories = [
    ('new', '新任务'),
    ('doing', '进行中'),
    ('done', '已完成'),
    ('failed', '已失败'),
  ];
  late final TabController _tabs;
  final SmoothScrollController _scroll = SmoothScrollController();
  late Future<List<TaskSummary>> _future;
  late String _item;

  @override
  void initState() {
    super.initState();
    final index =
        _categories.indexWhere((category) => category.$1 == widget.initialItem);
    _item = index < 0 ? 'new' : widget.initialItem;
    _tabs = TabController(
        length: _categories.length,
        initialIndex: index < 0 ? 0 : index,
        vsync: this)
      ..addListener(_changed);
    _load();
    DioClient.sessionChanges.addListener(_refresh);
  }

  void _load({bool refresh = false}) {
    _future = DioClient.isLoggedIn
        ? KlpbbsApi.getTasks(item: _item, forceRefresh: refresh)
        : Future.value(const <TaskSummary>[]);
    // Observe errors even if this request completes before the next build.
    // FutureBuilder still receives the same future and can display its error.
    _future.ignore();
  }

  void _changed() {
    final item = _categories[_tabs.index].$1;
    if (item != _item && mounted) {
      setState(() {
        _item = item;
        _load();
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() => _load(refresh: true));
  }

  Future<void> _web({TaskSummary? task}) async {
    final path = Uri(path: 'home.php', queryParameters: {
      'mod': 'task',
      'mobile': 'no',
      if (task != null) ...{'do': 'view', 'id': task.id.toString()} else
        'item': _item,
    }).toString();
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FuncListPage(title: task?.name ?? '任务中心', path: path)));
    if (mounted) _refresh();
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_refresh);
    _tabs.removeListener(_changed);
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tabStyle =
        Theme.of(context).textTheme.titleSmall ?? const TextStyle(fontSize: 14);
    final tabMetrics = _taskTabMetrics(
        context, _categories.map((category) => category.$2), tabStyle);
    return Scaffold(
      drawer: const GlobalAppDrawer(),
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('任务中心'),
        actions: [
          IconButton(
              onPressed: _web,
              icon: const Icon(Icons.open_in_browser),
              tooltip: '完整任务中心'),
          IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新任务'),
        ],
        bottom: PreferredSize(
            preferredSize: Size.fromHeight(tabMetrics.height + 2),
            child: LayoutBuilder(builder: (context, constraints) {
              final scrollable = constraints.maxWidth < tabMetrics.minimumWidth;
              return TabBar(
                  controller: _tabs,
                  labelStyle: tabStyle,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                  isScrollable: scrollable,
                  tabAlignment:
                      scrollable ? TabAlignment.start : TabAlignment.fill,
                  tabs: [
                    for (final category in _categories)
                      Tab(text: category.$2, height: tabMetrics.height)
                  ]);
            })),
      ),
      body: !DioClient.isLoggedIn
          ? Center(
              child: FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('登录后查看任务'),
              onPressed: () async {
                await Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const LoginPage()));
                if (mounted) _refresh();
              },
            ))
          : FutureBuilder<List<TaskSummary>>(
              key: ValueKey('task-$_item.${DioClient.sessionKey}'),
              future: _future,
              initialData: KlpbbsApi.cachedTasks(_item),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done &&
                    snapshot.data == null) {
                  return const Center(child: AppLoadingIndicator());
                }
                if (snapshot.hasError) {
                  final outage = ServerOutageInfo.tryParse(snapshot.error);
                  if (outage != null) {
                    return ServerOutageView(outage: outage, onRetry: _refresh);
                  }
                  return Center(
                      child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(snapshot.error.toString(),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _refresh, child: const Text('重试')),
                    ]),
                  ));
                }
                final tasks = snapshot.data ?? const <TaskSummary>[];
                return RefreshIndicator(
                  onRefresh: () async {
                    _refresh();
                    try {
                      await _future;
                    } catch (_) {
                      // FutureBuilder displays the failure; the refresh ends.
                    }
                  },
                  child: LayoutBuilder(builder: (context, constraints) {
                    Widget card(int index) {
                      final task = tasks[index];
                      return Card.outlined(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _web(task: task),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(children: [
                              Icon(Icons.assignment_outlined,
                                  size: 32, color: scheme.primary),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(task.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      if (task.reward.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(task.reward,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color:
                                                    scheme.onSurfaceVariant)),
                                      ],
                                      const SizedBox(height: 8),
                                      Text('查看详情与可用操作',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.primary)),
                                    ]),
                              ),
                              const Icon(Icons.chevron_right),
                            ]),
                          ),
                        ),
                      );
                    }

                    return CustomScrollView(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (tasks.isEmpty)
                            const SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(child: Text('当前分类暂无任务')))
                          else if (constraints.maxWidth >= 720)
                            SliverPadding(
                                padding: const EdgeInsets.all(16),
                                sliver: SliverTwoColumnFeed(
                                    itemCount: tasks.length,
                                    itemBuilder: (_, index) => card(index)))
                          else
                            SliverPadding(
                                padding: const EdgeInsets.all(12),
                                sliver: SliverList.builder(
                                    itemCount: tasks.length,
                                    itemBuilder: (_, index) => card(index))),
                        ]);
                  }),
                );
              },
            ),
    );
  }
}

({double minimumWidth, double height}) _taskTabMetrics(
    BuildContext context, Iterable<String> labels, TextStyle style) {
  var longest = 0.0, tallest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1)
      ..layout();
    if (painter.width > longest) longest = painter.width;
    if (painter.height > tallest) tallest = painter.height;
    painter.dispose();
  }
  final height = tallest + 16;
  return (
    minimumWidth: labels.length * (longest + 40),
    height: height > 46 ? height : 46,
  );
}
