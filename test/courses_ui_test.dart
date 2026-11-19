import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/core/db.dart';
import 'package:klaro/core/models.dart';
import 'test_paths.dart';
import 'package:klaro/design/tokens.dart';
import 'package:klaro/features/courses/courses_page.dart';

/// The course list offers "Remove from list" and "Open folder", and the detail
/// page exposes reordering. Removing must not delete anything.
void main() {
  late Directory root;
  late Course course;

  setUpAll(() async {
    testPaths();
    await Store.open();
    // Earlier runs of this file leave rows behind in the shared test database.
    for (final c in await Store.i.courses(includeArchived: true)) {
      if (c.id.startsWith('ui-')) await Store.i.deleteCourse(c.id);
    }
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('klaro-ui-course-');
    final video = File('${root.path}${Platform.pathSeparator}01 intro.mp4')
      ..writeAsStringSync('x');
    final now = DateTime.now();
    course = Course(
      id: 'ui-${DateTime.now().microsecondsSinceEpoch}',
      title: 'UI Course',
      folder: root.path,
      createdAt: now,
      updatedAt: now,
    );
    await Store.i.saveCourse(course);
    await Store.i.saveModule(
        Module(id: '${course.id}-m', courseId: course.id, title: 'Module 1', position: 0));
    await Store.i.saveLesson(Lesson(
      id: '${course.id}-l',
      courseId: course.id,
      moduleId: '${course.id}-m',
      title: 'Lesson one',
      path: video.path,
      position: 0,
      createdAt: now,
    ));
  });

  tearDown(() async {
    await Store.i.deleteCourse(course.id);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  testWidgets('the tile menu removes the course from the list only', (tester) async {
    tester.view.physicalSize = const Size(1200, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: CoursesPage()),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();

    expect(find.text('UI Course'), findsWidgets);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('Open folder'), findsOneWidget);
    expect(find.text('Remove from list'), findsOneWidget);

    await tester.tap(find.text('Remove from list'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();

    final stored = await tester.runAsync(() => Store.i.course(course.id));
    expect(stored, isNotNull, reason: 'the course row is kept');
    expect(stored!.archived, isTrue);
    expect(find.text('UI Course'), findsNothing, reason: 'hidden from the list');
    expect(File('${root.path}${Platform.pathSeparator}01 intro.mp4').existsSync(), isTrue);

    await tester.runAsync(() => Store.i.setCourseArchived(course.id, false));
  });

  testWidgets('the detail page exposes folder and reordering', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: CourseDetailPage(courseId: course.id)),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    // Let the tag bar finish its first database read.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump();

    expect(find.text('Open folder'), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsWidgets);
    expect(find.byTooltip('Move module up'), findsWidgets);
    expect(find.byTooltip('Move module down'), findsWidgets);
    // Context sidebar: attachments and the tutor are one click away.
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('AI Tutor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}