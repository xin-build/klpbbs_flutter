import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/klpbbs_api.dart';
import '../widgets/global_nav.dart';

/// 推广中心（klpbbs home.php?mod=spacecp&ac=promotion，需登录）
class PromotionPage extends StatefulWidget {
  const PromotionPage({super.key});

  @override
  State<PromotionPage> createState() => _PromotionPageState();
}

class _PromotionPageState extends State<PromotionPage> {
  late Future<List<({String label, String url})>> _future;

  @override
  void initState() {
    super.initState();
    _future = KlpbbsApi.getPromotion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('推广中心'),
        actions: const [GlobalNavButton()],
      ),
      body: FutureBuilder<List<({String label, String url})>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          final list = snap.data!;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primaryContainer,
                      scheme.secondaryContainer,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '分享推广链接',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('邀请好友注册，获得推广奖励', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('暂无推广链接（需登录后可见）', textAlign: TextAlign.center),
                )
              else
                for (final p in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.link),
                      title: Text(
                        p.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        p.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: '复制链接',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: p.url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('推广链接已复制')),
                          );
                        },
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
