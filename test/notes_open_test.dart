import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/core/db.dart';
import 'test_paths.dart';
import 'package:klaro/core/models.dart';
import 'package:klaro/design/tokens.dart';
import 'package:klaro/features/notes/notes_page.dart';

/// Selecting a page must always show its editor, at every window size.
void main() {
  setUpAll(() async {
    testPaths();
    await Store.open();
    final existing = await Store.i.notes();
    if (!existing.any((n) => n.id == 'test-page')) {
      final now = DateTime.now();
      await Store.i.saveNote(Note(
        id: 'test-page',
        title: 'Untitled page',
        body: '',
        createdAt: now,
        updatedAt: now,
      ));
    }
  });

  for (final size in <String, Size>{
    'wide 900x700': const Size(900, 700),
    'narrow 629x760': const Size(629, 760),
    'tiny 400x760': const Size(400, 760),
    'short 629x520': const Size(629, 520),
  }.entries) {
    testWidgets('notes editor opens at ${size.key}', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      tester.view.physicalSize = size.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: NotesPage()),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump();


      final row = find.text('Untitled page');
      expect(row, findsWidgets, reason: 'the page list shows the stored page');
      await tester.tap(row.first);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump();

      // The empty placeholder is replaced by the real editor chrome.
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.text('Select a page, or start a new one'), findsNothing);
      expect(find.byTooltip('Insert'), findsWidgets);
      final error = tester.takeException();
      if (error != null) {
        for (final d in errors) {
          // ignore: avoid_print
          print('--- ${size.key} ---\n$d');
        }
      }
      expect(error, isNull);
    });
  }
}