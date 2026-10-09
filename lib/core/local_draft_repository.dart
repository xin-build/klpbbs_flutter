import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/post_draft.dart';

typedef DraftRead = FutureOr<String?> Function(String key);
typedef DraftWrite = Future<bool> Function(String key, String value);
typedef DraftRemove = Future<bool> Function(String key);
typedef DraftKeys = FutureOr<Iterable<String>> Function();

/// One serialized queue prevents overlapping editors from losing saved entries.
/// It stores only snapshots; it has no network or submission capability.
class LocalDraftRepository {
  static const legacyKey = 'klpbbs_local_drafts_v1';
  final DraftRead read;
  final DraftWrite write;
  final DraftRemove remove;
  final DraftKeys? keys;
  Future<void> _queue = Future<void>.value();

  LocalDraftRepository(
      {required this.read,
      required this.write,
      required this.remove,
      this.keys});

  static String owner({required String site, int? uid, String? session}) {
    final parsed = Uri.parse(site);
    final identity = uid != null && uid > 0
        ? 'uid:$uid'
        : (session == null ? 'guest' : 'unresolved:$session');
    return sha256.convert(utf8.encode('${parsed.origin}|$identity')).toString();
  }

  static String draftsKey(String owner) => 'klpbbs_local_drafts_v2:$owner';
  static String autosaveKey(String owner,
          {int? fid,
          int? tid,
          int? pid,
          bool isReply = false,
          bool isEdit = false}) =>
      'klpbbs_editor_autosave_v2:$owner:${isEdit ? "edit_${tid ?? 0}_${pid ?? 0}" : isReply ? "reply_${tid ?? 0}" : "post_${fid ?? 0}"}';

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  List<PostDraft> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid draft list');
    final drafts = decoded
        .map((value) =>
            PostDraft.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
    if (drafts.any((draft) => draft.id.isEmpty)) {
      throw const FormatException('Draft without identity');
    }
    return drafts..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<List<PostDraft>> list(String owner, {bool? isReply}) async =>
      List<PostDraft>.unmodifiable(_decode(await read(draftsKey(owner)))
          .where((draft) => isReply == null || draft.isReply == isReply));

  Future<List<PostDraft>> unclaimedLegacy() async {
    final drafts = _decode(await read(legacyKey));
    final available = keys;
    if (available != null) {
      for (final key in await available()) {
        if (!RegExp(r'^klpbbs_editor_autosave_v1_(?:post|reply)_\d+$')
            .hasMatch(key)) {
          continue;
        }
        final raw = await read(key);
        if (raw == null || raw.isEmpty) continue;
        final draft = PostDraft.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
        if (draft.subject.trim().isNotEmpty ||
            draft.content.trim().isNotEmpty) {
          drafts.add(draft.copyWith(id: 'legacy_$key'));
        }
      }
    }
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List<PostDraft>.unmodifiable(drafts);
  }

  Future<bool> save(String owner, PostDraft draft) => _serialized(() async {
        final drafts = _decode(await read(draftsKey(owner)));
        drafts.removeWhere((entry) => entry.id == draft.id);
        drafts.insert(0, draft.copyWith(updatedAt: DateTime.now()));
        // Do not evict a different draft silently when the box is full.
        if (drafts.length > 50) return false;
        return write(draftsKey(owner),
            jsonEncode(drafts.map((entry) => entry.toJson()).toList()));
      });

  Future<bool> delete(String owner, String id) => _serialized(() async {
        final drafts = _decode(await read(draftsKey(owner)))
          ..removeWhere((entry) => entry.id == id);
        return write(draftsKey(owner),
            jsonEncode(drafts.map((entry) => entry.toJson()).toList()));
      });

  Future<bool> clear(String owner, {bool? isReply}) => _serialized(() async {
        if (isReply == null) return remove(draftsKey(owner));
        final drafts = _decode(await read(draftsKey(owner)))
          ..removeWhere((entry) => entry.isReply == isReply);
        return write(draftsKey(owner),
            jsonEncode(drafts.map((entry) => entry.toJson()).toList()));
      });

  Future<bool> saveAuto(String owner, PostDraft draft) =>
      _serialized(() => write(
          autosaveKey(owner,
              fid: draft.fid,
              tid: draft.tid,
              pid: draft.pid,
              isReply: draft.isReply,
              isEdit: draft.isEdit),
          jsonEncode(draft.toJson())));

  Future<PostDraft?> auto(String owner,
      {int? fid,
      int? tid,
      int? pid,
      bool isReply = false,
      bool isEdit = false}) async {
    final raw = await read(autosaveKey(owner,
        fid: fid, tid: tid, pid: pid, isReply: isReply, isEdit: isEdit));
    if (raw == null || raw.isEmpty) return null;
    return PostDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  Future<bool> clearAuto(String owner,
          {int? fid,
          int? tid,
          int? pid,
          bool isReply = false,
          bool isEdit = false}) =>
      _serialized(() => remove(autosaveKey(owner,
          fid: fid, tid: tid, pid: pid, isReply: isReply, isEdit: isEdit)));

  /// Explicitly selected legacy snapshots are copied. The unowned original stays
  /// untouched because an old global file cannot prove which account owns it.
  Future<bool> importLegacy(String owner, PostDraft draft) =>
      save(owner, draft.copyWith(id: 'import_${draft.id}'));
}
