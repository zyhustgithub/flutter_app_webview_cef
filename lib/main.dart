import 'package:flutter/material.dart';

import 'features/webview/embedded_webview_page.dart';
import 'features/webview/webview_dialog.dart';
import 'features/webview/ime_test_page.dart';

void main() {
  runApp(const WebviewCefApp());
}

class WebviewCefApp extends StatelessWidget {
  const WebviewCefApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebView CEF Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 默认显式加 https，避免 CEF 把无协议的 URL 当成 file:// 或拒绝加载
  final TextEditingController _urlController = TextEditingController(
    text: 'https://www.baidu.com',
  );

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String get _url {
    var v = _urlController.text.trim();
    if (v.isEmpty) return 'https://flutter.dev';
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'https://$v';
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebView CEF Demo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'webview_cef 0.6.2 · CEF 149 (Chromium 149)',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '加载 URL',
                  hintText: 'https://www.baidu.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                icon: const Icon(Icons.keyboard),
                label: const Text('Windows 输入法回归测试'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ImeTestPage()),
                ),
              ),
              _ActionCard(
                icon: Icons.tab,
                title: '内嵌双网页',
                subtitle: '左侧百度、右侧 Bing，按 2:1 宽度测试双 WebView',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        EmbeddedWebViewPage(url: _url, title: '内嵌双网页'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ActionCard(
                icon: Icons.picture_in_picture,
                title: '弹窗网页',
                subtitle: '以 Dialog 弹窗形式打开 WebView',
                onTap: () => showWebviewDialog(context, url: _url),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
