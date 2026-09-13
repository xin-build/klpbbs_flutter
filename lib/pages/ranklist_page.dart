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
  final String? author;
  final String? extra;
  final int? uid;
  final int? tid;
  final int? fid;

  const RankEntry({
    required this.rank,
    required this.title,
    this.subtitle,
    this.author,
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
  final Map<String, List<RankEntry>> _cache = {};
  final Map<String, GlobalKey<_RanklistTabViewContentState>> _tabKeys = {
    for (final (type, _) in _tabs)
      type: GlobalKey<_RanklistTabViewContentState>(),
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshCurrentTab() {
    final curType = _tabs[_tabController.index].$1;
    _cache.remove(curType);
    _tabKeys[curType]?.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      drawer: const GlobalAppDrawer(),
      drawerEdgeDragWidth: 50.0,
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('论坛排行榜'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新当前排行',
            onPressed: _refreshCurrentTab,
          ),
        ],
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
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final (type, _) in _tabs)
                _RanklistTabViewContent(
                  key: _tabKeys[type],
                  type: type,
                  cache: _cache,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RanklistTabViewContent extends StatefulWidget {
  final String type;
  final Map<String, List<RankEntry>> cache;

  const _RanklistTabViewContent({
    super.key,
    required this.type,
    required this.cache,
  });

  @override
  State<_RanklistTabViewContent> createState() =>
      _RanklistTabViewContentState();
}

class _RanklistTabViewContentState extends State<_RanklistTabViewContent>
    with AutomaticKeepAliveClientMixin {
  late Future<List<RankEntry>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _loadData(forceRefresh: false);
  }

  void refresh() {
    setState(() {
      _future = _loadData(forceRefresh: true);
    });
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

  Future<List<RankEntry>> _loadData({bool forceRefresh = false}) async {
    final type = widget.type;
    if (!forceRefresh && widget.cache.containsKey(type)) {
      return widget.cache[type]!;
    }

    final items = <RankEntry>[];

    if (type == 'day') {
      // 日排行策略 1：从 forum.php?mod=guide&view=hot 获取今日最热门帖子（24小时动态热榜）
      final hotHtml = await _fetchHtml('forum.php?mod=guide&view=hot');
      if (hotHtml.isNotEmpty) {
        items.addAll(_parseGuideHot(hotHtml));
      }

      // 日排行策略 2：若导读热帖为空，回退至 PC 首页日排行挂件
      if (items.isEmpty) {
        final homeHtml = await _fetchHtml('forum.php?mobile=no');
        if (homeHtml.isNotEmpty) {
          items.addAll(_parseHomeRankWidget(homeHtml, 'day'));
        }
      }
    } else {
      // 周排行与月排行策略：从 PC 首页 forum.php?mobile=no 提取对应的排行榜容器
      // （#diy_week_rank 与 #diy_month_rank）
      final homeHtml = await _fetchHtml('forum.php?mobile=no');
      if (homeHtml.isNotEmpty) {
        // 同步解析 Week 和 Month，实现多 Tab 预热缓存
        final weekItems = _parseHomeRankWidget(homeHtml, 'week');
        final monthItems = _parseHomeRankWidget(homeHtml, 'month');
        if (weekItems.isNotEmpty) {
          widget.cache['week'] = weekItems;
        }
        if (monthItems.isNotEmpty) {
          widget.cache['month'] = monthItems;
        }
        if (type == 'week') {
          items.addAll(weekItems);
        } else if (type == 'month') {
          items.addAll(monthItems);
        }
      }
    }

    // 策略 3（兜底）：从 misc.php?mod=ranklist 或常规表格获取
    if (items.isEmpty) {
      final order = type == 'day'
          ? 'thisday'
          : type == 'week'
              ? 'thisweek'
              : 'thismonth';
      final rankHtml = await _fetchHtml(
        'misc.php?mod=ranklist&type=thread&view=heats&orderby=$order&mobile=no',
      );
      if (rankHtml.isNotEmpty) {
        items.addAll(_parseThreadRank(rankHtml));
      }
    }

    widget.cache[type] = items;
    return items;
  }

  /// 解析导读热帖（今日 24 小时真实活跃热门榜）
  List<RankEntry> _parseGuideHot(String html) {
    final doc = hp.parse(html);
    final items = <RankEntry>[];
    final seenTids = <int>{};
    var rank = 1;

    for (final tb in doc.querySelectorAll('tbody[id^="normalthread_"]')) {
      final tidAttr = tb.attributes['id'] ?? '';
      final m = RegExp(r'normalthread_(\d+)').firstMatch(tidAttr);
      int? tid = m != null ? int.tryParse(m.group(1)!) : null;

      final aTitle = tb.querySelector('a.tit, a.xst');
      if (aTitle == null) continue;
      final title = aTitle.text.trim();
      if (title.isEmpty) continue;

      if (tid == null) {
        final href = aTitle.attributes['href'] ?? '';
        final m2 = RegExp(r'thread-(\d+)').firstMatch(href) ??
            RegExp(r'tid=(\d+)').firstMatch(href);
        if (m2 != null) tid = int.tryParse(m2.group(1)!);
      }
      if (tid == null || !seenTids.add(tid)) continue;

      // 作者与 UID
      final authorEl =
          tb.querySelector('.aor a, td.by cite a, a[href*="space-uid"]');
      final author = authorEl?.text.trim();
      final authorHref = authorEl?.attributes['href'] ?? '';
      final mUid = RegExp(r'space-uid-(\d+)').firstMatch(authorHref) ??
          RegExp(r'uid=(\d+)').firstMatch(authorHref);
      final uid = mUid != null ? int.tryParse(mUid.group(1)!) : null;

      // 板块
      final forumEl =
          tb.querySelector('td.by a[href*="forum-"], th a[href*="forum-"]');
      final forumName = forumEl?.text.trim();
      final forumHref = forumEl?.attributes['href'] ?? '';
      final mFid = RegExp(r'forum-(\d+)').firstMatch(forumHref) ??
          RegExp(r'fid=(\d+)').firstMatch(forumHref);
      final fid = mFid != null ? int.tryParse(mFid.group(1)!) : null;

      // 浏览与回复数
      final viewsEl = tb.querySelector('.vie, td.num em');
      final repliesEl = tb.querySelector('.rey, td.num a');
      final views = viewsEl?.text.trim();
      final replies = repliesEl?.text.trim();

      // 额外标记（例如 "4人参与"）
      final extraEl = tb.querySelector('.xi1');
      final extra = extraEl?.text.trim();

      final subParts = <String>[];
      if (forumName != null && forumName.isNotEmpty) subParts.add(forumName);
      if (extra != null && extra.isNotEmpty) subParts.add(extra);
      if (views != null && views.isNotEmpty && views != '0') {
        subParts.add('$views浏览');
      }
      if (replies != null && replies.isNotEmpty) subParts.add('$replies回复');
      if (author != null && author.isNotEmpty) subParts.add(author);

      items.add(
        RankEntry(
          rank: rank++,
          title: title,
          subtitle: subParts.isNotEmpty ? subParts.join(' · ') : null,
          author: author,
          uid: uid,
          tid: tid,
          fid: fid,
        ),
      );
      if (items.length >= 50) break;
    }
    return items;
  }

  /// 解析 PC 首页「📈 排行」侧边栏组件（日排行 #diy_day_rank / 周排行 #diy_week_rank / 月排行 #diy_month_rank）
  List<RankEntry> _parseHomeRankWidget(String html, String type) {
    final doc = hp.parse(html);
    final items = <RankEntry>[];
    final seenTids = <int>{};

    // 精准查找对应周期的排行榜容器
    dynamic container;
    if (type == 'day') {
      container = doc.querySelector('#diy_day_rank') ??
          doc.querySelector('#portal_block_115') ??
          doc.querySelector('#sd_rank .bd > ul:nth-child(1)');
    } else if (type == 'week') {
      container = doc.querySelector('#diy_week_rank') ??
          doc.querySelector('#portal_block_116') ??
          doc.querySelector('#sd_rank .bd > ul:nth-child(2)');
    } else if (type == 'month') {
      container = doc.querySelector('#diy_month_rank') ??
          doc.querySelector('#portal_block_117') ??
          doc.querySelector('#sd_rank .bd > ul:nth-child(3)');
    }

    // 兜底容器查找
    if (container == null) {
      final allBlocks =
          doc.querySelectorAll('#sd_rank .bd ul, .comiis_phb, .phb_list');
      if (allBlocks.isNotEmpty) {
        final idx = type == 'day' ? 0 : (type == 'week' ? 1 : 2);
        if (idx < allBlocks.length) {
          container = allBlocks[idx];
        } else {
          container = allBlocks.first;
        }
      }
    }

    if (container == null) return items;

    var r = 1;
    for (final li in container.querySelectorAll('li')) {
      final aTit =
          li.querySelector('a.tit, a[href*="thread-"], a[href*="tid="]');
      if (aTit == null) continue;
      final href = aTit.attributes['href'] ?? '';
      final m = RegExp(r'thread-(\d+)').firstMatch(href) ??
          RegExp(r'tid=(\d+)').firstMatch(href);
      final tid = m != null ? int.tryParse(m.group(1)!) : null;
      if (tid == null || !seenTids.add(tid)) continue;

      // 提取名次
      final iEl =
          aTit.querySelector('i') ?? li.querySelector('em, span.num, i, strong');
      int rankVal = r;
      if (iEl != null) {
        final parsed = int.tryParse(iEl.text.trim());
        if (parsed != null) rankVal = parsed;
      }

      // 提取标题（剔除开头的数字序号）
      var title = aTit.attributes['title'] ?? aTit.text.trim();
      if (title.isEmpty || title == '更多') continue;
      title = title.replaceFirst(RegExp(r'^\s*\d+\s*'), '').trim();

      // 作者与 UID
      final aor = li.querySelector('a.aor');
      String? author = aor?.attributes['title'] ?? aor?.text.trim();
      int? uid;
      if (aor != null) {
        final uHref = aor.attributes['href'] ?? '';
        final mU = RegExp(r'space-uid-(\d+)').firstMatch(uHref) ??
            RegExp(r'uid=(\d+)').firstMatch(uHref);
        if (mU != null) uid = int.tryParse(mU.group(1)!);
      }

      // 详情信息（版块、浏览量、回复数、作者）
      final subEl = li.querySelector('.sub, span.y, span.xg1');
      final subParts = <String>[];
      int? fid;
      if (subEl != null) {
        final forumA = subEl.querySelector('a[href*="forum-"]');
        if (forumA != null) {
          subParts.add(forumA.text.trim());
          final fHref = forumA.attributes['href'] ?? '';
          final mF = RegExp(r'forum-(\d+)').firstMatch(fHref);
          if (mF != null) fid = int.tryParse(mF.group(1)!);
        }

        final subText = subEl.text;
        final mViews = RegExp(r'浏览:\s*(\d+)').firstMatch(subText);
        if (mViews != null) {
          final v = int.tryParse(mViews.group(1)!) ?? 0;
          final vStr = v >= 10000
              ? '${(v / 10000).toStringAsFixed(1)}万'.replaceAll('.0万', '万')
              : '$v';
          subParts.add('$vStr浏览');
        }

        final mReplies = RegExp(r'回复:\s*(\d+)').firstMatch(subText);
        if (mReplies != null) {
          subParts.add('${mReplies.group(1)}回复');
        }

        if (author == null || author.isEmpty) {
          final authorA = subEl.querySelector('a[href*="space-uid"]');
          if (authorA != null) {
            author = authorA.text.trim();
            final uHref = authorA.attributes['href'] ?? '';
            final mU = RegExp(r'space-uid-(\d+)').firstMatch(uHref);
            if (mU != null && uid == null) uid = int.tryParse(mU.group(1)!);
          }
        }
        if (author != null && author.isNotEmpty) {
          subParts.add(author);
        }
      }

      items.add(
        RankEntry(
          rank: rankVal,
          title: title,
          subtitle: subParts.isNotEmpty ? subParts.join(' · ') : null,
          author: author,
          uid: uid,
          tid: tid,
          fid: fid,
        ),
      );
      r++;
      if (items.length >= 30) break;
    }

    return items;
  }

  /// 解析标准 Discuz 帖子排行页面
  List<RankEntry> _parseThreadRank(String html) {
    final doc = hp.parse(html);
    final items = <RankEntry>[];
    final seenTids = <int>{};
    var r = 1;

    for (final tr in doc.querySelectorAll(
      'table.dt tr, table.tl tr, .comiis_ranklist tr, tbody tr, tr',
    )) {
      if (tr.querySelector('th') != null && tr.querySelectorAll('td').isEmpty) {
        continue;
      }

      final a = tr.querySelector(
        'a[href*="thread-"], a[href*="tid="], a[href*="viewthread"], th.common a, td.common a',
      );
      if (a == null) continue;
      final title = a.attributes['title'] ?? a.text.trim();
      if (title.isEmpty || title == '更多' || title == '下一页') continue;

      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'thread-(\d+)').firstMatch(href) ??
          RegExp(r'tid=(\d+)').firstMatch(href);
      final tid = m != null ? int.tryParse(m.group(1)!) : null;
      if (tid == null || !seenTids.add(tid)) continue;

      final rankTd =
          tr.querySelector('td.rk, em.rk, span.num, td:first-child');
      final rankNum =
          rankTd != null ? int.tryParse(rankTd.text.trim()) : null;
      final rank = rankNum ?? r;

      final tds = tr.querySelectorAll('td');
      String? subtitle;
      if (tds.length >= 3) {
        subtitle =
            '${tds[tds.length - 2].text.trim()} · ${tds.last.text.trim()}';
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
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<List<RankEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: 12),
                  Text(
                    '加载失败：${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: refresh,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 100),
                EmptyView(
                  icon: Icons.emoji_events_outlined,
                  title: '暂无排行数据',
                  subtitle: '暂无当前分类排名记录',
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final item = items[i];
              return _buildRankTile(context, item, colorScheme);
            },
          ),
        );
      },
    );
  }

  /// 对应 PC 首页排行设计（① 红色、② 橙色、③ 青色、④..⑧ 灰色）
  Widget _buildRankTile(
    BuildContext context,
    RankEntry item,
    ColorScheme colorScheme,
  ) {
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
        if (item.tid != null && item.tid! > 0) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadDetailPage(tid: item.tid!),
            ),
          );
        } else if (item.uid != null && item.uid! > 0) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => UserSpacePage(uid: item.uid!),
            ),
          );
        } else if (item.fid != null && item.fid! > 0) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadListPage(
                fid: item.fid!,
                title: item.title,
              ),
            ),
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
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserSpacePage(uid: item.uid!),
                  ),
                );
              },
              child: UserAvatarWidget(
                uid: item.uid,
                author: item.author ?? '',
                size: 28,
              ),
            ),
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
      trailing: Icon(
        Icons.chevron_right,
        size: 16,
        color: colorScheme.outline.withAlpha(160),
      ),
    );
  }
}

