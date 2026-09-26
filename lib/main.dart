import 'dart:async';
import 'dart:io';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'api/klpbbs_api.dart';
import 'core/app_config.dart';
import 'core/cache_manager.dart';
import 'core/dio_client.dart';
import 'core/main_tab_controller.dart';
import 'pages/darkroom_page.dart';
import 'pages/forums_page.dart';
import 'pages/guide_page.dart';
import 'pages/home_page.dart';
import 'pages/medal_page.dart';
import 'pages/papa_ai_chat_page.dart';
import 'pages/post_page.dart';
import 'pages/ranklist_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/notice_page.dart';
import 'pages/sign_rank_page.dart';
import 'pages/user_center_page.dart';
import 'services/auto_sign_service.dart';
import 'services/clipboard_jump_service.dart';
import 'services/download_service.dart';
import 'services/push_notification_service.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'services/auto_test_screenshot_service.dart';
import 'services/rgb_theme_service.dart';
import 'services/tray_service.dart';
import 'widgets/fade_indexed_stack.dart';
import 'widgets/global_app_drawer.dart';
import 'widgets/in_app_notification_overlay.dart';
import 'widgets/responsive_layout.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
WebViewEnvironment? appWebViewEnvironment;
bool isWebView2Available = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局防御：拦截局部 Widget 渲染异常，防止 Release 模式下显示 0xF0C0C0C0 灰色大方块遮盖界面
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('全局 Widget 渲染异常捕获: ${details.exception}');
    return const SizedBox.shrink();
  };

  // 初始化 Windows 平台 WebView2 环境（设定独立可写用户数据目录，避免黑屏与权限异常）
  if (!kIsWeb && Platform.isWindows) {
    try {
      final availableVersion = await WebViewEnvironment.getAvailableVersion();
      if (availableVersion != null && availableVersion.isNotEmpty) {
        isWebView2Available = true;
        final appSupport = await getApplicationSupportDirectory();
        final userDataFolder = '${appSupport.path}\\webview2_userdata';
        final dir = Directory(userDataFolder);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        appWebViewEnvironment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: userDataFolder),
        );
      }
    } catch (e) {
      debugPrint('WebView2 初始化失败: $e');
    }
  }

  // 优化图片内存缓存上限（避免长期持有数千张解码位图导致内存膨胀 2GB+ 以及显存/WDDM 频繁换页卡顿）
  final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  PaintingBinding.instance.imageCache.maximumSize = isDesktop ? 300 : (isMobile ? 200 : 150);
  PaintingBinding.instance.imageCache.maximumSizeBytes = isDesktop
      ? 128 * 1024 * 1024
      : (isMobile ? 64 * 1024 * 1024 : 32 * 1024 * 1024);

  MediaKit.ensureInitialized();
  await AppConfig.loadAll();
  await DioClient.loadCookies();
  DioClient.onSessionCleared = () async {
    await KlpbbsApi.clearUserProfileCache();
    try {
      final cookieManager = (!kIsWeb && Platform.isWindows && appWebViewEnvironment != null)
          ? CookieManager.instance(webViewEnvironment: appWebViewEnvironment)
          : CookieManager.instance();
      await cookieManager.deleteAllCookies();
    } catch (e) {
      debugPrint('清理 WebView Cookies 失败: $e');
    }
  };
  await KlpbbsApi.initUserProfileCache();
  await KlpbbsApi.sanitizeFavoriteCache();
  unawaited(KlpbbsCacheManager.purgeCorruptedCache());
  await DownloadManager.instance.init();
  await RgbThemeService.instance.init();
  await PushNotificationService.instance.init();
  await TrayService.instance.init();
  await AutoSignService.instance.init();
  await ClipboardJumpService.instance.init();

  PushNotificationService.instance.onOpenNoticeCallback = () {
    TrayService.instance.showWindow();
    appNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NoticePage()),
    );
  };

  AppConfig.ensureServerStatusInHomeLayout();
  await KlpbbsApi.primeHomeCache();

  runApp(const KlpbbsApp());

  AutoTestScreenshotService.maybeTriggerTestingRoutine(appNavigatorKey);
}

/// klpbbs 客户端（全功能重构 + PC 桌面与移动端双排版 + 高级自定义）
class KlpbbsApp extends StatelessWidget {
  const KlpbbsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return ListenableBuilder(
          listenable: Listenable.merge([AppConfig.themeNotifier, RgbThemeService.instance]),
          builder: (context, _) {
            final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
            final useDynamic = isAndroid && AppConfig.useSystemMonet && lightDynamic != null;

            final seed = AppConfig.seedColor;
            final density = AppConfig.density.toVisualDensity;
            final isOled = AppConfig.isOledDark;

            final isRgb = RgbThemeService.instance.isEnabled;
            final ColorScheme lightColorScheme;
            final ColorScheme darkColorScheme;
            final int themeCacheKey;

            if (isRgb) {
              themeCacheKey = RgbThemeService.instance.currentHueIndex;
              lightColorScheme = RgbThemeService.instance.getLightColorScheme();
              darkColorScheme = RgbThemeService.instance.getDarkColorScheme(isOled: isOled);
            } else if (useDynamic) {
              themeCacheKey = 0x10000000 | (lightDynamic.primary.toARGB32() & 0x00FFFFFF);
              lightColorScheme = lightDynamic;
              final baseDark = darkDynamic ??
                  ColorScheme.fromSeed(
                    seedColor: seed,
                    brightness: Brightness.dark,
                  );
              darkColorScheme = isOled
                  ? baseDark.copyWith(
                      surface: Colors.black,
                      surfaceContainerLowest: Colors.black,
                      surfaceContainerLow: const Color(0xFF0C0E0D),
                      surfaceContainer: const Color(0xFF141715),
                      surfaceContainerHigh: const Color(0xFF1C201E),
                      surfaceContainerHighest: const Color(0xFF242927),
                      outlineVariant: const Color(0xFF323A35),
                    )
                  : baseDark.copyWith(
                      surface: const Color(0xFF151917),
                      surfaceContainerLowest: const Color(0xFF101312),
                      surfaceContainerLow: const Color(0xFF171B19),
                      surfaceContainer: const Color(0xFF1E2320),
                      surfaceContainerHigh: const Color(0xFF252B28),
                      surfaceContainerHighest: const Color(0xFF2D3430),
                      outlineVariant: const Color(0xFF3A443E),
                    );
            } else {
              themeCacheKey = seed.toARGB32();
              lightColorScheme = ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.light,
              );
              final baseDark = ColorScheme.fromSeed(
                seedColor: seed,
                brightness: Brightness.dark,
              );
              darkColorScheme = isOled
                  ? baseDark.copyWith(
                      surface: Colors.black,
                      surfaceContainerLowest: Colors.black,
                      surfaceContainerLow: const Color(0xFF0C0E0D),
                      surfaceContainer: const Color(0xFF141715),
                      surfaceContainerHigh: const Color(0xFF1C201E),
                      surfaceContainerHighest: const Color(0xFF242927),
                      outlineVariant: const Color(0xFF323A35),
                    )
                  : baseDark.copyWith(
                      surface: const Color(0xFF151917),
                      surfaceContainerLowest: const Color(0xFF101312),
                      surfaceContainerLow: const Color(0xFF171B19),
                      surfaceContainer: const Color(0xFF1E2320),
                      surfaceContainerHigh: const Color(0xFF252B28),
                      surfaceContainerHighest: const Color(0xFF2D3430),
                      outlineVariant: const Color(0xFF3A443E),
                    );
            }

            final lightTheme = _AppThemeDataCache.getLight(
              key: themeCacheKey,
              colorScheme: lightColorScheme,
              seed: seed,
              useDynamic: useDynamic,
              density: density,
            );

            final darkTheme = _AppThemeDataCache.getDark(
              key: themeCacheKey,
              colorScheme: darkColorScheme,
              isOled: isOled,
              density: density,
            );

            return MaterialApp(
              navigatorKey: appNavigatorKey,
              title: '苦力怕论坛',
              debugShowCheckedModeBanner: false,
              color: const Color(0xFFF6F8F7),
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: AppConfig.themeMode,
              themeAnimationDuration: isRgb ? Duration.zero : kThemeAnimationDuration,
              builder: (context, child) {
                final theme = Theme.of(context);
                final globalShortcuts = <ShortcutActivator, VoidCallback>{
                  // Ctrl+N / Cmd+N: 新建发帖
                  const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
                    appNavigatorKey.currentState?.push(
                      MaterialPageRoute(builder: (_) => const PostPage()),
                    );
                  },
                  const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () {
                    appNavigatorKey.currentState?.push(
                      MaterialPageRoute(builder: (_) => const PostPage()),
                    );
                  },
                  // Ctrl+F / Cmd+F: 全局搜索
                  const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
                    appNavigatorKey.currentState?.push(
                      MaterialPageRoute(builder: (_) => const SearchPage()),
                    );
                  },
                  const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
                    appNavigatorKey.currentState?.push(
                      MaterialPageRoute(builder: (_) => const SearchPage()),
                    );
                  },
                  // Escape: 关闭弹窗或返回
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    final nav = appNavigatorKey.currentState;
                    if (nav != null && nav.canPop()) {
                      nav.maybePop();
                    }
                  },
                };

                return CallbackShortcuts(
                  bindings: globalShortcuts,
                  child: FocusScope(
                    child: RepaintBoundary(
                      key: AutoTestScreenshotService.rootKey,
                      child: Container(
                        color: theme.scaffoldBackgroundColor,
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(AppConfig.fontScale),
                          ),
                          child: GlobalInAppNotificationOverlay(child: child!),
                        ),
                      ),
                    ),
                  ),
                );
              },
              scrollBehavior: const MaterialScrollBehavior().copyWith(
                scrollbars: true,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              home: const _MainShell(),
            );
          },
        );
      },
    );
  }
}

/// 针对全局动态主题与 RGB 炫彩流光的内存级高性能 ThemeData 缓存池
class _AppThemeDataCache {
  static final Map<int, ThemeData> _lightCache = {};
  static final Map<int, ThemeData> _darkCache = {};
  static VisualDensity? _lastDensity;
  static bool? _lastIsOled;

  static ThemeData getLight({
    required int key,
    required ColorScheme colorScheme,
    required Color seed,
    required bool useDynamic,
    required VisualDensity density,
  }) {
    if (_lastDensity != density) {
      _lastDensity = density;
      _lightCache.clear();
      _darkCache.clear();
    }
    return _lightCache[key] ??= _buildLightTheme(
      colorScheme: colorScheme,
      seed: seed,
      useDynamic: useDynamic,
      density: density,
    );
  }

  static ThemeData getDark({
    required int key,
    required ColorScheme colorScheme,
    required bool isOled,
    required VisualDensity density,
  }) {
    if (_lastIsOled != isOled || _lastDensity != density) {
      _lastIsOled = isOled;
      _lastDensity = density;
      _lightCache.clear();
      _darkCache.clear();
    }
    return _darkCache[key] ??= _buildDarkTheme(
      colorScheme: colorScheme,
      isOled: isOled,
      density: density,
    );
  }

  static ThemeData _buildLightTheme({
    required ColorScheme colorScheme,
    required Color seed,
    required bool useDynamic,
    required VisualDensity density,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: (!kIsWeb && Platform.isWindows) ? 'Microsoft YaHei UI' : null,
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
        'WenQuanYi Micro Hei',
        'Segoe UI Emoji',
        'Noto Color Emoji',
        'Apple Color Emoji',
      ],
      visualDensity: density,
      scaffoldBackgroundColor: const Color(0xFFF6F8F7),
      appBarTheme: AppBarTheme(
        leadingWidth: (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ? 96.0 : null,
        elevation: 1,
        centerTitle: false,
        scrolledUnderElevation: 2,
        backgroundColor: useDynamic ? colorScheme.primary : seed,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          fontSize: 17.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: Colors.white,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.none,
        elevation: 0.5,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(50),
            width: 0.8,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withAlpha(35),
        thickness: 0.6,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        backgroundColor: colorScheme.secondaryContainer,
        contentTextStyle: TextStyle(
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  static ThemeData _buildDarkTheme({
    required ColorScheme colorScheme,
    required bool isOled,
    required VisualDensity density,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: (!kIsWeb && Platform.isWindows) ? 'Microsoft YaHei UI' : null,
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
        'WenQuanYi Micro Hei',
        'Segoe UI Emoji',
        'Noto Color Emoji',
        'Apple Color Emoji',
      ],
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isOled ? Colors.black : const Color(0xFF111413),
      visualDensity: density,
      appBarTheme: AppBarTheme(
        leadingWidth: (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ? 96.0 : null,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 1.5,
        backgroundColor: isOled ? Colors.black : const Color(0xFF171B19),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          fontSize: 17.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: Colors.white,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isOled ? Colors.black : const Color(0xFF171B19),
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primary.withAlpha(50),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.none,
        elevation: 0,
        color: isOled ? const Color(0xFF111312) : const Color(0xFF1B201D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(70),
            width: 0.8,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isOled ? const Color(0xFF141615) : const Color(0xFF1F2522),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 6,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isOled ? const Color(0xFF141615) : const Color(0xFF1F2522),
        modalBackgroundColor: isOled ? const Color(0xFF141615) : const Color(0xFF1F2522),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isOled ? const Color(0xFF181A19) : const Color(0xFF242A27),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant.withAlpha(60), width: 0.6),
        ),
        elevation: 4,
        textStyle: const TextStyle(
          color: Color(0xFFE2E8F0),
          fontSize: 13.5,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isOled ? const Color(0xFF121413) : const Color(0xFF1A1F1D),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(70)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withAlpha(70)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isOled ? const Color(0xFF161817) : const Color(0xFF222825),
        labelStyle: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12.5),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(50), width: 0.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: true,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withAlpha(70),
        selectionHandleColor: colorScheme.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        backgroundColor: isOled ? const Color(0xFF222624) : const Color(0xFF262E2A),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withAlpha(40),
        thickness: 0.6,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  late int _index;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _index = AppConfig.defaultStartTab.clamp(0, 4);
    mainTabIndex.value = _index;
    mainTabIndex.addListener(_onGlobalTabChanged);
  }

  void _onGlobalTabChanged() {
    if (!mounted) return;
    final v = mainTabIndex.value.clamp(0, 4);
    if (_index != v) setState(() => _index = v);
  }

  @override
  void dispose() {
    mainTabIndex.removeListener(_onGlobalTabChanged);
    super.dispose();
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final navItems = [
      const NavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: '首页',
      ),
      const NavItem(
        icon: Icons.forum_outlined,
        selectedIcon: Icons.forum_rounded,
        label: '版块',
      ),
      const NavItem(
        icon: Icons.event_available_outlined,
        selectedIcon: Icons.event_available_rounded,
        label: '签到',
      ),
      const NavItem(
        icon: Icons.military_tech_outlined,
        selectedIcon: Icons.military_tech,
        label: '勋章',
      ),
      const NavItem(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: '个人中心',
      ),
      NavItem(
        icon: Icons.smart_toy_outlined,
        selectedIcon: Icons.smart_toy_rounded,
        label: '帕帕 AI',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PapaAiChatPage()),
          );
        },
      ),
      NavItem(
        icon: Icons.local_fire_department_outlined,
        selectedIcon: Icons.local_fire_department_rounded,
        label: '导读',
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const GuidePage()));
        },
      ),
      NavItem(
        icon: Icons.search_outlined,
        selectedIcon: Icons.search_rounded,
        label: '搜索',
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SearchPage()));
        },
      ),
      NavItem(
        icon: Icons.gavel_outlined,
        selectedIcon: Icons.gavel_rounded,
        label: '封神榜',
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const DarkroomPage()));
        },
      ),
      NavItem(
        icon: Icons.leaderboard_outlined,
        selectedIcon: Icons.leaderboard_rounded,
        label: '排行榜',
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const RanklistPage()));
        },
      ),
      NavItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: '设置',
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
        },
      ),
    ];

    // 主页面堆栈（添加 RepaintBoundary 隔离，未激活的页面在 RGB 变换时不重复光栅化绘制）
    final pages = [
      RepaintBoundary(
        child: HomePage(
          onSwitchTab: (i) => setState(() => _index = i),
          showDrawerButton: true,
          onOpenDrawer: _openDrawer,
          onOpenSettings: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
          },
        ),
      ),
      const RepaintBoundary(child: ForumsPage()),
      const RepaintBoundary(child: SignRankPage()),
      const RepaintBoundary(child: MedalPage()),
      const RepaintBoundary(child: UserCenterPage()),
    ];

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) {
          setState(() => _index = 0);
          mainTabIndex.value = 0;
        }
      },
      child: AdaptiveScaffold(
        scaffoldKey: _scaffoldKey,
        currentIndex: _index.clamp(0, pages.length - 1),
      onNavigationChanged: (i) {
        if (i < pages.length) {
          if (_index == i) {
            HapticFeedback.lightImpact();
          } else {
            HapticFeedback.selectionClick();
            setState(() => _index = i);
            mainTabIndex.value = i;
          }
        }
      },
      navItems: navItems,
      drawer: GlobalAppDrawer(currentTabIndex: _index),
      floatingActionButton: null,
      body: FadeIndexedStack(
        index: _index.clamp(0, pages.length - 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        children: pages,
      ),
    ),
  );
}
}
