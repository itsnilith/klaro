import 'dart:io';

import 'package:klaro/core/course_import.dart';
import 'package:klaro/core/db.dart';
import 'package:klaro/core/paths.dart';

/// Records one or more course folders in klaro.'s database, exactly like the
/// in-app "Import folder" action. Files are only read, never moved or deleted.
///
/// Usage:
///   dart run tool/seed_course.dart --root "C:\path\to\Klaro-Portable" "D:\course 1" "D:\course 2"
Future<void> main(List<String> args) async {
  final rootIndex = args.indexOf('--root');
  final root = rootIndex >= 0 && rootIndex + 1 < args.length ? args[rootIndex + 1] : null;
  final folders = [
    for (var i = 0; i < args.length; i++)
      if (i != rootIndex && i != rootIndex + 1) args[i],
  ];

  if (root != null) {
    AppPaths.initAt(root);
  } else {
    AppPaths.init();
  }
  await Store.open();

  for (final folder in folders) {
    if (!Directory(folder).existsSync()) {
      stdout.writeln('skip (missing): $folder');
      continue;
    }
    final result = await importCourseFromFolder(folder);
    if (result == null) {
      stdout.writeln('skip (nothing usable): $folder');
      continue;
    }
    stdout.writeln(
      'imported "${result.course.title}" lessons=${result.lessonCount} '
      'documents=${result.documentCount} folder=${result.course.folder}',
    );
  }
  await Store.i.db.close();
}
