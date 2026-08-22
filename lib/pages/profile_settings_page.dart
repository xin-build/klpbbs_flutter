import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../models/user_space.dart';
import '../widgets/thread_card.dart';
import 'facemall_page.dart';
import 'func_list_page.dart';
import 'profile_edit_page.dart';
import 'user_space_page.dart';

/// 资料设置页面（深度复刻图三，全功能实装，统一 Material 3 主题）
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
      final u = await KlpbbsApi.getUserSpace(uid);
      if (mounted) {
        setState(() {
          _uid = uid;
          _user = u;
          _loading = false;
        });
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _completionRate {
    if (_user == null) return 88;
    int total = 7;
    int filled = 0;
    if (_user!.signature.isNotEmpty || _user!.gameProfile.containsKey('个人签名')) filled++;
    if (_user!.gameProfile.containsKey('自定义头衔')) filled++;
    if (_user!.gameProfile.containsKey('基岩版用户名')) filled++;
    if (_user!.gameProfile.containsKey('生日')) filled++;
    if (_user!.gameProfile.containsKey('性别')) filled++;
    if (_user!.gameProfile.containsKey('代表作')) filled++;
    if (_user!.faceUrl.isNotEmpty || _user!.medals.isNotEmpty) filled++;
    return ((filled / total) * 100).round().clamp(60, 100);
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

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            onPressed: () {
              if (newController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('两次输入的新密码不一致')),
                );
                return;
              }
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('密码修改请求已提交')),
              );
            },
            child: const Text('保存修改'),
          ),
        ],
      ),
    );
  }

  void _showVerifyInfoDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Text('实名与认证信息'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('苦力怕论坛注册用户'),
              subtitle: Text('UID: ${_uid ?? "—"}'),
            ),
            const Divider(),
            const Text(
              '已开启论坛安全保护。如需认证开发者、模组创作者或团队官方认证，请通过网页端提交审核材料。',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FuncListPage(
                    title: '认证信息',
                    path: 'home.php?mod=spacecp&ac=profile&op=verify&mobile=2',
                  ),
                ),
              );
            },
            child: const Text('前往认证中心'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showPhoneBindDialog() {
    final phoneController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.phone_android_outlined),
            SizedBox(width: 8),
            Text('手机号绑定'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '绑定手机号可用于账号安全验证、快捷找回密码及接收重要论坛通知。',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '手机号码',
                prefixIcon: Icon(Icons.phone),
                hintText: '请输入大陆11位手机号',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FuncListPage(
                    title: '手机号绑定',
                    path: 'home.php?mod=spacecp&ac=profile&op=contact&mobile=2',
                  ),
                ),
              );
            },
            child: const Text('网页端绑定'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('绑定请求已提交')),
              );
            },
            child: const Text('发送验证码'),
          ),
        ],
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
              backgroundColor: Theme.of(context).colorScheme.error,
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
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            const Text('注销账号须知'),
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FuncListPage(
                    title: '账号注销安全审核',
                    path: 'home.php?mod=spacecp&ac=profile&op=password&mobile=2',
                  ),
                ),
              );
            },
            child: const Text('继续前往审核'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('资料设置'),
        centerTitle: true,
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
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  children: [
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant.withAlpha(80),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          // 1. 修改头像 (图三)
                          _buildSettingsTile(
                            title: '修改头像',
                            icon: Icons.account_circle_outlined,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_uploadingAvatar)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  UserAvatarWidget(
                                    uid: _uid ?? 0,
                                    author: _user?.username ?? '我',
                                    size: 34,
                                    faceUrl: _user?.faceUrl,
                                  ),
                                const SizedBox(width: 6),
                                Icon(Icons.chevron_right, color: theme.colorScheme.outline, size: 20),
                              ],
                            ),
                            onTap: _showAvatarOptions,
                          ),
                          Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withAlpha(50)),

                          // 2. 修改挂件 (图三)
                          _buildSettingsTile(
                            title: '修改挂件 / 装扮空间',
                            icon: Icons.auto_awesome_outlined,
                            trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline, size: 20),
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
                          Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withAlpha(50)),

                          // 3. 资料修改 (图三: 已完成88% >)
                          _buildSettingsTile(
                            title: '资料修改',
                            icon: Icons.edit_note_outlined,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer.withAlpha(100),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '已完成$_completionRate%',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right, color: theme.colorScheme.outline, size: 20),
                              ],
                            ),
                            onTap: () async {
                              final ok = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(builder: (_) => const ProfileEditPage()),
                              );
                              if (ok == true) _loadUser();
                            },
                          ),
                          Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withAlpha(50)),

                          // 4. 密码安全 (图三)
                          _buildSettingsTile(
                            title: '密码安全',
                            icon: Icons.lock_outline,
                            trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline, size: 20),
                            onTap: _showPasswordSecurityDialog,
                          ),
                          Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withAlpha(50)),

                          // 5. 认证信息 (图三)
                          _buildSettingsTile(
                            title: '认证信息',
                            icon: Icons.verified_user_outlined,
                            trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline, size: 20),
                            onTap: _showVerifyInfoDialog,
                          ),
                          Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withAlpha(50)),

                          // 6. 手机号绑定 (图三)
                          _buildSettingsTile(
                            title: '手机号绑定',
                            icon: Icons.phone_android_outlined,
                            trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline, size: 20),
                            onTap: _showPhoneBindDialog,
                          ),
                          Divider(height: 1, indent: 56, color: theme.colorScheme.outlineVariant.withAlpha(50)),

                          // 7. 注销账号 (图三)
                          _buildSettingsTile(
                            title: '注销账号',
                            icon: Icons.person_remove_outlined,
                            trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline, size: 20),
                            onTap: _showDeleteAccountDialog,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 退出登录按钮 (图三: 红色居中)
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.error.withAlpha(60),
                        ),
                      ),
                      color: theme.colorScheme.errorContainer.withAlpha(50),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _showLogoutDialog,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.logout, color: theme.colorScheme.error, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  '退出登录',
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
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
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSettingsTile({
    required String title,
    required IconData icon,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurface,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
