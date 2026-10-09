import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../core/klpbbs_developer_platform.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_motion.dart';
import '../widgets/responsive_layout.dart';
import 'login_page.dart';
import 'native_discuz_page.dart';
import 'thread_detail_page.dart';

/// Native reader for the current open-platform console and documentation.
/// Opening a tab only reads it; applying and other mutations are never implicit.
class DeveloperConsolePage extends StatefulWidget {
  final DeveloperPlatformView initialView;
  const DeveloperConsolePage(
      {super.key, this.initialView = DeveloperPlatformView.applications});
  @override
  State<DeveloperConsolePage> createState() => _DeveloperConsolePageState();
}

class _DeveloperConsolePageState extends State<DeveloperConsolePage> {
  final _search = TextEditingController();
  final _contentScroll = ScrollController();
  late DeveloperPlatformView _view;
  DeveloperPlatformReceipt? _receipt;
  bool _loading = true;
  String? _error, _sectionId;
  int _generation = 0, _accountGeneration = 0;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    DioClient.sessionChanges.addListener(_accountChanged);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    DioClient.sessionChanges.removeListener(_accountChanged);
    _search.dispose();
    _contentScroll.dispose();
    super.dispose();
  }

  void _accountChanged() {
    if (!mounted) return;
    _accountGeneration++;
    _search.clear();
    setState(() {
      _receipt = null;
      _sectionId = null;
      _error = null;
    });
    _load();
  }

  Future<void> _load({DeveloperPlatformView? view}) async {
    final generation = ++_generation, session = DioClient.sessionKey;
    setState(() {
      if (view != null && view != _view) {
        _view = view;
        _receipt = null;
        _sectionId = null;
        _search.clear();
      }
      _loading = true;
      _error = null;
    });
    final requestedView = _view;
    try {
      final receipt = await KlpbbsApi.getDeveloperPlatform(requestedView,
          expectedSession: session);
      if (!mounted ||
          generation != _generation ||
          session != DioClient.sessionKey) {
        return;
      }
      setState(() => _receipt = receipt);
    } catch (_) {
      if (mounted &&
          generation == _generation &&
          session == DioClient.sessionKey) {
        setState(() => _error =
            _receipt == null ? '暂时无法读取开放平台，请检查连接后重试。' : '刷新未完成，仍显示上次读取的内容。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectSection(String id) {
    setState(() => _sectionId = id);
    if (_contentScroll.hasClients) {
      _contentScroll.animateTo(0,
          duration: AppMotion.duration(context, 220),
          curve: AppMotion.emphasized);
    }
  }

  Future<void> _open(DeveloperPlatformLink link) async {
    final view = KlpbbsDeveloperPlatform.viewFor(link.uri);
    if (view != null) {
      await _load(view: view);
      return;
    }
    final thread = RegExp(r'^thread-(\d+)-\d+-\d+\.html$')
        .firstMatch(link.uri.path.split('/').last);
    if (thread != null) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ThreadDetailPage(tid: int.parse(thread[1]!))));
    }
  }

  Future<void> _login() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (mounted) await _load();
  }

  Widget _notice(String text, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      color: error ? scheme.errorContainer : scheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(error ? Icons.cloud_off_rounded : Icons.info_outline_rounded,
                  color: error
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                  child: SelectableText(text,
                      style: TextStyle(
                          color: error
                              ? scheme.onErrorContainer
                              : scheme.onSecondaryContainer))),
            ],
          )),
    );
  }

  Widget _console(KlpbbsDeveloperPlatform platform) {
    final scheme = Theme.of(context).colorScheme;
    final native = platform.nativePage;
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) _notice(_error!, error: true),
                    if (platform.message?.isNotEmpty == true)
                      _notice(platform.message!),
                    for (final notice in platform.notices) _notice(notice),
                    if (platform.requiresLogin)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                              onPressed: _login,
                              icon: const Icon(Icons.login_rounded),
                              label: const Text('登录后继续'))),
                    if (platform.emptyTitle != null)
                      Card.filled(
                        margin: EdgeInsets.zero,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 44),
                            child: Column(children: [
                              Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(24)),
                                  child: Icon(
                                      Icons.integration_instructions_outlined,
                                      size: 38,
                                      color: scheme.onPrimaryContainer)),
                              const SizedBox(height: 20),
                              Text(platform.emptyTitle!,
                                  textAlign: TextAlign.center,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              if (platform.emptyDescription?.isNotEmpty ==
                                  true) ...[
                                const SizedBox(height: 10),
                                ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 620),
                                    child: SelectableText(
                                        platform.emptyDescription!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: scheme.onSurfaceVariant,
                                            height: 1.6))),
                              ],
                              const SizedBox(height: 22),
                              Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    for (final link in platform.links)
                                      if (KlpbbsDeveloperPlatform.viewFor(
                                                  link.uri) !=
                                              _view &&
                                          KlpbbsDeveloperPlatform.viewFor(
                                                  link.uri) !=
                                              null)
                                        FilledButton.tonal(
                                            onPressed: () => _open(link),
                                            child: Text(link.label))
                                  ]),
                            ])),
                      ),
                    // A supplied application form remains the website's real declarative
                    // contract, including user-group-specific fields and constraints.
                    if (_view == DeveloperPlatformView.application &&
                        native.forms.isNotEmpty &&
                        !platform.requiresLogin) ...[
                      const SizedBox(height: 16),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                              key: const ValueKey('developer-application-form'),
                              onPressed: _loading
                                  ? null
                                  : () async {
                                      final receipt = _receipt!;
                                      await Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) => NativeDiscuzPage(
                                                  title: platform.title,
                                                  path: platform.uri.toString(),
                                                  initialData:
                                                      receipt.nativeReceipt)));
                                      if (mounted &&
                                          receipt.session ==
                                              DioClient.sessionKey) {
                                        await _load();
                                      }
                                    },
                              icon: const Icon(Icons.edit_note_rounded),
                              label: const Text('填写申请信息'))),
                    ],
                    for (final table in native.tables) ...[
                      const SizedBox(height: 16),
                      _DeveloperTable(
                          block: DeveloperDocumentBlock(
                              DeveloperBlockKind.table, table.title,
                              headers: table.headers, rows: table.rows),
                          sensitive: true),
                    ],
                    if (platform.emptyTitle == null &&
                        platform.notices.isEmpty &&
                        !platform.requiresLogin &&
                        native.forms.isEmpty &&
                        native.tables.isEmpty &&
                        platform.message == null)
                      _notice('当前页面未提供可读取的应用记录，请刷新后重试。'),
                    const SizedBox(height: 18),
                    Wrap(spacing: 10, runSpacing: 8, children: [
                      for (final link in platform.links)
                        if (KlpbbsDeveloperPlatform.viewFor(link.uri) == null)
                          TextButton.icon(
                              onPressed: () => _open(link),
                              icon: const Icon(Icons.description_outlined,
                                  size: 18),
                              label: Text(link.label))
                    ]),
                  ]),
            ))
          ],
        ));
  }

  Widget _documentation(KlpbbsDeveloperPlatform platform) {
    final scheme = Theme.of(context).colorScheme;
    final matches =
        platform.sections.where((s) => s.matches(_search.text)).toList();
    final section = matches.where((s) => s.id == _sectionId).firstOrNull ??
        matches.firstOrNull;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(children: [
          Expanded(
              child: TextField(
            key: const ValueKey('developer-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索接口、权限、参数或错误码',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      }),
              filled: true,
              fillColor: scheme.surfaceContainerLow,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none),
            ),
          )),
          if (MediaQuery.sizeOf(context).width >= 850) ...[
            const SizedBox(width: 20),
            Text('${matches.length} / ${platform.sections.length} 个章节',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ]
        ]),
      ),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _notice(_error!, error: true)),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final desktop = ResponsiveBreakpoints.isDesktop(context) &&
            constraints.maxWidth >= 900;
        final content = section == null
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        platform.sections.isEmpty
                            ? '当前页面未返回开发文档章节。'
                            : '没有找到匹配的章节，试试接口名称或错误码。',
                        textAlign: TextAlign.center)))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                    controller: _contentScroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(desktop ? 18 : 16, 8, 20, 32),
                    children: [
                      AnimatedSwitcher(
                        duration: AppMotion.duration(context, 220),
                        switchInCurve: AppMotion.emphasized,
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: _DeveloperSection(
                            key: ValueKey('developer-section-${section.id}'),
                            section: section),
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 10, children: [
                        for (final link in platform.links)
                          if (KlpbbsDeveloperPlatform.viewFor(link.uri) == null)
                            TextButton(
                                onPressed: () => _open(link),
                                child: Text(link.label))
                      ]),
                    ]));
        if (!desktop) {
          return Column(children: [
            if (matches.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 20, 8),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                        '${section?.id}:${matches.map((s) => s.id).join(',')}'),
                    initialValue: section?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: '文档目录', border: OutlineInputBorder()),
                    items: [
                      for (final item in matches)
                        DropdownMenuItem(
                            value: item.id,
                            child: Text(item.title,
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: (id) {
                      if (id != null) _selectSection(id);
                    },
                  )),
            Expanded(child: content),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              width: 250,
              child: Card.filled(
                  margin: const EdgeInsets.fromLTRB(20, 8, 0, 20),
                  child: ListView(padding: const EdgeInsets.all(10), children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                        child: Text('文档目录',
                            style: Theme.of(context).textTheme.titleMedium)),
                    for (final item in matches)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: ListTile(
                              key: ValueKey('developer-toc-${item.id}'),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              selected: section?.id == item.id,
                              selectedTileColor: scheme.secondaryContainer,
                              title: Text(item.title),
                              onTap: () => _selectSection(item.id))),
                  ]))),
          Expanded(child: content),
        ]);
      })),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final platform = _receipt?.platform;
    return Scaffold(
      appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('开放平台'),
          actions: [
            IconButton(
                key: const ValueKey('developer-refresh'),
                onPressed: _loading ? null : _load,
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded))
          ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SizedBox(
                width: 660,
                child: SegmentedButton<DeveloperPlatformView>(
                  key: const ValueKey('developer-tabs'),
                  segments: const [
                    ButtonSegment(
                        value: DeveloperPlatformView.applications,
                        label: Text('我的应用')),
                    ButtonSegment(
                        value: DeveloperPlatformView.application,
                        label: Text('申请接入')),
                    ButtonSegment(
                        value: DeveloperPlatformView.documentation,
                        label: Text('开发文档')),
                  ],
                  selected: {_view},
                  onSelectionChanged: (selection) =>
                      _load(view: selection.first),
                ))),
        if (_loading) const AppLoadingBar(),
        Expanded(
            child: AnimatedSwitcher(
          // Dispose outgoing account content immediately on session changes.
          key: ValueKey('developer-account-$_accountGeneration'),
          duration: AppMotion.duration(context, 220),
          child: platform == null
              ? (_loading
                  ? const Center(
                      key: ValueKey('loading'), child: AppLoadingIndicator())
                  : Center(
                      key: const ValueKey('error'),
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.cloud_off_rounded, size: 40),
                            const SizedBox(height: 16),
                            Text(_error ?? '暂时无法读取',
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                                onPressed: _load, child: const Text('重试'))
                          ]))))
              : KeyedSubtree(
                  key: ValueKey(_view),
                  child: _view == DeveloperPlatformView.documentation &&
                          !platform.requiresLogin
                      ? _documentation(platform)
                      : _console(platform)),
        )),
      ]),
    );
  }
}

class _DeveloperSection extends StatelessWidget {
  final DeveloperDocumentSection section;
  const _DeveloperSection({super.key, required this.section});
  @override
  Widget build(BuildContext context) => Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.only(bottom: 20, top: 10),
              child: Text(section.title,
                  style: Theme.of(context).textTheme.headlineSmall)),
          for (final block in section.blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: switch (block.kind) {
                DeveloperBlockKind.table => _DeveloperTable(block: block),
                DeveloperBlockKind.code => _DeveloperCode(text: block.text),
                DeveloperBlockKind.heading => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(block.text,
                        style: Theme.of(context).textTheme.titleLarge)),
                DeveloperBlockKind.notice => Card.filled(
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: SelectableText(block.text,
                            style: const TextStyle(height: 1.6)))),
                _ => SelectableText(block.text,
                    style: const TextStyle(fontSize: 15, height: 1.7)),
              },
            ),
        ]),
      ));
}

class _DeveloperCode extends StatelessWidget {
  final String text;
  const _DeveloperCode({required this.text});
  @override
  Widget build(BuildContext context) => Card.filled(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 12, 18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.code_rounded, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('示例')),
                    IconButton(
                        tooltip: '复制示例',
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('示例已复制')));
                          }
                        })
                  ]),
                  SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(text,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.6))),
                ])),
      );
}

class _DeveloperTable extends StatelessWidget {
  final DeveloperDocumentBlock block;
  final bool sensitive;
  const _DeveloperTable({required this.block, this.sensitive = false});
  String _cell(int column, String value) => sensitive &&
          column < block.headers.length &&
          RegExp(r'secret|token|密钥|令牌', caseSensitive: false)
              .hasMatch(block.headers[column]) &&
          value.isNotEmpty
      ? '••••••••'
      : value;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!ResponsiveBreakpoints.isDesktop(context) ||
        MediaQuery.sizeOf(context).width < 850) {
      return Column(children: [
        for (final row in block.rows)
          Card.filled(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < row.length; index++)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (index < block.headers.length &&
                                      block.headers[index].isNotEmpty)
                                    Text(block.headers[index],
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant)),
                                  const SizedBox(height: 4),
                                  SelectableText(_cell(index, row[index]),
                                      style: TextStyle(
                                          fontWeight: index == 0
                                              ? FontWeight.w600
                                              : FontWeight.normal)),
                                ])),
                    ])),
          )
      ]);
    }
    var columns = block.headers.length;
    for (final row in block.rows) {
      if (row.length > columns) columns = row.length;
    }
    if (columns == 0) return const SizedBox.shrink();
    return Card.filled(
        child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                WidgetStatePropertyAll(scheme.surfaceContainerHighest),
            dataRowMinHeight: 56,
            dataRowMaxHeight: double.infinity,
            columnSpacing: 24,
            horizontalMargin: 18,
            columns: [
              for (var column = 0; column < columns; column++)
                DataColumn(
                    label: Text(column < block.headers.length
                        ? block.headers[column]
                        : ''))
            ],
            rows: [
              for (final row in block.rows)
                DataRow(cells: [
                  for (var column = 0; column < columns; column++)
                    DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: SelectableText(
                                _cell(column,
                                    column < row.length ? row[column] : ''),
                                style: const TextStyle(height: 1.5))))),
                ])
            ],
          )),
    ));
  }
}
