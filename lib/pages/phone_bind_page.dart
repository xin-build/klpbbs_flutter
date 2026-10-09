import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../core/klpbbs_phone_binding.dart';
import '../models/user_space.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_motion.dart';

class PhoneBindPage extends StatefulWidget {
  final UserSpace? userSpace;
  const PhoneBindPage({super.key, this.userSpace});
  @override
  State<PhoneBindPage> createState() => _PhoneBindPageState();
}

class _PhoneBindPageState extends State<PhoneBindPage> {
  final _phone = TextEditingController(), _code = TextEditingController();
  PhoneBindingReceipt? _receipt;
  bool _loading = true, _busy = false, _editing = false;
  String? _error, _phoneError, _codeError;
  String _result = '';
  bool _resultSuccess = false;
  int _generation = 0, _remaining = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_onAccountChanged);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    DioClient.sessionChanges.removeListener(_onAccountChanged);
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onAccountChanged() {
    _timer?.cancel();
    _phone.clear();
    _code.clear();
    setState(() {
      _receipt = null;
      _remaining = 0;
      _busy = false;
      _result = '';
      _phoneError = _codeError = null;
    });
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation, session = DioClient.sessionKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final receipt = await KlpbbsApi.getPhoneBinding(expectedSession: session);
      if (!mounted ||
          generation != _generation ||
          session != DioClient.sessionKey) {
        return;
      }
      setState(() {
        _receipt = receipt;
        _editing = !receipt.binding.isBound;
        _remaining = KlpbbsApi.phoneCodeCooldown(receipt);
      });
      _startCountdown();
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          session == DioClient.sessionKey) {
        setState(() => _error = error
            .toString()
            .replaceFirst(RegExp(r'^(Bad state:|Exception:)\s*'), ''));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    if (_remaining == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final receipt = _receipt;
      if (!mounted ||
          receipt == null ||
          receipt.session != DioClient.sessionKey) {
        timer.cancel();
        return;
      }
      setState(() => _remaining = KlpbbsApi.phoneCodeCooldown(receipt));
      if (_remaining == 0) timer.cancel();
    });
  }

  Future<void> _submit({required bool sendCode}) async {
    final receipt = _receipt;
    if (receipt == null || _busy || _loading) return;
    final phone = _phone.text.trim(), code = _code.text.trim();
    setState(() {
      _phoneError = receipt.binding.validatePhone(phone);
      _codeError = sendCode ? null : receipt.binding.validateCode(code);
      _result = '';
    });
    if (_phoneError != null || _codeError != null) return;
    final generation = _generation, session = receipt.session;
    setState(() => _busy = true);
    try {
      final result = await KlpbbsApi.submitPhoneBinding(receipt, phone,
          code: sendCode ? null : code);
      if (!mounted ||
          generation != _generation ||
          session != DioClient.sessionKey) {
        return;
      }
      setState(() {
        _result = result.message;
        _resultSuccess = result.success;
        _remaining = KlpbbsApi.phoneCodeCooldown(receipt);
      });
      if (result.success && sendCode) _startCountdown();
      if (result.success && !sendCode) {
        _phone.clear();
        _code.clear();
        await _load();
      }
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          session == DioClient.sessionKey) {
        setState(() {
          _result = error
              .toString()
              .replaceFirst(RegExp(r'^(Bad state:|Exception:)\s*'), '');
          _resultSuccess = false;
        });
      }
    } finally {
      if (mounted && session == DioClient.sessionKey) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _bindingPanel(KlpbbsPhoneBinding binding) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return Card.filled(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20)),
                  child: Icon(Icons.phonelink_lock_rounded,
                      color: scheme.onPrimaryContainer, size: 28)),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(binding.isBound ? '手机已绑定' : '绑定手机号',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                        binding.isBound
                            ? binding.maskedPhone
                            : '验证手机号后解锁论坛对应功能',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ])),
              if (binding.isBound)
                Icon(Icons.verified_rounded, color: scheme.primary),
            ]),
            if (binding.boundAt.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('绑定时间 ${binding.boundAt}',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 24),
            AnimatedSize(
                duration: AppMotion.duration(context, 260),
                curve: AppMotion.emphasized,
                alignment: Alignment.topCenter,
                child: !_editing
                    ? OutlinedButton.icon(
                        key: const ValueKey('change-phone-binding'),
                        onPressed: _loading || _busy
                            ? null
                            : () => setState(() => _editing = true),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('更换手机号'))
                    : AutofillGroup(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                            TextField(
                                key: const ValueKey('binding-phone-input'),
                                controller: _phone,
                                enabled: !_busy && !_loading,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [
                                  AutofillHints.telephoneNumberNational
                                ],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(11)
                                ],
                                decoration: InputDecoration(
                                    labelText: binding.isBound ? '新手机号' : '手机号',
                                    hintText: '11 位中国大陆手机号',
                                    prefixIcon: const Icon(
                                        Icons.phone_android_outlined),
                                    errorText: _phoneError)),
                            const SizedBox(height: 20),
                            TextField(
                                key: const ValueKey('binding-code-input'),
                                controller: _code,
                                enabled: !_busy && !_loading,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [
                                  AutofillHints.oneTimeCode
                                ],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(
                                      binding.codeLength)
                                ],
                                onSubmitted: (_) => _submit(sendCode: false),
                                decoration: InputDecoration(
                                    labelText: '短信验证码',
                                    hintText: '${binding.codeLength} 位数字',
                                    prefixIcon: const Icon(Icons.sms_outlined),
                                    errorText: _codeError)),
                            const SizedBox(height: 14),
                            Wrap(spacing: 12, runSpacing: 12, children: [
                              OutlinedButton.icon(
                                  key: const ValueKey('send-phone-code'),
                                  onPressed: _busy || _loading || _remaining > 0
                                      ? null
                                      : () => _submit(sendCode: true),
                                  icon: const Icon(Icons.send_outlined),
                                  label: Text(_remaining > 0
                                      ? '$_remaining 秒后重发'
                                      : '获取验证码')),
                              FilledButton.icon(
                                  key: const ValueKey('verify-phone-code'),
                                  onPressed: _busy || _loading
                                      ? null
                                      : () => _submit(sendCode: false),
                                  icon: _busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: AppLoadingIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.check_rounded),
                                  label:
                                      Text(binding.isBound ? '确认更换' : '完成绑定')),
                              if (binding.isBound)
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                              _editing = false;
                                              _phone.clear();
                                              _code.clear();
                                              _phoneError = _codeError = null;
                                            }),
                                    child: const Text('取消更换')),
                            ]),
                          ]))),
          ]),
        ));
  }

  Widget _helpPanel(KlpbbsPhoneBinding binding) {
    final theme = Theme.of(context);
    return Card.outlined(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.sms_failed_outlined,
                color: theme.colorScheme.primary, size: 28),
            const SizedBox(height: 16),
            Text('短信验证帮助', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final text in binding.help)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SelectableText(text)),
            if (binding.help.isEmpty)
              Text('同一号码两次获取验证码至少间隔 ${binding.resendSeconds} 秒。收到后请尽快填写。'),
          ]),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme, binding = _receipt?.binding;
    return Scaffold(
      appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('手机绑定'),
          actions: [
            IconButton(
                onPressed: _busy || _loading ? null : _load,
                tooltip: '刷新绑定状态',
                icon: const Icon(Icons.refresh_rounded)),
          ]),
      body: RefreshIndicator(
          onRefresh: _busy ? () async {} : _load,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_loading)
                            const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: AppLoadingBar()),
                          if (_error != null)
                            Card.filled(
                                color: scheme.errorContainer,
                                child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SelectableText(_error!,
                                              style: TextStyle(
                                                  color:
                                                      scheme.onErrorContainer)),
                                          const SizedBox(height: 12),
                                          OutlinedButton.icon(
                                              onPressed:
                                                  _loading ? null : _load,
                                              icon: const Icon(
                                                  Icons.refresh_rounded),
                                              label: const Text('重新读取')),
                                        ]))),
                          if (_result.isNotEmpty) ...[
                            Card.filled(
                                color: _resultSuccess
                                    ? scheme.secondaryContainer
                                    : scheme.errorContainer,
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(children: [
                                      Icon(_resultSuccess
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.info_outline_rounded),
                                      const SizedBox(width: 12),
                                      Expanded(child: SelectableText(_result)),
                                    ]))),
                            const SizedBox(height: 16),
                          ],
                          if (binding != null)
                            LayoutBuilder(
                                builder: (context, constraints) =>
                                    constraints.maxWidth >= 850
                                        ? Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                                Expanded(
                                                    flex: 3,
                                                    child:
                                                        _bindingPanel(binding)),
                                                const SizedBox(width: 24),
                                                Expanded(
                                                    flex: 2,
                                                    child: _helpPanel(binding)),
                                              ])
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                                _bindingPanel(binding),
                                                const SizedBox(height: 20),
                                                _helpPanel(binding),
                                              ])),
                        ]))),
          ])),
    );
  }
}
