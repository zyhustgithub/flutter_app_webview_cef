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
  final GlobalKey<CefWebViewState> _webViewKey =
      GlobalKey<CefWebViewState>();

  String _title = '';
  String _currentUrl = '';
  final List<_ConsoleEntry> _logs = [];
  bool _showConsole = false;

  void _appendLog(int level, String message, String source, int line) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, _ConsoleEntry(level, message, source, line));
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title.isEmpty ? (widget.title ?? '内嵌网页') : _title),
        actions: [
          IconButton(
            tooltip: '后退',
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => _webViewKey.currentState?.goBack(),
          ),
          IconButton(
            tooltip: '前进',
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: () => _webViewKey.currentState?.goForward(),
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _webViewKey.currentState?.reload(),
          ),
          IconButton(
            tooltip: 'DevTools',
            icon: const Icon(Icons.developer_mode),
            onPressed: () => _webViewKey.currentState?.openDevTools(),
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
          // 背景色用来区分「CEF 白屏」和「Widget 区域为空」
          CefWebView(
            key: _webViewKey,
            url: widget.url,
            background: const Color(0xFFEFEFEF),
            onPageTitle: (t) {
              if (!mounted) return;
              setState(() => _title = t);
            },
            onUrlChanged: (u) {
              if (!mounted) return;
              setState(() => _currentUrl = u);
            },
            onConsoleMessage: _appendLog,
          ),
          if (_showConsole) _ConsolePanel(logs: _logs, currentUrl: _currentUrl),
        ],
      ),
    );
  }
}

class _ConsoleEntry {
  const _ConsoleEntry(this.level, this.message, this.source, this.line);
  final int level;
  final String message;
  final String source;
  final int line;
}

class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel({required this.logs, required this.currentUrl});

  final List<_ConsoleEntry> logs;
  final String currentUrl;

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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.black54,
                child: Row(
                  children: [
                    const Icon(Icons.bug_report, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'URL: $currentUrl',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white, size: 16),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text: logs
                                .map((e) =>
                                    '[L${e.level}] ${e.source}:${e.line} ${e.message}')
                                .join('\n')));
                      },
                    ),
                  ],
                ),
              ),
              Flexible(
                child: logs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('（暂无日志）',
                            style: TextStyle(color: Colors.white70)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: logs.length,
                        itemBuilder: (_, i) {
                          final e = logs[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            child: Text(
                              '[L${e.level}] ${e.source}:${e.line}\n${e.message}',
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
