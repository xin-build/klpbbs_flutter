import 'package:shared_preferences/shared_preferences.dart';
import '../core/local_draft_repository.dart';
import '../models/post_draft.dart';
export '../models/post_draft.dart';

/// The owner is captured by the editor before asynchronous work begins.
/// No global draft is attributed to the current account automatically.
class DraftService {
  DraftService._();
  static final DraftService instance = DraftService._();

  late final LocalDraftRepository _repository = LocalDraftRepository(
    read: (key) async => (await SharedPreferences.getInstance()).getString(key),
    write: (key, value) async =>
        (await SharedPreferences.getInstance()).setString(key, value),
    remove: (key) async => (await SharedPreferences.getInstance()).remove(key),
    keys: () async => (await SharedPreferences.getInstance()).getKeys(),
  );

  Future<List<PostDraft>> getAllDrafts(
          {required String owner, bool? isReply}) =>
      _repository.list(owner, isReply: isReply);
  Future<List<PostDraft>> getUnclaimedLegacyDrafts() =>
      _repository.unclaimedLegacy();
  Future<bool> saveDraft(PostDraft draft, {required String owner}) =>
      _repository.save(owner, draft);
  Future<bool> importLegacyDraft(PostDraft draft, {required String owner}) =>
      _repository.importLegacy(owner, draft);
  Future<bool> deleteDraft(String id, {required String owner}) =>
      _repository.delete(owner, id);
  Future<bool> clearAllDrafts({required String owner, bool? isReply}) =>
      _repository.clear(owner, isReply: isReply);
  Future<bool> saveAutoDraft(PostDraft draft, {required String owner}) =>
      _repository.saveAuto(owner, draft);
  Future<PostDraft?> getAutoSavedDraft(
          {required String owner,
          int? fid,
          int? tid,
          int? pid,
          bool isReply = false,
          bool isEdit = false}) =>
      _repository.auto(owner,
          fid: fid, tid: tid, pid: pid, isReply: isReply, isEdit: isEdit);
  Future<bool> clearAutoSavedDraft(
          {required String owner,
          int? fid,
          int? tid,
          int? pid,
          bool isReply = false,
          bool isEdit = false}) =>
      _repository.clearAuto(owner,
          fid: fid, tid: tid, pid: pid, isReply: isReply, isEdit: isEdit);
}
