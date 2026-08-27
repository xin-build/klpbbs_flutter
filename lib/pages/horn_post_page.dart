import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/write_confirm.dart';
import '../widgets/app_back_button.dart';
import '../widgets/global_nav.dart';

/// 小喇叭发布页（ahome_horn:add）
///
/// 逆向依据：mock-server/samples/horn_add.html（真实抓取，登录态）：
/// form action=plugin.php?id=ahome_horn:add，字段 formhash/fid/tid/fromurl/
/// ifsystem/hidename/color/boss/message/addsubmit；内置表情 smiles/{0-23}.png
/// 插入码 [s:{n}]。
class HornPostPage extends StatefulWidget {
  const HornPostPage({super.key});

  @override
  State<HornPostPage> createState() => _HornPostPageState();
}

class _HornPostPageState extends State<HornPostPage> {
  final _messageCtrl = TextEditingController();
  String _color = '';
  bool _boss = false;
  bool _loading = false;
  bool _loadingInfo = true;
  List<String> _colors = const [];
  static const _hornSmileCount = 24;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await KlpbbsApi.getHornPostInfo();
      if (mounted) {
        setState(() {
          _colors = info.colors;
          _loadingInfo = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  String _hornSmileUrl(int n) =>
      '${AppConfig.baseUrl}source/plugin/ahome_horn/image/smiles/$n.png';

  void _insertSmile(int n) {
    final t = _messageCtrl.text;
    final sel = _messageCtrl.selection;
    final start = sel.isValid ? sel.start : t.length;
    final code = '[s:$n]';
    final next = t.replaceRange(start, sel.isValid ? sel.end : start, code);
    _messageCtrl.text = next;
    _messageCtrl.selection = TextSelection.collapsed(
      offset: start + code.length,
    );
  }

  Future<void> _submit() async {
    final message = _messageCtrl.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入消息内容')));
      return;
    }
    final confirmed = await confirmWrite(context, '发布小喇叭');
    if (!confirmed || !mounted) return;
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await KlpbbsApi.postHorn(
        message: message,
        color: _color,
        boss: _boss,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? '小喇叭已发布' : '发布失败（未登录/真实论坛只读）')),
      );
      if (ok && mounted) Navigator.of(context).pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('发布异常：$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('发布小喇叭'),
        actions: [
          const GlobalNavButton(),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('发布'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loadingInfo) const LinearProgressIndicator(minHeight: 2),
          // 消息内容
          TextField(
            controller: _messageCtrl,
            maxLines: 4,
            maxLength: 240,
            decoration: InputDecoration(
              labelText: '消息内容',
              hintText: '说点什么吧（最多 240 字）',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 内置表情
          Text('内置表情', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var n = 0; n < _hornSmileCount; n++)
                InkWell(
                  onTap: () => _insertSmile(n),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(70),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: _hornSmileUrl(n),
                      width: 22,
                      height: 22,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) =>
                          Text('[s:$n]', style: const TextStyle(fontSize: 9)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // 文本颜色
          Text('文本颜色', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _colors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _parseColor(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: _color == c ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // 土豪霸屏
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('土豪霸屏（额外 1000 铁粒/天）'),
            subtitle: const Text('炫酷刷屏一天', style: TextStyle(fontSize: 12)),
            value: _boss,
            onChanged: (v) => setState(() => _boss = v),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    if (hex.isEmpty) return const Color(0xFF666666);
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) {
      final v = int.tryParse(h, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return const Color(0xFF666666);
  }
}
