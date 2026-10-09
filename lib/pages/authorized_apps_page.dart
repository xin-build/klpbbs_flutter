import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../core/klpbbs_authorizations.dart';
import '../core/klpbbs_developer_platform.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_motion.dart';
import '../widgets/empty_view.dart';
import 'developer_console_page.dart';
import 'login_page.dart';
import 'native_discuz_page.dart';

/// No authorization or revoke is triggered by opening or refreshing this page.
/// Private content stays in memory and is cleared on account changes.
class AuthorizedAppsPage extends StatefulWidget {
  const AuthorizedAppsPage({super.key});
  @override
  State<AuthorizedAppsPage> createState() => _AuthorizedAppsPageState();
}

class _AuthorizedAppsPageState extends State<AuthorizedAppsPage> {
  AuthorizationsReceipt? _receipt;
  String? _error;
  bool _loading = true, _busy = false;
  int _generation = 0, _accountGeneration = 0;

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_accountChanged);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    DioClient.sessionChanges.removeListener(_accountChanged);
    super.dispose();
  }

  void _accountChanged() {
    if (!mounted) return;
    _accountGeneration++;
    setState(() {
      _receipt = null;
      _error = null;
      _busy = false;
    });
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation, session = DioClient.sessionKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final receipt =
          await KlpbbsApi.getAuthorizations(expectedSession: session);
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
            _receipt == null ? '暂时无法读取授权数据，请检查连接后重试。' : '刷新未完成，仍显示上次读取的授权信息。');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _login() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (mounted) await _load();
  }

  Future<void> _action(
      AuthorizationsReceipt receipt, AuthorizationAction action) async {
    if (_busy || _loading) return;
    final session = receipt.session, generation = _accountGeneration;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(action.label),
              content: Text(action.confirmation),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    key: const ValueKey('authorization-confirm'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('确认')),
              ],
            ));
    if (confirmed != true ||
        !mounted ||
        generation != _accountGeneration ||
        session != DioClient.sessionKey) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result =
          await KlpbbsApi.performAuthorizationAction(receipt, action);
      if (!mounted ||
          generation != _accountGeneration ||
          session != DioClient.sessionKey) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      if (result.success) await _load();
    } finally {
      if (mounted && generation == _accountGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _notice(String text, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
        color: error ? scheme.errorContainer : scheme.surfaceContainerHigh,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(error ? Icons.cloud_off_rounded : Icons.info_outline_rounded,
                  color: error ? scheme.onErrorContainer : scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                  child: Text(text,
                      style: TextStyle(
                          height: 1.6,
                          color: error
                              ? scheme.onErrorContainer
                              : scheme.onSurfaceVariant))),
            ])));
  }

  List<Widget> _content(AuthorizationsReceipt receipt, double width) {
    final page = receipt.page, scheme = Theme.of(context).colorScheme;
    if (page.requiresLogin) {
      return [
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: EmptyView(
                key: const ValueKey('authorizations-login'),
                icon: Icons.account_circle_outlined,
                title: '登录后查看授权应用',
                subtitle: '只展示当前账号在论坛授权过的应用。',
                action:
                    FilledButton(onPressed: _login, child: const Text('登录'))))
      ];
    }
    final records = <Widget>[];
    for (final table in page.nativePage.tables) {
      for (final row in table.rows) {
        records.add(Card.filled(
            key: ValueKey('authorization-record-${records.length}'),
            margin: EdgeInsets.zero,
            child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (table.title.isNotEmpty) ...[
                        Text(table.title,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                      ],
                      for (var i = 0; i < row.length; i++)
                        if (row[i].isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (i < table.headers.length &&
                                        table.headers[i].isNotEmpty) ...[
                                      Text(table.headers[i],
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant)),
                                      const SizedBox(height: 4),
                                    ],
                                    SelectableText(row[i],
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge),
                                  ])),
                    ]))));
      }
    }
    final twoColumns =
        width >= 860 && MediaQuery.textScalerOf(context).scale(16) <= 22.4;
    return [
      for (final text in page.notices) _notice(text),
      if (page.developerLinks.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              for (final link in page.developerLinks)
                OutlinedButton.icon(
                    key: ValueKey(
                        'authorizations-developer-${KlpbbsDeveloperPlatform.viewFor(link.uri)?.name}'),
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => DeveloperConsolePage(
                                initialView: KlpbbsDeveloperPlatform.viewFor(
                                    link.uri)!))),
                    icon: Icon(KlpbbsDeveloperPlatform.viewFor(link.uri) ==
                            DeveloperPlatformView.documentation
                        ? Icons.menu_book_rounded
                        : Icons.code_rounded),
                    label: Text(link.label)),
            ])),
      if (page.message != null) _notice(page.message!, error: !page.recognized),
      if (page.isExplicitlyEmpty)
        Card.filled(
            key: const ValueKey('authorizations-empty'),
            margin: EdgeInsets.zero,
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: EmptyView(
                    icon: Icons.lock_outline_rounded,
                    title: page.emptyTitle!,
                    subtitle: page.emptyDescription))),
      if (records.isNotEmpty)
        Wrap(spacing: 16, runSpacing: 16, children: [
          for (final record in records)
            SizedBox(
                width: twoColumns ? (width - 16) / 2 : width,
                child: AppFadeIn(child: record)),
        ]),
      for (final detail in page.details)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SelectableText(detail)),
      if (page.unresolvedLinks.isNotEmpty) ...[
        _notice('网站返回了其他授权内容，当前操作方式尚待适配。'),
        for (final link in page.unresolvedLinks)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(link.label)),
      ],
      if (page.actions.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              for (var i = 0; i < page.actions.length; i++)
                OutlinedButton.icon(
                    key: ValueKey('authorization-action-$i'),
                    onPressed: _busy || _loading
                        ? null
                        : () => _action(receipt, page.actions[i]),
                    icon: const Icon(Icons.link_off_rounded),
                    label: Text(page.actions[i].label)),
            ])),
      if (page.nativePage.forms.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 20),
            child: OutlinedButton.icon(
                key: const ValueKey('authorizations-declared-forms'),
                onPressed: _busy
                    ? null
                    : () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => NativeDiscuzPage(
                                title: '授权操作',
                                path: receipt.page.uri.toString(),
                                initialData: receipt.nativeReceipt)));
                        if (mounted) await _load();
                      },
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('查看授权操作'))),
      if (page.recognized &&
          !page.isExplicitlyEmpty &&
          records.isEmpty &&
          page.details.isEmpty &&
          page.actions.isEmpty &&
          page.nativePage.forms.isEmpty)
        _notice('网站已返回授权页面，但当前内容尚无法确认。请刷新后重试。'),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            leading: const AppBackButton(),
            title: const Text('我的授权'),
            actions: [
              IconButton(
                  key: const ValueKey('authorizations-refresh'),
                  tooltip: '刷新',
                  onPressed: _busy || _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded)),
              const SizedBox(width: 8),
            ]),
        body: Column(children: [
          if (_loading || _busy) const AppLoadingBar(minHeight: 2),
          Expanded(
              child: RefreshIndicator(
                  onRefresh: _busy ? () async {} : _load,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final margin = constraints.maxWidth >= 768 ? 32.0 : 16.0;
                      final width = (constraints.maxWidth - margin * 2)
                          .clamp(0.0, 1120.0);
                      return ListView(
                          key: const ValueKey('authorizations-content'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.symmetric(
                              horizontal: margin, vertical: 24),
                          children: [
                            Center(
                                child: SizedBox(
                                    width: width,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (_error != null) ...[
                                            _notice(_error!, error: true),
                                            Align(
                                                alignment: Alignment.centerLeft,
                                                child: TextButton.icon(
                                                    key: const ValueKey(
                                                        'authorizations-retry'),
                                                    onPressed:
                                                        _loading ? null : _load,
                                                    icon: const Icon(
                                                        Icons.refresh_rounded),
                                                    label: const Text('重试'))),
                                            const SizedBox(height: 12),
                                          ],
                                          if (_receipt != null)
                                            ..._content(_receipt!, width),
                                          if (_receipt == null && _loading)
                                            const Padding(
                                                padding: EdgeInsets.symmetric(
                                                    vertical: 72),
                                                child: Center(
                                                    child:
                                                        AppLoadingIndicator())),
                                        ]))),
                          ]);
                    },
                  ))),
        ]),
      );
}
