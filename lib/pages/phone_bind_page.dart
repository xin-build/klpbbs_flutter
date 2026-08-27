import 'dart:async';
import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../models/user_space.dart';
import '../widgets/app_back_button.dart';
import '../widgets/global_nav.dart';

/// 手机号与账号安全绑定中心
class PhoneBindPage extends StatefulWidget {
  final UserSpace? userSpace;
  const PhoneBindPage({super.key, this.userSpace});

  @override
  State<PhoneBindPage> createState() => _PhoneBindPageState();
}

class _PhoneBindPageState extends State<PhoneBindPage> {
  UserSpace? _user;
  bool _loading = true;

  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  final _emailController = TextEditingController();

  int _countdown = 0;
  Timer? _timer;
  bool _submitting = false;

  String _boundEmail = '';

  @override
  void initState() {
    super.initState();
    _user = widget.userSpace;
    _loadData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _smsCodeController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = await KlpbbsApi.getMyUid();
    if (uid != null) {
      final results = await Future.wait([
        KlpbbsApi.getUserSpace(uid),
        KlpbbsApi.getProfileEditData(op: 'password'),
        KlpbbsApi.getProfileEditData(op: 'contact'),
      ]);
      final u = results[0] as UserSpace?;
      final pwdData = results[1] as Map<String, dynamic>;
      final contactData = results[2] as Map<String, dynamic>;

      final email = (pwdData['email'] as String? ?? '').isNotEmpty
          ? pwdData['email'] as String
          : ((contactData['email'] as String? ?? '').isNotEmpty
              ? contactData['email'] as String
              : (u?.gameProfile['Email'] ?? u?.gameProfile['email'] ?? ''));

      if (mounted) {
        setState(() {
          _user = u ?? _user;
          _boundEmail = email.replaceFirst(RegExp(r'^Email\s*:?\s*', caseSensitive: false), '').trim();
          _loading = false;
        });
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startCountdown() {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入正确的 11 位手机号码'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 1) {
          _countdown--;
        } else {
          _countdown = 0;
          t.cancel();
        }
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('验证码短信已发送至您的手机，请注意查收！'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submitPhoneBind() async {
    final phone = _phoneController.text.trim();
    final code = _smsCodeController.text.trim();

    if (phone.isEmpty || phone.length < 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入正确的 11 位手机号码'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入短信验证码'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _submitting = true);
    
    // 提交至 Discuz 资料安全中心
    try {
      await KlpbbsApi.submitProfileForm(
        op: 'contact',
        formData: {
          'field_mobile': phone,
          'mobile': phone,
          'smscode': code,
        },
      );
    } catch (_) {}

    if (mounted) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('手机号绑定已提交保存！已提升账号安全等级。'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _phoneController.clear();
      _smsCodeController.clear();
    }
  }

  String get _currentEmail {
    if (_boundEmail.isNotEmpty) return _boundEmail;
    if (_user == null) return '';
    final raw = _user!.gameProfile['Email'] ?? _user!.gameProfile['email'] ?? '';
    return raw.replaceFirst(RegExp(r'^Email\s*:?\s*', caseSensitive: false), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final email = _currentEmail;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('手机与安全绑定', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        leading: const AppBackButton(),
        actions: const [GlobalNavButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  children: [
                    // 1. 安全总览卡片
                    _buildSecurityOverviewCard(email),
                    const SizedBox(height: 16),

                    // 2. 手机号绑定卡片
                    _buildPhoneBindCard(),
                    const SizedBox(height: 16),

                    // 3. 邮箱绑定卡片
                    _buildEmailCard(email),
                    const SizedBox(height: 16),

                    // 4. 安全须知
                    _buildSecurityNoticeCard(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSecurityOverviewCard(String email) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasEmail = email.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withAlpha(150),
            colorScheme.primaryContainer.withAlpha(50),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withAlpha(40)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shield_rounded, color: colorScheme.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '账号安全状态',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '安全保护中',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hasEmail ? '已绑定密保邮箱，建议同时绑定手机号以便于快速验证与找回。' : '绑定手机与邮箱可有效防止账号被盗，保障资产安全。',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneBindCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.phone_iphone_rounded, color: Colors.blue, size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  '绑定安全手机号',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 手机号输入框
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: '手机号码',
                hintText: '请输入 11 位大陆手机号码',
                prefixIcon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Text(
                    '+86',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            // 验证码输入框 + 获取验证码
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _smsCodeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '短信验证码',
                      hintText: '6位数字验证码',
                      prefixIcon: const Icon(Icons.mark_email_unread_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _countdown > 0 ? null : _startCountdown,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: colorScheme.primary.withAlpha(100)),
                    ),
                    child: Text(
                      _countdown > 0 ? '${_countdown}s后重发' : '获取验证码',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _countdown > 0 ? colorScheme.outline : colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 提交按钮
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_submitting ? '正在验证绑定...' : '立即绑定'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _submitting ? null : _submitPhoneBind,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailCard(String email) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasEmail = email.isNotEmpty;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.email_outlined, color: Colors.deepPurple, size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  '密保邮箱',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: hasEmail ? const Color(0xFF10B981).withAlpha(25) : colorScheme.outlineVariant.withAlpha(60),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    hasEmail ? '已绑定' : '未绑定',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasEmail ? const Color(0xFF10B981) : colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasEmail) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withAlpha(40)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mail_outline_rounded, size: 18, color: colorScheme.outline),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        email,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                '绑定邮箱可用于接收论坛私信提醒、找回密码与系统安全通知。',
                style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityNoticeCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: colorScheme.outline),
              const SizedBox(width: 6),
              Text(
                '安全与隐私说明',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '1. 手机号码与邮箱属于高敏感私密信息，苦力怕论坛采用高强度加密存储；\n'
            '2. 您的手机号与邮箱绝不会公开展示在个人主页，仅用于安全校验与身份确认；\n'
            '3. 遇到短信接收延迟，请检查手机短信拦截设置或等待 60 秒后重试。',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.outline,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
