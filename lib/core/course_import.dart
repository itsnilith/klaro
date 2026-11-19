import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'course_files.dart';
import 'db.dart';
import 'models.dart';

const _uuid = Uuid();

const videoExtensions = {
  'mp4',
  'mkv',
  'webm',
  'mov',
  'avi',
  'm4v',
  'mp3',
  'm4a',
  'wav',
};
const documentExtensions = {
  'pdf',
  'md',
  'txt',
  'pptx',
  'ppt',
  'docx',
  'doc',
  'xlsx',
  'xls',
  'csv',
  'png',
  'jpg',
  'jpeg',
  'webp',
};
const _imageExtensions = {'png', 'jpg', 'jpeg', 'webp'};
const _coverNames = {
  'img',
  'cover',
  'poster',
  'thumbnail',
  'thumb',
  'banner',
  'folder',
  'logo',
};

/// Natural comparison so "2. Lesson" comes before "10. Lesson".
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final ma = re.allMatches(a.toLowerCase()).toList();
  final mb = re.allMatches(b.toLowerCase()).toList();
  final len = ma.length < mb.length ? ma.length : mb.length;
  for (var i = 0; i < len; i++) {
    final sa = ma[i].group(0)!;
    final sb = mb[i].group(0)!;
    final na = int.tryParse(sa);
    final nb = int.tryParse(sb);
    if (na != null && nb != null) {
      final c = na.compareTo(nb);
      if (c != 0) return c;
    } else {
      final c = sa.compareTo(sb);
      if (c != 0) return c;
    }
  }
  return ma.length.compareTo(mb.length);
}

bool _isCoverFile(String path) {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  if (!_imageExtensions.contains(ext)) return false;
  final base = p.basenameWithoutExtension(path).toLowerCase();
  return _coverNames.contains(base);
}

String? findFolderCover(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return null;
  try {
    final files = dir.listSync(followLinks: false).whereType<File>().toList();
    // Prefer img/cover/poster over logo.
    const priority = [
      'img',
      'cover',
      'poster',
      'thumbnail',
      'thumb',
      'banner',
      'folder',
      'logo',
    ];
    for (final wanted in priority) {
      for (final f in files) {
        final ext = p.extension(f.path).replaceFirst('.', '').toLowerCase();
        if (!_imageExtensions.contains(ext)) continue;
        if (p.basenameWithoutExtension(f.path).toLowerCase() == wanted) {
          return f.path;
        }
      }
    }
  } catch (_) {}
  return null;
}

/// What an import produced. Files are only read: the course is a catalogue
/// entry that points at the folder in place.
class CourseImport {
  const CourseImport({
    required this.course,
    required this.lessonCount,
    required this.documentCount,
  });

  final Course course;
  final int lessonCount;
  final int documentCount;
}

/// Scans [dir] recursively and records a course.
///
/// Sub-folders become modules, video files become lessons in natural order and
/// documents are attached as course resources. Nothing is moved, copied or
/// deleted: every path is stored exactly as found on disk.
///
/// Returns null when the folder holds nothing usable.
Future<CourseImport?> importCourseFromFolder(
  String dir, {
  String? title,
}) async {
  final root = Directory(dir);
  if (!root.existsSync()) return null;

  final videos = <File>[];
  final others = <File>[];
  await for (final e in root.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final name = p.basename(e.path);
    if (name.startsWith('._') || name == '.DS_Store') continue;
    final ext = p.extension(e.path).replaceFirst('.', '').toLowerCase();
    if (videoExtensions.contains(ext)) {
      videos.add(e);
    } else if (documentExtensions.contains(ext) && !_isCoverFile(e.path)) {
      others.add(e);
    }
  }
  if (videos.isEmpty && others.isEmpty) return null;
  videos.sort((a, b) => naturalCompare(a.path, b.path));
  others.sort((a, b) => naturalCompare(a.path, b.path));

  final now = DateTime.now();
  final courseCover = findFolderCover(root.path);
  final course = Course(
    id: _uuid.v4(),
    title: title ?? p.basename(root.path),
    description: 'Imported from ${root.path}',
    cover: courseCover,
    folder: root.path,
    createdAt: now,
    updatedAt: now,
  );
  await Store.i.saveCourse(course);

  final byFolder = <String, List<File>>{};
  for (final v in videos) {
    final rel = p.relative(v.path, from: dir);
    final folder = p.dirname(rel);
    byFolder.putIfAbsent(folder == '.' ? '' : folder, () => []).add(v);
  }

  // Keep the folder order natural and sort lessons naturally inside each module.
  final folderKeys = byFolder.keys.toList()..sort(naturalCompare);
  var modulePos = 0;
  var lessonPos = 0;
  final modulesToSave = <Module>[];
  final lessonsToSave = <Lesson>[];
  for (final key in folderKeys) {
    String? moduleId;
    if (key.isNotEmpty) {
      moduleId = _uuid.v4();
      final modCover = findFolderCover(p.join(root.path, key));
      modulesToSave.add(
        Module(
          id: moduleId,
          courseId: course.id,
          title: key,
          position: modulePos++,
          cover: modCover,
        ),
      );
    }
    final moduleVideos = byFolder[key]!
      ..sort((a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)));
    for (final f in moduleVideos) {
      lessonsToSave.add(
        Lesson(
          id: _uuid.v4(),
          courseId: course.id,
          moduleId: moduleId,
          title: p.basenameWithoutExtension(f.path),
          path: f.path,
          kind:
              {'mp3', 'm4a', 'wav'}.contains(
                p.extension(f.path).replaceFirst('.', '').toLowerCase(),
              )
              ? 'audio'
              : 'video',
          position: lessonPos++,
          createdAt: now,
        ),
      );
    }
  }
  final resourcesToSave =
      <({String title, String path, String kind, int size})>[];
  for (final f in others) {
    resourcesToSave.add((
      title: p.basename(f.path),
      path: f.path,
      kind: _kindFor(p.extension(f.path).replaceFirst('.', '').toLowerCase()),
      size: await f.length(),
    ));
  }
  await Store.i.saveCourseImportBatch(
    courseId: course.id,
    modules: modulesToSave,
    lessons: lessonsToSave,
    resources: resourcesToSave,
  );

  return CourseImport(
    course: course,
    lessonCount: videos.length,
    documentCount: others.length,
  );
}

/// Repairs courses imported before v12 so their cover, module covers and
/// natural module/lesson order are populated without re-importing.
Future<void> ensureCourseMetadata(
  Course course,
  List<Module> modules,
  List<Lesson> lessons,
) async {
  final root = courseFolderOf(course, lessons: lessons);
  if (root == null) return;

  if (course.cover == null || course.cover!.isEmpty) {
    final detected = findFolderCover(root);
    if (detected != null) {
      await Store.i.setCourseCover(course.id, detected);
    }
  }

  for (final m in modules) {
    if (m.cover == null || m.cover!.isEmpty) {
      final detected = findFolderCover(p.join(root, m.title));
      if (detected != null) {
        await Store.i.setModuleCover(m.id, detected);
      }
    }
  }

  // If modules are still in ASCII order (e.g. "1.", "10.", "2."), re-order them
  // and their lessons into natural order.
  final sortedModules = [...modules]
    ..sort((a, b) => naturalCompare(a.title, b.title));
  var asciiSorted = true;
  final asciiModules = [...modules]..sort((a, b) => a.title.compareTo(b.title));
  for (var i = 0; i < modules.length; i++) {
    if (modules[i].id != asciiModules[i].id) {
      asciiSorted = false;
      break;
    }
  }
  var needsNaturalModuleOrder = false;
  for (var i = 0; i < modules.length; i++) {
    if (modules[i].id != sortedModules[i].id) {
      needsNaturalModuleOrder = true;
      break;
    }
  }
  if (asciiSorted && needsNaturalModuleOrder) {
    await Store.i.reorderModules(sortedModules.map((m) => m.id).toList());
  }

  // Check if any module's lessons are still in ASCII order ("1.", "10.", "2.").
  var lessonOrderChanged = false;
  final orderedLessonIds = <String>[];
  final moduleSequence = (asciiSorted && needsNaturalModuleOrder)
      ? sortedModules
      : modules;
  for (final m in moduleSequence) {
    final group = lessons.where((l) => l.moduleId == m.id).toList();
    final natural = [...group]
      ..sort((a, b) => naturalCompare(a.title, b.title));
    final ascii = [...group]..sort((a, b) => a.title.compareTo(b.title));
    var isAscii = true;
    var differsFromNatural = false;
    for (var i = 0; i < group.length; i++) {
      if (group[i].id != ascii[i].id) isAscii = false;
      if (group[i].id != natural[i].id) differsFromNatural = true;
    }
    if (isAscii && differsFromNatural) {
      lessonOrderChanged = true;
      orderedLessonIds.addAll(natural.map((l) => l.id));
    } else {
      orderedLessonIds.addAll(group.map((l) => l.id));
    }
  }
  final loose = lessons.where((l) => l.moduleId == null).toList()
    ..sort((a, b) => naturalCompare(a.title, b.title));
  orderedLessonIds.addAll(loose.map((l) => l.id));
  if (lessonOrderChanged || (asciiSorted && needsNaturalModuleOrder)) {
    await Store.i.reorderLessons(orderedLessonIds);
  }
}

String _kindFor(String ext) => switch (ext) {
  'pdf' => 'pdf',
  'md' || 'txt' => 'text',
  'png' || 'jpg' || 'jpeg' || 'webp' => 'image',
  'pptx' || 'ppt' || 'docx' || 'doc' || 'xlsx' || 'xls' || 'csv' => 'document',
  _ => 'file',
};
