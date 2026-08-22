import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/klpbbs_api.dart';
import '../widgets/global_nav.dart';

/// 道具中心（klpbbs home.php?mod=magic，需登录）
class MagicPage extends StatefulWidget {
  const MagicPage({super.key});

  @override
  State<MagicPage> createState() => _MagicPageState();
}

class _MagicPageState extends State<MagicPage> {
  late Future<List<({int id, String name, String img, String desc})>> _future;

  @override
  void initState() {
    super.initState();
    _future = KlpbbsApi.getMagics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('道具中心'),
        actions: const [GlobalNavButton()],
      ),
      body:
          FutureBuilder<List<({int id, String name, String img, String desc})>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('加载失败：${snap.error}'));
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无道具（需登录后可见）', textAlign: TextAlign.center),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async =>
                    setState(() => _future = KlpbbsApi.getMagics()),
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final scheme = Theme.of(context).colorScheme;
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withAlpha(50),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer.withAlpha(60),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: m.img.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: m.img,
                                    fit: BoxFit.contain,
                                    errorWidget: (_, __, ___) => Icon(
                                      Icons.auto_fix_high,
                                      color: scheme.outline,
                                    ),
                                  )
                                : Icon(
                                    Icons.auto_fix_high,
                                    color: scheme.primary,
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            m.desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
    );
  }
}
