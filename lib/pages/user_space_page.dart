import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/comiis_parser.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../models/user_space.dart';
import '../models/usergroup_comparison.dart';
import '../widgets/global_nav.dart';
import '../widgets/inline_html_text.dart';
import '../widgets/thread_card.dart';
import 'credit_page.dart';
import 'friend_page.dart';
import 'homestyle_page.dart';
import 'login_page.dart';
import 'magic_page.dart';
import 'medal_page.dart';
import 'pm_detail_page.dart';
import 'profile_settings_page.dart';
import 'user_threads_page.dart';

/// 苦力怕论坛个人空间 / 我的空间（深度复刻图二：官方移动端空间完整资料与操作体系，100% 防塌陷架构）
class UserSpacePage extends StatefulWidget {
  final int uid;
  final bool? isMe;
  final UserSpace? initialUser;

  const UserSpacePage({
    super.key,
    required this.uid,
    this.isMe,
    this.initialUser,
  });

  @override
  State<UserSpacePage> createState() => _UserSpacePageState();
}

class _UserSpacePageState extends State<UserSpacePage> {
  late Future<UserSpace?> _future;
  int _selectedTab = 0; // 0: 资料, 1: 帖子
  bool _isMe = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialUser != null) {
      _future = Future.value(widget.initialUser);
      _isMe = widget.isMe ?? false;
    } else {
      _loadData();
    }
  }

  void _loadData() {
    setState(() {
      _future = KlpbbsApi.getUserSpace(widget.uid);
    });
    if (widget.isMe != null) {
      _isMe = widget.isMe!;
    } else {
      KlpbbsApi.getMyUid().then((myUid) {
        if (mounted && myUid != null) {
          setState(() => _isMe = (myUid == widget.uid));
        }
      });
    }
  }

  void _showQrCodeDialog(UserSpace user) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${user.username} 的空间二维码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withAlpha(50)),
              ),
              child: const Icon(Icons.qr_code_2, size: 160, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            SelectableText(
              'https://klpbbs.com/?${user.uid}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'https://klpbbs.com/?${user.uid}'));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制个人空间链接')),
              );
            },
            child: const Text('复制链接'),
          ),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 用户组权限与全等级对照系统抽屉（100% 还原 home.php?mod=spacecp&ac=usergroup 网页真实数据）
  /// 用户组权限与全等级对照系统抽屉（100% 还原 home.php?mod=spacecp&ac=usergroup 网页真实数据与菜单分类）
  void _showUsergroupPrivilegesDialog(UserSpace user) {
    int? selectedGid;
    String selectedGroupName = 'Lv.5 金牌会员';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => DefaultTabController(
          length: 2,
          child: DraggableScrollableSheet(
            initialChildSize: 0.88,
            maxChildSize: 0.96,
            minChildSize: 0.5,
            expand: false,
            builder: (c, scroll) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Color(0xFFF57C00), size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        '用户组权限对照系统',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                    ],
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(text: '我的与目标组对比'),
                    Tab(text: '全等级权限对照表'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Tab 1: 网页真实双列对照（我的主用户组 vs 选定用户组）
                      Column(
                        children: [
                          // 顶部用户组切换栏（对应网页右上角：晋级用户组 / 站点管理组 / 普通用户组）
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
                            child: Row(
                              children: [
                                const Text('对比目标：', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        // 晋级用户组快捷标签
                                        for (final g in UsergroupComparison.allGroups.where((e) => e.category == '晋级用户组'))
                                          Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: ChoiceChip(
                                              label: Text(g.name, style: const TextStyle(fontSize: 11.5)),
                                              selected: selectedGroupName == g.name,
                                              onSelected: (selected) {
                                                if (selected) {
                                                  setModalState(() {
                                                    selectedGroupName = g.name;
                                                    selectedGid = g.gid;
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                        // 更多用户组选择（站点管理组 / 普通用户组）
                                        PopupMenuButton<KlpbbsUserGroupMeta>(
                                          tooltip: '更多用户组',
                                          child: Chip(
                                            avatar: const Icon(Icons.more_horiz, size: 16),
                                            label: Text(
                                              UsergroupComparison.allGroups.any((e) => e.name == selectedGroupName && e.category != '晋级用户组')
                                                  ? selectedGroupName
                                                  : '管理/特殊组...',
                                              style: const TextStyle(fontSize: 11.5),
                                            ),
                                          ),
                                          itemBuilder: (ctx) => [
                                            const PopupMenuItem<KlpbbsUserGroupMeta>(
                                              enabled: false,
                                              child: Text('—— 站点管理组 ——', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                            ),
                                            for (final g in UsergroupComparison.allGroups.where((e) => e.category == '站点管理组'))
                                              PopupMenuItem(value: g, child: Text(g.name, style: const TextStyle(fontSize: 13))),
                                            const PopupMenuItem<KlpbbsUserGroupMeta>(
                                              enabled: false,
                                              child: Text('—— 普通用户组 ——', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                            ),
                                            for (final g in UsergroupComparison.allGroups.where((e) => e.category == '普通用户组'))
                                              PopupMenuItem(value: g, child: Text(g.name, style: const TextStyle(fontSize: 13))),
                                          ],
                                          onSelected: (meta) {
                                            setModalState(() {
                                              selectedGroupName = meta.name;
                                              selectedGid = meta.gid;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: FutureBuilder<UsergroupComparison>(
                              key: ValueKey('usergroup_${selectedGroupName}_${selectedGid ?? 0}'),
                              future: KlpbbsApi.getUsergroupComparison(
                                currentGroupName: user.levelName.isNotEmpty ? user.levelName : user.level,
                                currentCredits: int.tryParse(user.credits),
                                targetGroupName: selectedGroupName,
                                gid: selectedGid,
                              ),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(40),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                final comp = snapshot.data ??
                                    ComiisParser.defaultUsergroupComparison(
                                      currentGroupName: user.levelName.isNotEmpty ? user.levelName : user.level,
                                      currentCredits: int.tryParse(user.credits),
                                      targetGroupName: selectedGroupName,
                                      gid: selectedGid,
                                    );

                                return ListView(
                                  controller: scroll,
                                  padding: const EdgeInsets.all(12),
                                  children: [
                                    // 1. 顶部橙绿双列标头
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFF57C00),
                                              borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  comp.myGroup.title,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                                if (comp.myGroup.subtitle.isNotEmpty) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '💡 ${comp.myGroup.subtitle}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF00897B),
                                              borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  comp.upgradeGroup?.title ?? '对比目标 - $selectedGroupName',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                                if (comp.upgradeGroup?.subtitle.isNotEmpty == true) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '💡 ${comp.upgradeGroup!.subtitle}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // 2. 权限明细对照表
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surface,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          for (int i = 0; i < comp.permissions.length; i++)
                                            _buildComparisonItemRow(
                                              comp.permissions[i],
                                              i % 2 == 0,
                                              Theme.of(context),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      // Tab 2: 全等级对照表（严格对应苦力怕论坛真实用户组数据）
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildMatrixGroup('限制会员 (积分 < 0)', [
                            '积分下限：-999999999 (积分 < 0)',
                            '阅读权限 10，访问论坛 ✔，发新话题/回复 ✔',
                            '允许发短消息 ✔，允许加好友 ✔，允许 @ 10 人',
                            '最大签名长度 100 字节，支持编辑器代码，单个附件上限 5 MB',
                          ]),
                          _buildMatrixGroup('Lv.1 新手上路 (0 - 199 积分)', [
                            '积分下限：0 积分',
                            '阅读权限 10，允许常规版块发帖与回复 ✔',
                            '允许参与评分 ✔，加好友 ✖，打招呼 ✖，允许 @ 10 人',
                            '最大签名长度 100 字节，单个附件 50 MB，每天附件上限 50 MB',
                          ]),
                          _buildMatrixGroup('Lv.2 注册会员 (200 - 999 积分)', [
                            '积分下限：200 积分',
                            '阅读权限 20，解锁加好友 ✔，打招呼 ✔，回帖奖励 ✔，参与点评 ✔',
                            '签名支持 [img] 图文代码 ✔，最大签名长度 200 字节',
                            '允许 @ 15 人，单个附件 50 MB，每天附件上限 50 MB',
                          ]),
                          _buildMatrixGroup('Lv.3 中级会员 (1000 - 4999 积分)', [
                            '积分下限：1000 积分',
                            '阅读权限 30，解锁自定义头衔 ✔，发表辩论 ✔',
                            '允许创建 5 个淘专辑 ✔，允许 @ 20 人',
                            '最大签名长度 300 字节，每天附件上限 100 MB',
                          ]),
                          _buildMatrixGroup('Lv.4 高级会员 (5000 - 9999 积分)', [
                            '积分下限：5000 积分',
                            '阅读权限 50，自定义头衔 ✔，解锁设置附件权限 ✔',
                            '允许 @ 25 人，允许创建 5 个淘专辑 ✔',
                            '最大签名长度 500 字节，每天附件上限 300 MB',
                          ]),
                          _buildMatrixGroup('Lv.5 金牌会员 (10000 - 49999 积分)', [
                            '积分下限：10000 积分',
                            '阅读权限 70，解锁隐身特权 ✔，发表活动 ✔',
                            '允许 @ 30 人，允许创建 5 个淘专辑 ✔',
                            '最大签名长度 1000 字节，每天附件上限 500 MB',
                          ]),
                          _buildMatrixGroup('Lv.6 论坛元老 (50000+ 积分)', [
                            '积分下限：50000 积分',
                            '阅读权限 90，隐身特权 ✔，发表活动 ✔',
                            '允许 @ 50 人，允许创建 5 个淘专辑 ✔',
                            '最大签名长度 2000 字节，每天附件上限 1 GB (1024 MB)',
                          ]),
                          _buildMatrixGroup('👑 站点管理组 (管理员 / 超级版主 / 版主 / 实习版主 / 网站编辑 / 信息监察员 / 审核员)', [
                            '管理员：阅读权限 255，查看统计报表 ✔，发表文章 ✔，发帖不受限制 ✔，签名 3000 字节',
                            '超级版主：阅读权限 150，查看统计报表 ✔，发帖不受限制 ✔，签名 2000 字节，允许 @ 50 人',
                            '版主：阅读权限 100，查看统计报表 ✔，发帖不受限制 ✔，签名 1500 字节，允许 @ 50 人',
                            '实习版主 / 网站编辑 / 信息监察员 / 审核员：阅读权限 100 - 200，发帖不受限制与专属管理权限',
                          ]),
                          _buildMatrixGroup('💎 普通与特殊组 (SVIP / VIP / QQ游客 / 等待邮箱验证 / 游客 / 禁止发言 / 禁止访问 / 禁止 IP)', [
                            'SVIP：阅读权限 80，隐身 ✔，发表活动 ✔，允许 @ 50 人，签名 2000 字节，每天附件 300 MB',
                            'VIP：阅读权限 60，隐身 ✔，允许 @ 40 人，签名 1000 字节，每天附件 100 MB',
                            'QQ游客 / 游客：阅读权限 1，支持基础全站浏览',
                            '封禁用户组：禁止发言（只读）、禁止访问（封禁）、禁止 IP（全局封锁）',
                          ]),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComparisonItemRow(
    UsergroupPermissionItem item,
    bool isEven,
    ThemeData theme,
  ) {
    if (item.isCategoryHeader) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        child: Text(
          item.title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isEven
            ? theme.colorScheme.surfaceContainerLowest
            : theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(40),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              item.title,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: _buildPermissionValue(item.myValue, item.isMyBool, item.isMyAllowed, theme),
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: _buildPermissionValue(item.nextValue, item.isNextBool, item.isNextAllowed, theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionValue(
    String val,
    bool isBool,
    bool isAllowed,
    ThemeData theme,
  ) {
    if (val == '✔' || val == 'true') {
      return const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 18);
    }
    if (val == '✖' || val == 'false') {
      return const Icon(Icons.cancel_rounded, color: Color(0xFFC62828), size: 18);
    }
    return Text(
      val,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: isAllowed ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildMatrixGroup(String groupName, List<String> rules) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              groupName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
              ),
            ),
            const SizedBox(height: 6),
            for (final r in rules)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 12.5))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMoreActions(UserSpace user) {
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
              leading: const Icon(Icons.qr_code),
              title: const Text('空间二维码'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showQrCodeDialog(user);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制空间链接'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: 'https://klpbbs.com/?${user.uid}'));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制个人空间链接')),
                );
              },
            ),
            if (_isMe)
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('资料设置'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ProfileSettingsPage(uid: widget.uid)),
                  ).then((_) => _loadData());
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<UserSpace?>(
      initialData: widget.initialUser,
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done && snap.data == null) {
          return Scaffold(
            appBar: AppBar(title: Text(_isMe ? '我的空间' : 'Ta 的空间')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) {
          return Scaffold(
            appBar: AppBar(title: Text(_isMe ? '我的空间' : 'Ta 的空间')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 12),
                  const Text('用户信息加载失败', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _loadData, child: const Text('重新加载')),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    // 1. 顶部 Minecraft 森林沉浸式 Hero 顶栏
                    SliverAppBar(
                      expandedHeight: 220,
                      pinned: true,
                      foregroundColor: Colors.white,
                      backgroundColor: theme.colorScheme.primary,
                      title: Text(
                        _isMe ? '我的空间' : 'Ta 的空间',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.more_horiz),
                          tooltip: '更多',
                          onPressed: () => _showMoreActions(user),
                        ),
                        const GlobalNavButton(),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        background: _buildHeroHeader(user, theme),
                      ),
                    ),

              // 2. Tab 切换栏 (资料 / 帖子)
              SliverToBoxAdapter(
                child: Container(
                  color: theme.colorScheme.surface,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildTabItem(0, '资料', theme),
                            _buildTabItem(1, '帖子 (${user.stats['主题'] ?? user.stats['帖子'] ?? '0'})', theme),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Tab 内容区 (100% 居中无塌陷渲染)
              if (_selectedTab == 0)
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. 用户组卡片 (图二: Lv.4 高级会员  看看我能做什么 >)
                            _buildUsergroupCard(user, theme),
                            const SizedBox(height: 10),

                            // 2. 勋章荣誉卡片
                            _buildMedalCard(user, theme),
                            const SizedBox(height: 10),

                            // 3. 个人签名与头衔卡片
                            _buildSignatureCard(user, theme),
                            const SizedBox(height: 10),

                            // 4. 4 大统计徽章 (🟢 帖子, 🟠 回复, 🔵 好友, 🟡 人气)
                            _buildStatsCard(user, theme),
                            const SizedBox(height: 10),

                            // 5. 积分资产明细表格 (图二双列表格，自动消重单位)
                            _buildCreditsCard(user, theme),
                            const SizedBox(height: 10),

                            // 6. 基本资料
                            _buildBasicInfoCard(user, theme),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: SizedBox(
                        height: 600,
                        child: UserThreadsPage(
                          uid: widget.uid,
                          type: 'thread',
                          title: '${user.username} 的主题',
                          showAppBar: false,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
                _buildBottomActions(context, user),
            ],
          ),
        );
},
);
  }

  Widget _buildTabItem(int index, String title, ThemeData theme) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader(UserSpace user, ThemeData theme) {
    // 空间壁纸：优先 user.bgUrl，其次 AppConfig.spaceWallpaper，默认 klpbbs 官方风景空间壁纸
    final defaultBg = 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/1.png';
    final wallpaperUrl = user.bgUrl.isNotEmpty
        ? user.bgUrl
        : (_isMe ? (AppConfig.spaceWallpaper ?? defaultBg) : defaultBg);
    final hasWallpaper = wallpaperUrl.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 空间壁纸或深色纯色背景
        CachedNetworkImage(
          imageUrl: wallpaperUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: const Color(0xFF1B3828)),
          errorWidget: (_, __, ___) => Container(color: const Color(0xFF1B3828)),
        ),
        // 半透明微暗遮罩（确保文字在任何壁纸下均清晰可见）
        Container(
          color: Colors.black.withAlpha(hasWallpaper ? 110 : 40),
        ),
        // 用户信息卡 (居中响应式)
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(80),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: UserAvatarWidget(
                      uid: user.uid,
                      author: user.username,
                      size: 64,
                      faceUrl: user.faceUrl.isNotEmpty ? user.faceUrl : null,
                      isOnline: user.isOnline,
                      showOnlineBadge: true,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
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
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Builder(
                              builder: (context) {
                                final isOnline = _isMe || user.isOnline;
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isOnline
                                        ? const Color(0xFF4CAF50).withAlpha(220)
                                        : Colors.black.withAlpha(120),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isOnline ? const Color(0xFF81C784) : Colors.white24,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.only(right: 4),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isOnline ? Colors.white : Colors.white54,
                                        ),
                                      ),
                                      Text(
                                        isOnline ? '在线' : '离线',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${user.stats['人气'] ?? '0'} 人气 · ${user.credits.isNotEmpty ? user.credits : (user.creditsDetail['积分'] ?? '0')} 积分',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            shadows: [Shadow(color: Colors.black38, blurRadius: 3)],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (user.gameProfile['性别'] != null && user.gameProfile['性别']!.isNotEmpty)
                              _buildSmallBadge(
                                user.gameProfile['性别'] == '女' ? '♀ 女' : '♂ 男',
                                const Color(0xFF1976D2),
                              ),
                            _buildSmallBadge(
                              _formatUserLevel(user),
                              theme.colorScheme.secondary,
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
        ),
      ],
    );
  }

  String _formatUserLevel(UserSpace user) {
    final lvlName = user.levelName.trim();
    final lvl = user.level.trim();
    if (lvlName.isEmpty && lvl.isEmpty) return '注册会员';
    if (lvlName.isEmpty) return lvl;
    if (lvl.isEmpty) return lvlName;
    if (lvlName.toLowerCase().startsWith(lvl.toLowerCase()) || lvlName.contains(lvl)) {
      return lvlName;
    }
    if (RegExp(r'^Lv\.\d+', caseSensitive: false).hasMatch(lvlName)) {
      return lvlName;
    }
    return '$lvl $lvlName';
  }

  Widget _buildSmallBadge(String text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildUsergroupCard(UserSpace user, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Text('用户组', style: TextStyle(fontSize: 13.5, color: theme.colorScheme.outline)),
            const SizedBox(width: 14),
            _buildSmallBadge(
              _formatUserLevel(user),
              theme.colorScheme.secondary,
            ),
            const Spacer(),
            InkWell(
              onTap: () => _showUsergroupPrivilegesDialog(user),
              child: const Row(
                children: [
                  Text('看看我能做什么', style: TextStyle(fontSize: 12.5, color: Color(0xFFF57C00))),
                  Icon(Icons.chevron_right, size: 16, color: Color(0xFFF57C00)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedalCard(UserSpace user, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('勋章荣誉', style: TextStyle(fontSize: 13.5, color: theme.colorScheme.outline)),
                const Spacer(),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MedalPage()),
                  ),
                  child: Row(
                    children: [
                      Text('勋章中心', style: TextStyle(fontSize: 12.5, color: theme.colorScheme.outline)),
                      Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.outline),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: user.medals.isNotEmpty
                  ? ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: user.medals.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final m = user.medals[i];
                        return Tooltip(
                          message: '${m.name}\n${m.desc}',
                          child: CachedNetworkImage(
                            imageUrl: m.img,
                            httpHeaders: AppConfig.imageHeaders,
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.amber.withAlpha(30),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.military_tech, size: 20, color: Colors.amber),
                            ),
                          ),
                        );
                      },
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Text('暂无佩戴勋章', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureCard(UserSpace user, ThemeData theme) {
    final sigRaw = user.signature.isNotEmpty
        ? user.signature
        : (user.gameProfile['个人签名'] ?? '暂未设置个性签名');
    final sigHtml = ComiisParser.bbcodeToHtml(sigRaw);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_rounded, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '个人签名',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InlineHtmlText(
                html: sigHtml,
                baseStyle: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (user.gameProfile['自定义头衔'] != null && user.gameProfile['自定义头衔']!.isNotEmpty) ...[
              Divider(height: 16, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildInfoRow('自定义头衔', user.gameProfile['自定义头衔']!, theme),
            ],
            Divider(height: 16, color: theme.colorScheme.outlineVariant.withAlpha(40)),
            InkWell(
              onTap: () => _showQrCodeDialog(user),
              child: Row(
                children: [
                  Text('二维码', style: TextStyle(fontSize: 13.5, color: theme.colorScheme.outline)),
                  const Spacer(),
                  Icon(Icons.qr_code, size: 18, color: theme.colorScheme.outline),
                  Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(UserSpace user, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            _buildClickableStat(
              '帖子',
              user.stats['主题'] ?? user.stats['帖子'] ?? '0',
              Icons.chat_bubble_outline_rounded,
              const Color(0xFF4CAF50),
              () => setState(() => _selectedTab = 1),
            ),
            _buildClickableStat(
              '回复',
              user.stats['回复'] ?? user.stats['回帖'] ?? '0',
              Icons.reply_rounded,
              const Color(0xFFFF9800),
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserThreadsPage(uid: user.uid, type: 'reply', title: '${user.username} 的回复'),
                ),
              ),
            ),
            _buildClickableStat(
              '好友',
              user.stats['好友'] ?? '0',
              Icons.people_outline_rounded,
              const Color(0xFF2196F3),
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FriendPage(
                    uid: user.uid,
                    username: user.username,
                  ),
                ),
              ),
            ),
            _buildClickableStat(
              '人气',
              user.stats['人气'] ?? '0',
              Icons.local_fire_department_outlined,
              const Color(0xFFE91E63),
              null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditsCard(UserSpace user, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Table(
              border: TableBorder.all(color: theme.colorScheme.outlineVariant.withAlpha(40), width: 0.8),
              children: [
                TableRow(
                  children: [
                    _buildAssetCell('积分', _cleanUnit(user.credits.isNotEmpty ? user.credits : user.creditsDetail['积分'], '0', ''), theme),
                    _buildAssetCell('经验', _cleanUnit(user.creditsDetail['经验'], '0', 'EP'), theme),
                  ],
                ),
                TableRow(
                  children: [
                    _buildAssetCell('铁粒', _cleanUnit(user.creditsDetail['铁粒'], '0', '粒'), theme),
                    _buildAssetCell('铁锭[已弃用]', _cleanUnit(user.creditsDetail['铁锭'], '0', '块'), theme),
                  ],
                ),
                TableRow(
                  children: [
                    _buildAssetCell('贡献', _cleanUnit(user.creditsDetail['贡献'], '0', '点'), theme),
                    _buildAssetCell('钻石', _cleanUnit(user.creditsDetail['钻石'], '0', '个'), theme),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 2)),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 15),
                    label: const Text('积分记录', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 1)),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                    label: const Text('积分转账', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MagicPage()),
                    ),
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 15),
                    label: const Text('道具中心', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoCard(UserSpace user, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildFieldRow('用户ID', '${user.uid}', theme),
            if (user.gameProfile.containsKey('生日')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('生日', user.gameProfile['生日']!, theme),
            ],
            if (user.gameProfile.containsKey('基岩版用户名')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('基岩版用户名', user.gameProfile['基岩版用户名']!, theme),
            ],
            if (user.gameProfile.containsKey('网易用户名') || user.gameProfile.containsKey('网易版用户名')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('网易用户名', (user.gameProfile['网易用户名'] ?? user.gameProfile['网易版用户名'])!, theme),
            ],
            if (user.gameProfile.containsKey('QQ')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('QQ', user.gameProfile['QQ']!, theme),
            ],
            if (user.gameProfile.containsKey('代表作')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('代表作', user.gameProfile['代表作']!, theme),
            ],
            if (user.gameProfile.containsKey('性别')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('性别', user.gameProfile['性别']!, theme),
            ],
            if (user.gameProfile.containsKey('在线时间')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('在线时间', user.gameProfile['在线时间']!, theme),
            ],
            if (user.regdate.isNotEmpty || user.gameProfile.containsKey('注册时间')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('注册时间', user.regdate.isNotEmpty ? user.regdate : user.gameProfile['注册时间']!, theme),
            ],
            if (user.lastvisit.isNotEmpty || user.gameProfile.containsKey('最后访问')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('最后访问', user.lastvisit.isNotEmpty ? user.lastvisit : user.gameProfile['最后访问']!, theme),
            ],
            if (user.gameProfile.containsKey('上次活动时间')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('上次活动时间', user.gameProfile['上次活动时间']!, theme),
            ],
            if (user.gameProfile.containsKey('上次发表时间')) ...[
              Divider(height: 12, color: theme.colorScheme.outlineVariant.withAlpha(40)),
              _buildFieldRow('上次发表时间', user.gameProfile['上次发表时间']!, theme),
            ],
          ],
        ),
      ),
    );
  }

  String _cleanUnit(String? raw, String fallback, String unit) {
    if (raw == null || raw.isEmpty) return unit.isEmpty ? fallback : '$fallback $unit';
    final trimmed = raw.trim();
    if (unit.isEmpty) return trimmed;
    if (trimmed.endsWith(unit) ||
        trimmed.endsWith('EP') ||
        trimmed.endsWith('粒') ||
        trimmed.endsWith('块') ||
        trimmed.endsWith('点') ||
        trimmed.endsWith('个')) {
      return trimmed;
    }
    return '$trimmed $unit';
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 13.5, color: theme.colorScheme.outline))),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(fontSize: 13.5, color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  Widget _buildClickableStat(String label, String count, IconData icon, Color color, VoidCallback? onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withAlpha(30),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              '$label $count',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetCell(String label, String val, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
          const Spacer(),
          Text(
            val,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, String val, ThemeData theme) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: TextStyle(fontSize: 13, color: theme.colorScheme.outline)),
        ),
        Expanded(
          child: SelectableText(
            val,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  /// 底部固定操作栏 (图二: [✎ 更新资料] [⚙ 装扮空间])
  Widget _buildBottomActions(BuildContext context, UserSpace user) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: _isMe
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: const Text('更新资料'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ProfileSettingsPage(uid: widget.uid)),
                            ).then((_) => _loadData());
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.auto_awesome_outlined, size: 17),
                          label: const Text('装扮空间'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => HomeStylePage(
                                  uid: widget.uid,
                                  username: user.username,
                                ),
                              ),
                            ).then((_) => _loadData());
                          },
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.person_add_alt, size: 16),
                          label: const Text('加好友'),
                          onPressed: () async {
                            final noteCtrl = TextEditingController();
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('申请添加「${user.username}」为好友'),
                                content: TextField(
                                  controller: noteCtrl,
                                  decoration: const InputDecoration(
                                    labelText: '附言（可选）',
                                    hintText: '例如：你好，我是...',
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLength: 50,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: const Text('发送申请'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !context.mounted) return;
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final ok = await KlpbbsApi.addFriend(
                                widget.uid,
                                noteCtrl.text.trim(),
                              );
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(ok ? '好友请求已发送' : '请求失败，请稍后重试'),
                                ),
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('发送异常：$e')),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.chat_bubble_outline, size: 16),
                          label: const Text('私信'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PmDetailPage(
                                touid: widget.uid,
                                toUsername: user.username,
                                isOnline: user.isOnline,
                                onlineStatusText: user.onlineStatusText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 快速打开当前登录用户的「我的空间」
class MySpacePage extends StatefulWidget {
  const MySpacePage({super.key});

  @override
  State<MySpacePage> createState() => _MySpacePageState();
}

class _MySpacePageState extends State<MySpacePage> {
  int? _uid;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final uid = await KlpbbsApi.getMyUid();
    if (mounted) {
      setState(() {
        _uid = uid;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_uid == null || _uid == 0) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('我的空间'),
          centerTitle: true,
          actions: const [GlobalNavButton()],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(100),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_pin_rounded, size: 52, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 18),
                const Text(
                  '未登录账号',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '登录苦力怕论坛账号，查看您的积分资产、勋章荣誉与空间装扮',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.outline, height: 1.4),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 240,
                  height: 44,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      ).then((_) => _checkLogin());
                    },
                    child: const Text(
                      '立即登录 / 注册',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return UserSpacePage(uid: _uid!, isMe: true);
  }
}
