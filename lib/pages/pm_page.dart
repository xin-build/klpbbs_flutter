import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../widgets/app_back_button.dart';
import '../widgets/global_nav.dart';

/// 私信发送页（本地测试环境可写）
class PmPage extends StatefulWidget {
  final int touid;
  final String toName;

  const PmPage({super.key, required this.touid, required this.toName});

  @override
  State<PmPage> createState() => _PmPageState();
}

class _PmPageState extends State<PmPage> {
  final _contentCtrl = TextEditingController();
  bool _loading = false;
  String? _result;

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      setState(() => _result = '请输入内容');
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final ok = await KlpbbsApi.sendPm(widget.touid, content);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = ok ? '发送成功' : '发送失败（请检查登录态/对方设置）';
      });
      if (ok) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = '发送异常：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text('私信给 ${widget.toName}'),
        actions: const [GlobalNavButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _contentCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: '消息内容',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 8),
              Text(
                _result!,
                style: TextStyle(
                  color: _result == '发送成功' ? Colors.green : Colors.red,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _send,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('发送'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
