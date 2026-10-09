import 'dart:convert';

/// A local editor snapshot. Identity and routing are never inferred from its text.
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
  final bool isEdit;
  final int? tid;
  final int? pid;
  final String? targetAuthor;
  final bool? asMobile;
  final DateTime updatedAt;
  final Map<String, dynamic> composerState;

  PostDraft({
    required this.id,
    required this.subject,
    required this.content,
    this.fid,
    this.forumName,
    this.typeid,
    this.special = 0,
    this.tags,
    this.isReply = false,
    this.isEdit = false,
    this.tid,
    this.pid,
    this.targetAuthor,
    this.asMobile,
    required this.updatedAt,
    Map<String, dynamic> composerState = const {},
  }) : composerState = _freezeMap(composerState);

  static Map<String, dynamic> _freezeMap(Map<String, dynamic> source) =>
      Map<String, dynamic>.unmodifiable(
          source.map((key, value) => MapEntry(key, _freeze(value))));

  static dynamic _freeze(dynamic value) {
    if (value is Map) {
      return _freezeMap(Map<String, dynamic>.from(value));
    }
    if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw ArgumentError('Draft state must be JSON data');
  }

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
        'isEdit': isEdit,
        if (tid != null) 'tid': tid,
        if (pid != null) 'pid': pid,
        if (targetAuthor != null) 'targetAuthor': targetAuthor,
        if (asMobile != null) 'asMobile': asMobile,
        'updatedAt': updatedAt.toIso8601String(),
        'composerState': composerState,
      };

  factory PostDraft.fromJson(Map<String, dynamic> json) => PostDraft(
        id: json['id'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        content: json['content'] as String? ?? '',
        fid: json['fid'] as int?,
        forumName: json['forumName'] as String?,
        typeid: json['typeid'] as int?,
        special: json['special'] as int? ?? 0,
        tags: json['tags'] as String?,
        isReply: json['isReply'] as bool? ?? false,
        isEdit: json['isEdit'] as bool? ?? false,
        tid: json['tid'] as int?,
        pid: json['pid'] as int?,
        targetAuthor: json['targetAuthor'] as String?,
        asMobile: json['asMobile'] as bool?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        composerState: Map<String, dynamic>.from(
            json['composerState'] as Map? ?? const {}),
      );

  PostDraft copyWith({String? id, DateTime? updatedAt}) => PostDraft(
        id: id ?? this.id,
        subject: subject,
        content: content,
        fid: fid,
        forumName: forumName,
        typeid: typeid,
        special: special,
        tags: tags,
        isReply: isReply,
        isEdit: isEdit,
        tid: tid,
        pid: pid,
        targetAuthor: targetAuthor,
        asMobile: asMobile,
        updatedAt: updatedAt ?? this.updatedAt,
        composerState: composerState,
      );

  bool canRestoreInto(
          {required bool reply, required bool edit, int? thread, int? post}) =>
      isReply == reply &&
      isEdit == edit &&
      (!reply || tid == thread) &&
      (!edit || (tid == thread && pid == post));

  /// Excludes timestamps; unchanged snapshots do not cause another disk write.
  String get contentSignature {
    final json = toJson()
      ..remove('updatedAt')
      ..remove('id');
    return jsonEncode(json);
  }
}
