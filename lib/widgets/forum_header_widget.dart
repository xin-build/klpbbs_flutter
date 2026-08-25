import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;

import '../api/klpbbs_api.dart';
import '../core/url_helper.dart';
import '../models/forum_header_info.dart';
import 'retry_image.dart';

/// 版块头部组件（100% 还原网页版：Banner 顶图 + 统计与版主栏 + 版块导览与规章卡片）
class ForumHeaderWidget extends StatefulWidget {
  final ForumHeaderInfo headerInfo;
  final VoidCallback? onPost;
  final VoidCallback? onFavorite;

  const ForumHeaderWidget({
    super.key,
    required this.headerInfo,
    this.onPost,
    this.onFavorite,
  });

  @override
  State<ForumHeaderWidget> createState() => _ForumHeaderWidgetState();
}

class _ForumHeaderWidgetState extends State<ForumHeaderWidget> {
  bool _expanded = true;
  late ForumHeaderInfo _info;

  @override
  void initState() {
    super.initState();
    _info = widget.headerInfo;
    if (_info.rulesHtml.isEmpty && _info.bannerUrl == null) {
      _loadHeader();
    }
  }

  @override
  void didUpdateWidget(covariant ForumHeaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.headerInfo.fid != widget.headerInfo.fid ||
        oldWidget.headerInfo.rulesHtml != widget.headerInfo.rulesHtml) {
      _info = widget.headerInfo;
      if (_info.rulesHtml.isEmpty && _info.bannerUrl == null) {
        _loadHeader();
      }
    }
  }

  Future<void> _loadHeader() async {
    try {
      final header = await KlpbbsApi.getForumHeader(_info.fid);
      if (mounted && (header.rulesHtml.isNotEmpty || header.bannerUrl != null || header.todayPosts > 0)) {
        setState(() => _info = header);
      }
    } catch (_) {}
  }

  void _openLink(String href) {
    if (href.isEmpty) return;
    if (href.contains('post') || href.contains('newthread')) {
      widget.onPost?.call();
      return;
    }
    UrlHelper.openLink(context, href);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(50),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 版块顶部横幅 Banner（若存在）
          if (info.bannerUrl != null && info.bannerUrl!.isNotEmpty)
            Stack(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 90,
                    maxHeight: 180,
                  ),
                  child: AspectRatio(
                    aspectRatio: 3.8,
                    child: RetryImage(
                      imageUrl: info.bannerUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withAlpha(70),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

          // 2. 版块基础信息与统计数据栏
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：统计标签（左） + 积分规则与导览切换（右）
                Row(
                  children: [
                    // 统计指标
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildStatChip(
                          label: '今日',
                          value: '${info.todayPosts}',
                          color: colorScheme.primary,
                        ),
                        _buildStatChip(
                          label: '主题',
                          value: '${info.threadsCount}',
                          color: colorScheme.onSurface,
                        ),
                        if (info.rank > 0)
                          _buildStatChip(
                            label: '排名',
                            value: '${info.rank}',
                            color: const Color(0xFFE6A23C),
                          ),
                      ],
                    ),
                    const Spacer(),

                    // 积分规则按钮
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _showCreditRulesDialog(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.monetization_on_outlined,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '积分规则',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // 展开收起导览
                    if (info.rulesHtml.isNotEmpty)
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                size: 16,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                _expanded ? '收起导览' : '展开导览',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                // 第二行：版主列表（独立整齐展示，带盾牌图标）
                if (info.moderators.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(80),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 14,
                          color: colorScheme.primary.withAlpha(220),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '版主: ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            info.moderators,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colorScheme.onSurfaceVariant.withAlpha(220),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 3. 版块导览与规章卡片（还原网页版富文本与快速入口按钮）
          if (info.rulesHtml.isNotEmpty && _expanded) ...[
            const Divider(height: 1, indent: 12, endIndent: 12),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildRichRulesContent(context, info.rulesHtml),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 11,
              color: color.withAlpha(200),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichRulesContent(BuildContext context, String htmlContent) {
    final doc = html_parser.parse(htmlContent);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 0. 顶部公告/通知提示文本（如发帖审核提醒等）
    final notices = <String>[];
    for (final p in doc.querySelectorAll('div, p, strong, font')) {
      final t = p.text.replaceAll('&nbsp;', ' ').trim();
      if ((t.contains('审核') || t.contains('注意') || t.contains('提醒') || t.contains('公约')) &&
          p.children.isEmpty &&
          t.length < 150 &&
          !notices.contains(t)) {
        notices.add(t);
      }
    }

    // 1. 提取所有有效图片并严格区分为【宣传海报大图】与【功能按钮】
    final posters = <({String src, String? href})>[];
    final imageButtons = <({String src, String href, String alt})>[];

    final allImgs = doc.querySelectorAll('img');
    for (final img in allImgs) {
      final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
      if (src.isEmpty || src.contains('none.png') || src.contains('spacer.gif')) continue;

      final a = img.parent?.localName == 'a'
          ? img.parent
          : (img.parent?.parent?.localName == 'a' ? img.parent?.parent : null);
      final href = a?.attributes['href'] ?? '';

      final w = int.tryParse(img.attributes['width'] ?? '') ?? 0;
      final h = int.tryParse(img.attributes['height'] ?? '') ?? 0;

      // 海报判定：宽度 >= 350、高度 >= 140、或者在没有表格且仅有 1 张大图时
      final isPoster = w >= 350 || h >= 140 || (allImgs.indexOf(img) == 0 && allImgs.length > 1 && (w == 0 || w >= 280));

      if (isPoster) {
        posters.add((src: src, href: href.isNotEmpty ? href : null));
      } else if (href.isNotEmpty) {
        imageButtons.add((
          src: src,
          href: href,
          alt: img.attributes['alt'] ?? a?.text.trim() ?? '',
        ));
      } else {
        posters.add((src: src, href: null));
      }
    }

    // 2. 纯文本链接（如版主链接）
    final textLinks = <({String href, String text})>[];
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      final img = a.querySelector('img');
      if (img == null) {
        final text = a.text.trim();
        if (text.isNotEmpty && !text.contains('http') && text.length < 20) {
          textLinks.add((href: href, text: text));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 0. 提示通知条
        for (final notice in notices)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withAlpha(50),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colorScheme.primary.withAlpha(60),
                width: 0.6,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    notice,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // 1. 顶部宣传海报大图（全宽卡片，自适应圆角与点击事件）
        for (final poster in posters)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: poster.href != null ? () => _openLink(poster.href!) : null,
                  child: RetryImage(
                    imageUrl: poster.src,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                  ),
                ),
              ),
            ),
          ),

        // 2. 功能交互按钮区（智能适配：1-3 个横幅纵向全宽展示，4个以上卡片按矩阵网格展示）
        if (imageButtons.isNotEmpty) ...[
          if (imageButtons.length <= 3)
            for (final item in imageButtons)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openLink(item.href),
                      child: RetryImage(
                        imageUrl: item.src,
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                      ),
                    ),
                  ),
                ),
              )
          else
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth > 520;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isWide ? 3 : 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 275 / 90,
                  ),
                  itemCount: imageButtons.length,
                  itemBuilder: (ctx, i) {
                    final item = imageButtons[i];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _openLink(item.href),
                          child: RetryImage(
                            imageUrl: item.src,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ],
    );
  }

  void _showCreditRulesDialog(BuildContext context) {
    final theme = Theme.of(context);
    final creditRules = _info.creditRules.isNotEmpty
        ? _info.creditRules
        : const [
            ForumCreditRule(action: '发表主题', cycle: '每天', maxDaily: '10次', exp: '+2', iron: '+1', tribute: '0'),
            ForumCreditRule(action: '发表回复', cycle: '每天', maxDaily: '20次', exp: '+1', iron: '+0', tribute: '0'),
            ForumCreditRule(action: '加入精华', cycle: '一次', maxDaily: '不限', exp: '+10', iron: '+5', tribute: '+1'),
            ForumCreditRule(action: '采纳最佳', cycle: '一次', maxDaily: '不限', exp: '+3', iron: '+悬赏', tribute: '0'),
            ForumCreditRule(action: '删除主题', cycle: '一次', maxDaily: '不限', exp: '-5', iron: '-3', tribute: '0'),
            ForumCreditRule(action: '删除回复', cycle: '一次', maxDaily: '不限', exp: '-2', iron: '-1', tribute: '0'),
          ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.monetization_on_outlined, color: theme.colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              '${_info.name} · 本版积分规则',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...creditRules.map((rule) {
                  final isNegative = rule.exp.startsWith('-') || rule.iron.startsWith('-');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isNegative
                          ? theme.colorScheme.errorContainer.withAlpha(35)
                          : theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isNegative
                            ? theme.colorScheme.error.withAlpha(70)
                            : theme.colorScheme.outlineVariant.withAlpha(50),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          rule.action,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isNegative ? theme.colorScheme.error : theme.colorScheme.primary,
                          ),
                        ),
                        const Spacer(),
                        if (rule.exp != '0' && rule.exp != '+0')
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              '经验 ${rule.exp}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isNegative ? Colors.red : Colors.blue,
                              ),
                            ),
                          ),
                        if (rule.iron != '0' && rule.iron != '+0')
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              '铁粒 ${rule.iron}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isNegative
                                    ? (theme.brightness == Brightness.dark ? Colors.red.shade300 : Colors.red)
                                    : (theme.brightness == Brightness.dark ? Colors.amber.shade300 : Colors.amber.shade800),
                              ),
                            ),
                          ),
                        Text(
                          '(${rule.cycle}/${rule.maxDaily})',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }
}
