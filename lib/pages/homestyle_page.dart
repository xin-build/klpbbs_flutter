import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/klpbbs_homestyle.dart';
import '../models/user_space.dart';
import '../widgets/app_motion.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/retry_image.dart';
import '../widgets/user_avatar_widget.dart';

class HomeStylePage extends StatefulWidget {
  final int? uid;
  final String? username;
  final String? avatarUrl;
  const HomeStylePage({super.key, this.uid, this.username, this.avatarUrl});

  @override
  State<HomeStylePage> createState() => _HomeStylePageState();
}

class _HomeStylePageState extends State<HomeStylePage> {
  final _catalogs = <String, ({KlpHomeStyleCatalog data, DateTime time})>{};
  List<KlpHomeStyleCategory> _categories = const [];
  KlpHomeStyleCatalog? _catalog;
  KlpHomeStyle? _selection;
  UserSpace? _user;
  String _category = '', _selectionCategory = '', _background = '';
  String? _error, _profileError;
  bool _loading = false, _saving = false, _profileLoading = false;
  int _generation = 0, _profileRequest = 0, _saveRequest = 0, _myUid = 0;

  bool get _canSave =>
      _selection != null &&
      !_saving &&
      _myUid > 0 &&
      _user?.uid == _myUid &&
      _catalogs[_selectionCategory]?.data.saveValues(_selection!.id) != null;

  @override
  void initState() {
    super.initState();
    _load();
    _loadUser();
    DioClient.sessionChanges.addListener(_accountChanged);
  }

  void _accountChanged() {
    _generation++;
    _profileRequest++;
    _saveRequest++;
    _catalogs.clear();
    setState(() {
      _user = null;
      _myUid = 0;
      _selection = null;
      _selectionCategory = '';
      _background = '';
      _category = '';
      _categories = const [];
      _catalog = null;
      _error = null;
      _profileError = null;
      _saving = false;
    });
    _load();
    _loadUser();
  }

  Future<void> _load({bool refresh = false}) async {
    final request = ++_generation, category = _category;
    final session = DioClient.sessionKey;
    final cached = _catalogs[category];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.time) < const Duration(minutes: 2)) {
      setState(() {
        _catalog = cached.data;
        _categories = cached.data.categories;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _catalog = cached?.data;
    });
    try {
      final data = await KlpbbsApi.getHomeStyleCatalog(
          smod: category, forceRefresh: refresh);
      if (!mounted || session != DioClient.sessionKey) return;
      _catalogs[category] = (data: data, time: DateTime.now());
      if (request != _generation) return;
      setState(() {
        _catalog = data;
        _categories = data.categories;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          request != _generation ||
          session != DioClient.sessionKey) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadUser({bool refresh = false}) async {
    final request = ++_profileRequest;
    final session = DioClient.sessionKey;
    bool current() =>
        mounted &&
        request == _profileRequest &&
        session == DioClient.sessionKey;
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });
    try {
      final myUid = await KlpbbsApi.getMyUid();
      final uid = widget.uid ?? myUid;
      if (uid == null || uid <= 0) {
        if (current()) setState(() => _profileLoading = false);
        return;
      }
      final space = await KlpbbsApi.getUserSpace(uid, forceRefresh: refresh);
      if (!current()) return;
      setState(() {
        _myUid = myUid ?? 0;
        _user = space;
        _profileLoading = false;
        _profileError = space == null ? '暂时无法读取空间资料' : null;
        if (_selection == null) _background = space?.bgUrl ?? '';
      });
    } catch (_) {
      // The catalog remains usable when the independent profile read fails.
      if (current()) {
        setState(() {
          _profileLoading = false;
          _profileError = '空间资料读取失败';
        });
      }
    }
  }

  Future<void> _save() async {
    final item = _selection;
    if (!_canSave || item == null) return;
    final request = ++_saveRequest, category = _selectionCategory;
    final session = DioClient.sessionKey;
    bool current() =>
        mounted && request == _saveRequest && session == DioClient.sessionKey;
    setState(() => _saving = true);
    try {
      final ok = await KlpbbsApi.saveHomeStyle(item.id, smod: category);
      if (!current()) return;
      if (!ok) throw StateError('网站未确认保存成功，请刷新空间确认后重试');
      await AppConfig.setSpaceWallpaper(item.url);
      if (!mounted || !current()) return;
      setState(() {
        _background = item.url;
        _selection = null;
        _selectionCategory = '';
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('空间背景已保存')));
    } catch (error) {
      if (mounted && current()) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (current()) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _profileRequest++;
    _saveRequest++;
    DioClient.sessionChanges.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _catalog?.items ?? const <KlpHomeStyle>[];
    return Scaffold(
      drawer: const GlobalAppDrawer(),
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('空间装扮'),
        actions: [
          IconButton(
              tooltip: '刷新当前分类',
              onPressed: _loading ? null : () => _load(refresh: true),
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final catalog = Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Expanded(
                      child: Text('背景目录',
                          style: Theme.of(context).textTheme.titleMedium)),
                  if (_catalog != null)
                    Text('${items.length} 款',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                ])),
            if (_categories.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  for (final category in _categories)
                    Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(category.name),
                          selected: category.id == _category,
                          onSelected: _saving
                              ? null
                              : (selected) {
                                  if (selected && category.id != _category) {
                                    _category = category.id;
                                    _load();
                                  }
                                },
                        )),
                ]),
              ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.cloud_off_outlined, color: scheme.error),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_error!)),
                  TextButton(
                      onPressed: _loading ? null : () => _load(refresh: true),
                      child: const Text('重试')),
                ]),
              ),
            Expanded(
                child: AnimatedSwitcher(
              duration: AppMotion.duration(context, 180),
              child: items.isEmpty
                  ? Center(
                      key: ValueKey('empty-$_category'),
                      child: _loading
                          ? const AppLoadingIndicator()
                          : Text(_error == null ? '此分类暂无背景' : '暂时无法读取背景目录'),
                    )
                  : GridView.builder(
                      key: PageStorageKey('homestyle-$_category'),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 340,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.45,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _tile(items[index], index),
                    ),
            )),
          ]);
          return Padding(
            padding: EdgeInsets.all(wide ? 20 : 0),
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 330, child: _preview()),
                    const SizedBox(width: 16),
                    Expanded(child: catalog),
                  ])
                : Column(children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: _preview(compact: true)),
                    Expanded(child: catalog),
                  ]),
          );
        }),
      )),
      bottomNavigationBar: SafeArea(
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Expanded(
              child: Text(
                  _selection == null
                      ? _myUid <= 0 && !_profileLoading
                          ? '登录后可保存空间背景'
                          : '选择背景，预览后保存到空间'
                      : '已选择 ${_selection!.name.isEmpty ? '背景 ${_selection!.id}' : _selection!.name}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(width: 12),
          if (_selection != null && !_saving)
            IconButton(
                key: const ValueKey('homestyle-reset-preview'),
                tooltip: '恢复当前背景',
                onPressed: () => setState(() {
                      _selection = null;
                      _selectionCategory = '';
                    }),
                icon: const Icon(Icons.undo_rounded)),
          FilledButton.icon(
            key: const ValueKey('homestyle-save'),
            onPressed: _canSave ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: AppLoadingIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('保存'),
          ),
        ]),
      )),
    );
  }

  Widget _preview({bool compact = false}) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final url = _selection?.url ?? _background;
    final user = _user;
    return Card.filled(
      key: const ValueKey('homestyle-preview'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_profileLoading) const LinearProgressIndicator(minHeight: 2),
        SizedBox(
          height: compact ? 130 : 210,
          width: double.infinity,
          child: AnimatedSwitcher(
            duration: AppMotion.duration(context, 200),
            child: url.isEmpty
                ? ColoredBox(
                    key: const ValueKey('no-background'),
                    color: scheme.surfaceContainerHighest,
                    child: Center(
                        child: Icon(Icons.wallpaper_outlined,
                            size: 48, color: scheme.onSurfaceVariant)),
                  )
                : RetryImage(
                    key: ValueKey(url),
                    imageUrl: url,
                    width: double.infinity,
                    height: compact ? 130 : 210,
                    fit: BoxFit.cover,
                    memCacheWidth: 720),
          ),
        ),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              UserAvatarWidget(
                  uid: user?.uid,
                  author: user?.username ?? '',
                  avatarUrl: user != null && user.uid == widget.uid
                      ? widget.avatarUrl
                      : null,
                  size: 44,
                  reserveFrameSpace: true,
                  faceUrl: UserAvatarWidget.optionalFrame(user?.faceUrl)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(user?.username ?? '空间预览',
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (user?.group.isNotEmpty == true)
                      Text(user!.group, style: theme.textTheme.bodySmall),
                    if (user?.credits.isNotEmpty == true && !compact)
                      Text('积分 ${user!.credits}',
                          style: theme.textTheme.bodySmall),
                  ])),
            ])),
        if (_profileError != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(children: [
                Expanded(
                    child: Text(_profileError!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.error))),
                TextButton(
                    onPressed:
                        _profileLoading ? null : () => _loadUser(refresh: true),
                    child: const Text('重试')),
              ])),
      ]),
    );
  }

  Widget _tile(KlpHomeStyle item, int index) {
    final scheme = Theme.of(context).colorScheme;
    final selected =
        _selection?.id == item.id && _selectionCategory == _category;
    return RepaintBoundary(
        child: AppFadeIn(
            index: index,
            child: Card.filled(
              key: ValueKey('homestyle-item-${item.id}'),
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected ? 2 : 1)),
              child: InkWell(
                  onTap: _saving
                      ? null
                      : () => setState(() {
                            _selection = item;
                            _selectionCategory = _category;
                          }),
                  child: Column(children: [
                    Expanded(
                        child: RetryImage(
                            imageUrl: item.url,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            memCacheWidth: 480)),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Row(children: [
                          Expanded(
                              child: Text(
                                  item.name.isEmpty
                                      ? '背景 ${item.id}'
                                      : item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          if (Uri.tryParse(item.url)
                                  ?.path
                                  .toLowerCase()
                                  .endsWith('.gif') ==
                              true)
                            const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Text('GIF')),
                          AnimatedSwitcher(
                              duration: AppMotion.duration(context, 150),
                              child: Icon(
                                  selected
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  key: ValueKey(selected),
                                  size: 20,
                                  color: selected
                                      ? scheme.primary
                                      : scheme.outline)),
                        ])),
                  ])),
            )));
  }
}
