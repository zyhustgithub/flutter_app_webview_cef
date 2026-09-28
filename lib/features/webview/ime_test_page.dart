import 'dart:io';

import 'package:flutter/material.dart';

import '../../shared/widgets/cef_webview.dart';
import 'webview_dialog.dart';

class ImeTestPage extends StatefulWidget {
  const ImeTestPage({super.key});

  @override
  State<ImeTestPage> createState() => _ImeTestPageState();
}

class _ImeTestPageState extends State<ImeTestPage> {
  late final Future<String> _url = Future.value(
    Uri.file(
      '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/ime_test.html',
    ).toString(),
  );
  bool _dual = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Windows 输入法回归')),
    body: FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text('测试页面加载失败：${snapshot.error}');
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final url = snapshot.data!;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Flutter 输入框：与网页交替输入中文',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Text('双 WebView'),
                    selected: _dual,
                    onSelected: (v) => setState(() => _dual = v),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => showWebviewDialog(context, url: url),
                    child: const Text('弹窗测试'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CefWebView(
                      key: const ValueKey('ime-left'),
                      url: url,
                    ),
                  ),
                  if (_dual) ...[
                    const VerticalDivider(width: 8),
                    Expanded(
                      child: CefWebView(
                        key: const ValueKey('ime-right'),
                        url: url,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
