import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/preload_service.dart';
import '../models/user_space.dart';
import '../widgets/app_back_button.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';
import 'credit_page.dart';
import 'facemall_page.dart';
import 'favorite_forums_page.dart';
import 'friend_page.dart';
import 'homestyle_page.dart';
import 'login_page.dart';
import 'magic_page.dart';
import 'medal_page.dart';
import 'notice_page.dart';
import 'profile_settings_page.dart';
import 'settings_page.dart';
import 'sign_rank_page.dart';
import 'user_space_page.dart';
import 'user_threads_page.dart';

/// 苦力怕论坛全新独立个人中心（聚合资产、装扮、日常互动与账号管理）
class UserCenterPage extends StatefulWidget {
  const UserCenterPage({super.key});

  @override
  State<UserCenterPage> createState() => _UserCenterPageState();
}

class _UserCenterPageState extends State<UserCenterPage> {
  int? _myUid;
  UserSpace? _userSpace;
  bool _loading = true;
  String _iron = '0';
  String _credits = '0';
  int _medalsCount = 0;
  int _threadsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  static String _cleanPlainText(String html) {
    if (html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?<\/style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?<\/script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _loadProfile() async {
    final uid = await KlpbbsApi.getMyUid();
    if (!mounted) return;

    if (uid == null || uid <= 0) {
      setState(() {
        _myUid = null;
        _userSpace = null;
        _loading = false;
      });
      return;
    }

    _myUid = uid;
    final cached = PreloadService.instance.get<UserSpace>('user_space_$uid', ignoreExpired: true);
    if (cached != null) {
      final threadCount = int.tryParse(cached.stats['主题'] ?? '0') ?? 0;
      final rawIron = cached.creditsDetail['铁粒'] ?? '0';
      final cleanIron = rawIron.replaceAll('粒', '').replaceAll('铁', '').trim();
      setState(() {
        _userSpace = cached;
        _iron = cleanIron.isNotEmpty ? cleanIron : '0';
        _credits = cached.credits.isNotEmpty ? cached.credits : (cached.creditsDetail['经验'] ?? '0');
        _medalsCount = cached.medals.length;
        _threadsCount = threadCount;
        _loading = false;
      });
    } else {
      setState(() => _loading = true);
    }

    final space = await KlpbbsApi.getUserSpace(uid);
    if (!mounted) return;

    if (space != null) {
      final threadCount = int.tryParse(space.stats['主题'] ?? '0') ?? 0;
      final rawIron = space.creditsDetail['铁粒'] ?? '0';
      final cleanIron = rawIron.replaceAll('粒', '').replaceAll('铁', '').trim();
      setState(() {
        _userSpace = space;
        _iron = cleanIron.isNotEmpty ? cleanIron : '0';
        _credits = space.credits.isNotEmpty ? space.credits : (space.creditsDetail['经验'] ?? '0');
        _medalsCount = space.medals.length;
        _threadsCount = threadCount;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  void _openSpace() {
    if (_myUid != null && _myUid! > 0) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserSpacePage(uid: _myUid!, isMe: true, initialUser: _userSpace),
        ),
      ).then((_) => _loadProfile());
    } else {
      _openLogin();
    }
  }

  void _openLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    ).then((_) => _loadProfile());
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前论坛账号吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await KlpbbsApi.logout();
      await AppConfig.setMyFaceUrl(null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已退出登录'), behavior: SnackBarBehavior.floating),
      );
      _loadProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('个人中心'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新资料',
            onPressed: _loadProfile,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '应用设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          const GlobalNavButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          HapticFeedback.lightImpact();
          await _loadProfile();
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. 用户信息概览卡片
                _buildUserHeaderCard(theme, colorScheme),
                const SizedBox(height: 14),

                // 2. 核心资产快捷数字条 (铁粒 / 总积分 / 勋章 / 主题)
                _buildQuickAssetBar(theme, colorScheme),
                const SizedBox(height: 18),

                // 3. 个人资产与空间装扮
                _buildSectionTitle('资产与空间装扮', colorScheme),
                const SizedBox(height: 8),
                _buildCardGroup([
                  _buildMenuTile(
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: const Color(0xFFF07B00),
                    title: '积分中心',
                    subtitle: '我的积分 / 积分转账 / 交易记录流水',
                    trailingText: '$_iron 铁粒',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 0)),
                    ).then((_) => _loadProfile()),
                  ),
                  _buildMenuTile(
                    icon: Icons.auto_fix_high_outlined,
                    iconColor: const Color(0xFF78C252),
                    title: '道具中心',
                    subtitle: '道具商店 / 我的道具包 / 道具记录',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MagicPage()),
                    ).then((_) => _loadProfile()),
                  ),
                  _buildMenuTile(
                    icon: Icons.military_tech_outlined,
                    iconColor: const Color(0xFFFFB300),
                    title: '勋章中心',
                    subtitle: '勋章佩戴 / 勋章商城 / 勋章日志',
                    trailingText: '$_medalsCount 枚',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MedalPage()),
                    ).then((_) => _loadProfile()),
                  ),
                  _buildMenuTile(
                    icon: Icons.face_retouching_natural,
                    iconColor: const Color(0xFF00A2FF),
                    title: '头像挂件',
                    subtitle: '挂件商城 / 我的挂件 / 头像边框装扮',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => FacemallPage(uid: _myUid, username: _userSpace?.username)),
                    ).then((_) => _loadProfile()),
                  ),
                  _buildMenuTile(
                    icon: Icons.wallpaper_outlined,
                    iconColor: const Color(0xFF9C27B0),
                    title: '装扮空间',
                    subtitle: '空间主题壁纸 / 主世界 / 地狱 / 可爱风格',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => HomeStylePage(uid: _myUid, username: _userSpace?.username)),
                    ).then((_) => _loadProfile()),
                  ),
                ], colorScheme),
                const SizedBox(height: 18),

                // 4. 论坛日常与互动
                _buildSectionTitle('日常与论坛互动', colorScheme),
                const SizedBox(height: 8),
                _buildCardGroup([
                  _buildMenuTile(
                    icon: Icons.event_available_outlined,
                    iconColor: const Color(0xFF2E7D32),
                    title: '每日签到',
                    subtitle: '每日打卡 / 连续签到奖励 / 签到榜单',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SignRankPage()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.article_outlined,
                    iconColor: const Color(0xFF1976D2),
                    title: '我的帖子',
                    subtitle: '我发表的主题与回复历史',
                    trailingText: '$_threadsCount 篇',
                    onTap: () {
                      if (_myUid != null && _myUid! > 0) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UserThreadsPage(
                              uid: _myUid!,
                              type: 'thread',
                              title: '我的主题',
                            ),
                          ),
                        );
                      } else {
                        _openLogin();
                      }
                    },
                  ),
                  _buildMenuTile(
                    icon: Icons.star_outline_rounded,
                    iconColor: const Color(0xFFE91E63),
                    title: '我的收藏',
                    subtitle: '收藏的主题与关注的版块',
                    onTap: () {
                      if (_myUid != null && _myUid! > 0) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => FavoriteForumsPage(uid: _myUid!)),
                        );
                      } else {
                        _openLogin();
                      }
                    },
                  ),
                  _buildMenuTile(
                    icon: Icons.notifications_outlined,
                    iconColor: const Color(0xFF00897B),
                    title: '我的消息',
                    subtitle: '系统提醒 / 坛友私信 / 互动回复通知',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NoticePage()),
                    ),
                  ),
                  _buildMenuTile(
                    icon: Icons.people_outline_rounded,
                    iconColor: const Color(0xFF5C6BC0),
                    title: '我的好友',
                    subtitle: '好友列表与关注动态',
                    onTap: () {
                      if (_myUid != null && _myUid! > 0) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => FriendPage(uid: _myUid!)),
                        );
                      } else {
                        _openLogin();
                      }
                    },
                  ),
                ], colorScheme),
                const SizedBox(height: 18),

                // 5. 账号设置与系统
                _buildSectionTitle('账号与应用设置', colorScheme),
                const SizedBox(height: 8),
                _buildCardGroup([
                  _buildMenuTile(
                    icon: Icons.badge_outlined,
                    iconColor: const Color(0xFF455A64),
                    title: '个人资料设置',
                    subtitle: '修改昵称、密码、个性签名档与公开资料',
                    onTap: () {
                      if (_myUid != null && _myUid! > 0) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ProfileSettingsPage(uid: _myUid)),
                        ).then((_) => _loadProfile());
                      } else {
                        _openLogin();
                      }
                    },
                  ),
                  _buildMenuTile(
                    icon: Icons.palette_outlined,
                    iconColor: const Color(0xFF00ACC1),
                    title: '外观与偏好设置',
                    subtitle: '主题模式、RGB 流光、字号大小与单实例保护',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    ),
                  ),
                  if (_myUid != null && _myUid! > 0)
                    _buildMenuTile(
                      icon: Icons.logout_rounded,
                      iconColor: Colors.red.shade400,
                      title: '退出登录',
                      subtitle: '退出当前账号或切换其他论坛账号',
                      onTap: _handleLogout,
                    )
                  else
                    _buildMenuTile(
                      icon: Icons.login_rounded,
                      iconColor: colorScheme.primary,
                      title: '登录账号',
                      subtitle: '登录苦力怕论坛账号解锁全部特权',
                      onTap: _openLogin,
                    ),
                ], colorScheme),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 顶部用户信息展示卡片
  Widget _buildUserHeaderCard(ThemeData theme, ColorScheme colorScheme) {
    if (_loading && _userSpace == null) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_myUid == null || _myUid! <= 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.primary.withAlpha(210)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withAlpha(40),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person_outline, size: 36, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '尚未登录论坛账号',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '点击此处立即登录，同步个人资产与帖子',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: colorScheme.primary,
              ),
              onPressed: _openLogin,
              child: const Text('登录 / 注册', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    final user = _userSpace!;

    return InkWell(
      onTap: _openSpace,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary,
              colorScheme.primary.withAlpha(220),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withAlpha(50),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // 用户头像（叠放挂件）
            UserAvatarWidget(
              uid: _myUid,
              author: user.username,
              size: 64,
            ),
            const SizedBox(width: 16),
            // 用户资料信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(60),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          user.group.isNotEmpty ? user.group : (user.levelName.isNotEmpty ? user.levelName : '高级会员'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'UID: $_myUid',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _cleanPlainText(user.signature).isNotEmpty
                        ? _cleanPlainText(user.signature)
                        : '点击进入个人空间查看详细主页与动态',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  /// 核心资产快捷数据栏（铁粒 / 总积分 / 勋章 / 主题数）
  Widget _buildQuickAssetBar(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildAssetNumberItem(
            label: '铁粒余额',
            value: _iron,
            color: const Color(0xFFF07B00),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 0)),
            ).then((_) => _loadProfile()),
          ),
          _buildDivider(colorScheme),
          _buildAssetNumberItem(
            label: '论坛积分',
            value: _credits,
            color: colorScheme.primary,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 0)),
            ).then((_) => _loadProfile()),
          ),
          _buildDivider(colorScheme),
          _buildAssetNumberItem(
            label: '勋章数量',
            value: '$_medalsCount',
            color: const Color(0xFFFFB300),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MedalPage()),
            ).then((_) => _loadProfile()),
          ),
          _buildDivider(colorScheme),
          _buildAssetNumberItem(
            label: '发表主题',
            value: '$_threadsCount',
            color: const Color(0xFF1976D2),
            onTap: () {
              if (_myUid != null && _myUid! > 0) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserThreadsPage(
                      uid: _myUid!,
                      type: 'thread',
                      title: '我的主题',
                    ),
                  ),
                );
              } else {
                _openLogin();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAssetNumberItem({
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF777777),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Container(
      width: 1,
      height: 24,
      color: colorScheme.outlineVariant.withAlpha(50),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: colorScheme.primary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildCardGroup(List<Widget> children, ColorScheme colorScheme) {
    return Material(
      color: colorScheme.surface,
      elevation: 0.5,
      shadowColor: Colors.black.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.6,
                color: colorScheme.outlineVariant.withAlpha(35),
              ),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconColor.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11.5,
          color: Color(0xFF888888),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) ...[
            Text(
              trailingText,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.chevron_right, size: 20, color: Color(0xFFBBBBBB)),
        ],
      ),
      onTap: onTap,
    );
  }
}
