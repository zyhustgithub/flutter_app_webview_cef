import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/cef_webview.dart';

/// 内嵌 WebView 页面：以完整路由页面的形式承载网页。
class EmbeddedWebViewPage extends StatefulWidget {
  const EmbeddedWebViewPage({super.key, required this.url, this.title});

  final String url;
  final String? title;

  @override
  State<EmbeddedWebViewPage> createState() => _EmbeddedWebViewPageState();
}

class _EmbeddedWebViewPageState extends State<EmbeddedWebViewPage> {
  static const String _baiduUrl = 'https://www.baidu.com';
  static const String _bingUrl = 'https://www.bing.com';

  final GlobalKey<CefWebViewState> _baiduWebViewKey =
      GlobalKey<CefWebViewState>();
  final GlobalKey<CefWebViewState> _bingWebViewKey =
      GlobalKey<CefWebViewState>();

  String _baiduTitle = '';
  String _bingTitle = '';
  String _baiduCurrentUrl = _baiduUrl;
  String _bingCurrentUrl = _bingUrl;
  final List<_ConsoleEntry> _logs = [];
  bool _showConsole = false;

  void _appendLog(
    String webViewName,
    int level,
    String message,
    String source,
    int line,
  ) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, _ConsoleEntry(webViewName, level, message, source, line));
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  void _goBackAll() {
    _baiduWebViewKey.currentState?.goBack();
    _bingWebViewKey.currentState?.goBack();
  }

  void _goForwardAll() {
    _baiduWebViewKey.currentState?.goForward();
    _bingWebViewKey.currentState?.goForward();
  }

  void _reloadAll() {
    _baiduWebViewKey.currentState?.reload();
    _bingWebViewKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final pageTitle = widget.title ?? '内嵌双网页';
    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        actions: [
          IconButton(
            tooltip: '两个网页后退',
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: _goBackAll,
          ),
          IconButton(
            tooltip: '两个网页前进',
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: _goForwardAll,
          ),
          IconButton(
            tooltip: '刷新两个网页',
            icon: const Icon(Icons.refresh),
            onPressed: _reloadAll,
          ),
          IconButton(
            tooltip: '打开百度 DevTools',
            icon: const Icon(Icons.developer_mode),
            onPressed: () => _baiduWebViewKey.currentState?.openDevTools(),
          ),
          IconButton(
            tooltip: '打开 Bing DevTools',
            icon: const Icon(Icons.developer_board),
            onPressed: () => _bingWebViewKey.currentState?.openDevTools(),
          ),
          IconButton(
            tooltip: '查看日志',
            icon: Badge(
              isLabelVisible: _logs.isNotEmpty,
              label: Text('${_logs.length}'),
              child: const Icon(Icons.bug_report),
            ),
            onPressed: () => setState(() => _showConsole = !_showConsole),
          ),
        ],
      ),
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _WebViewPane(
                  label: '百度',
                  title: _baiduTitle,
                  url: _baiduCurrentUrl,
                  child: CefWebView(
                    key: _baiduWebViewKey,
                    url: _baiduUrl,
                    background: const Color(0xFFEFEFEF),
                    onPageTitle: (t) {
                      if (!mounted) return;
                      setState(() => _baiduTitle = t);
                    },
                    onUrlChanged: (u) {
                      if (!mounted) return;
                      setState(() => _baiduCurrentUrl = u);
                    },
                    onConsoleMessage: (level, message, source, line) =>
                        _appendLog('百度', level, message, source, line),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 1,
                child: _WebViewPane(
                  label: 'Bing',
                  title: _bingTitle,
                  url: _bingCurrentUrl,
                  child: CefWebView(
                    key: _bingWebViewKey,
                    url: _bingUrl,
                    background: const Color(0xFFEFEFEF),
                    onPageTitle: (t) {
                      if (!mounted) return;
                      setState(() => _bingTitle = t);
                    },
                    onUrlChanged: (u) {
                      if (!mounted) return;
                      setState(() => _bingCurrentUrl = u);
                    },
                    onConsoleMessage: (level, message, source, line) =>
                        _appendLog('Bing', level, message, source, line),
                  ),
                ),
              ),
            ],
          ),
          if (_showConsole)
            _ConsolePanel(
              logs: _logs,
              currentUrls: {'百度': _baiduCurrentUrl, 'Bing': _bingCurrentUrl},
            ),
        ],
      ),
    );
  }
}

class _WebViewPane extends StatelessWidget {
  const _WebViewPane({
    required this.label,
    required this.title,
    required this.url,
    required this.child,
  });

  final String label;
  final String title;
  final String url;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.isEmpty ? url : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _ConsoleEntry {
  const _ConsoleEntry(
    this.webViewName,
    this.level,
    this.message,
    this.source,
    this.line,
  );
  final String webViewName;
  final int level;
  final String message;
  final String source;
  final int line;
}

class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel({required this.logs, required this.currentUrls});

  final List<_ConsoleEntry> logs;
  final Map<String, String> currentUrls;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        elevation: 8,
        color: const Color(0xFF1E1E1E),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                color: Colors.black54,
                child: Row(
                  children: [
                    const Icon(Icons.bug_report, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentUrls.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join('  |  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.copy,
                        color: Colors.white,
                        size: 16,
                      ),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: logs
                                .map(
                                  (e) =>
                                      '[${e.webViewName}][L${e.level}] ${e.source}:${e.line} ${e.message}',
                                )
                                .join('\n'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Flexible(
                child: logs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '（暂无日志）',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: logs.length,
                        itemBuilder: (_, i) {
                          final e = logs[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            child: Text(
                              '[${e.webViewName}][L${e.level}] ${e.source}:${e.line}\n${e.message}',
                              style: TextStyle(
                                color: _levelColor(e.level),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _levelColor(int level) {
    if (level >= 4) return Colors.redAccent;
    if (level == 3) return Colors.amber;
    return Colors.greenAccent;
  }
}
