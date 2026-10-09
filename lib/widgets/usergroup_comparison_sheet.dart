import 'app_motion.dart';
import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../models/usergroup_comparison.dart';

class UsergroupComparisonSheet extends StatefulWidget {
  const UsergroupComparisonSheet({super.key});
  @override
  State<UsergroupComparisonSheet> createState() =>
      _UsergroupComparisonSheetState();
}

class _UsergroupComparisonSheetState extends State<UsergroupComparisonSheet> {
  late Future<UsergroupComparison> _future;
  List<KlpbbsUserGroupMeta> _groups = const [];
  int? _gid;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = KlpbbsApi.getUsergroupComparison(gid: _gid);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
          child: Row(children: [
            const Expanded(
                child: Text('用户组权限',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
            if (_groups.isNotEmpty)
              PopupMenuButton<int>(
                tooltip: '选择对比用户组',
                icon: const Icon(Icons.compare_arrows),
                itemBuilder: (_) => [
                  for (final group in _groups)
                    PopupMenuItem(
                        value: group.gid,
                        child: Text('${group.category} · ${group.name}'))
                ],
                onSelected: (gid) => setState(() {
                  _gid = gid;
                  _load();
                }),
              ),
            IconButton(
                tooltip: '刷新',
                onPressed: () => setState(_load),
                icon: const Icon(Icons.refresh)),
            IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close)),
          ]),
        ),
        Expanded(
            child: FutureBuilder<UsergroupComparison>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: AppLoadingIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                  child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_outlined, size: 40),
                  const SizedBox(height: 12),
                  const Text('无法获取用户组权限，请检查登录状态后重试',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                      onPressed: () => setState(_load),
                      child: const Text('重试')),
                ]),
              ));
            }
            final data = snapshot.data!;
            if (_groups.isEmpty && data.groups.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _groups = data.groups);
              });
            }
            return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: _column(data.myGroup, scheme.primaryContainer,
                            scheme.onPrimaryContainer)),
                    if (data.upgradeGroup != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                          child: _column(
                              data.upgradeGroup!,
                              scheme.secondaryContainer,
                              scheme.onSecondaryContainer)),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  for (final permission in data.permissions)
                    if (permission.isCategoryHeader)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(permission.title,
                              style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600)))
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        decoration: BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color:
                                        scheme.outlineVariant.withAlpha(90)))),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  flex: 4,
                                  child: Text(permission.title,
                                      style: const TextStyle(fontSize: 13))),
                              const SizedBox(width: 8),
                              Expanded(
                                  flex: 3,
                                  child: _value(permission.myValue, scheme)),
                              if (data.upgradeGroup != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                    flex: 3,
                                    child: _value(permission.nextValue, scheme))
                              ],
                            ]),
                      ),
                ]);
          },
        )),
      ]),
    );
  }

  Widget _column(UsergroupColumn column, Color background, Color foreground) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(column.title,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
          if (column.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(column.subtitle,
                style: TextStyle(color: foreground, fontSize: 12))
          ],
        ]),
      );
  Widget _value(String value, ColorScheme scheme) {
    if (value == '✔' || value == '✖') {
      return Icon(value == '✔' ? Icons.check_circle_outline : Icons.block,
          size: 20, color: value == '✔' ? scheme.primary : scheme.error);
    }
    return Text(value.isEmpty ? '—' : value,
        textAlign: TextAlign.center, style: const TextStyle(fontSize: 13));
  }
}
