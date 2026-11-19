import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';

/// Folder a course lives in.
///
/// Courses imported through "Import folder" remember it explicitly. Older
/// entries fall back to the deepest folder that contains every lesson and
/// attachment, so "Open folder" works for libraries imported before this was
/// stored. Nothing here reads or writes the files themselves.
String? courseFolderOf(
  Course course, {
  List<Lesson> lessons = const [],
  List<LibraryResource> resources = const [],
}) {
  final explicit = course.folder;
  if (explicit != null && explicit.trim().isNotEmpty) return explicit;
  final dirs = <String>[
    ...lessons.map((l) => l.path).whereType<String>(),
    ...resources.map((r) => r.path),
  ].where((path) => path.trim().isNotEmpty);
  return _commonDir(dirs);
}

String? _commonDir(Iterable<String> files) {
  final dirs = files.map((f) => p.dirname(f)).toList();
  if (dirs.isEmpty) return null;
  var common = p.split(dirs.first);
  for (final dir in dirs.skip(1)) {
    final parts = p.split(dir);
    var i = 0;
    while (i < common.length &&
        i < parts.length &&
        common[i].toLowerCase() == parts[i].toLowerCase()) {
      i++;
    }
    common = common.sublist(0, i);
    if (common.isEmpty) return null;
  }
  if (common.isEmpty) return null;
  return p.joinAll(common);
}

/// Opens [path] in the system file manager. Returns false when the folder no
/// longer exists, so callers can explain instead of failing silently.
Future<bool> openFolderInExplorer(String path) async {
  final dir = Directory(path);
  if (!dir.existsSync()) return false;
  return launchUrl(dir.uri, mode: LaunchMode.externalApplication);
}

/// Opens the containing folder of a single file, selecting nothing but landing
/// the user where the file lives.
Future<bool> revealFileInExplorer(String path) async {
  final file = File(path);
  if (!file.existsSync()) return false;
  return launchUrl(file.parent.uri, mode: LaunchMode.externalApplication);
}
