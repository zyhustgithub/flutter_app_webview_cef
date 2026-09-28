import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:webview_cef_app/main.dart';

void main() {
  testWidgets('HomePage 展示两个入口按钮', (tester) async {
    await tester.pumpWidget(const WebviewCefApp());

    expect(find.text('内嵌网页'), findsOneWidget);
    expect(find.text('弹窗网页'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
  });
}
