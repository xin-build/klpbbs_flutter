import '../widgets/app_motion.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/comiis_parser.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../core/dio_client.dart';
import '../core/preload_service.dart';
import '../core/url_helper.dart';
import '../core/write_confirm.dart';
import '../models/ai_summary.dart';
import '../models/post_floor.dart';
import '../models/server_outage_info.dart';
import '../models/smiley.dart';
import '../widgets/server_outage_view.dart';
import '../widgets/ai_summary_card.dart';
import '../widgets/bili_video_player.dart';
import '../widgets/general_audio_player.dart';
import '../widgets/general_video_player.dart';
import '../widgets/discuz_post_renderer.dart';
import '../widgets/netease_music_player.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/inline_html_text.dart';
import '../widgets/interactive_animations.dart';
import '../widgets/visual_grid_canvas.dart';
import '../widgets/favorite_dialog.dart';
import '../widgets/floor_admin_dialog.dart';
import '../widgets/rating_filter_hall.dart';
import '../widgets/report_dialog.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/thread_card.dart';
import '../widgets/user_avatar_widget.dart';
import '../widgets/post_copy_sheet.dart';
import '../core/post_copy_document.dart';
import '../widgets/thread_layout_workbench.dart';
import '../widgets/thread_access_view.dart';
import '../core/discuz_thread_access.dart';
import '../widgets/topic_admin_dialog.dart';
import 'login_page.dart';
import 'post_page.dart';
import 'search_page.dart';
import 'thread_list_page.dart';
import 'user_space_page.dart';

final _digitRegex = RegExp(r'(\d+)');

/// 帖子详情（楼层列表）
///
/// 正文以纯文本 + 图片网格展示（扩展点：可替换为富文本/WebView 渲染）。
String? _accountStateKey(String key) {
  if (key == 'fav_tids') return KlpbbsApi.favoriteThreadsPrefsKey;
  final uid = KlpbbsApi.currentCachedMyUid;
  if (!DioClient.isLoggedIn || uid == null || uid <= 0) return null;
  return '$key:${AppConfig.baseUrl}:$uid';
}

List<String> _savedAccountState(SharedPreferences prefs, String key) {
  final scoped = _accountStateKey(key);
  return scoped == null ? const [] : (prefs.getStringList(scoped) ?? const []);
}

bool _canSendLike(BuildContext context) {
  if (DioClient.isLoggedIn) return true;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: const Text('请先登录论坛账号后再进行点赞'),
    action: SnackBarAction(
        label: '去登录',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const LoginPage()))),
  ));
  return false;
}

class ThreadDetailPage extends StatefulWidget {
  final int tid;
  final int? fid;
  final bool showBackButton;
  final bool stopPlayersOnDispose;
  final bool canShowForumSidebar;
  final VoidCallback? onToggleForumSidebar;
  final bool? isForumSidebarVisible;

  const ThreadDetailPage({
    super.key,
    required this.tid,
    this.fid,
    this.showBackButton = true,
    this.stopPlayersOnDispose = true,
    this.canShowForumSidebar = true,
    this.onToggleForumSidebar,
    this.isForumSidebarVisible,
  });

  static String formatFloorNumber(int n) =>
      _ThreadDetailPageState.formatFloorNumber(n);
  static List<String> computeDisplayFloorNumbers(
    List<PostFloor> floors, {
    required int page,
    required bool isDescOrder,
    int? totalReplies,
  }) =>
      _ThreadDetailPageState.computeDisplayFloorNumbers(
        floors,
        page: page,
        isDescOrder: isDescOrder,
        totalReplies: totalReplies,
      );

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage> {
  late Future<ThreadDetailParsed> _future;
  AiSummaryData? _aiSummary;
  final _scrollCtrl = ScrollController();
  int _page = 1;
  final _scrolledNotifier = ValueNotifier<bool>(false);
  final _showBackToTopNotifier = ValueNotifier<bool>(false);
  String _title = '';
  String? _stamp;
  String? _stampUrl;
  bool _liked = false;
  bool _likeBusy = false;
  bool _favoriteBusy = false;
  int _loadGeneration = 0;
  final Set<int> _likingFloorPids = {};
  bool _favored = false;
  int? _favid;
  int? _myUid;
  int? _firstAuthorUid;
  bool _isBountyThread = false;
  bool _isBountySolved = false;
  int? _threadFid;
  late int _effectiveTid;
  int? _effectiveFid;
  String? _forumName;
  bool _showForumSidebar = false;
  bool _showInThreadSearch = false;
  final _inThreadSearchCtrl = TextEditingController();
  List<int> _inThreadSearchMatches = [];
  int _inThreadSearchCurrentIdx = 0;

  int? get currentFid => _effectiveFid ?? _threadFid ?? widget.fid;

  bool _canModerate = false;
  int _likes = 0;
  int _favorites = 0;
  int _views = 0;
  int _replies = 0;
  List<String> _tags = const [];
  List<PostFloor> _floors = const [];
  final Map<int, GlobalKey> _floorItemKeys = {};
  final Set<int> _likedFloorPids = {};
  int? _ordertype;
  bool _isDescOrder = false;
  int? _highlightedFloorIndex;
  int? _pendingTargetFloor;
  int _totalPages = 1;
  ServerOutageInfo? _activeOutage;
  bool _viewCacheAnyway = false;
  DiscuzThreadAccessException? _accessRestriction;

  void _clearThreadContent() {
    _title = '';
    _floors = const [];
    _firstAuthorUid = null;
    _stamp = null;
    _stampUrl = null;
    _aiSummary = null;
    _liked = false;
    _favored = false;
    _favid = null;
    _likes = 0;
    _favorites = 0;
    _views = 0;
    _replies = 0;
    _tags = const [];
    _totalPages = 1;
    _isBountyThread = false;
    _isBountySolved = false;
    _likedFloorPids.clear();
    _likingFloorPids.clear();
    _showInThreadSearch = false;
    _inThreadSearchCtrl.clear();
    _inThreadSearchMatches = [];
    _inThreadSearchCurrentIdx = 0;
    _floorItemKeys.clear();
  }

  @override
  void initState() {
    super.initState();
    _effectiveTid = widget.tid;
    _effectiveFid = widget.fid;
    _showForumSidebar = AppConfig.threadLeftEnabled;
    AppConfig.instance.addListener(_onConfigChanged);
    DioClient.sessionChanges.addListener(_onSessionChanged);
    final session = DioClient.sessionKey;
    _loadAndInit();
    KlpbbsApi.getMyUid().then((uid) {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _myUid = uid);
      }
    }).catchError((_) {});
    KlpbbsApi.getMyRole(fid: widget.fid).then((role) {
      if (mounted &&
          session == DioClient.sessionKey &&
          currentFid == widget.fid) {
        final canMod = role.canModerateFid(widget.fid);
        if (canMod != _canModerate) {
          setState(() => _canModerate = canMod);
        }
      }
    }).catchError((_) {});
    // AppBar 标题滚动折叠：滚动超过 120px 显示帖子标题；超过 280px 显示回到顶部（通过 ValueNotifier 通知，杜绝触发整个三栏页面重构）
    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.offset > 120;
      if (show != _scrolledNotifier.value) _scrolledNotifier.value = show;
      final showTop = _scrollCtrl.offset > 280;
      if (showTop != _showBackToTopNotifier.value) {
        _showBackToTopNotifier.value = showTop;
      }
    });
  }

  void _onSidebarSelectThread(int newTid) {
    if (_effectiveTid == newTid) return;
    BiliVideoPlayer.stopAll();
    NetEaseMusicPlayer.stopAll();
    GeneralAudioPlayer.stopAll();
    GeneralVideoPlayer.stopAll();
    setState(() {
      _effectiveTid = newTid;
      _page = 1;
      _ordertype = null;
      _accessRestriction = null;
      _clearThreadContent();
      _firstAuthorUid = null;
      _floorItemKeys.clear();
      _highlightedFloorIndex = null;
      _pendingTargetFloor = null;
      _floors = const [];
      _title = '';
      _stamp = null;
      _stampUrl = null;
      _aiSummary = null;
      _favored = false;
      _liked = false;
    });
    _loadAndInit(forceRefresh: true);
  }

  void _onConfigChanged() {
    if (mounted) {
      if (_showForumSidebar != AppConfig.threadLeftEnabled) {
        _showForumSidebar = AppConfig.threadLeftEnabled;
      }
      setState(() {});
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final session = DioClient.sessionKey;
    setState(() {
      _myUid = null;
      _accessRestriction = null;
      _clearThreadContent();
      _canModerate = false;
      _liked = false;
      _favored = false;
      _favid = null;
      _likeBusy = false;
      _favoriteBusy = false;
      _likedFloorPids.clear();
      _likingFloorPids.clear();
    });
    _loadAndInit(forceRefresh: true);
    KlpbbsApi.getMyUid().then((uid) {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _myUid = uid);
      }
    }).catchError((_) {});
  }

  void _loadAndInit({bool forceRefresh = false}) {
    final generation = ++_loadGeneration;
    final session = DioClient.sessionKey;
    setState(() {
      _viewCacheAnyway = false;
      _activeOutage = null;
      _floorItemKeys.clear();
      _future = KlpbbsApi.getThread(
        _effectiveTid,
        page: _page,
        ordertype: _ordertype,
        forceRefresh: forceRefresh,
      ).then((r) async {
        final prefs = await SharedPreferences.getInstance();
        if (mounted &&
            generation == _loadGeneration &&
            session == DioClient.sessionKey) {
          setState(() {
            _activeOutage = null;
            _accessRestriction = null;
            _applyThreadData(r, prefs);
          });
          if (_pendingTargetFloor != null) {
            final target = _pendingTargetFloor!;
            _pendingTargetFloor = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && generation == _loadGeneration) {
                  _scrollToFloorNumberInCurrentPage(target);
                }
              });
            });
          }
        }
        return r;
      }).catchError((Object error, StackTrace stack) {
        if (error is DiscuzThreadAccessException &&
            mounted &&
            generation == _loadGeneration &&
            session == DioClient.sessionKey) {
          setState(() {
            _clearThreadContent();
            _accessRestriction = error;
          });
          BiliVideoPlayer.stopAll();
          NetEaseMusicPlayer.stopAll();
          GeneralAudioPlayer.stopAll();
          GeneralVideoPlayer.stopAll();
        }
        Error.throwWithStackTrace(error, stack);
      });
      // A cached/fast response may fail before FutureBuilder's next frame.
      // Attach immediately; the builder still receives the original error.
      _future.ignore();
    });
  }

  void _applyThreadData(dynamic r, SharedPreferences prefs) {
    final generation = _loadGeneration;
    final session = DioClient.sessionKey;
    _title = r.title;
    // 记录主题作者（楼主）的 uid：优先使用页面解析出的权威 authorUid
    if (r.authorUid != null && (r.authorUid as int) > 0) {
      _firstAuthorUid = r.authorUid as int;
    } else if (r.floors.isNotEmpty) {
      final floorsList = r.floors as List<PostFloor>;
      final louzhuFloor = floorsList.firstWhere(
        (f) => f.floorNumber == '楼主' || f.isThreadAuthor,
        orElse: () => floorsList.first,
      );
      if (_firstAuthorUid == null ||
          louzhuFloor.floorNumber == '楼主' ||
          louzhuFloor.isThreadAuthor) {
        _firstAuthorUid = louzhuFloor.uid;
      }

      final firstFloor = floorsList.first;
      if (firstFloor.bountyPrice != null &&
          firstFloor.bountyPrice!.isNotEmpty) {
        _isBountyThread = true;
        _isBountySolved = firstFloor.isBountySolved;
      } else {
        final hasBest = floorsList.any((f) => f.isBestAnswer);
        final hasSolved = floorsList.any((f) => f.isBountySolved);
        if (hasBest || hasSolved) {
          _isBountyThread = true;
          _isBountySolved = true;
        }
      }
    }

    if (r.forumName != null && (r.forumName as String).trim().isNotEmpty) {
      _forumName = (r.forumName as String).trim();
    }

    if (r.fid != null && r.fid > 0) {
      _threadFid = r.fid;
      _effectiveFid ??= r.fid;
      KlpbbsApi.getMyRole(fid: r.fid).then((role) {
        if (mounted &&
            generation == _loadGeneration &&
            session == DioClient.sessionKey) {
          final canMod = role.canModerateFid(r.fid);
          if (canMod != _canModerate) setState(() => _canModerate = canMod);
        }
      }).catchError((_) {});
    }

    final likedList = _savedAccountState(prefs, 'liked_tids');
    final isLocalLiked = likedList.contains('$_effectiveTid');
    final isServerLiked = r.isLiked == true;
    if (_page == 1) {
      if (DioClient.isLoggedIn) {
        _liked = isServerLiked;
        if (isServerLiked != isLocalLiked) {
          _saveState('liked_tids', '$_effectiveTid', isServerLiked);
        }
      } else {
        _liked = false;
      }
      _likes = r.likes;
    }

    final favList = _savedAccountState(prefs, 'fav_tids');
    final isLocalFav = favList.contains('$_effectiveTid');

    if (DioClient.isLoggedIn) {
      if (r.hasExplicitFavState && r.isFavorited == true) {
        _favored = true;
        _favid = r.favid ?? (KlpbbsApi.getCachedFavid(_effectiveTid));
        _saveState('fav_tids', '$_effectiveTid', true);
      } else if (r.hasExplicitFavState && r.isFavorited == false) {
        // 服务端明确给出了未激活收藏态，坚决判定为 false 并清除历史残留的污染标记
        _favored = false;
        _favid = null;
        if (isLocalFav) {
          _saveState('fav_tids', '$_effectiveTid', false);
        }
      } else if (isLocalFav && !r.hasExplicitFavState) {
        _favored = true;
        _favid = KlpbbsApi.getCachedFavid(_effectiveTid);
      } else {
        // 关键防御：未给出明确激活类或未被命中时，保持 false，杜绝黄色星星闪烁；由后续 checkThreadFavorited 异步权威定夺
        _favored = false;
        _favid = null;
      }

      // 无论首屏是否推测出状态，均发起权威端点异步兜底核验，确保 100% 与网页端实际收藏状态保持绝对同步
      KlpbbsApi.checkThreadFavorited(_effectiveTid).then((serverFav) {
        if (serverFav != null &&
            mounted &&
            generation == _loadGeneration &&
            session == DioClient.sessionKey &&
            _favored != serverFav) {
          setState(() {
            _favored = serverFav;
            _favid = serverFav ? KlpbbsApi.getCachedFavid(_effectiveTid) : null;
          });
          _saveState('fav_tids', '$_effectiveTid', serverFav);
        }
      }).catchError((_) {});
    } else {
      // 未登录用户绝不展示高亮激活收藏态
      _favored = false;
      _favid = null;
    }

    _favorites = r.favorites;
    _views = r.views;
    _replies = r.replies;
    _totalPages = r.totalPages;
    if (_page == 1 || _tags.isEmpty) {
      _tags = r.tags;
    }
    _floors = r.floors;
    final likedPidsList =
        _savedAccountState(prefs, 'liked_pids_$_effectiveTid');
    _likedFloorPids.clear();
    for (final s in likedPidsList) {
      final p = int.tryParse(s);
      if (p != null) _likedFloorPids.add(p);
    }
    if (r.floors != null) {
      for (final f in (r.floors as List<PostFloor>)) {
        if (f.isLiked && f.pid != null && f.pid! > 0) {
          _likedFloorPids.add(f.pid!);
        }
      }
    }
    if (_page == 1 || _stamp == null) {
      _stamp = r.stamp;
      _stampUrl = r.stampUrl;
    }
    if (r.aiSummary != null) {
      _aiSummary = r.aiSummary;
    }
    if (_ordertype != null) {
      // 若用户明确指定了 ordertype（1 = 倒序，2 = 正序），必须以明确参数为准
      _isDescOrder = (_ordertype == 1);
    } else if (_page == 1) {
      // 仅在第 1 页初始化时，由服务端解析判断当前主题默认是正序还是倒序，后续翻页严禁被推断误翻转
      _isDescOrder = r.isDescOrder;
      // 关键：默认保持 _ordertype = null，沿用服务端天然排序，切勿强行设为 1 或 2 触发服务端 SQL 缺陷！
      _ordertype = null;
    }
  }

  @override
  void dispose() {
    AppConfig.instance.removeListener(_onConfigChanged);
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    // 退出帖子页时停止 B站/网易云/通用音频与视频内嵌播放器（若由外层管理生命周期则不盲目停止）
    if (widget.stopPlayersOnDispose) {
      BiliVideoPlayer.stopAll();
      NetEaseMusicPlayer.stopAll();
      GeneralAudioPlayer.stopAll();
      GeneralVideoPlayer.stopAll();
    }
    _inThreadSearchCtrl.dispose();
    _scrollCtrl.dispose();
    _scrolledNotifier.dispose();
    _showBackToTopNotifier.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _viewCacheAnyway = false;
      _activeOutage = null;
    });
    _loadAndInit(forceRefresh: true);
  }

  /// 切换正序 / 倒序浏览
  void _toggleOrder() {
    final nextDesc = !_isDescOrder;
    final nextOt = nextDesc ? 1 : 2;
    setState(() {
      _ordertype = nextOt;
      _isDescOrder = nextDesc;
      _page = 1; // 切换排序重置为第1页
    });
    // 清除该帖子的缓存，确保网络请求获取全新排序结果
    KlpbbsApi.clearThreadDetailCache(_effectiveTid);
    _loadAndInit(forceRefresh: true);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nextDesc ? '已切换为 倒序浏览 (最新在前)' : '已切换为 正序浏览 (最早在前)'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onToggleFloorLiked(int? pid) async {
    if (pid == null ||
        pid <= 0 ||
        _likingFloorPids.contains(pid) ||
        !_canSendLike(context)) {
      return;
    }
    final session = DioClient.sessionKey;
    final tid = _effectiveTid;
    final nextLiked = !_likedFloorPids.contains(pid);
    setState(() => _likingFloorPids.add(pid));
    try {
      final result = await KlpbbsApi.likeFloor(tid, pid, support: nextLiked);
      if (!mounted || session != DioClient.sessionKey || tid != _effectiveTid) {
        return;
      }
      if (result.success) {
        setState(() {
          if (result.isLiked) {
            _likedFloorPids.add(pid);
          } else {
            _likedFloorPids.remove(pid);
          }
        });
        await _saveState('liked_pids_$tid', '$pid', result.isLiked);
        if (mounted &&
            session == DioClient.sessionKey &&
            tid == _effectiveTid) {
          _loadAndInit(forceRefresh: true);
        }
      }
      if (mounted && session == DioClient.sessionKey) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (mounted && session == DioClient.sessionKey) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('点赞操作失败：$error')));
      }
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _likingFloorPids.remove(pid));
      }
    }
  }

  static String formatFloorNumber(int n) {
    if (n == 1) return '楼主';
    if (n == 2) return '2 楼 (沙发)';
    if (n == 3) return '3 楼 (板凳)';
    if (n == 4) return '4 楼 (地板)';
    return '$n 楼';
  }

  static int? _extractFloorDigit(String s, {bool isReply = false}) {
    if (s.isEmpty) return null;
    if (s == '楼主' || s.contains('楼主')) {
      return isReply ? 2 : 1;
    }
    final m = RegExp(r'(\d+)').firstMatch(s);
    if (m != null) {
      final val = int.tryParse(m.group(1)!);
      if (val != null) {
        if (isReply && val == 1) return 2;
        return val;
      }
    }
    if (s.contains('沙发')) return 2;
    if (s.contains('板凳')) return 3;
    if (s.contains('地板')) return 4;
    return null;
  }

  static int? _parseFloorNumberFromLabel(String label) {
    final s = label.trim();
    if (s.isEmpty) return null;
    if (s == '楼主' || s.contains('楼主')) return 1;
    final m = RegExp(r'^(\d+)').firstMatch(s);
    if (m != null) return int.tryParse(m.group(1)!);
    final anyDigit = RegExp(r'(\d+)').firstMatch(s);
    if (anyDigit != null) return int.tryParse(anyDigit.group(1)!);
    if (s.contains('沙发')) return 2;
    if (s.contains('板凳')) return 3;
    if (s.contains('地板')) return 4;
    return null;
  }

  static List<String> computeDisplayFloorNumbers(
    List<PostFloor> floors, {
    required int page,
    required bool isDescOrder,
    int? totalReplies,
  }) {
    if (floors.isEmpty) return const [];
    final result = List<String>.filled(floors.length, '');

    int startIndex = 0;
    if (page == 1) {
      result[0] = '楼主';
      startIndex = 1;
    }

    if (startIndex >= floors.length) return result;

    if (!isDescOrder) {
      // ===== 正序排列 (Ascending) =====
      // 第 1 页：包含 1 楼主 + 最多 10 楼回帖（即 2 楼 ~ 11 楼）
      // 第 P 页 (P >= 2)：前 P-1 页累计包含了 1 + (P-1)*10 楼，因此第 P 页基线必须从 1 + (P-1)*10 开始！
      int currentFloorNum = (page == 1) ? 1 : (1 + (page - 1) * 10);
      for (int i = startIndex; i < floors.length; i++) {
        final f = floors[i];
        final rawNum = _extractFloorDigit(f.floorNumber, isReply: true);

        if (page == 1 && i == 1) {
          currentFloorNum = 2;
        } else if (rawNum != null && rawNum > currentFloorNum) {
          currentFloorNum = rawNum;
        } else {
          currentFloorNum++;
        }
        result[i] = formatFloorNumber(currentFloorNum);
      }
    } else {
      // ===== 倒序排列 (Descending) =====
      final baseNums = List<int>.filled(floors.length, 0);
      final total =
          (totalReplies != null && totalReplies > 0) ? (totalReplies + 1) : 16;

      for (int i = startIndex; i < floors.length; i++) {
        final f = floors[i];
        final rawNum = _extractFloorDigit(f.floorNumber, isReply: true);
        if (rawNum != null && rawNum >= 2) {
          baseNums[i] = rawNum;
        } else {
          final offset =
              page == 1 ? (i > 0 ? i - 1 : 0) : 9 + (page - 2) * 10 + i;
          baseNums[i] = (total - offset).clamp(2, total);
        }
      }

      // 关键：倒向反向校准（Backward pass）！
      if (floors.length - 1 >= startIndex) {
        if (baseNums.last < 2) baseNums.last = 2;
        for (int i = floors.length - 2; i >= startIndex; i--) {
          if (baseNums[i] <= baseNums[i + 1]) {
            baseNums[i] = baseNums[i + 1] + 1;
          }
        }
      }

      for (int i = startIndex; i < floors.length; i++) {
        result[i] = formatFloorNumber(baseNums[i]);
      }
    }

    return result;
  }

  /// 回帖分割与排序栏（模拟 Discuz comiis_pltit）
  Widget _buildRepliesDivider(BuildContext context, {int repliesCount = 0}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(80),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.forum_outlined,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            '全部评论',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          if (repliesCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$repliesCount',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
          const Spacer(),
          // 正序 / 倒序 切换胶囊按钮
          InkWell(
            onTap: _toggleOrder,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withAlpha(100),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withAlpha(100),
                  width: 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isDescOrder
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isDescOrder ? '倒序浏览' : '正序浏览',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.swap_vert_rounded,
                    size: 14,
                    color: colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ThreadDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tid != widget.tid) {
      _effectiveTid = widget.tid;
      _page = 1;
      _ordertype = null;
      _firstAuthorUid = null;
      _floorItemKeys.clear();
      _highlightedFloorIndex = null;
      _pendingTargetFloor = null;
      _floors = const [];
      _title = '';
      _stamp = null;
      _stampUrl = null;
      _aiSummary = null;
      _favored = false;
      _liked = false;
      _reload();
    }
    if (oldWidget.fid != widget.fid && widget.fid != null) {
      _effectiveFid = widget.fid;
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
        color: Theme.of(context).colorScheme.primary,
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

  /// 只保存当前账号已获服务器确认的状态。
  Future<void> _saveState(String key, String tid, bool add) async {
    final scoped = _accountStateKey(key);
    final session = DioClient.sessionKey;
    if (scoped == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey) return;
      final list = (prefs.getStringList(scoped) ?? <String>[]).toList();
      if (add) {
        if (!list.contains(tid)) list.add(tid);
      } else {
        list.remove(tid);
      }
      await prefs.setStringList(scoped, list);
    } catch (_) {}
  }

  Future<void> _onLike() async {
    if (_likeBusy || !_canSendLike(context)) return;
    final session = DioClient.sessionKey;
    final tid = _effectiveTid;
    final nextLiked = !_liked;
    HapticFeedback.lightImpact();
    setState(() => _likeBusy = true);
    try {
      final result = await KlpbbsApi.recommendThread(tid, support: nextLiked);
      if (!mounted || session != DioClient.sessionKey || tid != _effectiveTid) {
        return;
      }
      if (result.success) {
        setState(() => _liked = result.isLiked);
        await _saveState('liked_tids', '$tid', result.isLiked);
        if (mounted &&
            session == DioClient.sessionKey &&
            tid == _effectiveTid) {
          _loadAndInit(forceRefresh: true);
        }
      }
      if (mounted && session == DioClient.sessionKey) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (mounted && session == DioClient.sessionKey) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('点赞操作失败：$error')));
      }
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _likeBusy = false);
      }
    }
  }

  void _setFavoriteState(bool favored) {
    setState(() {
      if (_favored != favored) {
        _favorites += favored ? 1 : (_favorites > 0 ? -1 : 0);
      }
      _favored = favored;
      _favid = favored ? KlpbbsApi.getCachedFavid(_effectiveTid) : null;
    });
    _saveState('fav_tids', '$_effectiveTid', favored);
  }

  Future<void> _onFavorite({bool openDialog = false}) async {
    if (_favoriteBusy) return;
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('请先登录论坛账号后再进行收藏'),
        action: SnackBarAction(
            label: '去登录',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LoginPage()))),
      ));
      return;
    }
    final session = DioClient.sessionKey;
    final tid = _effectiveTid;
    bool current() =>
        mounted && session == DioClient.sessionKey && tid == _effectiveTid;
    final messenger = ScaffoldMessenger.of(context);
    if (openDialog) {
      final result = await FavoriteDialog.show(context,
          tid: tid,
          title: _title,
          author: _floors.isNotEmpty ? _floors.first.author : '',
          isFavorited: _favored,
          favid: _favid, onFavoritedChanged: (value) {
        if (current()) _setFavoriteState(value);
      });
      if (result != null && current()) _setFavoriteState(result);
      return;
    }
    final nextFavored = !_favored;
    setState(() => _favoriteBusy = true);
    try {
      final result = nextFavored
          ? await KlpbbsApi.favoriteThread(tid)
          : await KlpbbsApi.unfavoriteThread(tid, favid: _favid);
      if (!current()) return;
      if (result.success) _setFavoriteState(nextFavored);
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    } catch (error) {
      if (current()) {
        messenger.showSnackBar(SnackBar(content: Text('收藏操作失败：$error')));
      }
    } finally {
      if (current()) setState(() => _favoriteBusy = false);
    }
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
                    const Icon(Icons.thumb_up,
                        size: 20, color: Color(0xFF1976D2)),
                    const SizedBox(width: 8),
                    Text(
                      '点赞与评分用户详情 (${rewards.isNotEmpty ? rewards.length : _likes})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
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
                            const Icon(Icons.thumb_up_alt_outlined,
                                size: 48, color: Colors.grey),
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
                              size: 32,
                              avatarUrl: r.avatar,
                              reserveFrameSpace: true,
                            ),
                            title: Text(
                              r.user,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              r.reason.isNotEmpty ? r.reason : '为楼主送上支持！',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
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
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          UserSpacePage(uid: r.uid!)),
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

  Future<void> _onReplyGlobal() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PostPage(
          tid: _effectiveTid,
          fid: _effectiveFid,
          threadTitle: _title,
          initialMessage: null,
        ),
      ),
    );
    if (ok == true && mounted) {
      _reload();
    }
  }

  void _goPage(int page) {
    final willScrollToPending = _pendingTargetFloor != null;
    _page = page;
    _loadAndInit();
    // 分页后若无待跳转楼层则回到顶部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!willScrollToPending &&
          _pendingTargetFloor == null &&
          _scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(0);
      }
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
      case 'toggle_search':
        setState(() {
          _showInThreadSearch = !_showInThreadSearch;
          if (!_showInThreadSearch) {
            _inThreadSearchCtrl.clear();
            _inThreadSearchMatches = [];
            _inThreadSearchCurrentIdx = 0;
          }
        });
        break;
      case 'toggle_forum_sidebar':
        if (widget.onToggleForumSidebar != null) {
          widget.onToggleForumSidebar!();
        } else if (ResponsiveBreakpoints.isDesktop(context)) {
          setState(() {
            _showForumSidebar = !_showForumSidebar;
            AppConfig.setThreadLeftEnabled(_showForumSidebar);
          });
        } else if (currentFid != null && currentFid! > 0) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadListPage(
                fid: currentFid!,
                title: _forumName ??
                    ComiisParser.getForumNameByFid(currentFid) ??
                    '版块列表',
              ),
            ),
          );
        }
        break;
      case 'topic_admin':
        final snap = await _future;
        if (!mounted) return;
        final targetFid = _threadFid ?? snap.fid ?? 2;
        final ok = await TopicAdminDialog.show(
          context,
          fid: targetFid,
          tid: widget.tid,
          threadTitle: _title.isNotEmpty ? _title : snap.title,
        );
        if (ok == true && mounted) _reload();
        break;
      case 'edit':
        final navigator = Navigator.of(context);
        final confirmed = await confirmWrite(context, '编辑帖子');
        if (!confirmed || !mounted) return;
        // 预填当前标题/内容（传递真实 fid、tid、pid 与标题，正文由 PostPage 自动拉取）
        final snap = await _future;
        if (!mounted) return;
        final floors = snap.floors;
        final first = floors.isNotEmpty ? floors.first : null;
        final ok = await navigator.push<bool>(
          MaterialPageRoute(
            builder: (_) => PostPage(
              isEdit: true,
              fid: snap.fid ?? 2,
              tid: widget.tid,
              pid: first?.pid,
              editSubject: _title.isNotEmpty ? _title : snap.title,
            ),
          ),
        );
        if (ok == true && mounted) _reload();
        break;
      case 'delete':
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        final reasonCtrl = TextEditingController(text: '违规内容');
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dlgCtx) => AlertDialog(
            title: Text(_canModerate ? '管理删除主题' : '删除主题'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('确定要删除该主题吗？此操作不可撤销。'),
                if (_canModerate) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: '管理删帖理由',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dlgCtx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dlgCtx).colorScheme.error,
                  foregroundColor: Theme.of(dlgCtx).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(dlgCtx).pop(true),
                child: const Text('确认删除'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        try {
          bool ok = false;
          String? failMsg;
          final snap = await _future;
          final targetFid = _threadFid ?? snap.fid ?? 2;
          if (_canModerate) {
            final reason = reasonCtrl.text.trim().isEmpty
                ? '违规内容'
                : reasonCtrl.text.trim();
            final res = await KlpbbsApi.moderateDeleteThread(
              fid: targetFid,
              tid: widget.tid,
              reason: reason,
            );
            ok = res.success;
            failMsg = res.message;
          } else {
            final targetPid =
                snap.floors.isNotEmpty ? (snap.floors.first.pid ?? 1) : 1;
            ok = await KlpbbsApi.deletePost(targetFid, widget.tid, targetPid);
          }
          messenger.showSnackBar(
            SnackBar(
                content: Text(ok ? '已删除主题' : (failMsg ?? '删除失败（可能无权限或已被处理）'))),
          );
          if (ok && mounted) navigator.pop(true);
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
      case 'copy_link':
        final url = '${AppConfig.baseUrl}thread-${widget.tid}-1-1.html';
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('帖子链接已复制')),
          );
        }
        break;
      case 'open_browser':
        final url = '${AppConfig.baseUrl}thread-${widget.tid}-1-1.html';
        UrlHelper.openExternalBrowser(context, url);
        break;
      case 'ai_summary':
        if (_aiSummary == null) {
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('正在获取 AI 总结...'),
                  duration: Duration(seconds: 1)),
            );
            final res =
                await KlpbbsApi.fetchAiSummary(widget.tid, forceRefresh: true);
            if (res != null && mounted) {
              setState(() => _aiSummary = res);
              _scrollCtrl.animateTo(0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut);
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('该帖子暂无 AI 总结数据')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('获取 AI 总结异常: $e')));
            }
          }
        } else {
          _scrollCtrl.animateTo(0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
        break;
      case 'toggle_order':
        _toggleOrder();
        break;
    }
  }

  bool get _canEditPost {
    final myUid = _myUid;
    if (myUid == null || myUid <= 0) return false;
    if (_canModerate) return true;
    if (_firstAuthorUid != null && _firstAuthorUid == myUid) return true;
    if (_floors.isNotEmpty && _floors.first.canEdit) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    final theme = Theme.of(context);
    final hasThreadContent = _accessRestriction == null && _floors.isNotEmpty;
    final hasSidebarToggle = widget.onToggleForumSidebar != null ||
        (widget.canShowForumSidebar &&
            isDesktop &&
            currentFid != null &&
            currentFid! > 0);
    final isSidebarOpen = widget.onToggleForumSidebar != null
        ? (widget.isForumSidebarVisible ?? true)
        : _showForumSidebar;

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Scaffold(
        drawer: widget.showBackButton ? const GlobalAppDrawer() : null,
        drawerEdgeDragWidth: 50.0,
        appBar: AppBar(
          automaticallyImplyLeading: widget.showBackButton,
          leading: widget.showBackButton
              ? GlobalNavLeading(showBackButton: widget.showBackButton)
              : null,
          leadingWidth: widget.showBackButton
              ? GlobalNavLeading.preferredLeadingWidth(
                  context,
                  showBackButton: widget.showBackButton,
                )
              : 0,
          title: ValueListenableBuilder<bool>(
            valueListenable: _scrolledNotifier,
            builder: (context, scrolled, _) {
              return Text(
                scrolled && _title.isNotEmpty ? _title : '帖子详情',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
          actions: [
            if (hasThreadContent)
              IconButton(
                icon: Icon(
                  _isDescOrder
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 20,
                ),
                tooltip: _isDescOrder
                    ? '当前为倒序浏览（最新在前），点击切换为正序'
                    : '当前为正序浏览（最早在前），点击切换为倒序',
                onPressed: _toggleOrder,
              ),
            if (hasSidebarToggle)
              IconButton(
                icon: Icon(
                  isSidebarOpen
                      ? Icons.view_sidebar_rounded
                      : Icons.view_sidebar_outlined,
                  size: 20,
                  color: isSidebarOpen ? theme.colorScheme.primary : null,
                ),
                tooltip: isSidebarOpen ? '收起版块列表' : '展开版块列表',
                onPressed: () {
                  if (widget.onToggleForumSidebar != null) {
                    widget.onToggleForumSidebar!();
                  } else {
                    setState(() {
                      _showForumSidebar = !_showForumSidebar;
                      AppConfig.setThreadLeftEnabled(_showForumSidebar);
                    });
                  }
                },
              ),
            if (hasThreadContent)
              IconButton(
                icon: Icon(
                  _showInThreadSearch
                      ? Icons.search_off_rounded
                      : Icons.search_rounded,
                  size: 20,
                  color: _showInThreadSearch ? theme.colorScheme.primary : null,
                ),
                tooltip: _showInThreadSearch ? '关闭楼层搜索' : '搜索本帖楼层',
                onPressed: () {
                  setState(() {
                    _showInThreadSearch = !_showInThreadSearch;
                    if (!_showInThreadSearch) {
                      _inThreadSearchCtrl.clear();
                      _inThreadSearchMatches = [];
                      _inThreadSearchCurrentIdx = 0;
                    }
                  });
                },
              ),
            if (isDesktop && hasThreadContent)
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: '工作台排版微调 (自由画布)',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (ctx) => VisualGridCanvas(
                        initialLayout: AppConfig.threadDashboardLayout,
                        pageCategory: 'thread',
                        onSave: (_) {
                          if (mounted) setState(() {});
                        },
                        onExit: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新帖子 (F5)',
              onPressed: _reload,
            ),
            if (hasThreadContent)
              PopupMenuButton<String>(
                tooltip: '更多选项',
                onSelected: (v) => _onMenuAction(v),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle_search',
                    child: Row(
                      children: [
                        Icon(
                          _showInThreadSearch
                              ? Icons.search_off_rounded
                              : Icons.search_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(_showInThreadSearch ? '关闭楼层搜索' : '搜索本帖楼层'),
                      ],
                    ),
                  ),
                  if (hasSidebarToggle)
                    PopupMenuItem(
                      value: 'toggle_forum_sidebar',
                      child: Row(
                        children: [
                          Icon(
                            isSidebarOpen
                                ? Icons.view_sidebar_rounded
                                : Icons.view_sidebar_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(isSidebarOpen ? '收起版块列表' : '展开版块列表'),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'toggle_order',
                    child: Row(
                      children: [
                        Icon(
                          _isDescOrder
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                            _isDescOrder ? '切换为正序浏览 (最早在前)' : '切换为倒序浏览 (最新在前)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'ai_summary',
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('AI 智能总结'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'copy_link',
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('复制链接'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'open_browser',
                    child: Row(
                      children: [
                        Icon(Icons.open_in_browser_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('浏览器打开'),
                      ],
                    ),
                  ),
                  if (_canModerate)
                    const PopupMenuItem(
                      value: 'topic_admin',
                      child: Row(
                        children: [
                          Icon(Icons.admin_panel_settings_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('管理此主题 (TopicAdmin)'),
                        ],
                      ),
                    ),
                  if (_canEditPost) ...[
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('编辑帖子'),
                        ],
                      ),
                    ),
                    if ((_firstAuthorUid != null &&
                            _myUid == _firstAuthorUid) ||
                        _canModerate)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18),
                            SizedBox(width: 8),
                            Text('删除帖子'),
                          ],
                        ),
                      ),
                  ],
                  if (!_canModerate &&
                      (_firstAuthorUid == null || _myUid != _firstAuthorUid))
                    const PopupMenuItem(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(Icons.report_problem_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('举报'),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
        body: Builder(
          builder: (context) {
            final mainDetailContent = FutureBuilder<ThreadDetailParsed>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const ThreadDetailSkeleton();
                }
                if (snap.hasError) {
                  if (snap.error
                      case final DiscuzThreadAccessException access) {
                    final returnFid = access.returnFid ?? currentFid;
                    return ThreadAccessView(
                      access: access,
                      onRetry: _reload,
                      onBackToForum: returnFid != null && returnFid > 0
                          ? () => Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => ThreadListPage(
                                    fid: returnFid,
                                    title: ComiisParser.getForumNameByFid(
                                            returnFid) ??
                                        _forumName ??
                                        '论坛板块',
                                  ),
                                ),
                              )
                          : null,
                      onLogin:
                          access.kind == DiscuzThreadAccessKind.loginRequired &&
                                  !DioClient.isLoggedIn
                              ? () async {
                                  await Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => const LoginPage()));
                                  if (mounted) _reload();
                                }
                              : null,
                    );
                  }
                  final errStr = snap.error.toString();
                  final outage = ServerOutageInfo.tryParse(snap.error);
                  if (outage != null && !_viewCacheAnyway) {
                    final otKey = _ordertype != null && _ordertype! > 0
                        ? '_ot$_ordertype'
                        : '';
                    final cacheKey =
                        'thread_detail_${_effectiveTid}_$_page$otKey';
                    final cached = PreloadService.instance
                        .get<ThreadDetailParsed>(cacheKey);
                    return ServerOutageView(
                      outage: outage,
                      onRetry: _reload,
                      onViewCache: cached != null
                          ? () {
                              setState(() {
                                _activeOutage = outage;
                                _viewCacheAnyway = true;
                                _future = Future.value(cached);
                              });
                            }
                          : null,
                      onGoHome: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst);
                        }
                      },
                    );
                  }
                  final is404 = errStr.contains('404') ||
                      errStr.contains('不存在') ||
                      errStr.contains('已删除') ||
                      errStr.contains('无访问权限') ||
                      errStr.contains('指定的主题不存在');
                  if (is404) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer
                                    .withAlpha(60),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.article_outlined,
                                size: 48,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '帖子不存在或已被删除',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '该主题可能已被版主清理、下架或链接有误 (HTTP 404)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (Navigator.of(context).canPop()) ...[
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                    icon:
                                        const Icon(Icons.arrow_back, size: 16),
                                    label: const Text('返回上一页'),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                FilledButton.icon(
                                  onPressed: _reload,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('重试'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded,
                              size: 48,
                              color: Theme.of(context).colorScheme.error),
                          const SizedBox(height: 12),
                          Text('加载失败：$errStr', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _reload,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
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
                return Column(
                  children: [
                    if (_activeOutage != null)
                      ServerOutageBanner(
                        outage: _activeOutage!,
                        onRetry: _reload,
                        onViewDetails: () {
                          setState(() => _viewCacheAnyway = false);
                        },
                        onDismiss: () => setState(() => _activeOutage = null),
                      ),
                    if (_showInThreadSearch) _buildInThreadSearchBar(floors),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async => _reload(),
                        child: ThreadLayoutWorkbench(
                          tid: _effectiveTid,
                          fid: data?.fid,
                          forumName: data?.forumName,
                          floors: floors,
                          scrollController: _scrollCtrl,
                          bottomBar: _buildBottomActions(floors),
                          floatingActionButton: _buildBackTopFab(),
                          currentPage: _page,
                          totalPages: data?.totalPages ?? _totalPages,
                          totalReplies: data?.replies ?? _replies,
                          isDescOrder: _isDescOrder,
                          onJumpToFloor: (idx) => _jumpToFloorIndex(idx),
                          onNavigateToFloor: (targetFloor) =>
                              _navigateToFloorNumber(targetFloor),
                          onSelectThread: (tid) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => ThreadDetailPage(
                                  tid: tid,
                                  fid: data?.fid,
                                ),
                              ),
                            );
                          },
                          onOpenRatingFilter: () {
                            final firstFloor =
                                floors.isNotEmpty ? floors.first : null;
                            final pid = firstFloor?.pid ?? 0;
                            RatingFilterHall.show(
                              context,
                              tid: widget.tid,
                              pid: pid,
                              fallbackRewards: firstFloor?.rewards
                                      .map((r) => FloorReward(
                                            username: r.user,
                                            uid: r.uid,
                                            amount: r.amount,
                                            reason: r.reason,
                                          ))
                                      .toList() ??
                                  const [],
                            );
                          },
                          child: Builder(
                            builder: (context) {
                              final displayFloorLabels =
                                  computeDisplayFloorNumbers(
                                floors,
                                page: _page,
                                isDescOrder: _isDescOrder,
                                totalReplies: data?.replies ?? _replies,
                              );
                              return CustomScrollView(
                                cacheExtent: 400.0,
                                controller: _scrollCtrl,
                                physics: const AlwaysScrollableScrollPhysics(),
                                slivers: [
                                  if (title.isNotEmpty)
                                    SliverToBoxAdapter(
                                      child: _buildThreadHeaderWidget(
                                          title, data, floors, context),
                                    ),
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, i) {
                                        final isThreadAuthor =
                                            floors[i].isThreadAuthor ||
                                                (_firstAuthorUid != null &&
                                                    floors[i].uid ==
                                                        _firstAuthorUid);
                                        final isFirstFloor = _page == 1 &&
                                            i == 0 &&
                                            (floors[i].floorNumber == '楼主' ||
                                                (_firstAuthorUid != null
                                                    ? (isThreadAuthor &&
                                                        !floors[i]
                                                            .floorNumber
                                                            .contains(
                                                                _digitRegex))
                                                    : !floors[i]
                                                        .floorNumber
                                                        .contains(
                                                            _digitRegex)));
                                        final displayFloor =
                                            displayFloorLabels.length > i
                                                ? displayFloorLabels[i]
                                                : null;
                                        final floorPid = floors[i].pid;
                                        final isFloorLiked = floorPid != null &&
                                            _likedFloorPids.contains(floorPid);
                                        return Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (_page == 1 &&
                                                i == 0 &&
                                                (_aiSummary != null ||
                                                    data?.aiSummary != null))
                                              AiSummaryCard(
                                                tid: _effectiveTid,
                                                initialData: _aiSummary ??
                                                    data?.aiSummary,
                                                onRefresh: () {
                                                  if (mounted) setState(() {});
                                                },
                                              ),
                                            if ((_page == 1 && i == 1) ||
                                                (_page > 1 && i == 0))
                                              _buildRepliesDivider(context,
                                                  repliesCount: data?.replies ??
                                                      _replies),
                                            _FloorView(
                                              key: _floorItemKeys.putIfAbsent(
                                                  i, () => GlobalKey()),
                                              floor: floors[i],
                                              index: i,
                                              page: _page,
                                              tid: _effectiveTid,
                                              fid: data?.fid,
                                              threadTitle:
                                                  (data?.title ?? _title)
                                                          .isNotEmpty
                                                      ? (data?.title ?? _title)
                                                      : null,
                                              displayFloorNumber: displayFloor,
                                              isFirstFloor: isFirstFloor,
                                              isThreadAuthor: isThreadAuthor,
                                              isDescOrder: _isDescOrder,
                                              totalReplies:
                                                  data?.replies ?? _replies,
                                              isHighlighted:
                                                  _highlightedFloorIndex == i,
                                              stamp: isFirstFloor
                                                  ? (data?.stamp ?? _stamp)
                                                  : null,
                                              stampUrl: isFirstFloor
                                                  ? (data?.stampUrl ??
                                                      _stampUrl)
                                                  : null,
                                              isLiked: isFirstFloor
                                                  ? _liked
                                                  : isFloorLiked,
                                              likesCount: isFirstFloor
                                                  ? _likes
                                                  : floors[i].likes,
                                              likeBusy: isFirstFloor
                                                  ? _likeBusy
                                                  : _likingFloorPids
                                                      .contains(floorPid),
                                              onLikeToggle: isFirstFloor
                                                  ? _onLike
                                                  : () => _onToggleFloorLiked(
                                                      floorPid),
                                              onReload: _reload,
                                              myUid: _myUid,
                                              canModerate: _canModerate,
                                            ),
                                            if (_page == 1 &&
                                                i == 0 &&
                                                _tags.isNotEmpty)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        14, 6, 14, 6),
                                                child: _buildTagsWrap(),
                                              ),
                                          ],
                                        );
                                      },
                                      childCount: floors.length,
                                      addRepaintBoundaries: false,
                                    ),
                                  ),
                                  SliverToBoxAdapter(
                                    child:
                                        _buildThreadFooterWidget(data, context),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );

            if (widget.canShowForumSidebar &&
                isDesktop &&
                _showForumSidebar &&
                currentFid != null &&
                currentFid! > 0) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: AppConfig.threadForumSidebarWidth,
                    child: RepaintBoundary(
                      child: ThreadListPage(
                        fid: currentFid!,
                        title: _forumName ??
                            ComiisParser.getForumNameByFid(currentFid) ??
                            '版块列表',
                        isSidebar: true,
                        activeTid: _effectiveTid,
                        onThreadSelected: _onSidebarSelectThread,
                        onCloseSidebar: () {
                          setState(() {
                            _showForumSidebar = false;
                            AppConfig.setThreadLeftEnabled(false);
                          });
                        },
                      ),
                    ),
                  ),
                  _buildForumSidebarSplitter(),
                  Expanded(
                    child: mainDetailContent,
                  ),
                ],
              );
            }

            return mainDetailContent;
          },
        ),
      ),
    );
  }

  Widget _buildTagsWrap() {
    return Wrap(
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        for (final tag in _tags)
          ActionChip(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            labelPadding: EdgeInsets.zero,
            backgroundColor:
                Theme.of(context).colorScheme.primaryContainer.withAlpha(45),
            side: BorderSide(
              color: Theme.of(context).colorScheme.primary.withAlpha(70),
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
    );
  }

  Widget _buildThreadHeaderWidget(String title, ThreadDetailParsed? data,
      List<PostFloor> floors, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
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
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      Icon(
                        Icons.home_outlined,
                        size: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withAlpha(200),
                      ),
                      Text(
                        '论坛',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      for (final bc in (data?.breadcrumbs ??
                          [
                            if ((data?.forumName ?? '').isNotEmpty)
                              data!.forumName,
                          ])) ...[
                        Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: Theme.of(context).colorScheme.outlineVariant,
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
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withAlpha(40),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              bc,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
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
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withAlpha(120),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              typeName,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.35,
                      fontSize: 18,
                    ),
              ),
            ],
          ),
        ),
        // 发布日期 + 最近回复日期 (左侧) + 浏览/回复/点赞量 (右侧)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final dateItems = <Widget>[
                if ((data?.publishDate ?? '').isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withAlpha(190),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '发布 ${data!.publishDate}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withAlpha(200),
                              fontSize: 11.5,
                            ),
                      ),
                    ],
                  ),
                if ((data?.lastReplyDate ?? '').isNotEmpty)
                  Text(
                    '最近回复 ${data!.lastReplyDate}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withAlpha(200),
                          fontSize: 11.5,
                        ),
                  ),
              ];

              final statsWidget = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withAlpha(190),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${(_views > 0 ? _views : (data?.views ?? 0))} 浏览 · ${(_replies > 0 ? _replies : (data?.replies ?? (floors.length > 1 ? floors.length - 1 : 0)))} 回复 · ${(_likes > 0 ? _likes : (data?.likes ?? 0))} 点赞',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withAlpha(200),
                          fontSize: 11.5,
                        ),
                  ),
                ],
              );

              if (constraints.maxWidth > 520) {
                return Row(
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 4,
                      children: dateItems,
                    ),
                    const Spacer(),
                    statsWidget,
                  ],
                );
              } else {
                return Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 4,
                      children: dateItems,
                    ),
                    statsWidget,
                  ],
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildThreadFooterWidget(
      ThreadDetailParsed? data, BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                await Clipboard.setData(ClipboardData(text: url));
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
                    onPressed: _page > 1 ? () => _goPage(_page - 1) : null,
                  ),
                  if (data!.totalPages <= 7)
                    for (var p = 1; p <= data.totalPages; p++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text('$p'),
                          selected: p == _page,
                          onSelected: (_) => _goPage(p),
                          labelStyle: const TextStyle(fontSize: 13),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                  else ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _jumpPage(data.totalPages),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withAlpha(70),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '$_page / ${data.totalPages} · 点此跳页',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
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
        const SizedBox(height: 64),
      ],
    );
  }

  Widget _buildBottomActions(List<PostFloor> currentFloors) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withAlpha(60),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onLongPress: () => _showLikedUsersDialog(
                    currentFloors.isNotEmpty ? currentFloors : _floors),
                child: _BottomAction(
                  icon: _liked ? Icons.thumb_up : Icons.thumb_up_outlined,
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
                  final shareText = _title.isNotEmpty ? '$_title $url' : url;
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
    );
  }

  Widget _buildBackTopFab() {
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _showBackToTopNotifier,
      builder: (context, showTop, _) {
        return ScrollDirectionAwareFab(
          isVisible: showTop,
          child: SafeArea(
            child: isDesktop
                ? FloatingActionButton.extended(
                    heroTag: 'back_top',
                    tooltip: '回到顶部 (Home / PgUp)',
                    elevation: 4,
                    onPressed: () {
                      if (_scrollCtrl.hasClients) {
                        _scrollCtrl.animateTo(
                          0,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    label: const Text(
                      '回到顶部',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  )
                : FloatingActionButton.small(
                    heroTag: 'back_top',
                    tooltip: '回顶部',
                    elevation: 3,
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
        );
      },
    );
  }

  void _jumpToFloorIndex(int idx) {
    if (idx < 0 || idx >= _floors.length) return;
    setState(() {
      _highlightedFloorIndex = idx;
    });
    // 2.5秒后自动淡出高亮
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && _highlightedFloorIndex == idx) {
        setState(() {
          _highlightedFloorIndex = null;
        });
      }
    });

    if (!_scrollCtrl.hasClients) return;
    if (idx <= 0) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (_floors.isNotEmpty && idx >= _floors.length - 1) {
      _scrollCtrl
          .animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      )
          .then((_) {
        if (mounted &&
            _scrollCtrl.hasClients &&
            _scrollCtrl.position.pixels <
                _scrollCtrl.position.maxScrollExtent) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
      return;
    }

    final key = _floorItemKeys[idx];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    } else {
      // 离屏虚拟化区域平滑过渡定位：基于楼层高度精确估算
      final baseTop = _page == 1 ? 550.0 : 150.0;
      final estimatedOffset = (baseTop + idx * 240.0)
          .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
      _scrollCtrl
          .animateTo(
        estimatedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      )
          .then((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final lateCtx = _floorItemKeys[idx]?.currentContext;
          if (lateCtx != null) {
            Scrollable.ensureVisible(
              lateCtx,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: 0.05,
            );
          }
        });
      });
    }
  }

  void _scrollToFloorNumberInCurrentPage(int targetFloor) {
    if (!mounted || _floors.isEmpty) return;

    if (targetFloor == -1) {
      if (_isDescOrder) {
        final idx = (_page == 1 && _floors.length > 1) ? 1 : 0;
        _jumpToFloorIndex(idx);
      } else {
        _jumpToFloorIndex((_floors.length - 1).clamp(0, _floors.length - 1));
      }
      return;
    }

    int? targetIndex;

    // 1. 楼主特殊直达（第 1 页 index 0）
    if (targetFloor == 1 && _page == 1) {
      targetIndex = 0;
    }

    // 2. 匹配实际在界面上呈现的权威楼层号标签
    final displayFloorLabels = computeDisplayFloorNumbers(
      _floors,
      page: _page,
      isDescOrder: _isDescOrder,
      totalReplies: _replies,
    );

    if (targetIndex == null) {
      for (int i = 0; i < displayFloorLabels.length; i++) {
        final label = displayFloorLabels[i];
        final num = _parseFloorNumberFromLabel(label);
        if (num == targetFloor) {
          targetIndex = i;
          break;
        }
      }
    }

    // 3. 原始楼层文字与编号比对兜底
    if (targetIndex == null) {
      for (int i = 0; i < _floors.length; i++) {
        final f = _floors[i];
        final fn = f.floorNumber.replaceAll(RegExp(r'[^\d]'), '');
        if (fn.isNotEmpty && int.tryParse(fn) == targetFloor) {
          targetIndex = i;
          break;
        }
        if (targetFloor == 1 &&
            (f.floorNumber == '楼主' ||
                f.isThreadAuthor ||
                (_page == 1 && i == 0))) {
          targetIndex = i;
          break;
        }
        if (targetFloor == 2 && f.floorNumber.contains('沙发')) {
          targetIndex = i;
          break;
        }
        if (targetFloor == 3 && f.floorNumber.contains('板凳')) {
          targetIndex = i;
          break;
        }
        if (targetFloor == 4 && f.floorNumber.contains('地板')) {
          targetIndex = i;
          break;
        }
      }
    }

    // 4. 数学推导兜底（当服务端未能解析出单楼层明确标号时）
    if (targetIndex == null) {
      if (!_isDescOrder) {
        // 正序：第 1 页 1..10 楼（index 0..9）；第 2 页 11..20 楼（index 0..9）
        final expectedIdx =
            _page == 1 ? (targetFloor - 1) : (targetFloor - 11) % 10;
        if (expectedIdx >= 0 && expectedIdx < _floors.length) {
          targetIndex = expectedIdx;
        }
      } else {
        // 倒序：1楼在第1页 index 0；回复依序倒序下排
        final total = _replies > 0 ? _replies + 1 : _floors.length;
        if (targetFloor == 1) {
          targetIndex = 0;
        } else {
          final k = total - targetFloor;
          if (_page == 1) {
            final expectedIdx = 1 + k;
            if (expectedIdx >= 0 && expectedIdx < _floors.length) {
              targetIndex = expectedIdx;
            }
          } else {
            final expectedIdx = (k - 9) % 10;
            if (expectedIdx >= 0 && expectedIdx < _floors.length) {
              targetIndex = expectedIdx;
            }
          }
        }
      }
    }

    targetIndex ??= 0;
    _jumpToFloorIndex(targetIndex.clamp(0, _floors.length - 1));
  }

  void _navigateToFloorNumber(int targetFloor) {
    if (targetFloor <= 0 && targetFloor != -1) return;

    // 最新回帖 (-1) 特殊快捷跳转
    if (targetFloor == -1) {
      if (_isDescOrder) {
        if (_page == 1) {
          final idx = _floors.length > 1 ? 1 : 0;
          _jumpToFloorIndex(idx);
        } else {
          _pendingTargetFloor = -1;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('正在前往第 1 页定位最新回帖...'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _goPage(1);
        }
      } else {
        final lastPage = _totalPages > 0 ? _totalPages : 1;
        if (_page == lastPage) {
          _jumpToFloorIndex((_floors.length - 1).clamp(0, _floors.length - 1));
        } else {
          _pendingTargetFloor = -1;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('正在前往第 $lastPage 页定位最新回帖...'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _goPage(lastPage);
        }
      }
      return;
    }

    // 楼主 (1#) 特殊快捷跳转：楼主只在第 1 页
    if (targetFloor == 1) {
      if (_page == 1) {
        _scrollToFloorNumberInCurrentPage(1);
      } else {
        _pendingTargetFloor = 1;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在前往第 1 页定位楼主...'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _goPage(1);
      }
      return;
    }

    // 0. 优先在当前页全面检索：若该楼层已在当前页列表中，直接平滑定位，杜绝无谓跳页与打架！
    if (_floors.isNotEmpty) {
      final currentLabels = computeDisplayFloorNumbers(
        _floors,
        page: _page,
        isDescOrder: _isDescOrder,
        totalReplies: _replies,
      );
      for (int i = 0; i < currentLabels.length; i++) {
        if (_parseFloorNumberFromLabel(currentLabels[i]) == targetFloor) {
          _scrollToFloorNumberInCurrentPage(targetFloor);
          return;
        }
      }
    }

    final totalReplies = _replies;
    final totalFloors = totalReplies > 0 ? totalReplies + 1 : _floors.length;
    final totalPages = _totalPages > 0 ? _totalPages : 1;

    int targetPage = 1;
    if (!_isDescOrder) {
      // 正序：1..10 楼在第 1 页；11..20 楼在第 2 页...
      targetPage = targetFloor <= 10 ? 1 : 2 + ((targetFloor - 11) ~/ 10);
    } else {
      // 倒序：1楼永远在第1页；最新回复从第1页 index 1 往下排
      final k = totalFloors - targetFloor;
      if (k < 9) {
        targetPage = 1;
      } else {
        targetPage = 2 + ((k - 9) ~/ 10);
      }
    }

    // 边界限制
    if (totalPages > 1 && targetPage > totalPages) {
      targetPage = totalPages;
    }
    if (targetPage < 1) targetPage = 1;

    if (targetPage == _page) {
      _scrollToFloorNumberInCurrentPage(targetFloor);
    } else {
      _pendingTargetFloor = targetFloor;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在前往第 $targetPage 页定位 $targetFloor# 楼...'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _goPage(targetPage);
    }
  }

  Widget _buildInThreadSearchBar(List<PostFloor> allFloors) {
    if (!_showInThreadSearch) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalMatches = _inThreadSearchMatches.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withAlpha(240),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(80),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inThreadSearchCtrl,
              autofocus: true,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: '搜索本帖楼层、作者或发言内容...',
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withAlpha(150),
                  fontSize: 13,
                ),
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
              onChanged: (val) {
                final query = val.trim().toLowerCase();
                if (query.isEmpty) {
                  setState(() {
                    _inThreadSearchMatches = [];
                    _inThreadSearchCurrentIdx = 0;
                  });
                } else {
                  final matches = <int>[];
                  for (int i = 0; i < allFloors.length; i++) {
                    final f = allFloors[i];
                    if (f.author.toLowerCase().contains(query) ||
                        f.contentHtml.toLowerCase().contains(query) ||
                        f.floorNumber.toLowerCase().contains(query)) {
                      matches.add(i);
                    }
                  }
                  setState(() {
                    _inThreadSearchMatches = matches;
                    _inThreadSearchCurrentIdx = matches.isNotEmpty ? 1 : 0;
                  });
                  if (matches.isNotEmpty) {
                    _jumpToFloorIndex(matches.first);
                  }
                }
              },
            ),
          ),
          if (_inThreadSearchCtrl.text.isNotEmpty) ...[
            Text(
              totalMatches > 0
                  ? '$_inThreadSearchCurrentIdx / $totalMatches'
                  : '无匹配',
              style: TextStyle(
                fontSize: 12,
                color:
                    totalMatches > 0 ? colorScheme.primary : colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
              tooltip: '上一个匹配楼层',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: totalMatches > 1
                  ? () {
                      setState(() {
                        if (_inThreadSearchCurrentIdx <= 1) {
                          _inThreadSearchCurrentIdx = totalMatches;
                        } else {
                          _inThreadSearchCurrentIdx--;
                        }
                      });
                      _jumpToFloorIndex(_inThreadSearchMatches[
                          _inThreadSearchCurrentIdx - 1]);
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              tooltip: '下一个匹配楼层',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: totalMatches > 1
                  ? () {
                      setState(() {
                        if (_inThreadSearchCurrentIdx >= totalMatches) {
                          _inThreadSearchCurrentIdx = 1;
                        } else {
                          _inThreadSearchCurrentIdx++;
                        }
                      });
                      _jumpToFloorIndex(_inThreadSearchMatches[
                          _inThreadSearchCurrentIdx - 1]);
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 18),
              tooltip: '清空输入',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () {
                _inThreadSearchCtrl.clear();
                setState(() {
                  _inThreadSearchMatches = [];
                  _inThreadSearchCurrentIdx = 0;
                });
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: '关闭搜索',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              setState(() {
                _showInThreadSearch = false;
                _inThreadSearchCtrl.clear();
                _inThreadSearchMatches = [];
                _inThreadSearchCurrentIdx = 0;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildForumSidebarSplitter() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () {
          setState(() {
            AppConfig.setThreadForumSidebarWidth(380.0);
          });
        },
        onHorizontalDragUpdate: (details) {
          final delta = details.delta.dx;
          final newWidth =
              (AppConfig.threadForumSidebarWidth + delta).clamp(240.0, 720.0);
          setState(() {
            AppConfig.setThreadForumSidebarWidth(newWidth);
          });
        },
        child: Container(
          width: 8,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 2.5,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withAlpha(120),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
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
  final String? displayFloorNumber;
  final bool isFirstFloor;
  final bool isThreadAuthor;
  final bool isDescOrder;
  final int? totalReplies;
  final bool isHighlighted;
  final String? stamp;
  final String? stampUrl;
  final String? threadTitle;
  final bool? isLiked;
  final int? likesCount;
  final VoidCallback? onLikeToggle;
  final bool likeBusy;
  final VoidCallback? onReload;
  final int? myUid;
  final bool canModerate;

  const _FloorView({
    super.key,
    required this.floor,
    required this.index,
    this.page = 1,
    required this.tid,
    this.fid,
    this.displayFloorNumber,
    this.threadTitle,
    this.isFirstFloor = false,
    this.isThreadAuthor = false,
    this.isDescOrder = false,
    this.totalReplies,
    this.isHighlighted = false,
    this.stamp,
    this.stampUrl,
    this.isLiked,
    this.likesCount,
    this.onLikeToggle,
    this.likeBusy = false,
    this.onReload,
    this.myUid,
    this.canModerate = false,
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
  bool _likeBusy = false;
  late int _likesCount;

  bool get _canEdit {
    final myUid = widget.myUid;
    if (myUid == null || myUid <= 0 || floor.pid == null) return false;
    // 1. 管理员 / 超级版主 / 本版版主拥有编辑特权
    if (widget.canModerate) return true;
    // 2. 服务端 HTML 明确返回了编辑操作（已授权）
    if (floor.canEdit) return true;
    // 3. 当前用户是该楼层作者
    return floor.uid != null && floor.uid! > 0 && floor.uid == myUid;
  }

  bool get _isSelf {
    final myUid = widget.myUid;
    return myUid != null &&
        myUid > 0 &&
        floor.uid != null &&
        floor.uid == myUid;
  }

  bool get _canReport {
    if (widget.canModerate) return false;
    if (_isSelf) return false;
    return true;
  }

  bool get _isFirstFloorOverall {
    if (widget.isFirstFloor) return true;
    if (widget.page == 1 && index == 0) {
      if (floor.floorNumber == '楼主' ||
          floor.floorNumber == '1' ||
          floor.floorNumber == '1楼' ||
          floor.floorNumber == '1#') {
        return true;
      }
      if (widget.isThreadAuthor && !floor.floorNumber.contains(_digitRegex)) {
        return true;
      }
    }
    return false;
  }

  bool get _canSetBestAnswer {
    final myUid = widget.myUid;
    if (myUid == null || myUid <= 0) return false;
    final detailState =
        context.findAncestorStateOfType<_ThreadDetailPageState>();
    final isBounty = detailState?._isBountyThread ?? false;
    final isSolved = detailState?._isBountySolved ?? false;
    if (!isBounty || isSolved) return false;

    final firstAuthorUid = detailState?._firstAuthorUid;
    final isAuthor = (firstAuthorUid != null && firstAuthorUid == myUid);
    if (!isAuthor && !widget.canModerate) return false;

    if (widget.isFirstFloor || _isFirstFloorOverall) return false;
    if (floor.uid != null &&
        firstAuthorUid != null &&
        floor.uid == firstAuthorUid) {
      return false;
    }
    if (floor.pid == null || floor.pid! <= 0) return false;
    if (floor.isBestAnswer) return false;
    return true;
  }

  Future<void> _onSetBestAnswer(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: Color(0xFFFF9800)),
            SizedBox(width: 8),
            Text('采纳最佳答案'),
          ],
        ),
        content: Text(
          '确定要将 ${floor.author} 的回答采纳为最佳答案吗？\n\n'
          '采纳后系统将自动把悬赏铁粒结算给该答主，且悬赏帖将自动结贴，此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('确认采纳'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;
    try {
      final pid = floor.pid!;
      final ok = await KlpbbsApi.setBestAnswer(widget.tid, pid);
      if (ok) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已成功将该回答设为最佳答案并结贴！'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        widget.onReload?.call();
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('设置最佳答案失败，请稍后再试')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('设置最佳答案异常: $e')),
      );
    }
  }

  Future<void> _onEditFloor(BuildContext context) async {
    final navigator = Navigator.of(context);
    final detailState =
        context.findAncestorStateOfType<_ThreadDetailPageState>();
    final currentTitle = detailState?._title ?? '';

    final confirmed = await confirmWrite(
      context,
      widget.isFirstFloor ? '编辑帖子' : '编辑回复',
    );
    if (!confirmed || !mounted) return;

    final ok = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => PostPage(
          isEdit: true,
          fid: fid ?? 2,
          tid: tid,
          pid: floor.pid,
          editSubject: widget.isFirstFloor ? currentTitle : null,
        ),
      ),
    );
    if (ok == true && mounted) {
      widget.onReload?.call();
    }
  }

  String get _displayFloorNumber {
    // 0. 若外部传递了严格全局计算推导的楼层号（彻底消灭顺序错乱/Discuz倒序模板伪标记/重复沙发），坚决优先采用
    if (widget.displayFloorNumber != null &&
        widget.displayFloorNumber!.isNotEmpty) {
      return widget.displayFloorNumber!;
    }

    // 1. 如果是第1页第1楼，坚决锁定为楼主
    if (widget.isFirstFloor) {
      return '楼主';
    }

    // 2. 优先从服务端解析出的真实楼层编号呈现（Discuz 真实权威标识，杜绝虚假计算楼层）
    final fn = floor.floorNumber.trim();
    if (fn.isNotEmpty) {
      if (fn == '楼主') {
        // 非首楼的「楼主」一律是 Discuz 倒序计数归 1 产生的模板伪标号，真实为沙发！
        return '2 楼 (沙发)';
      }
      final numM = _digitRegex.firstMatch(fn);
      if (numM != null) {
        final rawNum =
            numM.groupCount >= 1 ? (numM.group(1) ?? numM[0]) : numM[0];
        final n = rawNum != null ? int.tryParse(rawNum) : null;
        if (n != null) {
          if (n == 2) return '2 楼 (沙发)';
          if (n == 3) return '3 楼 (板凳)';
          if (n == 4) return '4 楼 (地板)';
          return '$n 楼';
        }
      }
      if (fn.contains('沙发')) return '2 楼 (沙发)';
      if (fn.contains('板凳')) return '3 楼 (板凳)';
      if (fn.contains('地板')) return '4 楼 (地板)';
      if (fn.endsWith('#')) return '${fn.replaceAll('#', '')} 楼';
      return fn;
    }

    // 3. 楼层编号缺失时的容错保底推导（绝不将任何回复错误标记为「楼主」）
    if (widget.isDescOrder) {
      final total = widget.totalReplies ?? 0;
      final totalFloors = total > 0 ? total + 1 : 16;
      final offset = widget.page == 1
          ? (index > 0 ? index - 1 : 0)
          : 9 + (widget.page - 2) * 10 + index;
      final descFloor = totalFloors - offset;
      if (descFloor == 2) return '2 楼 (沙发)';
      if (descFloor == 3) return '3 楼 (板凳)';
      if (descFloor == 4) return '4 楼 (地板)';
      if (descFloor > 1) return '$descFloor 楼';
      return '2 楼 (沙发)';
    } else {
      if (widget.page == 1) {
        final floorNum = index + 1;
        if (floorNum == 2) return '2 楼 (沙发)';
        if (floorNum == 3) return '3 楼 (板凳)';
        if (floorNum == 4) return '4 楼 (地板)';
        if (floorNum > 1) return '$floorNum 楼';
        return '2 楼 (沙发)';
      } else {
        // 第 2 页及之后：第 1 页有 10 楼（1 楼主 + 9 回复），第 2 页 index 0 为 11 楼
        final globalFloor = 10 + (widget.page - 2) * 10 + index + 1;
        return '$globalFloor 楼';
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked ?? floor.isLiked;
    _likesCount = widget.likesCount ?? floor.likes;
    if (widget.isLiked == null) {
      _loadFloorLikedState();
    }
  }

  @override
  void didUpdateWidget(covariant _FloorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.floor.pid != widget.floor.pid ||
        oldWidget.floor.floorNumber != widget.floor.floorNumber ||
        oldWidget.isDescOrder != widget.isDescOrder) {
      _isLiked = widget.isLiked ?? floor.isLiked;
      _likesCount = widget.likesCount ?? floor.likes;
      if (widget.isLiked == null) {
        _loadFloorLikedState();
      }
    } else {
      if (widget.isLiked != null && widget.isLiked != _isLiked) {
        _isLiked = widget.isLiked!;
      }
      if (widget.likesCount != null && widget.likesCount != _likesCount) {
        _likesCount = widget.likesCount!;
      }
    }
  }

  Future<void> _loadFloorLikedState() async {
    if (floor.pid == null || floor.pid! <= 0) return;
    final key = _accountStateKey(
        widget.isFirstFloor ? 'liked_tids' : 'liked_pids_$tid');
    final value = widget.isFirstFloor ? '$tid' : '${floor.pid}';
    final session = DioClient.sessionKey;
    if (key == null) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(key) ?? const [];
      if (list.contains(value) && mounted && session == DioClient.sessionKey) {
        setState(() {
          _isLiked = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveFloorLikedState(bool liked) async {
    if (floor.pid == null || floor.pid! <= 0) return;
    final key = _accountStateKey(
        widget.isFirstFloor ? 'liked_tids' : 'liked_pids_$tid');
    final value = widget.isFirstFloor ? '$tid' : '${floor.pid}';
    final session = DioClient.sessionKey;
    if (key == null) return;
    try {
      final sp = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey) return;
      final list = (sp.getStringList(key) ?? <String>[]).toList();
      if (liked) {
        if (!list.contains(value)) list.add(value);
      } else {
        list.remove(value);
      }
      await sp.setStringList(key, list);
    } catch (_) {}
  }

  Future<void> _toggleFloorLike() async {
    if (_likeBusy || widget.likeBusy || !_canSendLike(context)) return;
    if (widget.onLikeToggle != null) {
      widget.onLikeToggle!();
      return;
    }
    final session = DioClient.sessionKey;
    final nextLiked = !_isLiked;
    setState(() => _likeBusy = true);
    try {
      final result = await KlpbbsApi.likeFloor(tid, floor.pid ?? 0,
          isFirstFloor: widget.isFirstFloor, support: nextLiked);
      if (!mounted || session != DioClient.sessionKey) return;
      if (result.success) {
        setState(() => _isLiked = result.isLiked);
        await _saveFloorLikedState(result.isLiked);
        widget.onReload?.call();
      }
      if (mounted && session == DioClient.sessionKey) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (mounted && session == DioClient.sessionKey) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('点赞操作失败：$error')));
      }
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _likeBusy = false);
      }
    }
  }

  Widget _buildSignature(ThemeData theme) {
    final rawSig = floor.signature.trim();
    if (rawSig.isEmpty) return const SizedBox.shrink();
    var sigHtml = rawSig;
    if (sigHtml.contains('[') && sigHtml.contains(']')) {
      sigHtml = ComiisParser.bbcodeToHtml(sigHtml);
    }

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

  Widget _buildTextAction({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    Color? backgroundColor,
    String? tooltip,
    bool showLabel = true,
  }) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSurfaceVariant;
    final btn = Material(
      color: backgroundColor ?? Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(
                data: IconThemeData(color: fg, size: 14.5),
                child: icon,
              ),
              if (showLabel && label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }

  Widget _buildActionRow(BuildContext context, ThemeData theme) {
    final effectiveLiked = widget.isLiked ?? _isLiked;
    final effectiveCount = widget.likesCount ?? _likesCount;
    final commentCount = floor.replyFloorCount > floor.replyFloors.length
        ? floor.replyFloorCount
        : floor.replyFloors.length;
    final likeText = effectiveCount > 0
        ? (effectiveLiked ? '已赞 $effectiveCount' : '赞 $effectiveCount')
        : (effectiveLiked ? '已赞' : '赞');

    PopupMenuItem<VoidCallback> action(
            IconData icon, String label, VoidCallback onTap) =>
        PopupMenuItem<VoidCallback>(
          value: onTap,
          child: Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Flexible(child: Text(label)),
          ]),
        );
    PopupMenuItem<VoidCallback> category(String label) =>
        PopupMenuItem<VoidCallback>(
          enabled: false,
          height: 32,
          child: Text(label, style: theme.textTheme.labelMedium),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Expanded(
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            _buildTextAction(
              icon: widget.likeBusy || _likeBusy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: AppLoadingIndicator(strokeWidth: 2))
                  : Icon(
                      effectiveLiked
                          ? Icons.thumb_up_rounded
                          : Icons.thumb_up_outlined,
                      size: 15,
                      color: effectiveLiked ? theme.colorScheme.primary : null,
                    ),
              label: likeText,
              onTap: _toggleFloorLike,
              color: effectiveLiked ? theme.colorScheme.primary : null,
              backgroundColor: effectiveLiked
                  ? theme.colorScheme.primary.withAlpha(20)
                  : null,
              tooltip: effectiveLiked ? '取消点赞' : '点赞此楼层',
            ),
            _buildTextAction(
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
              label: '回复',
              onTap: () => _openReply(context, quote: false),
              tooltip: '回复此楼层',
            ),
            if (!_isFirstFloorOverall && commentCount > 0)
              _buildTextAction(
                icon: const Icon(Icons.forum_outlined, size: 15),
                label: '楼中楼 $commentCount',
                onTap: _onReplyFloorWrite,
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.primary.withAlpha(15),
                tooltip: '查看或添加楼中楼回复',
              ),
          ]),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<VoidCallback>(
          tooltip: '更多楼层操作',
          icon: const Icon(Icons.more_horiz),
          onSelected: (onTap) => onTap(),
          itemBuilder: (_) => [
            category('互动'),
            if (!_isFirstFloorOverall)
              action(Icons.forum_outlined, '楼中楼回复', _onReplyFloorWrite),
            if (!_isFirstFloorOverall)
              action(Icons.format_quote_rounded, '引用回复',
                  () => _openReply(context, quote: true)),
            action(Icons.card_giftcard_outlined, '打赏与评分',
                () => _onRewardFloor(context)),
            if (floor.magicItems.isNotEmpty)
              action(Icons.auto_fix_high_outlined, '使用道具',
                  () => _onMagicFloor(context)),
            const PopupMenuDivider(),
            category('内容与链接'),
            if (_canEdit)
              action(Icons.edit_outlined, widget.isFirstFloor ? '编辑帖子' : '编辑回复',
                  () => _onEditFloor(context)),
            action(Icons.link_outlined, '复制楼层链接', () {
              final pid = floor.pid;
              final url = pid != null && pid > 0
                  ? '${AppConfig.baseUrl}forum.php?mod=redirect&goto=findpost&pid=$pid'
                  : '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid';
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('楼层链接已复制')));
            }),
            if (_canReport)
              action(
                  Icons.flag_outlined, '举报违规楼层', () => _onReportFloor(context)),
            if (_canSetBestAnswer || widget.canModerate) ...[
              const PopupMenuDivider(),
              category('管理'),
              if (_canSetBestAnswer)
                action(Icons.workspace_premium_outlined, '采纳为最佳答案',
                    () => _onSetBestAnswer(context)),
              if (widget.canModerate)
                action(Icons.shield_outlined, '管理本楼',
                    () => _onManageFloor(context)),
            ],
          ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    final isHighlighted = widget.isHighlighted;
    final isBest = floor.isBestAnswer;
    final cardDecoration = BoxDecoration(
      color: widget.isFirstFloor
          ? theme.colorScheme.primaryContainer
              .withAlpha(isHighlighted ? 60 : 35)
          : isBest
              ? (theme.brightness == Brightness.dark
                  ? const Color(0xFF142E1F)
                  : const Color(0xFFF1F8E9))
              : isHighlighted
                  ? theme.colorScheme.primaryContainer.withAlpha(45)
                  : (theme.brightness == Brightness.dark
                      ? theme.colorScheme.surfaceContainerLow
                      : theme.colorScheme.surface),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isBest
            ? (theme.brightness == Brightness.dark
                ? const Color(0xFF2E7D32)
                : const Color(0xFF81C784))
            : isHighlighted
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withAlpha(60),
        width: (isBest || isHighlighted) ? 1.8 : 0.6,
      ),
      boxShadow: isBest
          ? [
              BoxShadow(
                color: const Color(0xFF2E7D32).withAlpha(50),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ]
          : isHighlighted
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withAlpha(120),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
    );

    return GestureDetector(
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
            // 楼层头部（左侧头像，右侧双行信息：首行作者+等级+楼层标号，次行勋章+发布时间/IP）
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
                    size: 36,
                    reserveFrameSpace: true,
                    faceUrl: floor.faceUrl.isNotEmpty ? floor.faceUrl : null,
                    isOnline: floor.isOnline,
                    showOnlineBadge: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 第 1 行：作者名 + 楼主标识 + 会员等级
                      Row(
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
                          if (widget.isThreadAuthor &&
                              !widget.isFirstFloor) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF9800),
                                    Color(0xFFFF5722)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        const Color(0xFFFF9800).withAlpha(80),
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
                        ],
                      ),
                      // 勋章列表（横向滚动）
                      if (floor.medals.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final md in floor.medals)
                                Padding(
                                  padding: const EdgeInsets.only(right: 3),
                                  child: CachedNetworkImage(
                                    imageUrl: md,
                                    cacheKey:
                                        KlpbbsCacheManager.normalizeCacheKey(
                                            md),
                                    cacheManager: KlpbbsCacheManager.instance,
                                    httpHeaders: AppConfig.imageHeaders,
                                    height: 15,
                                    memCacheHeight: 45,
                                    fit: BoxFit.contain,
                                    errorWidget: (_, __, ___) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 右侧信息组：楼层序号/状态 与 时间/IP 严格右对齐
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                                    color:
                                        const Color(0xFFFF9800).withAlpha(120),
                                    width: 0.8,
                                  )
                                : null,
                          ),
                          child: Text(
                            _displayFloorNumber,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: widget.isFirstFloor
                                  ? (theme.brightness == Brightness.dark
                                      ? const Color(0xFFFFB74D)
                                      : const Color(0xFFE65100))
                                  : theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (floor.isBestAnswer) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade700,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified,
                                    size: 12, color: Colors.white),
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
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (floor.timeText.isNotEmpty)
                          Text(
                            _friendlyTime(floor.timeText),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withAlpha(200),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (floor.sourceLabel.isNotEmpty)
                          Text(
                            floor.sourceLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        if (floor.ipText.isNotEmpty)
                          Text(
                            'IP: ${floor.ipText}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withAlpha(160),
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 悬赏贴专区头部
            if (widget.isFirstFloor &&
                (floor.bountyPrice != null || floor.isBountySolved))
              _buildBountyHeader(theme, floor),
            // 正文
            DiscuzPostRenderer(
              floor: floor,
              tid: tid,
              onQuickReply: () => _openReply(context, quote: false),
              onQuoteReply: _isFirstFloorOverall
                  ? null
                  : () => _openReply(context, quote: true),
              onPollVoted: widget.onReload,
            ),
            // 评分/打赏记录
            if (floor.rewards.isNotEmpty || floor.rewardCount.isNotEmpty)
              _RewardSection(floor: floor, tid: tid),
            // 楼主签名档（仅限 1 楼，排在点赞列表前面）
            if (widget.isFirstFloor) ...[
              ListenableBuilder(
                listenable: AppConfig.instance,
                builder: (context, _) {
                  if (AppConfig.showFloorSignature &&
                      floor.signature.isNotEmpty) {
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
                canModerate: widget.canModerate,
                myUid: widget.myUid,
                onReplyToAuthor: (author, msgid) =>
                    _onReplyFloorWrite(initialAuthor: author, msgid: msgid),
                onWriteReply: () => _onReplyFloorWrite(),
                onReportComment: _onReportFloorComment,
              ),
            // 点评
            if (floor.comments.isNotEmpty)
              _CommentsSection(
                comments: floor.comments,
                onReply: (author) => _onReplyFloorWrite(initialAuthor: author),
              ),
            // 普通楼层签名档（仅限非 1 楼回复）
            if (!widget.isFirstFloor)
              ListenableBuilder(
                listenable: AppConfig.instance,
                builder: (context, _) {
                  if (AppConfig.showFloorSignature &&
                      floor.signature.isNotEmpty) {
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      const Icon(Icons.thumb_up_rounded,
                          size: 14, color: Colors.white),
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
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  right: 6, top: 4, bottom: 4),
                              child: UserAvatarWidget(
                                uid: u.uid,
                                author: u.username,
                                avatarUrl: u.avatarUrl,
                                size: 28,
                                reserveFrameSpace: true,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        color:
            isSolved ? Colors.green.withAlpha(20) : Colors.amber.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSolved
              ? Colors.green.withAlpha(90)
              : Colors.amber.withAlpha(120),
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
                  isSolved
                      ? (price.isNotEmpty ? '悬赏问答 (已解决 $price)' : '悬赏问答 (已解决)')
                      : (price.isNotEmpty ? '悬赏问答主题 [$price]' : '悬赏问答主题'),
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
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static final RegExp _friendlyTimeRegex = RegExp(
    r'(\d{4})-(\d{1,2})-(\d{1,2})\s*(\d{1,2}):(\d{1,2})?',
  );
  static final Map<String, String> _friendlyTimeCache = {};

  String _friendlyTime(String raw) {
    final cached = _friendlyTimeCache[raw];
    if (cached != null) return cached;

    final m = _friendlyTimeRegex.firstMatch(raw);
    if (m == null) {
      _friendlyTimeCache[raw] = raw;
      return raw;
    }
    final now = DateTime.now();
    final y = int.tryParse(m.group(1) ?? '') ?? now.year;
    final mo = int.tryParse(m.group(2) ?? '') ?? 1;
    final d = int.tryParse(m.group(3) ?? '') ?? 1;
    final h = int.tryParse(m.group(4) ?? '') ?? 0;
    final mi = int.tryParse(m.group(5) ?? '') ?? 0;
    final postTime = DateTime(y, mo, d, h, mi);
    final hm =
        '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(y, mo, d);
    final diff = today.difference(that).inDays;

    String res;
    // 1. 若时间在未来（如论坛使用提升卡、置顶延期、定时发布或微小时钟偏差），绝不能显示负数「-X 天前」
    if (diff < 0 || postTime.isAfter(now)) {
      final futureDiffSec = postTime.difference(now).inSeconds;
      if (futureDiffSec < 300) {
        res = '刚刚';
      } else if (y == now.year) {
        res = '$mo月$d日 $hm';
      } else {
        res =
            '$y-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')} $hm';
      }
    } else if (diff == 0) {
      final diffMin = now.difference(postTime).inMinutes;
      if (diffMin < 1) {
        res = '刚刚';
      } else if (diffMin < 60) {
        res = '$diffMin 分钟前';
      } else {
        res = '今天 $hm';
      }
    } else if (diff == 1) {
      res = '昨天 $hm';
    } else if (diff >= 2 && diff < 7) {
      res = '$diff 天前';
    } else if (y == now.year) {
      res = '$mo月$d日 $hm';
    } else {
      res =
          '$y-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
    }

    if (_friendlyTimeCache.length > 500) {
      _friendlyTimeCache.clear();
    }
    _friendlyTimeCache[raw] = res;
    return res;
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
            if (_canEdit) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(widget.isFirstFloor ? '编辑帖子' : '编辑回复'),
                subtitle:
                    Text(widget.isFirstFloor ? '修改本帖标题与正文内容' : '修改该楼中楼回复内容'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _onEditFloor(context);
                },
              ),
              const Divider(height: 1),
            ],
            if (!_isFirstFloorOverall) ...[
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('楼中楼'),
                subtitle: const Text('对此楼层发表楼中楼回复'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openReply(context, quote: true);
                },
              ),
              const Divider(height: 1),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('回复主题'),
                subtitle: const Text('回复楼主发表的主题内容'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openReply(context, quote: false);
                },
              ),
              const Divider(height: 1),
            ],
            ListTile(
              leading: const Icon(Icons.select_all),
              title: const Text('选择复制正文'),
              subtitle: const Text('自由选字或按段组合，保留段落与链接地址'),
              onTap: () {
                Navigator.of(ctx).pop();
                showPostCopySheet(context,
                    html: floor.contentHtml,
                    title: '楼层 ${index + 1} · ${floor.author}');
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制正文'),
              onTap: () {
                Navigator.of(ctx).pop();
                final plain =
                    PostCopyDocument.fromHtml(floor.contentHtml).plainText;
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
            if (_canReport)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('举报'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _onReportFloor(context);
                },
              ),
            if (widget.canModerate)
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('管理此楼 (屏蔽/警告/删楼/IP)'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _onManageFloor(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 管理楼层（弹 Discuz 楼层管理弹窗）
  Future<void> _onManageFloor(BuildContext context) async {
    final ok = await FloorAdminDialog.show(
      context,
      fid: fid ?? 2,
      tid: tid,
      pid: floor.pid ?? 0,
      floorIndex: index,
      author: floor.author,
      snippet: floor.contentHtml.replaceAll(RegExp(r'<[^>]+>'), ' ').trim(),
    );
    if (ok == true && mounted) {
      widget.onReload?.call();
    }
  }

  // 楼层举报（弹 Discuz 规范选项弹窗 + reportPost）
  void _onReportFloor(BuildContext context) {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先登录论坛账号后再提交举报'),
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
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先登录论坛账号后再提交举报'),
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
    ReportDialog.show(
      context,
      tid: tid,
      pid: floor.pid ?? 0,
      author: comment.author,
      floorIndex: index,
    );
  }

  // 发起/回复楼中楼（支持表情库面板、快捷表情插入与实时反馈）
  void _onReplyFloorWrite({String? initialAuthor, int? msgid}) {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先登录论坛账号后再进行回复'),
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
    final hasAuthor = initialAuthor != null && initialAuthor.trim().isNotEmpty;
    final ctrl = TextEditingController(); // 对齐网页端：编辑输入区保持清空，不预填“回复xxx : ”
    showDialog<void>(
      context: context,
      builder: (ctx) {
        bool submitting = false;
        bool showEmojiPanel = false;
        int activeSmileyCatIndex = 0;
        List<SmileyCategory> smileyCats =
            ComiisParser.parseSmilies(ComiisParser.kDefaultSmiliesJs);

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
                  selection:
                      TextSelection.collapsed(offset: sel.start + code.length),
                );
              } else {
                ctrl.text = '$text$code';
                ctrl.selection =
                    TextSelection.collapsed(offset: ctrl.text.length);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              title: Row(
                children: [
                  Icon(Icons.reply_rounded,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasAuthor
                          ? '回复 @$initialAuthor'
                          : '回复 $_displayFloorNumber',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
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
                    if (hasAuthor)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withAlpha(90),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.reply,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              '回复 @$initialAuthor',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: ctrl,
                      maxLines: 4,
                      autofocus: true,
                      enabled: !submitting,
                      decoration: InputDecoration(
                        hintText: hasAuthor
                            ? '写下你想对 @$initialAuthor 说的话...'
                            : '写下你的回复内容...',
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
                            showEmojiPanel
                                ? Icons.keyboard_alt_outlined
                                : Icons.sentiment_satisfied_alt_outlined,
                            size: 20,
                            color: showEmojiPanel
                                ? Theme.of(context).colorScheme.primary
                                : null,
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
                                      label: Text(emoji.$1,
                                          style: const TextStyle(fontSize: 11)),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      onPressed: submitting
                                          ? null
                                          : () => insertCode(emoji.$2),
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
                                      setDialogState(
                                          () => activeSmileyCatIndex = cIdx);
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
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 44,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                            childAspectRatio: 1,
                          ),
                          itemCount:
                              smileyCats[activeSmileyCatIndex].smileys.length,
                          itemBuilder: (context, sIdx) {
                            final smiley =
                                smileyCats[activeSmileyCatIndex].smileys[sIdx];
                            return InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => insertCode(smiley.code),
                              child: Center(
                                child: CachedNetworkImage(
                                  imageUrl: smiley.imageUrl,
                                  cacheKey:
                                      KlpbbsCacheManager.normalizeCacheKey(
                                          smiley.imageUrl),
                                  cacheManager: KlpbbsCacheManager.instance,
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
                          final rawMsg = ctrl.text.trim();
                          if (rawMsg.isEmpty) return;
                          final msg = hasAuthor &&
                                  !rawMsg.startsWith('回复 @') &&
                                  !rawMsg.startsWith('回复@')
                              ? '回复 @$initialAuthor : $rawMsg'
                              : rawMsg;
                          final messenger = ScaffoldMessenger.of(context);
                          final confirmed = await confirmWrite(context, '发布回复');
                          if (!confirmed) return;
                          setDialogState(() => submitting = true);
                          try {
                            final ok = await KlpbbsApi.postFloorReply(
                              tid,
                              floor.pid ?? 0,
                              msg,
                              msgid: msgid ?? 0,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok ? '已成功发布回复' : '回复失败（请先登录论坛账号）',
                                ),
                              ),
                            );
                            if (ok) {
                              widget.onReload?.call();
                            }
                          } catch (e) {
                            if (dialogCtx.mounted) {
                              setDialogState(() => submitting = false);
                            }
                            messenger.showSnackBar(
                                SnackBar(content: Text('回复异常：$e')));
                          }
                        },
                  icon: submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: AppLoadingIndicator(
                              strokeWidth: 2, color: Colors.white))
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
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先登录论坛账号后再进行打赏评分'),
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
    final amountCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    int selected = 1;
    const amounts = [1, 5, 10, 50];
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(context).colorScheme;
        return Dialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 渐变全宽头部（对齐边缘，无外层 Padding 凹陷错位）
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primaryContainer,
                          scheme.secondaryContainer,
                        ],
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '打赏 @${floor.author}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '写贴不容易，打赏一下楼主吧',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 内容操作区域
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                              borderRadius:
                                  BorderRadius.all(Radius.circular(8)),
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 回复/引用回复（完全对齐 Discuz Web 端逻辑）
  Future<void> _openReply(BuildContext context, {required bool quote}) async {
    final isFirst = _isFirstFloorOverall;
    final effectiveQuote = quote && !isFirst;

    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(effectiveQuote ? '请先登录论坛账号后再进行引用回复' : '请先登录论坛账号后再进行回复'),
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

    // 提取纯文本摘要（剥离已有 quote 引用块和 HTML 标签，避免多层嵌套）
    final cleanContent = floor.contentHtml
        .replaceAll(RegExp(r'<div class="quote">.*?</div>', dotAll: true), '')
        .replaceAll(
            RegExp(r'<blockquote.*?>.*?</blockquote>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final snippet = cleanContent.length > 200
        ? '${cleanContent.substring(0, 200)}...'
        : cleanContent;

    // Discuz 标准带链接引用格式（作为 noticetrimstr 发送给服务端）
    final quoteBBCode = (floor.pid != null && floor.pid! > 0)
        ? '[quote][size=2][url=forum.php?mod=redirect&goto=findpost&pid=${floor.pid}&ptid=$tid][color=#999999]${floor.author}${floor.timeText.isNotEmpty ? " 发表于 ${floor.timeText}" : ""}[/color][/url][/size]\n$snippet[/quote]'
        : '[quote]${floor.author}:\n$snippet[/quote]';

    final tTitle = widget.threadTitle;
    final navigator = Navigator.of(context);
    bool? ok;

    if (effectiveQuote) {
      ok = await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => PostPage(
            tid: tid,
            fid: fid,
            threadTitle: tTitle,
            repquote: floor.pid,
            reppost: floor.pid,
            noticeauthor: floor.author,
            noticetrimstr: quoteBBCode,
            quoteAuthor: floor.author,
            quoteTimeText: floor.timeText,
            quoteContent: snippet,
            replyToFloorText: '引用 $_displayFloorNumber (${floor.author})',
            initialMessage: null, // 完美对齐 Discuz 网页版：输入框保持清空，正文不直接插入引用 BBCode
          ),
        ),
      );
    } else {
      // 普通回复：完全对齐 Discuz 网页版——输入框保持清空，绝不生硬插入“回复xxx : ”，在上方独立呈现回复目标卡片
      if (isFirst) {
        ok = await navigator.push<bool>(
          MaterialPageRoute(
            builder: (_) => PostPage(
              tid: tid,
              fid: fid,
              threadTitle: tTitle,
              replyToFloorText: '回复楼主 (${floor.author})',
              initialMessage: null,
            ),
          ),
        );
      } else {
        ok = await navigator.push<bool>(
          MaterialPageRoute(
            builder: (_) => PostPage(
              tid: tid,
              fid: fid,
              threadTitle: tTitle,
              reppost: floor.pid,
              noticeauthor: floor.author,
              quoteAuthor: floor.author,
              quoteTimeText: floor.timeText,
              quoteContent: snippet,
              replyToFloorText: '回复 $_displayFloorNumber (${floor.author})',
              initialMessage:
                  null, // 完美对齐 Discuz 网页版：输入框保持清空，绝不在编辑区插入“回复xxx : ”
            ),
          ),
        );
      }
    }
    if (ok == true && mounted) {
      widget.onReload?.call();
    }
  }

  // 头像长按放大
  void _zoomAvatar(BuildContext context, int uid) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: UserAvatarWidget(
          uid: uid,
          faceUrl: uid == floor.uid
              ? UserAvatarWidget.optionalFrame(floor.faceUrl)
              : null,
          reserveFrameSpace: true,
          size: 140,
        ),
      ),
    );
  }

  /// 道具菜单（mgc_post_{pid}）：底部弹出可用道具，点击在本地环境使用
  void _onMagicFloor(BuildContext context) {
    if (!DioClient.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先登录论坛账号后再使用道具'),
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
                          cacheKey: KlpbbsCacheManager.normalizeCacheKey(m.img),
                          cacheManager: KlpbbsCacheManager.instance,
                          httpHeaders: AppConfig.imageHeadersFor(m.img),
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
  final bool canModerate;
  final int? myUid;
  final void Function(String author, int msgid)? onReplyToAuthor;
  final VoidCallback? onWriteReply;
  final void Function(ReplyFloorComment comment)? onReportComment;

  const _ReplyFloorSection({
    required this.floor,
    required this.tid,
    this.canModerate = false,
    this.myUid,
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
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary.withAlpha(120),
            width: 2.5,
          ),
        ),
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
              canModerate: canModerate,
              myUid: myUid,
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
  final bool canModerate;
  final int? myUid;
  final void Function(String author, int msgid)? onReply;
  final void Function(ReplyFloorComment comment)? onReport;

  const _ReplyFloorItem({
    required this.comment,
    this.canModerate = false,
    this.myUid,
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
                final plainText =
                    comment.contentHtml.replaceAll(RegExp(r'<[^>]*>'), '');
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
                onReply?.call(comment.author, comment.msgid);
              },
            ),
            if (!canModerate && (comment.uid == null || comment.uid != myUid))
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
                reserveFrameSpace: true,
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
                                      builder: (_) =>
                                          UserSpacePage(uid: comment.uid!),
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
                      if (comment.isWarned) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800).withAlpha(20),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: const Color(0xFFFF9800).withAlpha(180),
                              width: 0.6,
                            ),
                          ),
                          child: Text(
                            comment.warningText.isNotEmpty
                                ? comment.warningText
                                : '受到警告',
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
                      const SizedBox(width: 6),
                      // 举报按钮
                      InkWell(
                        onTap: () => onReport?.call(comment),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.flag_outlined,
                                  size: 12,
                                  color: colorScheme.onSurfaceVariant
                                      .withAlpha(180)),
                              const SizedBox(width: 2),
                              Text(
                                '举报',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant
                                      .withAlpha(200),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 回复按钮
                      InkWell(
                        onTap: () =>
                            onReply?.call(comment.author, comment.msgid),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.reply_rounded,
                                  size: 12, color: colorScheme.primary),
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
                  if (comment.timeText.isNotEmpty ||
                      comment.sourceLabel.isNotEmpty ||
                      comment.location.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, bottom: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 3,
                        children: [
                          for (final text in [
                            comment.timeText,
                            comment.sourceLabel,
                            comment.location
                          ])
                            if (text.isNotEmpty)
                              Text(text,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 10)),
                        ],
                      ),
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

/// Discuz 点评（postcomment / 楼中楼点评，树状引线排版）
class _CommentsSection extends StatelessWidget {
  final List<({String author, String content})> comments;
  final void Function(String author)? onReply;
  const _CommentsSection({required this.comments, this.onReply});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withAlpha(90),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        border: Border(
          left: BorderSide(
            color: Colors.amber.shade700.withAlpha(120),
            width: 2.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.rate_review_outlined,
                size: 13,
                color: Colors.amber.shade800,
              ),
              const SizedBox(width: 5),
              Text(
                '点评',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade800,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${comments.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade800,
                  ),
                ),
              ),
              const Spacer(),
              if (onReply != null)
                Text(
                  '点击单条可回复',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: colorScheme.outline.withAlpha(140),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final c in comments)
            InkWell(
              onTap: onReply != null && c.author.isNotEmpty
                  ? () => onReply!(c.author)
                  : null,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserAvatarWidget(
                      author: c.author,
                      size: 18,
                      reserveFrameSpace: true,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: c.author.isNotEmpty ? '${c.author}：' : '',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: c.content,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
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
    RatingFilterHall.show(
      context,
      tid: widget.tid,
      pid: pid,
      fallbackRewards: floor.rewards
          .map((r) => FloorReward(
                username: r.user,
                uid: r.uid,
                amount: r.amount,
                reason: r.reason,
              ))
          .toList(),
    );
  }

  Widget _buildRewardItem(
    BuildContext ctx,
    ({String user, int? uid, String avatar, String amount, String reason}) r, {
    String dateline = '',
  }) {
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            UserAvatarWidget(
              uid: r.uid,
              author: r.user,
              size: 32,
              avatarUrl: r.avatar,
              reserveFrameSpace: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.user,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      if (dateline.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          dateline,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline.withAlpha(150),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (r.reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        r.reason,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
                        ? (theme.brightness == Brightness.dark
                            ? Colors.red.shade300
                            : Colors.red.shade600)
                        : (theme.brightness == Brightness.dark
                            ? Colors.orange.shade300
                            : Colors.orange.shade800),
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
                      : (floor.floorNumber == '楼主' ||
                              floor.floorNumber == '1#' ||
                              floor.floorNumber.isEmpty
                          ? '打赏 / 评分'
                          : '楼层评分'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Colors.orange.shade300
                        : Colors.orange.shade900,
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
                    ? '查看全部 ${floor.rewardCount} 条评分/打赏记录'
                    : '查看全部评分',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
    final color =
        highlighted ? (activeColor ?? scheme.primary) : scheme.outline;
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
