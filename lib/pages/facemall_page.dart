import '../widgets/app_motion.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/klpbbs_facemall.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';

class FacemallPage extends StatefulWidget {
  final int? uid;
  final String? username;
  final String? avatarUrl;
  const FacemallPage({super.key, this.uid, this.username, this.avatarUrl});

  @override
  State<FacemallPage> createState() => _FacemallPageState();
}

class _FacemallPageState extends State<FacemallPage> {
  final _searchController = TextEditingController();
  KlpFacemallCatalog? _catalog;
  int? _uid;
  String _username = '';
  int _tab = 0;
  int? _category;
  int _generation = 0;
  int _categoryRequest = 0;
  int _recordPage = 1;
  bool _loading = true;
  bool _busy = false;
  final List<bool> _tabLoading = [false, false, false];
  String? _error;
  final List<String?> _tabErrors = [null, null, null];
  final Map<int, List<Map<String, dynamic>>> _items = {};
  List<Map<String, dynamic>>? _owned;
  List<Map<String, dynamic>>? _records;
  FacemallPayListPage? _recordResult;

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_sessionChanged);
    unawaited(_loadCatalog());
  }

  @override
  void dispose() {
    _searchController.dispose();
    DioClient.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) return;
    _searchController.clear();
    setState(() {
      _catalog = null;
      _uid = null;
      _username = '';
      _category = null;
      _items.clear();
      _owned = null;
      _records = null;
      _recordResult = null;
      _recordPage = 1;
      _busy = false;
      for (var i = 0; i < 3; i++) {
        _tabErrors[i] = null;
        _tabLoading[i] = false;
      }
    });
    unawaited(_loadCatalog());
  }

  bool _current(int generation, String session) =>
      mounted && generation == _generation && session == DioClient.sessionKey;
  String _message(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(Bad state:|Exception:)\s*'), '');

  Future<void> _loadCatalog({bool refresh = false}) async {
    final generation = ++_generation;
    final session = DioClient.sessionKey;
    setState(() {
      _loading = true;
      _error = null;
      if (refresh) {
        _owned = null;
        _records = null;
        _recordResult = null;
        _recordPage = 1;
      }
      // Stale completions cannot clear their flags after generation changes.
      for (var index = 0; index < _tabLoading.length; index++) {
        _tabLoading[index] = false;
        _tabErrors[index] = null;
      }
    });
    try {
      if (!DioClient.isLoggedIn) throw StateError('请先登录后查看头像挂件');
      final uid = await KlpbbsApi.getMyUid();
      final catalog =
          await KlpbbsApi.getFacemallInitData(forceRefresh: refresh);
      if (!_current(generation, session)) return;
      await AppConfig.setMyFaceUrl(catalog.myFaceUrl);
      if (!_current(generation, session)) return;
      setState(() {
        _uid = uid;
        _catalog = catalog;
        _loading = false;
        if (!catalog.categories.any((c) => c.$1 == _category)) {
          _category =
              catalog.selectedCategory ?? catalog.categories.firstOrNull?.$1;
        }
        _items.clear();
        final initialCategory =
            catalog.selectedCategory ?? catalog.categories.firstOrNull?.$1;
        // 商城首屏只有占位容器时，列表要由 facelist 请求加载。
        // 空 HTML 不能代表分类已确认没有挂件。
        if (initialCategory != null && catalog.initialItems.isNotEmpty) {
          _items[initialCategory] = catalog.initialItems;
        }
      });
      if (uid != null) {
        unawaited(KlpbbsApi.getUserSpace(uid).then((space) {
          if (_current(generation, session) && space != null) {
            setState(() => _username = space.username);
          }
        }).catchError((_) {}));
      }
      if (_tab == 0 && _category != null && !_items.containsKey(_category)) {
        await _loadCategory(_category!);
      }
      if (_tab != 0) await _loadTab(_tab);
    } catch (error) {
      if (_current(generation, session)) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _loadCategory(int category) async {
    final request = ++_categoryRequest;
    final generation = _generation;
    final session = DioClient.sessionKey;
    setState(() {
      _tabLoading[0] = true;
      _tabErrors[0] = null;
    });
    try {
      final items = await KlpbbsApi.getFacemallCategoryItems(category,
          formhash: _catalog?.formhash);
      if (!_current(generation, session) || request != _categoryRequest) return;
      setState(() {
        _items[category] = items;
        _tabLoading[0] = false;
      });
    } catch (error) {
      if (_current(generation, session) && request == _categoryRequest) {
        setState(() {
          _tabLoading[0] = false;
          _tabErrors[0] = _message(error);
        });
      }
    }
  }

  Future<void> _loadTab(int tab) async {
    if (tab == 0) {
      if (_category != null) {
        await _loadCategory(_category!);
      }
      return;
    }
    if (_tabLoading[tab]) return;
    final generation = _generation;
    final session = DioClient.sessionKey;
    setState(() {
      _tabLoading[tab] = true;
      _tabErrors[tab] = null;
    });
    try {
      final List<Map<String, dynamic>> list;
      FacemallPayListPage? recordResult;
      if (tab == 1) {
        list = await KlpbbsApi.getMyFacemallList(formhash: _catalog?.formhash);
      } else {
        final result = await KlpbbsApi.getFacemallPayListPage(
            page: _recordPage, limit: 20, formhash: _catalog?.formhash);
        recordResult = result;
        list = result.items;
      }
      if (!_current(generation, session)) return;
      setState(() {
        if (tab == 1) {
          _owned = list;
        } else {
          _records = list;
          _recordResult = recordResult;
        }
        _tabLoading[tab] = false;
      });
    } catch (error) {
      if (_current(generation, session)) {
        setState(() {
          _tabLoading[tab] = false;
          _tabErrors[tab] = _message(error);
        });
      }
    }
  }

  Future<void> _changeEquipment({String? id}) async {
    if (_busy) return;
    final session = DioClient.sessionKey;
    setState(() => _busy = true);
    final success = id == null
        ? await KlpbbsApi.dropFacemall()
        : await KlpbbsApi.setFacemall(id);
    if (!mounted || session != DioClient.sessionKey) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            success ? (id == null ? '已卸下挂件' : '已佩戴挂件') : '网站未确认操作结果，请刷新查看')));
    if (success) {
      await _loadCatalog(refresh: true);
      if (mounted && _tab != 1) await _loadTab(1);
    }
  }

  Future<void> _buy(Map<String, dynamic> item) async {
    if (_busy || _catalog == null) return;
    final price = int.tryParse(item['price']?.toString() ?? '');
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('尚未读取到挂件价格，请刷新商城后再查看')));
      return;
    }
    final catalog = _catalog!;
    final session = DioClient.sessionKey;
    final minimum = catalog.minimumDays ?? 1;
    final options = catalog.dayOptions.where((day) => day >= minimum).toList();
    var days = options.firstOrNull ?? minimum;
    var custom = options.isEmpty;
    var equip = true;
    final input = TextEditingController(text: '$days');
    final selection = await showDialog<({int days, bool equip})>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, update) {
              final selected = custom ? int.tryParse(input.text) : days;
              final valid = selected != null && selected >= minimum;
              final total = valid ? price * selected : null;
              final sufficient = total != null &&
                  (catalog.userIronPoints == null ||
                      catalog.userIronPoints! >= total);
              return AlertDialog(
                  title: Text(item['title']?.toString() ?? '购买挂件'),
                  content: SizedBox(
                      width: 380,
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Center(
                                child: _avatar(
                                    size: 92, frame: item['img']?.toString())),
                            const SizedBox(height: 24),
                            Text('$price 铁粒 / 天',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 16),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final day in options)
                                ChoiceChip(
                                    label: Text('$day 天'),
                                    selected: !custom && days == day,
                                    onSelected: (_) => update(() {
                                          days = day;
                                          custom = false;
                                        })),
                              ChoiceChip(
                                  label: const Text('自定义'),
                                  selected: custom,
                                  onSelected: (_) =>
                                      update(() => custom = true)),
                            ]),
                            if (custom)
                              Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: TextField(
                                      controller: input,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                          labelText: '购买天数',
                                          helperText:
                                              catalog.minimumDays == null
                                                  ? null
                                                  : '网站要求至少 $minimum 天'),
                                      onChanged: (_) => update(() {}))),
                            const SizedBox(height: 20),
                            Text(total == null ? '请输入有效天数' : '合计 $total 铁粒',
                                style: Theme.of(context).textTheme.titleLarge),
                            if (catalog.userIronPoints != null)
                              Text('当前余额 ${catalog.userIronPoints} 铁粒'),
                            CheckboxListTile(
                                value: equip,
                                onChanged: (value) =>
                                    update(() => equip = value ?? true),
                                contentPadding: EdgeInsets.zero,
                                title: const Text('购买后立即佩戴')),
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: valid && sufficient
                            ? () => Navigator.pop(
                                dialogContext, (days: selected, equip: equip))
                            : null,
                        child: Text(valid && !sufficient ? '铁粒不足' : '确认购买'))
                  ]);
            }));
    input.dispose();
    if (selection == null || !mounted || session != DioClient.sessionKey) {
      return;
    }
    setState(() => _busy = true);
    final result = await KlpbbsApi.buyFacemall(item['id']?.toString() ?? '',
        sDay: selection.days, sNow: selection.equip);
    if (!mounted || session != DioClient.sessionKey) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) {
      _owned = null;
      _records = null;
      _recordResult = null;
      await _loadCatalog(refresh: true);
    }
  }

  Widget _avatar({double size = 76, String? frame}) => UserAvatarWidget(
      uid: _uid,
      author: _username,
      avatarUrl: _catalog?.userAvatarUrl,
      faceUrl: frame ?? _catalog?.myFaceUrl,
      useObservedAppearance: false,
      reserveFrameSpace: true,
      size: size);

  Widget _accountCard({bool compact = false}) => Card.filled(
      child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _avatar(size: compact ? 48 : 76),
                  SizedBox(width: compact ? 12 : 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(_username.isEmpty ? '我的挂件' : _username,
                            maxLines: compact ? 1 : null,
                            overflow: compact ? TextOverflow.ellipsis : null,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(_catalog?.myFaceUrl == null
                            ? '当前未佩戴挂件'
                            : '当前已佩戴挂件'),
                      ]))
                ]),
                SizedBox(height: compact ? 12 : 24),
                if (compact)
                  Wrap(spacing: 12, runSpacing: 6, children: [
                    Text('可用铁粒 ${_catalog?.userIronPoints?.toString() ?? '—'}',
                        style: Theme.of(context).textTheme.labelLarge),
                    if (_catalog?.minimumDays != null)
                      Text('最低购买 ${_catalog!.minimumDays} 天',
                          style: Theme.of(context).textTheme.bodySmall),
                  ])
                else ...[
                  Text('可用铁粒', style: Theme.of(context).textTheme.labelLarge),
                  Text(_catalog?.userIronPoints?.toString() ?? '—',
                      style: Theme.of(context).textTheme.headlineMedium),
                ],
                if (!compact && _catalog?.minimumDays != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('最低购买 ${_catalog!.minimumDays} 天')),
                if (_catalog?.myFaceUrl != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _changeEquipment(),
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('卸下当前挂件'))),
              ])));

  Widget _problem(String message, VoidCallback retry) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 16),
            SelectableText(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'))
          ])));

  Widget _mall() {
    final categoryItems = _items[_category] ?? const [];
    final query = _searchController.text.trim().toLowerCase();
    final list = categoryItems
        .where((item) =>
            query.isEmpty ||
            (item['title']?.toString() ?? '').toLowerCase().contains(query))
        .toList();
    return Column(children: [
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            for (final category in _catalog!.categories)
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(category.$2),
                      selected: _category == category.$1,
                      onSelected: _busy
                          ? null
                          : (_) {
                              if (_category == category.$1) return;
                              setState(() {
                                _category = category.$1;
                                _tabErrors[0] = null;
                              });
                              unawaited(_loadCategory(category.$1));
                            })),
          ])),
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            key: const ValueKey('facemall-search'),
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                hintText: '搜索当前分类的挂件',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: () => setState(_searchController.clear),
                        icon: const Icon(Icons.close_rounded))),
          )),
      if (_tabLoading[0]) const AppLoadingBar(),
      Expanded(
          child: _tabErrors[0] != null
              ? _problem(_tabErrors[0]!, () => _loadTab(0))
              : _tabLoading[0] && categoryItems.isEmpty
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AppLoadingIndicator(),
                      SizedBox(height: 16),
                      Text('正在读取挂件…')
                    ]))
                  : list.isEmpty
                      ? Center(
                          child:
                              Text(query.isEmpty ? '此分类暂无挂件' : '当前分类没有匹配的挂件'))
                      : RefreshIndicator(
                          onRefresh: () => _loadTab(0),
                          child: GridView.builder(
                              key: PageStorageKey(
                                  'facemall-category-$_category'),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              gridDelegate:
                                  SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 280,
                                      mainAxisExtent: 274 +
                                          (MediaQuery.textScalerOf(context)
                                                          .scale(20) -
                                                      20)
                                                  .clamp(0.0, 80.0) *
                                              3,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12),
                              itemCount: list.length,
                              itemBuilder: (context, index) {
                                final item = list[index];
                                final price = int.tryParse(
                                    item['price']?.toString() ?? '');
                                return LayoutBuilder(
                                    builder: (context, itemConstraints) =>
                                        Card.filled(
                                            margin: EdgeInsets.zero,
                                            child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                onTap: _busy
                                                    ? null
                                                    : () => _buy(item),
                                                child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            16),
                                                    child: Column(children: [
                                                      _avatar(
                                                          size: 86,
                                                          frame: item['img']
                                                                  ?.toString() ??
                                                              ''),
                                                      const SizedBox(
                                                          height: 16),
                                                      Text(
                                                          item['title']
                                                                  ?.toString() ??
                                                              '',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleMedium),
                                                      const SizedBox(height: 8),
                                                      Text(price == null ||
                                                              price < 0
                                                          ? '价格暂未读取'
                                                          : price == 0
                                                              ? '免费'
                                                              : '$price 铁粒 / 天'),
                                                      const Spacer(),
                                                      FilledButton.tonalIcon(
                                                          onPressed: _busy ||
                                                                  price ==
                                                                      null ||
                                                                  price < 0
                                                              ? null
                                                              : () =>
                                                                  _buy(item),
                                                          icon: const Icon(
                                                              Icons
                                                                  .shopping_bag_outlined,
                                                              size: 18),
                                                          label: Text(
                                                              itemConstraints
                                                                          .maxWidth <
                                                                      200
                                                                  ? '查看'
                                                                  : '查看与购买')),
                                                    ])))));
                              }))),
    ]);
  }

  Widget _ownedList() {
    if (_tabErrors[1] != null) {
      return _problem(_tabErrors[1]!, () => _loadTab(1));
    }
    if (_tabLoading[1] && _owned == null) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_owned?.isEmpty != false) return const Center(child: Text('暂无已购挂件'));
    return RefreshIndicator(
        onRefresh: () => _loadTab(1),
        child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: _owned!.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = _owned![index];
              final equipped = item['use'] == '1';
              final id = item['s_fid']?.toString() ?? '';
              final canEquip = KlpFacemallResponse.canEquip(item);
              return Card.filled(
                  margin: EdgeInsets.zero,
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        _avatar(size: 56, frame: item['img']?.toString() ?? ''),
                        const SizedBox(width: 16),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(item['title']?.toString() ?? '',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text('到期 ${item['endtime']}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ])),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                            onPressed: !canEquip || _busy
                                ? null
                                : () => _changeEquipment(id: id),
                            child: Text(equipped
                                ? '已佩戴'
                                : canEquip
                                    ? '佩戴'
                                    : '不可佩戴')),
                      ])));
            }));
  }

  Widget _recordList() {
    if (_tabErrors[2] != null) {
      return _problem(_tabErrors[2]!, () => _loadTab(2));
    }
    if (_tabLoading[2] && _records == null) {
      return const Center(child: AppLoadingIndicator());
    }
    final records = _records ?? const [];
    return Column(children: [
      if (_tabLoading[2]) const AppLoadingBar(),
      Expanded(
          child: records.isEmpty
              ? const Center(child: Text('暂无购买与激活记录'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: records.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = records[index];
                    return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item['title']?.toString() ?? ''),
                        subtitle: Text('${item['time']} · ${item['day']} 天'),
                        trailing: Text(
                            item['price']?.toString().isNotEmpty == true
                                ? '${item['price']} 铁粒'
                                : '—'));
                  })),
      Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
                onPressed: _recordResult?.hasPrevious == true && !_tabLoading[2]
                    ? () {
                        setState(() => _recordPage--);
                        _loadTab(2);
                      }
                    : null,
                tooltip: '上一页',
                icon: const Icon(Icons.chevron_left)),
            Text(_recordResult?.totalCount == null
                ? '第 $_recordPage 页'
                : '第 $_recordPage 页 · 共 ${_recordResult!.totalCount} 条'),
            IconButton(
                onPressed: _recordResult?.hasNext == true && !_tabLoading[2]
                    ? () {
                        setState(() => _recordPage++);
                        _loadTab(2);
                      }
                    : null,
                tooltip: '下一页',
                icon: const Icon(Icons.chevron_right)),
          ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final body = _loading && _catalog == null
        ? const Center(child: AppLoadingIndicator())
        : _error != null
            ? _problem(_error!, () => _loadCatalog(refresh: true))
            : _catalog == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.all(wide ? 24 : 16),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Column(children: [
                            if (!wide)
                              AnimatedSize(
                                  duration: AppMotion.duration(context, 240),
                                  curve: AppMotion.emphasized,
                                  alignment: Alignment.topCenter,
                                  child:
                                      MediaQuery.viewInsetsOf(context).bottom >
                                              0
                                          ? const SizedBox.shrink()
                                          : _accountCard(compact: true)),
                            if (_busy || _loading) const AppLoadingBar(),
                            TabBar(
                                onTap: (index) {
                                  setState(() => _tab = index);
                                  if (index == 1 && _owned == null ||
                                      index == 2 && _records == null) {
                                    _loadTab(index);
                                  }
                                },
                                tabs: const [
                                  Tab(text: '商城'),
                                  Tab(text: '我的挂件'),
                                  Tab(text: '激活记录')
                                ]),
                            Expanded(
                                child: switch (_tab) {
                              1 => _ownedList(),
                              2 => _recordList(),
                              _ => _mall()
                            }),
                          ])),
                          if (wide) ...[
                            const SizedBox(width: 24),
                            SizedBox(width: 280, child: _accountCard())
                          ],
                        ]));
    return DefaultTabController(
        length: 3,
        child: Scaffold(
            drawer: const GlobalAppDrawer(),
            appBar: AppBar(
                leading: const GlobalNavLeading(),
                title: const Text('头像挂件'),
                actions: [
                  IconButton(
                      onPressed: _busy || _loading
                          ? null
                          : () => _loadCatalog(refresh: true),
                      tooltip: '刷新',
                      icon: const Icon(Icons.refresh)),
                ]),
            body: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: body))));
  }
}
