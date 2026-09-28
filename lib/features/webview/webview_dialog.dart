import 'package:flutter/material.dart';

import '../../shared/widgets/cef_webview.dart';

/// 以弹窗（Dialog）形式展示 WebView。
///
/// 返回的 Future 在弹窗关闭时完成；关闭时内部 WebView 的
/// controller 会随组件一起 dispose，无需手动清理。
Future<void> showWebviewDialog(BuildContext context, {required String url}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WebviewDialog(url: url),
  );
}

class WebviewDialog extends StatefulWidget {
  const WebviewDialog({super.key, required this.url});

  final String url;

  @override
  State<WebviewDialog> createState() => _WebviewDialogState();
}

class _WebviewDialogState extends State<WebviewDialog> {
  final GlobalKey<CefWebViewState> _webViewKey = GlobalKey<CefWebViewState>();
  String _title = '';
  String _currentUrl = '';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        // 弹窗占屏幕 80% 宽 / 75% 高
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.75,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              // 顶部标题栏：页面标题 + 刷新 + DevTools + 关闭
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    const Icon(Icons.public, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title.isEmpty ? widget.url : _title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (_currentUrl.isNotEmpty && _currentUrl != widget.url)
                            Text(
                              _currentUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新',
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () => _webViewKey.currentState?.reload(),
                    ),
                    IconButton(
                      tooltip: 'DevTools',
                      icon: const Icon(Icons.developer_mode, size: 20),
                      onPressed: () => _webViewKey.currentState?.openDevTools(),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: CefWebView(
                  key: _webViewKey,
                  url: widget.url,
                  background: const Color(0xFFEFEFEF),
                  onPageTitle: (t) {
                    if (mounted) setState(() => _title = t);
                  },
                  onUrlChanged: (u) {
                    if (mounted) setState(() => _currentUrl = u);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
