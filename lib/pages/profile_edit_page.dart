import 'dart:async';
import '../widgets/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/klpbbs_api.dart';
import '../core/write_confirm.dart';
import '../core/dio_client.dart';
import '../models/user_space.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import 'user_space_page.dart';
import 'phone_bind_page.dart';

/// 网页表单字段、当前值和可用选项。
class _ProfileField {
  final String label;
  final String name;
  final String type; // 'text', 'textarea', 'email', 'gender', 'birthday'
  final bool hasPrivacy;
  final String privacyName;
  final bool readOnly;
  final List<Map<String, String>> options;
  final List<Map<String, String>> privacyOptions;
  final List<Map<String, String>> yearOptions, monthOptions, dayOptions;
  final int? maxLength;
  String privacyValue; // '0' (公开), '1' (好友可见), '3' (保密)
  final TextEditingController controller;
  int gender;
  int? birthYear;
  int? birthMonth;
  int? birthDay;
  late final Map<String, String> _baseline;

  _ProfileField({
    required this.label,
    required this.name,
    String value = '',
    this.type = 'text',
    this.hasPrivacy = false,
    this.privacyName = '',
    this.privacyValue = '0',
    this.readOnly = false,
    this.options = const [],
    this.privacyOptions = const [],
    this.yearOptions = const [],
    this.monthOptions = const [],
    this.dayOptions = const [],
    this.maxLength,
    this.gender = 0,
    this.birthYear,
    this.birthMonth,
    this.birthDay,
  }) : controller = TextEditingController(text: value) {
    _baseline = values;
  }

  Map<String, String> get values => {
        if (!readOnly) ...{
          if (type == 'birthday') ...{
            if (birthYear != null) 'birthyear': '$birthYear',
            if (birthMonth != null) 'birthmonth': '$birthMonth',
            if (birthDay != null) 'birthday': '$birthDay',
          } else if (type == 'gender')
            name: '$gender'
          else
            name: controller.text,
          if (hasPrivacy && privacyName.isNotEmpty) privacyName: privacyValue,
        }
      };
  Map<String, String> get edits => {
        for (final entry in values.entries)
          if (_baseline[entry.key] != entry.value) entry.key: entry.value,
      };
  bool get dirty => edits.isNotEmpty;
  void saved(Map<String, String> edits) {
    for (final key in values.keys) {
      if (edits.containsKey(key)) _baseline[key] = edits[key]!;
    }
  }

  void dispose() {
    controller.dispose();
  }
}

/// 资料设置 / 编辑资料页面（1:1 动态抓取与呈现 Discuz 3 大 Tab: 基本资料、游戏信息、个人信息）
class ProfileEditPage extends StatefulWidget {
  final int initialTabIndex;
  final UserSpace? initialUser;

  const ProfileEditPage({
    super.key,
    this.initialTabIndex = 1, // 默认进入游戏信息 Tab (对齐网页端习惯)
    this.initialUser,
  });

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 3 个 Tab 的字段列表: 0 -> 基本资料, 1 -> 游戏信息, 2 -> 个人信息
  final List<List<_ProfileField>> _tabFields = [[], [], []];

  bool _loading = false;
  final _tabLoading = [false, false, false];
  final _tabLoaded = [false, false, false];
  final List<String?> _tabErrors = [null, null, null];
  final _tabRequests = [0, 0, 0];
  final List<Future<void>?> _tabLoads = [null, null, null];
  final _editRevision = ValueNotifier<int>(0);
  int _sessionGeneration = 0;
  late int _lastTab;
  bool _wasDirty = false;
  bool get _dataLoading =>
      _tabLoading[_tabController.index] || !_tabLoaded[_tabController.index];
  String? get _loadError => _tabErrors[_tabController.index];
  bool get _dirty =>
      _tabFields.any((fields) => fields.any((field) => field.dirty));
  static const _ops = ['base', 'contact', 'info'];
  static const _labels = ['基本资料', '游戏信息', '个人信息'];
  int? _myUid;
  UserSpace? _user;

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_sessionChanged);
    _user = widget.initialUser?.uid == KlpbbsApi.currentCachedMyUid
        ? widget.initialUser
        : KlpbbsApi.cachedSpace;
    _myUid = KlpbbsApi.currentCachedMyUid;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );

    _lastTab = _tabController.index;
    _tabController.addListener(_tabChanged);
    unawaited(_loadTab(_lastTab));
    unawaited(_loadIdentity());
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_sessionChanged);
    _tabController.dispose();
    _editRevision.dispose();
    for (final list in _tabFields) {
      for (final f in list) {
        f.dispose();
      }
    }
    super.dispose();
  }

  void _tabChanged() {
    if (_lastTab == _tabController.index || !mounted) return;
    _lastTab = _tabController.index;
    setState(() {});
    unawaited(_loadTab(_lastTab));
  }

  void _edited() {
    if (!mounted) return;
    _editRevision.value++;
    final dirty = _dirty;
    if (dirty != _wasDirty) setState(() => _wasDirty = dirty);
  }

  Future<void> _loadIdentity() async {
    final generation = _sessionGeneration, session = DioClient.sessionKey;
    try {
      final uid = await KlpbbsApi.getMyUid();
      if (mounted &&
          generation == _sessionGeneration &&
          session == DioClient.sessionKey) {
        setState(() => _myUid = uid);
      }
    } catch (_) {}
  }

  Future<void> _refreshCurrentTab() async {
    final tab = _tabController.index, session = DioClient.sessionKey;
    if (_loading || _tabLoading[tab]) return;
    if (_tabFields[tab].any((field) => field.dirty)) {
      final discard =
          await _confirmDiscard('重新读取${_labels[tab]}？', '这个分类尚未保存的修改将被替换。');
      if (!discard || !mounted || session != DioClient.sessionKey) return;
    }
    await _loadTab(tab, force: true);
  }

  Future<void> _loadTab(int tab, {bool force = false}) {
    if (_tabLoads[tab] != null) return _tabLoads[tab]!;
    if (_tabLoaded[tab] && !force) return Future.value();
    final future = _fetchTab(tab, force: force);
    _tabLoads[tab] = future;
    return future.whenComplete(() {
      if (identical(_tabLoads[tab], future)) _tabLoads[tab] = null;
    });
  }

  Future<void> _fetchTab(int tab, {required bool force}) async {
    final request = ++_tabRequests[tab], generation = _sessionGeneration;
    final session = DioClient.sessionKey;
    bool current() =>
        mounted &&
        request == _tabRequests[tab] &&
        generation == _sessionGeneration &&
        session == DioClient.sessionKey;
    setState(() {
      _tabLoading[tab] = true;
      _tabErrors[tab] = null;
    });
    try {
      final data = await KlpbbsApi.getProfileEditData(
          op: _ops[tab], forceRefresh: force, expectedSession: session);
      if (!current()) return;
      setState(() {
        for (final field in _tabFields[tab]) {
          field.dispose();
        }
        _tabFields[tab].clear();
        for (final item in (data['items'] as List? ?? const [])) {
          final value = item['value']?.toString() ?? '';
          _tabFields[tab].add(_ProfileField(
            name: item['name'] as String,
            label: item['label'] as String,
            type: item['type'] as String,
            value: value,
            readOnly: item['readOnly'] == true,
            options: List<Map<String, String>>.from(
                item['options'] as List? ?? const []),
            hasPrivacy: item['hasPrivacy'] == true,
            privacyName: item['privacyName'] as String? ?? '',
            privacyValue: item['privacyValue'] as String? ?? '',
            privacyOptions: List<Map<String, String>>.from(
                item['privacyOptions'] as List? ?? const []),
            gender: int.tryParse(value) ?? 0,
            birthYear: item['birthYear'] as int?,
            birthMonth: item['birthMonth'] as int?,
            birthDay: item['birthDay'] as int?,
            yearOptions: List<Map<String, String>>.from(
                item['birthYearOptions'] as List? ?? const []),
            monthOptions: List<Map<String, String>>.from(
                item['birthMonthOptions'] as List? ?? const []),
            dayOptions: List<Map<String, String>>.from(
                item['birthDayOptions'] as List? ?? const []),
            maxLength: item['maxLength'] as int?,
          )..controller.addListener(_edited));
        }
        _tabLoaded[tab] = true;
        _tabLoading[tab] = false;
      });
      _edited();
    } catch (error) {
      if (current()) {
        setState(() {
          _tabLoading[tab] = false;
          _tabErrors[tab] = error
              .toString()
              .replaceFirst(RegExp(r'^(Bad state:|Exception:)\s*'), '');
        });
      }
    }
  }

  void _sessionChanged() {
    if (!mounted) return;
    _sessionGeneration++;
    setState(() {
      _user = null;
      _myUid = null;
      _loading = false;
      _wasDirty = false;
      for (var tab = 0; tab < 3; tab++) {
        _tabRequests[tab]++;
        _tabLoads[tab] = null;
        _tabErrors[tab] = null;
        _tabLoaded[tab] = false;
        _tabLoading[tab] = false;
        for (final field in _tabFields[tab]) {
          field.dispose();
        }
        _tabFields[tab].clear();
      }
    });
    unawaited(_loadTab(_tabController.index));
    unawaited(_loadIdentity());
  }

  Future<void> _submitCurrentTab() async {
    if (_loading || _dataLoading || _loadError != null) return;
    final session = DioClient.sessionKey;
    final currentTab = _tabController.index;
    final op = _ops[currentTab];
    final fields = _tabFields[currentTab];
    final formData = Map<String, String>.unmodifiable({
      for (final field in fields) ...field.edits,
    });
    if (formData.isEmpty) return;
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final confirmed = await confirmWrite(context, '保存${_labels[currentTab]}');
      if (!confirmed || !mounted || session != DioClient.sessionKey) return;
      final ok = await KlpbbsApi.submitProfileForm(
          op: op, formData: formData, expectedSession: session);
      if (mounted && session == DioClient.sessionKey) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(ok ? Icons.check_circle_outline : Icons.info_outline,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Flexible(
                    child: Text(ok
                        ? '${_labels[currentTab]}已保存'
                        : '服务器未确认保存，请刷新资料后重试')),
              ],
            ),
            backgroundColor: ok ? Colors.green.shade700 : null,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        if (ok) {
          for (final field in fields) {
            field.saved(formData);
          }
          _edited();
        }
      }
    } catch (e) {
      if (mounted && session == DioClient.sessionKey) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('保存异常：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _confirmDiscard(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('继续编辑')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('放弃修改')),
              ])) ==
      true;

  Future<void> _leave() async {
    if (_loading) return;
    if (!await _confirmDiscard('离开资料设置？', '尚未保存的资料修改会丢失。') || !mounted) return;
    for (final fields in _tabFields) {
      for (final field in fields) {
        field.saved(field.values);
      }
    }
    setState(() => _wasDirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
        canPop: !_wasDirty && !_loading,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leave());
        },
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          drawer: const GlobalAppDrawer(),
          drawerEdgeDragWidth: 50.0,
          appBar: AppBar(
            title: const Text(
              '资料设置',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 1,
            leading: const GlobalNavLeading(),
            leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
            actions: [
              IconButton(
                  onPressed: _loading || _tabLoading[_tabController.index]
                      ? null
                      : _refreshCurrentTab,
                  tooltip: '重新读取当前分类',
                  icon: const Icon(Icons.refresh_rounded)),
              IconButton(
                icon: const Icon(Icons.person_outline_rounded),
                tooltip: '我的空间',
                onPressed: () {
                  final uid = _myUid ?? _user?.uid;
                  if (uid != null && uid > 0) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => UserSpacePage(uid: uid)),
                    );
                  }
                },
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                        color: colorScheme.outlineVariant.withAlpha(50),
                        width: 1),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  indicatorColor: colorScheme.primary,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14.5),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 14),
                  tabs: const [
                    Tab(text: '基本资料'),
                    Tab(text: '游戏信息'),
                    Tab(text: '个人信息'),
                  ],
                ),
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildFieldsListTab(0),
              _buildFieldsListTab(1),
              _buildFieldsListTab(2),
            ],
          ),
          bottomNavigationBar: ValueListenableBuilder<int>(
              valueListenable: _editRevision,
              builder: (_, __, ___) => _buildBottomActionBar()),
        ));
  }

  Widget _buildBottomActionBar() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant.withAlpha(40)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: AppLoadingIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(
                _loading ? '正在保存…' : '保存${_labels[_tabController.index]}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _loading ||
                      _dataLoading ||
                      _loadError != null ||
                      !_tabFields[_tabController.index]
                          .any((field) => field.dirty)
                  ? null
                  : _submitCurrentTab,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldsListTab(int tabIndex) {
    final fields = _tabFields[tabIndex];
    if (_tabLoading[tabIndex] && !_tabLoaded[tabIndex]) {
      return const Center(child: AppLoadingIndicator());
    }
    final error = _tabErrors[tabIndex];
    if (error != null && fields.isEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
              onPressed: () => _loadTab(tabIndex, force: true),
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载资料')),
          if (error.contains('手机号'))
            TextButton(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const PhoneBindPage()));
                  if (mounted) await _loadTab(tabIndex, force: true);
                },
                child: const Text('进入手机绑定')),
        ]),
      ));
    }
    if (fields.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('当前用户组在此分类没有可编辑的资料', textAlign: TextAlign.center)));
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: SingleChildScrollView(
          key: PageStorageKey('profile-tab-$tabIndex'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTipBanner('资料的可编辑范围和隐私选项由论坛当前用户组决定。'),
              if (_tabLoading[tabIndex])
                const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: AppLoadingBar(minHeight: 2)),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Expanded(child: Text('读取失败，已保留当前输入。$error')),
                      TextButton(
                          onPressed: _refreshCurrentTab,
                          child: const Text('重试'))
                    ])),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, box) {
                final columns = box.maxWidth >= 820 &&
                        MediaQuery.textScalerOf(context).scale(14) < 21
                    ? 2
                    : 1;
                final width = (box.maxWidth - 14 * (columns - 1)) / columns;
                return Wrap(spacing: 14, runSpacing: 14, children: [
                  for (final field in fields)
                    SizedBox(
                        width: field.type == 'textarea' ? box.maxWidth : width,
                        child: AppFadeIn(
                            key: ValueKey(
                                'profile-${_ops[tabIndex]}-${field.name}'),
                            index: fields.indexOf(field),
                            child: _buildFieldCard(field))),
                ]);
              }),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipBanner(String tip) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withAlpha(40)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldCard(_ProfileField field) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 字段头部：Label + 隐私选择器
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text(
                  field.label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                )),
                if (field.hasPrivacy)
                  Flexible(child: _buildPrivacyBadgeDropdown(field)),
              ],
            ),
            const SizedBox(height: 10),

            // 字段核心输入控件
            if (field.type == 'gender')
              _buildGenderSelector(field)
            else if (field.type == 'birthday')
              _buildBirthdayControls(field)
            else if (field.type == 'email' && field.readOnly)
              _buildEmailReadOnlyTile(field)
            else if (field.type == 'choice')
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final option in field.options)
                  ChoiceChip(
                      label: Text(option['label'] ?? ''),
                      selected: field.controller.text == option['value'],
                      onSelected: field.readOnly || _loading
                          ? null
                          : (_) => setState(() {
                                field.controller.text = option['value'] ?? '';
                                _edited();
                              }))
              ])
            else if (field.type == 'checkbox')
              SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(field.options.isEmpty
                      ? field.label
                      : field.options.first['label'] ?? field.label),
                  value: field.controller.text.isNotEmpty,
                  onChanged: field.readOnly || _loading
                      ? null
                      : (checked) => setState(() {
                            field.controller.text =
                                checked && field.options.isNotEmpty
                                    ? field.options.first['value'] ?? 'on'
                                    : '';
                          }))
            else if (field.type == 'select')
              DropdownButtonFormField<String>(
                key: ValueKey(
                    'profile-select-${field.name}-${field.controller.text}'),
                initialValue: field.options.any(
                        (option) => option['value'] == field.controller.text)
                    ? field.controller.text
                    : null,
                isExpanded: true,
                items: field.options
                    .map((option) => DropdownMenuItem(
                        value: option['value'],
                        child: Text(option['label'] ?? '',
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: field.readOnly || _loading
                    ? null
                    : (value) {
                        if (value != null) field.controller.text = value;
                      },
              )
            else if (field.type == 'textarea')
              TextField(
                controller: field.controller,
                readOnly: field.readOnly || _loading,
                maxLength: field.maxLength,
                maxLines: 4,
                minLines: 3,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '请输入${field.label}',
                  filled: true,
                  fillColor: colorScheme.surface,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withAlpha(60)),
                  ),
                ),
              )
            else
              TextField(
                controller: field.controller,
                readOnly: field.readOnly || _loading,
                maxLength: field.maxLength,
                keyboardType: field.type == 'email'
                    ? TextInputType.emailAddress
                    : TextInputType.text,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '请输入${field.label}',
                  filled: true,
                  fillColor: colorScheme.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withAlpha(60)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyBadgeDropdown(_ProfileField field) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: field.privacyOptions
                  .any((option) => option['value'] == field.privacyValue)
              ? field.privacyValue
              : null,
          icon: Icon(Icons.arrow_drop_down_rounded,
              size: 18, color: colorScheme.outline),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary),
          items: field.privacyOptions
              .map((option) => DropdownMenuItem(
                  value: option['value'], child: Text(option['label'] ?? '')))
              .toList(),
          isExpanded: true,
          onChanged: field.readOnly || _loading
              ? null
              : (val) {
                  if (val != null) {
                    setState(() => field.privacyValue = val);
                    _edited();
                  }
                },
        ),
      ),
    );
  }

  Widget _buildGenderSelector(_ProfileField field) {
    if (field.options.isEmpty) return Text('${field.gender}');
    return Wrap(spacing: 10, runSpacing: 8, children: [
      for (final option in field.options)
        ChoiceChip(
            label: Text(option['label'] ?? ''),
            selected: '${field.gender}' == option['value'],
            onSelected: field.readOnly || _loading
                ? null
                : (_) {
                    final value = int.tryParse(option['value'] ?? '');
                    if (value == null) return;
                    setState(() => field.gender = value);
                    _edited();
                  }),
    ]);
  }

  Widget _buildBirthdayControls(_ProfileField field) {
    final year = field.birthYear ?? 0,
        month = field.birthMonth ?? 0,
        day = field.birthDay ?? 0;
    final parts = [
      if (year > 0) '$year 年',
      if (month > 0) '$month 月',
      if (day > 0) '$day 日'
    ];
    if (field.readOnly) {
      return SelectableText(parts.isEmpty ? '未设置' : parts.join(' '));
    }
    List<Map<String, String>> withValue(
        List<Map<String, String>> options, int selected) {
      final unique = <String, Map<String, String>>{
        for (final option in options)
          if (option['value'] != null) option['value']!: option,
      };
      if (!unique.containsKey('$selected')) {
        unique['$selected'] = {
          'value': '$selected',
          'label': selected == 0 ? '未设置' : '$selected',
        };
      }
      return unique.values.toList();
    }

    final maxDay = month >= 1 && month <= 12
        ? DateUtils.getDaysInMonth(year > 0 ? year : 2000, month)
        : 31;
    final dayOptions = [
      if (field.dayOptions.any((option) => option['value'] == '0') || day == 0)
        {'value': '0', 'label': '未设置'},
      for (var value = 1; value <= maxDay; value++)
        {'value': '$value', 'label': '$value'},
    ];
    Widget select(String label, int selected, List<Map<String, String>> options,
            ValueChanged<int> changed) =>
        SizedBox(
            width: label == '年' ? 132 : 94,
            child: DropdownButtonFormField<String>(
                key: ValueKey('${field.name}-$label-$selected-$year-$month'),
                initialValue: '$selected',
                isExpanded: true,
                decoration: InputDecoration(labelText: label),
                items: withValue(options, selected)
                    .map((option) => DropdownMenuItem(
                        value: option['value'],
                        child: Text(option['label'] ?? '',
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: _loading
                    ? null
                    : (value) {
                        final number = int.tryParse(value ?? '');
                        if (number != null) {
                          setState(() => changed(number));
                          _edited();
                        }
                      }));
    void clampDay() {
      if ((field.birthMonth ?? 0) > 0 &&
          (field.birthDay ?? 0) >
              DateUtils.getDaysInMonth(
                  (field.birthYear ?? 0) > 0 ? field.birthYear! : 2000,
                  field.birthMonth!)) {
        field.birthDay = DateUtils.getDaysInMonth(
            (field.birthYear ?? 0) > 0 ? field.birthYear! : 2000,
            field.birthMonth!);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 12, children: [
        if (field.yearOptions.isEmpty)
          SizedBox(
              width: 132,
              child: TextField(
                controller: field.controller,
                readOnly: _loading,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4)
                ],
                decoration:
                    const InputDecoration(labelText: '年', hintText: '未设置'),
                onChanged: (value) {
                  setState(() {
                    field.birthYear = int.tryParse(value) ?? 0;
                    clampDay();
                  });
                  _edited();
                },
              ))
        else
          select('年', year, field.yearOptions, (value) {
            field.birthYear = value;
            clampDay();
          }),
        select('月', month, field.monthOptions, (value) {
          field.birthMonth = value;
          clampDay();
        }),
        select('日', day, dayOptions, (value) => field.birthDay = value),
      ]),
      const SizedBox(height: 8),
      Text(parts.isEmpty ? '可以单独设置年月日' : parts.join(' '),
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _buildEmailReadOnlyTile(_ProfileField field) {
    final colorScheme = Theme.of(context).colorScheme;
    final email =
        field.controller.text.isNotEmpty ? field.controller.text : '未设置邮箱';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(Icons.mark_email_read_outlined,
              size: 18, color: colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              email,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('只读', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
