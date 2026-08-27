import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/write_confirm.dart';
import '../widgets/app_back_button.dart';

/// 注册页（支持 Discuz SecCode 验证码；真实 klpbbs 可能还需短信/邮箱）
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _seccodeCtrl = TextEditingController();

  bool _loading = false;
  bool _loadingSecCode = false;
  String? _error;

  String _formHash = '';
  String _seccodeHash = '';
  String _seccodeModid = '';
  Uint8List? _seccodeBytes;

  @override
  void initState() {
    super.initState();
    _refreshSecCode();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _emailCtrl.dispose();
    _seccodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshSecCode() async {
    setState(() => _loadingSecCode = true);
    try {
      final info = await KlpbbsApi.getRegisterSecCodeInfo();
      _formHash = info.formhash;
      _seccodeHash = info.seccodehash;
      _seccodeModid = info.seccodemodid;
      if (_seccodeHash.isNotEmpty) {
        final bytes = await KlpbbsApi.getSecCodeImageBytes(
          _seccodeHash,
          seccodemodid: _seccodeModid,
          referer: '${AppConfig.baseUrl}member.php?mod=register',
        );
        if (mounted) setState(() => _seccodeBytes = bytes);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSecCode = false);
    }
  }

  Future<void> _register() async {
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text;
    final p2 = _pass2Ctrl.text;
    final e = _emailCtrl.text.trim();
    final sc = _seccodeCtrl.text.trim();

    if (u.isEmpty || p.isEmpty || e.isEmpty) {
      setState(() => _error = '请填写用户名、密码和邮箱');
      return;
    }
    if (p != p2) {
      setState(() => _error = '两次密码不一致');
      return;
    }
    if (_seccodeHash.isNotEmpty && sc.isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }

    final confirmed = await confirmWrite(context, '注册');
    if (!confirmed || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final res = await KlpbbsApi.register(
        u,
        p,
        e,
        seccodeverify: sc,
        seccodehash: _seccodeHash,
        seccodemodid: _seccodeModid,
        formhash: _formHash,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      if (res.success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('注册成功，请登录')),
        );
        navigator.pop(true);
      } else {
        setState(() => _error = res.message);
        _refreshSecCode();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '注册异常：$e';
      });
      _refreshSecCode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('注册'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新验证码',
            onPressed: _refreshSecCode,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: '用户名',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pass2Ctrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '确认密码',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '邮箱',
                prefixIcon: Icon(Icons.mail_outline),
                border: OutlineInputBorder(),
              ),
            ),
            if (_seccodeHash.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _seccodeCtrl,
                      decoration: const InputDecoration(
                        labelText: '验证码',
                        prefixIcon: Icon(Icons.vpn_key_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _loadingSecCode ? null : _refreshSecCode,
                    child: _seccodeBytes != null
                        ? Image.memory(
                            _seccodeBytes!,
                            width: 110,
                            height: 44,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          )
                        : Container(
                            width: 110,
                            height: 44,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '点击图片刷新验证码',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '真实论坛（klpbbs）注册可能还需短信/邮箱验证，请在网页完成或联系管理员',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: _error == '注册成功，请登录'
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _register,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('注册'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
