import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/server_outage_info.dart';
import 'dashboard_cards/server_status_dashboard_card.dart';

/// 贴合苦力怕论坛应用设计语言的服务端故障视图（502 Bad Gateway / 503 / 504 / 521 等）
class ServerOutageView extends StatelessWidget {
  final ServerOutageInfo outage;
  final VoidCallback? onRetry;
  final VoidCallback? onGoHome;
  final VoidCallback? onViewCache;
  final VoidCallback? onClose;
  final bool isCompact;

  const ServerOutageView({
    super.key,
    required this.outage,
    this.onRetry,
    this.onGoHome,
    this.onViewCache,
    this.onClose,
    this.isCompact = false,
  });

  /// 以弹窗形式展示完整诊断页
  static Future<void> showAsDialog(
    BuildContext context, {
    required ServerOutageInfo outage,
    VoidCallback? onRetry,
    VoidCallback? onViewCache,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final screenHeight = MediaQuery.sizeOf(ctx).height;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: screenHeight * 0.88,
            ),
            child: ServerOutageView(
              outage: outage,
              onRetry: () {
                Navigator.of(ctx).pop();
                onRetry?.call();
              },
              onGoHome: () {
                Navigator.of(ctx).pop();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              onViewCache: onViewCache != null
                  ? () {
                      Navigator.of(ctx).pop();
                      onViewCache();
                    }
                  : null,
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        );
      },
    );
  }

  void _handleGoHome(BuildContext context) {
    if (onGoHome != null) {
      onGoHome!();
      return;
    }
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
  }

  void _copyDiagnostics(BuildContext context) {
    Clipboard.setData(ClipboardData(text: outage.toDiagnosticReport()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制诊断报告与 Request ID: ${outage.requestId}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openServerStatus(BuildContext context) {
    ServerStatusDetailDialog.show(context);
  }

  void _showRawResponse(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final raw = outage.rawHtml ?? '(无原始响应主体)';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, scrollController) {
              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.data_object_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '实时源站/网关响应数据',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          tooltip: '复制源码',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: raw));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('已复制原始响应数据到剪贴板'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const TabBar(
                    tabs: [
                      Tab(text: '网页源码 (HTML / Text)'),
                      Tab(text: '请求元信息 & Headers'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            raw,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                        ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildMetaRow('HTTP 状态码', '${outage.statusCode} ${outage.statusMessage}', colorScheme),
                            if (outage.requestUrl != null)
                              _buildMetaRow('请求地址 (URL)', outage.requestUrl!, colorScheme),
                            _buildMetaRow('Request / Ray ID', outage.requestId, colorScheme),
                            if (outage.datacenter != null)
                              _buildMetaRow('Cloudflare 数据中心', outage.datacenter!, colorScheme),
                            if (outage.serverEngine != null)
                              _buildMetaRow('网关服务器', outage.serverEngine!, colorScheme),
                            _buildMetaRow('客户端真实 IP', outage.clientIp, colorScheme),
                            _buildMetaRow('捕获时间', outage.timestamp.toLocal().toString(), colorScheme),
                            const SizedBox(height: 12),
                            const Text(
                              'HTTP 响应头 (Headers):',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            if (outage.headers != null && outage.headers!.isNotEmpty)
                              ...outage.headers!.entries.map(
                                (e) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${e.key}: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                      Expanded(
                                        child: SelectableText(
                                          e.value.join(', '),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              const Text('无响应头数据', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMetaRow(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    // 贴近应用原生调色板（契合苦力怕深色/浅色卡片与设计规范）
    final cardBg = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surface;
    final cardBorder = colorScheme.outlineVariant.withAlpha(isDark ? 65 : 120);
    final topologyBg = isDark
        ? colorScheme.surfaceContainer
        : colorScheme.surfaceContainerLowest;
    final textDark = colorScheme.onSurface;
    final textMid = colorScheme.onSurfaceVariant;
    final textMuted = colorScheme.outline;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorder, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 20,
              vertical: isCompact ? 12 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. 顶部状态胶囊标签 + 节点 + 应用身份标识 + 关闭按钮
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0x33EF4444)
                                  : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0x66EF4444)
                                    : const Color(0xFFFECACA),
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  outage.badgeText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: isDark
                                        ? const Color(0xFFF87171)
                                        : const Color(0xFFB91C1C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (outage.datacenter != null && outage.datacenter!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: topologyBg,
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(color: cardBorder, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on_outlined, size: 12, color: textMuted),
                                  const SizedBox(width: 4),
                                  Text(
                                    '节点: ${outage.datacenter}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: textMid,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            '苦力怕论坛 · 服务端异常',
                            style: TextStyle(
                              fontSize: 12,
                              color: textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (onClose != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              tooltip: '关闭',
                              onPressed: onClose,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),

                      // 2. 超大状态码与错误名称
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            outage.statusCode.toString(),
                            style: TextStyle(
                              fontSize: 54,
                              fontWeight: FontWeight.w900,
                              color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                              height: 1.0,
                              letterSpacing: -1.0,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  outage.title,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  outage.subtitleZh,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                    color: textMid,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // 2.1 实时请求 URL（如果可用）
                      if (outage.requestUrl != null && outage.requestUrl!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: topologyBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cardBorder, width: 0.8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.link_rounded, size: 14, color: textMuted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  outage.requestUrl!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontFamily: 'monospace',
                                    color: textMid,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // 3. 详细说明卡片
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: topologyBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cardBorder, width: 0.8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              outage.descZh,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.55,
                                color: textMid,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              outage.descEn,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 4. 诊断拓扑流卡片（与应用内服务器监控卡片风格深度对齐）
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: topologyBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cardBorder, width: 1.0),
                        ),
                        child: Column(
                          children: [
                            // 标题栏
                            Row(
                              children: [
                                Icon(Icons.hub_rounded, size: 16, color: colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  '网络链路诊断拓扑',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: textDark,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '实时网关状态',
                                  style: TextStyle(fontSize: 11, color: textMuted),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // 节点 1: 客户端 Client
                            _buildTopologyNode(
                              icon: Icons.phone_android_rounded,
                              isGreen: true,
                              titleZh: '客户端',
                              titleEn: 'Client',
                              detail: outage.clientIp,
                              statusText: outage.clientStatus,
                              statusColor: const Color(0xFF10B981),
                              textDark: textDark,
                              textMuted: textMuted,
                              isDark: isDark,
                            ),

                            // 连接线 1: 绿色实线
                            _buildConnectorLine(
                              color: const Color(0xFF10B981),
                              isDotted: false,
                            ),

                            // 节点 2: 网关 Gateway
                            _buildTopologyNode(
                              icon: Icons.cloud_done_rounded,
                              isGreen: true,
                              titleZh: '网关代理',
                              titleEn: 'Gateway',
                              detail: outage.datacenter != null
                                  ? 'Cloudflare (${outage.datacenter}) · 边缘节点'
                                  : (outage.serverEngine != null
                                      ? '${outage.serverEngine} · 边缘反向代理'
                                      : 'Cloudflare / Edge Reverse Proxy'),
                              statusText: outage.gatewayStatus,
                              statusColor: const Color(0xFF10B981),
                              textDark: textDark,
                              textMuted: textMuted,
                              isDark: isDark,
                            ),

                            // 连接线 2: 红色虚线
                            _buildConnectorLine(
                              color: const Color(0xFFEF4444),
                              isDotted: true,
                            ),

                            // 节点 3: 源站 Origin
                            _buildTopologyNode(
                              icon: Icons.dns_rounded,
                              isGreen: false,
                              titleZh: '论坛源站',
                              titleEn: 'Origin',
                              detail: outage.originDetail,
                              statusText: outage.originStatus,
                              statusColor: const Color(0xFFEF4444),
                              textDark: textDark,
                              textMuted: textMuted,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // 5. 操作按钮区（采用应用原生 Material 3 按钮规范）
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // 重新载入 Retry
                          FilledButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('重新载入 Retry'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),

                          // 返回首页 Home
                          FilledButton.tonalIcon(
                            onPressed: () => _handleGoHome(context),
                            icon: const Icon(Icons.home_rounded, size: 18),
                            label: const Text('返回首页 Home'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),

                          // 服务监控 ( status.klpz.net )
                          OutlinedButton.icon(
                            onPressed: () => _openServerStatus(context),
                            icon: const Icon(Icons.monitor_heart_outlined, size: 16),
                            label: const Text('服务监控'),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: cardBorder),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),

                          // 查看源站原始网页 / 源码 (Raw HTML)
                          if (outage.rawHtml != null && outage.rawHtml!.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _showRawResponse(context),
                              icon: const Icon(Icons.code_rounded, size: 16),
                              label: const Text('原始响应数据'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: cardBorder),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                          // 浏览离线缓存（如果可用）
                          if (onViewCache != null)
                            TextButton.icon(
                              onPressed: onViewCache,
                              icon: const Icon(Icons.archive_outlined, size: 16),
                              label: const Text('浏览离线缓存'),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 6. 底部 Request ID 与一键复制条
                Divider(color: cardBorder, height: 1, thickness: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.fingerprint_rounded, size: 16, color: textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Request ID: ${outage.requestId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _copyDiagnostics(context),
                        icon: const Icon(Icons.copy_rounded, size: 13),
                        label: const Text('复制诊断报告', style: TextStyle(fontSize: 11.5)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textMid,
                          side: BorderSide(color: cardBorder),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建单行拓扑节点
  Widget _buildTopologyNode({
    required IconData icon,
    required bool isGreen,
    required String titleZh,
    required String titleEn,
    required String? detail,
    required String statusText,
    required Color statusColor,
    required Color textDark,
    required Color textMuted,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 节点图标徽标（圆形带柔光）
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isGreen
                ? const Color(0x2210B981)
                : const Color(0x22EF4444),
            border: Border.all(
              color: isGreen
                  ? const Color(0x4410B981)
                  : const Color(0x44EF4444),
            ),
          ),
          child: Icon(
            icon,
            size: 15,
            color: isGreen ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          ),
        ),
        const SizedBox(width: 12),

        // 标题与附注详情
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    titleZh,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    titleEn,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: textMuted,
                    ),
                  ),
                ],
              ),
              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),

        // 右侧状态文本（大写，宽字距）
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: statusColor,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建节点之间的连接线
  Widget _buildConnectorLine({
    required Color color,
    required bool isDotted,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 13.25),
      child: Align(
        alignment: Alignment.centerLeft,
        child: isDotted
            ? CustomPaint(
                size: const Size(1.5, 18),
                painter: _DottedLinePainter(color: color),
              )
            : Container(
                width: 1.5,
                height: 16,
                color: color,
              ),
      ),
    );
  }
}

/// 顶部网关故障提醒横幅（当主站 502/宕机但应用正在使用本地离线缓存时置顶显示）
class ServerOutageBanner extends StatelessWidget {
  final ServerOutageInfo outage;
  final VoidCallback onRetry;
  final VoidCallback onViewDetails;
  final VoidCallback? onDismiss;

  const ServerOutageBanner({
    super.key,
    required this.outage,
    required this.onRetry,
    required this.onViewDetails,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bannerBg = isDark
        ? const Color(0xFF261815)
        : const Color(0xFFFFF1F0);
    final bannerBorder = isDark
        ? const Color(0xFF6B2721)
        : const Color(0xFFFFA39E);
    final textPrimary = isDark
        ? const Color(0xFFFFCCC7)
        : const Color(0xFFCF1322);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bannerBorder, width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 18,
              color: Color(0xFFEF4444),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '论坛源站网关异常 (${outage.statusCode} ${outage.title})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '当前正为您展示本地离线缓存数据，在线互动与最新内容暂不可用。',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: textPrimary.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onViewDetails,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: textPrimary,
              side: BorderSide(color: bannerBorder),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('详细诊断', style: TextStyle(fontSize: 11.5)),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('重试', style: TextStyle(fontSize: 11.5)),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.close, size: 16, color: textPrimary.withOpacity(0.7)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: onDismiss,
              tooltip: '关闭提示',
            ),
          ],
        ],
      ),
    );
  }
}

/// 虚线连接画笔（用于网关到源站的故障连接）
class _DottedLinePainter extends CustomPainter {
  final Color color;

  const _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width
      ..strokeCap = StrokeCap.round;

    const dashHeight = 3.0;
    const dashSpace = 3.0;
    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(0, startY),
        Offset(0, (startY + dashHeight).clamp(0, size.height)),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
