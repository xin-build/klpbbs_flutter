import '../widgets/app_motion.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/discuz_feature_catalog.dart';
import '../core/discuz_guide_protocol.dart';
import '../core/url_helper.dart';
import '../models/site_feature.dart';
import '../models/user_role.dart';
import 'credit_page.dart';
import 'darkroom_page.dart';
import 'facemall_page.dart';
import 'favorite_hub_page.dart';
import 'func_list_page.dart';
import 'forums_page.dart';
import 'friend_page.dart';
import 'guide_page.dart';
import 'login_page.dart';
import 'magic_page.dart';
import 'medal_page.dart';
import 'membership_page.dart';
import 'modcp_page.dart';
import 'notice_page.dart';
import 'pm_inbox_page.dart';
import 'promotion_page.dart';
import 'profile_settings_page.dart';
import 'search_page.dart';
import 'sign_rank_page.dart';
import 'task_page.dart';

class ForumFeaturesPage extends StatefulWidget {
  const ForumFeaturesPage({super.key});
  @override
  State<ForumFeaturesPage> createState() => _ForumFeaturesPageState();
}

class _ForumFeaturesPageState extends State<ForumFeaturesPage> {
  late Future<(List<SiteFeature>, DiscuzUserRole)> _future;
  String _filter = '';
  String _category = '全部';
  String? _navigationError;
  (List<SiteFeature>, DiscuzUserRole)? _loaded;
  int _loadGeneration = 0;
  static const _categories = [
    '全部',
    '社区',
    '我的',
    '积分与会员',
    '账号与隐私',
    '站点扩展',
    '站点工具',
    '管理'
  ];
  @override
  void initState() {
    super.initState();
    _load();
    DioClient.sessionChanges.addListener(_sessionChanged);
  }

  void _load({bool forceRefresh = false}) {
    final generation = ++_loadGeneration;
    final session = DioClient.sessionKey;
    _navigationError = null;
    _future = Future.wait<Object>([
      KlpbbsApi.getSiteFeatures(forceRefresh: forceRefresh)
          .catchError((Object error) {
        if (generation == _loadGeneration && session == DioClient.sessionKey) {
          _navigationError = '网站功能暂未同步，请重试';
          return _loaded?.$1 ?? <SiteFeature>[];
        }
        return <SiteFeature>[];
      }),
      DioClient.isLoggedIn
          ? KlpbbsApi.getMyRole()
              .catchError((Object _) => const DiscuzUserRole())
          : Future.value(const DiscuzUserRole()),
    ]).then((values) {
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新加载功能');
      final result =
          (values[0] as List<SiteFeature>, values[1] as DiscuzUserRole);
      if (generation == _loadGeneration) _loaded = result;
      return result;
    });
    _future.ignore();
  }

  void _refresh() {
    if (mounted) setState(() => _load(forceRefresh: true));
  }

  void _sessionChanged() {
    if (!mounted) return;
    setState(() {
      _loaded = null;
      if (_category == '管理') _category = '全部';
      _load();
    });
  }

  @override
  void dispose() {
    _loadGeneration++;
    DioClient.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  IconData _icon(SiteFeature feature) {
    final query = Uri.parse(feature.url).queryParameters;
    if (query['ac'] == 'usergroup') return Icons.workspace_premium_outlined;
    if (query['ac'] == 'credit') return Icons.account_balance_wallet_outlined;
    if (query['mod'] == 'medal') return Icons.military_tech_outlined;
    if (query['mod'] == 'magic') return Icons.auto_fix_high_outlined;
    if (query['mod'] == 'task') return Icons.assignment_outlined;
    if (query['do'] == 'favorite') return Icons.bookmarks_outlined;
    if (query['do'] == 'notice') return Icons.notifications_outlined;
    if (query['do'] == 'pm') return Icons.mail_outline;
    if (query['id']?.startsWith('klpbbs_ai') == true) {
      return Icons.smart_toy_outlined;
    }
    if (query['id']?.startsWith('klpbbs_new_api') == true) {
      return Icons.key_outlined;
    }
    if (feature.category == '管理') return Icons.admin_panel_settings_outlined;
    if (feature.category == '账号与隐私') return Icons.manage_accounts_outlined;
    return Icons.apps_outlined;
  }

  Widget? _native(SiteFeature feature) {
    final uri = Uri.parse(feature.url),
        q = Uri.parse(feature.url).queryParameters;
    if (q['mod'] == 'medal' && q['action'] == null) return const MedalPage();
    if (q['mod'] == 'magic' &&
        q['mid'] == null &&
        q['magicid'] == null &&
        q['operation'] == null) {
      return switch (q['action']) {
        null || 'shop' => const MagicPage(),
        'mybox' => const MagicPage(initialTab: 1),
        'log' when q['operation'] == null => const MagicPage(initialTab: 2),
        _ => null,
      };
    }
    if (q['mod'] == 'task' &&
        q['do'] == null &&
        const {null, 'new', 'doing', 'done', 'failed'}.contains(q['item'])) {
      return TaskPage(initialItem: q['item'] ?? 'new');
    }
    if (uri.path.endsWith('search.php')) return const SearchPage();
    if (q['mod'] == 'index' || q['forumlist'] == '1') return const ForumsPage();
    if (q['ac'] == 'profile' && q['op'] == null) {
      return const ProfileSettingsPage();
    }
    if (q['ac'] == 'friend' &&
        q['op'] == null &&
        KlpbbsApi.currentCachedMyUid != null) {
      return FriendPage(uid: KlpbbsApi.currentCachedMyUid!, isMe: true);
    }
    if (q['ac'] == 'usergroup' &&
        (q['do'] == null || q['do'] == 'list') &&
        q['gid'] == null) {
      return const MembershipPage();
    }
    if (q['ac'] == 'credit') {
      return switch (q['op']) {
        null || 'base' => const CreditPage(initialTabIndex: 0),
        'transfer' => const CreditPage(initialTabIndex: 1),
        'log' when q['suboperation'] == 'creditrulelog' =>
          const CreditPage(initialTabIndex: 2, initialLogCategory: 'reward'),
        'log'
            when q['suboperation'] == null &&
                q['subop'] == null &&
                q['optype'] == null &&
                q['income'] == null =>
          const CreditPage(initialTabIndex: 2),
        _ => null,
      };
    }
    if (q['ac'] == 'promotion') return const PromotionPage();
    if (q['mod'] == 'modcp' &&
        q['action'] == null &&
        q['op'] == null &&
        q['fid'] == null) {
      return const ModCpPage();
    }
    if (q['do'] == 'favorite' &&
        const {null, 'thread', 'forum'}.contains(q['type']) &&
        q['tagid'] == null &&
        q['tagname'] == null &&
        KlpbbsApi.currentCachedMyUid != null &&
        (q['uid'] == null ||
            int.tryParse(q['uid']!) == KlpbbsApi.currentCachedMyUid)) {
      return FavoriteHubPage(
          uid: KlpbbsApi.currentCachedMyUid!,
          initialIndex: q['type'] == 'forum' ? 1 : 0);
    }
    if (q['do'] == 'notice' && q['view'] == null && q['type'] == null) {
      return const NoticePage();
    }
    if (q['do'] == 'pm' &&
        q['subop'] == null &&
        q['touid'] == null &&
        q['plid'] == null) {
      return const PmInboxPage();
    }
    if (q['id'] == 'sunju_facemall:face') return const FacemallPage();
    if (q['id'] == 'k_misign:sign' &&
        const {null, 'today', 'month', 'zong', 'rewardlist', 'calendar'}
            .contains(q['operation'])) {
      return SignRankPage(initialOperation: q['operation'] ?? 'today');
    }
    if (q['mod'] == 'guide' &&
        q['rss'] == null &&
        DiscuzGuideProtocol.views.contains(q['view'] ?? 'newthread')) {
      return GuidePage(initialView: q['view'] ?? 'newthread');
    }
    if (q['action'] == 'showdarkroom') return const DarkroomPage();
    return null;
  }

  Future<void> _open(SiteFeature feature) async {
    if (Uri.parse(feature.url).origin != Uri.parse(AppConfig.baseUrl).origin) {
      await UrlHelper.openLink(context, feature.url);
      return;
    }
    if (!DioClient.isLoggedIn && feature.category != '社区') {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (!mounted || !DioClient.isLoggedIn) return;
    }
    final destination = _native(feature) ??
        FuncListPage(title: feature.title, path: feature.url);
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => destination));
  }

  List<SiteFeature> _withCommon(List<SiteFeature> actual, DiscuzUserRole role) {
    final base = Uri.parse(AppConfig.baseUrl);
    final common = <SiteFeature>[
      SiteFeature(
          title: '版块导航',
          url: base.resolve('forum.php?mod=index&forumlist=1').toString(),
          category: '社区'),
      SiteFeature(
          title: '搜索论坛',
          url: base.resolve('search.php?mod=forum').toString(),
          category: '社区'),
      SiteFeature(
          title: '积分中心',
          url: base.resolve('home.php?mod=spacecp&ac=credit').toString(),
          category: '积分与会员'),
      SiteFeature(
          title: '账号资料',
          url: base.resolve('home.php?mod=spacecp&ac=profile').toString(),
          category: '账号与隐私'),
      SiteFeature(
          title: '好友与关注',
          url: base.resolve('home.php?mod=spacecp&ac=friend').toString(),
          category: '我的'),
      SiteFeature(
          title: '勋章中心',
          url: base.resolve('home.php?mod=medal').toString(),
          category: '社区'),
      SiteFeature(
          title: '道具商城',
          url: base.resolve('home.php?mod=magic&action=shop').toString(),
          category: '我的'),
      SiteFeature(
          title: '任务中心',
          url: base.resolve('home.php?mod=task').toString(),
          category: '我的'),
      SiteFeature(
          title: '用户组与会员',
          url: base
              .resolve('home.php?mod=spacecp&ac=usergroup&do=list')
              .toString(),
          category: '积分与会员'),
      SiteFeature(
          title: '签到与排行',
          url: base.resolve('plugin.php?id=k_misign:sign').toString(),
          category: '社区'),
      SiteFeature(
          title: '收藏',
          url: base.resolve('home.php?mod=space&do=favorite').toString(),
          category: '我的'),
      SiteFeature(
          title: '通知',
          url: base.resolve('home.php?mod=space&do=notice').toString(),
          category: '我的'),
      SiteFeature(
          title: '私信',
          url: base.resolve('home.php?mod=space&do=pm').toString(),
          category: '我的'),
      if (role.hasAnyModPermission)
        SiteFeature(
            title: '前台管理中心',
            url: base.resolve('forum.php?mod=modcp').toString(),
            category: '管理'),
      if (role.isAdmin)
        SiteFeature(
            title: '论坛管理后台',
            url: base.resolve('admin.php').toString(),
            category: '管理'),
    ];
    final result = [...actual];
    for (final item in common) {
      if (!result.any((feature) =>
          DiscuzFeatureCatalog.sameDestination(item.url, feature.url, base))) {
        result.add(item);
      }
    }
    final permitted = result
        .where((feature) =>
            feature.category != '管理' ||
            (Uri.parse(feature.url).path.endsWith('admin.php')
                ? role.isAdmin
                : role.hasAnyModPermission))
        .toList();
    return [
      ...permitted.where((feature) => feature.category == '管理'),
      ...permitted.where((feature) => feature.category != '管理'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
        appBar: AppBar(title: const Text('论坛功能'), actions: [
          IconButton(
              onPressed: _refresh,
              tooltip: '同步网站功能',
              icon: const Icon(Icons.refresh)),
        ]),
        body: FutureBuilder<(List<SiteFeature>, DiscuzUserRole)>(
            key: ValueKey(DioClient.sessionKey),
            initialData: _loaded,
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(
                    child: snapshot.hasError
                        ? Column(mainAxisSize: MainAxisSize.min, children: [
                            Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text('${snapshot.error}')),
                            FilledButton.tonal(
                                onPressed: _refresh, child: const Text('重试')),
                          ])
                        : const AppLoadingIndicator());
              }
              final items = _withCommon(snapshot.data!.$1, snapshot.data!.$2)
                  .where((item) =>
                      (_category == '全部' || item.category == _category) &&
                      item.title.toLowerCase().contains(_filter.toLowerCase()))
                  .toList();
              return CustomScrollView(slivers: [
                if (snapshot.connectionState != ConnectionState.done)
                  const SliverToBoxAdapter(child: AppLoadingBar()),
                if (_navigationError != null)
                  SliverToBoxAdapter(
                      child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(children: [
                      Expanded(
                          child: Text(_navigationError!,
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant))),
                      TextButton(
                          onPressed: _refresh, child: const Text('重试同步')),
                    ]),
                  )),
                SliverToBoxAdapter(
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: Column(children: [
                          TextField(
                              onChanged: (value) =>
                                  setState(() => _filter = value),
                              decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search),
                                  hintText: '搜索功能、会员、插件…',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final category in _categories)
                                  if (category != '管理' ||
                                      snapshot.data!.$2.hasAnyModPermission)
                                    ChoiceChip(
                                        label: Text(category),
                                        selected: category == _category,
                                        onSelected: (_) => setState(
                                            () => _category = category)),
                              ])),
                        ]))),
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver:
                        SliverLayoutBuilder(builder: (context, constraints) {
                      final scaler = MediaQuery.textScalerOf(context);
                      final scale = (scaler.scale(14) / 14).clamp(1.0, 1.6);
                      final columns =
                          (constraints.crossAxisExtent / (320 * scale))
                              .floor()
                              .clamp(1, 4);
                      final tileHeight = (scaler.scale(14) * 2.9 +
                              scaler.scale(12) * 1.45 +
                              40)
                          .clamp(104.0, 230.0);
                      return SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisExtent: tileHeight,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return Card.outlined(
                                key: ValueKey('site-feature:${item.url}'),
                                margin: EdgeInsets.zero,
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                    onTap: () => _open(item),
                                    child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(children: [
                                          Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                  color:
                                                      scheme.secondaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          14)),
                                              child: Icon(_icon(item),
                                                  color: scheme
                                                      .onSecondaryContainer)),
                                          const SizedBox(width: 14),
                                          Expanded(
                                              child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(item.title,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                const SizedBox(height: 4),
                                                Text(item.category,
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: scheme
                                                            .onSurfaceVariant)),
                                              ])),
                                          const Icon(Icons.chevron_right,
                                              size: 20),
                                        ]))));
                          });
                    })),
                if (items.isEmpty)
                  const SliverToBoxAdapter(
                      child: Center(
                          child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('没有匹配的功能')))),
              ]);
            }));
  }
}
