import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/core/db.dart';
import 'test_paths.dart';
import 'package:klaro/design/tokens.dart';
import 'package:klaro/features/bookmarks/bookmarks_page.dart';

void main() {
  testWidgets('bookmarks page renders its header and empty state', (tester) async {
    await tester.runAsync(() async {
      testPaths();
      await Store.open();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: BookmarksPage()),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    expect(find.text('Bookmarks'), findsWidgets);
    expect(find.textContaining('Pin item'), findsWidgets);
  });
}
