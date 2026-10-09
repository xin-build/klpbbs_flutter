import 'dart:async';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import '../../api/klpbbs_api.dart';
import '../../core/app_config.dart';
import '../../core/dio_client.dart';
import '../../core/preload_service.dart';
import '../../core/url_helper.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/horn_message.dart';
import '../../pages/horn_post_page.dart';
import 'dashboard_card_frame.dart';

/// 当前站点广播；工坊复用已获取内容，轮播遵循系统及应用动画设置。
class HornDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;
  const HornDashboardCard(
      {super.key, required this.item, this.isPreview = false});
  @override
  State<HornDashboardCard> createState() => _HornDashboardCardState();
}

class _HornDashboardCardState extends State<HornDashboardCard>
    with WidgetsBindingObserver {
  List<HornMessage> _messages = [];
  int _index = 0;
  Timer? _timer;
  bool _tickerEnabled = true;
  bool _resumed = true;
  bool _systemReduced = false;
  bool _configuredReduced = AppConfig.reduceMotion;
  String? _error;

  @override
  void initState() {
    super.initState();
    _messages = PreloadService.instance
            .get<List<HornMessage>>('horn_messages', ignoreExpired: true) ??
        [];
    WidgetsBinding.instance.addObserver(this);
    AppConfig.instance.addListener(_configurationChanged);
    if (!widget.isPreview) _fetch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.of(context);
    _systemReduced = MediaQuery.disableAnimationsOf(context);
    _updateTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _updateTimer();
  }

  bool get _animate => !AppConfig.reduceMotion && !_systemReduced;
  void _configurationChanged() {
    if (_configuredReduced == AppConfig.reduceMotion) return;
    _configuredReduced = AppConfig.reduceMotion;
    if (mounted) setState(() {});
    _updateTimer();
  }

  void _updateTimer() {
    _timer?.cancel();
    _timer = null;
    if (!mounted ||
        widget.isPreview ||
        !_tickerEnabled ||
        !_resumed ||
        !_animate ||
        _messages.length < 2) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) setState(() => _index = (_index + 1) % _messages.length);
    });
  }

  Future<void> _fetch() async {
    final session = DioClient.sessionKey;
    try {
      final messages = await KlpbbsApi.getHornMessages();
      if (!mounted || session != DioClient.sessionKey) return;
      setState(() {
        _messages = messages;
        _index = 0;
        _error = null;
      });
      _updateTimer();
    } catch (_) {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _error = '广播暂时无法读取');
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AppConfig.instance.removeListener(_configurationChanged);
    super.dispose();
  }

  String _content(HornMessage message) =>
      (html.parseFragment(message.content).text ?? '').trim();

  Future<void> _open(HornMessage? message) async {
    if (widget.isPreview) return;
    if (message?.linkUrl?.isNotEmpty == true) {
      await UrlHelper.openLink(context, message!.linkUrl!);
    } else if (message != null) {
      await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
                title: Text(message.author.isEmpty ? '全站广播' : message.author),
                content: SingleChildScrollView(
                    child: SelectableText(_content(message))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'))
                ],
              ));
    } else {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const HornPostPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message =
        _messages.isEmpty ? null : _messages[_index % _messages.length];
    final title = widget.item.customParams['customTitle'] as String? ?? '全站小喇叭';
    final text = message == null
        ? _error ?? (widget.isPreview ? '暂无已获取的广播内容' : '暂无广播，点击查看发布入口')
        : _content(message);
    return RepaintBoundary(
        child: DashboardCardFrame(
      item: widget.item,
      padding: const EdgeInsets.all(12),
      onTap: () => _open(message),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxHeight < 90;
        final messageText = Text(text,
            key: ValueKey(message?.id ?? text),
            maxLines:
                compact ? 1 : (constraints.maxHeight / 24).floor().clamp(1, 5),
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(fontSize: 12, height: 1.45, color: scheme.onSurface));
        final content = AnimatedSwitcher(
            duration:
                _animate ? const Duration(milliseconds: 240) : Duration.zero,
            child: messageText);
        if (compact) {
          return Row(children: [
            Icon(Icons.campaign_outlined, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(child: content),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: scheme.outline),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.campaign_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
            if (_messages.length > 1)
              Text('${_index + 1}/${_messages.length}',
                  style: TextStyle(fontSize: 10, color: scheme.outline)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: scheme.outline),
          ]),
          const SizedBox(height: 8),
          if (message?.author.isNotEmpty == true &&
              constraints.maxHeight > 120) ...[
            Text(message!.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.primary)),
            const SizedBox(height: 4),
          ],
          Expanded(child: Align(alignment: Alignment.topLeft, child: content)),
          if (message?.timeText.isNotEmpty == true &&
              constraints.maxHeight > 145)
            Align(
                alignment: Alignment.centerRight,
                child: Text(message!.timeText,
                    maxLines: 1,
                    style: TextStyle(fontSize: 10, color: scheme.outline))),
        ]);
      }),
    ));
  }
}
