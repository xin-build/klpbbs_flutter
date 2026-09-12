import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/klpbbs_api.dart';
import '../core/url_helper.dart';
import '../models/papa_ai.dart';
import 'papa_ai_wallet_page.dart';
import 'thread_detail_page.dart';
import 'user_space_page.dart';

/// 苦力怕论坛 · 帕帕 AI 助手
/// 深度适配 Discuz 插件体系 (static/kai.css / kai.js)
class PapaAiChatPage extends StatefulWidget {
  final int? initialConvId;
  final String? initialReportType;
  const PapaAiChatPage({super.key, this.initialConvId, this.initialReportType});

  @override
  State<PapaAiChatPage> createState() => _PapaAiChatPageState();
}

class _PapaAiChatPageState extends State<PapaAiChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _composerFocusNode = FocusNode();

  bool _loading = true;
  bool _isStreaming = false;
  StreamSubscription? _chatSub;

  PapaChatContext _context = const PapaChatContext();
  List<PapaConversation> _conversations = [];
  int? _currentConvId;
  String _currentTitle = '帕帕 AI 助手';
  List<PapaMessage> _messages = [];

  // 报告视图状态
  String? _currentReportType; // 'day' | 'week' | 'month'
  PapaReport? _activeReport;
  List<PapaReport> _reportHistory = [];
  bool _generatingReport = false;
  StreamSubscription? _reportSub;

  // 版本偏好 ('auto', 'je', 'be')
  String _edition = 'je';

  @override
  void initState() {
    super.initState();
    _currentConvId = widget.initialConvId;
    _initData();
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _reportSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _loading = true);
    try {
      final ctx = await KlpbbsApi.fetchPapaChatContext(forceRefresh: true);
      final convs = await KlpbbsApi.getPapaConversations(apiUrl: ctx.apiUrl);

      if (mounted) {
        setState(() {
          _context = ctx;
          _conversations = convs;
          _loading = false;
        });

        if (widget.initialReportType != null &&
            ['day', 'week', 'month'].contains(widget.initialReportType)) {
          _selectReport(widget.initialReportType!);
        } else if (_currentConvId != null && _currentConvId! > 0) {
          _switchConversation(_currentConvId!);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startNewChat() {
    _chatSub?.cancel();
    _reportSub?.cancel();
    setState(() {
      _currentConvId = null;
      _currentReportType = null;
      _currentTitle = '帕帕 AI 助手';
      _messages = [];
      _isStreaming = false;
      _generatingReport = false;
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _switchConversation(int convId) async {
    _chatSub?.cancel();
    _reportSub?.cancel();
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    setState(() {
      _currentConvId = convId;
      _currentReportType = null;
      _isStreaming = false;
      _generatingReport = false;
    });

    try {
      final res = await KlpbbsApi.loadPapaConversation(convId, apiUrl: _context.apiUrl);
      if (mounted) {
        setState(() {
          _currentTitle = res.title.isNotEmpty ? res.title : '对话';
          _messages = res.messages;
        });
        _scrollToBottom(animated: false);
      }
    } catch (_) {}
  }

  Future<void> _deleteConversation(int convId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确认删除「$title」吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    await KlpbbsApi.deletePapaConversation(convId, apiUrl: _context.apiUrl);
    final convs = await KlpbbsApi.getPapaConversations(apiUrl: _context.apiUrl);
    if (mounted) {
      setState(() {
        _conversations = convs;
        if (_currentConvId == convId) {
          _startNewChat();
        }
      });
    }
  }

  Future<void> _selectReport(String type) async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    _chatSub?.cancel();
    _reportSub?.cancel();

    final typeNames = {'day': '日报', 'week': '周报', 'month': '月报'};
    final name = typeNames[type] ?? '报告';

    setState(() {
      _currentReportType = type;
      _currentTitle = '帕帕 · $name';
      _activeReport = null;
      _reportHistory = [];
      _isStreaming = false;
      _generatingReport = false;
    });

    try {
      final allReports = await KlpbbsApi.getPapaReports(apiUrl: _context.apiUrl);
      final matching = allReports.where((r) => r.type == type).toList();
      final todayRep = matching.where((r) => r.isToday).firstOrNull;
      final history = matching.where((r) => !r.isToday).toList();

      if (mounted) {
        setState(() {
          _activeReport = todayRep;
          _reportHistory = history;
        });
      }
    } catch (_) {}
  }

  void _generateReport(String type, {bool regen = false}) {
    final streamUrl = 'plugin.php?id=klpbbs_ai:stream&type=$type';
    setState(() {
      _generatingReport = true;
    });

    _reportSub?.cancel();
    _reportSub = KlpbbsApi.streamPapaGenerateReport(streamUrl, regen: regen).listen((evt) {
      if (!mounted) return;
      if (evt.event == 'delta') {
        final d = evt.data is Map ? evt.data as Map<String, dynamic> : <String, dynamic>{};
        setState(() {
          _activeReport = PapaReport.fromJson(d);
        });
      } else if (evt.event == 'complete') {
        final d = evt.data is Map ? evt.data as Map<String, dynamic> : <String, dynamic>{};
        setState(() {
          _generatingReport = false;
          if (d['report'] is Map<String, dynamic>) {
            _activeReport = PapaReport.fromJson(d['report'] as Map<String, dynamic>);
          }
          if (d['freeleft'] != null) {
            _context = PapaChatContext(
              streamUrl: _context.streamUrl,
              apiUrl: _context.apiUrl,
              formhash: _context.formhash,
              freeLeft: d['freeleft'] as int? ?? _context.freeLeft,
              balance: d['balance'] as int? ?? _context.balance,
              chatOn: _context.chatOn,
              inputMax: _context.inputMax,
              panels: _context.panels,
              reports: _context.reports,
            );
          }
        });
      } else if (evt.event == 'failed' || evt.event == 'unavailable') {
        setState(() {
          _generatingReport = false;
        });
        final msg = evt.data is Map ? (evt.data['message']?.toString() ?? '报告生成未完成') : '报告生成未完成';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }, onError: (e) {
      if (mounted) {
        setState(() => _generatingReport = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('报告流异常：$e')));
      }
    });
  }

  void _sendMessage({String? overrideText}) {
    final text = (overrideText ?? _inputCtrl.text).trim();
    if (text.isEmpty || _isStreaming) return;

    if (overrideText == null) {
      _inputCtrl.clear();
    }

    final userMsg = PapaMessage(role: 'user', content: text, time: '刚刚');
    final assistantMsg = PapaMessage(
      role: 'assistant',
      content: '',
      isStreaming: true,
      time: '刚刚',
    );

    setState(() {
      _currentReportType = null;
      _messages.add(userMsg);
      _messages.add(assistantMsg);
      _isStreaming = true;
    });
    _scrollToBottom();

    final targetMsgIndex = _messages.length - 1;
    String streamedText = '';

    _chatSub?.cancel();
    _chatSub = KlpbbsApi.streamPapaChat(
      streamUrl: _context.streamUrl,
      convId: _currentConvId,
      message: text,
      edition: _edition,
      editionMode: 'manual',
    ).listen((evt) {
      if (!mounted) return;
      final event = evt.event;
      final data = evt.data is Map ? evt.data as Map<String, dynamic> : <String, dynamic>{};

      if (event == 'meta') {
        final cid = int.tryParse(data['convid']?.toString() ?? '');
        final t = data['title']?.toString();
        setState(() {
          if (cid != null && cid > 0) _currentConvId = cid;
          if (t != null && t.isNotEmpty) _currentTitle = t;
        });
      } else if (event == 'tool') {
        final newTool = PapaToolCall.fromJson(data);
        setState(() {
          final cur = List<PapaToolCall>.from(_messages[targetMsgIndex].tools)..add(newTool);
          _messages[targetMsgIndex] = _messages[targetMsgIndex].copyWith(
            tools: cur,
          );
        });
        _scrollToBottom();
      } else if (event == 'delta') {
        final chunk = data['text']?.toString() ?? '';
        streamedText = chunk;
        setState(() {
          _messages[targetMsgIndex] = _messages[targetMsgIndex].copyWith(
            content: streamedText,
          );
        });
        _scrollToBottom();
      } else if (event == 'complete') {
        final finalContent = data['text']?.toString() ?? streamedText;
        final List<PapaReference> refs = [];
        final rawRefs = data['refs'];
        if (rawRefs is List) {
          for (final e in rawRefs) {
            if (e is Map<String, dynamic>) {
              refs.add(PapaReference.fromJson(e));
            } else if (e is Map) {
              refs.add(PapaReference.fromJson(Map<String, dynamic>.from(e)));
            }
          }
        } else if (rawRefs is Map) {
          for (final e in rawRefs.values) {
            if (e is Map<String, dynamic>) {
              refs.add(PapaReference.fromJson(e));
            } else if (e is Map) {
              refs.add(PapaReference.fromJson(Map<String, dynamic>.from(e)));
            }
          }
        }

        // 智能补充：如果正文中提及了站内帖子编号，自动将其注入 refs
        final tidMatches = RegExp(r'(?:[〔\[\(\{<（【‘“]\s*帖子\s*#?(\d+)\s*[〕\]\)\}>）】’”]|帖子\s*#?(\d+)(?![\dA-Za-z_.]))')
            .allMatches(finalContent);
        final existingTids = refs.where((r) => r.tid != null).map((r) => r.tid!).toSet();
        for (final m in tidMatches) {
          final tStr = m.group(1) ?? m.group(2);
          final tid = int.tryParse(tStr ?? '');
          if (tid != null && tid > 0 && !existingTids.contains(tid)) {
            existingTids.add(tid);
            refs.add(PapaReference(
              tid: tid,
              title: '帖子 #$tid',
              url: 'https://www.klpbbs.com/thread-$tid-1-1.html',
            ));
          }
        }

        final rawTools = data['tools'] as List<dynamic>? ?? const [];
        final completedTools = rawTools.isNotEmpty
            ? rawTools.map((e) => PapaToolCall.fromJson(e)).toList()
            : _messages[targetMsgIndex].tools;
        final cost = int.tryParse(data['cost']?.toString() ?? '0') ?? 0;
        final inTok = int.tryParse(data['intokens']?.toString() ?? '0') ?? 0;
        final outTok = int.tryParse(data['outtokens']?.toString() ?? '0') ?? 0;

        setState(() {
          _isStreaming = false;
          _messages[targetMsgIndex] = _messages[targetMsgIndex].copyWith(
            content: finalContent,
            refs: refs,
            tools: completedTools,
            cost: cost,
            inTokens: inTok,
            outTokens: outTok,
            isStreaming: false,
          );
          if (data['freeleft'] != null) {
            _context = PapaChatContext(
              streamUrl: _context.streamUrl,
              apiUrl: _context.apiUrl,
              formhash: _context.formhash,
              freeLeft: data['freeleft'] as int? ?? _context.freeLeft,
              balance: data['balance'] as int? ?? _context.balance,
              chatOn: _context.chatOn,
              inputMax: _context.inputMax,
              panels: _context.panels,
              reports: _context.reports,
            );
          }
        });

        // 刷新会话列表
        KlpbbsApi.getPapaConversations(apiUrl: _context.apiUrl).then((c) {
          if (mounted) setState(() => _conversations = c);
        });
        _scrollToBottom();
      } else if (event == 'failed' || event == 'unavailable') {
        final errMsg = data['message']?.toString() ?? '帕帕回复异常，请稍后重试';
        setState(() {
          _isStreaming = false;
          _messages[targetMsgIndex] = _messages[targetMsgIndex].copyWith(
            content: streamedText.isNotEmpty ? '$streamedText\n\n[提示：$errMsg]' : '[提示：$errMsg]',
            isStreaming: false,
          );
        });
        _scrollToBottom();
      }
    }, onError: (err) {
      if (!mounted) return;
      setState(() {
        _isStreaming = false;
        _messages[targetMsgIndex] = _messages[targetMsgIndex].copyWith(
          content: streamedText.isNotEmpty ? '$streamedText\n\n[网络中断]' : '[网络连接中断，请重试]',
          isStreaming: false,
        );
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (animated) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = PapaPalette.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 860;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: pal.bg,
      drawerEnableOpenDragGesture: !isDesktop,
      drawerEdgeDragWidth: 50.0,
      appBar: AppBar(
        backgroundColor: pal.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: pal.border)),
        titleSpacing: isDesktop ? 20 : 0,
        leadingWidth: isDesktop ? null : (Navigator.of(context).canPop() ? 84 : null),
        leading: isDesktop
            ? (Navigator.of(context).canPop()
                ? IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: pal.text2),
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (scaffoldContext) => IconButton(
                      icon: Icon(Icons.menu_rounded, color: pal.text2),
                      tooltip: '打开侧边栏',
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Scaffold.of(scaffoldContext).openDrawer();
                      },
                    ),
                  ),
                  if (Navigator.of(context).canPop())
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: pal.text2),
                      tooltip: '返回论坛',
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo
            Container(
              width: 26,
              height: 26,
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
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: isDesktop
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '帕帕',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: pal.heading),
                        ),
                        Text(
                          _currentTitle,
                          style: TextStyle(fontSize: 11, color: pal.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Text(
                      '帕帕 AI',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: pal.heading),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            if (isDesktop) ...[
              const SizedBox(width: 14),
              // 顶栏导航标签 (对话 / 我的积分)
              _buildNavTab(
                label: '对话',
                isActive: _currentReportType == null,
                onTap: () {
                  if (_currentReportType != null) {
                    _startNewChat();
                  }
                },
                pal: pal,
              ),
              const SizedBox(width: 4),
              _buildNavTab(
                label: '我的积分',
                isActive: false,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PapaAiWalletPage()),
                  );
                },
                pal: pal,
              ),
            ],
          ],
        ),
        actions: [
          // 快捷显示额度
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PapaAiWalletPage()),
                );
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 10 : 7,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: pal.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: pal.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 14, color: pal.primaryStrong),
                    const SizedBox(width: 3),
                    Text(
                      isDesktop
                          ? '${_context.freeLeft} 次 | ${_context.balance} 火药'
                          : '${_context.freeLeft}次',
                      style: TextStyle(fontSize: 11.5, color: pal.text2, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!isDesktop)
            Builder(
              builder: (scaffoldContext) => IconButton(
                icon: Icon(Icons.history_rounded, size: 21, color: pal.text2),
                tooltip: '历史与报告',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Scaffold.of(scaffoldContext).openDrawer();
                },
              ),
            ),
          IconButton(
            icon: Icon(Icons.add_comment_outlined, size: 20, color: pal.text2),
            tooltip: '新对话',
            onPressed: _startNewChat,
          ),
          const SizedBox(width: 6),
        ],
      ),
      drawer: isDesktop ? null : Drawer(backgroundColor: pal.bg, child: _buildSidebar(context, pal)),
      body: Row(
        children: [
          if (isDesktop)
            SizedBox(
              width: 256,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: pal.surface,
                  border: Border(right: BorderSide(color: pal.border)),
                ),
                child: _buildSidebar(context, pal),
              ),
            ),
          Expanded(
            child: Container(
              color: pal.bg,
              child: Column(
                children: [
                  Expanded(
                    child: _loading
                        ? Center(child: CircularProgressIndicator(color: pal.primaryStrong))
                        : (_currentReportType != null
                            ? _buildReportView(context, pal)
                            : _buildChatView(context, pal)),
                  ),
                  if (_currentReportType == null) _buildBottomComposer(context, pal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTab({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required PapaPalette pal,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? pal.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? pal.primaryText : pal.text2,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, PapaPalette pal) {
    final isDesktop = MediaQuery.of(context).size.width >= 860;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isDesktop)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
              child: Row(
                children: [
                  Text(
                    '历史会话与报告',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: pal.heading,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: pal.text2),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          // "+ 新对话" 幽灵线框按钮 (与 Discuz .kai-btn.ghost 对齐)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: OutlinedButton.icon(
              icon: Icon(Icons.add_rounded, size: 16, color: pal.primaryText),
              label: Text(
                '新对话',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: pal.primaryText,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(38),
                side: BorderSide(color: pal.border),
                backgroundColor: pal.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              ),
              onPressed: _startNewChat,
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                // 报告区域 (无冗余图标，极简排版)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
                  child: Text(
                    '报告',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: pal.muted,
                    ),
                  ),
                ),
                _buildReportMenuItem('day', '日报', '20 积分', pal),
                _buildReportMenuItem('week', '周报', '50 积分', pal),
                _buildReportMenuItem('month', '月报', '100 积分', pal),

                // 对话区域 (无冗余图标，极简排版)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 20, 10, 6),
                  child: Text(
                    '对话',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: pal.muted,
                    ),
                  ),
                ),
                if (_conversations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text('还没有对话', style: TextStyle(fontSize: 12.5, color: pal.muted)),
                  )
                else
                  ..._conversations.map((c) {
                    final selected = _currentReportType == null && _currentConvId == c.id;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _switchConversation(c.id),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? pal.primarySoft : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                  color: selected ? pal.primaryText : pal.text2,
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => _deleteConversation(c.id, c.title),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: selected ? pal.primaryText.withAlpha(160) : pal.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),

          // 底部积分与钱包入口 (.kai-rail-foot & .kai-mini)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: pal.border)),
              color: pal.surface,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                if (!isDesktop && (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
                  Navigator.of(context).pop();
                }
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PapaAiWalletPage()),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('今日免费剩余', style: TextStyle(fontSize: 12, color: pal.muted)),
                      Text(
                        '${_context.freeLeft}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: pal.heading,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('火药余额', style: TextStyle(fontSize: 12, color: pal.muted)),
                      Text(
                        '${_context.balance}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: pal.heading,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '我的积分 ›',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: pal.primaryText),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportMenuItem(String type, String title, String cost, PapaPalette pal) {
    final selected = _currentReportType == type;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _selectReport(type),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? pal.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? pal.primaryText : pal.text2,
              ),
            ),
            Text(
              cost,
              style: TextStyle(
                fontSize: 11.5,
                color: selected ? pal.primaryText : pal.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatView(BuildContext context, PapaPalette pal) {
    if (_messages.isEmpty) {
      return _buildEmptyHello(context, pal);
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final m = _messages[index];
        return _buildMessageTile(context, m, pal);
      },
    );
  }

  Widget _buildEmptyHello(BuildContext context, PapaPalette pal) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [pal.primary, pal.primaryStrong],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: pal.primaryStrong.withAlpha(80),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  '帕',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '你好，我是帕帕',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: pal.heading),
              ),
              const SizedBox(height: 10),
              Text(
                '想找资源、教程，或者看看站里最近发生了什么，都可以问我。我会先去论坛里搜一遍，再把找到的帖子讲给你听。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: pal.muted, height: 1.6),
              ),
              const SizedBox(height: 24),

              // 快捷 Prompts (无任何 emoji)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildPromptChip('找一个生存整合包', () => _sendMessage(overrideText: '找一个生存整合包'), pal),
                  _buildPromptChip('最近论坛上有什么新东西', () => _sendMessage(overrideText: '最近论坛上有什么新东西'), pal),
                  _buildPromptChip('生成今天的日报', () => _selectReport('day'), pal),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromptChip(String label, VoidCallback onTap, PapaPalette pal) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: pal.surface2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: pal.border),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, color: pal.text2),
        ),
      ),
    );
  }

  Widget _buildMessageTile(BuildContext context, PapaMessage m, PapaPalette pal) {
    if (m.isUser) {
      // 用户气泡：靠右，深色模式采用 --kai-primary-soft 与 --kai-primary-line
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: pal.primarySoft,
                  border: Border.all(color: pal.primaryLine),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: SelectableText(
                  m.content,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.6,
                    color: pal.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // 解析全部关联引用（包括服务端下发及正文中提及的帖子和用户）
    final allRefs = _resolveMessageReferences(m);

    // AI 助手回复：不套厚重气泡！全篇正文流式展开 (与 Discuz kai.css 对齐)
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：头像与名称 (.kai-who)
          Row(
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
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '帕',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '帕帕',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.text2),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 检索动作药丸集合 (.kai-tools & .kai-tool)
          if (m.tools.isNotEmpty) _buildToolsWrap(m.tools, pal),

          // 正在思考但未出字时的打字机动效
          if (m.isStreaming && m.content.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  _buildDot(0, pal),
                  const SizedBox(width: 4),
                  _buildDot(1, pal),
                  const SizedBox(width: 4),
                  _buildDot(2, pal),
                ],
              ),
            ),

          // 消息正文渲染 (支持段落、代码块、列表、行内引用标签点击直接跳转)
          if (m.content.isNotEmpty)
            _buildMarkdownBody(m.content, pal, allRefs),

          // 引用站内帖子 / 用户卡片 (.kai-ref & .kai-rescard)
          if (allRefs.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...allRefs.map((r) => _buildReferenceCard(context, r, pal)),
          ],

          // 消耗积分与 Token 元数据 (.kai-turn .meta)
          if (m.cost > 0 || m.inTokens > 0 || m.outTokens > 0) ...[
            const SizedBox(height: 10),
            Text(
              '消耗 ${m.cost} 积分 · 输入 ${m.inTokens} + 输出 ${m.outTokens} token',
              style: TextStyle(fontSize: 11.5, color: pal.muted),
            ),
          ],
        ],
      ),
    );
  }

  /// 解析消息内所有的引用资源（合并服务端推送与消息正文中提及的帖子与用户）
  List<PapaReference> _resolveMessageReferences(PapaMessage m) {
    final result = List<PapaReference>.from(m.refs);
    final existingTids = result.where((r) => r.tid != null).map((r) => r.tid!).toSet();
    final existingUids = result.where((r) => r.uid != null).map((r) => r.uid!).toSet();

    // 智能提取正文中出现的所有帖子和用户编号
    final matches = RegExp(
      r'(?:[〔\[\(\{<（【‘“]\s*(帖子|用户)\s*#?(\d+)\s*[〕\]\)\}>）】’”]|(帖子|用户)\s*#?(\d+)(?![\dA-Za-z_.]))',
    ).allMatches(m.content);

    for (final match in matches) {
      final kind = match.group(1) ?? match.group(3);
      final idStr = match.group(2) ?? match.group(4);
      final id = int.tryParse(idStr ?? '');
      if (id == null || id <= 0) continue;

      if (kind == '帖子') {
        if (!existingTids.contains(id)) {
          existingTids.add(id);
          result.add(PapaReference(
            tid: id,
            title: '帖子 #$id',
            url: 'https://www.klpbbs.com/thread-$id-1-1.html',
          ));
        }
      } else if (kind == '用户') {
        if (!existingUids.contains(id)) {
          existingUids.add(id);
          result.add(PapaReference(
            uid: id,
            title: '用户 $id',
            type: 'user',
            url: 'https://www.klpbbs.com/home.php?mod=space&uid=$id',
          ));
        }
      }
    }
    return result;
  }

  Widget _buildDot(int index, PapaPalette pal) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: pal.primaryStrong,
        shape: BoxShape.circle,
      ),
    );
  }

  /// 工具调用展示药丸组 (青绿圆点引导，无月亮图标，支持多项并列)
  Widget _buildToolsWrap(List<PapaToolCall> tools, PapaPalette pal) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: tools.map((tool) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3.5),
            decoration: BoxDecoration(
              color: pal.surface2,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: pal.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: pal.primaryStrong,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  tool.label,
                  style: TextStyle(fontSize: 12, color: pal.text2),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Markdown 简单流式解析与排版渲染（支持行内帖子/用户链接与富文本）
  Widget _buildMarkdownBody(
    String content,
    PapaPalette pal, [
    List<PapaReference> refs = const [],
  ]) {
    final lines = content.split('\n');
    final children = <Widget>[];

    var inCodeBlock = false;
    final codeBuffer = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        if (!inCodeBlock) {
          inCodeBlock = true;
          codeBuffer.clear();
        } else {
          inCodeBlock = false;
          final codeText = codeBuffer.toString();
          children.add(
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pal.surface2,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: pal.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      codeText,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12.5,
                        height: 1.5,
                        color: pal.text,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: 14, color: pal.muted),
                    tooltip: '复制',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: codeText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制代码'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }
        continue;
      }

      if (inCodeBlock) {
        codeBuffer.writeln(line);
        continue;
      }

      if (trimmed.isEmpty) {
        children.add(const SizedBox(height: 6));
        continue;
      }

      // 标题
      if (trimmed.startsWith('### ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: SelectableText(
              trimmed.substring(4),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: pal.heading),
            ),
          ),
        );
        continue;
      }

      // 引用
      if (trimmed.startsWith('> ')) {
        children.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: pal.primaryLine, width: 3)),
            ),
            child: _buildRichInlineText(
              context,
              trimmed.substring(2),
              TextStyle(fontSize: 13.5, height: 1.6, color: pal.text2),
              pal,
              refs,
            ),
          ),
        );
        continue;
      }

      // 无序列表
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4.5,
                  height: 4.5,
                  margin: const EdgeInsets.only(top: 8, right: 8),
                  decoration: BoxDecoration(
                    color: pal.primaryStrong,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: _buildRichInlineText(
                    context,
                    trimmed.substring(2),
                    TextStyle(fontSize: 14, height: 1.65, color: pal.text),
                    pal,
                    refs,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // 普通段落
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: _buildRichInlineText(
            context,
            trimmed,
            TextStyle(fontSize: 14.5, height: 1.7, color: pal.text),
            pal,
            refs,
          ),
        ),
      );
    }

    // 若流式输出中代码块还未闭合，补全渲染
    if (inCodeBlock && codeBuffer.isNotEmpty) {
      children.add(
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: pal.surface2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: pal.border),
          ),
          child: SelectableText(
            codeBuffer.toString(),
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12.5,
              height: 1.5,
              color: pal.text,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// 行内富文本解析：支持点击跳转帖子/用户，粗体与行内代码
  Widget _buildRichInlineText(
    BuildContext context,
    String text,
    TextStyle baseStyle,
    PapaPalette pal, [
    List<PapaReference> refs = const [],
  ]) {
    final spans = <InlineSpan>[];
    final regex = RegExp(
      r'(?:[〔\[\(\{<（【‘“]\s*(帖子|用户)\s*#?(\d+)\s*[〕\]\)\}>）】’”]|(帖子|用户)\s*#?(\d+)(?![\dA-Za-z_.]))|'
      r'\*\*([^*]+?)\*\*|'
      r'`([^`\n]+)`',
    );

    int lastIndex = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: baseStyle,
        ));
      }

      final kind = match.group(1) ?? match.group(3);
      final idStr = match.group(2) ?? match.group(4);
      final boldText = match.group(5);
      final codeText = match.group(6);

      if (kind != null && idStr != null) {
        final id = int.tryParse(idStr);
        if (id != null && id > 0) {
          if (kind == '帖子') {
            final matchingRef = refs.cast<PapaReference?>().firstWhere(
                  (r) => r?.tid == id,
                  orElse: () => null,
                );
            final title = (matchingRef != null && matchingRef.title.isNotEmpty)
                ? matchingRef.title
                : '帖子 #$id';

            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 1.5),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ThreadDetailPage(tid: id),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: pal.primarySoft,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: pal.primaryLine, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.article_outlined,
                              size: 13,
                              color: pal.primaryText,
                            ),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: pal.primaryText,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 11,
                              color: pal.primaryText.withAlpha(180),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          } else if (kind == '用户') {
            final matchingRef = refs.cast<PapaReference?>().firstWhere(
                  (r) => r?.uid == id,
                  orElse: () => null,
                );
            final name = (matchingRef != null && matchingRef.title.isNotEmpty)
                ? matchingRef.title
                : 'UID $id';

            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 1.5),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UserSpacePage(uid: id),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: pal.surface2,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: pal.border, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 13,
                              color: pal.text2,
                            ),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: pal.text2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }
      } else if (boldText != null) {
        spans.add(
          TextSpan(
            text: boldText,
            style: baseStyle.copyWith(
              fontWeight: FontWeight.bold,
              color: pal.heading,
            ),
          ),
        );
      } else if (codeText != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: pal.surface2,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: pal.border, width: 0.6),
              ),
              child: Text(
                codeText,
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12.5,
                  color: pal.primaryText,
                ),
              ),
            ),
          ),
        );
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: baseStyle,
      ));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }

  /// 资源卡片 (.kai-rescard，对齐 klpbbs 原生帖子卡片规范)
  Widget _buildReferenceCard(BuildContext context, PapaReference r, PapaPalette pal) {
    final cs = Theme.of(context).colorScheme;
    final isUser = r.type == 'user';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(pal.isDark ? 30 : 8),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (isUser && r.uid != null && r.uid! > 0) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => UserSpacePage(uid: r.uid!)),
              );
            } else if (r.tid != null && r.tid! > 0) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: r.tid!)),
              );
            } else {
              UrlHelper.openLink(context, r.url);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isUser ? cs.secondaryContainer.withAlpha(120) : pal.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isUser ? Icons.person_outline_rounded : Icons.article_outlined,
                        size: 17,
                        color: isUser ? cs.secondary : pal.primaryText,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.title.isNotEmpty ? r.title : (r.tid != null ? '帖子 #${r.tid}' : r.url),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: pal.heading,
                              height: 1.3,
                            ),
                          ),
                          if (r.summary != null && r.summary!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              r.summary!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: pal.text2, height: 1.45),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_ios_rounded, size: 12, color: pal.muted),
                  ],
                ),
                if (!isUser) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (r.edition == 'je' || (r.forum?.contains('JE') ?? false))
                        _buildBadgeChip(
                          icon: Icons.desktop_windows_outlined,
                          label: 'Java版',
                          color: pal.primaryText,
                          bgColor: pal.primarySoft,
                        )
                      else if (r.edition == 'be' || (r.forum?.contains('BE') ?? false))
                        _buildBadgeChip(
                          icon: Icons.smartphone_rounded,
                          label: '基岩版',
                          color: const Color(0xFF2E7D32),
                          bgColor: const Color(0xFF2E7D32).withAlpha(25),
                        ),
                      if (r.forum != null && r.forum!.isNotEmpty)
                        _buildBadgeChip(
                          icon: Icons.forum_outlined,
                          label: r.forum!,
                          color: pal.text2,
                          bgColor: pal.surface2,
                        ),
                      if (r.replies != null)
                        _buildBadgeChip(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: '${r.replies} 回复',
                          color: pal.muted,
                          bgColor: Colors.transparent,
                        ),
                      if (r.views != null && r.views! > 0)
                        _buildBadgeChip(
                          icon: Icons.visibility_outlined,
                          label: '${r.views} 浏览',
                          color: pal.muted,
                          bgColor: Colors.transparent,
                        ),
                      if (r.hasAttach)
                        _buildBadgeChip(
                          icon: Icons.attachment_rounded,
                          label: '有附件',
                          color: Colors.amber.shade700,
                          bgColor: Colors.amber.withAlpha(30),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadgeChip({
    required IconData icon,
    required String label,
    required Color color,
    Color? bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor ?? Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  /// 报告详情视图
  Widget _buildReportView(BuildContext context, PapaPalette pal) {
    final typeNames = {'day': '日报', 'week': '周报', 'month': '月报'};
    final type = _currentReportType ?? 'day';
    final name = typeNames[type] ?? '报告';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_generatingReport) ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: pal.border),
            ),
            child: Column(
              children: [
                CircularProgressIndicator(color: pal.primaryStrong),
                const SizedBox(height: 16),
                Text(
                  '帕帕正在阅览全站并生成今日$name...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: pal.heading),
                ),
                const SizedBox(height: 6),
                Text('正在检索活跃主题与帖子变动...', style: TextStyle(fontSize: 12, color: pal.muted)),
              ],
            ),
          ),
        ] else if (_activeReport != null) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: pal.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pal.primarySoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: pal.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_activeReport!.date, style: TextStyle(fontSize: 12, color: pal.muted)),
                    const Spacer(),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text('重新生成', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: pal.border),
                        foregroundColor: pal.text2,
                      ),
                      onPressed: () => _generateReport(type, regen: true),
                    ),
                  ],
                ),
                if (_activeReport!.headline.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _activeReport!.headline,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: pal.heading),
                  ),
                ],
                const SizedBox(height: 12),
                _buildMarkdownBody(_activeReport!.content, pal),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: pal.border),
            ),
            child: Column(
              children: [
                Icon(Icons.article_outlined, size: 44, color: pal.primaryStrong),
                const SizedBox(height: 12),
                Text(
                  '今天的$name还没有生成',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pal.heading),
                ),
                const SizedBox(height: 6),
                Text(
                  '汇集今日站内动态、热门回复与精华发布。',
                  style: TextStyle(fontSize: 12.5, color: pal.muted),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: Text('生成$name · ${_getReportPrice(type)} 积分'),
                  style: FilledButton.styleFrom(
                    backgroundColor: pal.primaryStrong,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  ),
                  onPressed: () => _generateReport(type),
                ),
              ],
            ),
          ),
        ],

        // 历史报告
        if (_reportHistory.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            '更早的$name',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: pal.heading),
          ),
          const SizedBox(height: 8),
          ..._reportHistory.map((h) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: pal.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: pal.border),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    h.headline.isNotEmpty ? h.headline : h.date,
                    style: TextStyle(fontSize: 13.5, color: pal.heading),
                  ),
                  trailing: Text(h.date, style: TextStyle(fontSize: 12, color: pal.muted)),
                  onTap: () {
                    setState(() => _activeReport = h);
                  },
                ),
              )),
        ],
      ],
    );
  }

  int _getReportPrice(String type) {
    if (type == 'week') return 50;
    if (type == 'month') return 100;
    return 20;
  }

  /// 底部集成式输入容器 (.kai-dock & .kai-composer)
  Widget _buildBottomComposer(BuildContext context, PapaPalette pal) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      color: pal.bg,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 集成输入框卡片
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: pal.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _composerFocusNode.hasFocus ? pal.primary : pal.border,
                      width: _composerFocusNode.hasFocus ? 1.4 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(pal.isDark ? 40 : 12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _inputCtrl,
                        focusNode: _composerFocusNode,
                        maxLines: 5,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: TextStyle(fontSize: 14.5, color: pal.text, height: 1.6),
                        decoration: InputDecoration(
                          hintText: '问帕帕点什么，比如「找一个生存整合包」',
                          hintStyle: TextStyle(fontSize: 13.5, color: pal.muted),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          // 版本切换器 (.kai-chipbtn，无 Emoji)
                          _buildEditionSelector(context, pal),
                          const Spacer(),
                          // 发送按钮 (34x34 圆角矩形，↑ 箭头)
                          InkWell(
                            onTap: _isStreaming ? () => _chatSub?.cancel() : () => _sendMessage(),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: pal.primaryStrong,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                _isStreaming ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '帕帕会先检索站内帖子再回答，不能保证内容准确无误，重要信息请以原帖为准。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: pal.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 版本选择器药丸按钮 (纯线框/无 Emoji)
  Widget _buildEditionSelector(BuildContext context, PapaPalette pal) {
    IconData icon;
    String label;
    if (_edition == 'be') {
      icon = Icons.smartphone_rounded;
      label = '基岩版';
    } else if (_edition == 'auto') {
      icon = Icons.devices_outlined;
      label = '跟着设备走';
    } else {
      icon = Icons.desktop_windows_outlined;
      label = 'Java版';
    }

    return PopupMenuButton<String>(
      tooltip: '切换优先查找的游戏版本',
      initialValue: _edition,
      color: pal.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: pal.border),
      ),
      onSelected: (v) => setState(() => _edition = v),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'auto',
          child: Row(
            children: [
              Icon(Icons.devices_outlined, size: 16, color: pal.text2),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('跟着设备走', style: TextStyle(fontSize: 13, color: pal.heading)),
                  Text('按设备优先自动匹配', style: TextStyle(fontSize: 11, color: pal.muted)),
                ],
              ),
              if (_edition == 'auto') ...[
                const Spacer(),
                Text('当前', style: TextStyle(fontSize: 11, color: pal.primaryText)),
              ],
            ],
          ),
        ),
        PopupMenuItem(
          value: 'je',
          child: Row(
            children: [
              Icon(Icons.desktop_windows_outlined, size: 16, color: pal.text2),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('电脑 · Java版', style: TextStyle(fontSize: 13, color: pal.heading)),
                  Text('JE 整合包、模组、材质', style: TextStyle(fontSize: 11, color: pal.muted)),
                ],
              ),
              if (_edition == 'je') ...[
                const Spacer(),
                Text('当前', style: TextStyle(fontSize: 11, color: pal.primaryText)),
              ],
            ],
          ),
        ),
        PopupMenuItem(
          value: 'be',
          child: Row(
            children: [
              Icon(Icons.smartphone_rounded, size: 16, color: pal.text2),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('手机 · 基岩版', style: TextStyle(fontSize: 13, color: pal.heading)),
                  Text('BE 地图、附加包、纹理', style: TextStyle(fontSize: 11, color: pal.muted)),
                ],
              ),
              if (_edition == 'be') ...[
                const Spacer(),
                Text('当前', style: TextStyle(fontSize: 11, color: pal.primaryText)),
              ],
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: pal.surface2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: pal.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: pal.text2),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: pal.text2),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: pal.muted),
          ],
        ),
      ),
    );
  }
}
