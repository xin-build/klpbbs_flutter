import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../core/dio_client.dart';
import '../models/sign_entry.dart';
import '../pages/user_space_page.dart';
import 'app_motion.dart';
import 'user_avatar_widget.dart';

/// The daily first signer declared by k_misign, never the latest rank row.
class TodaySignStar extends StatefulWidget {
  final SignHeaderInfo? info;
  final bool loading;
  final VoidCallback? onRetry;
  final bool isPreview;
  final bool compact;
  const TodaySignStar(
      {super.key,
      this.info,
      this.loading = false,
      this.onRetry,
      this.isPreview = false,
      this.compact = false});

  @override
  State<TodaySignStar> createState() => _TodaySignStarState();
}

class _TodaySignStarState extends State<TodaySignStar> {
  int _request = 0;
  int? _resolvedUid;
  String? _avatar, _frame;
  String get _name => widget.info?.starUsername ?? '';

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_sessionChanged);
    _resolve();
  }

  @override
  void didUpdateWidget(covariant TodaySignStar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info?.starUsername != _name ||
        oldWidget.info?.starUid != widget.info?.starUid ||
        oldWidget.info?.starAvatarUrl != widget.info?.starAvatarUrl ||
        oldWidget.info?.starFaceUrl != widget.info?.starFaceUrl ||
        oldWidget.isPreview != widget.isPreview) {
      _resolve();
    }
  }

  void _sessionChanged() {
    _request++;
    if (mounted) {
      setState(() {
        _resolvedUid = null;
        _avatar = null;
        _frame = null;
      });
    }
  }

  void _resolve() {
    final request = ++_request;
    final name = _name, session = DioClient.sessionKey;
    _resolvedUid = widget.info?.starUid ?? KlpbbsApi.getCachedAuthorUid(name);
    _avatar = widget.info?.starAvatarUrl;
    _frame = widget.info?.starFaceUrl;
    if (name.isEmpty || _resolvedUid != null || widget.isPreview) return;
    unawaited(KlpbbsApi.resolvePublicUserIdentity(name).then((identity) {
      if (!mounted ||
          request != _request ||
          name != _name ||
          session != DioClient.sessionKey ||
          identity == null) {
        return;
      }
      setState(() {
        _resolvedUid = identity.uid;
        _avatar = identity.avatarUrl;
        _frame = identity.faceUrl;
      });
    }).catchError((Object _) {}));
  }

  @override
  void dispose() {
    _request++;
    DioClient.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = _name;
    return Align(
      alignment: Alignment.centerLeft,
      heightFactor: 1,
      child: Material(
        key: const ValueKey('today-sign-star'),
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.isPreview || name.isEmpty
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      UserSpacePage(uid: _resolvedUid, username: name))),
          child: LayoutBuilder(builder: (context, box) {
            final scaler = MediaQuery.textScalerOf(context);
            final labelHeight = scaler.scale(12) * 1.45;
            final titleHeight = scaler.scale(16) * 1.45;
            final fullHeight = labelHeight * 2 + titleHeight * 2 + 35;
            final short = widget.compact ||
                (box.hasBoundedHeight && box.maxHeight < fullHeight);
            final tiny = short &&
                box.hasBoundedHeight &&
                box.maxHeight < labelHeight + scaler.scale(14) * 1.45 + 15;
            final avatarSize = tiny
                ? 22.0
                : short
                    ? widget.compact
                        ? 36.0
                        : 28.0
                    : widget.compact
                        ? 36.0
                        : 44.0;
            final verticalPadding = tiny
                ? 2.0
                : short
                    ? 6.0
                    : 12.0;
            final maxAvatarExtent = box.hasBoundedHeight
                ? math.max(0.0, box.maxHeight - verticalPadding * 2)
                : double.infinity;
            final title = name.isNotEmpty
                ? name
                : widget.loading
                    ? '正在读取签到榜首'
                    : '暂未取得今日榜首';
            return Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: short ? 10 : 16, vertical: verticalPadding),
                child: Row(children: [
                  if (name.isNotEmpty)
                    ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight: maxAvatarExtent,
                            maxWidth:
                                math.min(maxAvatarExtent, box.maxWidth * .35)),
                        child: UserAvatarWidget(
                            uid: _resolvedUid,
                            author: name,
                            avatarUrl: _avatar,
                            faceUrl: _frame,
                            size: avatarSize,
                            reserveFrameSpace: true))
                  else
                    Icon(Icons.emoji_events_outlined,
                        size: avatarSize, color: scheme.tertiary),
                  SizedBox(width: short ? 8 : 12),
                  Expanded(
                      child: AnimatedSwitcher(
                          duration: AppMotion.duration(context, 200,
                              scope: MotionScope.panels),
                          layoutBuilder: (current, previous) =>
                              Stack(alignment: Alignment.centerLeft, children: [
                                ...previous,
                                if (current != null) current,
                              ]),
                          child: Column(
                              key: ValueKey('$name|$_resolvedUid'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!tiny)
                                  Text('今日之星',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                              color: scheme.onSurfaceVariant)),
                                if (!tiny) const SizedBox(height: 3),
                                Text(
                                    tiny && name.isNotEmpty
                                        ? '今日之星 · $name'
                                        : title,
                                    key: const ValueKey('today-sign-star-name'),
                                    maxLines: short ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: (short
                                            ? Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                            : Theme.of(context)
                                                .textTheme
                                                .titleMedium)
                                        ?.copyWith(
                                            fontWeight: FontWeight.w600)),
                                if (!short && name.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                      spacing: 5,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Icon(Icons.emoji_events_rounded,
                                            size: 16, color: scheme.tertiary),
                                        Text('今日首位签到',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                    color: scheme.tertiary)),
                                      ]),
                                ],
                              ]))),
                  if (name.isEmpty &&
                      widget.onRetry != null &&
                      !widget.isPreview &&
                      !widget.loading)
                    IconButton(
                        onPressed: widget.onRetry,
                        tooltip: '重试读取',
                        icon: const Icon(Icons.refresh_rounded)),
                ]));
          }),
        ),
      ),
    );
  }
}
