import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/course_files.dart';
import '../../core/db.dart';
import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../shell.dart';
import '../../services/ai.dart';
import '../../services/rag.dart';

/// Context-aware sidebar for both the course overview and the lesson player.
///
/// Uses Klaro's native card, chip and typography system and exposes:
/// - Outline (when inside a lesson): modules and lessons with manual completion
///   toggles for both individual lessons and entire modules.
/// - Files: course attachments (highlighting files matching the active lesson or
///   module folder) plus an "+ Add file" action that attaches files to the course.
/// - AI Tutor: multi-turn chat aware of the active course, module, lesson,
///   playback timestamp, transcript, notes and course attachments.
class CourseContextSidebar extends StatefulWidget {
  const CourseContextSidebar({
    super.key,
    required this.course,
    required this.modules,
    required this.lessons,
    required this.resources,
    required this.progress,
    required this.onRefresh,
    this.currentLesson,
    this.currentPosition = Duration.zero,
    this.transcript,
    this.lessonNotes = const [],
    this.onPickLesson,
    this.onToggleLessonComplete,
    this.onToggleModuleComplete,
    this.onSeek,
    this.showOutline = false,
    this.onCreateNote,
    this.onOpenNote,
    this.initialTab = 1,
  });

  final Course course;
  final List<Module> modules;
  final List<Lesson> lessons;
  final List<LibraryResource> resources;
  final Map<String, Progress> progress;
  final VoidCallback onRefresh;

  final Lesson? currentLesson;
  final Duration currentPosition;
  final Transcript? transcript;
  final List<Note> lessonNotes;
  final ValueChanged<String>? onPickLesson;
  final void Function(Lesson lesson, bool completed)? onToggleLessonComplete;
  final void Function(String? moduleId, bool completed)? onToggleModuleComplete;
  final ValueChanged<Duration>? onSeek;
  final bool showOutline;
  final VoidCallback? onCreateNote;
  final ValueChanged<Note>? onOpenNote;
  final int initialTab;

  @override
  State<CourseContextSidebar> createState() => _CourseContextSidebarState();
}

class _ChatExchange {
  _ChatExchange({
    required this.question,
    required this.contextLabel,
  });

  final String question;
  final String contextLabel;
  String answer = '';
  List<Citation> citations = const [];
  bool busy = true;
  String? error;
}

class _CourseContextSidebarState extends State<CourseContextSidebar> {
  late int _tab;
  String _fileQuery = '';
  final TextEditingController _askController = TextEditingController();
  final AiClient _ai = AiClient();
  final List<_ChatExchange> _exchanges = [];
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  void dispose() {
    _askController.dispose();
    super.dispose();
  }

  Module? get _currentModule {
    final modId = widget.currentLesson?.moduleId;
    if (modId == null) return null;
    for (final m in widget.modules) {
      if (m.id == modId) return m;
    }
    return null;
  }

  String get _contextBadgeLabel {
    final lesson = widget.currentLesson;
    if (lesson == null) {
      return '${widget.course.title} · ${widget.lessons.length} lessons';
    }
    final mod = _currentModule;
    final prefix = mod != null ? '${mod.title} · ' : '';
    return '$prefix${lesson.title} @ ${formatClock(widget.currentPosition)}';
  }

  Future<void> _sendQuestion([String? preset]) async {
    final q = (preset ?? _askController.text).trim();
    if (q.isEmpty || _asking) return;
    if (preset == null) _askController.clear();

    final entry = _ChatExchange(
      question: q,
      contextLabel: _contextBadgeLabel,
    );
    setState(() {
      _asking = true;
      _exchanges.add(entry);
    });

    final provider = await Store.i.defaultProvider();
    if (provider == null) {
      if (!mounted) return;
      setState(() {
        entry.busy = false;
        entry.error = 'Configure an AI provider in Settings to use the AI Tutor.';
        _asking = false;
      });
      return;
    }

    try {
      final rag = RagService(Store.i, _ai);
      final lessonTitle = widget.currentLesson?.title ?? '';
      final chunks = await rag.retrieve(
        '${widget.course.title} $lessonTitle $q',
        provider: provider,
      );
      final (contextBlock, citations) = RagService.buildContext(chunks);

      final nearby = <String>[];
      final t = widget.transcript;
      if (t != null) {
        final ms = widget.currentPosition.inMilliseconds;
        for (final s in t.segments.where(
          (s) => s.startMs >= ms - 120000 && s.startMs <= ms + 120000,
        )) {
          nearby.add('[${formatClock(Duration(milliseconds: s.startMs))}] ${s.text}');
        }
      }

      final notesBlock = widget.lessonNotes.isEmpty
          ? ''
          : widget.lessonNotes
              .take(6)
              .map((n) => '- ${n.title}: ${n.body}')
              .join('\n');

      final filesBlock = widget.resources.isEmpty
          ? ''
          : widget.resources.take(15).map((r) => '- ${r.title}').join('\n');

      final mod = _currentModule;
      final system = '''
You are klaro.'s context-aware course tutor.
Always ground your answer in the current lesson and course context below. Cite sources with [n] when using retrieved material.
Course: ${widget.course.title}${widget.course.author != null ? ' (by ${widget.course.author})' : ''}
${widget.course.objectives != null && widget.course.objectives!.trim().isNotEmpty ? 'Course objectives:\n${widget.course.objectives}\n' : ''}${mod != null ? 'Current module: ${mod.title}\n' : ''}${widget.currentLesson != null ? 'Current lesson: ${widget.currentLesson!.title}\nCurrent playback timestamp: ${formatClock(widget.currentPosition)}\n' : 'View: Course overview (${widget.modules.length} modules, ${widget.lessons.length} lessons)\n'}${notesBlock.isEmpty ? '' : 'Student notes on this lesson:\n$notesBlock\n'}${nearby.isEmpty ? '' : 'Transcript around current timestamp:\n${nearby.join('\n')}\n'}${filesBlock.isEmpty ? '' : 'Course attachments:\n$filesBlock\n'}${contextBlock.isEmpty ? '' : 'Retrieved material:\n$contextBlock'}
''';

      final turns = <ChatTurn>[
        ChatTurn(role: 'system', content: system),
        for (final prev in _exchanges.take(_exchanges.length - 1))
          if (prev.answer.isNotEmpty) ...[
            ChatTurn(role: 'user', content: prev.question),
            ChatTurn(role: 'assistant', content: prev.answer),
          ],
        ChatTurn(role: 'user', content: q),
      ];

      final buffer = StringBuffer();
      await _ai.streamChat(
        provider: provider,
        messages: turns,
        onDelta: (d) {
          buffer.write(d);
          if (mounted) {
            setState(() => entry.answer = buffer.toString());
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              entry.busy = false;
              entry.citations = citations;
              _asking = false;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              entry.busy = false;
              entry.error = e.toString();
              _asking = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          entry.busy = false;
          entry.error = e.toString();
          _asking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Files first: it is the working surface; notes and the tutor follow.
    final tabs = <(int, String, IconData)>[
      (1, L.of(context).t('files'), Icons.attach_file_rounded),
      (3, L.of(context).t('notes'), Icons.sticky_note_2_outlined),
      (2, L.of(context).t('aiTutor'), Icons.auto_awesome_outlined),
      if (widget.showOutline) (0, L.of(context).t('outline'), Icons.format_list_bulleted_rounded),
    ];
    final effectiveTab = tabs.any((t) => t.$1 == _tab) ? _tab : tabs.first.$1;

    return MCard(
      padding: EdgeInsets.zero,
      radius: MRadius.xl,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: MSegmented(
              index: tabs.indexWhere((t) => t.$1 == effectiveTab),
              onChanged: (i) => setState(() => _tab = tabs[i].$1),
              items: [for (final t in tabs) (t.$2, t.$3)],
            ),
          ),
          Divider(height: 1, color: c.line),
          Expanded(
            child: MFadeIn(
              key: ValueKey(effectiveTab),
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(effectiveTab),
                child: switch (effectiveTab) {
                  0 => _buildOutline(context),
                  1 => _buildFiles(context),
                  3 => _buildNotes(context),
                  _ => _buildTutor(context),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutline(BuildContext context) {
    final c = context.c;
    final modules = [...widget.modules]..sort((a, b) => a.position.compareTo(b.position));
    final known = modules.map((m) => m.id).toSet();
    final groups = <(Module?, List<Lesson>)>[];
    for (final m in modules) {
      final list = widget.lessons.where((l) => l.moduleId == m.id).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      if (list.isNotEmpty) groups.add((m, list));
    }
    final loose = widget.lessons
        .where((l) => l.moduleId == null || !known.contains(l.moduleId))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    if (loose.isNotEmpty) groups.add((null, loose));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        for (final (mod, list) in groups) ...[
          if (mod != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
              child: Row(
                children: [
                  Builder(
                    builder: (context) {
                      final doneCount = list
                          .where((l) => widget.progress[l.id]?.completed == true)
                          .length;
                      final allDone = list.isNotEmpty && doneCount == list.length;
                      return InkWell(
                        onTap: widget.onToggleModuleComplete == null
                            ? null
                            : () => widget.onToggleModuleComplete!(mod.id, !allDone),
                        borderRadius: BorderRadius.circular(6),
                        child: Tooltip(
                          message: allDone
                              ? 'Mark module as incomplete'
                              : 'Mark entire module complete',
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              allDone
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 16,
                              color: allDone ? c.accent : c.inkMuted,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      mod.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MType.label.copyWith(color: c.inkMuted, fontSize: 10.5),
                    ),
                  ),
                  Text(
                    '${list.where((l) => widget.progress[l.id]?.completed == true).length}/${list.length}',
                    style: MType.small.copyWith(color: c.inkFaint, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          for (var i = 0; i < list.length; i++)
            _buildOutlineLessonTile(context, list[i], i + 1),
        ],
      ],
    );
  }

  Widget _buildOutlineLessonTile(BuildContext context, Lesson l, int index) {
    final c = context.c;
    final active = l.id == widget.currentLesson?.id;
    final done = widget.progress[l.id]?.completed == true;
    return InkWell(
      onTap: widget.onPickLesson == null ? null : () => widget.onPickLesson!(l.id),
      borderRadius: BorderRadius.circular(MSpace.x2),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: active ? c.surfaceSunken : Colors.transparent,
          borderRadius: BorderRadius.circular(MSpace.x2),
          border: Border.all(color: active ? c.lineStrong : Colors.transparent),
        ),
        child: Row(
          children: [
            InkWell(
              onTap: widget.onToggleLessonComplete == null
                  ? null
                  : () => widget.onToggleLessonComplete!(l, !done),
              borderRadius: BorderRadius.circular(6),
              child: Tooltip(
                message: done ? 'Mark as incomplete' : 'Mark as completed',
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 17,
                    color: done ? c.accent : (active ? c.ink : c.inkFaint),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MType.small.copyWith(
                  fontSize: 12,
                  color: active ? c.ink : c.inkMuted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

static const _coverNames = {
    'img',
    'logo',
    'cover',
    'poster',
    'thumbnail',
    'thumb',
    'banner',
    'folder',
  };

  bool _isCoverAsset(String path) {
    final base = p.basenameWithoutExtension(path).toLowerCase();
    return _coverNames.contains(base);
  }

  int? _leadingNumber(String label) {
    final m = RegExp(r'^\s*(\d+)').firstMatch(label);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// A file belongs to a lesson when its leading number matches the lesson's
  /// number, optionally followed by a letter ("1a", "1b", "1c"), and it sits in
  /// the same folder. Cover art and unrelated numbers are ignored.
  bool _matchesLesson(Lesson lesson, LibraryResource r) {
    if (_isCoverAsset(r.path)) return false;
    final lessonNumber = _leadingNumber(lesson.title);
    if (lessonNumber == null) return false;
    final fileNumber = _leadingNumber(p.basename(r.path));
    if (fileNumber == null || fileNumber != lessonNumber) return false;
    final lessonPath = lesson.path;
    if (lessonPath != null && lessonPath.isNotEmpty) {
      final lessonDir = p.dirname(lessonPath).toLowerCase();
      final fileDir = p.dirname(r.path).toLowerCase();
      if (lessonDir != fileDir) return false;
    }
    return true;
  }

  Future<void> _removeAttachment(BuildContext context, LibraryResource r) async {
    await Store.i.deleteResource(r.id);
    AppState.i.bump();
    widget.onRefresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Attachment unlinked from the course. The file stays where it is.'),
      ),
    );
  }

  Widget _buildFiles(BuildContext context) {
    final c = context.c;
    final q = _fileQuery.trim().toLowerCase();
    final lesson = widget.currentLesson;
    final all = widget.resources.where((r) => !_isCoverAsset(r.path)).toList();
    final scoped = lesson == null
        ? all
        : all.where((r) => _matchesLesson(lesson, r)).toList();
    final visible = scoped
        .where((r) =>
            q.isEmpty ||
            r.title.toLowerCase().contains(q) ||
            r.path.toLowerCase().contains(q))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: MType.small.copyWith(color: c.ink, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'Filter attachments',
                    prefixIcon: Icon(Icons.search_rounded, size: 15),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _fileQuery = v),
                ),
              ),
              const SizedBox(width: 6),
              MIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Attach files to this course',
                size: 34,
                onPressed: () async {
                  await importLibraryFiles(context, courseId: widget.course.id);
                  widget.onRefresh();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_copy_outlined, size: 26, color: c.inkFaint),
                        const SizedBox(height: 8),
                        Text(
                          widget.resources.isEmpty
                              ? 'No attachments in this course yet'
                              : scoped.isEmpty
                                  ? 'No file for this lesson yet'
                                  : 'No attachment matches that filter',
                          textAlign: TextAlign.center,
                          style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 12.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          scoped.isEmpty && widget.resources.isNotEmpty
                              ? 'Files named like this lesson (for example “3. Title.pdf” or “3a. …”) appear here.'
                              : 'PDFs, slides, worksheets or notes for this course.',
                          textAlign: TextAlign.center,
                          style: MType.small.copyWith(color: c.inkMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _buildFileTile(context, visible[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildFileTile(BuildContext context, LibraryResource r) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => Nav.resource(context, r.id),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c.surfaceSunken,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_fileIcon(r.kind), size: 14, color: c.inkMuted),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MType.small.copyWith(
                          color: c.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${r.kind.toUpperCase()} · ${humanFileSize(r.size)}',
                        style: MType.small.copyWith(color: c.inkFaint, fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'File options',
                  color: c.surface,
                  onSelected: (v) {
                    switch (v) {
                      case 'open':
                        Nav.resource(context, r.id);
                      case 'folder':
                        revealFileInExplorer(r.path);
                      case 'remove':
                        _removeAttachment(context, r);
                    }
                  },
                  itemBuilder: (_) => [
                    _fileMenuItem('open', Icons.open_in_new_rounded, 'Open'),
                    _fileMenuItem('folder', Icons.folder_open_outlined, 'Open file location'),
                    _fileMenuItem('remove', Icons.link_off_rounded, 'Unlink from course',
                        danger: true),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.more_horiz_rounded, size: 16, color: c.inkMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _fileMenuItem(String value, IconData icon, String label,
      {bool danger = false}) {
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

Widget _buildNotes(BuildContext context) {
    final c = context.c;
    final lesson = widget.currentLesson;
    if (lesson == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Open a lesson to take notes tied to its timestamp.',
            textAlign: TextAlign.center,
            style: MType.small.copyWith(color: c.inkMuted, height: 1.5),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Notes for this lesson',
                  style: MType.small.copyWith(
                    color: c.inkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              MButton(
                label: 'New note',
                icon: Icons.add_rounded,
                dense: true,
                onPressed: widget.onCreateNote,
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.lessonNotes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sticky_note_2_outlined, size: 26, color: c.inkFaint),
                        const SizedBox(height: 8),
                        Text(
                          'No notes in this lesson yet',
                          style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 12.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Notes stay linked to "${lesson.title}" and appear in the Notes section.',
                          textAlign: TextAlign.center,
                          style: MType.small.copyWith(color: c.inkMuted, fontSize: 11, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                  itemCount: widget.lessonNotes.length,
                  itemBuilder: (context, i) {
                    final note = widget.lessonNotes[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: widget.onOpenNote == null
                              ? null
                              : () => widget.onOpenNote!(note),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: c.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (note.timestampMs != null) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: c.ink,
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          formatClock(Duration(milliseconds: note.timestampMs!)),
                                          style: MType.small.copyWith(
                                            color: c.surface,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Expanded(
                                      child: Text(
                                        note.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: MType.small.copyWith(
                                          color: c.ink,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      relativeDate(note.updatedAt),
                                      style: MType.small.copyWith(
                                          color: c.inkFaint, fontSize: 9.5),
                                    ),
                                  ],
                                ),
                                if (note.body.trim().isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    note.body,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: MType.small.copyWith(
                                      color: c.inkMuted,
                                      fontSize: 11,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
  Widget _buildTutor(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(MRadius.md),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Icon(Icons.podcasts_rounded, size: 14, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _contextBadgeLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MType.small.copyWith(
                    color: c.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MChip(
                label: widget.currentLesson != null ? 'Summarize lesson' : 'Course overview',
                onTap: () => _sendQuestion(
                  widget.currentLesson != null
                      ? 'Summarize the key concepts of this lesson.'
                      : 'Give me a structured overview of this course and how to study it.',
                ),
              ),
              MChip(
                label: 'Key takeaways',
                onTap: () => _sendQuestion('What are the main takeaways and action steps here?'),
              ),
              MChip(
                label: 'Quiz me',
                onTap: () => _sendQuestion('Ask me 3 short active-recall questions on this material.'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _exchanges.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      widget.currentLesson != null
                          ? 'Ask anything about "${widget.currentLesson!.title}". The tutor knows which lesson and timestamp you are on.'
                          : 'Ask anything about "${widget.course.title}", its modules or its attached files.',
                      textAlign: TextAlign.center,
                      style: MType.small.copyWith(color: c.inkMuted, height: 1.5),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  itemCount: _exchanges.length,
                  itemBuilder: (context, i) {
                    final ex = _exchanges[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                              decoration: BoxDecoration(
                                color: c.ink,
                                borderRadius: BorderRadius.circular(MRadius.md),
                              ),
                              child: Text(
                                ex.question,
                                style: MType.small.copyWith(color: c.surface, fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: BorderRadius.circular(MRadius.md),
                              border: Border.all(color: c.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (ex.error != null)
                                  Text(
                                    ex.error!,
                                    style: MType.small.copyWith(color: c.danger, fontSize: 11.5),
                                  )
                                else
                                  Text(
                                    ex.answer.isEmpty && ex.busy ? 'Thinking...' : ex.answer,
                                    style: MType.body.copyWith(
                                      color: c.ink,
                                      fontSize: 12.5,
                                      height: 1.5,
                                    ),
                                  ),
                                if (ex.citations.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (var k = 0; k < ex.citations.length; k++)
                                        MChip(
                                          label: '${k + 1}. ${ex.citations[k].label}',
                                          tone: MChipTone.accent,
                                          onTap: () {
                                            final loc = ex.citations[k].locator;
                                            if (loc == null || widget.onSeek == null) return;
                                            final parts = loc.split(':');
                                            if (parts.length == 2) {
                                              final m = int.tryParse(parts[0]) ?? 0;
                                              final s = int.tryParse(parts[1]) ?? 0;
                                              widget.onSeek!(Duration(minutes: m, seconds: s));
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _askController,
                  style: MType.small.copyWith(color: c.ink, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: widget.currentLesson != null
                        ? 'Ask about this lesson...'
                        : 'Ask about this course...',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendQuestion(),
                ),
              ),
              const SizedBox(width: 6),
              MButton(
                label: _asking ? '...' : 'Ask',
                kind: MButtonKind.primary,
                dense: true,
                onPressed: _asking ? null : _sendQuestion,
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _fileIcon(String kind) => switch (kind) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'video' => Icons.movie_outlined,
        'audio' => Icons.graphic_eq_rounded,
        'image' => Icons.image_outlined,
        'code' => Icons.code_rounded,
        _ => Icons.description_outlined,
      };
}

