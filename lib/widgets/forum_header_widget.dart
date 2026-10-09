import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/url_helper.dart';
import '../models/forum_header_info.dart';
import 'interactive_animations.dart';
import 'app_motion.dart';
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
    if (oldWidget.headerInfo != widget.headerInfo) {
      _info = widget.headerInfo;
      if (oldWidget.headerInfo.fid != _info.fid &&
          _info.rulesHtml.isEmpty &&
          _info.bannerUrl == null) {
        _loadHeader();
      }
    }
  }

  Future<void> _loadHeader() async {
    final requestedFid = _info.fid;
    try {
      final header = await KlpbbsApi.getForumHeader(requestedFid);
      if (mounted && _info.fid == requestedFid && !header.isEmpty) {
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
          // 1. 版块顶部横幅 Banner（服务端动态配置，缺失自动启用官方分区高清风景横幅）
          Builder(
            builder: (context) {
              final banner =
                  (info.bannerUrl != null && info.bannerUrl!.isNotEmpty)
                      ? info.bannerUrl!
                      : AppConfig.forumBannerUrl(info.fid);
              return Stack(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 90,
                      maxHeight: 180,
                    ),
                    child: AspectRatio(
                      aspectRatio: 3.8,
                      child: RetryImage(
                        imageUrl: banner,
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
              );
            },
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
                    Expanded(
                        child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (info.hasTodayPosts)
                          _buildStatChip(
                            label: '今日',
                            value: info.displayCount('today'),
                            color: colorScheme.primary,
                          ),
                        if (info.hasThreadsCount)
                          _buildStatChip(
                            label: '主题',
                            value: info.displayCount('topics'),
                            color: colorScheme.onSurface,
                          ),
                        if (info.hasPostsCount)
                          _buildStatChip(
                              label: '帖数',
                              value: info.displayCount('posts'),
                              color: colorScheme.onSurfaceVariant),
                        if (info.rank > 0)
                          _buildStatChip(
                            label: '排名',
                            value: '${info.rank}',
                            color: const Color(0xFFE6A23C),
                          ),
                      ],
                    )),

                    // 积分规则按钮
                    InkWell(
                      key: const ValueKey('forum-credit-rules-open'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _showCreditRulesDialog(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
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

                    // 展开收起导览（带触控微回弹与状态记忆）
                    if (info.rulesHtml.isNotEmpty)
                      PressScaleEffect(
                        scaleDown: 0.94,
                        enableHaptic: true,
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withAlpha(90),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedExpandArrow(
                                isCollapsed: !_expanded,
                                size: 16,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _expanded ? '收起导览' : '展开导览',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                              color:
                                  colorScheme.onSurfaceVariant.withAlpha(220),
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

          // 3. 版块导览与规章卡片（原生 Android 级流体手风琴错峰视差展开）
          if (info.rulesHtml.isNotEmpty)
            FluidAccordionSection(
              isCollapsed: !_expanded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1, indent: 12, endIndent: 12),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildRichRulesContent(context, info.rulesHtml),
                  ),
                ],
              ),
            ),
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
    for (final p in doc.querySelectorAll('div, p')) {
      final t = p.text.replaceAll('&nbsp;', ' ').trim();
      if ((t.contains('审核') ||
              t.contains('注意') ||
              t.contains('提醒') ||
              t.contains('公约')) &&
          p.querySelector('img, table') == null &&
          t.length < 150 &&
          !notices.any((n) => n.contains(t) || t.contains(n))) {
        notices.add(t);
      }
    }

    // 1. 提取所有有效图片并严格区分为【宣传海报大图】与【功能按钮】
    final posters = <({String src, String? href})>[];
    final imageButtons = <({String src, String href, String alt})>[];

    final allImgs = doc.querySelectorAll('img');
    for (final img in allImgs) {
      final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
      if (src.isEmpty ||
          src.contains('none.png') ||
          src.contains('spacer.gif')) {
        continue;
      }

      final a = img.parent?.localName == 'a'
          ? img.parent
          : (img.parent?.parent?.localName == 'a' ? img.parent?.parent : null);
      final href = a?.attributes['href'] ?? '';

      final w = int.tryParse(img.attributes['width'] ?? '') ?? 0;
      final h = int.tryParse(img.attributes['height'] ?? '') ?? 0;

      // 海报判定：宽度 >= 350、高度 >= 140、或者在没有表格且仅有 1 张大图时
      final isPoster = w >= 350 ||
          h >= 140 ||
          (allImgs.indexOf(img) == 0 &&
              allImgs.length > 1 &&
              (w == 0 || w >= 280));

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
        // 0. 提示通知条（微延迟错峰浮现）
        for (var i = 0; i < notices.length; i++)
          AccordionStaggerItem(
            index: i,
            child: Container(
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
                      notices[i],
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
          ),

        // 1. 顶部宣传海报大图（全宽卡片，自适应圆角、微按压反馈与错峰弹跳展开）
        for (var i = 0; i < posters.length; i++)
          AccordionStaggerItem(
            index: notices.length + i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HoverScaleElevationEffect(
                translateY: -2.5,
                child: PressScaleEffect(
                  scaleDown: 0.985,
                  enableHaptic: true,
                  onTap: posters[i].href != null
                      ? () => _openLink(posters[i].href!)
                      : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: RetryImage(
                      imageUrl: posters[i].src,
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // 2. 功能交互按钮区（智能适配：1-3 个横幅纵向全宽展示，4个以上卡片按矩阵网格错峰展开，带触感微弹跳）
        if (imageButtons.isNotEmpty) ...[
          if (imageButtons.length <= 3)
            for (var i = 0; i < imageButtons.length; i++)
              AccordionStaggerItem(
                index: notices.length + posters.length + i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: HoverScaleElevationEffect(
                    translateY: -2.0,
                    child: PressScaleEffect(
                      scaleDown: 0.97,
                      enableHaptic: true,
                      onTap: () => _openLink(imageButtons[i].href),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: RetryImage(
                          imageUrl: imageButtons[i].src,
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                        ),
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
                    return AccordionStaggerItem(
                      index: notices.length + posters.length + i,
                      child: HoverScaleElevationEffect(
                        translateY: -2.0,
                        child: PressScaleEffect(
                          scaleDown: 0.955,
                          enableHaptic: true,
                          onTap: () => _openLink(item.href),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: RetryImage(
                              imageUrl: item.src,
                              fit: BoxFit.cover,
                            ),
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
    final info = _info;
    showDialog<void>(
      context: context,
      builder: (_) => _ForumCreditRulesDialog(fid: info.fid, name: info.name),
    );
  }
}

class _ForumCreditRulesDialog extends StatefulWidget {
  final int fid;
  final String name;
  const _ForumCreditRulesDialog({required this.fid, required this.name});

  @override
  State<_ForumCreditRulesDialog> createState() =>
      _ForumCreditRulesDialogState();
}

class _ForumCreditRulesDialogState extends State<_ForumCreditRulesDialog> {
  late final String _session;
  final _tableScroll = ScrollController();
  List<ForumCreditRule> _rules = const [];
  bool _loading = true, _restricted = false, _accountChanged = false;
  String? _message;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _session = DioClient.sessionKey;
    DioClient.sessionChanges.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    _tableScroll.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted || _session == DioClient.sessionKey) return;
    _generation++;
    setState(() {
      _rules = const [];
      _loading = false;
      _accountChanged = true;
      _restricted = true;
      _message = '账号已切换，请关闭后重新查看积分规则';
    });
  }

  Future<void> _load() async {
    if (_accountChanged || _session != DioClient.sessionKey) return;
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _message = null;
        _restricted = false;
      });
    }
    bool current() =>
        mounted &&
        generation == _generation &&
        _session == DioClient.sessionKey;
    try {
      final rules = await KlpbbsApi.getCreditRules(widget.fid);
      if (!current()) return;
      setState(() {
        _rules = rules;
        _loading = false;
      });
    } catch (error) {
      if (!current()) return;
      final message = error is StateError
          ? error.message
          : error is FormatException
              ? error.message
              : '积分规则加载失败，请重试';
      setState(() {
        _rules = const [];
        _loading = false;
        _message = message;
        _restricted = RegExp(r'权限|无权|拒绝|登录|验证|绑定|不存在|未提供').hasMatch(message);
      });
    }
  }

  Widget _ruleCard(ForumCreditRule rule, int index) {
    final scheme = Theme.of(context).colorScheme;
    final details = rule.columns.entries.where((entry) =>
        entry.value.isNotEmpty &&
        !const {'动作名称', '行为', '操作'}.contains(entry.key));
    return Card(
      key: ValueKey('forum-credit-rule-$index'),
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rule.action, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final entry in details)
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${entry.key}  ',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                    TextSpan(
                        text: entry.value,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const SizedBox(
        key: ValueKey('forum-credit-rules-loading'),
        height: 160,
        child: Center(child: AppLoadingIndicator()),
      );
    }
    if (_message != null) {
      return Column(
        key: const ValueKey('forum-credit-rules-error'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_restricted ? Icons.lock_outline : Icons.cloud_off_outlined,
              size: 36, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(_restricted ? '积分规则暂不可用' : '加载失败',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(_message!, textAlign: TextAlign.center),
          if (!_accountChanged) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('forum-credit-rules-retry'),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ],
      );
    }
    if (_rules.isEmpty) {
      return const Padding(
        key: ValueKey('forum-credit-rules-empty'),
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('网站当前没有提供本版积分规则', textAlign: TextAlign.center),
      );
    }
    final columns =
        <String>{for (final rule in _rules) ...rule.columns.keys}.toList();
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    if (!desktop || columns.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _rules.length; i++) _ruleCard(_rules[i], i)
        ],
      );
    }
    final headingStyle = DataTableTheme.of(context).headingTextStyle ??
        Theme.of(context).textTheme.titleSmall;
    var headingHeight = 64.0;
    for (final column in columns) {
      final painter = TextPainter(
        text: TextSpan(text: column, style: headingStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: 110);
      if (painter.height + 24 > headingHeight) {
        headingHeight = painter.height + 24;
      }
      painter.dispose();
    }
    return Scrollbar(
      controller: _tableScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _tableScroll,
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const ValueKey('forum-credit-rules-table'),
          columnSpacing: 20,
          horizontalMargin: 12,
          headingRowHeight: headingHeight,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 72,
          columns: [
            for (final column in columns)
              DataColumn(
                  label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(column, softWrap: true),
              )),
          ],
          rows: [
            for (final rule in _rules)
              DataRow(cells: [
                for (final column in columns)
                  DataCell(Text(rule.columns[column]?.isNotEmpty == true
                      ? rule.columns[column]!
                      : '—')),
              ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('forum-credit-rules-dialog'),
      title: Row(children: [
        Icon(Icons.monetization_on_outlined, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
            child: Text('${widget.name} · 本版积分规则',
                style: theme.textTheme.titleMedium)),
      ]),
      content: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .65),
        child: SizedBox(
          width: 840,
          child: SingleChildScrollView(child: _content()),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('forum-credit-rules-close'),
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        )
      ],
    );
  }
}
