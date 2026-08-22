import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/preload_service.dart';
import '../models/horn_message.dart';
import '../pages/thread_detail_page.dart';
import '../pages/user_space_page.dart';

/// 苦力怕论坛「土豪霸屏」置顶横幅组件与全站数据统计栏（完美还原网页端 forum.php?forumlist=1&mobile=2）
class TuhaoBannerWidget extends StatefulWidget {
  final int? authorUid;
  final String? authorName;
  final String? avatarUrl;
  final String? headline;
  final String? linkUrl;
  final int? tid;
  final int todayPosts;
  final int yesterdayPosts;
  final int totalPosts;
  final int totalMembers;

  const TuhaoBannerWidget({
    super.key,
    this.authorUid,
    this.authorName,
    this.avatarUrl,
    this.headline,
    this.linkUrl,
    this.tid,
    this.todayPosts = 119,
    this.yesterdayPosts = 194,
    this.totalPosts = 10310628,
    this.totalMembers = 2317216,
  });

  @override
  State<TuhaoBannerWidget> createState() => _TuhaoBannerWidgetState();
}

class _TuhaoBannerWidgetState extends State<TuhaoBannerWidget> {
  bool _dismissed = false;
  HornMessage? _tuhaoMessage;

  @override
  void initState() {
    super.initState();
    _loadHornData();
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
    // 查找土豪或霸屏相关的广播，默认取第一条
    final tuhao = list.firstWhere(
      (m) =>
          m.content.contains('土豪') ||
          m.content.contains('缔造者') ||
          m.author.contains('缔造者') ||
          (m.tag != null && m.tag!.contains('土豪')),
      orElse: () => list.first,
    );
    setState(() {
      _tuhaoMessage = tuhao;
    });
  }

  void _openTarget() {
    final targetTid = widget.tid ??
        (_tuhaoMessage?.linkUrl != null
            ? _extractTid(_tuhaoMessage!.linkUrl!)
            : 173255);
    if (targetTid != null && targetTid > 0) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: targetTid)),
      );
      return;
    }
    final url = widget.linkUrl ?? _tuhaoMessage?.linkUrl ?? 'https://klpbbs.com/thread-173255-1-1.html';
    final tid = _extractTid(url);
    if (tid != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: tid)),
      );
    }
  }

  int? _extractTid(String url) {
    final reg = RegExp(r'thread-(\d+)|tid=(\d+)').firstMatch(url);
    if (reg != null) {
      return int.tryParse(reg.group(1) ?? reg.group(2) ?? '');
    }
    return null;
  }

  void _openAuthor() {
    final uid = widget.authorUid ?? _tuhaoMessage?.uid ?? 13134;
    if (uid > 0) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => UserSpacePage(uid: uid)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final authorName = widget.authorName ?? _tuhaoMessage?.author ?? '缔造者';
    final uid = widget.authorUid ?? _tuhaoMessage?.uid ?? 13134;
    final avatarUrl = widget.avatarUrl ?? _tuhaoMessage?.avatarUrl ?? '';
    final finalAvatarUrl = avatarUrl.isNotEmpty ? avatarUrl : AppConfig.avatarUrl(uid, size: 'middle');

    String headline = widget.headline ?? '';
    if (headline.isEmpty && _tuhaoMessage != null) {
      // 剥离 HTML 标签、内联样式、URL、以及土豪字样与表情
      String text = _tuhaoMessage!.content
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'style="[^"]*"'), '')
          .replaceAll(RegExp(r'style=\x27[^\x27]*\x27'), '')
          .replaceAll(RegExp(r'https?://\S+'), '')
          .replaceAll(RegExp(r'[💰土豪]'), '')
          .trim();
      text = text.replaceAll(RegExp(r'[a-zA-Z0-9_-]+="[^"]*"'), '').trim();
      text = text.replaceAll(RegExp(r'[a-zA-Z0-9_-]+:[^;]+;'), '').trim();
      if (text.isNotEmpty) {
        headline = text;
      }
    }
    if (headline.isEmpty) {
      headline = '热烈庆祝缔造者入坛六周年（点击进入领取铁粒）';
    }

    String linkUrl = widget.linkUrl ?? '';
    if (linkUrl.isEmpty && _tuhaoMessage != null) {
      final urlM = RegExp(r'https?://(?:www\.)?klpbbs\.com/(?:thread-\d+-\d+-\d+\.html|forum\.php\?[^"\s<>\x27]+)').firstMatch(_tuhaoMessage!.content) ??
          RegExp(r'https?://[^\s"<>\x27]+').firstMatch(_tuhaoMessage!.content);
      if (urlM != null) {
        linkUrl = urlM.group(0)!;
      } else if (_tuhaoMessage!.linkUrl != null && _tuhaoMessage!.linkUrl!.isNotEmpty) {
        linkUrl = _tuhaoMessage!.linkUrl!;
      }
    }
    if (linkUrl.isEmpty) {
      linkUrl = 'https://klpbbs.com/thread-173255-1-1.html';
    }

    return Column(
      children: [
        if (!_dismissed)
          GestureDetector(
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
                        // 圆形头像
                        GestureDetector(
                          onTap: _openAuthor,
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: finalAvatarUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _fallbackAvatar(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // 土豪头衔
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('💰', style: TextStyle(fontSize: 13)),
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
                            const Text('💰', style: TextStyle(fontSize: 13)),
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
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 全站四大核心统计数据栏（今日/昨日/帖子/会员）
        Container(
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
              _buildStatItem('今日', '${widget.todayPosts}', theme),
              _buildDivider(theme),
              _buildStatItem('昨日', '${widget.yesterdayPosts}', theme),
              _buildDivider(theme),
              _buildStatItem('帖子', '${widget.totalPosts}', theme),
              _buildDivider(theme),
              _buildStatItem('会员', '${widget.totalMembers}', theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBag(double size, double opacity) {
    return Opacity(
      opacity: opacity,
      child: Text('💰', style: TextStyle(fontSize: size)),
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      color: Colors.black26,
      child: const Center(
        child: Icon(Icons.person, color: Colors.white, size: 28),
      ),
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
