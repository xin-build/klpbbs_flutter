import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/url_helper.dart';

/// Discuz! 前台管理中心 (ModCP) 页面
/// 专供管理员、超级版主及版主使用
/// 功能：处理违规举报列表、违规用户禁言/封禁、后台控制台快捷通道
class ModCpPage extends StatefulWidget {
  final int? initialFid;

  const ModCpPage({super.key, this.initialFid});

  @override
  State<ModCpPage> createState() => _ModCpPageState();
}

class _ModCpPageState extends State<ModCpPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 举报列表状态
  bool _loadingReports = false;
  List<({int id, String url, String message, String uName, String dateline})>
      _reports = [];
  final int _reportPage = 1;

  // 禁言/封号表单状态
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _banReasonCtrl =
      TextEditingController(text: '违规灌水/恶意言论');
  int _banType = 4; // 4: 禁言, 5: 封号
  int _banDays = 3; // 1, 3, 7, 14, 30, 0(永久)
  bool _submittingBan = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameCtrl.dispose();
    _banReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReports({bool forceRefresh = false}) async {
    if (_loadingReports) return;
    setState(() => _loadingReports = true);
    try {
      final list = await KlpbbsApi.getModReports(
        fid: widget.initialFid,
        page: _reportPage,
      );
      if (mounted) {
        setState(() {
          _reports = list;
          _loadingReports = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingReports = false);
    }
  }

  Future<void> _resolveSingleReport(int reportId) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await KlpbbsApi.resolveModReport(reportIds: [reportId]);
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('已标记并处理该举报')));
      _loadReports();
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('处理失败，可能无权限或已被处理')));
    }
  }

  Future<void> _submitBanUser() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入要处罚的目标用户名')),
      );
      return;
    }

    final reason = _banReasonCtrl.text.trim().isEmpty
        ? '违规处理'
        : _banReasonCtrl.text.trim();

    final actionLabel = _banType == 4 ? '禁言' : '封号';
    final daysLabel = _banDays == 0 ? '永久' : '$_banDays 天';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认执行用户$actionLabel？'),
        content: Text(
          '目标用户: @$username\n'
          '处罚类型: $actionLabel\n'
          '期限: $daysLabel\n'
          '处罚原因: $reason\n\n'
          '此操作将写入论坛管理日志并即刻生效。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  _banType == 5 ? Theme.of(ctx).colorScheme.error : null,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _submittingBan = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await KlpbbsApi.banUserInModCp(
        username: username,
        banGroupId: _banType,
        days: _banDays,
        reason: reason,
      );
      messenger.showSnackBar(
        SnackBar(
            content:
                Text(res.success ? '处理成功：${res.message}' : '失败：${res.message}')),
      );
      if (res.success && mounted) {
        _usernameCtrl.clear();
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('操作异常：$e')));
    } finally {
      if (mounted) setState(() => _submittingBan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('前台管理中心 (ModCP)'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          tabs: const [
            Tab(icon: Icon(Icons.flag_outlined, size: 20), text: '举报处理'),
            Tab(icon: Icon(Icons.gavel_outlined, size: 20), text: '违规禁言/封号'),
            Tab(icon: Icon(Icons.admin_panel_settings_outlined, size: 20), text: '后台与指引'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReportsTab(colorScheme),
          _buildBanUserTab(colorScheme),
          _buildAdminCpGuideTab(colorScheme),
        ],
      ),
    );
  }

  /// 举报处理 Tab
  Widget _buildReportsTab(ColorScheme colorScheme) {
    if (_loadingReports) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 64, color: colorScheme.primary.withAlpha(150)),
            const SizedBox(height: 16),
            const Text(
              '当前暂无待处理的违规举报',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '论坛风清气正，暂无违规待办',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => _loadReports(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新举报列表'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadReports(forceRefresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final r = _reports[index];
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '举报 #${r.id}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '举报人: @${r.uName}',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      if (r.dateline.isNotEmpty)
                        Text(
                          r.dateline,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '举报理由：${r.message}',
                    style: const TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (r.url.isNotEmpty) ...[
                        TextButton.icon(
                          onPressed: () {
                            final fullUrl = r.url.startsWith('http')
                                ? r.url
                                : '${AppConfig.baseUrl}${r.url}';
                            UrlHelper.openLink(context, fullUrl);
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text('查看被举报内容'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton.tonalIcon(
                        onPressed: () => _resolveSingleReport(r.id),
                        icon: const Icon(Icons.done_all_rounded, size: 16),
                        label: const Text('标记为已处理'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 违规禁言/封号 Tab
  Widget _buildBanUserTab(ColorScheme colorScheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '快速违规用户处置',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary),
            ),
            const SizedBox(height: 6),
            Text(
              '在 ModCP 中直接对违规灌水、发布广告或辱骂他人的账号执行限制。',
              style: TextStyle(
                  fontSize: 12.5, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            // 用户名输入
            TextField(
              controller: _usernameCtrl,
              enabled: !_submittingBan,
              decoration: const InputDecoration(
                labelText: '目标用户名',
                hintText: '输入要处罚的 Discuz 论坛用户名',
                prefixIcon: Icon(Icons.person_outline_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 处罚类型
            Text('处罚类型 (Usergroup)',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: colorScheme.primary)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 4,
                  label: Text('禁止发言 (禁言)'),
                  icon: Icon(Icons.speaker_notes_off_outlined),
                ),
                ButtonSegment(
                  value: 5,
                  label: Text('禁止访问 (封号)'),
                  icon: Icon(Icons.block_outlined),
                ),
              ],
              selected: {_banType},
              onSelectionChanged: (s) => setState(() => _banType = s.first),
            ),
            const SizedBox(height: 16),

            // 处罚时长
            Text('限制期限',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: colorScheme.primary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                (1, '1 天'),
                (3, '3 天'),
                (7, '7 天'),
                (14, '14 天'),
                (30, '30 天'),
                (0, '永久限制'),
              ].map((item) {
                final isSel = _banDays == item.$1;
                return ChoiceChip(
                  label: Text(item.$2),
                  selected: isSel,
                  onSelected: (_) => setState(() => _banDays = item.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 处罚理由
            TextField(
              controller: _banReasonCtrl,
              enabled: !_submittingBan,
              decoration: const InputDecoration(
                labelText: '操作原因 / 封禁理由',
                hintText: '违规事实记录，用户访问时将提示此原因',
                prefixIcon: Icon(Icons.description_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            // 提交按钮
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                    _banType == 5 ? colorScheme.error : colorScheme.primary,
                foregroundColor:
                    _banType == 5 ? colorScheme.onError : colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _submittingBan ? null : _submitBanUser,
              icon: Icon(_banType == 5
                  ? Icons.gavel_rounded
                  : Icons.speaker_notes_off_rounded),
              label: Text(_submittingBan
                  ? '提交处理中...'
                  : (_banType == 5 ? '执行用户封号' : '执行用户禁言')),
            ),
          ],
        ),
      ),
    );
  }

  /// 后台与指引 Tab
  Widget _buildAdminCpGuideTab(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          elevation: 0,
          color: colorScheme.secondaryContainer.withAlpha(60),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_rounded, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'Discuz! 管理体系说明',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '• 前台管理中心 (ModCP)：主要供版主、超级版主及管理员进行日常社区维护，包含主题置顶加精、楼层屏蔽删楼、违规举报跟进与用户禁言。\n'
                  '• 系统后台 (AdminCP)：仅限 AdminID=1 的最高管理员访问，包含版块设置、积分规则、插件管理、系统安全与数据库备份。\n'
                  '• 权限范围：普通版主仅在其管辖的版块内拥有操作权限，超级版主与管理员拥有全站所有版块的管理权限。',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
          ),
          leading: const Icon(Icons.open_in_browser_rounded, color: Colors.blue),
          title: const Text('打开网页版前台管理中心 (ModCP)'),
          subtitle: const Text('forum.php?mod=modcp'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            UrlHelper.openLink(context, '${AppConfig.baseUrl}forum.php?mod=modcp');
          },
        ),
        const SizedBox(height: 12),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
          ),
          leading: const Icon(Icons.security_rounded, color: Colors.deepPurple),
          title: const Text('打开 Discuz! 系统后台 (admin.php)'),
          subtitle: const Text('需管理员 adminid=1 并在网页端输入后台独立密码'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            UrlHelper.openLink(context, '${AppConfig.baseUrl}admin.php');
          },
        ),
      ],
    );
  }
}
