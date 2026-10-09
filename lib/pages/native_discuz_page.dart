import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../core/app_config.dart';
import '../core/discuz_forum_parser.dart';
import '../core/discuz_native_page.dart';
import '../core/klpbbs_developer_platform.dart';
import '../core/klpbbs_authorizations.dart';
import 'authorized_apps_page.dart';
import 'membership_page.dart';
import '../widgets/app_motion.dart';
import '../widgets/empty_view.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/retry_image.dart';
import 'login_page.dart';
import 'avatar_edit_page.dart';
import 'phone_bind_page.dart';
import 'facemall_page.dart';
import 'developer_console_page.dart';
import 'thread_detail_page.dart';
import 'thread_list_page.dart';
import 'user_space_page.dart';

/// 网页提供字段与数据，客户端负责布局、校验、状态与交互。
class NativeDiscuzPage extends StatefulWidget {
  final String title, path;
  final DiscuzNativePageReceipt? initialData;
  const NativeDiscuzPage(
      {super.key, required this.title, required this.path, this.initialData});
  @override
  State<NativeDiscuzPage> createState() => _NativeDiscuzPageState();
}

class _NativeDiscuzPageState extends State<NativeDiscuzPage> {
  late Future<DiscuzNativePageReceipt> _future;
  DiscuzNativePageReceipt? _lastReceipt;
  String _result = '';
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _future = widget.initialData == null
        ? KlpbbsApi.getNativePage(widget.path)
        : Future.value(widget.initialData);
    _future.ignore();
    DioClient.sessionChanges.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _result = '';
      _busy = false;
      _lastReceipt = null;
      _future = KlpbbsApi.getNativePage(widget.path);
      _future.ignore();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _result = '';
      _future = KlpbbsApi.getNativePage(widget.path);
      _future.ignore();
    });
    try {
      await _future;
    } catch (_) {}
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _login() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (mounted) await _refresh();
  }

  Future<void> _open(
      DiscuzNativePageReceipt receipt, DiscuzPageLink link) async {
    if (_busy) return;
    if (link.changesData) {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(link.label),
                content: const Text('确认执行此操作？'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认')),
                ],
              ));
      if (confirm != true || !mounted) return;
      final generation = _generation;
      setState(() => _busy = true);
      try {
        final result = await KlpbbsApi.performNativePageAction(receipt, link);
        if (!mounted || generation != _generation) return;
        setState(() {
          _future = Future.value(result);
          _result = result.page.message ?? '';
        });
      } catch (error) {
        if (mounted && generation == _generation) {
          setState(() => _result = '操作未完成，请刷新页面后重试。');
        }
      } finally {
        if (mounted && generation == _generation) setState(() => _busy = false);
      }
      return;
    }
    final uri = link.uri, query = link.uri.queryParameters;
    final thread = RegExp(r'thread-(\d+)').firstMatch(uri.path)?[1] ??
        (query['mod'] == 'viewthread' ? query['tid'] : null);
    final uid = RegExp(r'space-uid-(\d+)').firstMatch(uri.path)?[1] ??
        (query['mod'] == 'space' && query['do'] == null ? query['uid'] : null);
    final fid =
        DiscuzForumParser.forumId(uri.toString(), Uri.parse(AppConfig.baseUrl));
    final avatar = query['mod'] == 'spacecp' && query['ac'] == 'avatar';
    final phone = query['id'] == 'klpbbs_pnbind:my_bind';
    final accountUid = int.tryParse(query['uid'] ?? '');
    final facemall = (uri.path == 'home.php' ||
            uri.path.endsWith('/home.php')) &&
        query['mod'] == 'spacecp' &&
        query['ac'] == 'plugin' &&
        query['id'] == 'sunju_facemall:face' &&
        (query['uid'] == null ||
            (accountUid != null && accountUid == KlpbbsApi.currentCachedMyUid));
    final developerView = KlpbbsDeveloperPlatform.viewFor(uri);
    final ownAccount =
        query['uid'] == null || accountUid == KlpbbsApi.currentCachedMyUid;
    final membership = ownAccount &&
        uri.path.split('/').last == 'home.php' &&
        query['mod'] == 'spacecp' &&
        query['ac'] == 'usergroup' &&
        query['do'] == 'list' &&
        uri.queryParametersAll.values.every((values) => values.length == 1) &&
        query.keys.every(
            (key) => const {'mod', 'ac', 'do', 'mobile', 'uid'}.contains(key));
    final Widget target = membership
        ? const MembershipPage()
        : ownAccount && KlpbbsAuthorizations.isListPage(uri)
            ? const AuthorizedAppsPage()
            : developerView != null
                ? DeveloperConsolePage(initialView: developerView)
                : avatar
                    ? const AvatarEditPage()
                    : phone
                        ? const PhoneBindPage()
                        : facemall
                            ? const FacemallPage()
                            : int.tryParse(thread ?? '') != null
                                ? ThreadDetailPage(tid: int.parse(thread!))
                                : int.tryParse(uid ?? '') != null
                                    ? UserSpacePage(uid: int.parse(uid!))
                                    : fid != null
                                        ? ThreadListPage(
                                            fid: fid, title: link.label)
                                        : NativeDiscuzPage(
                                            title: link.label,
                                            path: uri.toString());
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => target));
  }

  Future<void> _submit(
      DiscuzNativePageReceipt receipt,
      DiscuzNativeForm form,
      String button,
      Map<String, List<String>> values,
      Map<String, List<String>> files) async {
    if (_busy) return;
    final generation = _generation;
    setState(() => _busy = true);
    final result = await KlpbbsApi.submitNativeForm(
        receipt, form.key, button, values,
        filePaths: files);
    if (!mounted || generation != _generation) return;
    setState(() {
      _busy = false;
      _result = result.message;
      if (result.nextPage != null) _future = Future.value(result.nextPage);
    });
    if (result.success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), leadingWidth: 56, actions: [
        IconButton(
            onPressed: _busy ? null : _refresh,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: Column(children: [
        if (_busy) const AppLoadingBar(),
        Expanded(
            child: FutureBuilder<DiscuzNativePageReceipt>(
          future: _future,
          builder: (context, snapshot) {
            final pending = snapshot.connectionState != ConnectionState.done;
            if (!pending &&
                !snapshot.hasError &&
                snapshot.hasData &&
                snapshot.data!.session == DioClient.sessionKey) {
              _lastReceipt = snapshot.data;
            }
            final receipt = _lastReceipt;
            if (pending && receipt == null) {
              return const Center(child: AppLoadingIndicator());
            }
            if (snapshot.hasError && receipt == null) {
              return EmptyView(
                icon: Icons.cloud_off_outlined,
                title: '暂时无法读取',
                subtitle: '连接未完成，请检查网络后重试。',
                action: FilledButton.tonal(
                    onPressed: _refresh, child: const Text('重试')),
              );
            }
            if (receipt == null || receipt.session != DioClient.sessionKey) {
              return const Center(child: AppLoadingIndicator());
            }
            final page = receipt.page;
            final desktop = ResponsiveBreakpoints.isDesktop(context);
            List<String> comparisonNames = const [];
            for (final table in page.tables) {
              if (table.headers.firstOrNull == '权限') {
                comparisonNames = table.headers
                    .skip(1)
                    .where((name) => name.trim().isNotEmpty)
                    .toList();
                break;
              }
            }
            return Column(children: [
              if (comparisonNames.isNotEmpty)
                _PermissionComparisonContext(
                    names: comparisonNames,
                    actions: page.headerActions,
                    busy: _busy,
                    onOpen: (link) => _open(receipt, link)),
              Expanded(
                  child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                      horizontal: desktop ? 24 : 12, vertical: 16),
                  children: [
                    Center(
                        child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (pending) const AppLoadingBar(),
                            if (snapshot.hasError)
                              Card.filled(
                                  child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(children: [
                                        const Expanded(
                                            child: Text('刷新未完成，保留上次读取的内容。')),
                                        TextButton(
                                            onPressed: _refresh,
                                            child: const Text('重试')),
                                      ]))),
                            if (_result.isNotEmpty ||
                                page.message?.isNotEmpty == true)
                              Card.filled(
                                  child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline_rounded,
                                          color: scheme.primary),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: SelectableText(
                                              _result.isNotEmpty
                                                  ? _result
                                                  : page.message!)),
                                    ]),
                              )),
                            if (page.requiresLogin) ...[
                              const SizedBox(height: 12),
                              FilledButton.tonalIcon(
                                  onPressed: _login,
                                  icon: const Icon(Icons.login_rounded),
                                  label: const Text('登录后继续')),
                            ],
                            if (page.avatarPage)
                              Card.filled(
                                  child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('当前头像与审核状态',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 8),
                                          const Text('当前仅查看头像和审核状态，上传正在适配。'),
                                          if (page.avatarDescriptor
                                                  ?.requiresReview ==
                                              true) ...[
                                            const SizedBox(height: 12),
                                            const Chip(
                                                avatar: Icon(
                                                    Icons
                                                        .verified_user_outlined,
                                                    size: 16),
                                                label: Text('头像需要论坛审核')),
                                          ],
                                          for (final image in page.images)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 16),
                                                child: RetryImage(
                                                    imageUrl:
                                                        image.uri.toString(),
                                                    width: 96,
                                                    height: 96,
                                                    fit: BoxFit.contain)),
                                        ],
                                      ))),
                            for (final form in page.avatarPage
                                ? <DiscuzNativeForm>[]
                                : page.forms) ...[
                              const SizedBox(height: 12),
                              _NativeFormPanel(
                                key: ValueKey(
                                    '${receipt.session}:${form.key}:${receipt.loadedAt.microsecondsSinceEpoch}'),
                                form: form,
                                receipt: receipt,
                                busy: _busy ||
                                    pending ||
                                    snapshot.hasError ||
                                    page.requiresLogin,
                                onSubmit: (button, values, files) => _submit(
                                    receipt, form, button, values, files),
                              ),
                            ],
                            for (final table in page.tables) ...[
                              const SizedBox(height: 12),
                              _NativeDataTable(
                                  table: table,
                                  desktop: desktop,
                                  onOpen: (link) => _open(receipt, link)),
                            ],
                            if (page.information.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Card.filled(
                                  child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final text in page.information)
                                            Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 4),
                                                child: SelectableText(text)),
                                        ],
                                      ))),
                            ],
                            if (!page.avatarPage)
                              for (final image in page.images)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Center(
                                        child: RetryImage(
                                            imageUrl: image.uri.toString(),
                                            width: 240,
                                            fit: BoxFit.contain))),
                            if (page.links.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _NativePageLinks(
                                links: page.links,
                                busy: _busy,
                                onOpen: (link) => _open(receipt, link),
                              ),
                            ],
                            if (page.emptyTitle != null ||
                                (page.forms.isEmpty &&
                                    page.tables.isEmpty &&
                                    page.information.isEmpty &&
                                    page.links.isEmpty &&
                                    page.message == null &&
                                    !page.requiresLogin))
                              EmptyView(
                                  icon: Icons.pending_actions_outlined,
                                  title: page.emptyTitle ?? '暂时没有可用内容',
                                  subtitle: page.emptyDescription ??
                                      '当前页面未提供可直接使用的表单或数据。'),
                            const SizedBox(height: 24),
                          ]),
                    ))
                  ],
                ),
              )),
            ]);
          },
        )),
      ]),
    );
  }
}

/// Keep the compared groups visible while the table and its footer scroll.
class _PermissionComparisonContext extends StatelessWidget {
  final List<String> names;
  final List<DiscuzPageLink> actions;
  final bool busy;
  final ValueChanged<DiscuzPageLink> onOpen;
  const _PermissionComparisonContext(
      {required this.names,
      required this.actions,
      required this.busy,
      required this.onOpen});

  @override
  Widget build(BuildContext context) => Material(
      key: const ValueKey('native-permission-comparison'),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var index = 0;
                                  index < names.length;
                                  index++) ...[
                                if (index > 0) const SizedBox(width: 16),
                                Expanded(
                                    child: Semantics(
                                        header: true,
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  index == 0
                                                      ? '当前用户组'
                                                      : '对比用户组',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                          color: Theme.of(
                                                                  context)
                                                              .colorScheme
                                                              .onSurfaceVariant)),
                                              const SizedBox(height: 4),
                                              Text(names[index],
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600)),
                                            ]))),
                              ],
                            ]),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(spacing: 8, runSpacing: 4, children: [
                                for (final action in actions)
                                  FilledButton.tonalIcon(
                                      key: const ValueKey(
                                          'native-permission-purchase'),
                                      onPressed:
                                          busy ? null : () => onOpen(action),
                                      icon: const Icon(
                                          Icons.shopping_bag_outlined,
                                          size: 18),
                                      label: Text(action.label)),
                              ])),
                        ],
                      ])))));
}

/// Keep page tabs, record links and destructive actions in separate groups.
class _NativePageLinks extends StatelessWidget {
  final List<DiscuzPageLink> links;
  final bool busy;
  final ValueChanged<DiscuzPageLink> onOpen;
  const _NativePageLinks(
      {required this.links, required this.busy, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final navigation =
        links.where((link) => link.kind == DiscuzLinkKind.navigation).toList();
    final records =
        links.where((link) => link.kind == DiscuzLinkKind.content).toList();
    final pages =
        links.where((link) => link.kind == DiscuzLinkKind.pagination).toList();
    final actions = links.where((link) => link.changesData).toList();
    Widget button(DiscuzPageLink link) => OutlinedButton(
          onPressed: busy ? null : () => onOpen(link),
          child: Text(link.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
    Widget record(DiscuzPageLink link) => ListTile(
          title: Text(link.label, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
          onTap: busy ? null : () => onOpen(link),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (navigation.isNotEmpty)
        Card.filled(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: navigation.take(8).map(button).toList()),
                      if (navigation.length > 8)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('其他入口'),
                          children: [
                            Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children:
                                    navigation.skip(8).map(button).toList())
                          ],
                        ),
                    ]))),
      if (records.isNotEmpty)
        Card.filled(
            child: Column(children: [
          ...records.take(6).map(record),
          if (records.length > 6)
            ExpansionTile(
                title: Text('更多内容（${records.length - 6}）'),
                children: records.skip(6).map(record).toList()),
        ])),
      if (pages.isNotEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: pages.map(button).toList())),
      if (actions.isNotEmpty)
        Card.outlined(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('可用操作',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: actions.take(6).map(button).toList()),
                      if (actions.length > 6)
                        ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text('其他操作（${actions.length - 6}）'),
                            children: actions.skip(6).map(record).toList()),
                    ]))),
    ]);
  }
}

typedef _Submit = Future<void> Function(String button,
    Map<String, List<String>> values, Map<String, List<String>> files);

class _NativeFormPanel extends StatefulWidget {
  final DiscuzNativeForm form;
  final DiscuzNativePageReceipt receipt;
  final bool busy;
  final _Submit onSubmit;
  const _NativeFormPanel(
      {super.key,
      required this.form,
      required this.receipt,
      required this.busy,
      required this.onSubmit});
  @override
  State<_NativeFormPanel> createState() => _NativeFormPanelState();
}

class _NativeFormPanelState extends State<_NativeFormPanel> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _values = <String, List<String>>{}, _files = <String, List<String>>{};
  Uint8List? _captcha;
  bool _captchaLoading = false;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    for (final field in widget.form.fields) {
      _values[field.name] = [...field.initialValues];
      if (!const {
        DiscuzFieldKind.select,
        DiscuzFieldKind.checkbox,
        DiscuzFieldKind.radio,
        DiscuzFieldKind.file
      }.contains(field.kind)) {
        _controllers[field.name] =
            TextEditingController(text: field.initialValues.firstOrNull ?? '');
        if (field.name == widget.form.quantityField) {
          _controllers[field.name]!.addListener(_quantityChanged);
        }
      }
    }
    if (widget.form.hasCaptcha && widget.form.captchaHash.isNotEmpty) {
      _loadCaptcha();
    }
  }

  void _quantityChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCaptcha() async {
    if (_captchaLoading) return;
    setState(() => _captchaLoading = true);
    final bytes = await KlpbbsApi.getSecCodeImageBytes(widget.form.captchaHash,
        seccodemodid: widget.form.captchaModid,
        referer: widget.receipt.page.uri.toString());
    if (mounted && widget.receipt.session == DioClient.sessionKey) {
      setState(() {
        _captcha = bytes;
        _captchaLoading = false;
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _captcha = null;
    super.dispose();
  }

  Future<void> _pickFile(DiscuzNativeField field) async {
    final result = await FilePicker.pickFiles(allowMultiple: field.multiple);
    if (!mounted || result == null) return;
    if (result.files.any((file) => !field.acceptsFileName(file.name))) {
      setState(() => _fieldError = '文件格式不符合${field.label}要求');
      return;
    }
    setState(() => _files[field.name] =
        result.files.map((file) => file.path).whereType<String>().toList());
  }

  Future<void> _submit(DiscuzSubmitButton button) async {
    if (!_formKey.currentState!.validate()) return;
    final values = {
      for (final field in widget.form.fields)
        field.name: _controllers.containsKey(field.name)
            ? [_controllers[field.name]!.text]
            : _values[field.name] ?? [],
    };
    try {
      widget.form.submission(values, button.key);
    } on FormatException catch (error) {
      setState(() => _fieldError = error.message);
      return;
    }
    final uri = widget.form.action, query = widget.form.action.queryParameters;
    final review = query['mod'] == 'magic' ||
        query['ac'] == 'usergroup' ||
        query['mod'] == 'modcp' ||
        query['mod'] == 'topicadmin' ||
        uri.path.endsWith('admin.php') ||
        query['op'] == 'buy' ||
        query['op'] == 'transfer';
    if (review && widget.form.method == 'POST') {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(widget.form.title.isEmpty
                    ? button.label
                    : widget.form.title),
                content: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      if (widget.form.description.isNotEmpty)
                        Text(widget.form.description),
                      if (widget.form.totalPrice(values)
                          case final double price)
                        Text(
                            '合计：${price == price.roundToDouble() ? price.toInt() : price} ${widget.form.priceUnit}'),
                      for (final field in widget.form.fields.where((field) =>
                          !field.readOnly &&
                          field.kind != DiscuzFieldKind.password))
                        if ((values[field.name] ?? []).isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                  '${field.label}：${values[field.name]!.join("、")}')),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('返回修改')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('确认${button.label}')),
                ],
              ));
      if (confirm != true || !mounted) return;
    }
    setState(() => _fieldError = null);
    await widget.onSubmit(button.key, values, _files);
  }

  Widget _field(DiscuzNativeField field) {
    final disabled =
        widget.busy || field.readOnly || widget.receipt.page.avatarPage;
    final scheme = Theme.of(context).colorScheme;
    if (field.kind == DiscuzFieldKind.file) {
      final paths = _files[field.name] ?? [];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(field.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (field.accept?.isNotEmpty == true)
          Text('支持格式：${field.accept}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final path in paths)
            InputChip(
                label: Text(path.split(RegExp(r'[/\\]')).last),
                onDeleted:
                    disabled ? null : () => setState(() => paths.remove(path))),
          OutlinedButton.icon(
              onPressed: disabled ? null : () => _pickFile(field),
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: const Text('选择文件')),
        ]),
      ]);
    }
    if (const {
          DiscuzFieldKind.select,
          DiscuzFieldKind.radio,
          DiscuzFieldKind.checkbox
        }.contains(field.kind) &&
        field.choices.isEmpty) {
      return InputDecorator(
          decoration: InputDecoration(labelText: field.label, enabled: false),
          child: const Text('当前没有可用选项'));
    }
    if (field.kind == DiscuzFieldKind.select && !field.multiple) {
      final choices = {
        for (final choice in field.choices) choice.value: choice.label
      };
      final current = _values[field.name]?.firstOrNull;
      return DropdownButtonFormField<String>(
        initialValue: choices.containsKey(current) ? current : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: field.label),
        items: choices.entries
            .map((entry) => DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value,
                    maxLines: 2, overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: disabled || choices.isEmpty
            ? null
            : (value) => setState(
                () => _values[field.name] = value == null ? [] : [value]),
        validator: (_) => field.validate(_values[field.name] ?? []),
      );
    }
    if (field.choices.isNotEmpty) {
      final checkbox = field.multiple || field.kind == DiscuzFieldKind.checkbox;
      return FormField<List<String>>(
        initialValue: _values[field.name],
        validator: (_) => field.validate(_values[field.name] ?? []),
        builder: (state) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(field.label,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            if (checkbox && field.choices.length > 4)
              TextButton(
                  onPressed: disabled
                      ? null
                      : () => setState(() => _values[field.name] =
                          _values[field.name]!.length == field.choices.length
                              ? []
                              : field.choices
                                  .map((choice) => choice.value)
                                  .toList()),
                  child: const Text('全选 / 清空')),
          ]),
          if (checkbox)
            for (final choice in field.choices)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(choice.label),
                value: _values[field.name]!.contains(choice.value),
                onChanged: disabled
                    ? null
                    : (value) => setState(() {
                          final list = _values[field.name]!;
                          if (value == true) {
                            list.add(choice.value);
                          } else {
                            list.remove(choice.value);
                          }
                        }),
              )
          else
            RadioGroup<String>(
              groupValue: _values[field.name]?.firstOrNull,
              onChanged: (value) {
                if (!disabled) {
                  setState(
                      () => _values[field.name] = value == null ? [] : [value]);
                }
              },
              child: Column(children: [
                for (final choice in field.choices)
                  RadioListTile<String>(
                      value: choice.value,
                      enabled: !disabled,
                      title: Text(choice.label),
                      dense: true,
                      contentPadding: EdgeInsets.zero),
              ]),
            ),
          if (state.hasError)
            Text(state.errorText!, style: TextStyle(color: scheme.error)),
        ]),
      );
    }
    return TextFormField(
      controller: _controllers[field.name],
      readOnly: disabled,
      obscureText: field.kind == DiscuzFieldKind.password,
      enableSuggestions: field.kind != DiscuzFieldKind.password,
      autocorrect: field.kind != DiscuzFieldKind.password,
      minLines: field.kind == DiscuzFieldKind.multiline ? 3 : 1,
      maxLines: field.kind == DiscuzFieldKind.multiline ? 8 : 1,
      maxLength: field.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      buildCounter: field.maxLength == null
          ? null
          : (context, {required currentLength, required isFocused, maxLength}) {
              final length = _controllers[field.name]!.text.length;
              return Text('$length / $maxLength',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: length > field.maxLength!
                          ? scheme.error
                          : scheme.onSurfaceVariant));
            },
      keyboardType: field.kind == DiscuzFieldKind.number ||
              const {'magicnum', 'days', 'tid', 'pid'}.contains(field.name)
          ? TextInputType.number
          : field.kind == DiscuzFieldKind.email
              ? TextInputType.emailAddress
              : TextInputType.text,
      decoration: InputDecoration(
          labelText: field.label,
          helperText:
              field.minLength == null ? null : '至少 ${field.minLength} 个字符',
          alignLabelWithHint: field.kind == DiscuzFieldKind.multiline),
      validator: (value) => field.validate([value ?? '']),
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form, scheme = Theme.of(context).colorScheme;
    return Card.filled(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (form.title.isNotEmpty) ...[
                      Text(form.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                    ],
                    if (form.description.isNotEmpty) ...[
                      Text(form.description,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, height: 1.45)),
                      const SizedBox(height: 18),
                    ],
                    for (final field in form.fields)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _field(field)),
                    if (form.unitPrice != null &&
                        _controllers[form.quantityField] != null) ...[
                      Builder(builder: (context) {
                        final total = form.totalPrice({
                          form.quantityField: [
                            _controllers[form.quantityField]!.text
                          ]
                        });
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.payments_outlined),
                          title: const Text('费用合计'),
                          trailing: Text(
                              total == null
                                  ? '—'
                                  : '${total == total.roundToDouble() ? total.toInt() : total} ${form.priceUnit}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: scheme.primary)),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],
                    if (form.hasCaptcha) ...[
                      Row(children: [
                        if (_captchaLoading)
                          const SizedBox(
                              width: 100,
                              height: 42,
                              child: Center(child: AppLoadingIndicator()))
                        else if (_captcha != null)
                          Image.memory(_captcha!, height: 42)
                        else
                          const Text('验证码暂未能加载'),
                        IconButton(
                            onPressed:
                                _captchaLoading || form.captchaHash.isEmpty
                                    ? null
                                    : _loadCaptcha,
                            tooltip: '刷新验证码',
                            icon: const Icon(Icons.refresh_rounded)),
                      ]),
                      const SizedBox(height: 12),
                    ],
                    if (_fieldError != null) ...[
                      Text(_fieldError!, style: TextStyle(color: scheme.error)),
                      const SizedBox(height: 12)
                    ],
                    if (form.method == 'POST' && !form.hasCsrf)
                      const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('当前提交方式仍在适配。')),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final button in form.buttons)
                        FilledButton(
                          onPressed: widget.busy ||
                                  widget.receipt.page.avatarPage ||
                                  (form.method == 'POST' && !form.hasCsrf)
                              ? null
                              : () => _submit(button),
                          child: Text(button.label),
                        ),
                    ]),
                  ]),
            )));
  }
}

class _NativeDataTable extends StatefulWidget {
  final DiscuzDataTable table;
  final bool desktop;
  final ValueChanged<DiscuzPageLink> onOpen;
  const _NativeDataTable(
      {required this.table, required this.desktop, required this.onOpen});
  @override
  State<_NativeDataTable> createState() => _NativeDataTableState();
}

class _NativeDataTableState extends State<_NativeDataTable> {
  final _pageKey = GlobalKey<PaginatedDataTableState>();
  int _rowsPerPage = 20;
  String _query = '';
  late final _TableSource _source = _TableSource(widget.table, _cell);
  Widget _cell(String value, int column, int index) {
    final link = column == 0 ? widget.table.rowLinks[index] : null;
    return SizedBox(
        width: column == 0
            ? 180
            : widget.table.headers.length > 4
                ? 96
                : 230,
        child: link == null
            ? _NativeTableValue(value: value)
            : TextButton(
                onPressed: () => widget.onOpen(link),
                style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
                child:
                    Text(value, maxLines: 2, overflow: TextOverflow.ellipsis)));
  }

  @override
  void didUpdateWidget(covariant _NativeDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.table != widget.table) _source.update(widget.table, _query);
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    Widget? heading = table.title.isEmpty
        ? null
        : Text(table.title, style: Theme.of(context).textTheme.titleMedium);
    if (table.rowLinks.isNotEmpty) {
      heading = Row(children: [
        Expanded(
            child: Text(table.title.isEmpty ? '版块权限' : table.title,
                style: Theme.of(context).textTheme.titleMedium)),
        SizedBox(
            width: widget.desktop ? 300 : 160,
            child: TextField(
                key: const ValueKey('forum-permission-search'),
                decoration: const InputDecoration(
                    hintText: '查找版块',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true),
                onChanged: (value) => setState(() {
                      _query = value;
                      _source.update(table, value);
                      _pageKey.currentState?.pageTo(0);
                    }))),
      ]);
    }
    if (!widget.desktop || table.headers.isEmpty) {
      return Card.filled(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (heading != null) heading,
                  for (final index in _source.indexes) ...[
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _cell(table.rows[index].first, 0, index),
                              const SizedBox(height: 8),
                              Wrap(spacing: 16, runSpacing: 10, children: [
                                for (var i = 1;
                                    i < table.rows[index].length;
                                    i++)
                                  SizedBox(
                                      width: 150,
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (i < table.headers.length)
                                              Text(table.headers[i],
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                          color: Theme.of(
                                                                  context)
                                                              .colorScheme
                                                              .onSurfaceVariant)),
                                            const SizedBox(height: 3),
                                            _NativeTableValue(
                                                value: table.rows[index][i]),
                                          ])),
                              ]),
                            ])),
                    if (index != _source.indexes.last) const Divider(height: 1),
                  ],
                  if (_source.rowCount == 0)
                    const Padding(
                        padding: EdgeInsets.all(16), child: Text('没有匹配的记录')),
                ],
              )));
    }
    final rowCount = _source.rowCount;
    final pageRows = rowCount == 0
        ? 1
        : rowCount < _rowsPerPage
            ? rowCount
            : _rowsPerPage;
    final pageOptions = <int>{
      pageRows,
      if (rowCount > 0 && rowCount <= 100) rowCount,
      5,
      10,
      20,
      50,
    }.toList()
      ..sort();
    return Card.filled(
        child: PaginatedDataTable(
      key: _pageKey,
      header: heading,
      horizontalMargin: 18,
      columnSpacing: 16,
      headingRowHeight: 68,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 84,
      rowsPerPage: pageRows,
      availableRowsPerPage: pageOptions,
      onRowsPerPageChanged: (value) {
        if (value != null) setState(() => _rowsPerPage = value);
      },
      showCheckboxColumn: false,
      showEmptyRows: false,
      columns: [
        for (var i = 0; i < table.headers.length; i++)
          DataColumn(
              label: SizedBox(
                  width: i == 0
                      ? 180
                      : table.headers.length > 4
                          ? 96
                          : 230,
                  child: Text(table.headers[i],
                      maxLines: 3, overflow: TextOverflow.ellipsis)))
      ],
      source: _source,
    ));
  }
}

class _TableSource extends DataTableSource {
  DiscuzDataTable table;
  final Widget Function(String value, int column, int index) cellBuilder;
  List<int> indexes;
  _TableSource(this.table, this.cellBuilder)
      : indexes = List.generate(table.rows.length, (index) => index);
  void update(DiscuzDataTable value, String query) {
    table = value;
    final term = query.trim().toLowerCase();
    indexes = [
      for (var index = 0; index < table.rows.length; index++)
        if (term.isEmpty ||
            table.rows[index].first.toLowerCase().contains(term))
          index
    ];
    notifyListeners();
  }

  @override
  DataRow? getRow(int index) {
    if (index >= indexes.length) return null;
    final original = indexes[index], row = table.rows[original];
    return DataRow.byIndex(index: index, cells: [
      for (var column = 0; column < table.headers.length; column++)
        DataCell(cellBuilder(
            column < row.length ? row[column] : '', column, original)),
    ]);
  }

  @override
  int get rowCount => indexes.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;
}

class _NativeTableValue extends StatelessWidget {
  final String value;
  const _NativeTableValue({required this.value});
  @override
  Widget build(BuildContext context) {
    if (value == '✔' || value == '✖') {
      final allowed = value == '✔', scheme = Theme.of(context).colorScheme;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(allowed ? Icons.check_circle_outline_rounded : Icons.block_rounded,
            size: 18, color: allowed ? scheme.primary : scheme.error),
        const SizedBox(width: 6),
        Text(allowed ? '允许' : '禁止',
            style: Theme.of(context).textTheme.labelMedium),
      ]);
    }
    return SelectableText(value.isEmpty ? '—' : value,
        maxLines: 3, style: Theme.of(context).textTheme.bodyMedium);
  }
}
