import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/klpbbs_api.dart';
import '../core/url_helper.dart';
import '../models/ai_summary.dart';

/// 苦力怕论坛 AI 总结卡片（对接 klpbbs_aisum 插件）
///
/// 支持三大维度智能解析：速览、下载外链、注意事项；
/// 提供一键复制、外链唤起、动态刷新与折叠展开功能。
class AiSummaryCard extends StatefulWidget {
  final int tid;
  final AiSummaryData? initialData;
  final VoidCallback? onRefresh;

  const AiSummaryCard({
    super.key,
    required this.tid,
    this.initialData,
    this.onRefresh,
  });

  @override
  State<AiSummaryCard> createState() => _AiSummaryCardState();
}

class _AiSummaryCardState extends State<AiSummaryCard> {
  AiSummaryData? _data;
  bool _isLoading = false;
  int _tabIndex = 0;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    if (_data == null || _data!.isEmpty) {
      _loadSummary();
    }
  }

  @override
  void didUpdateWidget(covariant AiSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialData != null && widget.initialData != oldWidget.initialData) {
      setState(() {
        _data = widget.initialData;
      });
    }
  }

  Future<void> _loadSummary({bool forceRefresh = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final res = await KlpbbsApi.fetchAiSummary(
        widget.tid,
        streamUrl: _data?.streamUrl,
        forceRefresh: forceRefresh,
      );
      if (mounted && res != null) {
        setState(() {
          _data = res;
          _isLoading = false;
        });
        widget.onRefresh?.call();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyContent(BuildContext context) {
    if (_data == null || _data!.isEmpty) return;
    final buf = StringBuffer();
    if (_data!.headline.isNotEmpty) {
      buf.writeln('【AI 总结】\n');
    }
    if (_tabIndex == 0) {
      buf.writeln(_data!.summary);
    } else if (_tabIndex == 1) {
      if (_data!.downloadSteps.isNotEmpty) {
        buf.writeln('【下载说明】');
        for (var i = 0; i < _data!.downloadSteps.length; i++) {
          buf.writeln('${i + 1}. ${_data!.downloadSteps[i]}');
        }
      }
      if (_data!.links.isNotEmpty) {
        buf.writeln('\n【外链地址】');
        for (final l in _data!.links) {
          buf.writeln('${l.label.isNotEmpty ? l.label : "链接"}: ${l.url}');
        }
      }
    } else if (_tabIndex == 2) {
      buf.writeln('【注意事项】');
      for (final n in _data!.notices) {
        buf.writeln('• $n');
      }
    }
    Clipboard.setData(ClipboardData(text: buf.toString().trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制 AI 总结内容至剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final data = _data;

    if (data == null || (data.isEmpty && !_isLoading)) {
      return const SizedBox.shrink();
    }

    final downloadCount = data.links.length + data.downloadSteps.length;
    final hasDownloads = downloadCount > 0;
    final hasNotices = data.notices.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withAlpha(60),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withAlpha(12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部标题栏
          _buildHeader(context, theme, colorScheme),

          // 主体折叠区域
          if (_isExpanded) ...[
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              // 大标题提要
              if (data.headline.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withAlpha(45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border(
                      left: BorderSide(
                        color: colorScheme.primary,
                        width: 3.5,
                      ),
                    ),
                  ),
                  child: Text(
                    data.headline,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),

              // 分段 Tab 切换胶囊
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                child: Row(
                  children: [
                    _buildTabPill(
                      index: 0,
                      label: '总结',
                      icon: Icons.article_outlined,
                      selectedIcon: Icons.article_rounded,
                      theme: theme,
                    ),
                    const SizedBox(width: 8),
                    _buildTabPill(
                      index: 1,
                      label: hasDownloads ? '下载 $downloadCount' : '下载',
                      icon: Icons.download_outlined,
                      selectedIcon: Icons.download_rounded,
                      theme: theme,
                    ),
                    const SizedBox(width: 8),
                    _buildTabPill(
                      index: 2,
                      label: hasNotices ? '提醒 ${data.notices.length}' : '提醒',
                      icon: Icons.info_outline_rounded,
                      selectedIcon: Icons.info_rounded,
                      theme: theme,
                    ),
                  ],
                ),
              ),

              // Tab 对应面板
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _buildTabContent(context, theme, data),
                ),
              ),

              // 底部免责声明与生成时间
              _buildFooter(theme, colorScheme, data),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withAlpha(16),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(35),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.tertiary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 15,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'AI 智能速览',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'KLP-AI',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const Spacer(),
          // 复制
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: '复制当前内容',
            visualDensity: VisualDensity.compact,
            onPressed: () => _copyContent(context),
          ),
          // 刷新
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 17),
            tooltip: '重新生成总结',
            visualDensity: VisualDensity.compact,
            onPressed: _isLoading ? null : () => _loadSummary(forceRefresh: true),
          ),
          // 折叠 / 展开
          IconButton(
            icon: Icon(
              _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              size: 20,
            ),
            tooltip: _isExpanded ? '收起总结' : '展开总结',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _isExpanded = !_isExpanded),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    required ThemeData theme,
  }) {
    final isSelected = _tabIndex == index;
    final colorScheme = theme.colorScheme;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                size: 13.5,
                color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, ThemeData theme, AiSummaryData data) {
    switch (_tabIndex) {
      case 0:
        return _buildSummaryTab(theme, data);
      case 1:
        return _buildDownloadTab(context, theme, data);
      case 2:
        return _buildNoticeTab(theme, data);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSummaryTab(ThemeData theme, AiSummaryData data) {
    final text = data.summary.trim();
    if (text.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '暂无提炼速览',
          style: TextStyle(color: theme.colorScheme.outline),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SelectableText(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          height: 1.6,
          color: theme.colorScheme.onSurface.withAlpha(225),
        ),
      ),
    );
  }

  Widget _buildDownloadTab(BuildContext context, ThemeData theme, AiSummaryData data) {
    final hasLinks = data.links.isNotEmpty;
    final hasSteps = data.downloadSteps.isNotEmpty;

    if (!hasLinks && !hasSteps) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '未检测到外链或网盘下载信息',
            style: TextStyle(color: theme.colorScheme.outline, fontSize: 12.5),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasSteps) ...[
            Text(
              '下载步骤与指引：',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < data.downloadSteps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}. ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        data.downloadSteps[i],
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (hasLinks) const SizedBox(height: 10),
          ],
          if (hasLinks) ...[
            Text(
              '外链与资源地址：',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            for (final l in data.links)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withAlpha(60),
                    width: 0.8,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  onTap: () => UrlHelper.openLink(context, l.url),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.cloud_download_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    l.label.isNotEmpty ? l.label : (l.service.isNotEmpty ? l.service : '下载外链'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: Text(
                    l.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        tooltip: '复制链接',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: l.url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已复制外链至剪贴板'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        tooltip: '打开链接',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => UrlHelper.openLink(context, l.url),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoticeTab(ThemeData theme, AiSummaryData data) {
    if (data.notices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '作者未声明特殊注意事项',
            style: TextStyle(color: theme.colorScheme.outline, fontSize: 12.5),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final n in data.notices)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withAlpha(28),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.error.withAlpha(40),
                  width: 0.8,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      n,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, ColorScheme colorScheme, AiSummaryData data) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(50),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(30),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 12,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'AI 生成内容仅供参考，请以帖内正文为准',
              style: TextStyle(
                fontSize: 10.5,
                color: colorScheme.outline,
              ),
            ),
          ),
          if (data.generatedTime != null && data.generatedTime!.isNotEmpty)
            Text(
              data.generatedTime!,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.outline.withAlpha(180),
              ),
            ),
        ],
      ),
    );
  }
}
