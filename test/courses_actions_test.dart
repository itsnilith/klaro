import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:klaro/core/course_files.dart';
import 'package:klaro/core/db.dart';
import 'package:klaro/core/models.dart';
import 'test_paths.dart';

/// A course can be taken out of the list without a single file being touched,
/// and its lessons and modules can be reordered.
void main() {
  late Directory root;
  late Course course;

  setUpAll(() async {
    testPaths();
    await Store.open();
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('klaro-course-');
    File('${root.path}${Platform.pathSeparator}01 intro.mp4').writeAsStringSync('a');
    final sub = Directory('${root.path}${Platform.pathSeparator}Module A')..createSync();
    File('${sub.path}${Platform.pathSeparator}02 lesson.mp4').writeAsStringSync('b');

    final now = DateTime.now();
    course = Course(
      id: 'course-${DateTime.now().microsecondsSinceEpoch}',
      title: 'Test course',
      folder: root.path,
      createdAt: now,
      updatedAt: now,
    );
    await Store.i.saveCourse(course);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('hiding a course keeps its row and every file on disk', () async {
    final now = DateTime.now();
    final module = Module(id: '${course.id}-m1', courseId: course.id, title: 'Module A', position: 0);
    await Store.i.saveModule(module);
    await Store.i.saveLesson(Lesson(
      id: '${course.id}-l1',
      courseId: course.id,
      moduleId: module.id,
      title: 'Intro',
      path: '${root.path}${Platform.pathSeparator}01 intro.mp4',
      position: 0,
      createdAt: now,
    ));

    await Store.i.setCourseArchived(course.id, true);

    final visible = await Store.i.courses();
    final all = await Store.i.courses(includeArchived: true);
    expect(visible.any((c) => c.id == course.id), isFalse);
    expect(all.any((c) => c.id == course.id), isTrue);
    expect((await Store.i.lessons(course.id)).length, 1);
    expect(File('${root.path}${Platform.pathSeparator}01 intro.mp4').existsSync(), isTrue);

    await Store.i.setCourseArchived(course.id, false);
    expect((await Store.i.courses()).any((c) => c.id == course.id), isTrue);
  });

  test('lessons and modules can be reordered without touching files', () async {
    final now = DateTime.now();
    for (var i = 0; i < 3; i++) {
      await Store.i.saveLesson(Lesson(
        id: '${course.id}-r$i',
        courseId: course.id,
        title: 'Lesson $i',
        path: '${root.path}${Platform.pathSeparator}01 intro.mp4',
        position: i,
        createdAt: now,
      ));
    }
    final ordered = ['${course.id}-r2', '${course.id}-r0', '${course.id}-r1'];
    await Store.i.reorderLessons(ordered);
    expect((await Store.i.lessons(course.id)).map((l) => l.id).toList(), ordered);

    for (var i = 0; i < 2; i++) {
      await Store.i.saveModule(Module(
          id: '${course.id}-mm$i', courseId: course.id, title: 'M$i', position: i));
    }
    await Store.i.reorderModules(['${course.id}-mm1', '${course.id}-mm0']);
    expect((await Store.i.modules(course.id)).map((m) => m.id).toList(),
        ['${course.id}-mm1', '${course.id}-mm0']);

    expect(Directory(root.path).listSync().length, greaterThanOrEqualTo(2));
  });

  test('the folder comes from the course, or from the common lesson folder', () async {
    expect(courseFolderOf(course), root.path);

    final legacy = Course(
      id: '${course.id}-legacy',
      title: 'Legacy',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final now = DateTime.now();
    final lessons = [
      Lesson(
        id: 'a',
        courseId: legacy.id,
        title: 'A',
        path: '${root.path}${Platform.pathSeparator}01 intro.mp4',
        position: 0,
        createdAt: now,
      ),
      Lesson(
        id: 'b',
        courseId: legacy.id,
        title: 'B',
        path: '${root.path}${Platform.pathSeparator}Module A'
            '${Platform.pathSeparator}02 lesson.mp4',
        position: 1,
        createdAt: now,
      ),
    ];
    expect(courseFolderOf(legacy, lessons: lessons), root.path);
    expect(courseFolderOf(legacy), isNull);
  });

  test('tags can be created, assigned, renamed and deleted cleanly', () async {
    final tag = await Store.i.createTag('Exam prep');
    expect(tag.name, 'Exam prep');

    await Store.i.setTagIdsFor('course', course.id, {tag.id});
    var assigned = await Store.i.tagsFor('course', course.id);
    expect(assigned.map((t) => t.name), contains('Exam prep'));

    await Store.i.renameTag(tag.id, 'Finals');
    assigned = await Store.i.tagsFor('course', course.id);
    expect(assigned.first.name, 'Finals');

    final reused = await Store.i.createTag('finals');
    expect(reused.id, tag.id, reason: 'names are unique, case-insensitively');

    await Store.i.deleteTag(tag.id);
    expect(await Store.i.tagsFor('course', course.id), isEmpty);
    expect(await Store.i.tagUsage(tag.id), 0);
  });

  test('a lesson description is stored and editable', () async {
    final now = DateTime.now();
    final lesson = Lesson(
      id: '${course.id}-desc',
      courseId: course.id,
      title: 'Described',
      description: 'First pass',
      createdAt: now,
    );
    await Store.i.saveLesson(lesson);
    expect((await Store.i.lesson(lesson.id))!.description, 'First pass');

    await Store.i.setLessonDescription(lesson.id, 'Edited copy');
    expect((await Store.i.lesson(lesson.id))!.description, 'Edited copy');

    await Store.i.renameLesson(lesson.id, 'Renamed');
    final stored = await Store.i.lesson(lesson.id);
    expect(stored!.title, 'Renamed');
    expect(stored.description, 'Edited copy');
  });

  test('the Library lists standalone items, not course attachments', () async {
    final file = File('${root.path}${Platform.pathSeparator}book.pdf')
      ..writeAsStringSync('x');
    final standalone = await Store.i.addResource(
      title: 'Standalone book',
      path: file.path,
      kind: 'pdf',
      size: 10,
    );
    final attached = await Store.i.addResource(
      title: 'Course handout',
      path: file.path,
      kind: 'pdf',
      size: 10,
      courseId: course.id,
    );

    final library = await Store.i.resources(standaloneOnly: true);
    expect(library.any((r) => r.id == standalone), isTrue);
    expect(library.any((r) => r.id == attached), isFalse);
    expect((await Store.i.resources()).any((r) => r.id == attached), isTrue);

    await Store.i.deleteResource(standalone);
    await Store.i.deleteResource(attached);
  });
}