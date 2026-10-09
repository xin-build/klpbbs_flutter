import '../widgets/app_motion.dart';
import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../core/app_config.dart';
import '../models/user_space.dart';
import '../widgets/global_app_drawer.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';
import 'facemall_page.dart';
import 'authorized_apps_page.dart';
import 'avatar_edit_page.dart';
import 'func_list_page.dart';
import 'phone_bind_page.dart';
import 'profile_edit_page.dart';
import 'user_space_page.dart';
import 'verify_info_page.dart';
import 'web_login_page.dart';

class ProfileSettingsPage extends StatefulWidget {
  final int? uid;
  const ProfileSettingsPage({super.key, this.uid});
  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  UserSpace? _user;
  int? _uid;
  String? _error;
  bool _loading = true;
  int _loadSequence = 0;
  bool _refreshNeeded = false;

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_onSessionChanged);
    KlpbbsApi.profileChanges.addListener(_onProfileChanged);
    _uid = KlpbbsApi.currentCachedMyUid;
    _user = KlpbbsApi.cachedSpace;
    _loadUser();
  }

  @override
  void dispose() {
    _loadSequence++;
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    KlpbbsApi.profileChanges.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {
        _user = null;
        _uid = null;
        _refreshNeeded = false;
      });
      _loadUser();
    }
  }

  void _onProfileChanged() {
    _refreshNeeded = true;
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      _loadUser(force: true);
    }
  }

  Future<void> _loadUser({bool force = false}) async {
    final sequence = ++_loadSequence;
    final session = DioClient.sessionKey;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final uid = await KlpbbsApi.getMyUid();
      final user = uid == null
          ? null
          : await KlpbbsApi.getUserSpace(uid, forceRefresh: force);
      if (!mounted ||
          sequence != _loadSequence ||
          session != DioClient.sessionKey) {
        return;
      }
      setState(() {
        final sameUser = _uid == uid;
        _uid = uid;
        _user = user ?? (sameUser ? _user : null);
        _refreshNeeded = false;
        _error = uid == null
            ? '登录后可管理个人资料与账号安全'
            : (user == null ? '个人资料暂时无法读取' : null);
      });
    } catch (error) {
      if (mounted &&
          sequence == _loadSequence &&
          session == DioClient.sessionKey) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted &&
          sequence == _loadSequence &&
          session == DioClient.sessionKey) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(Widget page) async {
    final session = DioClient.sessionKey;
    final result = await Navigator.of(context)
        .push(MaterialPageRoute<Object?>(builder: (_) => page));
    if (mounted &&
        session == DioClient.sessionKey &&
        (_refreshNeeded || result == true)) {
      await _loadUser(force: true);
    }
  }

  Future<void> _logout() async {
    final session = DioClient.sessionKey;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出当前论坛账号？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出')),
        ],
      ),
    );
    if (confirmed != true || session != DioClient.sessionKey) return;
    await KlpbbsApi.logout();
    if (mounted) Navigator.pop(context, true);
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap,
      {Widget? trailing}) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: Icon(icon, color: colors.primary),
      title: Text(title),
      subtitle: Text(subtitle,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: _uid == null ? null : onTap,
    );
  }

  Widget _group(String title, List<Widget> items) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ),
        Card.filled(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) const Divider(height: 1, indent: 58),
              items[index],
            ]
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appearance = _group('资料与装扮', [
      _tile(Icons.account_circle_outlined, '修改头像', '使用论坛当前的头像编辑与审核流程',
          () => _open(AvatarEditPage(userSpace: _user)),
          trailing: _uid == null
              ? null
              : UserAvatarWidget(
                  uid: _uid!,
                  author: _user?.username ?? '',
                  size: 30,
                  reserveFrameSpace: true,
                  faceUrl: UserAvatarWidget.optionalFrame(_user?.faceUrl))),
      _tile(Icons.badge_outlined, '个人资料', '基本资料、游戏信息与个性签名',
          () => _open(ProfileEditPage(initialUser: _user))),
      _tile(
          Icons.auto_awesome_outlined,
          '头像挂件',
          '查看、选购与佩戴已有挂件',
          () => _open(FacemallPage(
              uid: _uid,
              username: _user?.username,
              avatarUrl: KlpbbsApi.currentCachedMyAvatar ??
                  (_uid == null ? null : AppConfig.avatarUrl(_uid!))))),
    ]);
    final security = _group('账号安全', [
      _tile(
          Icons.shield_outlined,
          '密码与安全邮箱',
          '修改密码、邮箱与安全提问',
          () => _open(const FuncListPage(
                title: '密码安全中心',
                path: 'home.php?mod=spacecp&ac=profile&op=password&mobile=no',
              ))),
      _tile(Icons.phone_android_outlined, '手机绑定', '查看绑定状态与短信验证',
          () => _open(PhoneBindPage(userSpace: _user))),
      _tile(Icons.verified_outlined, '认证信息', '查看论坛开放的认证与申请状态',
          () => _open(VerifyInfoPage(userSpace: _user))),
      _tile(Icons.apps_outlined, '我的授权', '查看第三方应用与账号授权',
          () => _open(const AuthorizedAppsPage())),
    ]);
    return Scaffold(
      drawer: const GlobalAppDrawer(),
      appBar: AppBar(
        leading: const GlobalNavLeading(),
        leadingWidth: GlobalNavLeading.preferredLeadingWidth(context),
        title: const Text('资料设置'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新资料',
              onPressed: _loading ? null : () => _loadUser(force: true))
        ],
      ),
      body: _loading && _user == null && _uid == null
          ? const Center(child: AppLoadingIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_loading)
                      const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: AppLoadingBar(minHeight: 2)),
                    if (_error != null)
                      Card.outlined(
                          child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: _uid == null
                                  ? () => _open(const WebLoginPage())
                                  : () => _loadUser(force: true),
                              child: Text(_uid == null ? '登录论坛' : '重试')),
                        ]),
                      )),
                    if (_uid != null)
                      Card.filled(
                        color: theme.colorScheme.primaryContainer,
                        margin: const EdgeInsets.only(bottom: 24),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(children: [
                            UserAvatarWidget(
                                uid: _uid!,
                                author: _user?.username ?? '',
                                size: 60,
                                reserveFrameSpace: true,
                                faceUrl: UserAvatarWidget.optionalFrame(
                                    _user?.faceUrl),
                                onTap: () => _open(UserSpacePage(uid: _uid!))),
                            const SizedBox(width: 18),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(_user?.username ?? '我的资料',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onPrimaryContainer)),
                                  const SizedBox(height: 4),
                                  Text(
                                      'UID $_uid${_user?.group.isNotEmpty == true ? ' · ${_user!.group}' : ''}',
                                      style: TextStyle(
                                          color: theme
                                              .colorScheme.onPrimaryContainer)),
                                  if (_user?.hasProfileProgress == true) ...[
                                    const SizedBox(height: 10),
                                    Text('资料完整度 ${_user!.profileProgress}%',
                                        style: theme.textTheme.labelMedium),
                                    const SizedBox(height: 5),
                                    AppLoadingBar(
                                        value: _user!.profileProgress
                                                .clamp(0, 100) /
                                            100),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    FilledButton.tonalIcon(
                                        onPressed: () => _open(ProfileEditPage(
                                            initialUser: _user)),
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 18),
                                        label: const Text('编辑资料')),
                                    TextButton.icon(
                                        onPressed: () =>
                                            _open(UserSpacePage(uid: _uid!)),
                                        icon: const Icon(
                                            Icons.open_in_new_rounded,
                                            size: 18),
                                        label: const Text('查看空间')),
                                  ]),
                                ])),
                          ]),
                        ),
                      ),
                    LayoutBuilder(
                        builder: (context, constraints) => constraints
                                    .maxWidth >=
                                780
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Expanded(
                                        child: AppFadeIn(
                                            key: const ValueKey(
                                                'profile-appearance'),
                                            child: appearance)),
                                    const SizedBox(width: 20),
                                    Expanded(
                                        child: AppFadeIn(
                                            key: const ValueKey(
                                                'profile-security'),
                                            index: 1,
                                            child: security))
                                  ])
                            : Column(children: [
                                AppFadeIn(
                                    key: const ValueKey('profile-appearance'),
                                    child: appearance),
                                const SizedBox(height: 24),
                                AppFadeIn(
                                    key: const ValueKey('profile-security'),
                                    index: 1,
                                    child: security)
                              ])),
                    if (_uid != null) ...[
                      const SizedBox(height: 24),
                      Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                              onPressed: _logout,
                              icon: const Icon(Icons.logout),
                              label: const Text('退出登录'))),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
