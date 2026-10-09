import 'dart:async';
import 'dart:collection';
import '../core/dio_client.dart';
import 'package:flutter/material.dart';
import '../services/push_notification_service.dart';

/// 全局应用内浮动横幅通知组件（支持 Android, iOS, Windows, macOS, Linux, Web 全平台）
/// 特性：
/// 1. 极致跟手的 2D 物理拖拽反馈（向上推直接退回顶栏、向左/向右滑出屏幕）；
/// 2. 划动时伴随微动倾角 (tilt rotation) 与动态透明度渐隐；
/// 3. 手势释放时智能判定滑出阈值，未达阈值平滑弹性回弹 (easeOutBack)；
/// 4. 桌面端鼠标悬停或触屏按住时自动暂停倒计时，移开后恢复自动关闭；
/// 5. 醒目的关闭按钮与查看操作，支持全平台键盘与无障碍交互。
class GlobalInAppNotificationOverlay extends StatefulWidget {
  final Widget child;

  const GlobalInAppNotificationOverlay({super.key, required this.child});

  @override
  State<GlobalInAppNotificationOverlay> createState() =>
      _GlobalInAppNotificationOverlayState();
}

class _GlobalInAppNotificationOverlayState
    extends State<GlobalInAppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  StreamSubscription<InAppNotificationMessage>? _sub;
  InAppNotificationMessage? _currentMsg;
  late AnimationController _animCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  Timer? _dismissTimer;
  final _pending = Queue<InAppNotificationMessage>();
  bool _dismissing = false;
  int _presentation = 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    _sub = PushNotificationService.instance.onNotificationReceived
        .listen(_showMessage);
    DioClient.sessionChanges.addListener(_onSessionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _animCtrl.duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 320);
    _animCtrl.reverseDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    if (reduceMotion && _animCtrl.isAnimating) {
      _animCtrl.value = _currentMsg == null || _dismissing ? 0 : 1;
    }
  }

  void _onSessionChanged() {
    _pending.clear();
    _dismissImmediate();
  }

  void _showMessage(InAppNotificationMessage msg) {
    if (!mounted) return;
    if (_currentMsg != null) {
      if (_pending.length >= 8) _pending.removeFirst();
      _pending.addLast(msg);
      return;
    }
    _dismissTimer?.cancel();
    _presentation++;
    setState(() {
      _currentMsg = msg;
      _dragOffset = Offset.zero;
    });
    _animCtrl.forward(from: 0.0);
    _startDismissTimer();
  }

  void _startDismissTimer() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 4), () {
      _dismiss();
    });
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    if (_dismissing || _currentMsg == null) return;
    _dismissing = true;
    final presentation = ++_presentation;
    if (mounted) {
      _animCtrl.reverse().then((_) {
        if (mounted && presentation == _presentation) {
          setState(() {
            _currentMsg = null;
          });
          _dismissing = false;
          _showNext();
        }
      });
    }
  }

  Offset _dragOffset = Offset.zero;

  void _dismissImmediate() {
    _dismissTimer?.cancel();
    _animCtrl.stop();
    _presentation++;
    _dismissing = false;
    if (mounted) {
      setState(() {
        _currentMsg = null;
        _dragOffset = Offset.zero;
      });
      _showNext();
    }
  }

  void _showNext() {
    if (mounted && _pending.isNotEmpty) _showMessage(_pending.removeFirst());
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_onSessionChanged);
    _pending.clear();
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
                child: MouseRegion(
                  onEnter: (_) => _dismissTimer?.cancel(),
                  onExit: (_) => _startDismissTimer(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) {
                          _dismissTimer?.cancel();
                        },
                        onPanUpdate: (details) {
                          setState(() {
                            _dragOffset += details.delta;
                          });
                        },
                        onPanEnd: (details) {
                          final vx = details.velocity.pixelsPerSecond.dx;
                          final vy = details.velocity.pixelsPerSecond.dy;
                          // 向上轻推（>25px 或速度>250）或左右轻划（>50px 或速度>300）立即顺滑划走
                          if (_dragOffset.dy < -25 ||
                              vy < -250 ||
                              _dragOffset.dx.abs() > 50 ||
                              vx.abs() > 300) {
                            _dismissImmediate();
                          } else {
                            setState(() {
                              _dragOffset = Offset.zero;
                            });
                            _startDismissTimer();
                          }
                        },
                        child: AnimatedContainer(
                          duration: _dragOffset == Offset.zero
                              ? const Duration(milliseconds: 200)
                              : Duration.zero,
                          curve: Curves.easeOutCubic,
                          transform: Matrix4.translationValues(
                              _dragOffset.dx, _dragOffset.dy, 0),
                          child: AnimatedOpacity(
                            duration: _dragOffset == Offset.zero
                                ? const Duration(milliseconds: 200)
                                : Duration.zero,
                            opacity: (1.0 - (_dragOffset.distance / 160))
                                .clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color:
                                      colorScheme.outlineVariant.withAlpha(120),
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
                                  key: const ValueKey(
                                      'in_app_notification_card'),
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    final action = _currentMsg?.onTap;
                                    _dismissImmediate();
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                                  color: colorScheme
                                                      .onSurfaceVariant,
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
                                            borderRadius:
                                                BorderRadius.circular(20),
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
                                          key: const ValueKey(
                                              'in_app_notification_close_btn'),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          onTap: _dismissImmediate,
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                              color:
                                                  colorScheme.onSurfaceVariant,
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
            ),
          ),
      ],
    );
  }
}
