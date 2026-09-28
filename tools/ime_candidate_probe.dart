import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:webview_cef_app/shared/widgets/cef_webview.dart';

const _channel = MethodChannel('webview_cef');
final _webKey = GlobalKey<CefWebViewState>();
final _flutterFocus = FocusNode();
final _flutterController = TextEditingController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final url = Uri.file(
    '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/ime_test.html',
  ).toString();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(
              height: 56,
              child: TextField(
                focusNode: _flutterFocus,
                controller: _flutterController,
              ),
            ),
            Expanded(
              child: CefWebView(key: _webKey, url: url),
            ),
          ],
        ),
      ),
    ),
  );
  final result = <String, Object?>{};
  try {
    await _run(result).timeout(const Duration(seconds: 45));
    final requireCandidate =
        Platform.environment['IME_CANDIDATE_REQUIRE'] == '1';
    result['passed'] =
        result['webInitialOk'] == true &&
        result['webReturnOk'] == true &&
        (!requireCandidate || result['candidateDetected'] == true);
  } catch (error, stack) {
    result['passed'] = false;
    result['error'] = '$error';
    result['stack'] = '$stack';
  }
  await Directory('build').create(recursive: true);
  await File('build/ime_candidate_probe.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  await _webKey.currentState?.controller?.dispose();
  exit(result['passed'] == true ? 0 : 1);
}

Future<void> _run(Map<String, Object?> result) async {
  while (_webKey.currentState?.controller?.value != true) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final web = _webKey.currentState!.controller!;
  await Future<void>.delayed(const Duration(seconds: 2));
  await web.setClientFocus(true);
  await web.executeJavaScript(
    "document.querySelector('input').focus(); document.querySelector('input').setSelectionRange(0,0);",
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  result['webInitial'] = await _sampleCandidate('webInitial');

  _flutterFocus.requestFocus();
  await web.setClientFocus(false);
  await Future<void>.delayed(const Duration(milliseconds: 500));
  result['flutterNative'] = await _sampleCandidate('flutterNative');

  await web.setClientFocus(true);
  await web.executeJavaScript(
    "document.querySelector('input').focus(); document.querySelector('input').setSelectionRange(0,0);",
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  result['webReturn'] = await _sampleCandidate('webReturn');

  final initial = result['webInitial']! as Map<String, Object?>;
  final returned = result['webReturn']! as Map<String, Object?>;
  result['candidateDetected'] =
      (initial['candidateCount'] as int) > 0 ||
      (returned['candidateCount'] as int) > 0;
  result['webInitialOk'] =
      (initial['candidateCount'] as int) == 0 ||
      initial['candidateBelowCaret'] == true;
  result['webReturnOk'] =
      (returned['candidateCount'] as int) == 0 ||
      returned['candidateBelowCaret'] == true;
}

Future<Map<String, Object?>> _sampleCandidate(String stage) async {
  final diag =
      await _channel.invokeMapMethod<String, dynamic>('imeDiagnostics') ??
      <String, dynamic>{};
  final candidates =
      await _channel.invokeListMethod<dynamic>('imeCandidateWindows') ??
      const <dynamic>[];
  final screenX = (diag['screenX'] as num?)?.toDouble() ?? 0;
  final screenY = (diag['screenY'] as num?)?.toDouble() ?? 0;
  final screenHeight = (diag['clientHeight'] as num?)?.toDouble() ?? 0;
  Map<String, dynamic>? nearest;
  var nearestScore = double.infinity;
  for (final raw in candidates) {
    final item = Map<String, dynamic>.from(raw as Map);
    final left = (item['left'] as num).toDouble();
    final top = (item['top'] as num).toDouble();
    final dx = (left - screenX).abs();
    final dy = (top - (screenY + screenHeight)).abs();
    final score = dx + dy;
    if (score < nearestScore) {
      nearestScore = score;
      nearest = item;
    }
  }
  final below = nearest == null
      ? null
      : ((nearest['top'] as num) >= screenY + screenHeight - 8 &&
            ((nearest['left'] as num) - screenX).abs() < 240);
  return {
    'stage': stage,
    'diagnostics': diag,
    'candidateCount': candidates.length,
    'nearestCandidate': nearest,
    'candidateBelowCaret': below,
  };
}
