import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/core/db.dart';

import 'test_paths.dart';

import 'package:klaro/design/tokens.dart';
import 'package:klaro/features/bookmarks/bookmarks_page.dart';
import 'package:klaro/features/courses/courses_page.dart';
import 'package:klaro/features/home/home_page.dart';
import 'package:klaro/features/library/library_page.dart';
import 'package:klaro/features/maps/maps_page.dart';
import 'package:klaro/features/notes/notes_page.dart';
import 'package:klaro/features/review/review_page.dart';
import 'package:klaro/features/settings/settings_page.dart';
import 'package:klaro/features/shell.dart';
import 'package:klaro/features/tutor/tutor_page.dart';

/// Pumps every top-level page at several window sizes in both themes and fails
/// on any RenderFlex overflow or layout assertion. This is the regression net
/// for window resizing and theme-wide layout/color integration.
void main() {
  setUpAll(() async {
    testPaths();
    await Store.open();
  });

  final pages = <String, Widget Function()>{
    'home': () => HomePage(onNavigate: (_) {}),
    'bookmarks': () => const BookmarksPage(),
    'courses': () => const CoursesPage(),
    'library': () => const LibraryPage(),
    'notes': () => const NotesPage(),
    'maps': () => const ConceptMapsPage(),
    'review': () => const ReviewPage(),
    'tutor': () => const TutorPage(),
    'settings': () => const SettingsPage(),
  };

  const sizes = <String, Size>{
    'micro 400': Size(400, 720),
    'short 400x500': Size(400, 500),
    'wide short 1400x430': Size(1400, 430),
    'tiny 460': Size(460, 760),
    'narrow 560': Size(560, 820),
    'compact 900': Size(900, 760),
    'wide 1500': Size(1500, 900),
    'ultrawide 2400': Size(2400, 1200),
  };

  const themes = <String, Brightness>{
    'light': Brightness.light,
    'dark': Brightness.dark,
  };

  for (final entry in pages.entries) {
    for (final size in sizes.entries) {
      for (final theme in themes.entries) {
        testWidgets('${entry.key} lays out at ${size.key} in ${theme.key}', (
          tester,
        ) async {
          tester.view.physicalSize = size.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final errors = <FlutterErrorDetails>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (details) {
            errors.add(details);
            previous?.call(details);
          };
          addTearDown(() => FlutterError.onError = previous);

          // Mount inside runAsync so pages that query the database complete on
          // the real clock instead of leaving fake timers pending.
          await tester.runAsync(() async {
            await tester.pumpWidget(
              MaterialApp(
                theme: buildTheme(theme.value),
                home: Scaffold(body: entry.value()),
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 350));
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          final error = tester.takeException();
          if (error != null) {
            for (final d in errors) {
              // ignore: avoid_print
              print('--- ${entry.key} @ ${size.key} ---\n$d');
            }
          }
          expect(
            error,
            isNull,
            reason: '${entry.key} at ${size.key} in ${theme.key}: $error',
          );
        });
      }
    }
  }

  // The shell adds the floating rail and the header bar, and those must survive
  // both a very narrow window and a very short one.
  const shellSizes = <String, Size>{
    'tiny 560x480': Size(560, 480),
    'short 1200x420': Size(1200, 420),
    'ultrawide 2400x1200': Size(2400, 1200),
  };

  for (final size in shellSizes.entries) {
    for (final theme in themes.entries) {
      testWidgets('shell lays out at ${size.key} in ${theme.key}', (
        tester,
      ) async {
        tester.view.physicalSize = size.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          errors.add(details);
          previous?.call(details);
        };
        addTearDown(() => FlutterError.onError = previous);

        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(theme: buildTheme(theme.value), home: const Shell()),
          );
          await Future<void>.delayed(const Duration(milliseconds: 450));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final error = tester.takeException();
        if (error != null) {
          for (final d in errors) {
            // ignore: avoid_print
            print('--- shell @ ${size.key} ---\n$d');
          }
        }
        expect(
          error,
          isNull,
          reason: 'shell at ${size.key} in ${theme.key}: $error',
        );
      });
    }
  }
}
