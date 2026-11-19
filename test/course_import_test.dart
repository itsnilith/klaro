import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:klaro/core/course_import.dart';
import 'package:klaro/core/db.dart';
import 'test_paths.dart';

/// Importing a folder must build modules from sub-folders, keep every path as
/// found, and never modify the files themselves.
void main() {
  late Directory root;

  setUpAll(() async {
    testPaths();
    await Store.open();
  });

  setUp(() {
    root = Directory.systemTemp.createTempSync('klaro-import-');
    File(p.join(root.path, '01 intro.mp4')).writeAsStringSync('a');
    final module = Directory(p.join(root.path, '02 Module'))..createSync();
    File(p.join(module.path, '01 first.mp4')).writeAsStringSync('b');
    File(p.join(module.path, '02 second.mkv')).writeAsStringSync('c');
    File(p.join(root.path, 'slides.pdf')).writeAsStringSync('d');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('sub-folders become modules and files stay where they are', () async {
    final before = Directory(root.path)
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => '${f.path}:${f.lengthSync()}')
        .toList()
      ..sort();

    final result = await importCourseFromFolder(root.path);
    expect(result, isNotNull);
    expect(result!.lessonCount, 3);
    expect(result.documentCount, 1);
    expect(result.course.folder, root.path);

    final modules = await Store.i.modules(result.course.id);
    expect(modules.map((m) => m.title), contains('02 Module'));
    final lessons = await Store.i.lessons(result.course.id);
    expect(lessons.length, 3);
    expect(lessons.every((l) => File(l.path!).existsSync()), isTrue);
    final moduleLesson = lessons.firstWhere((l) => l.path!.contains('02 Module'));
    expect(moduleLesson.moduleId, isNotNull);

    final after = Directory(root.path)
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => '${f.path}:${f.lengthSync()}')
        .toList()
      ..sort();
    expect(after, before, reason: 'the import only reads the folder');
  });

  test('an empty folder imports nothing', () async {
    final empty = Directory.systemTemp.createTempSync('klaro-import-empty-');
    addTearDown(() => empty.deleteSync(recursive: true));
    expect(await importCourseFromFolder(empty.path), isNull);
  });
}