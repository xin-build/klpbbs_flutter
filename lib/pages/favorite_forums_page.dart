import 'package:flutter/material.dart';

import 'favorite_hub_page.dart';

/// Compatibility entry: both routes share the current-account favorite view.
class FavoriteForumsPage extends StatelessWidget {
  final int uid;
  const FavoriteForumsPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) =>
      FavoriteHubPage(uid: uid, initialIndex: 1);
}
