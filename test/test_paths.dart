import 'dart:io';

import 'package:klaro/core/paths.dart';

/// Isolated storage for one test file.
///
/// Every file gets its own folder and database, so parallel `flutter test`
/// runs never share a SQLite file and stale rows from an earlier run cannot
/// leak into a layout test.
AppPaths testPaths() {
  final root = Directory.systemTemp.createTempSync('klaro-test-');
  return AppPaths.initAt(root.path);
}
