import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/preload_service.dart';
import '../models/horn_message.dart';
import '../models/site_stats.dart';
import '../pages/thread_detail_page.dart';
import '../pages/user_space_page.dart';
import 'thread_card.dart';

/// 苦力怕论坛「土豪霸屏」置顶横幅组件与全站数据统计栏（完美还原网页端，未检测到霸屏时严格隐藏）
class TuhaoBannerWidget extends StatefulWidget {
  final int? authorUid;
  final String? authorName;
  final String? avatarUrl;
  final String? headline;
  final String? linkUrl;
  final int? tid;
  final SiteStats? stats;
  final int? todayPosts;
  final int? yesterdayPosts;
  final int? totalPosts;
  final int? totalMembers;
  final bool showStatsBar;

  const TuhaoBannerWidget({
    super.key,
    this.authorUid,
    this.authorName,
    this.avatarUrl,
    this.headline,
    this.linkUrl,
    this.tid,
    this.stats,
    this.todayPosts,
    this.yesterdayPosts,
    this.totalPosts,
    this.totalMembers,
    this.showStatsBar = true,
  });

  @override
  State<TuhaoBannerWidget> createState() => _TuhaoBannerWidgetState();
}

class _TuhaoBannerWidgetState extends State<TuhaoBannerWidget> {
  bool _dismissed = false;
  HornMessage? _tuhaoMessage;
  SiteStats? _siteStats;

  @override
  void initState() {
    super.initState();
    _siteStats = widget.stats ?? PreloadService.instance.get<SiteStats>('site_stats');
    _loadTuhaoBannerData();
    _loadHornData();
    if (widget.showStatsBar) {
      _loadStatsData();
    }
  }

  @override
  void didUpdateWidget(covariant TuhaoBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stats != null && widget.stats != _siteStats) {
      setState(() {
        _siteStats = widget.stats;
      });
    }
  }

  void _loadTuhaoBannerData() {
    KlpbbsApi.getTuhaoBanner().then((tuhao) {
      if (mounted && tuhao != null && tuhao.message.isNotEmpty) {
        setState(() {
          int uid = tuhao.uid;
          if (uid <= 0) {
            final uidM = RegExp(r'/avatar/\d+/(\d+)/(\d+)/(\d+)').firstMatch(tuhao.avatarUrl);
            if (uidM != null) {
              final uidStr = '${uidM.group(1)}${uidM.group(2)}${uidM.group(3)}';
              uid = int.tryParse(uidStr) ?? 0;
            }
          }
          _tuhaoMessage = HornMessage(
            id: 999999,
            author: tuhao.author,
            avatarUrl: tuhao.avatarUrl,
            uid: uid > 0 ? uid : null,
            content: tuhao.message,
            linkUrl: tuhao.linkUrl,
            tag: '土豪',
          );
        });
      }
    }).catchError((_) {});
  }

  void _loadStatsData() {
    KlpbbsApi.getSiteStats().then((stats) {
      if (mounted && !stats.isEmpty) {
        setState(() {
          _siteStats = stats;
        });
      }
    }).catchError((_) {});
  }

  void _loadHornData() {
    final cached = PreloadService.instance.get<List<HornMessage>>('horn_messages');
    if (cached != null && cached.isNotEmpty) {
      _applyHornList(cached);
    }
    KlpbbsApi.getHornMessages().then((list) {
      if (mounted && list.isNotEmpty) {
        _applyHornList(list);
      }
    }).catchError((_) {});
  }

  void _applyHornList(List<HornMessage> list) {
    // 严格查找带有土豪或霸屏标识的广播（未检测到时不设置，避免误报）
    try {
      final tuhao = list.firstWhere(
        (m) =>
            m.tag == '土豪' ||
            m.tag == '霸屏' ||
            (m.tag != null && (m.tag!.contains('土豪') || m.tag!.contains('霸屏'))) ||
            m.content.contains('【土豪】') ||
            m.content.contains('土豪霸屏'),
      );
      if (mounted) {
        setState(() {
          _tuhaoMessage = tuhao;
        });
      }
    } catch (_) {
      // 未检测到土豪霸屏广播，保持为空
    }
  }

  void _openTarget() async {
    final targetTid = widget.tid ??
        _extractTid(widget.linkUrl ?? '') ??
        (_tuhaoMessage?.linkUrl != null ? _extractTid(_tuhaoMessage!.linkUrl!) : null) ??
        (_tuhaoMessage?.content != null ? _extractTid(_tuhaoMessage!.content) : null);
    if (targetTid != null && targetTid > 0) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: targetTid)),
      );
      return;
    }
    final url = _resolveLinkUrl();
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  String _resolveLinkUrl() {
    if (widget.linkUrl != null && widget.linkUrl!.isNotEmpty) {
      return widget.linkUrl!;
    }
    if (_tuhaoMessage != null) {
      if (_tuhaoMessage!.linkUrl != null && _tuhaoMessage!.linkUrl!.isNotEmpty) {
        return _tuhaoMessage!.linkUrl!;
      }
      final urlM = RegExp(r'https?://(?:www\.)?klpbbs\.com/(?:thread-\d+-\d+-\d+\.html|forum\.php\?[^"\s<>\x27]+)').firstMatch(_tuhaoMessage!.content) ??
          RegExp(r'https?://[^\s"<>\x27]+').firstMatch(_tuhaoMessage!.content);
      if (urlM != null) {
        return urlM.group(0)!;
      }
    }
    return '';
  }

  int? _extractTid(String url) {
    if (url.isEmpty) return null;
    final reg = RegExp(r'thread-(\d+)|[?&]tid=(\d+)').firstMatch(url);
    if (reg != null) {
      return int.tryParse(reg.group(1) ?? reg.group(2) ?? '');
    }
    return null;
  }

  void _openAuthor() {
    final uid = widget.authorUid ?? _tuhaoMessage?.uid ?? 0;
    if (uid > 0) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => UserSpacePage(uid: uid)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 严格检测：必须有来自服务器的土豪霸屏数据或外部显式传入 headline，未检测到时绝对不显示土豪横幅
    final bool hasTuhao = !_dismissed &&
        ((widget.headline != null && widget.headline!.isNotEmpty) || _tuhaoMessage != null);

    Widget? tuhaoBanner;
    if (hasTuhao) {
      final authorName = widget.authorName ?? _tuhaoMessage?.author ?? '';
      final uid = widget.authorUid ?? _tuhaoMessage?.uid ?? 0;
      final avatarUrl = widget.avatarUrl ?? _tuhaoMessage?.avatarUrl ?? '';
      final finalAvatarUrl = avatarUrl.isNotEmpty
          ? avatarUrl
          : (uid > 0 ? AppConfig.avatarUrl(uid, size: 'middle') : '');

      String headline = widget.headline ?? '';
      if (headline.isEmpty && _tuhaoMessage != null) {
        // 剥离 HTML 标签、内联样式、URL、以及土豪字样与表情
        String text = _tuhaoMessage!.content
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll(RegExp(r'style="[^"]*"'), '')
            .replaceAll(RegExp(r"style='[^']*'"), '')
            .replaceAll(RegExp(r'https?://\S+'), '')
            .replaceAll(RegExp(r'[💰土豪]'), '')
            .trim();
        text = text.replaceAll(RegExp(r'[a-zA-Z0-9_-]+="[^"]*"'), '').trim();
        text = text.replaceAll(RegExp(r'[a-zA-Z0-9_-]+:[^;]+;'), '').trim();
        if (text.isNotEmpty) {
          headline = text;
        }
      }
      // 确保宣传语中彻底清除可能残留的 URL 字符串
      headline = headline.replaceAll(RegExp(r'https?://\S+'), '').trim();

      final linkUrl = _resolveLinkUrl();

      if (headline.isNotEmpty && authorName.isNotEmpty) {
        tuhaoBanner = GestureDetector(
          onTap: _openTarget,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF9CF42),
                  Color(0xFFF2A900),
                  Color(0xFFE28B00),
                ],
              ),
            ),
            child: Stack(
              children: [
                // 背景装饰金币钱袋
                Positioned(left: 24, top: 22, child: _buildBag(18, 0.75)),
                Positioned(left: 80, top: 12, child: _buildBag(14, 0.55)),
                Positioned(left: 18, bottom: 28, child: _buildBag(17, 0.70)),
                Positioned(right: 28, top: 26, child: _buildBag(18, 0.75)),
                Positioned(right: 76, top: 16, child: _buildBag(14, 0.55)),
                Positioned(right: 32, bottom: 22, child: _buildBag(16, 0.70)),
                Positioned(left: 130, bottom: 8, child: _buildBag(13, 0.45)),
                Positioned(right: 140, bottom: 10, child: _buildBag(13, 0.45)),

                // 右上角关闭按钮
                Positioned(
                  top: 10,
                  right: 12,
                  child: GestureDetector(
                    onTap: () => setState(() => _dismissed = true),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withAlpha(90),
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // 内容主体
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 土豪头像（支持全站设置的头像形状与挂件头像框）
                      if (finalAvatarUrl.isNotEmpty || uid > 0)
                        UserAvatarWidget(
                          uid: uid > 0 ? uid : null,
                          author: authorName,
                          avatarUrl: finalAvatarUrl,
                          faceUrl: UserAvatarWidget.sanitizeFaceUrl(_tuhaoMessage?.faceUrl),
                          size: 52,
                          onTap: _openAuthor,
                        ),
                      const SizedBox(height: 6),

                      // 土豪头衔
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.monetization_on_rounded,
                            size: 15,
                            color: Color(0xFFC67D00),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '土豪 $authorName 驾到',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4E2600),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.monetization_on_rounded,
                            size: 15,
                            color: Color(0xFFC67D00),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // 粗体核心宣传语
                      Text(
                        headline,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF261200),
                          height: 1.25,
                        ),
                      ),
                      if (linkUrl.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        // 链接地址
                        Text(
                          linkUrl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4A2600),
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF4A2600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    // 全站四大核心统计数据栏
    Widget? statsBar;
    if (widget.showStatsBar) {
      final stats = _siteStats ?? widget.stats;
      if (stats != null && !stats.isEmpty) {
        final todayVal = widget.todayPosts ?? stats.todayPosts;
        final yesterdayVal = widget.yesterdayPosts ?? stats.yesterdayPosts;
        final totalPostsVal = widget.totalPosts ?? stats.totalPosts;
        final totalMembersVal = widget.totalMembers ?? stats.totalMembers;

        statsBar = Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withAlpha(40),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              _buildStatItem('今日', '$todayVal', theme),
              _buildDivider(theme),
              _buildStatItem('昨日', '$yesterdayVal', theme),
              _buildDivider(theme),
              _buildStatItem('帖子', '$totalPostsVal', theme),
              _buildDivider(theme),
              _buildStatItem('会员', '$totalMembersVal', theme),
            ],
          ),
        );
      }
    }

    if (tuhaoBanner == null && statsBar == null) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tuhaoBanner != null) tuhaoBanner,
          if (statsBar != null) statsBar,
        ],
      ),
    );
  }

  Widget _buildBag(double size, double opacity) {
    return Icon(
      Icons.monetization_on_rounded,
      size: size,
      color: const Color(0xFFC67D00).withAlpha((255 * opacity.clamp(0.0, 1.0)).round()),
    );
  }


  Widget _buildStatItem(String label, String value, ThemeData theme) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Container(
      width: 1,
      height: 22,
      color: theme.colorScheme.outlineVariant.withAlpha(40),
    );
  }
}
