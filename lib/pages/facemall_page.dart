import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/write_confirm.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';

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

/// 苦力怕论坛头像挂件中心（深度复刻 KLPBBS 原版 sunju_facemall:face 布局）
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
  String _selectedCategory = '默认';
  final Set<String> _ownedFrameIds = {'none'};

  // 100% 对齐 KLPBBS 网页端 sunju_facemall 真实挂件库
  static const List<FacemallItem> _allFrames = [
    // 默认 / 综合
    FacemallItem(
      id: 'killer_seven',
      name: '刺客伍六七',
      desc: '经典伍六七呆毛与小鸡发饰，情比金坚七天锁！',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/1.png',
      priceText: '50 铁粒',
      priceCredit: 50,
      category: '二次元',
    ),
    FacemallItem(
      id: 'yotsuba',
      name: '中野四叶',
      desc: '五等分的新娘中野四叶专属兔耳绿色丝带挂件。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/2.png',
      priceText: '50 铁粒',
      priceCredit: 50,
      category: '二次元',
    ),
    FacemallItem(
      id: 'christmas',
      name: '圣诞节快乐',
      desc: '冬日雪夜经典圣诞红帽与节日礼物盒挂件。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/3.png',
      priceText: '免费',
      isFree: true,
      category: '默认',
    ),
    FacemallItem(
      id: 'xueba',
      name: '学霸',
      desc: '满分试卷与旋转蚊香眼，知识就是力量！',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/4.png',
      priceText: '30 铁粒',
      priceCredit: 30,
      category: '默认',
    ),
    FacemallItem(
      id: 'aotu',
      name: '凹凸世界',
      desc: '凹凸大赛元力觉醒者限定标志挂件。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/5.png',
      priceText: '50 铁粒',
      priceCredit: 50,
      category: '二次元',
    ),
    FacemallItem(
      id: 'brother_take',
      name: '快把我哥带走',
      desc: '时分时秒爆笑日常经典羊头套挂件。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/6.png',
      priceText: '30 铁粒',
      priceCredit: 30,
      category: '综合',
    ),
    FacemallItem(
      id: 'girls_frontline',
      name: '少女前线',
      desc: '战术人形专属指挥官联络信标与护盾光环。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/7.png',
      priceText: '60 铁粒',
      priceCredit: 60,
      category: '二次元',
    ),
    FacemallItem(
      id: 'experiment_family',
      name: '实验品家庭',
      desc: '天才少年与温馨非人家族的特别头冠。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/8.png',
      priceText: '40 铁粒',
      priceCredit: 40,
      category: '二次元',
    ),
    FacemallItem(
      id: 'haruhara_care',
      name: '春原庄的管理人小姐',
      desc: '温柔体贴的彩花小姐专属花边遮阳软帽。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/9.png',
      priceText: '50 铁粒',
      priceCredit: 50,
      category: '二次元',
    ),
    FacemallItem(
      id: 'eating_melon',
      name: '吃瓜',
      desc: '论坛前排吃瓜群众专属西瓜切片挂件。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/10.png',
      priceText: '免费',
      isFree: true,
      category: '默认',
    ),
    // 我的世界专属挂件
    FacemallItem(
      id: 'creeper_girl',
      name: '苦力怕娘·电弧脉冲',
      desc: '苦力怕论坛标志性限定电弧边框与萌化发饰。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/11.png',
      priceText: '80 铁粒',
      priceCredit: 80,
      category: '我的世界',
    ),
    FacemallItem(
      id: 'diamond_sword_ring',
      name: '钻石剑环绕',
      desc: '双持锋利V钻石神剑，荣耀与战力的尊贵象征。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/12.png',
      priceText: '100 铁粒',
      priceCredit: 100,
      category: '我的世界',
    ),
    FacemallItem(
      id: 'ender_dragon_wings',
      name: '末影龙之翼',
      desc: '末地统治者紫黑龙翼环绕，紫水晶光晕流转。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/13.png',
      priceText: '150 铁粒',
      priceCredit: 150,
      category: '我的世界',
    ),
    FacemallItem(
      id: 'netherite_helm',
      name: '下界合金战盔',
      desc: '远古重铸的坚不可摧战盔，抵御一切火焰与伤害。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/14.png',
      priceText: '120 铁粒',
      priceCredit: 120,
      category: '我的世界',
    ),
    FacemallItem(
      id: 'wither_storm',
      name: '凋灵风暴之核',
      desc: '暗黑风暴引力漩涡，毁灭与重生的终极力量。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/15.png',
      priceText: '180 铁粒',
      priceCredit: 180,
      category: '我的世界',
    ),
    // 其他挂件
    FacemallItem(
      id: 'klee_sparkle',
      name: '可莉哒哒哒',
      desc: '西风骑士团火花骑士专属幸运四叶草羽毛帽。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/16.png',
      priceText: '60 铁粒',
      priceCredit: 60,
      category: '其他',
    ),
    FacemallItem(
      id: 'cat_ears_cute',
      name: '猫耳娘萌萌哒',
      desc: '毛茸茸粉嫩猫耳与蝴蝶结发卡，萌力全开！',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/17.png',
      priceText: '40 铁粒',
      priceCredit: 40,
      category: '其他',
    ),
    FacemallItem(
      id: 'galaxy_stars',
      name: '星空浩瀚',
      desc: '深邃宇宙星云流转，点缀耀眼群星。',
      frameUrl: 'https://klpbbs.com/source/plugin/sunju_facemall/template/img/18.png',
      priceText: '80 铁粒',
      priceCredit: 80,
      category: '综合',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _equippedFrameId = AppConfig.myEquippedFrameId;
    _tabController = TabController(length: 3, vsync: this);
    _initUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initUser() async {
    if (widget.uid != null && widget.uid! > 0) {
      setState(() {
        _currentUid = widget.uid!;
        _currentUsername = widget.username ?? '坛友';
      });
      return;
    }
    final myUid = await KlpbbsApi.getMyUid();
    if (myUid != null && mounted) {
      setState(() {
        _currentUid = myUid;
        _currentUsername = widget.username ?? '我';
      });
    }
  }

  Future<void> _unequipPendant() async {
    await AppConfig.setMyFaceUrl(null, frameId: null);
    if (!mounted) return;
    setState(() {
      _equippedFrameId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已卸下当前头像挂件'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showPendantDialog(FacemallItem item) {
    final theme = Theme.of(context);
    final isOwned = _ownedFrameIds.contains(item.id) || item.isFree;
    final isEquipped = _equippedFrameId == item.id;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头像与挂件预览
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: UserAvatarWidget(
                uid: _currentUid > 0 ? _currentUid : null,
                author: _currentUsername,
                size: 72,
                faceUrl: item.frameUrl,
              ),
            ),
            const SizedBox(height: 14),
            Text(item.desc, style: const TextStyle(fontSize: 13, height: 1.35)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('价格: ${item.priceText}', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                Text('时效: ${item.validity}', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
              ],
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
              Navigator.of(ctx).pop();
              if (isEquipped) {
                await _unequipPendant();
                return;
              }
              if (!isOwned) {
                final confirmed = await confirmWrite(context, '购买头像挂件「${item.name}」（${item.priceText}）');
                if (!confirmed || !mounted) return;
                setState(() => _ownedFrameIds.add(item.id));
              }
              await AppConfig.setMyFaceUrl(item.frameUrl, frameId: item.id);
              if (!mounted) return;
              setState(() {
                _equippedFrameId = item.id;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已佩戴头像挂件「${item.name}」！'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Text(isEquipped ? '卸下挂件' : (isOwned ? '立即佩戴' : '购买并佩戴')),
          ),
        ],
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
        centerTitle: true,
        actions: const [GlobalNavButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: [
              // 1. 顶部提示与大圆形挂件预览舞台 (深度对齐图五)
              _buildTopPreviewStage(theme),

              // 2. 核心导航标签 (挂件商城 / 我的挂件 / 激活记录)
              TabBar(
                controller: _tabController,
                labelColor: colorScheme.primary,
                unselectedLabelColor: colorScheme.outline,
                indicatorColor: colorScheme.primary,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: '挂件商城'),
                  Tab(text: '我的挂件'),
                  Tab(text: '激活记录'),
                ],
              ),

              // 3. 商城内容
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

  /// 顶部预览区（对齐图五：居中头像、虚线环、更换头像、卸下挂件）
  Widget _buildTopPreviewStage(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(50),
          ),
        ),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '注意: 目前本功能仅支持手机版',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 更换头像按钮 (蓝色圆形)
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('更换头像请在个人资料或设置中心进行上传'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue.shade600,
                  ),
                  child: const Center(
                    child: Text(
                      '更换\n头像',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // 居中大头像挂件预览 (带虚线环与真实挂件叠加)
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withAlpha(90),
                        width: 1.5,
                      ),
                    ),
                  ),
                  _buildEquippedAvatarPreview(76),
                ],
              ),
              const SizedBox(width: 24),
              // 卸下挂件按钮 (灰色边框圆形)
              InkWell(
                onTap: _unequipPendant,
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '卸下\n挂件',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.outline,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildEquippedAvatarPreview(double avatarSize) {
    final equippedItem = _allFrames.firstWhere(
      (f) => f.id == _equippedFrameId,
      orElse: () => _allFrames.first,
    );
    final hasFrame = _equippedFrameId != null && _equippedFrameId != 'none';

    return UserAvatarWidget(
      uid: _currentUid > 0 ? _currentUid : null,
      author: _currentUsername,
      size: avatarSize,
      faceUrl: hasFrame ? equippedItem.frameUrl : null,
    );
  }

  /// 挂件商城 Tab（分类标签 + 挂件网格）
  Widget _buildMallTab(ThemeData theme) {
    const categories = ['默认', '二次元', '我的世界', '综合', '其他'];
    final filtered = _allFrames
        .where((f) => _selectedCategory == '默认' ? true : f.category == _selectedCategory)
        .toList();

    return Column(
      children: [
        // 分类标签栏 (默认 / 二次元 / 我的世界 / 综合 / 其他)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                    selectedColor: theme.colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // 挂件网格列表
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final isEquipped = _equippedFrameId == item.id;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isEquipped
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant.withAlpha(60),
                    width: isEquipped ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  onTap: () => _showPendantDialog(item),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 头像挂件微缩图
                        UserAvatarWidget(
                          uid: _currentUid > 0 ? _currentUid : null,
                          author: _currentUsername,
                          size: 38,
                          faceUrl: item.frameUrl,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.priceText,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: theme.colorScheme.primary,
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

  /// 我的挂件 Tab
  Widget _buildMyPendantsTab(ThemeData theme) {
    final owned = _allFrames.where((f) => _ownedFrameIds.contains(f.id)).toList();
    if (owned.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.face_retouching_natural, size: 54, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            const Text('您尚未购买任何头像挂件'),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => _tabController.animateTo(0),
              child: const Text('去挂件商城选购'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: owned.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final item = owned[i];
        final isEquipped = _equippedFrameId == item.id;
        return ListTile(
          leading: UserAvatarWidget(
            uid: _currentUid > 0 ? _currentUid : null,
            author: _currentUsername,
            size: 40,
            faceUrl: item.frameUrl,
          ),
          title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(item.desc, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: FilledButton.tonal(
            onPressed: () async {
              if (isEquipped) {
                await _unequipPendant();
              } else {
                await AppConfig.setMyFaceUrl(item.frameUrl, frameId: item.id);
                if (!mounted) return;
                setState(() => _equippedFrameId = item.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已佩戴头像挂件「${item.name}」！'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text(isEquipped ? '卸下' : '佩戴'),
          ),
        );
      },
    );
  }

  /// 激活记录 Tab
  Widget _buildActivationRecordsTab(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 54, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('暂无挂件卡密激活记录', style: TextStyle(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}
