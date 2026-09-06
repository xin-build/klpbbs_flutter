import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as hp;

import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';
import 'thread_detail_page.dart';
import 'thread_list_page.dart';
import 'user_space_page.dart';

class RankEntry {
  final int rank;
  final String title;
  final String? subtitle;
  final String? extra;
  final int? uid;
  final int? tid;
  final int? fid;

  const RankEntry({
    required this.rank,
    required this.title,
    this.subtitle,
    this.extra,
    this.uid,
    this.tid,
    this.fid,
  });
}

/// 苦力怕论坛排行榜（深度复刻 PC 首页日排行/周排行/月排行与 Discuz 排行榜）
class RanklistPage extends StatefulWidget {
  const RanklistPage({super.key});

  @override
  State<RanklistPage> createState() => _RanklistPageState();
}

class _RanklistPageState extends State<RanklistPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    ('day', '日排行'),
    ('week', '周排行'),
    ('month', '月排行'),
  ];

  late final TabController _tabController;
  late Future<List<RankEntry>> _future;
  String _type = 'day';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(_onTabChanged);
    _future = _load(_type);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final type = _tabs[_tabController.index].$1;
    if (type != _type) {
      setState(() {
        _type = type;
        _future = _load(type);
      });
    }
  }

  Future<String> _fetchHtml(String path) async {
    try {
      final resp = await DioClient.dio.get<List<int>>(
        '${AppConfig.baseUrl}$path',
        options: Options(responseType: ResponseType.bytes),
      );
      return const Utf8Decoder(
        allowMalformed: true,
      ).convert(resp.data ?? const []);
    } catch (_) {
      return '';
    }
  }

  Future<List<RankEntry>> _load(String type) async {
    final items = <RankEntry>[];

    // 策略 1：从 misc.php?mod=ranklist&type=thread 获取对应时间段热榜
    final order = type == 'day'
        ? 'thisday'
        : type == 'week'
        ? 'thisweek'
        : 'thismonth';
    final html = await _fetchHtml(
      'misc.php?mod=ranklist&type=thread&view=heats&orderby=$order&mobile=no',
    );
    if (html.isNotEmpty) {
      items.addAll(_parseThreadRank(html));
    }

    // 策略 2：从 PC 首页 forum.php?mobile=no 提取 sidebar 排行组件
    if (items.isEmpty) {
      final homeHtml = await _fetchHtml('forum.php?mobile=no');
      if (homeHtml.isNotEmpty) {
        items.addAll(_parseHomeRankWidget(homeHtml, type));
      }
    }

    // 策略 3：从 views 榜获取
    if (items.isEmpty) {
      final viewHtml = await _fetchHtml(
        'misc.php?mod=ranklist&type=thread&view=views&orderby=$order&mobile=no',
      );
      if (viewHtml.isNotEmpty) {
        items.addAll(_parseThreadRank(viewHtml));
      }
    }
    return items;
  }

  /// 解析 PC 首页「📈 排行」侧边栏组件（日排行/周排行/月排行）
  List<RankEntry> _parseHomeRankWidget(String html, String type) {
    final doc = hp.parse(html);
    final items = <RankEntry>[];
    final seenTids = <int>{};

    // 查找包含日排行/周排行/月排行的容器
    for (final block in doc.querySelectorAll(
      '.comiis_phb, .comiis_mh_txtlist_phb, .phb_list, .module.cl.xl.xl1, [id^="portal_block_"]',
    )) {
      final listItems = block.querySelectorAll('li, tr, p');
      var r = 1;
      for (final li in listItems) {
        final a = li.querySelector('a[href*="thread-"], a[href*="tid="], a[href*="viewthread"]');
        if (a == null) continue;
        final title = a.attributes['title'] ?? a.text.trim();
        if (title.isEmpty || title == '更多') continue;
        final href = a.attributes['href'] ?? '';
        final m = RegExp(r'thread-(\d+)').firstMatch(href) ?? RegExp(r'tid=(\d+)').firstMatch(href);
        final tid = m != null ? int.tryParse(m.group(1)!) : null;
        if (tid == null || !seenTids.add(tid)) continue;

        final numEl = li.querySelector('em, span.num, i, strong');
        final numVal = numEl != null ? int.tryParse(numEl.text.trim()) : null;
        final rank = numVal ?? r;

        final subEl = li.querySelector('span.y, span.xg1, span.views, em.y');
        final subtitle = subEl?.text.trim();

        items.add(
          RankEntry(
            rank: rank,
            title: title,
            subtitle: subtitle,
            tid: tid,
          ),
        );
        r++;
        if (items.length >= 10) break;
      }
      if (items.isNotEmpty) break;
    }

    return items;
  }

  /// 解析标准 Discuz 帖子排行页面
  List<RankEntry> _parseThreadRank(String html) {
    final doc = hp.parse(html);
    final items = <RankEntry>[];
    final seenTids = <int>{};
    var r = 1;

    for (final tr in doc.querySelectorAll('table.dt tr, table.tl tr, .comiis_ranklist tr, tbody tr, tr')) {
      if (tr.querySelector('th') != null && tr.querySelectorAll('td').isEmpty) continue;

      final a = tr.querySelector('a[href*="thread-"], a[href*="tid="], a[href*="viewthread"], th.common a, td.common a');
      if (a == null) continue;
      final title = a.attributes['title'] ?? a.text.trim();
      if (title.isEmpty || title == '更多' || title == '下一页') continue;

      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'thread-(\d+)').firstMatch(href) ?? RegExp(r'tid=(\d+)').firstMatch(href);
      final tid = m != null ? int.tryParse(m.group(1)!) : null;
      if (tid == null || !seenTids.add(tid)) continue;

      final rankTd = tr.querySelector('td.rk, em.rk, span.num, td:first-child');
      final rankNum = rankTd != null ? int.tryParse(rankTd.text.trim()) : null;
      final rank = rankNum ?? r;

      final tds = tr.querySelectorAll('td');
      String? subtitle;
      if (tds.length >= 3) {
        subtitle = '${tds[tds.length - 2].text.trim()} · ${tds.last.text.trim()}';
      }

      items.add(
        RankEntry(
          rank: rank,
          title: title,
          subtitle: subtitle,
          tid: tid,
        ),
      );
      r++;
      if (items.length >= 30) break;
    }

    return items;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      drawer: const GlobalAppDrawer(),
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        title: const Text('论坛排行榜'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.outline,
          indicatorColor: colorScheme.primary,
          tabs: [for (final (_, label) in _tabs) Tab(text: label)],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: FutureBuilder<List<RankEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('加载失败：${snap.error}'));
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return const EmptyView(
                  icon: Icons.emoji_events_outlined,
                  title: '暂无排行数据',
                  subtitle: '暂无当前分类排名记录',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => setState(() {
                  _future = _load(_type);
                }),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    return _buildRankTile(item, colorScheme);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 对应图二 PC 首页排行设计（① 红色、② 橙色、③ 青色、④..⑧ 灰色）
  Widget _buildRankTile(RankEntry item, ColorScheme colorScheme) {
    Widget rankBadge;

    if (item.rank == 1) {
      rankBadge = Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: Color(0xFFE53935),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text(
          '1',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      );
    } else if (item.rank == 2) {
      rankBadge = Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: Color(0xFFFF9800),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text(
          '2',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      );
    } else if (item.rank == 3) {
      rankBadge = Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: Color(0xFF00ACC1),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text(
          '3',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      );
    } else {
      rankBadge = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withAlpha(120),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          '${item.rank}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      onTap: () {
        if (item.uid != null && item.uid! > 0) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UserSpacePage(uid: item.uid!)),
          );
        } else if (item.tid != null && item.tid! > 0) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: item.tid!)),
          );
        } else if (item.fid != null && item.fid! > 0) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ThreadListPage(fid: item.fid!, title: item.title)),
          );
        }
      },
      leading: SizedBox(
        width: 32,
        child: Center(child: rankBadge),
      ),
      title: Row(
        children: [
          if (item.uid != null && item.uid! > 0) ...[
            UserAvatarWidget(uid: item.uid, author: item.title, size: 28),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
      subtitle: item.subtitle != null && item.subtitle!.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item.subtitle!,
                style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
              ),
            )
          : null,
      trailing: Icon(Icons.chevron_right, size: 16, color: colorScheme.outline.withAlpha(160)),
    );
  }
}

