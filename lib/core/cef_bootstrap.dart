import 'package:webview_cef/webview_cef.dart';

/// 全局 CEF 初始化（整个应用生命周期内只执行一次）。
///
/// 多个页面/弹窗共享同一次初始化结果，避免重复启动 CEF 子进程。
Future<void> ensureCefInitialized() => _cefInit ??= WebviewManager().initialize();

Future<void>? _cefInit;
