import 'package:flutter/material.dart';
import 'package:webview_cef/webview_cef.dart';

import '../../core/cef_bootstrap.dart';

/// 可复用的 CEF WebView 组件。
///
/// 自行管理 [WebViewController] 的完整生命周期：
/// - [State.initState] 中创建 controller
/// - 首帧后再做异步初始化，避免在 build 期间产生副作用
/// - [State.dispose] 中释放 controller（注意：不会调用
///   `WebviewManager().quit()`，它只允许在应用退出时调用一次）
class CefWebView extends StatefulWidget {
  const CefWebView({
    super.key,
    required this.url,
    this.loading,
    this.onPageTitle,
    this.onPageLoaded,
    this.onUrlChanged,
    this.onConsoleMessage,
    this.background,
  });

  /// 初始加载的地址
  final String url;

  /// WebView 就绪前展示的占位组件
  final Widget? loading;

  /// 页面标题变化回调（可用于 AppBar / 弹窗标题）
  final ValueChanged<String>? onPageTitle;

  /// 页面加载完成回调
  final ValueChanged<String>? onPageLoaded;

  /// URL 变化回调
  final ValueChanged<String>? onUrlChanged;

  /// 控制台消息回调（CEF 内部输出）
  final void Function(int level, String message, String source, int line)?
  onConsoleMessage;

  /// WebView 背后的背景色：CEF 白屏时这一层能区分是「没渲染」还是「真白底」。
  final Color? background;

  @override
  State<CefWebView> createState() => CefWebViewState();
}

class CefWebViewState extends State<CefWebView> {
  WebViewController? _controller;
  String _title = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    if (!mounted) return;
    await ensureCefInitialized();
    if (!mounted) return;

    final controller = WebviewManager().createWebView(
      loading:
          widget.loading ??
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
    controller.setWebviewListener(
      WebviewEventsListener(
        onTitleChanged: (t) {
          if (!mounted) return;
          setState(() => _title = t);
          widget.onPageTitle?.call(t);
        },
        onUrlChanged: (url) {
          debugPrint('[$runtimeType] onUrlChanged => $url');
          widget.onUrlChanged?.call(url);
        },
        onLoadStart: (_, url) =>
            debugPrint('[$runtimeType] onLoadStart => $url'),
        onLoadEnd: (_, url) {
          debugPrint('[$runtimeType] onLoadEnd => $url');
          widget.onPageLoaded?.call(url);
        },
        onConsoleMessage: (level, message, source, line) {
          debugPrint('[$runtimeType] console L$level $source:$line $message');
          widget.onConsoleMessage?.call(level, message, source, line);
        },
      ),
    );
    await controller.initialize(widget.url);

    if (!mounted) {
      // 异步初始化期间组件已被销毁，直接回收资源
      controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  /// 当前页面标题
  String get title => _title;

  /// 底层 controller（可能尚未就绪）
  WebViewController? get controller => _controller;

  /// 导航：后退
  void goBack() => _controller?.goBack();

  /// 导航：前进
  void goForward() => _controller?.goForward();

  /// 导航：重新加载
  void reload() => _controller?.reload();

  /// 加载新地址
  void loadUrl(String url) => _controller?.loadUrl(url);

  /// 打开 DevTools
  void openDevTools() => _controller?.openDevTools();

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return widget.loading ??
          const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Container(
      // 显式背景：CEF 真的白屏时，方便判断「纹理没出来」还是「页面本身就是白底」
      color: widget.background,
      child: ValueListenableBuilder<bool>(
        valueListenable: controller,
        builder: (_, ready, _) => ready
            ? controller.webviewWidget
            : (widget.loading ?? const SizedBox()),
      ),
    );
  }
}
