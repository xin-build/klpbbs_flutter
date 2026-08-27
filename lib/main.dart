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
import 'core/dio_client.dart';
import 'core/main_tab_controller.dart';
import 'core/write_confirm.dart';
import 'pages/credit_page.dart';
import 'pages/darkroom_page.dart';
import 'pages/forums_page.dart';
import 'pages/guide_page.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/magic_page.dart';
import 'pages/medal_page.dart';
import 'pages/post_page.dart';
import 'pages/profile_settings_page.dart';
import 'pages/ranklist_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/notice_page.dart';
import 'pages/sign_rank_page.dart';
import 'pages/user_center_page.dart';
import 'pages/user_space_page.dart';
import 'services/auto_sign_service.dart';
import 'services/download_service.dart';
import 'services/push_notification_service.dart';
import 'services/rgb_theme_service.dart';
import 'services/tray_service.dart';
import 'widgets/in_app_notification_overlay.dart';
import 'widgets/responsive_layout.dart';
import 'widgets/thread_card.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 开启全平台 GPU 显卡硬件纹理与光栅化缓存加速（Desktop 512MB / Mobile 256MB VRAM 材质池）
  final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  PaintingBinding.instance.imageCache.maximumSize = isDesktop ? 2000 : (isMobile ? 1200 : 800);
  PaintingBinding.instance.imageCache.maximumSizeBytes = isDesktop
      ? 512 * 1024 * 1024
      : (isMobile ? 256 * 1024 * 1024 : 128 * 1024 * 1024);

  MediaKit.ensureInitialized();
  await AppConfig.loadAll();
  await DioClient.loadCookies();
  await DownloadManager.instance.init();
  await RgbThemeService.instance.init();
  await PushNotificationService.instance.init();
  await TrayService.instance.init();
  await AutoSignService.instance.init();

  PushNotificationService.instance.onOpenNoticeCallback = () {
    TrayService.instance.showWindow();
    appNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NoticePage()),
    );
  };

  runApp(const KlpbbsApp());
}

/// klpbbs 客户端（全功能重构 + PC 桌面与移动端双排版 + 高级自定义）
class KlpbbsApp extends StatelessWidget {
  const KlpbbsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return ListenableBuilder(
          listenable: Listenable.merge([AppConfig.instance, RgbThemeService.instance]),
          builder: (context, _) {
            final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
            final isCustomMonet = AppConfig.style == AppStyle.custom;
            final useDynamic = isAndroid && isCustomMonet && lightDynamic != null;

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
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'Noto Color Emoji',
        'Apple Color Emoji',
        'Segoe UI Emoji',
      ],
      visualDensity: density,
      scaffoldBackgroundColor: const Color(0xFFF6F8F7),
      appBarTheme: AppBarTheme(
        elevation: 1,
        centerTitle: false,
        scrolledUnderElevation: 2,
        backgroundColor: useDynamic ? colorScheme.primary : seed,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          fontSize: 17.5,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
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
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'Noto Color Emoji',
        'Apple Color Emoji',
        'Segoe UI Emoji',
      ],
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isOled ? Colors.black : const Color(0xFF111413),
      visualDensity: density,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 1.5,
        backgroundColor: isOled ? Colors.black : const Color(0xFF171B19),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          fontSize: 17.5,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.15,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isOled ? Colors.black : const Color(0xFF171B19),
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primary.withAlpha(50),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
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
  int? _myUid;

  @override
  void initState() {
    super.initState();
    _index = AppConfig.defaultStartTab.clamp(0, 4);
    _refreshMyUid();
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

  Future<void> _refreshMyUid() async {
    final uid = await KlpbbsApi.getMyUid();
    if (mounted) setState(() => _myUid = uid);
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _openPost() {
    confirmWrite(context, '发帖').then((ok) {
      if (ok && mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PostPage()));
      }
    });
  }

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
          }
        }
      },
      navItems: navItems,
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              InkWell(
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  final uid = _myUid ?? await KlpbbsApi.getMyUid();
                  if (uid != null && uid > 0) {
                    nav.push(
                      MaterialPageRoute(builder: (_) => UserSpacePage(uid: uid, isMe: true)),
                    ).then((_) => _refreshMyUid());
                  } else {
                    nav.push(
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    ).then((_) => _refreshMyUid());
                  }
                },
                child: DrawerHeader(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (DioClient.isLoggedIn && _myUid != null)
                        Row(
                          children: [
                            UserAvatarWidget(uid: _myUid!, author: '我', size: 48),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '已登录',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '点击进入我的空间 >',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        const Text(
                          '点击登录',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      const SizedBox(height: 4),
                      const Text(
                        '苦力怕论坛 · KLPBBS',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              for (int i = 0; i < navItems.length; i++)
                ListTile(
                  leading: Icon(
                    _index == i ? navItems[i].selectedIcon : navItems[i].icon,
                  ),
                  title: Text(navItems[i].label),
                  selected: _index == i,
                  onTap: () {
                    Navigator.of(context).pop();
                    if (navItems[i].onTap != null) {
                      navItems[i].onTap!();
                    } else if (i < pages.length) {
                      setState(() => _index = i);
                    }
                  },
                ),
              const Divider(),
              if (DioClient.isLoggedIn) ...[
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: const Text('我的空间'),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    nav.pop();
                    final uid = _myUid ?? await KlpbbsApi.getMyUid();
                    if (uid != null && uid > 0) {
                      nav.push(
                        MaterialPageRoute(builder: (_) => UserSpacePage(uid: uid, isMe: true)),
                      ).then((_) => _refreshMyUid());
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('资料设置'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ProfileSettingsPage(uid: _myUid)),
                    ).then((_) => _refreshMyUid());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('积分中心'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreditPage(initialTabIndex: 0)),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.military_tech_outlined),
                  title: const Text('勋章中心'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MedalPage()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.auto_fix_high_outlined),
                  title: const Text('道具中心'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MagicPage()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout_outlined),
                  title: const Text('退出登录'),
                  onTap: () {
                    Navigator.of(context).pop();
                    KlpbbsApi.logout().then((_) {
                      if (mounted) setState(() => _myUid = null);
                    });
                  },
                ),
              ] else
                ListTile(
                  leading: const Icon(Icons.login_outlined),
                  title: const Text('登录'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        )
                        .then((_) => _refreshMyUid());
                  },
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '苦力怕论坛客户端 v1.0.4',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 11.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: _openPost,
              tooltip: '发帖',
              icon: const Icon(Icons.edit_rounded),
              label: const Text('发帖'),
            )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_index.clamp(0, pages.length - 1)),
          child: IndexedStack(
            index: _index.clamp(0, pages.length - 1),
            children: pages,
          ),
        ),
      ),
    ),
  );
}
}
