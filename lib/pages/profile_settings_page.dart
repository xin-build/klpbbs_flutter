import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../models/user_space.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';
import 'facemall_page.dart';
import 'func_list_page.dart';
import 'phone_bind_page.dart';
import 'profile_edit_page.dart';
import 'user_space_page.dart';
import 'verify_info_page.dart';

/// 资料设置主页面（1:1 绝对对齐 Discuz 移动端网页 home.php?mod=space&do=profile&set=comiis&mycenter=1&mobile=2）
class ProfileSettingsPage extends StatefulWidget {
  final int? uid;
  const ProfileSettingsPage({super.key, this.uid});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  int? _uid;
  UserSpace? _user;
  bool _loading = true;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = widget.uid ?? await KlpbbsApi.getMyUid();
    if (uid != null) {
      final results = await Future.wait([
        KlpbbsApi.getUserSpace(uid),
        KlpbbsApi.getProfileEditData(op: 'info'),
      ]);
      final u = results[0] as UserSpace?;
      final editData = results[1] as Map<String, dynamic>;
      final compRate = editData['completionRate'] as int? ?? 0;

      if (mounted) {
        setState(() {
          _uid = uid;
          if (u != null && compRate > 0) {
            _user = UserSpace(
              uid: u.uid,
              username: u.username,
              credits: u.credits,
              group: u.group,
              regdate: u.regdate,
              lastvisit: u.lastvisit,
              signature: u.signature,
              level: u.level,
              levelName: u.levelName,
              medals: u.medals,
              faceUrl: u.faceUrl,
              bgUrl: u.bgUrl,
              stats: u.stats,
              creditsDetail: u.creditsDetail,
              gameProfile: u.gameProfile,
              isOnline: u.isOnline,
              onlineStatusText: u.onlineStatusText,
              profileProgress: compRate,
            );
          } else {
            _user = u;
          }
          _loading = false;
        });
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _completionRate {
    if (_user == null) return 0;
    if (_user!.profileProgress > 0) return _user!.profileProgress;
    int total = 8;
    int filled = 0;
    if (_user!.signature.isNotEmpty) filled++;
    if (_user!.gameProfile.containsKey('自定义头衔') || _user!.gameProfile.containsKey('头衔')) filled++;
    if (_user!.gameProfile.containsKey('基岩版用户名') || _user!.gameProfile.containsKey('Minecraft 基岩版 ID')) filled++;
    if (_user!.gameProfile.containsKey('Java版用户名') || _user!.gameProfile.containsKey('Minecraft Java 正版玩家 ID')) filled++;
    if (_user!.gameProfile.containsKey('生日') || _user!.gameProfile.containsKey('出生日期')) filled++;
    if (_user!.gameProfile.containsKey('性别')) filled++;
    if (_user!.gameProfile.containsKey('代表作')) filled++;
    if (_user!.faceUrl.isNotEmpty || _user!.medals.isNotEmpty) filled++;
    return ((filled / total) * 100).round().clamp(0, 100);
  }

  Future<void> _pickAndUploadAvatar() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      if (mounted) setState(() => _uploadingAvatar = true);
      final ok = await KlpbbsApi.uploadAvatar(path);
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? '头像上传更新成功！' : '头像上传已提交，等待后台生效'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadUser();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('头像选取/上传异常：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _showAvatarOptions() {
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
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: theme.colorScheme.primary),
              title: const Text('从相册选择图片上传'),
              subtitle: Text(
                '支持 JPG / PNG / GIF 图片',
                style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndUploadAvatar();
              },
            ),
            ListTile(
              leading: Icon(Icons.crop_original_outlined, color: theme.colorScheme.secondary),
              title: const Text('网页端完整头像编辑器'),
              subtitle: Text(
                '支持在线缩放、裁剪与预览',
                style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FuncListPage(
                      title: '修改头像',
                      path: 'home.php?mod=spacecp&ac=avatar&mobile=2',
                    ),
                  ),
                ).then((_) => _loadUser());
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPasswordSecurityDialog() {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool isSubmitting = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.shield_outlined),
              SizedBox(width: 8),
              Text('密码安全设置'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '原密码',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新密码',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '确认新密码',
                    prefixIcon: Icon(Icons.check_circle_outline),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FuncListPage(
                      title: '密码安全中心',
                      path: 'home.php?mod=spacecp&ac=profile&op=password&mobile=2',
                    ),
                  ),
                );
              },
              child: const Text('网页端修改'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final oldPwd = oldController.text.trim();
                      final newPwd = newController.text.trim();
                      final confirmPwd = confirmController.text.trim();

                      if (oldPwd.isEmpty || newPwd.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入原密码和新密码')),
                        );
                        return;
                      }
                      if (newPwd != confirmPwd) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('两次输入的新密码不一致')),
                        );
                        return;
                      }

                      setModalState(() => isSubmitting = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final nav = Navigator.of(ctx);
                      final res = await KlpbbsApi.updatePassword(
                        oldPassword: oldPwd,
                        newPassword: newPwd,
                        newPasswordConfirm: confirmPwd,
                      );
                      if (!mounted) return;
                      nav.pop();
                      messenger.showSnackBar(
                        SnackBar(content: Text(res.message), behavior: SnackBarBehavior.floating),
                      );
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('保存修改'),
            ),
          ],
        ),
      ),
    );
  }

  void _showVerifyInfoDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerifyInfoPage(userSpace: _user),
      ),
    );
  }

  void _showPhoneBindDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhoneBindPage(userSpace: _user),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前登录的苦力怕论坛账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF5222D),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await KlpbbsApi.logout();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已退出登录')),
                );
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('确定退出'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF5222D)),
            SizedBox(width: 8),
            Text('注销账号须知'),
          ],
        ),
        content: const Text(
          '账号注销后，您在论坛发表的所有资源、帖子、积分资产、已佩戴勋章及好友关系将被永久清空且无法找回。\n\n如需继续注销，请前往网页端安全中心进行身份验证与审核。',
          style: TextStyle(height: 1.4, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF5222D)),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FuncListPage(
                    title: '注销账号',
                    path: 'home.php?mod=spacecp&ac=profile&op=cancel&mobile=2',
                  ),
                ),
              );
            },
            child: const Text('继续注销'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('资料设置'),
        centerTitle: true,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '我的空间',
            onPressed: () {
              if (_uid != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => UserSpacePage(uid: _uid!)),
                );
              }
            },
          ),
          const GlobalNavButton(),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  children: [
                    // 1. 用户资料概览卡片 (带完整度指示器)
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withAlpha(60),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            UserAvatarWidget(
                              uid: _uid ?? 0,
                              author: _user?.username ?? '我',
                              size: 54,
                              faceUrl: _user?.faceUrl,
                              onTap: _showAvatarOptions,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _user?.username ?? '我的账号',
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'UID: ${_uid ?? "—"}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: _completionRate / 100,
                                            minHeight: 6,
                                            backgroundColor: colorScheme.surfaceContainerHighest,
                                            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '资料完整度 $_completionRate%',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.primary,
                                        ),
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
                    const SizedBox(height: 16),

                    // 2. 账号装扮与个人资料设置组
                    _buildSectionHeader('装扮与资料'),
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withAlpha(60),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _buildAppTile(
                            icon: Icons.account_box_outlined,
                            iconColor: Colors.blueAccent,
                            title: '修改头像',
                            subtitle: '支持本地图片上传或网页在线裁剪',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_uploadingAvatar)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  UserAvatarWidget(
                                    uid: _uid ?? 0,
                                    author: _user?.username ?? '我',
                                    size: 28,
                                    faceUrl: _user?.faceUrl,
                                  ),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right_rounded, color: colorScheme.outline, size: 20),
                              ],
                            ),
                            onTap: _showAvatarOptions,
                          ),
                          Divider(height: 1, indent: 54, color: colorScheme.outlineVariant.withAlpha(40)),
                          _buildAppTile(
                            icon: Icons.auto_awesome_rounded,
                            iconColor: Colors.amber.shade700,
                            title: '修改挂件',
                            subtitle: '选购、续费与佩戴论坛专属头像框挂件',
                            trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline, size: 20),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FacemallPage(
                                    uid: _uid,
                                    username: _user?.username,
                                    avatarUrl: _user?.faceUrl,
                                  ),
                                ),
                              ).then((_) => _loadUser());
                            },
                          ),
                          Divider(height: 1, indent: 54, color: colorScheme.outlineVariant.withAlpha(40)),
                          _buildAppTile(
                            icon: Icons.badge_outlined,
                            iconColor: colorScheme.primary,
                            title: '资料修改',
                            subtitle: '基本资料、游戏信息、个性签名与自定义头衔',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withAlpha(120),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '已完成$_completionRate%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right_rounded, color: colorScheme.outline, size: 20),
                              ],
                            ),
                            onTap: () async {
                              final ok = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(builder: (_) => ProfileEditPage(initialUser: _user)),
                              );
                              if (ok == true) _loadUser();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. 安全与认证设置组
                    _buildSectionHeader('安全与认证'),
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withAlpha(60),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _buildAppTile(
                            icon: Icons.lock_outline_rounded,
                            iconColor: Colors.indigoAccent,
                            title: '密码安全',
                            subtitle: '修改论坛登录密码与安全提问',
                            trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline, size: 20),
                            onTap: _showPasswordSecurityDialog,
                          ),
                          Divider(height: 1, indent: 54, color: colorScheme.outlineVariant.withAlpha(40)),
                          _buildAppTile(
                            icon: Icons.verified_user_outlined,
                            iconColor: Colors.teal,
                            title: '认证信息',
                            subtitle: '创作者认证、官方认证与实名信息',
                            trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline, size: 20),
                            onTap: _showVerifyInfoDialog,
                          ),
                          Divider(height: 1, indent: 54, color: colorScheme.outlineVariant.withAlpha(40)),
                          _buildAppTile(
                            icon: Icons.phone_android_rounded,
                            iconColor: Colors.blue,
                            title: '手机号绑定',
                            subtitle: '绑定或更换安全验证手机号',
                            trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline, size: 20),
                            onTap: _showPhoneBindDialog,
                          ),
                          Divider(height: 1, indent: 54, color: colorScheme.outlineVariant.withAlpha(40)),
                          _buildAppTile(
                            icon: Icons.person_remove_outlined,
                            iconColor: Colors.deepOrangeAccent,
                            title: '注销账号',
                            subtitle: '永久注销论坛账号与清空个人数据',
                            trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline, size: 20),
                            onTap: _showDeleteAccountDialog,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 4. 退出登录按钮 (App 风格卡片)
                    Card(
                      elevation: 0,
                      color: colorScheme.errorContainer.withAlpha(40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: colorScheme.error.withAlpha(60),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _showLogoutDialog,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.logout_rounded, color: colorScheme.error, size: 19),
                                const SizedBox(width: 8),
                                Text(
                                  '退出登录',
                                  style: TextStyle(
                                    color: colorScheme.error,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildAppTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
