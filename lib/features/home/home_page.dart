import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db.dart';
import '../../core/state.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../shell.dart';
import '../shell_dialogs.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onNavigate});
  final ValueChanged<Section> onNavigate;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, Object?>? _stats;
  List<Map<String, Object?>> _continue = const [];
  String _rangeLabel = 'Last 30 Days';
  int _filterTab =
      0; // 0: All Sources, 1: Books & PDFs, 2: Video Courses, 3: Maps & Notes
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
    final stats = await Store.i.dashboardStats();
    final cont = await Store.i.continueWatching();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _continue = cont;
      _loading = false;
    });
  }

  Future<void> _openAddSourceSheet(BuildContext context) async {
    final choice = await showMSheet<String>(
      context,
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MDialogHeader(
              title: 'Add Study Source',
              subtitle: 'Import books, PDFs, slides, lecture recordings, video courses, or start a concept map.',
            ),
            _SourceModalRow(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Add Books, PDFs, Slides & Documents',
              subtitle: 'Read with Focus mode, extract LaTeX formulas & keywords, ask the AI Tutor',
              onTap: () => Navigator.of(context).pop('files'),
            ),
            _SourceModalRow(
              icon: Icons.create_new_folder_outlined,
              title: 'Import a Video Course Folder',
              subtitle: 'Index local video/audio lectures in place without copying files',
              onTap: () => Navigator.of(context).pop('folder'),
            ),
            _SourceModalRow(
              icon: Icons.school_outlined,
              title: 'Create a Structured Course',
              subtitle:
                  'Group modules, lessons, PDFs, objectives and flashcards',
              onTap: () => Navigator.of(context).pop('course'),
            ),
            _SourceModalRow(
              icon: Icons.account_tree_outlined,
              title: 'Open Concept Maps & Schemas',
              subtitle: 'Build visual schemas or import/export a klaro. Knowledge Card',
              onTap: () => Navigator.of(context).pop('maps'),
            ),
            _SourceModalRow(
              icon: Icons.sticky_note_2_outlined,
              title: 'Write a Study Note',
              subtitle:
                  'Markdown notes with LaTeX, quotes and flashcard generation',
              onTap: () => Navigator.of(context).pop('note'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'files':
        await importLibraryFiles(context);
        await _load();
      case 'folder':
        await importCourseFolder(context);
        await _load();
      case 'course':
        await showCourseEditor(context);
        await _load();
      case 'maps':
        widget.onNavigate(Section.maps);
      case 'note':
        await showNoteEditor(context);
        await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final stats = _stats;
    final recentCourses =
        (stats?['recent_courses'] as List?)?.cast<Map<String, Object?>>() ?? [];
    final recentResources =
        (stats?['recent_resources'] as List?)?.cast<Map<String, Object?>>() ??
        [];
    final dailySeries =
        (stats?['daily_series'] as List?)?.cast<Map<String, Object?>>() ?? [];

    final coursesCount = stats?['courses'] as int? ?? 0;
    final resourcesCount = stats?['resources'] as int? ?? 0;
    final notesCount = stats?['notes'] as int? ?? 0;
    final extractsCount = stats?['extracts'] as int? ?? 0;
    final mapsCount = stats?['maps'] as int? ?? 0;
    final cardsCount = stats?['cards'] as int? ?? 0;
    final dueCount = stats?['due'] as int? ?? 0;
    final watchedMs = stats?['watched_7d_ms'] as int? ?? 0;
    final reviewMs = stats?['review_ms_30d'] as int? ?? 0;
    final actions30 = stats?['actions_30d'] as int? ?? 0;
    final activeDays = stats?['active_days_30d'] as int? ?? 0;
    final reviews30 = stats?['reviews_30d'] as int? ?? 0;
    final retention = (stats?['retention'] as num? ?? 0.0).toDouble();
    final lessonsCompleted = stats?['lessons_completed'] as int? ?? 0;

    final totalStudySources = coursesCount + resourcesCount;
    final totalKnowledgeItems = notesCount + extractsCount + mapsCount;
    final userName = Platform.environment['USERNAME'] ?? 'Learner';

    return MSmoothScrollView(
      padding: const EdgeInsets.fromLTRB(22, 10, 36, 36),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 720;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Welcome back header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'Welcome back, $userName!',
                          style: MType.display.copyWith(
                            color: c.ink,
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.1,
                          ),
                        ),
                      ),
                      if (dueCount > 0)
                        MButton(
                          label: '$dueCount flashcards due for Review',
                          icon: Icons.style_outlined,
                          kind: MButtonKind.primary,
                          dense: true,
                          onPressed: () => widget.onNavigate(Section.review),
                        ),
                    ],
                  ),
                  const SizedBox(height: 26),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else ...[
                    // 2. Top Hero Row: Continue Studying (Left) + Learning Progress Chart (Right)
                    if (wide)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 48,
                              child: _ContinueStudyingCard(
                                compact: constraints.maxWidth < 900,
                                continueRow: _continue.isNotEmpty
                                    ? _continue.first
                                    : null,
                                firstResourceRow: recentResources.isNotEmpty
                                    ? recentResources.first
                                    : null,
                                firstCourseRow: recentCourses.isNotEmpty
                                    ? recentCourses.first
                                    : null,
                                onResumeLesson: (courseId, lessonId) =>
                                    Nav.lesson(context, courseId, lessonId),
                                onOpenResource: (resId) =>
                                    Nav.resource(context, resId),
                                onOpenCourse: (courseId) =>
                                    Nav.course(context, courseId),
                                onAddSource: () => _openAddSourceSheet(context),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 52,
                              child: _LearningProgressCard(
                                watchedMs: watchedMs + reviewMs,
                                actions: actions30,
                                activeDays: activeDays,
                                dailySeries: dailySeries,
                                rangeLabel: _rangeLabel,
                                onRangeChanged: (v) =>
                                    setState(() => _rangeLabel = v),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      _ContinueStudyingCard(
                        compact: true,
                        continueRow: _continue.isNotEmpty
                            ? _continue.first
                            : null,
                        firstResourceRow: recentResources.isNotEmpty
                            ? recentResources.first
                            : null,
                        firstCourseRow: recentCourses.isNotEmpty
                            ? recentCourses.first
                            : null,
                        onResumeLesson: (courseId, lessonId) =>
                            Nav.lesson(context, courseId, lessonId),
                        onOpenResource: (resId) => Nav.resource(context, resId),
                        onOpenCourse: (courseId) =>
                            Nav.course(context, courseId),
                        onAddSource: () => _openAddSourceSheet(context),
                      ),
                      const SizedBox(height: 16),
                      _LearningProgressCard(
                        watchedMs: watchedMs + reviewMs,
                        actions: actions30,
                        activeDays: activeDays,
                        dailySeries: dailySeries,
                        rangeLabel: _rangeLabel,
                        onRangeChanged: (v) => setState(() => _rangeLabel = v),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // 3. 4 Horizontal Stat Cards Row (holistic 360° learning metrics, identical visual geometry)
                    LayoutBuilder(
                      builder: (context, statCons) {
                        final cols = wide ? 4 : 2;
                        final cardW =
                            (statCons.maxWidth - (cols - 1) * 18) / cols;
                        return Wrap(
                          spacing: 18,
                          runSpacing: 14,
                          children: [
                            SizedBox(
                              width: cardW,
                              child: _HorizontalStatCard(
                                icon: Icons.menu_book_rounded,
                                value: '$totalStudySources',
                                label: 'Sources & Courses',
                                onTap: () => widget.onNavigate(Section.library),
                              ),
                            ),
                            SizedBox(
                              width: cardW,
                              child: _HorizontalStatCard(
                                icon: Icons.account_tree_outlined,
                                value: '$totalKnowledgeItems',
                                label: 'Notes, Maps & Extracts',
                                onTap: () => widget.onNavigate(Section.maps),
                              ),
                            ),
                            SizedBox(
                              width: cardW,
                              child: _HorizontalStatCard(
                                icon: Icons.style_outlined,
                                value: '$cardsCount',
                                label: dueCount > 0
                                    ? '$dueCount Flashcards Due'
                                    : 'Flashcards',
                                onTap: () => widget.onNavigate(Section.review),
                              ),
                            ),
                            SizedBox(
                              width: cardW,
                              child: _HorizontalStatCard(
                                icon: Icons.task_alt_rounded,
                                value: '$lessonsCompleted',
                                label: 'Lessons Completed',
                                onTap: () => widget.onNavigate(Section.courses),
                              ),
                            ),
                            SizedBox(
                              width: cardW,
                              child: _HorizontalStatCard(
                                icon: Icons.psychology_alt_outlined,
                                value: reviews30 == 0
                                    ? '—'
                                    : '${(retention * 100).round()}%',
                                label: reviews30 == 0
                                    ? 'No reviews yet'
                                    : 'Recall Accuracy',
                                onTap: () => widget.onNavigate(Section.review),
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 30),

                    // 4. "Your Study Sources" Header + Category Filter Pills + Dark Pill "+ Add Source" Button
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          'Your Study Sources',
                          style: MType.h1.copyWith(
                            color: c.ink,
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (wide) ...[
                          MChip(
                            label: 'All Sources',
                            selected: _filterTab == 0,
                            onTap: () => setState(() => _filterTab = 0),
                          ),
                          MChip(
                            label: 'Books & PDFs',
                            selected: _filterTab == 1,
                            onTap: () => setState(() => _filterTab = 1),
                          ),
                          MChip(
                            label: 'Video Courses',
                            selected: _filterTab == 2,
                            onTap: () => setState(() => _filterTab = 2),
                          ),
                        ],
                        _DarkPillAddButton(
                          label: 'Add Source',
                          onTap: () => _openAddSourceSheet(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // 5. Unified 3-Column Study Sources Grid (PDFs, Textbooks, Slides, Video Courses)
                    _UnifiedStudySourcesGrid(
                      courses: _filterTab == 1 ? const [] : recentCourses,
                      resources: _filterTab == 1 ? recentResources : const [],
                      onOpenCourse: (id) => Nav.course(context, id),
                      onOpenResource: (id) => Nav.resource(context, id),
                      onAddSource: () => _openAddSourceSheet(context),
                      onGoToMaps: () => widget.onNavigate(Section.maps),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _formatWatchTime(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
    return '$m min';
  }
}

class _SourceModalRow extends StatelessWidget {
  const _SourceModalRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.surfaceSunken,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: c.ink),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: MType.bodyStrong.copyWith(
                      color: c.ink,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: MType.small.copyWith(
                      color: c.inkMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Left hero card matching the CourseBox reference layout ("Continue Studying / Watching"),
/// supporting whichever study source the learner used most recently: a video lesson,
/// a PDF textbook/slide deck, or a structured course.
class _ContinueStudyingCard extends StatelessWidget {
  const _ContinueStudyingCard({
    required this.compact,
    required this.continueRow,
    required this.firstResourceRow,
    required this.firstCourseRow,
    required this.onResumeLesson,
    required this.onOpenResource,
    required this.onOpenCourse,
    required this.onAddSource,
  });

  final bool compact;
  final Map<String, Object?>? continueRow;
  final Map<String, Object?>? firstResourceRow;
  final Map<String, Object?>? firstCourseRow;
  final void Function(String courseId, String lessonId) onResumeLesson;
  final ValueChanged<String> onOpenResource;
  final ValueChanged<String> onOpenCourse;
  final VoidCallback onAddSource;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final String headerTitle;
    final String sourceTitle;
    final String itemSubtitle;
    final double progress;
    final bool hasProgress;
    final String? coverPath;
    final IconData centerBadgeIcon;
    final VoidCallback onAction;

    if (continueRow != null) {
      final row = continueRow!;
      headerTitle = 'Continue\nWatching';
      sourceTitle = row['course_title'] as String? ?? 'Course';
      itemSubtitle = row['title'] as String? ?? 'Lesson';
      final dur = row['duration_ms'] as int? ?? 0;
      final pos = row['position_ms'] as int? ?? 0;
      progress = dur <= 0 ? 0.0 : (pos / dur).clamp(0.0, 1.0);
      hasProgress = dur > 0;
      coverPath = null;
      centerBadgeIcon = Icons.play_arrow_rounded;
      onAction = () =>
          onResumeLesson(row['course_id'] as String, row['id'] as String);
    } else if (firstResourceRow != null) {
      final row = firstResourceRow!;
      final kind = (row['kind'] as String? ?? 'pdf').toUpperCase();
      headerTitle = 'Continue\nStudying';
      sourceTitle = row['title'] as String? ?? 'Document';
      itemSubtitle = '$kind · Interactive reader, notes, formulas & AI Tutor';
      progress = 0.0;
      hasProgress = false;
      coverPath = null;
      centerBadgeIcon = kind == 'PDF'
          ? Icons.menu_book_rounded
          : Icons.description_outlined;
      onAction = () => onOpenResource(row['id'] as String);
    } else if (firstCourseRow != null) {
      final row = firstCourseRow!;
      headerTitle = 'Continue\nStudying';
      sourceTitle = row['title'] as String? ?? 'Course';
      final lessonCount = row['lesson_count'] as int? ?? 0;
      final completedCount = row['completed_count'] as int? ?? 0;
      itemSubtitle = lessonCount > 0
          ? '$lessonCount ${lessonCount == 1 ? 'lesson' : 'lessons'} · Video, notes & flashcards'
          : 'Open course to add lessons or PDFs';
      progress = lessonCount == 0
          ? 0.0
          : (completedCount / lessonCount).clamp(0.0, 1.0);
      hasProgress = lessonCount > 0;
      coverPath = row['cover'] as String?;
      centerBadgeIcon = Icons.play_arrow_rounded;
      onAction = () => onOpenCourse(row['id'] as String);
    } else {
      headerTitle = 'Continue\nStudying';
      sourceTitle = 'Your Personal Study Ecosystem';
      itemSubtitle = 'Add PDFs, books, slides, notes, maps or video courses';
      progress = 0.0;
      hasProgress = false;
      coverPath = null;
      centerBadgeIcon = Icons.add_rounded;
      onAction = onAddSource;
    }

    final art = Stack(
      fit: StackFit.expand,
      children: [
        _StudioCourseArtwork(title: sourceTitle, coverPath: coverPath, seed: 0),
        Center(
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFF161618).withValues(alpha: 0.86),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(centerBadgeIcon, size: 28, color: Colors.white),
          ),
        ),
      ],
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          headerTitle,
          style: MType.h1.copyWith(
            color: c.ink,
            fontSize: 25,
            height: 1.15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          sourceTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MType.h3.copyWith(
            color: c.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          itemSubtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MType.small.copyWith(color: c.inkMuted, fontSize: 12.5),
        ),
        const SizedBox(height: 18),
        if (hasProgress)
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: c.surfaceSunken,
                    valueColor: AlwaysStoppedAnimation(c.ink),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(progress * 100).round()}%',
                style: MType.small.copyWith(
                  color: c.inkMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          )
        else
          Text(
            _hintFor(continueRow, firstResourceRow, firstCourseRow),
            style: MType.small.copyWith(color: c.inkFaint, fontSize: 11.5),
          ),
      ],
    );
    return MCard(
      padding: const EdgeInsets.all(20),
      radius: MRadius.xl,
      onTap: onAction,
      child: compact
          // Narrow cards stack the artwork above the text instead of
          // squeezing the copy into a few pixels.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: art,
                  ),
                ),
                const SizedBox(height: 16),
                details,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(width: 176, height: 158, child: art),
                ),
                const SizedBox(width: 22),
                Expanded(child: details),
              ],
            ),
    );
  }
}

String _hintFor(
  Map<String, Object?>? continueRow,
  Map<String, Object?>? resource,
  Map<String, Object?>? course,
) {
  if (continueRow != null) return 'Resume where you left off';
  if (resource != null) return 'Open the reader to pick up where you left off';
  if (course != null) return 'Start the first lesson to begin this course';
  return 'Add a source to start studying';
}

class _LearningProgressCard extends StatelessWidget {
  const _LearningProgressCard({
    required this.watchedMs,
    required this.actions,
    required this.activeDays,
    required this.dailySeries,
    required this.rangeLabel,
    required this.onRangeChanged,
  });

  final int watchedMs;
  final int actions;
  final int activeDays;
  final List<Map<String, Object?>> dailySeries;
  final String rangeLabel;
  final ValueChanged<String> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    final spanDays = switch (rangeLabel) {
      'Last 7 Days' => 7,
      'Last 90 Days' => 90,
      _ => 30,
    };
    final stepDays = (spanDays / 4).round().clamp(1, 30);
    final dateFmt = DateFormat('MMM d');
    final axisDates = [
      for (var i = 4; i >= 0; i--)
        dateFmt.format(now.subtract(Duration(days: i * stepDays))),
    ];

    final points = <double>[0, 0, 0, 0, 0];
    final actionCounts = <int>[0, 0, 0, 0, 0];

    for (final row in dailySeries) {
      final dStr = row['d'] as String?;
      final ms = (row['ms'] as num? ?? 0).toDouble();
      final acts = (row['actions'] as num? ?? 0).toInt();
      if (dStr == null) continue;
      final d = DateTime.tryParse(dStr);
      if (d == null) continue;
      final daysAgo = now.difference(d).inDays;
      if (daysAgo < 0 || daysAgo > spanDays) continue;
      final bucket = (4 - ((daysAgo / spanDays) * 4).floor()).clamp(0, 4);
      points[bucket] += ms / (1000 * 60);
      actionCounts[bucket] += acts;
    }

    var peakIdx = 4;
    var peakVal = -1.0;
    for (var i = 0; i < points.length; i++) {
      if (points[i] >= peakVal) {
        peakVal = points[i];
        peakIdx = i;
      }
    }

    final totalMinutes = points.fold<double>(0, (a, b) => a + b).round();
    final badgeText = actions > 0
        ? '$actions learning actions · $activeDays active days'
        : totalMinutes > 0
        ? '$totalMinutes min of real study'
        : 'No activity yet';

    return MCard(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      radius: MRadius.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Learning Progress',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MType.h2.copyWith(
                              color: c.ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const LearningActionsInfo(),
                      ],
                    ),
                    Text(
                      'Real actions: lessons finished, cards reviewed, notes and schemas written',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MType.small.copyWith(
                        color: c.inkMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                initialValue: rangeLabel,
                onSelected: onRangeChanged,
                color: c.surface,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'Last 7 Days',
                    child: Text('Last 7 Days'),
                  ),
                  PopupMenuItem(
                    value: 'Last 30 Days',
                    child: Text('Last 30 Days'),
                  ),
                  PopupMenuItem(
                    value: 'Last 90 Days',
                    child: Text('Last 90 Days'),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.isDark
                        ? Colors.white.withValues(alpha: 0.075)
                        : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(MRadius.pill),
                    border: Border.all(
                      color: context.isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : c.line,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rangeLabel,
                        style: MType.small.copyWith(
                          color: c.inkMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: c.inkMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 128,
            width: double.infinity,
            child: CustomPaint(
              painter: _ProgressChartPainter(
                values: points,
                peakIndex: peakIdx,
                lineColor: c.ink,
                fillColor: c.surfaceSunken,
                gridColor: c.line,
                pointColor: context.isDark ? c.surface : Colors.white,
                badgeColor: context.isDark ? c.accent : const Color(0xFF18181B),
                badgeTextColor: context.isDark ? c.accentInk : Colors.white,
                badgeText: badgeText,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in axisDates)
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.small.copyWith(
                      color: c.inkFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressChartPainter extends CustomPainter {
  _ProgressChartPainter({
    required this.values,
    required this.peakIndex,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.pointColor,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.badgeText,
  });

  final List<double> values;
  final int peakIndex;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color pointColor;
  final Color badgeColor;
  final Color badgeTextColor;
  final String badgeText;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = h * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    final maxVal = values.fold<double>(0, math.max);
    // Honest zero baseline when there is no recorded study activity yet;
    // proportional scaling when real data exists.
    final norm = maxVal <= 0
        ? const [0.06, 0.06, 0.06, 0.06, 0.06]
        : values.map((v) => 0.08 + 0.76 * (v / maxVal)).toList();

    final pts = <Offset>[];
    for (var i = 0; i < norm.length; i++) {
      final x = w * (i / (norm.length - 1));
      final y = h * (1.0 - norm[i]);
      pts.add(Offset(x, y));
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = lineColor.withValues(alpha: maxVal <= 0 ? 0.04 : 0.08)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    final focusPt = pts[peakIndex.clamp(0, pts.length - 1)];
    canvas.drawCircle(focusPt, 6, Paint()..color = pointColor);
    canvas.drawCircle(
      focusPt,
      5,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );

    final tp = TextPainter(
      maxLines: 1,
      ellipsis: '…',
      text: TextSpan(
        text: badgeText,
        style: TextStyle(
          fontFamily: 'Inter',
          color: badgeTextColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: math.max(40, w - 20));

    final badgeW = tp.width + 18;
    final badgeH = tp.height + 8;
    final minX = badgeW / 2 + 4;
    final maxX = math.max(minX, w - badgeW / 2 - 4);
    final minY = badgeH / 2 + 2;
    final maxY = math.max(minY, h - badgeH / 2 - 2);
    final cx = focusPt.dx.clamp(minX, maxX);
    final cy = (focusPt.dy - 22).clamp(minY, maxY);
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: badgeW, height: badgeH),
      const Radius.circular(8),
    );
    canvas.drawRRect(badgeRect, Paint()..color = badgeColor);
    tp.paint(canvas, Offset(badgeRect.left + 9, badgeRect.top + 4));
  }

  @override
  bool shouldRepaint(covariant _ProgressChartPainter old) =>
      old.badgeText != badgeText ||
      !listEquals(old.values, values) ||
      old.peakIndex != peakIndex ||
      old.lineColor != lineColor ||
      old.fillColor != fillColor ||
      old.gridColor != gridColor ||
      old.pointColor != pointColor ||
      old.badgeColor != badgeColor ||
      old.badgeTextColor != badgeTextColor;
}

class _HorizontalStatCard extends StatelessWidget {
  const _HorizontalStatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      radius: MRadius.lg,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 22, color: c.ink),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MType.h1.copyWith(
                    color: c.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MType.small.copyWith(
                    color: c.inkMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkPillAddButton extends StatelessWidget {
  const _DarkPillAddButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.ink,
      borderRadius: BorderRadius.circular(MRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18, color: c.surface),
              const SizedBox(width: 6),
              Text(
                label,
                style: MType.bodyStrong.copyWith(
                  color: c.surface,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unified 3-column grid showing both Library Study Sources (PDF books, slides,
/// documents, audio lectures) and Video Courses in the exact card geometry of the reference.
class _UnifiedStudySourcesGrid extends StatelessWidget {
  const _UnifiedStudySourcesGrid({
    required this.courses,
    required this.resources,
    required this.onOpenCourse,
    required this.onOpenResource,
    required this.onAddSource,
    required this.onGoToMaps,
  });

  final List<Map<String, Object?>> courses;
  final List<Map<String, Object?>> resources;
  final ValueChanged<String> onOpenCourse;
  final ValueChanged<String> onOpenResource;
  final VoidCallback onAddSource;
  final VoidCallback onGoToMaps;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final items = <_UnifiedSourceItem>[];

    for (final r in resources) {
      final kind = (r['kind'] as String? ?? 'pdf').toUpperCase();
      final sizeBytes = r['size'] as int? ?? 0;
      items.add(
        _UnifiedSourceItem(
          id: r['id'] as String,
          title: r['title'] as String? ?? 'Document',
          subtitle:
              '$kind · ${humanFileSize(sizeBytes)} · Notes, Formulas & AI',
          badge: kind,
          progress: 0,
          coverPath: null,
          isCourse: false,
        ),
      );
    }

    for (final row in courses) {
      final lessonCount = row['lesson_count'] as int? ?? 0;
      final completedCount = row['completed_count'] as int? ?? 0;
      final totalDurationMs = row['total_duration_ms'] as int? ?? 0;
      final progress = lessonCount == 0
          ? 0.0
          : (completedCount / lessonCount).clamp(0.0, 1.0);
      final durationLabel = totalDurationMs > 0
          ? _HomePageState._formatWatchTime(totalDurationMs)
          : '${lessonCount * 18} min';
      items.add(
        _UnifiedSourceItem(
          id: row['id'] as String,
          title: row['title'] as String? ?? 'Course',
          subtitle:
              '$lessonCount ${lessonCount == 1 ? 'lesson' : 'lessons'}  ·  $durationLabel',
          badge: 'COURSE',
          progress: progress,
          coverPath: row['cover'] as String?,
          isCourse: true,
        ),
      );
    }

    if (items.isEmpty) {
      return MCard(
        padding: const EdgeInsets.all(28),
        radius: MRadius.xl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bring all your study sources into one workspace',
              style: MType.h2.copyWith(color: c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'Load PDFs, textbooks, slides, lecture transcripts, notes, or video courses. '
              'Extract LaTeX formulas & keywords, build concept maps, review with spaced repetition, '
              'and ask the AI Tutor with exact citations.',
              style: MType.body.copyWith(color: c.inkMuted, height: 1.55),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                MButton(
                  label: 'Add Books, PDFs & Files',
                  icon: Icons.picture_as_pdf_outlined,
                  kind: MButtonKind.primary,
                  onPressed: onAddSource,
                ),
                MButton(
                  label: 'Import Video Course Folder',
                  icon: Icons.create_new_folder_outlined,
                  onPressed: onAddSource,
                ),
                MButton(
                  label: 'Build a Concept Map',
                  icon: Icons.account_tree_outlined,
                  onPressed: onGoToMaps,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 740
            ? 3
            : constraints.maxWidth > 480
            ? 2
            : 1;
        final width = (constraints.maxWidth - (cols - 1) * 20) / cols;
        return Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: width,
                child: _ReferenceSourceCard(
                  item: items[i],
                  seed: i + 1,
                  onTap: () => items[i].isCourse
                      ? onOpenCourse(items[i].id)
                      : onOpenResource(items[i].id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UnifiedSourceItem {
  const _UnifiedSourceItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.progress,
    required this.coverPath,
    required this.isCourse,
  });

  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final double progress;
  final String? coverPath;
  final bool isCourse;
}

class _ReferenceSourceCard extends StatelessWidget {
  const _ReferenceSourceCard({
    required this.item,
    required this.seed,
    required this.onTap,
  });

  final _UnifiedSourceItem item;
  final int seed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MCard(
      padding: const EdgeInsets.all(14),
      radius: MRadius.xl,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 158,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _StudioCourseArtwork(
                    title: item.title,
                    coverPath: item.coverPath,
                    seed: seed,
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(MRadius.pill),
                      ),
                      child: Text(
                        item.badge,
                        style: MType.label.copyWith(
                          color: Colors.white,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (item.isCourse)
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 5,
                      backgroundColor: c.surfaceSunken,
                      valueColor: AlwaysStoppedAnimation(c.ink),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(item.progress * 100).round()}%',
                  style: MType.small.copyWith(
                    color: c.inkMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            Text(
              item.badge,
              style: MType.small.copyWith(
                color: c.inkFaint,
                fontSize: 10,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MType.h3.copyWith(
                color: c.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MType.small.copyWith(color: c.inkMuted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudioCourseArtwork extends StatelessWidget {
  const _StudioCourseArtwork({
    required this.title,
    this.coverPath,
    required this.seed,
  });

  final String title;
  final String? coverPath;
  final int seed;

  @override
  Widget build(BuildContext context) {
    if (coverPath != null && File(coverPath!).existsSync()) {
      return Image.file(File(coverPath!), fit: BoxFit.cover);
    }
    const palettes = [
      (Color(0xFF23272F), Color(0xFF3B4252), Icons.menu_book_rounded),
      (Color(0xFF1F2421), Color(0xFF353E39), Icons.code_rounded),
      (Color(0xFF2B2623), Color(0xFF4A4039), Icons.science_outlined),
      (Color(0xFF25242B), Color(0xFF3E3C4A), Icons.account_tree_outlined),
    ];
    final p = palettes[seed % palettes.length];
    return Container(
      decoration: BoxDecoration(color: p.$1),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: p.$2.withValues(alpha: 0.65),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 16,
            right: 18,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    p.$3,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.bodyStrong.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet info dot that opens a styled card, matching the app's surfaces
/// instead of the platform tooltip.
class LearningActionsInfo extends StatefulWidget {
  const LearningActionsInfo({super.key});

  @override
  State<LearningActionsInfo> createState() => _LearningActionsInfoState();
}

class _LearningActionsInfoState extends State<LearningActionsInfo> {
  OverlayEntry? _entry;

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  void _show() {
    final c = context.c;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || _entry != null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    _entry = OverlayEntry(
      builder: (context) {
        const width = 330.0;
        final left = (origin.dx - width + 24).clamp(
          12.0,
          overlay.size.width - width - 12,
        );
        return Positioned(
          left: left,
          top: origin.dy + 26,
          width: width,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.line),
                  boxShadow: [
                    BoxShadow(
                      color: context.elevationShadow(0.18, darkAlpha: 0.45),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What counts as a learning action',
                      style: MType.bodyStrong.copyWith(
                        color: c.ink,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final line in const [
                      'A lesson marked complete — by hand or at 92% of playback',
                      'A flashcard reviewed',
                      'A note or page written',
                      'A keyword, formula or quote extracted',
                      'A schema or concept map edited',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: c.inkFaint,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line,
                                style: MType.small.copyWith(
                                  color: c.inkMuted,
                                  fontSize: 11.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Divider(height: 16, color: c.line),
                    Text(
                      'Study time is real video playback plus the measured duration of each review. Time with the app open but idle is never counted.',
                      style: MType.small.copyWith(
                        color: c.inkFaint,
                        fontSize: 10.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MouseRegion(
      cursor: SystemMouseCursors.help,
      onEnter: (_) => _show(),
      onExit: (_) => _remove(),
      child: Icon(Icons.info_outline_rounded, size: 15, color: c.inkFaint),
    );
  }
}
