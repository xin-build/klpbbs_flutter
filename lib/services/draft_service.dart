import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地草稿模型
class PostDraft {
  final String id;
  final String subject;
  final String content;
  final int? fid;
  final String? forumName;
  final int? typeid;
  final int special;
  final String? tags;
  final bool isReply;
  final int? tid;
  final String? targetAuthor;
  final bool? asMobile;
  final DateTime updatedAt;

  const PostDraft({
    required this.id,
    required this.subject,
    required this.content,
    this.fid,
    this.forumName,
    this.typeid,
    this.special = 0,
    this.tags,
    this.isReply = false,
    this.tid,
    this.targetAuthor,
    this.asMobile,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'content': content,
        if (fid != null) 'fid': fid,
        if (forumName != null) 'forumName': forumName,
        if (typeid != null) 'typeid': typeid,
        'special': special,
        if (tags != null) 'tags': tags,
        'isReply': isReply,
        if (tid != null) 'tid': tid,
        if (targetAuthor != null) 'targetAuthor': targetAuthor,
        if (asMobile != null) 'asMobile': asMobile,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PostDraft.fromJson(Map<String, dynamic> json) {
    return PostDraft(
      id: json['id'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      content: json['content'] as String? ?? '',
      fid: json['fid'] as int?,
      forumName: json['forumName'] as String?,
      typeid: json['typeid'] as int?,
      special: json['special'] as int? ?? 0,
      tags: json['tags'] as String?,
      isReply: json['isReply'] as bool? ?? false,
      tid: json['tid'] as int?,
      targetAuthor: json['targetAuthor'] as String?,
      asMobile: json['asMobile'] as bool?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  PostDraft copyWith({
    String? id,
    String? subject,
    String? content,
    int? fid,
    String? forumName,
    int? typeid,
    int? special,
    String? tags,
    bool? isReply,
    int? tid,
    String? targetAuthor,
    bool? asMobile,
    DateTime? updatedAt,
  }) {
    return PostDraft(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      content: content ?? this.content,
      fid: fid ?? this.fid,
      forumName: forumName ?? this.forumName,
      typeid: typeid ?? this.typeid,
      special: special ?? this.special,
      tags: tags ?? this.tags,
      isReply: isReply ?? this.isReply,
      tid: tid ?? this.tid,
      targetAuthor: targetAuthor ?? this.targetAuthor,
      asMobile: asMobile ?? this.asMobile,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 本地草稿箱服务
class DraftService {
  DraftService._();
  static final DraftService instance = DraftService._();

  static const String _draftsKey = 'klpbbs_local_drafts_v1';
  static const String _autosaveKey = 'klpbbs_editor_autosave_v1';

  Timer? _debounceTimer;

  /// 获取所有保存的草稿列表（按最后更新时间倒序）
  Future<List<PostDraft>> getAllDrafts({bool? isReply}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_draftsKey);
      if (raw == null || raw.isEmpty) return [];

      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => PostDraft.fromJson(e as Map<String, dynamic>))
          .where((d) => isReply == null || d.isReply == isReply)
          .toList();

      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// 保存或更新草稿
  Future<bool> saveDraft(PostDraft draft) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final drafts = await getAllDrafts();
      final index = drafts.indexWhere((d) => d.id == draft.id);

      final updatedDraft = draft.copyWith(updatedAt: DateTime.now());
      if (index >= 0) {
        drafts[index] = updatedDraft;
      } else {
        drafts.insert(0, updatedDraft);
      }

      // 最多保留 50 份草稿
      if (drafts.length > 50) {
        drafts.removeRange(50, drafts.length);
      }

      final jsonStr = jsonEncode(drafts.map((d) => d.toJson()).toList());
      return await sp.setString(_draftsKey, jsonStr);
    } catch (_) {
      return false;
    }
  }

  /// 删除指定草稿
  Future<bool> deleteDraft(String id) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final drafts = await getAllDrafts();
      drafts.removeWhere((d) => d.id == id);
      final jsonStr = jsonEncode(drafts.map((d) => d.toJson()).toList());
      return await sp.setString(_draftsKey, jsonStr);
    } catch (_) {
      return false;
    }
  }

  /// 清空所有草稿
  Future<bool> clearAllDrafts({bool? isReply}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (isReply == null) {
        return await sp.remove(_draftsKey);
      } else {
        final drafts = await getAllDrafts();
        drafts.removeWhere((d) => d.isReply == isReply);
        final jsonStr = jsonEncode(drafts.map((d) => d.toJson()).toList());
        return await sp.setString(_draftsKey, jsonStr);
      }
    } catch (_) {
      return false;
    }
  }

  /// 取消正在等待的防抖自动保存
  void cancelAutoSave() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// 自动保存草稿（防抖 1 秒）
  void autoSave(PostDraft draft) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1000), () async {
      try {
        final sp = await SharedPreferences.getInstance();
        final key = draft.isReply
            ? '${_autosaveKey}_reply_${draft.tid ?? 0}'
            : '${_autosaveKey}_post_${draft.fid ?? 0}';
        final jsonStr = jsonEncode(draft.toJson());
        await sp.setString(key, jsonStr);
      } catch (_) {}
    });
  }

  /// 获取自动保存的草稿
  Future<PostDraft?> getAutoSavedDraft({int? fid, int? tid, bool isReply = false}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final key = isReply
          ? '${_autosaveKey}_reply_${tid ?? 0}'
          : '${_autosaveKey}_post_${fid ?? 0}';
      final raw = sp.getString(key);
      if (raw == null || raw.isEmpty) return null;
      return PostDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 清除自动保存的草稿（发帖/回帖成功后调用）
  Future<void> clearAutoSavedDraft({int? fid, int? tid, bool isReply = false}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final key = isReply
          ? '${_autosaveKey}_reply_${tid ?? 0}'
          : '${_autosaveKey}_post_${fid ?? 0}';
      await sp.remove(key);
    } catch (_) {}
  }
}
