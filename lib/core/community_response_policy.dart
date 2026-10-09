import 'discuz_forum_parser.dart';
import 'discuz_guide_protocol.dart';

/// Only an actual same-origin HTTP redirect can declare a forum alias.
class ForumPageRedirect implements Exception {
  final int fromFid, targetFid;
  final Uri uri;
  const ForumPageRedirect(this.fromFid, this.targetFid, this.uri);

  @override
  String toString() => '论坛将该版块转到了版块 $targetFid';
}

/// A recognizable document must still come from the requested community route.
/// The selected HTML page marker, rather than a redirect's optional page query,
/// is responsible for checking the returned pagination position.
class CommunityResponsePolicy {
  CommunityResponsePolicy._();

  static bool acceptsForum(Uri base, Uri response, int fid) =>
      _acceptsOrigin(base, response) &&
      _hasUniqueQuery(response) &&
      fid > 0 &&
      DiscuzForumParser.forumId(response.toString(), base) == fid;

  static ForumPageRedirect? declaredForumRedirect(
      Uri base, Uri response, int fid, int serverRedirects) {
    if (serverRedirects <= 0 ||
        !_acceptsOrigin(base, response) ||
        !_hasUniqueQuery(response)) {
      return null;
    }
    final target = DiscuzForumParser.forumId(response.toString(), base);
    return target != null && target > 0 && target != fid
        ? ForumPageRedirect(fid, target, response)
        : null;
  }

  static bool acceptsGuide(Uri base, Uri response, String view) =>
      _acceptsOrigin(base, response) &&
      _hasUniqueQuery(response) &&
      DiscuzGuideProtocol.views.contains(view) &&
      response.path.endsWith('/forum.php') &&
      response.queryParameters['mod'] == 'guide' &&
      response.queryParameters['view'] == view;

  static bool _acceptsOrigin(Uri base, Uri response) =>
      const {'http', 'https'}.contains(base.scheme) &&
      const {'http', 'https'}.contains(response.scheme) &&
      base.host.isNotEmpty &&
      response.host.isNotEmpty &&
      base.userInfo.isEmpty &&
      response.userInfo.isEmpty &&
      base.origin == response.origin;

  static bool _hasUniqueQuery(Uri response) =>
      response.queryParametersAll.values.every((values) => values.length == 1);
}
