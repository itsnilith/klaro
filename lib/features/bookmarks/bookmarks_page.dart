import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/state.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../shell.dart';

class BookmarkEntry {
  const BookmarkEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.pinned,
    required this.onOpen,
    required this.onTogglePin,
  });

  final String kind; // note | course | lesson | resource | map
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool pinned;
  final VoidCallback onOpen;
  final Future<void> Function() onTogglePin;

  String get badgeLabel => switch (kind) {
        'note' => 'Page / Note',
        'course' => 'Video Course',
        'lesson' => 'Video Lesson',
        'resource' => 'Library',
        'map' => 'Schema',
        _ => 'Item',
      };
}

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  List<BookmarkEntry> _allItems = const [];
  String _filter = 'all'; // all | note | course | lesson | resource | map
  String _query = '';
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
    final notes = await Store.i.notes();
    final courses = await Store.i.courses();
    final lessons = await Store.i.allLessons();
    final resources = await Store.i.resources();
    final maps = await Store.i.conceptMaps();

    final pinnedNoteIds = await Store.i.bookmarkIdsFor('note');
    final pinnedCourseIds = await Store.i.bookmarkIdsFor('course');
    final pinnedLessonIds = await Store.i.bookmarkIdsFor('lesson');
    final pinnedResourceIds = await Store.i.bookmarkIdsFor('resource');
    final pinnedMapIds = await Store.i.bookmarkIdsFor('map');

    final courseMap = {for (final c in courses) c.id: c};
    final entries = <BookmarkEntry>[];

    for (final n in notes) {
      final isPinned = n.pinned || pinnedNoteIds.contains(n.id);
      final parent = n.parentId == null
          ? null
          : notes.where((x) => x.id == n.parentId).firstOrNull;
      entries.add(BookmarkEntry(
        kind: 'note',
        id: n.id,
        title: n.title.isEmpty ? 'Untitled page' : n.title,
        subtitle: parent != null
            ? 'Sub-page of ${parent.title} · Updated ${relativeDate(n.updatedAt)}'
            : 'Note page · Updated ${relativeDate(n.updatedAt)}',
        icon: Icons.edit_note_rounded,
        pinned: isPinned,
        onOpen: () {
          AppState.i.setActiveWorkspaceContext(section: 'Note page', noteId: n.id);
          Shell.of(context)?.go(Section.notes, preserveFocus: true);
        },
        onTogglePin: () async {
          final next = !isPinned;
          await Store.i.saveNote(n.copyWith(pinned: next, updatedAt: DateTime.now()));
          if (pinnedNoteIds.contains(n.id) != next) {
            await Store.i.toggleBookmark('note', n.id);
          }
          AppState.i.bump();
        },
      ));
    }

    for (final c in courses) {
      final isPinned = c.favorite || pinnedCourseIds.contains(c.id);
      entries.add(BookmarkEntry(
        kind: 'course',
        id: c.id,
        title: c.title,
        subtitle: [
          if (c.author != null && c.author!.isNotEmpty) c.author!,
          if (c.category != null && c.category!.isNotEmpty) c.category!,
          'Video Course',
        ].join(' · '),
        icon: Icons.ondemand_video_rounded,
        pinned: isPinned,
        onOpen: () => Nav.course(context, c.id),
        onTogglePin: () async {
          final next = !isPinned;
          await Store.i.saveCourse(c.copyWith(favorite: next, updatedAt: DateTime.now()));
          if (pinnedCourseIds.contains(c.id) != next) {
            await Store.i.toggleBookmark('course', c.id);
          }
          AppState.i.bump();
        },
      ));
    }

    for (final l in lessons) {
      final isPinned = pinnedLessonIds.contains(l.id);
      final parentCourse = courseMap[l.courseId];
      entries.add(BookmarkEntry(
        kind: 'lesson',
        id: l.id,
        title: l.title,
        subtitle: [
          if (parentCourse != null) parentCourse.title,
          if (l.durationMs > 0) formatDuration(Duration(milliseconds: l.durationMs)),
          'Lesson',
        ].join(' · '),
        icon: Icons.play_circle_outline_rounded,
        pinned: isPinned,
        onOpen: () => Nav.lesson(context, l.courseId, l.id),
        onTogglePin: () async {
          await Store.i.toggleBookmark('lesson', l.id);
          AppState.i.bump();
        },
      ));
    }

    for (final r in resources) {
      final isPinned = r.favorite || pinnedResourceIds.contains(r.id);
      entries.add(BookmarkEntry(
        kind: 'resource',
        id: r.id,
        title: r.title,
        subtitle: '${r.kind.toUpperCase()} · ${humanFileSize(r.size)}',
        icon: Icons.menu_book_rounded,
        pinned: isPinned,
        onOpen: () => Nav.resource(context, r.id),
        onTogglePin: () async {
          final next = !isPinned;
          await Store.i.db.update(
            'resources',
            {'favorite': next ? 1 : 0},
            where: 'id = ?',
            whereArgs: [r.id],
          );
          if (pinnedResourceIds.contains(r.id) != next) {
            await Store.i.toggleBookmark('resource', r.id);
          }
          AppState.i.bump();
        },
      ));
    }

    for (final m in maps) {
      final isPinned = pinnedMapIds.contains(m.id);
      entries.add(BookmarkEntry(
        kind: 'map',
        id: m.id,
        title: m.title,
        subtitle: '${m.kind.toUpperCase()} · Updated ${relativeDate(m.updatedAt)}',
        icon: Icons.account_tree_outlined,
        pinned: isPinned,
        onOpen: () {
          Shell.of(context)?.go(Section.maps);
        },
        onTogglePin: () async {
          await Store.i.toggleBookmark('map', m.id);
          AppState.i.bump();
        },
      ));
    }

    if (!mounted) return;
    setState(() {
      _allItems = entries;
      _loading = false;
    });
  }

  Future<void> _openPinPicker() async {
    final c = context.c;
    String search = '';
    String tab = 'all';
    await showMSheet<void>(
      context,
      maxWidth: 580,
      child: StatefulBuilder(
        builder: (context, setModal) {
          final q = search.trim().toLowerCase();
          final candidates = _allItems.where((item) {
            if (tab != 'all' && item.kind != tab) return false;
            if (q.isEmpty) return true;
            return item.title.toLowerCase().contains(q) ||
                item.subtitle.toLowerCase().contains(q);
          }).toList();

          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 580),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const MDialogHeader(
                    title: 'Pin items to Bookmarks',
                    subtitle:
                        'Pin any page, note, video course, lesson, book or schema for instant access.',
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search pages, courses, lessons, books, schemas…',
                        prefixIcon: Icon(Icons.search_rounded, size: 17),
                        isDense: true,
                      ),
                      onChanged: (v) => setModal(() => search = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final entry in const [
                          ('all', 'All'),
                          ('note', 'Pages & Notes'),
                          ('course', 'Courses'),
                          ('lesson', 'Lessons'),
                          ('resource', 'Library'),
                          ('map', 'Schemas'),
                        ])
                          MChip(
                            label: entry.$2,
                            selected: tab == entry.$1,
                            onTap: () => setModal(() => tab = entry.$1),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  Flexible(
                    child: candidates.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              'No items found in your workspace yet.',
                              textAlign: TextAlign.center,
                              style: MType.small.copyWith(color: c.inkMuted),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: candidates.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: c.line.withValues(alpha: 0.6)),
                            itemBuilder: (context, index) {
                              final item = candidates[index];
                              return ListTile(
                                dense: true,
                                leading: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: c.surfaceAlt,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(color: c.line),
                                  ),
                                  child: Icon(item.icon, size: 17, color: c.ink),
                                ),
                                title: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: MType.bodyStrong.copyWith(fontSize: 13, color: c.ink),
                                ),
                                subtitle: Text(
                                  item.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: MType.small.copyWith(fontSize: 11, color: c.inkMuted),
                                ),
                                trailing: IconButton(
                                  tooltip: item.pinned ? 'Unpin' : 'Pin to Bookmarks',
                                  icon: Icon(
                                    item.pinned
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_add_outlined,
                                    size: 19,
                                    color: item.pinned ? c.ink : c.inkMuted,
                                  ),
                                  onPressed: () async {
                                    await item.onTogglePin();
                                    await _load();
                                    setModal(() {});
                                  },
                                ),
                                onTap: () async {
                                  await item.onTogglePin();
                                  await _load();
                                  setModal(() {});
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pinned = _allItems.where((e) => e.pinned).toList();
    final q = _query.trim().toLowerCase();
    final visible = pinned.where((item) {
      if (_filter != 'all' && item.kind != _filter) return false;
      if (q.isEmpty) return true;
      return item.title.toLowerCase().contains(q) ||
          item.subtitle.toLowerCase().contains(q);
    }).toList();

    int countOf(String kind) =>
        pinned.where((e) => kind == 'all' || e.kind == kind).length;

    return MSmoothScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bookmarks', style: MType.h1.copyWith(color: c.ink, fontSize: 26)),
                    const SizedBox(height: 2),
                    Text(
                      '${pinned.length} pinned · Pages, notes, video courses, lessons, books & schemas kept in focus',
                      style: MType.small.copyWith(color: c.inkMuted),
                    ),
                  ],
                ),
              ),
              MButton(
                label: 'Pin item',
                icon: Icons.bookmark_add_outlined,
                kind: MButtonKind.primary,
                onPressed: _openPinPicker,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tab in [
                      ('all', 'All (${countOf('all')})'),
                      ('note', 'Pages & Notes (${countOf('note')})'),
                      ('course', 'Video Courses (${countOf('course')})'),
                      ('lesson', 'Lessons (${countOf('lesson')})'),
                      ('resource', 'Library (${countOf('resource')})'),
                      ('map', 'Schemas (${countOf('map')})'),
                    ])
                      MChip(
                        label: tab.$2,
                        selected: _filter == tab.$1,
                        onTap: () => setState(() => _filter = tab.$1),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 240,
                child: TextField(
                  style: MType.body.copyWith(color: c.ink, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Filter bookmarks…',
                    prefixIcon: Icon(Icons.search_rounded, size: 17),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (visible.isEmpty)
            MEmpty(
              icon: Icons.bookmarks_outlined,
              title: pinned.isEmpty ? 'No bookmarks pinned yet' : 'No bookmark matches this filter',
              message: pinned.isEmpty
                  ? 'Pin any note page, video course, individual video lesson, library book or study schema to keep your key material in one place.'
                  : 'Try another category or clear the search filter.',
              action: MButton(
                label: 'Pin an item',
                icon: Icons.bookmark_add_outlined,
                kind: MButtonKind.primary,
                onPressed: _openPinPicker,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 980
                    ? 3
                    : constraints.maxWidth >= 620
                        ? 2
                        : 1;
                const gap = 14.0;
                final cardWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final item in visible)
                      SizedBox(
                        width: cardWidth,
                        child: MCard(
                          padding: const EdgeInsets.all(16),
                          radius: MRadius.lg,
                          onTap: item.onOpen,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: c.surfaceSunken,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(item.icon, size: 20, color: c.ink),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: c.surfaceAlt,
                                            borderRadius: BorderRadius.circular(5),
                                            border: Border.all(color: c.line),
                                          ),
                                          child: Text(
                                            item.badgeLabel,
                                            style: MType.small.copyWith(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: c.inkMuted,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        MIconButton(
                                          icon: Icons.bookmark_rounded,
                                          size: 26,
                                          tooltip: 'Remove from Bookmarks',
                                          onPressed: item.onTogglePin,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: MType.h3.copyWith(color: c.ink, fontSize: 14.5),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: MType.small.copyWith(
                                          color: c.inkMuted, fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
