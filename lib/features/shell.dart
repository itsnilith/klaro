import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/db.dart';
import '../core/i18n.dart';
import '../core/state.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import 'bookmarks/bookmarks_page.dart';
import 'courses/courses_page.dart';
import 'courses/lesson_page.dart';
import 'home/home_page.dart';
import 'library/library_page.dart';
import 'library/resource_viewer.dart';
import 'maps/maps_page.dart';
import 'notes/notes_page.dart';
import 'review/review_page.dart';
import 'settings/settings_page.dart';
import 'shell_dialogs.dart';
import 'tutor/tutor_page.dart';

enum Section {
  home,
  bookmarks,
  courses,
  library,
  notes,
  maps,
  review,
  tutor,
  settings,
}

class SectionInfo {
  const SectionInfo(this.section, this.label, this.icon, this.shortcut);
  final Section section;
  final String label;
  final IconData icon;
  final String shortcut;
}

const sections = [
  SectionInfo(Section.home, 'Home', Icons.home_rounded, '1'),
  SectionInfo(Section.bookmarks, 'Bookmarks', Icons.bookmarks_outlined, '2'),
  SectionInfo(
    Section.courses,
    'Video Courses',
    Icons.ondemand_video_rounded,
    '3',
  ),
  SectionInfo(Section.library, 'Library', Icons.menu_book_rounded, '4'),
  SectionInfo(Section.notes, 'Notes & Pages', Icons.edit_note_rounded, '5'),
  SectionInfo(Section.maps, 'Maps & Schemas', Icons.account_tree_outlined, '6'),
  SectionInfo(Section.review, 'Flashcards & Review', Icons.style_outlined, '7'),
  SectionInfo(Section.tutor, 'AI Tutor', Icons.auto_awesome_outlined, '8'),
];

class Nav {
  static NavigatorState _nav(BuildContext context) {
    final shell = Shell.of(context);
    final nav = shell?.contentNavigator;
    return nav ?? Navigator.of(context);
  }

  static Future<void> course(BuildContext context, String id) {
    AppState.i.setActiveWorkspaceContext(section: 'Video Course', courseId: id);
    return _nav(
      context,
    ).push(MaterialPageRoute(builder: (_) => CourseDetailPage(courseId: id)));
  }

  static Future<void> lesson(
    BuildContext context,
    String courseId,
    String lessonId,
  ) {
    AppState.i.setActiveWorkspaceContext(
      section: 'Video Lesson',
      courseId: courseId,
      lessonId: lessonId,
    );
    return _nav(context).push(
      MaterialPageRoute(
        builder: (_) => LessonPage(courseId: courseId, lessonId: lessonId),
      ),
    );
  }

  static Future<void> resource(BuildContext context, String resourceId) {
    AppState.i.setActiveWorkspaceContext(
      section: 'Document Reader',
      resourceId: resourceId,
    );
    return _nav(context).push(
      MaterialPageRoute(
        builder: (_) => ResourceViewerPage(resourceId: resourceId),
      ),
    );
  }

  static void settings(BuildContext context, {String? section}) {
    if (section != null) {
      AppState.i.pendingSettingsTab = section;
      AppState.i.bump();
    }
    Shell.of(context)?.go(Section.settings);
  }

  static void tutor(
    BuildContext context, {
    String? courseId,
    String? lessonId,
    String? prompt,
  }) {
    Shell.of(context)?.tutorContext = (courseId, lessonId, prompt);
    Shell.of(context)?.go(Section.tutor);
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  static ShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<ShellState>();

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  Section _section = Section.home;
  final FocusNode _focus = FocusNode();
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();
  final ValueNotifier<int> _routeEpoch = ValueNotifier<int>(0);

  NavigatorState? get contentNavigator => _contentNavKey.currentState;
  (String?, String?, String?)? tutorContext;
  int _tutorEpoch = 0;

  void go(Section s, {bool preserveFocus = false}) {
    _contentNavKey.currentState?.popUntil((r) => r.isFirst);
    AppState.i.setActiveWorkspaceContext(section: s.name);
    if (s != Section.tutor && !preserveFocus) {
      AppState.i.clearFocusContext();
    }
    if (s == _section) {
      _routeEpoch.value++;
      if (s == Section.settings) setState(() {});
      return;
    }
    setState(() {
      if (s == Section.tutor) _tutorEpoch++;
      _section = s;
      _routeEpoch.value++;
    });
  }

  TextEditingController? _paletteController;

  @override
  void dispose() {
    _focus.dispose();
    _routeEpoch.dispose();
    _paletteController?.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyK) {
      _openPalette();
      return KeyEventResult.handled;
    }
    if (ctrl) {
      final map = {
        LogicalKeyboardKey.digit1: Section.home,
        LogicalKeyboardKey.digit2: Section.bookmarks,
        LogicalKeyboardKey.digit3: Section.courses,
        LogicalKeyboardKey.digit4: Section.library,
        LogicalKeyboardKey.digit5: Section.notes,
        LogicalKeyboardKey.digit6: Section.maps,
        LogicalKeyboardKey.digit7: Section.review,
        LogicalKeyboardKey.digit8: Section.tutor,
      };
      final target = map[event.logicalKey];
      if (target != null) {
        go(target);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _openPalette() {
    _paletteController ??= TextEditingController();
    _paletteController!.clear();
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (ctx) => CommandPalette(
        controller: _paletteController!,
        goTo: (s) => go(s, preserveFocus: true),
        onPick: (action) {
          Navigator.of(ctx).pop();
          action();
        },
      ),
    );
  }

  Widget _page() {
    final child = switch (_section) {
      Section.home => HomePage(
        onNavigate: (s) => go(s),
        key: const ValueKey('home'),
      ),
      Section.bookmarks => const BookmarksPage(key: ValueKey('bookmarks')),
      Section.courses => const CoursesPage(key: ValueKey('courses')),
      Section.library => const LibraryPage(key: ValueKey('library')),
      Section.notes => const NotesPage(key: ValueKey('notes')),
      Section.maps => const ConceptMapsPage(key: ValueKey('maps')),
      Section.review => const ReviewPage(key: ValueKey('review')),
      Section.tutor => TutorPage(
        key: ValueKey('tutor-$_tutorEpoch'),
        initialContext: tutorContext,
      ),
      Section.settings => const SettingsPage(key: ValueKey('settings')),
    };
    // Switch pages outright. The previous PageTransitionSwitcher stacked the
    // outgoing page above the incoming one while its animation ran, which on
    // this desktop build could leave a stale layer that centred short pages and
    // swallowed every click inside them.
    // The new page fades in on its own: the previous one is removed at once, so
    // there is no double exposure between two full-page surfaces.
    return MFadeIn(
      key: ValueKey(_section),
      duration: const Duration(milliseconds: 180),
      child: child,
    );
  }

  Future<void> _quickAdd() async {
    final choice = await showMSheet<String>(
      context,
      maxWidth: 440,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MDialogHeader(
              title: 'Add to klaro.',
              subtitle: 'Everything stays on this device unless you sync it.',
            ),
            _AddRow(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Add books, PDFs, slides or files',
              subtitle:
                  'Read, extract LaTeX formulas & keywords, or ask the Tutor',
              onTap: () => Navigator.of(context).pop('files'),
            ),
            _AddRow(
              icon: Icons.create_new_folder_outlined,
              title: 'Import a video course folder',
              subtitle: 'Use your existing video files without moving them',
              onTap: () => Navigator.of(context).pop('folder'),
            ),
            _AddRow(
              icon: Icons.school_outlined,
              title: 'New structured course',
              subtitle: 'Create a course and add your own lessons',
              onTap: () => Navigator.of(context).pop('course'),
            ),
            _AddRow(
              icon: Icons.note_add_outlined,
              title: 'Write a note',
              subtitle: 'A standalone note, linked later if you want',
              onTap: () => Navigator.of(context).pop('note'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'course':
        await showCourseEditor(context);
      case 'folder':
        await importCourseFolder(context);
      case 'files':
        await importLibraryFiles(context);
      case 'note':
        go(Section.notes);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (mounted) await showNoteEditor(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: c.canvas,
        body: Column(
          children: [
            _TopHeaderBar(
              onLogoTap: () => go(Section.home),
              onSearchTap: _openPalette,
              onAiAssistantTap: () => go(Section.tutor),
              onQuickAddTap: _quickAdd,
              onThemeToggle: () {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                AppState.i.setTheme(isDark ? ThemeMode.light : ThemeMode.dark);
              },
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FloatingIconRail(section: _section, onSelect: go),
                  Expanded(
                    child: Navigator(
                      key: _contentNavKey,
                      onGenerateRoute: (_) => PageRouteBuilder<void>(
                        pageBuilder: (context, _, _) =>
                            ValueListenableBuilder<int>(
                              valueListenable: _routeEpoch,
                              builder: (context, _, _) => _page(),
                            ),
                        transitionDuration: const Duration(milliseconds: 220),
                        reverseTransitionDuration: const Duration(
                          milliseconds: 180,
                        ),
                        transitionsBuilder:
                            (context, animation, secondary, child) {
                              return FadeTransition(
                                opacity: CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOut,
                                ),
                                child: child,
                              );
                            },
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

/// Top header bar matching the CourseBox primary design reference.
/// Only empty space is wrapped in a window drag region so buttons never miss clicks.
class _TopHeaderBar extends StatelessWidget {
  const _TopHeaderBar({
    required this.onLogoTap,
    required this.onSearchTap,
    required this.onAiAssistantTap,
    required this.onQuickAddTap,
    required this.onThemeToggle,
  });

  final VoidCallback onLogoTap;
  final VoidCallback onSearchTap;
  final VoidCallback onAiAssistantTap;
  final VoidCallback onQuickAddTap;
  final VoidCallback onThemeToggle;

  Widget _dragRegion() {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => windowManager.startDragging(),
        onDoubleTap: () async {
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        },
        child: const SizedBox(height: 54),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        final showSearch = w >= 1000;
        final showAiLabel = w >= 980;
        final tight = w < 760;
        return Container(
          height: 76,
          padding: EdgeInsets.fromLTRB(tight ? 16 : 34, 14, tight ? 10 : 18, 8),
          color: c.canvas,
          child: Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onLogoTap,
                  child: KlaroWordmark(size: tight ? 25 : 30),
                ),
              ),
              if (showSearch) ...[
                _dragRegion(),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 460,
                    minWidth: 260,
                  ),
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.34,
                    height: 44,
                    child: Material(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(MRadius.pill),
                      elevation: 0,
                      child: InkWell(
                        onTap: onSearchTap,
                        borderRadius: BorderRadius.circular(MRadius.pill),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(MRadius.pill),
                            border: Border.all(
                              color: c.line.withValues(alpha: 0.7),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: c.shadow,
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 19,
                                color: c.inkMuted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Search courses, lessons, or notes...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: MType.body.copyWith(
                                    color: c.inkFaint,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _dragRegion(),
              ] else
                _dragRegion(),
              if (!showSearch)
                _CircleHeaderButton(
                  icon: Icons.search_rounded,
                  tooltip: 'Search',
                  onTap: onSearchTap,
                ),
              Material(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.075)
                    : c.surface,
                borderRadius: BorderRadius.circular(MRadius.pill),
                child: InkWell(
                  onTap: onAiAssistantTap,
                  borderRadius: BorderRadius.circular(MRadius.pill),
                  child: Container(
                    height: 42,
                    padding: EdgeInsets.symmetric(
                      horizontal: showAiLabel ? 18 : 13,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(MRadius.pill),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : c.line,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: c.shadow,
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: c.ink,
                        ),
                        if (showAiLabel) ...[
                          const SizedBox(width: 8),
                          Text(
                            'AI Assistant',
                            style: MType.bodyStrong.copyWith(
                              color: c.ink,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _CircleHeaderButton(
                icon: Icons.add_rounded,
                tooltip: 'Quick add / import',
                onTap: onQuickAddTap,
              ),
              const SizedBox(width: 6),
              _CircleHeaderButton(
                icon: isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_outlined,
                tooltip: isDark
                    ? 'Switch to Light mode'
                    : 'Switch to Dark mode',
                onTap: onThemeToggle,
              ),
              const SizedBox(width: 12),
              _WinCtrlButton(
                icon: Icons.remove_rounded,
                onTap: () => windowManager.minimize(),
              ),
              _WinCtrlButton(
                icon: Icons.crop_square_rounded,
                onTap: () async {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
              ),
              _WinCtrlButton(
                icon: Icons.close_rounded,
                danger: true,
                onTap: () => windowManager.close(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CircleHeaderButton extends StatefulWidget {
  const _CircleHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_CircleHeaderButton> createState() => _CircleHeaderButtonState();
}

class _CircleHeaderButtonState extends State<_CircleHeaderButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isDark = context.isDark;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.white.withValues(alpha: _hover ? 0.13 : 0.075)
                  : (_hover ? c.surfaceSunken : c.surface),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: _hover ? 0.24 : 0.15)
                    : c.line,
              ),
              boxShadow: [
                BoxShadow(
                  color: c.shadow,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(widget.icon, size: 19, color: c.ink),
          ),
        ),
      ),
    );
  }
}

class _WinCtrlButton extends StatefulWidget {
  const _WinCtrlButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_WinCtrlButton> createState() => _WinCtrlButtonState();
}

class _WinCtrlButtonState extends State<_WinCtrlButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 34,
          height: 30,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: _hover
                ? (widget.danger ? c.danger : c.surfaceSunken)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            widget.icon,
            size: 15,
            color: _hover && widget.danger
                ? (context.isDark ? c.canvas : Colors.white)
                : c.inkMuted,
          ),
        ),
      ),
    );
  }
}

/// Floating vertical dark capsule on the left with a smooth sliding selection
/// indicator (`AnimatedPositioned`) and dedicated Video Courses (`ondemand_video_rounded`)
/// + Books & Library (`menu_book_rounded`) slots.
class _FloatingIconRail extends StatelessWidget {
  const _FloatingIconRail({required this.section, required this.onSelect});

  final Section section;
  final ValueChanged<Section> onSelect;

  static const _allRailItems = <(Section, String, IconData)>[
    (Section.home, 'Home', Icons.home_rounded),
    (Section.bookmarks, 'Bookmarks', Icons.bookmarks_outlined),
    (Section.courses, 'Video Courses', Icons.ondemand_video_rounded),
    (Section.library, 'Library', Icons.menu_book_rounded),
    (Section.notes, 'Notes & Pages', Icons.edit_note_rounded),
    (Section.maps, 'Maps & Schemas', Icons.account_tree_outlined),
    (Section.review, 'Flashcards & Review', Icons.style_outlined),
    (Section.settings, 'Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.i,
      builder: (context, _) {
        final hidden = AppState.i.hiddenSections;
        final visibleItems = _allRailItems.where((item) {
          if (item.$1 == Section.home || item.$1 == Section.settings) {
            return true;
          }
          return !hidden.contains(item.$2);
        }).toList();

        return LayoutBuilder(
          builder: (context, cons) {
            final activeIdx = visibleItems.indexWhere((e) => e.$1 == section);
            final compact = cons.maxWidth < 700;
            final railWidth = compact ? 76.0 : 112.0;
            final capWidth = compact ? 56.0 : 64.0;
            const slotGap = 6.0;
            const padV = 12.0;
            final n = visibleItems.length;
            // Shrink the slots when the window is short so the rail always fits.
            final availH = cons.maxHeight - 28 - padV * 2;
            final slotSize = n == 0
                ? 44.0
                : ((availH - (n - 1) * slotGap) / n).clamp(30.0, 44.0);
            final stackH = n * slotSize + (n - 1) * slotGap;

            return Container(
              width: railWidth,
              alignment: Alignment.topCenter,
              padding: EdgeInsets.only(
                top: compact ? 18 : 28,
                left: compact ? 10 : 26,
                right: compact ? 10 : 18,
              ),
              child: Container(
                width: capWidth,
                padding: const EdgeInsets.symmetric(vertical: padV),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E22),
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: stackH,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      if (activeIdx >= 0)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          top: activeIdx * (slotSize + slotGap),
                          left: (capWidth - slotSize) / 2,
                          width: slotSize,
                          height: slotSize,
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF38383F),
                            ),
                          ),
                        ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < n; i++) ...[
                            _RailIconButton(
                              label: _sectionLabel(context, visibleItems[i].$1),
                              icon: visibleItems[i].$3,
                              selected: section == visibleItems[i].$1,
                              size: slotSize,
                              onTap: () => onSelect(visibleItems[i].$1),
                            ),
                            if (i < n - 1) const SizedBox(height: slotGap),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

String _sectionLabel(BuildContext context, Section s) {
  final t = L.of(context).t;
  return switch (s) {
    Section.home => t('home'),
    Section.bookmarks => t('bookmarks'),
    Section.courses => t('courses'),
    Section.library => t('library'),
    Section.notes => t('notes'),
    Section.maps => t('maps'),
    Section.review => t('review'),
    Section.tutor => t('tutor'),
    Section.settings => t('settings'),
  };
}

class _RailIconButton extends StatefulWidget {
  const _RailIconButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.size = 44,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  State<_RailIconButton> createState() => _RailIconButtonState();
}

class _RailIconButtonState extends State<_RailIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: !widget.selected && _hover
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              size: widget.size * 0.45,
              color: widget.selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: _hover ? 0.92 : 0.62),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({
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
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(MSpace.x2 + 1),
                border: Border.all(color: c.line),
              ),
              child: Icon(icon, size: 17, color: c.inkMuted),
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
                      fontSize: 13,
                    ),
                  ),
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

// ---------------------------------------------------------------------------
// Command palette

class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.controller,
    required this.onPick,
    required this.goTo,
  });
  final TextEditingController controller;
  final void Function(VoidCallback action) onPick;
  final ValueChanged<Section> goTo;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  List<_PaletteItem> _items = const [];
  int _selected = 0;
  Timer? _debounce;

  void _pick() {
    if (_items.isEmpty) return;
    widget.onPick(_items[_selected].action);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_search);
    _search();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_search);
    _debounce?.cancel();
    super.dispose();
  }

  void _search() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), _run);
  }

  Future<void> _run() async {
    final q = widget.controller.text.trim();
    final items = <_PaletteItem>[];
    final courses = await Store.i.courses(includeArchived: true);
    for (final c
        in courses
            .where(
              (c) =>
                  q.isEmpty || c.title.toLowerCase().contains(q.toLowerCase()),
            )
            .take(6)) {
      items.add(
        _PaletteItem(
          c.title,
          Icons.ondemand_video_rounded,
          'Video Course',
          () => Nav.course(context, c.id),
        ),
      );
    }
    final notes = await Store.i.notes(query: q);
    for (final n in notes.take(6)) {
      items.add(
        _PaletteItem(
          n.title.isEmpty ? 'Untitled note' : n.title,
          Icons.sticky_note_2_outlined,
          'Note',
          () {
            AppState.i.setActiveWorkspaceContext(
              section: 'Note page',
              noteId: n.id,
            );
            widget.goTo(Section.notes);
          },
        ),
      );
    }
    final resources = (await Store.i.resources())
        .where(
          (r) => q.isEmpty || r.title.toLowerCase().contains(q.toLowerCase()),
        )
        .take(6);
    for (final r in resources) {
      items.add(
        _PaletteItem(
          r.title,
          Icons.description_outlined,
          'Library',
          () => Nav.resource(context, r.id),
        ),
      );
    }
    if (mounted) {
      setState(() {
        _items = items;
        _selected = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 90),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter) {
              _pick();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 620,
              constraints: const BoxConstraints(maxHeight: 460),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(MRadius.lg),
                border: Border.all(color: c.line),
                boxShadow: [
                  BoxShadow(
                    color: c.shadow,
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: TextField(
                      controller: widget.controller,
                      autofocus: true,
                      style: MType.body.copyWith(color: c.ink),
                      decoration: InputDecoration(
                        hintText: 'Search courses, lessons, or notes...',
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: c.inkFaint,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _pick(),
                      onChanged: (_) => _search(),
                    ),
                  ),
                  const MDivider(),
                  Flexible(
                    child: _items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Nothing matches that search.',
                              style: MType.small.copyWith(color: c.inkMuted),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: _items.length,
                            itemBuilder: (context, i) {
                              final item = _items[i];
                              final selected = i == _selected;
                              return InkWell(
                                onTap: () => widget.onPick(item.action),
                                onHover: (_) => setState(() => _selected = i),
                                child: Container(
                                  height: 42,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  color: selected
                                      ? c.surfaceAlt
                                      : Colors.transparent,
                                  child: Row(
                                    children: [
                                      Icon(
                                        item.icon,
                                        size: 16,
                                        color: c.inkMuted,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          item.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: MType.body.copyWith(
                                            fontSize: 13,
                                            color: c.ink,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        item.kind,
                                        style: MType.small.copyWith(
                                          fontSize: 10.5,
                                          color: c.inkFaint,
                                        ),
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
          ),
        ),
      ),
    );
  }
}

class _PaletteItem {
  const _PaletteItem(this.label, this.icon, this.kind, this.action);
  final String label;
  final IconData icon;
  final String kind;
  final VoidCallback action;
}

// ---------------------------------------------------------------------------
// Shared import actions

Future<void> importLibraryFiles(
  BuildContext? context, {
  String? courseId,
}) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.any,
    dialogTitle: courseId == null
        ? 'Add files to your library'
        : 'Add files to this course',
  );
  if (result == null) return;
  var count = 0;
  for (final f in result.files) {
    final path = f.path;
    if (path == null) continue;
    final ext = _ext(path);
    await Store.i.addResource(
      title: f.name,
      path: path,
      kind: kindForFile(ext),
      size: f.size,
      courseId: courseId,
    );
    count++;
  }
  AppState.i.bump();
  if (context != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          courseId == null
              ? 'Added $count ${count == 1 ? 'file' : 'files'} to the library.'
              : 'Added $count ${count == 1 ? 'file' : 'files'} to the course.',
        ),
      ),
    );
  }
}

String _ext(String path) {
  final i = path.lastIndexOf('.');
  return i < 0 ? '' : path.substring(i + 1).toLowerCase();
}

String kindForFile(String ext) {
  if (ext == 'pdf') return 'pdf';
  if (['mp4', 'mkv', 'webm', 'mov', 'avi', 'm4v'].contains(ext)) return 'video';
  if (['mp3', 'wav', 'm4a', 'flac', 'ogg'].contains(ext)) return 'audio';
  if (['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'svg'].contains(ext)) {
    return 'image';
  }
  if (['md', 'txt', 'rtf'].contains(ext)) return 'document';
  if ([
    'dart',
    'rs',
    'py',
    'js',
    'ts',
    'c',
    'cpp',
    'h',
    'java',
    'go',
    'sql',
    'json',
    'yaml',
    'yml',
  ].contains(ext)) {
    return 'code';
  }
  if (['pptx', 'ppt', 'docx', 'doc', 'xlsx', 'xls', 'csv'].contains(ext)) {
    return 'document';
  }
  return 'other';
}

String humanFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
