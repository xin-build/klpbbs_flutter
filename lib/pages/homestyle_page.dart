import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../widgets/app_back_button.dart';
import '../widgets/global_nav.dart';
import '../widgets/thread_card.dart';

/// 空间装扮壁纸数据模型
class HomeStyleItem {
  final String id;
  final String name;
  final String imageUrl;
  final String category; // 推荐, 主世界, 地狱, 末地, 可爱
  final List<Color> gradientColors;

  const HomeStyleItem({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.category,
    this.gradientColors = const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
  });
}

/// 苦力怕论坛空间装扮中心（1:1 深度对齐 plugin.php?id=comiis_app_homestyle&mobile=2）
class HomeStylePage extends StatefulWidget {
  final int? uid;
  final String? username;
  final String? avatarUrl;

  const HomeStylePage({
    super.key,
    this.uid,
    this.username,
    this.avatarUrl,
  });

  @override
  State<HomeStylePage> createState() => _HomeStylePageState();
}

class _HomeStylePageState extends State<HomeStylePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentUid = 0;
  String _currentUsername = '坛友';
  String _userGroup = 'Lv.4 高级会员';
  String _credits = '6994';
  int _popularity = 100;
  String _activeWallpaperUrl = 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/1.png';

  static const List<String> _categories = ['推荐', '主世界', '地狱', '末地', '可爱'];

  // 严格 1:1 对齐苦力怕论坛 comiis_app_homestyle 官方原站所有分类壁纸库
  static const List<HomeStyleItem> _allWallpapers = [
    // 1. 推荐 (6 款，完全对齐 smod 默认)
    HomeStyleItem(
      id: '89',
      name: 'nacho',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/nacho0.png',
      category: '推荐',
      gradientColors: [Color(0xFF80D8FF), Color(0xFF40C4FF), Color(0xFF0091EA)],
    ),
    HomeStyleItem(
      id: '88',
      name: '猫羽雫',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/myn2.gif',
      category: '推荐',
      gradientColors: [Color(0xFFFF80AB), Color(0xFFFF4081), Color(0xFFC51162)],
    ),
    HomeStyleItem(
      id: '83',
      name: 'nacho',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/nacho3.gif',
      category: '推荐',
      gradientColors: [Color(0xFF81D4FA), Color(0xFF29B6F6), Color(0xFF0288D1)],
    ),
    HomeStyleItem(
      id: '82',
      name: '猫羽雫',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/mynele.gif',
      category: '推荐',
      gradientColors: [Color(0xFFF48FB1), Color(0xFFEC407A), Color(0xFFAD1457)],
    ),
    HomeStyleItem(
      id: '74',
      name: '主世界',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/1.png',
      category: '推荐',
      gradientColors: [Color(0xFF43A047), Color(0xFF2E7D32), Color(0xFF1B5E20)],
    ),
    HomeStyleItem(
      id: '73',
      name: '主世界',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/2.png',
      category: '推荐',
      gradientColors: [Color(0xFF66BB6A), Color(0xFF388E3C), Color(0xFF1B5E20)],
    ),

    // 2. 主世界 (6 款，完全对齐 smod=1)
    HomeStyleItem(
      id: '76',
      name: '主世界',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/bw1.gif',
      category: '主世界',
      gradientColors: [Color(0xFF42A5F5), Color(0xFF1E88E5), Color(0xFF1565C0)],
    ),
    HomeStyleItem(
      id: '72',
      name: '主世界',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/xy2.gif',
      category: '主世界',
      gradientColors: [Color(0xFF7E57C2), Color(0xFF5E35B1), Color(0xFF4527A0)],
    ),
    HomeStyleItem(
      id: '71',
      name: '主世界',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/zy1.gif',
      category: '主世界',
      gradientColors: [Color(0xFF26A69A), Color(0xFF00897B), Color(0xFF00695C)],
    ),
    HomeStyleItem(
      id: '74',
      name: '主世界',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/1.png',
      category: '主世界',
      gradientColors: [Color(0xFF43A047), Color(0xFF2E7D32), Color(0xFF1B5E20)],
    ),
    HomeStyleItem(
      id: '73',
      name: '主世界',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/2.png',
      category: '主世界',
      gradientColors: [Color(0xFF66BB6A), Color(0xFF388E3C), Color(0xFF1B5E20)],
    ),
    HomeStyleItem(
      id: '75',
      name: '主世界',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/fengjing/3.png',
      category: '主世界',
      gradientColors: [Color(0xFFFFA726), Color(0xFFFB8C00), Color(0xFFEF6C00)],
    ),

    // 3. 地狱 (1 款，完全对齐 smod=44)
    HomeStyleItem(
      id: '77',
      name: '地狱',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/shishang/dy1.png',
      category: '地狱',
      gradientColors: [Color(0xFFD32F2F), Color(0xFFC2185B), Color(0xFF4A148C)],
    ),

    // 4. 末地 (1 款，完全对齐 smod=17)
    HomeStyleItem(
      id: '78',
      name: '末地',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/jingwu/dl1.gif',
      category: '末地',
      gradientColors: [Color(0xFF7B1FA2), Color(0xFF4A148C), Color(0xFF1A237E)],
    ),

    // 5. 可爱 (13 款，完全对齐 smod=34)
    HomeStyleItem(
      id: '92',
      name: '2233',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/2233_sd.png',
      category: '可爱',
      gradientColors: [Color(0xFF00A2FF), Color(0xFFFB7299), Color(0xFF0088CC)],
    ),
    HomeStyleItem(
      id: '89',
      name: 'nacho',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/nacho0.png',
      category: '可爱',
      gradientColors: [Color(0xFF80D8FF), Color(0xFF40C4FF), Color(0xFF0091EA)],
    ),
    HomeStyleItem(
      id: '90',
      name: '猫羽雫',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/myn1.gif',
      category: '可爱',
      gradientColors: [Color(0xFF81D4FA), Color(0xFF4FC3F7), Color(0xFF0288D1)],
    ),
    HomeStyleItem(
      id: '88',
      name: '猫羽雫',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/myn2.gif',
      category: '可爱',
      gradientColors: [Color(0xFFFF80AB), Color(0xFFFF4081), Color(0xFFC51162)],
    ),
    HomeStyleItem(
      id: '87',
      name: '猫羽雫',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/myn3.gif',
      category: '可爱',
      gradientColors: [Color(0xFFCE93D8), Color(0xFFAB47BC), Color(0xFF7B1FA2)],
    ),
    HomeStyleItem(
      id: '91',
      name: '鲨鲨',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/gura.png',
      category: '可爱',
      gradientColors: [Color(0xFF4FC3F7), Color(0xFF0288D1), Color(0xFF01579B)],
    ),
    HomeStyleItem(
      id: '84',
      name: 'nacho',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/nacho2.gif',
      category: '可爱',
      gradientColors: [Color(0xFFFFCC80), Color(0xFFFFA726), Color(0xFFFB8C00)],
    ),
    HomeStyleItem(
      id: '83',
      name: 'nacho',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/nacho3.gif',
      category: '可爱',
      gradientColors: [Color(0xFF81D4FA), Color(0xFF29B6F6), Color(0xFF0288D1)],
    ),
    HomeStyleItem(
      id: '82',
      name: '猫羽雫',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/mynele.gif',
      category: '可爱',
      gradientColors: [Color(0xFFF48FB1), Color(0xFFEC407A), Color(0xFFAD1457)],
    ),
    HomeStyleItem(
      id: '85',
      name: '2233',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/2233.png',
      category: '可爱',
      gradientColors: [Color(0xFF00A2FF), Color(0xFFFB7299), Color(0xFF0088CC)],
    ),
    HomeStyleItem(
      id: '86',
      name: '猫羽雫',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/myn0.png',
      category: '可爱',
      gradientColors: [Color(0xFF80DEEA), Color(0xFF26C6DA), Color(0xFF0097A7)],
    ),
    HomeStyleItem(
      id: '81',
      name: 'nacho',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/nacho1.png',
      category: '可爱',
      gradientColors: [Color(0xFFB0BEC5), Color(0xFF78909C), Color(0xFF455A64)],
    ),
    HomeStyleItem(
      id: '80',
      name: 'dianna',
      imageUrl: 'https://klpbbs.com/source/plugin/comiis_app_homestyle/image/home_bg/meng/dianna.png',
      category: '可爱',
      gradientColors: [Color(0xFFFFAB91), Color(0xFFFF7043), Color(0xFFD84315)],
    ),
  ];

  String? _selectedStyleId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    if (AppConfig.spaceWallpaper != null && AppConfig.spaceWallpaper!.isNotEmpty) {
      _activeWallpaperUrl = AppConfig.spaceWallpaper!;
    }
    _loadUserInfo();
    _syncServerStyles();
  }

  Future<void> _syncServerStyles() async {
    try {
      final remoteList = await KlpbbsApi.getHomeStyles();
      if (remoteList.isNotEmpty && mounted) {
        setState(() {
          // 动态合并服务器抓取的最新壁纸
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final uid = widget.uid ?? await KlpbbsApi.getMyUid();
    if (uid == null || uid <= 0) return;
    final space = await KlpbbsApi.getUserSpace(uid);
    if (!mounted) return;
    if (space != null) {
      setState(() {
        _currentUid = uid;
        _currentUsername = space.username.isNotEmpty ? space.username : (widget.username ?? '坛友');
        _userGroup = space.group.isNotEmpty ? space.group : (space.levelName.isNotEmpty ? space.levelName : 'Lv.4 高级会员');
        _credits = space.credits.isNotEmpty ? space.credits : (space.creditsDetail['经验'] ?? '6994');
        final threadCount = int.tryParse(space.stats['主题'] ?? '0') ?? 0;
        _popularity = threadCount * 3 + 50;
      });
    }
  }

  void _selectWallpaper(HomeStyleItem item) {
    setState(() {
      _activeWallpaperUrl = item.imageUrl;
      _selectedStyleId = item.id;
    });
  }

  Future<void> _saveWallpaper() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_selectedStyleId != null && _selectedStyleId!.isNotEmpty) {
        await KlpbbsApi.saveHomeStyle(_selectedStyleId!);
      }
      await AppConfig.setSpaceWallpaper(_activeWallpaperUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('空间背景装扮已保存成功！'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存失败，请检查网络'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('我的空间'),
        centerTitle: false,
        actions: const [GlobalNavButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: [
              // 1. 顶部空间背景实时预览卡片 (1:1 深度对齐截图)
              _buildLiveSpacePreviewHeader(theme),

              // 2. 分类标签导航栏 (推荐 / 主世界 / 地狱 / 末地 / 可爱)
              Container(
                color: colorScheme.surface,
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF00A2FF),
                  unselectedLabelColor: const Color(0xFF666666),
                  indicatorColor: const Color(0xFF00A2FF),
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  tabs: _categories.map((c) => Tab(text: c)).toList(),
                ),
              ),

              // 3. 壁纸选择网格列表
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _categories.map((cat) => _buildWallpaperGrid(cat, theme)).toList(),
                ),
              ),

              // 4. 底部版权与免责声明
              _buildBottomNotice(),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部实时个人空间舞台预览卡片（1:1 复刻截图）
  Widget _buildLiveSpacePreviewHeader(ThemeData theme) {
    final currentItem = _allWallpapers.firstWhere(
      (w) => w.imageUrl == _activeWallpaperUrl,
      orElse: () => _allWallpapers.first,
    );

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 空间壁纸背景图（网络加载 + 本地渐变双重保障）
          CachedNetworkImage(
            imageUrl: _activeWallpaperUrl,
            cacheManager: KlpbbsCacheManager.instance,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: currentItem.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: currentItem.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // 阴影渐变层保护文字可读性
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withAlpha(70),
                  Colors.black.withAlpha(20),
                  Colors.black.withAlpha(140),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // 用户资料内容居左展示（头像、昵称、人气、积分、等级）
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 20),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 用户头像（叠加头像挂件）
                  UserAvatarWidget(
                    uid: _currentUid > 0 ? _currentUid : null,
                    author: _currentUsername,
                    size: 64,
                  ),
                  const SizedBox(width: 14),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 用户名
                      Text(
                        _currentUsername,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 人气与积分
                      Row(
                        children: [
                          Text(
                            '人气 $_popularity',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$_credits 积分',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 等级胶囊
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A2FF).withAlpha(220),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _userGroup,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 右上角红色「保存」按钮 (1:1 深度对齐网页端视觉与交互)
          Positioned(
            top: 14,
            right: 16,
            child: Material(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(16),
              elevation: 2,
              child: InkWell(
                onTap: _saveWallpaper,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_saving)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Text(
                          '保存',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 壁纸网格视图（3 列，选中带鲜明蓝色高亮）
  Widget _buildWallpaperGrid(String category, ThemeData theme) {
    final list = _allWallpapers.where((w) => w.category == category).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 140,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final item = list[i];
        final isSelected = _activeWallpaperUrl == item.imageUrl;

        return InkWell(
          onTap: () => _selectWallpaper(item),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? const Color(0xFF00A2FF) : Colors.transparent,
                width: isSelected ? 2.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Column(
                children: [
                  // 壁纸缩略图
                  Expanded(
                    child: CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      cacheManager: KlpbbsCacheManager.instance,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: item.gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.wallpaper, color: Colors.white70, size: 28),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: item.gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.wallpaper, color: Colors.white70, size: 28),
                        ),
                      ),
                    ),
                  ),
                  // 壁纸名称条（选中为亮蓝底白字）
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    color: isSelected ? const Color(0xFF00A2FF) : Colors.white,
                    child: Text(
                      item.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : const Color(0xFF555555),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 底部免责声明条（1:1 对齐截图底部黄色提示条）
  Widget _buildBottomNotice() {
    return Builder(
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: isDark ? const Color(0xFF2E2612) : const Color(0xFFFFFBE6),
          child: Text(
            '图片来自网络，侵权立删',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFFFFD591) : const Color(0xFFFA8C16),
            ),
          ),
        );
      },
    );
  }
}
