import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/write_confirm.dart';
import '../widgets/global_nav.dart';
import 'func_list_page.dart';
import 'user_space_page.dart';

/// 动态表单字段模型（100% 严格对齐 Discuz 网页字段、隐私选项与实时数据）
class _ProfileField {
  final String label;
  final String name;
  final String type; // 'text', 'textarea', 'email', 'gender', 'birthday'
  final bool hasPrivacy;
  final String privacyName;
  String privacyValue; // '0' (公开), '1' (好友可见), '3' (保密)
  final TextEditingController controller;
  int gender;
  int? birthYear;
  int? birthMonth;
  int? birthDay;

  _ProfileField({
    required this.label,
    required this.name,
    String value = '',
    this.type = 'text',
    this.hasPrivacy = false,
    this.privacyName = '',
    this.privacyValue = '0',
    this.gender = 0,
    this.birthYear,
    this.birthMonth,
    this.birthDay,
  }) : controller = TextEditingController(text: value);

  void dispose() {
    controller.dispose();
  }
}

/// 资料设置 / 编辑资料页面（1:1 动态抓取与呈现 Discuz 3 大 Tab: 基本资料、游戏信息、个人信息）
class ProfileEditPage extends StatefulWidget {
  final int initialTabIndex;

  const ProfileEditPage({
    super.key,
    this.initialTabIndex = 1, // 默认进入游戏信息 Tab (对齐网页端截图)
  });

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 3 个 Tab 的动态字段列表: 0 -> 基本资料 (op=base), 1 -> 游戏信息 (op=contact), 2 -> 个人信息 (op=info)
  final List<List<_ProfileField>> _tabFields = [[], [], []];

  bool _loading = false;
  bool _fetchingInitial = true;
  int? _myUid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAllProfileData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final list in _tabFields) {
      for (final f in list) {
        f.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadAllProfileData() async {
    setState(() => _fetchingInitial = true);
    try {
      _myUid = await KlpbbsApi.getMyUid();

      // 并行拉取 Discuz 移动端 3 个 Tab 原生表单数据与空间兜底
      final baseFuture = KlpbbsApi.getProfileEditData(op: 'base');
      final contactFuture = KlpbbsApi.getProfileEditData(op: 'contact');
      final infoFuture = KlpbbsApi.getProfileEditData(op: 'info');
      final spaceFuture = _myUid != null && _myUid! > 0
          ? KlpbbsApi.getUserSpace(_myUid!)
          : Future.value(null);

      final results = await Future.wait([baseFuture, contactFuture, infoFuture, spaceFuture]);
      final baseData = results[0] as Map<String, dynamic>;
      final contactData = results[1] as Map<String, dynamic>;
      final infoData = results[2] as Map<String, dynamic>;
      final space = results[3] as dynamic;

      if (mounted) {
        setState(() {
          // 清理之前的字段
          for (final list in _tabFields) {
            for (final f in list) {
              f.dispose();
            }
            list.clear();
          }

          // 1. 基本资料 Tab (op=base)
          _tabFields[0] = _buildBaseFields(baseData, space);

          // 2. 游戏信息 Tab (op=contact)
          _tabFields[1] = _buildContactFields(contactData, space);

          // 3. 个人信息 Tab (op=info)
          _tabFields[2] = _buildInfoFields(infoData, space);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _fetchingInitial = false);
  }

  String _cleanLabel(String label, String name, int tabIndex) {
    if (label == '公开' || label == '保密' || label == '好友可见' || label.isEmpty || label == name) {
      if (name == 'field1') return '基岩版用户名';
      if (name == 'field2') return tabIndex == 1 ? '网易用户名' : '代表作';
      if (name == 'field3') return 'Java版用户名';
      if (name == 'field4') return 'Xbox ID';
      if (name == 'field8') return '代表作';
      if (name == 'customstatus') return '自定义头衔';
      if (name == 'sightml' || name == 'signature') return '个人签名';
      if (name == 'realname') return '真实姓名';
      if (name == 'gender') return '性别';
      if (name == 'birthday' || name == 'birthyear') return '生日';
      if (name == 'qq') return 'QQ';
      if (name == 'email') return 'Email';
    }
    return label;
  }

  List<_ProfileField> _buildBaseFields(Map<String, dynamic> data, dynamic space) {
    final list = <_ProfileField>[];
    final items = data['items'] as List<dynamic>? ?? [];

    if (items.isNotEmpty) {
      for (final it in items) {
        final m = it as Map<String, dynamic>;
        final name = m['name']?.toString() ?? '';
        final rawLabel = m['label']?.toString() ?? name;
        final label = _cleanLabel(rawLabel, name, 0);
        final val = m['value']?.toString() ?? '';
        final type = m['type']?.toString() ?? 'text';
        final hasPriv = m['hasPrivacy'] == true;
        final privName = m['privacyName']?.toString() ?? '';
        final privVal = m['privacyValue']?.toString() ?? '0';

        if (type == 'gender') {
          final g = int.tryParse(val) ?? (space?.gameProfile['性别'] == '男' ? 1 : (space?.gameProfile['性别'] == '女' ? 2 : 0));
          list.add(_ProfileField(
            label: label,
            name: name,
            type: 'gender',
            gender: g,
            hasPrivacy: hasPriv,
            privacyName: privName,
            privacyValue: privVal,
          ));
        } else if (type == 'birthday') {
          int? by, bm, bd;
          final bMatch = RegExp(r'(\\d{4})\\D+(\\d{1,2})\\D+(\\d{1,2})').firstMatch(val.isNotEmpty ? val : (space?.gameProfile['生日'] ?? ''));
          if (bMatch != null) {
            by = int.tryParse(bMatch.group(1)!);
            bm = int.tryParse(bMatch.group(2)!);
            bd = int.tryParse(bMatch.group(3)!);
          }
          list.add(_ProfileField(
            label: label,
            name: name,
            type: 'birthday',
            birthYear: by ?? data['birthYear'] as int?,
            birthMonth: bm ?? data['birthMonth'] as int?,
            birthDay: bd ?? data['birthDay'] as int?,
            hasPrivacy: hasPriv,
            privacyName: privName,
            privacyValue: privVal,
          ));
        } else {
          list.add(_ProfileField(
            label: label,
            name: name,
            value: val.isNotEmpty ? val : (space?.gameProfile[label] ?? ''),
            type: type,
            hasPrivacy: hasPriv,
            privacyName: privName,
            privacyValue: privVal,
          ));
        }
      }
    } else {
      // 缺省/兜底基本资料字段
      final customFields = data['customFields'] as Map<String, String>? ?? {};
      final privMap = data['fieldPrivacy'] as Map<String, String>? ?? {};

      list.add(_ProfileField(
        label: '真实姓名',
        name: 'realname',
        value: data['realname']?.toString() ?? customFields['realname'] ?? (space?.gameProfile['真实姓名'] ?? ''),
        hasPrivacy: true,
        privacyName: 'privacy[realname]',
        privacyValue: privMap['privacy[realname]'] ?? '0',
      ));

      final g = data['gender'] as int? ?? (space?.gameProfile['性别'] == '男' ? 1 : (space?.gameProfile['性别'] == '女' ? 2 : 0));
      list.add(_ProfileField(
        label: '性别',
        name: 'gender',
        type: 'gender',
        gender: g,
        hasPrivacy: true,
        privacyName: 'privacy[gender]',
        privacyValue: privMap['privacy[gender]'] ?? '0',
      ));

      int? by = data['birthYear'] as int?;
      int? bm = data['birthMonth'] as int?;
      int? bd = data['birthDay'] as int?;
      if (by == null && space != null) {
        final birth = space.gameProfile['生日'] ?? '';
        final bMatch = RegExp(r'(\\d{4})\\D+(\\d{1,2})\\D+(\\d{1,2})').firstMatch(birth);
        if (bMatch != null) {
          by = int.tryParse(bMatch.group(1)!);
          bm = int.tryParse(bMatch.group(2)!);
          bd = int.tryParse(bMatch.group(3)!);
        }
      }
      list.add(_ProfileField(
        label: '生日',
        name: 'birthday',
        type: 'birthday',
        birthYear: by,
        birthMonth: bm,
        birthDay: bd,
        hasPrivacy: true,
        privacyName: 'privacy[birthday]',
        privacyValue: privMap['privacy[birthday]'] ?? '0',
      ));
    }
    return list;
  }

  List<_ProfileField> _buildContactFields(Map<String, dynamic> data, dynamic space) {
    final list = <_ProfileField>[];
    final items = data['items'] as List<dynamic>? ?? [];

    if (items.isNotEmpty) {
      for (final it in items) {
        final m = it as Map<String, dynamic>;
        final name = m['name']?.toString() ?? '';
        final rawLabel = m['label']?.toString() ?? name;
        final label = _cleanLabel(rawLabel, name, 1);
        var val = m['value']?.toString() ?? '';
        final type = m['type']?.toString() ?? 'text';
        final hasPriv = m['hasPrivacy'] == true;
        final privName = m['privacyName']?.toString() ?? '';
        final privVal = m['privacyValue']?.toString() ?? '0';

        if (type == 'email' || name == 'email') {
          if (val.toLowerCase().startsWith('email')) {
            val = val.substring(5).trim();
          }
        }

        list.add(_ProfileField(
          label: label,
          name: name,
          value: val.isNotEmpty ? val : (space?.gameProfile[label] ?? ''),
          type: type,
          hasPrivacy: hasPriv,
          privacyName: privName,
          privacyValue: privVal,
        ));
      }
    } else {
      // 严格对齐网页实际字段: 基岩版用户名 (field1), 网易用户名 (field2), Java版用户名 (field3), Email (email)
      final customFields = data['customFields'] as Map<String, String>? ?? {};
      final privMap = data['fieldPrivacy'] as Map<String, String>? ?? {};

      list.add(_ProfileField(
        label: '基岩版用户名',
        name: 'field1',
        value: customFields['field1'] ?? (space?.gameProfile['基岩版用户名'] ?? ''),
        hasPrivacy: true,
        privacyName: 'privacy[field1]',
        privacyValue: privMap['privacy[field1]'] ?? '0',
      ));

      list.add(_ProfileField(
        label: '网易用户名',
        name: 'field2',
        value: customFields['field2'] ?? (space?.gameProfile['网易用户名'] ?? ''),
        hasPrivacy: true,
        privacyName: 'privacy[field2]',
        privacyValue: privMap['privacy[field2]'] ?? '3', // 默认保密
      ));

      list.add(_ProfileField(
        label: 'Java版用户名',
        name: 'field3',
        value: customFields['field3'] ?? (space?.gameProfile['Java版用户名'] ?? ''),
        hasPrivacy: true,
        privacyName: 'privacy[field3]',
        privacyValue: privMap['privacy[field3]'] ?? '0',
      ));

      var email = data['email']?.toString() ?? (space?.gameProfile['Email'] ?? '');
      if (email.toLowerCase().startsWith('email')) {
        email = email.substring(5).trim();
      }
      if (email.isNotEmpty) {
        list.add(_ProfileField(
          label: 'Email',
          name: 'email',
          value: email,
          type: 'email',
          hasPrivacy: false,
        ));
      }
    }
    return list;
  }

  List<_ProfileField> _buildInfoFields(Map<String, dynamic> data, dynamic space) {
    final list = <_ProfileField>[];
    final items = data['items'] as List<dynamic>? ?? [];

    if (items.isNotEmpty) {
      for (final it in items) {
        final m = it as Map<String, dynamic>;
        final name = m['name']?.toString() ?? '';
        final rawLabel = m['label']?.toString() ?? name;
        final label = _cleanLabel(rawLabel, name, 2);
        var val = m['value']?.toString() ?? '';
        final type = m['type']?.toString() ?? 'text';
        final hasPriv = m['hasPrivacy'] == true;
        final privName = m['privacyName']?.toString() ?? '';
        final privVal = m['privacyValue']?.toString() ?? '0';

        if (val.startsWith('高级链接')) {
          val = val.replaceFirst('高级链接', '').trim();
        }

        list.add(_ProfileField(
          label: label,
          name: name,
          value: val.isNotEmpty ? val : (space?.gameProfile[label] ?? (name == 'sightml' ? space?.signature : '') ?? ''),
          type: type,
          hasPrivacy: hasPriv,
          privacyName: privName,
          privacyValue: privVal,
        ));
      }
    } else {
      // 缺省/兜底个人信息字段
      final customFields = data['customFields'] as Map<String, String>? ?? {};
      final privMap = data['fieldPrivacy'] as Map<String, String>? ?? {};

      var repWork = customFields['field2'] ??
          customFields['field8'] ??
          (space?.gameProfile['代表作'] ?? '');
      if (repWork.startsWith('高级链接')) {
        repWork = repWork.replaceFirst('高级链接', '').trim();
      }
      list.add(_ProfileField(
        label: '代表作',
        name: customFields.containsKey('field8') ? 'field8' : 'field2',
        value: repWork,
        hasPrivacy: true,
        privacyName: customFields.containsKey('field8') ? 'privacy[field8]' : 'privacy[field2]',
        privacyValue: privMap['privacy[field8]'] ?? privMap['privacy[field2]'] ?? '0',
      ));

      final customStatus = data['customStatus']?.toString() ??
          (space?.gameProfile['自定义头衔'] ?? '');
      list.add(_ProfileField(
        label: '自定义头衔',
        name: 'customstatus',
        value: customStatus,
        hasPrivacy: false,
      ));

      final signature = data['signature']?.toString() ??
          (space?.signature ?? '');
      list.add(_ProfileField(
        label: '个人签名',
        name: 'sightml',
        value: signature,
        type: 'textarea',
        hasPrivacy: false,
      ));
    }
    return list;
  }

  Future<void> _submitCurrentTab() async {
    final confirmed = await confirmWrite(context, '保存资料设置');
    if (!confirmed || !mounted) return;

    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    final currentTab = _tabController.index;
    final op = currentTab == 0 ? 'base' : (currentTab == 1 ? 'contact' : 'info');
    final fields = _tabFields[currentTab];

    final formData = <String, String>{};
    for (final f in fields) {
      if (f.type == 'birthday') {
        if (f.birthYear != null) formData['birthyear'] = '${f.birthYear}';
        if (f.birthMonth != null) formData['birthmonth'] = '${f.birthMonth}';
        if (f.birthDay != null) formData['birthday'] = '${f.birthDay}';
      } else if (f.type == 'gender') {
        formData['gender'] = '${f.gender}';
      } else if (f.type != 'email') {
        formData[f.name] = f.controller.text.trim();
        if (f.name == 'sightml') {
          formData['signature'] = f.controller.text.trim();
        }
      }
      if (f.hasPrivacy && f.privacyName.isNotEmpty) {
        formData[f.privacyName] = f.privacyValue;
      }
    }

    try {
      final ok = await KlpbbsApi.submitProfileForm(op: op, formData: formData);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(ok ? Icons.check_circle_outline : Icons.info_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(ok ? '资料保存成功！' : '资料保存已提交，等待后台生效'),
              ],
            ),
            backgroundColor: ok ? Colors.green.shade700 : null,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        if (ok) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) Navigator.of(context).pop(true);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('保存异常：$e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          '资料设置',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: '我的空间',
            onPressed: () {
              if (_myUid != null && _myUid! > 0) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => UserSpacePage(uid: _myUid!)),
                );
              }
            },
          ),
          const GlobalNavButton(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(50), width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.primary,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              tabs: const [
                Tab(text: '基本资料'),
                Tab(text: '游戏信息'),
                Tab(text: '个人信息'),
              ],
            ),
          ),
        ),
      ),
      body: _fetchingInitial
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFieldsListTab(0),
                    _buildFieldsListTab(1),
                    _buildFieldsListTab(2),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _buildBottomActionBar(),
    );
  }

  Widget _buildBottomActionBar() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant.withAlpha(40)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(
                _loading ? '正在提交保存...' : '保存',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: (_loading || _fetchingInitial) ? null : _submitCurrentTab,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldsListTab(int tabIndex) {
    final fields = _tabFields[tabIndex];
    final tips = [
      '个人基本身份信息，可通过右侧权限选择公开或仅好友可见。',
      '绑定 Minecraft 及网易游戏 ID，让论坛其他冒险家随时找到你。',
      '展示您的优秀代表作、专属自定义头衔以及个性签名档。',
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        _buildTipBanner(tips[tabIndex]),
        const SizedBox(height: 12),
        for (int i = 0; i < fields.length; i++) ...[
          _buildFieldCard(fields[i]),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTipBanner(String tip) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withAlpha(40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.tips_and_updates_outlined, color: colorScheme.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForField(String label, String name) {
    if (label.contains('基岩') || name.contains('field1')) return Icons.sports_esports_rounded;
    if (label.contains('网易') || name.contains('field2')) return Icons.videogame_asset_rounded;
    if (label.contains('Java') || name.contains('field3')) return Icons.computer_rounded;
    if (label.toLowerCase().contains('email') || name == 'email') return Icons.alternate_email_rounded;
    if (label.contains('姓名') || name == 'realname') return Icons.badge_rounded;
    if (label.contains('性别') || name == 'gender') return Icons.wc_rounded;
    if (label.contains('生日') || name == 'birthday') return Icons.cake_rounded;
    if (label.contains('代表作') || name.contains('field8')) return Icons.star_rounded;
    if (label.contains('头衔') || name == 'customstatus') return Icons.military_tech_rounded;
    if (label.contains('签名') || name == 'sightml' || name == 'signature') return Icons.draw_rounded;
    if (label.contains('QQ') || name == 'qq') return Icons.chat_bubble_outline_rounded;
    return Icons.edit_note_rounded;
  }

  Color _getColorForField(String label, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (label.contains('基岩')) return const Color(0xFF2E7D32); // Emerald green
    if (label.contains('网易')) return const Color(0xFFEF6C00); // Vibrant orange
    if (label.contains('Java')) return const Color(0xFF1976D2); // Blue
    if (label.toLowerCase().contains('email')) return const Color(0xFF00796B); // Teal
    if (label.contains('姓名')) return const Color(0xFF00838F); // Cyan
    if (label.contains('性别')) return const Color(0xFF7B1FA2); // Purple
    if (label.contains('生日')) return const Color(0xFFE64A19); // Deep orange
    if (label.contains('代表作')) return const Color(0xFF512DA8); // Deep purple
    if (label.contains('头衔')) return const Color(0xFFF57F17); // Amber
    if (label.contains('QQ')) return const Color(0xFF3949AB); // Indigo
    return colorScheme.primary;
  }

  String _getHintForField(String label, String name) {
    if (label.contains('基岩')) return 'Minecraft 基岩版 Gamertag ID';
    if (label.contains('网易')) return '网易我的世界玩家用户名';
    if (label.contains('Java')) return 'Minecraft Java 正版玩家 ID';
    if (label.contains('代表作')) return '如: http://klpbbs.com/... 或作品名';
    if (label.contains('头衔')) return '展示在头像旁的个性荣誉头衔';
    if (label.contains('签名')) return '请输入个性签名，支持在帖子底部展示...';
    if (label.contains('真实姓名')) return '您的真实姓名或称呼';
    if (label.contains('QQ')) return '请输入联系 QQ 号码';
    return '请输入$label';
  }

  Widget _buildFieldCard(_ProfileField field) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = _getColorForField(field.label, context);
    final icon = _getIconForField(field.label, field.name);
    final hint = _getHintForField(field.label, field.name);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：图标 + 标题 + 右侧隐私胶囊选择器 / 修改按钮
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(22),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  field.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (field.hasPrivacy)
                _buildPrivacySelector(field),
              if (field.type == 'email')
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('修改', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FuncListPage(
                          title: '密码与安全邮箱',
                          path: 'home.php?mod=spacecp&ac=profile&op=password&mobile=2',
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 中部输入控制
          if (field.type == 'gender') ...[
            _buildGenderSegmentedButton(field),
          ] else if (field.type == 'birthday') ...[
            _buildBirthdaySelector(field),
          ] else if (field.type == 'email') ...[
            _buildEmailDisplayCard(field),
          ] else if (field.type == 'textarea') ...[
            TextField(
              controller: field.controller,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13.5, color: colorScheme.outline.withAlpha(150)),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withAlpha(35),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
          ] else ...[
            TextField(
              controller: field.controller,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13.5, color: colorScheme.outline.withAlpha(150)),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(50)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withAlpha(35),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGenderSegmentedButton(_ProfileField field) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        style: ButtonStyle(
          visualDensity: VisualDensity.comfortable,
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          side: WidgetStatePropertyAll(BorderSide(color: colorScheme.outlineVariant.withAlpha(60))),
        ),
        segments: const [
          ButtonSegment<int>(
            value: 0,
            label: Text('保密'),
            icon: Icon(Icons.visibility_off_outlined, size: 16),
          ),
          ButtonSegment<int>(
            value: 1,
            label: Text('男'),
            icon: Icon(Icons.male_rounded, size: 18),
          ),
          ButtonSegment<int>(
            value: 2,
            label: Text('女'),
            icon: Icon(Icons.female_rounded, size: 18),
          ),
        ],
        selected: {field.gender},
        onSelectionChanged: (set) {
          if (set.isNotEmpty) setState(() => field.gender = set.first);
        },
      ),
    );
  }

  Widget _buildEmailDisplayCard(_ProfileField field) {
    final colorScheme = Theme.of(context).colorScheme;
    final emailText = field.controller.text.isNotEmpty ? field.controller.text : '未绑定安全邮箱';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(
            field.controller.text.isNotEmpty ? Icons.verified_user_rounded : Icons.mail_outline_rounded,
            size: 18,
            color: field.controller.text.isNotEmpty ? Colors.teal : colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              emailText,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: field.controller.text.isNotEmpty ? colorScheme.onSurface : colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySelector(_ProfileField field) {
    final colorScheme = Theme.of(context).colorScheme;

    final isPublic = field.privacyValue == '0';
    final isFriend = field.privacyValue == '1';
    final iconColor = isPublic
        ? const Color(0xFF2E7D32)
        : (isFriend ? const Color(0xFF1976D2) : const Color(0xFFE64A19));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: iconColor.withAlpha(16),
        border: Border.all(color: iconColor.withAlpha(60)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: field.privacyValue,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down_rounded, size: 20, color: iconColor),
          style: TextStyle(
            fontSize: 12.5,
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          items: [
            DropdownMenuItem(
              value: '0',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.public_rounded, size: 14, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 6),
                  const Text('公开'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: '1',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_alt_rounded, size: 14, color: Color(0xFF1976D2)),
                  const SizedBox(width: 6),
                  const Text('好友'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: '3',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded, size: 14, color: Color(0xFFE64A19)),
                  const SizedBox(width: 6),
                  const Text('保密'),
                ],
              ),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => field.privacyValue = v);
          },
        ),
      ),
    );
  }

  Widget _buildBirthdaySelector(_ProfileField field) {
    final colorScheme = Theme.of(context).colorScheme;
    final years = [for (var y = 2026; y >= 1950; y--) y];
    final days = [for (var d = 1; d <= 31; d++) d];

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<int?>(
                value: field.birthYear,
                isDense: true,
                decoration: InputDecoration(
                  labelText: '年份',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('未选')),
                  for (final y in years) DropdownMenuItem(value: y, child: Text('$y 年')),
                ],
                onChanged: (v) => setState(() => field.birthYear = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int?>(
                value: field.birthMonth,
                isDense: true,
                decoration: InputDecoration(
                  labelText: '月份',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('未选')),
                  for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text('$m 月')),
                ],
                onChanged: (v) => setState(() => field.birthMonth = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int?>(
                value: field.birthDay,
                isDense: true,
                decoration: InputDecoration(
                  labelText: '日期',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('未选')),
                  for (final d in days) DropdownMenuItem(value: d, child: Text('$d 日')),
                ],
                onChanged: (v) => setState(() => field.birthDay = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.calendar_month_rounded, size: 16),
            label: const Text('从日历选择', style: TextStyle(fontSize: 12.5)),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: colorScheme.primary,
            ),
            onPressed: () async {
              final initialDate = DateTime(
                field.birthYear ?? 2000,
                field.birthMonth ?? 1,
                field.birthDay ?? 1,
              );
              final picked = await showDatePicker(
                context: context,
                initialDate: initialDate,
                firstDate: DateTime(1950),
                lastDate: DateTime(2026),
              );
              if (picked != null) {
                setState(() {
                  field.birthYear = picked.year;
                  field.birthMonth = picked.month;
                  field.birthDay = picked.day;
                });
              }
            },
          ),
        ),
      ],
    );
  }
}
