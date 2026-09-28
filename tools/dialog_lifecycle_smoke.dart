import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:webview_cef_app/features/webview/webview_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final checks = <String, Object?>{};
  runApp(_DialogLifecycleHarness(checks: checks));
}

class _DialogLifecycleHarness extends StatefulWidget {
  const _DialogLifecycleHarness({required this.checks});

  final Map<String, Object?> checks;

  @override
  State<_DialogLifecycleHarness> createState() =>
      _DialogLifecycleHarnessState();
}

class _DialogLifecycleHarnessState extends State<_DialogLifecycleHarness> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      home: const Scaffold(body: SizedBox.expand()),
    );
  }

  Future<void> _run() async {
    try {
      final url = Uri.file(
        '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/ime_test.html',
      ).toString();
      final cycles =
          int.tryParse(Platform.environment['DIALOG_SMOKE_CYCLES'] ?? '') ?? 2;
      for (var i = 1; i <= cycles; i++) {
        await _cycle(url, i);
      }
      widget.checks['passed'] = true;
    } catch (error, stack) {
      widget.checks['passed'] = false;
      widget.checks['error'] = '$error';
      widget.checks['stack'] = '$stack';
    }
    await Directory('build').create(recursive: true);
    await File(
      'build/dialog_lifecycle_smoke.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(widget.checks));
    exit(widget.checks['passed'] == true ? 0 : 1);
  }

  Future<void> _cycle(String url, int number) async {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      throw StateError('Navigator context was not ready for cycle $number');
    }
    widget.checks['cycle$number'] = 'opening';
    final dialog = showWebviewDialog(context, url: url);
    final openMs =
        int.tryParse(Platform.environment['DIALOG_SMOKE_OPEN_MS'] ?? '') ??
        3000;
    await Future<void>.delayed(Duration(milliseconds: openMs));
    widget.checks['cycle$number'] = 'closing';
    if (Platform.environment['DIALOG_SMOKE_EXTERNAL_CLICK'] == '1') {
      await dialog.timeout(const Duration(seconds: 20));
    } else {
      _tapDialogCloseButton();
      await dialog.timeout(const Duration(seconds: 5));
    }
    widget.checks['cycle$number'] = 'closed';
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  void _tapDialogCloseButton() {
    final overlay = _navigatorKey.currentState?.overlay?.context
        .findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) {
      throw StateError('Navigator overlay was not ready for click automation');
    }
    final size = overlay.size;
    final dialogWidth = size.width * 0.8;
    final dialogHeight = size.height * 0.75;
    final top = (size.height - dialogHeight) / 2;
    final left = (size.width - dialogWidth) / 2;
    final position = Offset(left + dialogWidth - 24, top + 24);
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(
      PointerDownEvent(
        pointer: 1,
        position: position,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      ),
    );
    binding.handlePointerEvent(
      PointerUpEvent(
        pointer: 1,
        position: position,
        kind: PointerDeviceKind.mouse,
      ),
    );
  }
}
