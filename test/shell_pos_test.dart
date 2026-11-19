import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/core/db.dart';
import 'package:klaro/design/tokens.dart';
import 'package:klaro/features/shell.dart';
import 'test_paths.dart';

void main() {
  setUpAll(() async {
    testPaths();
    await Store.open();
  });

  testWidgets('shell pins a short page to the top', (tester) async {
    tester.view.physicalSize = const Size(1589, 814);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Shell(),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // The page must start right below the header, not centred in the window.
    final top = tester.getTopLeft(find.text('Video Courses')).dy;
    expect(top, lessThan(120));
    final import = find.text('Import folder');
    // ignore: avoid_print
    print('import found=${import.evaluate().length} ${import.evaluate().isEmpty ? "" : tester.getTopLeft(import)}');
    final neu = find.text('New course');
    // ignore: avoid_print
    print('new found=${neu.evaluate().length} ${neu.evaluate().isEmpty ? "" : tester.getTopLeft(neu)}');
  });
}
