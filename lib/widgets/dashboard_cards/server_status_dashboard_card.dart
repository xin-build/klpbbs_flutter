import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/klpbbs_api.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/server_status_model.dart';
import 'dashboard_card_frame.dart';

/// 19. 服务器状态监控卡片（深度适配 status.klpz.net，支持 GPU 隔离与多阶 LOD 自适应）
class ServerStatusDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const ServerStatusDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  static ServerStatusData get fixedMockData => _ServerStatusDashboardCardState.fixedMockData;

  @override
  State<ServerStatusDashboardCard> createState() => _ServerStatusDashboardCardState();
}

class _ServerStatusDashboardCardState extends State<ServerStatusDashboardCard> {
  ServerStatusData? _data;
  bool _loading = false;

  // 专属高保真固定演示数据（严格对齐 status.klpz.net 真实节点）
  static ServerStatusData get _fixedMockData => fixedMockData;
  static final ServerStatusData fixedMockData = ServerStatusData(
    siteName: '服务状态面板',
    overallRaw: 'operational',
    groups: const [
      ServerStatusGroup(id: 1, name: '核心服务'),
      ServerStatusGroup(id: 2, name: '存储服务'),
      ServerStatusGroup(id: 3, name: '其他业务'),
      ServerStatusGroup(id: 4, name: '边缘节点'),
    ],
    services: const [
      ServerStatusService(id: 1, groupId: 1, name: '主站服务', currentStatusRaw: 'operational', lastLatencyMs: 232),
      ServerStatusService(id: 2, groupId: 1, name: '用户中心', currentStatusRaw: 'operational', lastLatencyMs: 1242),
      ServerStatusService(id: 3, groupId: 2, name: '广东存储', currentStatusRaw: 'operational', lastLatencyMs: 79),
      ServerStatusService(id: 4, groupId: 2, name: '附件存储', currentStatusRaw: 'operational', lastLatencyMs: 161),
      ServerStatusService(id: 5, groupId: 2, name: '宁波存储', currentStatusRaw: 'operational', lastLatencyMs: 288),
      ServerStatusService(id: 6, groupId: 3, name: '下载站', currentStatusRaw: 'operational', lastLatencyMs: 455),
      ServerStatusService(id: 7, groupId: 3, name: '博客', currentStatusRaw: 'operational', lastLatencyMs: 641),
      ServerStatusService(id: 15, groupId: 3, name: 'KlpWiki', currentStatusRaw: 'operational', lastLatencyMs: 2780),
      ServerStatusService(id: 17, groupId: 4, name: '103.*.*.186', currentStatusRaw: 'operational', lastLatencyMs: 54),
      ServerStatusService(id: 18, groupId: 4, name: '38.*.*.93', currentStatusRaw: 'operational', lastLatencyMs: 50),
    ],
    incidents: const [
      ServerStatusIncident(
        id: 1279,
        serviceId: 15,
        serviceName: 'KlpWiki',
        title: 'KlpWiki 出现故障',
        status: 'resolved',
        message: '系统检测到服务已完全恢复。',
        startedAt: '2026-09-19 15:11',
        resolvedAt: '2026-09-19 17:18',
      ),
    ],
    updatedAt: DateTime.now(),
  );

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isPreview) {
      _data = _fixedMockData;
    } else {
      _loadStatus();
      _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) {
        if (mounted && !widget.isPreview) {
          _loadStatus(force: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus({bool force = false}) async {
    if (_loading) return;
    if (_data == null && mounted) {
      setState(() => _loading = true);
    }
    try {
      final res = await KlpbbsApi.getServerStatus(forceRefresh: force);
      if (mounted) {
        setState(() {
          _data = res;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _openDetails() {
    HapticFeedback.lightImpact();
    ServerStatusDetailDialog.show(context, initialData: _data);
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = widget.item.colSpan <= 2;
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title = (customTitle != null && customTitle.isNotEmpty) ? customTitle : '服务器状态';

    final data = _data ?? _fixedMockData;
    final overall = data.overallStatus;

    final rawDataStyle = widget.item.customParams['dataStyle'] as String? ?? 'auto';
    final String dataStyle;
    if (rawDataStyle == 'auto') {
      final isCompact = widget.item.rowSpan <= 1;
      dataStyle = isCompact ? 'simple' : 'detailed';
    } else {
      dataStyle = rawDataStyle;
    }

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 10 : 14,
          vertical: dataStyle == 'simple' ? 8 : 12,
        ),
        onTap: _openDetails,
        child: dataStyle == 'simple'
            ? _buildCompactLOD(context, title, data, overall)
            : _buildFullLOD(context, title, data, overall, isNarrow),
      ),
    );
  }

  /// 紧凑模式（1 行）
  Widget _buildCompactLOD(
    BuildContext context,
    String title,
    ServerStatusData data,
    ServerHealthStatus overall,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final mainService = data.services.firstWhere(
      (s) => s.id == 1,
      orElse: () => data.services.first,
    );

    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: overall.color.withAlpha(25),
            border: Border.all(color: overall.color.withAlpha(80), width: 1.2),
          ),
          child: Icon(overall.icon, size: 16, color: overall.color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              Text(
                '主站 ${mainService.lastLatencyMs}ms · ${overall.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: colorScheme.outline),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: overall.color.withAlpha(25),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: overall.color,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                overall.label,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: overall.color),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 展开模式（2 行或更高）
  Widget _buildFullLOD(
    BuildContext context,
    String title,
    ServerStatusData data,
    ServerHealthStatus overall,
    bool isNarrow,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayServices = data.services.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 标题与总体状态指示
        Row(
          children: [
            Icon(Icons.dns_rounded, size: 17, color: overall.color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: overall.color.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: overall.color.withAlpha(60), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: overall.color),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    overall.label,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: overall.color),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 2. 核心节点延迟胶囊流（采用 Expanded 2×2 自适应弹性行网格，彻底根除底部裁切与错位）
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (displayServices.isNotEmpty)
                      Expanded(child: _buildServiceTile(context, displayServices[0])),
                    if (!isNarrow && displayServices.length > 1) ...[
                      const SizedBox(width: 8),
                      Expanded(child: _buildServiceTile(context, displayServices[1])),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Row(
                  children: [
                    if (isNarrow && displayServices.length > 1)
                      Expanded(child: _buildServiceTile(context, displayServices[1]))
                    else if (!isNarrow && displayServices.length > 2) ...[
                      Expanded(child: _buildServiceTile(context, displayServices[2])),
                      if (displayServices.length > 3) ...[
                        const SizedBox(width: 8),
                        Expanded(child: _buildServiceTile(context, displayServices[3])),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // 3. 底部快捷提示
        Row(
          children: [
            Text(
              '数据源 status.klpz.net',
              style: TextStyle(fontSize: 9.5, color: colorScheme.outline.withAlpha(150)),
            ),
            const Spacer(),
            Text(
              '点击查看详情 >',
              style: TextStyle(fontSize: 10, color: colorScheme.primary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServiceTile(BuildContext context, ServerStatusService s) {
    final colorScheme = Theme.of(context).colorScheme;
    final latColor = s.latencyColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withAlpha(70),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(40), width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: s.status.color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '${s.lastLatencyMs}ms',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: latColor),
          ),
        ],
      ),
    );
  }
}

/// 服务器状态全功能交互弹窗（status.klpz.net 完整数据展示）
class ServerStatusDetailDialog extends StatefulWidget {
  final ServerStatusData? initialData;

  const ServerStatusDetailDialog({super.key, this.initialData});

  static Future<void> show(BuildContext context, {ServerStatusData? initialData}) {
    return showDialog(
      context: context,
      builder: (ctx) => ServerStatusDetailDialog(initialData: initialData),
    );
  }

  @override
  State<ServerStatusDetailDialog> createState() => _ServerStatusDetailDialogState();
}

class _ServerStatusDetailDialogState extends State<ServerStatusDetailDialog> {
  late ServerStatusData _data;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData ?? _ServerStatusDashboardCardState.fixedMockData;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final fresh = await KlpbbsApi.getServerStatus(forceRefresh: true);
      if (mounted) setState(() => _data = fresh);
    } catch (_) {}
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _openWeb() async {
    final uri = Uri.parse('https://status.klpz.net/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final overall = _data.overallStatus;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Column(
          children: [
            // 头部
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: overall.color.withAlpha(30),
                    ),
                    child: Icon(overall.icon, color: overall.color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _data.siteName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '状态: ${overall.label} · 实时监控',
                        style: TextStyle(fontSize: 11, color: overall.color, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: _refreshing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: '刷新状态',
                    onPressed: _refreshing ? null : _refresh,
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    tooltip: '在浏览器打开',
                    onPressed: _openWeb,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),

            // 滚动服务列表
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                children: [
                  // 1. 最近事件记录 (若有)
                  if (_data.incidents.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.event_note_rounded, size: 16),
                        const SizedBox(width: 6),
                        const Text('最近故障与维护事件', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._data.incidents.take(3).map((inc) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: inc.isResolved
                              ? Colors.green.withAlpha(15)
                              : Colors.amber.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: inc.isResolved
                                ? Colors.green.withAlpha(60)
                                : Colors.amber.withAlpha(80),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  inc.title,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: inc.isResolved ? Colors.green : Colors.amber.shade700,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    inc.isResolved ? '已恢复' : '处理中',
                                    style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              inc.message,
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '开始: ${inc.startedAt} ${inc.resolvedAt != null ? "· 恢复: ${inc.resolvedAt}" : ""}',
                              style: TextStyle(fontSize: 9.5, color: colorScheme.outline),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],

                  // 2. 按分组展示所有服务节点
                  for (final group in _data.groups) ...[
                    Builder(builder: (context) {
                      final groupServices = _data.services.where((s) => s.groupId == group.id).toList();
                      if (groupServices.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  group.name,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${groupServices.length})',
                                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                                ),
                              ],
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: groupServices.map((service) {
                              final latColor = service.latencyColor;
                              return Container(
                                width: 180,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withAlpha(80),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant.withAlpha(50),
                                    width: 0.6,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: service.status.color,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            service.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Text(
                                          service.status.label,
                                          style: TextStyle(fontSize: 10, color: service.status.color, fontWeight: FontWeight.w500),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '${service.lastLatencyMs} ms',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: latColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    }),
                  ],
                ],
              ),
            ),

            // 底部操作区
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(40), width: 0.8)),
              ),
              child: Row(
                children: [
                  Text(
                    '监控主页: status.klpz.net',
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.launch_rounded, size: 15),
                    label: const Text('访问监控主站', style: TextStyle(fontSize: 12)),
                    onPressed: _openWeb,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
