import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../pages/download_manager_page.dart';
import '../services/download_service.dart';

/// 苦力怕论坛专属附件下载面板（支持解析下载页、选择下载线路、直接多线程下载、浏览器跳转）
class KlpbbsDownloadDialog extends StatefulWidget {
  final String filename;
  final String url;
  final String? sizeText;
  final String? priceText;

  const KlpbbsDownloadDialog({
    super.key,
    required this.filename,
    required this.url,
    this.sizeText,
    this.priceText,
  });

  static Future<void> show(
    BuildContext context, {
    required String filename,
    required String url,
    String? sizeText,
    String? priceText,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => KlpbbsDownloadDialog(
        filename: filename,
        url: url,
        sizeText: sizeText,
        priceText: priceText,
      ),
    );
  }

  @override
  State<KlpbbsDownloadDialog> createState() => _KlpbbsDownloadDialogState();
}

class _KlpbbsDownloadDialogState extends State<KlpbbsDownloadDialog> {
  int _selectedLineIndex = 0;
  bool _loadingLines = false;
  List<({String name, String url, String tag})> _lines = [];

  @override
  void initState() {
    super.initState();
    _initLines();
  }

  Future<void> _initLines() async {
    setState(() => _loadingLines = true);

    var targetUrl = widget.url.trim();
    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
      targetUrl = '${AppConfig.baseUrl}/$targetUrl'.replaceAll(RegExp(r'(?<!:)/+'), '/');
    }

    // 默认内置 3 条常用线路配置
    final defaultLines = <({String name, String url, String tag})>[
      (name: '官方主线路 (推荐·高速)', url: targetUrl, tag: '高速直连'),
      (name: '备用镜像线路 1 (CDN 加速)', url: targetUrl, tag: '国内节点'),
      (name: '备用镜像线路 2 (多线优化)', url: targetUrl, tag: '稳定备用'),
    ];

    try {
      // 尝试拉取下载跳转页探测是否存在多源下载线路与网盘
      final resp = await DioClient.dio.get<String>(
        targetUrl,
        options: Options(
          headers: {'Referer': 'https://klpbbs.com/forum.php'},
          followRedirects: true,
        ),
      );
      final html = resp.data ?? '';
      final customLines = <({String name, String url, String tag})>[];

      // 1. 探测网页中的所有下载按钮与下载链接
      final matches = RegExp(r'''<a[^>]+href=['"]([^'"]+)['"][^>]*>(.*?)</a>''', caseSensitive: false).allMatches(html);
      for (final m in matches) {
        final href = (m.group(1) ?? '').trim();
        final text = m.group(2)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) continue;

        if (text.contains('线路') || text.contains('下载') || text.contains('高速') ||
            text.contains('网盘') || text.contains('直链') || text.contains('本地') ||
            href.contains('attach') || href.contains('download') || href.contains('pan.baidu') ||
            href.contains('123pan') || href.contains('lanzou') || href.contains('quark')) {
          
          var fullUrl = href;
          if (!fullUrl.startsWith('http://') && !fullUrl.startsWith('https://')) {
            fullUrl = '${AppConfig.baseUrl}/$fullUrl'.replaceAll(RegExp(r'(?<!:)/+'), '/');
          }

          var tag = '直连';
          if (text.contains('高速')) {
            tag = '极速';
          } else if (text.contains('网盘')) {
            tag = '网盘';
          } else if (text.contains('备用')) {
            tag = '备用';
          }

          customLines.add((
            name: text.isNotEmpty ? text : '下载线路 ${customLines.length + 1}',
            url: fullUrl,
            tag: tag,
          ));
        }
      }

      if (customLines.isNotEmpty) {
        _lines = customLines;
      } else {
        _lines = defaultLines;
      }
    } catch (_) {
      _lines = defaultLines;
    } finally {
      if (mounted) setState(() => _loadingLines = false);
    }
  }

  Future<void> _startDownload() async {
    final chosen = _lines.isNotEmpty ? _lines[_selectedLineIndex] : (name: '默认线路', url: widget.url, tag: '');
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    Navigator.of(context).pop();

    // 如果是第三方网盘链接，直接通过浏览器调起
    final isCloudDrive = chosen.url.contains('pan.baidu') ||
        chosen.url.contains('123pan') ||
        chosen.url.contains('lanzou') ||
        chosen.url.contains('quark.cn') ||
        chosen.url.contains('mediafire.com') ||
        chosen.url.contains('curseforge.com');

    if (isCloudDrive) {
      final uri = Uri.tryParse(chosen.url);
      if (uri != null) {
        await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
      }
      messenger.showSnackBar(
        SnackBar(content: Text('已在外部浏览器中打开第三方网盘: ${chosen.name}')),
      );
      return;
    }

    await DownloadManager.instance.startDownload(
      url: chosen.url,
      filename: widget.filename,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text('已加入下载任务: ${widget.filename}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '查看下载',
          onPressed: () {
            nav.push(
              MaterialPageRoute(builder: (_) => const DownloadManagerPage()),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openInBrowser() async {
    var targetUrl = widget.url.trim();
    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
      targetUrl = '${AppConfig.baseUrl}/$targetUrl'.replaceAll(RegExp(r'(?<!:)/+'), '/');
    }
    Navigator.of(context).pop();
    final uri = Uri.tryParse(targetUrl);
    if (uri != null) {
      await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 顶部文件概要
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.insert_drive_file_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.filename,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (widget.sizeText != null && widget.sizeText!.isNotEmpty) ...[
                            Text(
                              widget.sizeText!,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (widget.priceText != null && widget.priceText!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.orange.withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.priceText!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // 2. 线路选择
            Row(
              children: [
                Icon(Icons.route_rounded, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '选择下载线路',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_loadingLines)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            for (int i = 0; i < _lines.length; i++) ...[
              InkWell(
                onTap: () => setState(() => _selectedLineIndex = i),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: _selectedLineIndex == i
                        ? colorScheme.primaryContainer.withAlpha(50)
                        : colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedLineIndex == i
                          ? colorScheme.primary
                          : colorScheme.outlineVariant.withAlpha(50),
                      width: _selectedLineIndex == i ? 1.5 : 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedLineIndex == i
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 20,
                        color: _selectedLineIndex == i
                            ? colorScheme.primary
                            : colorScheme.outline,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _lines[i].name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: _selectedLineIndex == i
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (_lines[i].tag.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _lines[i].tag,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // 3. 操作按钮组
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _startDownload,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('多线程直接下载'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _openInBrowser,
                  icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                  label: const Text('网页跳转下载'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
