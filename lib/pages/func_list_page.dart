import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/discuz_request_policy.dart';
import '../core/klpbbs_developer_platform.dart';
import '../core/klpbbs_authorizations.dart';
import 'authorized_apps_page.dart';
import 'membership_page.dart';
import 'developer_console_page.dart';
import 'native_discuz_page.dart';
import 'avatar_edit_page.dart';
import 'phone_bind_page.dart';
import 'facemall_page.dart';

/// 保留旧调用位置，实际内容由原生表单与数据页面承接。
class FuncListPage extends StatelessWidget {
  final String title;
  final String path;
  const FuncListPage({super.key, required this.title, required this.path});

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(path);
    final query = uri?.queryParameters ?? const <String, String>{};
    final accountUid = int.tryParse(query['uid'] ?? '');
    final ownAccount = query['uid'] == null ||
        (accountUid != null && accountUid == KlpbbsApi.currentCachedMyUid);
    final base = Uri.parse(AppConfig.baseUrl);
    final localRoute = uri != null &&
        DiscuzRequestPolicy.sameOrigin(base, base.resolveUri(uri));
    final developerView = localRoute
        ? KlpbbsDeveloperPlatform.viewFor(base.resolveUri(uri))
        : null;
    if (developerView != null) {
      return DeveloperConsolePage(initialView: developerView);
    }
    if (localRoute &&
        ownAccount &&
        KlpbbsAuthorizations.isListPage(base.resolveUri(uri))) {
      return const AuthorizedAppsPage();
    }
    if (localRoute &&
        ownAccount &&
        uri.path.split('/').last == 'home.php' &&
        query['mod'] == 'spacecp' &&
        query['ac'] == 'usergroup' &&
        query['do'] == 'list' &&
        uri.queryParametersAll.values.every((values) => values.length == 1) &&
        query.keys.every((key) =>
            const {'mod', 'ac', 'do', 'mobile', 'uid'}.contains(key))) {
      return const MembershipPage();
    }
    if (localRoute &&
        (uri.path == 'home.php' || uri.path.endsWith('/home.php')) &&
        query['mod'] == 'spacecp' &&
        query['ac'] == 'plugin' &&
        query['id'] == 'sunju_facemall:face' &&
        ownAccount) {
      return const FacemallPage();
    }
    if (uri?.queryParameters['id'] == 'klpbbs_pnbind:my_bind') {
      return const PhoneBindPage();
    }
    if (uri?.path.endsWith('home.php') == true &&
        uri?.queryParameters['mod'] == 'spacecp' &&
        uri?.queryParameters['ac'] == 'avatar') {
      return const AvatarEditPage();
    }
    return NativeDiscuzPage(title: title, path: path);
  }
}
