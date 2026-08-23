import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';
import 'profile_settings_page.dart';

/// 苦力怕论坛头像挂件数据模型（对齐 Discuz sunju_facemall 插件规范）
class FacemallItem {
  final String id;
  final String name;
  final String desc;
  final String frameUrl;
  final String priceText;
  final int priceCredit;
  final String creditType;
  final String validity;
  final String category; // 默认, 二次元, 我的世界, 综合, 其他
  final bool isFree;

  const FacemallItem({
    required this.id,
    required this.name,
    required this.desc,
    required this.frameUrl,
    required this.priceText,
    this.priceCredit = 0,
    this.creditType = '铁粒',
    this.validity = '永久有效',
    this.category = '默认',
    this.isFree = false,
  });
}

/// 苦力怕论坛头像挂件中心（1:1 深度复刻 KLPBBS 网页端 sunju_facemall:face 视觉与交互）
class FacemallPage extends StatefulWidget {
  final int? uid;
  final String? username;
  final String? avatarUrl;

  const FacemallPage({
    super.key,
    this.uid,
    this.username,
    this.avatarUrl,
  });

  @override
  State<FacemallPage> createState() => _FacemallPageState();
}

class _FacemallPageState extends State<FacemallPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentUid = 0;
  String _currentUsername = '坛友';
  String? _equippedFrameId;
  String? _formhash;
  bool _initialLoading = true;
  bool _loadingCategory = false;
  bool _loadingMyPendants = false;
  bool _loadingPayList = false;

  List<(int, String)> _categories = [
    (1, '默认'),
    (2, '二次元'),
    (3, '我的世界'),
    (4, '综合'),
    (5, '其他'),
  ];
  late (int, String) _selectedCategory;
  final Map<int, List<FacemallItem>> _categoryItemsMap = {};
  List<Map<String, dynamic>> _myPendants = [];
  List<Map<String, dynamic>> _payList = [];

  @override
  void initState() {
    super.initState();
    _selectedCategory = _categories.first;
    _equippedFrameId = null; // 默认不要带挂件
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _initUser();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1) {
      _loadMyPendants();
    } else if (_tabController.index == 2) {
      _loadPayList();
    }
  }

  Future<void> _initUser() async {
    final myUid = widget.uid ?? await KlpbbsApi.getMyUid();
    if (myUid != null && mounted) {
      setState(() {
        _currentUid = myUid;
        _currentUsername = widget.username ?? '坛友';
      });
    }

    // 1. 实时拉取官方 sunju_facemall 页面初始化数据（当前挂件、分类、首屏商品）
    try {
      final initData = await KlpbbsApi.getFacemallInitData();
      if (!mounted) return;

      if (initData.formhash != null && initData.formhash!.isNotEmpty) {
        _formhash = initData.formhash;
      }

      if (initData.categories.isNotEmpty) {
        setState(() {
          _categories = initData.categories;
          if (!_categories.any((c) => c.$1 == _selectedCategory.$1)) {
            _selectedCategory = _categories.first;
          }
        });
      }

      if (initData.myFaceUrl != null && initData.myFaceUrl!.isNotEmpty && initData.myFaceUrl != 'none') {
        await AppConfig.setMyFaceUrl(initData.myFaceUrl);
        setState(() {
          _equippedFrameId = initData.myFaceUrl;
        });
      } else {
        await AppConfig.setMyFaceUrl(null);
        setState(() {
          _equippedFrameId = null;
        });
      }

      if (initData.initialItems.isNotEmpty) {
        final firstList = initData.initialItems.map((m) => FacemallItem(
          id: m['id'] ?? '',
          name: m['title'] ?? '',
          desc: '${m['title']} 论坛专属头像挂件',
          frameUrl: m['img'] ?? '',
          priceText: m['price'] == '0' || m['price'] == '' ? '免费' : '${m['price']} 铁粒',
          priceCredit: int.tryParse(m['price'] ?? '0') ?? 0,
          isFree: m['price'] == '0' || m['price'] == '',
          category: _categories.first.$2,
        )).toList();
        setState(() {
          _categoryItemsMap[_categories.first.$1] = firstList;
        });
      }
    } catch (_) {}

    // 2. 初始数据已就绪，立即呈现（与网页端单次 GET 请求速度对齐）
    if (mounted) {
      setState(() => _initialLoading = false);
    }

    // 3. 若首屏分类尚未缓存，则异步补齐
    if (!_categoryItemsMap.containsKey(_selectedCategory.$1)) {
      await _loadCategoryItems(_selectedCategory.$1);
    }
  }

  /// 动态从官方 AJAX 接口拉取指定分类下的真实商品列表
  Future<void> _loadCategoryItems(int cateId) async {
    setState(() => _loadingCategory = true);
    try {
      final liveList = await KlpbbsApi.getFacemallCategoryItems(cateId, formhash: _formhash);
      if (!mounted) return;
      if (liveList.isNotEmpty) {
        final mapped = liveList.map((m) => FacemallItem(
          id: m['id'] ?? '',
          name: m['title'] ?? '',
          desc: '${m['title']} 论坛专属头像挂件',
          frameUrl: m['img'] ?? '',
          priceText: m['price'] == '0' || m['price'] == '' ? '免费' : '${m['price']} 铁粒',
          priceCredit: int.tryParse(m['price'] ?? '0') ?? 0,
          isFree: m['price'] == '0' || m['price'] == '',
          category: _selectedCategory.$2,
        )).toList();

        setState(() {
          _categoryItemsMap[cateId] = mapped;
          _loadingCategory = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _loadingCategory = false);
    }
  }

  /// 动态从官方接口拉取我的挂件列表
  Future<void> _loadMyPendants() async {
    setState(() => _loadingMyPendants = true);
    try {
      final list = await KlpbbsApi.getMyFacemallList(formhash: _formhash);
      if (!mounted) return;
      setState(() {
        _myPendants = list;
        _loadingMyPendants = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMyPendants = false);
    }
  }

  /// 动态从官方接口拉取激活记录
  Future<void> _loadPayList() async {
    setState(() => _loadingPayList = true);
    try {
      final list = await KlpbbsApi.getFacemallPayList(formhash: _formhash);
      if (!mounted) return;
      setState(() {
        _payList = list;
        _loadingPayList = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPayList = false);
    }
  }

  Future<void> _unequipPendant() async {
    await KlpbbsApi.dropFacemall();
    await AppConfig.setMyFaceUrl(null, frameId: null);
    if (!mounted) return;
    setState(() {
      _equippedFrameId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已向服务器提交卸下头像挂件请求'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _equipPendant(FacemallItem item) async {
    await KlpbbsApi.setFacemall(item.id, frameUrl: item.frameUrl);
    await AppConfig.setMyFaceUrl(item.frameUrl, frameId: item.id);
    if (!mounted) return;
    setState(() {
      _equippedFrameId = item.id;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已成功向服务器佩戴「${item.name}」头像挂件！'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 1:1 复刻截图四官方购买/佩戴对话框
  void _showPendantDialog(FacemallItem item) {
    int selectedDays = 30;
    bool equipNow = true;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final unitPrice = item.priceCredit > 0 ? item.priceCredit : 50;
          final multiplier = selectedDays == 30 ? 1 : (selectedDays == 90 ? 2.5 : (selectedDays == 360 ? 8 : 1));
          final totalPrice = (unitPrice * multiplier).round();

          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Stack(
                children: [
                  // 右上角关闭按钮 (X)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF8C8C8C), size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 顶部大头像与挂件预览 (官方 1.75x 比例)
                        UserAvatarWidget(
                          uid: _currentUid > 0 ? _currentUid : null,
                          author: _currentUsername,
                          size: 80,
                          faceUrl: item.frameUrl,
                        ),
                        const SizedBox(height: 14),

                        // 挂件名称
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF262626),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 购买天数
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '购买天数',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 天数选择标签组
                        Row(
                          children: [
                            for (final d in [30, 90, 360, 0]) ...[
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () => setModalState(() => selectedDays = d),
                                    child: Container(
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: selectedDays == d ? const Color(0xFFE6F7FF) : Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: selectedDays == d ? const Color(0xFF1890FF) : const Color(0xFFD9D9D9),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        d > 0 ? '$d天' : '自定义',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: selectedDays == d ? const Color(0xFF1890FF) : const Color(0xFF595959),
                                          fontWeight: selectedDays == d ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 铁粒兑换胶囊
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F7FF),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF1890FF)),
                            ),
                            child: const Text(
                              '铁粒兑换',
                              style: TextStyle(fontSize: 12.5, color: Color(0xFF1890FF)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 价格展示 (粉红大字)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: RichText(
                            text: TextSpan(
                              text: item.isFree ? '免费' : '$totalPrice',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF5222D),
                              ),
                              children: [
                                if (!item.isFree)
                                  const TextSpan(
                                    text: ' 铁粒',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.normal,
                                      color: Color(0xFF8C8C8C),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // 当前拥有与差额提示
                        Row(
                          children: [
                            const Text(
                              '当前拥有: 12805',
                              style: TextStyle(fontSize: 12, color: Color(0xFF8C8C8C)),
                            ),
                            const Spacer(),
                            const Text(
                              '还差0，如何获取？',
                              style: TextStyle(fontSize: 12, color: Color(0xFF1890FF)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // 确认购买按钮
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF00A2FF),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.of(ctx).pop();
                              final res = await KlpbbsApi.buyFacemall(
                                item.id,
                                sDay: selectedDays > 0 ? selectedDays : 30,
                                sNow: equipNow,
                              );
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(res.message),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              if (res.success && equipNow) {
                                _equipPendant(item);
                              }
                            },
                            child: const Text(
                              '确认购买',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 立即装备复选框
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: equipNow,
                              activeColor: const Color(0xFF00A2FF),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) => setModalState(() => equipNow = v ?? true),
                            ),
                            const Text(
                              '立即装备',
                              style: TextStyle(fontSize: 13, color: Color(0xFF595959)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('头像挂件'),
        centerTitle: false,
        actions: const [GlobalNavButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: [
              // 1. 顶部大圆形挂件预览舞台 (1:1 深度对齐网页截图)
              _buildTopPreviewStage(theme),

              // 2. 核心导航标签 (挂件商城 / 我的挂件 / 激活记录) - 红色高亮下划线
              Container(
                color: colorScheme.surface,
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFFE53935),
                  unselectedLabelColor: const Color(0xFF555555),
                  indicatorColor: const Color(0xFFE53935),
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  tabs: const [
                    Tab(text: '挂件商城'),
                    Tab(text: '我的挂件'),
                    Tab(text: '激活记录'),
                  ],
                ),
              ),

              // 3. 页面内容
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMallTab(theme),
                    _buildMyPendantsTab(theme),
                    _buildActivationRecordsTab(theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部预览区（对齐图二：居中头像、虚线环、更换头像、卸下挂件）
  Widget _buildTopPreviewStage(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(40),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 更换头像按钮 (蓝色圆形)
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileSettingsPage(uid: _currentUid > 0 ? _currentUid : null),
                ),
              );
            },
            borderRadius: BorderRadius.circular(30),
            child: Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF00A2FF),
              ),
              child: const Center(
                child: Text(
                  '更换\n头像',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 32),
          // 居中大头像挂件预览 (带虚线环与真实挂件叠加)
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFE2E4E8),
                    width: 1.5,
                  ),
                ),
              ),
              _buildEquippedAvatarPreview(78),
            ],
          ),
          const SizedBox(width: 32),
          // 卸下挂件按钮 (灰色边框圆形)
          InkWell(
            onTap: _unequipPendant,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: const Color(0xFFDCDFE6),
                  width: 1.5,
                ),
              ),
              child: const Center(
                child: Text(
                  '卸下\n挂件',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF909399),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquippedAvatarPreview(double avatarSize) {
    final hasFrame = _equippedFrameId != null && _equippedFrameId != 'none' && _equippedFrameId!.isNotEmpty;

    return UserAvatarWidget(
      uid: _currentUid > 0 ? _currentUid : null,
      author: _currentUsername,
      size: avatarSize,
      faceUrl: hasFrame ? _equippedFrameId : '',
    );
  }

  /// 挂件商城 Tab（分类标签 + 挂件网格 3 列）
  Widget _buildMallTab(ThemeData theme) {
    final currentList = _categoryItemsMap[_selectedCategory.$1] ?? const <FacemallItem>[];

    return Column(
      children: [
        // 分类标签栏 (默认 / 二次元 / 我的世界 / 综合 / 其他 - 蓝色药丸胶囊)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory.$1 == cat.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() => _selectedCategory = cat);
                      _loadCategoryItems(cat.$1);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF00A2FF) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        cat.$2,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : const Color(0xFF555555),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const Divider(height: 1, thickness: 0.8),
        // 挂件网格列表 (3 列卡片布局)
        Expanded(
          child: (_initialLoading || _loadingCategory) && currentList.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : currentList.isEmpty
                  ? const Center(
                      child: Text(
                        '该分类下暂无挂件商品',
                        style: TextStyle(fontSize: 14, color: Color(0xFF999999)),
                      ),
                    )
                  : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisExtent: 150,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: currentList.length,
                  itemBuilder: (ctx, i) {
                    final item = currentList[i];
                    final isEquipped = _equippedFrameId == item.id || _equippedFrameId == item.frameUrl;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isEquipped
                              ? const Color(0xFF00A2FF)
                              : const Color(0xFFEBEEF5),
                          width: isEquipped ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(4),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () => _showPendantDialog(item),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 头像叠放挂件微缩预览图 (56px)
                              UserAvatarWidget(
                                uid: _currentUid > 0 ? _currentUid : null,
                                author: _currentUsername,
                                size: 56,
                                faceUrl: item.frameUrl,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF333333),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 我的挂件 Tab (100% 官方接口 action=mylist 真实数据)
  Widget _buildMyPendantsTab(ThemeData theme) {
    if (_loadingMyPendants) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_myPendants.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.face_retouching_natural, size: 54, color: Color(0xFFCCCCCC)),
            const SizedBox(height: 12),
            const Text('您尚未拥有任何头像挂件', style: TextStyle(fontSize: 15, color: Color(0xFF666666))),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00A2FF)),
              onPressed: () => _tabController.animateTo(0),
              child: const Text('前往挂件商城挑选'),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisExtent: 180,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _myPendants.length,
      itemBuilder: (ctx, i) {
        final item = _myPendants[i];
        final imgUrl = item['img']?.toString() ?? '';
        final title = item['title']?.toString() ?? '头像挂件';
        final endtime = item['endtime']?.toString() ?? '';
        final sFid = item['s_fid']?.toString() ?? item['id']?.toString() ?? '';
        final isEquipped = item['use'] == '1' || _equippedFrameId == imgUrl || _equippedFrameId == sFid;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isEquipped ? const Color(0xFF00A2FF) : const Color(0xFFEBEEF5),
              width: isEquipped ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              UserAvatarWidget(
                uid: _currentUid > 0 ? _currentUid : null,
                author: _currentUsername,
                size: 56,
                faceUrl: imgUrl,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
              ),
              if (endtime.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '$endtime 到期',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 28,
                child: isEquipped
                    ? OutlinedButton(
                        onPressed: () async {
                          await _unequipPendant();
                          _loadMyPendants();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('卸下', style: TextStyle(fontSize: 11.5)),
                      )
                    : FilledButton(
                        onPressed: () async {
                          final fItem = FacemallItem(
                            id: sFid,
                            name: title,
                            desc: title,
                            frameUrl: imgUrl,
                            priceText: '已拥有',
                          );
                          await _equipPendant(fItem);
                          _loadMyPendants();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00A2FF),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('佩戴', style: TextStyle(fontSize: 11.5)),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 激活记录 Tab (100% 官方接口 action=paylist 真实数据)
  Widget _buildActivationRecordsTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('挂件购买与激活记录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: _loadingPayList
                ? const Center(child: CircularProgressIndicator())
                : _payList.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无挂件激活与购买记录',
                          style: TextStyle(fontSize: 14, color: Color(0xFF999999)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _payList.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final item = _payList[i];
                          final title = item['title']?.toString() ?? '头像挂件';
                          final day = item['day']?.toString() ?? '';
                          final price = item['price']?.toString() ?? '0';
                          final time = item['time']?.toString() ?? '';

                          return ListTile(
                            leading: const Icon(Icons.history, color: Color(0xFF00A2FF)),
                            title: Text('$title · $day 天'),
                            subtitle: Text('$time · 消耗 $price 铁粒'),
                            dense: true,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
