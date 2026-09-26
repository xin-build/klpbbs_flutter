import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dashboard_card_model.dart';
import '../services/rgb_theme_service.dart';

/// 界面风格（预设主题配色）
enum AppStyle {
  sakura('樱花粉', Color(0xFFFA7298)),
  creeper('苦力怕绿', Color(0xFF3BA55D)),
  biliBlue('哔哩蓝', Color(0xFF00AEEC)),
  cyberPurple('赛博紫', Color(0xFF8E24AA)),
  amberGold('活力金', Color(0xFFFFB300)),
  deepslate('深板岩灰', Color(0xFF455A64)),
  custom('自定义/莫奈取色', Color(0xFF3BA55D));

  final String label;
  final Color seed;
  const AppStyle(this.label, this.seed);
}

/// 排版模式：自适应 / 强制移动端 / 强制桌面端
enum AppLayoutMode {
  auto('自适应（根据屏幕宽度）'),
  mobile('移动端排版（底栏+单列）'),
  desktop('PC 桌面排版（侧栏+多列网格）');

  final String label;
  const AppLayoutMode(this.label);
}

/// 导航布局（底部导航栏 / 侧边栏抽屉）- 移动端模式下生效
enum NavLayout {
  bottom('底部导航栏'),
  side('侧边栏抽屉');

  final String label;
  const NavLayout(this.label);
}

/// 帖子卡片样式
enum CardStyle {
  largeCover('大图流卡片 (16:9 封面)'),
  compact('紧凑图文行（高信息密度）'),
  grid('瀑布流网格卡片'),
  minimal('极简风 · 纯净通透（去繁就简）'),
  magazine('画报杂志风 · 焦点大图（全景头图）'),
  modernCard('现代微质感卡片（圆角立体与主题彩带）');

  final String label;
  const CardStyle(this.label);
}

/// 头像形状
enum AvatarShape {
  circle('圆形'),
  roundedRect('圆角矩形'),
  hexagon('六边形');

  final String label;
  const AvatarShape(this.label);
}

/// 图片质量与省流策略
enum ImageQuality {
  original('高质量原图'),
  dataSaver('智能省流（低分辨率）'),
  noImage('无图模式（仅文字）');

  final String label;
  const ImageQuality(this.label);
}

/// 视觉密度
enum AppDensity {
  compact('紧凑'),
  comfortable('舒适'),
  spacious('宽松');

  final String label;
  const AppDensity(this.label);

  VisualDensity get toVisualDensity {
    switch (this) {
      case AppDensity.compact:
        return VisualDensity.compact;
      case AppDensity.comfortable:
        return VisualDensity.comfortable;
      case AppDensity.spacious:
        return const VisualDensity(horizontal: 1.0, vertical: 1.0);
    }
  }
}

/// 轻量全局主题更新通知器（专供 MaterialApp 根构建监听，解耦布局调节与拖拽重绘）
class AppThemeNotifier extends ChangeNotifier {
  void notifyThemeChanged() {
    notifyListeners();
  }
}

/// 全局应用配置与状态控制器
class AppConfig extends ChangeNotifier {
  static final AppConfig instance = AppConfig._();
  AppConfig._();

  /// 专供 MaterialApp 根节点和全局主题监听的轻量 Notifier，
  /// 仅在颜色、风格、明暗模式、字体缩放、视觉密度等主题核心属性改变时触发。
  /// 拖拽侧边栏宽度、微调排版等绝不触发此 Notifier，从而避免根 MaterialApp 重构。
  static final AppThemeNotifier themeNotifier = AppThemeNotifier();

  // 细粒度响应式 Notifier：用于侧边栏拖拽、工作台缩放与阅读器调节，实现 120 FPS 零开销局部重绘
  static final ValueNotifier<double> threadForumSidebarWidthNotifier =
      ValueNotifier<double>(380.0);
  static final ValueNotifier<double> threadRightWidthNotifier =
      ValueNotifier<double>(320.0);
  static final ValueNotifier<double> threadContentMaxWidthNotifier =
      ValueNotifier<double>(960.0);
  static final ValueNotifier<double> homeLeftSidebarWidthNotifier =
      ValueNotifier<double>(270.0);
  static final ValueNotifier<double> homeRightSidebarWidthNotifier =
      ValueNotifier<double>(285.0);
  static final ValueNotifier<double> threadReaderFontSizeNotifier =
      ValueNotifier<double>(15.0);
  static final ValueNotifier<double> threadReaderLineHeightNotifier =
      ValueNotifier<double>(1.6);

  // ================= 应用版本信息 =================
  static const String appVersion = '1.1.1';
  static const String buildNumber = '13';
  static const String versionDisplay = 'v$appVersion (Build $buildNumber)';

  // ================= 论坛环境与网络 =================
  /// 本地测试论坛（真实 Discuz X3.4 + 克米插件）
  static const String localBaseUrl = 'http://127.0.0.1:8000/';

  /// 真实论坛地址（klpbbs）
  static const String realBaseUrl = 'https://klpbbs.com/';

  /// 旧 mock 服务器（离线开发）
  static const String mockBaseUrl = 'http://localhost:3000/';

  /// 当前使用的 baseUrl（默认官方真实论坛；可在设置页切换）
  static String baseUrl = realBaseUrl;

  /// 全局图片防盗链与 UA 标头（防止图片加载失败）
  static const Map<String, String> imageHeaders = {
    'Referer': 'https://klpbbs.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  /// 获取会话 Cookie 请求头回调（解耦 DioClient 避免循环依赖）
  static String Function()? getCookieHeader;

  /// 根据图片 URL 动态生成防盗链与 UA 标头（针对 B站、Wiki、Loli计数器与第三方图床智能分流）
  static Map<String, String> imageHeadersFor(String url) {
    var uri = Uri.tryParse(url);
    if (uri == null) {
      try {
        uri = Uri.tryParse(Uri.encodeFull(url));
      } catch (_) {}
    }
    final host = uri?.host.toLowerCase() ?? '';
    const imageAccept = 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8';

    // 1. 哔哩哔哩图床
    if (host.endsWith('bilibili.com') || host.endsWith('hdslb.com') || host.endsWith('bilivideo.com')) {
      return {
        'Referer': 'https://www.bilibili.com/',
        'User-Agent': pcUserAgent,
        'Accept': imageAccept,
      };
    }
    // 2. Minecraft Wiki / Fandom / MediaWiki 类知识库图床（必须使用规范 UA 且不可发送跨域 Referer）
    if (host.contains('minecraft.wiki') ||
        host.contains('weirdgloop.org') ||
        host.contains('fandom.com') ||
        host.contains('nocookie.net') ||
        host.contains('huijiwiki.com') ||
        host.contains('moegirl.org.cn') ||
        host.contains('wikia.org')) {
      return {
        'User-Agent': 'KlpbbsApp/1.0 (https://klpbbs.com; contact@klpbbs.com)',
        'Accept': imageAccept,
      };
    }
    // 3. Moe-Counter 等萌系计数器与论坛内部图片
    if (host.endsWith('count.getloli.com') || host.endsWith('getloli.com') || host.endsWith('klpbbs.com') || host == 'localhost' || host == '127.0.0.1' || host.isEmpty) {
      final headers = <String, String>{
        'Referer': 'https://klpbbs.com/',
        'User-Agent': pcUserAgent,
        'Accept': imageAccept,
      };
      final cookies = getCookieHeader?.call();
      if (cookies != null && cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }
      return headers;
    }
    // 4. 第三方外链图床（路过图床/sm.ms/微博/图虫/imgbb等）：不发送跨域 Referer 避免 403
    return {
      'User-Agent': pcUserAgent,
      'Accept': imageAccept,
    };
  }

  /// 头像域名
  static const String avatarHost = 'https://user.klpbbs.com';

  /// 根据当前环境生成头像 URL（本地测试论坛走 uc_server/avatar.php）
  static String avatarUrl(int uid, {String size = 'small'}) {
    if (isLocalTestMode) {
      return '${baseUrl}uc_server/avatar.php?uid=$uid&size=$size';
    }
    return '$avatarHost/avatar.php?uid=$uid&size=$size';
  }

  /// 将低清缩略图自动提升为高清原图 URL（去除 Discuz .thumb.jpg、&thumb=yes 等低清压缩参数，并规避 Discuz 动态图 0 字节缺陷）
  static String? toHighResImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    var clean = url.trim();

    // 1. 对于 forum.php?mod=image 的 Discuz 动态缩略图请求：
    // 其 key 参数为 Discuz 服务端根据 aid/size/type 计算的 HMAC 签名校验值，
    // 严禁添加或篡改任何 query 参数（如 &type=fixnone），否则签名校验失败 Discuz 会直接 exit 输出 0 字节！
    if (clean.contains('mod=image')) {
      return clean;
    }

    // 2. 去除 Discuz 缩略图后缀，彻底避免拉伸缩略图（双后缀与单后缀均自动还原为原始高清原图）
    clean = clean.replaceAll(RegExp(r'(\.(?:jpg|png|webp|jpeg|gif))\.thumb\.(?:jpg|png|webp|jpeg)$', caseSensitive: false), r'$1');
    clean = clean.replaceAll(RegExp(r'(\.(?:jpg|png|webp|jpeg|gif))\.(?:small|middle)\.(?:jpg|png|webp|jpeg)$', caseSensitive: false), r'$1');
    clean = clean.replaceAll(RegExp(r'_(?:thumb|small|middle)\.(?:jpg|png|webp|jpeg)$', caseSensitive: false), '.jpg');
    clean = clean.replaceAll(RegExp(r'\.thumb\.(?:jpg|jpeg)$', caseSensitive: false), '.jpg');
    clean = clean.replaceAll(RegExp(r'\.thumb\.(?:png)$', caseSensitive: false), '.png');
    clean = clean.replaceAll(RegExp(r'\.thumb\.(?:webp)$', caseSensitive: false), '.webp');

    // 3. 去除 URL query 中的 thumb 参数：&thumb=yes, &thumb=1, &thumb=2
    if (clean.contains('thumb=')) {
      clean = clean.replaceAll(RegExp(r'[?&]thumb=(?:yes|1|2|true)', caseSensitive: false), '');
      if (clean.contains('?') && !clean.contains('=')) {
        clean = clean.replaceAll('?', '');
      }
    }

    // 4. 处理 thumb.php 代理链接：pic/thumb.php?w=200&h=150&src=http... -> 提取 src
    if (clean.contains('thumb.php') && clean.contains('src=')) {
      final m = RegExp(r'[?&]src=([^&]+)').firstMatch(clean);
      if (m != null) {
        final decoded = Uri.decodeFull(m.group(1)!);
        if (decoded.startsWith('http') || decoded.startsWith('data/')) {
          clean = decoded;
        }
      }
    }

    return clean;
  }

  /// 浏览器 UA（可切换 PC/手机）
  static const String mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  static const String pcUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 是否使用 PC UA（默认 false=手机 UA）
  static bool usePcUa = false;

  static String get userAgent => usePcUa ? pcUserAgent : mobileUserAgent;

  /// 请求超时
  static const Duration timeout = Duration(seconds: 20);

  /// 真实模式下请求最小间隔
  static const Duration realModeMinInterval = Duration(milliseconds: 800);

  /// 当前是否真实论坛模式
  static bool get isRealMode => baseUrl.startsWith('https://klpbbs.com');

  /// 当前是否本地测试模式
  static bool get isLocalTestMode => baseUrl.startsWith('http://127.0.0.1');

  /// 写操作是否允许。
  ///
  /// 正常用户使用：始终 true（真实论坛写操作经 needRealWriteConfirm 二次确认）。
  /// 开发/逆向期间：AI 代理不应主动执行真实论坛写操作（只读逆向），但应用本身对用户开放写。
  static bool get allowWrite => true;

  /// 真实论坛写操作是否需要风险确认
  static bool get needRealWriteConfirm => isRealMode && !fastWriteMode;

  // ================= 用户自定义配置与持久化状态 =================
  /// 获取各平台默认主题风格：Android 默认自定义（莫奈动态壁纸取色），其余平台默认苦力怕绿
  static AppStyle get defaultPlatformStyle =>
      defaultTargetPlatform == TargetPlatform.android
          ? AppStyle.custom
          : AppStyle.creeper;

  static AppStyle style = defaultPlatformStyle;
  static int customSeedColorValue = 0xFF3BA55D;
  static ThemeMode themeMode = ThemeMode.system;
  static bool isOledDark = false;

  static AppLayoutMode layoutMode = AppLayoutMode.auto;
  static NavLayout navLayout = NavLayout.bottom;
  static int desktopGridColumns = 0; // 0 = 自动根据窗口宽度计算，2/3/4 = 固定列数
  static bool isMasterDetailEnabled = true;

  static CardStyle cardStyle = CardStyle.largeCover;
  static AppDensity density = AppDensity.comfortable;
  static double fontScale = 1.0;
  static AvatarShape avatarShape = AvatarShape.circle;

  /// 当前登录用户的头像挂件 URL（若有，全局生效）
  static String? myFaceUrl;

  /// 当前佩戴的挂件 ID（如 'creeper_girl'）
  static String? myEquippedFrameId;

  // 性能与 GPU
  static bool gpuAcceleration = true;
  static bool highRefreshRate = true;
  static ImageQuality imageQuality = ImageQuality.original;
  static int imageCacheMaxMb = 250;
  static bool smoothScrollPhysics = true;
  static bool enableMultiThreadParsing = true;
  static bool enableGpuAcceleratedRendering = true;

  // 论坛与阅读偏好
  static bool showFloorSignature = true;
  static bool showThreadListImages = true;
  static bool useSystemMonet = false;
  static bool autoCheckin = true;
  static bool fastWriteMode = false;
  static int defaultStartTab = 0;
  static List<String> blockedKeywords = [];
  static List<int> blockedUids = [];

  // 剪贴板跳转设置
  static bool clipboardJumpEnabled = true;
  static bool clipboardJumpThreadEnabled = true;
  static bool clipboardJumpSearchEnabled = true;
  static bool clipboardJumpConfirm = true;

  // 下载与存储管理
  static String downloadPath = '';
  static int downloadThreads = 4;
  static bool autoOpenFile = false;

  // 消息推送与托盘后台
  static bool minimizeToTrayOnClose = true;

  // 空间个性化
  static String? spaceWallpaper;

  // ================= DIY 模块化布局与工作台配置 =================
  /// 默认首页模块列表（顺序渲染）
  static const List<String> defaultHomeModules = [
    'tuhao_stats',
    'horn_banner',
    'forum_grid',
    'feed_list',
  ];

  /// 默认帖子详情页左栏模块
  static const List<String> defaultThreadLeftModules = [
    'forum_list',
    'media_gallery',
  ];

  /// 默认帖子详情页右栏模块
  static const List<String> defaultThreadRightModules = [
    'toc_outline',
    'floor_compass',
    'reader_tuning',
    'rating_hub',
  ];

  /// 默认版块页模块列表
  static const List<String> defaultForumModules = [
    'forum_header',
    'sub_forums',
    'type_filter',
    'sticky_threads',
    'thread_feed',
  ];

  /// 首页当前启用的模块列表
  static List<String> homeModules = List.from(defaultHomeModules);

  /// 版块页当前启用的模块列表
  static List<String> forumModules = List.from(defaultForumModules);

  /// 帖子详情页左栏模块列表
  static List<String> threadLeftModules = List.from(defaultThreadLeftModules);

  /// 帖子详情页右栏模块列表
  static List<String> threadRightModules = List.from(defaultThreadRightModules);

  /// 帖子详情页左栏宽度 (180 ~ 480)
  static double threadLeftWidth = 300.0;

  /// 帖子详情页右栏宽度 (180 ~ 520)
  static double threadRightWidth = 320.0;

  /// 帖子详情页正文最大限制宽度 (600 ~ 2400, 0 为 100% 满屏无上限)
  static double threadContentMaxWidth = 960.0;

  /// 是否开启帖子页左栏
  static bool threadLeftEnabled = true;

  /// 是否开启帖子页右栏
  static bool threadRightEnabled = true;

  /// 帖子阅读专属字号微调 (12.0 ~ 24.0)
  static double threadReaderFontSize = 15.0;

  /// 帖子阅读专属行高倍数 (1.2 ~ 2.4)
  static double threadReaderLineHeight = 1.6;

  // ================= 自由网格工作台与画布系统配置 =================
  /// 首页网格仪表盘布局项
  static List<DashboardGridItem> homeDashboardLayout = CardRegistry.getDefaultHomeLayout();

  /// 首页左右卡片栏折叠与展开状态（宽屏默认展开，自适应收起）
  static bool homeShowLeftCards = true;
  static bool homeShowRightCards = true;

  /// 首页左右侧边栏可拖动调节的宽度（支持用户拖拽微调）
  static double homeLeftSidebarWidth = 270.0;
  static double homeRightSidebarWidth = 285.0;

  /// 帖子详情页展开的版块列表边栏宽度（支持鼠标自由拖拽调节，240px ~ 720px）
  static double threadForumSidebarWidth = 380.0;

  /// 帖子页网格仪表盘布局项
  static List<DashboardGridItem> threadDashboardLayout = [];

  /// 导读页网格仪表盘工作台布局项（只支持右侧 4 列卡片）
  static List<DashboardGridItem> guideDashboardLayout = [];

  /// 主页/正文核心内容最小保护宽度 (400 ~ 1000px，防止被卡片占满)
  static double mainContentMinWidth = 620.0;

  /// 卡片栏布局位置 ('top', 'left', 'right', 'both')
  static String dashboardSidebarPosition = 'top';

  // ================= 移动端首页轻量自定义系统 =================
  /// 默认移动端首页组件排序与启闭（轻量、克制、美观）
  static const List<String> defaultMobileHomeSections = [
    'horn_banner',   // 全站小喇叭公告
    'stats',         // 站点统计看板
    'quick_actions', // 快捷金刚区
    'forum_nav',     // 原版版块导航
    'carousel',      // 精华推荐轮播
  ];

  /// 移动端首页当前启用的组件列表（有序）
  static List<String> mobileHomeSections = List.from(defaultMobileHomeSections);

  /// 默认移动端快捷功能（8 个核心功能）
  static const List<String> defaultMobileQuickActions = [
    'papa_ai',
    'forum_nav',
    'checkin',
    'medals',
    'guide',
    'search',
    'rank_god',
    'rank_board',
  ];

  /// 移动端快捷功能当前启用的功能项（4 ~ 8 项）
  static List<String> mobileQuickActions = List.from(defaultMobileQuickActions);

  /// 获取当前实际的主题种子颜色
  static Color get seedColor {
    if (RgbThemeService.instance.isEnabled) {
      return RgbThemeService.instance.currentColor;
    }
    if (style == AppStyle.custom) {
      return Color(customSeedColorValue);
    }
    return style.seed;
  }

  /// 初始化全部配置（App 启动时调用）
  static Future<void> loadAll() async {
    try {
      final sp = await SharedPreferences.getInstance();

      // 基础与主题
      final styleName = sp.getString('app_style');
      if (styleName != null) {
        if (styleName == 'piliplus') {
          style = AppStyle.sakura;
        } else {
          style = AppStyle.values.firstWhere(
            (s) => s.name == styleName,
            orElse: () => defaultPlatformStyle,
          );
        }
      } else {
        style = defaultPlatformStyle;
      }
      customSeedColorValue = sp.getInt('custom_seed_color') ?? 0xFF3BA55D;

      final themeModeStr = sp.getString('theme_mode');
      if (themeModeStr != null) {
        themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == themeModeStr,
          orElse: () => ThemeMode.system,
        );
      }
      isOledDark = sp.getBool('is_oled_dark') ?? false;

      // 排版与布局
      final layoutModeStr = sp.getString('layout_mode');
      if (layoutModeStr != null) {
        layoutMode = AppLayoutMode.values.firstWhere(
          (l) => l.name == layoutModeStr,
          orElse: () => AppLayoutMode.auto,
        );
      }

      final navLayoutStr = sp.getString('nav_layout');
      if (navLayoutStr != null) {
        navLayout = NavLayout.values.firstWhere(
          (n) => n.name == navLayoutStr,
          orElse: () => NavLayout.bottom,
        );
      }
      desktopGridColumns = sp.getInt('desktop_grid_columns') ?? 0;
      isMasterDetailEnabled = sp.getBool('master_detail_enabled') ?? true;
      usePcUa = sp.getBool('use_pc_ua') ?? false;

      // 界面样式
      final cardStyleStr = sp.getString('card_style');
      if (cardStyleStr != null) {
        if (cardStyleStr == 'piliplus') {
          cardStyle = CardStyle.largeCover;
        } else {
          cardStyle = CardStyle.values.firstWhere(
            (c) => c.name == cardStyleStr,
            orElse: () => CardStyle.largeCover,
          );
        }
      }

      final densityStr = sp.getString('density');
      if (densityStr != null) {
        density = AppDensity.values.firstWhere(
          (d) => d.name == densityStr,
          orElse: () => AppDensity.comfortable,
        );
      }

      fontScale = sp.getDouble('font_scale') ?? 1.0;

      final avatarShapeStr = sp.getString('avatar_shape');
      if (avatarShapeStr != null) {
        avatarShape = AvatarShape.values.firstWhere(
          (a) => a.name == avatarShapeStr,
          orElse: () => AvatarShape.circle,
        );
      }

      // 性能
      gpuAcceleration = sp.getBool('gpu_acceleration') ?? true;
      highRefreshRate = sp.getBool('high_refresh_rate') ?? true;
      final imageQualityStr = sp.getString('image_quality');
      if (imageQualityStr != null) {
        imageQuality = ImageQuality.values.firstWhere(
          (q) => q.name == imageQualityStr,
          orElse: () => ImageQuality.original,
        );
      }
      imageCacheMaxMb = sp.getInt('image_cache_max_mb') ?? 250;
      PaintingBinding.instance.imageCache.maximumSizeBytes = imageCacheMaxMb << 20;
      smoothScrollPhysics = sp.getBool('smooth_scroll_physics') ?? true;
      enableMultiThreadParsing = sp.getBool('enable_multithread_parsing') ?? true;
      enableGpuAcceleratedRendering = sp.getBool('enable_gpu_rendering') ?? true;

      // 论坛功能
      showFloorSignature = sp.getBool('show_floor_signature') ?? true;
      showThreadListImages = sp.getBool('show_thread_list_images') ?? true;
      useSystemMonet = sp.getBool('use_system_monet') ?? false;
      autoCheckin = sp.getBool('auto_checkin') ?? sp.getBool('auto_sign_on_launch') ?? true;
      fastWriteMode = sp.getBool('fast_write_mode') ?? false;
      defaultStartTab = sp.getInt('default_start_tab') ?? 0;
      blockedKeywords = sp.getStringList('blocked_keywords') ?? [];
      blockedUids = (sp.getStringList('blocked_uids') ?? [])
          .map((e) => int.tryParse(e) ?? 0)
          .where((uid) => uid > 0)
          .toList();

      // 剪贴板跳转
      clipboardJumpEnabled = sp.getBool('clipboard_jump_enabled') ?? true;
      clipboardJumpThreadEnabled = sp.getBool('clipboard_jump_thread_enabled') ?? true;
      clipboardJumpSearchEnabled = sp.getBool('clipboard_jump_search_enabled') ?? true;
      clipboardJumpConfirm = sp.getBool('clipboard_jump_confirm') ?? true;

      // 下载与存储管理
      downloadPath = sp.getString('download_path') ?? '';
      downloadThreads = sp.getInt('download_threads') ?? 4;
      autoOpenFile = sp.getBool('auto_open_file') ?? false;

      // 消息推送与托盘后台
      minimizeToTrayOnClose = sp.getBool('minimize_to_tray_on_close') ?? true;

      // 空间壁纸
      spaceWallpaper = sp.getString('space_wallpaper');

      // 头像挂件
      myFaceUrl = sp.getString('my_face_url');
      myEquippedFrameId = sp.getString('my_equipped_frame_id');

      final savedBaseUrl = sp.getString('base_url');
      if (savedBaseUrl != null && savedBaseUrl.isNotEmpty) {
        baseUrl = savedBaseUrl;
      }

      // DIY 模块化配置
      final loadedHomeModules = sp.getStringList('diy_home_modules');
      if (loadedHomeModules != null && loadedHomeModules.isNotEmpty) {
        homeModules = List.from(loadedHomeModules);
      } else {
        homeModules = List.from(defaultHomeModules);
      }
      final loadedThreadLeft = sp.getStringList('diy_thread_left_modules');
      if (loadedThreadLeft != null) {
        threadLeftModules = List.from(loadedThreadLeft);
      } else {
        threadLeftModules = List.from(defaultThreadLeftModules);
      }
      final loadedThreadRight = sp.getStringList('diy_thread_right_modules');
      if (loadedThreadRight != null) {
        threadRightModules = List.from(loadedThreadRight);
      } else {
        threadRightModules = List.from(defaultThreadRightModules);
      }
      threadRightModules.remove('forum_list');

      final loadedForumModules = sp.getStringList('diy_forum_modules');
      if (loadedForumModules != null && loadedForumModules.isNotEmpty) {
        forumModules = List.from(loadedForumModules);
      } else {
        forumModules = List.from(defaultForumModules);
      }
      threadLeftWidth = sp.getDouble('diy_thread_left_width') ?? 300.0;
      threadRightWidth = sp.getDouble('diy_thread_right_width') ?? 320.0;
      threadContentMaxWidth = sp.getDouble('diy_thread_content_max_width') ?? 960.0;
      threadLeftEnabled = sp.getBool('diy_thread_left_enabled') ?? true;
      threadRightEnabled = sp.getBool('diy_thread_right_enabled') ?? true;
      threadReaderFontSize = sp.getDouble('diy_thread_reader_font_size') ?? 15.0;
      threadReaderLineHeight = sp.getDouble('diy_thread_reader_line_height') ?? 1.6;

      // 自由网格仪表盘配置
      final homeGridJson = sp.getString('home_dashboard_layout_v2');
      if (homeGridJson != null && homeGridJson.isNotEmpty) {
        try {
          final list = jsonDecode(homeGridJson) as List;
          homeDashboardLayout = list.map((e) => DashboardGridItem.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {}
      }
      // 移除积分流水（credit_log）与小喇叭卡片，确保小喇叭使用原版经典样式、杜绝冗余
      homeModules.remove('credit_log');
      homeDashboardLayout.removeWhere((item) => item.cardType == 'credit_log' || item.cardType == 'horn_banner');

      // 确保首页左右两边平衡支持：如果历史旧数据中左侧卡片缺失，自动补全官方推荐的左侧卡片
      final hasLeftCards = homeDashboardLayout.any((c) => (c.col + c.colSpan / 2.0) < 6);
      if (homeDashboardLayout.isEmpty || !hasLeftCards) {
        homeDashboardLayout = CardRegistry.getDefaultHomeLayout();
      }

      homeShowLeftCards = sp.getBool('home_show_left_cards_v3') ?? true;
      homeShowRightCards = sp.getBool('home_show_right_cards_v3') ?? true;
      homeLeftSidebarWidth = sp.getDouble('home_left_sidebar_width') ?? 270.0;
      homeRightSidebarWidth = sp.getDouble('home_right_sidebar_width') ?? 285.0;
      threadForumSidebarWidth = sp.getDouble('thread_forum_sidebar_width') ?? 380.0;

      if (!homeDashboardLayout.any((e) => e.cardType == 'server_status')) {
        int maxRow = 0;
        for (final item in homeDashboardLayout.where((c) => (c.col + c.colSpan / 2.0) >= 6)) {
          final bottom = item.row + item.rowSpan;
          if (bottom > maxRow) maxRow = bottom;
        }
        homeDashboardLayout.add(
          DashboardGridItem(
            id: 'server_status_1',
            cardType: 'server_status',
            col: 8,
            row: maxRow,
            colSpan: 4,
            rowSpan: 2,
          ),
        );
      }
      final threadGridJson = sp.getString('thread_dashboard_layout_v2');
      if (threadGridJson != null && threadGridJson.isNotEmpty) {
        try {
          final list = jsonDecode(threadGridJson) as List;
          threadDashboardLayout = list.map((e) => DashboardGridItem.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {}
      }
      // 强力对齐 threadDashboardLayout 与 threadRightModules：彻底清除不属于帖子的 cardType（如 user_profile）、左侧错位卡片，并与 threadRightModules 保持 1:1 双向同步
      final validRight = threadRightModules;
      final existingMap = <String, DashboardGridItem>{};
      for (final item in threadDashboardLayout) {
        if (item.cardType != 'user_profile' && validRight.contains(item.cardType)) {
          existingMap[item.cardType] = item;
        }
      }
      int curRow = 0;
      threadDashboardLayout = validRight.map((id) {
        final existing = existingMap[id];
        final def = CardRegistry.definitions[id];
        final span = existing?.rowSpan ?? def?.defaultRowSpan ?? 2;
        final item = DashboardGridItem(
          id: existing?.id ?? 'th_$id',
          cardType: id,
          col: 8,
          row: curRow,
          colSpan: 4,
          rowSpan: span,
        );
        curRow += span;
        return item;
      }).toList();
      final guideGridJson = sp.getString('guide_dashboard_layout_v1');
      if (guideGridJson != null && guideGridJson.isNotEmpty) {
        try {
          final list = jsonDecode(guideGridJson) as List;
          guideDashboardLayout = list.map((e) => DashboardGridItem.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {}
      }
      if (guideDashboardLayout.isEmpty) {
        guideDashboardLayout = CardRegistry.getDefaultGuideLayout();
      }
      // 移动端轻量首页配置
      final loadedMobileSections = sp.getStringList('mobile_home_sections');
      if (loadedMobileSections != null && loadedMobileSections.isNotEmpty) {
        mobileHomeSections = List.from(loadedMobileSections);
      } else {
        mobileHomeSections = List.from(defaultMobileHomeSections);
      }
      final loadedMobileActions = sp.getStringList('mobile_quick_actions');
      if (loadedMobileActions != null && loadedMobileActions.isNotEmpty) {
        mobileQuickActions = List.from(loadedMobileActions);
      } else {
        mobileQuickActions = List.from(defaultMobileQuickActions);
      }

      mainContentMinWidth = sp.getDouble('main_content_min_width') ?? 620.0;
      dashboardSidebarPosition = sp.getString('dashboard_sidebar_position') ?? 'top';

      threadForumSidebarWidthNotifier.value = threadForumSidebarWidth;
      threadRightWidthNotifier.value = threadRightWidth;
      threadContentMaxWidthNotifier.value = threadContentMaxWidth;
      homeLeftSidebarWidthNotifier.value = homeLeftSidebarWidth;
      homeRightSidebarWidthNotifier.value = homeRightSidebarWidth;
      threadReaderFontSizeNotifier.value = threadReaderFontSize;
      threadReaderLineHeightNotifier.value = threadReaderLineHeight;
      themeNotifier.notifyThemeChanged();
    } catch (_) {}
  }

  // ================= 更新与持久化方法 =================
  static Future<void> setMyFaceUrl(String? url, {String? frameId}) async {
    myFaceUrl = url;
    myEquippedFrameId = frameId;
    final sp = await SharedPreferences.getInstance();
    if (url != null && url.isNotEmpty) {
      await sp.setString('my_face_url', url);
    } else {
      await sp.remove('my_face_url');
    }
    if (frameId != null && frameId.isNotEmpty) {
      await sp.setString('my_equipped_frame_id', frameId);
    } else {
      await sp.remove('my_equipped_frame_id');
    }
    instance.notifyListeners();
  }

  static Future<void> setSpaceWallpaper(String? url) async {
    spaceWallpaper = url;
    final sp = await SharedPreferences.getInstance();
    if (url != null && url.isNotEmpty) {
      await sp.setString('space_wallpaper', url);
    } else {
      await sp.remove('space_wallpaper');
    }
    instance.notifyListeners();
  }

  static Future<void> setMinimizeToTrayOnClose(bool v) async {
    minimizeToTrayOnClose = v;
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('minimize_to_tray_on_close', v);
    } catch (_) {}
  }

  static Future<void> setBaseUrl(String url) async {
    baseUrl = url;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', url);
    instance.notifyListeners();
  }

  static Future<void> setStyle(AppStyle s) async {
    style = s;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('app_style', s.name);
    themeNotifier.notifyThemeChanged();
    instance.notifyListeners();
  }

  static Future<void> setCustomSeedColor(Color color) async {
    customSeedColorValue = color.toARGB32();
    useSystemMonet = false;
    style = AppStyle.custom;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('custom_seed_color', customSeedColorValue);
    await sp.setBool('use_system_monet', false);
    await sp.setString('app_style', AppStyle.custom.name);
    themeNotifier.notifyThemeChanged();
    instance.notifyListeners();
  }

  static Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('theme_mode', m.name);
    themeNotifier.notifyThemeChanged();
    instance.notifyListeners();
  }

  static Future<void> setIsOledDark(bool value) async {
    isOledDark = value;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('is_oled_dark', value);
    themeNotifier.notifyThemeChanged();
    instance.notifyListeners();
  }

  static Future<void> setLayoutMode(AppLayoutMode m) async {
    layoutMode = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('layout_mode', m.name);
    themeNotifier.notifyThemeChanged();
    instance.notifyListeners();
  }

  static Future<void> setUsePcUa(bool v) async {
    usePcUa = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('use_pc_ua', v);
    instance.notifyListeners();
  }

  static Future<void> setNavLayout(NavLayout l) async {
    navLayout = l;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('nav_layout', l.name);
    instance.notifyListeners();
  }

  static Future<void> setDesktopGridColumns(int cols) async {
    desktopGridColumns = cols;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('desktop_grid_columns', cols);
    instance.notifyListeners();
  }

  static Future<void> setIsMasterDetailEnabled(bool enabled) async {
    isMasterDetailEnabled = enabled;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('master_detail_enabled', enabled);
    instance.notifyListeners();
  }

  static Future<void> setCardStyle(CardStyle s) async {
    cardStyle = s;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('card_style', s.name);
    instance.notifyListeners();
  }

  static Future<void> setDensity(AppDensity d) async {
    density = d;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('density', d.name);
    themeNotifier.notifyThemeChanged();
    instance.notifyListeners();
  }

  static Future<void> setFontScale(double s) async {
    fontScale = ((s * 20).round() / 20.0).clamp(0.8, 1.4);
    themeNotifier.notifyThemeChanged();
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('font_scale', fontScale);
    } catch (_) {}
  }

  static Future<void> setAvatarShape(AvatarShape shape) async {
    avatarShape = shape;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('avatar_shape', shape.name);
    instance.notifyListeners();
  }

  static Future<void> setGpuAcceleration(bool enable) async {
    gpuAcceleration = enable;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('gpu_acceleration', enable);
    instance.notifyListeners();
  }

  static Future<void> setHighRefreshRate(bool enable) async {
    highRefreshRate = enable;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('high_refresh_rate', enable);
    instance.notifyListeners();
  }

  static Future<void> setImageQuality(ImageQuality quality) async {
    imageQuality = quality;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('image_quality', quality.name);
    instance.notifyListeners();
  }

  static Future<void> setImageCacheMaxMb(int mb) async {
    imageCacheMaxMb = mb;
    PaintingBinding.instance.imageCache.maximumSizeBytes = mb << 20;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('image_cache_max_mb', mb);
    instance.notifyListeners();
  }

  static Future<void> setSmoothScrollPhysics(bool enable) async {
    smoothScrollPhysics = enable;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('smooth_scroll_physics', enable);
    instance.notifyListeners();
  }

  static Future<void> setMultiThreadParsing(bool enable) async {
    enableMultiThreadParsing = enable;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('enable_multithread_parsing', enable);
    instance.notifyListeners();
  }

  static Future<void> setGpuAcceleratedRendering(bool enable) async {
    enableGpuAcceleratedRendering = enable;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('enable_gpu_rendering', enable);
    instance.notifyListeners();
  }

  static Future<void> setShowFloorSignature(bool show) async {
    showFloorSignature = show;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('show_floor_signature', show);
    instance.notifyListeners();
  }

  static Future<void> setShowThreadListImages(bool show) async {
    showThreadListImages = show;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('show_thread_list_images', show);
    instance.notifyListeners();
  }

  static Future<void> setUseSystemMonet(bool use) async {
    useSystemMonet = use;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('use_system_monet', use);
    themeNotifier.notifyThemeChanged();
    instance.notifyListeners();
  }

  static Future<void> setAutoCheckin(bool auto) async {
    autoCheckin = auto;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('auto_checkin', auto);
    await sp.setBool('auto_sign_on_launch', auto);
    instance.notifyListeners();
  }

  static Future<void> setFastWriteMode(bool fast) async {
    fastWriteMode = fast;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('fast_write_mode', fast);
    instance.notifyListeners();
  }

  static Future<void> setDefaultStartTab(int tab) async {
    defaultStartTab = tab;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('default_start_tab', tab);
    instance.notifyListeners();
  }

  static Future<void> addBlockedKeyword(String kw) async {
    if (kw.trim().isEmpty || blockedKeywords.contains(kw.trim())) return;
    blockedKeywords.add(kw.trim());
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('blocked_keywords', blockedKeywords);
    instance.notifyListeners();
  }

  static Future<void> removeBlockedKeyword(String kw) async {
    blockedKeywords.remove(kw);
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('blocked_keywords', blockedKeywords);
    instance.notifyListeners();
  }

  static Future<void> addBlockedUid(int uid) async {
    if (uid <= 0 || blockedUids.contains(uid)) return;
    blockedUids.add(uid);
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(
      'blocked_uids',
      blockedUids.map((e) => e.toString()).toList(),
    );
    instance.notifyListeners();
  }

  static Future<void> removeBlockedUid(int uid) async {
    blockedUids.remove(uid);
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(
      'blocked_uids',
      blockedUids.map((e) => e.toString()).toList(),
    );
    instance.notifyListeners();
  }

  static Future<void> setClipboardJumpEnabled(bool enable) async {
    clipboardJumpEnabled = enable;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('clipboard_jump_enabled', enable);
    instance.notifyListeners();
  }

  static Future<void> setClipboardJumpThreadEnabled(bool enable) async {
    clipboardJumpThreadEnabled = enable;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('clipboard_jump_thread_enabled', enable);
    instance.notifyListeners();
  }

  static Future<void> setClipboardJumpSearchEnabled(bool enable) async {
    clipboardJumpSearchEnabled = enable;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('clipboard_jump_search_enabled', enable);
    instance.notifyListeners();
  }

  static Future<void> setClipboardJumpConfirm(bool confirm) async {
    clipboardJumpConfirm = confirm;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('clipboard_jump_confirm', confirm);
    instance.notifyListeners();
  }

  static Future<void> setDownloadPath(String path) async {
    downloadPath = path;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('download_path', path);
    instance.notifyListeners();
  }

  static Future<void> setDownloadThreads(int threads) async {
    downloadThreads = threads.clamp(1, 8);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('download_threads', downloadThreads);
    instance.notifyListeners();
  }

  static Future<void> setAutoOpenFile(bool auto) async {
    autoOpenFile = auto;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('auto_open_file', auto);
    instance.notifyListeners();
  }

  // ================= DIY 模块化布局与工作台更新方法 =================
  static Future<void> setHomeModules(List<String> modules) async {
    homeModules = List.from(modules);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('diy_home_modules', homeModules);
    } catch (_) {}
  }

  static Future<void> setThreadLeftModules(List<String> modules) async {
    threadLeftModules = List.from(modules);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('diy_thread_left_modules', threadLeftModules);
    } catch (_) {}
  }

  static Future<void> setThreadRightModules(List<String> modules) async {
    threadRightModules = List.from(modules);
    // 同时同步 threadDashboardLayout，保证 2D 画布与工作台助手数据 100% 实时双向互通
    final existingMap = <String, DashboardGridItem>{};
    for (final item in threadDashboardLayout) {
      if (item.cardType != 'user_profile' && modules.contains(item.cardType)) {
        existingMap[item.cardType] = item;
      }
    }
    int r = 0;
    threadDashboardLayout = modules.map((id) {
      final existing = existingMap[id];
      final def = CardRegistry.get(id);
      final span = existing?.rowSpan ?? def.defaultRowSpan;
      final item = DashboardGridItem(
        id: existing?.id ?? 'th_$id',
        cardType: id,
        col: 8,
        row: r,
        colSpan: 4,
        rowSpan: span,
      );
      r += span;
      return item;
    }).toList();
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('diy_thread_right_modules', threadRightModules);
      final jsonStr = jsonEncode(threadDashboardLayout.map((e) => e.toJson()).toList());
      await sp.setString('thread_dashboard_layout_v2', jsonStr);
    } catch (_) {}
  }

  static Future<void> addThreadRightModule(String id) async {
    if (!threadRightModules.contains(id)) {
      final list = List<String>.from(threadRightModules)..add(id);
      await setThreadRightModules(list);
    }
  }

  static Future<void> removeThreadRightModule(String id) async {
    final list = List<String>.from(threadRightModules)..remove(id);
    await setThreadRightModules(list);
  }

  static void updateThreadLeftWidth(double width) {
    threadLeftWidth = width.clamp(180.0, 480.0);
  }

  static Future<void> setThreadLeftWidth(double width) async {
    updateThreadLeftWidth(width);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('diy_thread_left_width', threadLeftWidth);
    } catch (_) {}
  }

  static void updateThreadRightWidth(double width) {
    final clamped = width.clamp(180.0, 520.0);
    if ((threadRightWidth - clamped).abs() > 0.5) {
      threadRightWidth = clamped;
      threadRightWidthNotifier.value = clamped;
    }
  }

  static Future<void> setThreadRightWidth(double width) async {
    updateThreadRightWidth(width);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('diy_thread_right_width', threadRightWidth);
    } catch (_) {}
  }

  static void updateThreadContentMaxWidth(double width) {
    final clamped = width <= 0 ? 0.0 : width.clamp(600.0, 2400.0);
    if ((threadContentMaxWidth - clamped).abs() > 0.5) {
      threadContentMaxWidth = clamped;
      threadContentMaxWidthNotifier.value = clamped;
    }
  }

  static Future<void> setThreadContentMaxWidth(double width) async {
    updateThreadContentMaxWidth(width);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('diy_thread_content_max_width', threadContentMaxWidth);
    } catch (_) {}
  }

  static Future<void> setThreadLeftEnabled(bool enabled) async {
    threadLeftEnabled = enabled;
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('diy_thread_left_enabled', enabled);
    } catch (_) {}
  }

  static Future<void> setThreadRightEnabled(bool enabled) async {
    threadRightEnabled = enabled;
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('diy_thread_right_enabled', enabled);
    } catch (_) {}
  }

  static void updateThreadReaderFontSize(double size) {
    final clamped = size.clamp(12.0, 24.0);
    if ((threadReaderFontSize - clamped).abs() > 0.1) {
      threadReaderFontSize = clamped;
      threadReaderFontSizeNotifier.value = clamped;
    }
  }

  static Future<void> setThreadReaderFontSize(double size) async {
    updateThreadReaderFontSize(size);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('diy_thread_reader_font_size', threadReaderFontSize);
    } catch (_) {}
  }

  static void updateThreadReaderLineHeight(double height) {
    final clamped = height.clamp(1.2, 2.5);
    if ((threadReaderLineHeight - clamped).abs() > 0.05) {
      threadReaderLineHeight = clamped;
      threadReaderLineHeightNotifier.value = clamped;
    }
  }

  static Future<void> setThreadReaderLineHeight(double height) async {
    updateThreadReaderLineHeight(height);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('diy_thread_reader_line_height', threadReaderLineHeight);
    } catch (_) {}
  }

  static Future<void> setForumModules(List<String> modules) async {
    forumModules = List.from(modules);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('diy_forum_modules', forumModules);
    } catch (_) {}
  }

  static Future<void> resetDiyLayout() async {
    homeModules = List.from(defaultHomeModules);
    forumModules = List.from(defaultForumModules);
    threadLeftModules = List.from(defaultThreadLeftModules);
    threadRightModules = List.from(defaultThreadRightModules);
    threadForumSidebarWidth = 380.0;
    threadLeftWidth = 300.0;
    threadRightWidth = 320.0;
    threadContentMaxWidth = 960.0;
    threadLeftEnabled = true;
    threadRightEnabled = true;
    threadReaderFontSize = 15.0;
    threadReaderLineHeight = 1.6;
    threadForumSidebarWidthNotifier.value = 380.0;
    threadRightWidthNotifier.value = 320.0;
    threadContentMaxWidthNotifier.value = 960.0;
    threadReaderFontSizeNotifier.value = 15.0;
    threadReaderLineHeightNotifier.value = 1.6;
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('diy_home_modules');
      await sp.remove('diy_forum_modules');
      await sp.remove('diy_thread_left_modules');
      await sp.remove('diy_thread_right_modules');
      await sp.remove('thread_forum_sidebar_width');
      await sp.remove('diy_thread_left_width');
      await sp.remove('diy_thread_right_width');
      await sp.remove('diy_thread_content_max_width');
      await sp.remove('diy_thread_left_enabled');
      await sp.remove('diy_thread_right_enabled');
      await sp.remove('diy_thread_reader_font_size');
      await sp.remove('diy_thread_reader_line_height');
    } catch (_) {}
  }

  static Future<void> setHomeDashboardLayout(List<DashboardGridItem> items) async {
    homeDashboardLayout = List.from(items);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(homeDashboardLayout.map((e) => e.toJson()).toList());
      await sp.setString('home_dashboard_layout_v2', jsonStr);
    } catch (_) {}
  }

  static Future<void> setHomeShowLeftCards(bool val) async {
    homeShowLeftCards = val;
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('home_show_left_cards_v3', val);
      await sp.setBool('home_show_left_cards', val);
    } catch (_) {}
  }

  static Future<void> setHomeShowRightCards(bool val) async {
    homeShowRightCards = val;
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('home_show_right_cards_v3', val);
      await sp.setBool('home_show_right_cards', val);
    } catch (_) {}
  }

  static void updateHomeLeftSidebarWidth(double width) {
    final clamped = width.clamp(200.0, 480.0);
    if ((homeLeftSidebarWidth - clamped).abs() > 0.5) {
      homeLeftSidebarWidth = clamped;
      homeLeftSidebarWidthNotifier.value = clamped;
    }
  }

  static Future<void> setHomeLeftSidebarWidth(double width) async {
    updateHomeLeftSidebarWidth(width);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('home_left_sidebar_width', width);
    } catch (_) {}
  }

  static void updateHomeRightSidebarWidth(double width) {
    final clamped = width.clamp(200.0, 480.0);
    if ((homeRightSidebarWidth - clamped).abs() > 0.5) {
      homeRightSidebarWidth = clamped;
      homeRightSidebarWidthNotifier.value = clamped;
    }
  }

  static Future<void> setHomeRightSidebarWidth(double width) async {
    updateHomeRightSidebarWidth(width);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('home_right_sidebar_width', width);
    } catch (_) {}
  }

  static void updateThreadForumSidebarWidth(double width) {
    final clamped = width.clamp(240.0, 720.0);
    if ((threadForumSidebarWidth - clamped).abs() > 0.5) {
      threadForumSidebarWidth = clamped;
      threadForumSidebarWidthNotifier.value = clamped;
    }
  }

  static Future<void> setThreadForumSidebarWidth(double width) async {
    updateThreadForumSidebarWidth(width);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('thread_forum_sidebar_width', threadForumSidebarWidth);
    } catch (_) {}
  }

  static void ensureServerStatusInHomeLayout() {
    final hasLeft = homeDashboardLayout.any((c) => (c.col + c.colSpan / 2.0) < 6);
    if (homeDashboardLayout.isEmpty || !hasLeft) {
      homeDashboardLayout = CardRegistry.getDefaultHomeLayout();
      setHomeDashboardLayout(homeDashboardLayout);
      return;
    }
    if (!homeDashboardLayout.any((e) => e.cardType == 'server_status')) {
      int maxRow = 0;
      for (final item in homeDashboardLayout.where((c) => (c.col + c.colSpan / 2.0) >= 6)) {
        final bottom = item.row + item.rowSpan;
        if (bottom > maxRow) maxRow = bottom;
      }
      homeDashboardLayout.add(
        DashboardGridItem(
          id: 'server_status_1',
          cardType: 'server_status',
          col: 8,
          row: maxRow,
          colSpan: 4,
          rowSpan: 2,
        ),
      );
      setHomeDashboardLayout(homeDashboardLayout);
    }
  }

  static Future<void> resetHomeDashboardLayout() async {
    homeDashboardLayout = CardRegistry.getDefaultHomeLayout();
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('home_dashboard_layout_v2');
    } catch (_) {}
  }

  static Future<void> setThreadDashboardLayout(List<DashboardGridItem> items) async {
    final sorted = List<DashboardGridItem>.from(items)
      ..sort((a, b) => a.row.compareTo(b.row));
    threadDashboardLayout = sorted.where((e) => e.cardType != 'user_profile').map((e) {
      return e.copyWith(col: 8, colSpan: 4);
    }).toList();
    final moduleIds = threadDashboardLayout.map((e) => e.cardType).toSet().toList();
    threadRightModules = List.from(moduleIds);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(threadDashboardLayout.map((e) => e.toJson()).toList());
      await sp.setString('thread_dashboard_layout_v2', jsonStr);
      await sp.setStringList('diy_thread_right_modules', threadRightModules);
    } catch (_) {}
  }

  static Future<void> resetThreadDashboardLayout() async {
    threadDashboardLayout = [];
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('thread_dashboard_layout_v2');
    } catch (_) {}
  }

  static Future<void> setGuideDashboardLayout(List<DashboardGridItem> items) async {
    int curRow = 0;
    guideDashboardLayout = items.map((e) {
      final span = e.rowSpan;
      final copy = e.copyWith(col: 8, row: curRow, colSpan: 4, rowSpan: span);
      curRow += span;
      return copy;
    }).toList();
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(guideDashboardLayout.map((e) => e.toJson()).toList());
      await sp.setString('guide_dashboard_layout_v1', jsonStr);
    } catch (_) {}
  }

  static Future<void> resetGuideDashboardLayout() async {
    guideDashboardLayout = CardRegistry.getDefaultGuideLayout();
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('guide_dashboard_layout_v1');
    } catch (_) {}
  }

  static Future<void> setMainContentMinWidth(double width) async {
    mainContentMinWidth = width.clamp(400.0, 1000.0);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('main_content_min_width', mainContentMinWidth);
    } catch (_) {}
  }

  static Future<void> setDashboardSidebarPosition(String pos) async {
    dashboardSidebarPosition = pos;
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('dashboard_sidebar_position', pos);
    } catch (_) {}
  }

  static Future<void> applyHomeDashboardPreset(String presetKey) async {
    switch (presetKey) {
      case 'geek':
        homeDashboardLayout = CardRegistry.getGeekProductivityLayout();
        break;
      case 'collector':
        homeDashboardLayout = CardRegistry.getCollectorLayout();
        break;
      case 'minimal':
        homeDashboardLayout = CardRegistry.getMinimalLayout();
        break;
      case 'default':
      default:
        homeDashboardLayout = CardRegistry.getDefaultHomeLayout();
        break;
    }
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(homeDashboardLayout.map((e) => e.toJson()).toList());
      await sp.setString('home_dashboard_layout_v2', jsonStr);
    } catch (_) {}
  }

  static Future<void> resetAllDashboards() async {
    await resetHomeDashboardLayout();
    await resetThreadDashboardLayout();
    await resetGuideDashboardLayout();
    await setMainContentMinWidth(620.0);
    await setDashboardSidebarPosition('top');
  }

  // ================= 移动端首页轻量自定义控制 =================
  static Future<void> setMobileHomeSections(List<String> sections) async {
    mobileHomeSections = List.from(sections);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('mobile_home_sections', mobileHomeSections);
    } catch (_) {}
  }

  static Future<void> setMobileQuickActions(List<String> actions) async {
    mobileQuickActions = List.from(actions);
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('mobile_quick_actions', mobileQuickActions);
    } catch (_) {}
  }

  static Future<void> applyMobileHomePreset(String presetKey) async {
    switch (presetKey) {
      case 'minimal':
        mobileHomeSections = ['quick_actions', 'carousel'];
        mobileQuickActions = ['papa_ai', 'forum_nav', 'checkin', 'search'];
        break;
      case 'nav':
        mobileHomeSections = ['horn_banner', 'quick_actions', 'forum_nav'];
        mobileQuickActions = ['forum_nav', 'checkin', 'favorites', 'search'];
        break;
      case 'classic':
      case 'default':
      default:
        mobileHomeSections = List.from(defaultMobileHomeSections);
        mobileQuickActions = List.from(defaultMobileQuickActions);
        break;
    }
    instance.notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('mobile_home_sections', mobileHomeSections);
      await sp.setStringList('mobile_quick_actions', mobileQuickActions);
    } catch (_) {}
  }

  static Future<void> resetMobileHomeConfig() async {
    await applyMobileHomePreset('default');
  }

  // 兼容老代码的函数
  static Future<void> loadStyle() async => loadAll();
  static Future<void> loadNavLayout() async => loadAll();
}
