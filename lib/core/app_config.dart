import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  grid('瀑布流网格卡片');

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

/// 全局应用配置与状态控制器
class AppConfig extends ChangeNotifier {
  static final AppConfig instance = AppConfig._();
  AppConfig._();

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
      return {
        'Referer': 'https://klpbbs.com/',
        'User-Agent': pcUserAgent,
        'Accept': imageAccept,
      };
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

  /// 将低清缩略图自动提升为高清原图 URL（去除 Discuz .thumb.jpg、&thumb=yes 等低清压缩参数）
  static String? toHighResImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    var clean = url.trim();

    // 1. 去除 Discuz 缩略图后缀：xxx.jpg.thumb.jpg -> xxx.jpg, xxx.png.thumb.png -> xxx.png, xxx.thumb.jpg -> xxx.jpg
    clean = clean.replaceAll(RegExp(r'\.(?:thumb|small|middle)\.(?:jpg|png|webp|jpeg)$', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'(\.(?:jpg|png|webp|jpeg|gif))\.thumb\.(?:jpg|png|webp|jpeg)$', caseSensitive: false), r'$1');
    clean = clean.replaceAll(RegExp(r'_(?:thumb|small|middle)\.(?:jpg|png|webp|jpeg)$', caseSensitive: false), '.jpg');

    // 2. 去除 URL query 中的 thumb 参数：&thumb=yes, &thumb=1, &thumb=2
    if (clean.contains('thumb=')) {
      clean = clean.replaceAll(RegExp(r'[?&]thumb=(?:yes|1|2|true)', caseSensitive: false), '');
      if (clean.contains('?') && !clean.contains('=')) {
        clean = clean.replaceAll('?', '');
      }
    }

    // 3. 处理 thumb.php 代理链接：pic/thumb.php?w=200&h=150&src=http... -> 提取 src
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

  // 论坛与阅读偏好
  static bool showFloorSignature = true;
  static bool autoCheckin = false;
  static bool fastWriteMode = false;
  static int defaultStartTab = 0;
  static List<String> blockedKeywords = [];
  static List<int> blockedUids = [];

  // 下载与存储管理
  static String downloadPath = '';
  static int downloadThreads = 4;
  static bool autoOpenFile = false;

  // 消息推送与托盘后台
  static bool minimizeToTrayOnClose = true;

  // 空间个性化
  static String? spaceWallpaper;

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
      smoothScrollPhysics = sp.getBool('smooth_scroll_physics') ?? true;

      // 论坛功能
      showFloorSignature = sp.getBool('show_floor_signature') ?? true;
      autoCheckin = sp.getBool('auto_checkin') ?? false;
      fastWriteMode = sp.getBool('fast_write_mode') ?? false;
      defaultStartTab = sp.getInt('default_start_tab') ?? 0;
      blockedKeywords = sp.getStringList('blocked_keywords') ?? [];
      blockedUids = (sp.getStringList('blocked_uids') ?? [])
          .map((e) => int.tryParse(e) ?? 0)
          .where((uid) => uid > 0)
          .toList();

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
    instance.notifyListeners();
  }

  static Future<void> setCustomSeedColor(Color color) async {
    customSeedColorValue = color.toARGB32();
    style = AppStyle.custom;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('custom_seed_color', customSeedColorValue);
    await sp.setString('app_style', AppStyle.custom.name);
    instance.notifyListeners();
  }

  static Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('theme_mode', m.name);
    instance.notifyListeners();
  }

  static Future<void> setIsOledDark(bool value) async {
    isOledDark = value;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('is_oled_dark', value);
    instance.notifyListeners();
  }

  static Future<void> setLayoutMode(AppLayoutMode m) async {
    layoutMode = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('layout_mode', m.name);
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
    instance.notifyListeners();
  }

  static Future<void> setFontScale(double s) async {
    fontScale = ((s * 20).round() / 20.0).clamp(0.8, 1.4);
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

  static Future<void> setShowFloorSignature(bool show) async {
    showFloorSignature = show;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('show_floor_signature', show);
    instance.notifyListeners();
  }

  static Future<void> setAutoCheckin(bool auto) async {
    autoCheckin = auto;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('auto_checkin', auto);
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

  // 兼容老代码的函数
  static Future<void> loadStyle() async => loadAll();
  static Future<void> loadNavLayout() async => loadAll();
}
