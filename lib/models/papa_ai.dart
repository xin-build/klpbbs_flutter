// 苦力怕论坛 帕帕 AI 助手（klpbbs_ai）领域数据模型
import 'package:flutter/material.dart';

/// 帕帕 AI 官方配色设计规范 (与 Discuz 插件 static/kai.css 100% 对齐)
class PapaColors {
  // Dark mode (默认)
  static const darkBg = Color(0xFF11171D);
  static const darkSurface = Color(0xFF1A212A);
  static const darkSurface2 = Color(0xFF212A34);
  static const darkSurface3 = Color(0xFF29333E);
  static const darkBorder = Color(0xFF2B3641);
  static const darkLine = Color(0xFF242E38);
  static const darkText = Color(0xFFD5DDE4);
  static const darkHeading = Color(0xFFEEF3F7);
  static const darkText2 = Color(0xFFA3AFBA);
  static const darkMuted = Color(0xFF76828D);
  static const darkPrimary = Color(0xFF4FBFAB);
  static const darkPrimaryStrong = Color(0xFF35A893);
  static const darkPrimaryHover = Color(0xFF46BDA7);
  static const darkPrimaryText = Color(0xFF6FD3C1);
  static const darkPrimarySoft = Color(0xFF17312D);
  static const darkPrimaryLine = Color(0xFF2C5F55);

  // Light mode
  static const lightBg = Color(0xFFF5F7F9);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFF4F7F9);
  static const lightSurface3 = Color(0xFFEAEFF3);
  static const lightBorder = Color(0xFFE5EAEF);
  static const lightLine = Color(0xFFEFF2F5);
  static const lightText = Color(0xFF2A333C);
  static const lightHeading = Color(0xFF141C24);
  static const lightText2 = Color(0xFF59646F);
  static const lightMuted = Color(0xFF8B959F);
  static const lightPrimary = Color(0xFF61CAB8);
  static const lightPrimaryStrong = Color(0xFF2B9D8A);
  static const lightPrimaryText = Color(0xFF17806F);
  static const lightPrimarySoft = Color(0xFFEEF9F6);
  static const lightPrimaryLine = Color(0xFFCDEAE2);
}

/// 帕帕主题动态配色调色板
class PapaPalette {
  final bool isDark;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color line;
  final Color text;
  final Color heading;
  final Color text2;
  final Color muted;
  final Color primary;
  final Color primaryStrong;
  final Color primaryText;
  final Color primarySoft;
  final Color primaryLine;

  const PapaPalette({
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.line,
    required this.text,
    required this.heading,
    required this.text2,
    required this.muted,
    required this.primary,
    required this.primaryStrong,
    required this.primaryText,
    required this.primarySoft,
    required this.primaryLine,
  });

  factory PapaPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    return PapaPalette(
      isDark: isDark,
      bg: theme.scaffoldBackgroundColor,
      surface: cs.surfaceContainerLow,
      surface2: cs.surfaceContainer,
      surface3: cs.surfaceContainerHigh,
      border: cs.outlineVariant.withAlpha(isDark ? 55 : 85),
      line: cs.outlineVariant.withAlpha(isDark ? 35 : 55),
      text: cs.onSurface,
      heading: cs.onSurface,
      text2: cs.onSurfaceVariant,
      muted: cs.outline,
      primary: cs.primary,
      primaryStrong: cs.primary,
      primaryText: cs.primary,
      primarySoft: cs.primaryContainer.withAlpha(isDark ? 120 : 160),
      primaryLine: cs.primary.withAlpha(isDark ? 70 : 90),
    );
  }
}

/// 会话简要信息
class PapaConversation {
  final int id;
  final String title;
  final String time;
  final int count;

  const PapaConversation({
    required this.id,
    required this.title,
    this.time = '',
    this.count = 0,
  });

  factory PapaConversation.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['convid'];
    final rawCount = json['count'] ?? json['msg_count'];
    return PapaConversation(
      id: rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '0') ?? 0,
      title: json['title'] as String? ?? '新对话',
      time: json['time'] as String? ?? '',
      count: rawCount is int ? rawCount : int.tryParse(rawCount?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'time': time,
        'count': count,
      };
}

/// 工具调用记录
class PapaToolCall {
  final String name;
  final String label;
  final int? count;

  const PapaToolCall({
    required this.name,
    required this.label,
    this.count,
  });

  factory PapaToolCall.fromJson(dynamic json) {
    if (json is String) {
      return PapaToolCall(name: '', label: json);
    }
    if (json is Map) {
      final name = json['name']?.toString() ?? '';
      final label = json['label']?.toString() ?? '';
      final count = int.tryParse(json['count']?.toString() ?? '');
      String computedLabel = label;
      if (computedLabel.isEmpty) {
        final names = {
          'search_threads': '搜索',
          'search_users': '搜索用户',
          'search_user_threads': '用户主题',
          'get_thread_brief': '读取帖子',
          'list_hot_threads': '热门榜',
        };
        computedLabel = names[name] ?? (name.isNotEmpty ? name : '未知工具');
        if (count != null) {
          computedLabel += ' · $count 条';
        }
      }
      return PapaToolCall(name: name, label: computedLabel, count: count);
    }
    return const PapaToolCall(name: '', label: '未知工具');
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'label': label,
        if (count != null) 'count': count,
      };
}

/// 消息引用的站内帖子/回帖溯源信息
class PapaReference {
  final int? tid;
  final int? pid;
  final int? uid;
  final String title;
  final String url;
  final String snippet;
  final String author;
  final String time;
  final String? type; // 'thread' | 'user'
  final String? edition; // 'je' | 'be'
  final String? forum;
  final int? replies;
  final int? views;
  final bool hasAttach;
  final String? summary;
  final List<String> notices;
  final String? date;

  const PapaReference({
    this.tid,
    this.pid,
    this.uid,
    required this.title,
    required this.url,
    this.snippet = '',
    this.author = '',
    this.time = '',
    this.type,
    this.edition,
    this.forum,
    this.replies,
    this.views,
    this.hasAttach = false,
    this.summary,
    this.notices = const [],
    this.date,
  });

  factory PapaReference.fromJson(Map<String, dynamic> json) {
    final rawNotices = json['notices'] as List<dynamic>? ?? const [];
    final tid = json['tid'] is int ? json['tid'] as int : int.tryParse(json['tid']?.toString() ?? '');
    final rawUrl = json['url'] as String? ?? json['link'] as String?;
    final finalUrl = (rawUrl != null && rawUrl.isNotEmpty)
        ? rawUrl
        : (tid != null && tid > 0 ? 'https://www.klpbbs.com/thread-$tid-1-1.html' : '');
    return PapaReference(
      tid: tid,
      pid: json['pid'] is int ? json['pid'] as int : int.tryParse(json['pid']?.toString() ?? ''),
      uid: json['uid'] is int ? json['uid'] as int : int.tryParse(json['uid']?.toString() ?? ''),
      title: json['title'] as String? ?? json['subject'] as String? ?? json['username'] as String? ?? '',
      url: finalUrl,
      snippet: json['snippet'] as String? ?? json['content'] as String? ?? '',
      author: json['author'] as String? ?? json['username'] as String? ?? '',
      time: json['time'] as String? ?? json['date'] as String? ?? '',
      type: json['type'] as String?,
      edition: json['edition'] as String?,
      forum: json['forum'] as String?,
      replies: json['replies'] is int ? json['replies'] as int : int.tryParse(json['replies']?.toString() ?? ''),
      views: json['views'] is int ? json['views'] as int : int.tryParse(json['views']?.toString() ?? ''),
      hasAttach: json['attach'] == true || json['has_attach'] == true,
      summary: json['summary'] as String?,
      notices: rawNotices.map((e) => e.toString()).toList(),
      date: json['date'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'tid': tid,
        'pid': pid,
        'uid': uid,
        'title': title,
        'url': url,
        'snippet': snippet,
        'author': author,
        'time': time,
        'type': type,
        'edition': edition,
        'forum': forum,
        'replies': replies,
        'views': views,
        'attach': hasAttach,
        'summary': summary,
        'notices': notices,
        'date': date,
      };
}

/// 对话消息单项
class PapaMessage {
  final int? id;
  final String role; // 'user' | 'assistant'
  final String content;
  final List<PapaReference> refs;
  final List<PapaToolCall> tools;
  final int cost; // 消耗积分数
  final int inTokens;
  final int outTokens;
  final String? time;
  final bool isStreaming;
  final String? currentTool;

  const PapaMessage({
    this.id,
    required this.role,
    required this.content,
    this.refs = const [],
    this.tools = const [],
    this.cost = 0,
    this.inTokens = 0,
    this.outTokens = 0,
    this.time,
    this.isStreaming = false,
    this.currentTool,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory PapaMessage.fromJson(Map<String, dynamic> json) {
    final rawRefs = json['refs'] as List<dynamic>? ?? const [];
    final rawTools = json['tools'] as List<dynamic>? ?? const [];
    final rawInTokens = json['intokens'] ?? json['in_tokens'];
    final rawOutTokens = json['outtokens'] ?? json['out_tokens'];
    return PapaMessage(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? ''),
      role: json['role'] as String? ?? 'assistant',
      content: json['text'] as String? ?? json['content'] as String? ?? '',
      refs: rawRefs.map((e) => PapaReference.fromJson(e as Map<String, dynamic>)).toList(),
      tools: rawTools.map((e) => PapaToolCall.fromJson(e)).toList(),
      cost: json['cost'] is int ? json['cost'] as int : int.tryParse(json['cost']?.toString() ?? '0') ?? 0,
      inTokens: rawInTokens is int ? rawInTokens : int.tryParse(rawInTokens?.toString() ?? '0') ?? 0,
      outTokens: rawOutTokens is int ? rawOutTokens : int.tryParse(rawOutTokens?.toString() ?? '0') ?? 0,
      time: json['time'] as String?,
      isStreaming: false,
    );
  }

  PapaMessage copyWith({
    int? id,
    String? role,
    String? content,
    List<PapaReference>? refs,
    List<PapaToolCall>? tools,
    int? cost,
    int? inTokens,
    int? outTokens,
    String? time,
    bool? isStreaming,
    String? currentTool,
  }) {
    return PapaMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      refs: refs ?? this.refs,
      tools: tools ?? this.tools,
      cost: cost ?? this.cost,
      inTokens: inTokens ?? this.inTokens,
      outTokens: outTokens ?? this.outTokens,
      time: time ?? this.time,
      isStreaming: isStreaming ?? this.isStreaming,
      currentTool: currentTool ?? this.currentTool,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'text': content,
        'refs': refs.map((e) => e.toJson()).toList(),
        'tools': tools.map((e) => e.toJson()).toList(),
        'cost': cost,
        'intokens': inTokens,
        'outtokens': outTokens,
        'time': time,
      };
}

/// 智能报告单项（日报/周报/月报）
class PapaReport {
  final int id;
  final String type; // 'day' | 'week' | 'month'
  final String typename; // '日报' | '周报' | '月报'
  final String headline;
  final String date;
  final String range;
  final String content;
  final Map<String, dynamic> stats;
  final int price;
  final int regenPrice;
  final int regenLeft;
  final bool isToday;

  const PapaReport({
    required this.id,
    required this.type,
    required this.typename,
    required this.headline,
    this.date = '',
    this.range = '',
    this.content = '',
    this.stats = const {},
    this.price = 0,
    this.regenPrice = 0,
    this.regenLeft = 0,
    this.isToday = false,
  });

  factory PapaReport.fromJson(Map<String, dynamic> json) {
    return PapaReport(
      id: json['rid'] is int
          ? json['rid'] as int
          : (json['id'] is int ? json['id'] as int : int.tryParse(json['rid']?.toString() ?? json['id']?.toString() ?? '0') ?? 0),
      type: json['type'] as String? ?? 'day',
      typename: json['typename'] as String? ?? '报告',
      headline: json['headline'] as String? ?? '',
      date: json['date'] as String? ?? '',
      range: json['range'] as String? ?? '',
      content: json['content'] as String? ?? json['text'] as String? ?? '',
      stats: json['stats'] is Map<String, dynamic> ? json['stats'] as Map<String, dynamic> : const {},
      price: json['price'] is int ? json['price'] as int : int.tryParse(json['price']?.toString() ?? '0') ?? 0,
      regenPrice: json['regenprice'] is int ? json['regenprice'] as int : int.tryParse(json['regenprice']?.toString() ?? '0') ?? 0,
      regenLeft: json['regenleft'] is int ? json['regenleft'] as int : int.tryParse(json['regenleft']?.toString() ?? '0') ?? 0,
      isToday: json['today'] == true || json['today'] == 1 || json['today'] == '1',
    );
  }
}

/// 积分兑换比率项
class PapaExchangeRate {
  final int src; // 积分 ID (如 2 代表铁粒)
  final String title; // 积分名称 (如 "铁粒")
  final int have; // 当前拥有数额
  final int rate; // 1 积分可兑换多少火药

  const PapaExchangeRate({
    required this.src,
    required this.title,
    required this.have,
    required this.rate,
  });

  factory PapaExchangeRate.fromJson(Map<String, dynamic> json) {
    return PapaExchangeRate(
      src: json['src'] is int ? json['src'] as int : int.tryParse(json['src']?.toString() ?? '0') ?? 0,
      title: json['title'] as String? ?? '',
      have: json['have'] is int ? json['have'] as int : int.tryParse(json['have']?.toString() ?? '0') ?? 0,
      rate: json['rate'] is int ? json['rate'] as int : int.tryParse(json['rate']?.toString() ?? '0') ?? 0,
    );
  }
}

/// 计费表单项
class PapaPriceItem {
  final String name;
  final String price;

  const PapaPriceItem({
    required this.name,
    required this.price,
  });

  factory PapaPriceItem.fromJson(Map<String, dynamic> json) {
    return PapaPriceItem(
      name: json['name'] as String? ?? '',
      price: json['price']?.toString() ?? '',
    );
  }
}

/// 火药流水记录
class PapaCreditLog {
  final String time;
  final String name;
  final String amount;
  final bool isIncome;
  final bool isPending;
  final String remark;

  const PapaCreditLog({
    required this.time,
    required this.name,
    required this.amount,
    this.isIncome = false,
    this.isPending = false,
    this.remark = '',
  });

  factory PapaCreditLog.fromJson(Map<String, dynamic> json) {
    final amt = json['amount']?.toString() ?? '';
    final income = json['income'] == true || amt.startsWith('+');
    return PapaCreditLog(
      time: json['time'] as String? ?? '',
      name: json['name'] as String? ?? '',
      amount: amt,
      isIncome: income,
      isPending: json['pending'] == true,
      remark: json['remark'] as String? ?? '',
    );
  }
}

/// 钱包与积分总览
class PapaWallet {
  final int freeLeft;
  final int freeTotal;
  final int balance;
  final String creditTitle;
  final bool exchangeOn;
  final int exchangeMin;
  final List<PapaExchangeRate> rates;
  final List<PapaPriceItem> prices;
  final List<PapaCreditLog> logs;

  const PapaWallet({
    this.freeLeft = 0,
    this.freeTotal = 50,
    this.balance = 0,
    this.creditTitle = '火药',
    this.exchangeOn = true,
    this.exchangeMin = 1,
    this.rates = const [],
    this.prices = const [],
    this.logs = const [],
  });

  PapaWallet copyWith({
    int? freeLeft,
    int? freeTotal,
    int? balance,
    String? creditTitle,
    bool? exchangeOn,
    int? exchangeMin,
    List<PapaExchangeRate>? rates,
    List<PapaPriceItem>? prices,
    List<PapaCreditLog>? logs,
  }) {
    return PapaWallet(
      freeLeft: freeLeft ?? this.freeLeft,
      freeTotal: freeTotal ?? this.freeTotal,
      balance: balance ?? this.balance,
      creditTitle: creditTitle ?? this.creditTitle,
      exchangeOn: exchangeOn ?? this.exchangeOn,
      exchangeMin: exchangeMin ?? this.exchangeMin,
      rates: rates ?? this.rates,
      prices: prices ?? this.prices,
      logs: logs ?? this.logs,
    );
  }
}

/// 聊天上下文初始化数据
class PapaChatContext {
  final String streamUrl;
  final String apiUrl;
  final String formhash;
  final int freeLeft;
  final int balance;
  final bool chatOn;
  final int inputMax;
  final Map<String, dynamic> panels;
  final List<Map<String, dynamic>> reports;

  const PapaChatContext({
    this.streamUrl = 'plugin.php?id=klpbbs_ai:stream',
    this.apiUrl = 'plugin.php?id=klpbbs_ai:api',
    this.formhash = '',
    this.freeLeft = 50,
    this.balance = 0,
    this.chatOn = true,
    this.inputMax = 1000,
    this.panels = const {},
    this.reports = const [],
  });
}
