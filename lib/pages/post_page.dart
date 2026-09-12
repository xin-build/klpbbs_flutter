import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../api/comiis_parser.dart';
import '../api/klpbbs_api.dart';
import '../services/draft_service.dart';
import '../core/app_config.dart';
import '../core/bbcode.dart';
import '../core/cache_manager.dart';
import '../core/forum_events.dart';
import '../models/forum.dart';
import '../models/post_floor.dart';
import '../models/post_edit_info.dart';
import '../models/thread_sort_model.dart';
import '../models/smiley.dart';
import '../widgets/discuz_post_renderer.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/responsive_layout.dart';
import 'thread_detail_page.dart';

/// 发帖/回复页（完美复刻 Discuz PC 版发帖与回复富媒体编辑器）
class PostPage extends StatefulWidget {
  final int? fid; // 发帖版块
  final int? tid; // 回复帖子 ID
  final int? pid; // 编辑楼层 pid
  final bool isEdit; // 是否为编辑模式
  final int? reppost; // 回复指定楼层 pid
  final int? repquote; // 引用指定楼层 pid
  final String? noticeauthor; // 被回复/引用用户
  final String? noticetrimstr; // 引用摘要
  final String? replyToFloorText; // 提示标题（如：回复 2# 沙发 (小明)）
  final String? editSubject; // 编辑预填标题
  final String? editMessage; // 编辑预填内容
  final List<Forum>? forums; // 可选版块列表
  final String? initialMessage; // 预填正文（引用回复等）
  final String? threadTitle; // 回复的原帖标题

  /// 预置表情目录（测试/截图用；跳过网络加载）
  final List<SmileyCategory>? initialSmileys;

  const PostPage({
    super.key,
    this.fid,
    this.tid,
    this.pid,
    this.isEdit = false,
    this.reppost,
    this.repquote,
    this.noticeauthor,
    this.noticetrimstr,
    this.replyToFloorText,
    this.editSubject,
    this.editMessage,
    this.forums,
    this.initialMessage,
    this.threadTitle,
    this.initialSmileys,
  });

  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  final _subjectCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _readPermCtrl = TextEditingController();
  final _rewardCreditCtrl = TextEditingController();
  final _rewardTimesCtrl = TextEditingController(text: '1');

  bool _loading = false;
  String? _result;
  int? _fid;
  String _forumName = '';
  List<Forum> _forums = const [];
  bool _showEmoji = false;
  final List<PostAttachmentItem> _uploadedAttachments = [];
  bool _uploadingAttachment = false;
  bool _isPoll = false;
  bool _preview = false;
  bool _isPlainMode = false;
  double _editorMinHeight = 280;
  int _activeToolbarTab = 0; // 0 常用, 1 排版, 2 媒体, 3 辅助, 4 全部平铺

  // 投票
  final _pollDaysCtrl = TextEditingController(text: '7');
  final _pollMaxCtrl = TextEditingController(text: '1');
  final _pollCtrls = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  // 辩论
  final _affirmCtrl = TextEditingController();
  final _negaCtrl = TextEditingController();
  final _endTimeCtrl = TextEditingController();

  // 高级选项 Tab (0 附加选项, 1 阅读权限, 2 回帖奖励, 3 主题标签, 4 定时发布)
  int _activeOptionTab = 3;
  // 网页端实时属性与权限解析结果
  PostEditorAttributes _editorAttributes = const PostEditorAttributes();

  // 基本属性 (Discuz Web)
  bool _useSig = true;
  bool _isAnonymous = false;
  bool _hiddenReplies = false;
  bool _orderType = false;
  bool _allowNoticeAuthor = true;

  // 文本特性 (Discuz Web)
  bool _htmlOn = false;
  bool _allowImgCode = true;
  bool _allowImgUrl = true;
  bool _parseUrlOff = false;
  bool _smileyOff = false;
  bool _bbcodeOff = false;
  bool _imgContent = false;
  bool _remoteImgLocalize = false;
  bool _replyEmailNotice = false;
  DateTime? _scheduledPublishTime;

  // 管理用户组专属设置 (Discuz Web post_editor_extra.htm & post_editpost.htm)
  int _stickTopic = 0;
  int _addDigest = 0;
  bool _closeThread = false;
  bool _deletePost = false;

  // 投票扩展设置 (Discuz Web)
  bool _pollVisibility = false;
  bool _pollOvert = false;

  // Discuz 用户组阅读权限预设（动态来自网页端时优先使用网页数据）
  List<({String label, int value})> _dynamicUserGroupPermissions = const [];
  static const _userGroupPermissions = [
    (label: '不限 (所有用户可见)', value: 0),
    (label: 'Lv.1 伐木工 (10)', value: 10),
    (label: 'Lv.2 采矿工 (20)', value: 20),
    (label: 'Lv.3 探索者 (30)', value: 30),
    (label: 'Lv.4 冒险家 (50)', value: 50),
    (label: 'Lv.5 领主 (70)', value: 70),
    (label: 'Lv.6 创世神 (100)', value: 100),
    (label: 'VIP 会员 (150)', value: 150),
    (label: 'SVIP 会员 (180)', value: 180),
    (label: '实习版主 / 荣誉版主 (200)', value: 200),
    (label: '超级版主 / 管理员 (255)', value: 255),
  ];

  // 未使用的附件列表
  List<PostAttachmentItem> _unusedAttachments = const [];
  String? _formhash;

  // 分类信息发帖模板（ThreadSorts / sortid / typeoption）
  ThreadSortInfo? _threadSortInfo;
  int? _activeSortid;
  bool _loadingSortTemplate = false;
  final Map<String, dynamic> _typeOptionValues = {};
  final Map<String, TextEditingController> _typeOptionCtrls = {};

  // 快捷回复预设
  String? _selectedQuickReply;
  static const _quickReplies = [
    '感谢楼主分享！',
    '支持一下楼主！',
    '楼主好帖，学到了！',
    '感谢分享，拿走了！',
    '太棒了，期待更新！',
    'Minecraft 有你更精彩！',
  ];

  // 常用标签预设
  static const _presetTags = ['Minecraft', 'Java版', '基岩版', 'BE附加包', '资源', '教程', '灵感', 'NOFOLLOW'];

  // 撤销/重做历史记录
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  bool _isUndoingOrRedoing = false;

  /// 当前版块允许的特殊主题类型（0 普通 / 1 投票 / 3 悬赏 / 5 辩论 ...）
  Set<int> _allowedSpecials = {0};
  List<({int value, String name})> _typeOptions = const [];
  int? _typeid;
  int _special = 0;
  String? _forumPermissionError;

  // 全站表情目录（Discuz 内置 smilies）
  List<SmileyCategory> _smileyCats = const [];
  int _smileyCatIndex = 0;
  bool _smileyLoadFailed = false;

  // 发帖设备来源（电脑端 / 手机端）
  late bool _asMobile;

  // 自动保存与本地草稿箱
  Timer? _draftTimer;
  String _lastSavedTimeText = '';
  int _draftCount = 0;
  List<PostDraft> _draftList = const [];

  bool get _isReply => widget.tid != null && !widget.isEdit;
  bool get _isEdit => widget.isEdit;
  bool _loadingEditData = false;
  bool _isFirstFloorEdit = true;

  @override
  void initState() {
    super.initState();
    _asMobile = !(kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    _fid = widget.fid;
    _forums = widget.forums ?? const [];

    if (widget.editSubject != null) _subjectCtrl.text = widget.editSubject!;
    if (widget.editMessage != null) _contentCtrl.text = widget.editMessage!;
    if (widget.initialMessage != null && widget.editMessage == null) {
      _contentCtrl.text = widget.initialMessage!;
    }

    _contentCtrl.addListener(_onContentChanged);
    _subjectCtrl.addListener(_onFieldChanged);
    _tagCtrl.addListener(_onFieldChanged);

    _refreshDrafts();

    if (_isEdit) {
      if (widget.editMessage != null && widget.editMessage!.isNotEmpty) {
        _contentCtrl.text = widget.editMessage!;
        if (widget.editSubject != null) _subjectCtrl.text = widget.editSubject!;
      } else {
        _loadingEditData = true;
        _loadPostEditInfo();
      }
    } else if (!_isReply && widget.initialMessage == null) {
      _restoreAutoSavedDraft();
    }
    if (_isReply) {
      _activeOptionTab = 0;
    }

    // 定时保存草稿（每 20 秒）
    _draftTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && (_subjectCtrl.text.isNotEmpty || _contentCtrl.text.isNotEmpty)) {
        _triggerAutoSave();
      }
    });

    ForumFavoriteNotifier.instance.addListener(_onForumFavChanged);

    if (!_isReply && !_isEdit && widget.initialSmileys == null) {
      _loadForums();
    }
    if (!_isEdit && widget.initialSmileys == null && (_fid != null || _isReply)) {
      _loadNewThreadInfo();
    }
    _updateForumName();

    if (widget.initialSmileys != null) {
      _smileyCats = widget.initialSmileys!;
      _smileyLoadFailed = _smileyCats.isEmpty;
    } else {
      _loadSmileys();
    }
  }

  /// 异步加载 Discuz 真实编辑数据（首楼/回复正文、标题、分类、权限、标签、已有附件等）
  Future<void> _loadPostEditInfo() async {
    final tid = widget.tid;
    final pid = widget.pid;
    final fid = _fid ?? 2;
    if (tid == null || pid == null) {
      if (mounted) setState(() => _loadingEditData = false);
      return;
    }
    final info = await KlpbbsApi.getPostEditInfo(fid, tid, pid);
    if (!mounted) return;
    if (info.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('加载原帖失败：${info.errorMessage}'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
      );
    }
    setState(() {
      _loadingEditData = false;
      if (info.subject.isNotEmpty) {
        _subjectCtrl.text = info.subject;
      } else if (widget.editSubject != null && widget.editSubject!.isNotEmpty) {
        _subjectCtrl.text = widget.editSubject!;
      }
      if (info.message.isNotEmpty) {
        _contentCtrl.text = info.message;
      }
      if (info.typeid != null && info.typeid! > 0) {
        _typeid = info.typeid;
      }
      if (info.readperm != null && info.readperm! > 0) {
        _readPermCtrl.text = '${info.readperm}';
      }
      if (info.tags.isNotEmpty) {
        _tagCtrl.text = info.tags.join(' ');
      }
      if (info.attachments.isNotEmpty) {
        _uploadedAttachments.clear();
        _uploadedAttachments.addAll(info.attachments);
      }
      _isFirstFloorEdit = info.isFirstFloor;
      _formhash = info.formhash;
      if (info.threadSortInfo != null) {
        _threadSortInfo = info.threadSortInfo;
        _activeSortid = info.sortid ?? info.threadSortInfo?.sortid;
        _initThreadSortFields(info.threadSortInfo);
      }
      if (info.editorAttributes != null) {
        _editorAttributes = info.editorAttributes!;
        _htmlOn = info.editorAttributes!.htmlOn.checked;
        _useSig = info.editorAttributes!.useSig.checked;
      }
    });
  }

  void _onFieldChanged() {
    _triggerAutoSave();
  }

  void _onContentChanged() {
    if (_isUndoingOrRedoing) return;
    final text = _contentCtrl.text;
    if (_undoStack.isEmpty || _undoStack.last != text) {
      _undoStack.add(text);
      if (_undoStack.length > 40) _undoStack.removeAt(0);
      _redoStack.clear();
    }
  }

  void _undo() {
    if (_undoStack.length > 1) {
      _isUndoingOrRedoing = true;
      final current = _undoStack.removeLast();
      _redoStack.add(current);
      final prev = _undoStack.last;
      _contentCtrl.text = prev;
      _contentCtrl.selection = TextSelection.collapsed(offset: prev.length);
      _isUndoingOrRedoing = false;
      setState(() {});
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      _isUndoingOrRedoing = true;
      final next = _redoStack.removeLast();
      _undoStack.add(next);
      _contentCtrl.text = next;
      _contentCtrl.selection = TextSelection.collapsed(offset: next.length);
      _isUndoingOrRedoing = false;
      setState(() {});
    }
  }

  List<ForumGroup> _forumGroups = const [];

  void _updateForumName() {
    if (_fid != null && _forums.isNotEmpty) {
      final f = _forums.where((x) => x.fid == _fid).firstOrNull;
      if (f != null) {
        setState(() => _forumName = f.name);
      }
    }
  }

  void _onForumFavChanged() {
    if (mounted) {
      _loadForums();
    }
  }

  Future<void> _loadForums() async {
    try {
      final groups = await KlpbbsApi.getForumGroups();
      if (mounted) {
        final allForums = <Forum>[];
        final seenFids = <int>{};
        for (final g in groups) {
          for (final f in g.forums) {
            if (seenFids.add(f.fid)) {
              allForums.add(f);
            }
          }
        }
        setState(() {
          _forumGroups = groups;
          _forums = allForums;
          if (_fid == null && allForums.isNotEmpty) {
            final defForum = allForums.firstWhere((x) => x.fid == 52, orElse: () => allForums.first);
            _fid = defForum.fid;
            _forumName = defForum.name;
            _loadNewThreadInfo();
          }
          _updateForumName();
        });
      }
    } catch (_) {
      try {
        final forums = await KlpbbsApi.getForums();
        if (mounted) {
          setState(() {
            _forums = forums;
            if (_fid == null && forums.isNotEmpty) {
              final defForum = forums.firstWhere((x) => x.fid == 52, orElse: () => forums.first);
              _fid = defForum.fid;
              _forumName = defForum.name;
              _loadNewThreadInfo();
            }
            _updateForumName();
          });
        }
      } catch (_) {}
    }
  }

  void _showForumPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, scrollCtrl) {
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.forum_outlined, size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          '选择发布版块',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    child: _forumGroups.isNotEmpty
                        ? ListView.builder(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _forumGroups.length,
                            itemBuilder: (_, i) {
                              final group = _forumGroups[i];
                              return ExpansionTile(
                                initiallyExpanded: true,
                                title: Text(
                                  group.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final f in group.forums)
                                          ChoiceChip(
                                            label: Text(f.name),
                                            selected: _fid == f.fid,
                                            onSelected: (_) {
                                              Navigator.of(ctx).pop();
                                              setState(() {
                                                _fid = f.fid;
                                                _forumName = f.name;
                                              });
                                              _loadNewThreadInfo();
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          )
                        : ListView(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.all(16),
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final f in _forums)
                                    ChoiceChip(
                                      label: Text(f.name),
                                      selected: _fid == f.fid,
                                      onSelected: (_) {
                                        Navigator.of(ctx).pop();
                                        setState(() {
                                          _fid = f.fid;
                                          _forumName = f.name;
                                        });
                                        _loadNewThreadInfo();
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadNewThreadInfo() async {
    if (_isReply && widget.tid != null) {
      try {
        final info = await KlpbbsApi.getReplyInfo(widget.tid!, fid: _fid, asMobile: _asMobile);
        if (!mounted) return;
        setState(() {
          _forumPermissionError = info.errorMessage;
          _unusedAttachments = info.unusedAttachments;
          _editorAttributes = info.editorAttributes;
          _useSig = info.editorAttributes.useSig.checked;
          _isAnonymous = info.editorAttributes.isAnonymous.checked;
          _hiddenReplies = info.editorAttributes.hiddenReplies.checked;
          _orderType = info.editorAttributes.orderType.checked;
          _allowNoticeAuthor = info.editorAttributes.allowNoticeAuthor.checked;
          _htmlOn = info.editorAttributes.htmlOn.checked;
          _allowImgCode = info.editorAttributes.allowImgCode.checked;
          _allowImgUrl = info.editorAttributes.allowImgUrl.checked;
          _parseUrlOff = info.editorAttributes.parseUrlOff.checked;
          _smileyOff = info.editorAttributes.smileyOff.checked;
          _bbcodeOff = info.editorAttributes.bbcodeOff.checked;
          _imgContent = info.editorAttributes.imgContent.checked;
        });
      } catch (_) {}
      return;
    }
    final fid = _fid;
    if (fid == null || _isReply || _isEdit) return;
    try {
      final info = await KlpbbsApi.getNewThreadInfo(fid);
      if (!mounted) return;
      setState(() {
        _allowedSpecials = info.allowedSpecials.contains(0)
            ? info.allowedSpecials
            : {0, ...info.allowedSpecials};
        _typeOptions = info.typeOptions;
        _typeid = _typeOptions.any((t) => t.value == _typeid) ? _typeid : null;
        _forumPermissionError = info.errorMessage.isEmpty ? null : info.errorMessage;
        _formhash = info.formhash;
        _unusedAttachments = info.unusedAttachments;
        _threadSortInfo = info.threadSortInfo;
        _activeSortid = info.threadSortInfo?.sortid;
        _initThreadSortFields(info.threadSortInfo);

        // 如果当前版块检测到分类模板但字段未在初始 HTML 中注入（如软件资源 fid=43），自动异步获取该模板的字段规格
        if (info.threadSortInfo != null &&
            info.threadSortInfo!.fields.isEmpty &&
            info.threadSortInfo!.availableSorts.isNotEmpty) {
          final targetSortid = info.threadSortInfo!.sortid > 0
              ? info.threadSortInfo!.sortid
              : info.threadSortInfo!.availableSorts.first.sortid;
          if (targetSortid > 0) {
            _switchThreadSort(targetSortid, force: true);
          }
        }
        _editorAttributes = info.editorAttributes;
        _useSig = info.editorAttributes.useSig.checked;
        _isAnonymous = info.editorAttributes.isAnonymous.checked;
        _hiddenReplies = info.editorAttributes.hiddenReplies.checked;
        _orderType = info.editorAttributes.orderType.checked;
        _allowNoticeAuthor = info.editorAttributes.allowNoticeAuthor.checked;
        _htmlOn = info.editorAttributes.htmlOn.checked;
        _allowImgCode = info.editorAttributes.allowImgCode.checked;
        _allowImgUrl = info.editorAttributes.allowImgUrl.checked;
        _parseUrlOff = info.editorAttributes.parseUrlOff.checked;
        _smileyOff = info.editorAttributes.smileyOff.checked;
        _bbcodeOff = info.editorAttributes.bbcodeOff.checked;
        _imgContent = info.editorAttributes.imgContent.checked;
        if (info.editorAttributes.readPermOptions.isNotEmpty) {
          _dynamicUserGroupPermissions = [
            (label: '不限 (所有用户可见)', value: 0),
            for (final p in info.editorAttributes.readPermOptions)
              (label: '${p.name} (${p.value})', value: p.value),
          ];
        }
        if (!_allowedSpecials.contains(_special)) {
          _special = 0;
          _isPoll = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _forumPermissionError = '权限获取失败';
      });
    }
  }

  void _initThreadSortFields(ThreadSortInfo? sortInfo) {
    _typeOptionValues.clear();
    for (final c in _typeOptionCtrls.values) {
      c.dispose();
    }
    _typeOptionCtrls.clear();
    if (sortInfo == null) return;
    for (final f in sortInfo.fields) {
      if (f.isCheckbox) {
        if (f.initialValue is List) {
          _typeOptionValues[f.identifier] = (f.initialValue as List).map((e) => '$e').toSet();
        } else {
          _typeOptionValues[f.identifier] = <String>{};
        }
      } else if (f.isRadio || f.isSelect) {
        _typeOptionValues[f.identifier] = f.initialValue?.toString() ?? '';
      } else {
        final textVal = f.initialValue?.toString() ?? '';
        _typeOptionCtrls[f.identifier] = TextEditingController(text: textVal);
        _typeOptionValues[f.identifier] = textVal;
      }
    }
  }

  Future<void> _switchThreadSort(int sortid, {bool force = false}) async {
    if (_fid == null) return;
    if (!force && _activeSortid == sortid && (_threadSortInfo != null && _threadSortInfo!.fields.isNotEmpty)) return;
    setState(() {
      _loadingSortTemplate = true;
    });
    try {
      if (sortid == 0) {
        setState(() {
          _activeSortid = 0;
          _threadSortInfo = _threadSortInfo != null
              ? ThreadSortInfo(
                  sortid: 0,
                  name: _threadSortInfo!.name,
                  sortrequired: _threadSortInfo!.sortrequired,
                  availableSorts: _threadSortInfo!.availableSorts,
                  fields: const [],
                )
              : null;
          _initThreadSortFields(null);
          _loadingSortTemplate = false;
        });
        return;
      }
      final newSortInfo = await KlpbbsApi.getThreadSortInfo(_fid!, sortid, asMobile: _asMobile);
      if (!mounted) return;
      setState(() {
        _activeSortid = sortid;
        _threadSortInfo = newSortInfo;
        _initThreadSortFields(newSortInfo);
        _loadingSortTemplate = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingSortTemplate = false);
      }
    }
  }

  void _selectSpecial(int special) {
    setState(() {
      _special = special;
      _isPoll = special == 1;
      if (special == 1 && _pollCtrls.length < 2) {
        _pollCtrls.add(TextEditingController());
      }
    });
  }

  Future<void> _loadSmileys() async {
    // 立即以内置兜底表情秒级初始化
    if (_smileyCats.isEmpty) {
      final defaultList = ComiisParser.parseSmilies(ComiisParser.kDefaultSmiliesJs);
      if (defaultList.isNotEmpty && mounted) {
        setState(() {
          _smileyCats = defaultList;
          _smileyLoadFailed = false;
        });
      }
    }
    try {
      final cats = await KlpbbsApi.getSmilies();
      if (mounted && cats.isNotEmpty) {
        setState(() {
          _smileyCats = cats;
          _smileyLoadFailed = false;
        });
      }
    } catch (_) {}
  }

  void _insertText(String text) {
    final sel = _contentCtrl.selection;
    final t = _contentCtrl.text;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    final next = t.replaceRange(start, end, text);
    _contentCtrl.text = next;
    _contentCtrl.selection = TextSelection.collapsed(offset: start + text.length);
  }

  void _insertTag(String open, String close) {
    final sel = _contentCtrl.selection;
    final t = _contentCtrl.text;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    final inner = t.substring(start, end);
    final next = t.replaceRange(start, end, '$open$inner$close');
    _contentCtrl.text = next;
    _contentCtrl.selection = TextSelection.collapsed(offset: start + open.length + inner.length);
  }

  @override
  void dispose() {
    ForumFavoriteNotifier.instance.removeListener(_onForumFavChanged);
    _draftTimer?.cancel();
    DraftService.instance.cancelAutoSave();
    _contentCtrl.removeListener(_onContentChanged);
    _subjectCtrl.removeListener(_onFieldChanged);
    _tagCtrl.removeListener(_onFieldChanged);
    _subjectCtrl.dispose();
    _contentCtrl.dispose();
    _tagCtrl.dispose();
    _readPermCtrl.dispose();
    _rewardCreditCtrl.dispose();
    _rewardTimesCtrl.dispose();
    for (final c in _pollCtrls) {
      c.dispose();
    }
    _pollDaysCtrl.dispose();
    _pollMaxCtrl.dispose();
    _affirmCtrl.dispose();
    _negaCtrl.dispose();
    _endTimeCtrl.dispose();
    for (final c in _typeOptionCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _triggerAutoSave() {
    if (_isEdit) return;
    final title = _subjectCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty && content.isEmpty) return;

    final draft = PostDraft(
      id: 'autosave_${_isReply ? "reply_${widget.tid}" : "post_${_fid ?? 0}"}',
      subject: title,
      content: content,
      fid: _fid,
      forumName: _forumName,
      typeid: _typeid,
      special: _special,
      tags: _tagCtrl.text.trim(),
      isReply: _isReply,
      tid: widget.tid,
      asMobile: _asMobile,
      updatedAt: DateTime.now(),
    );
    DraftService.instance.autoSave(draft);
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _lastSavedTimeText =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _refreshDrafts() async {
    final list = await DraftService.instance.getAllDrafts();
    if (mounted) {
      setState(() {
        _draftList = list;
        _draftCount = list.length;
      });
    }
  }

  Future<void> _saveDraftManual() async {
    final title = _subjectCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题或内容后再保存草稿')),
      );
      return;
    }
    final draft = PostDraft(
      id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
      subject: title.isNotEmpty ? title : (content.length > 20 ? '${content.substring(0, 20)}...' : content),
      content: content,
      fid: _fid,
      forumName: _forumName,
      typeid: _typeid,
      special: _special,
      tags: _tagCtrl.text.trim(),
      isReply: _isReply,
      tid: widget.tid,
      asMobile: _asMobile,
      updatedAt: DateTime.now(),
    );
    await DraftService.instance.saveDraft(draft);
    await _refreshDrafts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到本地草稿箱')),
      );
    }
  }

  Future<void> _restoreAutoSavedDraft() async {
    final autoDraft = await DraftService.instance.getAutoSavedDraft(
      fid: _fid,
      tid: widget.tid,
      isReply: _isReply,
    );
    if (autoDraft != null && mounted && (autoDraft.subject.isNotEmpty || autoDraft.content.isNotEmpty)) {
      setState(() {
        if (autoDraft.subject.isNotEmpty && _subjectCtrl.text.isEmpty) {
          _subjectCtrl.text = autoDraft.subject;
        }
        if (autoDraft.content.isNotEmpty && _contentCtrl.text.isEmpty) {
          _contentCtrl.text = autoDraft.content;
        }
        if (autoDraft.fid != null && _fid == null) {
          _fid = autoDraft.fid;
          _updateForumName();
        }
        if (autoDraft.typeid != null) _typeid = autoDraft.typeid;
        if (autoDraft.special != 0) {
          _special = autoDraft.special;
          _isPoll = autoDraft.special == 1;
        }
        if (autoDraft.asMobile != null) _asMobile = autoDraft.asMobile!;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已自动恢复上次未提交的草稿数据')),
      );
    }
  }

  void _loadDraft(PostDraft draft) {
    setState(() {
      _subjectCtrl.text = draft.subject;
      _contentCtrl.text = draft.content;
      if (draft.fid != null) {
        _fid = draft.fid;
        _updateForumName();
      }
      if (draft.typeid != null) _typeid = draft.typeid;
      _special = draft.special;
      _isPoll = draft.special == 1;
      if (draft.tags != null) _tagCtrl.text = draft.tags!;
      if (draft.asMobile != null) _asMobile = draft.asMobile!;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已载入草稿「${draft.subject}」')),
    );
  }

  void _showDraftsModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final theme = Theme.of(ctx);
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '本地草稿箱 (${_draftList.length})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            await _saveDraftManual();
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('保存当前'),
                        ),
                        if (_draftList.isNotEmpty)
                          TextButton(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: ctx,
                                builder: (c) => AlertDialog(
                                  title: const Text('清空草稿箱'),
                                  content: const Text('确定要删除全部本地草稿吗？此操作不可撤销。'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(c).pop(false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.of(c).pop(true),
                                      child: const Text('清空'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await DraftService.instance.clearAllDrafts();
                                await _refreshDrafts();
                                setModalState(() {});
                              }
                            },
                            child: const Text('清空', style: TextStyle(color: Colors.redAccent)),
                          ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _draftList.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.drafts_outlined, size: 48, color: theme.colorScheme.outlineVariant),
                                  const SizedBox(height: 8),
                                  Text(
                                    '暂无已保存的草稿\n点击上方「保存当前」即可保存草稿',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: theme.colorScheme.outline, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _draftList.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final d = _draftList[i];
                                final timeStr =
                                    '${d.updatedAt.year}-${d.updatedAt.month.toString().padLeft(2, '0')}-${d.updatedAt.day.toString().padLeft(2, '0')} ${d.updatedAt.hour.toString().padLeft(2, '0')}:${d.updatedAt.minute.toString().padLeft(2, '0')}';
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  title: Text(
                                    d.subject.isNotEmpty ? d.subject : (d.content.isNotEmpty ? d.content : '无标题草稿'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    '${d.isReply ? "回复" : (d.forumName ?? "主题")} · $timeStr · ${d.content.length}字',
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FilledButton.tonal(
                                        onPressed: () {
                                          if (ctx.mounted) {
                                            Navigator.of(ctx).pop();
                                          }
                                          _loadDraft(d);
                                        },
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: const Text('载入', style: TextStyle(fontSize: 12)),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                        tooltip: '删除草稿',
                                        onPressed: () async {
                                          await DraftService.instance.deleteDraft(d.id);
                                          await _refreshDrafts();
                                          setModalState(() {});
                                        },
                                      ),
                                    ],
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

  Future<void> _pickAndUploadAttachment({bool imageOnly = false}) async {
    final fid = _fid ?? 52;
    final result = await FilePicker.pickFiles(
      type: imageOnly ? FileType.image : FileType.any,
      withData: false,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final files = result.files;
    if (!mounted || files.isEmpty) return;

    setState(() => _uploadingAttachment = true);
    int successCount = 0;

    for (final f in files) {
      final path = f.path;
      if (path == null) continue;
      final ext = p.extension(path).toLowerCase();
      final isImg = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(ext);
      try {
        final aid = await KlpbbsApi.uploadAttachment(
          fid,
          path,
          tid: widget.tid,
          pid: widget.pid,
          isImage: isImg,
        );
        if (aid != null && aid > 0) {
          final item = PostAttachmentItem(
            aid: aid,
            filename: f.name,
            filesize: f.size,
            isImage: isImg,
            localPath: path,
          );
          _uploadedAttachments.add(item);
          // 在当前光标位置插入对应 BBCode 标记
          final tag = isImg ? '[attachimg]$aid[/attachimg]' : '[attach]$aid[/attach]';
          _insertText('\n$tag\n');
          item.isInserted = true;
          successCount++;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _uploadingAttachment = false);
      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功上传并插入 $successCount 个附件')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('附件上传失败，请检查网络或登录状态')),
        );
      }
    }
  }

  void _insertAttachmentTag(PostAttachmentItem item) {
    final tag = item.isImage
        ? '[attachimg]${item.aid}[/attachimg]'
        : '[attach]${item.aid}[/attach]';
    _insertText('\n$tag\n');
    setState(() => item.isInserted = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已在光标处插入附件标签：$tag')),
    );
  }

  void _removeAttachment(PostAttachmentItem item) {
    setState(() {
      _uploadedAttachments.remove(item);
      final tag1 = '[attach]${item.aid}[/attach]';
      final tag2 = '[attachimg]${item.aid}[/attachimg]';
      _contentCtrl.text = _contentCtrl.text
          .replaceAll(tag1, '')
          .replaceAll(tag2, '');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已移除附件：${item.filename}')),
    );
  }

  List<String> get _pollOptions =>
      _pollCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      setState(() => _result = '请输入正文内容');
      return;
    }
    if (!_isReply && _fid == null) {
      setState(() => _result = '请选择发表版块');
      return;
    }
    if (_special == 1 && _pollOptions.length < 2) {
      setState(() => _result = '投票帖至少需要 2 个选项');
      return;
    }
    if (_special == 5) {
      if (_affirmCtrl.text.trim().isEmpty || _negaCtrl.text.trim().isEmpty) {
        setState(() => _result = '辩论帖需要填写正方与反方观点');
        return;
      }
    }
    if ((!_isReply && !_isEdit) || (_isEdit && _isFirstFloorEdit)) {
      if (_subjectCtrl.text.trim().isEmpty) {
        setState(() => _result = '请输入帖子标题');
        return;
      }
      if (_activeSortid != null && _activeSortid! > 0 && _threadSortInfo != null && _threadSortInfo!.fields.isNotEmpty) {
        final missing = <String>[];
        for (final f in _threadSortInfo!.fields) {
          if (!f.required) continue;
          if (f.isCheckbox) {
            final val = _typeOptionValues[f.identifier];
            if (val == null || (val is Set && val.isEmpty) || (val is List && val.isEmpty)) {
              missing.add(f.title);
            }
          } else if (f.isRadio || f.isSelect) {
            final val = _typeOptionValues[f.identifier];
            if (val == null || '$val'.trim().isEmpty) {
              missing.add(f.title);
            }
          } else {
            final ctrl = _typeOptionCtrls[f.identifier];
            if (ctrl == null || ctrl.text.trim().isEmpty) {
              missing.add(f.title);
            }
          }
        }
        if (missing.isNotEmpty) {
          setState(() => _result = '请填写必填的分类信息：${missing.join('、')}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('请填写必填的分类信息：${missing.join('、')}'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }
    }
    if (_forumPermissionError != null && _forumPermissionError!.isNotEmpty) {
      setState(() => _result = '当前版块发帖受限：$_forumPermissionError');
      return;
    }

    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      var finalContent = content;
      // 检查是否有未插入正文的已上传附件，自动附加到文末
      for (final att in _uploadedAttachments) {
        final tag1 = '[attach]${att.aid}[/attach]';
        final tag2 = '[attachimg]${att.aid}[/attachimg]';
        if (!finalContent.contains(tag1) && !finalContent.contains(tag2)) {
          finalContent += '\n${att.isImage ? tag2 : tag1}\n';
        }
      }
      final attachAids = _uploadedAttachments.map((a) => a.aid).toList();

      // 组装分类信息提交参数
      final submitSortid = (_activeSortid != null && _activeSortid! > 0) ? _activeSortid : null;
      final Map<String, dynamic> typeoptions = {};
      if (submitSortid != null && _threadSortInfo != null) {
        for (final f in _threadSortInfo!.fields) {
          if (f.isCheckbox) {
            final val = _typeOptionValues[f.identifier];
            if (val is Set && val.isNotEmpty) {
              typeoptions[f.identifier] = val.toList();
            } else if (val is List && val.isNotEmpty) {
              typeoptions[f.identifier] = val;
            }
          } else if (f.isRadio || f.isSelect) {
            final val = _typeOptionValues[f.identifier];
            if (val != null && '$val'.isNotEmpty) {
              typeoptions[f.identifier] = '$val';
            }
          } else {
            final ctrl = _typeOptionCtrls[f.identifier];
            if (ctrl != null && ctrl.text.trim().isNotEmpty) {
              typeoptions[f.identifier] = ctrl.text.trim();
            }
          }
        }
      }

      final ok = _isEdit
          ? await KlpbbsApi.editPost(
              _fid ?? 2,
              widget.tid!,
              widget.pid!,
              subject: _subjectCtrl.text.trim(),
              message: finalContent,
              typeid: _typeid,
              sortid: submitSortid,
              typeoptions: (submitSortid != null && typeoptions.isNotEmpty) ? typeoptions : null,
              readPerm: int.tryParse(_readPermCtrl.text.trim()),
              tags: _tagCtrl.text
                  .split(RegExp(r'[,，\s]+'))
                  .where((s) => s.isNotEmpty)
                  .toList(),
              attachAids: attachAids,
              stickTopic: _stickTopic > 0 ? _stickTopic : null,
              addDigest: _addDigest > 0 ? _addDigest : null,
              deletePost: _deletePost ? true : null,
            )
          : _isReply
          ? await KlpbbsApi.replyThread(
              widget.tid!,
              finalContent,
              fid: _fid ?? widget.fid,
              pid: widget.reppost ?? widget.repquote,
              reppost: widget.reppost,
              repquote: widget.repquote,
              noticeauthor: widget.noticeauthor,
              noticeauthormsg: widget.noticetrimstr,
              noticetrimstr: widget.noticetrimstr,
              attachAids: attachAids,
              asMobile: _asMobile,
              isAnonymous: _isAnonymous,
              hiddenReplies: _hiddenReplies,
              allowNoticeAuthor: _allowNoticeAuthor,
              useSig: _useSig,
              htmlOn: _htmlOn,
              parseUrlOff: _parseUrlOff,
              smileyOff: _smileyOff,
              bbcodeOff: _bbcodeOff,
              replyEmailNotice: _replyEmailNotice,
            )
          : await KlpbbsApi.postThread(
              _fid!,
              _subjectCtrl.text.trim(),
              finalContent,
              typeid: _typeid,
              sortid: submitSortid,
              typeoptions: (submitSortid != null && typeoptions.isNotEmpty) ? typeoptions : null,
              special: _special,
              pollOptions: _special == 1 ? _pollOptions : null,
              pollDays: _special == 1
                  ? int.tryParse(_pollDaysCtrl.text.trim())
                  : null,
              pollMaxChoices: _special == 1
                  ? int.tryParse(_pollMaxCtrl.text.trim())
                  : null,
              pollVisibility: _special == 1 ? _pollVisibility : null,
              pollOvert: _special == 1 ? _pollOvert : null,
              affirmPoint: _special == 5 ? _affirmCtrl.text.trim() : null,
              negaPoint: _special == 5 ? _negaCtrl.text.trim() : null,
              endTime: _special == 5 ? _endTimeCtrl.text.trim() : null,
              attachAids: attachAids,
              readPerm: int.tryParse(_readPermCtrl.text.trim()),
              rewardCredit: int.tryParse(_rewardCreditCtrl.text.trim()),
              rewardTimes: int.tryParse(_rewardTimesCtrl.text.trim()),
              tags: _tagCtrl.text.split(RegExp(r'[,，\s]+')).where((s) => s.isNotEmpty).toList(),
              isAnonymous: _isAnonymous,
              hiddenReplies: _hiddenReplies,
              orderType: _orderType,
              allowNoticeAuthor: _allowNoticeAuthor,
              useSig: _useSig,
              htmlOn: _htmlOn,
              parseUrlOff: _parseUrlOff,
              smileyOff: _smileyOff,
              bbcodeOff: _bbcodeOff,
              replyEmailNotice: _replyEmailNotice,
              stickTopic: _stickTopic > 0 ? _stickTopic : null,
              addDigest: _addDigest > 0 ? _addDigest : null,
              closed: _closeThread ? true : null,
              asMobile: _asMobile,
            );

      if (!mounted) return;
      final success = ok is bool ? ok : ok != null;
      setState(() {
        _loading = false;
        _result = success ? '提交成功！' : '提交失败（请检查登录状态与网络）';
      });

      if (success) {
        await DraftService.instance.clearAutoSavedDraft(
          fid: _fid,
          tid: widget.tid,
          isReply: _isReply,
        );
        if (!mounted) return;
        if (!_isEdit && !_isReply && ok is int && ok > 0) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: ok)),
          );
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = '提交异常：$e';
      });
    }
  }

  // --- 富文本弹窗与快捷插入助手 ---
  void _insertSize(int size) => _insertTag('[size=$size]', '[/size]');
  void _insertColor(String color) => _insertTag('[color=$color]', '[/color]');
  void _insertBackColor(String color) => _insertTag('[backcolor=$color]', '[/backcolor]');
  void _insertAlign(String align) => _insertTag('[align=$align]', '[/align]');
  void _insertFont(String font) => _insertTag('[font=$font]', '[/font]');
  void _insertTable() => _insertText(
        '[table=50%]\n[tr][td]表头1[/td][td]表头2[/td][/tr]\n[tr][td]内容1[/td][td]内容2[/td][/tr]\n[/table]',
      );

  Future<void> _showInsertMusicDialog() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('插入音乐'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('支持网易云音乐 ID（如 1859245）或直接输入音频链接 (.mp3)'),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '音乐 ID 或音频 URL',
                hintText: '如 1859245 或 https://.../audio.mp3',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('插入'),
          ),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) {
      if (RegExp(r'^\d+$').hasMatch(res)) {
        _insertText('[wyy]$res[/wyy]');
      } else {
        _insertText('[audio]$res[/audio]');
      }
    }
  }

  Future<void> _showInsertVideoDialog() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('插入视频'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('支持 B站 BV号（如 BV1CT4y1X7Sd）或直接输入视频链接 (.mp4)'),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'B站 BV 号或视频 URL',
                hintText: '如 BV1CT4y1X7Sd 或 https://.../video.mp4',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('插入'),
          ),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) {
      if (res.toUpperCase().startsWith('BV') || res.contains('bilibili.com')) {
        final m = RegExp(r'(BV[a-zA-Z0-9]+)').firstMatch(res);
        final bvid = m?.group(1) ?? res;
        _insertText('[bili]$bvid[/bili]');
      } else {
        _insertText('[media=x,500,375]$res[/media]');
      }
    }
  }

  Future<void> _showInsertLinkDialog() async {
    final urlCtrl = TextEditingController();
    final textCtrl = TextEditingController();
    final res = await showDialog<({String url, String text})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '链接地址 (URL)',
                hintText: 'https://...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: textCtrl,
              decoration: const InputDecoration(
                labelText: '链接文字（可选）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final u = urlCtrl.text.trim();
              if (u.isNotEmpty) {
                Navigator.pop(ctx, (url: u, text: textCtrl.text.trim()));
              }
            },
            child: const Text('插入'),
          ),
        ],
      ),
    );
    if (res != null) {
      if (res.text.isNotEmpty) {
        _insertText('[url=${res.url}]${res.text}[/url]');
      } else {
        _insertText('[url]${res.url}[/url]');
      }
    }
  }

  Future<void> _showColorPicker({required bool isBackground}) async {
    const palette = [
      '#000000', '#808080', '#c0c0c0', '#ffffff',
      '#ff0000', '#ff8c00', '#ffd700', '#008000',
      '#00bcd4', '#0000ff', '#800080', '#ff69b4',
      '#795548', '#607d8b', '#4caf50', '#e91e63'
    ];
    final customCtrl = TextEditingController();
    final pick = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBackground ? '设置文字背景色' : '设置文字颜色'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in palette)
                  InkWell(
                    onTap: () => Navigator.pop(ctx, hex),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: customCtrl,
              decoration: const InputDecoration(
                labelText: '自定义 #RRGGBB',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = customCtrl.text.trim();
              Navigator.pop(ctx, v.isNotEmpty ? v : null);
            },
            child: const Text('应用'),
          ),
        ],
      ),
    );
    if (pick != null && pick.isNotEmpty) {
      isBackground ? _insertBackColor(pick) : _insertColor(pick);
    }
  }

  /// 插入折叠内容弹窗 (Spoiler / Collapse)
  Future<void> _showInsertSpoilerDialog() async {
    final titleCtrl = TextEditingController(text: '折叠内容（点击展开）');
    final contentCtrl = TextEditingController();
    final res = await showDialog<({String title, String content})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.unfold_less, size: 20),
            SizedBox(width: 8),
            Text('插入折叠内容 (Spoiler)', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: '折叠标题',
                hintText: '如：点击查看详细说明',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '折叠内部正文',
                hintText: '输入需要被收起的内容...',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final t = titleCtrl.text.trim();
              final c = contentCtrl.text.trim();
              if (c.isNotEmpty) {
                Navigator.pop(ctx, (title: t.isNotEmpty ? t : '折叠内容（点击展开）', content: c));
              }
            },
            child: const Text('插入'),
          ),
        ],
      ),
    );
    if (res != null) {
      _insertText('\n[spoiler=${res.title}]\n${res.content}\n[/spoiler]\n');
    }
  }

  /// 插入隐藏内容弹窗 (Hide / 回帖或积分可见)
  Future<void> _showInsertHideDialog() async {
    final pointsCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    int hideType = 0; // 0: 回帖可见, 1: 积分可见

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline, size: 20),
              SizedBox(width: 8),
              Text('插入隐藏内容 (Hide)', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Radio<int>(
                    value: 0,
                    groupValue: hideType,
                    onChanged: (v) => setDlgState(() => hideType = v ?? 0),
                  ),
                  const Text('回复后可见', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 12),
                  Radio<int>(
                    value: 1,
                    groupValue: hideType,
                    onChanged: (v) => setDlgState(() => hideType = v ?? 1),
                  ),
                  const Text('积分可见', style: TextStyle(fontSize: 13)),
                ],
              ),
              if (hideType == 1) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: pointsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '所需积分下限',
                    hintText: '如 20',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '隐藏内容正文',
                  hintText: '输入需要隐藏的内容...',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final c = contentCtrl.text.trim();
                if (c.isNotEmpty) {
                  if (hideType == 1 && pointsCtrl.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, '[hide=${pointsCtrl.text.trim()}]$c[/hide]');
                  } else {
                    Navigator.pop(ctx, '[hide]$c[/hide]');
                  }
                }
              },
              child: const Text('插入'),
            ),
          ],
        ),
      ),
    );
    if (res != null) {
      _insertText('\n$res\n');
    }
  }

  // --- 智能自适应响应式工具栏（无 Emoji，流畅动画与 Material 3 风格） ---
  Widget _buildAdaptiveToolbar(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(45),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withAlpha(70),
                width: 0.8,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部分类切换栏 + 核心全局控制 (撤销/重做/预览)
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _toolbarCategoryChip(0, '常用', Icons.flash_on_outlined, theme),
                          const SizedBox(width: 4),
                          _toolbarCategoryChip(1, '排版', Icons.format_paint_outlined, theme),
                          const SizedBox(width: 4),
                          _toolbarCategoryChip(2, '媒体', Icons.perm_media_outlined, theme),
                          const SizedBox(width: 4),
                          _toolbarCategoryChip(3, '辅助', Icons.tune_outlined, theme),
                          if (isWide) ...[
                            const SizedBox(width: 4),
                            _toolbarCategoryChip(4, '全部平铺', Icons.grid_view_outlined, theme),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 高频通用控制
                  _toolIcon(Icons.undo, '撤销', _undo),
                  _toolIcon(Icons.redo, '重做', _redo),
                  _toolIcon(
                    _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                    _preview ? '返回编辑' : '实时预览',
                    () => setState(() => _preview = !_preview),
                    isActive: _preview,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Divider(height: 1, thickness: 0.6, color: theme.colorScheme.outlineVariant.withAlpha(50)),
              const SizedBox(height: 5),

              // 自适应功能区：平滑过渡动画展开/切换
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOutCubic,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_activeToolbarTab),
                    child: _buildActiveToolbarContent(theme, isWide),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolbarCategoryChip(int index, String label, IconData icon, ThemeData theme) {
    final isActive = _activeToolbarTab == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _activeToolbarTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
          decoration: BoxDecoration(
            color: isActive ? theme.colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive
                  ? theme.colorScheme.primary.withAlpha(120)
                  : theme.colorScheme.outlineVariant.withAlpha(50),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13.5,
                color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveToolbarContent(ThemeData theme, bool isWide) {
    switch (_activeToolbarTab) {
      case 0:
        // 常用高频栏 (自适应横向流动)
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _toolIcon(
                Icons.emoji_emotions_outlined,
                '表情',
                () => setState(() => _showEmoji = !_showEmoji),
                isActive: _showEmoji,
              ),
              _toolIcon(Icons.image_outlined, '插入图片', () => _pickAndUploadAttachment(imageOnly: true)),
              _toolIcon(Icons.attach_file, '上传附件', () => _pickAndUploadAttachment(imageOnly: false)),
              const _ToolbarDivider(),
              _bbTextBtn('B', '粗体', () => _insertTag('[b]', '[/b]'), isBold: true),
              _bbTextBtn('I', '斜体', () => _insertTag('[i]', '[/i]'), isItalic: true),
              _bbTextBtn('U', '下划线', () => _insertTag('[u]', '[/u]'), isUnderline: true),
              _bbTextBtn('S', '删除线', () => _insertTag('[s]', '[/s]'), isStrike: true),
              const _ToolbarDivider(),
              _toolIcon(Icons.link, '添加链接', _showInsertLinkDialog),
              _toolIcon(Icons.format_quote, '引用', () => _insertTag('[quote]', '[/quote]')),
              _toolIcon(Icons.code, '代码块', () => _insertTag('[code]', '[/code]')),
              _toolIcon(Icons.unfold_less, '折叠内容 (Spoiler)', _showInsertSpoilerDialog),
              _toolIcon(Icons.lock_outline, '隐藏内容 (Hide)', _showInsertHideDialog),
              _toolIcon(Icons.format_color_text, '调色板', () => _showColorPicker(isBackground: false)),
            ],
          ),
        );

      case 1:
        // 排版与样式栏
        return Wrap(
          spacing: 5,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 常用字号直接点选
            _quickSizeChip(1, '极小'),
            _quickSizeChip(2, '标准'),
            _quickSizeChip(3, '中号'),
            _quickSizeChip(4, '大号'),
            _quickSizeChip(5, '特大'),
            const _ToolbarDivider(),
            // 常用快捷色点
            _quickColorDot(const Color(0xFFF44336), 'red', '红色'),
            _quickColorDot(const Color(0xFFFF9800), 'orange', '橙色'),
            _quickColorDot(const Color(0xFF4CAF50), 'green', '绿色'),
            _quickColorDot(const Color(0xFF2196F3), 'blue', '蓝色'),
            _quickColorDot(const Color(0xFF9C27B0), 'purple', '紫色'),
            _quickColorDot(const Color(0xFF212121), 'black', '深黑'),
            _toolIcon(Icons.palette_outlined, '自定义文字颜色', () => _showColorPicker(isBackground: false)),
            _toolIcon(Icons.format_color_fill, '背景色', () => _showColorPicker(isBackground: true)),
            const _ToolbarDivider(),
            // 字体选择下拉
            PopupMenuButton<String>(
              tooltip: '选择字体',
              onSelected: _insertFont,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'Tahoma', child: Text('Tahoma')),
                PopupMenuItem(value: '微软雅黑', child: Text('微软雅黑')),
                PopupMenuItem(value: '宋体', child: Text('宋体')),
                PopupMenuItem(value: '黑体', child: Text('黑体')),
                PopupMenuItem(value: 'Arial', child: Text('Arial')),
                PopupMenuItem(value: 'Courier New', child: Text('Courier New')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('字体', style: TextStyle(fontSize: 11.5)),
                    Icon(Icons.arrow_drop_down, size: 15),
                  ],
                ),
              ),
            ),
            const _ToolbarDivider(),
            _toolIcon(Icons.format_align_left, '居左', () => _insertAlign('left')),
            _toolIcon(Icons.format_align_center, '居中', () => _insertAlign('center')),
            _toolIcon(Icons.format_align_right, '居右', () => _insertAlign('right')),
            _toolIcon(Icons.format_list_bulleted, '无序列表', () => _insertText('\n[list]\n[*]项目一\n[*]项目二\n[/list]\n')),
            _toolIcon(Icons.format_list_numbered, '有序列表', () => _insertText('\n[list=1]\n[*]项目一\n[*]项目二\n[/list]\n')),
            _toolIcon(Icons.table_chart_outlined, '添加表格', _insertTable),
            _toolIcon(Icons.horizontal_rule, '分隔线', () => _insertText('\n[hr]\n')),
            _toolIcon(Icons.link_off, '清除格式', () => _insertText(_contentCtrl.text.replaceAll(RegExp(r'\[/?(b|i|u|s|color|size|url|font|align)[^\]]*\]'), ''))),
          ],
        );

      case 2:
        // 媒体与扩展
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _toolButtonWithLabel(Icons.music_note_outlined, '网易云音乐', _showInsertMusicDialog, theme),
            _toolButtonWithLabel(Icons.videocam_outlined, '视频', _showInsertVideoDialog, theme),
            _toolButtonWithLabel(Icons.table_chart_outlined, '表格', _insertTable, theme),
            _toolButtonWithLabel(Icons.unfold_less, '折叠 Spoiler', _showInsertSpoilerDialog, theme),
            _toolButtonWithLabel(Icons.lock_outline, '隐藏 Hide', _showInsertHideDialog, theme),
            _toolButtonWithLabel(Icons.card_giftcard, '免费信息 [free]', () => _insertTag('[free]', '[/free]'), theme),
            _toolButtonWithLabel(Icons.alternate_email, '@朋友', () => _insertText('[@用户名] '), theme),
            _toolButtonWithLabel(Icons.flash_on_outlined, 'Flash', () => _insertTag('[flash]', '[/flash]'), theme),
          ],
        );

      case 3:
        // 辅助设置与编辑控制
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _toolButtonWithLabel(
              _isPlainMode ? Icons.code : Icons.text_format,
              _isPlainMode ? '纯文本: 开启' : '纯文本: 关闭',
              () => setState(() => _isPlainMode = !_isPlainMode),
              theme,
              isActive: _isPlainMode,
            ),
            _toolButtonWithLabel(Icons.add_circle_outline, '加大编辑区', () => setState(() => _editorMinHeight = min(600, _editorMinHeight + 80)), theme),
            _toolButtonWithLabel(Icons.remove_circle_outline, '缩小编辑区', () => setState(() => _editorMinHeight = max(200, _editorMinHeight - 80)), theme),
            _toolButtonWithLabel(Icons.save_outlined, '手动保存草稿', _saveDraftManual, theme),
            _toolButtonWithLabel(Icons.drafts_outlined, '草稿箱 ($_draftCount)', () => _showDraftsModal(context), theme),
            _toolButtonWithLabel(
              Icons.delete_sweep_outlined,
              '清空内容',
              () {
                if (_contentCtrl.text.isEmpty) return;
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('确认清空内容？'),
                    content: const Text('清空后可通过撤销 (Ctrl+Z) 恢复。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() => _contentCtrl.clear());
                        },
                        child: const Text('确认清空'),
                      ),
                    ],
                  ),
                );
              },
              theme,
              isDanger: true,
            ),
          ],
        );

      case 4:
      default:
        // 全部平铺 (宽屏模式)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToolbarSectionTitle('常用与排版', theme),
            const SizedBox(height: 3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _toolIcon(Icons.emoji_emotions_outlined, '表情', () => setState(() => _showEmoji = !_showEmoji), isActive: _showEmoji),
                  _toolIcon(Icons.image_outlined, '插入图片', () => _pickAndUploadAttachment(imageOnly: true)),
                  _toolIcon(Icons.attach_file, '上传附件', () => _pickAndUploadAttachment(imageOnly: false)),
                  const _ToolbarDivider(),
                  _bbTextBtn('B', '粗体', () => _insertTag('[b]', '[/b]'), isBold: true),
                  _bbTextBtn('I', '斜体', () => _insertTag('[i]', '[/i]'), isItalic: true),
                  _bbTextBtn('U', '下划线', () => _insertTag('[u]', '[/u]'), isUnderline: true),
                  _bbTextBtn('S', '删除线', () => _insertTag('[s]', '[/s]'), isStrike: true),
                  const _ToolbarDivider(),
                  _toolIcon(Icons.link, '添加链接', _showInsertLinkDialog),
                  _toolIcon(Icons.format_quote, '引用', () => _insertTag('[quote]', '[/quote]')),
                  _toolIcon(Icons.code, '代码块', () => _insertTag('[code]', '[/code]')),
                  _toolIcon(Icons.format_align_left, '居左', () => _insertAlign('left')),
                  _toolIcon(Icons.format_align_center, '居中', () => _insertAlign('center')),
                  _toolIcon(Icons.format_align_right, '居右', () => _insertAlign('right')),
                  _toolIcon(Icons.format_list_bulleted, '无序列表', () => _insertText('\n[list]\n[*]项目一\n[*]项目二\n[/list]\n')),
                  _toolIcon(Icons.format_list_numbered, '有序列表', () => _insertText('\n[list=1]\n[*]项目一\n[*]项目二\n[/list]\n')),
                  _toolIcon(Icons.format_color_text, '文字颜色', () => _showColorPicker(isBackground: false)),
                  _toolIcon(Icons.format_color_fill, '背景色', () => _showColorPicker(isBackground: true)),
                  _toolIcon(Icons.horizontal_rule, '分隔线', () => _insertText('\n[hr]\n')),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _buildToolbarSectionTitle('多媒体与扩展', theme),
            const SizedBox(height: 3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _toolButtonWithLabel(Icons.music_note_outlined, '网易云音乐', _showInsertMusicDialog, theme),
                  const SizedBox(width: 4),
                  _toolButtonWithLabel(Icons.videocam_outlined, '视频', _showInsertVideoDialog, theme),
                  const SizedBox(width: 4),
                  _toolButtonWithLabel(Icons.table_chart_outlined, '表格', _insertTable, theme),
                  const SizedBox(width: 4),
                  _toolButtonWithLabel(Icons.unfold_less, '折叠', _showInsertSpoilerDialog, theme),
                  const SizedBox(width: 4),
                  _toolButtonWithLabel(Icons.lock_outline, '隐藏', _showInsertHideDialog, theme),
                  const SizedBox(width: 4),
                  _toolButtonWithLabel(Icons.card_giftcard, '免费信息', () => _insertTag('[free]', '[/free]'), theme),
                  const SizedBox(width: 4),
                  _toolButtonWithLabel(Icons.alternate_email, '@朋友', () => _insertText('[@用户名] '), theme),
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget _quickSizeChip(int size, String label) {
    return Tooltip(
      message: '字号 $size',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _insertSize(size),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black12, width: 0.6),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }

  Widget _quickColorDot(Color color, String colorCode, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _insertTag('[color=$colorCode]', '[/color]'),
        child: Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 0.8),
          ),
        ),
      ),
    );
  }

  Widget _toolButtonWithLabel(
    IconData icon,
    String label,
    VoidCallback onTap,
    ThemeData theme, {
    bool isActive = false,
    bool isDanger = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer
              : (isDanger
                  ? Colors.red.withAlpha(15)
                  : theme.colorScheme.surfaceContainerHighest.withAlpha(35)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary
                : (isDanger
                    ? Colors.red.withAlpha(70)
                    : theme.colorScheme.outlineVariant.withAlpha(50)),
            width: 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isDanger
                  ? Colors.redAccent
                  : (isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isDanger
                    ? Colors.redAccent
                    : (isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarSectionTitle(String title, ThemeData theme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _toolIcon(IconData icon, String tooltip, VoidCallback onTap, {bool isActive = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isActive ? theme.colorScheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bbTextBtn(String label, String tooltip, VoidCallback onTap,
      {bool isBold = false, bool isItalic = false, bool isUnderline = false, bool isStrike = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black12, width: 0.5),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                decoration: isUnderline
                    ? TextDecoration.underline
                    : (isStrike ? TextDecoration.lineThrough : TextDecoration.none),
              ),
            ),
          ),
        ),
      ),
    );
  }
  // --- 高级选项卡片 (附加选项 / 阅读权限 / 回帖奖励 / 主题标签 / 定时发布) ---
  Widget _buildAdvancedOptionsCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(70),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 选项 Tab 栏
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withAlpha(60),
                  width: 0.8,
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _optionTab('附加选项', 0),
                  if (!_isReply) ...[
                    _optionTab('阅读权限', 1),
                    _optionTab('回帖奖励', 2),
                    _optionTab('主题标签', 3, isHighlighted: true),
                    _optionTab('定时发布', 4),
                  ],
                ],
              ),
            ),
          ),
          // Tab 对应内容区
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildActiveTabContent(theme),
          ),
        ],
      ),
    );
  }

  Widget _optionTab(String label, int index, {bool isHighlighted = false}) {
    final active = _activeOptionTab == index;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _activeOptionTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.surface : Colors.transparent,
          border: Border(
            top: active
                ? BorderSide(color: theme.colorScheme.primary, width: 2)
                : BorderSide.none,
            right: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(40),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isHighlighted)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(right: 4),
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkboxTile(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    bool enabled = true,
    Color? textColor,
  }) {
    final theme = Theme.of(context);
    final color = textColor ??
        (enabled
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurface.withAlpha(120));
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                visualDensity: VisualDensity.compact,
                onChanged: enabled ? (v) => onChanged(v ?? false) : null,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(ThemeData theme) {
    switch (_activeOptionTab) {
      case 0:
        final attr = _editorAttributes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '基本属性',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _checkboxTile(
                  '使用匿名发帖',
                  _isAnonymous,
                  (v) => setState(() => _isAnonymous = v),
                  enabled: !attr.isAnonymous.disabled,
                ),
                _checkboxTile(
                  '使用个人签名',
                  _useSig,
                  (v) => setState(() => _useSig = v),
                  enabled: !attr.useSig.disabled,
                ),
                if (!_isReply) ...[
                  _checkboxTile(
                    '回帖仅作者可见',
                    _hiddenReplies,
                    (v) => setState(() => _hiddenReplies = v),
                    enabled: !attr.hiddenReplies.disabled,
                  ),
                  _checkboxTile(
                    '回帖倒序排列',
                    _orderType,
                    (v) => setState(() => _orderType = v),
                    enabled: !attr.orderType.disabled,
                  ),
                  _checkboxTile(
                    '接收回复通知',
                    _allowNoticeAuthor,
                    (v) => setState(() => _allowNoticeAuthor = v),
                    enabled: !attr.allowNoticeAuthor.disabled,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '文本特性',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _checkboxTile(
                  'HTML 代码',
                  _htmlOn,
                  (v) => setState(() => _htmlOn = v),
                  enabled: !attr.htmlOn.disabled,
                ),
                _checkboxTile(
                  '[img] 代码',
                  _allowImgCode,
                  (v) => setState(() => _allowImgCode = v),
                  enabled: !attr.allowImgCode.disabled,
                ),
                _checkboxTile(
                  '解析图片链接',
                  _allowImgUrl,
                  (v) => setState(() => _allowImgUrl = v),
                  enabled: !attr.allowImgUrl.disabled,
                ),
                _checkboxTile(
                  '禁用链接识别',
                  _parseUrlOff,
                  (v) => setState(() => _parseUrlOff = v),
                  enabled: !attr.parseUrlOff.disabled,
                ),
                _checkboxTile(
                  '禁用表情',
                  _smileyOff,
                  (v) => setState(() => _smileyOff = v),
                  enabled: !attr.smileyOff.disabled,
                ),
                _checkboxTile(
                  '禁用编辑器代码',
                  _bbcodeOff,
                  (v) => setState(() => _bbcodeOff = v),
                  enabled: !attr.bbcodeOff.disabled,
                ),
                _checkboxTile(
                  '内容生成图片',
                  _imgContent,
                  (v) => setState(() => _imgContent = v),
                  enabled: !attr.imgContent.disabled,
                ),
                _checkboxTile(
                  '远程图片本地化',
                  _remoteImgLocalize,
                  (v) => setState(() => _remoteImgLocalize = v),
                ),
                _checkboxTile(
                  '回帖邮件提醒',
                  _replyEmailNotice,
                  (v) => setState(() => _replyEmailNotice = v),
                ),
              ],
            ),
            if (attr.hasManagementOptions) ...[
              const Divider(height: 18),
              Row(
                children: [
                  Icon(Icons.admin_panel_settings_outlined, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    '管理用户组专属选项 (Discuz Moderator)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (attr.stickTopicOptions.isNotEmpty)
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<int>(
                        value: attr.stickTopicOptions.any((o) => o.value == _stickTopic) ? _stickTopic : 0,
                        decoration: InputDecoration(
                          labelText: '置顶设置',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        items: [
                          for (final opt in attr.stickTopicOptions)
                            DropdownMenuItem(value: opt.value, child: Text(opt.name, style: const TextStyle(fontSize: 12))),
                        ],
                        onChanged: (v) => setState(() => _stickTopic = v ?? 0),
                      ),
                    ),
                  if (attr.addDigestOptions.isNotEmpty)
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<int>(
                        value: attr.addDigestOptions.any((o) => o.value == _addDigest) ? _addDigest : 0,
                        decoration: InputDecoration(
                          labelText: '加精设置',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        items: [
                          for (final opt in attr.addDigestOptions)
                            DropdownMenuItem(value: opt.value, child: Text(opt.name, style: const TextStyle(fontSize: 12))),
                        ],
                        onChanged: (v) => setState(() => _addDigest = v ?? 0),
                      ),
                    ),
                  if (attr.canCloseThread)
                    _checkboxTile(
                      '锁定主题 (关闭回复)',
                      _closeThread,
                      (v) => setState(() => _closeThread = v),
                    ),
                  if (_isEdit && attr.canDeletePost)
                    _checkboxTile(
                      '删除本帖 (管理删帖)',
                      _deletePost,
                      (v) => setState(() => _deletePost = v),
                      textColor: Colors.redAccent,
                    ),
                ],
              ),
            ],
          ],
        );
      case 1:
        final permOptions = _dynamicUserGroupPermissions.isNotEmpty
            ? _dynamicUserGroupPermissions
            : _userGroupPermissions;
        final curPerm = int.tryParse(_readPermCtrl.text.trim()) ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('快捷用户组门槛：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: permOptions.any((p) => p.value == curPerm) ? curPerm : null,
                      hint: Text(curPerm > 0 ? '自定义门槛 ($curPerm)' : '选择用户组', style: const TextStyle(fontSize: 12)),
                      items: [
                        for (final p in permOptions)
                          DropdownMenuItem(
                            value: p.value,
                            child: Text(p.label, style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _readPermCtrl.text = v > 0 ? '$v' : '');
                        }
                      },
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('精确门槛数值：', style: TextStyle(fontSize: 12)),
                    SizedBox(
                      width: 75,
                      height: 36,
                      child: TextField(
                        controller: _readPermCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: '0-255',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '说明：只有阅读权限大于或等于此数值的用户才能查看本帖内容。0 或留空为不设阅读门槛。',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('每次奖励：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    SizedBox(
                      width: 80,
                      height: 36,
                      child: TextField(
                        controller: _rewardCreditCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '铁粒',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('铁粒', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('奖励次数：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    SizedBox(
                      width: 60,
                      height: 36,
                      child: TextField(
                        controller: _rewardTimesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '次',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('次', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '发放回帖奖励将在发布帖子时扣除相应的铁粒，回复帖子的会员将按设置获得奖励。',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('标签：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _tagCtrl,
                    decoration: const InputDecoration(
                      hintText: '用逗号或空格隔开多个标签，最多可填写 5 个',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text('常用预设标签：',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
                  for (final tag in _presetTags)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        label: Text(tag, style: const TextStyle(fontSize: 10.5)),
                        onPressed: () {
                          final cur = _tagCtrl.text.trim();
                          if (cur.isEmpty) {
                            _tagCtrl.text = tag;
                          } else if (!cur.contains(tag)) {
                            _tagCtrl.text = '$cur, $tag';
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('定时发布时间：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _scheduledPublishTime ?? DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (date != null && mounted) {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _scheduledPublishTime != null
                            ? TimeOfDay.fromDateTime(_scheduledPublishTime!)
                            : const TimeOfDay(hour: 12, minute: 0),
                      );
                      if (mounted) {
                        setState(() {
                          _scheduledPublishTime = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time?.hour ?? 12,
                            time?.minute ?? 0,
                          );
                        });
                      }
                    }
                  },
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text(
                    _scheduledPublishTime == null
                        ? '选择定时日期与时间'
                        : '${_scheduledPublishTime!.year}-${_scheduledPublishTime!.month.toString().padLeft(2, '0')}-${_scheduledPublishTime!.day.toString().padLeft(2, '0')} ${_scheduledPublishTime!.hour.toString().padLeft(2, '0')}:${_scheduledPublishTime!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (_scheduledPublishTime != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    tooltip: '取消定时',
                    onPressed: () => setState(() => _scheduledPublishTime = null),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '说明：设定未来时间后，帖子将在到达指定时间时自动对所有用户公开显示。',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // --- 表情面板 ---
  Widget _buildSmileyPanel(ThemeData theme) {
    if (_smileyCats.isEmpty) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        child: _smileyLoadFailed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('表情列表加载失败', style: TextStyle(fontSize: 12)),
                  TextButton.icon(
                    onPressed: _loadSmileys,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重试'),
                  ),
                ],
              )
            : const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      );
    }

    final curCat = _smileyCats[_smileyCatIndex.clamp(0, _smileyCats.length - 1)];

    return Container(
      height: 200,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              children: [
                for (var i = 0; i < _smileyCats.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text(_smileyCats[i].name, style: const TextStyle(fontSize: 11)),
                      selected: _smileyCatIndex == i,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _smileyCatIndex = i),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(6),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 44,
                mainAxisExtent: 44,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: curCat.smileys.length,
              itemBuilder: (ctx, i) {
                final s = curCat.smileys[i];
                return InkWell(
                  onTap: () => _insertText(s.code),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: s.imageUrl,
                      cacheManager: KlpbbsCacheManager.instance,
                      httpHeaders: AppConfig.imageHeaders,
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => Text(
                        s.code.replaceAll('[', '').replaceAll(']', ''),
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentList(ThemeData theme) {
    if (_uploadedAttachments.isEmpty && !_uploadingAttachment) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attachment_rounded, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '已上传附件 (${_uploadedAttachments.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (_uploadingAttachment)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton.icon(
                  onPressed: () => _pickAndUploadAttachment(imageOnly: false),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加附件', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final att in _uploadedAttachments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    Icon(
                      att.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            att.filename,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${att.sizeText} · aid: ${att.aid}',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _insertAttachmentTag(att),
                      icon: const Icon(Icons.input, size: 15),
                      label: const Text('插入到光标', style: TextStyle(fontSize: 11.5)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                      tooltip: '删除附件',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeAttachment(att),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUnusedAttachmentsBanner(ThemeData theme) {
    if (_unusedAttachments.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '您有 ${_unusedAttachments.length} 个未使用的附件',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
                onPressed: _showUnusedAttachmentsDialog,
                icon: const Icon(Icons.folder_open, size: 14),
                label: const Text('管理/查看', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 6),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                ),
                onPressed: _insertAllUnusedAttachments,
                child: const Text('全部插入', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.redAccent),
                tooltip: '全部删除',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('删除所有未使用的附件'),
                      content: Text('确定彻底删除全部 ${_unusedAttachments.length} 个未使用的附件吗？此操作无法撤销。'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: () => Navigator.of(c).pop(true),
                          child: const Text('确认删除'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _deleteUnusedAttachments(_unusedAttachments.map((a) => a.aid).toList());
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final att in _unusedAttachments)
                ActionChip(
                  avatar: Icon(att.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 14),
                  label: Text('${att.filename} (${att.sizeText})', style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    final tag = att.isImage ? '[attachimg]${att.aid}[/attachimg]' : '[attach]${att.aid}[/attach]';
                    _insertText('\n$tag\n');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已在光标处插入附件标签：$tag')),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _insertAllUnusedAttachments() {
    final buf = StringBuffer();
    for (final a in _unusedAttachments) {
      final tag = a.isImage ? '[attachimg]${a.aid}[/attachimg]' : '[attach]${a.aid}[/attach]';
      if (!_contentCtrl.text.contains(tag)) {
        buf.writeln(tag);
      }
    }
    if (buf.isNotEmpty) {
      _insertText('\n${buf.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已将 ${_unusedAttachments.length} 个未使用附件插入正文')),
      );
    }
  }

  Future<void> _deleteUnusedAttachments(List<int> aids) async {
    final fh = _formhash ?? KlpbbsApi.cachedFormhash ?? '';
    if (fh.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缺少发帖安全凭证，删除失败')),
      );
      return;
    }
    final ok = await KlpbbsApi.deleteUnusedAttachments(
      aids,
      formhash: fh,
      tid: widget.tid,
      pid: widget.pid,
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _unusedAttachments = _unusedAttachments.where((a) => !aids.contains(a.aid)).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${aids.length} 个未使用附件')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除附件失败，请稍后重试')),
      );
    }
  }

  Future<void> _showUnusedAttachmentsDialog() async {
    if (_unusedAttachments.isEmpty) return;
    final selectedAids = <int>{for (final a in _unusedAttachments) a.aid};
    bool isDeletingBatch = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final theme = Theme.of(dialogContext);
            final allSelected = selectedAids.length == _unusedAttachments.length;
            final noneSelected = selectedAids.isEmpty;

            return Container(
              height: MediaQuery.of(dialogContext).size.height * 0.72,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_file, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '未使用的附件管理 (${_unusedAttachments.length})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Checkbox(
                          value: allSelected,
                          tristate: !allSelected && !noneSelected,
                          onChanged: (val) {
                            setDialogState(() {
                              if (allSelected) {
                                selectedAids.clear();
                              } else {
                                selectedAids.addAll(_unusedAttachments.map((a) => a.aid));
                              }
                            });
                          },
                        ),
                        InkWell(
                          onTap: () {
                            setDialogState(() {
                              if (allSelected) {
                                selectedAids.clear();
                              } else {
                                selectedAids.addAll(_unusedAttachments.map((a) => a.aid));
                              }
                            });
                          },
                          child: Text(
                            allSelected
                                ? '全选 (已选 ${selectedAids.length})'
                                : '全选 (${selectedAids.length}/${_unusedAttachments.length})',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.playlist_add_check, size: 16),
                          label: const Text('全部插入', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            _insertAllUnusedAttachments();
                            Navigator.of(ctx).pop();
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _unusedAttachments.isEmpty
                        ? const Center(child: Text('暂无未使用的附件'))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _unusedAttachments.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final att = _unusedAttachments[index];
                              final isSelected = selectedAids.contains(att.aid);

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (val) {
                                        setDialogState(() {
                                          if (val == true) {
                                            selectedAids.add(att.aid);
                                          } else {
                                            selectedAids.remove(att.aid);
                                          }
                                        });
                                      },
                                    ),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: att.isImage
                                          ? CachedNetworkImage(
                                              imageUrl: att.previewUrl,
                                              width: 44,
                                              height: 44,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => Container(
                                                width: 44,
                                                height: 44,
                                                color: theme.colorScheme.surfaceContainerHighest,
                                                child: const Icon(Icons.broken_image_outlined, size: 20),
                                              ),
                                            )
                                          : Container(
                                              width: 44,
                                              height: 44,
                                              color: theme.colorScheme.surfaceContainerHighest,
                                              child: const Icon(Icons.insert_drive_file_outlined, size: 22),
                                            ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  att.filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  'AID: ${att.aid} · ${att.sizeText}',
                                  style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: '插入正文',
                                      icon: const Icon(Icons.add_comment_outlined, size: 19),
                                      onPressed: () {
                                        final tag = att.isImage ? '[attachimg]${att.aid}[/attachimg]' : '[attach]${att.aid}[/attach]';
                                        _insertText('\n$tag\n');
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('已在光标处插入：$tag')),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      tooltip: '彻底删除',
                                      icon: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text('删除附件'),
                                            content: Text('确定彻底删除未使用的附件“${att.filename}”吗？此操作无法撤销。'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
                                              FilledButton(
                                                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                                onPressed: () => Navigator.of(c).pop(true),
                                                child: const Text('确认删除'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          await _deleteUnusedAttachments([att.aid]);
                                          setDialogState(() {
                                            selectedAids.remove(att.aid);
                                          });
                                          if (ctx.mounted && _unusedAttachments.isEmpty) {
                                            Navigator.of(ctx).pop();
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 18),
                            label: Text(
                              '删除选中 (${selectedAids.length})',
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                            ),
                            onPressed: selectedAids.isEmpty || isDeletingBatch
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('批量删除附件'),
                                        content: Text('确定彻底删除选中的 ${selectedAids.length} 个未使用的附件吗？此操作无法撤销。'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
                                          FilledButton(
                                            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                            onPressed: () => Navigator.of(c).pop(true),
                                            child: const Text('确认删除'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      setDialogState(() => isDeletingBatch = true);
                                      await _deleteUnusedAttachments(selectedAids.toList());
                                      setDialogState(() {
                                        isDeletingBatch = false;
                                        selectedAids.clear();
                                      });
                                      if (ctx.mounted && _unusedAttachments.isEmpty) {
                                        Navigator.of(ctx).pop();
                                      }
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.input, size: 18),
                            label: Text(
                              '插入选中 (${selectedAids.length})',
                              style: const TextStyle(fontSize: 13),
                            ),
                            onPressed: selectedAids.isEmpty
                                ? null
                                : () {
                                    final selectedList = _unusedAttachments.where((a) => selectedAids.contains(a.aid)).toList();
                                    final buf = StringBuffer();
                                    for (final a in selectedList) {
                                      final tag = a.isImage ? '[attachimg]${a.aid}[/attachimg]' : '[attach]${a.aid}[/attach]';
                                      if (!_contentCtrl.text.contains(tag)) {
                                        buf.writeln(tag);
                                      }
                                    }
                                    if (buf.isNotEmpty) {
                                      _insertText('\n${buf.toString()}');
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('已将 ${selectedList.length} 个附件插入正文')),
                                      );
                                    }
                                    Navigator.of(ctx).pop();
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThreadSortCard(ThemeData theme) {
    if (_threadSortInfo == null && _activeSortid == null) return const SizedBox.shrink();
    final sortInfo = _threadSortInfo;
    final availableSorts = sortInfo?.availableSorts ?? const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sortInfo != null ? '分类信息模板：${sortInfo.name}' : '分类信息模板',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              if (sortInfo != null && sortInfo.sortrequired)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.withAlpha(90)),
                  ),
                  child: const Text('必填模板', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          if (availableSorts.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in availableSorts)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: _activeSortid == item.sortid,
                        label: Text(item.name, style: const TextStyle(fontSize: 12)),
                        onSelected: (selected) {
                          if (selected) {
                            _switchThreadSort(item.sortid);
                          }
                        },
                      ),
                    ),
                  if (sortInfo != null && !sortInfo.sortrequired)
                    ChoiceChip(
                      selected: _activeSortid == 0,
                      label: const Text('不使用模板', style: TextStyle(fontSize: 12)),
                      onSelected: (selected) {
                        if (selected) {
                          _switchThreadSort(0);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
          if (_loadingSortTemplate)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (sortInfo != null && sortInfo.fields.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            for (final f in sortInfo.fields) ...[
              _buildSortFieldItem(f, theme),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSortFieldItem(SortOptionField field, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (field.required)
              const Text('* ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(
              field.title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (field.unit.isNotEmpty)
              Text(' (${field.unit})', style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
            if (field.description.isNotEmpty) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: field.description,
                child: Icon(Icons.help_outline, size: 14, color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
        if (field.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              field.description,
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
            ),
          ),
        const SizedBox(height: 6),
        if (field.isCheckbox)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in field.choices.entries)
                FilterChip(
                  label: Text(entry.value, style: const TextStyle(fontSize: 12)),
                  selected: (_typeOptionValues[field.identifier] as Set<String>?)?.contains(entry.key) ?? false,
                  onSelected: (selected) {
                    setState(() {
                      var set = _typeOptionValues[field.identifier] as Set<String>?;
                      if (set == null) {
                        set = <String>{};
                        _typeOptionValues[field.identifier] = set;
                      }
                      if (selected) {
                        set.add(entry.key);
                      } else {
                        set.remove(entry.key);
                      }
                    });
                  },
                ),
            ],
          )
        else if (field.isRadio)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in field.choices.entries)
                ChoiceChip(
                  label: Text(entry.value, style: const TextStyle(fontSize: 12)),
                  selected: _typeOptionValues[field.identifier] == entry.key,
                  onSelected: (selected) {
                    setState(() {
                      _typeOptionValues[field.identifier] = selected ? entry.key : '';
                    });
                  },
                ),
            ],
          )
        else if (field.isSelect)
          DropdownButtonFormField<String>(
            value: (_typeOptionValues[field.identifier] as String?)?.isNotEmpty == true
                ? _typeOptionValues[field.identifier] as String
                : null,
            hint: Text('请选择${field.title}', style: const TextStyle(fontSize: 13)),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
            items: [
              for (final entry in field.choices.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value, style: const TextStyle(fontSize: 13))),
            ],
            onChanged: (val) {
              setState(() {
                _typeOptionValues[field.identifier] = val ?? '';
              });
            },
          )
        else if (field.isCalendar)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2010),
                lastDate: DateTime(2035),
              );
              if (picked != null) {
                final dateStr = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                setState(() {
                  _typeOptionCtrls[field.identifier]?.text = dateStr;
                  _typeOptionValues[field.identifier] = dateStr;
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _typeOptionCtrls[field.identifier]?.text.isNotEmpty == true
                          ? _typeOptionCtrls[field.identifier]!.text
                          : '点击选择日期',
                      style: TextStyle(
                        fontSize: 13,
                        color: _typeOptionCtrls[field.identifier]?.text.isNotEmpty == true
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (field.isTextarea)
          TextField(
            controller: _typeOptionCtrls[field.identifier],
            maxLines: 3,
            minLines: 2,
            onChanged: (v) => _typeOptionValues[field.identifier] = v,
            decoration: InputDecoration(
              hintText: '请输入${field.title}',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          )
        else
          TextField(
            controller: _typeOptionCtrls[field.identifier],
            keyboardType: field.isNumber
                ? TextInputType.number
                : (field.type == 'url' ? TextInputType.url : TextInputType.text),
            onChanged: (v) => _typeOptionValues[field.identifier] = v,
            decoration: InputDecoration(
              hintText: '请输入${field.title}',
              isDense: true,
              suffixText: field.unit.isNotEmpty ? field.unit : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
      ],
    );
  }

  Widget _buildSpecialTypeTabs(ThemeData theme) {
    final types = <({int special, String name, IconData icon})>[
      (special: 0, name: '发表帖子', icon: Icons.article_outlined),
      if (_allowedSpecials.contains(1) || _allowedSpecials.length <= 1)
        (special: 1, name: '发起投票', icon: Icons.poll_outlined),
      if (_allowedSpecials.contains(3))
        (special: 3, name: '发布悬赏', icon: Icons.monetization_on_outlined),
      if (_allowedSpecials.contains(5))
        (special: 5, name: '发起辩论', icon: Icons.compare_arrows_outlined),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final t in types) ...[
            ChoiceChip(
              showCheckmark: false,
              avatar: Icon(t.icon, size: 14),
              label: Text(t.name),
              selected: _special == t.special,
              onSelected: (_) => _selectSpecial(t.special),
            ),
            const SizedBox(width: 8),
          ],
          const SizedBox(width: 4),
          ChoiceChip(
            showCheckmark: false,
            avatar: Icon(_asMobile ? Icons.phone_android : Icons.computer, size: 14),
            label: Text(_asMobile ? '手机' : '电脑', style: const TextStyle(fontSize: 11)),
            selected: true,
            onSelected: (_) {
              setState(() => _asMobile = !_asMobile);
            },
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: () => _showDraftsModal(context),
            icon: const Icon(Icons.drafts_outlined, size: 16),
            label: Text('草稿箱($_draftCount)'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = ResponsiveBreakpoints.isDesktop(context);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _insertTag('[b]', '[/b]'),
      const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _insertTag('[b]', '[/b]'),
      const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _insertTag('[i]', '[/i]'),
      const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _insertTag('[i]', '[/i]'),
      const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _insertTag('[u]', '[/u]'),
      const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _insertTag('[u]', '[/u]'),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): _showInsertLinkDialog,
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _showInsertLinkDialog,
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: FocusScope(
        child: Scaffold(
          drawer: const GlobalAppDrawer(),
          drawerEdgeDragWidth: 50.0,
          appBar: AppBar(
            leading: const GlobalNavLeading(),
            leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
            title: Text(
          widget.replyToFloorText ??
              (_isEdit
                  ? (_isFirstFloorEdit ? '编辑帖子' : '编辑回复')
                  : (_isReply ? '回复主题' : '发表帖子')),
        ),
        actions: [
          IconButton(
            tooltip: _asMobile ? '发帖设备：手机 (点击切换为电脑)' : '发帖设备：电脑 (点击切换为手机)',
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_asMobile ? Icons.phone_android : Icons.computer, size: 18),
                const SizedBox(width: 2),
                Text(
                  _asMobile ? '手机' : '电脑',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            onPressed: () {
              setState(() => _asMobile = !_asMobile);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_asMobile ? '已切换发帖来源：手机' : '已切换发帖来源：电脑'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            tooltip: '本地草稿箱',
            icon: Badge(
              isLabelVisible: _draftCount > 0,
              label: Text('$_draftCount'),
              child: const Icon(Icons.drafts_outlined),
            ),
            onPressed: () => _showDraftsModal(context),
          ),
        ],
      ),
      body: _loadingEditData
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    '正在获取帖子原有数据与 BBCode...',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : double.infinity),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // 顶部面包屑导航与版块选择（图二 & 图三）
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  Icon(Icons.home_outlined, size: 14, color: theme.colorScheme.outline),
                  Text('论坛', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                  Icon(Icons.chevron_right, size: 14, color: theme.colorScheme.outlineVariant),
                  // 版块名称（发帖模式可点击切换版块）
                  if (!_isReply && !_isEdit)
                    InkWell(
                      onTap: _showForumPicker,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withAlpha(60),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: theme.colorScheme.primary.withAlpha(90), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forum_outlined, size: 13, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              _forumName.isNotEmpty ? _forumName : '选择发布版块',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.arrow_drop_down, size: 16, color: theme.colorScheme.primary),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      _forumName.isNotEmpty ? _forumName : '灵感交流',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  Icon(Icons.chevron_right, size: 14, color: theme.colorScheme.outlineVariant),
                  Text(
                    _isReply
                        ? (_selectedQuickReply ?? (widget.threadTitle != null ? 'RE: ${widget.threadTitle}' : '参与/回复主题'))
                        : '发表帖子',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 主题类型 Tab（发表帖子 / 发起投票 / 发布悬赏 / 发起辩论 | 发帖设备 | 草稿箱）
              if (!_isReply && !_isEdit)
                _buildSpecialTypeTabs(theme),

              // 版块发帖权限异常提示
              if (_forumPermissionError != null && _forumPermissionError!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.redAccent.withAlpha(80), width: 0.8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '版块发帖限制：$_forumPermissionError',
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),

              // 未使用附件提示 Banner
              if (!_isEdit)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildUnusedAttachmentsBanner(theme),
                ),

              // 回复模式：原帖标题前缀提示（图三）
              if (_isReply)
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(40),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.colorScheme.primary.withAlpha(60), width: 0.6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.threadTitle != null && widget.threadTitle!.isNotEmpty
                              ? 'RE: ${widget.threadTitle}'
                              : 'RE: 回复当前主题',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // 发帖/编辑主楼模式：主题分类下拉 + 标题输入框 + 剩余字数统计（图二）
              if ((!_isReply && !_isEdit) || (_isEdit && _isFirstFloorEdit)) ...[
                if (isDesktop)
                  Row(
                    children: [
                      // 版块分类选择
                      if (_typeOptions.isNotEmpty) ...[
                        Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _typeid,
                              hint: const Text('选择主题分类', style: TextStyle(fontSize: 13)),
                              items: [
                                const DropdownMenuItem(value: 0, child: Text('选择主题分类')),
                                for (final t in _typeOptions)
                                  DropdownMenuItem(value: t.value, child: Text(t.name)),
                              ],
                              onChanged: (v) => setState(() => _typeid = v == 0 ? null : v),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // 标题输入框
                      Expanded(
                        child: TextField(
                          controller: _subjectCtrl,
                          maxLength: 120,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: '请输入标题',
                            isDense: true,
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '还可输入 ${120 - _subjectCtrl.text.length} 个字符',
                        style: TextStyle(
                          fontSize: 12,
                          color: _subjectCtrl.text.length >= 100
                              ? Colors.redAccent
                              : theme.colorScheme.outline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_typeOptions.isNotEmpty) ...[
                            Container(
                              height: 42,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.colorScheme.outlineVariant),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _typeid,
                                  hint: const Text('分类', style: TextStyle(fontSize: 13)),
                                  items: [
                                    const DropdownMenuItem(value: 0, child: Text('分类')),
                                    for (final t in _typeOptions)
                                      DropdownMenuItem(value: t.value, child: Text(t.name)),
                                  ],
                                  onChanged: (v) => setState(() => _typeid = v == 0 ? null : v),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: TextField(
                              controller: _subjectCtrl,
                              maxLength: 120,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: '请输入帖子标题',
                                isDense: true,
                                counterText: '',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '还可输入 ${120 - _subjectCtrl.text.length} 个字符',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _subjectCtrl.text.length >= 100
                                    ? Colors.redAccent
                                    : theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
              ],

              // 分类信息发帖模板卡片（threadsorts / sortid / typeoption）
              if ((!_isReply && !_isEdit) || (_isEdit && _isFirstFloorEdit))
                _buildThreadSortCard(theme),

              // 投票专用输入卡片 (special=1)
              if (_isPoll && !_isReply)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(70)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.poll_outlined, size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 6),
                          Text('投票设置', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _pollCtrls.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _pollCtrls[i],
                                  decoration: InputDecoration(
                                    hintText: '选项 ${i + 1}',
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 18),
                                onPressed: _pollCtrls.length > 2
                                    ? () => setState(() => _pollCtrls.removeAt(i))
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('添加选项'),
                            onPressed: () => setState(() => _pollCtrls.add(TextEditingController())),
                          ),
                          const Spacer(),
                          const Text('最多可选：', style: TextStyle(fontSize: 12)),
                          SizedBox(
                            width: 50,
                            height: 34,
                            child: TextField(
                              controller: _pollMaxCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('有效天数：', style: TextStyle(fontSize: 12)),
                          SizedBox(
                            width: 50,
                            height: 34,
                            child: TextField(
                              controller: _pollDaysCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _checkboxTile('投票后结果可见', _pollVisibility, (v) => setState(() => _pollVisibility = v)),
                          _checkboxTile('公开投票参与人', _pollOvert, (v) => setState(() => _pollOvert = v)),
                        ],
                      ),
                    ],
                  ),
                ),

              // 悬赏专用输入卡片 (special=3)
              if (_special == 3 && !_isReply)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(70)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.monetization_on_outlined, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      const Text('悬赏铁粒数：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      SizedBox(
                        width: 90,
                        height: 36,
                        child: TextField(
                          controller: _rewardCreditCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '如 50',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('铁粒', style: TextStyle(fontSize: 12)),
                      const Spacer(),
                      Text(
                        '结帖后可将悬赏派发给最佳回复者',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),

              // 辩论专用输入卡片 (special=5)
              if (_special == 5 && !_isReply)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(70)),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _affirmCtrl,
                        decoration: const InputDecoration(
                          labelText: '正方观点（必填）',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _negaCtrl,
                        decoration: const InputDecoration(
                          labelText: '反方观点（必填）',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _endTimeCtrl,
                        decoration: const InputDecoration(
                          labelText: '结束时间（可选，格式如 2026-10-01 12:00）',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),

              // 编辑器主框：双行工具栏 + 大输入框 / 实时预览
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  children: [
                    _buildAdaptiveToolbar(theme),
                    ConstrainedBox(
                      constraints: BoxConstraints(minHeight: _editorMinHeight),
                      child: _preview
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer.withAlpha(35),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: theme.colorScheme.primary.withAlpha(60)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.visibility_rounded, size: 16, color: theme.colorScheme.primary),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Discuz BBCode 实时全排版预览',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        const Spacer(),
                                        TextButton.icon(
                                          onPressed: () => setState(() => _preview = false),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          icon: const Icon(Icons.edit_outlined, size: 14),
                                          label: const Text('返回编辑', style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_contentCtrl.text.trim().isEmpty)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.description_outlined,
                                            size: 44,
                                            color: theme.colorScheme.outlineVariant,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            '编辑区尚无内容',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '在编辑区输入 BBCode 或文字后即可在此处查看实时排版',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: theme.colorScheme.outline,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    DiscuzPostRenderer(
                                      floor: PostFloor(
                                        author: '我（预览）',
                                        contentHtml: bbcodeToHtml(
                                          _contentCtrl.text,
                                          customSmileys: _smileyCats,
                                        ),
                                        blocks: ComiisParser.parseStructuredBlocksFromHtml(
                                          bbcodeToHtml(
                                            _contentCtrl.text,
                                            customSmileys: _smileyCats,
                                          ),
                                        ),
                                      ),
                                      tid: 0,
                                    ),
                                ],
                              ),
                            )
                          : TextField(
                              controller: _contentCtrl,
                              maxLines: null,
                              minLines: (_editorMinHeight / 24).floor(),
                              decoration: const InputDecoration(
                                hintText: '点击输入文本',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(14),
                              ),
                            ),
                    ),
                    // 底部草稿与统计状态栏
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withAlpha(30),
                        border: Border(
                          top: BorderSide(
                            color: theme.colorScheme.outlineVariant.withAlpha(60),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, size: 14, color: theme.colorScheme.outline),
                            const SizedBox(width: 4),
                            Text(
                              _lastSavedTimeText.isNotEmpty
                                  ? '草稿已于 $_lastSavedTimeText 自动保存'
                                  : '草稿自动保存中...',
                              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline),
                            ),
                            const SizedBox(width: 8),
                            Text('•', style: TextStyle(color: theme.colorScheme.outlineVariant)),
                            const SizedBox(width: 8),
                            Text(
                              '${_contentCtrl.text.length} 字符 / ${_contentCtrl.text.split('\n').length} 行',
                              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 8),
                            Text('•', style: TextStyle(color: theme.colorScheme.outlineVariant)),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _saveDraftManual,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text('手动保存',
                                    style: TextStyle(fontSize: 11.5, color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _showDraftsModal(context),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text('草稿箱 ($_draftCount)',
                                    style: TextStyle(fontSize: 11.5, color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('•', style: TextStyle(color: theme.colorScheme.outlineVariant)),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () {
                                if (_contentCtrl.text.isEmpty) return;
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('确认清空内容？'),
                                    content: const Text('清空后可通过撤销 (Ctrl+Z) 恢复。'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                                      FilledButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          setState(() => _contentCtrl.clear());
                                        },
                                        child: const Text('确认清空'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text('清空',
                                    style: TextStyle(fontSize: 11.5, color: Colors.redAccent)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('•', style: TextStyle(color: theme.colorScheme.outlineVariant)),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => setState(() => _editorMinHeight = min(600, _editorMinHeight + 80)),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text('加大编辑框',
                                    style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline)),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => setState(() => _editorMinHeight = max(200, _editorMinHeight - 80)),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Text('缩小编辑框',
                                    style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 已上传附件列表管理卡片
              _buildAttachmentList(theme),

              // 表情面板（点击表情图标展开）
              if (_showEmoji) _buildSmileyPanel(theme),

              // 回复模式专属：快捷回复下拉框（图三）
              if (_isReply)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      const Text('快捷回复：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Expanded(
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedQuickReply,
                              hint: const Text('在下拉框中选择您的观点快速回复↓', style: TextStyle(fontSize: 12)),
                              isExpanded: true,
                              items: [
                                for (final qr in _quickReplies)
                                  DropdownMenuItem(value: qr, child: Text(qr, style: const TextStyle(fontSize: 12))),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedQuickReply = v);
                                  _insertText(v);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 高级选项（附加选项 / 阅读权限 / 回帖奖励 / 主题标签 / 定时发布）
              _buildAdvancedOptionsCard(theme),

              const SizedBox(height: 16),

              // 提交与发布按钮行（现代 Material 3 高质感主副操作栏）
              Row(
                children: [
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        elevation: 1,
                      ),
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _isEdit ? '保存修改' : (_isReply ? '发表回复' : '立即发布帖子'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 独立位置的实时预览 / 返回编辑按钮
                  SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(
                          color: _preview ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                          width: _preview ? 1.5 : 1,
                        ),
                        backgroundColor: _preview ? theme.colorScheme.primaryContainer.withAlpha(50) : null,
                      ),
                      onPressed: () => setState(() => _preview = !_preview),
                      icon: Icon(
                        _preview ? Icons.edit_note_rounded : Icons.preview_rounded,
                        size: 18,
                        color: _preview ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                      label: Text(
                        _preview ? '返回编辑' : '实时排版预览',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _preview ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_result != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _result!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _result!.contains('成功') ? Colors.green : Colors.red,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).colorScheme.outlineVariant.withAlpha(60),
    );
  }
}



