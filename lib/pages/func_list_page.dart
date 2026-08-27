import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as hp;

import '../core/dio_client.dart';
import '../widgets/app_back_button.dart';
import '../widgets/global_nav.dart';

/// 通用功能列表页（勋章/道具/任务等 Discuz 用户中心页面）
class FuncListPage extends StatefulWidget {
  final String title;
  final String path; // 页面路径（相对 baseUrl）

  const FuncListPage({super.key, required this.title, required this.path});

  @override
  State<FuncListPage> createState() => _FuncListPageState();
}

class _FuncListPageState extends State<FuncListPage> {
  late Future<List<String>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<String>> _load() async {
    final resp = await DioClient.dio.get<List<int>>(
      widget.path,
      options: Options(responseType: ResponseType.bytes),
    );
    final html = const Utf8Decoder(
      allowMalformed: true,
    ).convert(resp.data ?? const []);
    // 提取条目：li 文本（去重、去空）
    final doc = hp.parse(html);
    final items = <String>{};
    for (final li in doc.querySelectorAll('li')) {
      final t = li.text.trim();
      if (t.length >= 2 && t.length <= 50) items.add(t);
    }
    return items.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(widget.title),
        actions: const [GlobalNavButton()],
      ),
      body: FutureBuilder<List<String>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('加载失败：${snap.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final items = snap.data!;
          if (items.isEmpty) return const Center(child: Text('暂无数据'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => ListTile(title: Text(items[i])),
          );
        },
      ),
    );
  }
}
