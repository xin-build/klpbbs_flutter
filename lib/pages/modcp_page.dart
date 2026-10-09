import '../widgets/app_motion.dart';
import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/url_helper.dart';
import '../core/dio_client.dart';
import '../models/user_role.dart';
import 'func_list_page.dart';

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
  int _reportPage = 1;
  String? _reportError;
  DiscuzUserRole? _role;
  final Set<int> _resolvingReports = {};

  // 禁言/封号表单状态
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _banReasonCtrl =
      TextEditingController(text: '违规灌水/恶意言论');
  int _banType = 4; // 4: 禁言, 5: 封号
  int _banDays = 3; // 1, 3, 7, 14, 30, 0(永久)
  bool _submittingBan = false;
  int _banOperation = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadReports();
    DioClient.sessionChanges.addListener(_onSessionChanged);
    _loadRole();
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    _tabController.dispose();
    _usernameCtrl.dispose();
    _banReasonCtrl.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _role = null;
      _reports = [];
      _reportPage = 1;
      _reportError = null;
      _loadingReports = false;
      _resolvingReports.clear();
      _banOperation++;
      _submittingBan = false;
      _usernameCtrl.clear();
      _banReasonCtrl.text = '违规灌水/恶意言论';
      _banType = 4;
      _banDays = 3;
    });
    _loadRole();
    _loadReports();
  }

  Future<void> _loadRole() async {
    final session = DioClient.sessionKey;
    final role = await KlpbbsApi.getMyRole(fid: widget.initialFid);
    if (mounted && session == DioClient.sessionKey) {
      setState(() => _role = role);
    }
  }

  Future<void> _loadReports({bool forceRefresh = false}) async {
    if (_loadingReports) return;
    setState(() {
      _loadingReports = true;
      _reportError = null;
    });
    final session = DioClient.sessionKey;
    final page = _reportPage;
    try {
      final list = await KlpbbsApi.getModReports(
        fid: widget.initialFid,
        page: page,
        forceRefresh: forceRefresh,
        expectedSession: session,
      );
      if (mounted && session == DioClient.sessionKey) {
        setState(() {
          _reports = list;
          _loadingReports = false;
        });
      }
    } catch (error) {
      if (mounted && session == DioClient.sessionKey) {
        setState(() {
          _loadingReports = false;
          _reportError = '$error';
        });
      }
    }
  }

  Future<void> _resolveSingleReport(int reportId) async {
    if (_loadingReports) return;
    if (!_resolvingReports.add(reportId)) return;
    setState(() {});
    final session = DioClient.sessionKey;
    final page = _reportPage;
    try {
      final ok = await KlpbbsApi.resolveModReport(
          reportIds: [reportId],
          fid: widget.initialFid,
          page: page,
          expectedSession: session);
      if (!mounted || session != DioClient.sessionKey) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? '已处理该举报' : '处理失败，请查看论坛返回的权限或验证要求')));
      if (ok) await _loadReports(forceRefresh: true);
    } catch (error) {
      if (mounted && session == DioClient.sessionKey) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _resolvingReports.remove(reportId));
      }
    }
  }

  Future<void> _submitBanUser() async {
    if (_submittingBan) return;
    final usernameInput = _usernameCtrl.text;
    final reasonInput = _banReasonCtrl.text;
    final username = usernameInput.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入要处罚的目标用户名')),
      );
      return;
    }

    final reason = reasonInput.trim().isEmpty ? '违规处理' : reasonInput.trim();
    final banType = _banType;
    final banDays = _banDays;
    final actionLabel = banType == 4 ? '禁言' : '封号';
    final daysLabel = banDays == 0 ? '永久' : '$banDays 天';
    final session = DioClient.sessionKey;
    final operation = ++_banOperation;
    bool ownsOperation() =>
        mounted &&
        session == DioClient.sessionKey &&
        operation == _banOperation;
    // Lock the entire form before opening the confirmation route, including
    // repeated invocations in the frame before the disabled button rebuilds.
    setState(() => _submittingBan = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('modcp-ban-confirmation'),
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
              key: const ValueKey('modcp-ban-cancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('modcp-ban-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor:
                    banType == 5 ? Theme.of(ctx).colorScheme.error : null,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认提交'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !ownsOperation()) return;
      if (_usernameCtrl.text != usernameInput ||
          _banReasonCtrl.text != reasonInput ||
          _banType != banType ||
          _banDays != banDays) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('处罚表单已变化，请重新确认操作')),
        );
        return;
      }
      final res = await KlpbbsApi.banUserInModCp(
        username: username,
        banGroupId: banType,
        days: banDays,
        reason: reason,
        expectedSession: session,
      );
      if (!mounted || !ownsOperation()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                res.success ? '处理成功：${res.message}' : '失败：${res.message}')),
      );
      if (res.success) _usernameCtrl.clear();
    } catch (e) {
      if (mounted && ownsOperation()) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作异常：$e')));
      }
    } finally {
      if (ownsOperation()) setState(() => _submittingBan = false);
    }
  }

  void _changeReportPage(int delta) {
    if (_loadingReports || _resolvingReports.isNotEmpty) return;
    final page = _reportPage + delta;
    if (page < 1) return;
    setState(() => _reportPage = page);
    _loadReports();
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
          isScrollable: MediaQuery.sizeOf(context).width < 600,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          tabs: const [
            Tab(
                key: ValueKey('modcp-reports-tab'),
                icon: Icon(Icons.flag_outlined, size: 20),
                text: '举报处理'),
            Tab(
                key: ValueKey('modcp-ban-tab'),
                icon: Icon(Icons.gavel_outlined, size: 20),
                text: '违规禁言/封号'),
            Tab(
                icon: Icon(Icons.admin_panel_settings_outlined, size: 20),
                text: '后台与指引'),
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
      return const Center(child: AppLoadingIndicator());
    }
    if (_reportError != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_reportError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                    onPressed: () => _openManagement('管理中心验证', ''),
                    icon: const Icon(Icons.login),
                    label: const Text('打开论坛管理中心')),
                TextButton(
                    onPressed: () => _loadReports(forceRefresh: true),
                    child: const Text('验证后刷新')),
              ])));
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
              '可刷新列表查看最新待办',
              style:
                  TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            if (_reportPage > 1)
              TextButton(
                  key: const ValueKey('modcp-reports-previous-empty'),
                  onPressed: () => _changeReportPage(-1),
                  child: const Text('返回上一页')),
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
        itemCount: _reports.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _reports.length) {
            return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton(
                  key: const ValueKey('modcp-reports-previous'),
                  onPressed: _reportPage <= 1 || _resolvingReports.isNotEmpty
                      ? null
                      : () => _changeReportPage(-1),
                  child: const Text('上一页')),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('第 $_reportPage 页')),
              OutlinedButton(
                  key: const ValueKey('modcp-reports-next'),
                  onPressed: _resolvingReports.isNotEmpty
                      ? null
                      : () => _changeReportPage(1),
                  child: const Text('下一页')),
            ]);
          }
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
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
                      Text(
                        '举报人: @${r.uName}',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
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
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
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
                      ],
                      FilledButton.tonalIcon(
                        key: ValueKey('modcp-report-resolve-${r.id}'),
                        onPressed: _resolvingReports.contains(r.id)
                            ? null
                            : () => _resolveSingleReport(r.id),
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
              key: const ValueKey('modcp-ban-username'),
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
            LayoutBuilder(
                builder: (context, constraints) => SegmentedButton<int>(
                      key: const ValueKey('modcp-ban-type'),
                      direction: constraints.maxWidth < 430
                          ? Axis.vertical
                          : Axis.horizontal,
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
                      onSelectionChanged: _submittingBan
                          ? null
                          : (s) => setState(() => _banType = s.first),
                    )),
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
                  key: ValueKey('modcp-ban-days-${item.$1}'),
                  label: Text(item.$2),
                  selected: isSel,
                  onSelected: _submittingBan
                      ? null
                      : (_) => setState(() => _banDays = item.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 处罚理由
            TextField(
              key: const ValueKey('modcp-ban-reason'),
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
              key: const ValueKey('modcp-ban-submit'),
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
  Future<void> _openManagement(String title, String query) async {
    final fid = widget.initialFid;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FuncListPage(
            title: title,
            path:
                'forum.php?mod=modcp${query.isEmpty ? '' : '&$query'}${fid == null ? '' : '&fid=$fid'}&mobile=no')));
    if (mounted) _loadReports(forceRefresh: true);
  }

  Widget _buildAdminCpGuideTab(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
              onPressed: () =>
                  _openManagement('待审核主题', 'action=moderate&op=threads'),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('审核主题')),
          FilledButton.tonalIcon(
              onPressed: () =>
                  _openManagement('待审核回复', 'action=moderate&op=replies'),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('审核回复')),
          OutlinedButton.icon(
              onPressed: () => _openManagement('主题管理', 'action=thread'),
              icon: const Icon(Icons.forum_outlined),
              label: const Text('主题管理')),
          OutlinedButton.icon(
              onPressed: () => _openManagement('管理日志', 'action=log'),
              icon: const Icon(Icons.history),
              label: const Text('管理日志')),
          OutlinedButton.icon(
              onPressed: () => _openManagement('主题回收站', 'action=recyclebin'),
              icon: const Icon(Icons.restore_from_trash_outlined),
              label: const Text('回收站')),
          OutlinedButton.icon(
              onPressed: () => _openManagement('论坛公告', 'action=announcement'),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('公告')),
        ]),
        const SizedBox(height: 20),
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
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
          leading:
              const Icon(Icons.open_in_browser_rounded, color: Colors.blue),
          title: const Text('打开网页版前台管理中心 (ModCP)'),
          subtitle: const Text('forum.php?mod=modcp'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            _openManagement('前台管理中心', '');
          },
        ),
        const SizedBox(height: 12),
        if (_role?.isAdmin == true)
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
            ),
            leading:
                const Icon(Icons.security_rounded, color: Colors.deepPurple),
            title: const Text('系统管理后台'),
            subtitle: const Text('需管理员 adminid=1 并在网页端输入后台独立密码'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      const FuncListPage(title: '系统管理后台', path: 'admin.php')));
            },
          ),
      ],
    );
  }
}
