import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/write_confirm.dart';
import '../models/credit_log.dart';
import '../widgets/empty_view.dart';
import '../widgets/global_nav.dart';
import '../widgets/pagination_control.dart';
import 'magic_page.dart';
import 'medal_page.dart';
import 'sign_rank_page.dart';

/// 论坛积分中心（我的积分 / 转账 / 积分记录流水）
/// 深度对齐 Discuz spacecp credit (图二: home.php?mod=spacecp&ac=credit&op=log&mobile=2)
class CreditPage extends StatefulWidget {
  final int initialTabIndex; // 0: 我的, 1: 转账, 2: 记录

  const CreditPage({super.key, this.initialTabIndex = 2});

  @override
  State<CreditPage> createState() => _CreditPageState();
}

class _CreditPageState extends State<CreditPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Tab 3: 积分记录
  int _logPage = 1;
  String _subop = ''; // 全部, income, reward, payment
  Future<List<CreditLogEntry>>? _logsFuture;

  // Tab 1: 我的积分
  Future<CreditBaseInfo?>? _baseFuture;
  int? _myIron;

  // Tab 2: 转账表单
  final _toUserCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  bool _transferring = false;

  @override
  void initState() {
    super.initState();
    final initialIdx = widget.initialTabIndex.clamp(0, 2);
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIdx,
    );
    _tabController.addListener(_onTabChanged);
    _loadTab(initialIdx);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _loadTab(_tabController.index);
  }

  void _loadTab(int index) {
    if (index == 0 && _baseFuture == null) {
      _reloadBase();
    } else if (index == 1 && _baseFuture == null) {
      _reloadBase();
    } else if (index == 2 && _logsFuture == null) {
      _reloadLogs();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _toUserCtrl.dispose();
    _amountCtrl.dispose();
    _pwdCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  void _reloadLogs() {
    setState(() {
      _logsFuture = KlpbbsApi.getCreditLogs(page: _logPage, subop: _subop);
    });
  }

  void _reloadBase() {
    setState(() {
      _baseFuture = KlpbbsApi.getCreditBase().then((info) {
        if (info != null && info.details.containsKey('铁粒')) {
          final ironVal = int.tryParse(info.details['铁粒']!);
          if (ironVal != null && mounted) {
            setState(() => _myIron = ironVal);
          }
        }
        return info;
      });
    });
  }

  Future<void> _submitTransfer() async {
    final toUser = _toUserCtrl.text.trim();
    final amountStr = _amountCtrl.text.trim();
    final pwd = _pwdCtrl.text.trim();
    final memo = _memoCtrl.text.trim();

    if (toUser.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入接收人用户名')));
      return;
    }
    final amount = int.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入有效的转账数量')));
      return;
    }
    if (pwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入论坛登录支付密码')));
      return;
    }

    final confirmed = await confirmWrite(
      context,
      '转账确认：向「$toUser」转账 $amount 铁粒\n此操作不可撤销，请核对用户名！',
    );
    if (!confirmed || !mounted) return;

    setState(() => _transferring = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await KlpbbsApi.transferCredits(
        toUser: toUser,
        amount: amount,
        password: pwd,
        memo: memo,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.message),
          backgroundColor: res.success ? Colors.green.shade700 : Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (res.success) {
        _amountCtrl.clear();
        _pwdCtrl.clear();
        _memoCtrl.clear();
        _reloadBase();
        _reloadLogs();
      }
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('积分', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              _reloadLogs();
              _reloadBase();
            },
          ),
          const GlobalNavButton(),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.outline,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          tabs: const [
            Tab(text: '我的'),
            Tab(text: '转账'),
            Tab(text: '记录'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMyCreditsTab(),
              _buildTransferTab(),
              _buildLogsTab(),
            ],
          ),
        ),
      ),
    );
  }

  /// Tab 3: 积分记录（深度复刻图二）
  Widget _buildLogsTab() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // 子分类栏：全部 / 积分收益 / 系统奖励 / 积分支出
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _subop = '';
                      _logPage = 1;
                    });
                    _reloadLogs();
                  },
                  child: Text(
                    '全部',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _subop.isEmpty ? FontWeight.bold : FontWeight.normal,
                      color: _subop.isEmpty ? colorScheme.primary : colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('/', style: TextStyle(color: colorScheme.outlineVariant)),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    setState(() {
                      _subop = 'income';
                      _logPage = 1;
                    });
                    _reloadLogs();
                  },
                  child: Text(
                    '积分收益',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _subop == 'income' ? FontWeight.bold : FontWeight.normal,
                      color: _subop == 'income' ? colorScheme.primary : colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('/', style: TextStyle(color: colorScheme.outlineVariant)),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    setState(() {
                      _subop = 'reward';
                      _logPage = 1;
                    });
                    _reloadLogs();
                  },
                  child: Text(
                    '系统奖励',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _subop == 'reward' ? FontWeight.bold : FontWeight.normal,
                      color: _subop == 'reward' ? colorScheme.primary : colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('/', style: TextStyle(color: colorScheme.outlineVariant)),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    setState(() {
                      _subop = 'payment';
                      _logPage = 1;
                    });
                    _reloadLogs();
                  },
                  child: Text(
                    '积分支出',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _subop == 'payment' ? FontWeight.bold : FontWeight.normal,
                      color: _subop == 'payment' ? colorScheme.primary : colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // 记录流水列表
        Expanded(
          child: FutureBuilder<List<CreditLogEntry>>(
            future: _logsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () async => _reloadLogs(),
                  child: ListView(
                    children: [
                      const SizedBox(height: 80),
                      const EmptyView(
                        icon: Icons.receipt_long_outlined,
                        title: '暂无积分变动记录',
                        subtitle: '日常签到、发帖、回帖或购买勋章的积分变动将在此显示',
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async => _reloadLogs(),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withAlpha(40),
                  ),
                  itemBuilder: (ctx, i) {
                    if (i == list.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: PaginationControl(
                          page: _logPage,
                          hasMore: list.length >= 10,
                          onPageChanged: (page) {
                            setState(() => _logPage = page);
                            _reloadLogs();
                          },
                        ),
                      );
                    }

                    final item = list[i];
                    final isPos = item.isPositive;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左侧：蓝底方块（图二像素级对齐）
                          Container(
                            width: 52,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isPos ? const Color(0xFF42A5F5) : const Color(0xFF5C9CE6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item.creditType,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  item.amount,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 中间：操作与详情
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.operation,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      item.timeText,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                  ],
                                ),
                                if (item.detail.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    item.detail,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.outline,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Tab 2: 积分转账
  Widget _buildTransferTab() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当前可用余额卡片
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer,
                  colorScheme.primaryContainer.withAlpha(160),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, size: 32, color: colorScheme.primary),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前账户可用余额',
                      style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer.withAlpha(200)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _myIron != null ? '$_myIron 铁粒' : '加载中...',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 转账表单
          Text('转账信息', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // 接收人用户名
          TextField(
            controller: _toUserCtrl,
            decoration: InputDecoration(
              labelText: '转账接收人用户名',
              hintText: '输入对方的论坛用户名',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 14),

          // 转账铁粒数量
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '转账数量 (铁粒)',
              hintText: '输入要转出的铁粒数量',
              prefixIcon: const Icon(Icons.monetization_on_outlined),
              suffixText: '粒',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 14),

          // 登录密码
          TextField(
            controller: _pwdCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: '论坛登录密码',
              hintText: '输入当前账号密码以验证安全身份',
              prefixIcon: const Icon(Icons.lock_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 14),

          // 附言留言
          TextField(
            controller: _memoCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: '转账附言 (选填)',
              hintText: '写给对方的留言说明',
              prefixIcon: const Icon(Icons.comment_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 12),

          // 转账规则与手续费说明（1:1 对齐官方网页）
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200, width: 0.8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '转账后最低余额 50 粒, 积分交易税 3.00%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '转账操作即时生效，积分将直接转入对方账户；请仔细核对对方用户名，切勿输入错误。',
                        style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 确认转账按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _transferring ? null : _submitTransfer,
              icon: _transferring
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(_transferring ? '正在提交转账...' : '确认转账', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  /// Tab 1: 我的积分概况
  Widget _buildMyCreditsTab() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<CreditBaseInfo?>(
      future: _baseFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final info = snap.data;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 总积分卡片
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withAlpha(200),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withAlpha(50),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('我的论坛总积分', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text(
                    info?.totalCredits.isNotEmpty == true
                        ? info!.totalCredits
                        : (_myIron != null ? '$_myIron' : '0'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 快捷功能入口（每日签到、勋章中心、道具中心）
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SignRankPage()),
                    ),
                    icon: const Icon(Icons.event_available, size: 16),
                    label: const Text('每日签到', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MedalPage()),
                    ),
                    icon: const Icon(Icons.military_tech, size: 16),
                    label: const Text('勋章中心', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MagicPage()),
                    ),
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                    label: const Text('道具中心', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 资产明细（1:1 对齐苦力怕论坛真实积分项：铁粒、经验、铁锭[已弃用]、贡献、钻石）
            Text('积分资产明细', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    _buildCreditRow(
                      '铁粒 (extcredits2)',
                      info?.details['铁粒'] != null
                          ? '${info!.details['铁粒']} 粒'
                          : (_myIron != null ? '$_myIron 粒' : '0 粒'),
                      Icons.monetization_on_outlined,
                      Colors.amber.shade800,
                    ),
                    const Divider(height: 1),
                    _buildCreditRow(
                      '经验 (extcredits1)',
                      info?.details['经验'] != null
                          ? '${info!.details['经验']} EP'
                          : (info?.totalCredits.isNotEmpty == true ? '${info!.totalCredits} EP' : '0 EP'),
                      Icons.star_border,
                      Colors.blue.shade700,
                    ),
                    const Divider(height: 1),
                    _buildCreditRow(
                      '铁锭[已弃用] (extcredits3)',
                      '${info?.details['铁锭[已弃用]'] ?? info?.details['铁锭'] ?? '0'} 块',
                      Icons.square_outlined,
                      Colors.grey.shade600,
                    ),
                    const Divider(height: 1),
                    _buildCreditRow(
                      '贡献 (extcredits4)',
                      '${info?.details['贡献'] ?? '0'} 点',
                      Icons.volunteer_activism_outlined,
                      Colors.teal,
                    ),
                    const Divider(height: 1),
                    _buildCreditRow(
                      '钻石 (extcredits8)',
                      '${info?.details['钻石'] ?? '0'} 个',
                      Icons.diamond_outlined,
                      Colors.lightBlueAccent.shade700,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 积分计算公式
            if (info?.ruleFormula != null && info!.ruleFormula!.isNotEmpty) ...[
              Text('积分计算规则', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  info.ruleFormula!,
                  style: TextStyle(fontSize: 12, color: colorScheme.outline, height: 1.4),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCreditRow(String name, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(name, style: const TextStyle(fontSize: 13.5)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
