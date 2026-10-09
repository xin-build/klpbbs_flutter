import 'package:flutter/material.dart';
import '../../api/klpbbs_api.dart';
import '../../core/app_config.dart';
import '../../core/dio_client.dart';
import '../../models/dashboard_card_model.dart';
import '../../models/user_space.dart';
import '../../pages/credit_page.dart';
import '../../pages/login_page.dart';
import '../../pages/magic_page.dart';
import '../../pages/user_space_page.dart';
import '../thread_card.dart';
import 'dashboard_card_frame.dart';

/// 14. 个人空间名片卡片（对接真实登录 UID、用户名、用户组与头像，支持 GPU 隔离与 LOD 尺寸自适应）
class UserProfileDashboardCard extends StatefulWidget {
  final DashboardGridItem item;
  final bool isPreview;

  const UserProfileDashboardCard({
    super.key,
    required this.item,
    this.isPreview = false,
  });

  @override
  State<UserProfileDashboardCard> createState() =>
      _UserProfileDashboardCardState();
}

class _UserProfileDashboardCardState extends State<UserProfileDashboardCard> {
  int? _uid;
  UserSpace? _space;
  int _profileGeneration = 0;

  @override
  void initState() {
    super.initState();
    _readCurrentProfile();
    DioClient.sessionChanges.addListener(_onProfileChanged);
    KlpbbsApi.profileChanges.addListener(_onProfileChanged);
    if (DioClient.isLoggedIn && !widget.isPreview) {
      _loadProfile();
    }
  }

  @override
  void dispose() {
    DioClient.sessionChanges.removeListener(_onProfileChanged);
    KlpbbsApi.profileChanges.removeListener(_onProfileChanged);
    _profileGeneration++;
    super.dispose();
  }

  void _readCurrentProfile() {
    _uid = DioClient.isLoggedIn ? KlpbbsApi.currentCachedMyUid : null;
    final space = KlpbbsApi.cachedSpace;
    _space = _uid != null && space?.uid == _uid ? space : null;
  }

  void _onProfileChanged() {
    if (!mounted) return;
    _profileGeneration++;
    setState(_readCurrentProfile);
    if (DioClient.isLoggedIn && !widget.isPreview) _loadProfile();
  }

  Future<void> _loadProfile() async {
    final session = DioClient.sessionKey;
    final generation = ++_profileGeneration;
    bool current() =>
        mounted &&
        session == DioClient.sessionKey &&
        generation == _profileGeneration;
    try {
      final uid = await KlpbbsApi.getMyUid();
      if (!current()) return;
      if (uid != null && uid > 0) {
        final space = await KlpbbsApi.getUserSpace(uid);
        if (current() && space?.uid == uid) {
          setState(() {
            _uid = uid;
            _space = space;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final customTitle = widget.item.customParams['customTitle'] as String?;
    final title =
        (customTitle != null && customTitle.isNotEmpty) ? customTitle : '个人名片';

    final rawDataStyle =
        widget.item.customParams['dataStyle'] as String? ?? 'auto';
    final String dataStyle;
    if (rawDataStyle == 'auto') {
      final isCompact = widget.item.rowSpan <= 1;
      final isNarrow = widget.item.colSpan <= 2;
      dataStyle = (isCompact || isNarrow) ? 'compact' : 'detailed';
    } else {
      dataStyle = rawDataStyle;
    }

    final isLoggedIn = DioClient.isLoggedIn;
    final username = _space?.username.isNotEmpty == true
        ? _space!.username
        : (isLoggedIn ? (_uid != null ? 'UID: $_uid' : '已登录') : '未登录访客');
    final role = _space?.group.isNotEmpty == true
        ? _space!.group
        : (_space?.level.isNotEmpty == true
            ? _space!.level
            : (isLoggedIn ? '资料尚未取得' : '点击登录'));

    return RepaintBoundary(
      child: DashboardCardFrame(
        item: widget.item,
        padding: const EdgeInsets.all(12),
        onTap: () async {
          if (!isLoggedIn) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginPage()),
            );
            return;
          }
          final session = DioClient.sessionKey;
          final targetUid = _uid ?? await KlpbbsApi.getMyUid();
          if (targetUid == null || targetUid <= 0) return;
          if (context.mounted && session == DioClient.sessionKey) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => UserSpacePage(uid: targetUid)),
            );
          }
        },
        child: dataStyle == 'compact'
            ? _buildCompact(context, username, role, title, isLoggedIn)
            : _buildExpanded(context, username, role, title, isLoggedIn),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, String username, String role,
      String title, bool isLoggedIn) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        if (isLoggedIn && _uid != null)
          UserAvatarWidget(
            reserveFrameSpace: true,
            uid: _uid,
            author: username,
            faceUrl: (_space?.faceUrl.isNotEmpty == true)
                ? _space!.faceUrl
                : AppConfig.myFaceUrl,
            size: 34,
          )
        else
          CircleAvatar(
            radius: 17,
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(Icons.person_rounded,
                size: 20, color: colorScheme.primary),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              Text(
                role,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  color: isLoggedIn ? colorScheme.outline : colorScheme.primary,
                  fontWeight: isLoggedIn ? FontWeight.normal : FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.outline),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context, String username, String role,
      String title, bool isLoggedIn) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (isLoggedIn && _uid != null)
              UserAvatarWidget(
                reserveFrameSpace: true,
                uid: _uid,
                author: username,
                faceUrl: (_space?.faceUrl.isNotEmpty == true)
                    ? _space!.faceUrl
                    : AppConfig.myFaceUrl,
                size: 38,
              )
            else
              CircleAvatar(
                radius: 19,
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(Icons.person_rounded,
                    size: 22, color: colorScheme.primary),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      role,
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 12, color: Colors.grey),
          ],
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatCol('我的空间', Icons.home_rounded, () async {
              final targetUid = _uid ?? await KlpbbsApi.getMyUid();
              if (targetUid == null || targetUid <= 0) return;
              if (context.mounted) {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => UserSpacePage(uid: targetUid)));
              }
            }),
            _buildStatCol('道具背包', Icons.inventory_2_rounded, () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const MagicPage(initialTab: 1)));
            }),
            _buildStatCol('积分明细', Icons.monetization_on_rounded, () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CreditPage()));
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCol(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
