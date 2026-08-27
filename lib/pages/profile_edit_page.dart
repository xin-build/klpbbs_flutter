import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/write_confirm.dart';
import '../models/user_space.dart';
import '../widgets/global_nav.dart';
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
  final UserSpace? initialUser;

  const ProfileEditPage({
    super.key,
    this.initialTabIndex = 1, // 默认进入游戏信息 Tab (对齐网页端习惯)
    this.initialUser,
  });

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 3 个 Tab 的字段列表: 0 -> 基本资料, 1 -> 游戏信息, 2 -> 个人信息
  final List<List<_ProfileField>> _tabFields = [[], [], []];

  bool _loading = false;
  int? _myUid;
  UserSpace? _user;

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );

    // 1. 立即根据初始用户资料初始化 3 大 Tab 字段（零延迟、防空白）
    _initDefaultFields(_user);

    // 2. 异步后台网络增量刷新与校验
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

  /// 立即构建 3 个 Tab 的标准字段（防止网络未返回时出现空白页）
  void _initDefaultFields(UserSpace? space) {
    for (final list in _tabFields) {
      for (final f in list) {
        f.dispose();
      }
      list.clear();
    }

    final gp = space?.gameProfile ?? {};
    final sig = space?.signature ?? '';

    // --- Tab 0: 基本资料 (op=base) ---
    int genderVal = 0;
    if (gp['性别'] == '男') genderVal = 1;
    if (gp['性别'] == '女') genderVal = 2;

    int? bYear, bMonth, bDay;
    final birthStr = gp['生日'] ?? gp['出生日期'] ?? '';
    final bMatch = RegExp(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(birthStr);
    if (bMatch != null) {
      bYear = int.tryParse(bMatch.group(1)!);
      bMonth = int.tryParse(bMatch.group(2)!);
      bDay = int.tryParse(bMatch.group(3)!);
    }

    _tabFields[0] = [
      _ProfileField(
        label: '真实姓名',
        name: 'realname',
        value: gp['真实姓名'] ?? '',
        hasPrivacy: true,
        privacyName: 'privacy[realname]',
        privacyValue: '0',
      ),
      _ProfileField(
        label: '性别',
        name: 'gender',
        type: 'gender',
        gender: genderVal,
        hasPrivacy: true,
        privacyName: 'privacy[gender]',
        privacyValue: '0',
      ),
      _ProfileField(
        label: '生日',
        name: 'birthday',
        type: 'birthday',
        birthYear: bYear,
        birthMonth: bMonth,
        birthDay: bDay,
        hasPrivacy: true,
        privacyName: 'privacy[birthday]',
        privacyValue: '0',
      ),
      _ProfileField(
        label: '自定义头衔',
        name: 'customstatus',
        value: gp['自定义头衔'] ?? gp['头衔'] ?? '',
        hasPrivacy: false,
      ),
      _ProfileField(
        label: '个人签名',
        name: 'sightml',
        value: sig,
        type: 'textarea',
        hasPrivacy: false,
      ),
    ];

    // --- Tab 1: 游戏信息 (op=contact) ---
    var emailVal = gp['Email'] ?? gp['email'] ?? gp['邮箱'] ?? '';
    if (emailVal.toLowerCase().startsWith('email')) {
      emailVal = emailVal.replaceFirst(RegExp(r'^email\s*:?\s*', caseSensitive: false), '').trim();
    }

    _tabFields[1] = [
      _ProfileField(
        label: '基岩版用户名',
        name: 'field1',
        value: gp['基岩版用户名'] ?? gp['Minecraft 基岩版 ID'] ?? '',
        hasPrivacy: true,
        privacyName: 'privacy[field1]',
        privacyValue: '0',
      ),
      _ProfileField(
        label: '网易用户名',
        name: 'field2',
        value: gp['网易用户名'] ?? gp['网易版 ID'] ?? '',
        hasPrivacy: true,
        privacyName: 'privacy[field2]',
        privacyValue: '3', // 默认保密
      ),
      _ProfileField(
        label: 'Java版用户名',
        name: 'field3',
        value: gp['Java版用户名'] ?? gp['Minecraft Java 正版玩家 ID'] ?? '',
        hasPrivacy: true,
        privacyName: 'privacy[field3]',
        privacyValue: '0',
      ),
      _ProfileField(
        label: 'Xbox ID',
        name: 'field4',
        value: gp['Xbox ID'] ?? gp['Xbox Gamertag'] ?? '',
        hasPrivacy: true,
        privacyName: 'privacy[field4]',
        privacyValue: '0',
      ),
      _ProfileField(
        label: '绑定邮箱',
        name: 'email',
        value: emailVal,
        type: 'email',
        hasPrivacy: false,
      ),
    ];

    // --- Tab 2: 个人信息 (op=info) ---
    var repWork = gp['代表作'] ?? '';
    if (repWork.startsWith('高级链接')) {
      repWork = repWork.replaceFirst('高级链接', '').trim();
    }

    _tabFields[2] = [
      _ProfileField(
        label: '代表作',
        name: 'field8',
        value: repWork,
        hasPrivacy: true,
        privacyName: 'privacy[field8]',
        privacyValue: '0',
      ),
      _ProfileField(
        label: 'QQ 号码',
        name: 'qq',
        value: gp['QQ'] ?? gp['qq'] ?? '',
        hasPrivacy: true,
        privacyName: 'privacy[qq]',
        privacyValue: '1', // 默认好友可见
      ),
      _ProfileField(
        label: '自定义头衔',
        name: 'customstatus',
        value: gp['自定义头衔'] ?? gp['头衔'] ?? '',
        hasPrivacy: false,
      ),
      _ProfileField(
        label: '个人签名',
        name: 'sightml',
        value: sig,
        type: 'textarea',
        hasPrivacy: false,
      ),
    ];
  }

  Future<void> _loadAllProfileData() async {
    try {
      _myUid = await KlpbbsApi.getMyUid();

      final spaceFuture = _myUid != null && _myUid! > 0
          ? KlpbbsApi.getUserSpace(_myUid!)
          : Future.value(null);
      final baseFuture = KlpbbsApi.getProfileEditData(op: 'base');
      final contactFuture = KlpbbsApi.getProfileEditData(op: 'contact');
      final infoFuture = KlpbbsApi.getProfileEditData(op: 'info');

      final results = await Future.wait([spaceFuture, baseFuture, contactFuture, infoFuture]);
      final space = results[0] as UserSpace?;
      final baseData = results[1] as Map<String, dynamic>;
      final contactData = results[2] as Map<String, dynamic>;
      final infoData = results[3] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _user = space ?? _user;
          // 用最新拉取到的网络数据更新字段
          _updateFieldValues(0, baseData, _user);
          _updateFieldValues(1, contactData, _user);
          _updateFieldValues(2, infoData, _user);
        });
      }
    } catch (_) {}
  }

  void _updateFieldValues(int tabIndex, Map<String, dynamic> data, UserSpace? space) {
    final fields = _tabFields[tabIndex];
    final customFields = data['customFields'] as Map<String, String>? ?? {};
    final privMap = data['fieldPrivacy'] as Map<String, String>? ?? {};
    final gp = space?.gameProfile ?? {};

    for (final f in fields) {
      // 1. 更新隐私值
      if (f.hasPrivacy && f.privacyName.isNotEmpty) {
        if (privMap.containsKey(f.privacyName)) {
          f.privacyValue = privMap[f.privacyName]!;
        }
      }

      // 2. 更新字段文本值（若当前为空则补全）
      if (f.controller.text.isEmpty) {
        if (f.name == 'realname') {
          f.controller.text = data['realname']?.toString() ?? customFields['realname'] ?? gp['真实姓名'] ?? '';
        } else if (f.name == 'customstatus') {
          f.controller.text = data['customStatus']?.toString() ?? gp['自定义头衔'] ?? gp['头衔'] ?? '';
        } else if (f.name == 'sightml' || f.name == 'signature') {
          f.controller.text = data['signature']?.toString() ?? space?.signature ?? '';
        } else if (customFields.containsKey(f.name)) {
          f.controller.text = customFields[f.name]!;
        } else if (gp.containsKey(f.label)) {
          f.controller.text = gp[f.label]!;
        }
      }

      // 3. 更新特殊控件值
      if (f.type == 'gender') {
        final g = data['gender'] as int?;
        if (g != null && g > 0) f.gender = g;
      } else if (f.type == 'birthday') {
        final by = data['birthYear'] as int?;
        final bm = data['birthMonth'] as int?;
        final bd = data['birthDay'] as int?;
        if (by != null) f.birthYear = by;
        if (bm != null) f.birthMonth = bm;
        if (bd != null) f.birthDay = bd;
      }
    }
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
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: '我的空间',
            onPressed: () {
              final uid = _myUid ?? _user?.uid;
              if (uid != null && uid > 0) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => UserSpacePage(uid: uid)),
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFieldsListTab(0),
          _buildFieldsListTab(1),
          _buildFieldsListTab(2),
        ],
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
                _loading ? '正在提交保存...' : '保存修改',
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
              onPressed: _loading ? null : _submitCurrentTab,
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTipBanner(tips[tabIndex]),
              const SizedBox(height: 12),
              for (int i = 0; i < fields.length; i++) ...[
                _buildFieldCard(fields[i]),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
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
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldCard(_ProfileField field) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 字段头部：Label + 隐私选择器
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                field.label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (field.hasPrivacy) _buildPrivacyBadgeDropdown(field),
            ],
          ),
          const SizedBox(height: 10),

          // 字段核心输入控件
          if (field.type == 'gender')
            _buildGenderSelector(field)
          else if (field.type == 'birthday')
            _buildBirthdayPicker(field)
          else if (field.type == 'email')
            _buildEmailReadOnlyTile(field)
          else if (field.type == 'textarea')
            TextField(
              controller: field.controller,
              maxLines: 4,
              minLines: 3,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '请输入${field.label}',
                filled: true,
                fillColor: colorScheme.surface,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
                ),
              ),
            )
          else
            TextField(
              controller: field.controller,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '请输入${field.label}',
                filled: true,
                fillColor: colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(60)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrivacyBadgeDropdown(_ProfileField field) {
    final colorScheme = Theme.of(context).colorScheme;
    final privMap = {'0': '公开', '1': '好友可见', '3': '保密'};

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: privMap.containsKey(field.privacyValue) ? field.privacyValue : '0',
          icon: Icon(Icons.arrow_drop_down_rounded, size: 18, color: colorScheme.outline),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
          items: const [
            DropdownMenuItem(value: '0', child: Text('公开')),
            DropdownMenuItem(value: '1', child: Text('好友可见')),
            DropdownMenuItem(value: '3', child: Text('保密')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => field.privacyValue = val);
            }
          },
        ),
      ),
    );
  }

  Widget _buildGenderSelector(_ProfileField field) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        _buildGenderRadioItem(field, 0, '保密', Icons.lock_outline_rounded, colorScheme.outline),
        const SizedBox(width: 12),
        _buildGenderRadioItem(field, 1, '男', Icons.male_rounded, Colors.blue),
        const SizedBox(width: 12),
        _buildGenderRadioItem(field, 2, '女', Icons.female_rounded, Colors.pink),
      ],
    );
  }

  Widget _buildGenderRadioItem(_ProfileField field, int value, String label, IconData icon, Color activeColor) {
    final selected = field.gender == value;
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => field.gender = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? activeColor.withAlpha(20) : colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? activeColor : colorScheme.outlineVariant.withAlpha(60),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? activeColor : colorScheme.outline),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? activeColor : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBirthdayPicker(_ProfileField field) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDate = field.birthYear != null && field.birthMonth != null && field.birthDay != null;
    final text = hasDate ? '${field.birthYear} 年 ${field.birthMonth} 月 ${field.birthDay} 日' : '选择出生年月日';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final initial = DateTime(
          field.birthYear ?? 2000,
          field.birthMonth ?? 1,
          field.birthDay ?? 1,
        );
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(1950),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          setState(() {
            field.birthYear = picked.year;
            field.birthMonth = picked.month;
            field.birthDay = picked.day;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
        ),
        child: Row(
          children: [
            Icon(Icons.cake_outlined, size: 18, color: colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasDate ? FontWeight.w600 : FontWeight.normal,
                  color: hasDate ? colorScheme.onSurface : colorScheme.outline,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailReadOnlyTile(_ProfileField field) {
    final colorScheme = Theme.of(context).colorScheme;
    final email = field.controller.text.isNotEmpty ? field.controller.text : '未绑定邮箱';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(Icons.mark_email_read_outlined, size: 18, color: colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              email,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('已验证', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}
