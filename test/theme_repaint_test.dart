import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/core/db.dart';
import 'package:klaro/design/tokens.dart';
import 'package:klaro/features/home/home_page.dart';

import 'test_paths.dart';

void main() {
  setUpAll(() async {
    testPaths();
    await Store.open();
  });

  testWidgets('home progress chart repaints when theme colors change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget app(Brightness brightness) => MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(body: HomePage(onNavigate: (_) {})),
    );

    CustomPainter progressPainter() {
      return tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<CustomPainter>()
          .singleWhere(
            (painter) =>
                painter.runtimeType.toString().contains('ProgressChartPainter'),
          );
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(app(Brightness.light));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final lightPainter = progressPainter();

    await tester.pumpWidget(app(Brightness.dark));
    // MaterialApp animates its ThemeData, including ThemeExtension colors.
    // The first frame still has the old palette; advance to the final palette.
    await tester.pump(const Duration(milliseconds: 300));
    final darkPainter = progressPainter();

    expect(darkPainter.shouldRepaint(lightPainter), isTrue);
    expect(darkPainter.shouldRepaint(darkPainter), isFalse);
  });
}
