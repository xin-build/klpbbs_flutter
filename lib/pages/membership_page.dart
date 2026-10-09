import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../core/klpbbs_membership.dart';
import '../widgets/app_motion.dart';
import '../widgets/usergroup_comparison_sheet.dart';
import 'func_list_page.dart';
import 'login_page.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});
  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  MembershipCenterReceipt? _receipt;
  bool _loading = true;
  String? _error;
  int _generation = 0;
  int? _openingGroup;
  String _filter = 'all';

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
    _generation++;
    setState(() {
      _receipt = null;
      _error = null;
      _openingGroup = null;
      _filter = 'all';
    });
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation, session = DioClient.sessionKey;
    setState(() {
      _loading = DioClient.isLoggedIn;
      _error = null;
    });
    if (!DioClient.isLoggedIn) return;
    try {
      final receipt = await KlpbbsApi.getMembershipCenter(
          forceRefresh: true, expectedSession: session);
      if (!mounted ||
          generation != _generation ||
          session != DioClient.sessionKey) {
        return;
      }
      setState(() => _receipt = receipt);
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          session == DioClient.sessionKey) {
        setState(() => _error = _errorText(error));
      }
    } finally {
      if (mounted &&
          generation == _generation &&
          session == DioClient.sessionKey) {
        setState(() => _loading = false);
      }
    }
  }

  static String _errorText(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(Bad state:|Exception:)\s*'), '');

  Future<void> _openPermissions({MembershipPlan? plan}) async {
    if (plan?.permissionsUrl != null) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FuncListPage(
              title: '${plan!.title} 权限', path: plan.permissionsUrl!)));
      return;
    }
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SizedBox(
            height: MediaQuery.sizeOf(context).height * .88,
            child: const UsergroupComparisonSheet()));
  }

  Future<void> _openOperation(
      MembershipPlan plan, MembershipOperation operation) async {
    final receipt = _receipt;
    if (receipt == null || _openingGroup != null || _loading) return;
    final generation = _generation, session = receipt.session;
    setState(() => _openingGroup = plan.groupId);
    try {
      final action =
          await KlpbbsApi.getMembershipAction(receipt, plan.groupId, operation);
      if (!mounted ||
          generation != _generation ||
          session != DioClient.sessionKey) {
        return;
      }
      if (MediaQuery.sizeOf(context).width >= 720) {
        await showDialog<void>(
            context: context,
            builder: (_) => Dialog(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _MembershipConfirmation(initial: action))));
      } else {
        await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _MembershipConfirmation(initial: action));
      }
      if (mounted && session == DioClient.sessionKey) await _load();
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          session == DioClient.sessionKey) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorText(error))));
        await _load();
      }
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _openingGroup = null);
      }
    }
  }

  Widget _summary(MembershipCenter center) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Card.filled(
        margin: EdgeInsets.zero,
        color: colors.primaryContainer,
        child: Padding(
            padding: const EdgeInsets.all(24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.workspace_premium_rounded,
                    size: 40, color: colors.onPrimaryContainer),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('当前用户组',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: colors.onPrimaryContainer)),
                      const SizedBox(height: 4),
                      Text(
                          center.currentGroup.isEmpty
                              ? '网站暂未提供用户组名称'
                              : center.currentGroup,
                          key: const ValueKey('membership-current-group'),
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(color: colors.onPrimaryContainer)),
                    ])),
              ]),
              const SizedBox(height: 20),
              Wrap(spacing: 24, runSpacing: 14, children: [
                if (center.balanceText.isNotEmpty)
                  _summaryValue(
                      '可用余额', center.balanceText, colors.onPrimaryContainer),
                _summaryValue(
                    '列表中已持有',
                    '${center.plans.where((p) => p.isOwned).length}',
                    colors.onPrimaryContainer),
                _summaryValue(
                    '可加入用户组',
                    '${center.plans.where((p) => p.buyUrl != null && !p.isOwned).length}',
                    colors.onPrimaryContainer),
              ]),
            ])));
  }

  Widget _summaryValue(String label, String value, Color color) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: theme.textTheme.labelMedium?.copyWith(color: color)),
      const SizedBox(height: 3),
      Text(value, style: theme.textTheme.titleMedium?.copyWith(color: color)),
    ]);
  }

  Widget _planCard(MembershipPlan plan, int index) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final busy = _openingGroup == plan.groupId;
    final enabled = !_loading && _openingGroup == null;
    final status = plan.isExpired
        ? '已过期'
        : plan.isCurrent
            ? '主用户组'
            : plan.isOwned
                ? '已持有'
                : null;
    return AppFadeIn(
        key: ValueKey('membership-plan-${plan.groupId}'),
        index: index,
        child: Card.outlined(
            margin: EdgeInsets.zero,
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: colors.secondaryContainer,
                                borderRadius: BorderRadius.circular(18)),
                            child: Icon(Icons.stars_rounded,
                                color: colors.onSecondaryContainer)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(plan.title,
                                style: theme.textTheme.headlineSmall)),
                        if (status != null)
                          Chip(
                              label: Text(status),
                              visualDensity: VisualDensity.compact),
                      ]),
                      if (plan.priceText.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                            plan.dailyPrice == null
                                ? plan.priceText
                                : plan.dailyPrice == 0
                                    ? '免费'
                                    : '${_formatAmount(plan.dailyPrice!)} ${plan.priceUnit}',
                            key: ValueKey('membership-price-${plan.groupId}'),
                            style: theme.textTheme.headlineMedium
                                ?.copyWith(color: colors.primary)),
                        if (plan.dailyPrice != null && plan.dailyPrice! > 0)
                          Text('每天',
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                      if (plan.expiryText.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _detail(
                            Icons.schedule_rounded, '到期时间', plan.expiryText),
                      ],
                      if (plan.affordableDays != null) ...[
                        const SizedBox(height: 12),
                        _detail(Icons.account_balance_wallet_outlined,
                            '当前余额可购买', '${plan.affordableDays} 天'),
                      ],
                      const SizedBox(height: 24),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (plan.buyUrl != null)
                          FilledButton.icon(
                              key: ValueKey('membership-buy-${plan.groupId}'),
                              onPressed: enabled
                                  ? () => _openOperation(
                                      plan, MembershipOperation.buy)
                                  : null,
                              icon: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child:
                                          AppLoadingIndicator(strokeWidth: 2))
                                  : const Icon(Icons.shopping_bag_outlined),
                              label: Text(plan.buyLabel.isEmpty
                                  ? '查看报价'
                                  : plan.buyLabel)),
                        if (plan.permissionsUrl != null)
                          OutlinedButton.icon(
                              onPressed: () => _openPermissions(plan: plan),
                              icon: const Icon(Icons.rule_rounded),
                              label: const Text('组权限')),
                        if (plan.switchUrl != null)
                          FilledButton.tonalIcon(
                              key:
                                  ValueKey('membership-switch-${plan.groupId}'),
                              onPressed: enabled
                                  ? () => _openOperation(
                                      plan, MembershipOperation.switchGroup)
                                  : null,
                              icon: const Icon(Icons.swap_horiz_rounded),
                              label: const Text('设为主用户组')),
                        if (plan.exitUrl != null)
                          TextButton.icon(
                              key: ValueKey('membership-exit-${plan.groupId}'),
                              onPressed: enabled
                                  ? () => _openOperation(
                                      plan, MembershipOperation.exit)
                                  : null,
                              icon: const Icon(Icons.logout_rounded),
                              label: const Text('退出该组')),
                      ]),
                    ]))));
  }

  Widget _detail(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(
          child: Text('$label  $value', style: theme.textTheme.bodyMedium)),
    ]);
  }

  Widget _notice(String message, {bool error = false}) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
        key: error ? const ValueKey('membership-error') : null,
        color: error ? colors.errorContainer : colors.surfaceContainerHighest,
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Icon(error ? Icons.wifi_off_rounded : Icons.info_outline_rounded,
                  color: error
                      ? colors.onErrorContainer
                      : colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(message,
                      style: TextStyle(
                          color: error
                              ? colors.onErrorContainer
                              : colors.onSurfaceVariant))),
              if (error)
                TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('重试')),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), center = _receipt?.center;
    final plans = center?.plans
            .where((p) => _filter == 'owned'
                ? p.isOwned
                : _filter == 'available'
                    ? p.buyUrl != null
                    : true)
            .toList() ??
        const <MembershipPlan>[];
    return Scaffold(
        appBar: AppBar(title: const Text('用户组与会员'), actions: [
          IconButton(
              onPressed: _openPermissions,
              tooltip: '对比用户组权限',
              icon: const Icon(Icons.rule_outlined)),
          IconButton(
              onPressed: _loading ? null : _load,
              tooltip: '同步会员状态',
              icon: const Icon(Icons.refresh_rounded)),
        ]),
        body: RefreshIndicator(
            onRefresh: _load,
            child: LayoutBuilder(
                builder: (context, constraints) => ListView(
                        padding: EdgeInsets.symmetric(
                            horizontal: constraints.maxWidth >= 720 ? 32 : 16,
                            vertical: 20),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Center(
                              child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 1180),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (!DioClient.isLoggedIn)
                                          Card.filled(
                                              child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(28),
                                                  child: Column(children: [
                                                    const Icon(
                                                        Icons
                                                            .account_circle_outlined,
                                                        size: 48),
                                                    const SizedBox(height: 16),
                                                    Text('登录后查看会员报价与持有用户组',
                                                        style: theme.textTheme
                                                            .titleLarge),
                                                    const SizedBox(height: 20),
                                                    FilledButton(
                                                        onPressed: () async {
                                                          await Navigator.of(
                                                                  context)
                                                              .push(MaterialPageRoute(
                                                                  builder: (_) =>
                                                                      const LoginPage()));
                                                          if (mounted) {
                                                            await _load();
                                                          }
                                                        },
                                                        child:
                                                            const Text('登录论坛')),
                                                  ]))),
                                        if (_loading)
                                          const Padding(
                                              padding:
                                                  EdgeInsets.only(bottom: 16),
                                              child: AppLoadingBar()),
                                        if (_error != null) ...[
                                          _notice(
                                              center == null
                                                  ? _error!
                                                  : '刷新未完成，以下为上次读取的会员状态。\n$_error',
                                              error: true),
                                          const SizedBox(height: 16),
                                        ],
                                        if (center != null) ...[
                                          _summary(center),
                                          const SizedBox(height: 24),
                                          LayoutBuilder(
                                              builder:
                                                  (context, content) => Wrap(
                                                          alignment:
                                                              WrapAlignment
                                                                  .spaceBetween,
                                                          crossAxisAlignment:
                                                              WrapCrossAlignment
                                                                  .center,
                                                          spacing: 12,
                                                          runSpacing: 12,
                                                          children: [
                                                            if (content.maxWidth <
                                                                    520 ||
                                                                MediaQuery.textScalerOf(
                                                                            context)
                                                                        .scale(
                                                                            1) >
                                                                    1.4)
                                                              Wrap(
                                                                  key: const ValueKey(
                                                                      'membership-filter'),
                                                                  spacing: 8,
                                                                  runSpacing: 8,
                                                                  children: [
                                                                    for (final option
                                                                        in const {
                                                                      'all':
                                                                          '全部用户组',
                                                                      'owned':
                                                                          '已持有',
                                                                      'available':
                                                                          '可加入'
                                                                    }.entries)
                                                                      ChoiceChip(
                                                                          label: Text(option
                                                                              .value),
                                                                          selected: _filter ==
                                                                              option
                                                                                  .key,
                                                                          onSelected: (_) =>
                                                                              setState(() => _filter = option.key)),
                                                                  ])
                                                            else
                                                              SegmentedButton<
                                                                      String>(
                                                                  key: const ValueKey(
                                                                      'membership-filter'),
                                                                  segments: const [
                                                                    ButtonSegment(
                                                                        value:
                                                                            'all',
                                                                        label: Text(
                                                                            '全部用户组')),
                                                                    ButtonSegment(
                                                                        value:
                                                                            'owned',
                                                                        label: Text(
                                                                            '已持有')),
                                                                    ButtonSegment(
                                                                        value:
                                                                            'available',
                                                                        label: Text(
                                                                            '可加入')),
                                                                  ],
                                                                  selected: {
                                                                    _filter
                                                                  },
                                                                  showSelectedIcon:
                                                                      false,
                                                                  onSelectionChanged:
                                                                      (value) =>
                                                                          setState(() =>
                                                                              _filter = value.first)),
                                                            OutlinedButton.icon(
                                                                onPressed: () => Navigator.of(
                                                                        context)
                                                                    .push(MaterialPageRoute(
                                                                        builder: (_) => const FuncListPage(
                                                                            title:
                                                                                '板块权限',
                                                                            path:
                                                                                'home.php?mod=spacecp&ac=usergroup&do=forum&mobile=no'))),
                                                                icon: const Icon(
                                                                    Icons
                                                                        .grid_view_outlined),
                                                                label:
                                                                    const Text(
                                                                        '板块权限')),
                                                          ])),
                                          const SizedBox(height: 20),
                                          if (plans.isEmpty)
                                            _notice(_filter == 'owned'
                                                ? '网站当前没有列出已持有的用户组。'
                                                : _filter == 'available'
                                                    ? '当前账号没有可加入的用户组。'
                                                    : '网站当前没有提供可加入或持有的用户组。'),
                                          LayoutBuilder(
                                              builder: (context, content) {
                                            final width = content.maxWidth >=
                                                    850
                                                ? (content.maxWidth - 20) / 2
                                                : content.maxWidth;
                                            return Wrap(
                                                spacing: 20,
                                                runSpacing: 20,
                                                children: [
                                                  for (var i = 0;
                                                      i < plans.length;
                                                      i++)
                                                    SizedBox(
                                                        width: width,
                                                        child: _planCard(
                                                            plans[i], i)),
                                                ]);
                                          }),
                                        ],
                                      ]))),
                        ]))));
  }
}

String _formatAmount(double amount) => amount == amount.truncateToDouble()
    ? amount.toInt().toString()
    : amount.toString();

class _MembershipConfirmation extends StatefulWidget {
  final MembershipActionReceipt initial;
  const _MembershipConfirmation({required this.initial});
  @override
  State<_MembershipConfirmation> createState() =>
      _MembershipConfirmationState();
}

class _MembershipConfirmationState extends State<_MembershipConfirmation> {
  late MembershipActionReceipt _receipt = widget.initial;
  late final TextEditingController _days = TextEditingController(
      text: _receipt.contract.minimumDays?.toString() ?? '');
  bool _busy = false, _changed = false, _needsRefresh = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_accountChanged);
  }

  @override
  void dispose() {
    _generation++;
    DioClient.sessionChanges.removeListener(_accountChanged);
    _days.dispose();
    super.dispose();
  }

  void _accountChanged() {
    if (!mounted) return;
    _generation++;
    _days.clear();
    setState(() {
      _changed = true;
      _busy = false;
      _error = '账号已切换，请关闭后重新打开会员操作';
    });
  }

  Future<void> _reload() async {
    final generation = ++_generation, session = _receipt.session;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final center = await KlpbbsApi.getMembershipCenter(
          forceRefresh: true, expectedSession: session);
      final receipt = await KlpbbsApi.getMembershipAction(
          center, _receipt.plan.groupId, _receipt.contract.operation);
      if (!mounted ||
          generation != _generation ||
          session != DioClient.sessionKey) {
        return;
      }
      final oldDays = int.tryParse(_days.text),
          minimum = receipt.contract.minimumDays;
      setState(() {
        _receipt = receipt;
        _needsRefresh = false;
        if (receipt.contract.requiresDays) {
          _days.text =
              oldDays != null && receipt.contract.validateDays(oldDays) == null
                  ? '$oldDays'
                  : '${minimum ?? ''}';
        }
      });
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          session == DioClient.sessionKey) {
        setState(() => _error = _MembershipPageState._errorText(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _changed || _needsRefresh) return;
    final receipt = _receipt, generation = _generation;
    final days =
        receipt.contract.requiresDays ? int.tryParse(_days.text) : null;
    final invalid = receipt.contract.validateDays(days);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await KlpbbsApi.submitMembershipAction(receipt, days: days);
      if (!mounted ||
          generation != _generation ||
          receipt.session != DioClient.sessionKey) {
        return;
      }
      if (result.success) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
        Navigator.of(context).pop();
      } else {
        setState(() {
          _error = result.message;
          _needsRefresh = result.needsRefresh;
        });
      }
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          receipt.session == DioClient.sessionKey) {
        setState(() {
          _error = _MembershipPageState._errorText(error);
          _needsRefresh = true;
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    if (_changed) {
      return SingleChildScrollView(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('账号已切换'),
                    const SizedBox(height: 16),
                    Text(_error!),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('关闭')),
                  ])));
    }
    final contract = _receipt.contract;
    final parsedDays = contract.requiresDays ? int.tryParse(_days.text) : null;
    final invalid = contract.validateDays(parsedDays);
    final total = contract.totalPrice(parsedDays);
    final operation = contract.operation;
    final verb = operation == MembershipOperation.buy
        ? (_receipt.plan.isOwned
            ? '续费'
            : contract.dailyPrice == 0
                ? '加入'
                : '购买')
        : operation == MembershipOperation.switchGroup
            ? '切换主用户组'
            : '退出用户组';
    return ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
        child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
            child: SafeArea(
                top: false,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('$verb ${_receipt.plan.title}',
                                key: const ValueKey('membership-confirmation'),
                                style: theme.textTheme.headlineSmall)),
                        IconButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).pop(),
                            tooltip: '关闭',
                            icon: const Icon(Icons.close_rounded)),
                      ]),
                      if (_receipt
                          .centerReceipt.center.currentGroup.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                            '当前用户组：${_receipt.centerReceipt.center.currentGroup}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                      const SizedBox(height: 24),
                      if (operation == MembershipOperation.buy)
                        Card.filled(
                            margin: EdgeInsets.zero,
                            child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('当前报价',
                                          style: theme.textTheme.labelLarge),
                                      const SizedBox(height: 6),
                                      Text(
                                          contract.dailyPrice == null
                                              ? '网站尚未提供可确认的价格'
                                              : contract.dailyPrice == 0
                                                  ? '免费'
                                                  : '${_formatAmount(contract.dailyPrice!)} ${contract.priceUnit} / 天',
                                          style: theme.textTheme.titleLarge),
                                      if (contract.minimumDays != null)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Text(
                                                '最低购买 ${contract.minimumDays} 天')),
                                      if (contract.maximumDays != null)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 6),
                                            child: Text(
                                                '当前最多可购买 ${contract.maximumDays} 天')),
                                    ]))),
                      if (contract.requiresDays) ...[
                        const SizedBox(height: 24),
                        TextField(
                            key: const ValueKey('membership-days'),
                            controller: _days,
                            enabled: !_busy && !_needsRefresh,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            onChanged: (_) => setState(() => _error = null),
                            decoration: InputDecoration(
                                labelText: '购买期限',
                                suffixText: '天',
                                border: const OutlineInputBorder(),
                                helperText:
                                    '最低 ${contract.minimumDays ?? '待确认'} 天',
                                errorText:
                                    _days.text.isNotEmpty ? invalid : null)),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final count in {
                            if (contract.minimumDays != null)
                              contract.minimumDays!,
                            30,
                            90,
                            365
                          }.where(
                              (value) => contract.validateDays(value) == null))
                            ChoiceChip(
                                label: Text('$count 天'),
                                selected: parsedDays == count,
                                onSelected: _busy || _needsRefresh
                                    ? null
                                    : (_) => setState(() {
                                          _days.text = '$count';
                                          _error = null;
                                        })),
                        ]),
                      ],
                      if (total != null &&
                          operation == MembershipOperation.buy) ...[
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(
                              child: Text('本次合计',
                                  style: theme.textTheme.titleMedium)),
                          Flexible(
                              child: Text(
                                  total == 0
                                      ? '免费'
                                      : '${_formatAmount(total)} ${contract.priceUnit}',
                                  key: const ValueKey('membership-total'),
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(color: colors.primary))),
                        ]),
                      ],
                      if (contract.explanations.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        for (final explanation in contract.explanations)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(explanation,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.onSurfaceVariant))),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!,
                            key: const ValueKey('membership-operation-error'),
                            style: TextStyle(color: colors.error)),
                      ],
                      const SizedBox(height: 24),
                      if (_busy)
                        const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: AppLoadingBar()),
                      if (_needsRefresh || !contract.canSubmit)
                        FilledButton.tonalIcon(
                            key: const ValueKey('membership-reload-quote'),
                            onPressed: _busy ? null : _reload,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重新读取报价')),
                      FilledButton.icon(
                          key: const ValueKey('membership-confirm-submit'),
                          onPressed: _busy || _needsRefresh || invalid != null
                              ? null
                              : _submit,
                          icon: Icon(operation == MembershipOperation.exit
                              ? Icons.logout_rounded
                              : Icons.check_rounded),
                          label: Text(_busy ? '正在核对并提交' : '确认$verb')),
                    ]))));
  }
}
