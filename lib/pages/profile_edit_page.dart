import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/write_confirm.dart';
import '../widgets/global_nav.dart';

/// 个人资料编辑（签名/性别/生日）
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _signatureCtrl = TextEditingController();
  final _customStatusCtrl = TextEditingController();
  final _bedrockUserCtrl = TextEditingController();
  final _repWorkCtrl = TextEditingController();
  int? _gender; // 0 保密 1 男 2 女
  int? _birthYear;
  int? _birthMonth;
  int? _birthDay;
  bool _loading = false;
  bool _fetchingInitial = true;
  String? _result;

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  Future<void> _loadCurrentProfile() async {
    try {
      final myUid = await KlpbbsApi.getMyUid();
      if (myUid != null && myUid > 0) {
        final space = await KlpbbsApi.getUserSpace(myUid);
        if (space != null && mounted) {
          setState(() {
            _signatureCtrl.text = space.signature;
            if (space.gameProfile.containsKey('自定义头衔')) {
              _customStatusCtrl.text = space.gameProfile['自定义头衔'] ?? '';
            }
            if (space.gameProfile.containsKey('基岩版用户名')) {
              _bedrockUserCtrl.text = space.gameProfile['基岩版用户名'] ?? '';
            }
            if (space.gameProfile.containsKey('代表作')) {
              _repWorkCtrl.text = space.gameProfile['代表作'] ?? '';
            }
            final g = space.gameProfile['性别'];
            if (g == '男') {
              _gender = 1;
            } else if (g == '女') {
              _gender = 2;
            } else {
              _gender = 0;
            }
            final birth = space.gameProfile['生日'] ?? '';
            final bMatch = RegExp(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(birth);
            if (bMatch != null) {
              _birthYear = int.tryParse(bMatch.group(1)!);
              _birthMonth = int.tryParse(bMatch.group(2)!);
              _birthDay = int.tryParse(bMatch.group(3)!);
            }
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _fetchingInitial = false);
  }

  @override
  void dispose() {
    _signatureCtrl.dispose();
    _customStatusCtrl.dispose();
    _bedrockUserCtrl.dispose();
    _repWorkCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final confirmed = await confirmWrite(context, '保存个人资料');
    if (!confirmed || !mounted) return;
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final ok = await KlpbbsApi.updateProfile(
        signature: _signatureCtrl.text.trim(),
        customStatus: _customStatusCtrl.text.trim(),
        bedrockUsername: _bedrockUserCtrl.text.trim(),
        representativeWork: _repWorkCtrl.text.trim(),
        gender: _gender,
        birthYear: _birthYear,
        birthMonth: _birthMonth,
        birthDay: _birthDay,
      );
      setState(() => _result = ok ? '保存成功' : '保存已提交');
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('个人资料保存成功')),
        );
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
    } catch (e) {
      setState(() => _result = '保存异常：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final years = [for (var y = 2026; y >= 1950; y--) y];
    final days = [for (var d = 1; d <= 31; d++) d];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF29B6F6),
        foregroundColor: Colors.white,
        title: const Text('编辑资料', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          const GlobalNavButton(),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0288D1),
              ),
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: _fetchingInitial
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
          // 个人签名
          TextField(
            controller: _signatureCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '个人签名',
              hintText: '展示在您的个人空间与帖子底部',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 自定义头衔
          TextField(
            controller: _customStatusCtrl,
            decoration: InputDecoration(
              labelText: '自定义头衔',
              hintText: '例如: We\'re no strangers to love',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 基岩版用户名
          TextField(
            controller: _bedrockUserCtrl,
            decoration: InputDecoration(
              labelText: '基岩版用户名',
              hintText: 'Minecraft 基岩版 Gamertag / Xbox ID',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 代表作
          TextField(
            controller: _repWorkCtrl,
            decoration: InputDecoration(
              labelText: '代表作',
              hintText: '您的原创模组、地图或知名作品链接/名称',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 性别
          Text('性别', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<int?>(
            segments: const [
              ButtonSegment(value: null, label: Text('保密')),
              ButtonSegment(value: 1, label: Text('♂ 男')),
              ButtonSegment(value: 2, label: Text('♀ 女')),
            ],
            selected: {_gender},
            onSelectionChanged: (s) => setState(() => _gender = s.first),
          ),
          const SizedBox(height: 18),

          // 生日
          Text('生日', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _birthYear,
                  decoration: const InputDecoration(labelText: '年'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('--')),
                    for (final y in years)
                      DropdownMenuItem(value: y, child: Text('$y')),
                  ],
                  onChanged: (v) => setState(() => _birthYear = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _birthMonth,
                  decoration: const InputDecoration(labelText: '月'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('--')),
                    for (var m = 1; m <= 12; m++)
                      DropdownMenuItem(value: m, child: Text('$m')),
                  ],
                  onChanged: (v) => setState(() => _birthMonth = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _birthDay,
                  decoration: const InputDecoration(labelText: '日'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('--')),
                    for (final d in days)
                      DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: (v) => setState(() => _birthDay = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_result != null)
            Text(
              _result!,
              style: TextStyle(
                fontSize: 13,
                color: _result == '保存成功' || _result == '保存已提交'
                    ? Colors.green
                    : theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
