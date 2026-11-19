import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/course_files.dart';
import '../../core/i18n.dart';
import '../../core/course_import.dart';
import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../services/transcription.dart';
import '../../services/whisper_models.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../shell.dart';
import '../shell_dialogs.dart';
import '../tags/tag_bar.dart';
import 'course_sidebar.dart';
import 'module_content_dialogs.dart';
import 'module_quiz_generator.dart';

const _uuid = Uuid();

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  List<Course> _courses = const [];
  String _query = '';
  String _filter = 'all';
  bool _grid = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    AppState.i.addListener(_load);
  }

  @override
  void dispose() {
    AppState.i.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final list = await Store.i.courses(includeArchived: true);
    if (!mounted) return;
    setState(() {
      _courses = list;
      _loading = false;
    });
  }

  List<Course> get _visible {
    var list = _courses;
    if (_filter == 'favorites') list = list.where((c) => c.favorite).toList();
    if (_filter == 'archived') list = list.where((c) => c.archived).toList();
    if (_filter != 'archived') list = list.where((c) => !c.archived).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where(
            (c) =>
                c.title.toLowerCase().contains(q) ||
                (c.author ?? '').toLowerCase().contains(q) ||
                (c.category ?? '').toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final visible = _visible;
    return MSmoothScrollView(
      padding: const EdgeInsets.fromLTRB(22, 10, 32, 32),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L.of(context).t('courses'),
                      style: MType.h1.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_courses.where((e) => !e.archived).length} active - video files stay in their original folders',
                      style: MType.small.copyWith(color: c.inkMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 260,
                      child: TextField(
                        style: MType.body.copyWith(color: c.ink, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: L.of(context).t('filterCourses'),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 17,
                          ),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    MChip(
                      label: L.of(context).t('all'),
                      selected: _filter == 'all',
                      onTap: () => setState(() => _filter = 'all'),
                    ),
                    MChip(
                      label: L.of(context).t('favorites'),
                      selected: _filter == 'favorites',
                      onTap: () => setState(() => _filter = 'favorites'),
                    ),
                    MChip(
                      label: L.of(context).t('hidden'),
                      selected: _filter == 'archived',
                      onTap: () => setState(() => _filter = 'archived'),
                    ),
                    MIconButton(
                      icon: Icons.grid_view_rounded,
                      tooltip: 'Grid',
                      selected: _grid,
                      onPressed: () => setState(() => _grid = true),
                    ),
                    MIconButton(
                      icon: Icons.view_list_rounded,
                      tooltip: 'List',
                      selected: !_grid,
                      onPressed: () => setState(() => _grid = false),
                    ),
                    MButton(
                      label: 'Import folder',
                      icon: Icons.create_new_folder_outlined,
                      dense: true,
                      onPressed: () async {
                        await importCourseFolder(context);
                        _load();
                      },
                    ),
                    MButton(
                      label: 'New course',
                      icon: Icons.add_rounded,
                      kind: MButtonKind.primary,
                      dense: true,
                      onPressed: () async {
                        await showCourseEditor(context);
                        _load();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (visible.isEmpty)
                  MEmpty(
                    icon: Icons.play_lesson_outlined,
                    title: _query.isEmpty
                        ? L.of(context).t('noCourses')
                        : L.of(context).t('noCourses'),
                    message: _query.isEmpty
                        ? 'Import a folder of videos, or create a course and add lessons one by one.'
                        : 'Try a different word, or clear the filters.',
                    action: MButton(
                      label: L.of(context).t('importCourseFolder'),
                      kind: MButtonKind.primary,
                      onPressed: () async {
                        await importCourseFolder(context);
                        _load();
                      },
                    ),
                  )
                else if (_grid)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth > 1400
                          ? 5
                          : constraints.maxWidth > 1100
                          ? 4
                          : constraints.maxWidth > 820
                          ? 3
                          : constraints.maxWidth > 520
                          ? 2
                          : 1;
                      final w = (constraints.maxWidth - (cols - 1) * 16) / cols;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final course in visible)
                            SizedBox(
                              width: w,
                              child: _CourseTile(
                                course: course,
                                onOpen: () => Nav.course(context, course.id),
                                onChanged: _load,
                              ),
                            ),
                        ],
                      );
                    },
                  )
                else
                  MCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < visible.length; i++) ...[
                          _CourseListRow(
                            course: visible[i],
                            onOpen: () => Nav.course(context, visible[i].id),
                            onChanged: _load,
                          ),
                          if (i < visible.length - 1) const MDivider(),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseTile extends StatefulWidget {
  const _CourseTile({
    required this.course,
    required this.onOpen,
    required this.onChanged,
  });
  final Course course;
  final VoidCallback onOpen;
  final VoidCallback onChanged;

  @override
  State<_CourseTile> createState() => _CourseTileState();
}

class _CourseTileState extends State<_CourseTile> {
  Map<String, int> _progress = const {'total': 0, 'done': 0};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await Store.i.courseProgress(widget.course.id);
    if (mounted) setState(() => _progress = p);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final course = widget.course;
    final total = _progress['total'] ?? 0;
    final done = _progress['done'] ?? 0;
    final ratio = total == 0 ? 0.0 : done / total;
    return MCard(
      padding: EdgeInsets.zero,
      clip: true,
      onTap: widget.onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              _Cover(title: course.title, cover: course.cover, height: 118),
              Positioned(
                top: 8,
                right: 8,
                child: _IconBubble(
                  icon: course.favorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  active: course.favorite,
                  onTap: () async {
                    await Store.i.saveCourse(
                      course.copyWith(
                        favorite: !course.favorite,
                        updatedAt: DateTime.now(),
                      ),
                    );
                    AppState.i.bump();
                    widget.onChanged();
                  },
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: _IconBubble(
                  icon: Icons.more_horiz_rounded,
                  onTap: () => _menu(context),
                ),
              ),
              if (course.archived)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(MRadius.pill),
                    ),
                    child: Text(
                      'Hidden',
                      style: MType.small.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MType.bodyStrong.copyWith(
                    color: c.ink,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  course.author?.isNotEmpty == true
                      ? course.author!
                      : '$total ${total == 1 ? 'lesson' : 'lessons'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MType.small.copyWith(color: c.inkFaint, fontSize: 11),
                ),
                const SizedBox(height: 12),
                MProgress(value: ratio, height: 4),
                const SizedBox(height: 6),
                Text(
                  '$done of $total complete',
                  style: MType.small.copyWith(
                    color: c.inkFaint,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final c = context.c;
    // Anchor the menu to the tile: showMenu requires an explicit position.
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final position = (box == null || overlay == null)
        ? const RelativeRect.fromLTRB(0, 0, 0, 0)
        : RelativeRect.fromRect(
            Rect.fromPoints(
              box.localToGlobal(Offset.zero, ancestor: overlay),
              box.localToGlobal(
                box.size.bottomRight(Offset.zero),
                ancestor: overlay,
              ),
            ),
            Offset.zero & overlay.size,
          );
    final action = await showMenu<String>(
      context: context,
      position: position,
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
        side: BorderSide(color: c.line),
      ),
      items: [
        _menuItem('open-folder', Icons.folder_open_outlined, 'Open folder'),
        _menuItem('edit', Icons.edit_outlined, 'Edit details'),
        _menuItem('duplicate', Icons.copy_all_outlined, 'Duplicate'),
        _menuItem(
          'hide',
          widget.course.archived
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          widget.course.archived ? 'Show in list' : 'Remove from list',
        ),
        _menuItem(
          'delete',
          Icons.delete_outline_rounded,
          'Delete from library',
          danger: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'open-folder':
        if (!context.mounted) return;
        await _openCourseFolder(context);
        return;
      case 'edit':
        if (context.mounted) {
          await showCourseEditor(context, course: widget.course);
        }
      case 'duplicate':
        final now = DateTime.now();
        final copy = Course(
          id: _uuid.v4(),
          title: '${widget.course.title} (copy)',
          author: widget.course.author,
          description: widget.course.description,
          category: widget.course.category,
          objectives: widget.course.objectives,
          cover: widget.course.cover,
          folder: widget.course.folder,
          createdAt: now,
          updatedAt: now,
        );
        await Store.i.saveCourse(copy);
        for (final l in await Store.i.lessons(widget.course.id)) {
          await Store.i.saveLesson(
            Lesson(
              id: _uuid.v4(),
              courseId: copy.id,
              title: l.title,
              path: l.path,
              kind: l.kind,
              durationMs: l.durationMs,
              position: l.position,
              createdAt: now,
            ),
          );
        }
      case 'hide':
        await Store.i.setCourseArchived(
          widget.course.id,
          !widget.course.archived,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.course.archived ? 'Course shown in the list again.' : 'Removed from the list. Its folder, videos and attachments were not touched.',
              ),
            ),
          );
        }
      case 'delete':
        if (!context.mounted) return;
        final ok = await _confirmDelete(context, widget.course.title);
        if (ok) await Store.i.deleteCourse(widget.course.id);
    }
    AppState.i.bump();
    widget.onChanged();
  }

  Future<void> _openCourseFolder(BuildContext context) async {
    final lessons = await Store.i.lessons(widget.course.id);
    final resources = await Store.i.resources(courseId: widget.course.id);
    final folder = courseFolderOf(
      widget.course,
      lessons: lessons,
      resources: resources,
    );
    if (folder == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This course has no folder on disk to open.'),
          ),
        );
      }
      return;
    }
    final opened = await openFolderInExplorer(folder);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Folder not found: $folder')));
    }
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final c = context.c;
    return PopupMenuItem(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 15, color: danger ? c.danger : c.inkMuted),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MType.small.copyWith(
                color: danger ? c.danger : c.ink,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseListRow extends StatelessWidget {
  const _CourseListRow({
    required this.course,
    required this.onOpen,
    required this.onChanged,
  });
  final Course course;
  final VoidCallback onOpen;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(MSpace.x2),
              child: SizedBox(
                width: 56,
                height: 40,
                child: _Cover(
                  title: course.title,
                  cover: course.cover,
                  height: 40,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.bodyStrong.copyWith(
                      color: c.ink,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    [
                      course.author,
                      course.category,
                    ].whereType<String>().join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.small.copyWith(
                      color: c.inkFaint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (course.archived)
              MChip(label: 'Hidden', icon: Icons.visibility_off_outlined),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.title,
    required this.cover,
    required this.height,
  });
  final String title;
  final String? cover;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (cover != null && File(cover!).existsSync()) {
      return Image.file(
        File(cover!),
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }
    final initials = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Container(
      height: height,
      width: double.infinity,
      color: c.surfaceSunken,
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: c.accentSoft,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 14,
            bottom: 10,
            child: Text(
              initials.isEmpty ? 'K' : initials,
              style: MType.h1.copyWith(
                color: c.ink.withValues(alpha: 0.7),
                fontSize: 26,
                letterSpacing: -0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({
    required this.icon,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(MSpace.x2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MSpace.x2),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 15, color: active ? c.amber : c.inkMuted),
        ),
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, String title) async {
  final result = await showMSheet<bool>(
    context,
    maxWidth: 420,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delete "$title"?',
            style: MType.h2.copyWith(color: context.c.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Only the Klaro entry is removed: the course, its lessons and their progress. '
            'The folder on disk, its videos and attachments stay exactly where they are.',
            style: MType.small.copyWith(color: context.c.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MButton(
                label: 'Keep it',
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(width: 8),
              MButton(
                label: 'Delete entry',
                kind: MButtonKind.danger,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Course detail

class CourseDetailPage extends StatefulWidget {
  const CourseDetailPage({
    super.key,
    required this.courseId,
    this.quizGenerator,
  });

  final String courseId;
  final ModuleQuizGeneratorOverride? quizGenerator;

  @override
  State<CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends State<CourseDetailPage> {
  Course? _course;
  List<Module> _modules = const [];
  List<Lesson> _lessons = const [];
  List<LibraryResource> _resources = const [];
  List<Note> _notes = const [];
  Map<String, Progress> _progress = const {};
  Set<String> _bookmarkedLessons = const {};

  @override
  void initState() {
    super.initState();
    _load();
    AppState.i.addListener(_load);
  }

  @override
  void dispose() {
    AppState.i.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final course = await Store.i.course(widget.courseId);
    if (course == null) return;
    await Store.i.touchCourse(course.id);
    final modules = await Store.i.modules(course.id);
    final lessons = await Store.i.lessons(course.id);
    final resources = await Store.i.resources(courseId: course.id);
    final notes = await Store.i.notes(courseId: course.id);
    final bookmarkedLessons = await Store.i.bookmarkIdsFor('lesson');
    final progress = await Store.i.courseProgressMap(course.id);
    if (!mounted) return;
    setState(() {
      _course = course;
      _modules = modules;
      _lessons = lessons;
      _resources = resources;
      _notes = notes;
      _progress = progress;
      _bookmarkedLessons = bookmarkedLessons;
    });

    // Covers and natural order for libraries imported before v12. Runs after
    // the first paint so the page is never blocked by filesystem work.
    if (_metadataChecked) return;
    _metadataChecked = true;
    try {
      await ensureCourseMetadata(course, modules, lessons);
    } catch (_) {}
    if (!mounted) return;
    final refreshed = await Store.i.course(widget.courseId);
    final freshModules = await Store.i.modules(course.id);
    final freshLessons = await Store.i.lessons(course.id);
    final freshProgress = await Store.i.courseProgressMap(course.id);
    if (!mounted) return;
    setState(() {
      if (refreshed != null) _course = refreshed;
      _modules = freshModules;
      _lessons = freshLessons;
      _progress = freshProgress;
    });
  }

  Lesson? get _next {
    for (final l in _lessons) {
      if (_progress[l.id]?.completed != true) return l;
    }
    return _lessons.isEmpty ? null : _lessons.first;
  }

  bool _moduleGallery = false;
  bool _metadataChecked = false;
  bool _transcribing = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final course = _course;
    if (course == null) {
      return Scaffold(
        backgroundColor: c.canvas,
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final done = _lessons
        .where((l) => _progress[l.id]?.completed == true)
        .length;
    final ratio = _lessons.isEmpty ? 0.0 : done / _lessons.length;

    return Scaffold(
      backgroundColor: c.canvas,
      body: LayoutBuilder(
        builder: (context, cons) {
          final wide = cons.maxWidth >= 940;
          final main = MSmoothScrollView(
            padding: EdgeInsets.fromLTRB(24, 14, wide ? 12 : 24, 40),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 860 : 980),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _headerBar(context, course),
                      const SizedBox(height: 14),
                      _hero(context, course, done, ratio),
                      const SizedBox(height: 22),
                      _modulesHeader(context, course),
                      const SizedBox(height: 12),
                      if (_lessons.isEmpty && _modules.isEmpty)
                        MEmpty(
                          icon: Icons.play_lesson_outlined,
                          title: 'No lessons yet',
                          message: 'Add video files to this course. They can live anywhere on your disk.',
                          action: MButton(
                            label: 'Add a lesson',
                            kind: MButtonKind.primary,
                            onPressed: () => _addLesson(context),
                          ),
                        )
                      else if (_moduleGallery)
                        _moduleGalleryView(context)
                      else
                        _moduleListView(context),
                      if (_notes.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        _notesSection(context),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );

          final sidebar = Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              wide ? 14 : 0,
              wide ? 18 : 24,
              wide ? 24 : 0,
            ),
            child: CourseContextSidebar(
              course: course,
              modules: _modules,
              lessons: _lessons,
              resources: _resources,
              progress: _progress,
              onRefresh: _load,
            ),
          );

          if (wide) {
            // A Stack with an explicit Positioned rail: the sidebar keeps its
            // width even while the main column is scrolled.
            return Stack(
              children: [
                Positioned.fill(right: 374, child: main),
                Positioned(
                  top: 14,
                  right: 18,
                  bottom: 24,
                  width: 356,
                  child: sidebar,
                ),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: main),
              SizedBox(
                height: 420,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: CourseContextSidebar(
                    course: course,
                    modules: _modules,
                    lessons: _lessons,
                    resources: _resources,
                    progress: _progress,
                    onRefresh: _load,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _transcribeCourse(BuildContext context) async {
    final s = AppState.i;
    if (s.transcriptionBackend == 'none') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a transcription backend in Settings first.'),
        ),
      );
      Nav.settings(context);
      return;
    }
    final candidates = _lessons
        .where((l) => l.path != null && File(l.path!).existsSync())
        .toList();
    if (candidates.isEmpty) return;

    setState(() => _transcribing = true);
    final progress = ValueNotifier<int>(0);
    final current = ValueNotifier<String>('');
    if (context.mounted) {
      showMSheet<void>(
        context,
        maxWidth: 460,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transcribing the course',
                style: MType.h2.copyWith(color: context.c.ink, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                'Whisper runs locally on each lesson, then the transcript is indexed so the tutor can answer from it.',
                style: MType.small.copyWith(
                  color: context.c.inkMuted,
                  height: 1.45,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<int>(
                valueListenable: progress,
                builder: (context, done, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MProgress(
                      value: candidates.isEmpty ? 0 : done / candidates.length,
                      height: 6,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$done of ${candidates.length} lessons',
                      style: MType.small.copyWith(
                        color: context.c.inkMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder<String>(
                valueListenable: current,
                builder: (context, label, _) => Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MType.small.copyWith(
                    color: context.c.inkFaint,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    var done = 0;
    var failed = 0;
    var skipped = 0;
    final service = TranscriptionService();
    for (final lesson in candidates) {
      current.value = lesson.title;
      final existing = await Store.i.transcriptFor('lesson', lesson.id);
      if (existing != null) {
        skipped++;
      } else {
        try {
          final segments = await service.transcribe(
            filePath: lesson.path!,
            backend: s.transcriptionBackend,
            endpoint: s.transcriptionEndpoint,
            apiKey: s.transcriptionApiKey,
            model: s.transcriptionModel,
            language: s.transcriptionLanguage,
            executable: s.whisperPath,
            modelPath: s.whisperModelPath.isNotEmpty
                ? s.whisperModelPath
                : (s.transcriptionBackend == 'whispercpp'
                      ? whisperModelPath(s.whisperModel)
                      : ''),
          );
          await Store.i.saveTranscript(
            ownerType: 'lesson',
            ownerId: lesson.id,
            language: s.transcriptionLanguage,
            source: s.transcriptionBackend,
            segments: segments,
          );
        } catch (_) {
          failed++;
        }
      }
      done++;
      progress.value = done;
    }

    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (mounted) setState(() => _transcribing = false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transcripts ready: ${done - failed - skipped} new, $skipped already present'
            '${failed > 0 ? ', $failed failed' : ''}.',
          ),
        ),
      );
    }
    AppState.i.bump();
    await _load();
  }

  Widget _headerBar(BuildContext context, Course course) {
    final c = context.c;
    return Row(
      children: [
        MButton(
          label: 'Courses',
          icon: Icons.arrow_back_rounded,
          kind: MButtonKind.ghost,
          dense: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              MButton(
                label: L.of(context).t('openFolder'),
                icon: Icons.folder_open_outlined,
                dense: true,
                onPressed: () => _openCourseFolder(context),
              ),
              MButton(
                label: L.of(context).t('addLesson'),
                icon: Icons.add_rounded,
                dense: true,
                onPressed: () => _addLesson(context),
              ),
              MButton(
                label: _transcribing
                    ? '…'
                    : L.of(context).t('transcribeCourse'),
                icon: Icons.subtitles_rounded,
                dense: true,
                onPressed: _transcribing
                    ? null
                    : () => _transcribeCourse(context),
              ),
              MButton(
                label: L.of(context).t('edit'),
                icon: Icons.edit_outlined,
                dense: true,
                onPressed: () async {
                  await showCourseEditor(context, course: course);
                  await _load();
                },
              ),
              PopupMenuButton<String>(
                tooltip: 'Course options',
                color: c.surface,
                onSelected: (v) async {
                  switch (v) {
                    case 'open-folder':
                      await _openCourseFolder(context);
                    case 'cover':
                      final picked = await pickCoverImageFile(
                        dialogTitle: 'Choose course cover',
                      );
                      if (picked != null) {
                        await Store.i.setCourseCover(course.id, picked);
                        AppState.i.bump();
                        await _load();
                      }
                    case 'remove-cover':
                      await Store.i.setCourseCover(course.id, null);
                      AppState.i.bump();
                      await _load();
                    case 'edit':
                      await showCourseEditor(context, course: course);
                      await _load();
                    case 'add-lesson':
                      await _addLesson(context);
                    case 'hide':
                      await Store.i.setCourseArchived(
                        course.id,
                        !course.archived,
                      );
                      AppState.i.bump();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              course.archived
                                  ? 'Course shown in the list again.'
                                  : 'Removed from the list. Its folder, videos and attachments were not touched.',
                            ),
                          ),
                        );
                      }
                      await _load();
                    case 'delete':
                      final ok = await _confirmDelete(context, course.title);
                      if (!ok) return;
                      await Store.i.deleteCourse(course.id);
                      AppState.i.bump();
                      if (context.mounted) Navigator.of(context).pop();
                  }
                },
                itemBuilder: (_) => [
                  _optionItem(
                    'open-folder',
                    Icons.folder_open_outlined,
                    'Open folder',
                  ),
                  _optionItem(
                    'edit',
                    Icons.edit_outlined,
                    'Edit details & author',
                  ),
                  _optionItem('cover', Icons.image_outlined, 'Change cover'),
                  if (course.cover != null && course.cover!.isNotEmpty)
                    _optionItem(
                      'remove-cover',
                      Icons.hide_image_outlined,
                      'Remove cover',
                    ),
                  _optionItem('add-lesson', Icons.add_rounded, 'Add lesson'),
                  const PopupMenuDivider(),
                  _optionItem(
                    'hide',
                    course.archived
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    course.archived ? 'Show in list' : 'Remove from list',
                  ),
                  _optionItem(
                    'delete',
                    Icons.delete_outline_rounded,
                    'Delete from library',
                    danger: true,
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: c.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hero(BuildContext context, Course course, int done, double ratio) {
    final c = context.c;
    final hasCover =
        course.cover != null &&
        course.cover!.isNotEmpty &&
        File(course.cover!).existsSync();
    return MCard(
      padding: EdgeInsets.zero,
      clip: true,
      radius: MRadius.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 168,
            child: Stack(
              fit: StackFit.expand,
              children: [
                hasCover
                    ? Image.file(File(course.cover!), fit: BoxFit.cover)
                    : _Cover(title: course.title, cover: null, height: 168),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(MRadius.pill),
                    child: InkWell(
                      onTap: () async {
                        final picked = await pickCoverImageFile(
                          dialogTitle: 'Choose course cover',
                        );
                        if (picked != null) {
                          await Store.i.setCourseCover(course.id, picked);
                          AppState.i.bump();
                          await _load();
                        }
                      },
                      borderRadius: BorderRadius.circular(MRadius.pill),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.image_outlined,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Change cover',
                              style: MType.small.copyWith(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MType.h1.copyWith(color: c.ink, fontSize: 28),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (course.author?.isNotEmpty == true)
                      MChip(
                        label: course.author!,
                        icon: Icons.person_outline_rounded,
                        tone: MChipTone.neutral,
                      ),
                    if (course.category?.isNotEmpty == true)
                      MChip(label: course.category!, icon: Icons.sell_outlined),
                    MChip(
                      label: '${_lessons.length} lessons',
                      icon: Icons.play_lesson_outlined,
                    ),
                    MChip(
                      label: '${_modules.length} modules',
                      icon: Icons.view_module_outlined,
                    ),
                    MChip(
                      label: '${_resources.length} files',
                      icon: Icons.attach_file_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TagBar(entityType: 'course', entityId: course.id),
                if (course.description?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    course.description!,
                    style: MType.body.copyWith(color: c.inkMuted, height: 1.55),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (_next != null)
                      MButton(
                        label: done == 0
                            ? L.of(context).t('startCourse')
                            : L.of(context).t('continue'),
                        icon: Icons.play_arrow_rounded,
                        kind: MButtonKind.primary,
                        onPressed: () =>
                            Nav.lesson(context, course.id, _next!.id),
                      ),
                    if (_next != null) const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MProgress(value: ratio, height: 5),
                          const SizedBox(height: 5),
                          Text(
                            '$done of ${_lessons.length} lessons complete',
                            style: MType.small.copyWith(
                              color: c.inkFaint,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (course.objectives?.isNotEmpty == true)
                      MButton(
                        label: 'Objectives',
                        icon: Icons.flag_outlined,
                        dense: true,
                        onPressed: () => _showObjectives(context, course),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modulesHeader(BuildContext context, Course course) {
    final c = context.c;
    final done = _lessons
        .where((l) => _progress[l.id]?.completed == true)
        .length;
    final allDone = _lessons.isNotEmpty && done == _lessons.length;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Text(
          L.of(context).t('courseContent'),
          style: MType.h2.copyWith(color: c.ink, fontSize: 19),
        ),
        Text(
          '$done/${_lessons.length} completed',
          style: MType.small.copyWith(color: c.inkFaint, fontSize: 11),
        ),
        MButton(
          label: allDone
              ? L.of(context).t('resetProgress')
              : L.of(context).t('markAllComplete'),
          icon: allDone ? Icons.restart_alt_rounded : Icons.done_all_rounded,
          dense: true,
          onPressed: () async {
            await Store.i.setModuleCompleted(course.id, null, !allDone);
            for (final m in _modules) {
              await Store.i.setModuleCompleted(course.id, m.id, !allDone);
            }
            AppState.i.bump();
            await _load();
          },
        ),
        MIconButton(
          icon: Icons.view_list_rounded,
          tooltip: 'List view',
          selected: !_moduleGallery,
          onPressed: () => setState(() => _moduleGallery = false),
        ),
        MIconButton(
          icon: Icons.grid_view_rounded,
          tooltip: 'Gallery view',
          selected: _moduleGallery,
          onPressed: () => setState(() => _moduleGallery = true),
        ),
      ],
    );
  }

  /// Ordered module groups: (module, lessons). A null module holds loose lessons.
  List<(Module?, List<Lesson>)> _grouped() {
    final modules = [..._modules]
      ..sort((a, b) => a.position.compareTo(b.position));
    final known = modules.map((m) => m.id).toSet();
    final groups = <(Module?, List<Lesson>)>[];
    for (final m in modules) {
      final list = _lessons.where((l) => l.moduleId == m.id).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      // Empty modules remain visible so their Add content action is reachable.
      groups.add((m, list));
    }
    final loose =
        _lessons
            .where((l) => l.moduleId == null || !known.contains(l.moduleId))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    if (loose.isNotEmpty) groups.add((null, loose));
    return groups;
  }

  Widget _moduleListView(BuildContext context) {
    final groups = _grouped();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var g = 0; g < groups.length; g++) ...[
          _moduleHeader(
            context,
            groups[g].$1,
            groups[g].$2,
            canUp: g > 0,
            canDown: g < groups.length - 1,
            groupIndex: g,
          ),
          MCard(
            padding: EdgeInsets.zero,
            clip: true,
            child: groups[g].$2.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: MButton(
                      label: 'Add the first content',
                      icon: Icons.add_rounded,
                      dense: true,
                      onPressed: () =>
                          _showModuleContentPicker(context, groups[g].$1!),
                    ),
                  )
                : ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: groups[g].$2.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        _reorderGroup(groups[g].$1?.id, oldIndex, newIndex),
                    itemBuilder: (context, i) {
                      final lesson = groups[g].$2[i];
                      return Column(
                        key: ValueKey(lesson.id),
                        children: [
                          _LessonRow(
                            lesson: lesson,
                            dragIndex: i,
                            progress: _progress[lesson.id],
                            bookmarked: _bookmarkedLessons.contains(lesson.id),
                            onTap: () =>
                                Nav.lesson(context, widget.courseId, lesson.id),
                            onToggleComplete: () =>
                                _toggleLesson(context, lesson),
                            onToggleBookmark: () async {
                              await Store.i.toggleBookmark('lesson', lesson.id);
                              AppState.i.bump();
                              _load();
                            },
                            onOpenFolder: () =>
                                _openLessonFolder(context, lesson),
                            onRemove: () => _removeLesson(context, lesson),
                            onMoveUp: () => _moveLesson(lesson, -1),
                            onMoveDown: () => _moveLesson(lesson, 1),
                          ),
                          if (i < groups[g].$2.length - 1) const MDivider(),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  Widget _moduleHeader(
    BuildContext context,
    Module? module,
    List<Lesson> lessons, {
    required bool canUp,
    required bool canDown,
    required int groupIndex,
  }) {
    final c = context.c;
    final done = lessons
        .where((l) => _progress[l.id]?.completed == true)
        .length;
    final allDone = lessons.isNotEmpty && done == lessons.length;
    final title = module?.title ?? 'Other lessons';
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Row(
        children: [
          if (module != null)
            InkWell(
              onTap: () => _toggleModule(context, module, lessons, !allDone),
              borderRadius: BorderRadius.circular(6),
              child: Tooltip(
                message: allDone
                    ? 'Mark module as incomplete'
                    : 'Mark module complete',
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    allDone
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 17,
                    color: allDone ? c.accent : c.inkMuted,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MType.label.copyWith(color: c.inkFaint, fontSize: 10.5),
            ),
          ),
          Text(
            '$done/${lessons.length}',
            style: MType.small.copyWith(color: c.inkFaint, fontSize: 10.5),
          ),
          if (module != null) ...[
            const SizedBox(width: 4),
            _addModuleButton(context, module),
            MIconButton(
              icon: Icons.arrow_upward_rounded,
              tooltip: 'Move module up',
              size: 26,
              onPressed: canUp ? () => _moveModule(module.id, -1) : null,
            ),
            MIconButton(
              icon: Icons.arrow_downward_rounded,
              tooltip: 'Move module down',
              size: 26,
              onPressed: canDown ? () => _moveModule(module.id, 1) : null,
            ),
            PopupMenuButton<String>(
              tooltip: 'Module options',
              color: c.surface,
              onSelected: (v) async {
                switch (v) {
                  case 'cover':
                    final picked = await pickCoverImageFile(
                      dialogTitle: 'Choose module cover',
                    );
                    if (picked != null) {
                      await Store.i.setModuleCover(module.id, picked);
                      AppState.i.bump();
                      await _load();
                    }
                  case 'remove-cover':
                    await Store.i.setModuleCover(module.id, null);
                    AppState.i.bump();
                    await _load();
                  case 'rename':
                    await _renameModule(context, module);
                }
              },
              itemBuilder: (_) => [
                _optionItem('cover', Icons.image_outlined, 'Change cover'),
                if (module.cover != null && module.cover!.isNotEmpty)
                  _optionItem(
                    'remove-cover',
                    Icons.hide_image_outlined,
                    'Remove cover',
                  ),
                _optionItem('rename', Icons.edit_outlined, 'Rename module'),
              ],
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 16,
                  color: c.inkMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _addModuleButton(BuildContext context, Module module) {
    final c = context.c;
    return PopupMenuButton<String>(
      key: Key('add-content-${module.id}'),
      tooltip: 'Add content to ${module.title}',
      color: c.surface,
      onSelected: (action) => _addModuleContent(context, module, action),
      itemBuilder: (_) => [
        _optionItem(
          'media',
          Icons.video_library_outlined,
          'Add video or audio lessons',
        ),
        _optionItem('text', Icons.notes_outlined, 'Add text lesson'),
        _optionItem('quiz', Icons.quiz_outlined, 'Add quiz'),
      ],
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(Icons.add_rounded, size: 19, color: c.inkMuted),
      ),
    );
  }

  Future<void> _showModuleContentPicker(
    BuildContext context,
    Module module,
  ) async {
    final action = await showMSheet<String>(
      context,
      maxWidth: 440,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add to ${module.title}',
              style: MType.h2.copyWith(color: context.c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose the kind of content to add to this module.',
              style: MType.small.copyWith(
                color: context.c.inkMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in <(String, IconData, String, String)>[
              (
                'media',
                Icons.video_library_outlined,
                'Video or audio lessons',
                'Choose one or more media files',
              ),
              (
                'text',
                Icons.notes_outlined,
                'Text lesson',
                'Write material to study',
              ),
              (
                'quiz',
                Icons.quiz_outlined,
                'Quiz',
                'Create questions and answers',
              ),
            ])
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(item.$2, size: 21, color: context.c.inkMuted),
                title: Text(
                  item.$3,
                  style: MType.bodyStrong.copyWith(color: context.c.ink),
                ),
                subtitle: Text(
                  item.$4,
                  style: MType.small.copyWith(color: context.c.inkMuted),
                ),
                onTap: () => Navigator.of(context).pop(item.$1),
              ),
          ],
        ),
      ),
    );
    if (action != null && context.mounted) {
      await _addModuleContent(context, module, action);
    }
  }

  Widget _moduleGalleryView(BuildContext context) {
    final groups = _grouped();
    return LayoutBuilder(
      builder: (context, cons) {
        final cols = cons.maxWidth > 760 ? 3 : 2;
        final w = (cons.maxWidth - (cols - 1) * 14) / cols;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final (module, lessons) in groups)
              SizedBox(
                width: w,
                child: _ModuleCard(
                  module: module,
                  lessons: lessons,
                  progress: _progress,
                  onOpen: () => _showModuleSheet(context, module, lessons),
                  onToggleComplete: module == null
                      ? null
                      : () => _toggleModule(
                          context,
                          module,
                          lessons,
                          lessons.every(
                            (l) => _progress[l.id]?.completed == true,
                          ),
                        ),
                  onAddContent: module == null
                      ? null
                      : () => _showModuleContentPicker(context, module),
                  onChangeCover: module == null
                      ? null
                      : () async {
                          final picked = await pickCoverImageFile(
                            dialogTitle: 'Choose module cover',
                          );
                          if (picked != null) {
                            await Store.i.setModuleCover(module.id, picked);
                            AppState.i.bump();
                            await _load();
                          }
                        },
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _toggleLesson(BuildContext context, Lesson lesson) async {
    final done = _progress[lesson.id]?.completed == true;
    await Store.i.toggleLessonCompleted(lesson.id, !done);
    AppState.i.bump();
    await _load();
  }

  Future<void> _toggleModule(
    BuildContext context,
    Module module,
    List<Lesson> lessons,
    bool completed,
  ) async {
    await Store.i.setModuleCompleted(widget.courseId, module.id, completed);
    AppState.i.bump();
    await _load();
  }

  Future<void> _showModuleSheet(
    BuildContext context,
    Module? module,
    List<Lesson> lessons,
  ) async {
    final c = context.c;
    await showMSheet<void>(
      context,
      maxWidth: 560,
      child: StatefulBuilder(
        builder: (context, setLocal) {
          final done = lessons
              .where((l) => _progress[l.id]?.completed == true)
              .length;
          final ratio = lessons.isEmpty ? 0.0 : done / lessons.length;
          final allDone = lessons.isNotEmpty && done == lessons.length;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (module?.cover != null && File(module!.cover!).existsSync())
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(MRadius.xl),
                  ),
                  child: SizedBox(
                    height: 120,
                    child: Image.file(File(module.cover!), fit: BoxFit.cover),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module?.title ?? 'Other lessons',
                      style: MType.h2.copyWith(color: c.ink, fontSize: 20),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$done of ${lessons.length} lessons complete',
                      style: MType.small.copyWith(
                        color: c.inkMuted,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    MProgress(value: ratio, height: 4),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        MButton(
                          label: allDone
                              ? 'Mark module incomplete'
                              : 'Mark module complete',
                          icon: allDone
                              ? Icons.restart_alt_rounded
                              : Icons.done_all_rounded,
                          dense: true,
                          onPressed: module == null
                              ? null
                              : () async {
                                  await _toggleModule(
                                    context,
                                    module,
                                    lessons,
                                    !allDone,
                                  );
                                  setLocal(() {});
                                },
                        ),
                        if (module != null)
                          MButton(
                            key: const Key('module-sheet-add-content'),
                            label: 'Add content',
                            icon: Icons.add_rounded,
                            kind: MButtonKind.primary,
                            dense: true,
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await _showModuleContentPicker(
                                this.context,
                                module,
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: lessons.length,
                        itemBuilder: (context, i) {
                          final l = lessons[i];
                          final isDone = _progress[l.id]?.completed == true;
                          return InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              Nav.lesson(context, widget.courseId, l.id);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                children: [
                                  InkWell(
                                    onTap: () async {
                                      await Store.i.toggleLessonCompleted(
                                        l.id,
                                        !isDone,
                                      );
                                      AppState.i.bump();
                                      await _load();
                                      setLocal(() {});
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Icon(
                                      isDone
                                          ? Icons.check_circle_rounded
                                          : Icons
                                                .radio_button_unchecked_rounded,
                                      size: 18,
                                      color: isDone ? c.accent : c.inkMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      l.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: MType.small.copyWith(
                                        color: c.ink,
                                        fontSize: 12.5,
                                        fontWeight: isDone
                                            ? FontWeight.w500
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    size: 16,
                                    color: c.inkFaint,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _notesSection(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Notes', style: MType.h2.copyWith(color: c.ink, fontSize: 18)),
            const Spacer(),
            MButton(
              label: 'Write a note',
              icon: Icons.note_add_outlined,
              dense: true,
              onPressed: () async {
                await showNoteEditor(context, courseId: widget.courseId);
                await _load();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        MCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < _notes.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notes_rounded, size: 15, color: c.inkFaint),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _notes[i].title,
                              style: MType.bodyStrong.copyWith(
                                color: c.ink,
                                fontSize: 12.5,
                              ),
                            ),
                            if (_notes[i].body.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                _notes[i].body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: MType.small.copyWith(
                                  color: c.inkMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        relativeDate(_notes[i].updatedAt),
                        style: MType.small.copyWith(
                          color: c.inkFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < _notes.length - 1) const MDivider(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Persists the display order after a drag inside one module.
  Future<void> _reorderGroup(
    String? moduleId,
    int oldIndex,
    int newIndex,
  ) async {
    final modules = [..._modules]
      ..sort((a, b) => a.position.compareTo(b.position));
    final known = modules.map((m) => m.id).toSet();
    final groups = <String?, List<Lesson>>{};
    for (final m in modules) {
      final list = _lessons.where((l) => l.moduleId == m.id).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      if (list.isNotEmpty) groups[m.id] = list;
    }
    final loose =
        _lessons
            .where((l) => l.moduleId == null || !known.contains(l.moduleId))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    if (loose.isNotEmpty) groups[null] = loose;

    final list = groups[moduleId];
    if (list == null) return;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), moved);

    // Flatten in module order so the stored positions match what is on screen.
    final ordered = <String>[
      for (final m in modules) ...?groups[m.id]?.map((l) => l.id),
      ...?groups[null]?.map((l) => l.id),
      ...groups.entries
          .where((e) => e.key != null && !modules.any((m) => m.id == e.key))
          .expand((e) => e.value.map((l) => l.id)),
    ];
    await Store.i.reorderLessons(ordered);
    AppState.i.bump();
    _load();
  }

  /// Moves one lesson by [delta] inside its own module and rewrites positions.
  Future<void> _moveLesson(Lesson lesson, int delta) async {
    final modules = [..._modules]
      ..sort((a, b) => a.position.compareTo(b.position));
    final known = modules.map((m) => m.id).toSet();
    final groups = <String?, List<Lesson>>{};
    for (final m in modules) {
      final list = _lessons.where((l) => l.moduleId == m.id).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      if (list.isNotEmpty) groups[m.id] = list;
    }
    final loose =
        _lessons
            .where((l) => l.moduleId == null || !known.contains(l.moduleId))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    if (loose.isNotEmpty) groups[null] = loose;

    final key = groups.keys.firstWhere(
      (k) => groups[k]!.any((l) => l.id == lesson.id),
      orElse: () => null,
    );
    final list = groups[key];
    if (list == null) return;
    final from = list.indexWhere((l) => l.id == lesson.id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= list.length) return;
    final moved = list.removeAt(from);
    list.insert(to, moved);
    await Store.i.reorderLessons(<String>[
      for (final m in modules) ...?groups[m.id]?.map((l) => l.id),
      ...?groups[null]?.map((l) => l.id),
    ]);
    AppState.i.bump();
    _load();
  }

  Future<void> _moveModule(String moduleId, int delta) async {
    final modules = [..._modules]
      ..sort((a, b) => a.position.compareTo(b.position));
    final from = modules.indexWhere((m) => m.id == moduleId);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= modules.length) return;
    final moved = modules.removeAt(from);
    modules.insert(to, moved);
    await Store.i.reorderModules(modules.map((m) => m.id).toList());
    AppState.i.bump();
    _load();
  }

  Future<void> _renameModule(BuildContext context, Module module) async {
    final ctrl = TextEditingController(text: module.title);
    final name = await showMSheet<String>(
      context,
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rename module',
              style: MType.h2.copyWith(color: context.c.ink),
            ),
            const SizedBox(height: 14),
            TextField(controller: ctrl, autofocus: true),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                MButton(
                  label: 'Save',
                  kind: MButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty || name == module.title) return;
    await Store.i.renameModule(module.id, name);
    AppState.i.bump();
    _load();
  }

  Future<void> _openLessonFolder(BuildContext context, Lesson lesson) async {
    final path = lesson.path;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This lesson has no file on disk.')),
      );
      return;
    }
    final opened = await revealFileInExplorer(path);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('File not found: $path')));
    }
  }

  Future<void> _removeLesson(BuildContext context, Lesson lesson) async {
    await Store.i.deleteLesson(lesson.id);
    AppState.i.bump();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lesson removed from this course. The file stays on disk.',
          ),
        ),
      );
    }
    _load();
  }

  PopupMenuItem<String> _optionItem(
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final c = context.c;
    return PopupMenuItem(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 15, color: danger ? c.danger : c.inkMuted),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MType.small.copyWith(
                color: danger ? c.danger : c.ink,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCourseFolder(BuildContext context) async {
    final course = _course;
    if (course == null) return;
    final folder = courseFolderOf(
      course,
      lessons: _lessons,
      resources: _resources,
    );
    if (folder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This course has no folder on disk to open.'),
        ),
      );
      return;
    }
    final opened = await openFolderInExplorer(folder);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Folder not found: $folder')));
    }
  }

  Future<void> _addModuleContent(
    BuildContext context,
    Module module,
    String action,
  ) async {
    if (action == 'media') {
      await _addLesson(context, moduleId: module.id);
      return;
    }

    try {
      final now = DateTime.now();
      final position = _lessons.length;
      if (action == 'text') {
        final draft = await showTextLessonCreator(
          context,
          moduleTitle: module.title,
        );
        if (draft == null || !context.mounted) return;
        await Store.i.saveLesson(
          Lesson(
            id: _uuid.v4(),
            courseId: widget.courseId,
            moduleId: module.id,
            title: draft.title,
            kind: 'text',
            description: draft.text.isEmpty ? null : draft.text,
            position: position,
            createdAt: now,
          ),
        );
      } else if (action == 'quiz') {
        final override = widget.quizGenerator;
        final draft = await showQuizCreator(
          context,
          moduleTitle: module.title,
          generateWithAi: () => override == null
              ? ModuleQuizGenerator(module: module).generate()
              : override(module),
        );
        if (draft == null || !context.mounted) return;
        final lesson = Lesson(
          id: _uuid.v4(),
          courseId: widget.courseId,
          moduleId: module.id,
          title: draft.title,
          kind: 'quiz',
          position: position,
          createdAt: now,
        );
        await Store.i.createQuiz(lesson, [
          for (final (index, q) in draft.questions.indexed)
            Flashcard(
              id: _uuid.v4(),
              deck: 'Quiz: ${draft.title}',
              front: q.question,
              back: q.answer,
              courseId: widget.courseId,
              lessonId: lesson.id,
              dueAt: now,
              // Millisecond steps preserve the author's order in SQLite.
              createdAt: now.add(Duration(milliseconds: index)),
            ),
        ]);
      } else {
        return;
      }
      AppState.i.bump();
      await _load();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Content added to ${module.title}.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The content could not be added: $e')),
        );
      }
    }
  }

  Future<void> _addLesson(BuildContext context, {String? moduleId}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'mp4',
        'mkv',
        'webm',
        'mov',
        'avi',
        'm4v',
        'mp3',
        'm4a',
        'wav',
      ],
      dialogTitle: 'Add lessons',
    );
    if (result == null) return;
    var pos = _lessons.length;
    for (final f in result.files) {
      if (f.path == null) continue;
      final ext = p.extension(f.path!).replaceFirst('.', '').toLowerCase();
      await Store.i.saveLesson(
        Lesson(
          id: _uuid.v4(),
          courseId: widget.courseId,
          moduleId: moduleId,
          title: p.basenameWithoutExtension(f.path!),
          path: f.path,
          kind: ['mp3', 'm4a', 'wav'].contains(ext) ? 'audio' : 'video',
          position: pos++,
          createdAt: DateTime.now(),
        ),
      );
    }
    AppState.i.bump();
    await _load();
  }

  void _showObjectives(BuildContext context, Course course) {
    final c = context.c;
    showMSheet<void>(
      context,
      maxWidth: 480,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Learning objectives', style: MType.h2.copyWith(color: c.ink)),
            const SizedBox(height: 12),
            for (final line
                in (course.objectives ?? '')
                    .split('\n')
                    .where((l) => l.trim().isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line.trim(),
                        style: MType.body.copyWith(
                          color: c.inkMuted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.lessons,
    required this.progress,
    required this.onOpen,
    this.onToggleComplete,
    this.onChangeCover,
    this.onAddContent,
  });

  final Module? module;
  final List<Lesson> lessons;
  final Map<String, Progress> progress;
  final VoidCallback onOpen;
  final VoidCallback? onToggleComplete;
  final VoidCallback? onChangeCover;
  final VoidCallback? onAddContent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final done = lessons.where((l) => progress[l.id]?.completed == true).length;
    final ratio = lessons.isEmpty ? 0.0 : done / lessons.length;
    final allDone = lessons.isNotEmpty && done == lessons.length;
    final cover = module?.cover;
    final hasCover =
        cover != null && cover.isNotEmpty && File(cover).existsSync();

    return MCard(
      padding: EdgeInsets.zero,
      clip: true,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 96,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasCover)
                  Image.file(File(cover), fit: BoxFit.cover)
                else
                  Container(
                    color: c.surfaceSunken,
                    child: Center(
                      child: Icon(
                        Icons.view_module_outlined,
                        size: 22,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
                if (onToggleComplete != null)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: InkWell(
                      onTap: onToggleComplete,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: c.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Tooltip(
                          message: allDone
                              ? 'Mark module as incomplete'
                              : 'Mark module complete',
                          child: Icon(
                            allDone
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 17,
                            color: allDone ? c.accent : c.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (onChangeCover != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: onChangeCover,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: c.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Tooltip(
                          message: 'Change module cover',
                          child: Icon(
                            Icons.image_outlined,
                            size: 15,
                            color: c.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (onAddContent != null)
                  Positioned(
                    top: 38,
                    right: 6,
                    child: Tooltip(
                      key: Key('module-gallery-add-${module!.id}'),
                      message: 'Add content to module',
                      child: _IconBubble(
                        icon: Icons.add_rounded,
                        onTap: onAddContent!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module?.title ?? 'Other lessons',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MType.bodyStrong.copyWith(
                    color: c.ink,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$done of ${lessons.length} complete',
                  style: MType.small.copyWith(
                    color: c.inkFaint,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 8),
                MProgress(value: ratio, height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({
    required this.lesson,
    required this.progress,
    required this.bookmarked,
    required this.onTap,
    required this.onToggleComplete,
    required this.onToggleBookmark,
    required this.onOpenFolder,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    this.dragIndex,
  });

  final Lesson lesson;
  final Progress? progress;
  final bool bookmarked;
  final VoidCallback onTap;
  final VoidCallback onToggleComplete;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenFolder;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  /// When set, a grip appears on the left and starts a drag reorder.
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final done = progress?.completed == true;
    final ratio = lesson.durationMs > 0
        ? ((progress?.positionMs ?? 0) / lesson.durationMs).clamp(0.0, 1.0)
        : 0.0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          children: [
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex!,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 16,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              ),
            InkWell(
              onTap: onToggleComplete,
              borderRadius: BorderRadius.circular(MSpace.x2),
              child: Tooltip(
                message: done ? 'Mark as incomplete' : 'Mark as completed',
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: done ? c.accentSoft : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(MSpace.x2),
                    border: Border.all(
                      color: done ? Colors.transparent : c.line,
                    ),
                  ),
                  child: Icon(
                    done
                        ? Icons.check_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 15,
                    color: done ? c.accent : c.inkMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (lesson.kind == 'quiz' || lesson.kind == 'text') ...[
              Tooltip(
                message: lesson.kind == 'quiz' ? 'Quiz' : 'Text lesson',
                child: Icon(
                  lesson.kind == 'quiz'
                      ? Icons.quiz_outlined
                      : Icons.notes_outlined,
                  size: 17,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.body.copyWith(
                      color: c.ink,
                      fontSize: 13,
                      fontWeight: done ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                  if (ratio > 0 && !done) ...[
                    const SizedBox(height: 5),
                    SizedBox(
                      width: 180,
                      child: MProgress(value: ratio, height: 3),
                    ),
                  ],
                ],
              ),
            ),
            if (lesson.durationMs > 0)
              Text(
                formatClock(Duration(milliseconds: lesson.durationMs)),
                style: MType.small.copyWith(color: c.inkFaint, fontSize: 10.5),
              ),
            const SizedBox(width: 6),
            MIconButton(
              icon: bookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              tooltip: bookmarked
                  ? 'Remove from Bookmarks'
                  : 'Pin lesson to Bookmarks',
              size: 28,
              onPressed: onToggleBookmark,
            ),
            PopupMenuButton<String>(
              tooltip: 'Lesson options',
              color: c.surface,
              onSelected: (v) {
                switch (v) {
                  case 'up':
                    onMoveUp();
                  case 'down':
                    onMoveDown();
                  case 'folder':
                    onOpenFolder();
                  case 'remove':
                    onRemove();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'up',
                  height: 38,
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_upward_rounded,
                        size: 15,
                        color: c.inkMuted,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Move lesson up',
                        style: MType.small.copyWith(
                          color: c.ink,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'down',
                  height: 38,
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_downward_rounded,
                        size: 15,
                        color: c.inkMuted,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Move lesson down',
                        style: MType.small.copyWith(
                          color: c.ink,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (lesson.path?.isNotEmpty == true)
                  PopupMenuItem(
                    value: 'folder',
                    height: 38,
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_open_outlined,
                          size: 15,
                          color: c.inkMuted,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Open file location',
                          style: MType.small.copyWith(
                            color: c.ink,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'remove',
                  height: 38,
                  child: Row(
                    children: [
                      Icon(
                        Icons.remove_circle_outline,
                        size: 15,
                        color: c.danger,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Remove from course',
                        style: MType.small.copyWith(
                          color: c.danger,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 17,
                  color: c.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
