import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../models/user_space.dart';
import '../widgets/app_back_button.dart';
import '../widgets/global_nav.dart';

/// 认证项目模型
class _VerifyItem {
  final String title;
  final String tag;
  final IconData icon;
  final Color color;
  final String desc;
  final List<String> benefits;
  final bool isVerified;
  final String verifyStatusText;

  const _VerifyItem({
    required this.title,
    required this.tag,
    required this.icon,
    required this.color,
    required this.desc,
    required this.benefits,
    required this.isVerified,
    required this.verifyStatusText,
  });
}

/// 苦力怕论坛认证信息中心
class VerifyInfoPage extends StatefulWidget {
  final UserSpace? userSpace;
  const VerifyInfoPage({super.key, this.userSpace});

  @override
  State<VerifyInfoPage> createState() => _VerifyInfoPageState();
}

class _VerifyInfoPageState extends State<VerifyInfoPage> {
  UserSpace? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _user = widget.userSpace;
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = await KlpbbsApi.getMyUid();
    if (uid != null) {
      final u = await KlpbbsApi.getUserSpace(uid);
      if (mounted) {
        setState(() {
          _user = u ?? _user;
          _loading = false;
        });
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_VerifyItem> _buildVerifyItems() {
    final group = _user?.group.toLowerCase() ?? '';
    final levelName = _user?.levelName ?? '';
    final username = _user?.username ?? '';

    final isDev = group.contains('开发者') ||
        group.contains('dev') ||
        levelName.contains('开发者') ||
        (_user?.medals.any((m) => m.name.contains('开发') || m.name.contains('模组')) ?? false);

    final isCreator = group.contains('创作者') ||
        group.contains('up') ||
        levelName.contains('创作者') ||
        (_user?.medals.any((m) => m.name.contains('创作者') || m.name.contains('优秀')) ?? false);

    final isRealname = _user != null && username.isNotEmpty;

    return [
      _VerifyItem(
        title: '认证开发者',
        tag: 'Developer',
        icon: Icons.code_rounded,
        color: const Color(0xFF10B981),
        desc: '面向在苦力怕论坛发布 Minecraft 模组、插件、材质包、地图等原创资源的开发者。',
        benefits: [
          '专属「开发者」认证大字与认证标识',
          '资源中心发布资源极速审核与免审通道',
          '开发者专属技术交流板块权限',
          '作品首页置顶推荐与精选收录加权',
        ],
        isVerified: isDev,
        verifyStatusText: isDev ? '已认证' : '未认证',
      ),
      _VerifyItem(
        title: '优质创作者',
        tag: 'Creator',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFFF59E0B),
        desc: '面向在社区持续输出高质量技术教程、建筑展示、视频图文的原创作者。',
        benefits: [
          '专属创作者标识与身份卡片展示',
          '原创精华作品双倍金粒 / 绿宝石奖励',
          '社区官方活动特邀评委与优先体验权',
          '专属创作者社群与官方运营对接',
        ],
        isVerified: isCreator,
        verifyStatusText: isCreator ? '已认证' : '未认证',
      ),
      _VerifyItem(
        title: '实名认证',
        tag: 'Real-name',
        icon: Icons.verified_user_rounded,
        color: const Color(0xFF3B82F6),
        desc: '依据国家互联网信息安全规范完成实名登记，全面提升账号安全与信誉等级。',
        benefits: [
          '最高级别账号安全保障，防盗防封快速找回',
          '解锁论坛所有高阶互动与交易功能',
          '提升账号信誉评级，防范冒充风险',
        ],
        isVerified: isRealname,
        verifyStatusText: isRealname ? '已完成实名登记' : '未认证',
      ),
    ];
  }

  void _showApplyDialog(_VerifyItem item) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(item.icon, color: item.color, size: 22),
            const SizedBox(width: 8),
            Text('申请${item.title}'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请填写您的申请理由与作品/证明链接（例如您在论坛发布的优质作品、模组发布帖地址等）：',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '输入申请理由、代表作品链接...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await KlpbbsApi.submitProfileForm(
                  op: 'verify',
                  formData: {
                    'verifysubmit': 'true',
                    'verifytype': item.tag,
                    'reason': controller.text.trim(),
                  },
                );
              } catch (_) {}
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('认证申请已提交至审核后台，管理员将在 1-3 个工作日内处理！'),
                    backgroundColor: Color(0xFF10B981),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('提交申请'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = _buildVerifyItems();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('认证信息', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        leading: const AppBackButton(),
        actions: const [GlobalNavButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    // 1. 官方网页一致的黄色审核提示条
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFD97706), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '以下信息通过审核后将不能再次修改，提交后请耐心等待核查',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF92400E),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. 当前账号与认证总览卡片
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primaryContainer.withAlpha(160),
                            colorScheme.primaryContainer.withAlpha(60),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.primary.withAlpha(40)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withAlpha(30),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.verified_rounded, color: colorScheme.primary, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '苦力怕论坛官方认证体系',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15.5,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    if ((_user?.username ?? '').isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary.withAlpha(20),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '用户名: ${_user!.username}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '获取专属认证标识、作品免审发布与丰厚创作者权益。',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 各项认证卡片
                    for (final item in items) ...[
                      _buildVerifyCard(item),
                      const SizedBox(height: 14),
                    ],

                    const SizedBox(height: 10),
                    // 认证须知说明
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withAlpha(40)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 16, color: colorScheme.outline),
                              const SizedBox(width: 6),
                              Text(
                                '认证说明',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '1. 认证申请通过后，专属标识将自动展示在您的个人空间、发帖头像与评论区；\n'
                            '2. 认证身份严禁转借、租售，如有违规行为将被取消认证资格；\n'
                            '3. 如有任何疑问，可前往社区「事务求助」版块联系管理团队。',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.outline,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildVerifyCard(_VerifyItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: item.isVerified
              ? item.color.withAlpha(120)
              : colorScheme.outlineVariant.withAlpha(50),
          width: item.isVerified ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：图标 + 标题 + 状态
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: item.color.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: item.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: item.color.withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.tag,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: item.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.desc,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.isVerified
                        ? item.color.withAlpha(30)
                        : colorScheme.outlineVariant.withAlpha(60),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.isVerified ? Icons.check_circle_rounded : Icons.pending_outlined,
                        size: 14,
                        color: item.isVerified ? item.color : colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.verifyStatusText,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: item.isVerified ? item.color : colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(40)),
            const SizedBox(height: 12),

            // 认证权益列表
            Text(
              '认证专属权益：',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            for (final benefit in item.benefits) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.star_rounded, size: 14, color: item.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        benefit,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),

            // 底部操作按钮
            Align(
              alignment: Alignment.centerRight,
              child: item.isVerified
                  ? OutlinedButton.icon(
                      icon: Icon(Icons.check_rounded, size: 16, color: item.color),
                      label: Text('已获得该认证', style: TextStyle(color: item.color)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: item.color.withAlpha(80)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: null,
                    )
                  : FilledButton.icon(
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('申请此认证'),
                      style: FilledButton.styleFrom(
                        backgroundColor: item.color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _showApplyDialog(item),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
