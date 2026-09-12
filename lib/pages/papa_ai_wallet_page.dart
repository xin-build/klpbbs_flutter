import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../models/papa_ai.dart';
import 'papa_ai_chat_page.dart';

/// 帕帕 AI 积分与火药钱包中心
/// 深度适配 Discuz 插件体系 (static/kai.css / template_wallet.htm)
class PapaAiWalletPage extends StatefulWidget {
  const PapaAiWalletPage({super.key});

  @override
  State<PapaAiWalletPage> createState() => _PapaAiWalletPageState();
}

class _PapaAiWalletPageState extends State<PapaAiWalletPage> {
  bool _loading = true;
  PapaWallet _wallet = const PapaWallet();
  PapaChatContext _chatContext = const PapaChatContext();
  int? _selectedSrcCredit;
  int _exchangeAmount = 1;
  final TextEditingController _amountCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        KlpbbsApi.getPapaWallet(),
        KlpbbsApi.fetchPapaChatContext(forceRefresh: true),
      ]);
      final wallet = results[0] as PapaWallet;
      final ctx = results[1] as PapaChatContext;

      if (mounted) {
        setState(() {
          _wallet = wallet;
          _chatContext = ctx;
          if (wallet.rates.isNotEmpty) {
            _selectedSrcCredit = wallet.rates.first.src;
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doExchange() async {
    if (_selectedSrcCredit == null || _exchangeAmount <= 0) return;
    final rate = _wallet.rates.firstWhere(
      (r) => r.src == _selectedSrcCredit,
      orElse: () => const PapaExchangeRate(src: 0, title: '', have: 0, rate: 10),
    );

    if (rate.have < _exchangeAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${rate.title}余额不足（当前拥有 ${rate.have}，需消耗 $_exchangeAmount）')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final res = await KlpbbsApi.exchangePapaGunpowder(
      srcCredit: _selectedSrcCredit!,
      amount: _exchangeAmount,
      formhash: _chatContext.formhash,
    );

    messenger.showSnackBar(
      SnackBar(content: Text(res.message)),
    );

    if (res.success) {
      _loadData();
    }
  }

  Future<void> _doClearMemory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除 AI 记忆'),
        content: const Text('清除记忆后，帕帕将遗忘与你的过往对话上下文偏好，确定要清除吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认清除')),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final res = await KlpbbsApi.clearPapaMemory(_chatContext.formhash);
    messenger.showSnackBar(SnackBar(content: Text(res.message)));
  }

  @override
  Widget build(BuildContext context) {
    final pal = PapaPalette.of(context);

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: pal.border)),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: pal.text2),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [pal.primary, pal.primaryStrong],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Text(
                '帕',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '我的积分',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: pal.heading),
            ),
            const SizedBox(width: 6),
            Text('· 帕帕 AI', style: TextStyle(fontSize: 12, color: pal.muted)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: 20, color: pal.text2),
            tooltip: '刷新钱包',
            onPressed: _loadData,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: pal.primaryStrong))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: pal.primaryStrong,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    children: [
                      // 顶部导航标签 (对话 / 我的积分)
                      Row(
                        children: [
                          InkWell(
                            onTap: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                              } else {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(builder: (_) => const PapaAiChatPage()),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(99),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: pal.surface2,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: pal.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_back_rounded, size: 14, color: pal.text2),
                                  const SizedBox(width: 4),
                                  Text('返回对话', style: TextStyle(fontSize: 13, color: pal.text2)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: pal.primarySoft,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '我的积分 (当前)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: pal.primaryText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // 1. 额度与火药统计卡片 (.kai-stats & .kai-stat-tile)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: pal.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: pal.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_wallet.freeLeft}',
                                    style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                      color: pal.heading,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '今日免费剩余 / ${_wallet.freeTotal}',
                                    style: TextStyle(fontSize: 12.5, color: pal.muted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: pal.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: pal.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_wallet.balance}',
                                    style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                      color: pal.primaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_wallet.creditTitle}余额',
                                    style: TextStyle(fontSize: 12.5, color: pal.muted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 2. 计费表 (.kai-prices)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: pal.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: pal.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '计费表',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: pal.heading),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildPriceTile('生成日报', '20 积分', pal),
                                _buildPriceTile('生成周报', '50 积分', pal),
                                _buildPriceTile('生成月报', '100 积分', pal),
                                _buildPriceTile('对话·每1000输入', '2 token', pal),
                                _buildPriceTile('对话·每1000输出', '6 token', pal),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3. 兑换火药 (.kai-exchange)
                      if (_wallet.exchangeOn && _wallet.rates.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: pal.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: pal.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '兑换 ${_wallet.creditTitle}',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: pal.heading),
                              ),
                              const SizedBox(height: 14),

                              // 用哪种积分
                              Text('用哪种积分', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.text2)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: pal.surface2,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(color: pal.border),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _selectedSrcCredit,
                                    dropdownColor: pal.surface,
                                    isExpanded: true,
                                    items: _wallet.rates.map((r) {
                                      return DropdownMenuItem<int>(
                                        value: r.src,
                                        child: Text(
                                          '${r.title} (有 ${r.have}) · 1 换 ${r.rate} ${_wallet.creditTitle}',
                                          style: TextStyle(fontSize: 13, color: pal.text),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (v) => setState(() => _selectedSrcCredit = v),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 兑换数量
                              Text('兑换数量', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.text2)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _amountCtrl,
                                keyboardType: TextInputType.number,
                                style: TextStyle(fontSize: 14, color: pal.text),
                                decoration: InputDecoration(
                                  hintText: '输入数量',
                                  isDense: true,
                                  filled: true,
                                  fillColor: pal.surface2,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(9),
                                    borderSide: BorderSide(color: pal.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(9),
                                    borderSide: BorderSide(color: pal.border),
                                  ),
                                ),
                                onChanged: (v) {
                                  final n = int.tryParse(v) ?? 1;
                                  setState(() => _exchangeAmount = n);
                                },
                              ),
                              const SizedBox(height: 12),

                              // 将得到
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('将得到', style: TextStyle(fontSize: 13, color: pal.muted)),
                                  Builder(builder: (_) {
                                    final r = _wallet.rates.firstWhere(
                                      (x) => x.src == _selectedSrcCredit,
                                      orElse: () => const PapaExchangeRate(src: 0, title: '', have: 0, rate: 10),
                                    );
                                    final totalGain = _exchangeAmount * r.rate;
                                    return Text(
                                      '$totalGain ${_wallet.creditTitle}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: pal.primaryText,
                                      ),
                                    );
                                  }),
                                ],
                              ),
                              const SizedBox(height: 14),

                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: pal.primaryStrong,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                                  ),
                                  onPressed: _doExchange,
                                  child: const Text('确认兑换', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 4. 清除记忆 (.kai-clear-memory)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: pal.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: pal.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '清除 AI 记忆',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: pal.heading),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '重置帕帕对个人对话上下文的长期记忆',
                                    style: TextStyle(fontSize: 12, color: pal.muted),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: pal.text2,
                                side: BorderSide(color: pal.border),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _doClearMemory,
                              child: const Text('清除记忆', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 5. 流水 (.kai-flow)
                      Text(
                        '流水记录',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: pal.heading),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: pal.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: pal.border),
                        ),
                        child: _wallet.logs.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        '还没有任何记录',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: pal.heading),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '去和帕帕聊两句、或者生成一份报告就有了。',
                                        style: TextStyle(fontSize: 12, color: pal.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _wallet.logs.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: pal.border),
                                itemBuilder: (context, i) {
                                  final log = _wallet.logs[i];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                log.name,
                                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: pal.heading),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(log.time, style: TextStyle(fontSize: 11.5, color: pal.muted)),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          log.amount,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5,
                                            color: log.isIncome ? pal.primaryText : pal.text2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
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

  Widget _buildPriceTile(String title, String price, PapaPalette pal) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: pal.surface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: pal.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: pal.text2)),
          const SizedBox(width: 8),
          Text(price, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: pal.heading)),
        ],
      ),
    );
  }
}
