import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/comiis_parser.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/write_confirm.dart';
import '../models/post_floor.dart';
import '../models/smiley.dart';
import '../widgets/desktop_shortcuts.dart';
import '../widgets/bili_video_player.dart';
import '../widgets/general_audio_player.dart';
import '../widgets/general_video_player.dart';
import '../widgets/discuz_post_renderer.dart';
import '../widgets/netease_music_player.dart';
import '../widgets/global_nav.dart';
import '../widgets/inline_html_text.dart';
import '../widgets/favorite_dialog.dart';
import '../widgets/report_dialog.dart';
import '../widgets/thread_card.dart';
import 'login_page.dart';
import 'post_page.dart';
import 'search_page.dart';
import 'thread_list_page.dart';
import 'user_space_page.dart';

/// 帖子详情（楼层列表）
///
/// 正文以纯文本 + 图片网格展示（扩展点：可替换为富文本/WebView 渲染）。
class ThreadDetailPage extends StatefulWidget {
  final int tid;
  final bool showBackButton;

  const ThreadDetailPage({
    super.key,
    required this.tid,
    this.showBackButton = true,
  });

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage> {
  late Future<
    ({
      String title,
      List<PostFloor> floors,
      int totalPages,
      int firstAuthorCredits,
      String publishDate,
      String lastReplyDate,
      String forumName,
      int? fid,
      List<String> breadcrumbs,
      String? typeName,
      int? typeid,
      int likes,
      int favorites,
      int views,
      int replies,
      List<String> tags,
      String? stamp,
      String? stampUrl,
      String? coverUrl,
      bool isFavorited,
      bool isLiked,
      int? favid,
    })
  >
  _future;
  final _scrollCtrl = ScrollController();
  int _page = 1;
  bool _scrolled = false;
  String _title = '';
  String? _stamp;
  String? _stampUrl;
  bool _liked = false;
  bool _favored = false;
  int? _favid;
  int? _myUid;
  int? _firstAuthorUid;
  int _likes = 0;
  int _favorites = 0;
  int _views = 0;
  int _replies = 0;
  List<String> _tags = const [];
  List<PostFloor> _floors = const [];

  @override
  void initState() {
    super.initState();
    AppConfig.instance.addListener(_onConfigChanged);
    _loadAndInit();
    KlpbbsApi.getMyUid()
        .then((uid) {
          if (mounted) setState(() => _myUid = uid);
        })
        .catchError((_) {});
    // AppBar 标题滚动折叠：滚动超过 120px 显示帖子标题
    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.offset > 120;
      if (show != _scrolled) setState(() => _scrolled = show);
    });
  }

  void _onConfigChanged() {
    if (mounted) setState(() {});
  }

  void _loadAndInit({bool forceRefresh = false}) {
    setState(() {
      _future = KlpbbsApi.getThread(widget.tid, page: _page, forceRefresh: forceRefresh).then((r) async {
        final prefs = await SharedPreferences.getInstance();
        if (mounted) {
          setState(() {
            _applyThreadData(r, prefs);
          });
        }
        return r;
      });
    });
  }

  void _applyThreadData(dynamic r, SharedPreferences prefs) {
    _title = r.title;
    // 仅在第1页记录主题作者（楼主）的 uid，避免翻页后被回复者 uid 覆盖
    if (_page == 1 && r.floors.isNotEmpty) {
      _firstAuthorUid = r.floors.first.uid;
    }

    final likedList = prefs.getStringList('liked_tids') ?? const [];
    final isLocalLiked = likedList.contains('${widget.tid}');
    final isServerLiked = (r.isLiked == true) || (r.floors.isNotEmpty && r.floors.first.isLiked && _page == 1);
    if (_page == 1) {
      _liked = isServerLiked || isLocalLiked;
      _likes = r.likes;
    }

    final favList = prefs.getStringList('fav_tids') ?? const [];
    final isLocalFav = favList.contains('${widget.tid}');
    if (DioClient.isLoggedIn) {
      _favored = r.isFavorited || isLocalFav;
      _favid = r.favid;
      if (r.isFavorited) {
        _saveState('fav_tids', '${widget.tid}', true);
      }
    } else {
      _favored = isLocalFav;
    }

    _favorites = r.favorites;
    _views = r.views;
    _replies = r.replies;
    if (_page == 1 || _tags.isEmpty) {
      _tags = r.tags;
    }
    _floors = r.floors;
    if (_page == 1 || _stamp == null) {
      _stamp = r.stamp;
      _stampUrl = r.stampUrl;
    }
  }

  @override
  void dispose() {
    AppConfig.instance.removeListener(_onConfigChanged);
    // 退出帖子页时停止 B站/网易云/通用音频与视频内嵌播放器
    BiliVideoPlayer.stopAll();
    NetEaseMusicPlayer.stopAll();
    GeneralAudioPlayer.stopAll();
    GeneralVideoPlayer.stopAll();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    _loadAndInit(forceRefresh: true);
  }

  @override
  void didUpdateWidget(covariant ThreadDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tid != widget.tid) {
      _page = 1;
      _reload();
    }
  }

  Widget _buildStampBadge(String stamp) {
    if (stamp == '美图') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE91E63), Color(0xFFFF4081)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE91E63).withAlpha(90),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_rounded,
              size: 13,
              color: Colors.white,
            ),
            SizedBox(width: 3.5),
            Text(
              '美图',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }
    if (stamp == '荐' || stamp.contains('推荐')) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B35), Color(0xFFFF9E80)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6B35).withAlpha(90),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.thumb_up_alt_rounded,
              size: 12.5,
              color: Colors.white,
            ),
            SizedBox(width: 3.5),
            Text(
              '推荐',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    if (stamp == '精' || stamp.contains('精华')) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withAlpha(90),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              size: 13.5,
              color: Colors.white,
            ),
            SizedBox(width: 3.5),
            Text(
              '精华',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    if (stamp == '原创') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8E24AA), Color(0xFFBA68C8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8E24AA).withAlpha(90),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.brush_rounded,
              size: 12.5,
              color: Colors.white,
            ),
            SizedBox(width: 3.5),
            Text(
              '原创',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    if (stamp == '优秀') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00ACC1), Color(0xFF4DD0E1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00ACC1).withAlpha(90),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.military_tech_rounded,
              size: 13,
              color: Colors.white,
            ),
            SizedBox(width: 3.5),
            Text(
              '优秀',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xFF43A047),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        stamp,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 保存本地状态
  Future<void> _saveState(String key, String tid, bool add) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(key) ?? <String>[];
      if (add && !list.contains(tid)) {
        list.add(tid);
        await prefs.setStringList(key, list);
      } else if (!add) {
        list.remove(tid);
        await prefs.setStringList(key, list);
      }
    } catch (_) {}
  }

  Future<void> _onLike() async {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先登录论坛账号后再进行点赞'),
          action: SnackBarAction(
            label: '去登录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
          ),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    final nextLiked = !_liked;
    setState(() {
      _liked = nextLiked;
      _likes += nextLiked ? 1 : (_likes > 0 ? -1 : 0);
      if (_floors.isNotEmpty) {
        final f = _floors.first;
        _floors = [
          f.copyWith(
            isLiked: nextLiked,
            likes: nextLiked ? (f.likes + 1) : (f.likes > 0 ? f.likes - 1 : 0),
          ),
          ..._floors.sublist(1),
        ];
      }
    });
    _saveState('liked_tids', '${widget.tid}', nextLiked);

    try {
      final firstPid = _floors.isNotEmpty ? _floors.first.pid : null;
      final res = await KlpbbsApi.recommendThread(
        widget.tid,
        support: nextLiked,
        pid: firstPid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.message.isNotEmpty
                  ? res.message
                  : (nextLiked ? '点赞成功 +1' : '已取消点赞'),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        // 操作后立即拉取网页最新数据，与网页状态绝对同步
        _loadAndInit(forceRefresh: true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextLiked ? '点赞已记录' : '已取消点赞'),
            duration: const Duration(seconds: 1),
          ),
        );
        _loadAndInit(forceRefresh: true);
      }
    }
  }

  Future<void> _onFavorite({bool openDialog = false}) async {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先登录论坛账号后再进行收藏'),
          action: SnackBarAction(
            label: '去登录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
          ),
        ),
      );
      return;
    }

    if (openDialog) {
      final author = _floors.isNotEmpty ? _floors.first.author : '';
      final res = await FavoriteDialog.show(
        context,
        tid: widget.tid,
        title: _title,
        author: author,
        isFavorited: _favored,
        favid: _favid,
        onFavoritedChanged: (fav) {
          setState(() {
            _favored = fav;
            _favorites += fav ? 1 : (_favorites > 0 ? -1 : 0);
          });
          _saveState('fav_tids', '${widget.tid}', fav);
          _loadAndInit(forceRefresh: true);
        },
      );
      if (res != null) {
        setState(() {
          _favored = res;
          _favorites += res ? 1 : (_favorites > 0 ? -1 : 0);
        });
        _saveState('fav_tids', '${widget.tid}', res);
      }
      return;
    }

    HapticFeedback.lightImpact();
    final nextFav = !_favored;
    setState(() {
      _favored = nextFav;
      _favorites += nextFav ? 1 : (_favorites > 0 ? -1 : 0);
    });
    _saveState('fav_tids', '${widget.tid}', nextFav);

    try {
      if (nextFav) {
        final res = await KlpbbsApi.favoriteThread(widget.tid);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.message.isNotEmpty ? res.message : '已收藏'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        final res = await KlpbbsApi.unfavoriteThread(widget.tid, favid: _favid);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.message.isNotEmpty ? res.message : '已取消收藏'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
      _loadAndInit(forceRefresh: true);
    } catch (_) {}
  }

  void _showLikedUsersDialog([List<PostFloor>? floors]) {
    final list = floors ?? _floors;
    final rewards = list.isNotEmpty ? list.first.rewards : const [];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.35,
        builder: (c, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.thumb_up, size: 20, color: Color(0xFF1976D2)),
                    const SizedBox(width: 8),
                    Text(
                      '点赞与评分用户详情 (${rewards.isNotEmpty ? rewards.length : _likes})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: rewards.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.thumb_up_alt_outlined, size: 48, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text(
                              _likes > 0 ? '已有 $_likes 人为此帖点赞推荐' : '暂无点赞或评分记录',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: rewards.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = rewards[i];
                          return ListTile(
                            leading: UserAvatarWidget(
                              uid: r.uid ?? 0,
                              author: r.user,
                              size: 40,
                              faceUrl: UserAvatarWidget.sanitizeFaceUrl(r.avatar),
                            ),
                            title: Text(
                              r.user,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              r.reason.isNotEmpty ? r.reason : '为楼主送上支持！',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.orange.withAlpha(30),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                r.amount,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[800],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              if (r.uid != null && r.uid! > 0) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => UserSpacePage(uid: r.uid!)),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onReplyGlobal() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostPage(tid: widget.tid, initialMessage: null),
      ),
    );
  }

  void _goPage(int page) {
    setState(() {
      _page = page;
      _future = KlpbbsApi.getThread(widget.tid, page: page).then((r) async {
        final prefs = await SharedPreferences.getInstance();
        if (mounted) {
          setState(() {
            _applyThreadData(r, prefs);
          });
        }
        return r;
      });
    });
    // 分页后回到顶部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    });
  }

  /// 跳转指定页（输入页码）
  Future<void> _jumpPage(int total) async {
    final ctrl = TextEditingController();
    final target = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到第几页'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '1 - $total',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final p = int.tryParse(v);
            if (p != null) Navigator.of(ctx).pop(p);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(ctrl.text.trim());
              if (p != null) Navigator.of(ctx).pop(p);
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (target != null && target >= 1 && target <= total) {
      _goPage(target);
    }
  }

  Future<void> _onMenuAction(String action) async {
    if (!context.mounted) return;
    switch (action) {
      case 'edit':
        final navigator = Navigator.of(context);
        final confirmed = await confirmWrite(context, '编辑帖子');
        if (!confirmed || !mounted) return;
        // 预填当前标题/内容（简化：用帖子首楼）
        final snap = await _future;
        if (!mounted) return;
        final floors = snap.floors;
        final first = floors.isNotEmpty ? floors.first : null;
        final ok = await navigator.push<bool>(
          MaterialPageRoute(
            builder: (_) => PostPage(
              fid: 2,
              tid: widget.tid,
              pid: first?.pid ?? 1,
              editSubject: '',
              editMessage: '',
            ),
          ),
        );
        if (ok == true && mounted) _reload();
        break;
      case 'delete':
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        final confirmed = await confirmWrite(context, '删除帖子');
        if (!confirmed || !mounted) return;
        try {
          final ok = await KlpbbsApi.deletePost(2, widget.tid, 1);
          messenger.showSnackBar(
            SnackBar(content: Text(ok ? '已删除' : '删除失败（可能无权限）')),
          );
          if (ok && mounted) navigator.pop();
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('删除异常：$e')));
        }
        break;
      case 'report':
        final firstFloor = _floors.isNotEmpty ? _floors.first : null;
        await ReportDialog.show(
          context,
          tid: widget.tid,
          pid: firstFloor?.pid ?? 0,
          author: firstFloor?.author ?? '楼主',
          floorIndex: 0,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DesktopShortcutsWrapper(
      onRefresh: _reload,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: widget.showBackButton,
          leading: widget.showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          title: Text(
            _scrolled && _title.isNotEmpty ? _title : '帖子详情',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (widget.showBackButton) const GlobalNavButton(),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新帖子 (F5)',
              onPressed: _reload,
            ),
            IconButton(
              icon: Icon(
                _liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                color: _liked ? Theme.of(context).colorScheme.primary : null,
              ),
              tooltip: _likes > 0 ? '已有点赞: $_likes' : '点赞帖子',
              onPressed: _onLike,
            ),
            IconButton(
              icon: Icon(
                _favored ? Icons.star : Icons.star_outline,
                color: _favored ? Colors.amber.shade700 : null,
              ),
              tooltip: _favored ? '已收藏 (点击取消/长按管理)' : '收藏帖子',
              onPressed: () => _onFavorite(openDialog: false),
            ),
            IconButton(
              icon: const Icon(Icons.reply),
              tooltip: '回复',
              onPressed: () async {
                if (!context.mounted) return;
                final confirmed = await confirmWrite(context, '回复');
                if (!confirmed || !context.mounted) return;
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => PostPage(tid: widget.tid)),
                );
                if (ok == true && mounted) _reload();
              },
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: '分享',
              onPressed: () async {
                final url = '${AppConfig.baseUrl}thread-${widget.tid}-1-1.html';
                final shareText = _title.isNotEmpty ? '$_title $url' : url;
                await Clipboard.setData(ClipboardData(text: shareText));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('标题+链接已复制')));
                }
              },
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (v) => _onMenuAction(v),
              itemBuilder: (_) => [
                if (_myUid != null &&
                    _firstAuthorUid != null &&
                    _myUid == _firstAuthorUid) ...[
                  const PopupMenuItem(value: 'edit', child: Text('编辑帖子')),
                  const PopupMenuItem(value: 'delete', child: Text('删除帖子')),
                ],
                const PopupMenuItem(value: 'report', child: Text('举报')),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            FutureBuilder<
              ({
                String title,
                List<PostFloor> floors,
                int totalPages,
                int firstAuthorCredits,
                String publishDate,
                String lastReplyDate,
                String forumName,
                int? fid,
                List<String> breadcrumbs,
                String? typeName,
                int? typeid,
                int likes,
                int favorites,
                int views,
                int replies,
                List<String> tags,
                String? stamp,
                String? stampUrl,
                String? coverUrl,
                bool isFavorited,
                bool isLiked,
                int? favid,
              })
            >(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('加载失败：${snap.error}', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }
                final data = snap.data;
                final title = data?.title ?? '';
                final floors = data?.floors ?? const <PostFloor>[];
                if (floors.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('帖子内容加载为空'),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _reload,
                          child: const Text('重新加载'),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: ListView(
                        cacheExtent: 800.0,
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.only(bottom: 48),
                        children: [
                          if (title.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 顶部面包屑导航（如 论坛 › 灵感交流 › 闲聊讨论）
                                  if ((data?.breadcrumbs ?? const []).isNotEmpty ||
                                      (data?.forumName ?? '').isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          Icon(
                                            Icons.home_outlined,
                                            size: 14,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant.withAlpha(200),
                                          ),
                                          Text(
                                            '论坛',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.onSurfaceVariant,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                          for (final bc in (data?.breadcrumbs ?? [
                                            if ((data?.forumName ?? '').isNotEmpty)
                                              data!.forumName,
                                          ])) ...[
                                            Icon(
                                              Icons.chevron_right,
                                              size: 14,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.outlineVariant,
                                            ),
                                            InkWell(
                                              onTap: () {
                                                if (data?.fid != null) {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => ThreadListPage(
                                                        fid: data!.fid!,
                                                        title: bc,
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                      .withAlpha(40),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  bc,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 12,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  // 主题标签与图章行（美图/精/荐/原创/分类）
                                  Builder(
                                    builder: (context) {
                                      final currentStamp = data?.stamp ?? _stamp;
                                      final typeName = data?.typeName;
                                      if ((currentStamp == null || currentStamp.isEmpty) &&
                                          (typeName == null || typeName.isEmpty)) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            if (currentStamp != null && currentStamp.isNotEmpty)
                                              _buildStampBadge(currentStamp),
                                            if (typeName != null && typeName.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                      .withAlpha(120),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  typeName,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  Text(
                                    title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          height: 1.35,
                                          fontSize: 18,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          // 发布日期 + 最近回复日期 + 浏览/回复量
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                if ((data?.publishDate ?? '').isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.schedule,
                                        size: 13,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant.withAlpha(190),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '发布 ${data!.publishDate}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant.withAlpha(200),
                                              fontSize: 11.5,
                                            ),
                                      ),
                                    ],
                                  ),
                                if ((data?.lastReplyDate ?? '').isNotEmpty)
                                  Text(
                                    '最近回复 ${data!.lastReplyDate}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant.withAlpha(200),
                                          fontSize: 11.5,
                                        ),
                                  ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.visibility_outlined,
                                      size: 13,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(190),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${(_views > 0 ? _views : (data?.views ?? 0))} 浏览 · ${(_replies > 0 ? _replies : (data?.replies ?? (floors.length > 1 ? floors.length - 1 : 0)))} 回复 · ${(_likes > 0 ? _likes : (data?.likes ?? 0))} 点赞',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant.withAlpha(200),
                                            fontSize: 11.5,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          for (var i = 0; i < floors.length; i++) ...[
                            () {
                              final isFirstFloor = (_page == 1 && i == 0);
                              final isThreadAuthor = floors[i].isThreadAuthor ||
                                  (_firstAuthorUid != null && floors[i].uid == _firstAuthorUid);
                              return _FloorView(
                                floor: floors[i],
                                index: i,
                                page: _page,
                                tid: widget.tid,
                                fid: data?.fid,
                                isFirstFloor: isFirstFloor,
                                isThreadAuthor: isThreadAuthor,
                                stamp: isFirstFloor ? (data?.stamp ?? _stamp) : null,
                                stampUrl: isFirstFloor ? (data?.stampUrl ?? _stampUrl) : null,
                                isLiked: isFirstFloor ? _liked : null,
                                likesCount: isFirstFloor ? _likes : null,
                                onLikeToggle: isFirstFloor ? _onLike : null,
                                onReload: _reload,
                              );
                            }(),
                            // 首楼下方展示主题标签（仅第1页首楼且有标签时展示）
                            if (_page == 1 && i == 0 && _tags.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.local_offer_outlined,
                                      size: 14,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    Text(
                                      '标签：',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                    ),
                                    for (final tag in _tags)
                                      ActionChip(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        labelPadding: EdgeInsets.zero,
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withAlpha(45),
                                        side: BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withAlpha(70),
                                          width: 0.6,
                                        ),
                                        label: Text(
                                          tag,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(context).colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => SearchPage(initialKeyword: tag),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                          ],
                          // 查看原文链接（复制到剪贴板）
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Center(
                              child: TextButton.icon(
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text(
                                  '查看原文（复制链接）',
                                  style: TextStyle(fontSize: 13),
                                ),
                                onPressed: () async {
                                  final url =
                                      '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=${widget.tid}';
                                  await Clipboard.setData(
                                    ClipboardData(text: url),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('链接已复制：$url')),
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                          // 页码导航（多页时显示）
                          if ((data?.totalPages ?? 1) > 1)
                            SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left),
                                      onPressed: _page > 1
                                          ? () => _goPage(_page - 1)
                                          : null,
                                    ),
                                    // 页数多时折叠为胶囊数字（当前/总），少时逐个显示
                                    if (data!.totalPages <= 7)
                                      for (var p = 1; p <= data.totalPages; p++)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          child: ChoiceChip(
                                            label: Text('$p'),
                                            selected: p == _page,
                                            onSelected: (_) => _goPage(p),
                                            labelStyle: const TextStyle(
                                              fontSize: 13,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        )
                                    else ...[
                                      InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () => _jumpPage(data.totalPages),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                                .withAlpha(70),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Text(
                                            '$_page / ${data.totalPages} · 点此跳页',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.last_page),
                                        tooltip: '末页',
                                        onPressed: _page < data.totalPages
                                            ? () => _goPage(data.totalPages)
                                            : null,
                                      ),
                                    ],
                                    IconButton(
                                      icon: const Icon(Icons.chevron_right),
                                      onPressed: _page < data.totalPages
                                          ? () => _goPage(_page + 1)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // 底部操作栏（赞/收藏/分享/回复）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withAlpha(60),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onLongPress: () => _showLikedUsersDialog(_floors),
                          child: _BottomAction(
                            icon: _liked
                                ? Icons.thumb_up
                                : Icons.thumb_up_outlined,
                            label: _likes > 0 ? '$_likes 赞' : '点赞',
                            highlighted: _liked,
                            onTap: _onLike,
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onLongPress: () => _onFavorite(openDialog: true),
                          child: _BottomAction(
                            icon: _favored ? Icons.star : Icons.star_outline,
                            label: _favorites > 0 ? '$_favorites 收藏' : '收藏',
                            highlighted: _favored,
                            activeColor: Colors.amber.shade700,
                            onTap: () => _onFavorite(openDialog: false),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _BottomAction(
                          icon: Icons.share_outlined,
                          label: '分享',
                          onTap: () {
                            final url =
                                '${AppConfig.baseUrl}thread-${widget.tid}-1-1.html';
                            final shareText = _title.isNotEmpty
                                ? '$_title $url'
                                : url;
                            Clipboard.setData(ClipboardData(text: shareText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('标题+链接已复制')),
                            );
                          },
                        ),
                      ),
                      Expanded(
                        child: _BottomAction(
                          icon: Icons.reply_outlined,
                          label: _replies > 0 ? '$_replies 回复' : '回复',
                          onTap: () => _onReplyGlobal(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 回顶部 FAB（操作栏上方）
            Positioned(
              right: 16,
              bottom: 84,
              child: SafeArea(
                child: FloatingActionButton.small(
                  heroTag: 'back_top',
                  tooltip: '回顶部',
                  onPressed: () {
                    if (_scrollCtrl.hasClients) {
                      _scrollCtrl.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: const Icon(Icons.arrow_upward, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloorView extends StatefulWidget {
  final PostFloor floor;
  final int index;
  final int page;
  final int tid;
  final int? fid;
  final bool isFirstFloor;
  final bool isThreadAuthor;
  final String? stamp;
  final String? stampUrl;
  final bool? isLiked;
  final int? likesCount;
  final VoidCallback? onLikeToggle;
  final VoidCallback? onReload;

  const _FloorView({
    required this.floor,
    required this.index,
    this.page = 1,
    required this.tid,
    this.fid,
    this.isFirstFloor = false,
    this.isThreadAuthor = false,
    this.stamp,
    this.stampUrl,
    this.isLiked,
    this.likesCount,
    this.onLikeToggle,
    this.onReload,
  });

  @override
  State<_FloorView> createState() => _FloorViewState();
}

class _FloorViewState extends State<_FloorView> {
  PostFloor get floor => widget.floor;
  int get index => widget.index;
  int get tid => widget.tid;
  int? get fid => widget.fid;
  late bool _isLiked;
  late int _likesCount;

  String get _displayFloorNumber {
    // 1. 如果是第1页第1楼，为楼主
    if (widget.isFirstFloor) {
      return '楼主';
    }
    // 2. 如果服务端 HTML 解析出了明确的楼层号（如 11#、沙发、板凳、地板、20# 等），优先展示
    final fn = floor.floorNumber.trim();
    if (fn.isNotEmpty && fn != '楼主') {
      if (fn.endsWith('#')) {
        return '#${fn.replaceAll('#', '')} 楼';
      }
      return fn;
    }
    // 3. 根据分页与索引计算真实的全局楼层序号
    if (widget.page == 1) {
      if (index == 1) return '沙发';
      if (index == 2) return '板凳';
      if (index == 3) return '地板';
      return '#${index + 1} 楼';
    } else {
      final globalFloor = (widget.page - 1) * 10 + index + 1;
      return '#$globalFloor 楼';
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.isLiked != null) {
      _isLiked = widget.isLiked!;
      _likesCount = widget.likesCount ?? floor.likes;
    } else {
      _isLiked = floor.isLiked;
      _likesCount = floor.likes;
      _loadFloorLikedState();
    }
  }

  Future<void> _loadFloorLikedState() async {
    if (floor.pid == null || floor.pid! <= 0) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList('liked_pids_$tid') ?? const [];
      if (list.contains('${floor.pid}') && mounted) {
        setState(() {
          _isLiked = true;
          if (_likesCount == 0) _likesCount = 1;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveFloorLikedState(bool liked) async {
    if (floor.pid == null || floor.pid! <= 0) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final key = 'liked_pids_$tid';
      final list = (sp.getStringList(key) ?? <String>[]).toList();
      if (liked) {
        if (!list.contains('${floor.pid}')) list.add('${floor.pid}');
      } else {
        list.remove('${floor.pid}');
      }
      await sp.setStringList(key, list);
    } catch (_) {}
  }

  Future<void> _toggleFloorLike() async {
    if (widget.onLikeToggle != null) {
      widget.onLikeToggle!();
      return;
    }
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先登录论坛账号后再进行点赞'),
          action: SnackBarAction(
            label: '去登录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
          ),
        ),
      );
      return;
    }
    final nextLiked = !_isLiked;
    setState(() {
      _isLiked = nextLiked;
      _likesCount += nextLiked ? 1 : (_likesCount > 0 ? -1 : 0);
    });
    _saveFloorLikedState(nextLiked);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await KlpbbsApi.likeFloor(
        tid,
        floor.pid ?? 0,
        isFirstFloor: widget.isFirstFloor,
        support: nextLiked,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            res.message.isNotEmpty
                ? res.message
                : (nextLiked ? '点赞成功 +1' : '已取消点赞'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(nextLiked ? '点赞已记录' : '已取消点赞'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _FloorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLiked != null) {
      _isLiked = widget.isLiked!;
      _likesCount = widget.likesCount ?? _likesCount;
    } else if (oldWidget.floor.likes != widget.floor.likes ||
        oldWidget.floor.isLiked != widget.floor.isLiked) {
      _isLiked = widget.floor.isLiked;
      _likesCount = widget.floor.likes;
    }
  }

  Widget _buildSignature(ThemeData theme) {
    final rawSig = floor.signature.trim();
    if (rawSig.isEmpty) return const SizedBox.shrink();
    final sigHtml = rawSig.contains('<') ? rawSig : ComiisParser.bbcodeToHtml(rawSig);

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(45),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SIGNATURE',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: theme.colorScheme.outline.withAlpha(160),
            ),
          ),
          const SizedBox(height: 3),
          InlineHtmlText(
            html: sigHtml,
            baseStyle: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(200),
            ),
            emojiSize: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, ThemeData theme) {
    final effectiveLiked = widget.isLiked ?? _isLiked;
    final effectiveCount = widget.likesCount ?? _likesCount;

    final leftActions = <Widget>[
      // 赞
      TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _toggleFloorLike,
        icon: Icon(
          effectiveLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
          size: 15,
          color: effectiveLiked ? theme.colorScheme.primary : null,
        ),
        label: Text(
          effectiveCount > 0
              ? (effectiveLiked ? '已赞 $effectiveCount' : '赞 $effectiveCount')
              : (effectiveLiked ? '已赞' : '赞'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: effectiveLiked ? theme.colorScheme.primary : null,
            fontWeight: effectiveLiked ? FontWeight.bold : null,
          ),
        ),
      ),
      // 回复
      TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _openReply(context, quote: false),
        icon: const Icon(Icons.comment_outlined, size: 15),
        label: Text('回复', style: theme.textTheme.bodySmall),
      ),
      // 打赏
      TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _onRewardFloor(context),
        icon: const Icon(Icons.card_giftcard, size: 15),
        label: Text('赏', style: theme.textTheme.bodySmall),
      ),
    ];

    final rightActions = <Widget>[
      // 楼中楼
      if (floor.floorNumber != '1' && floor.floorNumber != '楼主' && floor.floorNumber != '1#')
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _onReplyFloorWrite(),
          icon: const Icon(Icons.forum_outlined, size: 14),
          label: Text(
            floor.replyFloors.isNotEmpty ? '楼中楼(${floor.replyFloors.length})' : '发起楼中楼',
            style: theme.textTheme.bodySmall,
          ),
        ),
      // 引用
      TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _openReply(context, quote: true),
        icon: const Icon(Icons.format_quote, size: 14),
        label: Text('引用', style: theme.textTheme.bodySmall),
      ),
      // 分享
      TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () {
          final url = '${AppConfig.baseUrl}forum.php?mod=redirect&goto=findpost&pid=${floor.pid ?? 0}';
          Clipboard.setData(ClipboardData(text: url));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('楼层链接已复制：$url')));
        },
        icon: const Icon(Icons.share_outlined, size: 14),
        label: Text('分享', style: theme.textTheme.bodySmall),
      ),
      // 道具
      if (floor.magicItems.isNotEmpty)
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _onMagicFloor(context),
          icon: const Icon(Icons.auto_fix_high, size: 14),
          label: Text('道具', style: theme.textTheme.bodySmall),
        ),
      // 举报
      TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _onReportFloor(context),
        icon: const Icon(Icons.flag_outlined, size: 14),
        label: Text('举报', style: theme.textTheme.bodySmall),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: leftActions,
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: rightActions,
                ),
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: leftActions,
              ),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: rightActions,
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    final cardDecoration = BoxDecoration(
      color: widget.isFirstFloor
          ? theme.colorScheme.primaryContainer.withAlpha(35)
          : theme.brightness == Brightness.dark
          ? theme.colorScheme.surfaceContainerLow
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: theme.colorScheme.outlineVariant.withAlpha(60),
        width: 0.6,
      ),
    );

    return RepaintBoundary(
      child: GestureDetector(
        onLongPress: () => _onFloorLongPress(context),
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: isDesktop ? 16 : 10,
          vertical: 6,
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 楼层头部（左侧头像+名称+头衔勋章，右侧发布时间/IP与楼层序号右对齐）
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: floor.uid != null
                      ? () => _openUserSpace(context, floor.uid!)
                      : null,
                  onLongPress: floor.uid != null
                      ? () => _zoomAvatar(context, floor.uid!)
                      : null,
                  child: UserAvatarWidget(
                    uid: floor.uid,
                    author: floor.author,
                    size: 34,
                    faceUrl: floor.faceUrl.isNotEmpty ? floor.faceUrl : null,
                    isOnline: floor.isOnline,
                    showOnlineBadge: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: floor.uid != null
                              ? () => _openUserSpace(context, floor.uid!)
                              : null,
                          child: Text(
                            floor.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      if (widget.isThreadAuthor && !widget.isFirstFloor) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF9800).withAlpha(80),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Text(
                            '楼主',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      if (floor.levelText.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _badgeColor(floor.levelColor, theme),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            floor.levelText,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: floor.levelColor.isNotEmpty
                                  ? Colors.white
                                  : theme.colorScheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (floor.medals.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        for (final md in floor.medals)
                          Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: CachedNetworkImage(
                              imageUrl: md,
                              httpHeaders: AppConfig.imageHeaders,
                              height: 16,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 右侧时间与楼层序号右对齐
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (floor.timeText.isNotEmpty)
                          Text(
                            _friendlyTime(floor.timeText),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withAlpha(200),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (floor.ipText.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            floor.ipText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (floor.isWarned) ...[
                          Tooltip(
                            message: '该楼层受到版主/管理员警告处理',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800).withAlpha(20),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFFFF9800).withAlpha(180),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 11,
                                    color: theme.brightness == Brightness.dark
                                        ? const Color(0xFFFFB74D)
                                        : const Color(0xFFE65100),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    floor.warningText.isNotEmpty
                                        ? floor.warningText
                                        : '受到警告',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: theme.brightness == Brightness.dark
                                          ? const Color(0xFFFFB74D)
                                          : const Color(0xFFE65100),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isFirstFloor
                                ? const Color(0xFFFF9800).withAlpha(30)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                            border: widget.isFirstFloor
                                ? Border.all(
                                    color: const Color(0xFFFF9800).withAlpha(120),
                                    width: 0.8,
                                  )
                                : null,
                          ),
                          child: Text(
                            _displayFloorNumber,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: widget.isFirstFloor
                                  ? (theme.brightness == Brightness.dark ? const Color(0xFFFFB74D) : const Color(0xFFE65100))
                                  : theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (floor.isBestAnswer) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade700,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified, size: 12, color: Colors.white),
                                SizedBox(width: 2),
                                Text(
                                  '最佳答案',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 悬赏贴专区头部
            if (widget.isFirstFloor && floor.bountyPrice != null)
              _buildBountyHeader(theme, floor),
            // 正文
            DiscuzPostRenderer(
              floor: floor,
              tid: tid,
              onQuickReply: () => _openReply(context, quote: false),
              onQuoteReply: () => _openReply(context, quote: true),
            ),
            // 评分/打赏记录
            if (floor.rewards.isNotEmpty || floor.rewardCount.isNotEmpty)
              _RewardSection(floor: floor, tid: tid),
            // 楼主签名档（仅限 1 楼，排在点赞列表前面）
            if (widget.isFirstFloor) ...[
              ListenableBuilder(
                listenable: AppConfig.instance,
                builder: (context, _) {
                  if (AppConfig.showFloorSignature && floor.signature.isNotEmpty) {
                    return _buildSignature(theme);
                  }
                  return const SizedBox.shrink();
                },
              ),
              // 首楼点赞专区 (点赞绿色胶囊按钮 + 帖子ID + 点赞用户头像列表 + 赞数角标)
              _buildDzhanSection(theme, floor),
            ],
            // 楼中楼
            if (floor.replyFloors.isNotEmpty)
              _ReplyFloorSection(
                floor: floor,
                tid: tid,
                onReplyToAuthor: (author) => _onReplyFloorWrite(initialAuthor: author),
                onWriteReply: () => _onReplyFloorWrite(),
                onReportComment: _onReportFloorComment,
              ),
            // 点评
            if (floor.comments.isNotEmpty)
              _CommentsSection(comments: floor.comments),
            // 普通楼层签名档（仅限非 1 楼回复）
            if (!widget.isFirstFloor)
              ListenableBuilder(
                listenable: AppConfig.instance,
                builder: (context, _) {
                  if (AppConfig.showFloorSignature && floor.signature.isNotEmpty) {
                    return _buildSignature(theme);
                  }
                  return const SizedBox.shrink();
                },
              ),
            // 操作栏
            _buildActionRow(context, theme),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildDzhanSection(ThemeData theme, PostFloor floor) {
    final likeCount = _likesCount > 0 ? _likesCount : floor.likes;
    final likedUsers = floor.likedUsers;

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 8),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(50),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部栏：点赞绿色按钮 + 帖子ID
          Row(
            children: [
              InkWell(
                onTap: () {
                  if (widget.onLikeToggle != null) {
                    widget.onLikeToggle!();
                  } else {
                    _toggleFloorLike();
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5AB75C),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5AB75C).withAlpha(50),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.thumb_up_rounded, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        _isLiked ? '已点赞' : '点赞这个帖子',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '帖子ID: $tid',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          if (likedUsers.isNotEmpty || likeCount > 0) ...[
            const SizedBox(height: 10),
            Row(
            children: [
              if (likedUsers.isNotEmpty)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: likedUsers.map((u) {
                        return GestureDetector(
                          onTap: () {
                            if (u.uid != null && u.uid! > 0) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => UserSpacePage(uid: u.uid!),
                                ),
                              );
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.surface,
                                width: 1.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: u.avatarUrl.isNotEmpty
                                    ? u.avatarUrl
                                    : AppConfig.avatarUrl(u.uid ?? 0),
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                )
              else
                const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$likeCount赞',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

  Widget _buildBountyHeader(ThemeData theme, PostFloor floor) {
    final isSolved = floor.isBountySolved;
    final price = floor.bountyPrice ?? '';

    final isDark = theme.brightness == Brightness.dark;
    final iconColor = isSolved
        ? (isDark ? Colors.green.shade400 : Colors.green.shade700)
        : (isDark ? Colors.amber.shade400 : Colors.amber.shade800);
    final titleColor = isSolved
        ? (isDark ? Colors.green.shade300 : Colors.green.shade900)
        : (isDark ? Colors.amber.shade300 : Colors.amber.shade900);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isSolved ? Colors.green.withAlpha(20) : Colors.amber.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSolved ? Colors.green.withAlpha(90) : Colors.amber.withAlpha(120),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSolved ? Icons.check_circle : Icons.monetization_on,
            color: iconColor,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '悬赏问答主题 [$price]',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isSolved ? '此悬赏已结贴，已产生最佳答案。' : '此悬赏进行中，回帖提供正确解答即可赢取悬赏铁粒！',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isSolved ? Colors.green.shade700 : Colors.amber.shade800,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isSolved ? '已解决' : '进行中',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _friendlyTime(String raw) {
    final m = RegExp(
      r'(\d{4})-(\d{1,2})-(\d{1,2})\s*(\d{1,2}):(\d{1,2})?',
    ).firstMatch(raw);
    if (m == null) return raw;
    final now = DateTime.now();
    final y = int.tryParse(m.group(1) ?? '') ?? now.year;
    final mo = int.tryParse(m.group(2) ?? '') ?? 1;
    final d = int.tryParse(m.group(3) ?? '') ?? 1;
    final h = int.tryParse(m.group(4) ?? '') ?? 0;
    final mi = int.tryParse(m.group(5) ?? '') ?? 0;
    final hm =
        '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(y, mo, d);
    final diff = today.difference(that).inDays;
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '昨天 $hm';
    if (diff < 7) return '$diff 天前';
    if (y == now.year) return '$mo月$d日 $hm';
    return '$y-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  // 楼层长按菜单（复制/分享/举报）
  void _onFloorLongPress(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '楼层 ${index + 1} · ${floor.author}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              dense: true,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text((index == 0 || floor.floorNumber == '1' || floor.floorNumber == '楼主' || floor.floorNumber == '1#') ? '回复主题' : '楼中楼回复'),
              subtitle: Text((index == 0 || floor.floorNumber == '1' || floor.floorNumber == '楼主' || floor.floorNumber == '1#') ? '回复楼主发表的主题内容' : '引用该楼层进行楼中楼回复'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openReply(context, quote: !(index == 0 || floor.floorNumber == '1' || floor.floorNumber == '楼主' || floor.floorNumber == '1#'));
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.select_all),
              title: const Text('选择复制正文'),
              subtitle: const Text('长按后自由选择帖子内信息复制（含隐藏内容）'),
              onTap: () {
                Navigator.of(ctx).pop();
                final plain = floor.contentHtml
                    .replaceAll(RegExp(r'<[^>]+>'), ' ')
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
                showDialog<void>(
                  context: context,
                  builder: (dlg) => AlertDialog(
                    title: Text('楼层 ${index + 1} · ${floor.author}'),
                    content: SizedBox(
                      width: 560,
                      height: 360,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          plain.isEmpty ? '(该楼层无文字内容)' : plain,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dlg).pop(),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制正文'),
              onTap: () {
                Navigator.of(ctx).pop();
                final plain = floor.contentHtml
                    .replaceAll(RegExp(r'<[^>]+>'), ' ')
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
                if (plain.isEmpty) return;
                Clipboard.setData(ClipboardData(text: plain));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('正文已复制')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享楼层链接'),
              onTap: () {
                Navigator.of(ctx).pop();
                final url =
                    '${AppConfig.baseUrl}forum.php?mod=redirect&goto=findpost&pid=${floor.pid ?? 0}';
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('楼层链接已复制')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('举报'),
              onTap: () {
                Navigator.of(ctx).pop();
                _onReportFloor(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 楼层举报（弹 Discuz 规范选项弹窗 + reportPost）
  void _onReportFloor(BuildContext context) {
    ReportDialog.show(
      context,
      tid: tid,
      pid: floor.pid ?? 0,
      author: floor.author,
      floorIndex: index,
    );
  }

  // 楼中楼单条评论举报
  void _onReportFloorComment(ReplyFloorComment comment) {
    ReportDialog.show(
      context,
      tid: tid,
      pid: floor.pid ?? 0,
      author: comment.author,
      floorIndex: index,
    );
  }

  // 发起/回复楼中楼（支持表情库面板、快捷表情插入与实时反馈）
  void _onReplyFloorWrite({String? initialAuthor}) {
    final hasAuthor = initialAuthor != null && initialAuthor.trim().isNotEmpty;
    final ctrl = TextEditingController(
      text: hasAuthor ? '回复 @$initialAuthor : ' : '',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) {
        bool submitting = false;
        bool showEmojiPanel = false;
        int activeSmileyCatIndex = 0;
        List<SmileyCategory> smileyCats = ComiisParser.parseSmilies(ComiisParser.kDefaultSmiliesJs);

        // 异步尝试拉取论坛最新全量表情集
        KlpbbsApi.getSmilies().then((cats) {
          if (cats.isNotEmpty && ctx.mounted) {
            smileyCats = cats;
          }
        }).catchError((_) {});

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            void insertCode(String code) {
              final text = ctrl.text;
              final sel = ctrl.selection;
              if (sel.isValid) {
                final newText = text.replaceRange(sel.start, sel.end, code);
                ctrl.value = TextEditingValue(
                  text: newText,
                  selection: TextSelection.collapsed(offset: sel.start + code.length),
                );
              } else {
                ctrl.text = '$text$code';
                ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: Row(
                children: [
                  Icon(Icons.reply_rounded, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasAuthor ? '回复 @$initialAuthor' : '回复 $_displayFloorNumber (楼中楼)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: ctrl,
                      maxLines: 4,
                      autofocus: true,
                      enabled: !submitting,
                      decoration: InputDecoration(
                        hintText: hasAuthor
                            ? '写下你想对 @$initialAuthor 说的话...'
                            : '写下你的楼中楼内容...',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 常用表情快捷插入栏 + 完整表情库展开按钮
                    Row(
                      children: [
                        IconButton(
                          tooltip: showEmojiPanel ? '收起表情面板' : '展开完整表情库',
                          icon: Icon(
                            showEmojiPanel ? Icons.keyboard_alt_outlined : Icons.sentiment_satisfied_alt_outlined,
                            size: 20,
                            color: showEmojiPanel ? Theme.of(context).colorScheme.primary : null,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setDialogState(() {
                              showEmojiPanel = !showEmojiPanel;
                            });
                          },
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final emoji in [
                                  ('滑稽', '[贴吧_滑稽]'),
                                  ('呵呵', '[贴吧_呵呵]'),
                                  ('疑问', '[贴吧_疑问]'),
                                  ('点赞', '[B站_点赞]'),
                                  ('打call', '[B站_打call]'),
                                  ('妙啊', '[B站_妙啊]'),
                                  ('干杯', '[B站_干杯]'),
                                  ('汗', '[贴吧_汗]'),
                                  ('笑眼', '[贴吧_笑眼]'),
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ActionChip(
                                      label: Text(emoji.$1, style: const TextStyle(fontSize: 11)),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      onPressed: submitting ? null : () => insertCode(emoji.$2),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 完整表情库选择面板
                    if (showEmojiPanel && smileyCats.isNotEmpty) ...[
                      const Divider(height: 12),
                      // 分类 Tab 切换
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var cIdx = 0; cIdx < smileyCats.length; cIdx++)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: ChoiceChip(
                                  label: Text(
                                    smileyCats[cIdx].name,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  selected: activeSmileyCatIndex == cIdx,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (sel) {
                                    if (sel) {
                                      setDialogState(() => activeSmileyCatIndex = cIdx);
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 表情图片网格
                      SizedBox(
                        height: 140,
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 44,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                            childAspectRatio: 1,
                          ),
                          itemCount: smileyCats[activeSmileyCatIndex].smileys.length,
                          itemBuilder: (context, sIdx) {
                            final smiley = smileyCats[activeSmileyCatIndex].smileys[sIdx];
                            return InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => insertCode(smiley.code),
                              child: Center(
                                child: CachedNetworkImage(
                                  imageUrl: smiley.imageUrl,
                                  httpHeaders: AppConfig.imageHeaders,
                                  width: 28,
                                  height: 28,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, __, ___) => const Icon(
                                    Icons.image_not_supported_outlined,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton.icon(
                  onPressed: submitting
                      ? null
                      : () async {
                          final msg = ctrl.text.trim();
                          if (msg.isEmpty) return;
                          final messenger = ScaffoldMessenger.of(context);
                          final confirmed = await confirmWrite(context, '回复楼中楼');
                          if (!confirmed) return;
                          setDialogState(() => submitting = true);
                          try {
                            final ok = await KlpbbsApi.postFloorReply(
                              tid,
                              floor.pid ?? 0,
                              msg,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok ? '已成功发布楼中楼回复' : '回复失败（请先登录论坛账号）',
                                ),
                              ),
                            );
                            if (ok) {
                              widget.onReload?.call();
                            }
                          } catch (e) {
                            if (dialogCtx.mounted) setDialogState(() => submitting = false);
                            messenger.showSnackBar(SnackBar(content: Text('回复异常：$e')));
                          }
                        },
                  icon: submitting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, size: 16),
                  label: Text(submitting ? '发送中...' : '发送'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 打赏（Discuz rating：金额快捷选择 + 理由）
  void _onRewardFloor(BuildContext context) {
    final amountCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    int selected = 1;
    const amounts = [1, 5, 10, 50];
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(context).colorScheme;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 渐变头部
                  Container(
                    padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primaryContainer,
                          scheme.secondaryContainer,
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scheme.primary.withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.card_giftcard,
                            color: scheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '打赏 @${floor.author}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '写贴不容易，打赏一下楼主吧',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 金额快捷选择
                  Text(
                    '选择金额',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in amounts)
                        ChoiceChip(
                          label: Text('$a 铁粒'),
                          selected: selected == a,
                          onSelected: (_) {
                            setLocal(() {
                              selected = a;
                              amountCtrl.text = '$a';
                            });
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      // 自定义金额
                      SizedBox(
                        width: 76,
                        height: 32,
                        child: TextField(
                          controller: amountCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (v) => setLocal(() => selected = 0),
                          decoration: InputDecoration(
                            hintText: '自定义',
                            isDense: true,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // 理由
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: '打赏理由（可选）',
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('取消'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () async {
                          final amount =
                              int.tryParse(amountCtrl.text.trim()) ?? 0;
                          if (amount <= 0) return;
                          Navigator.of(ctx).pop();
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final res = await KlpbbsApi.ratePost(
                              tid,
                              floor.pid ?? 0,
                              amount,
                              reason: reasonCtrl.text.trim(),
                            );
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(res.message),
                              ),
                            );
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('打赏异常：$e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.card_giftcard, size: 18),
                        label: const Text('打赏'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 回复/引用回复（完全对齐 Discuz Web 端逻辑）
  void _openReply(BuildContext context, {required bool quote}) {
    final isFirst = widget.isFirstFloor ||
        floor.floorNumber == '1' ||
        floor.floorNumber == '楼主' ||
        floor.floorNumber == '1#';

    if (quote) {
      // 引用回复：先剥离已有 quote 引用块和 HTML 标签，避免多层嵌套
      final cleanContent = floor.contentHtml
          .replaceAll(RegExp(r'<div class="quote">.*?</div>', dotAll: true), '')
          .replaceAll(RegExp(r'<blockquote.*?>.*?</blockquote>', dotAll: true), '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final snippet = cleanContent.length > 200
          ? '${cleanContent.substring(0, 200)}...'
          : cleanContent;

      // Discuz 标准带链接引用格式
      final quoteText = (floor.pid != null && floor.pid! > 0)
          ? '[quote][size=2][url=forum.php?mod=redirect&goto=findpost&pid=${floor.pid}&ptid=$tid][color=#999999]${floor.author}${floor.timeText.isNotEmpty ? " 发表于 ${floor.timeText}" : ""}[/color][/url][/size]\n$snippet[/quote]\n\n'
          : '[quote]${floor.author}:\n$snippet[/quote]\n\n';

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostPage(
            tid: tid,
            fid: fid,
            pid: floor.pid,
            repquote: floor.pid,
            noticeauthor: floor.author,
            noticetrimstr: snippet,
            replyToFloorText: '引用 $_displayFloorNumber (${floor.author})',
            initialMessage: quoteText,
          ),
        ),
      );
    } else {
      // 普通回复：若回复非楼主楼层，对齐 Discuz 传递 reppost 并预填 @用户，触发系统站内信提醒
      if (isFirst) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostPage(
              tid: tid,
              fid: fid,
              replyToFloorText: '回复楼主 (${floor.author})',
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostPage(
              tid: tid,
              fid: fid,
              pid: floor.pid,
              reppost: floor.pid,
              noticeauthor: floor.author,
              replyToFloorText: '回复 $_displayFloorNumber (${floor.author})',
              initialMessage: '回复 @${floor.author} : ',
            ),
          ),
        );
      }
    }
  }

  // 头像长按放大
  void _zoomAvatar(BuildContext context, int uid) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: CachedNetworkImage(
          imageUrl: 'https://user.klpbbs.com/avatar.php?uid=$uid&size=middle',
          placeholder: (_, __) => const SizedBox(
            width: 120,
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, __, ___) => const SizedBox(
            width: 120,
            height: 120,
            child: Icon(Icons.person, size: 60),
          ),
        ),
      ),
    );
  }

  /// 道具菜单（mgc_post_{pid}）：底部弹出可用道具，点击在本地环境使用
  void _onMagicFloor(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  '使用道具',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (final m in floor.magicItems)
                ListTile(
                  leading: m.img.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: m.img,
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.auto_fix_high, size: 24),
                        )
                      : const Icon(Icons.auto_fix_high),
                  title: Text(m.name),
                  subtitle: Text(m.idtype == 'tid' ? '作用于主题' : '作用于本楼'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final confirmed = await confirmWrite(
                      context,
                      '使用道具「${m.name}」',
                    );
                    if (!confirmed || !context.mounted) return;
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final ok = await KlpbbsApi.useMagicOnPost(
                        mid: m.mid,
                        idtype: m.idtype,
                        id: m.id,
                      );
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? '道具「${m.name}」已使用' : '使用失败（未登录/无该道具/真实论坛只读）',
                          ),
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('使用异常：$e')),
                      );
                    }
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('取消'),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openUserSpace(BuildContext context, int uid) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => UserSpacePage(uid: uid)));
  }
}

/// 楼中楼（replyfloor 插件）区块
class _ReplyFloorSection extends StatelessWidget {
  final PostFloor floor;
  final int tid;
  final void Function(String author)? onReplyToAuthor;
  final VoidCallback? onWriteReply;
  final void Function(ReplyFloorComment comment)? onReportComment;

  const _ReplyFloorSection({
    required this.floor,
    required this.tid,
    this.onReplyToAuthor,
    this.onWriteReply,
    this.onReportComment,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = floor.replyFloorCount > 0
        ? floor.replyFloorCount
        : floor.replyFloors.length;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withAlpha(90),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.subdirectory_arrow_right,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '楼中楼',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          for (final c in floor.replyFloors)
            _ReplyFloorItem(
              comment: c,
              onReply: onReplyToAuthor,
              onReport: onReportComment,
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onWriteReply,
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('我要说一句', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyFloorItem extends StatelessWidget {
  final ReplyFloorComment comment;
  final void Function(String author)? onReply;
  final void Function(ReplyFloorComment comment)? onReport;

  const _ReplyFloorItem({
    required this.comment,
    this.onReply,
    this.onReport,
  });

  void _showContextMenu(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制评论文字'),
              onTap: () {
                Navigator.pop(ctx);
                final plainText = comment.contentHtml.replaceAll(RegExp(r'<[^>]*>'), '');
                Clipboard.setData(ClipboardData(text: plainText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制评论到剪贴板')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text('回复 @${comment.author}'),
              onTap: () {
                Navigator.pop(ctx);
                onReply?.call(comment.author);
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('举报此违规评论'),
              onTap: () {
                Navigator.pop(ctx);
                onReport?.call(comment);
              },
            ),
            if (comment.uid != null && comment.uid! > 0)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('查看 @${comment.author} 的空间'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UserSpacePage(uid: comment.uid!),
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onLongPress: () => _showContextMenu(context),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: comment.uid != null && comment.uid! > 0
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UserSpacePage(uid: comment.uid!),
                        ),
                      )
                  : null,
              child: UserAvatarWidget(
                uid: comment.uid,
                author: comment.author,
                size: 22,
                faceUrl: comment.faceUrl.isNotEmpty ? comment.faceUrl : null,
                isOnline: comment.isOnline,
                showOnlineBadge: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: comment.uid != null && comment.uid! > 0
                              ? () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => UserSpacePage(uid: comment.uid!),
                                    ),
                                  )
                              : null,
                          child: Text(
                            comment.author,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (comment.location.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          comment.location,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline.withAlpha(160),
                            fontSize: 10,
                          ),
                        ),
                      ],
                      if (comment.isWarned) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800).withAlpha(20),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: const Color(0xFFFF9800).withAlpha(180),
                              width: 0.6,
                            ),
                          ),
                          child: Text(
                            comment.warningText.isNotEmpty ? comment.warningText : '受到警告',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: theme.brightness == Brightness.dark
                                  ? const Color(0xFFFFB74D)
                                  : const Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (comment.timeText.isNotEmpty)
                        Text(
                          comment.timeText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline.withAlpha(160),
                            fontSize: 10,
                          ),
                        ),
                      const SizedBox(width: 6),
                      // 举报按钮
                      InkWell(
                        onTap: () => onReport?.call(comment),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.flag_outlined, size: 12, color: colorScheme.onSurfaceVariant.withAlpha(180)),
                              const SizedBox(width: 2),
                              Text(
                                '举报',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant.withAlpha(200),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 回复按钮
                      InkWell(
                        onTap: () => onReply?.call(comment.author),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.reply_rounded, size: 12, color: colorScheme.primary),
                              const SizedBox(width: 2),
                              Text(
                                '回复',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  InlineHtmlText(
                    html: comment.contentHtml,
                    baseStyle: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      height: 1.55,
                    ),
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

/// Discuz 点评（postcomment / 楼中楼点评）
class _CommentsSection extends StatelessWidget {
  final List<({String author, String content})> comments;
  const _CommentsSection({required this.comments});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withAlpha(90),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '点评',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 4),
          for (final c in comments)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: c.author.isNotEmpty ? '${c.author}：' : '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: c.content,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 打赏记录（ratelog，含头像/金额正负/理由，支持折叠与查看详情弹窗）
class _RewardSection extends StatefulWidget {
  final PostFloor floor;
  final int tid;
  const _RewardSection({required this.floor, required this.tid});

  @override
  State<_RewardSection> createState() => _RewardSectionState();
}

class _RewardSectionState extends State<_RewardSection> {
  PostFloor get floor => widget.floor;

  void _openRewardDetail() {
    final pid = floor.pid ?? 0;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return FutureBuilder<List<FloorReward>>(
          future: (pid > 0 ? KlpbbsApi.getRatings(widget.tid, pid) : Future.value(<FloorReward>[])).then((apiList) {
            if (apiList.isNotEmpty) {
              return apiList;
            }
            return floor.rewards.map((r) => FloorReward(
              username: r.user,
              uid: r.uid,
              amount: r.amount,
              reason: r.reason,
            )).toList();
          }),
          builder: (context, snap) {
            final allList = snap.data ?? floor.rewards.map((r) => FloorReward(
              username: r.user,
              uid: r.uid,
              amount: r.amount,
              reason: r.reason,
            )).toList();
            final count = allList.isNotEmpty ? allList.length : floor.rewards.length;

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.65,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.card_giftcard_rounded,
                            size: 20,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '楼层评分与打赏日志 ($count 条)',
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: (snap.connectionState != ConnectionState.done && allList.isEmpty)
                          ? const Center(child: CircularProgressIndicator())
                          : allList.isEmpty
                              ? const Center(child: Text('暂无打赏记录'))
                              : ListView.separated(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: allList.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1, indent: 44),
                                  itemBuilder: (_, idx) {
                                    final r = allList[idx];
                                    return _buildRewardItem(
                                      ctx,
                                      (
                                        user: r.username,
                                        uid: r.uid,
                                        avatar: '',
                                        amount: r.amount,
                                        reason: r.reason,
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRewardItem(
    BuildContext ctx,
    ({String user, int? uid, String avatar, String amount, String reason}) r,
  ) {
    final theme = Theme.of(ctx);
    final negative = r.amount.contains('-');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: r.uid != null
          ? () => Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => UserSpacePage(uid: r.uid!)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatarWidget(
              uid: r.uid,
              author: r.user,
              size: 30,
              // 不打赏头像图，避免与 UserAvatarWidget 内部 uid 头像重叠
              faceUrl: null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.user,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (r.reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        r.reason,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (r.amount.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (negative ? Colors.red : Colors.orange).withAlpha(22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  r.amount,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: negative
                        ? (theme.brightness == Brightness.dark ? Colors.red.shade300 : Colors.red.shade600)
                        : (theme.brightness == Brightness.dark ? Colors.orange.shade300 : Colors.orange.shade800),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rewards = floor.rewards;
    if (rewards.isEmpty && floor.rewardCount.isEmpty) {
      return const SizedBox.shrink();
    }
    final visible = rewards.take(3).toList();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withAlpha(45), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.card_giftcard_rounded,
                size: 16,
                color: isDark ? Colors.orange.shade400 : Colors.orange.shade800,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  floor.rewardCount.isNotEmpty
                      ? '已有 ${floor.rewardCount} 人打赏'
                      : '打赏',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.orange.shade300 : Colors.orange.shade900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _openRewardDetail,
                icon: const Icon(Icons.list_alt, size: 14),
                label: const Text('查看详情', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          for (final r in visible) _buildRewardItem(context, r),
          Center(
            child: TextButton.icon(
              onPressed: _openRewardDetail,
              icon: const Icon(Icons.open_in_new, size: 14),
              label: Text(
                floor.rewardCount.isNotEmpty
                    ? '查看全部 ${floor.rewardCount} 条打赏/评分记录'
                    : '查看全部 ${rewards.length} 条打赏记录',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 等级徽章背景色：管理员/版主用内联红/品红，普通会员用主题色浅底
Color _badgeColor(String hex, ThemeData theme) {
  if (hex.isNotEmpty) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) {
      final v = int.tryParse(h, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
  }
  return theme.colorScheme.primaryContainer.withAlpha(80);
}

/// 底部操作栏按钮（图标 + 文字）
class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;
  final Color? activeColor;

  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlighted ? (activeColor ?? scheme.primary) : scheme.outline;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
