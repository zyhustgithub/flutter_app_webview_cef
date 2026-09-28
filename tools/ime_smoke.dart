// Run as a Windows Flutter target with WEBVIEW_CEF_IME_TRACE=1.
// Exercises the real CEF renderer -> browser -> HWND bridge; does not simulate
// Microsoft Pinyin or claim to validate the visible OS candidate window.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:webview_cef_app/shared/widgets/cef_webview.dart';

final _key = GlobalKey<CefWebViewState>();
final _secondKey = GlobalKey<CefWebViewState>();
const _channel = MethodChannel('webview_cef');
final _events = <String>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final url = Uri.file(
    '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/ime_test.html',
  ).toString();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(64),
          // The hidden harness drives native focus explicitly. Prevent desktop
          // activation changes from racing Flutter autofocus callbacks.
          child: FocusScope(
            canRequestFocus: false,
            child: Row(
              children: [
                Expanded(
                  child: CefWebView(
                    key: _key,
                    url: url,
                    onPageLoaded: (value) => _events.add(
                      'loaded: ${value.substring(0, value.length.clamp(0, 120))}',
                    ),
                    onConsoleMessage: (level, message, source, line) =>
                        _events.add('$level $message'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CefWebView(key: _secondKey, url: url),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  final checks = <String, Object?>{};
  try {
    await _run(checks).timeout(const Duration(seconds: 45));
    checks['passed'] = true;
  } catch (error, stack) {
    checks['passed'] = false;
    checks['error'] = '$error';
    checks['stack'] = '$stack';
    checks['native'] = await _snapshot();
    checks['events'] = _events;
  }
  await File('build/ime_smoke.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(checks));
  await _key.currentState?.controller?.dispose();
  await _secondKey.currentState?.controller?.dispose();
  exit(checks['passed'] == true ? 0 : 1);
}

Future<Map<String, dynamic>> _snapshot() async {
  final result = await _channel.invokeMapMethod<String, dynamic>(
    'imeDiagnostics',
  );
  return result!;
}

Future<void> _run(Map<String, Object?> checks) async {
  while (_key.currentState?.controller?.value != true ||
      _secondKey.currentState?.controller?.value != true) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final controller = _key.currentState!.controller!;
  await Future<void>.delayed(const Duration(seconds: 2));
  await controller.setClientFocus(true);
  Future<Map<String, dynamic>> focus(String code) async {
    await controller.executeJavaScript(code);
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final state = await _snapshot();
      if (state['editable'] == true && state['hasRect'] == true) return state;
    }
    final dom = await controller
        .evaluateJavascript(
          "JSON.stringify({ready:document.readyState,focus:document.hasFocus(),tag:document.activeElement?.tagName,bridge:typeof __cefImeSetEpoch,inputs:document.querySelectorAll('input').length})",
        )
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => 'evaluateJavascript timed out',
        );
    throw StateError(
      'No editable caret report: ${await _snapshot()}, DOM: $dom',
    );
  }

  final single = await focus(
    "document.querySelector('input').focus(); document.querySelector('input').setSelectionRange(2,2);",
  );
  checks['single'] = single;
  if ((single['x'] as num) < 20 || (single['y'] as num) < 20) {
    throw StateError('Caret at origin');
  }
  final movingInitial = await focus(
    "document.querySelector('#moving-input').focus(); document.querySelector('#moving-input').setSelectionRange(0,0);",
  );
  checks['movingInitial'] = movingInitial;
  await controller.executeJavaScript(
    "document.querySelector('#moving-search').classList.add('moved');",
  );
  Map<String, dynamic> movingAfter = movingInitial;
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    movingAfter = await _snapshot();
    if ((movingInitial['screenY'] as num) - (movingAfter['screenY'] as num) >
        80) {
      break;
    }
  }
  checks['movingAfter'] = movingAfter;
  if ((movingInitial['screenY'] as num) - (movingAfter['screenY'] as num) <
      80) {
    throw StateError(
      'Moving input did not update native candidate anchor: $movingInitial -> $movingAfter',
    );
  }
  final multiline = await focus(
    "document.querySelector('textarea').focus(); document.querySelector('textarea').setSelectionRange(0,0);",
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  checks['multiline'] = await _snapshot();
  // Textarea caret should be at its first line, not at its element bottom.
  final bounds = await controller.evaluateJavascript(
    "JSON.stringify((()=>{let r=document.querySelector('textarea').getBoundingClientRect();return {top:r.top,bottom:r.bottom}})())",
  );
  final rect = jsonDecode(bounds as String) as Map<String, dynamic>;
  final multi = await _snapshot();
  if ((multi['y'] as num) >= (rect['bottom'] as num) - 40 ||
      (multi['y'] as num) < (rect['top'] as num)) {
    throw StateError(
      'Textarea anchor is not on first line: $multiline, $rect, $multi',
    );
  }
  await focus(
    "document.querySelector('iframe').scrollIntoView(); document.querySelector('iframe').contentDocument.querySelector('input').focus();",
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  checks['iframe'] = await _snapshot();
  await controller.executeJavaScript(
    "document.querySelector('#opaque').scrollIntoView(); document.querySelector('#opaque').contentWindow.postMessage('focus','*');",
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  checks['opaqueIframe'] = await _snapshot();
  await controller.setClientFocus(false);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  final unfocused = await _snapshot();
  checks['unfocused'] = unfocused;
  if (unfocused['browser'] != -1 || unfocused['hasRect'] != false) {
    throw StateError('Focus not released');
  }
  await controller.setClientFocus(true);
  await focus(
    "document.querySelector('input').scrollIntoView(); document.querySelector('input').focus();",
  );
  checks['refocused'] = await _snapshot();
  final second = _secondKey.currentState!.controller!;
  await second.setClientFocus(true);
  await second.executeJavaScript("document.querySelector('input').focus();");
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final secondState = await _snapshot();
  checks['secondBrowser'] = secondState;
  if (secondState['browser'] == single['browser'] ||
      secondState['editable'] != true ||
      secondState['hasRect'] != true) {
    throw StateError('Second browser did not acquire input ownership');
  }
  await controller.executeJavaScript(
    "document.querySelector('textarea').focus();",
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if ((await _snapshot())['browser'] != secondState['browser']) {
    throw StateError('Inactive browser stole native input ownership');
  }
}
