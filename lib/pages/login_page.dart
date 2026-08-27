import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../widgets/app_back_button.dart';
import '../widgets/desktop_shortcuts.dart';
import 'web_login_page.dart';

/// 苦力怕论坛登录与注册认证中心（完美还原 Discuz 网页端登录、注册、验证码、安全提问与网页快捷授权）
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 登录表单控制器
  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();
  final _seccodeCtrl = TextEditingController();
  int _questionId = 0;
  bool _cookietime = true;
  bool _obscurePwd = true;

  // 注册表单控制器
  final _regUserCtrl = TextEditingController();
  final _regPwdCtrl = TextEditingController();
  final _regPwd2Ctrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regSecCodeCtrl = TextEditingController();
  bool _regObscurePwd = true;
  bool _agreeRules = true;

  // 状态与凭证
  bool _loading = false;
  bool _loadingSecCode = false;
  bool _loadingRegSecCode = false;
  bool _checkingWebAuth = false;
  String? _errorMessage;
  String? _formHash;
  String? _loginHash;
  String? _seccodeHash;
  String _seccodeModid = '';
  Uint8List? _seccodeBytes;

  // 注册凭证
  String? _regFormHash;
  String? _regSecCodeHash;
  String _regSecCodeModid = '';
  Uint8List? _regSecCodeBytes;

  static const _questions = [
    '安全提问 (未设置请忽略)',
    '母亲的名字',
    '爷爷的名字',
    '父亲出生的城市',
    '你其中一位老师的名字',
    '你个人计算机的型号',
    '你最喜欢的餐馆名称',
    '驾驶执照最后四位数字',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => _errorMessage = null);
        if (_tabController.index == 0 && _seccodeBytes == null) {
          _refreshSecCode();
        } else if (_tabController.index == 1 && _regSecCodeBytes == null) {
          _refreshRegSecCode();
        }
      }
    });
    _refreshSecCode();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _answerCtrl.dispose();
    _seccodeCtrl.dispose();
    _regUserCtrl.dispose();
    _regPwdCtrl.dispose();
    _regPwd2Ctrl.dispose();
    _regEmailCtrl.dispose();
    _regSecCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshSecCode() async {
    setState(() => _loadingSecCode = true);
    try {
      final info = await KlpbbsApi.getSecCodeInfo();
      _formHash = info.formhash;
      _loginHash = info.loginhash;
      _seccodeHash = info.seccodehash;
      _seccodeModid = info.seccodemodid;
      if (_seccodeHash != null && _seccodeHash!.isNotEmpty) {
        final bytes = await KlpbbsApi.getSecCodeImageBytes(
          _seccodeHash!,
          seccodemodid: _seccodeModid,
        );
        if (mounted) {
          setState(() {
            _seccodeBytes = bytes;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSecCode = false);
    }
  }

  Future<void> _refreshRegSecCode() async {
    setState(() => _loadingRegSecCode = true);
    try {
      final info = await KlpbbsApi.getRegisterSecCodeInfo();
      _regFormHash = info.formhash;
      _regSecCodeHash = info.seccodehash;
      _regSecCodeModid = info.seccodemodid;
      if (_regSecCodeHash != null && _regSecCodeHash!.isNotEmpty) {
        final bytes = await KlpbbsApi.getSecCodeImageBytes(
          _regSecCodeHash!,
          seccodemodid: _regSecCodeModid,
        );
        if (mounted) {
          setState(() {
            _regSecCodeBytes = bytes;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingRegSecCode = false);
    }
  }

  Future<void> _doLogin() async {
    final username = _userCtrl.text.trim();
    final password = _pwdCtrl.text.trim();
    final seccode = _seccodeCtrl.text.trim();
    final answer = _answerCtrl.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = '请输入论坛账号和密码');
      return;
    }

    if (_questionId > 0 && answer.isEmpty) {
      setState(() => _errorMessage = '请填写安全提问答案');
      return;
    }

    if (_seccodeHash != null && _seccodeHash!.isNotEmpty && seccode.isEmpty) {
      setState(() => _errorMessage = '请输入图形验证码');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await KlpbbsApi.login(
        username,
        password,
        seccodeverify: seccode,
        seccodehash: _seccodeHash,
        formhash: _formHash,
        loginhash: _loginHash,
        questionid: _questionId,
        answer: answer,
        cookietime: _cookietime,
      );

      if (mounted) {
        setState(() => _loading = false);
        if (res.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登录成功！欢迎回来')),
          );
          Navigator.of(context).pop(true);
        } else {
          setState(() => _errorMessage = res.message);
          _refreshSecCode();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = '登录异常：$e';
        });
        _refreshSecCode();
      }
    }
  }

  Future<void> _doRegister() async {
    final username = _regUserCtrl.text.trim();
    final password = _regPwdCtrl.text.trim();
    final password2 = _regPwd2Ctrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final seccode = _regSecCodeCtrl.text.trim();

    if (username.isEmpty || password.isEmpty || email.isEmpty) {
      setState(() => _errorMessage = '请完整填写用户名、密码和邮箱');
      return;
    }

    if (password != password2) {
      setState(() => _errorMessage = '两次输入的密码不一致');
      return;
    }

    if (!_agreeRules) {
      setState(() => _errorMessage = '请阅读并同意《论坛服务条款与使用协议》');
      return;
    }

    if (_regSecCodeHash != null && _regSecCodeHash!.isNotEmpty && seccode.isEmpty) {
      setState(() => _errorMessage = '请输入注册验证码');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await KlpbbsApi.register(
        username,
        password,
        email,
        seccodeverify: seccode,
        seccodehash: _regSecCodeHash,
        seccodemodid: _regSecCodeModid,
        formhash: _regFormHash,
      );

      if (mounted) {
        setState(() => _loading = false);
        if (res.success) {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('注册成功'),
              content: Text(res.message.isNotEmpty ? res.message : '恭喜，账号注册成功！现在可以直接登录。'),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _userCtrl.text = username;
                    _pwdCtrl.text = password;
                    _tabController.animateTo(0);
                  },
                  child: const Text('前往登录'),
                ),
              ],
            ),
          );
        } else {
          setState(() => _errorMessage = res.message);
          _refreshRegSecCode();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = '注册请求异常：$e';
        });
        _refreshRegSecCode();
      }
    }
  }

  Future<void> _openEmbeddedWebLogin({bool pcMode = false}) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WebLoginPage(initialPcMode: pcMode),
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openLostPassword() async {
    final uri = Uri.parse('${AppConfig.baseUrl}member.php?mod=logging&action=login&viewlostpw=1');
    if (await url_launcher.canLaunchUrl(uri)) {
      await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
    }
  }

  void _showManualCookieDialog() {
    final textCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动导入 Cookie / 会话凭证'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '如因特殊验证码或双重认证导致无法自动获取，可直接将浏览器的 Cookie 字符串粘贴在下方：',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '如: k2U_2132_auth=xxxx; k2U_2132_saltkey=yyyy; ...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = textCtrl.text.trim();
              if (raw.isEmpty) return;
              Navigator.of(ctx).pop();
              await DioClient.importCookieString(raw);
              final status = await KlpbbsApi.checkLoginStatus();
              if (!mounted) return;
              if (status.isLoggedIn || DioClient.isLoggedIn) {
                final uname = (status.username != null && status.username!.isNotEmpty)
                    ? status.username!
                    : '已登录';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Cookie 导入成功！已识别为「$uname」'),
                    backgroundColor: const Color(0xFF2E7D32),
                  ),
                );
                Navigator.of(context).pop(true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cookie 已保存，但未能识别有效登录态，请检查是否包含 auth 字段'),
                  ),
                );
              }
            },
            child: const Text('导入并登录'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkWebLoginStatus() async {
    setState(() {
      _checkingWebAuth = true;
      _errorMessage = null;
    });
    try {
      final status = await KlpbbsApi.checkLoginStatus();
      if (mounted) {
        setState(() => _checkingWebAuth = false);
        if (status.isLoggedIn || DioClient.isLoggedIn) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('网页登录凭证同步成功！已成功登录')),
          );
          Navigator.of(context).pop(true);
        } else {
          setState(() => _errorMessage = '尚未检测到网页端登录会话，请先通过内嵌网页登录成功后再同步');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkingWebAuth = false;
          _errorMessage = '检测登录态失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DesktopShortcutsWrapper(
      onRefresh: () {
        if (_tabController.index == 0) {
          _refreshSecCode();
        } else if (_tabController.index == 1) {
          _refreshRegSecCode();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('苦力怕论坛 账户认证'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新验证码 (F5)',
              onPressed: () {
                if (_tabController.index == 0) {
                  _refreshSecCode();
                } else if (_tabController.index == 1) {
                  _refreshRegSecCode();
                }
              },
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 1.5,
                shadowColor: theme.colorScheme.shadow.withAlpha(50),
                color: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(30),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 顶部 Logo
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.terrain_rounded,
                          color: Color(0xFF4CAF50),
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'klpbbs.com 苦力怕论坛',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 切换选项卡
                      TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: '账号登录'),
                          Tab(text: '新用户注册'),
                          Tab(text: '网页授权'),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (_errorMessage != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer.withAlpha(70),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.error.withAlpha(80),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // 表单区域
                      AnimatedBuilder(
                        animation: _tabController,
                        builder: (context, _) {
                          return switch (_tabController.index) {
                            0 => _buildPasswordLoginForm(theme),
                            1 => _buildRegisterForm(theme),
                            _ => _buildWebAuthForm(theme),
                          };
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordLoginForm(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _userCtrl,
          decoration: const InputDecoration(
            labelText: '用户名 / UID / 注册邮箱',
            prefixIcon: Icon(Icons.person_outline_rounded),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pwdCtrl,
          obscureText: _obscurePwd,
          decoration: InputDecoration(
            labelText: '登录密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePwd
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
            ),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),

        // 安全提问下拉菜单
        DropdownButtonFormField<int>(
          value: _questionId,
          decoration: const InputDecoration(
            labelText: '安全提问',
            prefixIcon: Icon(Icons.help_outline_rounded),
            isDense: true,
          ),
          items: List.generate(_questions.length, (i) {
            return DropdownMenuItem(
              value: i,
              child: Text(_questions[i], style: const TextStyle(fontSize: 13.5)),
            );
          }),
          onChanged: (v) => setState(() => _questionId = v ?? 0),
        ),
        if (_questionId > 0) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _answerCtrl,
            decoration: const InputDecoration(
              labelText: '安全提问答案',
              prefixIcon: Icon(Icons.question_answer_outlined),
              isDense: true,
            ),
          ),
        ],
        const SizedBox(height: 12),

        // 图形验证码
        if (_seccodeHash != null && _seccodeHash!.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _seccodeCtrl,
                  decoration: const InputDecoration(
                    labelText: '图形验证码',
                    prefixIcon: Icon(Icons.security_rounded),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _refreshSecCode,
                child: Tooltip(
                  message: '点击换一张验证码',
                  child: Container(
                    height: 48,
                    width: 120,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _loadingSecCode
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _seccodeBytes != null
                              ? Image.memory(
                                  _seccodeBytes!,
                                  fit: BoxFit.contain,
                                )
                              : const Center(
                                  child: Text('点击加载', style: TextStyle(fontSize: 11)),
                                ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        // 自动登录与找回密码
        Row(
          children: [
            Checkbox(
              value: _cookietime,
              onChanged: (v) => setState(() => _cookietime = v ?? true),
            ),
            const Text('记住登录状态 (30天)', style: TextStyle(fontSize: 13)),
            const Spacer(),
            TextButton(
              onPressed: _openLostPassword,
              child: const Text('找回密码', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 登录按钮
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton.icon(
            onPressed: _loading ? null : _doLogin,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(_loading ? '正在验证登录...' : '立即登录'),
          ),
        ),
        const SizedBox(height: 10),

        // 快捷网页内嵌登录
        SizedBox(
          width: double.infinity,
          height: 40,
          child: FilledButton.tonalIcon(
            onPressed: () => _openEmbeddedWebLogin(pcMode: false),
            icon: const Icon(Icons.language_rounded, size: 18),
            label: const Text('通过网页版内嵌登录 (支持扫码/滑动验证)'),
          ),
        ),
        const SizedBox(height: 10),

        // 底部注册入口
        Center(
          child: TextButton(
            onPressed: () => _tabController.animateTo(1),
            child: const Text('还没有论坛账号？立即免费注册'),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterForm(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _regUserCtrl,
          decoration: const InputDecoration(
            labelText: '用户名 (3-15个字符)',
            prefixIcon: Icon(Icons.person_add_outlined),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPwdCtrl,
          obscureText: _regObscurePwd,
          decoration: InputDecoration(
            labelText: '密码 (至少6位)',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _regObscurePwd ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
              onPressed: () => setState(() => _regObscurePwd = !_regObscurePwd),
            ),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPwd2Ctrl,
          obscureText: _regObscurePwd,
          decoration: const InputDecoration(
            labelText: '确认密码',
            prefixIcon: Icon(Icons.lock_reset_rounded),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: '安全电子邮箱',
            prefixIcon: Icon(Icons.email_outlined),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),

        // 注册图形验证码
        if (_regSecCodeHash != null && _regSecCodeHash!.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _regSecCodeCtrl,
                  decoration: const InputDecoration(
                    labelText: '图形验证码',
                    prefixIcon: Icon(Icons.security_rounded),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _refreshRegSecCode,
                child: Tooltip(
                  message: '点击换一张验证码',
                  child: Container(
                    height: 48,
                    width: 120,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _loadingRegSecCode
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _regSecCodeBytes != null
                              ? Image.memory(
                                  _regSecCodeBytes!,
                                  fit: BoxFit.contain,
                                )
                              : const Center(
                                  child: Text('点击加载', style: TextStyle(fontSize: 11)),
                                ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        // 协议同意
        Row(
          children: [
            Checkbox(
              value: _agreeRules,
              onChanged: (v) => setState(() => _agreeRules = v ?? true),
            ),
            const Expanded(
              child: Text(
                '我已阅读并同意《论坛使用协议与隐私条款》',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 注册按钮
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton.icon(
            onPressed: _loading ? null : _doRegister,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.app_registration_rounded),
            label: Text(_loading ? '正在提交注册...' : '立即注册账号'),
          ),
        ),
      ],
    );
  }

  Widget _buildWebAuthForm(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withAlpha(60),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.primary.withAlpha(40),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, color: colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '应用内置了完整的网页内嵌认证能力，支持手机版/电脑版界面、极验滑动验证、QQ/微信扫码快捷登录，登录成功后将自动嗅探并同步 Cookie 凭证。',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 手机版内嵌网页登录（推荐）
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: () => _openEmbeddedWebLogin(pcMode: false),
            icon: const Icon(Icons.phone_android_rounded),
            label: const Text('打开手机版内嵌网页登录 (推荐)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),

        // 电脑版内嵌网页登录
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton.tonalIcon(
            onPressed: () => _openEmbeddedWebLogin(pcMode: true),
            icon: const Icon(Icons.desktop_windows_rounded),
            label: const Text('打开电脑版内嵌网页登录 (适合扫码)'),
          ),
        ),
        const SizedBox(height: 12),

        // 手动导入 Cookie
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            onPressed: _showManualCookieDialog,
            icon: const Icon(Icons.vpn_key_outlined, size: 18),
            label: const Text('手动粘贴 Cookie 字符串登录'),
          ),
        ),
        const SizedBox(height: 14),
        const Divider(height: 16),
        const SizedBox(height: 4),

        // 手动检测与同步
        Row(
          children: [
            Expanded(
              child: Text(
                '如在已认证页面完成登录，可点击右侧立即检测并同步：',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _checkingWebAuth ? null : _checkWebLoginStatus,
              child: _checkingWebAuth
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('检测同步'),
            ),
          ],
        ),
      ],
    );
  }
}
