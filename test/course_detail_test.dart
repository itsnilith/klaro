import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:klaro/core/course_import.dart';
import 'package:klaro/core/db.dart';
import 'package:klaro/design/tokens.dart';
import 'package:klaro/features/courses/courses_page.dart';
import 'test_paths.dart';

void main() {
  late String courseId;

  setUpAll(() async {
    testPaths();
    await Store.open();
    final root = Directory.systemTemp.createTempSync('klaro-detail-');
    File(p.join(root.path, '01 intro.mp4')).writeAsStringSync('a');
    File(p.join(root.path, 'IMG.jpg')).writeAsStringSync('cover');
    final module = Directory(p.join(root.path, '02 Module'))..createSync();
    File(p.join(module.path, '01 first.mp4')).writeAsStringSync('b');
    File(p.join(module.path, '02 second.mp4')).writeAsStringSync('c');
    File(p.join(module.path, 'cover.png')).writeAsStringSync('module cover');
    final imported = await importCourseFromFolder(root.path);
    courseId = imported!.course.id;
  });

  for (final size in <String, Size>{
    'narrow 560': const Size(560, 760),
    'compact 900': const Size(900, 760),
    'wide 1600': const Size(1600, 800),
  }.entries) {
    testWidgets('detail page lays out at ${size.key}', (tester) async {
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
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: CourseDetailPage(courseId: courseId)),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      final error = tester.takeException();
      if (error != null) {
        for (final d in errors) {
          // ignore: avoid_print
          print('--- ${size.key} ---\n$d');
        }
      }
      expect(error, isNull, reason: '${size.key}: $error');
      expect(find.text('Open folder'), findsOneWidget);
      final rect = tester.getRect(find.text('Open folder'));
      expect(rect.right, lessThanOrEqualTo(size.value.width));
    });
  }

  testWidgets('a lesson can be moved with the row menu', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: CourseDetailPage(courseId: courseId)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    final before = await tester.runAsync(() => Store.i.lessons(courseId)) ?? [];
    final moduleIds = before.where((l) => l.moduleId != null).map((l) => l.id).toList();
    expect(moduleIds.length, 2);

    // Open the first module lesson and move it down one slot.
    final optionsBtn = find.byTooltip('Lesson options').first;
    await tester.ensureVisible(optionsBtn);
    await tester.pumpAndSettle();
    await tester.tap(optionsBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move lesson down').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    final after = await tester.runAsync(() => Store.i.lessons(courseId)) ?? [];
    final afterModuleIds =
        after.where((l) => l.moduleId != null).map((l) => l.id).toList();
    expect(afterModuleIds, moduleIds.reversed.toList(),
        reason: 'the drag rewrote the lesson positions');
  });

  testWidgets('lessons and whole modules can be marked complete by hand',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: CourseDetailPage(courseId: courseId)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    // The first lesson checkbox toggles that lesson only.
    final lessonBox = find.byTooltip('Mark as completed').first;
    await tester.ensureVisible(lessonBox);
    await tester.pumpAndSettle();
    await tester.tap(lessonBox);
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
    await tester.pump();

    var progress = await tester.runAsync(() => Store.i.courseProgressMap(courseId)) ?? {};
    expect(progress.values.where((p) => p.completed).length, 1);

    // Mark the whole course complete from the header action.
    await tester.tap(find.text('Mark all complete'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();

    progress = await tester.runAsync(() => Store.i.courseProgressMap(courseId)) ?? {};
    final lessons = await tester.runAsync(() => Store.i.lessons(courseId)) ?? [];
    expect(progress.values.where((p) => p.completed).length, lessons.length);
  });

  testWidgets('module gallery shows covers and opens a module', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: CourseDetailPage(courseId: courseId)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    await tester.tap(find.byTooltip('Gallery view'));
    await tester.pumpAndSettle();

    // Cards replace the rows, and the module cover picked from the folder is used.
    expect(find.byTooltip('Change module cover'), findsWidgets);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);

    // Metadata pass filled the covers from IMG.jpg / cover.png.
    final course = await tester.runAsync(() => Store.i.course(courseId));
    expect(course!.cover, isNotNull);
    final modules = await tester.runAsync(() => Store.i.modules(courseId)) ?? [];
    expect(modules.any((m) => m.cover != null && m.cover!.endsWith('cover.png')), isTrue);

    await tester.tap(find.text('02 Module').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Mark module'), findsWidgets);
  });
}