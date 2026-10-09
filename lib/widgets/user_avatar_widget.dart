import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/app_config.dart';
import '../core/cache_manager.dart';
import '../core/dio_client.dart';
import '../core/klpbbs_facemall.dart';
import '../core/user_avatar_presentation.dart';
import '../core/discuz_avatar_declaration.dart';
import '../services/avatar_appearance_store.dart';
import 'app_motion.dart';
import 'avatar_shape_clip.dart';
import 'facemall_frame_widget.dart';

/// Actual UCenter avatar with the separately declared sunju_facemall pendant.
class UserAvatarWidget extends StatelessWidget {
  final int? uid;
  final String author;
  final String? avatarUrl;
  final double size;
  final String? faceUrl;
  final bool? isOnline;
  final bool showOnlineBadge;
  final VoidCallback? onTap;

  /// Allocate the pendant's extent, including the selected avatar outline,
  /// so it cannot overlap neighboring text.
  /// Keep the same slot for users with and without a pendant. Otherwise a
  /// mixed feed indents framed authors and changes row heights asynchronously.
  /// False preserves existing callers that already reserve exterior spacing.
  final bool reserveFrameSpace;

  /// Pendant previews can deliberately override the currently worn frame.
  final bool useObservedAppearance;

  const UserAvatarWidget({
    super.key,
    this.uid,
    this.author = '',
    this.avatarUrl,
    this.size = 20,
    this.faceUrl,
    this.isOnline,
    this.showOnlineBadge = false,
    this.onTap,
    this.reserveFrameSpace = false,
    this.useObservedAppearance = true,
  });

  static String? sanitizeFaceUrl(String? rawUrl) =>
      KlpFacemallResponse.frameUrl(rawUrl, Uri.parse(AppConfig.baseUrl));

  /// Only website-declared default avatars belong here, never request failures.
  static final Set<int> knownDefaultAvatarUids = <int>{};
  static void clearDefaultAvatarCache() => knownDefaultAvatarUids.clear();

  /// Older models use empty strings when their template omitted a pendant.
  /// Omission may use a previously observed declaration for the same UID.
  static String? optionalFrame(String? value) =>
      value?.isNotEmpty == true ? value : null;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: AppConfig.instance,
      builder: (context, _) => _buildForSettings(context));

  Widget _buildForSettings(BuildContext context) {
    final effectiveUid = author == '匿名'
        ? null
        : uid != null && uid! > 0
            ? uid
            : DiscuzAvatarDeclarations.uidFromAvatar(
                    avatarUrl, Uri.parse(AppConfig.baseUrl)) ??
                KlpbbsApi.getCachedAuthorUid(author);
    if (effectiveUid == null) return _buildAvatar(context, null, null);
    final rawHasFrame = avatarUrl?.contains('##SJ##') == true;
    return _AvatarAppearanceObserver(
        uid: effectiveUid,
        enabled: useObservedAppearance &&
            AppConfig.imageQuality != ImageQuality.noImage &&
            faceUrl == null &&
            !rawHasFrame,
        child: ValueListenableBuilder<DiscuzAvatarDeclaration?>(
            valueListenable:
                AvatarAppearanceStore.instance.listenable(effectiveUid),
            builder: (context, declaration, _) =>
                _buildAvatar(context, effectiveUid, declaration)));
  }

  Widget _buildAvatar(BuildContext context, int? effectiveUid,
      DiscuzAvatarDeclaration? declaration) {
    final scheme = Theme.of(context).colorScheme;
    final base = Uri.parse(AppConfig.baseUrl);
    final observed = useObservedAppearance ? declaration : null;
    final explicitAvatar = UserAvatarPresentation.avatarUrl(avatarUrl, base);
    final isDefault = explicitAvatar == null &&
        observed?.avatarUrl == null &&
        effectiveUid != null &&
        knownDefaultAvatarUids.contains(effectiveUid);
    final resolvedAvatar = isDefault
        ? null
        : observed?.avatarUrl ??
            explicitAvatar ??
            (effectiveUid != null && effectiveUid > 0
                ? AppConfig.avatarUrl(effectiveUid,
                    size: size >= 32 ? 'middle' : 'small')
                : null);
    final isMe = UserAvatarPresentation.isCurrentUser(
      loggedIn: DioClient.isLoggedIn,
      uid: effectiveUid,
      currentUid: KlpbbsApi.currentCachedMyUid,
      author: author,
      currentUsername: KlpbbsApi.currentCachedMyUsername,
    );
    final cachedSpace = KlpbbsApi.cachedSpace;
    final candidateFrame = UserAvatarPresentation.frameUrl(
      base: base,
      declaredFrame: observed?.faceUrl ?? faceUrl,
      avatarSource: avatarUrl,
      isCurrentUser: isMe,
      currentFrame: AppConfig.myFaceUrl,
      cachedCurrentFrame:
          cachedSpace?.uid == effectiveUid ? cachedSpace?.faceUrl : null,
      cachedDeclaredFrame: observed?.faceUrl,
    );
    // A mistakenly repeated avatar URL must never become a huge overlay.
    final frame = candidateFrame == resolvedAvatar ? null : candidateFrame;
    final showImages = AppConfig.imageQuality != ImageQuality.noImage;
    final hasFrame = frame != null && showImages;
    final frameSize = size *
        UserAvatarPresentation.frameScale *
        AvatarShapeClip.frameOutlineScale(AppConfig.avatarShape);
    final extent = reserveFrameSpace && showImages ? frameSize : size;
    final inset = (extent - size) / 2;

    Widget initials({bool loading = false}) => ColoredBox(
        color:
            loading ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        child: Center(
            child: Padding(
                padding: EdgeInsets.all(size * .1),
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(author.isEmpty ? '?' : author.characters.first,
                        style: TextStyle(
                            fontSize: size * .45,
                            fontWeight: FontWeight.w600,
                            color: loading
                                ? scheme.primary
                                : scheme.onPrimaryContainer))))));
    final image = resolvedAvatar != null && showImages
        ? CachedNetworkImage(
            imageUrl: resolvedAvatar,
            cacheKey: KlpbbsCacheManager.normalizeCacheKey(resolvedAvatar),
            cacheManager: KlpbbsCacheManager.instance,
            httpHeaders: AppConfig.imageHeadersFor(resolvedAvatar),
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                .clamp(48, 256)
                .round(),
            fadeInDuration:
                AppMotion.duration(context, 140, scope: MotionScope.loading),
            fadeOutDuration: Duration.zero,
            placeholder: (_, __) => initials(loading: true),
            errorWidget: (_, __, ___) => initials(loading: true),
          )
        : initials();
    final avatar =
        AvatarShapeClip(shape: AppConfig.avatarShape, size: size, child: image);
    final result = SizedBox(
        width: extent,
        height: extent,
        child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              avatar,
              if (hasFrame)
                Positioned(
                    left: (extent - frameSize) / 2,
                    top: (extent - frameSize) / 2,
                    width: frameSize,
                    height: frameSize,
                    child: IgnorePointer(
                        key: const ValueKey('avatar-frame-artwork'),
                        child: FacemallFrameWidget(
                            frameIdOrUrl: frame, size: frameSize))),
              if (showOnlineBadge && isOnline == true)
                Positioned(
                    right: inset,
                    bottom: inset,
                    child: Container(
                        width: size >= 36 ? 10.5 : 8,
                        height: size >= 36 ? 10.5 : 8,
                        decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: scheme.surface,
                                width: size >= 36 ? 2 : 1.5))))
            ]));
    return Semantics(
        image: true,
        label: author.isEmpty ? '用户头像' : '$author的头像',
        button: onTap != null,
        excludeSemantics: true,
        child: onTap == null
            ? FittedBox(fit: BoxFit.scaleDown, child: result)
            : GestureDetector(
                onTap: onTap,
                child: FittedBox(fit: BoxFit.scaleDown, child: result)));
  }
}

/// Resolve an omitted field after painting, rather than performing network IO
/// in build. Hidden routes, pendant previews and fast scrolling do not enqueue
/// queries. Shared UID resolution also lets a whole horn batch satisfy them.
class _AvatarAppearanceObserver extends StatefulWidget {
  final int uid;
  final bool enabled;
  final Widget child;
  const _AvatarAppearanceObserver(
      {required this.uid, required this.enabled, required this.child});

  @override
  State<_AvatarAppearanceObserver> createState() =>
      _AvatarAppearanceObserverState();
}

class _AvatarAppearanceObserverState extends State<_AvatarAppearanceObserver> {
  String? _requested;
  bool _scheduled = false;
  Timer? _scrollDelay;

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    _requested = null;
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(_AvatarAppearanceObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) _requested = null;
    _schedule();
  }

  void _schedule() {
    if (!widget.enabled ||
        _scheduled ||
        _scrollDelay != null ||
        !TickerMode.of(context)) {
      return;
    }
    final key = '${widget.uid}|${DioClient.sessionKey}';
    if (_requested == key) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !widget.enabled || !TickerMode.of(context)) return;
      if (Scrollable.recommendDeferredLoadingForContext(context)) {
        _scrollDelay = Timer(const Duration(milliseconds: 180), () {
          _scrollDelay = null;
          if (mounted) _schedule();
        });
        return;
      }
      final currentKey = '${widget.uid}|${DioClient.sessionKey}';
      if (_requested == currentKey) return;
      _requested = currentKey;
      unawaited(KlpbbsApi.resolveAvatarAppearance(widget.uid).then((value) {
        if (mounted && _requested == currentKey && value?.faceUrl == null) {
          // A failed read can retry on a later rebuild; the coordinator keeps
          // its backoff, so theme/layout rebuilds cannot storm the endpoint.
          _requested = null;
        }
      }));
    });
  }

  @override
  void dispose() {
    _scrollDelay?.cancel();
    DioClient.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
