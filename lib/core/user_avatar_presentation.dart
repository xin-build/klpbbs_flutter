import 'klpbbs_facemall.dart';

/// Display contract from sunju_face.js: frame = avatar * 7/4, inset = 3/8.
/// Avatar URLs and declared pendant URLs remain separate sources.
class UserAvatarPresentation {
  UserAvatarPresentation._();

  static const double frameScale = 7 / 4;

  static String? avatarUrl(String? source, Uri base) {
    final value = source?.split('##SJ##').first.trim();
    if (value == null || value.isEmpty) return null;
    final Uri uri;
    try {
      uri = base.resolve(value);
    } on FormatException {
      return null;
    }
    if (!const {'http', 'https'}.contains(uri.scheme)) return null;
    final path = uri.path.toLowerCase();
    if (path.contains('noavatar') ||
        path.endsWith('/none.gif') ||
        path.endsWith('/none.png') ||
        path.endsWith('/spacer.gif') ||
        path.contains('static/image/common/none')) {
      return null;
    }
    return uri.toString();
  }

  static bool isCurrentUser({
    required bool loggedIn,
    required int? uid,
    required int? currentUid,
    required String author,
    required String? currentUsername,
  }) {
    if (!loggedIn) return false;
    // A real UID takes precedence over labels, including the UI label "我".
    if (uid != null && uid > 0) {
      return currentUid != null && currentUid > 0 && uid == currentUid;
    }
    return currentUsername?.isNotEmpty == true && author == currentUsername;
  }

  static String? frameUrl({
    required Uri base,
    String? declaredFrame,
    String? avatarSource,
    required bool isCurrentUser,
    String? currentFrame,
    String? cachedCurrentFrame,
    String? cachedDeclaredFrame,
  }) {
    // Explicit empty means the page returned no frame; do not put it back.
    final source = declaredFrame ??
        (avatarSource?.contains('##SJ##') == true
            ? avatarSource!.split('##SJ##').last
            : cachedDeclaredFrame ??
                (isCurrentUser ? currentFrame ?? cachedCurrentFrame : null));
    return KlpFacemallResponse.frameUrl(source, base);
  }
}
