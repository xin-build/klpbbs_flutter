import '../core/discuz_magic_protocol.dart';
import '../core/discuz_task_protocol.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../core/dio_client.dart';
import '../core/discuz_request_policy.dart';
import '../core/discuz_session_parser.dart';
import '../core/discuz_unread_summary.dart';
import '../core/discuz_role_parser.dart';
import '../core/discuz_response.dart';
import '../core/discuz_form.dart';
import '../core/discuz_profile_contract.dart';
import '../core/discuz_native_page.dart';
import '../core/discuz_sign_parser.dart';
import '../core/discuz_sign_pagination.dart';
import '../core/discuz_sign_response.dart';
import '../core/discuz_feature_catalog.dart';
import '../core/klpbbs_membership.dart';
import '../core/discuz_modcp.dart';
import '../models/site_feature.dart';
import '../core/discuz_upload.dart';
import '../core/discuz_ip_response.dart';
import '../core/discuz_reaction_response.dart';
import '../core/discuz_site_stats.dart';
import '../core/discuz_medals.dart';
import '../core/klpbbs_medal_order.dart';
import '../core/discuz_favorites.dart';
import '../core/discuz_credit_log_protocol.dart';
import '../core/discuz_credit_rules.dart';
import '../core/discuz_rankings.dart';
import '../core/discuz_horn_protocol.dart';
import '../core/discuz_guide_protocol.dart';
import '../core/discuz_forum_parser.dart';
import '../core/discuz_forum_counters.dart';
import '../core/discuz_thread_parser.dart';
import '../core/discuz_thread_types.dart';
import '../core/discuz_thread_access.dart';
import '../core/community_response_policy.dart';
import '../models/site_rank_entry.dart';
import '../core/klpbbs_facemall.dart';
import '../core/klpbbs_homestyle.dart';
import '../core/klpbbs_search_protocol.dart';
import '../core/klpbbs_phone_binding.dart';
import '../core/klpbbs_developer_platform.dart';
import '../core/klpbbs_authorizations.dart';
import '../core/discuz_avatar_protocol.dart';
import '../core/discuz_avatar_declaration.dart';
import '../services/avatar_appearance_store.dart';
import '../core/avatar_appearance_lookup.dart';
import '../core/avatar_image_processor.dart';
import '../core/avatar_transport_encoder.dart';
import '../core/forum_events.dart';
import '../core/preload_service.dart';
import '../models/ai_summary.dart';
import '../models/credit_log.dart';
import '../models/darkroom_entry.dart';
import '../models/forum.dart';
import '../models/forum_header_info.dart';
import '../models/friend_item.dart';
import '../models/horn_message.dart';
import '../models/magic_item.dart';
import '../models/medal_item.dart';
import '../models/notice_item.dart';
import '../models/pm_models.dart';
import '../models/post_edit_info.dart';
import '../models/thread_sort_model.dart';
import '../models/post_floor.dart';
import '../models/server_status_model.dart';
import '../models/server_outage_info.dart';
import '../models/sign_entry.dart';
import '../models/site_stats.dart';
import '../models/smiley.dart';
import '../models/thread_summary.dart';
import '../models/user_space.dart';
import '../models/user_role.dart';
import '../models/usergroup_comparison.dart';
import '../models/papa_ai.dart';
import '../services/auto_sign_service.dart';
import '../services/push_notification_service.dart';
import 'comiis_parser.dart';

/// Discuz 搜索频控异常（两次搜索间隔通常为 15 秒）
class SearchRateLimitException implements Exception {
  final String message;
  const SearchRateLimitException(this.message);

  @override
  String toString() => message;
}

/// klpbbs 完整 API 封装（浏览 + 写操作 + 内存预加载）
///
/// 浏览接口按页面选择模板；写操作受用户配置和服务端权限控制。
class KlpbbsApi {
  KlpbbsApi._();

  /// 成功操作后的资料变化；已挂载的个人中心与导航据此重新读取。
  static final ValueNotifier<int> profileChanges = ValueNotifier<int>(0);
  static final ValueNotifier<int> signHeaderChanges = ValueNotifier<int>(0);

  static final Dio _dio = _initializeDio();
  static bool _sessionTrackingInstalled = false;
  static Dio _initializeDio() {
    if (!_sessionTrackingInstalled) {
      _sessionTrackingInstalled = true;
      DioClient.sessionChanges.addListener(_resetSessionCache);
    }
    return DioClient.dio;
  }

  static void _resetSessionCache() {
    _clearCache();
    _inFlightGets.clear();
    _signHeaderLoads.clear();
    _signInLoads.clear();
    _forumFavoriteLoads.clear();
    _threadFavoriteLoads.clear();
    _cachedFormhash = null;
    _cachedSignFormhash = null;
    _cachedMyUid = null;
    _cachedMyUsername = null;
    _cachedMyAvatar = null;
    _cachedMyUserSpace = null;
    AppConfig.myFaceUrl = null;
    _threadOpFloors.clear();
    _threadOpPids.clear();
    _threadAuthorUids.clear();
    _threadContentVersions.clear();
    _authorUidCache.clear();
    _publicIdentityLoads.clear();
    _publicIdentityCache.clear();
    AvatarAppearanceStore.instance.useScope(DioClient.sessionKey);
    _avatarLookup.useScope(DioClient.sessionKey);
    _hornAvatarLoads.clear();
    _searchMemoryCache.clear();
    _siteSearchDeclarations.clear();
    _searchMemoryCacheTime.clear();
    _searchIndexes.clear();
    _searchPageCounts.clear();
    _failedForumTids.clear();
    _forumFavidCache.clear();
    _threadFavidCache.clear();
    ForumFavoriteNotifier.instance.replace({});
    unawaited(sanitizeFavoriteCache());
    unawaited(AutoSignService.instance.onAccountSwitched());
    PushNotificationService.instance.clearUnread();
  }

  static String _url(String path) => Uri.parse(AppConfig.baseUrl)
      .resolve(path.replaceAll('&amp;', '&'))
      .toString();
  static String _diskKey(String name) => '$name.${DioClient.sessionKey}';
  static String signCalendarKey(int year, int month) =>
      _diskKey('sign_dates_$year${month.toString().padLeft(2, '0')}');

  static Future<Map<String, List<SiteRankEntry>>> getSiteHotRankings(
      {bool forceRefresh = false}) async {
    final key = _diskKey('site_hot_rankings');
    final cached =
        PreloadService.instance.get<Map<String, List<SiteRankEntry>>>(key);
    if (!forceRefresh && cached != null) return cached;
    final source =
        await _get('forum.php?mod=index&mobile=no', forceRefresh: forceRefresh);
    if (!DiscuzRankings.recognized(source)) {
      throw StateError(DiscuzResponse.message(source) ?? '网站未提供当前热门排行面板');
    }
    final result = DiscuzRankings.parse(source);
    PreloadService.instance.set(key, result, ttl: const Duration(minutes: 5));
    return result;
  }

  static Future<List<SiteFeature>> getSiteFeatures(
      {bool forceRefresh = false}) async {
    final session = DioClient.sessionKey;
    final key = _diskKey('site_features');
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<List<SiteFeature>>(key);
      if (cached != null) return cached;
    }
    final source = await _get(
        DioClient.isLoggedIn
            ? 'home.php?mod=spacecp&ac=usergroup&do=list&mobile=no'
            : 'forum.php?mod=guide&view=newthread&mobile=no',
        forceRefresh: forceRefresh);
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新功能列表');
    final features =
        DiscuzFeatureCatalog.parse(source, Uri.parse(AppConfig.baseUrl));
    if (features.isEmpty) {
      throw StateError(DiscuzResponse.message(source) ?? '网站未返回功能导航');
    }
    PreloadService.instance.set(key, features, ttl: const Duration(minutes: 5));
    return features;
  }

  static Future<List<MembershipOffer>> getMembershipOffers(
      {bool forceRefresh = false}) async {
    return (await getMembershipCenter(forceRefresh: forceRefresh)).center.plans;
  }

  static const _membershipPath =
      'home.php?mod=spacecp&ac=usergroup&do=list&mobile=no';
  static final Set<String> _membershipRequests = {};

  /// Current-account status and prices use the actual desktop usergroup list.
  /// Quotes/CSRF are process-local receipts, never a persisted purchase form.
  static Future<MembershipCenterReceipt> getMembershipCenter(
      {bool forceRefresh = false, String? expectedSession}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    if (session != DioClient.sessionKey || !DioClient.isLoggedIn) {
      throw StateError('请使用当前登录账号查看用户组与会员');
    }
    final base = Uri.parse(AppConfig.baseUrl);
    var responseUri = base.resolve(_membershipPath);
    final source = await _get(_membershipPath,
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: forceRefresh,
        cacheTtl: Duration.zero,
        expectedSession: session,
        onResponseUri: (uri) => responseUri = uri);
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新加载会员');
    if (!DiscuzRequestPolicy.sameOrigin(base, responseUri) ||
        !responseUri.path.endsWith('/home.php') ||
        responseUri.queryParameters['mod'] != 'spacecp' ||
        responseUri.queryParameters['ac'] != 'usergroup' ||
        responseUri.queryParameters['do'] != 'list') {
      throw StateError('论坛会员入口已变化，请重新加载');
    }
    _rejectRestrictedPage(source);
    final center = KlpbbsMembership.parse(source, responseUri);
    if (!center.recognized) {
      throw StateError(DiscuzResponse.message(source) ?? '论坛未返回可识别的会员价格和用户组列表');
    }
    return MembershipCenterReceipt(center, session, DateTime.now());
  }

  static Future<MembershipActionReceipt> _readMembershipAction(
      MembershipCenterReceipt center,
      MembershipPlan plan,
      MembershipOperation operation) async {
    final uri = KlpbbsMembership.route(plan.route(operation), center.center.uri,
        operation: operation, groupId: plan.groupId);
    if (uri == null ||
        center.session != DioClient.sessionKey ||
        !DioClient.isLoggedIn) {
      throw StateError('当前账号没有此会员操作入口，请刷新');
    }
    var responseUri = uri;
    final source = await _get(uri.toString(),
        headers: {
          'User-Agent': AppConfig.pcUserAgent,
          'Referer': center.center.uri.toString()
        },
        forceRefresh: true,
        cacheTtl: Duration.zero,
        expectedSession: center.session,
        onResponseUri: (target) => responseUri = target);
    if (center.session != DioClient.sessionKey) {
      throw StateError('账号已切换，请重新打开会员操作');
    }
    _rejectRestrictedPage(source);
    if (KlpbbsMembership.route(responseUri.toString(), center.center.uri,
            operation: operation, groupId: plan.groupId) ==
        null) {
      throw StateError('会员操作入口已变化，请刷新');
    }
    final contract =
        MembershipActionContract.parse(source, responseUri, operation, plan);
    return MembershipActionReceipt(center, plan, contract, DateTime.now());
  }

  /// Reading a user-tapped confirmation performs no POST. Only list-declared
  /// Discuz buy/switch/exit branches without submission flags are accepted.
  static Future<MembershipActionReceipt> getMembershipAction(
      MembershipCenterReceipt receipt,
      int groupId,
      MembershipOperation operation) async {
    if (receipt.session != DioClient.sessionKey || !DioClient.isLoggedIn) {
      throw StateError('账号已变化，请重新打开会员中心');
    }
    final reviewed = receipt.center.plans
        .where((plan) => plan.groupId == groupId)
        .firstOrNull;
    if (reviewed == null || reviewed.route(operation) == null) {
      throw StateError('论坛当前没有提供此会员操作');
    }
    final fresh = await getMembershipCenter(
        forceRefresh: true, expectedSession: receipt.session);
    final current =
        fresh.center.plans.where((plan) => plan.groupId == groupId).firstOrNull;
    if (current == null ||
        !reviewed.sameAvailabilityAs(current) ||
        fresh.center.currentGroup != receipt.center.currentGroup) {
      throw StateError('会员价格、持有状态或操作权限已变化，请刷新后确认');
    }
    return _readMembershipAction(fresh, current, operation);
  }

  static Future<MembershipActionResult> submitMembershipAction(
      MembershipActionReceipt receipt,
      {int? days}) async {
    final session = receipt.session;
    if (session != DioClient.sessionKey || !DioClient.isLoggedIn) {
      return const MembershipActionResult(false, '账号已变化，请重新打开会员操作');
    }
    final invalid = receipt.contract.validateDays(days);
    if (invalid != null) return MembershipActionResult(false, invalid);
    if (DateTime.now().difference(receipt.loadedAt) >
        const Duration(minutes: 5)) {
      return const MembershipActionResult(false, '会员报价已过期，请重新读取后确认',
          needsRefresh: true);
    }
    if (!_membershipRequests.add(session)) {
      return const MembershipActionResult(false, '正在处理上一项会员操作，请稍候');
    }
    try {
      final center = await getMembershipCenter(
          forceRefresh: true, expectedSession: session);
      final current = center.center.plans
          .where((p) => p.groupId == receipt.plan.groupId)
          .firstOrNull;
      if (current == null ||
          !receipt.plan.sameAvailabilityAs(current) ||
          receipt.centerReceipt.center.currentGroup !=
              center.center.currentGroup) {
        return const MembershipActionResult(false, '会员价格、持有状态或操作权限已变化，请重新读取后确认',
            needsRefresh: true);
      }
      final fresh = await _readMembershipAction(
          center, current, receipt.contract.operation);
      if (!receipt.contract.sameTermsAs(fresh.contract) ||
          !fresh.contract.canSubmit) {
        return const MembershipActionResult(false, '会员报价或表单已变化，请重新读取后确认',
            needsRefresh: true);
      }
      final values = fresh.contract.submission(days);
      if (session != DioClient.sessionKey) {
        return const MembershipActionResult(false, '账号已切换，本次操作未提交');
      }
      final response = await _post(fresh.contract.action.toString(), values,
          expectedSession: session,
          invalidateCache: false,
          headers: {
            'User-Agent': AppConfig.pcUserAgent,
            'Referer': fresh.contract.pageUri.toString()
          });
      if (session != DioClient.sessionKey) {
        return const MembershipActionResult(false, '账号已变化，请刷新确认本次会员操作结果');
      }
      final success = DiscuzResponse.isSuccess(response);
      if (success) {
        _clearCache();
        await invalidateUserProfile(expectedSession: session);
      }
      return MembershipActionResult(
          success,
          DiscuzResponse.message(response) ??
              (success ? '会员操作成功' : '论坛未确认操作结果，请刷新查看'));
    } on FormatException catch (error) {
      return MembershipActionResult(false, error.message);
    } on StateError catch (error) {
      return MembershipActionResult(
          false, error.toString().replaceFirst('Bad state: ', ''),
          needsRefresh: true);
    } catch (_) {
      return const MembershipActionResult(false, '连接未完成，论坛未确认操作结果，请刷新查看',
          needsRefresh: true);
    } finally {
      _membershipRequests.remove(session);
    }
  }

  static String? get favoriteForumsPrefsKey => _cachedMyUid == null
      ? null
      : 'fav_forums:${AppConfig.baseUrl}:$_cachedMyUid';

  static Future<Set<int>> getSavedFavoriteForumIds() async {
    if (!DioClient.isLoggedIn) return {};
    final session = DioClient.sessionKey;
    await getMyUid();
    final key = favoriteForumsPrefsKey;
    if (key == null || session != DioClient.sessionKey) return {};
    final prefs = await SharedPreferences.getInstance();
    if (session != DioClient.sessionKey) return {};
    return (prefs.getStringList(key) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
  }

  /// 全局缓存的最新 FormHash（任意请求返回即自动更新）
  static String? _cachedFormhash;
  static String? get cachedFormhash => _cachedFormhash;
  static void setCachedFormhash(String fh) {
    if (fh.isNotEmpty) _cachedFormhash = fh;
  }

  static final Map<String, Future<String>> _inFlightGets = {};
  static final Map<String, ({String html, DateTime time})> _quickGetCache = {};
  static int _cacheGeneration = 0;

  /// 清空内存中的快速 GET 缓存（在写操作、退出登录、手动强制刷新时调用）
  static void clearQuickCache([String? pathPrefix]) {
    _cacheGeneration++;
    if (pathPrefix != null) {
      _quickGetCache.removeWhere((k, _) => k.startsWith(pathPrefix));
    } else {
      _quickGetCache.clear();
    }
  }

  /// 清空预加载缓存与内存快速 GET 缓存（写操作/点赞/回复/刷新后调用）
  static void _clearCache([int? tid]) {
    if (tid != null) {
      PreloadService.instance.clear('thread_detail_$tid');
      clearQuickCache('forum.php?mod=viewthread&tid=$tid');
    } else {
      PreloadService.instance.clear();
      clearQuickCache();
    }
  }

  static ServerStatusData? _cachedServerStatus;
  static DateTime? _lastServerStatusTime;
  static Future<ServerStatusData>? _statusInFlight;

  static final Dio _statusDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ),
  )..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient(context: SecurityContext.defaultContext);
        if (!AppConfig.useSystemProxy) {
          client.findProxy = (uri) => 'DIRECT';
        }
        return client;
      },
    );

  /// 获取服务器状态面板实时监控数据 (https://status.klpz.net/api/public/status)
  static ServerStatusData? get cachedServerStatus => _cachedServerStatus;

  static Future<ServerStatusData> getServerStatus(
      {bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedServerStatus != null &&
        _lastServerStatusTime != null &&
        DateTime.now().difference(_lastServerStatusTime!).inSeconds < 30) {
      return _cachedServerStatus!;
    }

    return _statusInFlight ??= _loadServerStatus().whenComplete(() {
      _statusInFlight = null;
    });
  }

  static Future<ServerStatusData> _loadServerStatus() async {
    try {
      final res = await _statusDio
          .get<dynamic>('https://status.klpz.net/api/public/status');
      if (res.data != null) {
        final raw = res.data;
        final map = raw is Map
            ? Map<String, dynamic>.from(raw)
            : jsonDecode(raw.toString()) as Map<String, dynamic>;
        final data = ServerStatusData.fromJson(map);
        if (data.services.isNotEmpty) {
          _cachedServerStatus = data;
          _lastServerStatusTime = DateTime.now();
          PreloadService.instance
              .set('server_status', data, ttl: const Duration(seconds: 30));
          debugPrint(
              '[ServerStatus] 成功获取真实监控数据: ${data.siteName}，包含 ${data.services.length} 个服务');
          return data;
        }
      }
    } catch (e) {
      debugPrint('[ServerStatus] 请求真实监控数据异常: $e');
    }

    if (_cachedServerStatus != null) return _cachedServerStatus!;
    throw Exception('无法连接到服务器状态监控服务 (status.klpz.net)');
  }

  /// 彻底清除某个主题的预加载与快速 GET 缓存（包含所有分页与排序变体）
  static void clearThreadDetailCache(int tid) {
    _threadOpFloors.remove(tid);
    _threadOpPids.remove(tid);
    _threadAuthorUids.remove(tid);
    PreloadService.instance.clear('thread_detail_${tid}_');
    clearQuickCache('forum.php?mod=viewthread&tid=$tid');
  }

  /// 容错解码（个别插件模板内嵌 GBK 字节）
  static String _decode(List<int> bytes) =>
      const Utf8Decoder(allowMalformed: true).convert(bytes);

  /// 实时 GET 请求（内置并发请求防抖复用与短期热数据缓存，彻底避免同页面重复抓取）
  static Future<String> _get(
    String path, {
    Map<String, String>? headers,
    int retries = 1,
    bool forceRefresh = false,
    Duration cacheTtl = const Duration(seconds: 15),
    void Function(Uri)? onResponseUri,
    void Function(int)? onResponseRedirects,
    String? expectedSession,
  }) async {
    _initializeDio();
    final uri = Uri.parse(_url(path));
    final session = DioClient.sessionKey;
    if (expectedSession != null && expectedSession != session) {
      throw StateError('账号已变化，请重新打开页面');
    }
    final generation = _cacheGeneration;
    final headerParts = headers?.entries
            .map((e) => '${e.key.toLowerCase()}:${e.value}')
            .toList() ??
        <String>[];
    headerParts.sort();
    final cacheKey =
        '$path|$session|$uri|${DioClient.userAgentFor(uri, headers: headers)}|${headerParts.join(';')}';
    final cacheable = DiscuzRequestPolicy.isCacheable(uri) &&
        onResponseUri == null &&
        onResponseRedirects == null;

    // 1. 若非强制刷新，优先命中短期热缓存（默认 15 秒，快速页面切换无感知）
    if (cacheable && !forceRefresh && cacheTtl > Duration.zero) {
      final cached = _quickGetCache[cacheKey];
      if (cached != null && DateTime.now().difference(cached.time) < cacheTtl) {
        _quickGetCache.remove(cacheKey);
        _quickGetCache[cacheKey] = cached;
        return cached.html;
      }
    }

    // 2. 并发请求防抖合并：若同地址请求正在网络传输中，直接复用同一个 Future，杜绝多次并发抓取
    if (cacheable && !forceRefresh && _inFlightGets.containsKey(cacheKey)) {
      return _inFlightGets[cacheKey]!;
    }

    // Discuz 的部分 GET 会点赞、取消或购买；失败后的自动重试可能重复写入。
    // Coalesce the validated result, including metadata, rather than raw IO.
    // Every consumer must pass the same session checks before using the body.
    final future = () async {
      final html = await _doGet(path,
          headers: headers,
          retries: cacheable ? retries : 0,
          onResponseUri: onResponseUri,
          onResponseRedirects: onResponseRedirects,
          expectedSession: expectedSession);
      if (session != DioClient.sessionKey &&
          uri.queryParameters['action'] != 'logout') {
        throw StateError('登录状态已改变，请重新加载页面');
      }
      // The plugin declares frames inside real avatar regions. Decode only
      // pages containing those declarations, and leave large DOM work off UI.
      final mobileFrameTemplate =
          DiscuzAvatarDeclarations.usesMobileFrameTemplate(html, uri);
      if (DiscuzAvatarDeclarations.mayContainFrames(html) ||
          mobileFrameTemplate) {
        final base = Uri.parse(AppConfig.baseUrl);
        final declarations = html.length > 180000
            ? await Isolate.run(
                () => DiscuzAvatarDeclarations.parse(html, base))
            : DiscuzAvatarDeclarations.parse(html, base);
        if (session != DioClient.sessionKey) {
          throw StateError('登录状态已改变，请重新加载页面');
        }
        if (generation == _cacheGeneration) {
          AvatarAppearanceStore.instance.useScope(session);
          for (final declaration in declarations) {
            AvatarAppearanceStore.instance.remember(declaration);
            if (mobileFrameTemplate || declaration.faceUrl != null) {
              _avatarLookup.observed(declaration.uid);
            }
            cacheAuthorUid(declaration.username, declaration.uid);
          }
        }
      }
      if (cacheable &&
          generation == _cacheGeneration &&
          cacheTtl > Duration.zero) {
        _quickGetCache[cacheKey] = (html: html, time: DateTime.now());
        if (_quickGetCache.length > 80) {
          _quickGetCache.remove(_quickGetCache.keys.first);
        }
      }
      return html;
    }();
    if (cacheable) _inFlightGets[cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightGets[cacheKey], future)) {
        _inFlightGets.remove(cacheKey);
      }
    }
  }

  static Future<String> _doGet(
    String path, {
    Map<String, String>? headers,
    int retries = 2,
    void Function(Uri)? onResponseUri,
    void Function(int)? onResponseRedirects,
    String? expectedSession,
  }) async {
    final session = DioClient.sessionKey;
    DioException? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        if (attempt > 0) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
        final resp = await _dio.get<List<int>>(
          _url(path),
          options: Options(
            responseType: ResponseType.bytes,
            headers: headers,
            extra: {
              if (expectedSession != null)
                'discuz.expectedSession': expectedSession
            },
            // 3xx 由拦截器手动跟随重定向，不抛异常
            validateStatus: (code) => code != null && code < 400,
          ),
        );
        final html = _decode(resp.data ?? const []);
        if (resp.requestOptions.extra['discuz.cookiesAccepted'] == false) {
          throw StateError('会话凭证已更新，重新获取页面');
        }
        onResponseUri?.call(resp.realUri);
        onResponseRedirects
            ?.call(resp.requestOptions.extra['discuz.redirects'] as int? ?? 0);
        if (ServerOutageInfo.isOutageHtml(html)) {
          throw ServerOutageException(ServerOutageInfo.fromHtml(
            html,
            statusCode: resp.statusCode ?? 200,
            statusMessage: resp.statusMessage,
            requestUrl: resp.realUri.toString(),
            headers: resp.headers.map,
          ));
        }
        final fh = _extractFormhash(html);
        if (session == DioClient.sessionKey && fh != null && fh.isNotEmpty) {
          _cachedFormhash = fh;
        }
        return html;
      } on DioException catch (e) {
        lastError = e;
        final code = e.response?.statusCode;
        // 如果是 523/522/521/502/503/504 等临时网络/服务器错误，或握手/连接中断，自动重试
        if (attempt < retries &&
            (code == 523 ||
                code == 522 ||
                code == 521 ||
                code == 502 ||
                code == 503 ||
                code == 504 ||
                e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.sendTimeout ||
                e.type == DioExceptionType.connectionError ||
                e.error is HandshakeException ||
                e.error is SocketException ||
                e.error is TlsException ||
                (e.type == DioExceptionType.unknown && code == null))) {
          continue;
        }
        if (ServerOutageInfo.isOutageDioException(e)) {
          throw ServerOutageException(ServerOutageInfo.fromDioException(e));
        }
        rethrow;
      } catch (_) {
        // Credentials/template/programming errors are not transport retries.
        rethrow;
      }
    }
    if (lastError != null) {
      if (ServerOutageInfo.isOutageDioException(lastError)) {
        throw ServerOutageException(
            ServerOutageInfo.fromDioException(lastError));
      }
      throw lastError;
    }
    throw Exception('请求失败');
  }

  static Future<String> _post(
    String path,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
    void Function(Uri)? onResponseUri,
    String? encodedForm,
    FormData? multipart,
    String? expectedSession,
    bool invalidateCache = true,
  }) async {
    final session = DioClient.sessionKey;
    if (expectedSession != null && expectedSession != session) {
      throw StateError('账号已变化，请重新打开表单');
    }
    if (invalidateCache) _clearCache();
    try {
      final resp = await _dio.post<List<int>>(
        _url(path),
        data: multipart ?? encodedForm ?? data,
        options: Options(
          responseType: ResponseType.bytes,
          contentType: multipart == null
              ? Headers.formUrlEncodedContentType
              : Headers.multipartFormDataContentType,
          headers: headers,
          extra: {
            if (expectedSession != null)
              'discuz.expectedSession': expectedSession
          },
          validateStatus: (code) => code != null && code < 400,
        ),
      );
      final html = _decode(resp.data ?? const []);
      if (resp.requestOptions.extra['discuz.cookiesAccepted'] == false) {
        throw StateError('会话凭证已改变，无法确认提交结果，请刷新页面查看');
      }
      onResponseUri?.call(resp.realUri);
      if (ServerOutageInfo.isOutageHtml(html)) {
        throw ServerOutageException(ServerOutageInfo.fromHtml(
          html,
          statusCode: resp.statusCode ?? 200,
          statusMessage: resp.statusMessage,
          requestUrl: resp.realUri.toString(),
          headers: resp.headers.map,
        ));
      }
      final fh = _extractFormhash(html);
      if (session == DioClient.sessionKey && fh != null && fh.isNotEmpty) {
        _cachedFormhash = fh;
      }
      return html;
    } on DioException catch (e) {
      if (ServerOutageInfo.isOutageDioException(e)) {
        throw ServerOutageException(ServerOutageInfo.fromDioException(e));
      }
      rethrow;
    } finally {
      if (invalidateCache) _clearCache();
    }
  }

  /// 从 HTML 提取 formhash（多级兜底支持 JS 变量、按钮 href、表单 input 与 URL 参数，大小写不敏感）
  static String? _extractFormhash(String html) {
    if (html.isEmpty) return null;
    final patterns = <RegExp>[
      RegExp(
          r'''k_misign-sign\.html\?[^"'<>\\]*?formhash=([0-9a-zA-Z]{8,32})''',
          caseSensitive: false),
      RegExp(r'''name=["']formhash["'][^>]*value=["']([0-9a-zA-Z]{8,32})["']''',
          caseSensitive: false),
      RegExp(r'''value=["']([0-9a-zA-Z]{8,32})["'][^>]*name=["']formhash["']''',
          caseSensitive: false),
      RegExp(r'''name=["']formhash["']\s+value=["']([0-9a-zA-Z]{8,32})["']''',
          caseSensitive: false),
      RegExp(r"formhash\s*=\s*'([0-9a-zA-Z]{8,32})'", caseSensitive: false),
      RegExp(r'formhash\s*=\s*"([0-9a-zA-Z]{8,32})"', caseSensitive: false),
      RegExp(r'formhash=([0-9a-zA-Z]{8,32})', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(html);
      if (m != null) return m.group(1);
    }
    return null;
  }

  /// 全局作者名与 UID 映射缓存（用于各版块、搜索、门户自动补全头像）
  static final Map<String, int> _authorUidCache = {};
  static void cacheAuthorUid(String author, int uid) {
    if (author.isNotEmpty && uid > 0) {
      _authorUidCache.remove(author);
      _authorUidCache[author] = uid;
      if (_authorUidCache.length > 2048) {
        _authorUidCache.remove(_authorUidCache.keys.first);
      }
    }
  }

  static int? getCachedAuthorUid(String author) => _authorUidCache[author];

  static final _avatarLookup = AvatarAppearanceLookup(
      fetch: _loadPublicAvatarAppearance,
      currentScope: () => DioClient.sessionKey,
      read: AvatarAppearanceStore.instance.get,
      revision: AvatarAppearanceStore.instance.revision,
      publish: (declaration) {
        AvatarAppearanceStore.instance.remember(declaration);
        cacheAuthorUid(declaration.username, declaration.uid);
      });
  static final _hornAvatarLoads = <String, Future<void>>{};

  /// Missing desktop fields are resolved without blocking their list or saving
  /// account/profile data. A horn batch already in flight takes precedence.
  static Future<DiscuzAvatarDeclaration?> resolveAvatarAppearance(
      int uid) async {
    _initializeDio();
    final session = DioClient.sessionKey;
    AvatarAppearanceStore.instance.useScope(session);
    final batch = _hornAvatarLoads['$session|$_cacheGeneration'];
    if (batch != null) await batch;
    if (session != DioClient.sessionKey) return null;
    return _avatarLookup.resolve(uid);
  }

  static Future<DiscuzAvatarDeclaration?> _loadPublicAvatarAppearance(
      int uid, String session) async {
    final generation = _cacheGeneration;
    final base = Uri.parse(AppConfig.baseUrl);
    final path = 'home.php?mod=space&uid=$uid&do=profile&mobile=2';
    var responseUri = base.resolve(path);
    // Bypass full personal-space hydration: this GET only reads the owner's
    // avatar wrapper and must not persist currencies, identity or preferences.
    final source = await _doGet(path,
        retries: 0,
        headers: {'User-Agent': AppConfig.mobileUserAgent},
        expectedSession: session,
        onResponseUri: (uri) => responseUri = uri);
    if (session != DioClient.sessionKey || generation != _cacheGeneration) {
      return null;
    }
    return DiscuzAvatarDeclarations.mobileSpace(source,
        base: base, responseUri: responseUri, uid: uid);
  }

  /// Model parsers also receive declarations in plugin JSON and inline script
  /// data. Share those verified identities with every avatar without fetching
  /// an extra profile for each list row. Empty legacy model fields are unknown;
  /// explicit removals are handled by the HTML/catalog declaration parser.
  /// Model caches may seed an unknown appearance, but cannot restore an older
  /// pendant after a newer server declaration removed or replaced it.
  static void _observeModelAvatars(
      Iterable<DiscuzAvatarDeclaration> declarations, String session,
      {bool allowFrameRemoval = false,
      bool replaceObservedAppearance = false}) {
    if (session != DioClient.sessionKey) return;
    final store = AvatarAppearanceStore.instance;
    store.useScope(session);
    for (final declaration in declarations) {
      if (declaration.uid <= 0 || declaration.username == '匿名') continue;
      final observed = store.get(declaration.uid);
      final frame = declaration.faceUrl?.isNotEmpty == true
          ? KlpFacemallResponse.frameUrl(
              declaration.faceUrl, Uri.parse(AppConfig.baseUrl))
          : allowFrameRemoval && declaration.faceUrl == ''
              ? ''
              : null;
      store.remember(DiscuzAvatarDeclaration(
          uid: declaration.uid,
          username: declaration.username,
          avatarUrl: replaceObservedAppearance || observed?.avatarUrl == null
              ? declaration.avatarUrl
              : null,
          faceUrl: replaceObservedAppearance || observed?.faceUrl == null
              ? frame
              : null));
      if (frame != null) _avatarLookup.observed(declaration.uid);
      if (!const {'我', '您', '匿名'}.contains(declaration.username)) {
        cacheAuthorUid(declaration.username, declaration.uid);
      }
    }
  }

  static void _observeThreadAvatars(
      Iterable<ThreadSummary> threads, String session) {
    _observeModelAvatars(
        threads.where((thread) => (thread.uid ?? 0) > 0).map((thread) =>
            DiscuzAvatarDeclaration(
                uid: thread.uid!,
                username: thread.author,
                faceUrl: thread.faceUrl)),
        session);
  }

  /// 首页推荐流：采用用户明确指定的“导读的新帖”（guide.php?mod=guide&view=newthread）
  static Future<List<ThreadSummary>> getHome(
      {bool forceRefresh = false}) async {
    final session = DioClient.sessionKey;
    final cacheKey = _diskKey('cached_home_threads_newthread_v3');
    // Capture the last valid feed before a refresh. A failed read must not
    // erase it; an explicitly recognized empty guide remains a valid result.
    final cached = PreloadService.instance
        .get<List<ThreadSummary>>('home_threads', ignoreExpired: true);
    if (!forceRefresh) {
      if (cached != null && cached.isNotEmpty) {
        _observeThreadAvatars(cached, session);
        return cached;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新首页');
        await prefs.remove('cached_home_threads_json'); // 彻底清除旧版热帖混杂缓存
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新首页');
        final raw = prefs.getString(cacheKey);
        if (raw != null && raw.isNotEmpty) {
          final list = (jsonDecode(raw) as List<dynamic>)
              .map((e) => ThreadSummary.fromJson(e as Map<String, dynamic>))
              .toList();
          if (list.isNotEmpty) {
            _observeThreadAvatars(list, session);
            PreloadService.instance
                .set('home_threads', list, ttl: const Duration(minutes: 30));
            unawaited(getHome(forceRefresh: true)
                .catchError((_) => const <ThreadSummary>[]));
            return list;
          }
        }
      } catch (_) {
        if (session != DioClient.sessionKey) rethrow;
      }
    }
    try {
      // 严格使用用户明确指定的“导读 - 新帖”作为首页帖子源
      final newThreads =
          await getGuide('newthread', page: 1, forceRefresh: forceRefresh);
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新首页');
      final cleanThreads = List<ThreadSummary>.of(newThreads);

      PreloadService.instance.set(
        'home_threads',
        cleanThreads,
        ttl: const Duration(minutes: 30),
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新首页');
        await prefs.remove('cached_home_threads_json');
        final raw = jsonEncode(cleanThreads.map((e) => e.toJson()).toList());
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新首页');
        await prefs.setString(cacheKey, raw);
      } catch (_) {
        if (session != DioClient.sessionKey) rethrow;
      }
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新首页');
      return cleanThreads;
    } catch (e) {
      if (session != DioClient.sessionKey) rethrow;
      if (e is ServerOutageException || ServerOutageInfo.tryParse(e) != null) {
        rethrow;
      }
      if (cached != null && cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  /// 版块导航列表（真实分区结构，扁平化所有版块）
  static Future<List<Forum>> getForums() async {
    final groups = await getForumGroups();
    if (groups.isNotEmpty) {
      return groups.expand((g) => g.forums).toList();
    }
    return const [];
  }

  /// 社区版块树（分区 → 版块），多端合并提取移动端高清图标与 PC 端精准贴数/今日帖数
  /// 支持本地持久化磁盘存储（0ms 秒开），结合 SWR 后台静默联网更新
  static Future<List<ForumGroup>> getForumGroups(
      {bool forceRefresh = false}) async {
    final session = DioClient.sessionKey;
    final diskKey = _diskKey('cached_forum_groups_v2_json');
    final cached = PreloadService.instance.get<List<ForumGroup>>(
      'forum_groups',
      ignoreExpired: true,
    );
    if (!forceRefresh && cached != null && cached.isNotEmpty) {
      return cached;
    }

    // 优先从本地持久化磁盘缓存瞬时加载（0ms 启动秒开）
    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新版块');
        final rawJson = prefs.getString(diskKey);
        if (rawJson != null && rawJson.isNotEmpty) {
          final list = (jsonDecode(rawJson) as List<dynamic>)
              .map((e) => ForumGroup.fromJson(e as Map<String, dynamic>))
              .toList();
          if (list.isNotEmpty) {
            final injected = _injectFavoriteForums(list, prefs);
            PreloadService.instance
                .set('forum_groups', injected, ttl: const Duration(hours: 24));
            // 在后台静默异步拉取服务端最新实时版块树并更新本地
            unawaited(getForumGroups(forceRefresh: true)
                .catchError((_) => const <ForumGroup>[]));
            return injected;
          }
        }
      } catch (_) {
        if (session != DioClient.sessionKey) rethrow;
      }
    }

    if (forceRefresh) {
      clearQuickCache('forum.php?forumlist=1');
      clearQuickCache('index.php');
      clearQuickCache('forum.php?mobile=no');
    }
    try {
      final results = await Future.wait([
        _get(
          'forum.php?forumlist=1&mobile=2',
          headers: {'User-Agent': AppConfig.mobileUserAgent},
          forceRefresh: forceRefresh,
          expectedSession: session,
        ),
        _get(
          'forum.php?mobile=no',
          headers: {'User-Agent': AppConfig.pcUserAgent},
          forceRefresh: forceRefresh,
          expectedSession: session,
        ).catchError((_) => ''),
      ]);
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新版块');
      final mobileGroups = ComiisParser.parseForumGroups(results[0]);
      final pcGroups = ComiisParser.parseForumGroups(results[1]);

      // 实时解析并缓存全站统计数据（优先 PC 端权威 #chart 数据）
      final statsPc = ComiisParser.parseSiteStats(results[1]);
      final statsMobile = ComiisParser.parseSiteStats(results[0]);
      final finalStats = DiscuzSiteStats.merge(statsMobile, statsPc);
      if (!finalStats.isEmpty) {
        PreloadService.instance.set('site_stats', finalStats);
      }

      final prefs = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新版块');
      if (mobileGroups.isNotEmpty) {
        final mergedGroups =
            DiscuzForumParser.mergeGroups(mobileGroups, pcGroups);
        final finalGroups = _injectFavoriteForums(mergedGroups, prefs);
        PreloadService.instance.set(
          'forum_groups',
          finalGroups,
          ttl: const Duration(hours: 24),
        );
        try {
          final rawJson =
              jsonEncode(finalGroups.map((g) => g.toJson()).toList());
          await prefs.setString(diskKey, rawJson);
        } catch (_) {
          if (session != DioClient.sessionKey) rethrow;
        }
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新版块');
        return finalGroups;
      }
      if (pcGroups.isNotEmpty) {
        final finalGroups = _injectFavoriteForums(pcGroups, prefs);
        PreloadService.instance.set(
          'forum_groups',
          finalGroups,
          ttl: const Duration(hours: 24),
        );
        try {
          final rawJson =
              jsonEncode(finalGroups.map((g) => g.toJson()).toList());
          await prefs.setString(diskKey, rawJson);
        } catch (_) {
          if (session != DioClient.sessionKey) rethrow;
        }
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新版块');
        return finalGroups;
      }
    } catch (e) {
      if (session != DioClient.sessionKey) rethrow;
      if (e is ServerOutageException || ServerOutageInfo.tryParse(e) != null) {
        rethrow;
      }
    }
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新版块');
    if (cached != null && cached.isNotEmpty) return cached;
    throw StateError('网站未返回可识别的版块列表，请刷新后重试');
  }

  /// 统一将本地收藏/关注版块注入版块分组中的「我关注的」分区 (gid 0)，严格对齐用户实际收藏列表
  static List<ForumGroup> _injectFavoriteForums(
    List<ForumGroup> groups,
    SharedPreferences prefs,
  ) {
    if (groups.isEmpty) return groups;

    final rawFavList = !DioClient.isLoggedIn || favoriteForumsPrefsKey == null
        ? const <String>[]
        : prefs.getStringList(favoriteForumsPrefsKey!) ?? const [];
    final favFids = rawFavList
        .map(int.tryParse)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();

    return DiscuzFavorites.groupsWithSavedForums(groups, favFids);
  }

  /// 获取全站统计数据（今日发帖 / 昨日发帖 / 论坛总帖 / 注册会员）
  /// 实时从 PC 首页 #chart 与 forum.php?forumlist=1&mobile=2 提取并动态刷新
  static Future<SiteStats> getSiteStats({bool forceRefresh = false}) async {
    final cached = PreloadService.instance
        .get<SiteStats>('site_stats', ignoreExpired: true);
    if (!forceRefresh) {
      if (cached != null && cached.isComplete && cached.isFresh) {
        return cached;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_diskKey('cached_site_stats_json'));
        if (raw != null && raw.isNotEmpty) {
          final stats =
              SiteStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          if (stats.isComplete && stats.isFresh) {
            PreloadService.instance
                .set('site_stats', stats, ttl: const Duration(minutes: 5));
            return stats;
          }
        }
      } catch (_) {}
    }
    if (forceRefresh) {
      PreloadService.instance.remove('site_stats');
      clearQuickCache('forum.php?mobile=no');
      clearQuickCache('forum.php?forumlist=1');
    }
    try {
      final results = await Future.wait([
        _get(
          'forum.php?mobile=no',
          headers: {'User-Agent': AppConfig.pcUserAgent},
          forceRefresh: forceRefresh,
        ).catchError((_) => ''),
        _get('forum.php?forumlist=1&mobile=2', forceRefresh: forceRefresh)
            .catchError((_) => ''),
      ]);
      final pcStats = DiscuzSiteStats.merge(
          ComiisParser.parseSiteStats(results[1]),
          ComiisParser.parseSiteStats(results[0]));
      if (pcStats.isComplete) {
        PreloadService.instance
            .set('site_stats', pcStats, ttl: const Duration(minutes: 5));
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              _diskKey('cached_site_stats_json'), jsonEncode(pcStats.toJson()));
        } catch (_) {}
        return pcStats;
      }
      if (!pcStats.isEmpty) {
        PreloadService.instance
            .set('site_stats', pcStats, ttl: const Duration(minutes: 5));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _diskKey('cached_site_stats_json'), jsonEncode(pcStats.toJson()));
        return pcStats;
      }
    } catch (_) {}
    if (cached != null && !cached.isEmpty) return cached;
    return const SiteStats();
  }

  /// 在应用启动（main）时由底层异步预加载并瞬时灌入内存缓存（0ms 秒开）
  static Future<void> primeHomeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. 版块树磁盘缓存灌入内存
      final rawForumGroups =
          prefs.getString(_diskKey('cached_forum_groups_v2_json'));
      if (rawForumGroups != null && rawForumGroups.isNotEmpty) {
        final list = (jsonDecode(rawForumGroups) as List<dynamic>)
            .map((e) => ForumGroup.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          final injected = _injectFavoriteForums(list, prefs);
          PreloadService.instance
              .set('forum_groups', injected, ttl: const Duration(hours: 24));
        }
      }

      // 2. 首页帖子流磁盘缓存灌入内存
      final rawHomeThreads =
          prefs.getString(_diskKey('cached_home_threads_newthread_v3'));
      if (rawHomeThreads != null && rawHomeThreads.isNotEmpty) {
        final list = (jsonDecode(rawHomeThreads) as List<dynamic>)
            .map((e) => ThreadSummary.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          PreloadService.instance
              .set('home_threads', list, ttl: const Duration(minutes: 30));
        }
      }

      // 3. 全站统计看板磁盘缓存灌入内存
      final rawSiteStats = prefs.getString(_diskKey('cached_site_stats_json'));
      if (rawSiteStats != null && rawSiteStats.isNotEmpty) {
        final stats = SiteStats.fromJson(
            jsonDecode(rawSiteStats) as Map<String, dynamic>);
        if (!stats.isEmpty) {
          PreloadService.instance
              .set('site_stats', stats, ttl: const Duration(hours: 24));
        }
      }
    } catch (_) {}
  }

  /// 获取首页土豪霸屏信息
  static Future<
      ({
        String author,
        String avatarUrl,
        String message,
        String linkUrl,
        int tid,
        int uid
      })?> getTuhaoBanner() async {
    final banners = await getTuhaoBanners();
    if (banners.isEmpty) return null;
    final first = banners.first;
    return (
      author: first.author,
      avatarUrl: first.avatarUrl ?? '',
      message: DiscuzHornProtocol.messageText(first.content),
      linkUrl: first.linkUrl ?? '',
      tid: DiscuzHornProtocol.threadId(
              first.linkUrl ?? '', Uri.parse(AppConfig.baseUrl)) ??
          0,
      uid: first.uid ?? 0,
    );
  }

  /// 当前 ahome_horn 的完整霸屏列表，与小喇叭共享同一首页请求。
  static Future<List<HornMessage>> getTuhaoBanners() async =>
      (await getHornMessages())
          .where((message) => message.tag == '土豪')
          .toList();

  /// 表情目录（帖子/回复编辑器表情面板用；分类 + 表情图片 URL）
  static Future<List<SmileyCategory>> getSmilies() async {
    try {
      final js = await _get('data/cache/common_smilies_var.js');
      final list = ComiisParser.parseSmilies(js);
      if (list.isNotEmpty) return list;
    } catch (_) {}
    return ComiisParser.parseSmilies(ComiisParser.kDefaultSmiliesJs);
  }

  /// 版块主题分类（forumdisplay 分类链接）
  static Future<List<({int typeid, String name})>> getThreadTypes(
    int fid,
  ) async =>
      (await getForumBundle(fid)).types;

  /// Keep the response origin and forum/category identity attached to the read.
  /// Content caches are updated only after a validated final response.
  static Future<String> _getCommunitySource(String path,
      {required String expectedSession,
      Map<String, String>? headers,
      bool forceRefresh = false,
      int? fid,
      String? guideView}) async {
    final base = Uri.parse(AppConfig.baseUrl);
    var responseUri = base.resolve(path);
    var serverRedirects = 0;
    final source = await _get(path,
        headers: headers,
        forceRefresh: forceRefresh,
        expectedSession: expectedSession,
        onResponseUri: (uri) => responseUri = uri,
        onResponseRedirects: (count) => serverRedirects = count);
    final matches = fid != null
        ? CommunityResponsePolicy.acceptsForum(base, responseUri, fid)
        : CommunityResponsePolicy.acceptsGuide(base, responseUri, guideView!);
    if (!matches) {
      final alias = fid == null
          ? null
          : CommunityResponsePolicy.declaredForumRedirect(
              base, responseUri, fid, serverRedirects);
      if (alias != null) throw alias;
      throw StateError('论坛返回了其他页面，已保留当前内容，请刷新重试');
    }
    return source;
  }

  /// 获取版块真实子版块列表（forumdisplay 子版块区）
  static Future<List<Forum>> getSubForums(int fid,
      {bool forceRefresh = false}) async {
    final cached =
        PreloadService.instance.get<List<Forum>>('forum_children_$fid');
    if (!forceRefresh && cached != null) return cached;
    final bundle = await getForumBundle(fid, forceRefresh: forceRefresh);
    return bundle.subForums;
  }

  static String _forumNextKey(
          int fid, int page, int? typeid, String? orderby) =>
      'forum_next_${fid}_${page}_${typeid ?? 0}_${orderby ?? ""}';
  static bool? forumHasNextPage(int fid, int page,
          {int? typeid, String? orderby}) =>
      PreloadService.instance.get<bool>(
          _forumNextKey(fid, page, typeid, orderby),
          ignoreExpired: true);

  /// 获取版块头部信息（Banner、统计数据、版主、版规导览卡片，优先 PC 完整源，失败回退移动端）
  static Future<ForumHeaderInfo> getForumHeader(int fid) async {
    if (fid <= 0) throw ArgumentError.value(fid, 'fid');
    final session = DioClient.sessionKey;
    final cacheKey = 'forum_header_$fid';
    final cached = PreloadService.instance.get<ForumHeaderInfo>(cacheKey);
    if (cached != null && !cached.isEmpty) return cached;

    try {
      Future<String> read(String mobile, String userAgent) =>
          _get(DiscuzForumParser.pagePath(fid, mobile: mobile),
                  headers: {'User-Agent': userAgent}, expectedSession: session)
              .catchError((_) {
            if (session != DioClient.sessionKey) {
              throw StateError('账号已切换，请刷新版块');
            }
            return '';
          });
      final bodies = await Future.wait([
        read('no', AppConfig.pcUserAgent),
        read('2', AppConfig.mobileUserAgent),
      ]);
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新版块');
      final pcValid = DiscuzForumParser.recognizesPage(bodies[0]);
      final mobileValid = DiscuzForumParser.recognizesPage(bodies[1]);
      if (!pcValid && !mobileValid) {
        throw const FormatException('网站未返回可识别的版块头部');
      }
      final pc = ComiisParser.parseForumHeader(pcValid ? bodies[0] : '', fid);
      final mobile =
          ComiisParser.parseForumHeader(mobileValid ? bodies[1] : '', fid);
      final header =
          pcValid ? DiscuzForumCounters.mergeHeaders(pc, mobile) : mobile;
      PreloadService.instance.set(cacheKey, header);
      return header;
    } catch (_) {
      if (session != DioClient.sessionKey) rethrow;
      if (cached != null) return cached;
      return ForumHeaderInfo(
          fid: fid, name: '', bannerUrl: AppConfig.forumBannerUrl(fid));
    }
  }

  /// 获取本版积分规则列表（发帖、回帖、加精、删帖积分变动）
  static Future<List<ForumCreditRule>> getCreditRules(int fid) async {
    if (fid <= 0) throw ArgumentError.value(fid, 'fid');
    final session = DioClient.sessionKey;
    final source = await _get(
      'home.php?mod=spacecp&ac=credit&op=rule&fid=$fid&mobile=no',
      headers: {'User-Agent': AppConfig.pcUserAgent},
      forceRefresh: true,
      expectedSession: session,
    );
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新加载积分规则');
    _rejectRestrictedPage(source);
    if (!DiscuzCreditRules.recognized(source)) {
      throw StateError(DiscuzResponse.message(source) ?? '网站未返回可识别的积分规则，请重试');
    }
    return ComiisParser.parseCreditRules(source);
  }

  /// 版块公告（forumdisplay 公告区；本地无公告时返回空）
  /// fid<=0 表示全站公告：抓首页 forum.php?mobile=2
  static Future<List<String>> getAnnouncements(int fid) async {
    final path = fid <= 0
        ? 'forum.php?mobile=2'
        : 'forum.php?mod=forumdisplay&fid=$fid&mobile=2';
    final html = await _get(path);
    return ComiisParser.parseAnnouncements(html);
  }

  /// 一站式整合获取版块完整数据包（帖子列表、版头信息、主题分类、子版块列表），单次网络抓取全量解析，零重复抓取
  static Future<
      ({
        List<ThreadSummary> threads,
        ForumHeaderInfo header,
        List<({int typeid, String name})> types,
        List<Forum> subForums,
      })> getForumBundle(
    int fid, {
    int page = 1,
    int? typeid,
    String? orderby,
    bool forceRefresh = false,
  }) async {
    final session = DioClient.sessionKey, visited = <int>{};
    var destination = fid;
    while (visited.length < 4 && visited.add(destination)) {
      try {
        return await _loadForumBundle(destination,
            page: page,
            typeid: typeid,
            orderby: orderby,
            forceRefresh: forceRefresh);
      } on ForumPageRedirect catch (redirect) {
        if (session != DioClient.sessionKey) {
          throw StateError('账号已切换，请刷新版块');
        }
        destination = redirect.targetFid;
      }
    }
    throw StateError('论坛版块重定向循环，请刷新重试');
  }

  static Future<
      ({
        List<ThreadSummary> threads,
        ForumHeaderInfo header,
        List<({int typeid, String name})> types,
        List<Forum> subForums,
      })> _loadForumBundle(
    int fid, {
    int page = 1,
    int? typeid,
    String? orderby,
    bool forceRefresh = false,
  }) async {
    final session = DioClient.sessionKey;
    final cacheKey =
        'forum_bundle_${fid}_${page}_${typeid ?? 0}_${orderby ?? ""}';
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<
          ({
            List<ThreadSummary> threads,
            ForumHeaderInfo header,
            List<({int typeid, String name})> types,
            List<Forum> subForums,
          })>(cacheKey);
      if (cached != null) {
        final catalog = PreloadService.instance.get<List<DiscuzThreadType>>(
            'forum_types_$fid',
            ignoreExpired: true);
        return (
          threads: cached.threads,
          header: cached.header,
          types: DiscuzThreadTypes.merge(catalog ?? const [], cached.types),
          subForums: cached.subForums
        );
      }
    } else {
      clearQuickCache('forum.php?mod=forumdisplay&fid=$fid');
    }

    Object? mobileError, pcError;
    final results = await Future.wait([
      _getCommunitySource(
        DiscuzForumParser.pagePath(fid,
            mobile: '2', page: page, typeid: typeid, orderby: orderby),
        forceRefresh: forceRefresh,
        expectedSession: session,
        fid: fid,
      ).catchError((Object error) {
        mobileError = error;
        return '';
      }),
      _getCommunitySource(
        DiscuzForumParser.pagePath(fid,
            mobile: 'no', page: page, typeid: typeid, orderby: orderby),
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: forceRefresh,
        expectedSession: session,
        fid: fid,
      ).catchError((Object error) {
        pcError = error;
        return '';
      }),
    ]);
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新版块');

    final mobileHtml =
        DiscuzForumParser.recognizesPage(results[0]) ? results[0] : '';
    final pcHtml =
        DiscuzForumParser.recognizesPage(results[1]) ? results[1] : '';
    if (mobileHtml.isEmpty && pcHtml.isEmpty) {
      throw mobileError ??
          pcError ??
          StateError(DiscuzResponse.message(results[0]) ??
              DiscuzResponse.message(results[1]) ??
              '网站未返回可识别的版块内容，请刷新后重试');
    }
    for (final source in [mobileHtml, pcHtml]) {
      final actualPage = DiscuzForumParser.actualCurrentPage(source);
      if (actualPage != null && actualPage != page) {
        throw StateError('论坛返回第 $actualPage 页，已保留当前内容，请选择有效页码');
      }
    }

    final workerBaseUrl = AppConfig.baseUrl;
    var bundle = await Isolate.run(() {
      AppConfig.baseUrl = workerBaseUrl;
      final mobileThreads =
          ComiisParser.parseThreadList(mobileHtml, pageFid: fid);
      final pcThreads = pcHtml.isNotEmpty
          ? ComiisParser.parseThreadList(pcHtml, pageFid: fid)
          : <ThreadSummary>[];
      final mergedThreads =
          DiscuzThreadParser.mergeTemplates(mobileThreads, pcThreads);

      var header = ComiisParser.parseForumHeader(pcHtml, fid);
      final mHeader = ComiisParser.parseForumHeader(mobileHtml, fid);
      if (header.rulesHtml.isEmpty &&
          header.name.isEmpty &&
          !header.hasTodayPosts) {
        if (mHeader.rulesHtml.isNotEmpty ||
            mHeader.bannerUrl != null ||
            mHeader.todayPosts > 0) {
          header = mHeader;
        }
      }
      header = DiscuzForumCounters.mergeHeaders(header, mHeader);
      // 版主名单互补合并：杜绝任何截断与缺失
      if (header.moderators.isEmpty ||
          header.moderators.contains('+') ||
          (mHeader.moderators.isNotEmpty &&
              mHeader.moderators.split(' ').length >
                  header.moderators.split(' ').length)) {
        header = header.copyWith(moderators: mHeader.moderators);
      }

      final types = DiscuzThreadTypes.merge(
          ComiisParser.parseThreadTypes(pcHtml,
              fid: fid, selectedTypeid: typeid),
          ComiisParser.parseThreadTypes(mobileHtml,
              fid: fid, selectedTypeid: typeid));
      final base = Uri.parse(AppConfig.baseUrl);
      final subForums = DiscuzForumParser.mergeSubForums(
          DiscuzForumParser.parseSubForums(mobileHtml, base, currentFid: fid),
          DiscuzForumParser.parseSubForums(pcHtml, base, currentFid: fid));
      return (
        threads: mergedThreads.isNotEmpty ? mergedThreads : pcThreads,
        header: header,
        types: types,
        subForums: subForums,
      );
    });
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新版块');

    final previousTypes = PreloadService.instance
        .get<List<DiscuzThreadType>>('forum_types_$fid', ignoreExpired: true);
    final replaceCatalog = page == 1 &&
        (typeid ?? 0) == 0 &&
        pcHtml.isNotEmpty &&
        mobileHtml.isNotEmpty &&
        bundle.types.isNotEmpty;
    final catalog = replaceCatalog
        ? bundle.types
        : DiscuzThreadTypes.merge(previousTypes ?? const [], bundle.types);
    PreloadService.instance.set('forum_types_$fid', catalog);
    bundle = (
      threads: bundle.threads,
      header: bundle.header,
      types: catalog,
      subForums: bundle.subForums
    );

    final base = Uri.parse(AppConfig.baseUrl);
    final next = DiscuzForumParser.forumNextPage(mobileHtml, fid, page, base,
                typeid: typeid, orderby: orderby) !=
            null ||
        DiscuzForumParser.forumNextPage(pcHtml, fid, page, base,
                typeid: typeid, orderby: orderby) !=
            null;
    PreloadService.instance
        .set(_forumNextKey(fid, page, typeid, orderby), next);
    // Default Discuz only declares children on page 1. Absence on a later
    // page is not a new empty child-forum list.
    if (page == 1 || bundle.subForums.isNotEmpty) {
      PreloadService.instance.set('forum_children_$fid', bundle.subForums);
    }

    if (bundle.threads.isNotEmpty ||
        !bundle.header.isEmpty ||
        bundle.subForums.isNotEmpty) {
      PreloadService.instance
          .set(cacheKey, bundle, ttl: const Duration(minutes: 5));
    }
    _observeThreadAvatars(bundle.threads, session);
    return bundle;
  }

  /// 版块帖子列表（实时获取）
  static Future<List<ThreadSummary>> getThreadList(
    int fid, {
    int? typeid,
    int page = 1,
    String? orderby,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'thread_list_${fid}_${typeid}_${orderby}_$page';
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<List<ThreadSummary>>(cacheKey);
      if (cached != null) return cached;
    }
    final bundle = await getForumBundle(fid,
        typeid: typeid,
        page: page,
        orderby: orderby,
        forceRefresh: forceRefresh);
    PreloadService.instance
        .set(cacheKey, bundle.threads, ttl: const Duration(minutes: 5));
    return bundle.threads;
  }

  static final Map<int, PostFloor> _threadOpFloors = {};
  static final Map<int, int> _threadOpPids = {};
  static final Map<int, int> _threadAuthorUids = {};
  static final Map<int, int> _threadContentVersions = {};

  /// 帖子详情（支持内存预加载与分页，支持正序/倒序 ordertype）
  static Future<ThreadDetailParsed> getThreadDetail(
    int tid, {
    int page = 1,
    int? ordertype,
    bool forceRefresh = false,
  }) async {
    final session = DioClient.sessionKey;
    final version = _threadContentVersions[tid] ?? 0;
    final otKey = ordertype != null && ordertype > 0 ? '_ot$ordertype' : '';
    final cacheKey = 'thread_detail_${tid}_$page$otKey';
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<ThreadDetailParsed>(cacheKey);
      if (cached != null) {
        PreloadService.instance
            .set('thread_preview_detail', (tid: tid, detail: cached));
        _preloadThreadDetail(tid, page,
            totalPages: cached.totalPages, ordertype: ordertype);
        return cached;
      }
    } else {
      PreloadService.instance.remove(cacheKey);
      clearQuickCache('forum.php?mod=viewthread&tid=$tid');
    }
    try {
      final res = await _fetchThreadDetail(
        tid,
        page,
        ordertype: ordertype,
        forceRefresh: forceRefresh,
      );
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新帖子');
      if (version != (_threadContentVersions[tid] ?? 0)) {
        throw StateError('帖子访问状态已变化，请重新加载');
      }
      PreloadService.instance.set(cacheKey, res);
      PreloadService.instance
          .set('thread_preview_detail', (tid: tid, detail: res));
      _preloadThreadDetail(tid, page,
          totalPages: res.totalPages, ordertype: ordertype);
      return res;
    } catch (e) {
      if (session != DioClient.sessionKey) rethrow;
      if (version != (_threadContentVersions[tid] ?? 0)) rethrow;
      if (e is DiscuzThreadAccessException) {
        _invalidateThreadContent(tid);
        rethrow;
      }
      if (e is ServerOutageException || ServerOutageInfo.tryParse(e) != null) {
        rethrow;
      }
      final cached = PreloadService.instance.get<ThreadDetailParsed>(cacheKey);
      if (cached != null) return cached;
      rethrow;
    }
  }

  static void _invalidateThreadContent(int tid) {
    _threadContentVersions[tid] = (_threadContentVersions[tid] ?? 0) + 1;
    PreloadService.instance.clear('thread_detail_${tid}_');
    clearQuickCache('forum.php?mod=viewthread&tid=$tid');
    clearQuickCache('thread-$tid-');
    // Old responses may finish after a restriction was received. Stop new
    // readers from sharing those requests; the version also blocks late writes.
    _inFlightGets.removeWhere((key, _) =>
        key.startsWith('forum.php?mod=viewthread&tid=$tid&') ||
        key.startsWith('thread-$tid-'));
    final preview = PreloadService.instance
        .get<({int tid, ThreadDetailParsed detail})>('thread_preview_detail',
            ignoreExpired: true);
    if (preview?.tid == tid) {
      PreloadService.instance.remove('thread_preview_detail');
    }
    _threadOpFloors.remove(tid);
    _threadOpPids.remove(tid);
    _threadAuthorUids.remove(tid);
  }

  static void _preloadThreadDetail(int tid, int page,
      {required int totalPages, int? ordertype}) {
    if (page >= totalPages) return;
    final session = DioClient.sessionKey;
    final version = _threadContentVersions[tid] ?? 0;
    Future.microtask(() async {
      try {
        final nextPage = page + 1;
        final otKey = ordertype != null && ordertype > 0 ? '_ot$ordertype' : '';
        final nextKey = 'thread_detail_${tid}_$nextPage$otKey';
        if (!PreloadService.instance.has(nextKey)) {
          final res =
              await _fetchThreadDetail(tid, nextPage, ordertype: ordertype);
          if (session != DioClient.sessionKey ||
              version != (_threadContentVersions[tid] ?? 0)) {
            return;
          }
          PreloadService.instance.set(nextKey, res);
        }
      } on DiscuzThreadAccessException {
        if (session == DioClient.sessionKey &&
            version == (_threadContentVersions[tid] ?? 0)) {
          _invalidateThreadContent(tid);
        }
      } catch (_) {}
    });
  }

  static Future<ThreadDetailParsed> _fetchThreadDetail(
    int tid,
    int page, {
    int? ordertype,
    bool forceRefresh = false,
  }) async {
    final session = DioClient.sessionKey;
    final version = _threadContentVersions[tid] ?? 0;
    void checkContentVersion() {
      if (session != DioClient.sessionKey ||
          version != (_threadContentVersions[tid] ?? 0)) {
        throw StateError('帖子访问状态已变化，请重新加载');
      }
    }

    final otParam =
        (ordertype != null && ordertype > 0) ? '&ordertype=$ordertype' : '';
    String html;
    try {
      html = await _get(
        'forum.php?mod=viewthread&tid=$tid&mobile=2&page=$page$otParam',
        forceRefresh: forceRefresh,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // 404 兜底：尝试伪静态 thread-X-1-1.html 与 PC 端接口，杜绝移动端路由异常
        try {
          html = await _get(
            'thread-$tid-$page-1.html',
            forceRefresh: forceRefresh,
          );
        } catch (_) {
          try {
            html = await _get(
              'forum.php?mod=viewthread&tid=$tid&mobile=no&page=$page$otParam',
              forceRefresh: forceRefresh,
            );
          } catch (_) {
            throw Exception('该帖子不存在、已被删除或无访问权限 (HTTP 404)');
          }
        }
      } else {
        rethrow;
      }
    }
    checkContentVersion();
    var detail = await ComiisParser.parseThreadDetailAsync(html);
    checkContentVersion();
    if (detail.floors.isEmpty) {
      // 检查是否包含权限/密码等系统错误提示；若无，尝试回退到 PC 端（mobile=no）提取完整内容
      final hasAlert = html.contains('messagetext') ||
          html.contains('alert_error') ||
          html.contains('jump_c') ||
          html.contains('comiis_tip');
      if (!hasAlert) {
        try {
          final pcHtml = await _get(
            'forum.php?mod=viewthread&tid=$tid&mobile=no&page=$page$otParam',
            forceRefresh: forceRefresh,
          );
          final pcDetail = await ComiisParser.parseThreadDetailAsync(pcHtml);
          checkContentVersion();
          if (pcDetail.floors.isNotEmpty) {
            detail = pcDetail;
          }
        } on DiscuzThreadAccessException {
          rethrow;
        } catch (_) {}
      }
    }
    checkContentVersion();
    if (detail.floors.isEmpty) {
      throw const DiscuzThreadAccessException(
          DiscuzThreadAccessKind.unavailable, '论坛未返回可阅读的帖子内容，请刷新后重试。');
    }
    final currentIsDesc = (ordertype != null && ordertype > 0)
        ? (ordertype == 1)
        : detail.isDescOrder;

    if (detail.authorUid != null) {
      _threadAuthorUids[tid] = detail.authorUid!;
    }
    final effectiveAuthorUid = detail.authorUid ?? _threadAuthorUids[tid];

    List<PostFloor> processedFloors = List<PostFloor>.from(detail.floors);

    if (page == 1) {
      // 1. 在第 1 页：寻找并锁定真实楼主 OP
      int louzhuIdx = -1;
      for (int i = 0; i < processedFloors.length; i++) {
        final f = processedFloors[i];
        if (f.floorNumber == '楼主' &&
            (effectiveAuthorUid == null || f.uid == effectiveAuthorUid)) {
          louzhuIdx = i;
          break;
        }
      }
      if (louzhuIdx < 0 && effectiveAuthorUid != null) {
        for (int i = 0; i < processedFloors.length; i++) {
          final f = processedFloors[i];
          if (f.uid == effectiveAuthorUid &&
              (f.floorNumber.isEmpty || f.floorNumber == '1#')) {
            louzhuIdx = i;
            break;
          }
        }
      }

      if (louzhuIdx >= 0) {
        final opFloor = processedFloors[louzhuIdx];
        _threadOpFloors[tid] = opFloor;
        if (opFloor.pid != null) _threadOpPids[tid] = opFloor.pid!;

        if (louzhuIdx != 0) {
          processedFloors.removeAt(louzhuIdx);
          processedFloors.insert(0, opFloor);
        }
      } else {
        // 第 1 页未包含楼主（典型如未来 dateline 导致在 ordertype=2 下楼主被推迟到末页）
        PostFloor? opFloor = _threadOpFloors[tid];
        if (opFloor == null) {
          try {
            final baseHtml =
                await _get('forum.php?mod=viewthread&tid=$tid&mobile=2&page=1');
            checkContentVersion();
            final baseDetail = ComiisParser.parseThreadDetail(baseHtml);
            if (baseDetail.floors.isNotEmpty) {
              final first = baseDetail.floors.first;
              if (effectiveAuthorUid == null ||
                  first.uid == effectiveAuthorUid) {
                opFloor = first;
                _threadOpFloors[tid] = opFloor;
                if (opFloor.pid != null) _threadOpPids[tid] = opFloor.pid!;
              }
            }
          } on DiscuzThreadAccessException {
            rethrow;
          } catch (_) {}
        }
        checkContentVersion();
        if (opFloor != null) {
          final targetPid = opFloor.pid;
          if (targetPid != null) {
            processedFloors.removeWhere((f) => f.pid == targetPid);
          }
          processedFloors.insert(0, opFloor);
        }
      }

      // 规范化第 1 页的回复：任何在 index >= 1 处的「楼主」标号均为 Discuz 模板计数伪标号，一律矫正为「沙发」
      for (int i = 1; i < processedFloors.length; i++) {
        final f = processedFloors[i];
        if (f.floorNumber == '楼主') {
          processedFloors[i] = f.copyWith(
            floorNumber: '沙发',
            isThreadAuthor:
                effectiveAuthorUid != null && f.uid == effectiveAuthorUid,
          );
        }
      }
    } else {
      // 2. 在第 2 页及之后：
      // 绝对剔除真正的楼主主帖（杜绝任何未来 dateline 或服务端 SQL 排序缺陷导致楼主落入第 2 页作为回帖渲染！）
      int? opPid = _threadOpPids[tid];
      if (opPid == null) {
        try {
          final baseKey = 'thread_detail_${tid}_1';
          final cached =
              PreloadService.instance.get<ThreadDetailParsed>(baseKey);
          if (cached != null && cached.floors.isNotEmpty) {
            opPid = cached.floors.first.pid;
            if (opPid != null) _threadOpPids[tid] = opPid;
          }
        } catch (_) {}
      }
      if (opPid != null) {
        processedFloors.removeWhere((f) => f.pid == opPid);
      }

      // 规范化假「楼主」标号：所有进入回帖列表却被打上「楼主」标签的楼层（Discuz 模板倒序倒数至 1 的产物），全部矫正为「沙发」
      for (int i = 0; i < processedFloors.length; i++) {
        final f = processedFloors[i];
        if (f.floorNumber == '楼主' || f.floorNumber.startsWith('楼主')) {
          processedFloors[i] = f.copyWith(
            floorNumber: '沙发',
            isThreadAuthor:
                effectiveAuthorUid != null && f.uid == effectiveAuthorUid,
          );
        }
      }
    }

    final normalizedFloors = _normalizeFloorsOrder(
      processedFloors,
      isDescOrder: currentIsDesc,
      page: page,
      threadAuthorUid: effectiveAuthorUid,
    );
    final effectiveReplies = math.max(
      detail.replies,
      normalizedFloors.length > 1 ? (normalizedFloors.length - 1) : 0,
    );
    if (detail.isDescOrder != currentIsDesc ||
        detail.floors != normalizedFloors ||
        detail.replies != effectiveReplies) {
      detail = (
        title: detail.title,
        floors: normalizedFloors,
        totalPages: detail.totalPages,
        firstAuthorCredits: detail.firstAuthorCredits,
        publishDate: detail.publishDate,
        lastReplyDate: detail.lastReplyDate,
        forumName: detail.forumName,
        fid: detail.fid,
        breadcrumbs: detail.breadcrumbs,
        typeName: detail.typeName,
        typeid: detail.typeid,
        likes: detail.likes,
        favorites: detail.favorites,
        views: detail.views,
        replies: effectiveReplies,
        tags: detail.tags,
        stamp: detail.stamp,
        stampUrl: detail.stampUrl,
        coverUrl: detail.coverUrl,
        isFavorited: detail.isFavorited,
        hasExplicitFavState: detail.hasExplicitFavState,
        isLiked: detail.isLiked,
        favid: detail.favid,
        aiSummary: detail.aiSummary,
        isDescOrder: currentIsDesc,
        targetOrdertype: currentIsDesc ? 2 : 1,
        authorUid: effectiveAuthorUid ?? detail.authorUid,
        author: detail.author,
      );
    }
    checkContentVersion();
    _observeModelAvatars([
      for (final floor in detail.floors) ...[
        if ((floor.uid ?? 0) > 0)
          DiscuzAvatarDeclaration(
              uid: floor.uid!, username: floor.author, faceUrl: floor.faceUrl),
        for (final reply in floor.replyFloors)
          if ((reply.uid ?? 0) > 0)
            DiscuzAvatarDeclaration(
                uid: reply.uid!,
                username: reply.author,
                avatarUrl: reply.avatar,
                faceUrl: reply.faceUrl),
      ],
    ], session);
    return detail;
  }

  /// 楼层排序规范化保障：
  /// 1. 第 1 页的主题作者（楼主）永远锁定在 index 0，绝不参与倒序反转！
  /// 2. 仅对第 1 页回复楼层进行排序对齐：若服务端未反转回复，按要求准确规范回复顺序。
  /// 3. 第 2 页及之后：保持 Discuz 服务端返回的天然分页回复顺序，严禁反转破坏服务端分页！
  static List<PostFloor> _normalizeFloorsOrder(
    List<PostFloor> floors, {
    required bool isDescOrder,
    required int page,
    int? threadAuthorUid,
  }) {
    if (floors.length <= 1) return floors;
    if (page == 1) {
      final louzhu = floors.first;
      final replies = floors.sublist(1);
      if (replies.length <= 1) return floors;

      // 检查回复楼层的单调性
      final numFloors = <int>[];
      for (final r in replies) {
        if (r.floorNumber.contains('沙发')) {
          numFloors.add(2);
        } else if (r.floorNumber.contains('板凳')) {
          numFloors.add(3);
        } else if (r.floorNumber.contains('地板')) {
          numFloors.add(4);
        } else {
          final n =
              int.tryParse(r.floorNumber.replaceAll(RegExp(r'[^\d]'), ''));
          if (n != null && n > 0) numFloors.add(n);
        }
      }
      bool isRepliesDesc = false;
      if (numFloors.length >= 2) {
        int desc = 0;
        int asc = 0;
        for (int i = 0; i < numFloors.length - 1; i++) {
          if (numFloors[i] > numFloors[i + 1]) desc++;
          if (numFloors[i] < numFloors[i + 1]) asc++;
        }
        isRepliesDesc = desc > asc;
      }
      if (isDescOrder && !isRepliesDesc && numFloors.isNotEmpty) {
        return [louzhu, ...replies.reversed];
      } else if (!isDescOrder && isRepliesDesc && numFloors.isNotEmpty) {
        return [louzhu, ...replies.reversed];
      }
      return floors;
    } else {
      return floors;
    }
  }

  static final Set<int> _failedForumTids = {};
  static final Map<int, Future<String?>> _inFlightForumRequests = {};
  static final List<({int tid, Completer<String?> completer})>
      _forumResolutionQueue = [];
  static bool _isProcessingForumQueue = false;

  /// 异步获取帖子的绝对真实版块信息（带串行低优先级排队与流量节流，彻底杜绝并发抓取导致页面卡顿）
  static Future<String?> resolveThreadForumAsync(int tid) async {
    if (tid <= 0 || _failedForumTids.contains(tid)) return null;
    final cached = ComiisParser.getForumNameByTid(tid);
    if (cached != null && cached.isNotEmpty) return cached;

    if (_inFlightForumRequests.containsKey(tid)) {
      return _inFlightForumRequests[tid]!;
    }

    final completer = Completer<String?>();
    _inFlightForumRequests[tid] = completer.future;

    // 滑动太快时控制排队上限，丢弃队列最前端旧请求，防止无谓的网络占用
    if (_forumResolutionQueue.length >= 10) {
      final dropped = _forumResolutionQueue.removeAt(0);
      _inFlightForumRequests.remove(dropped.tid);
      if (!dropped.completer.isCompleted) {
        dropped.completer.complete(null);
      }
    }

    _forumResolutionQueue.add((tid: tid, completer: completer));
    _processForumResolutionQueue();

    return completer.future;
  }

  static void _processForumResolutionQueue() async {
    if (_isProcessingForumQueue) return;
    _isProcessingForumQueue = true;

    while (_forumResolutionQueue.isNotEmpty) {
      final req = _forumResolutionQueue.removeAt(0);
      final tid = req.tid;

      final cached = ComiisParser.getForumNameByTid(tid);
      if (cached != null && cached.isNotEmpty) {
        if (!req.completer.isCompleted) req.completer.complete(cached);
        _inFlightForumRequests.remove(tid);
        continue;
      }

      String? forumName;
      try {
        final html = await _get(
          'forum.php?mod=viewthread&tid=$tid&mobile=2',
          retries: 0,
          cacheTtl: const Duration(minutes: 5),
        );
        int? fid;
        final fidMatch = RegExp(r'\bfid\s*=\s*parseInt\(\s*[\x27\x22]?(\d+)')
            .firstMatch(html);
        if (fidMatch != null) {
          fid = int.tryParse(fidMatch.group(1)!);
          if (fid != null && fid > 0) {
            forumName = ComiisParser.getForumNameByFid(fid);
          }
        }

        if (forumName == null || forumName.isEmpty) {
          final titleMatch =
              RegExp(r'<title>(?:[^\-<]*)?-\s*([^<>\-]+?)\s*-[^<]*</title>')
                  .firstMatch(html);
          if (titleMatch != null) {
            final cand = titleMatch.group(1)!.trim();
            if (cand.isNotEmpty && !cand.contains('苦力怕论坛')) {
              forumName = cand;
            }
          }
        }

        if (forumName != null && forumName.isNotEmpty) {
          ComiisParser.registerThread(
            tid,
            fid: fid,
            forumName: forumName,
          );
        }
      } catch (_) {}

      if (forumName == null || forumName.isEmpty) {
        _failedForumTids.add(tid);
      }

      if (!req.completer.isCompleted) {
        req.completer.complete(forumName);
      }
      _inFlightForumRequests.remove(tid);

      // 请求之间留出 200ms 空隙，让出网络信道与渲染帧
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _isProcessingForumQueue = false;
  }

  /// 快速获取主题详情（兼容别名）
  static Future<ThreadDetailParsed> getThread(
    int tid, {
    int page = 1,
    int? ordertype,
    bool forceRefresh = false,
  }) =>
      getThreadDetail(tid,
          page: page, ordertype: ordertype, forceRefresh: forceRefresh);

  /// 导读分类、顺序、空列表和下一页以当前站点页面为准。
  static Future<List<ThreadSummary>> getGuide(String view,
      {int page = 1, bool forceRefresh = false}) async {
    if (!DiscuzGuideProtocol.views.contains(view) || page < 1) {
      throw ArgumentError('当前站点未提供该导读分类');
    }
    final session = DioClient.sessionKey;
    final cacheKey = 'guide_${view}_$page';
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<List<ThreadSummary>>(cacheKey);
      if (cached != null) {
        _observeThreadAvatars(cached, session);
        return cached;
      }
    }
    final templates = view == 'sofa' ? ['2'] : ['no', '2'];
    Object? lastError;
    for (final mobile in templates) {
      try {
        final path = Uri(path: 'forum.php', queryParameters: {
          'mod': 'guide',
          'view': view,
          'page': page.toString(),
          'mobile': mobile,
          if (mobile == '2') 'index': '1',
        }).toString();
        final source = await _getCommunitySource(path,
            forceRefresh: forceRefresh,
            expectedSession: session,
            guideView: view);
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新导读');
        _rejectRestrictedPage(source);
        if (!DiscuzGuideProtocol.recognizes(source, view)) {
          lastError =
              StateError(DiscuzResponse.message(source) ?? '网站未返回对应导读分类');
          continue;
        }
        final actualPage = DiscuzForumParser.actualCurrentPage(source);
        if (actualPage != null && actualPage != page) {
          throw StateError('论坛返回第 $actualPage 页，请选择有效页码');
        }
        final workerBaseUrl = AppConfig.baseUrl;
        final list = await Isolate.run(() {
          AppConfig.baseUrl = workerBaseUrl;
          return ComiisParser.parseThreadList(source);
        });
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新导读');
        _observeThreadAvatars(list, session);
        for (final thread in list) {
          ComiisParser.registerThread(thread.tid,
              fid: thread.fid, forumName: thread.forumName);
          PreloadService.instance.saveThreadSummary(thread.tid, thread);
        }
        PreloadService.instance
            .set(cacheKey, list, ttl: const Duration(minutes: 5));
        PreloadService.instance.set('guide_preview_threads', list);
        PreloadService.instance.set(
            'guide_next_${view}_$page',
            DiscuzGuideProtocol.nextPage(
                    source, view, page, Uri.parse(AppConfig.baseUrl)) !=
                null);
        return list;
      } catch (error) {
        if (session != DioClient.sessionKey) rethrow;
        lastError = error;
      }
    }
    throw lastError ?? StateError('导读暂不可用');
  }

  static bool? guideHasNextPage(String view, int page) =>
      PreloadService.instance
          .get<bool>('guide_next_${view}_$page', ignoreExpired: true);

  /// 当前签到页的实际个人状态；短缓存与并发合并避免首页卡片重复抓取。
  static final Map<String, Future<SignHeaderInfo>> _signHeaderLoads = {};
  static String get _signHeaderCacheKey =>
      _diskKey('sign_header_${AutoSignService.instance.serverTodayStr}');
  static SignHeaderInfo? get cachedSignHeaderInfo =>
      PreloadService.instance.get<SignHeaderInfo>(_signHeaderCacheKey);
  // The first signer belongs to a server day, not the personal-state 20s TTL.
  static SignHeaderInfo? get cachedTodaySignHeader => PreloadService.instance
      .get<SignHeaderInfo>(_signHeaderCacheKey, ignoreExpired: true);

  static Future<SignHeaderInfo> getSignHeaderInfo(
      {bool forceRefresh = true}) async {
    final session = DioClient.sessionKey;
    final day = AutoSignService.instance.serverTodayStr;
    final signWriteRevision = AutoSignService.instance.signWriteRevision;
    final loadKey = '$session|$day';
    final cacheKey = _signHeaderCacheKey;
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<SignHeaderInfo>(cacheKey);
      if (cached != null) return cached;
    }
    final pending = _signHeaderLoads[loadKey];
    if (pending != null) return pending;
    final future = _loadSignHeader(session).then((result) {
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新签到页面');
      if (day != AutoSignService.instance.serverTodayStr) {
        throw StateError('论坛日期已变化，请刷新签到页面');
      }
      if (signWriteRevision != AutoSignService.instance.signWriteRevision) {
        throw StateError('签到状态已更新，旧页面结果已忽略');
      }
      PreloadService.instance
          .set(cacheKey, result, ttl: const Duration(seconds: 20));
      signHeaderChanges.value++;
      return result;
    });
    _signHeaderLoads[loadKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_signHeaderLoads[loadKey], future)) {
        _signHeaderLoads.remove(loadKey);
      }
    }
  }

  static Future<SignHeaderInfo> _loadSignHeader(String session) async {
    final now = AutoSignService.instance.estimatedServerNow;
    SignHeaderInfo? best;
    Object? lastError;
    for (final path in const [
      'plugin.php?id=k_misign:sign&mobile=no',
      'k_misign-sign.html?mobile=no',
      'plugin.php?id=k_misign:sign&mobile=2',
    ]) {
      try {
        final source =
            await _get(path, forceRefresh: true, cacheTtl: Duration.zero);
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新签到页面');
        final parsed = DiscuzSignParser.page(source,
            defaultUid: _cachedMyUid,
            defaultUsername: _cachedMyUsername,
            serverDay: now.day);
        if (!parsed.isRecognized) continue;
        if (parsed.hasPersonalState &&
            _cachedMyUid != null &&
            parsed.uid != null &&
            parsed.uid != _cachedMyUid) {
          throw StateError('签到页面账号与当前会话不一致，请重新登录后刷新');
        }
        if (parsed.hasPersonalState && DioClient.isLoggedIn) {
          final formhash = _extractFormhash(source);
          if (formhash != null && formhash.isNotEmpty) {
            _cachedSignFormhash = formhash;
          }
        }
        final previous = best;
        final combined = previous != null &&
                previous.hasPersonalState &&
                !parsed.hasPersonalState
            ? previous
            : parsed;
        best = previous == null
            ? parsed
            : combined.copyWith(
                hasPersonalStats:
                    parsed.hasPersonalStats || previous.hasPersonalStats,
                hasContinuousDays:
                    parsed.hasContinuousDays || previous.hasContinuousDays,
                continuousDays: parsed.hasContinuousDays
                    ? parsed.continuousDays
                    : previous.continuousDays,
                hasTotalDays: parsed.hasTotalDays || previous.hasTotalDays,
                totalDays:
                    parsed.hasTotalDays ? parsed.totalDays : previous.totalDays,
                hasTodaySignCount:
                    parsed.hasTodaySignCount || previous.hasTodaySignCount,
                todaySignCount: parsed.hasTodaySignCount
                    ? parsed.todaySignCount
                    : previous.todaySignCount,
                starUsername: parsed.starUsername.isNotEmpty
                    ? parsed.starUsername
                    : previous.starUsername,
                starUid: parsed.starUsername.isNotEmpty &&
                        parsed.starUsername != previous.starUsername
                    ? parsed.starUid
                    : parsed.starUid ?? previous.starUid,
                clearStarIdentity: parsed.starUsername.isNotEmpty &&
                    parsed.starUsername != previous.starUsername,
                highestCount: parsed.highestCount > 0
                    ? parsed.highestCount
                    : previous.highestCount,
              );
        if (best.hasTodaySignCount &&
            (!DioClient.isLoggedIn || best.hasPersonalState)) {
          break;
        }
      } catch (error) {
        if (session != DioClient.sessionKey) rethrow;
        lastError = error;
      }
    }
    if (best == null) {
      if (lastError != null) throw lastError;
      throw StateError('论坛没有返回可识别的签到页面，请稍后刷新');
    }
    if (DioClient.isLoggedIn && !best.hasPersonalState) {
      throw StateError('未取得当前账号的签到状态，请检查登录状态');
    }
    return best;
  }

  /// 用户搜索（对接 Discuz spacecp&ac=search 原生接口 + 用户名直查 + UID 精确直达）
  static Future<List<UserSpace>> searchUsers(String keyword,
      {int page = 1}) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const [];

    final results = <UserSpace>[];
    final seenUids = <int>{};

    // 1. 若关键词为纯数字 UID，优先精确查询该 UID
    final directUid = int.tryParse(trimmed);
    if (directUid != null && directUid > 0) {
      try {
        final directUser = await getUserSpace(directUid, forceRefresh: true);
        if (directUser != null && directUser.username.isNotEmpty) {
          results.add(directUser);
          seenUids.add(directUser.uid);
        }
      } catch (_) {}
    }

    // 2. 发起 Discuz 原生用户搜索接口
    try {
      final encoded = Uri.encodeComponent(trimmed);
      final html = await _get(
        'home.php?mod=spacecp&ac=search&searchsubmit=yes&username=$encoded&page=$page',
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: true,
      );
      final list = ComiisParser.parseSearchUsers(html);
      for (final u in list) {
        if (!seenUids.contains(u.uid)) {
          seenUids.add(u.uid);
          results.add(u);
        }
      }
    } catch (_) {}

    // 3. 若搜索结果仍为空，且非纯数字，尝试按精确用户名直接查询其 PC 空间
    if (results.isEmpty && directUid == null) {
      try {
        final encoded = Uri.encodeComponent(trimmed);
        final directHtml = await _get(
          'home.php?mod=space&username=$encoded&mobile=no',
          headers: {'User-Agent': AppConfig.pcUserAgent},
          forceRefresh: true,
        );
        final uidMatch =
            RegExp(r'space-uid-(\d+)|uid=(\d+)').firstMatch(directHtml);
        final foundUid = uidMatch != null
            ? (int.tryParse(uidMatch.group(1) ?? uidMatch.group(2) ?? '') ?? 0)
            : 0;
        if (foundUid > 0 && !seenUids.contains(foundUid)) {
          final foundUser = await getUserSpace(foundUid, forceRefresh: true);
          if (foundUser != null && foundUser.username.isNotEmpty) {
            results.add(foundUser);
            seenUids.add(foundUid);
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// 签到排行（k_misign；实时获取）
  static Future<List<SignEntry>> getSignRank(String op,
      {int page = 1, bool forceRefresh = true}) async {
    final queryOp = DiscuzSignPagination.operation(op);
    if (page < 1) throw ArgumentError('签到排行页码无效');
    final session = DioClient.sessionKey;
    final cacheKey = 'sign_rank_${queryOp}_$page';
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<List<SignEntry>>(cacheKey);
      if (cached != null) return cached;
    } else {
      // Keep the last confirmed page when a manual refresh fails.
      clearQuickCache('plugin.php?id=k_misign:sign&operation=list&op=$queryOp');
    }
    final result = await _fetchSignRankPage(queryOp, page,
        forceRefresh: forceRefresh, session: session);
    _cacheSignRankPage(queryOp, page, result.entries, result.pagination,
        session: session);
    final nextPage = result.pagination.nextPage;
    if (nextPage != null) _preloadSignRank(queryOp, nextPage, session);
    return result.entries;
  }

  static DiscuzSignPagination? signRankPagination(String op, int page) =>
      PreloadService.instance.get<DiscuzSignPagination>(
          'sign_rank_pagination_${DiscuzSignPagination.operation(op)}_$page',
          ignoreExpired: true);

  static int? signRankTotalPages(String op) => PreloadService.instance.get<int>(
      'sign_rank_total_${DiscuzSignPagination.operation(op)}',
      ignoreExpired: true);

  static Future<({List<SignEntry> entries, DiscuzSignPagination pagination})>
      _fetchSignRankPage(String op, int page,
          {required bool forceRefresh, required String session}) async {
    for (final template in const ['no', '2']) {
      final source = await _get(
        'plugin.php?id=k_misign:sign&operation=list&op=$op&mobile=$template'
        '${page > 1 ? '&page=$page&pp=$page' : ''}',
        headers: {
          'User-Agent': template == 'no'
              ? AppConfig.pcUserAgent
              : AppConfig.mobileUserAgent
        },
        forceRefresh: forceRefresh,
        cacheTtl: const Duration(seconds: 15),
        expectedSession: session,
      );
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新排行');
      _rejectRestrictedPage(source);
      final pagination = DiscuzSignPagination.parse(source,
          op: op, requestedPage: page, base: Uri.parse(AppConfig.baseUrl));
      if (!pagination.recognized) continue;
      return (
        entries: ComiisParser.parseSignList(source),
        pagination: pagination
      );
    }
    throw StateError('论坛没有返回可识别的签到排行，请刷新重试');
  }

  static void _cacheSignRankPage(String op, int page, List<SignEntry> entries,
      DiscuzSignPagination pagination,
      {required String session}) {
    if (session != DioClient.sessionKey) return;
    const ttl = Duration(seconds: 15);
    PreloadService.instance.set('sign_rank_${op}_$page', entries, ttl: ttl);
    PreloadService.instance
        .set('sign_rank_pagination_${op}_$page', pagination, ttl: ttl);
    final total = pagination.totalPages ??
        (page == 1 && entries.length < 10 && pagination.nextPage == null
            ? 1
            : null);
    if (total != null) {
      PreloadService.instance.set('sign_rank_total_$op', total, ttl: ttl);
    }
  }

  static void _preloadSignRank(String op, int nextPage, String session) {
    Future.microtask(() async {
      try {
        final nextKey = 'sign_rank_${op}_$nextPage';
        if (session == DioClient.sessionKey &&
            !PreloadService.instance.has(nextKey)) {
          final result = await _fetchSignRankPage(op, nextPage,
              forceRefresh: false, session: session);
          _cacheSignRankPage(op, nextPage, result.entries, result.pagination,
              session: session);
        }
      } catch (_) {}
    });
  }

  /// 获取服务端日历已签到日期（全实时从 k_misign 提取，兼容 PC 与移动端）
  static Future<Set<int>> getSignedDaysFromServerCalendar({
    int? month,
    int? year,
    bool forceRefresh = true,
  }) async {
    if (!DioClient.isLoggedIn) return const {};
    final session = DioClient.sessionKey;
    final now = AutoSignService.instance.estimatedServerNow;
    final m = month ?? now.month;
    final y = year ?? now.year;
    if (m < 1 || m > 12 || y < 1970 || y > 9999) throw ArgumentError('无效月份');
    final monthKey = signCalendarKey(y, m);
    final paths = [
      'plugin.php?id=k_misign:sign&operation=calendar&month=$m&year=$y&mobile=no',
      if (y == now.year && m == now.month)
        'plugin.php?id=k_misign:sign&mobile=no',
    ];
    for (final path in paths) {
      final source = await _get(path,
          forceRefresh: forceRefresh, cacheTtl: const Duration(seconds: 20));
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新签到日历');
      if (RegExp(r'''\b(?:discuz_uid|comiis_uid)\s*=\s*['"]?0(?:['";\s]|$)''')
          .hasMatch(source)) {
        throw StateError('签到日历返回游客页面，请检查登录状态');
      }
      final calendar = DiscuzSignParser.calendar(source, year: y, month: m);
      if (!calendar.recognized) continue;
      final sp = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新签到日历');
      await sp.setStringList(
          monthKey, calendar.days.map((day) => '$day').toList());
      return calendar.days;
    }
    throw StateError('论坛没有返回 $y 年 $m 月的签到日历');
  }

  /// 小黑屋（违规公示；使用移动端接口 mobile=2 及 cid 分页游标）
  static Future<({List<DarkroomEntry> entries, int? nextCid})> getDarkroom({
    int? cid,
    int page = 1,
  }) async {
    final cacheKey = 'darkroom_${cid}_$page';
    final cached = PreloadService.instance
        .get<({List<DarkroomEntry> entries, int? nextCid})>(cacheKey);
    if (cached != null) return cached;

    final url = cid != null
        ? 'forum.php?mod=misc&action=showdarkroom&cid=$cid&mobile=2'
        : 'forum.php?mod=misc&action=showdarkroom&page=$page&mobile=2';
    final html = await _get(
      url,
      headers: {'User-Agent': AppConfig.mobileUserAgent},
    );
    final res = ComiisParser.parseDarkroom(html);
    PreloadService.instance
        .set(cacheKey, res, ttl: const Duration(minutes: 10));
    return res;
  }

  // ================= 登录用户个人资料 7 天持久化长效缓存 =================
  static int? _cachedMyUid;
  static String? _cachedMyUsername;
  static String? _cachedMyAvatar;
  static UserSpace? _cachedMyUserSpace;

  static const String _keyCachedMyUid = 'klpbbs_cached_my_uid';
  static const String _keyCachedMyUsername = 'klpbbs_cached_my_username';
  static const String _keyCachedMyAvatar = 'klpbbs_cached_my_avatar';
  static const String _keyCachedUserSpaceJson = 'klpbbs_cached_user_space_json';
  static const String _keyCachedUserProfileTime =
      'klpbbs_cached_user_profile_time';
  static const String _keyCachedUserProfileSchema =
      'klpbbs_cached_user_profile_schema';
  // Earlier templates mixed storage usage with balances and omitted currencies.
  // Keep the saved identity, but only restore data parsed with this schema.
  static const int _userProfileSchemaVersion = 2;
  static const Duration userProfileTtl = Duration(days: 7);

  /// 初始化/恢复登录用户个人资料（App 启动时在 main() 调用）
  static Future<void> initUserProfileCache() async {
    _initializeDio();
    try {
      final sp = await SharedPreferences.getInstance();
      if (!DioClient.isLoggedIn ||
          sp.getString('klpbbs_profile_session') != DioClient.sessionKey) {
        AppConfig.myFaceUrl = null;
        return;
      }
      final savedTimeMs = sp.getInt(_keyCachedUserProfileTime) ?? 0;
      if (savedTimeMs > 0) {
        final savedDate = DateTime.fromMillisecondsSinceEpoch(savedTimeMs);
        if (DateTime.now().difference(savedDate) < userProfileTtl) {
          _cachedMyUid = sp.getInt(_keyCachedMyUid);
          _cachedMyUsername = sp.getString(_keyCachedMyUsername);
          _cachedMyAvatar = sp.getString(_keyCachedMyAvatar);
          final rawJson = sp.getString(_keyCachedUserSpaceJson);
          if (rawJson != null &&
              rawJson.isNotEmpty &&
              sp.getInt(_keyCachedUserProfileSchema) ==
                  _userProfileSchemaVersion) {
            try {
              final map = jsonDecode(rawJson) as Map<String, dynamic>;
              final space = UserSpace.fromJson(map);
              if (space.uid > 0 &&
                  space.username.isNotEmpty &&
                  !space.isLocked) {
                _cachedMyUserSpace = space;
                if (space.faceUrl.isNotEmpty) {
                  AppConfig.myFaceUrl ??= space.faceUrl;
                }
                PreloadService.instance
                    .set('user_space_${space.uid}', space, ttl: userProfileTtl);
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// 持久化缓存登录用户的空间资料（7天有效）
  static Future<void> saveUserProfile(UserSpace space,
      {String? expectedSession}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    if (space.uid <= 0 ||
        space.username.isEmpty ||
        space.isLocked ||
        !DioClient.isLoggedIn ||
        session != DioClient.sessionKey) {
      return;
    }
    final avatar = AppConfig.avatarUrl(space.uid);
    _cachedMyUid = space.uid;
    if (space.username.isNotEmpty) _cachedMyUsername = space.username;
    _cachedMyUserSpace = space;
    _cachedMyAvatar = avatar;
    if (space.faceUrl.isNotEmpty) {
      AppConfig.updateCachedFaceUrl(space.faceUrl);
    }
    PreloadService.instance
        .set('user_space_${space.uid}', space, ttl: userProfileTtl);

    try {
      final sp = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey) return;
      await sp.setString('klpbbs_profile_session', session);
      if (session != DioClient.sessionKey) return;
      await sp.setString(_keyCachedMyAvatar, avatar);
      if (session != DioClient.sessionKey) return;
      await sp.setInt(_keyCachedMyUid, space.uid);
      if (session != DioClient.sessionKey) return;
      if (space.username.isNotEmpty) {
        await sp.setString(_keyCachedMyUsername, space.username);
        if (session != DioClient.sessionKey) return;
      }
      if (space.faceUrl.isNotEmpty) {
        await sp.setString('my_face_url', space.faceUrl);
        if (session != DioClient.sessionKey) return;
      }
      await sp.setString(_keyCachedUserSpaceJson, jsonEncode(space.toJson()));
      if (session != DioClient.sessionKey) return;
      await sp.setInt(_keyCachedUserProfileSchema, _userProfileSchemaVersion);
      if (session != DioClient.sessionKey) return;
      await sp.setInt(
          _keyCachedUserProfileTime, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// 清除登录用户持久化资料缓存（登出时调用）
  static Future<void> clearUserProfileCache() async {
    _cachedMyUid = null;
    _cachedMyUsername = null;
    _cachedMyAvatar = null;
    _cachedMyUserSpace = null;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_keyCachedMyUid);
      await sp.remove(_keyCachedMyUsername);
      await sp.remove(_keyCachedMyAvatar);
      await sp.remove(_keyCachedUserSpaceJson);
      await sp.remove(_keyCachedUserProfileTime);
      await sp.remove(_keyCachedUserProfileSchema);
      await sp.remove('klpbbs_profile_session');
    } catch (_) {}
  }

  /// 获取当前已缓存的我的 UID（纯同步/零延迟）
  static int? get currentCachedMyUid => _cachedMyUid;

  /// 获取当前已缓存的我的用户名（纯同步/零延迟）
  static String? get currentCachedMyUsername => _cachedMyUsername;

  /// 获取当前已缓存的我的头像 URL（纯同步/零延迟）
  static String? get currentCachedMyAvatar => _cachedMyAvatar;

  /// 获取当前已缓存的我的用户空间资料（纯同步/零延迟）
  static UserSpace? get cachedSpace => _cachedMyUserSpace;
  static UserSpace? get currentCachedMyUserSpace => _cachedMyUserSpace;

  /// 成功写入后保留登录身份，重新读取会变化的资料、余额与用户组。
  static Future<void> invalidateUserProfile({String? expectedSession}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    if (session != DioClient.sessionKey) return;
    _cachedMyUserSpace = null;
    PreloadService.instance.clear('user_space_');
    clearQuickCache();
    try {
      final sp = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey) return;
      await sp.remove(_keyCachedUserSpaceJson);
      if (session != DioClient.sessionKey) return;
      await sp.remove(_keyCachedUserProfileTime);
      if (session != DioClient.sessionKey) return;
      await sp.remove(_keyCachedUserProfileSchema);
    } catch (_) {}
    if (session == DioClient.sessionKey) {
      profileChanges.value++;
    }
  }

  /// 用户空间（个人资料，支持 7 天长期本地持久化秒开）
  static Future<UserSpace?> getUserSpace(int uid,
      {bool forceRefresh = false}) async {
    final session = DioClient.sessionKey;
    void checkSession() {
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新加载个人空间');
    }

    UserSpace observe(UserSpace space) {
      checkSession();
      if (!space.isLocked) {
        _observeModelAvatars([
          DiscuzAvatarDeclaration(
              uid: space.uid, username: space.username, faceUrl: space.faceUrl)
        ], session);
      }
      return space;
    }

    Future<String> profileSource(String mobile, {int retries = 2}) async {
      try {
        return await _get(
            'home.php?mod=space&uid=$uid&do=profile&mobile=$mobile',
            headers:
                mobile == 'no' ? {'User-Agent': AppConfig.pcUserAgent} : null,
            forceRefresh: forceRefresh,
            retries: retries,
            expectedSession: session);
      } catch (_) {
        checkSession();
        return '';
      }
    }

    final cacheKey = 'user_space_$uid';
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<UserSpace>(cacheKey);
      if (cached != null &&
          (cached.creditsDetail.isNotEmpty || cached.isLocked)) {
        return observe(cached);
      }
      if (_cachedMyUserSpace != null &&
          (_cachedMyUserSpace!.uid == uid || uid <= 0) &&
          _cachedMyUserSpace!.creditsDetail.isNotEmpty) {
        return observe(_cachedMyUserSpace!);
      }
    }

    try {
      final myUid = await getMyUid();
      checkSession();
      final isMe = (myUid != null && myUid > 0 && myUid == uid) || (uid <= 0);

      if (!isMe && uid > 0) {
        // Current desktop profile declares all currencies and medal details.
        // One complete request serves both native layouts; mobile is fallback.
        final html = await profileSource('no', retries: 1);
        checkSession();

        var userProfile = ComiisParser.parseUserSpace(html, uid);

        // 如果资料页为空或缺少关键数据，且未被明确判定为锁定，才回退拉取 PC 权威个人资料页
        if (userProfile == null ||
            (userProfile.username.isEmpty && !userProfile.isLocked)) {
          final fallbackHtml = await profileSource('2', retries: 1);
          checkSession();
          final fallbackProfile =
              ComiisParser.parseUserSpace(fallbackHtml, uid);
          if (fallbackProfile != null) {
            userProfile = fallbackProfile;
          }
        }

        if (userProfile == null ||
            (userProfile.username.isEmpty && !userProfile.isLocked)) {
          return null;
        }

        if (userProfile.isLocked) {
          final lockReason = userProfile.lockReason.isNotEmpty
              ? userProfile.lockReason
              : '空间已被锁定无法访问，如有疑问请联系管理员';
          final lockedRes = UserSpace(
            uid: uid,
            username: '',
            isLocked: true,
            lockReason: lockReason,
          );
          PreloadService.instance
              .set(cacheKey, lockedRes, ttl: const Duration(minutes: 15));
          return lockedRes;
        }

        PreloadService.instance
            .set(cacheKey, userProfile, ttl: const Duration(minutes: 30));
        return observe(userProfile);
      }

      // The site now omits some medal details from the mobile profile.
      final html = await profileSource('no');
      checkSession();
      var res = ComiisParser.parseUserSpace(html, uid);

      if (res == null || res.username.isEmpty) {
        final pcHtml = await profileSource('2');
        checkSession();
        final pcRes = ComiisParser.parseUserSpace(pcHtml, uid);
        if (pcRes != null) {
          res = pcRes;
        }
      }

      if (res == null || (res.username.isEmpty && !res.isLocked)) return null;

      if (res.isLocked) {
        PreloadService.instance
            .set(cacheKey, res, ttl: const Duration(minutes: 15));
        return res;
      }

      if (isMe) {
        await saveUserProfile(res, expectedSession: session);
        checkSession();
      } else {
        PreloadService.instance
            .set(cacheKey, res, ttl: const Duration(minutes: 30));
      }
      return observe(res);
    } catch (_) {
      checkSession();
      return null;
    }
  }

  static final _publicIdentityLoads =
      <String, Future<DiscuzAvatarDeclaration?>>{};
  static final _publicIdentityCache =
      <String, ({DiscuzAvatarDeclaration identity, DateTime time})>{};

  /// Read-only lookup through the exact name query and scoped space owner.
  /// Simultaneous home, sign and canvas consumers share one request.
  static Future<DiscuzAvatarDeclaration?> resolvePublicUserIdentity(
      String username) async {
    final name = username.trim();
    if (name.isEmpty) return null;
    final session = DioClient.sessionKey;
    final base = Uri.parse(AppConfig.baseUrl);
    final key = '$session|$base|$name';
    final cached = _publicIdentityCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.time) < const Duration(hours: 1)) {
      _observeModelAvatars([cached.identity], session, allowFrameRemoval: true);
      return cached.identity;
    }
    final pending = _publicIdentityLoads[key];
    if (pending != null) return pending;
    final future = (() async {
      final path = Uri(
          path: 'home.php',
          queryParameters: {'mod': 'space', 'username': name, 'mobile': 'no'});
      Uri? finalUri;
      final source = await _get(path.toString(),
          headers: {'User-Agent': AppConfig.pcUserAgent},
          expectedSession: session,
          onResponseUri: (uri) => finalUri = uri);
      if (session != DioClient.sessionKey) return null;
      final identity = DiscuzAvatarDeclarations.namedSpace(source,
          base: base,
          responseUri: finalUri ?? base.resolve(path.toString()),
          username: name);
      if (identity == null) return null;
      AvatarAppearanceStore.instance.useScope(session);
      AvatarAppearanceStore.instance.remember(identity);
      cacheAuthorUid(name, identity.uid);
      _publicIdentityCache[key] = (identity: identity, time: DateTime.now());
      if (_publicIdentityCache.length > 128) {
        _publicIdentityCache.remove(_publicIdentityCache.keys.first);
      }
      final header = cachedTodaySignHeader;
      if (header?.starUsername == name) {
        PreloadService.instance.update<SignHeaderInfo>(
            _signHeaderCacheKey,
            (value) => value.copyWith(
                starUid: identity.uid,
                starAvatarUrl: identity.avatarUrl,
                starFaceUrl: identity.faceUrl));
        signHeaderChanges.value++;
      }
      return identity;
    })();
    _publicIdentityLoads[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_publicIdentityLoads[key], future)) {
        _publicIdentityLoads.remove(key);
      }
    }
  }

  /// 按用户名查询用户空间资料
  static Future<UserSpace?> getUserSpaceByName(String username) async {
    try {
      final identity = await resolvePublicUserIdentity(username);
      return identity == null ? null : await getUserSpace(identity.uid);
    } catch (_) {
      return null;
    }
  }

  /// 当前用户身份来自站点会话变量，持久化资料只用于同一会话的展示。
  static Future<int?> getMyUid({bool forceRefresh = false}) async {
    _initializeDio();
    if (!DioClient.isLoggedIn) return null;
    if (!forceRefresh && _cachedMyUid != null && _cachedMyUid! > 0) {
      return _cachedMyUid;
    }
    return (await checkLoginStatus(forceRefresh: forceRefresh)).uid;
  }

  /// 管理身份和管辖版块以本人实时 PC 资料为准，不根据组名或用户名子串推断。
  static Future<DiscuzUserRole> getMyRole({int? fid}) async {
    final uid = await getMyUid();
    if (uid == null) return const DiscuzUserRole();
    try {
      final page = await _get(
          'home.php?mod=space&uid=$uid&do=profile&mobile=no',
          cacheTtl: const Duration(seconds: 30));
      return DiscuzRoleParser.parseOwnProfile(page, uid);
    } catch (_) {
      return DiscuzUserRole(uid: uid);
    }
  }

  /// 小喇叭广播（ahome_horn，内嵌于「社区」页 forumlist=1）
  static Future<List<HornMessage>> getHornMessages() async {
    final session = DioClient.sessionKey;
    final generation = _cacheGeneration;
    Object? failure;
    for (final path in const [
      'forum.php?mobile=no',
      'forum.php?forumlist=1&mobile=2'
    ]) {
      try {
        final source = await _get(path);
        if (session != DioClient.sessionKey) {
          throw StateError('论坛会话已切换');
        }
        final list = ComiisParser.parseHornMessages(source);
        if (generation == _cacheGeneration) {
          _observeModelAvatars(
              list.where((message) => (message.uid ?? 0) > 0).map((message) =>
                  DiscuzAvatarDeclaration(
                      uid: message.uid!,
                      username: message.author,
                      avatarUrl: message.avatarUrl,
                      faceUrl: message.faceUrl)),
              session,
              allowFrameRemoval: true,
              replaceObservedAppearance: true);
        }
        if (list.isNotEmpty || path.endsWith('mobile=2')) {
          if (generation == _cacheGeneration) {
            PreloadService.instance
                .set('horn_messages', list, ttl: const Duration(seconds: 15));
          }
          if (path.endsWith('mobile=no') &&
              list.any((message) => (message.uid ?? 0) > 0)) {
            _startHornAvatarBatch(session, generation);
          }
          return list;
        }
        failure = null;
      } catch (error) {
        if (session != DioClient.sessionKey) rethrow;
        failure = error;
      }
    }
    if (failure != null) throw failure;
    return const [];
  }

  static void _startHornAvatarBatch(String session, int generation) {
    final key = '$session|$generation';
    if (_hornAvatarLoads.containsKey(key)) return;
    final future = () async {
      try {
        final path = 'forum.php?forumlist=1&mobile=2';
        final source = await _get(path, expectedSession: session);
        if (session != DioClient.sessionKey || generation != _cacheGeneration) {
          return;
        }
        final mobileTemplate = DiscuzAvatarDeclarations.usesMobileFrameTemplate(
            source, Uri.parse(_url(path)));
        final messages = ComiisParser.parseHornMessages(source);
        _observeModelAvatars(
            messages.where((message) => (message.uid ?? 0) > 0).map((message) =>
                DiscuzAvatarDeclaration(
                    uid: message.uid!,
                    username: message.author,
                    avatarUrl: message.avatarUrl,
                    faceUrl: message.faceUrl)),
            session,
            allowFrameRemoval: true,
            replaceObservedAppearance: true);
        if (mobileTemplate) {
          for (final message in messages) {
            if ((message.uid ?? 0) > 0) _avatarLookup.observed(message.uid!);
          }
        }
      } catch (_) {
        // The canonical PC messages remain usable while mobile is unavailable.
        // Visible unresolved authors can use the bounded profile fallback.
      }
    }();
    _hornAvatarLoads[key] = future;
    unawaited(future.whenComplete(() {
      if (identical(_hornAvatarLoads[key], future)) {
        _hornAvatarLoads.remove(key);
      }
    }));
  }

  /// 小喇叭发布页信息（formhash + 文本颜色选项）
  static Future<({String formhash, List<String> colors})>
      getHornPostInfo() async {
    final html = await _get('plugin.php?id=ahome_horn:add&fid=&tid=0');
    return ComiisParser.parseHornPostInfo(html);
  }

  /// 发布小喇叭，以插件的实际响应确认结果。
  static Future<bool> postHorn({
    required String message,
    String color = '',
    bool boss = false,
    String url = '',
    String hidename = '0',
    String ifsystem = '0',
  }) async {
    if (!AppConfig.allowWrite) return false;
    final info = await getHornPostInfo();
    if (info.formhash.isEmpty) return false;
    final data = <String, dynamic>{
      'formhash': info.formhash,
      'fid': '',
      'tid': '',
      'fromurl': '',
      'ifsystem': ifsystem,
      'hidename': hidename,
      'color': color,
      'message': message,
      'addsubmit': 'true',
    };
    if (boss) data['boss'] = '1';
    if (url.isNotEmpty) data['url'] = url;
    final response = await _post('plugin.php?id=ahome_horn:add', data);
    return DiscuzResponse.isSuccess(response);
  }

  /// 只使用当前网页提供的删除链接，避免重复 id 参数和猜测插件路由。
  static Future<bool> deleteHorn(int id, {String? deleteUrl}) async {
    if (!AppConfig.allowWrite ||
        !DioClient.isLoggedIn ||
        id <= 0 ||
        deleteUrl?.isNotEmpty != true) {
      return false;
    }
    final target = Uri.parse(_url(deleteUrl!));
    if (!DiscuzRequestPolicy.sameOrigin(target, Uri.parse(AppConfig.baseUrl))) {
      return false;
    }
    try {
      final response = await _get(target.toString(), forceRefresh: true);
      _clearCache();
      return DiscuzResponse.isSuccess(response, acceptedMessages: ['已删除']);
    } catch (_) {
      return false;
    }
  }

  /// 提交帖子投票
  static Future<bool> submitPoll({
    required int tid,
    int? fid,
    required List<int> optionIds,
  }) async {
    if (!AppConfig.allowWrite || optionIds.isEmpty) return false;
    try {
      final page = await _get('forum.php?mod=viewthread&tid=$tid&mobile=2');
      final formhash = _extractFormhash(page) ?? '';
      if (formhash.isEmpty) return false;

      final data = <String, dynamic>{
        'formhash': formhash,
        'pollsubmit': 'yes',
        'pollanswers[]': optionIds.map((e) => e.toString()).toList(),
      };
      for (var i = 0; i < optionIds.length; i++) {
        data['pollanswers[$i]'] = optionIds[i].toString();
      }
      final targetFid = fid ?? 0;
      final res = await _post(
        'forum.php?mod=misc&action=votepoll&fid=$targetFid&tid=$tid&pollsubmit=yes&quickforward=yes&mobile=2',
        data,
      );
      final ok = DiscuzResponse.isSuccess(res);
      if (ok) {
        clearThreadDetailCache(tid);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  static bool _isSearchRateLimited(String html) {
    return html.contains('秒内只能进行一次搜索') ||
        html.contains('两次搜索之间') ||
        html.contains('搜索间隔');
  }

  static String _extractRateLimitNotice(String html) {
    final match = RegExp(
      r'(?:抱歉|对不起)[^<，,。！!\n]*(?:秒内只能进行一次搜索|两次搜索之间[^<，,。！!\n]*|搜索间隔[^<，,。！!\n]*)',
    ).firstMatch(html);
    if (match != null) {
      return match.group(0)!.trim();
    }
    return '抱歉，您在 15 秒内只能进行一次搜索，请稍后再试';
  }

  /// 搜索结果内存缓存（5分钟 TTL，避免频繁重复查询触发 Discuz 15 秒限频）
  static final Map<String, List<ThreadSummary>> _searchMemoryCache = {};
  static final Map<String, DateTime> _searchMemoryCacheTime = {};
  static final Map<String, ({int id, DateTime time})> _searchIndexes = {};
  static final Map<String, int> _searchPageCounts = {};
  static final Map<String, ({String source, DateTime time})>
      _siteSearchDeclarations = {};

  /// 基础检索使用网站当前入口；高级检索使用 Discuz 的真实表单参数。
  static Future<List<ThreadSummary>> search(
    String keyword, {
    String author = '',
    String srchtype = 'title',
    String orderby = 'dateline',
    String ascdesc = 'desc',
    int? fid,
    List<int>? fids,
    int page = 1,
    bool preferTheme = false,
    void Function(int pages)? onPagination,
  }) async {
    final kw = keyword.trim();
    if (kw.isEmpty && author.trim().isEmpty) return const [];
    final selectedFids = {...?fids, if (fid != null && fid > 0) fid}
        .where((id) => id > 0)
        .toList()
      ..sort();
    final session = DioClient.sessionKey;
    final queryKey =
        '$session|$kw|${author.trim()}|$srchtype|$orderby|$ascdesc|${selectedFids.join("_")}';
    final key = '$queryKey|$page';
    final time = _searchMemoryCacheTime[key];
    if (time != null &&
        DateTime.now().difference(time) < const Duration(minutes: 5)) {
      onPagination?.call(_searchPageCounts[key] ?? page);
      return _searchMemoryCache[key]!;
    }
    final headers = {'User-Agent': AppConfig.pcUserAgent};
    String? failure(String source) {
      if (_isSearchRateLimited(source)) {
        throw SearchRateLimitException(_extractRateLimitNotice(source));
      }
      final doc = html_parser.parse(source);
      final notice = doc
          .querySelector('#messagetext, .alert_error, .comiis_tip, .jump_c')
          ?.text
          .trim();
      if (notice?.isNotEmpty == true) return notice;
      if (doc.querySelector('#loginform, form[name="login"]') != null) {
        return '请登录后搜索';
      }
      return null;
    }

    List<ThreadSummary> store(String source) {
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新搜索');
      final message = failure(source);
      if (message != null) throw StateError(message);
      final doc = html_parser.parse(source);
      final results = ComiisParser.parseSearchResults(source);
      final empty = RegExp(r'没有找到|未找到|没有搜索到|没有匹配|搜索结果.*?0|暂无.*?结果')
          .hasMatch(doc.body?.text ?? '');
      if (results.isEmpty &&
          !empty &&
          doc.querySelector(
                  '#threadlist, .slst, .search-results, .result-list, .emp, '
                  '.result-card, .main-layout .content .search-stats') ==
              null) {
        throw const FormatException('未取得搜索结果页面，请在论坛网页确认当前账号的搜索权限');
      }
      final pages = KlpSearchProtocol.pages(doc, page);
      _searchMemoryCache[key] = results;
      _searchMemoryCacheTime[key] = DateTime.now();
      _searchPageCounts[key] = pages;
      while (_searchMemoryCache.length > 40) {
        final oldest = _searchMemoryCache.keys.first;
        _searchMemoryCache.remove(oldest);
        _searchMemoryCacheTime.remove(oldest);
        _searchPageCounts.remove(oldest);
      }
      onPagination?.call(pages);
      return results;
    }

    Future<List<ThreadSummary>> siteSearch(String declarations) async {
      if (author.trim().isNotEmpty && kw.isNotEmpty) {
        throw StateError('当前网站请按关键词或用户名分别搜索，结果可再筛选作者');
      }
      final request = KlpSearchProtocol.request(declarations,
          keyword: kw.isNotEmpty ? kw : author.trim(),
          scope: kw.isEmpty ? 'author' : srchtype,
          orderby: orderby,
          direction: ascdesc,
          fids: selectedFids,
          page: page);
      return store(await _get(request.toString(),
          headers: headers, forceRefresh: true, expectedSession: session));
    }

    final siteKey = '$session|${AppConfig.baseUrl}';
    final declaration = _siteSearchDeclarations[siteKey];
    if (declaration != null &&
        DateTime.now().difference(declaration.time) <
            const Duration(minutes: 5)) {
      return siteSearch(declaration.source);
    }
    final index = _searchIndexes[queryKey];
    final validIndex = index != null &&
        DateTime.now().difference(index.time) < const Duration(minutes: 5);
    final parameters = <String, String>{
      'mod': 'forum',
      'mobile': 'no',
      'searchsubmit': 'yes',
      'orderby':
          const {'dateline', 'lastpost', 'replies', 'views'}.contains(orderby)
              ? orderby
              : 'lastpost',
      'ascdesc': ascdesc == 'asc' ? 'asc' : 'desc',
      'page': '$page',
    };
    if (validIndex) {
      parameters['searchid'] = '${index.id}';
    } else {
      final formSource = await _get('search.php?mod=forum&adv=yes&mobile=no',
          headers: headers, expectedSession: session);
      if (KlpSearchProtocol.recognizes(formSource)) {
        _siteSearchDeclarations[siteKey] =
            (source: formSource, time: DateTime.now());
        return siteSearch(formSource);
      }
      final message = failure(formSource);
      if (message != null) throw StateError(message);
      final formDoc = html_parser.parse(formSource);
      final formhash = _extractFormhash(formSource);
      if (formhash == null ||
          formDoc.querySelector('[name="srchtxt"]') == null) {
        throw const FormatException('搜索表单不可用');
      }
      if (srchtype == 'fulltext' &&
          formDoc.querySelector('[name="srchtype"][value="fulltext"]') ==
              null) {
        throw StateError('当前用户组不支持全文搜索，请改为标题搜索');
      }
      parameters.addAll({
        'formhash': formhash,
        'srchtxt': kw,
        'srchuname': author.trim(),
        'srchtype': srchtype == 'fulltext' ? 'fulltext' : 'title',
        if (selectedFids.isNotEmpty) 'srchfid': selectedFids.join('_'),
      });
    }
    Uri? resultUri;
    final resultSource = await _get(
        Uri(path: 'search.php', queryParameters: parameters).toString(),
        headers: headers,
        forceRefresh: true,
        onResponseUri: (uri) => resultUri = uri);
    final results = store(resultSource);
    final searchId = int.tryParse(resultUri?.queryParameters['searchid'] ?? '');
    if (searchId != null && searchId > 0) {
      _searchIndexes[queryKey] = (id: searchId, time: DateTime.now());
    }
    return results;
  }

  /// 设置最佳答案（Discuz 悬赏帖楼主采纳最佳回复并结算悬赏）
  static Future<bool> setBestAnswer(int tid, int pid) async {
    if (!DioClient.isLoggedIn || tid <= 0 || pid <= 0) return false;
    try {
      final page = await _get('forum.php?mod=viewthread&tid=$tid&mobile=no',
          headers: {'User-Agent': AppConfig.pcUserAgent}, forceRefresh: true);
      final formhash = _extractFormhash(page);
      if (formhash == null || formhash.isEmpty) return false;
      final response = await _post(
          'forum.php?mod=misc&action=bestanswer&tid=$tid&pid=$pid&bestanswersubmit=yes&inajax=1&mobile=no',
          {
            'formhash': formhash,
            'bestanswersubmit': 'yes',
            'tid': '$tid',
            'pid': '$pid'
          },
          headers: {
            'User-Agent': AppConfig.pcUserAgent
          });
      if (DiscuzResponse.isSuccess(response, acceptedMessages: const ['已解决'])) {
        clearQuickCache('forum.php?mod=viewthread&tid=$tid');
        return true;
      }
      throw StateError(_extractDiscuzResponseMessage(response,
          defaultMsg: '网站未确认采纳结果，请刷新帖子查看'));
    } on DioException {
      throw StateError('网站未确认采纳结果，请刷新帖子查看后再操作');
    }
  }

  /// 私信收件箱（会话列表）
  static Future<List<PmConversation>> getPmList() async {
    final session = DioClient.sessionKey;
    List<PmConversation> observe(List<PmConversation> list) {
      _observeModelAvatars(
          list.where((item) => item.touid > 0).map((item) =>
              DiscuzAvatarDeclaration(
                  uid: item.touid,
                  username: item.username,
                  faceUrl: item.faceUrl)),
          session);
      return list;
    }

    final html = await _get(
      'home.php?mod=space&do=pm&filter=privatepm&mobile=no',
    );
    if (html.contains('抱歉，您尚未登录') ||
        html.contains('messagelogin') ||
        html.contains('member.php?mod=logging&action=login')) {
      throw Exception('未登录或登录状态已失效，请重新登录');
    }
    final list = ComiisParser.parsePmList(html);
    if (list.isEmpty) {
      try {
        final fallbackHtml = await _get(
          'home.php?mod=space&do=pm&mobile=no',
        );
        if (!fallbackHtml.contains('抱歉，您尚未登录') &&
            !fallbackHtml.contains('messagelogin')) {
          final fallbackList = ComiisParser.parsePmList(fallbackHtml);
          if (fallbackList.isNotEmpty) return observe(fallbackList);
        }
      } catch (_) {}
    }
    return observe(list);
  }

  /// 私信会话详情（与某用户的消息）
  static Future<List<PmMessage>> getPmDetail(int touid) async {
    final session = DioClient.sessionKey;
    final html = await _get(
      'home.php?mod=space&do=pm&subop=view&touid=$touid&mobile=no',
    );
    final list = ComiisParser.parsePmDetail(html);
    _observeModelAvatars(
        list.where((item) => item.authorUid > 0).map((item) =>
            DiscuzAvatarDeclaration(
                uid: item.authorUid,
                username: item.author,
                faceUrl: item.faceUrl)),
        session);
    return list;
  }

  /// 用户主题/回复列表（home.php?mod=space&uid=&do=thread，实时获取）
  static Future<List<ThreadSummary>> getUserThreads(
    int uid, {
    String type = 'thread',
    int page = 1,
  }) async {
    final cacheKey = 'user_threads_${uid}_${type}_$page';
    final myUid = await getMyUid().catchError((_) => null);
    final isMe = myUid != null && myUid == uid;

    final endpoints = isMe
        ? [
            'home.php?mod=space&uid=$uid&do=thread&view=me&from=space&type=$type&mobile=no${page > 1 ? '&page=$page' : ''}',
            'home.php?mod=space&uid=$uid&do=thread&view=me&type=$type&from=space&mobile=2${page > 1 ? '&page=$page' : ''}',
            'home.php?mod=space&do=thread&view=me&type=$type&mobile=no${page > 1 ? '&page=$page' : ''}',
            'forum.php?mod=guide&view=my&type=$type&mobile=no${page > 1 ? '&page=$page' : ''}',
            'home.php?mod=space&uid=$uid&do=thread&type=$type&from=space&mobile=no${page > 1 ? '&page=$page' : ''}',
            'home.php?mod=space&uid=$uid&do=thread&type=$type&mobile=2${page > 1 ? '&page=$page' : ''}',
          ]
        : [
            'home.php?mod=space&uid=$uid&do=thread&type=$type&from=space&mobile=no${page > 1 ? '&page=$page' : ''}',
            'home.php?mod=space&uid=$uid&do=thread&type=$type&from=space&mobile=2${page > 1 ? '&page=$page' : ''}',
            'home.php?mod=space&uid=$uid&do=thread&type=$type&view=all&from=space&mobile=no${page > 1 ? '&page=$page' : ''}',
            'home.php?mod=space&uid=$uid&do=thread&type=$type&view=all&mobile=2${page > 1 ? '&page=$page' : ''}',
          ];

    List<ThreadSummary> list = const [];
    for (final ep in endpoints) {
      try {
        final html = await _get(ep);
        if (html.contains('抱歉，您尚未登录') ||
            (html.contains('提示信息') &&
                (html.contains('请先登录') ||
                    html.contains('没有权限') ||
                    html.contains('指定的用户空间不存在')))) {
          // 论坛权限拦截或未登录，后续接口必然同样拦截，直接跳出避免无意义的多次请求导致严重卡顿
          break;
        }
        list = ComiisParser.parseUserThreads(html);
        if (list.isNotEmpty) break;
      } catch (_) {}
    }

    if (list.isNotEmpty) {
      PreloadService.instance.set(cacheKey, list);
      _preloadUserThreads(uid, type, page, isMe: isMe);
      return list;
    }
    final cached = PreloadService.instance.get<List<ThreadSummary>>(cacheKey);
    return cached ?? const [];
  }

  static void _preloadUserThreads(int uid, String type, int page,
      {bool isMe = false}) {
    Future.microtask(() async {
      try {
        final nextPage = page + 1;
        final nextKey = 'user_threads_${uid}_${type}_$nextPage';
        if (!PreloadService.instance.has(nextKey)) {
          final ep = isMe
              ? 'home.php?mod=space&uid=$uid&do=thread&view=me&from=space&type=$type&mobile=no&page=$nextPage'
              : 'home.php?mod=space&uid=$uid&do=thread&type=$type&from=space&mobile=no&page=$nextPage';
          final html = await _get(ep);
          final res = ComiisParser.parseUserThreads(html);
          if (res.isNotEmpty) {
            PreloadService.instance.set(nextKey, res);
          }
        }
      } catch (_) {}
    });
  }

  /// 收藏分页只更新已确认的项目；完整同步完成后才替换全部收藏。
  static Future<List<ThreadSummary>> getFavorites(
    int uid, {
    int page = 1,
    String? tag,
    bool forceRefresh = false,
  }) async {
    final session = DioClient.sessionKey;
    final myUid = await getMyUid();
    final key = favoriteThreadsPrefsKey;
    if (!DioClient.isLoggedIn || uid != myUid || key == null) {
      throw StateError('请使用当前账号查看自己的收藏');
    }
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新收藏');
    final selectedTag = tag != null && tag.isNotEmpty && tag != '全部';
    final tagParam = selectedTag ? '&tag=${Uri.encodeComponent(tag)}' : '';
    final path =
        'home.php?mod=space&uid=$uid&do=favorite&type=thread&mobile=no&page=$page$tagParam';
    final source = await _get(path, forceRefresh: forceRefresh);
    if (!DiscuzFavorites.recognizesThreads(source)) {
      throw StateError(DiscuzResponse.message(source) ?? '网站未返回可识别的收藏列表');
    }
    final list = ComiisParser.parseUserThreads(source);
    final prefs = await SharedPreferences.getInstance();
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新收藏');
    _ensureFavidCacheLoaded(prefs);
    final nextPage = DiscuzFavorites.nextPage(source, 'thread');
    PreloadService.instance.set(
        _diskKey('favorite_next_${uid}_${tag ?? ''}_$page'), nextPage != null);
    final complete = page == 1 && !selectedTag && nextPage == null;
    final ids = complete
        ? <String>{}
        : (prefs.getStringList(key) ?? const <String>[]).toSet();
    if (complete) _threadFavidCache.clear();
    for (final thread in list) {
      ids.add(thread.tid.toString());
      final favid =
          thread.favid ?? ComiisParser.extractFavidFromHtml(source, thread.tid);
      if (favid != null && favid > 0) _threadFavidCache[thread.tid] = favid;
    }
    await prefs.setStringList(key, ids.toList());
    await _persistThreadFavidCache(prefs, expectedSession: session);
    return list;
  }

  static bool? favoriteHasNextPage(int uid, int page, {String? tag}) =>
      PreloadService.instance
          .get<bool>(_diskKey('favorite_next_${uid}_${tag ?? ''}_$page'));

  /// 通知提醒（我的帖子/互动/系统/公共/应用/提到我的，实时获取）
  static Future<List<NoticeItem>> getNotices(
    String view, {
    String? type,
    int page = 1,
  }) async {
    final session = DioClient.sessionKey;
    List<NoticeItem> observe(List<NoticeItem> list) {
      _observeModelAvatars(
          list.where((item) => (item.uid ?? 0) > 0).map((item) =>
              DiscuzAvatarDeclaration(
                  uid: item.uid!,
                  username: item.author,
                  avatarUrl: item.avatarUrl,
                  faceUrl: item.faceUrl)),
          session);
      return list;
    }

    final viewParam = (view.isNotEmpty && view != 'all') ? '&view=$view' : '';
    final typeParam =
        (type != null && type.isNotEmpty && type != 'all') ? '&type=$type' : '';
    final cacheKey = 'notices_${view}_${type ?? "all"}_$page';
    try {
      var html = await _get(
        'home.php?mod=space&do=notice$viewParam$typeParam&mobile=2${page > 1 ? '&page=$page' : ''}',
      );
      var res = ComiisParser.parseNotices(html);
      if (res.isEmpty) {
        final pcHtml = await _get(
          'home.php?mod=space&do=notice$viewParam$typeParam&mobile=no${page > 1 ? '&page=$page' : ''}',
        );
        res = ComiisParser.parseNotices(pcHtml);
      }
      if (res.isNotEmpty) {
        PreloadService.instance.set(cacheKey, res);
        _preloadNotices(view, type, page);
        return observe(res);
      }
    } catch (_) {}
    final cached = PreloadService.instance.get<List<NoticeItem>>(cacheKey);
    return observe(cached ?? const []);
  }

  /// 仅从首页账号导航读取角标，避免后台打开提醒/私信列表并标记已读。
  static Future<DiscuzUnreadSummary> getUnreadSummary() async {
    if (!DioClient.isLoggedIn) throw StateError('请先登录');
    final session = DioClient.sessionKey;
    final source = await _get('forum.php?mod=index&mobile=no',
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: true,
        retries: 0,
        expectedSession: session);
    final summary = DiscuzUnreadSummary.parse(
        source, Uri.parse(AppConfig.baseUrl),
        expectedUid: _cachedMyUid);
    if (summary == null) throw StateError('网站未返回有效的未读消息角标');
    if (session != DioClient.sessionKey) throw StateError('账号已切换');
    return summary;
  }

  /// 忽略/标记全部提醒已读（向 Discuz 服务端发送清除通知）
  static Future<bool> ignoreNotice({String? view}) async {
    if (!DioClient.isLoggedIn) return false;
    try {
      final uid = await getMyUid();
      if (uid == null) return false;
      final viewParam = view != null && view.isNotEmpty ? '&view=$view' : '';
      final response = await _get(
        'home.php?mod=space&do=notice&ignore=all$viewParam&mobile=2',
        forceRefresh: true,
      );
      _clearCache();
      return DiscuzSessionParser.parse(response).uid == uid &&
          html_parser
                  .parse(response)
                  .querySelector('#messagetext, .alert_error, .comiis_tip') ==
              null;
    } catch (_) {
      return false;
    }
  }

  /// 获取 Discuz 用户组权限与晋级对照数据（home.php?mod=spacecp&ac=usergroup 网页真实数据）
  static Future<UsergroupComparison> getUsergroupComparison({
    String? currentGroupName,
    int? currentCredits,
    String? targetGroupName,
    int? gid,
  }) async {
    final gidParam = gid != null ? '&gid=$gid' : '';
    final html =
        await _get('home.php?mod=spacecp&ac=usergroup$gidParam&mobile=no');
    return ComiisParser.parseUsergroupComparison(html);
  }

  static void _preloadNotices(String view, String? type, int page) {
    Future.microtask(() async {
      try {
        final nextPage = page + 1;
        final typeParam =
            (type != null && type.isNotEmpty) ? '&type=$type' : '';
        final nextKey = 'notices_${view}_${type ?? "all"}_$nextPage';
        if (!PreloadService.instance.has(nextKey)) {
          final html = await _get(
            'home.php?mod=space&do=notice&view=$view$typeParam&mobile=no&page=$nextPage',
          );
          final res = ComiisParser.parseNotices(html);
          PreloadService.instance.set(nextKey, res);
        }
      } catch (_) {}
    });
  }

  /// 注册新账号（支持 SecCode 验证码；真实 klpbbs 可能还需短信/邮箱）
  static Future<({bool success, String message})> register(
    String username,
    String password,
    String email, {
    String? seccodeverify,
    String? seccodehash,
    String? seccodemodid,
    String? formhash,
  }) async {
    // 注册页字段名是 Discuz 随机生成的（reginput），必须先抓页面解析出真实字段名。
    // 已登录时访问注册页会 302 回首页，需先登出并清缓存后重试。
    var page = await _get('member.php?mod=register&mobile=2');
    var rf = ComiisParser.parseRegisterForm(page);
    if ((rf.formhash.isEmpty ||
            rf.usernameField.isEmpty ||
            rf.emailField.isEmpty) &&
        DioClient.isLoggedIn) {
      await DioClient.clearCookies();
      _clearCache();
      page = await _get('member.php?mod=register&mobile=2');
      rf = ComiisParser.parseRegisterForm(page);
    }

    var fHash = formhash ?? rf.formhash;
    var sHash = seccodehash ?? rf.seccodehash;
    var sModid = seccodemodid ?? rf.seccodemodid;

    if (fHash.isEmpty) {
      final info = await getRegisterSecCodeInfo();
      fHash = info.formhash;
      if (sHash.isEmpty) sHash = info.seccodehash;
      if (sModid.isEmpty) sModid = info.seccodemodid;
    }
    if (fHash.isEmpty || rf.usernameField.isEmpty || rf.emailField.isEmpty) {
      return (success: false, message: '获取注册表单凭证失败，请检查网络');
    }

    final data = <String, dynamic>{
      'formhash': fHash,
      'regsubmit': 'yes',
      'referer': AppConfig.baseUrl,
      rf.usernameField: username,
      rf.passwordField: password,
      rf.password2Field: password,
      rf.emailField: email,
      if (rf.agreebbrule.isNotEmpty) 'agreebbrule': rf.agreebbrule,
    };
    if (sHash.isNotEmpty && seccodeverify != null && seccodeverify.isNotEmpty) {
      data['seccodehash'] = sHash;
      data['seccodeverify'] = seccodeverify;
      if (sModid.isNotEmpty) data['seccodemodid'] = sModid;
    }

    final html = await _post(
      'member.php?mod=register&regsubmit=yes&mobile=2',
      data,
    );
    if (html.contains('验证码')) {
      return (success: false, message: '验证码错误或已过期，请刷新重试');
    }
    if (html.contains('来路不正确')) {
      return (success: false, message: '来路不正确（表单凭证失效，请刷新）');
    }
    if (html.contains('alert_error')) {
      final m = RegExp(r'alert_error[^>]*>([^<]+)<').firstMatch(html);
      return (success: false, message: m?.group(1)?.trim() ?? '注册失败，请检查填写信息');
    }
    return (success: true, message: '注册成功，请登录');
  }

  /// 退出登录
  static Future<bool> logout() async {
    bool serverOk = false;
    try {
      final page = await _get('home.php?mobile=no');
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash != null && formhash.isNotEmpty) {
        final html = await _get(
          'member.php?mod=logging&action=logout&formhash=$formhash&mobile=no',
        );
        serverOk = !html.contains('alert_error');
      }
    } catch (_) {}

    // 彻底重置所有本地内存与磁盘脏缓存
    _cachedMyUid = null;
    _cachedFormhash = null;
    _cachedSignFormhash = null;
    PreloadService.instance.clear();
    clearQuickCache();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('my_uid');
      await sp.remove('cached_username');
      await sp.remove('fav_tids');
      await sp.remove('liked_tids');
      await clearSignLocalCache();
      try {
        await AutoSignService.instance.onAccountSwitched();
      } catch (_) {}
      try {
        PushNotificationService.instance.clearUnread();
      } catch (_) {}
    } catch (_) {}

    // 清理 Dio 及已挂载的 WebView2 全局 Cookies
    await DioClient.clearCookies();
    return serverOk;
  }

  /// 从当前收藏表单读取备注和标签支持，供弹窗使用。
  static Future<({bool description, bool tags})> getThreadFavoriteOptions(
      int tid) async {
    final source = await _get(
      'home.php?mod=spacecp&ac=favorite&type=thread&id=$tid&inajax=1&mobile=no',
      cacheTtl: const Duration(seconds: 15),
    );
    final form = DiscuzForm.namedSubmit(source, 'favoritesubmit');
    if (form == null) {
      throw StateError(DiscuzResponse.message(source) ?? '网站未提供收藏表单');
    }
    return (
      description: form.editableNames.contains('description'),
      tags: form.editableNames.contains('favtag'),
    );
  }

  static String? get favoriteThreadsPrefsKey =>
      _cachedMyUid == null || !DioClient.isLoggedIn
          ? null
          : 'fav_tids:${AppConfig.baseUrl}:$_cachedMyUid';

  static final Set<String> _busyThreadFavorites = {};

  static Future<({bool success, String message})> favoriteThread(int tid,
          {String description = '', String favtag = ''}) =>
      _changeThreadFavorite(tid, true,
          description: description, favtag: favtag);

  static Future<({bool success, String message})> unfavoriteThread(int tid,
          {int? favid}) =>
      _changeThreadFavorite(tid, false);

  /// 先读取当前账号的确认表单，然后只提交一次网站提供的操作。
  static Future<({bool success, String message})> _changeThreadFavorite(
      int tid, bool add,
      {String description = '', String favtag = ''}) async {
    if (!DioClient.isLoggedIn || tid <= 0) {
      return (success: false, message: '请先登录论坛账号');
    }
    final session = DioClient.sessionKey;
    final busyKey = '$session:$tid';
    if (!_busyThreadFavorites.add(busyKey)) {
      return (success: false, message: '正在同步收藏，请稍候');
    }
    try {
      await getMyUid();
      final prefsKey = favoriteThreadsPrefsKey;
      if (prefsKey == null || session != DioClient.sessionKey) {
        return (success: false, message: '账号已改变，请重新加载');
      }
      final operation = add ? '' : '&op=delete';
      final pageUrl = _url(
          'home.php?mod=spacecp&ac=favorite&type=thread&id=$tid$operation&inajax=1&mobile=no');
      final source =
          await _get(pageUrl, forceRefresh: true, cacheTtl: Duration.zero);
      final already = add && DiscuzFavorites.isAlreadySaved(source);
      final form = DiscuzForm.namedSubmit(
          source, add ? 'favoritesubmit' : 'deletesubmit');
      var response = source;
      if (!already) {
        if (form == null) {
          return (
            success: false,
            message: DiscuzResponse.message(source) ?? '网站未提供收藏操作表单'
          );
        }
        final target = Uri.parse(pageUrl).resolve(form.action);
        final q = target.queryParameters;
        if (target.origin != Uri.parse(AppConfig.baseUrl).origin ||
            q['mod'] != 'spacecp' ||
            q['ac'] != 'favorite' ||
            q['type'] != 'thread' ||
            (add
                ? q['id'] != '$tid' || q['op'] == 'delete'
                : q['op'] != 'delete' ||
                    (int.tryParse(q['favid'] ?? '') ?? 0) <= 0)) {
          return (success: false, message: '收藏表单已改变，请重新加载');
        }
        final data = {...form.values};
        if (add &&
            description.isNotEmpty &&
            !form.editableNames.contains('description')) {
          return (success: false, message: '网站当前收藏表单不支持备注');
        }
        if (add &&
            favtag.isNotEmpty &&
            !form.editableNames.contains('favtag')) {
          return (success: false, message: '网站当前收藏表单不支持标签，请清空标签后重试');
        }
        if (add && form.editableNames.contains('description')) {
          data['description'] = description;
        }
        if (add && form.editableNames.contains('favtag')) {
          data['favtag'] = favtag;
        }
        if (session != DioClient.sessionKey) {
          return (success: false, message: '账号已切换，请重新操作');
        }
        response =
            await _post(target.toString(), data, headers: {'Referer': pageUrl});
      }
      if (!already && !DiscuzResponse.isSuccess(response)) {
        return (
          success: false,
          message: DiscuzResponse.message(response) ?? '网站未确认收藏操作，请刷新后确认'
        );
      }
      final prefs = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey) {
        return (success: false, message: '账号已切换，请刷新确认操作结果');
      }
      _ensureFavidCacheLoaded(prefs);
      final ids = (prefs.getStringList(prefsKey) ?? const <String>[]).toSet();
      if (add) {
        ids.add('$tid');
        final id = int.tryParse(
            RegExp(r'favid=(\d+)').firstMatch(response)?.group(1) ?? '');
        if (id != null && id > 0) _threadFavidCache[tid] = id;
      } else {
        ids.remove('$tid');
        _threadFavidCache.remove(tid);
      }
      await prefs.setStringList(prefsKey, ids.toList());
      await _persistThreadFavidCache(prefs, expectedSession: session);
      clearQuickCache('home.php?mod=space');
      return (
        success: true,
        message:
            DiscuzResponse.message(response) ?? (add ? '已收藏该帖子' : '已取消收藏该帖子')
      );
    } catch (error) {
      return (success: false, message: '收藏同步失败：$error');
    } finally {
      _busyThreadFavorites.remove(busyKey);
    }
  }

  /// 获取用户收藏标签列表
  static Future<List<String>> getFavoriteTags() async {
    try {
      final html =
          await _get('home.php?mod=space&do=favorite&type=thread&mobile=no');
      final tags = <String>[];
      final matches = RegExp(
              r'home\.php\?mod=space&amp;do=favorite&amp;type=thread&amp;tag=([^"&]+)')
          .allMatches(html);
      for (final m in matches) {
        final t = Uri.decodeComponent(m.group(1) ?? '').trim();
        if (t.isNotEmpty && !tags.contains(t)) {
          tags.add(t);
        }
      }
      return tags;
    } catch (_) {
      return const [];
    }
  }

  /// 收藏版块：先读取当前站点表单，只在服务器确认后更新该账号缓存。
  static Future<({bool success, String message})> favoriteForum(int fid,
          {String? description}) =>
      _changeForumFavorite(fid, true, description: description);

  static Future<({bool success, String message})> unfavoriteForum(int fid,
          {int? favid}) =>
      _changeForumFavorite(fid, false, favid: favid);

  static final Set<int> _busyForumFavorites = {};

  static Future<({bool success, String message})> _changeForumFavorite(
      int fid, bool add,
      {String? description, int? favid}) async {
    if (!DioClient.isLoggedIn || fid <= 0) {
      return (success: false, message: '请先登录论坛账号');
    }
    if (!_busyForumFavorites.add(fid)) {
      return (success: false, message: '正在同步收藏，请稍候');
    }
    try {
      final session = DioClient.sessionKey;
      final uid = await getMyUid();
      final prefsKey = favoriteForumsPrefsKey;
      if (uid == null || prefsKey == null || session != DioClient.sessionKey) {
        return (success: false, message: '账号已改变，请重新加载');
      }
      final query = add ? '' : '&op=delete';
      final page = await _get(
        'home.php?mod=spacecp&ac=favorite&type=forum&id=$fid$query&inajax=1&mobile=no',
        forceRefresh: true,
        cacheTtl: Duration.zero,
        expectedSession: session,
      );
      final submit = add ? 'favoritesubmit' : 'deletesubmit';
      final form = DiscuzForm.namedSubmit(page, submit);
      var response = page;
      final already = add && DiscuzFavorites.isAlreadySaved(page);
      if (!already) {
        if (form == null) {
          return (
            success: false,
            message: DiscuzResponse.message(page) ?? '网站未提供收藏操作表单'
          );
        }
        final data = {...form.values};
        if (add && form.editableNames.contains('description')) {
          data['description'] = description ?? '';
        }
        final action = Uri.parse(AppConfig.baseUrl).resolve(form.action);
        if (action.origin != Uri.parse(AppConfig.baseUrl).origin ||
            action.queryParameters['ac'] != 'favorite' ||
            session != DioClient.sessionKey) {
          return (success: false, message: '收藏表单或账号已改变，请刷新重试');
        }
        response = await _post(action.toString(), data,
            invalidateCache: false, expectedSession: session);
      }
      final ok = already || DiscuzResponse.isSuccess(response);
      if (!ok) {
        return (
          success: false,
          message: DiscuzResponse.message(response) ?? '网站未确认收藏操作，请重试'
        );
      }
      if (session != DioClient.sessionKey) {
        return (success: false, message: '账号已切换，请刷新确认操作结果');
      }
      final prefs = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey) {
        return (success: false, message: '账号已切换，请刷新确认操作结果');
      }
      final ids = (prefs.getStringList(prefsKey) ?? const <String>[]).toSet();
      if (add) {
        ids.add('$fid');
      } else {
        ids.remove('$fid');
        _forumFavidCache.remove(fid);
      }
      await prefs.setStringList(prefsKey, ids.toList());
      if (session != DioClient.sessionKey) {
        return (success: false, message: '账号已切换，请刷新确认操作结果');
      }
      clearQuickCache('home.php?mod=space');
      PreloadService.instance.remove('favorite_forums_$uid');
      final groups = PreloadService.instance
          .get<List<ForumGroup>>('forum_groups', ignoreExpired: true);
      if (groups != null) {
        PreloadService.instance.set(
            'forum_groups', _injectFavoriteForums(groups, prefs),
            ttl: const Duration(hours: 24));
      }
      ForumFavoriteNotifier.instance.notifyFavoriteChanged(fid, add);
      return (
        success: true,
        message:
            DiscuzResponse.message(response) ?? (add ? '已收藏该版块' : '已取消收藏该版块')
      );
    } catch (e) {
      return (success: false, message: '收藏同步失败：$e');
    } finally {
      _busyForumFavorites.remove(fid);
    }
  }

  /// 内存中缓存的版块 FID -> FAV_ID 映射
  static final Map<int, int> _forumFavidCache = {};

  /// 内存中缓存的帖子 TID -> FAV_ID 映射
  static final Map<int, int> _threadFavidCache = {};

  /// 检查特定 TID 是否有缓存的 favid 或在收藏中
  static bool isThreadFavidCached(int tid) {
    return _threadFavidCache.containsKey(tid);
  }

  /// 获取缓存的 favid
  static int? getCachedFavid(int tid) {
    return _threadFavidCache[tid];
  }

  /// 确保从本地持久化中加载 TID -> FAV_ID 映射
  static void _ensureFavidCacheLoaded(SharedPreferences prefs) {
    if (_threadFavidCache.isNotEmpty) return;
    try {
      final mapStr = prefs.getString(_diskKey('fav_favid_map'));
      if (mapStr != null && mapStr.isNotEmpty) {
        final decoded = jsonDecode(mapStr) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final t = int.tryParse(entry.key);
          final f = entry.value is int
              ? entry.value as int
              : int.tryParse(entry.value.toString());
          if (t != null && f != null && t > 0 && f > 0) {
            _threadFavidCache[t] = f;
          }
        }
      }
    } catch (_) {}
  }

  /// 持久化 TID -> FAV_ID 映射
  static Future<void> _persistThreadFavidCache(SharedPreferences prefs,
      {String? expectedSession}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    if (session != DioClient.sessionKey) return;
    final key = 'fav_favid_map.$session';
    try {
      final map = <String, int>{};
      for (final e in _threadFavidCache.entries) {
        map['${e.key}'] = e.value;
      }
      await prefs.setString(key, jsonEncode(map));
    } catch (_) {}
  }

  /// 缓存单个帖子的 favid 并持久化
  static Future<void> cacheThreadFavid(int tid, int favid) async {
    if (tid <= 0 || favid <= 0) return;
    final session = DioClient.sessionKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey) return;
      _threadFavidCache[tid] = favid;
      await _persistThreadFavidCache(prefs, expectedSession: session);
    } catch (_) {}
  }

  /// 净化旧版本残留的脏收藏与点赞缓存（一次性迁移修复）
  static Future<void> sanitizeFavoriteCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final session = DioClient.sessionKey;
      if (prefs.getString('favorites_session') != session) {
        for (final key in [
          'fav_forums',
          'fav_tids',
          'liked_tids',
          'liked_pids'
        ]) {
          await prefs.remove(key);
        }
        if (session != DioClient.sessionKey) return;
        await prefs.setString('favorites_session', session);
      }
      final hasSanitized =
          prefs.getBool('fav_and_like_cache_sanitized_v5') ?? false;
      if (!hasSanitized) {
        await prefs.remove('fav_tids');
        await prefs.remove('liked_tids');
        _threadFavidCache.clear();
        await prefs.remove(_diskKey('fav_favid_map'));
        await prefs.setBool('fav_and_like_cache_sanitized_v5', true);
        if (DioClient.isLoggedIn) {
          unawaited(syncFavorites());
        }
      }
    } catch (_) {}
  }

  static final Map<String, Future<void>> _threadFavoriteLoads = {};

  /// 读取实际分页；任何一页失败时保留已确认缓存，避免部分列表覆盖全部收藏。
  static Future<void> syncFavorites({int? uid}) async {
    if (!DioClient.isLoggedIn) return;
    final session = DioClient.sessionKey;
    final myUid = await getMyUid();
    if (myUid == null ||
        uid != null && uid != myUid ||
        session != DioClient.sessionKey) {
      return;
    }
    final loadKey = '$session:$myUid';
    final existing = _threadFavoriteLoads[loadKey];
    if (existing != null) return existing;
    final future = _syncThreadFavorites(myUid, session);
    _threadFavoriteLoads[loadKey] = future;
    try {
      await future;
    } catch (error) {
      debugPrint('收藏同步未完成，保留已确认缓存：$error');
    } finally {
      if (identical(_threadFavoriteLoads[loadKey], future)) {
        _threadFavoriteLoads.remove(loadKey);
      }
    }
  }

  static Future<void> _syncThreadFavorites(int uid, String session) async {
    final key = favoriteThreadsPrefsKey;
    if (key == null || session != DioClient.sessionKey) return;
    final ids = <String>{};
    final favids = <int, int>{};
    final visited = <int>{};
    var page = 1;
    while (true) {
      if (!visited.add(page) || visited.length > 200) {
        throw StateError('收藏分页异常，请在论坛网页查看');
      }
      final source = await _get(
        'home.php?mod=space&uid=$uid&do=favorite&type=thread&mobile=no&page=$page',
        forceRefresh: true,
      );
      if (!DiscuzFavorites.recognizesThreads(source)) {
        throw StateError(DiscuzResponse.message(source) ?? '收藏分页未返回列表');
      }
      final list = ComiisParser.parseUserThreads(source);
      for (final thread in list) {
        ids.add(thread.tid.toString());
        final favid = thread.favid ??
            ComiisParser.extractFavidFromHtml(source, thread.tid);
        if (favid != null && favid > 0) favids[thread.tid] = favid;
      }
      final next = DiscuzFavorites.nextPage(source, 'thread');
      if (next == null) break;
      if (next <= page) throw StateError('收藏分页没有前进');
      page = next;
    }
    final prefs = await SharedPreferences.getInstance();
    if (session != DioClient.sessionKey) return;
    _threadFavidCache
      ..clear()
      ..addAll(favids);
    await prefs.setStringList(key, ids.toList());
    await _persistThreadFavidCache(prefs, expectedSession: session);
  }

  /// 未知响应保持未知；不能把网络错误或权限页面当作未收藏。
  static Future<bool?> checkThreadFavorited(int tid) async {
    if (tid <= 0 || !DioClient.isLoggedIn) return false;
    final session = DioClient.sessionKey;
    await getMyUid();
    final key = favoriteThreadsPrefsKey;
    if (key == null || session != DioClient.sessionKey) return null;
    final response = await _get(
      'home.php?mod=spacecp&ac=favorite&type=thread&id=$tid&inajax=1&mobile=no',
      cacheTtl: Duration.zero,
      forceRefresh: true,
    );
    final saved = DiscuzFavorites.isAlreadySaved(response);
    final form = DiscuzForm.namedSubmit(response, 'favoritesubmit');
    if (!saved && form == null) return null;
    final prefs = await SharedPreferences.getInstance();
    if (session != DioClient.sessionKey) return null;
    final ids = (prefs.getStringList(key) ?? const <String>[]).toSet();
    if (saved) {
      ids.add('$tid');
    } else {
      ids.remove('$tid');
      _threadFavidCache.remove(tid);
    }
    await prefs.setStringList(key, ids.toList());
    await _persistThreadFavidCache(prefs, expectedSession: session);
    return saved;
  }

  /// 清空收藏主键缓存
  static void clearFavoriteCaches() {
    _forumFavidCache.clear();
    _threadFavidCache.clear();
  }

  /// 自己的收藏板块：读取全部实际分页，空列表同样覆盖本地；不合并历史记录。
  static Future<List<Forum>> getFavoriteForums(int uid,
      {bool forceRefresh = false}) async {
    if (!DioClient.isLoggedIn) return const [];
    final session = DioClient.sessionKey;
    final myUid = await getMyUid();
    if (myUid != uid || session != DioClient.sessionKey) {
      throw StateError('收藏账号已改变，请重新打开');
    }
    final prefsKey = favoriteForumsPrefsKey!;
    final cacheKey = 'favorite_forums_$uid';
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<List<Forum>>(cacheKey);
      if (cached != null) return cached;
    }
    final requestKey = '$uid:$session';
    final pending = _forumFavoriteLoads[requestKey];
    if (pending != null) return pending;
    final future = () async {
      final all = <int, Forum>{};
      var page = 1;
      final visited = <int>{};
      while (visited.add(page) && visited.length <= 200) {
        DiscuzForumFavoritesPage? parsed;
        String lastResponse = '';
        for (final template in const ['2', 'no']) {
          final response = await _get(
            'home.php?mod=space&uid=$uid&do=favorite&view=me&type=forum&page=$page&mobile=$template',
            forceRefresh: forceRefresh,
          );
          if (session != DioClient.sessionKey) throw StateError('账号已切换');
          lastResponse = response;
          final candidate = DiscuzFavorites.parseForums(response);
          if (candidate.recognized) {
            parsed = candidate;
            break;
          }
        }
        if (parsed == null) {
          throw FormatException(
              DiscuzResponse.message(lastResponse) ?? '未识别到站点收藏列表，请重试');
        }
        for (final forum in parsed.forums) {
          all[forum.fid] = forum;
        }
        if (parsed.nextPage == null) break;
        if (visited.contains(parsed.nextPage)) {
          throw const FormatException('收藏分页循环，请重试');
        }
        page = parsed.nextPage!;
      }
      if (visited.length > 200) throw const FormatException('收藏分页未完整读取，请重试');
      if (session != DioClient.sessionKey) throw StateError('账号已切换');
      final forums = all.values.toList();
      final prefs = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey) throw StateError('账号已切换');
      _forumFavidCache.clear();
      for (final forum in forums) {
        if (forum.favid != null && forum.favid! > 0) {
          _forumFavidCache[forum.fid] = forum.favid!;
        }
      }
      await prefs.setStringList(prefsKey, all.keys.map((id) => '$id').toList());
      PreloadService.instance
          .set(cacheKey, forums, ttl: const Duration(seconds: 30));
      ForumFavoriteNotifier.instance.replace(all.keys.toSet());
      return forums;
    }();
    _forumFavoriteLoads[requestKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_forumFavoriteLoads[requestKey], future)) {
        _forumFavoriteLoads.remove(requestKey);
      }
    }
  }

  static final Map<String, Future<List<Forum>>> _forumFavoriteLoads = {};

  // ---------------------------------------------------------------------
  // 写操作（仅本地测试环境可用）
  // ---------------------------------------------------------------------

  /// 提取登录页面的 SecCode / FormHash 信息
  static Future<
      ({
        String formhash,
        String loginhash,
        String seccodehash,
        String seccodemodid,
        bool hasSecCode,
      })> getSecCodeInfo() async {
    final page = await _get(
      'member.php?mod=logging&action=login&mobile=no',
      forceRefresh: true,
      cacheTtl: Duration.zero,
    );
    final info = ComiisParser.parseSecCodeInfo(page);
    return (
      formhash: info.formhash,
      loginhash: info.loginhash,
      seccodehash: info.seccodehash,
      seccodemodid: info.seccodemodid,
      hasSecCode: info.hasSecCode,
    );
  }

  /// 提取注册页面的 SecCode / FormHash 信息
  static Future<({String formhash, String seccodehash, String seccodemodid})>
      getRegisterSecCodeInfo() async {
    final page = await _get(
      'member.php?mod=register&mobile=2',
      forceRefresh: true,
      cacheTtl: Duration.zero,
    );
    final info = ComiisParser.parseSecCodeInfo(page);
    return (
      formhash: info.formhash,
      seccodehash: info.seccodehash.isNotEmpty ? info.seccodehash : 'cS0',
      seccodemodid: info.seccodemodid,
    );
  }

  /// 构造验证码图片绝对 URL（供 UI 直接显示）
  static String getSecCodeImageUrl(String seccodehash) {
    final sHash = seccodehash.isNotEmpty ? seccodehash : 'cS0';
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${AppConfig.baseUrl}misc.php?mod=seccode&update=$ts&idhash=$sHash';
  }

  /// 获取验证码二进制图片数据
  ///
  /// 深度适配 Discuz 原生验证码协议：
  /// 1. 先通过 `action=update&idhash=xxx` 通知 Discuz 服务端在 Session 中生成验证码及专用更新随机码（update token）；
  /// 2. 从返回的脚本中精准提取 Discuz 服务端分配的带 token 的图片路径（如 `misc.php?mod=seccode&update=61269&idhash=cS0`）；
  /// 3. 带上同源 Referer 请求图片字节流，确保客户端获取的图片与 Discuz 服务端待核对的 Session 验证码 100% 一致。
  static Future<Uint8List?> getSecCodeImageBytes(
    String seccodehash, {
    String seccodemodid = '',
    String referer = '',
  }) async {
    try {
      final sHash = seccodehash.isNotEmpty ? seccodehash : 'cS0';
      final ref = referer.isNotEmpty
          ? referer
          : '${AppConfig.baseUrl}member.php?mod=logging&action=login';

      // 1) 触发服务端生成验证码会话（action=update）
      final updUrl = 'misc.php?mod=seccode&action=update&idhash=$sHash'
          '${seccodemodid.isNotEmpty ? '&modid=$seccodemodid' : ''}';
      final updRes = await _dio.get<String>(
        updUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Referer': ref},
        ),
      );
      final body = updRes.data ?? '';

      // 2) 从响应中提取 Discuz 分配的真实图片链接与 update 随机码
      final srcMatch = RegExp(
        r'''src=["\x27]([^"\x27]*misc\.php\?mod=seccode[^"\x27]*)["\x27]''',
      ).firstMatch(body);
      String imgUrl;
      if (srcMatch != null) {
        imgUrl = srcMatch.group(1)!.replaceAll('&amp;', '&');
      } else {
        final updateMatch = RegExp(r'''update=(\d+)''').firstMatch(body);
        final token = updateMatch != null
            ? updateMatch.group(1)!
            : '${DateTime.now().millisecondsSinceEpoch}';
        imgUrl = 'misc.php?mod=seccode&update=$token&idhash=$sHash';
      }

      // 3) 请求真实二进制验证码图片数据
      final res = await _dio.get<List<int>>(
        imgUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Referer': ref,
            'Accept':
                'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
          },
        ),
      );
      if (res.data != null && res.data!.isNotEmpty) {
        return Uint8List.fromList(res.data!);
      }
    } catch (_) {}
    return null;
  }

  /// 登录（支持带 Discuz 验证码 SecCode、安全提问、自动登录提交；mobile=no 强制 PC 模板）
  static Future<({bool success, String message, bool needsSecCode})> login(
    String username,
    String password, {
    String? seccodeverify,
    String? seccodehash,
    String? seccodemodid,
    String? formhash,
    String? loginhash,
    int questionid = 0,
    String answer = '',
    bool cookietime = true,
  }) async {
    var fHash = formhash;
    var lHash = loginhash;
    var sHash = seccodehash;
    var sModid = seccodemodid;

    if (fHash == null || lHash == null) {
      final info = await getSecCodeInfo();
      fHash ??= info.formhash;
      lHash ??= info.loginhash;
      sHash ??= info.seccodehash;
      sModid ??= info.seccodemodid;
    }

    if (fHash.isEmpty) {
      return (
        success: false,
        message: '获取论坛表单凭证（formhash）失败，请检查网络',
        needsSecCode: false
      );
    }

    if (lHash.isEmpty && DioClient.isLoggedIn) {
      return (
        success: false,
        message: '当前账号仍已登录，请先退出后再登录其他账号',
        needsSecCode: false,
      );
    }
    final loginParam = lHash.isNotEmpty ? '&loginhash=$lHash' : '';
    final postUrl =
        'member.php?mod=logging&action=login&loginsubmit=yes$loginParam&inajax=1';

    final data = <String, dynamic>{
      'formhash': fHash,
      'referer': '${AppConfig.baseUrl}./',
      'loginfield': 'username',
      'fastloginfield': 'username',
      'username': username,
      'password': password,
      'questionid': '$questionid',
      'answer': answer,
      'cookietime': cookietime ? '2592000' : '0',
      'quickforward': 'yes',
      'handlekey': 'ls',
    };

    // 只有在明确提供了验证码时才附加提交验证码参数，防止无验证码时误触发服务端校验失败
    if (seccodeverify != null && seccodeverify.isNotEmpty) {
      data['seccodehash'] = (sHash != null && sHash.isNotEmpty) ? sHash : 'cS0';
      data['seccodeverify'] = seccodeverify;
      if (sModid != null && sModid.isNotEmpty) {
        data['seccodemodid'] = sModid;
      }
    }

    final html = await _post(postUrl, data);

    final needsCaptcha = html.contains('seccode_invalid') ||
        html.contains('验证码填写错误') ||
        html.contains('updateseccode(') ||
        html.contains('seccode');

    if (html.contains('login_strike')) {
      return (
        success: false,
        message: '密码错误次数过多，请 15 分钟后再试',
        needsSecCode: true
      );
    }
    if (html.contains('seccode_invalid') || html.contains('验证码填写错误')) {
      return (
        success: false,
        message: '验证码输入错误或已过期，请重新输入图形验证码',
        needsSecCode: true
      );
    }
    if (html.contains('password_error') || html.contains('密码错误')) {
      return (
        success: false,
        message: '登录失败：账号或密码错误',
        needsSecCode: needsCaptcha
      );
    }

    // 登录表单必须返回明确成功响应，旧账号残留的 auth 不能证明本次登录成功。
    final isSucceed = html.contains('location_login_succeed') ||
        html.contains('欢迎您回来') ||
        html.contains('succeedhandle_') ||
        html.contains('login_succeed');

    if (isSucceed) {
      await DioClient.saveCookies();
      // 登录成功立即清空所有旧的内存预加载缓存，确保后续各页面绝对拉取最新实时数据
      PreloadService.instance.clear();
      final status = await checkLoginStatus(forceRefresh: true);
      if (!status.isLoggedIn || status.uid == null) {
        return (success: false, message: '论坛尚未确认登录状态，请重试', needsSecCode: false);
      }
      final displayName = status.username ?? username;
      return (
        success: true,
        message: '欢迎您回来，$displayName',
        needsSecCode: false
      );
    }

    if (html.contains('alert_error')) {
      final m1 = RegExp(
        r'<div class="jump_c">[\s\S]*?<p>([^<]+)</p>',
      ).firstMatch(html);
      final m2 = RegExp(r'alert_error[^>]*>([^<]+)<').firstMatch(html);
      final msg = m1?.group(1)?.trim() ?? m2?.group(1)?.trim() ?? '登录失败，请核对信息';
      return (success: false, message: msg, needsSecCode: needsCaptcha);
    }

    return (
      success: false,
      message: '登录未能识别成功响应，请重试',
      needsSecCode: needsCaptcha
    );
  }

  /// 手动导入 Cookie 字符串（支持直接粘贴 Cookie 快速完成登录认证）
  static bool importCookies(String rawCookies) {
    if (rawCookies.trim().isEmpty) return false;
    final parts = rawCookies.split(';');
    for (final part in parts) {
      final p = part.trim();
      final idx = p.indexOf('=');
      if (idx > 0) {
        final k = p.substring(0, idx).trim();
        final v = p.substring(idx + 1).trim();
        if (k.isNotEmpty && v.isNotEmpty) {
          DioClient.setCookie(k, v);
        }
      }
    }
    DioClient.saveCookies();
    checkLoginStatus();
    return DioClient.isLoggedIn;
  }

  /// 发帖前获取发帖页凭证与版块允许的特殊主题类型（普通=0/投票=1/辩论=5 等）、分类信息发帖模板及未使用附件。
  static Future<
      ({
        String formhash,
        Set<int> allowedSpecials,
        List<({int value, String name})> typeOptions,
        ThreadSortInfo? threadSortInfo,
        List<PostAttachmentItem> unusedAttachments,
        String errorMessage,
        PostEditorAttributes editorAttributes,
      })> getNewThreadInfo(int fid, {int? sortid, bool? asMobile}) async {
    final sortParam = (sortid != null && sortid > 0) ? '&sortid=$sortid' : '';
    final html = await _get(
      asMobile == true
          ? 'forum.php?mod=post&action=newthread&fid=$fid$sortParam&mobile=2'
          : 'forum.php?mod=post&action=newthread&fid=$fid$sortParam&mobile=no',
      headers: {
        'Referer': '${AppConfig.baseUrl}forum.php?mod=forumdisplay&fid=$fid',
        if (asMobile == true) 'User-Agent': AppConfig.mobileUserAgent,
        if (asMobile == false) 'User-Agent': AppConfig.pcUserAgent,
      },
    );
    final info = ComiisParser.parseNewThreadInfo(html);
    if (info.formhash.isEmpty && info.errorMessage.isEmpty) {
      return (
        formhash: '',
        allowedSpecials: info.allowedSpecials,
        typeOptions: info.typeOptions,
        threadSortInfo: info.threadSortInfo,
        unusedAttachments: info.unusedAttachments,
        errorMessage: '无法获取发帖凭证，请检查登录状态或版块权限',
        editorAttributes: info.editorAttributes,
      );
    }
    return info;
  }

  /// 获取指定版块特定模板的分类信息配置（threadsorts / sortid）
  static Future<ThreadSortInfo?> getThreadSortInfo(int fid, int sortid,
      {bool? asMobile}) async {
    try {
      final html = await _get(
        'forum.php?mod=post&action=newthread&fid=$fid&sortid=$sortid&mobile=no',
        headers: {
          'Referer':
              '${AppConfig.baseUrl}forum.php?mod=post&action=newthread&fid=$fid',
          'User-Agent': AppConfig.pcUserAgent,
        },
      );
      return ComiisParser.parseThreadSortInfo(html);
    } catch (_) {
      return null;
    }
  }

  /// 删除未使用的附件（Discuz 标准 ajax deleteattach 接口）
  static Future<bool> deleteUnusedAttachments(
    List<int> aids, {
    required String formhash,
    int? tid,
    int? pid,
  }) async {
    if (aids.isEmpty || formhash.isEmpty) return false;
    try {
      final aidsQuery = aids.map((a) => 'aids[]=$a').join('&');
      final path =
          'forum.php?mod=ajax&action=deleteattach&inajax=yes&formhash=$formhash&tid=${tid ?? 0}&pid=${pid ?? 0}&$aidsQuery';
      final res = await _get(path);
      final cdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(res);
      final count = int.tryParse(
          html_parser.parse(cdata?.group(1) ?? res).body?.text.trim() ?? '');
      return count == aids.toSet().length;
    } catch (e) {
      return false;
    }
  }

  /// 发帖（支持投票、辩论、分类信息模板、附件关联与高级选项，完全对齐 Discuz Web 端）
  /// 发帖。成功返回新帖 tid，失败返回 null
  static Future<int?> postThread(
    int fid,
    String subject,
    String message, {
    int? typeid,
    int? sortid,
    Map<String, dynamic>? typeoptions,
    int special = 0,
    List<String>? pollOptions,
    int? pollDays,
    int? pollMaxChoices,
    bool? pollVisibility,
    bool? pollOvert,
    String? affirmPoint,
    String? negaPoint,
    String? endTime,
    String? umpire,
    List<int>? attachAids,
    int? readPerm,
    int? rewardCredit,
    int? rewardTimes,
    List<String>? tags,
    bool isAnonymous = false,
    bool hiddenReplies = false,
    bool orderType = false,
    bool allowNoticeAuthor = true,
    bool useSig = true,
    bool htmlOn = false,
    bool parseUrlOff = false,
    bool smileyOff = false,
    bool bbcodeOff = false,
    bool replyEmailNotice = false,
    int? stickTopic,
    int? addDigest,
    bool? closed,
    bool? asMobile,
  }) async {
    if (!DioClient.isLoggedIn) return null;
    final session = DioClient.sessionKey;
    String? formhash;
    final sortQuery = (sortid != null && sortid > 0) ? '&sortid=$sortid' : '';
    try {
      final page = await _get(
        asMobile == true
            ? 'forum.php?mod=post&action=newthread&fid=$fid$sortQuery&mobile=2'
            : 'forum.php?mod=post&action=newthread&fid=$fid$sortQuery&mobile=no',
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=forumdisplay&fid=$fid',
          if (asMobile == true) 'User-Agent': AppConfig.mobileUserAgent,
          if (asMobile == false) 'User-Agent': AppConfig.pcUserAgent,
        },
      );
      final info = ComiisParser.parseNewThreadInfo(page);
      if (info.errorMessage.isNotEmpty) throw StateError(info.errorMessage);
      if (!info.allowedSpecials.contains(special)) {
        throw StateError('当前版块或用户组未开放此主题类型');
      }
      formhash = info.formhash;
    } on DioException {
      return null;
    }

    if (formhash.isEmpty || session != DioClient.sessionKey) return null;

    final data = <String, dynamic>{
      'formhash': formhash,
      'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'wysiwyg': '0',
      'usesig': useSig ? '1' : '0',
      'allownoticeauthor': allowNoticeAuthor ? '1' : '0',
      'topicsubmit': 'yes',
      'subject': subject,
      'message': message,
      'handlekey': 'newthread',
      if (special != 0) 'special': '$special',
      if (isAnonymous) 'isanonymous': '1',
      if (hiddenReplies) 'hiddenreplies': '1',
      if (orderType) 'ordertype': '1',
      if (htmlOn) 'htmlon': '1',
      if (parseUrlOff) 'parseurloff': '1',
      if (smileyOff) 'smileyoff': '1',
      if (bbcodeOff) 'bbcodeoff': '1',
      if (replyEmailNotice) 'emailnotify': '1',
      if (stickTopic != null && stickTopic > 0) 'sticktopic': '$stickTopic',
      if (addDigest != null && addDigest > 0) 'adddigest': '$addDigest',
      if (closed == true) 'closed': '1',
    };
    if (typeid != null) data['typeid'] = '$typeid';
    if (sortid != null && sortid > 0) {
      data['sortid'] = '$sortid';
      data['selectsortid'] = '$sortid';
      if (typeoptions != null && typeoptions.isNotEmpty) {
        for (final entry in typeoptions.entries) {
          final val = entry.value;
          if (val is List) {
            data['typeoption[${entry.key}][]'] = val.map((e) => '$e').toList();
          } else if (val != null && '$val'.isNotEmpty) {
            data['typeoption[${entry.key}]'] = '$val';
          }
        }
      }
    }

    // 自动关联上传的附件到新主题
    final aids = <int>{
      ...?attachAids,
      for (final m in RegExp(r'\[attach(?:img)?\](\d+)\[/attach(?:img)?\]')
          .allMatches(message))
        if (int.tryParse(m.group(1)!) != null) int.parse(m.group(1)!),
    };
    for (final aid in aids) {
      data['attachnew[$aid][description]'] = '';
    }
    if (aids.isNotEmpty) {
      data['unused[]'] = aids.map((a) => '$a').toList();
    }

    // 附加高级选项支持：阅读权限、回帖奖励、主题标签
    if (readPerm != null && readPerm > 0) {
      data['readperm'] = '$readPerm';
    }
    if (rewardCredit != null && rewardCredit > 0) {
      data['rewardprice'] = '$rewardCredit';
      if (rewardTimes != null && rewardTimes > 0) {
        data['rewardtimes'] = '$rewardTimes';
      }
    }
    if (tags != null && tags.isNotEmpty) {
      data['tags'] = tags.join(',');
    }
    // 投票帖（Discuz 3.4 官方字段）
    if (special == 1 && pollOptions != null && pollOptions.isNotEmpty) {
      data['polls'] = '${pollOptions.length}';
      data['polloptions[]'] = pollOptions; // Discuz 3.4 standard array!
      data['polloption[]'] = pollOptions; // 兼容不同模板
      data['visibilitypoll'] = pollVisibility == true ? '1' : '0';
      if (pollOvert == true) data['overt'] = '1';
      if (pollDays != null && pollDays > 0) {
        data['expiration'] = '$pollDays';
      }
      if (pollMaxChoices != null && pollMaxChoices > 0) {
        data['maxchoices'] = '$pollMaxChoices';
      }
    }
    // 辩论帖（special=5）
    if (special == 5) {
      if (affirmPoint != null && affirmPoint.isNotEmpty) {
        data['affirmpoint'] = affirmPoint;
      }
      if (negaPoint != null && negaPoint.isNotEmpty) {
        data['negapoint'] = negaPoint;
      }
      if (endTime != null && endTime.isNotEmpty) {
        data['endtime'] = endTime;
      }
      if (umpire != null && umpire.isNotEmpty) {
        data['umpire'] = umpire;
      }
    }
    final specialParam = special != 0 ? '&special=$special' : '';
    final postUrl = asMobile == true
        ? 'forum.php?mod=post&action=newthread&fid=$fid&extra=&topicsubmit=yes$specialParam&mobile=2'
        : 'forum.php?mod=post&action=newthread&fid=$fid&extra=&topicsubmit=yes$specialParam&mobile=no';
    Uri? submittedUri;
    final html = await _post(
      postUrl,
      data,
      expectedSession: session,
      onResponseUri: (uri) => submittedUri = uri,
      headers: {
        'Referer':
            '${AppConfig.baseUrl}forum.php?mod=post&action=newthread&fid=$fid',
        if (asMobile == true) 'User-Agent': AppConfig.mobileUserAgent,
        if (asMobile == false) 'User-Agent': AppConfig.pcUserAgent,
      },
    );
    if (session != DioClient.sessionKey) {
      throw StateError('账号已切换，请核对发帖结果');
    }
    if (html.contains('alert_error') || html.contains('抱歉，您尚未登录')) return null;
    final redirectTid = submittedUri?.queryParameters['mod'] == 'viewthread'
        ? int.tryParse(submittedUri?.queryParameters['tid'] ?? '')
        : int.tryParse(RegExp(r'/thread-(\d+)-')
                .firstMatch(submittedUri?.path ?? '')
                ?.group(1) ??
            '');
    if (redirectTid != null && redirectTid > 0) return redirectTid;
    if (!DiscuzResponse.isSuccess(html)) return null;
    _clearCache();
    // 新帖 tid：成功跳转 viewthread 页
    for (final m in RegExp(r'''viewthread&tid=(\d+)''').allMatches(html)) {
      final tid = int.tryParse(m.group(1) ?? '');
      if (tid != null) return tid;
    }
    for (final m in RegExp(r'''thread-(\d+)-''').allMatches(html)) {
      final tid = int.tryParse(m.group(1) ?? '');
      if (tid != null) return tid;
    }
    return -1; // 成功但无法确认 tid
  }

  /// 获取 Discuz 回复页信息（formhash、权限提示与未使用附件列表）
  static Future<
      ({
        String formhash,
        String? errorMessage,
        List<PostAttachmentItem> unusedAttachments,
        PostEditorAttributes editorAttributes,
      })> getReplyInfo(
    int tid, {
    int? fid,
    int? repquote,
    int? reppost,
    bool? asMobile,
  }) async {
    try {
      final fidPart = (fid != null && fid > 0) ? '&fid=$fid' : '';
      final repquotePart =
          (repquote != null && repquote > 0) ? '&repquote=$repquote' : '';
      final reppostPart =
          (reppost != null && reppost > 0) ? '&reppost=$reppost' : '';
      final html = await _get(
        'forum.php?mod=post&action=reply&tid=$tid$fidPart$repquotePart$reppostPart&extra=page%3D1&page=1&mobile=${asMobile == true ? '2' : 'no'}',
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
          if (asMobile == true) 'User-Agent': AppConfig.mobileUserAgent,
          if (asMobile == false) 'User-Agent': AppConfig.pcUserAgent,
        },
      );
      final info = ComiisParser.parseNewThreadInfo(html);
      if (info.formhash.isNotEmpty) {
        _cachedFormhash = info.formhash;
      }
      return (
        formhash: info.formhash,
        errorMessage: info.errorMessage.isNotEmpty ? info.errorMessage : null,
        unusedAttachments: info.unusedAttachments,
        editorAttributes: info.editorAttributes,
      );
    } catch (e) {
      return (
        formhash: '',
        errorMessage: '无法读取回复表单：$e',
        unusedAttachments: <PostAttachmentItem>[],
        editorAttributes: const PostEditorAttributes(),
      );
    }
  }

  /// 回复（支持楼层回复、引用、点评与附件关联）
  static Future<bool> replyThread(
    int tid,
    String message, {
    int? pid,
    int? reppost,
    int? repquote,
    String? noticeauthor,
    String? noticetrimstr,
    List<int>? attachAids,
    bool asComment = false,
    bool? asMobile,
    bool? isAnonymous,
    bool? hiddenReplies,
    bool? allowNoticeAuthor,
    bool? useSig,
    bool? htmlOn,
    bool? parseUrlOff,
    bool? smileyOff,
    bool? bbcodeOff,
    bool? replyEmailNotice,
    int? fid,
    String? noticeauthormsg,
    int? repposition,
  }) async {
    if (!DioClient.isLoggedIn) return false;
    final session = DioClient.sessionKey;
    String? formhash;
    try {
      final page = await _get(
        asMobile == true
            ? 'forum.php?mod=post&action=reply&tid=$tid&extra=&mobile=2'
            : 'forum.php?mod=post&action=reply&tid=$tid&extra=&mobile=no',
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
          if (asMobile == true) 'User-Agent': AppConfig.mobileUserAgent,
          if (asMobile == false) 'User-Agent': AppConfig.pcUserAgent,
        },
      );
      final info = ComiisParser.parseNewThreadInfo(page);
      if (info.errorMessage.isNotEmpty) throw StateError(info.errorMessage);
      formhash = info.formhash;
    } on DioException {
      return false;
    }

    if (formhash.isEmpty || session != DioClient.sessionKey) return false;
    // 楼中楼（点评）：回复时带 comment 参数 + pid 定位楼层
    // 注意：commentsubmit 的 submitcheck 要求 formhash 在 GET
    final fidParam = (fid != null && fid > 0) ? '&fid=$fid' : '';
    final url =
        '${asComment && pid != null ? 'forum.php?mod=post&action=reply&tid=$tid$fidParam&extra=&replysubmit=yes&comment=$pid&formhash=$formhash${asMobile == true ? '&mobile=2' : ''}' : (reppost != null ? 'forum.php?mod=post&action=reply&tid=$tid$fidParam&reppost=$reppost&extra=&replysubmit=yes${asMobile == true ? '&mobile=2' : ''}' : (repquote != null ? 'forum.php?mod=post&action=reply&tid=$tid$fidParam&repquote=$repquote&extra=&replysubmit=yes${asMobile == true ? '&mobile=2' : ''}' : 'forum.php?mod=post&action=reply&tid=$tid$fidParam&extra=&replysubmit=yes${asMobile == true ? '&mobile=2' : ''}'))}${asMobile == true ? '' : '&mobile=no'}';
    final replyData = <String, dynamic>{
      'formhash': formhash,
      'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'wysiwyg': '0',
      'usesig': (useSig ?? true) ? '1' : '0',
      'handlekey': 'fastpost',
      'replysubmit': 'yes',
      'message': message,
      if (fid != null && fid > 0) 'fid': '$fid',
      if (asComment && pid != null) 'comment': '$pid',
      if (reppost != null) 'reppost': '$reppost',
      if (repquote != null) 'repquote': '$repquote',
      if (repposition != null && repposition > 0) 'repposition': '$repposition',
      if (noticeauthor != null && noticeauthor.isNotEmpty)
        'noticeauthor': noticeauthor,
      if (noticeauthormsg != null && noticeauthormsg.isNotEmpty)
        'noticeauthormsg': noticeauthormsg,
      if (noticetrimstr != null && noticetrimstr.isNotEmpty)
        'noticetrimstr': noticetrimstr,
      if (isAnonymous == true) 'isanonymous': '1',
      if (hiddenReplies == true) 'hiddenreplies': '1',
      if (allowNoticeAuthor != null)
        'allownoticeauthor': allowNoticeAuthor ? '1' : '0',
      if (replyEmailNotice == true) 'emailnotice': '1',
      if (htmlOn == true) 'htmlon': '1',
      if (parseUrlOff == true) 'parseurloff': '1',
      if (smileyOff == true) 'smileyoff': '1',
      if (bbcodeOff == true) 'bbcodeoff': '1',
    };

    final aids = <int>{
      ...?attachAids,
      for (final m in RegExp(r'\[attach(?:img)?\](\d+)\[/attach(?:img)?\]')
          .allMatches(message))
        if (int.tryParse(m.group(1)!) != null) int.parse(m.group(1)!),
    };
    for (final aid in aids) {
      replyData['attachnew[$aid][description]'] = '';
    }
    if (aids.isNotEmpty) {
      replyData['unused[]'] = aids.map((aid) => '$aid').toList();
    }

    Uri? replyResponseUri;
    final html = await _post(
      url,
      replyData,
      expectedSession: session,
      onResponseUri: (uri) => replyResponseUri = uri,
      headers: {
        'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        if (asMobile == true) 'User-Agent': AppConfig.mobileUserAgent,
        if (asMobile == false) 'User-Agent': AppConfig.pcUserAgent,
      },
    );
    if (session != DioClient.sessionKey) {
      throw StateError('账号已切换，请核对回复结果');
    }
    final returnedTid = replyResponseUri?.queryParameters['mod'] == 'viewthread'
        ? int.tryParse(replyResponseUri?.queryParameters['tid'] ?? '')
        : int.tryParse(RegExp(r'/thread-(\d+)-')
                .firstMatch(replyResponseUri?.path ?? '')
                ?.group(1) ??
            '');
    final ok = returnedTid == tid || DiscuzResponse.isSuccess(html);
    if (ok) {
      _clearCache(tid);
    }
    return ok;
  }

  /// 楼中楼回复（klpbbs replyfloor 插件：plugin.php?id=replyfloor）
  /// 返回 true 表示提交成功（本地无该插件时可能返回 false）
  static Future<bool> postFloorReply(
    int tid,
    int pid,
    String message, {
    int msgid = 0,
  }) async {
    var formhash = _cachedFormhash;
    try {
      final page = await _get(
        'plugin.php?id=replyfloor:index&tid=$tid&mobile=no',
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );
      formhash = _extractFormhash(page) ?? formhash;
    } catch (_) {}

    if (formhash == null || formhash.isEmpty) {
      // 回退标准 Discuz 点评/楼层回复
      return replyThread(tid, message, pid: pid, asComment: true);
    }
    final html = await _post(
      'plugin.php?id=replyfloor:index&ac=post&tid=$tid',
      {
        'formhash': formhash,
        'savesubmit': 'true',
        'pid': '$pid',
        'msgid': '$msgid',
        'handlekey': 'messagepost',
        'message': message,
      },
      headers: {
        'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
      },
    );
    if (html.contains('alert_error') || html.contains('插件不存在')) {
      return replyThread(tid, message, pid: pid, asComment: true);
    }
    _clearCache(tid);
    return true;
  }

  /// 校验当前会话登录状态并提取用户 UID、用户名及最新 FormHash
  static Future<
          ({bool isLoggedIn, int? uid, String? username, String? formhash})>
      checkLoginStatus({bool forceRefresh = false}) async {
    try {
      final html = await _get(
        'home.php?mod=spacecp&mobile=no',
        forceRefresh: forceRefresh,
        cacheTtl: forceRefresh ? Duration.zero : const Duration(seconds: 15),
      );
      final formhash = _extractFormhash(html) ?? _cachedFormhash;
      final session = DiscuzSessionParser.parse(html);
      final uid = session.uid;
      final username = session.username;
      final loggedIn = uid != null && DioClient.isLoggedIn;
      if (uid != null && uid > 0) {
        if (_cachedMyUid != null && _cachedMyUid != uid) {
          clearSignLocalCache();
          try {
            PushNotificationService.instance.clearUnread();
          } catch (_) {}
          AutoSignService.instance.onAccountSwitched();
        }
        _cachedMyUid = uid;
      }
      return (
        isLoggedIn: loggedIn,
        uid: uid,
        username: username,
        formhash: formhash,
      );
    } catch (_) {
      return (
        isLoggedIn: DioClient.isLoggedIn,
        uid: null,
        username: null,
        formhash: _cachedFormhash,
      );
    }
  }

  /// 提取 Discuz AJAX XML/HTML 弹窗返回的文本消息（支持 CDATA、alert_info/error、showmessage 等）
  static String _extractDiscuzResponseMessage(
    String html, {
    String defaultMsg = '操作完成',
  }) {
    // 1. CDATA in XML: <root><![CDATA[...]]></root>
    final cdataM = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(html);
    final raw = cdataM != null ? cdataM.group(1)! : html;

    // 2. 优先通过 ComiisParser.parseMessage 进行 DOM 节点提取
    final comiisMsg = ComiisParser.parseMessage(raw);
    if (comiisMsg != null && comiisMsg.isNotEmpty) {
      return comiisMsg;
    }

    // 3. DOM 解析 alert_info / alert_error / messagetext / alert_correct / tip / jump_c / altw
    try {
      final doc = html_parser.parse(raw);
      final alertEl = doc.querySelector(
        '#messagetext, .alert_right, .alert_error, .alert_info, .alert_correct, .comiis_tip, .jump_c, .tip, p.message, .altw',
      );
      if (alertEl != null) {
        final p = alertEl.querySelector('p') ?? alertEl;
        final t = p.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isNotEmpty) return t;
      }
    } catch (_) {}

    // 4. 匹配 popup.open('...', ...) 或 showmessage('...', ...)
    final popM = RegExp(
      r"(?:popup\.open|showmessage|showError|showPrompt)\s*\(\s*['\x22]([^'\x22]+)['\x22]",
    ).firstMatch(raw);
    if (popM != null) {
      final text = popM.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (text.isNotEmpty) return text;
    }

    // 5. 清理 HTML 标签后若文本简短直接作为消息返回
    final stripped = raw.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    if (stripped.isNotEmpty && stripped.length < 80) {
      return stripped;
    }
    return defaultMsg;
  }

  /// 帖子主题推荐/点赞与取消点赞（严格对接 Discuz 原生与克米移动端）
  static Future<({bool success, String message, bool isLiked})> recommendThread(
    int tid, {
    bool support = true,
    int? pid,
  }) =>
      _changeReaction(tid, support: support);

  /// 首楼属于主题推荐；网页 comiis_recommend(pid) 用于回帖投票。
  /// 每次只提交对应接口，不在推荐成功后再追加另一种投票。
  static Future<({bool success, String message, bool isLiked})> likeFloor(
    int tid,
    int pid, {
    bool isFirstFloor = false,
    bool support = true,
  }) {
    if (isFirstFloor) return _changeReaction(tid, support: support);
    if (pid <= 0) {
      return Future.value(
          (success: false, message: '楼层信息缺失，请刷新后再试', isLiked: !support));
    }
    return _changeReaction(tid, pid: pid, support: support);
  }

  static Future<({bool success, String message, bool isLiked})> _changeReaction(
      int tid,
      {int? pid,
      required bool support}) async {
    final session = DioClient.sessionKey;
    if (!DioClient.isLoggedIn) {
      return (success: false, message: '请先登录论坛账号后再进行点赞', isLiked: !support);
    }
    try {
      final page = await _get('forum.php?mod=viewthread&tid=$tid&mobile=no',
          headers: {'User-Agent': AppConfig.pcUserAgent}, forceRefresh: true);
      final formhash = _extractFormhash(page);
      if (session != DioClient.sessionKey) {
        return (success: false, message: '账号已切换，请重新操作', isLiked: !support);
      }
      if (formhash == null || formhash.isEmpty) {
        return (
          success: false,
          message: DiscuzResponse.message(page) ?? '未能获取点赞凭证，请刷新后再试',
          isLiked: !support
        );
      }
      final String endpoint;
      if (support) {
        endpoint = pid == null
            ? 'forum.php?mod=misc&action=recommend&do=add&tid=$tid&hash=$formhash&inajax=1&mobile=2'
            : 'forum.php?mod=misc&action=postreview&do=support&tid=$tid&pid=$pid&hash=$formhash&inajax=1&mobile=2';
      } else {
        endpoint = pid == null
            ? 'plugin.php?id=comiis_app&comiis=re_recommend&tid=$tid&inajax=1&mobile=2'
            : 'plugin.php?id=comiis_app&comiis=re_hotreply&tid=$tid&pid=$pid&inajax=1&mobile=2';
      }
      final response = await _get(endpoint, forceRefresh: true, headers: {
        'X-Requested-With': 'XMLHttpRequest',
        'Referer':
            '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid&mobile=2',
      });
      if (session != DioClient.sessionKey) {
        return (success: false, message: '账号已切换，请重新操作', isLiked: !support);
      }
      final result = DiscuzReactionResponse.parse(response,
          support: support, floor: pid != null);
      if (result.success) _clearCache(tid);
      return result;
    } catch (error) {
      // 取消失败直接返回，不继续发送添加请求，也不更改其他点赞记录。
      return (success: false, message: '点赞操作失败：$error', isLiked: !support);
    }
  }

  /// 获取论坛帖子 AI 总结（对接 klpbbs_aisum 插件）
  static Future<AiSummaryData?> fetchAiSummary(
    int tid, {
    String? streamUrl,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'ai_summary_$tid';
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<AiSummaryData>(cacheKey);
      if (cached != null) return cached;
    }

    try {
      String url = streamUrl ?? 'plugin.php?id=klpbbs_aisum:stream&tid=$tid';
      if (!url.contains('mode=json')) {
        url += url.contains('?') ? '&mode=json' : '?mode=json';
      }
      if (_cachedFormhash != null &&
          _cachedFormhash!.isNotEmpty &&
          !url.contains('formhash=')) {
        url += '&formhash=$_cachedFormhash';
      }

      final resp = await DioClient.dio.get(url);
      dynamic data = resp.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }
      if (data is Map<String, dynamic>) {
        final aiData = AiSummaryData.fromJson(data, streamUrl: url);
        if (aiData.hasContent) {
          PreloadService.instance.set(cacheKey, aiData);
          return aiData;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 打赏楼层（Discuz 评分 rating；klpbbs 铁粒=credit id 2 → score2）
  /// 返回 (success: bool, message: String)
  static Future<({bool success, String message})> ratePost(
    int tid,
    int pid,
    int score, {
    String reason = '',
  }) async {
    if (!DioClient.isLoggedIn) {
      return (success: false, message: '请先登录论坛账号后再进行打赏评分');
    }
    try {
      var formhash = _cachedFormhash;
      if (formhash == null || formhash.isEmpty) {
        final page = await _get(
          'forum.php?mod=misc&action=rate&tid=$tid&pid=$pid&inajax=1',
        );
        formhash = _extractFormhash(page);
      }
      if (formhash == null || formhash.isEmpty) {
        return (success: false, message: '未能获取评分凭证，请重试');
      }
      final data = <String, String>{
        'formhash': formhash,
        'ratesubmit': 'yes',
        'handlekey': 'rate',
        'tid': '$tid',
        'pid': '$pid',
        'score2': '$score', // 铁粒（klpbbs 评分表单 score2=铁粒，score8=钻石）
        'reason': reason,
      };
      final html = await _post(
        'forum.php?mod=misc&action=rate&tid=$tid&pid=$pid&ratesubmit=yes&inajax=1',
        data,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );
      if (html.contains('thread_rate_duplicate') ||
          html.contains('24 小时内不能再次评分')) {
        return (success: false, message: '24 小时内不能对同一楼层重复评分');
      }
      if (html.contains('抱歉，您尚未登录') || html.contains('请先登录')) {
        return (success: false, message: '登录状态已失效，请重新登录');
      }
      final serverMsg = _extractDiscuzResponseMessage(
        html,
        defaultMsg: '已成功打赏 $score 铁粒！',
      );
      final isSuccess =
          DiscuzResponse.isSuccess(html, acceptedMessages: ['感谢']);
      if (isSuccess) {
        _clearCache(tid);
        PreloadService.instance.clear('user_space_');
      }
      return (success: isSuccess, message: serverMsg);
    } catch (e) {
      return (success: false, message: '打赏请求异常：$e');
    }
  }

  /// 勋章中心（home.php?mod=medal）
  static Future<List<MedalItem>> getMedals({bool forceRefresh = false}) async {
    const cacheKey = 'medals_all';
    if (!forceRefresh) {
      final cached = PreloadService.instance.get<List<MedalItem>>(cacheKey);
      if (cached != null) return cached;
    }

    final session = DioClient.sessionKey;
    final pages = await Future.wait(['no', '2'].map((mobile) async {
      try {
        final source = await _get('home.php?mod=medal&mobile=$mobile',
            forceRefresh: forceRefresh, expectedSession: session);
        _rejectRestrictedPage(source);
        if (!DiscuzMedals.recognized(source)) {
          throw StateError(DiscuzResponse.message(source) ?? '勋章页面无法识别');
        }
        return (medals: ComiisParser.parseMedals(source), error: null);
      } catch (error) {
        return (medals: <MedalItem>[], error: error);
      }
    }));
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新加载勋章');
    if (pages.every((page) => page.error != null)) {
      throw StateError('勋章读取失败：${pages.first.error}');
    }
    final res = DiscuzMedals.merge(pages[0].medals, pages[1].medals);
    PreloadService.instance.set(cacheKey, res, ttl: const Duration(minutes: 5));
    return res;
  }

  /// 获取当前登录用户的勋章列表（真实数据）
  static Future<List<({int id, String name, String desc, String img})>>
      getMyMedalsList({bool forceRefresh = false}) async {
    final session = DioClient.sessionKey;
    if (!DioClient.isLoggedIn) return const [];
    final uid = await getMyUid();
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新加载勋章');
    if (uid == null) throw StateError('未能识别当前账号，请重新加载');
    final indexUri = Uri.parse(_url('home.php?mod=medal&mobile=no'));
    final indexSource = await _get(indexUri.toString(),
        forceRefresh: forceRefresh, expectedSession: session);
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新加载勋章');
    _rejectRestrictedPage(indexSource);
    if (!DiscuzMedals.recognized(indexSource)) {
      throw StateError(DiscuzResponse.message(indexSource) ?? '勋章页面无法识别，请重试');
    }
    final index = html_parser.parse(indexSource);
    Uri? declaredLink(String label) {
      final link = index
          .querySelectorAll('a[href]')
          .where((element) => element.text.trim() == label)
          .firstOrNull;
      if (link == null) return null;
      final uri = indexUri.resolve(link.attributes['href']!);
      return DiscuzRequestPolicy.sameOrigin(indexUri, uri) ? uri : null;
    }

    final ownedUri = declaredLink('我的勋章');
    final orderUri = declaredLink('勋章排序');
    if (ownedUri == null) {
      throw StateError('网站未提供我的勋章入口，请刷新后重试');
    }
    final ownedSource = await _get(ownedUri.toString(),
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: forceRefresh,
        expectedSession: session);
    _rejectRestrictedPage(ownedSource);
    if (!DiscuzMedals.recognized(ownedSource)) {
      throw StateError(DiscuzResponse.message(ownedSource) ?? '我的勋章页面无法识别，请重试');
    }
    final owned = DiscuzMedals.parse(ownedSource, ownedUri);
    KlpbbsMedalOrder? order;
    if (orderUri != null) {
      try {
        final source = await _get(orderUri.toString(),
            headers: {'User-Agent': AppConfig.pcUserAgent},
            forceRefresh: forceRefresh,
            expectedSession: session);
        final parsed = KlpbbsMedalOrder.parse(source, orderUri);
        if (parsed.recognized) order = parsed;
      } catch (_) {
        if (session != DioClient.sessionKey) rethrow;
      }
    }
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新加载勋章');
    // 本次已读取目录，不再为补充名称/ID 重复请求 PC 与手机目录。
    // 缓存仅补充当前会话的目录元数据；持有条目来自上面的实际持有页。
    final catalog = DiscuzMedals.merge(
        DiscuzMedals.parse(indexSource, indexUri),
        PreloadService.instance
                .get<List<MedalItem>>('medals_all', ignoreExpired: true) ??
            const []);
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新加载勋章');
    // 本人空间仍用于同步余额；其失败不把已读到的持有列表变成空数据。
    await getUserSpace(uid, forceRefresh: forceRefresh);
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新加载勋章');
    final entries = owned.map((owned) {
      final matching = catalog
          .where((item) =>
              (owned.id > 0 && item.id == owned.id) ||
              owned.img.isNotEmpty &&
                  item.img.isNotEmpty &&
                  Uri.tryParse(item.img)?.path ==
                      Uri.tryParse(owned.img)?.path ||
              owned.name.isNotEmpty && item.name == owned.name)
          .firstOrNull;
      return (
        id: owned.id > 0 ? owned.id : matching?.id ?? 0,
        name: owned.name.isNotEmpty ? owned.name : matching?.name ?? '',
        desc: owned.desc.isNotEmpty ? owned.desc : matching?.desc ?? '',
        img: owned.img
      );
    }).toList();
    if (order != null && order.serverIds.length == entries.length) {
      final ordered = <({int id, String name, String desc, String img})>[];
      final matched = <int>{};
      for (final medal in order.medals) {
        final index = entries.indexWhere((entry) =>
            entry.id > 0 && entry.id == medal.id ||
            medal.img.isNotEmpty &&
                entry.img.isNotEmpty &&
                Uri.tryParse(entry.img)?.path ==
                    Uri.tryParse(medal.img)?.path ||
            medal.name.isNotEmpty && entry.name == medal.name);
        if (index < 0 || !matched.add(index)) break;
        final entry = entries[index];
        ordered.add(
            (id: medal.id, name: entry.name, desc: entry.desc, img: entry.img));
      }
      if (ordered.length == entries.length) {
        PreloadService.instance.set('my_medals', ordered);
        return ordered;
      }
    }
    PreloadService.instance.set('my_medals', entries);
    return entries;
  }

  /// 系统奖励使用当前页面提供的筛选地址；有效空列表不回退为另一分类。
  static Future<List<CreditLogEntry>> getCreditLogs({
    int page = 1,
    String subop = '',
    bool forceRefresh = false,
  }) async {
    if (!const {'', 'income', 'reward', 'creditrulelog'}.contains(subop)) {
      throw ArgumentError.value(subop, 'subop', '网站未提供该流水分类');
    }
    final session = DioClient.sessionKey;
    Object? lastError;
    for (final mobile in ['no', '2']) {
      try {
        final base = Uri.parse(_url(
            'home.php?mod=spacecp&ac=credit&op=log&mobile=$mobile&page=$page'));
        var source = await _get(base.toString(),
            forceRefresh: forceRefresh, cacheTtl: const Duration(seconds: 15));
        if (subop == 'reward' || subop == 'creditrulelog') {
          final reward = DiscuzCreditLogProtocol.rewardPage(source, base);
          if (reward == null) {
            throw StateError(DiscuzResponse.message(source) ?? '网站未提供系统奖励记录入口');
          }
          final target = reward.replace(queryParameters: {
            ...reward.queryParameters,
            'mobile': mobile,
            'page': '$page',
          });
          source = await _get(target.toString(),
              forceRefresh: forceRefresh,
              cacheTtl: const Duration(seconds: 15));
        }
        if (session != DioClient.sessionKey) {
          throw StateError('账号已切换，请重新加载积分记录');
        }
        if (!DiscuzCreditLogProtocol.recognized(source)) {
          throw StateError(DiscuzResponse.message(source) ?? '网站未返回可识别的积分记录');
        }
        final logs = ComiisParser.parseCreditLogs(source);
        PreloadService.instance.set('credit_logs_${subop}_$page', logs,
            ttl: const Duration(seconds: 15));
        return logs;
      } catch (error) {
        if (session != DioClient.sessionKey) rethrow;
        lastError = error;
      }
    }
    throw StateError('积分记录读取失败：$lastError');
  }

  /// 当前账号的积分明细；未返回的指标不推算为零。
  static Future<CreditBaseInfo?> getCreditBase(
      {bool forceRefresh = false}) async {
    if (!DioClient.isLoggedIn) return null;
    final session = DioClient.sessionKey;
    for (final path in const [
      'home.php?mod=spacecp&ac=credit&mobile=2',
      'home.php?mod=spacecp&ac=credit&op=base&mobile=2',
      'home.php?mod=spacecp&ac=credit&mobile=no',
    ]) {
      try {
        final source = await _get(path, forceRefresh: forceRefresh);
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新积分');
        _rejectRestrictedPage(source);
        final info = ComiisParser.parseCreditBase(source);
        if (info.details.isNotEmpty || info.totalCredits.isNotEmpty) {
          return info;
        }
      } catch (_) {
        if (session != DioClient.sessionKey) rethrow;
      }
    }
    try {
      final uid = await getMyUid();
      if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新积分');
      if (uid != null && uid > 0) {
        final space = await getUserSpace(uid, forceRefresh: forceRefresh);
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新积分');
        if (space != null) {
          return CreditBaseInfo(
              totalCredits: space.credits,
              details: Map<String, String>.from(space.creditsDetail),
              ruleFormula: '');
        }
      }
    } catch (_) {
      if (session != DioClient.sessionKey) rethrow;
    }
    return null;
  }

  /// 提取今日签到在积分记录中的实际奖励数额
  static Future<({int amount, String timeText})?> getTodaySignReward() async {
    try {
      final logs = await getCreditLogs(page: 1);
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      for (final log in logs) {
        if (log.operation.contains('签到') || log.detail.contains('签到')) {
          if (log.timeText.contains(todayStr) ||
              log.timeText.contains('今天') ||
              log.timeText.contains('分钟前') ||
              log.timeText.contains('小时前') ||
              log.timeText.contains('刚刚')) {
            final val = log.numericValue;
            if (val > 0) {
              return (amount: val, timeText: log.timeText);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 积分转账（home.php?mod=spacecp&ac=credit&op=transfer）
  static Future<({bool success, String message})> transferCredits({
    required String toUser,
    required int amount,
    required String password,
    String memo = '',
  }) async {
    if (!DioClient.isLoggedIn) return (success: false, message: '请先登录');
    if (amount <= 0 || toUser.trim().isEmpty || password.isEmpty) {
      return (success: false, message: '请填写收款人、正整数金额和支付密码');
    }
    final session = DioClient.sessionKey;
    try {
      final page = await _get(
        'home.php?mod=spacecp&ac=credit&op=transfer&mobile=no',
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: true,
      );
      final form = DiscuzForm.namedSubmit(page, 'transfersubmit');
      if (form == null) {
        return (
          success: false,
          message: DiscuzResponse.message(page) ?? '当前账号无法取得转账表单'
        );
      }
      final base = Uri.parse(AppConfig.baseUrl);
      final target = base.resolve(form.action.isEmpty
          ? 'home.php?mod=spacecp&ac=credit&op=transfer'
          : form.action);
      if (target.origin != base.origin || session != DioClient.sessionKey) {
        return (success: false, message: '账号或转账表单已变化，请重新打开页面');
      }
      final resHtml = await _post(
        target.replace(queryParameters: {
          ...target.queryParameters,
          'mobile': 'no'
        }).toString(),
        {
          ...form.values,
          'to': toUser.trim(),
          'transferamount': '$amount',
          'password': password,
          'transfermessage': memo,
          'transfersubmit': 'true',
        },
        headers: {
          'User-Agent': AppConfig.pcUserAgent,
          'Referer':
              '${AppConfig.baseUrl}home.php?mod=spacecp&ac=credit&op=transfer',
        },
      );

      final success = DiscuzResponse.isSuccess(resHtml);
      if (success) {
        PreloadService.instance.clear('user_space_');
        PreloadService.instance.clear('credit_');
        clearQuickCache('home.php?mod=spacecp&ac=credit');
      }
      return (
        success: success,
        message: DiscuzResponse.message(resHtml) ??
            (success ? '转账成功' : '网站未确认转账结果，请查看积分记录后再操作')
      );
    } catch (e) {
      return (success: false, message: '转账异常：$e');
    }
  }

  static void _rejectRestrictedPage(String source) {
    if (html_parser
            .parse(source)
            .querySelector('#messagetext, .comiis_password_top') !=
        null) {
      final message = DiscuzResponse.message(source);
      if (message?.isNotEmpty == true) throw StateError(message!);
    }
  }

  static Future<({List<MagicItem> magics, MagicBagInfo bag})>
      _getMagicCollection(String action,
          {int page = 1, bool forceRefresh = false}) async {
    if (!DioClient.isLoggedIn) throw StateError('请先登录后查看道具');
    if (page < 1) throw ArgumentError('道具页码无效');
    final session = DioClient.sessionKey;
    final cacheKey = 'magic_collection_${action}_$page';
    if (!forceRefresh) {
      final cached = PreloadService.instance
          .get<({List<MagicItem> magics, MagicBagInfo bag})>(cacheKey);
      if (cached != null) return cached;
    }
    Object? lastError;
    for (final template in ['no', '2']) {
      try {
        final source = await _get(
            'home.php?mod=magic&action=$action&page=$page&mobile=$template',
            forceRefresh: forceRefresh,
            headers: {
              'User-Agent': template == 'no'
                  ? AppConfig.pcUserAgent
                  : AppConfig.mobileUserAgent
            },
            expectedSession: session);
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新道具');
        _rejectRestrictedPage(source);
        if (!DiscuzMagicProtocol.recognizes(source, action)) continue;
        final list = action == 'shop'
            ? DiscuzMagicProtocol.shop(source,
                base: Uri.parse(AppConfig.baseUrl))
            : DiscuzMagicProtocol.mybox(source,
                base: Uri.parse(AppConfig.baseUrl));
        var bag = DiscuzMagicProtocol.bag(source);
        if (bag.ironCount < 0) {
          final credit = await getCreditBase();
          if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新道具');
          final balance =
              DiscuzMagicProtocol.balanceValue(credit?.details['铁粒']);
          if (balance != null) bag = bag.copyWith(ironCount: balance);
        }
        final result = (magics: list, bag: bag);
        PreloadService.instance.set(
            'magic_collection_next_${action}_$page',
            DiscuzMagicProtocol.nextPage(
                    source, action, page, Uri.parse(AppConfig.baseUrl)) ??
                -1);
        PreloadService.instance.set(cacheKey, result);
        return result;
      } catch (error) {
        if (session != DioClient.sessionKey) rethrow;
        lastError = error;
      }
    }
    throw StateError(
        '道具页面读取失败，请打开完整道具中心查看：${lastError?.toString() ?? '当前模板未提供可识别的列表'}');
  }

  static Future<({List<MagicItem> magics, MagicBagInfo bag})> getMagicShop(
          {int page = 1, bool forceRefresh = false}) =>
      _getMagicCollection('shop', page: page, forceRefresh: forceRefresh);

  static Future<({List<MagicItem> magics, MagicBagInfo bag})> getMyMagics(
          {int page = 1, bool forceRefresh = false}) =>
      _getMagicCollection('mybox', page: page, forceRefresh: forceRefresh);

  static int? magicCollectionNextPage(String action, int page) {
    final next = PreloadService.instance
        .get<int>('magic_collection_next_${action}_$page', ignoreExpired: true);
    return next != null && next > page ? next : null;
  }

  static Future<List<MagicLogEntry>> getMagicLogs(
      {String op = 'uselog', int page = 1, bool forceRefresh = false}) async {
    if (!DioClient.isLoggedIn) throw StateError('请先登录后查看道具记录');
    if (!DiscuzMagicProtocol.logOperations.contains(op) || page < 1) {
      throw ArgumentError('道具记录分类或页码无效');
    }
    final session = DioClient.sessionKey;
    Object? lastError;
    for (final template in ['no', '2']) {
      try {
        final source = await _get(
            'home.php?mod=magic&action=log&operation=$op&page=$page&mobile=$template',
            forceRefresh: forceRefresh,
            headers: {
              'User-Agent': template == 'no'
                  ? AppConfig.pcUserAgent
                  : AppConfig.mobileUserAgent
            },
            expectedSession: session);
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新道具记录');
        _rejectRestrictedPage(source);
        if (!DiscuzMagicProtocol.recognizes(source, 'log')) continue;
        final records = DiscuzMagicProtocol.logs(source, op: op);
        if (records.isEmpty &&
            !DiscuzMagicProtocol.hasExplicitEmptyLogs(source)) {
          continue;
        }
        PreloadService.instance.set(
            'magic_log_next_${op}_$page',
            DiscuzMagicProtocol.nextLogPage(
                    source, op, page, Uri.parse(AppConfig.baseUrl)) ??
                -1);
        return records;
      } catch (error) {
        if (session != DioClient.sessionKey) rethrow;
        lastError = error;
      }
    }
    throw StateError('道具记录读取失败：${lastError?.toString() ?? '当前模板未提供可识别的记录'}');
  }

  static int? magicLogNextPage(String op, int page) {
    final next = PreloadService.instance
        .get<int>('magic_log_next_${op}_$page', ignoreExpired: true);
    return next != null && next > page ? next : null;
  }

  static const _avatarEditorPath = 'home.php?mod=spacecp&ac=avatar&mobile=no';
  static final Set<String> _avatarRequests = {};

  static Future<DiscuzAvatarReceipt> getAvatarEditor(
      {String? expectedSession}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    final target = Uri.parse(_url(_avatarEditorPath));
    var responseUri = target;
    final source = await _get(_avatarEditorPath,
        forceRefresh: true,
        expectedSession: session,
        onResponseUri: (uri) => responseUri = uri);
    if (session != DioClient.sessionKey) throw StateError('账号已变化，请重新打开头像页面');
    if (!DiscuzRequestPolicy.sameOrigin(target, responseUri)) {
      throw StateError('头像页面已进入外部认证流程');
    }
    return DiscuzAvatarReceipt(
        DiscuzAvatarDescriptor.parse(source, responseUri),
        responseUri,
        session,
        DateTime.now());
  }

  /// Uploading is separate from generic forms: the current cropper declares
  /// a three-image byte transport, and a review hook must be retained.
  static Future<DiscuzAvatarResult> submitAvatar(
      DiscuzAvatarReceipt receipt, PreparedAvatar avatar,
      {bool allowAnimationAttempt = false}) async {
    if (receipt.session != DioClient.sessionKey) {
      return const DiscuzAvatarResult(false, '账号已变化，请重新打开头像页面');
    }
    if (!receipt.descriptor.canUpload) {
      return const DiscuzAvatarResult(false, '当前账号没有可用的头像上传表单');
    }
    if (DateTime.now().difference(receipt.loadedAt) >
        const Duration(minutes: 5)) {
      return const DiscuzAvatarResult(false, '头像页面已过期，请刷新后确认');
    }
    if (avatar.variants.length != 3 ||
        avatar.variants.any((bytes) => bytes.isEmpty) ||
        avatar.byteLength > AvatarImageProcessor.maxUploadBytes ||
        (avatar.animated && !allowAnimationAttempt)) {
      return const DiscuzAvatarResult(false, '请重新确认头像图片与动画选项');
    }
    if (!_avatarRequests.add(receipt.session)) {
      return const DiscuzAvatarResult(false, '头像正在提交，请稍候');
    }
    try {
      final fresh = await getAvatarEditor(expectedSession: receipt.session);
      if (!receipt.descriptor.sameContractAs(fresh.descriptor)) {
        return const DiscuzAvatarResult(false, '账号权限或头像审核流程已变化，请刷新后确认');
      }
      final descriptor = fresh.descriptor;
      final imageFields = await AvatarTransportEncoder.encode(avatar.variants,
          useBase64: descriptor.useBase64,
          maxSourceBytes: AvatarImageProcessor.maxUploadBytes);
      if (receipt.session != DioClient.sessionKey) {
        return const DiscuzAvatarResult(false, '账号已变化，请重新查看头像状态');
      }
      final result = DiscuzAvatarResult.parse(
          await _post(
              descriptor.declaredUpload.toString(),
              {
                'formhash': descriptor.formhash,
                'savesubmit': 'true',
                ...imageFields,
              },
              headers: {
                'Referer': fresh.pageUri.toString(),
                'User-Agent': DioClient.userAgentFor(fresh.pageUri),
              },
              expectedSession: receipt.session),
          requiresReview: descriptor.requiresReview);
      if (receipt.session != DioClient.sessionKey) {
        return const DiscuzAvatarResult(false, '账号已变化，请重新查看头像状态');
      }
      if (result.success) {
        await clearUserProfileCache();
        profileChanges.value++;
      }
      return result;
    } finally {
      _avatarRequests.remove(receipt.session);
    }
  }

  static const _phoneBindingPath =
      'home.php?mod=spacecp&ac=plugin&id=klpbbs_pnbind:my_bind&mobile=no';
  static final Map<String, DateTime> _phoneCodeSentAt = {};
  static final Set<String> _phoneRequests = {};

  static Future<PhoneBindingReceipt> getPhoneBinding(
      {String? expectedSession}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    final source = await _get(_phoneBindingPath,
        forceRefresh: true, expectedSession: session);
    if (session != DioClient.sessionKey) throw StateError('账号已变化，请重新打开手机绑定');
    return PhoneBindingReceipt(
        KlpbbsPhoneBinding.parse(source, Uri.parse(_url(_phoneBindingPath))),
        session,
        DateTime.now());
  }

  static int phoneCodeCooldown(PhoneBindingReceipt receipt) {
    final sent = _phoneCodeSentAt[receipt.session];
    if (sent == null) return 0;
    return (receipt.binding.resendSeconds -
            DateTime.now().difference(sent).inSeconds)
        .clamp(0, receipt.binding.resendSeconds);
  }

  /// Only called by the native page after an explicit send/verify button tap.
  /// Reading binding status is a GET and never sends an SMS.
  static Future<PhoneBindingResult> submitPhoneBinding(
      PhoneBindingReceipt receipt, String phone,
      {String? code}) async {
    if (receipt.session != DioClient.sessionKey) {
      return const PhoneBindingResult(false, '账号已变化，请重新打开手机绑定');
    }
    final invalid = receipt.binding.validatePhone(phone) ??
        (code == null ? null : receipt.binding.validateCode(code));
    if (invalid != null) return PhoneBindingResult(false, invalid);
    if (code == null && phoneCodeCooldown(receipt) > 0) {
      return PhoneBindingResult(
          false, '请在 ${phoneCodeCooldown(receipt)} 秒后重新获取验证码');
    }
    if (!_phoneRequests.add(receipt.session)) {
      return const PhoneBindingResult(false, '正在处理上一条手机号验证请求');
    }
    try {
      final fresh = await getPhoneBinding(expectedSession: receipt.session);
      if (!receipt.binding.sameActionsAs(fresh.binding)) {
        return const PhoneBindingResult(false, '手机号绑定状态或接口已变化，请刷新后继续');
      }
      final result = PhoneBindingResult.parse(await _post(
          (code == null ? fresh.binding.sendUri : fresh.binding.verifyUri)
              .toString(),
          {
            'phone': phone,
            if (code != null) 'code': code,
            'formhash': fresh.binding.formhash
          },
          headers: {
            'Referer': fresh.binding.pageUri.toString(),
            'User-Agent': DioClient.userAgentFor(fresh.binding.pageUri)
          },
          expectedSession: receipt.session));
      if (receipt.session != DioClient.sessionKey) {
        return const PhoneBindingResult(false, '账号已变化，请重新查看绑定状态');
      }
      if (result.success) {
        if (code == null) {
          _phoneCodeSentAt[receipt.session] = DateTime.now();
        } else {
          await clearUserProfileCache();
          profileChanges.value++;
        }
      }
      return result;
    } finally {
      _phoneRequests.remove(receipt.session);
    }
  }

  /// The developer console can contain secrets. Keep its response out of both
  /// the quick cache and shared in-flight requests; bind it to this account.
  static Future<DeveloperPlatformReceipt> getDeveloperPlatform(
      DeveloperPlatformView view,
      {String? expectedSession}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    final target = Uri.parse(_url(KlpbbsDeveloperPlatform.pathFor(view)));
    var responseUri = target;
    final source = await _get(target.toString(),
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: true,
        cacheTtl: Duration.zero,
        expectedSession: session,
        onResponseUri: (uri) => responseUri = uri);
    if (session != DioClient.sessionKey) {
      throw StateError('账号已变化，请重新打开开放平台');
    }
    if (!DiscuzRequestPolicy.sameOrigin(target, responseUri)) {
      throw StateError('开放平台已转入外部认证流程');
    }
    final platform =
        KlpbbsDeveloperPlatform.parse(source, responseUri, view: view);
    if (!platform.recognized &&
        !platform.requiresLogin &&
        platform.message == null) {
      throw StateError('网站暂未返回开放平台内容，请稍后刷新');
    }
    return DeveloperPlatformReceipt(platform, session, DateTime.now());
  }

  /// This private page can contain authorization identifiers. No response
  /// cache or shared in-flight request is used, even when refreshing rapidly.
  static Future<AuthorizationsReceipt> getAuthorizations(
      {String? expectedSession}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    final target = Uri.parse(_url(KlpbbsAuthorizations.path));
    var responseUri = target;
    final String source;
    try {
      source = await _get(target.toString(),
          headers: {'User-Agent': AppConfig.pcUserAgent},
          forceRefresh: true,
          cacheTtl: Duration.zero,
          expectedSession: session,
          onResponseUri: (uri) => responseUri = uri);
    } on DioException catch (error) {
      final response = error.response;
      final finalUri = response?.realUri ?? error.requestOptions.uri;
      if (session != DioClient.sessionKey) {
        throw StateError('账号已变化，请重新打开我的授权');
      }
      if (response?.statusCode != 401 ||
          !DiscuzRequestPolicy.sameOrigin(target, finalUri)) {
        rethrow;
      }
      return AuthorizationsReceipt(
          KlpbbsAuthorizations(
              uri: finalUri,
              requiresLogin: true,
              message: '登录状态已失效，请重新登录',
              nativePage: DiscuzNativePage(uri: finalUri, requiresLogin: true)),
          session,
          DateTime.now());
    }
    if (session != DioClient.sessionKey) {
      throw StateError('账号已变化，请重新打开我的授权');
    }
    if (!DiscuzRequestPolicy.sameOrigin(target, responseUri)) {
      throw StateError('网站已转入外部认证流程');
    }
    final page = KlpbbsAuthorizations.parse(source, responseUri);
    if (!page.recognized && !page.requiresLogin && page.message == null) {
      throw StateError('网站暂未返回授权数据，请稍后刷新');
    }
    return AuthorizationsReceipt(page, session, DateTime.now());
  }

  /// Only a link declared by this account's current page may be confirmed.
  /// The real populated/revoke variant is still awaiting a server sample.
  static Future<({bool success, String message})> performAuthorizationAction(
      AuthorizationsReceipt receipt, AuthorizationAction action) async {
    if (!DioClient.isLoggedIn ||
        receipt.session != DioClient.sessionKey ||
        !receipt.page.actions.contains(action)) {
      return (success: false, message: '账号或授权操作已变化，请刷新');
    }
    if (DateTime.now().difference(receipt.loadedAt) >
        const Duration(minutes: 5)) {
      return (success: false, message: '授权页面已过期，请刷新后确认');
    }
    try {
      final fresh = await getAuthorizations(expectedSession: receipt.session);
      final current = fresh.page.actions
          .where((candidate) => action.sameContractAs(candidate))
          .firstOrNull;
      if (current == null ||
          !fresh.page.recognized ||
          fresh.page.requiresLogin) {
        return (success: false, message: '授权信息或操作已变化，请刷新后确认');
      }
      var responseUri = current.uri;
      final source = await _get(current.uri.toString(),
          headers: {
            'User-Agent': AppConfig.pcUserAgent,
            'Referer': fresh.page.uri.toString()
          },
          forceRefresh: true,
          cacheTtl: Duration.zero,
          expectedSession: receipt.session,
          onResponseUri: (uri) => responseUri = uri);
      if (receipt.session != DioClient.sessionKey) {
        return (success: false, message: '账号状态已变化，请重新打开页面确认');
      }
      if (!DiscuzRequestPolicy.sameOrigin(fresh.page.uri, responseUri)) {
        return (success: false, message: '网站未确认授权操作，请刷新查看');
      }
      final success = DiscuzResponse.isSuccess(source);
      return (
        success: success,
        message: DiscuzResponse.message(source) ??
            (success ? '操作成功' : '网站未确认操作结果，请刷新查看')
      );
    } catch (_) {
      return (success: false, message: '连接未完成，网站未确认操作结果，请刷新查看');
    }
  }

  /// 表单、数据表与操作地址从当前模板读取，界面由 Flutter 构建。
  static Future<DiscuzNativePageReceipt> getNativePage(String path,
      {bool allowDataChange = false, String? expectedSession}) async {
    final base = Uri.parse(AppConfig.baseUrl);
    final target = base.resolve(path);
    if (!DiscuzRequestPolicy.sameOrigin(base, target)) {
      throw StateError('此入口不属于当前论坛');
    }
    if (!allowDataChange && DiscuzNativePage.changesData(target)) {
      throw StateError('请先确认此操作');
    }
    final session = expectedSession ?? DioClient.sessionKey;
    var responseUri = target;
    final source = await _get(target.toString(),
        forceRefresh: true,
        expectedSession: session,
        onResponseUri: (uri) => responseUri = uri);
    if (session != DioClient.sessionKey) throw StateError('账号已变化，请重新打开页面');
    if (!DiscuzRequestPolicy.sameOrigin(base, responseUri)) {
      throw StateError('网站已转入外部认证流程');
    }
    final avatarReadOnly = target.queryParameters['ac'] == 'avatar';
    final page = AppConfig.enableMultiThreadParsing && source.length > 50000
        ? await Isolate.run(() => DiscuzNativePage.parse(source, responseUri,
            avatarReadOnly: avatarReadOnly))
        : DiscuzNativePage.parse(source, responseUri,
            avatarReadOnly: avatarReadOnly);
    if (session != DioClient.sessionKey) throw StateError('账号已变化，请重新打开页面');
    return DiscuzNativePageReceipt(page, session, DateTime.now());
  }

  static Future<DiscuzNativeSubmitResult> submitNativeForm(
      DiscuzNativePageReceipt receipt,
      String formKey,
      String buttonKey,
      Map<String, List<String>> edits,
      {Map<String, List<String>> filePaths = const {}}) async {
    if (receipt.session != DioClient.sessionKey) {
      return const DiscuzNativeSubmitResult(false, '账号已变化，请重新打开表单');
    }
    if (receipt.page.avatarPage) {
      return const DiscuzNativeSubmitResult(false, '头像上传接口仍在核对审核流程，当前仅展示状态');
    }
    try {
      final base = Uri.parse(AppConfig.baseUrl);
      var form =
          receipt.page.forms.where((form) => form.key == formKey).firstOrNull;
      if (form == null || !DiscuzRequestPolicy.sameOrigin(base, form.action)) {
        return const DiscuzNativeSubmitResult(false, '当前表单已变化，请刷新');
      }
      if (DateTime.now().difference(receipt.loadedAt) >
          const Duration(minutes: 5)) {
        return const DiscuzNativeSubmitResult(false, '表单已过期，请刷新后重试');
      }
      if (form.method == 'POST' && !form.hasCsrf) {
        return const DiscuzNativeSubmitResult(false, '当前表单没有可确认的提交凭证，请刷新');
      }
      if (form.method != 'GET' && form.method != 'POST') {
        return const DiscuzNativeSubmitResult(false, '当前提交方式尚未适配');
      }
      // 验证码必须使用用户看到的同一次表单，避免刷新时把验证码换掉。
      if (form.method == 'POST' && !form.hasCaptcha) {
        final fresh = await getNativePage(receipt.page.uri.toString(),
            expectedSession: receipt.session);
        final current = fresh.page.forms
            .where((candidate) => candidate.key == formKey)
            .firstOrNull;
        if (current == null ||
            fresh.page.avatarPage ||
            !form.sameContractAs(current) ||
            !current.hasCsrf ||
            current.buttons.every((button) => button.key != buttonKey)) {
          return const DiscuzNativeSubmitResult(false, '表单内容或费用已变化，请刷新后确认');
        }
        form = current;
      }
      final pairs = form.submission(edits, buttonKey);
      final headers = <String, String>{
        'Referer': receipt.page.uri.toString(),
        'User-Agent': DioClient.userAgentFor(receipt.page.uri),
      };
      if (form.method == 'GET') {
        if (form.fields
            .any((field) => field.kind == DiscuzFieldKind.password)) {
          return const DiscuzNativeSubmitResult(false, '密码不能通过查询地址发送');
        }
        final query = {...form.action.queryParametersAll};
        final names = pairs.map((entry) => entry.key).toSet();
        for (final name in names) {
          query[name] = pairs
              .where((entry) => entry.key == name)
              .map((entry) => entry.value)
              .toList();
        }
        final page = await getNativePage(
            form.action.replace(queryParameters: query).toString(),
            expectedSession: receipt.session);
        return DiscuzNativeSubmitResult(false, '', nextPage: page);
      }
      FormData? multipart;
      if (filePaths.isNotEmpty ||
          form.enctype.toLowerCase().startsWith('multipart/form-data')) {
        multipart = FormData();
        multipart.fields.addAll(pairs);
        for (final fileEntry in filePaths.entries) {
          final field = form.fields
              .where((field) =>
                  field.name == fileEntry.key &&
                  field.kind == DiscuzFieldKind.file)
              .firstOrNull;
          if (field == null ||
              (!field.multiple && fileEntry.value.length > 1)) {
            return const DiscuzNativeSubmitResult(false, '当前表单没有提供此附件字段');
          }
          for (final path in fileEntry.value) {
            final file = File(path);
            if (!field.acceptsFileName(path)) {
              return const DiscuzNativeSubmitResult(false, '文件格式不符合当前表单要求');
            }
            if (!await file.exists()) {
              return const DiscuzNativeSubmitResult(false, '所选文件已不存在，请重新选择');
            }
            final maxBytes = int.tryParse(form.hidden('MAX_FILE_SIZE'));
            if (maxBytes != null && await file.length() > maxBytes) {
              return const DiscuzNativeSubmitResult(false, '文件超过论坛允许的大小');
            }
            multipart.files.add(
                MapEntry(fileEntry.key, await MultipartFile.fromFile(path)));
          }
        }
      }
      for (final field in form.fields.where(
          (field) => field.kind == DiscuzFieldKind.file && field.required)) {
        if (filePaths[field.name]?.isNotEmpty != true) {
          return DiscuzNativeSubmitResult(false, '请选择${field.label}');
        }
      }
      var responseUri = form.action;
      final response = await _post(form.action.toString(), {},
          encodedForm: DiscuzNativeForm.encode(pairs),
          multipart: multipart,
          headers: headers,
          expectedSession: receipt.session,
          onResponseUri: (uri) => responseUri = uri);
      final success = DiscuzResponse.isSuccess(response);
      if (receipt.session != DioClient.sessionKey) {
        final security = receipt.page.uri.queryParameters['op'] == 'password';
        return DiscuzNativeSubmitResult(security && success,
            security && success ? '安全信息已更新，请重新登录' : '账号状态已变化，请刷新确认本次操作结果');
      }
      DiscuzNativePageReceipt? nextPage;
      if (DiscuzRequestPolicy.sameOrigin(base, responseUri)) {
        final next = DiscuzNativePage.parse(response, responseUri);
        if (next.forms.isNotEmpty || next.images.isNotEmpty) {
          nextPage =
              DiscuzNativePageReceipt(next, receipt.session, DateTime.now());
        }
      }
      if (success) {
        PreloadService.instance.clear('magic_');
        PreloadService.instance.clear('credit_');
        await invalidateUserProfile(expectedSession: receipt.session);
        PreloadService.instance.clear('membership_');
      }
      return DiscuzNativeSubmitResult(
          success,
          DiscuzResponse.message(response) ??
              (success
                  ? '操作成功'
                  : nextPage != null
                      ? '请完成下面的后续步骤'
                      : '网站未确认操作结果，请刷新查看'),
          nextPage: nextPage);
    } on FormatException catch (error) {
      return DiscuzNativeSubmitResult(false, error.message);
    } catch (error) {
      return const DiscuzNativeSubmitResult(false, '连接未完成，网站未确认操作结果，请刷新查看');
    }
  }

  static Future<DiscuzNativePageReceipt> performNativePageAction(
      DiscuzNativePageReceipt receipt, DiscuzPageLink action) async {
    if (receipt.session != DioClient.sessionKey ||
        !receipt.page.links.contains(action) ||
        !action.changesData ||
        !DioClient.isLoggedIn) {
      throw StateError('账号或操作已变化，请刷新');
    }
    if (DateTime.now().difference(receipt.loadedAt) >
        const Duration(minutes: 5)) {
      throw StateError('操作已过期，请刷新后重试');
    }
    final result = await getNativePage(action.uri.toString(),
        allowDataChange: true, expectedSession: receipt.session);
    _clearCache();
    PreloadService.instance.clear();
    return result;
  }

  static Future<({bool success, String message})> _submitMagicForm(
      String path, Map<String, String> edits,
      {String submitName = 'operatesubmit'}) async {
    if (!DioClient.isLoggedIn) return (success: false, message: '请先登录');
    final session = DioClient.sessionKey;
    try {
      final page = await _get(path,
          headers: {'User-Agent': AppConfig.pcUserAgent}, forceRefresh: true);
      final form = DiscuzForm.namedSubmit(page, submitName);
      if (form == null) {
        return (
          success: false,
          message: DiscuzResponse.message(page) ?? '当前账号无法取得道具操作表单'
        );
      }
      final base = Uri.parse(AppConfig.baseUrl);
      final target = base.resolve(form.action.isEmpty ? path : form.action);
      if (target.origin != base.origin || session != DioClient.sessionKey) {
        return (success: false, message: '账号或道具表单已变化，请重新打开');
      }
      final response = await _post(
          target.replace(queryParameters: {
            ...target.queryParameters,
            'mobile': 'no',
            'inajax': '1'
          }).toString(),
          {
            ...form.values,
            ...edits,
            submitName: 'yes'
          },
          headers: {
            'User-Agent': AppConfig.pcUserAgent,
            'Referer': base.resolve(path).toString()
          });
      if (session != DioClient.sessionKey) {
        return (success: false, message: '账号已切换，请刷新道具确认原账号操作结果');
      }
      final success = DiscuzResponse.isSuccess(response);
      if (success) {
        clearQuickCache('home.php?mod=magic');
        clearQuickCache('home.php?mod=spacecp&ac=credit');
        PreloadService.instance.clear('credit_');
        PreloadService.instance.clear('magic_');
        PreloadService.instance.clear('user_space_');
      }
      return (
        success: success,
        message: DiscuzResponse.message(response) ??
            (success ? '操作成功' : '网站未确认操作结果，请刷新道具包查看')
      );
    } catch (error) {
      return (success: false, message: '网站未确认操作结果：$error');
    }
  }

  /// shop 使用 identifier；mybox 由实际表单签发 magicid。
  static Future<({bool success, String message})> buyMagic(
      dynamic magicIdOrIdentifier,
      {int count = 1}) async {
    if (count <= 0) return (success: false, message: '购买数量必须为正整数');
    var identifier = magicIdOrIdentifier.toString();
    final numeric = int.tryParse(identifier);
    if (numeric != null) {
      final item = (await getMagicShop())
          .magics
          .where((item) => item.id == numeric)
          .firstOrNull;
      if (item == null || item.identifier.isEmpty) {
        return (success: false, message: '无法确认道具标识，请刷新商店');
      }
      identifier = item.identifier;
    }
    final path = Uri(path: 'home.php', queryParameters: {
      'mod': 'magic',
      'action': 'shop',
      'operation': 'buy',
      'mid': identifier,
      'inajax': '1',
      'mobile': 'no'
    }).toString();
    return _submitMagicForm(path, {'magicnum': '$count'});
  }

  static Future<({bool success, String message})> giveMagic(
    dynamic magicIdOrIdentifier, {
    required String username,
    int count = 1,
    String message = '',
  }) async {
    if (username.trim().isEmpty || count <= 0) {
      return (success: false, message: '请填写收件人和正整数数量');
    }
    final id = magicIdOrIdentifier.toString();
    final path = Uri(path: 'home.php', queryParameters: {
      'mod': 'magic',
      'action': 'mybox',
      'operation': 'give',
      int.tryParse(id) == null ? 'mid' : 'magicid': id,
      'inajax': '1',
      'mobile': 'no'
    }).toString();
    return _submitMagicForm(path, {
      'magicnum': '$count',
      'tousername': username.trim(),
      'givemessage': message
    });
  }

  static Future<({bool success, String message})> useMagic(
    int magicId, {
    int? tid,
    int? pid,
    int? bid,
    String? targetUsername,
    String? newUsername,
    int count = 1,
  }) async {
    if (magicId <= 0 || count <= 0) {
      return (success: false, message: '道具或使用数量无效');
    }
    final path =
        'home.php?mod=magic&action=mybox&operation=use&magicid=$magicId&inajax=1&mobile=no';
    return _submitMagicForm(
        path,
        {
          'magicid': '$magicId',
          'magicnum': '$count',
          if (tid != null) 'tid': '$tid',
          if (pid != null) 'pid': '$pid',
          if (bid != null) 'bid': '$bid',
          if (targetUsername?.isNotEmpty == true) 'tousername': targetUsername!,
          if (newUsername?.isNotEmpty == true) 'newusername': newUsername!,
        },
        submitName: 'usesubmit');
  }

  static Future<({bool success, String message})> useRetroSignCard(
      {required int bid, int? magicId}) async {
    if (!DioClient.isLoggedIn) return (success: false, message: '请先登录');
    var id = magicId;
    if (id == null || id <= 0) {
      final box = await getMyMagics(forceRefresh: true);
      id = box.magics
          .where((item) =>
              item.identifier.contains('bq') || item.name.contains('补签'))
          .firstOrNull
          ?.id;
    }
    if (id == null || id <= 0) return (success: false, message: '道具包中没有可用的补签卡');
    final result = await _submitMagicForm(
        'home.php?mod=magic&action=mybox&operation=use&magicid=$id&bid=$bid&inajax=1&mobile=no',
        {'magicid': '$id', 'bid': '$bid'},
        submitName: 'usesubmit');
    if (result.success) await clearSignLocalCache();
    return result;
  }

  static Future<({bool success, String message})> dropMagic(int magicId,
      {int count = 1}) async {
    if (magicId <= 0 || count <= 0) {
      return (success: false, message: '道具或回收数量无效');
    }
    return _submitMagicForm(
        'home.php?mod=magic&action=mybox&operation=sell&magicid=$magicId&inajax=1&mobile=no',
        {'magicid': '$magicId', 'magicnum': '$count'});
  }

  /// 兼容旧版道具接口
  static Future<List<({int id, String name, String img, String desc})>>
      getMagics() async {
    final shop = await getMagicShop();
    return shop.magics
        .map((m) => (id: m.id, name: m.name, img: m.img, desc: m.desc))
        .toList();
  }

  /// 楼中楼回复（replyfloor 插件；仅本地测试环境，真实论坛只读拦截）
  static Future<bool> postReplyFloor({
    required int tid,
    required int pid,
    required String message,
    int msgid = 0,
  }) async {
    if (!AppConfig.allowWrite) return false;
    // 从帖子详情页取 formhash（replyfloor 表单模板内）
    final html = await _get('forum.php?mod=viewthread&tid=$tid&mobile=2');
    final formhash = _extractFormhash(html);
    if (formhash == null) return false;
    final response =
        await _post('plugin.php?id=replyfloor:index&ac=post&tid=$tid', {
      'formhash': formhash,
      'savesubmit': 'true',
      'pid': '$pid',
      'msgid': '$msgid',
      'handlekey': 'messagepost',
      'message': message,
    });
    return DiscuzResponse.isSuccess(response);
  }

  /// 使用道具（mgc_post_{pid} 菜单；仅本地测试环境，真实论坛只读拦截）
  ///
  /// 先取道具使用页 formhash，再 POST usesubmit 提交。
  static Future<bool> useMagicOnPost({
    required String mid,
    required String idtype,
    required String id,
  }) async {
    if (!AppConfig.allowWrite) return false;
    final page = await _get(
      'home.php?mod=magic&mid=$mid&idtype=$idtype&id=$id&mobile=no',
      headers: {'User-Agent': AppConfig.pcUserAgent},
    );
    final formhash = _extractFormhash(page);
    if (formhash == null) return false;
    final response = await _post(
      'home.php?mod=magic&mid=$mid&idtype=$idtype&id=$id&operation=use&mobile=no',
      {'formhash': formhash, 'usesubmit': 'yes'},
      headers: {
        'User-Agent': AppConfig.pcUserAgent,
        'Referer':
            '${AppConfig.baseUrl}home.php?mod=magic&mid=$mid&idtype=$idtype&id=$id&mobile=no',
      },
    );
    return DiscuzResponse.isSuccess(response);
  }

  static List<({int id, String name, String reward})>? cachedTasks(String item,
          {bool ignoreExpired = false}) =>
      DioClient.isLoggedIn
          ? PreloadService.instance
              .get<List<({int id, String name, String reward})>>(
                  _diskKey('task_list_$item'),
                  ignoreExpired: ignoreExpired)
          : null;

  /// 任务中心，按实际分类读取；短缓存供当前账号的首页和任务页共同使用。
  static Future<List<({int id, String name, String reward})>> getTasks(
      {String item = 'doing', bool forceRefresh = false}) async {
    if (!const {'new', 'doing', 'done', 'failed'}.contains(item)) {
      throw ArgumentError('未知任务分类');
    }
    if (!DioClient.isLoggedIn) throw StateError('请先登录后查看任务');
    final session = DioClient.sessionKey;
    if (!forceRefresh) {
      final cached = cachedTasks(item);
      if (cached != null) return cached;
    }
    Object? lastError;
    for (final mobile in ['no', '2']) {
      try {
        final source = await _get(
            Uri(path: 'home.php', queryParameters: {
              'mod': 'task',
              'item': item,
              'mobile': mobile,
            }).toString(),
            forceRefresh: forceRefresh);
        if (session != DioClient.sessionKey) throw StateError('账号已切换，请刷新任务');
        _rejectRestrictedPage(source);
        if (DiscuzTaskProtocol.recognizes(source, item)) {
          final tasks = DiscuzTaskProtocol.parse(source);
          PreloadService.instance.set(_diskKey('task_list_$item'), tasks,
              ttl: const Duration(minutes: 1));
          return tasks;
        }
        lastError = StateError('网站未返回该任务分类');
      } catch (error) {
        if (session != DioClient.sessionKey) rethrow;
        lastError = error;
      }
    }
    throw lastError ?? StateError('任务暂不可用');
  }

  /// 当前账号的推广链接。
  static Future<List<({String label, String url})>> getPromotion() async {
    final html = await _get(
      'home.php?mod=spacecp&ac=promotion&mobile=2',
      headers: {'User-Agent': AppConfig.mobileUserAgent},
    );
    var list = ComiisParser.parsePromotion(html);
    if (list.isEmpty) {
      final pcHtml = await _get(
        'home.php?mod=spacecp&ac=promotion&mobile=no',
        headers: {'User-Agent': AppConfig.pcUserAgent},
      );
      list = ComiisParser.parsePromotion(pcHtml);
    }
    return list;
  }

  /// 获取好友列表（支持 7 大 Tab 分类，对齐移动端手机版与 PC 版）
  static Future<List<FriendItem>> getFriends(
    int uid, {
    String view = 'me',
    int page = 1,
  }) async {
    final session = DioClient.sessionKey;
    List<FriendItem> observe(List<FriendItem> list) {
      _observeModelAvatars(
          list.map((item) => DiscuzAvatarDeclaration(
              uid: item.uid,
              username: item.username,
              avatarUrl: item.avatarUrl,
              faceUrl: item.faceUrl)),
          session);
      return list;
    }

    final myUid = await getMyUid();
    final isMe = (myUid != null && myUid > 0 && myUid == uid) || (uid <= 0);

    if (!isMe) {
      // 查看他人好友：调用 Discuz 原生 PC 好友页面接口
      try {
        final pcHtml = await _get(
          'home.php?mod=space&uid=$uid&do=friend&page=$page&mobile=no',
          headers: {'User-Agent': AppConfig.pcUserAgent},
          forceRefresh: true,
        );
        final list = ComiisParser.parseFriends(pcHtml, excludeUid: myUid);
        if (list.isNotEmpty) return observe(list);
      } catch (_) {}
      return const [];
    }

    // 根据 view 构造请求路径 (优先移动端手机版结构，对齐网页截图)
    String url;
    switch (view) {
      case 'follow':
        url = 'home.php?mod=space&do=friend&view=follow&page=$page&mobile=2';
        break;
      case 'fans':
        url = 'home.php?mod=space&do=friend&view=fans&page=$page&mobile=2';
        break;
      case 'visitor':
        url = 'home.php?mod=space&do=friend&view=visitor&page=$page&mobile=2';
        break;
      case 'trace':
        url = 'home.php?mod=space&do=friend&view=trace&page=$page&mobile=2';
        break;
      case 'request':
        url = 'home.php?mod=spacecp&ac=friend&op=request&page=$page&mobile=2';
        break;
      case 'blacklist':
        url = 'home.php?mod=space&do=friend&view=blacklist&page=$page&mobile=2';
        break;
      case 'me':
      default:
        url = 'home.php?mod=space&do=friend&page=$page&mobile=2';
        break;
    }

    try {
      final html = await _get(url);
      final list = ComiisParser.parseFriends(html, excludeUid: uid);
      if (list.isNotEmpty) return observe(list);
    } catch (_) {}

    // 移动端/PC 多端回退接口 (仅限本人主页时使用，严禁把本人好友当作他人好友)
    if (isMe) {
      if (view == 'me') {
        try {
          final myFriendsHtml =
              await _get('home.php?mod=space&do=friend&page=$page&mobile=2');
          final list = ComiisParser.parseFriends(myFriendsHtml,
              excludeUid: isMe ? uid : null);
          if (list.isNotEmpty) return observe(list);
        } catch (_) {}

        try {
          final pcMeHtml = await _get(
            'home.php?mod=space&uid=$uid&do=friend&view=me&from=space&page=$page&mobile=no',
            headers: {'User-Agent': AppConfig.pcUserAgent},
          );
          final list = ComiisParser.parseFriends(pcMeHtml,
              excludeUid: isMe ? uid : null);
          if (list.isNotEmpty) return observe(list);
        } catch (_) {}
      } else if (view == 'follow') {
        try {
          final fHtml = await _get('home.php?mod=follow&page=$page&mobile=2');
          final list =
              ComiisParser.parseFriends(fHtml, excludeUid: isMe ? uid : null);
          if (list.isNotEmpty) return observe(list);
        } catch (_) {}

        try {
          final pcFollowHtml = await _get(
            'home.php?mod=space&uid=$uid&do=friend&view=follow&page=$page&mobile=no',
            headers: {'User-Agent': AppConfig.pcUserAgent},
          );
          final list = ComiisParser.parseFriends(pcFollowHtml,
              excludeUid: isMe ? uid : null);
          if (list.isNotEmpty) return observe(list);
        } catch (_) {}
      }
    } else if (view == 'fans') {
      try {
        final fHtml =
            await _get('home.php?mod=follow&do=follower&page=$page&mobile=2');
        final list =
            ComiisParser.parseFriends(fHtml, excludeUid: isMe ? uid : null);
        if (list.isNotEmpty) return observe(list);
      } catch (_) {}

      try {
        final pcFansHtml = await _get(
          'home.php?mod=space&uid=$uid&do=friend&view=fans&page=$page&mobile=no',
          headers: {'User-Agent': AppConfig.pcUserAgent},
        );
        final list = ComiisParser.parseFriends(pcFansHtml,
            excludeUid: isMe ? uid : null);
        if (list.isNotEmpty) return observe(list);
      } catch (_) {}
    } else if (view == 'blacklist') {
      try {
        final blHtml =
            await _get('home.php?mod=spacecp&ac=friend&op=blacklist&mobile=2');
        final list =
            ComiisParser.parseFriends(blHtml, excludeUid: isMe ? uid : null);
        if (list.isNotEmpty) return observe(list);
      } catch (_) {}
    }

    return const [];
  }

  /// 修改好友备注/附注
  static Future<bool> editFriendNote(int uid, String note) async {
    try {
      final page = await _get(
          'home.php?mod=spacecp&ac=friend&op=editnote&uid=$uid&mobile=no');
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=friend&op=editnote&uid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'note': note,
          'editnotesubmit': 'true',
          'handlekey': 'editnote_$uid',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 更改好友分组
  static Future<bool> changeFriendGroup(int uid, int group) async {
    try {
      final page = await _get(
          'home.php?mod=spacecp&ac=friend&op=changegroup&uid=$uid&mobile=no');
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=friend&op=changegroup&uid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'group': group.toString(),
          'changegroupsubmit': 'true',
          'handlekey': 'cghk_$uid',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 按用户名添加黑名单 (对齐截图三)
  static Future<bool> addToBlacklistByUsername(String username) async {
    if (username.trim().isEmpty) return false;
    try {
      final page =
          await _get('home.php?mod=space&do=friend&view=blacklist&mobile=no');
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=friend&op=blacklist&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'username': username.trim(),
          'blacklistsubmit': 'true',
          'handlekey': 'addblackhk',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 打招呼 (Poke)
  static Future<bool> pokeUser(int uid, [String message = '打个招呼']) async {
    try {
      final page = await _get(
        'home.php?mod=spacecp&ac=poke&op=send&uid=$uid&mobile=no',
      );
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=poke&op=send&uid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'pokesubmit': 'true',
          'handlekey': 'poke_$uid',
          'iconid': '0',
          'note': message,
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 关注用户
  static Future<bool> followUser(int uid) async {
    try {
      final page = await _get('home.php?mod=space&uid=$uid&mobile=no');
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=follow&op=add&fuid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'hash': formhash,
          'handlekey': 'follow_$uid',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 取消关注用户
  static Future<bool> unfollowUser(int uid) async {
    try {
      final page = await _get('home.php?mod=space&uid=$uid&mobile=no');
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=follow&op=del&fuid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'handlekey': 'follow_$uid',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 同意好友申请
  static Future<bool> acceptFriendRequest(int uid) async {
    try {
      final page =
          await _get('home.php?mod=spacecp&ac=friend&op=request&mobile=no');
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=friend&op=add&uid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'addsubmit': 'true',
          'handlekey': 'afrhk_$uid',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 忽略好友申请
  static Future<bool> ignoreFriendRequest(int uid) async {
    try {
      final page =
          await _get('home.php?mod=spacecp&ac=friend&op=request&mobile=no');
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=friend&op=ignore&uid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'friendsubmit': 'true',
          'handlekey': 'ifr_hk_$uid',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 加入黑名单
  static Future<bool> addToBlacklist(int uid) async {
    try {
      final target = await getUserSpace(uid);
      if (target == null ||
          target.uid != uid ||
          target.username.isEmpty ||
          target.username.contains('***')) {
        return false;
      }
      final page =
          await _get('home.php?mod=spacecp&ac=friend&op=blacklist&mobile=no');
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=friend&op=blacklist&uid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'blacklistsubmit': 'true',
          'username': target.username,
          'handlekey': 'addblackhk_$uid',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 移出黑名单
  static Future<bool> removeFromBlacklist(int uid) async {
    try {
      final page =
          await _get('home.php?mod=space&do=friend&view=blacklist&mobile=no');
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=friend&op=blacklist&subop=delete&uid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'blacklistsubmit': 'true',
          'handlekey': 'delblackhk_$uid',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 发送好友申请
  static Future<bool> addFriend(int uid, [String message = '']) async {
    try {
      final page = await _get(
        'home.php?mod=spacecp&ac=friend&op=add&uid=$uid&mobile=no',
      );
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=friend&op=add&uid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'note': message,
          'addsubmit': 'true',
          'handlekey': 'addfriendhk_$uid',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// 删除好友
  static Future<bool> deleteFriend(int uid) async {
    try {
      final page = await _get(
        'home.php?mod=spacecp&ac=friend&op=ignore&uid=$uid&mobile=no',
      );
      final formhash = _extractFormhash(page) ?? _cachedFormhash;
      if (formhash == null) return false;
      final res = await _post(
        'home.php?mod=spacecp&ac=friend&op=ignore&uid=$uid&inajax=1&mobile=no',
        {
          'formhash': formhash,
          'friendsubmit': 'true',
          'handlekey': 'delfriendhk_$uid',
        },
      );
      return DiscuzResponse.isSuccess(res,
          acceptedMessages: ['请求已发送', '已发送', '成为好友']);
    } catch (_) {
      return false;
    }
  }

  /// Discuz 的单条消息删除与会话删除使用互斥的数组字段。
  static Future<bool> deletePm(int touid, {int? pmid}) async {
    if (!DioClient.isLoggedIn || touid <= 0) return false;
    final session = DioClient.sessionKey;
    try {
      final page = await _get('home.php?mod=space&do=pm&mobile=no',
          forceRefresh: true, expectedSession: session);
      if (session != DioClient.sessionKey || !DioClient.isLoggedIn) {
        return false;
      }
      final formhash = _extractFormhash(page);
      if (formhash == null) return false;
      final response = await _post(
          'home.php?mod=spacecp&ac=pm&op=delete&inajax=1&mobile=no',
          {
            'formhash': formhash,
            'deletesubmit': 'true',
            'touid': '$touid',
            if (pmid != null && pmid > 0)
              'deletepm_pmid[]': ['$pmid']
            else
              'deletepm_deluid[]': ['$touid'],
          },
          headers: {
            'User-Agent': AppConfig.pcUserAgent,
            'Referer': '${AppConfig.baseUrl}home.php?mod=space&do=pm&mobile=no'
          },
          expectedSession: session,
          invalidateCache: false);
      if (session != DioClient.sessionKey) return false;
      final success = DiscuzResponse.isSuccess(response);
      if (success) {
        clearQuickCache('home.php?mod=space&do=pm');
        PreloadService.instance.clear('pm_');
      }
      return success;
    } catch (_) {
      return false;
    }
  }

  /// 发送私信
  static Future<bool> sendPm(int touid, String message) async {
    var formhash = _cachedFormhash;
    try {
      final page = await _get(
        'home.php?mod=spacecp&ac=pm&op=send&touid=$touid',
      );
      formhash = _extractFormhash(page) ?? formhash;
    } catch (_) {}

    if (formhash == null || formhash.isEmpty) return false;
    final html = await _post(
      'home.php?mod=spacecp&ac=pm&op=send&touid=$touid&pmid=0&pmsubmit=yes&inajax=1',
      {
        'formhash': formhash,
        'message': message,
        'touid': '$touid',
        'pmsubmit': 'yes',
        'handlekey': 'pmsend',
      },
      headers: {
        'X-Requested-With': 'XMLHttpRequest',
        'Referer':
            '${AppConfig.baseUrl}home.php?mod=spacecp&ac=pm&op=send&touid=$touid',
      },
    );
    final success = DiscuzResponse.isSuccess(html);
    if (success) clearQuickCache('home.php?mod=space&do=pm');
    return success;
  }

  /// 检查今日是否已签到（严格依据 Discuz k_misign 插件实时解析）
  static Future<bool> checkSigned() async {
    try {
      final info = await getSignHeaderInfo(forceRefresh: true);
      return info.isSignedToday;
    } catch (_) {
      return false;
    }
  }

  static String? _cachedSignFormhash;

  /// 获取或预热签到 FormHash（100% 实时拉取最新登录凭据，优先从签到页提取，失败降级首页）
  static Future<String?> getSignFormhash({bool forceRefresh = true}) async {
    if (!forceRefresh &&
        _cachedSignFormhash != null &&
        _cachedSignFormhash!.isNotEmpty) {
      return _cachedSignFormhash;
    }
    String? formhash;
    final ts = DateTime.now().millisecondsSinceEpoch;
    // 1. 优先从 k_misign-sign.html 页面中获取（官方签到按钮所在页面）
    try {
      final signPageHtml = await _get(
        'k_misign-sign.html?_t=$ts',
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: true,
        cacheTtl: Duration.zero,
      );
      formhash = _extractFormhash(signPageHtml);
    } catch (_) {}

    // 2. 备用从 plugin.php 获取
    if (formhash == null) {
      try {
        final signPageHtml = await _get(
          'plugin.php?id=k_misign:sign&mobile=no&_t=$ts',
          headers: {'User-Agent': AppConfig.pcUserAgent},
          forceRefresh: true,
          cacheTtl: Duration.zero,
        );
        formhash = _extractFormhash(signPageHtml);
      } catch (_) {}
    }

    // 3. 兜底从论坛首页抓取（对齐油猴脚本 HOME_URL）
    if (formhash == null) {
      try {
        final homeHtml = await _get(
          'forum.php?_t=$ts',
          headers: {'User-Agent': AppConfig.pcUserAgent},
          forceRefresh: true,
          cacheTtl: Duration.zero,
        );
        formhash = _extractFormhash(homeHtml);
      } catch (_) {}
    }

    // 4. 移动端兜底
    if (formhash == null) {
      try {
        final forumHtml = await _get(
          'forum.php?mobile=2',
          forceRefresh: true,
          cacheTtl: Duration.zero,
        );
        formhash = _extractFormhash(forumHtml);
      } catch (_) {}
    }

    if (formhash != null && formhash.isNotEmpty) {
      _cachedSignFormhash = formhash;
    }
    return formhash;
  }

  /// 获取服务器精准时间与本地时间的偏差（毫秒：serverTime - localTime）
  /// 通过轻量 HEAD/GET 请求提取响应头 Date，解析 RFC 1123 / HttpDate
  static Future<int?> pingServerTime() async {
    try {
      final t0 = DateTime.now().millisecondsSinceEpoch;
      final resp = await _dio.head<void>(
        _url('k_misign-sign.html'),
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
          headers: {'User-Agent': AppConfig.pcUserAgent},
        ),
      );
      final t1 = DateTime.now().millisecondsSinceEpoch;
      final dateStr = resp.headers.value('date');
      if (dateStr != null) {
        final serverTime = HttpDate.parse(dateStr).millisecondsSinceEpoch;
        final latency = (t1 - t0) ~/ 2;
        final estimatedServerNow = serverTime + latency;
        return estimatedServerNow - t1;
      }
    } catch (_) {
      try {
        final t0 = DateTime.now().millisecondsSinceEpoch;
        final resp = await _dio.get<String>(
          _url('k_misign-sign.html'),
          options: Options(
            sendTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 3),
            headers: {'User-Agent': AppConfig.pcUserAgent},
          ),
        );
        final t1 = DateTime.now().millisecondsSinceEpoch;
        final dateStr = resp.headers.value('date');
        if (dateStr != null) {
          final serverTime = HttpDate.parse(dateStr).millisecondsSinceEpoch;
          final latency = (t1 - t0) ~/ 2;
          final estimatedServerNow = serverTime + latency;
          return estimatedServerNow - t1;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 实时探测论坛服务器恢复状态（轻量级探针，不走重型签到接口与大页面解析）
  /// 返回 true 表示论坛源站已完全恢复（HTTP 200 且响应体为正常论坛 HTML，非 502/503/504 故障页）
  static Future<bool> probeServerRecovery() async {
    try {
      final resp = await _dio.get<String>(
        _url(
            'k_misign-sign.html?_probe=${DateTime.now().millisecondsSinceEpoch}'),
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          headers: {
            'User-Agent': AppConfig.pcUserAgent,
            'Cache-Control': 'no-cache, no-store',
          },
          validateStatus: (status) => true,
        ),
      );
      final statusCode = resp.statusCode ?? 0;
      if (statusCode != 200 && statusCode != 302 && statusCode != 301) {
        return false;
      }
      final data = resp.data ?? '';
      if (data.isEmpty) return false;
      if (ServerOutageInfo.isOutageHtml(data)) {
        return false;
      }
      if (data.contains('klpbbs') ||
          data.contains('Discuz') ||
          data.contains('k_misign') ||
          data.contains('<!DOCTYPE') ||
          data.contains('<html')) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 只读访问签到页回退校验（对齐油猴脚本 verifySigned：安全只读请求）
  static Future<bool?> verifySigned() async {
    try {
      final info = await getSignHeaderInfo(forceRefresh: true);
      return info.hasPersonalState ? info.isSignedToday : null;
    } catch (_) {
      return null;
    }
  }

  /// 清理签到相关的内存与持久化排行榜缓存（严禁污染日历）
  static Future<void> clearSignLocalCache() async {
    PreloadService.instance.remove('sign_header_info_realtime');
    PreloadService.instance.clear('sign_header_');
    PreloadService.instance.clear('sign_rank_');
    clearQuickCache('plugin.php?id=k_misign');
    clearQuickCache('k_misign');
    try {
      final sp = await SharedPreferences.getInstance();
      final keys =
          sp.getKeys().where((k) => k.startsWith('sign_rank_')).toList();
      for (final k in keys) {
        await sp.remove(k);
      }
    } catch (_) {}
  }

  /// 真正确认签到成功时，将今日写入本地日历持久化缓存（严格锚定论坛东八区北京时间）
  static Future<void> recordSignDateToLocalCalendar(
      {String? expectedSession, String? expectedDay}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    if (session != DioClient.sessionKey) return;
    final now = AutoSignService.instance.estimatedServerNow;
    final targetDay = expectedDay ?? AutoSignService.instance.serverTodayStr;
    if (targetDay != AutoSignService.instance.serverTodayStr) return;
    final monthKey = KlpbbsApi.signCalendarKey(now.year, now.month);
    try {
      final sp = await SharedPreferences.getInstance();
      if (session != DioClient.sessionKey ||
          targetDay != AutoSignService.instance.serverTodayStr) {
        return;
      }
      final list = sp.getStringList(monthKey) ?? [];
      if (!list.contains('${now.day}')) {
        list.add('${now.day}');
        await sp.setStringList(monthKey, list.toSet().toList());
      }
    } catch (_) {}
  }

  /// 按当前 k_misign qiandao 路由签到，支持 CDATA 解包与只读状态核验。
  static final Map<String, Future<DiscuzSignResult>> _signInLoads = {};
  static const DiscuzSignResult _signDayChangedResult = (
    success: false,
    message: '论坛日期已变化，请刷新今日签到状态',
    rewardIron: null,
    rewardExp: null,
    rank: null,
    continuousDays: null,
  );

  static Future<DiscuzSignResult> signIn(
      {String? formhash, bool fastMode = false}) async {
    final session = DioClient.sessionKey;
    final existing = _signInLoads[session];
    if (existing != null) return existing;
    final future = _performSignIn(formhash: formhash, fastMode: fastMode);
    _signInLoads[session] = future;
    try {
      return await future;
    } finally {
      if (identical(_signInLoads[session], future)) {
        _signInLoads.remove(session);
      }
    }
  }

  static Future<DiscuzSignResult> _performSignIn(
      {String? formhash, bool fastMode = false}) async {
    final requestSession = DioClient.sessionKey;
    final requestDay = AutoSignService.instance.serverTodayStr;
    if (!AppConfig.allowWrite) {
      return (
        success: false,
        message: '当前配置不允许写操作',
        rewardIron: null,
        rewardExp: null,
        rank: null,
        continuousDays: null,
      );
    }
    if (!DioClient.isLoggedIn) {
      return (
        success: false,
        message: '请先登录论坛账号后再进行签到',
        rewardIron: null,
        rewardExp: null,
        rank: null,
        continuousDays: null,
      );
    }

    // 1. 获取/复用 FormHash（全实时拉取最新凭证）
    String? fh = formhash ?? _cachedSignFormhash ?? _cachedFormhash;
    if (fh == null || fh.isEmpty) {
      fh = await getSignFormhash(forceRefresh: true);
    }

    if (fh == null || fh.isEmpty) {
      return (
        success: false,
        message: '未能获取签到 FormHash，请确认登录会话是否有效',
        rewardIron: null,
        rewardExp: null,
        rank: null,
        continuousDays: null,
      );
    }

    if (requestSession != DioClient.sessionKey) {
      throw StateError('账号已切换，签到请求已取消');
    }
    if (requestDay != AutoSignService.instance.serverTodayStr) {
      return _signDayChangedResult;
    }

    // 当前插件的原生路由仅提交一次；网络响应不明确时由只读页面确认。
    String html = '';
    ServerOutageInfo? detectedOutage;
    try {
      html = await _get(
        'plugin.php?id=k_misign:sign&operation=qiandao&format=button&formhash=$fh&mobile=no',
        headers: {
          'User-Agent': AppConfig.pcUserAgent,
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '${AppConfig.baseUrl}plugin.php?id=k_misign:sign&mobile=no'
        },
        forceRefresh: true,
        cacheTtl: Duration.zero,
      );
      if (ServerOutageInfo.isOutageHtml(html)) {
        detectedOutage = ServerOutageInfo.fromHtml(html);
        html = '';
      }
    } on ServerOutageException catch (error) {
      detectedOutage = error.info;
    } catch (error) {
      detectedOutage = ServerOutageInfo.tryParse(error);
    }
    if (requestSession != DioClient.sessionKey) {
      throw StateError('账号已切换，请刷新签到状态');
    }
    if (requestDay != AutoSignService.instance.serverTodayStr) {
      return _signDayChangedResult;
    }

    if (html.isEmpty) {
      if (detectedOutage != null) {
        // 静默故障上报：自动通知 AutoSignService 启动恢复探测器
        AutoSignService.instance
            .notifyServerOutage(detectedOutage, source: '签到请求');
        return (
          success: false,
          message:
              '论坛暂不可用（${detectedOutage.statusCode} ${detectedOutage.title}），请稍后刷新签到状态',
          rewardIron: null,
          rewardExp: null,
          rank: null,
          continuousDays: null,
        );
      }
      return (
        success: false,
        message: '网络连接超时或未能连接到论坛服务器',
        rewardIron: null,
        rewardExp: null,
        rank: null,
        continuousDays: null,
      );
    }

    final parsed = DiscuzSignResponse.parse(html);
    final success = parsed.status == DiscuzSignStatus.success;
    var isAlready = parsed.status == DiscuzSignStatus.alreadySigned;
    var message = parsed.message;
    var rewardIron = parsed.rewardIron;
    var rewardExp = parsed.rewardExp;
    var rank = parsed.rank;
    var continuousDays = parsed.continuousDays;
    if (parsed.status == DiscuzSignStatus.unknown &&
        await verifySigned() == true) {
      isAlready = true;
      message = '今日已签到';
    }

    // 6. 权威数据二次同步补充（非 fastMode 时同步头部奖励/连续天数，但绝不逆转已判定的成功）
    if (!fastMode &&
        (success || isAlready) &&
        (rank == null || continuousDays == null)) {
      try {
        final headerInfo = await getSignHeaderInfo(forceRefresh: true);
        if (headerInfo.rewardIron.isNotEmpty) {
          rewardIron ??= headerInfo.rewardIron;
        }
        if (headerInfo.hasContinuousDays) {
          continuousDays ??= headerInfo.continuousDays;
        }
        if (headerInfo.mySignRank != null && headerInfo.mySignRank! > 0) {
          rank ??= headerInfo.mySignRank;
        }
      } catch (_) {}
    }

    if (requestSession != DioClient.sessionKey) {
      throw StateError('账号已切换，请刷新签到状态');
    }

    // 7. 成功或已签时，彻底清理排行榜缓存并落库本地日历与持久化签到成功状态
    if (requestDay != AutoSignService.instance.serverTodayStr) {
      return _signDayChangedResult;
    }
    if (success || isAlready) {
      // Signing cannot invalidate unrelated feeds, forums or user navigation.
      if (success) await clearSignLocalCache();
      await recordSignDateToLocalCalendar(
          expectedSession: requestSession, expectedDay: requestDay);
      if (!fastMode) {
        try {
          await AutoSignService.instance.markSignedToday(
            rank: rank,
            continuousDays: continuousDays,
            rewardIron: rewardIron?.toString(),
            rewardExp: rewardExp?.toString(),
            notify: success && AutoSignService.instance.notifyOnResult,
            submittedSuccessfully: success,
            expectedDay: requestDay,
            expectedSession: requestSession,
          );
        } catch (_) {}
      }
    }

    if (requestSession != DioClient.sessionKey) {
      throw StateError('账号已切换，请刷新签到状态');
    }
    if (requestDay != AutoSignService.instance.serverTodayStr) {
      return _signDayChangedResult;
    }
    return (
      success: success,
      message: message,
      rewardIron: rewardIron,
      rewardExp: rewardExp,
      rank: rank,
      continuousDays: continuousDays,
    );
  }

  /// 解码 HTML 实体（还原 Discuz textarea 中的真实原始 BBCode）
  static String _unescapeHtml(String text) {
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    }).replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
  }

  /// 获取帖子/楼层真实编辑数据（直接解析 Discuz 编辑页原始 BBCode 与表单数据）
  static Future<PostEditInfo> getPostEditInfo(
    int fid,
    int tid,
    int pid,
  ) async {
    String html = '';
    try {
      html = await _get(
        'forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&mobile=no',
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );
    } catch (e) {
      return PostEditInfo(errorMessage: '网络连接异常：$e');
    }

    // 检查移动端重定向或兜底
    if (!html.contains('<textarea') && !html.contains('messagetext')) {
      try {
        final mobHtml = await _get(
          'forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&mobile=2',
          headers: {
            'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
          },
        );
        if (mobHtml.contains('<textarea') ||
            mobHtml.contains('messagetext') ||
            mobHtml.contains('jump_c')) {
          html = mobHtml;
        }
      } catch (_) {}
    }

    final doc = html_parser.parse(html);

    // 1. 检查是否有 Discuz 权限/错误提示
    final alertEl =
        doc.querySelector('#messagetext, .jump_c, .alert_error, .alert_info');
    if (alertEl != null) {
      final msg = alertEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (msg.contains('没有权限') ||
          msg.contains('未登录') ||
          msg.contains('已过') ||
          msg.contains('抱歉')) {
        return PostEditInfo(errorMessage: msg);
      }
    }

    // 2. 提取 formhash 和 posttime
    final formhash = _extractFormhash(html) ?? _cachedFormhash;
    final posttimeInput = doc.querySelector('input[name="posttime"]');
    final posttime = posttimeInput?.attributes['value'];

    // 3. 提取 textarea 中的 BBCode message 原文
    final textareaEl =
        doc.querySelector('textarea#needmessage, textarea[name="message"]');
    String rawMessage = _unescapeHtml(textareaEl?.text ?? '');

    // 4. 提取标题 subject
    final subjectInput = doc.querySelector('input[name="subject"]');
    String subject = _unescapeHtml(subjectInput?.attributes['value'] ?? '');

    // 5. 提取分类 typeid
    int? typeid;
    final selOpt = doc.querySelector('select[name="typeid"] option[selected]');
    if (selOpt != null) {
      typeid = int.tryParse(selOpt.attributes['value'] ?? '');
    }
    if (typeid == null) {
      final typeidInput = doc.querySelector('input[name="typeid"]');
      if (typeidInput != null) {
        typeid = int.tryParse(typeidInput.attributes['value'] ?? '');
      }
    }

    // 6. 提取阅读权限 readperm
    int? readperm;
    final readpermInput = doc.querySelector('input[name="readperm"]');
    if (readpermInput != null) {
      readperm = int.tryParse(readpermInput.attributes['value'] ?? '');
    }

    // 7. 提取标签 tags
    final tags = <String>[];
    final tagsInput = doc.querySelector('input[name="tags"]');
    final tStr = tagsInput?.attributes['value'] ?? '';
    if (tStr.isNotEmpty) {
      tags.addAll(
        tStr.split(RegExp(r'[,，\s]+')).where((s) => s.isNotEmpty),
      );
    }

    // 8. 提取已有附件列表
    final attachments = <PostAttachmentItem>[];
    final seenAids = <int>{};

    for (final row
        in doc.querySelectorAll('tr[id^="attach_"], tbody[id^="attach_"]')) {
      final idAttr = row.attributes['id'] ?? '';
      final aid = int.tryParse(idAttr.replaceFirst('attach_', ''));
      if (aid != null && !seenAids.contains(aid)) {
        seenAids.add(aid);
        final nameEl =
            row.querySelector('a.attnt, [id^="span_attach_"], a[title]');
        final filename = nameEl?.text.trim() ??
            nameEl?.attributes['title']?.trim() ??
            '附件_$aid';

        final sizeEl = row.querySelector('.xg1');
        int filesize = 0;
        if (sizeEl != null) {
          final sizeMatch = RegExp(
            r'\(([\d\.]+)\s*([KkMmGg]?[Bb])',
            caseSensitive: false,
          ).firstMatch(sizeEl.text);
          if (sizeMatch != null) {
            final numVal = double.tryParse(sizeMatch.group(1)!) ?? 0;
            final unit = sizeMatch.group(2)!.toUpperCase();
            if (unit.startsWith('M')) {
              filesize = (numVal * 1024 * 1024).round();
            } else if (unit.startsWith('K')) {
              filesize = (numVal * 1024).round();
            } else {
              filesize = numVal.round();
            }
          }
        }

        final lowerName = filename.toLowerCase();
        final isImage = lowerName.endsWith('.png') ||
            lowerName.endsWith('.jpg') ||
            lowerName.endsWith('.jpeg') ||
            lowerName.endsWith('.gif') ||
            lowerName.endsWith('.webp') ||
            row.classes.contains('attach_img') ||
            row.innerHtml.contains('attach_img');

        final isInserted = rawMessage.contains('[attach]$aid') ||
            rawMessage.contains('[attachimg]$aid');

        attachments.add(
          PostAttachmentItem(
            aid: aid,
            filename: filename,
            filesize: filesize,
            isImage: isImage,
            isInserted: isInserted,
          ),
        );
      }
    }

    // 方式 B：检查 delete[] 复选框
    for (final delInput in doc
        .querySelectorAll('input[name="delete[]"], input[name*="delete"]')) {
      final aid = int.tryParse(delInput.attributes['value'] ?? '');
      if (aid != null && !seenAids.contains(aid)) {
        seenAids.add(aid);
        final isInserted = rawMessage.contains('[attach]$aid') ||
            rawMessage.contains('[attachimg]$aid');
        attachments.add(
          PostAttachmentItem(
            aid: aid,
            filename: '附件_$aid',
            filesize: 0,
            isImage: false,
            isInserted: isInserted,
          ),
        );
      }
    }

    // 方式 C：从 message 中的 [attach] 或 [attachimg] 兜底提取
    for (final m in RegExp(r'\[attach(?:img)?\](\d+)\[/attach(?:img)?\]')
        .allMatches(rawMessage)) {
      final aid = int.tryParse(m.group(1)!);
      if (aid != null && !seenAids.contains(aid)) {
        seenAids.add(aid);
        attachments.add(
          PostAttachmentItem(
            aid: aid,
            filename: '附件_$aid',
            filesize: 0,
            isImage: m.group(0)!.contains('attachimg'),
            isInserted: true,
          ),
        );
      }
    }

    final isFirstFloor = subject.isNotEmpty || html.contains('name="subject"');
    final threadSortInfo = ComiisParser.parseThreadSortInfo(html);
    int? sortid = threadSortInfo?.sortid;
    if (sortid == null || sortid <= 0) {
      final m = RegExp(r'name="sortid"[^>]+value="(\d+)"').firstMatch(html) ??
          RegExp(r"var\s+sortid\s*=\s*parseInt\('(\d+)'\)").firstMatch(html);
      if (m != null) sortid = int.tryParse(m.group(1)!);
    }

    final editorAttributes =
        ComiisParser.parseNewThreadInfo(html).editorAttributes;

    return PostEditInfo(
      subject: subject,
      message: rawMessage,
      typeid: typeid,
      sortid: sortid,
      threadSortInfo: threadSortInfo,
      readperm: readperm,
      tags: tags,
      formhash: formhash,
      posttime: posttime,
      attachments: attachments,
      isFirstFloor: isFirstFloor,
      editorAttributes: editorAttributes,
    );
  }

  /// 编辑自己的帖子（先取编辑页 formhash，再提交，支持分类、分类模板、权限、标签与附件关联）
  static Future<bool> editPost(
    int fid,
    int tid,
    int pid, {
    required String subject,
    required String message,
    int? typeid,
    int? sortid,
    Map<String, dynamic>? typeoptions,
    int? readPerm,
    List<String>? tags,
    List<int>? attachAids,
    int? stickTopic,
    int? addDigest,
    bool? deletePost,
  }) async {
    if (!DioClient.isLoggedIn) return false;
    final session = DioClient.sessionKey;
    DiscuzForm? form;
    try {
      final page = await _get(
        'forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&mobile=no',
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
          'User-Agent': AppConfig.pcUserAgent,
        },
      );
      form = DiscuzForm.namedSubmit(page, 'editsubmit');
      if (form == null) {
        throw StateError(DiscuzResponse.message(page) ?? '当前账号无法取得编辑表单');
      }
    } on DioException {
      return false;
    }

    if (session != DioClient.sessionKey) return false;
    final formhash = form.values['formhash']!;
    final editData = <String, dynamic>{
      ...form.values,
      'formhash': formhash,
      'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'wysiwyg': '0',
      'usesig': '1',
      'editsubmit': 'yes',
      if (subject.isNotEmpty) 'subject': subject,
      'message': message,
      if (stickTopic != null && stickTopic > 0) 'sticktopic': '$stickTopic',
      if (addDigest != null && addDigest > 0) 'adddigest': '$addDigest',
      if (deletePost == true) 'delete': '1',
    };

    if (typeid != null && typeid > 0) {
      editData['typeid'] = '$typeid';
    }
    if (sortid != null && sortid > 0) {
      editData['sortid'] = '$sortid';
      editData['selectsortid'] = '$sortid';
      if (typeoptions != null && typeoptions.isNotEmpty) {
        for (final entry in typeoptions.entries) {
          final val = entry.value;
          if (val is List) {
            editData['typeoption[${entry.key}][]'] =
                val.map((e) => '$e').toList();
          } else if (val != null && '$val'.isNotEmpty) {
            editData['typeoption[${entry.key}]'] = '$val';
          }
        }
      }
    }
    if (readPerm != null && readPerm >= 0) {
      editData['readperm'] = '$readPerm';
    }
    if (tags != null && tags.isNotEmpty) {
      editData['tags'] = tags.join(',');
    }

    final aids = <int>{
      ...?attachAids,
      for (final m in RegExp(r'\[attach(?:img)?\](\d+)\[/attach(?:img)?\]')
          .allMatches(message))
        if (int.tryParse(m.group(1)!) != null) int.parse(m.group(1)!),
    };
    for (final aid in aids) {
      editData['attachnew[$aid][description]'] = '';
    }
    if (aids.isNotEmpty) {
      editData['unused[]'] = aids.map((a) => '$a').toList();
    }

    Uri? responseUri;
    final html = await _post(
      'forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&editsubmit=yes&mobile=no',
      editData,
      expectedSession: session,
      onResponseUri: (uri) => responseUri = uri,
      headers: {
        'User-Agent': AppConfig.pcUserAgent,
        'Referer':
            '${AppConfig.baseUrl}forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid',
      },
    );
    if (session != DioClient.sessionKey) {
      throw StateError('账号已切换，请核对编辑结果');
    }
    final returnedTid = responseUri?.queryParameters['mod'] == 'viewthread'
        ? int.tryParse(responseUri?.queryParameters['tid'] ?? '')
        : int.tryParse(RegExp(r'/thread-(\d+)-')
                .firstMatch(responseUri?.path ?? '')
                ?.group(1) ??
            '');
    final ok = returnedTid == tid || DiscuzResponse.isSuccess(html);
    if (ok) {
      _clearCache(tid);
    }
    return ok;
  }

  /// 举报帖子/楼层（Discuz 标准 report 提交接口）
  static Future<bool> reportPost(
    int tid,
    int pid,
    String message, {
    String reason = '其他原因',
  }) async {
    if (!DioClient.isLoggedIn) return false;

    // 1. 获取 formhash
    String? formhash = _cachedFormhash;
    if (formhash == null || formhash.isEmpty) {
      try {
        final p1 = await _get(
          'misc.php?mod=report&rtype=post&rid=$pid&tid=$tid&inajax=1',
        );
        formhash = _extractFormhash(p1);
      } catch (_) {}
    }

    if (formhash == null || formhash.isEmpty) {
      try {
        final p2 = await _get(
          'forum.php?mod=misc&action=report&inajax=1&tid=$tid&pid=$pid',
        );
        formhash = _extractFormhash(p2);
      } catch (_) {}
    }

    if (formhash == null || formhash.isEmpty) {
      try {
        final p3 = await _get('forum.php?mod=viewthread&tid=$tid&mobile=2');
        formhash = _extractFormhash(p3);
      } catch (_) {}
    }

    if (formhash == null || formhash.isEmpty) return false;

    final payload = {
      'formhash': formhash,
      'reportsubmit': 'yes',
      'rtype': 'post',
      'rid': '$pid',
      'tid': '$tid',
      'url': 'forum.php?mod=viewthread&tid=$tid&pid=$pid#pid$pid',
      'message': message,
      'reason': reason,
      'message_reason': reason,
      'handlekey': 'report',
    };

    try {
      final html = await _post(
        'misc.php?mod=report&inajax=1',
        payload,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );
      if (DiscuzResponse.isSuccess(html,
          acceptedMessages: ['感谢您的举报', '已向管理员报告'])) {
        return true;
      }
    } catch (_) {}

    try {
      final fallbackHtml = await _post(
        'forum.php?mod=misc&action=report&reportsubmit=yes&inajax=1',
        payload,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );
      return DiscuzResponse.isSuccess(fallbackHtml,
          acceptedMessages: ['感谢您的举报', '已向管理员报告']);
    } catch (_) {
      return false;
    }
  }

  /// PC 模板包含完整资料表单；康美手机版可能只返回资料设置导航。
  static Future<Map<String, dynamic>> getProfileEditData(
      {String op = 'info',
      bool forceRefresh = false,
      String? expectedSession}) async {
    if (!const {'base', 'contact', 'info'}.contains(op)) {
      throw ArgumentError.value(op, 'op');
    }
    final session = expectedSession ?? DioClient.sessionKey;
    final page =
        Uri.parse(_url('home.php?mod=spacecp&ac=profile&op=$op&mobile=no'));
    Uri? responseUri;
    final source = await _get(page.toString(),
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: forceRefresh,
        expectedSession: session,
        onResponseUri: (uri) => responseUri = uri);
    if (session != DioClient.sessionKey) throw StateError('账号已变化，请重新打开资料设置');
    final form = DiscuzForm.profile(source);
    if (form == null) {
      throw StateError(
          ComiisParser.parseMessage(source) ?? '当前账号未取得资料编辑表单，请重新登录后重试');
    }
    if (!_isProfileForm(page, responseUri ?? page, form, op)) {
      throw StateError('论坛返回了其他资料分类，请刷新当前分类');
    }
    return ComiisParser.parseProfileEditInfo(source, op: op);
  }

  static bool _isProfileForm(
      Uri page, Uri responseUri, DiscuzForm form, String op) {
    return DiscuzProfileContract.matches(page, responseUri, form, op);
  }

  /// 提交更新个人资料（根据 Discuz 标准拆分至对应 op 提交，确保签名/头衔/字段绝对生效）
  static Future<bool> updateProfile({
    String op = 'info', // 'info', 'base', 'contact'
    String? signature,
    String? customStatus,
    String? representativeWork,
    String? repWorkPrivacy,
    String? bedrockUsername,
    String? bedrockPrivacy,
    String? neteaseUsername,
    String? neteasePrivacy,
    String? javaUsername,
    String? javaPrivacy,
    String? xboxId,
    String? realname,
    String? realnamePrivacy,
    int? gender,
    String? genderPrivacy,
    int? birthYear,
    int? birthMonth,
    int? birthDay,
    String? birthdayPrivacy,
    Map<String, String>? extraFields,
  }) async {
    if (!const {'base', 'contact', 'info'}.contains(op)) return false;
    final session = DioClient.sessionKey;
    final form = DiscuzForm.profile(await _get(
        'home.php?mod=spacecp&ac=profile&op=$op&mobile=no',
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: true,
        expectedSession: session));
    if (session != DioClient.sessionKey) return false;
    if (form == null) return false;
    final edits = <String, String>{
      if (signature != null) 'sightml': signature,
      if (customStatus != null) 'customstatus': customStatus,
      if (realname != null) 'realname': realname,
      if (realnamePrivacy != null) 'privacy[realname]': realnamePrivacy,
      if (gender != null) 'gender': '$gender',
      if (genderPrivacy != null) 'privacy[gender]': genderPrivacy,
      if (birthYear != null) 'birthyear': '$birthYear',
      if (birthMonth != null) 'birthmonth': '$birthMonth',
      if (birthDay != null) 'birthday': '$birthDay',
      if (birthdayPrivacy != null) 'privacy[birthday]': birthdayPrivacy,
      if (extraFields != null) ...extraFields,
    };
    bool addField(String label, String? value, String? privacy) {
      if (value == null) return true;
      final matches = form.labels.entries.where(
          (entry) => entry.value.replaceAll(RegExp(r'[\s*：:]'), '') == label);
      if (matches.length != 1) return false;
      final name = matches.single.key;
      edits[name] = value;
      if (privacy != null) edits['privacy[$name]'] = privacy;
      return true;
    }

    if (!addField('代表作', representativeWork, repWorkPrivacy) ||
        !addField('基岩版用户名', bedrockUsername, bedrockPrivacy) ||
        !addField('网易用户名', neteaseUsername, neteasePrivacy) ||
        !addField('Java版用户名', javaUsername, javaPrivacy) ||
        !addField('XboxID', xboxId, null)) {
      return false;
    }
    return submitProfileForm(op: op, formData: edits, expectedSession: session);
  }

  /// 提交任意 op 的动态个人资料表单
  static Future<bool> submitProfileForm({
    required String op,
    required Map<String, String> formData,
    String? expectedSession,
  }) async {
    final session = expectedSession ?? DioClient.sessionKey;
    final edits = Map<String, String>.unmodifiable(formData);
    if (!DioClient.isLoggedIn ||
        session != DioClient.sessionKey ||
        !const {'base', 'contact', 'info'}.contains(op)) {
      return false;
    }
    final pageUrl = _url('home.php?mod=spacecp&ac=profile&op=$op&mobile=no');
    Uri? responseUri;
    final form = DiscuzForm.profile(await _get(pageUrl,
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: true,
        expectedSession: session,
        onResponseUri: (uri) => responseUri = uri));
    if (form == null ||
        session != DioClient.sessionKey ||
        !_isProfileForm(
            Uri.parse(pageUrl), responseUri ?? Uri.parse(pageUrl), form, op)) {
      return false;
    }
    final data = DiscuzProfileContract.merge(form, edits);
    if (data == null) return false;
    final target = Uri.parse(pageUrl).resolve(form.action);
    if (!DiscuzRequestPolicy.sameOrigin(Uri.parse(pageUrl), target)) {
      return false;
    }
    final submitUrl = target
        .replace(queryParameters: {...target.queryParameters, 'mobile': 'no'});
    final response = await _post(submitUrl.toString(), data,
        expectedSession: session,
        headers: {
          'User-Agent': AppConfig.pcUserAgent,
          'Referer': pageUrl,
        });
    if (session != DioClient.sessionKey) return false;
    final success = DiscuzResponse.isSuccess(response);
    if (success) await invalidateUserProfile(expectedSession: session);
    return success;
  }

  /// 排序由 KLPBBS 插件提供，action=order 不是 Discuz 原生接口。
  static Future<bool> saveMedalOrder(List<int> medalIds,
      {String? expectedSession}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    final ids = List<int>.unmodifiable(medalIds);
    if (!DioClient.isLoggedIn ||
        session != DioClient.sessionKey ||
        ids.isEmpty ||
        ids.any((id) => id <= 0) ||
        ids.toSet().length != ids.length) {
      return false;
    }
    try {
      final indexUrl = Uri.parse(_url('home.php?mod=medal&mobile=no'));
      final index = html_parser.parse(await _get(indexUrl.toString(),
          forceRefresh: true, expectedSession: session));
      if (session != DioClient.sessionKey) return false;
      final links = index
          .querySelectorAll('a[href]')
          .where((link) => link.text.trim() == '勋章排序');
      if (links.isEmpty) return false;
      final pageUri = indexUrl.resolve(links.first.attributes['href']!);
      if (!DiscuzRequestPolicy.sameOrigin(pageUri, indexUrl)) return false;
      final pageUrl = pageUri.toString();
      final source = await _get(pageUrl,
          headers: {'User-Agent': AppConfig.pcUserAgent},
          forceRefresh: true,
          expectedSession: session);
      if (session != DioClient.sessionKey) return false;
      final order = KlpbbsMedalOrder.parse(source, pageUri);
      final data = order.mergeEdits(ids);
      if (data == null ||
          !DiscuzRequestPolicy.sameOrigin(
              order.action, Uri.parse(AppConfig.baseUrl))) {
        return false;
      }
      final response = await _post(order.action.toString(), data,
          headers: {'User-Agent': AppConfig.pcUserAgent, 'Referer': pageUrl},
          expectedSession: session);
      if (session != DioClient.sessionKey) return false;
      final success = DiscuzResponse.isSuccess(response);
      if (success) await invalidateUserProfile(expectedSession: session);
      return success && session == DioClient.sessionKey;
    } catch (_) {
      return false;
    }
  }

  /// 修改论坛登录密码 / 安全提问 / 安全邮箱
  static Future<({bool success, String message})> updatePassword({
    required String oldPassword,
    required String newPassword,
    String? newPasswordConfirm,
    int? questionId,
    String? answer,
    String? email,
  }) async {
    try {
      if (newPassword.isEmpty ||
          newPassword != (newPasswordConfirm ?? newPassword)) {
        return (success: false, message: '新密码为空或两次输入不一致');
      }
      const pagePath = 'home.php?mod=spacecp&ac=profile&op=password&mobile=no';
      final page = await _get(pagePath,
          headers: {'User-Agent': AppConfig.pcUserAgent}, forceRefresh: true);
      final doc = html_parser.parse(page);
      final form = doc
          .querySelectorAll('form')
          .where((element) =>
              element.querySelector('[name="passwordsubmit"]') != null)
          .firstOrNull;
      final formhash =
          form?.querySelector('[name="formhash"]')?.attributes['value'];
      if (form == null || formhash?.isNotEmpty != true) {
        return (success: false, message: '密码安全表单不可用，请在安全中心完成操作');
      }
      if (form.querySelector(
              '[name="seccodeverify"], [name="secanswer"], [id^="seccode_"]') !=
          null) {
        return (success: false, message: '此操作需要网页验证，请在密码安全中心完成');
      }
      final currentEmail =
          form.querySelector('[name="emailnew"]')?.attributes['value'];
      if (email == null && currentEmail == null) {
        return (success: false, message: '无法读取当前安全邮箱，请在密码安全中心完成');
      }
      final data = <String, String>{};
      for (final control
          in form.querySelectorAll('input[type="hidden"][name]')) {
        data[control.attributes['name']!] = control.attributes['value'] ?? '';
      }
      data.addAll({
        'formhash': formhash!,
        'passwordsubmit': 'true',
        'oldpassword': oldPassword,
        'newpassword': newPassword,
        'newpassword2': newPasswordConfirm ?? newPassword,
        // 空字符串是 Discuz 的“保留安全提问”，省略字段会清除旧设置。
        'questionidnew': questionId == null ? '' : '$questionId',
        'answernew': questionId == null ? '' : (answer ?? ''),
        'emailnew': email ?? currentEmail!,
      });
      final action = Uri.parse(_url(pagePath))
          .resolve(form.attributes['action'] ?? pagePath);
      if (!DiscuzRequestPolicy.sameOrigin(
          action, Uri.parse(AppConfig.baseUrl))) {
        return (success: false, message: '密码安全表单的提交地址无效');
      }
      final response = await _post(
        action.replace(queryParameters: {
          ...action.queryParameters,
          'mobile': 'no'
        }).toString(),
        data,
        headers: {
          'User-Agent': AppConfig.pcUserAgent,
          'Referer': _url(pagePath),
        },
      );
      final success = DiscuzResponse.isSuccess(response);
      final message = html_parser
          .parse(response)
          .querySelector(
              '#messagetext, .alert_error, .alert_info, .jump_c, .comiis_tip')
          ?.text
          .trim();
      if (success) clearQuickCache();
      return (
        success: success,
        message: message?.isNotEmpty == true
            ? message!
            : (success ? '密码安全设置已保存，请按网站提示重新登录' : '网站未确认修改成功，请检查原密码与验证要求')
      );
    } catch (e) {
      return (success: false, message: '请求异常：$e');
    }
  }

  /// 上传附件/文件/图片（发帖附件；Discuz swfupload 接口，深度兼容 Web 端）
  /// 返回上传成功后的 aid，失败返回 null
  static Future<int?> uploadAttachment(
    int fid,
    String filePath, {
    int? tid,
    int? pid,
    bool isImage = false,
  }) async {
    try {
      // 1) 优先从发帖/回复/编辑页面获取 uid 与 upload hash 会话凭证
      final postUrl = (pid != null && pid > 0 && tid != null && tid > 0)
          ? 'forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&mobile=no'
          : ((tid != null && tid > 0)
              ? 'forum.php?mod=post&action=reply&fid=$fid&tid=$tid&mobile=no'
              : 'forum.php?mod=post&action=newthread&fid=$fid&mobile=no');

      final refererUrl = (tid != null && tid > 0)
          ? '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid'
          : '${AppConfig.baseUrl}forum.php?mod=forumdisplay&fid=$fid';

      String page = '';
      try {
        page = await _get(
          postUrl,
          headers: {
            'Referer': refererUrl,
            'User-Agent': AppConfig.pcUserAgent,
          },
        );
      } catch (_) {}

      final session = DioClient.cookieStateKey;
      final uid = DiscuzSessionParser.parse(page).uid;
      if (uid == null || uid <= 0) return null;
      // upload hash 是 32 位 MD5，不能用 8 位 formhash 代替。
      final hashM = RegExp(
        r'''(?:name=["'](?:upload)?hash["']\s+value=["']([a-f0-9]{32})["']|(?:upload)?hash\s*[:=]\s*["']([a-f0-9]{32})["']|['"](?:upload)?hash['"]\s*:\s*['"]([a-f0-9]{32})['"]|hash=([a-f0-9]{32})(?:[&"']|$))''',
        caseSensitive: false,
      ).firstMatch(page);
      final hash = hashM?.group(1) ??
          hashM?.group(2) ??
          hashM?.group(3) ??
          hashM?.group(4);
      if (hash == null) return null;

      final filename = filePath.split(RegExp(r'[/\\]')).last;
      final formMap = <String, dynamic>{
        'uid': '$uid',
        'hash': hash,
        'Filedata': await MultipartFile.fromFile(
          filePath,
          filename: filename,
        ),
      };
      final form = FormData.fromMap(formMap);
      final resp = await _dio.post<List<int>>(
        _url(
            'misc.php?mod=swfupload&action=swfupload&operation=upload&fid=$fid&simple=1&mobile=no${isImage ? '&type=image' : ''}'),
        data: form,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (code) => code != null && code < 400,
          headers: {
            'Referer': '${AppConfig.baseUrl}$postUrl',
            'User-Agent': AppConfig.pcUserAgent,
          },
        ),
      );
      if (DioClient.cookieStateKey != session ||
          resp.extra['cookiesAccepted'] == false) {
        return null;
      }
      return DiscuzUploadResponse.attachmentId(_decode(resp.data ?? const []));
    } catch (_) {}
    return null;
  }

  /// 上传图片（兼容旧方法调用，返回 aid 字符串）
  static Future<String?> uploadImage(int fid, String filePath) async {
    final aid = await uploadAttachment(fid, filePath, isImage: true);
    return aid != null ? '$aid' : null;
  }

  /// 删除自己的帖子/主题
  static Future<bool> deletePost(int fid, int tid, int pid) async {
    var formhash = _cachedFormhash;
    try {
      final page = await _get(
        'forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&mobile=no',
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );
      formhash = _extractFormhash(page) ?? formhash;
    } catch (_) {}

    if (formhash == null || formhash.isEmpty) return false;
    final html = await _post(
      'forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&editsubmit=yes&mobile=no',
      {
        'formhash': formhash,
        'posttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'delete': '1',
        'editsubmit': 'yes',
      },
      headers: {
        'Referer':
            '${AppConfig.baseUrl}forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid',
      },
    );
    return DiscuzResponse.isSuccess(html);
  }

  /// 统一 Discuz 主题管理提交接口 (forum.php?mod=topicadmin&action=moderate)
  static Future<({bool success, String message})> moderateTopicAdmin({
    required int fid,
    required int tid,
    required int optgroup,
    required String operation,
    Map<String, dynamic> extraParams = const {},
    String reason = '管理操作',
  }) async {
    try {
      var formhash = _cachedFormhash;
      final page = await _get(
        'forum.php?mod=topicadmin&action=moderate&fid=$fid&moderate[]=$tid&operation=$operation&infloat=yes&handlekey=mods&inajax=1&mobile=no',
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );
      formhash = _extractFormhash(page) ?? formhash;
      if (formhash == null || formhash.isEmpty) {
        return (success: false, message: '获取管理权限凭证失败，请确认是否已登录并具备管理权限');
      }

      final payload = <String, dynamic>{
        'formhash': formhash,
        'fid': '$fid',
        'moderate[]': '$tid',
        'operation': operation,
        'optgroup': '$optgroup',
        'reason': reason,
        'modsubmit': 'yes',
        ...extraParams,
      };

      final res = await _post(
        'forum.php?mod=topicadmin&action=moderate&fid=$fid&optgroup=$optgroup&modsubmit=yes&inajax=1',
        payload,
        headers: {
          'Referer':
              '${AppConfig.baseUrl}forum.php?mod=topicadmin&action=moderate&fid=$fid&moderate[]=$tid&operation=$operation',
        },
      );

      if (DiscuzResponse.isSuccess(res)) {
        return (success: true, message: '操作成功');
      } else {
        final msg =
            _extractDiscuzResponseMessage(res, defaultMsg: '操作失败，可能无权限或已被处理');
        return (success: false, message: msg);
      }
    } catch (e) {
      return (success: false, message: '管理操作异常：$e');
    }
  }

  /// 置顶主题 (0=取消置顶, 1=本版置顶, 2=分区置顶, 3=全局置顶)
  static Future<({bool success, String message})> moderateStickThread({
    required int fid,
    required int tid,
    required int stickLevel,
    String reason = '版主置顶管理',
  }) {
    return moderateTopicAdmin(
      fid: fid,
      tid: tid,
      optgroup: 1,
      operation: 'stick',
      extraParams: {'sticklevel': '$stickLevel'},
      reason: reason,
    );
  }

  /// 加精主题 (0=取消精华, 1=精华I, 2=精华II, 3=精华III)
  static Future<({bool success, String message})> moderateDigestThread({
    required int fid,
    required int tid,
    required int digestLevel,
    String reason = '版主加精管理',
  }) {
    return moderateTopicAdmin(
      fid: fid,
      tid: tid,
      optgroup: 1,
      operation: 'digest',
      extraParams: {'digestlevel': '$digestLevel'},
      reason: reason,
    );
  }

  /// 高亮变色主题
  static Future<({bool success, String message})> moderateHighlightThread({
    required int fid,
    required int tid,
    String color = '1',
    bool bold = false,
    bool italic = false,
    bool underline = false,
    String reason = '版主高亮管理',
  }) {
    final extra = <String, dynamic>{
      'highlight_color': color,
    };
    if (bold) extra['highlight_style[1]'] = '1';
    if (italic) extra['highlight_style[2]'] = '1';
    if (underline) extra['highlight_style[3]'] = '1';
    return moderateTopicAdmin(
      fid: fid,
      tid: tid,
      optgroup: 1,
      operation: 'highlight',
      extraParams: extra,
      reason: reason,
    );
  }

  /// 关闭 / 打开主题 (close=true 锁定禁止回复, false 解锁开启)
  static Future<({bool success, String message})> moderateCloseThread({
    required int fid,
    required int tid,
    required bool close,
    String reason = '版主锁定管理',
  }) {
    return moderateTopicAdmin(
      fid: fid,
      tid: tid,
      optgroup: 4,
      operation: 'close',
      extraParams: {'close': close ? '1' : '0'},
      reason: reason,
    );
  }

  /// 移动主题到目标版块
  static Future<({bool success, String message})> moderateMoveThread({
    required int fid,
    required int tid,
    required int targetFid,
    String reason = '版主移动主题',
  }) {
    return moderateTopicAdmin(
      fid: fid,
      tid: tid,
      optgroup: 2,
      operation: 'move',
      extraParams: {'moveto': '$targetFid', 'type': 'normal'},
      reason: reason,
    );
  }

  /// 给主题盖图章 (stamp: 0=取消图章, 1~10=图章编号)
  static Future<({bool success, String message})> moderateStampThread({
    required int fid,
    required int tid,
    required int stampId,
    String reason = '版主盖图章管理',
  }) {
    return moderateTopicAdmin(
      fid: fid,
      tid: tid,
      optgroup: 5,
      operation: 'stamp',
      extraParams: {'stamp': '$stampId'},
      reason: reason,
    );
  }

  /// 版主/管理人员通过 topicadmin 接口管理删帖
  static Future<({bool success, String message})> moderateDeleteThread({
    required int fid,
    required int tid,
    String reason = '版主管理删帖',
  }) async {
    return moderateTopicAdmin(
      fid: fid,
      tid: tid,
      optgroup: 3,
      operation: 'delete',
      extraParams: {'operations[]': 'delete'},
      reason: reason,
    );
  }

  /// 删除指定单楼层回帖 (delpost)
  static Future<({bool success, String message})> moderateDeleteFloor({
    required int fid,
    required int tid,
    required int pid,
    String reason = '违规回帖删除',
  }) async {
    try {
      var formhash = _cachedFormhash;
      if (formhash == null || formhash.isEmpty) {
        final page = await _get('forum.php?mod=viewthread&tid=$tid&mobile=2');
        formhash = _extractFormhash(page);
      }
      if (formhash == null || formhash.isEmpty) {
        return (success: false, message: '获取凭证失败，请先登录');
      }

      final res = await _post(
        'forum.php?mod=topicadmin&action=delpost&fid=$fid&tid=$tid&modsubmit=yes&inajax=1',
        {
          'formhash': formhash,
          'topiclist[]': '$pid',
          'reason': reason,
          'modsubmit': 'yes',
        },
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );

      if (DiscuzResponse.isSuccess(res)) {
        return (success: true, message: '楼层删除成功');
      } else {
        final msg = _extractDiscuzResponseMessage(res, defaultMsg: '删除楼层失败');
        return (success: false, message: msg);
      }
    } catch (e) {
      return (success: false, message: '删除楼层异常：$e');
    }
  }

  /// 屏蔽 / 取消屏蔽指定楼层 (banpost)
  static Future<({bool success, String message})> moderateBanFloor({
    required int fid,
    required int tid,
    required int pid,
    required bool banned,
    String reason = '违规内容屏蔽',
  }) async {
    try {
      var formhash = _cachedFormhash;
      if (formhash == null || formhash.isEmpty) {
        final page = await _get('forum.php?mod=viewthread&tid=$tid&mobile=2');
        formhash = _extractFormhash(page);
      }
      if (formhash == null || formhash.isEmpty) {
        return (success: false, message: '获取凭证失败，请先登录');
      }

      final res = await _post(
        'forum.php?mod=topicadmin&action=banpost&fid=$fid&tid=$tid&modsubmit=yes&inajax=1',
        {
          'formhash': formhash,
          'topiclist[]': '$pid',
          'banned': banned ? '1' : '0',
          'reason': reason,
          'modsubmit': 'yes',
        },
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );

      if (DiscuzResponse.isSuccess(res)) {
        return (success: true, message: banned ? '楼层已成功屏蔽' : '已解除楼层屏蔽');
      } else {
        final msg = _extractDiscuzResponseMessage(res, defaultMsg: '屏蔽操作失败');
        return (success: false, message: msg);
      }
    } catch (e) {
      return (success: false, message: '屏蔽操作异常：$e');
    }
  }

  /// 警告 / 取消警告指定楼层作者 (warnpost)
  static Future<({bool success, String message})> moderateWarnFloor({
    required int fid,
    required int tid,
    required int pid,
    required bool warned,
    String reason = '违规言论警告',
  }) async {
    try {
      var formhash = _cachedFormhash;
      if (formhash == null || formhash.isEmpty) {
        final page = await _get('forum.php?mod=viewthread&tid=$tid&mobile=2');
        formhash = _extractFormhash(page);
      }
      if (formhash == null || formhash.isEmpty) {
        return (success: false, message: '获取凭证失败，请先登录');
      }

      final res = await _post(
        'forum.php?mod=topicadmin&action=warnpost&fid=$fid&tid=$tid&modsubmit=yes&inajax=1',
        {
          'formhash': formhash,
          'topiclist[]': '$pid',
          'warned': warned ? '1' : '0',
          'reason': reason,
          'modsubmit': 'yes',
        },
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );

      if (DiscuzResponse.isSuccess(res)) {
        return (success: true, message: warned ? '已向该作者发出警告' : '已撤销警告');
      } else {
        final msg = _extractDiscuzResponseMessage(res, defaultMsg: '警告操作失败');
        return (success: false, message: msg);
      }
    } catch (e) {
      return (success: false, message: '警告操作异常：$e');
    }
  }

  /// 查询指定楼层真实发帖 IP 与归属地 (getip)
  static Future<({bool success, String ip, String location, String message})>
      getFloorIp({
    required int fid,
    required int tid,
    required int pid,
  }) async {
    try {
      final html = await _get(
        'forum.php?mod=topicadmin&action=getip&fid=$fid&tid=$tid&pid=$pid&inajax=1&mobile=no',
        headers: {
          'User-Agent': AppConfig.pcUserAgent,
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
        forceRefresh: true,
      );
      final result = DiscuzIpResponse.parse(html);
      if (result != null) {
        return (
          success: true,
          ip: result.ip,
          location: result.location,
          message: '获取成功'
        );
      }
      return (
        success: false,
        ip: '',
        location: '',
        message: _extractDiscuzResponseMessage(html,
            defaultMsg: '网站未返回该楼层的 IP，请检查查看权限')
      );
    } catch (e) {
      return (success: false, ip: '', location: '', message: '查询 IP 异常：$e');
    }
  }

  /// 获取前台管理中心 (ModCP) 待处理举报列表
  static Future<List<DiscuzReport>> getModReports(
      {int? fid,
      int page = 1,
      bool forceRefresh = false,
      String? expectedSession}) async {
    if (!DioClient.isLoggedIn) throw StateError('请先登录管理账号');
    if (page < 1) throw ArgumentError.value(page, 'page', '举报页码必须大于零');
    final session = DioClient.sessionKey;
    if (expectedSession != null && session != expectedSession) {
      throw StateError('账号已切换，请重新打开管理中心');
    }
    final source = await _get(
        'forum.php?mod=modcp&action=report${fid != null ? '&fid=$fid' : ''}&page=$page&mobile=no',
        forceRefresh: forceRefresh,
        expectedSession: session);
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新打开管理中心');
    return DiscuzModcp.reports(source);
  }

  /// 使用当前管理表单中的 reportsubmit 与 reportids[]，仅确认已选举报。
  static Future<bool> resolveModReport(
      {required List<int> reportIds,
      int? fid,
      int page = 1,
      String? expectedSession}) async {
    if (!DioClient.isLoggedIn ||
        reportIds.isEmpty ||
        page < 1 ||
        reportIds.any((id) => id <= 0) ||
        reportIds.toSet().length != reportIds.length) {
      return false;
    }
    final session = DioClient.sessionKey;
    if (expectedSession != null && session != expectedSession) return false;
    final path =
        'forum.php?mod=modcp&action=report${fid != null ? '&fid=$fid' : ''}&page=$page&mobile=no';
    try {
      final source = await _get(path,
          forceRefresh: true,
          cacheTtl: Duration.zero,
          expectedSession: session);
      final form = DiscuzForm.namedSubmit(source, 'reportsubmit');
      final present =
          DiscuzModcp.reports(source).map((report) => report.id).toSet();
      if (form == null ||
          !reportIds.every(present.contains) ||
          session != DioClient.sessionKey) {
        return false;
      }
      final target = Uri.parse(_url(path)).resolve(form.action);
      if (target.origin != Uri.parse(AppConfig.baseUrl).origin ||
          target.queryParameters['action'] != 'report') {
        return false;
      }
      final values = <String, dynamic>{
        ...form.values,
        'reportids[]': reportIds.map((id) => '$id').toList()
      };
      // “标记处理”不会给举报人自动加减积分。
      for (final name in values.keys.toList()) {
        if (name.startsWith('creditsvalue[')) values[name] = '0';
        if (name == 'chkall') values.remove(name);
      }
      final response = await _post(target.toString(), values,
          headers: {'Referer': _url(path)}, expectedSession: session);
      return session == DioClient.sessionKey &&
          DiscuzResponse.isSuccess(response, acceptedMessages: ['举报处理完成']);
    } catch (_) {
      return false;
    }
  }

  static Future<({bool success, String message})> banUserInModCp({
    required String username,
    required int banGroupId,
    int days = 0,
    String reason = '违规处理',
    String? expectedSession,
  }) async {
    if (!DioClient.isLoggedIn ||
        !const {4, 5}.contains(banGroupId) ||
        days < 0) {
      return (success: false, message: '请检查管理账号与处罚期限');
    }
    final session = DioClient.sessionKey;
    if (expectedSession != null && session != expectedSession) {
      return (success: false, message: '账号已切换，请重新确认处罚操作');
    }
    final path =
        'forum.php?mod=modcp&action=member&op=ban&username=${Uri.encodeComponent(username)}&mobile=no';
    try {
      final source = await _get(path,
          forceRefresh: true,
          cacheTtl: Duration.zero,
          expectedSession: session);
      final form = DiscuzForm.namedSubmit(source, 'bansubmit');
      if (form == null) {
        return (
          success: false,
          message: DiscuzResponse.message(source) ?? '网站未提供对此用户的处罚表单，请检查权限'
        );
      }
      final document = html_parser.parse(source);
      final choices = document
          .querySelectorAll('[name="bannew"]')
          .expand((field) => field.localName == 'select'
              ? field
                  .querySelectorAll('option')
                  .map((option) => option.attributes['value'])
              : [field.attributes['value']])
          .toSet();
      if (!choices.contains('$banGroupId')) {
        return (success: false, message: '当前用户组没有所选处罚权限');
      }
      if (session != DioClient.sessionKey) {
        return (success: false, message: '账号已切换，请重新确认处罚操作');
      }
      final target = Uri.parse(_url(path)).resolve(form.action);
      if (target.origin != Uri.parse(AppConfig.baseUrl).origin ||
          target.queryParameters['op'] != 'ban') {
        return (success: false, message: '网站管理表单地址不匹配');
      }
      final response = await _post(
          target.toString(),
          {
            ...form.values,
            'bannew': '$banGroupId',
            'banexpirynew': '$days',
            'reason': reason,
          },
          headers: {'Referer': _url(path)},
          expectedSession: session);
      final ok =
          session == DioClient.sessionKey && DiscuzResponse.isSuccess(response);
      return (
        success: ok,
        message: DiscuzResponse.message(response) ??
            (ok ? '论坛已确认处罚操作' : '论坛尚未确认处罚结果')
      );
    } catch (error) {
      return (success: false, message: '处理失败：$error');
    }
  }

  /// 获取回复引用的官方 Discuz 结构与隐藏参数（repquote）
  static Future<
      ({
        String quoteText,
        String? noticeauthor,
        String? noticetrimstr,
        String? noticeauthormsg,
      })?> getReplyQuote({
    required int fid,
    required int tid,
    required int repquotePid,
  }) async {
    try {
      final html = await _get(
        'forum.php?mod=post&action=reply&fid=$fid&tid=$tid&repquote=$repquotePid&extra=page%3D1&page=1&mobile=no',
        headers: {
          'Referer': '${AppConfig.baseUrl}forum.php?mod=viewthread&tid=$tid',
        },
      );
      final doc = html_parser.parse(html);
      final msgEl =
          doc.querySelector('textarea#postmessage, textarea[name="message"]');
      final quoteText = msgEl?.text.trim() ?? '';
      final noticeauthor =
          doc.querySelector('input[name="noticeauthor"]')?.attributes['value'];
      final noticetrimstr =
          doc.querySelector('input[name="noticetrimstr"]')?.attributes['value'];
      final noticeauthormsg = doc
          .querySelector('input[name="noticeauthormsg"]')
          ?.attributes['value'];

      return (
        quoteText: quoteText,
        noticeauthor: noticeauthor,
        noticetrimstr: noticetrimstr,
        noticeauthormsg: noticeauthormsg,
      );
    } catch (_) {
      return null;
    }
  }

  /// 只读确认页给出当前价格、条件和真实提交字段。
  static Future<({DiscuzMedalConfirmation? confirmation, String message})>
      getMedalConfirmation(int medalId, {String? expectedSession}) async {
    final session = expectedSession ?? DioClient.sessionKey;
    if (!DioClient.isLoggedIn ||
        medalId <= 0 ||
        session != DioClient.sessionKey) {
      return (confirmation: null, message: '请先登录，并刷新勋章页面');
    }
    final page = await _get(
      'home.php?mod=medal&action=confirm&medalid=$medalId&inajax=1&mobile=no',
      forceRefresh: true,
      cacheTtl: Duration.zero,
      expectedSession: session,
    );
    final form = DiscuzForm.namedSubmit(page, 'medalsubmit');
    if (form == null || session != DioClient.sessionKey) {
      return (
        confirmation: null,
        message: session != DioClient.sessionKey
            ? '账号已切换，请重新打开勋章页面'
            : DiscuzResponse.message(page) ?? '网站未提供此勋章的领取表单'
      );
    }
    final action = Uri.parse(AppConfig.baseUrl).resolve(form.action);
    if (action.origin != Uri.parse(AppConfig.baseUrl).origin ||
        action.queryParameters['mod'] != 'medal' ||
        action.queryParameters['action'] != 'apply' ||
        int.tryParse(action.queryParameters['medalid'] ??
                form.values['medalid'] ??
                '') !=
            medalId) {
      return (confirmation: null, message: '勋章表单与当前选择不一致，请刷新后重试');
    }
    return (
      confirmation: DiscuzMedalConfirmation(
          medalId, DiscuzMedals.confirmationTerms(page), form, session),
      message: ''
    );
  }

  /// 申请/购买勋章（提交刚读取的站点表单，不构造未提供的字段）。
  static Future<({bool success, String message})> applyMedal(
    int medalId, {
    DiscuzMedalConfirmation? confirmation,
  }) async {
    try {
      if (confirmation == null) {
        final result = await getMedalConfirmation(medalId);
        if (result.confirmation == null) {
          return (success: false, message: result.message);
        }
        confirmation = result.confirmation!;
      }
      if (confirmation.session != DioClient.sessionKey ||
          confirmation.medalId != medalId) {
        return (success: false, message: '账号或勋章已改变，请重新确认');
      }
      final html = await _post(
        confirmation.form.action,
        confirmation.form.values,
        expectedSession: confirmation.session,
        headers: {
          'User-Agent': AppConfig.pcUserAgent,
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '${AppConfig.baseUrl}home.php?mod=medal',
        },
      );
      if (confirmation.session != DioClient.sessionKey) {
        return (success: false, message: '账号已切换，请刷新确认操作结果');
      }
      final success = DiscuzResponse.isSuccess(html,
          acceptedMessages: const ['已获得', '已提交申请']);
      if (success) {
        await invalidateUserProfile(expectedSession: confirmation.session);
        clearQuickCache('home.php?mod=medal');
      }
      return (
        success: success,
        message: DiscuzResponse.message(html) ??
            (success ? '勋章申请已提交' : '网站未确认申请结果，请刷新查看')
      );
    } catch (e) {
      return (success: false, message: '请求失败：$e');
    }
  }

  /// 提取楼层全量评分/打赏记录（突破 5 条限制）
  static Future<List<FloorReward>> getRatings(int tid, int pid) async {
    try {
      final html = await _get(
        'forum.php?mod=misc&action=viewratings&tid=$tid&pid=$pid&mobile=no',
      );
      final list = ComiisParser.parseRatings(html);
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// 采用 KLPBBS 当前网页提供的分类、价格和账号状态。
  static Future<KlpFacemallCatalog> getFacemallInitData(
      {bool forceRefresh = false}) async {
    final session = DioClient.sessionKey;
    final source = await _get(
        'home.php?mod=spacecp&ac=plugin&id=sunju_facemall:face&mobile=2',
        headers: {'User-Agent': AppConfig.mobileUserAgent},
        forceRefresh: forceRefresh,
        cacheTtl: const Duration(seconds: 15));
    final catalog = KlpFacemallCatalog.parse(
        source, Uri.parse(AppConfig.baseUrl),
        formhash: _extractFormhash(source));
    if (session != DioClient.sessionKey) throw StateError('账号已变化，请重新打开挂件页面');
    _observeMyFrame(catalog.myFaceUrl, session,
        avatarUrl: catalog.userAvatarUrl);
    return catalog;
  }

  static void _observeMyFrame(String? frame, String session,
      {String? avatarUrl}) {
    final uid = _cachedMyUid;
    if (session != DioClient.sessionKey || uid == null || uid <= 0) return;
    AvatarAppearanceStore.instance.useScope(session);
    AvatarAppearanceStore.instance.remember(DiscuzAvatarDeclaration(
        uid: uid,
        username: _cachedMyUsername ?? '',
        avatarUrl: avatarUrl,
        faceUrl: frame ?? ''));
  }

  /// 读取接口可以在明确拒绝后重取凭证，写操作不自动重复提交。
  static Future<Map<String, dynamic>> _facemallRequest(
    String operation, {
    Map<String, String> values = const {},
    bool readOnly = false,
    String? formhash,
    bool get = false,
  }) async {
    if (!DioClient.isLoggedIn) throw StateError('请先登录');
    final session = DioClient.sessionKey;
    var hash = formhash ?? '';
    if (!readOnly || hash.isEmpty) {
      hash =
          (await getFacemallInitData(forceRefresh: !readOnly)).formhash ?? '';
    }
    if (hash.isEmpty || session != DioClient.sessionKey) {
      throw StateError('账号或挂件页面已变化，请重新打开');
    }
    final headers = {
      'User-Agent': AppConfig.mobileUserAgent,
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': Uri.parse(AppConfig.baseUrl)
          .resolve(
              'home.php?mod=spacecp&ac=plugin&id=sunju_facemall:face&mobile=2')
          .toString()
    };
    Future<String> request() {
      final query = <String, String>{
        'id': 'sunju_facemall:ajax',
        'sjop': operation,
        'mobile': '2',
        if (get || const {'buy', 'put'}.contains(operation)) 'formhash': hash,
        if (get) ...values
      };
      final path = Uri(path: 'plugin.php', queryParameters: query).toString();
      return get
          ? _get(path,
              headers: headers, forceRefresh: true, expectedSession: session)
          : _post(
              path,
              {
                ...values,
                if (!const {'buy', 'put'}.contains(operation)) 'formhash': hash
              },
              headers: headers,
              expectedSession: session,
              invalidateCache: !readOnly);
    }

    var data = KlpFacemallResponse.decode(await request());
    if (readOnly && num.tryParse(data['code']?.toString() ?? '') == -1001) {
      hash = (await getFacemallInitData(forceRefresh: true)).formhash ?? '';
      if (hash.isEmpty || session != DioClient.sessionKey) {
        throw StateError('账号已变化，请重新打开');
      }
      data = KlpFacemallResponse.decode(await request());
    }
    if (session != DioClient.sessionKey) throw StateError('账号已切换，请重新打开挂件页面');
    return data;
  }

  static Future<List<Map<String, dynamic>>> getFacemallCategoryItems(int cateId,
          {String? formhash}) async =>
      KlpFacemallResponse.items(
          await _facemallRequest('facelist',
              values: {'s_cate': '$cateId'},
              formhash: formhash,
              readOnly: true),
          Uri.parse(AppConfig.baseUrl));

  static void _invalidateFacemall() {
    clearQuickCache('home.php?mod=spacecp&ac=plugin&id=sunju_facemall');
    PreloadService.instance.clear('user_space_');
    PreloadService.instance.clear('credit_');
  }

  static Future<bool> dropFacemall({String? formhash}) async {
    final session = DioClient.sessionKey;
    try {
      final data = await _facemallRequest('drop', formhash: formhash);
      if (!KlpFacemallResponse.succeeded(data) ||
          session != DioClient.sessionKey) {
        return false;
      }
      _invalidateFacemall();
      _observeMyFrame(null, session);
      await AppConfig.setMyFaceUrl(null);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setFacemall(String sId,
      {String? frameUrl, String? formhash}) async {
    final session = DioClient.sessionKey;
    if ((int.tryParse(sId) ?? 0) <= 0) return false;
    try {
      final data = await _facemallRequest('put',
          values: {'sj_id': sId}, formhash: formhash);
      if (!KlpFacemallResponse.succeeded(data) ||
          session != DioClient.sessionKey) {
        return false;
      }
      _invalidateFacemall();
      final frame = KlpFacemallResponse.frameUrl(
          data['data'] is String ? data['data'] as String : null,
          Uri.parse(AppConfig.baseUrl));
      if (frame != null) {
        _observeMyFrame(frame, session);
        await AppConfig.setMyFaceUrl(frame);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<({bool success, String message, String? pendantUrl})>
      buyFacemall(String sId,
          {int sDay = 30, bool sNow = true, String? formhash}) async {
    final session = DioClient.sessionKey;
    if ((int.tryParse(sId) ?? 0) <= 0 || sDay <= 0) {
      return (success: false, message: '挂件或购买天数无效', pendantUrl: null);
    }
    try {
      final data = await _facemallRequest('buy',
          formhash: formhash,
          values: {'sj_id': sId, 'sj_day': '$sDay', 'zb': sNow ? '1' : '0'});
      final success = KlpFacemallResponse.succeeded(data);
      if (session != DioClient.sessionKey) {
        return (success: false, message: '账号已变化，请刷新确认挂件购买结果', pendantUrl: null);
      }
      final frame = success
          ? KlpFacemallResponse.frameUrl(
              data['data'] is String ? data['data'] as String : null,
              Uri.parse(AppConfig.baseUrl))
          : null;
      if (success) {
        _invalidateFacemall();
        clearQuickCache('home.php?mod=spacecp&ac=credit');
        if (sNow && frame != null) {
          _observeMyFrame(frame, session);
          await AppConfig.setMyFaceUrl(frame);
        }
      }
      return (
        success: success,
        message:
            data['msg']?.toString() ?? (success ? '购买成功' : '网站未确认购买结果，请刷新查看'),
        pendantUrl: frame
      );
    } catch (error) {
      return (success: false, message: '网站未确认购买结果：$error', pendantUrl: null);
    }
  }

  static Future<List<Map<String, dynamic>>> getMyFacemallList(
      {String? formhash}) async {
    final data =
        await _facemallRequest('mylist', formhash: formhash, readOnly: true);
    if (!KlpFacemallResponse.succeeded(data) || data['data'] is! List) {
      throw StateError(data['msg']?.toString() ?? '无法取得我的挂件');
    }
    return (data['data'] as List)
        .whereType<Map>()
        .map((item) => <String, dynamic>{
              'id': item['id']?.toString() ?? '',
              's_fid': item['s_fid']?.toString() ?? '',
              'title': item['s_title']?.toString() ?? '',
              'img': KlpFacemallResponse.frameUrl(item['s_img']?.toString(),
                      Uri.parse(AppConfig.baseUrl)) ??
                  '',
              'endtime': item['s_endtime']?.toString() ?? '',
              'use': item['use']?.toString() ?? '',
            })
        .toList();
  }

  /// layui 表格默认通过 GET 分页，成功码为 0。
  static Future<List<Map<String, dynamic>>> getFacemallPayList(
          {int page = 1, String? formhash}) async =>
      (await getFacemallPayListPage(page: page, formhash: formhash)).items;

  static Future<FacemallPayListPage> getFacemallPayListPage(
      {int page = 1, int limit = 20, String? formhash}) async {
    if (page < 1 || limit < 1 || limit > 100) {
      throw const FormatException('挂件记录分页参数无效');
    }
    final data = await _facemallRequest('paylist',
        formhash: formhash,
        readOnly: true,
        get: true,
        values: {'page': '$page', 'limit': '$limit'});
    return FacemallPayListPage.parse(data, Uri.parse(AppConfig.baseUrl),
        page: page, limit: limit);
  }

  /// The category IDs, images and save form come from the selected real page.
  static Future<KlpHomeStyleCatalog> getHomeStyleCatalog(
      {String smod = '', bool forceRefresh = false}) async {
    if (smod.isNotEmpty && int.tryParse(smod) == null) {
      throw const FormatException('空间装扮分类无效');
    }
    final session = DioClient.sessionKey;
    final path = Uri(path: 'plugin.php', queryParameters: {
      'id': 'comiis_app_homestyle',
      if (smod.isNotEmpty) 'smod': smod,
      'mobile': '2',
    }).toString();
    final source = await _get(path,
        forceRefresh: forceRefresh,
        cacheTtl: const Duration(minutes: 2),
        expectedSession: session);
    _rejectRestrictedPage(source);
    final catalog = KlpHomeStyleCatalog.parse(
        source, Uri.parse(AppConfig.baseUrl),
        category: smod);
    if (!catalog.recognized) throw StateError('网站未返回该空间装扮分类');
    return catalog;
  }

  /// Compatibility for callers needing only the website-declared thumbnails.
  static Future<List<Map<String, String>>> getHomeStyles(
      {String smod = ''}) async {
    final catalog = await getHomeStyleCatalog(smod: smod);
    return [
      for (final item in catalog.items)
        {'id': item.id, 'url': item.url, 'name': item.name}
    ];
  }

  /// Submit only an ID present in the fresh category and its declared form.
  static Future<bool> saveHomeStyle(String styleId, {String smod = ''}) async {
    if (!DioClient.isLoggedIn) throw StateError('请先登录后保存空间背景');
    final session = DioClient.sessionKey;
    final catalog = await getHomeStyleCatalog(smod: smod, forceRefresh: true);
    final values = catalog.saveValues(styleId);
    if (values == null) throw StateError('背景或保存表单已变化，请刷新后重试');
    final res = await _post(
      catalog.saveForm!.action,
      values,
      expectedSession: session,
      headers: {
        'User-Agent': AppConfig.mobileUserAgent,
        'Referer': _url('plugin.php?id=comiis_app_homestyle&mobile=2'
            '${smod.isEmpty ? '' : '&smod=$smod'}'),
      },
    );
    if (!DiscuzResponse.isSuccess(res)) {
      final message = DiscuzResponse.message(res);
      if (message?.isNotEmpty == true) throw StateError(message!);
      return false;
    }
    _cachedMyUserSpace = null;
    profileChanges.value++;
    return true;
  }

  // ================= 帕帕 AI 助手 (klpbbs_ai) 接口对接 =================

  /// 初始化/拉取帕帕 AI 对话页上下文
  static Future<PapaChatContext> fetchPapaChatContext(
      {bool forceRefresh = false}) async {
    try {
      final html = await _get(
        'plugin.php?id=klpbbs_ai:chat',
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: forceRefresh,
      );

      final doc = html_parser.parse(html);

      final streamEl = doc.querySelector('[data-stream]');
      final streamUrl = streamEl?.attributes['data-stream'] ??
          RegExp(r'data-stream="([^"]+)"').firstMatch(html)?.group(1) ??
          'plugin.php?id=klpbbs_ai:stream';

      final apiEl = doc.querySelector('[data-api]');
      final apiUrl = apiEl?.attributes['data-api'] ??
          RegExp(r'data-api="([^"]+)"').firstMatch(html)?.group(1) ??
          'plugin.php?id=klpbbs_ai:api';

      final inputMaxEl = doc.querySelector('[data-inputmax]');
      final inputMax =
          int.tryParse(inputMaxEl?.attributes['data-inputmax'] ?? '') ??
              int.tryParse(
                  RegExp(r'data-inputmax="(\d+)"').firstMatch(html)?.group(1) ??
                      '') ??
              1000;

      final chatOnEl = doc.querySelector('[data-chaton]');
      final chatOnVal = chatOnEl?.attributes['data-chaton'] ??
          RegExp(r'data-chaton="([^"]+)"').firstMatch(html)?.group(1);
      final chatOn = chatOnVal != '0';

      final freeEl = doc.querySelector('[data-kai-free], .kai-free');
      final freeLeft = int.tryParse(freeEl?.attributes['data-kai-free'] ??
              freeEl?.text.trim() ??
              '') ??
          int.tryParse(
              RegExp(r'data-kai-free[^>]*>(\d+)<').firstMatch(html)?.group(1) ??
                  '') ??
          50;

      final balEl = doc.querySelector('[data-kai-balance], .kai-balance');
      final balance = int.tryParse(balEl?.attributes['data-kai-balance'] ??
              balEl?.text.trim() ??
              '') ??
          int.tryParse(RegExp(r'data-kai-balance[^>]*>(\d+)<')
                  .firstMatch(html)
                  ?.group(1) ??
              '') ??
          0;

      final fhM = _extractFormhash(html);

      Map<String, dynamic> panels = {};
      final panelsM = RegExp(r'var\s+KAI_PANELS\s*=\s*(\{.*?\});', dotAll: true)
          .firstMatch(html);
      if (panelsM != null) {
        try {
          panels = jsonDecode(panelsM.group(1)!) as Map<String, dynamic>;
        } catch (_) {}
      }

      List<Map<String, dynamic>> reports = [];
      final reportsM =
          RegExp(r'var\s+KAI_REPORTS\s*=\s*(\[.*?\]);', dotAll: true)
              .firstMatch(html);
      if (reportsM != null) {
        try {
          final decoded = jsonDecode(reportsM.group(1)!);
          if (decoded is List) {
            reports = decoded.whereType<Map<String, dynamic>>().toList();
          }
        } catch (_) {}
      }

      return PapaChatContext(
        streamUrl: streamUrl,
        apiUrl: apiUrl,
        formhash: fhM ?? '',
        freeLeft: freeLeft,
        balance: balance,
        chatOn: chatOn,
        inputMax: inputMax,
        panels: panels,
        reports: reports,
      );
    } catch (_) {
      return const PapaChatContext();
    }
  }

  /// 获取历史对话会话列表
  static Future<List<PapaConversation>> getPapaConversations(
      {String? apiUrl}) async {
    try {
      final ep = '${apiUrl ?? "plugin.php?id=klpbbs_ai:api"}&act=list';
      final jsonStr =
          await _get(ep, forceRefresh: true, cacheTtl: Duration.zero);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['ok'] == true && map['list'] is List) {
        final list = map['list'] as List;
        return list
            .map((e) => PapaConversation.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 加载指定会话的消息记录
  static Future<({String title, List<PapaMessage> messages})>
      loadPapaConversation(int convId, {String? apiUrl}) async {
    try {
      final ep =
          '${apiUrl ?? "plugin.php?id=klpbbs_ai:api"}&act=load&convid=$convId';
      final jsonStr =
          await _get(ep, forceRefresh: true, cacheTtl: Duration.zero);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['ok'] == true) {
        final title = map['title'] as String? ?? '对话';
        final rawMsgs = map['messages'] as List<dynamic>? ?? const [];
        final messages = rawMsgs
            .map((e) => PapaMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        return (title: title, messages: messages);
      }
      return (title: '', messages: const <PapaMessage>[]);
    } catch (_) {
      return (title: '', messages: const <PapaMessage>[]);
    }
  }

  /// 删除指定会话
  static Future<bool> deletePapaConversation(int convId,
      {String? apiUrl}) async {
    try {
      final ep = '${apiUrl ?? "plugin.php?id=klpbbs_ai:api"}&act=del';
      final res = await _post(
        ep,
        {'convid': convId.toString()},
        headers: {'X-Requested-With': 'XMLHttpRequest'},
      );
      final map = jsonDecode(res) as Map<String, dynamic>;
      return map['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 发起帕帕 AI 对话并返回 SSE 流 (EventStream)
  static Stream<({String event, dynamic data})> streamPapaChat({
    String? streamUrl,
    int? convId,
    required String message,
    String edition = 'auto',
    String editionMode = 'auto',
  }) async* {
    final ep = streamUrl ?? 'plugin.php?id=klpbbs_ai:stream';
    final body = {
      'convid': (convId != null && convId > 0) ? convId.toString() : '0',
      'message': message,
      'edition': edition,
      'edition_mode': editionMode,
    };

    Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        _url(ep),
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': _url('plugin.php?id=klpbbs_ai:chat'),
            'User-Agent': AppConfig.pcUserAgent,
          },
        ),
      );
    } catch (e) {
      yield (event: 'failed', data: {'message': '网络连接异常：$e'});
      return;
    }

    final responseStream = response.data?.stream;
    if (responseStream == null) {
      yield (event: 'failed', data: {'message': '未获取到响应流'});
      return;
    }

    String buffer = '';
    await for (final chunk in responseStream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      final parts = buffer.split('\n\n');
      buffer = parts.removeLast();

      for (final p in parts) {
        if (p.trim().isEmpty) continue;
        String event = '';
        String dataStr = '';
        for (final line in p.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('event:')) {
            event = trimmed.substring(6).trim();
          } else if (trimmed.startsWith('data:')) {
            dataStr += trimmed.substring(5).trim();
          }
        }
        if (event.isNotEmpty) {
          dynamic parsed;
          try {
            parsed = jsonDecode(dataStr);
          } catch (_) {
            parsed = {'raw': dataStr};
          }
          yield (event: event, data: parsed);
        }
      }
    }

    if (buffer.trim().isNotEmpty) {
      String event = '';
      String dataStr = '';
      for (final line in buffer.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('event:')) {
          event = trimmed.substring(6).trim();
        } else if (trimmed.startsWith('data:')) {
          dataStr += trimmed.substring(5).trim();
        }
      }
      if (event.isNotEmpty) {
        dynamic parsed;
        try {
          parsed = jsonDecode(dataStr);
        } catch (_) {
          parsed = {'raw': dataStr};
        }
        yield (event: event, data: parsed);
      }
    }
  }

  /// 获取报告列表
  static Future<List<PapaReport>> getPapaReports({String? apiUrl}) async {
    try {
      final ep = '${apiUrl ?? "plugin.php?id=klpbbs_ai:api"}&act=reports';
      final jsonStr =
          await _get(ep, forceRefresh: true, cacheTtl: Duration.zero);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['ok'] == true && map['list'] is List) {
        final list = map['list'] as List;
        return list
            .map((e) => PapaReport.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 读取某一份具体报告详情
  static Future<PapaReport?> loadPapaReport(int rid, {String? apiUrl}) async {
    try {
      final ep =
          '${apiUrl ?? "plugin.php?id=klpbbs_ai:api"}&act=report&rid=$rid';
      final jsonStr =
          await _get(ep, forceRefresh: true, cacheTtl: Duration.zero);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['ok'] == true && map['report'] is Map<String, dynamic>) {
        return PapaReport.fromJson(map['report'] as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 生成智能报告（SSE 流式）
  static Stream<({String event, dynamic data})> streamPapaGenerateReport(
    String streamUrl, {
    bool regen = false,
  }) async* {
    final urlWithParams =
        '$streamUrl${regen ? "&regen=1" : ""}&_=${DateTime.now().millisecondsSinceEpoch}';
    Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        _url(urlWithParams),
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Accept': 'text/event-stream',
            'Referer': _url('plugin.php?id=klpbbs_ai:chat'),
            'User-Agent': AppConfig.pcUserAgent,
          },
        ),
      );
    } catch (e) {
      yield (event: 'failed', data: {'message': '网络连接异常：$e'});
      return;
    }

    final responseStream = response.data?.stream;
    if (responseStream == null) {
      yield (event: 'failed', data: {'message': '未获取到响应流'});
      return;
    }

    String buffer = '';
    await for (final chunk in responseStream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      final parts = buffer.split('\n\n');
      buffer = parts.removeLast();

      for (final p in parts) {
        if (p.trim().isEmpty) continue;
        String event = '';
        String dataStr = '';
        for (final line in p.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('event:')) {
            event = trimmed.substring(6).trim();
          } else if (trimmed.startsWith('data:')) {
            dataStr += trimmed.substring(5).trim();
          }
        }
        if (event.isNotEmpty) {
          dynamic parsed;
          try {
            parsed = jsonDecode(dataStr);
          } catch (_) {
            parsed = {'raw': dataStr};
          }
          yield (event: event, data: parsed);
        }
      }
    }
  }

  /// 获取帕帕 AI 积分钱包数据
  static Future<PapaWallet> getPapaWallet() async {
    try {
      final html = await _get(
        'plugin.php?id=klpbbs_ai:wallet',
        headers: {'User-Agent': AppConfig.pcUserAgent},
        forceRefresh: true,
      );

      final doc = html_parser.parse(html);

      // 提取免费点数与总额
      int freeLeft = 50;
      int freeTotal = 50;
      final freeEl = doc.querySelector('[data-kai-free], .kai-free');
      if (freeEl != null) {
        final val = int.tryParse(
            freeEl.attributes['data-kai-free'] ?? freeEl.text.trim());
        if (val != null) freeLeft = val;
      } else {
        final freeM = RegExp(r'data-kai-free[^>]*>(\d+)<').firstMatch(html);
        if (freeM != null) freeLeft = int.tryParse(freeM.group(1)!) ?? 50;
      }
      final freeTotalM = RegExp(r'/\s*(\d+)').firstMatch(html);
      if (freeTotalM != null) {
        freeTotal = int.tryParse(freeTotalM.group(1)!) ?? 50;
      }

      // 提取火药余额
      int balance = 0;
      final balEl = doc.querySelector('[data-kai-balance], .kai-balance');
      if (balEl != null) {
        final val = int.tryParse(
            balEl.attributes['data-kai-balance'] ?? balEl.text.trim());
        if (val != null) balance = val;
      } else {
        final balM = RegExp(r'data-kai-balance[^>]*>(\d+)<').firstMatch(html);
        if (balM != null) balance = int.tryParse(balM.group(1)!) ?? 0;
      }

      // 兑换最低数量
      int exchangeMin = 1;
      final minEl = doc.querySelector('#kai-amount, input[name="amount"]');
      if (minEl != null) {
        final val = int.tryParse(minEl.attributes['min'] ?? '');
        if (val != null && val > 0) exchangeMin = val;
      }

      // 解析兑换比率
      final rates = <PapaExchangeRate>[];
      for (final opt in doc.querySelectorAll(
          'select#kai-credits option, select option[data-rate], select option[value]')) {
        final valStr = opt.attributes['value'] ?? '';
        final src = int.tryParse(valStr) ?? 0;
        final rateStr = opt.attributes['data-rate'] ?? '';
        final rate = int.tryParse(rateStr) ?? 0;
        final title = opt.text.trim();
        if (src > 0 || rate > 0) {
          final haveM = RegExp(r'有\s*(\d+)').firstMatch(title);
          final have = haveM != null ? int.tryParse(haveM.group(1)!) ?? 0 : 0;
          rates.add(
              PapaExchangeRate(src: src, title: title, have: have, rate: rate));
        }
      }

      // 解析计费表
      final prices = <PapaPriceItem>[];
      for (final pEl in doc.querySelectorAll('.kai-price .p, .p')) {
        final span = pEl.querySelector('span');
        final b = pEl.querySelector('b');
        if (span != null && b != null) {
          prices
              .add(PapaPriceItem(name: span.text.trim(), price: b.text.trim()));
        }
      }

      // 解析流水明细
      final logs = <PapaCreditLog>[];
      final liElements = doc.querySelectorAll('.kai-flow li');
      for (final li in liElements) {
        final time = li.querySelector('.time')?.text.trim() ?? '';
        final name = li.querySelector('.name')?.text.trim() ?? '';
        final amt = li.querySelector('.amt')?.text.trim() ?? '';
        final remark = li.querySelector('.remark')?.text.trim() ?? '';
        final isPending = li.querySelector('.kai-chip.warn') != null;
        if (time.isNotEmpty || name.isNotEmpty) {
          logs.add(PapaCreditLog(
            time: time,
            name: name,
            amount: amt,
            isIncome: amt.startsWith('+'),
            isPending: isPending,
            remark: remark,
          ));
        }
      }

      return PapaWallet(
        freeLeft: freeLeft,
        freeTotal: freeTotal,
        balance: balance,
        exchangeOn: html.contains('kai_exchangesubmit') ||
            doc.querySelector('form[name="kai_exchange"]') != null,
        exchangeMin: exchangeMin,
        rates: rates,
        prices: prices,
        logs: logs,
      );
    } catch (_) {
      return const PapaWallet();
    }
  }

  /// 兑换火药
  static Future<({bool success, String message})> exchangePapaGunpowder({
    required int srcCredit,
    required int amount,
    required String formhash,
  }) async {
    try {
      final res = await _post(
        'plugin.php?id=klpbbs_ai:wallet',
        {
          'formhash': formhash,
          'kai_exchangesubmit': 'yes',
          'srccredit': srcCredit.toString(),
          'amount': amount.toString(),
          'kai_exchange': 'true',
        },
        headers: {
          'Referer': _url('plugin.php?id=klpbbs_ai:wallet'),
          'User-Agent': AppConfig.pcUserAgent,
        },
      );
      if (res.contains('成功') || res.contains('兑换成功')) {
        return (success: true, message: '火药兑换成功！');
      }
      final msg = _extractDiscuzResponseMessage(res, defaultMsg: '兑换已提交');
      return (success: true, message: msg);
    } catch (e) {
      return (success: false, message: '兑换失败：$e');
    }
  }

  /// 清除 AI 记忆
  static Future<({bool success, String message})> clearPapaMemory(
      String formhash) async {
    try {
      await _post(
        'plugin.php?id=klpbbs_ai:wallet',
        {
          'formhash': formhash,
          'kai_clear_memory': 'true',
        },
        headers: {
          'Referer': _url('plugin.php?id=klpbbs_ai:wallet'),
          'User-Agent': AppConfig.pcUserAgent,
        },
      );
      return (success: true, message: '记忆已成功清除！');
    } catch (e) {
      return (success: false, message: '清除记忆失败：$e');
    }
  }
}
