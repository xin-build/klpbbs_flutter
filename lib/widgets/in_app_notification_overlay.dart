import 'dart:async';
import 'package:flutter/material.dart';
import '../services/push_notification_service.dart';

/// 全局应用内浮动横幅通知组件（支持 Android, iOS, Windows, macOS, Linux, Web 全平台）
class GlobalInAppNotificationOverlay extends StatefulWidget {
  final Widget child;

  const GlobalInAppNotificationOverlay({super.key, required this.child});

  @override
  State<GlobalInAppNotificationOverlay> createState() => _GlobalInAppNotificationOverlayState();
}

class _GlobalInAppNotificationOverlayState extends State<GlobalInAppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  StreamSubscription<InAppNotificationMessage>? _sub;
  InAppNotificationMessage? _currentMsg;
  late AnimationController _animCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 220),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    _sub = PushNotificationService.instance.onNotificationReceived.listen(_showMessage);
  }

  void _showMessage(InAppNotificationMessage msg) {
    if (!mounted) return;
    _dismissTimer?.cancel();
    setState(() {
      _currentMsg = msg;
    });
    _animCtrl.forward();

    _dismissTimer = Timer(const Duration(seconds: 4), () {
      _dismiss();
    });
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    if (mounted && _animCtrl.status != AnimationStatus.dismissed) {
      _animCtrl.reverse().then((_) {
        if (mounted) {
          setState(() {
            _currentMsg = null;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _sub?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        widget.child,
        if (_currentMsg != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 16,
            right: 16,
            child: SlideTransition(
              position: _slideAnim,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Material(
                  color: Colors.transparent,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: GestureDetector(
                        onHorizontalDragEnd: (details) {
                          if ((details.primaryVelocity?.abs() ?? 0) > 100) {
                            _dismiss();
                          }
                        },
                        onVerticalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) < -80) {
                            _dismiss();
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withAlpha(120),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const ValueKey('in_app_notification_card'),
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                final action = _currentMsg?.onTap;
                                _dismiss();
                                action?.call();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.notifications_active_rounded,
                                        color: colorScheme.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _currentMsg!.title,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.onSurface,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _currentMsg!.body,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        '查看',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      key: const ValueKey('in_app_notification_close_btn'),
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: _dismiss,
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
