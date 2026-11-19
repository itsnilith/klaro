import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/db.dart';
import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../core/paths.dart';
import '../../core/state.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/ai.dart';
import '../../services/rag.dart';
import '../../services/transcription.dart';
import '../shell.dart';
import '../shell_dialogs.dart';
import '../tags/tag_bar.dart';
import 'course_sidebar.dart';
import 'quiz_view.dart';

const _uuid = Uuid();

class LessonPage extends StatefulWidget {
  const LessonPage({super.key, required this.courseId, required this.lessonId});
  final String courseId;
  final String lessonId;

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  late final Player _player;
  late final VideoController _controller;
  var _playerInitialized = false;
  Course? _course;
  Lesson? _lesson;
  List<Module> _modules = const [];
  List<Lesson> _lessons = const [];
  List<Note> _notes = const [];
  List<LibraryResource> _resources = const [];
  Map<String, Progress> _progressMap = const {};
  Transcript? _transcript;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _volume = 1;
  bool _completed = false;
  int _tab = 0;
  bool _compact = false;
  bool _subtitleOn = false;
  StreamSubscription? _sub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _completedSub;
  final FocusNode _focus = FocusNode();
  Timer? _saveTimer;
  bool _ready = false;
  bool _sidebarOpen = true;
  String? _error;
  // Fullscreen playback: the lesson body goes black and the player is shown on
  // a root overlay, so it covers the whole window, shell chrome included.
  bool _fullscreen = false;
  OverlayEntry? _fsEntry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _initializePlayer() {
    if (_playerInitialized) return;
    MediaKit.ensureInitialized();
    _player = Player();
    _controller = VideoController(_player);
    _playerInitialized = true;
  }

  Future<void> _load() async {
    final lesson = await Store.i.lesson(widget.lessonId);
    if (lesson == null) {
      setState(() => _error = 'This lesson no longer exists.');
      return;
    }
    final course = await Store.i.course(widget.courseId);
    final modules = await Store.i.modules(widget.courseId);
    final lessons = await Store.i.lessons(widget.courseId);
    final notes = await Store.i.notes(lessonId: widget.lessonId);
    final resources = await Store.i.resources(courseId: widget.courseId);
    final transcript = await Store.i.transcriptFor('lesson', lesson.id);
    final progressMap = await Store.i.courseProgressMap(widget.courseId);
    final progress = progressMap[lesson.id];
    if (!mounted) return;
    setState(() {
      _lesson = lesson;
      _course = course;
      _modules = modules;
      _lessons = lessons;
      _notes = notes;
      _resources = resources;
      _transcript = transcript;
      _progressMap = progressMap;
      _completed = progress?.completed ?? false;
      _ready = true;
    });
    // Text lessons and quizzes are complete without a file on disk. Only media
    // kinds enter the player; treating them as videos made their entries fail.
    if (lesson.kind != 'video' && lesson.kind != 'audio') return;
    final path = lesson.path;
    if (path == null || !File(path).existsSync()) {
      setState(
        () => _error = 'The media file is missing at its original location.',
      );
      return;
    }
    try {
      _initializePlayer();
      await _player.open(Media(path));
      await _player.setVolume(_volume * 100);
      await _player.setRate(AppState.i.playbackSpeed);
      if (progress != null &&
          AppState.i.resumePlayback &&
          progress.positionMs > 3000) {
        await _player.seek(Duration(milliseconds: progress.positionMs));
      }
      _sub = _player.stream.position.listen((pos) {
        if (!mounted) return;
        setState(() => _position = pos);
        _saveTimer ??= Timer(const Duration(seconds: 5), () {
          _saveTimer = null;
          _persist(pos);
        });
      });
      _durSub = _player.stream.duration.listen((d) async {
        if (!mounted) return;
        setState(() => _duration = d);
        if (d.inMilliseconds > 0 &&
            (lesson.durationMs == 0 ||
                (lesson.durationMs - d.inMilliseconds).abs() > 1000)) {
          await Store.i.setLessonDuration(lesson.id, d.inMilliseconds);
        }
      });
      _playSub = _player.stream.playing.listen((v) {
        if (!mounted) return;
        setState(() => _playing = v);
      });
      _completedSub = _player.stream.completed.listen((done) async {
        if (done) {
          await Store.i.saveProgress(
            lesson.id,
            _duration.inMilliseconds,
            _duration.inMilliseconds,
            true,
          );
          AppState.i.bump();
          await _refreshSidebar();
          if (mounted) setState(() => _completed = true);
          if (AppState.i.autoplayNext) _playNext();
        }
      });
      await _player.play();
      await _attachSubtitles(transcript);
    } catch (e) {
      setState(() => _error = 'Playback could not start: $e');
    }
  }

  bool posShouldComplete(Duration duration, Duration position) =>
      duration.inMilliseconds > 0 &&
      position.inMilliseconds >= duration.inMilliseconds * 0.92;

  Future<void> _attachSubtitles(Transcript? t) async {
    if (t == null || t.segments.isEmpty) return;
    try {
      final dir = Directory(p.join(AppPaths.i.cacheDir, 'subtitles'));
      await dir.create(recursive: true);
      final f = File(p.join(dir.path, '${widget.lessonId}.vtt'));
      await f.writeAsString(TranscriptionService.toVtt(t.segments));
      if (AppState.i.subtitlesEnabled) {
        await _player.setSubtitleTrack(SubtitleTrack.uri(f.path));
        if (mounted) setState(() => _subtitleOn = true);
      } else {
        await _player.setSubtitleTrack(SubtitleTrack.no());
        if (mounted) setState(() => _subtitleOn = false);
      }
    } catch (_) {}
  }

  Future<void> _persist(Duration pos) async {
    final lesson = _lesson;
    if (lesson == null || (lesson.kind != 'video' && lesson.kind != 'audio')) {
      return;
    }
    final completed = _completed || posShouldComplete(_duration, pos);
    await Store.i.saveProgress(
      lesson.id,
      pos.inMilliseconds,
      pos.inMilliseconds,
      completed,
    );
    if (completed && !_completed && mounted) {
      setState(() => _completed = true);
      AppState.i.bump();
      await _refreshSidebar();
    }
  }

  Lesson? get _previousLesson {
    final index = _lessons.indexWhere((l) => l.id == widget.lessonId);
    if (index <= 0) return null;
    return _lessons[index - 1];
  }

  Lesson? get _nextLesson {
    final index = _lessons.indexWhere((l) => l.id == widget.lessonId);
    if (index < 0 || index + 1 >= _lessons.length) return null;
    return _lessons[index + 1];
  }

  void _openLesson(String id) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LessonPage(courseId: widget.courseId, lessonId: id),
      ),
    );
  }

  Future<void> _refreshNotes() async {
    final notes = await Store.i.notes(lessonId: widget.lessonId);
    if (!mounted) return;
    setState(() => _notes = notes);
  }

  Future<void> _refreshSidebar() async {
    final resources = await Store.i.resources(courseId: widget.courseId);
    final progressMap = await Store.i.courseProgressMap(widget.courseId);
    if (!mounted) return;
    setState(() {
      _resources = resources;
      _progressMap = progressMap;
      if (_lesson != null) {
        _completed = progressMap[_lesson!.id]?.completed ?? _completed;
      }
    });
  }

  void _playNext() {
    final idx = _lessons.indexWhere((l) => l.id == widget.lessonId);
    if (idx >= 0 && idx + 1 < _lessons.length) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LessonPage(
            courseId: widget.courseId,
            lessonId: _lessons[idx + 1].id,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_fullscreen) {
      _fsEntry?.remove();
      _fsEntry = null;
      unawaited(_leaveWindowFullscreen());
    }
    _sub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _completedSub?.cancel();
    _focus.dispose();
    _persist(_position);
    if (_playerInitialized) _player.dispose();
    super.dispose();
  }

  Future<void> _leaveWindowFullscreen() async {
    try {
      await windowManager.setFullScreen(false);
    } catch (_) {}
  }

  void _seek(Duration d) {
    _player.seek(d);
    setState(() => _position = d);
  }

  // ---------------------------------------------------------------- fullscreen

  Future<void> _enterFullscreen() async {
    if (_fullscreen || !_playerInitialized) return;
    final lesson = _lesson;
    if (lesson == null) return;
    setState(() => _fullscreen = true);
    _fsEntry = OverlayEntry(
      builder: (_) => _FullscreenPlayer(
        player: _player,
        controller: _controller,
        title: lesson.title,
        courseTitle: _course?.title ?? '',
        isAudio: lesson.kind == 'audio',
        skipSeconds: AppState.i.skipSeconds,
        volume: _volume,
        subtitleOn: _subtitleOn,
        onExit: _exitFullscreen,
        onVolume: (v) => setState(() => _volume = v),
        onSpeed: _setPlaybackSpeed,
        onSubtitles: (on) async {
          setState(() => _subtitleOn = on);
          await _applySubtitleState(on);
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_fsEntry!);
    try {
      await windowManager.setFullScreen(true);
    } catch (_) {}
  }

  Future<void> _exitFullscreen() async {
    if (!_fullscreen) return;
    _fsEntry?.remove();
    _fsEntry = null;
    if (mounted) setState(() => _fullscreen = false);
    try {
      await windowManager.setFullScreen(false);
    } catch (_) {}
    if (mounted) _focus.requestFocus();
  }

  Future<void> _toggleSubtitles() async {
    final on = !_subtitleOn;
    setState(() => _subtitleOn = on);
    await _applySubtitleState(on);
  }

  Future<void> _applySubtitleState(bool on) async {
    final t = _transcript;
    if (on && t != null && t.segments.isNotEmpty) {
      try {
        final dir = Directory(p.join(AppPaths.i.cacheDir, 'subtitles'));
        await dir.create(recursive: true);
        final f = File(p.join(dir.path, '${widget.lessonId}.vtt'));
        await f.writeAsString(TranscriptionService.toVtt(t.segments));
        await _player.setSubtitleTrack(SubtitleTrack.uri(f.path));
      } catch (_) {}
    } else {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    }
  }

  Future<void> _setPlaybackSpeed(double v) async {
    await _player.setRate(v);
    await AppState.i.setDouble('playback_speed', v);
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape && _fullscreen) {
      _exitFullscreen();
      return KeyEventResult.handled;
    }
    final focused = FocusManager.instance.primaryFocus;
    if (focused?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }
    final lesson = _lesson;
    final isMedia = lesson?.kind == 'video' || lesson?.kind == 'audio';
    if (!isMedia) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      _player.playOrPause();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _seek(_position + Duration(seconds: AppState.i.skipSeconds));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _seek(_position - Duration(seconds: AppState.i.skipSeconds));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF && !_fullscreen) {
      _enterFullscreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lesson = _lesson;
    if (_error != null) {
      return Scaffold(
        backgroundColor: c.canvas,
        body: Center(
          child: MEmpty(
            icon: Icons.error_outline_rounded,
            title: 'Cannot open this lesson',
            message: _error!,
            action: MButton(
              label: 'Back to course',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      );
    }
    if (!_ready || lesson == null) {
      return Scaffold(
        backgroundColor: c.canvas,
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final isMedia = lesson.kind == 'video' || lesson.kind == 'audio';
    return Scaffold(
      backgroundColor: _fullscreen ? Colors.black : c.canvas,
      body: _fullscreen && isMedia
          ? const ColoredBox(color: Colors.black)
          : Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: _onKey,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: MSmoothScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 16, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              MButton(
                                label: _course?.title ?? 'Course',
                                icon: Icons.arrow_back_rounded,
                                kind: MButtonKind.ghost,
                                dense: true,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              const Spacer(),
                              MButton(
                                label: _completed
                                    ? L.of(context).t('completed')
                                    : L.of(context).t('markComplete'),
                                icon: _completed
                                    ? Icons.check_rounded
                                    : Icons.check_circle_outline,
                                dense: true,
                                kind: _completed
                                    ? MButtonKind.secondary
                                    : MButtonKind.ghost,
                                onPressed: () async {
                                  final done = !_completed;
                                  await Store.i.saveProgress(
                                    lesson.id,
                                    _position.inMilliseconds,
                                    _position.inMilliseconds,
                                    done,
                                  );
                                  setState(() => _completed = done);
                                  AppState.i.bump();
                                  await _refreshSidebar();
                                },
                              ),
                              const SizedBox(width: 4),
                              MIconButton(
                                icon: Icons.skip_previous_rounded,
                                tooltip: L.of(context).t('previousLesson'),
                                onPressed: _previousLesson == null
                                    ? null
                                    : () => _openLesson(_previousLesson!.id),
                              ),
                              MIconButton(
                                icon: Icons.skip_next_rounded,
                                tooltip: L.of(context).t('nextLesson'),
                                onPressed: _nextLesson == null
                                    ? null
                                    : () => _openLesson(_nextLesson!.id),
                              ),
                              if (isMedia) ...[
                                const SizedBox(width: 4),
                                MIconButton(
                                  icon: _compact
                                      ? Icons.open_in_full_rounded
                                      : Icons.picture_in_picture_alt_outlined,
                                  tooltip: _compact
                                      ? 'Exit floating player'
                                      : 'Float the video while you take notes',
                                  onPressed: () =>
                                      setState(() => _compact = !_compact),
                                ),
                              ],
                              const SizedBox(width: 4),
                              MIconButton(
                                icon: _sidebarOpen
                                    ? Icons.view_sidebar_rounded
                                    : Icons.view_sidebar_outlined,
                                tooltip: _sidebarOpen
                                    ? 'Hide the study panel'
                                    : 'Show the study panel',
                                onPressed: () => setState(
                                  () => _sidebarOpen = !_sidebarOpen,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _compact && isMedia
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 420,
                                      child: _playerSurface(
                                        context,
                                        floating: true,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _lessonHeader(
                                            context,
                                            lesson,
                                            compact: true,
                                          ),
                                          const SizedBox(height: 14),
                                          _tabs(context),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isMedia)
                                      _playerSurface(context)
                                    else
                                      _contentSurface(context, lesson),
                                    const SizedBox(height: 16),
                                    _lessonHeader(context, lesson),
                                    const SizedBox(height: 18),
                                    _tabs(context),
                                  ],
                                ),
                        ],
                      ),
                    ),
                  ),
                  if (isMedia &&
                      !_compact &&
                      _course != null &&
                      MediaQuery.sizeOf(context).width > 900)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: _sidebarOpen ? 380 : 56,
                      padding: const EdgeInsets.fromLTRB(0, 12, 20, 20),
                      child: _sidebarOpen
                          ? CourseContextSidebar(
                              course: _course!,
                              modules: _modules,
                              lessons: _lessons,
                              resources: _resources,
                              progress: _progressMap,
                              currentLesson: lesson,
                              currentPosition: _position,
                              transcript: _transcript,
                              lessonNotes: _notes,
                              showOutline: true,
                              onRefresh: _refreshSidebar,
                              onSeek: _seek,
                              onPickLesson: (id) => _openLesson(id),
                              onCreateNote: _createLessonNote,
                              onOpenNote: _openLessonNote,
                              onToggleLessonComplete: (target, done) async {
                                await Store.i.toggleLessonCompleted(
                                  target.id,
                                  done,
                                );
                                AppState.i.bump();
                                await _refreshSidebar();
                              },
                              onToggleModuleComplete: (modId, done) async {
                                await Store.i.setModuleCompleted(
                                  widget.courseId,
                                  modId,
                                  done,
                                );
                                AppState.i.bump();
                                await _refreshSidebar();
                              },
                            )
                          : _CollapsedPanel(
                              onExpand: () =>
                                  setState(() => _sidebarOpen = true),
                            ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _createLessonNote() async {
    final lesson = _lesson;
    if (lesson == null) return;
    await showNoteEditor(
      context,
      courseId: widget.courseId,
      lessonId: lesson.id,
      timestampMs: _position.inMilliseconds,
      initialBody: 'At ${formatClock(_position)} - ',
    );
    await _refreshNotes();
  }

  Future<void> _openLessonNote(Note note) async {
    await showNoteEditor(context, note: note);
    await _refreshNotes();
  }

  Widget _lessonHeader(
    BuildContext context,
    Lesson lesson, {
    bool compact = false,
  }) {
    final c = context.c;
    final description = lesson.description?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.title,
                    style: compact
                        ? MType.h2.copyWith(color: c.ink, fontSize: 19)
                        : MType.h1.copyWith(color: c.ink, fontSize: 26),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _course?.title ?? '',
                    style: MType.small.copyWith(
                      color: c.inkMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            MIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit title and description',
              size: 30,
              onPressed: () => _editLessonInfo(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TagBar(entityType: 'lesson', entityId: lesson.id, compact: true),
        if (lesson.kind != 'text' &&
            lesson.kind != 'quiz' &&
            description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            description,
            style: MType.body.copyWith(
              color: c.inkMuted,
              height: 1.55,
              fontSize: 13,
            ),
          ),
        ] else if (lesson.kind != 'text' && lesson.kind != 'quiz') ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _editLessonInfo(context),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Add a description for this lesson',
                style: MType.small.copyWith(
                  color: c.inkFaint,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _editLessonInfo(BuildContext context) async {
    final lesson = _lesson;
    if (lesson == null) return;
    final titleCtrl = TextEditingController(text: lesson.title);
    final descCtrl = TextEditingController(text: lesson.description ?? '');
    final saved = await showMSheet<bool>(
      context,
      maxWidth: 520,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              L.of(context).t('lessonDetails'),
              style: MType.h2.copyWith(color: context.c.ink),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(labelText: L.of(context).t('title')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: lesson.kind == 'text'
                    ? 'Lesson text'
                    : L.of(context).t('description'),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 8),
                MButton(
                  label: 'Save',
                  kind: MButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final newTitle = titleCtrl.text.trim();
    final newDesc = descCtrl.text.trim();
    if (newTitle.isNotEmpty && newTitle != lesson.title) {
      await Store.i.renameLesson(lesson.id, newTitle);
    }
    await Store.i.setLessonDescription(
      lesson.id,
      newDesc.isEmpty ? null : newDesc,
    );
    AppState.i.bump();
    await _load();
    if (mounted) {
      setState(() {
        _lesson = _lesson?.copyWith(
          title: newTitle.isEmpty ? lesson.title : newTitle,
          description: newDesc.isEmpty ? null : newDesc,
          clearDescription: newDesc.isEmpty,
        );
      });
    }
  }

  Widget _contentSurface(BuildContext context, Lesson lesson) {
    if (lesson.kind == 'quiz') {
      return QuizView(key: ValueKey(lesson.id), lesson: lesson);
    }
    final c = context.c;
    final text = lesson.description?.trim() ?? '';
    return MCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lesson text',
                  style: MType.label.copyWith(color: c.inkFaint),
                ),
              ),
              MButton(
                label: 'Edit text',
                icon: Icons.edit_outlined,
                dense: true,
                onPressed: () => _editLessonInfo(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const MDivider(),
          const SizedBox(height: 16),
          if (text.isEmpty)
            Text(
              'No lesson text yet. Choose Edit text to start writing.',
              style: MType.body.copyWith(
                color: c.inkMuted,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            SelectionArea(
              child: Text(
                text,
                style: MType.body.copyWith(
                  color: c.ink,
                  height: 1.65,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _playerSurface(BuildContext context, {bool floating = false}) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(MRadius.lg),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _player.playOrPause(),
                  onDoubleTap: _enterFullscreen,
                  child: Video(
                    controller: _controller,
                    controls: NoVideoControls,
                    fill: Colors.black,
                  ),
                ),
                if (!_playing)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => _player.playOrPause(),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.18),
                        child: Center(
                          child: Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 34,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            color: c.surface,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              children: [
                _Timeline(
                  position: _position,
                  duration: _duration,
                  onSeek: _seek,
                  channels: _transcript?.segments.length ?? 0,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    MIconButton(
                      icon: _playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onPressed: () => _player.playOrPause(),
                      size: 32,
                    ),
                    MIconButton(
                      icon: Icons.replay_10_rounded,
                      onPressed: () => _seek(
                        _position - Duration(seconds: AppState.i.skipSeconds),
                      ),
                      size: 30,
                    ),
                    MIconButton(
                      icon: Icons.forward_10_rounded,
                      onPressed: () => _seek(
                        _position + Duration(seconds: AppState.i.skipSeconds),
                      ),
                      size: 30,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${formatClock(_position)} / ${formatClock(_duration)}',
                      style: MType.small.copyWith(
                        color: c.inkMuted,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    MIconButton(
                      icon: _subtitleOn
                          ? Icons.subtitles_rounded
                          : Icons.subtitles_off_outlined,
                      tooltip: 'Subtitles',
                      selected: _subtitleOn,
                      onPressed: _toggleSubtitles,
                    ),
                    Icon(Icons.speed_rounded, size: 15, color: c.inkMuted),
                    SizedBox(
                      width: 104,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          activeTrackColor: c.ink,
                          inactiveTrackColor: c.surfaceSunken,
                          thumbColor: c.ink,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 11,
                          ),
                          tickMarkShape: const RoundSliderTickMarkShape(
                            tickMarkRadius: 1.5,
                          ),
                          activeTickMarkColor: c.surface,
                          inactiveTickMarkColor: c.inkFaint,
                        ),
                        child: Slider(
                          value: AppState.i.playbackSpeed.clamp(0.5, 2.0),
                          min: 0.5,
                          max: 2.0,
                          divisions: 6,
                          onChanged: _setPlaybackSpeed,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 38,
                      child: Text(
                        '${AppState.i.playbackSpeed}x',
                        textAlign: TextAlign.center,
                        style: MType.small.copyWith(
                          color: c.inkMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: _volume,
                          onChanged: (v) {
                            setState(() => _volume = v);
                            _player.setVolume(v * 100);
                          },
                        ),
                      ),
                    ),
                    MIconButton(
                      icon: Icons.fullscreen_rounded,
                      tooltip: 'Fullscreen (F)',
                      size: 32,
                      onPressed: _enterFullscreen,
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

  Widget _tabs(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LessonTab(
              label: 'Notes',
              selected: _tab == 0,
              onTap: () => setState(() => _tab = 0),
            ),
            if (_lesson?.kind == 'video' || _lesson?.kind == 'audio')
              _LessonTab(
                label: 'Transcript',
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
            _LessonTab(
              label: 'Ask',
              selected: _tab == 2,
              onTap: () => setState(() => _tab = 2),
            ),
            _LessonTab(
              label: 'Files',
              selected: _tab == 3,
              onTap: () => setState(() => _tab = 3),
            ),
            const Spacer(),
            if (_tab == 0)
              MButton(
                label: 'Capture note',
                icon: Icons.add_rounded,
                dense: true,
                onPressed: _captureNote,
              ),
          ],
        ),
        const SizedBox(height: 12),
        MFadeIn(
          key: ValueKey(_tab),
          duration: const Duration(milliseconds: 180),
          offset: 4,
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: _tab == 0
                ? _notesTab(context)
                : _tab == 1
                ? _transcriptTab(context)
                : _tab == 2
                ? _askTab(context)
                : _filesTab(context),
          ),
        ),
      ],
    );
  }

  Future<void> _captureNote() async {
    final lesson = _lesson!;
    await showNoteEditor(
      context,
      courseId: widget.courseId,
      lessonId: lesson.id,
      timestampMs: _position.inMilliseconds,
      initialBody: 'At ${formatClock(_position)} â€” ',
    );
    final notes = await Store.i.notes(lessonId: lesson.id);
    if (mounted) setState(() => _notes = notes);
  }

  Widget _notesTab(BuildContext context) {
    final c = context.c;
    if (_notes.isEmpty) {
      return MEmpty(
        icon: Icons.sticky_note_2_outlined,
        title: 'No notes in this lesson',
        message: 'Notes you write here keep the course, the lesson and the exact timestamp.',
        compact: true,
        action: MButton(
          label: 'Write a note at ${formatClock(_position)}',
          kind: MButtonKind.primary,
          dense: true,
          onPressed: _captureNote,
        ),
      );
    }
    return Column(
      children: [
        for (final n in _notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (n.timestampMs != null)
                        MChip(
                          label: formatClock(
                            Duration(milliseconds: n.timestampMs!),
                          ),
                          icon: Icons.play_arrow_rounded,
                          onTap: () =>
                              _seek(Duration(milliseconds: n.timestampMs!)),
                          tone: MChipTone.accent,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          n.title,
                          style: MType.bodyStrong.copyWith(
                            color: c.ink,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      MIconButton(
                        icon: Icons.edit_outlined,
                        size: 28,
                        onPressed: () async {
                          await showNoteEditor(context, note: n);
                          final notes = await Store.i.notes(
                            lessonId: widget.lessonId,
                          );
                          if (mounted) setState(() => _notes = notes);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    n.body,
                    style: MType.body.copyWith(
                      color: c.inkMuted,
                      height: 1.55,
                      fontSize: 13,
                    ),
                  ),
                  if (n.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    MButton(
                      label: 'Make a card from this',
                      icon: Icons.style_outlined,
                      dense: true,
                      onPressed: () => _cardFromNote(n),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _cardFromNote(Note n) async {
    final front = TextEditingController(text: n.title);
    final back = TextEditingController(text: n.body);
    final ok = await showMSheet<bool>(
      context,
      maxWidth: 480,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New flashcard',
              style: MType.h2.copyWith(color: context.c.ink),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: front,
              decoration: const InputDecoration(hintText: 'Question'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: back,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'Answer'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 8),
                MButton(
                  label: 'Add card',
                  kind: MButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await Store.i.saveCard(
      Flashcard(
        id: _uuid.v4(),
        deck: _course?.title ?? 'General',
        front: front.text.trim(),
        back: back.text.trim(),
        courseId: widget.courseId,
        lessonId: widget.lessonId,
        dueAt: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );
    AppState.i.bump();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card added to your review queue.')),
      );
    }
  }

  Widget _transcriptTab(BuildContext context) {
    final c = context.c;
    final t = _transcript;
    if (t == null || t.segments.isEmpty) {
      return MEmpty(
        icon: Icons.graphic_eq_rounded,
        title: 'No transcript yet',
        message:
            'Transcribe this lesson with a local whisper.cpp install or any OpenAI-compatible endpoint. '
            'Configure the backend in Settings, then start here.',
        compact: true,
        action: MButton(
          label: 'Transcribe this lesson',
          kind: MButtonKind.primary,
          dense: true,
          onPressed: _transcribe,
        ),
      );
    }
    final current = _transcriptIndex(t);
    return MCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        height: 300,
        child: ListView.builder(
          itemCount: t.segments.length,
          itemBuilder: (context, i) {
            final s = t.segments[i];
            final active = i == current;
            return InkWell(
              onTap: () => _seek(Duration(milliseconds: s.startMs)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: active ? c.accentSoft : Colors.transparent,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        formatClock(Duration(milliseconds: s.startMs)),
                        style: MType.small.copyWith(
                          color: active ? c.accent : c.inkFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.text,
                        style: MType.small.copyWith(
                          color: active ? c.ink : c.inkMuted,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  int _transcriptIndex(Transcript t) {
    final ms = _position.inMilliseconds;
    for (var i = 0; i < t.segments.length; i++) {
      if (ms >= t.segments[i].startMs && ms < t.segments[i].endMs) return i;
    }
    return -1;
  }

  Future<void> _transcribe() async {
    final s = AppState.i;
    final lesson = _lesson!;
    if (s.transcriptionBackend == 'none') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose a transcription backend in Settings first.'),
          ),
        );
        Nav.settings(context);
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Transcribingâ€¦ this can take a while.')),
    );
    try {
      final segments = await TranscriptionService().transcribe(
        filePath: lesson.path!,
        backend: s.transcriptionBackend,
        endpoint: s.transcriptionEndpoint,
        apiKey: s.transcriptionApiKey,
        model: s.transcriptionModel,
        language: s.transcriptionLanguage,
        executable: s.whisperPath,
      );
      final t = await Store.i.saveTranscript(
        ownerType: 'lesson',
        ownerId: lesson.id,
        language: s.transcriptionLanguage,
        source: s.transcriptionBackend,
        segments: segments,
      );
      final provider = await Store.i.defaultProvider();
      if (provider != null) {
        await RagService(Store.i, AiClient()).indexTranscript(
          lessonId: lesson.id,
          lessonTitle: lesson.title,
          courseTitle: _course?.title ?? 'Course',
          segments: segments,
          provider: provider,
        );
      }
      if (mounted) setState(() => _transcript = t);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Transcript ready: ${segments.length} segments.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Transcription failed: $e')),
      );
    }
  }

  Widget _filesTab(BuildContext context) {
    final c = context.c;
    if (_resources.isEmpty) {
      return MEmpty(
        icon: Icons.folder_copy_outlined,
        title: 'No files in this course',
        message: 'PDFs and documents attached to the course appear here while you study.',
        compact: true,
        action: MButton(
          label: 'Add files',
          dense: true,
          onPressed: () async {
            await importLibraryFiles(context, courseId: widget.courseId);
            final r = await Store.i.resources(courseId: widget.courseId);
            if (mounted) setState(() => _resources = r);
          },
        ),
      );
    }
    return MCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final r in _resources)
            InkWell(
              onTap: () => Nav.resource(context, r.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 15,
                      color: c.inkMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MType.small.copyWith(
                          color: c.ink,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _askTab(BuildContext context) {
    return _InlineAsk(
      courseId: widget.courseId,
      lessonId: widget.lessonId,
      position: _position,
      lessonTitle: _lesson?.title ?? '',
      courseTitle: _course?.title ?? '',
      transcript: _transcript,
      onSeek: _seek,
    );
  }
}

/// The fullscreen stage. It lives on the root overlay, so it covers the whole
/// window, and it subscribes to the player directly: the page underneath is
/// replaced by a black box while this is visible, keeping a single [Video].
class _FullscreenPlayer extends StatefulWidget {
  const _FullscreenPlayer({
    required this.player,
    required this.controller,
    required this.title,
    required this.courseTitle,
    required this.isAudio,
    required this.skipSeconds,
    required this.volume,
    required this.subtitleOn,
    required this.onExit,
    required this.onVolume,
    required this.onSpeed,
    required this.onSubtitles,
  });

  final Player player;
  final VideoController controller;
  final String title;
  final String courseTitle;
  final bool isAudio;
  final int skipSeconds;
  final double volume;
  final bool subtitleOn;
  final Future<void> Function() onExit;
  final ValueChanged<double> onVolume;
  final Future<void> Function(double) onSpeed;
  final Future<void> Function(bool) onSubtitles;

  @override
  State<_FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<_FullscreenPlayer> {
  final FocusNode _focus = FocusNode();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  late double _volume = widget.volume;
  late bool _subtitleOn = widget.subtitleOn;
  bool _controls = true;
  bool _pointerOnBar = false;
  Timer? _hideTimer;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;

  @override
  void initState() {
    super.initState();
    _posSub = widget.player.stream.position.listen((v) {
      if (!mounted) return;
      setState(() => _position = v);
    });
    _durSub = widget.player.stream.duration.listen((v) {
      if (!mounted) return;
      setState(() => _duration = v);
    });
    _playSub = widget.player.stream.playing.listen((v) {
      if (!mounted) return;
      setState(() => _playing = v);
      if (v) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
        if (!_controls) setState(() => _controls = true);
      }
    });
    _playing = widget.player.state.playing;
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _pointerOnBar || !_playing) return;
      setState(() => _controls = false);
    });
  }

  void _wake() {
    _hideTimer?.cancel();
    if (!_controls) setState(() => _controls = true);
    _scheduleHide();
  }

  void _seek(Duration d) {
    widget.player.seek(d);
    setState(() => _position = d);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.keyF) {
          widget.onExit();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.space) {
          widget.player.playOrPause();
          _wake();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _seek(_position + Duration(seconds: widget.skipSeconds));
          _wake();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _seek(_position - Duration(seconds: widget.skipSeconds));
          _wake();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: _controls ? SystemMouseCursors.basic : SystemMouseCursors.none,
        onHover: (_) => _wake(),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  widget.player.playOrPause();
                  _wake();
                },
                onDoubleTap: widget.onExit,
                child: widget.isAudio
                    ? _artwork()
                    : Video(
                        controller: widget.controller,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                        fill: Colors.black,
                      ),
              ),
              if (!_playing)
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 46,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              _topBar(),
              _bottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artwork() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              size: 48,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: MType.h2.copyWith(color: Colors.white, fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            widget.courseTitle,
            textAlign: TextAlign.center,
            style: MType.small.copyWith(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Align(
      alignment: Alignment.topCenter,
      child: IgnorePointer(
        ignoring: !_controls,
        child: AnimatedOpacity(
          opacity: _controls ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 44),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.62),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MType.bodyStrong.copyWith(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.courseTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MType.small.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _FsIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Exit fullscreen (Esc)',
                  size: 38,
                  onPressed: widget.onExit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        ignoring: !_controls,
        child: AnimatedOpacity(
          opacity: _controls ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: MouseRegion(
            onEnter: (_) {
              _pointerOnBar = true;
              _hideTimer?.cancel();
              if (!_controls) setState(() => _controls = true);
            },
            onExit: (_) {
              _pointerOnBar = false;
              _scheduleHide();
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(26, 46, 26, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Timeline(
                    position: _position,
                    duration: _duration,
                    onSeek: (d) {
                      _seek(d);
                      _wake();
                    },
                    channels: 0,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white.withValues(alpha: 0.22),
                    thumbColor: Colors.white,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _FsIconButton(
                        icon: _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        tooltip: _playing ? 'Pause (Space)' : 'Play (Space)',
                        size: 42,
                        onPressed: () {
                          widget.player.playOrPause();
                          _wake();
                        },
                      ),
                      _FsIconButton(
                        icon: Icons.replay_10_rounded,
                        tooltip: 'Back ${widget.skipSeconds}s',
                        size: 36,
                        onPressed: () {
                          _seek(
                            _position - Duration(seconds: widget.skipSeconds),
                          );
                          _wake();
                        },
                      ),
                      _FsIconButton(
                        icon: Icons.forward_10_rounded,
                        tooltip: 'Forward ${widget.skipSeconds}s',
                        size: 36,
                        onPressed: () {
                          _seek(
                            _position + Duration(seconds: widget.skipSeconds),
                          );
                          _wake();
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${formatClock(_position)} / ${formatClock(_duration)}',
                        style: MType.small.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 11.5,
                        ),
                      ),
                      const Spacer(),
                      _FsIconButton(
                        icon: _subtitleOn
                            ? Icons.subtitles_rounded
                            : Icons.subtitles_off_outlined,
                        tooltip: 'Subtitles',
                        size: 36,
                        selected: _subtitleOn,
                        onPressed: () async {
                          final on = !_subtitleOn;
                          setState(() => _subtitleOn = on);
                          await widget.onSubtitles(on);
                          _wake();
                        },
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 124,
                        child: SliderTheme(
                          data: _fsSliderTheme(context, trackHeight: 2.5),
                          child: Slider(
                            value: AppState.i.playbackSpeed.clamp(0.5, 2.0),
                            min: 0.5,
                            max: 2.0,
                            divisions: 6,
                            onChanged: (v) {
                              widget.onSpeed(v);
                              setState(() {});
                              _wake();
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${AppState.i.playbackSpeed}x',
                          textAlign: TextAlign.center,
                          style: MType.small.copyWith(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        _volume == 0
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      SizedBox(
                        width: 110,
                        child: SliderTheme(
                          data: _fsSliderTheme(context, trackHeight: 2),
                          child: Slider(
                            value: _volume,
                            onChanged: (v) {
                              setState(() => _volume = v);
                              widget.player.setVolume(v * 100);
                              widget.onVolume(v);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _FsIconButton(
                        icon: Icons.fullscreen_exit_rounded,
                        tooltip: 'Exit fullscreen (Esc)',
                        size: 38,
                        onPressed: widget.onExit,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  SliderThemeData _fsSliderTheme(
    BuildContext context, {
    required double trackHeight,
  }) {
    return SliderTheme.of(context).copyWith(
      trackHeight: trackHeight,
      activeTrackColor: Colors.white,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
      thumbColor: Colors.white,
      overlayColor: Colors.white.withValues(alpha: 0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
      activeTickMarkColor: Colors.black,
      inactiveTickMarkColor: Colors.white.withValues(alpha: 0.35),
    );
  }
}

/// Round, white-on-black icon control used by the fullscreen stage. It is
/// deliberately independent of [MIconButton] so the light theme never leaks a
/// dark glyph onto the video.
class _FsIconButton extends StatefulWidget {
  const _FsIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 36,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool selected;

  @override
  State<_FsIconButton> createState() => _FsIconButtonState();
}

class _FsIconButtonState extends State<_FsIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final button = Opacity(
      opacity: disabled ? 0.45 : 1,
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.selected
                  ? Colors.white.withValues(alpha: 0.92)
                  : (_hover
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(
              widget.icon,
              size: widget.size * 0.5,
              color: widget.selected ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.channels,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
  });
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final int channels;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final active = activeColor ?? c.accent;
    final max = duration.inMilliseconds.toDouble();
    final value = position.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toDouble();
    return SizedBox(
      height: 18,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: active,
          inactiveTrackColor: inactiveColor ?? c.surfaceSunken,
          thumbColor: thumbColor ?? active,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        ),
        child: Slider(
          value: max <= 0 ? 0 : value,
          max: max <= 0 ? 1 : max,
          onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
        ),
      ),
    );
  }
}

class _LessonTab extends StatelessWidget {
  const _LessonTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          margin: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? c.ink : Colors.transparent,
                width: 1.8,
              ),
            ),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: MType.bodyStrong.copyWith(
              color: selected ? c.ink : c.inkMuted,
              fontSize: 12.5,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _InlineAsk extends StatefulWidget {
  const _InlineAsk({
    required this.courseId,
    required this.lessonId,
    required this.position,
    required this.lessonTitle,
    required this.courseTitle,
    this.transcript,
    required this.onSeek,
  });
  final String courseId;
  final String lessonId;
  final Duration position;
  final String lessonTitle;
  final String courseTitle;
  final Transcript? transcript;
  final ValueChanged<Duration> onSeek;

  @override
  State<_InlineAsk> createState() => _InlineAskState();
}

class _InlineAskState extends State<_InlineAsk> {
  final _controller = TextEditingController();
  final _client = AiClient();
  String _answer = '';
  bool _busy = false;
  List<Citation> _citations = const [];
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _busy) return;
    final provider = await Store.i.defaultProvider();
    if (provider == null) {
      setState(
        () => _error = 'Add an AI provider in Settings to use the tutor.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _answer = '';
      _error = null;
      _citations = const [];
    });
    final rag = RagService(Store.i, _client);
    final chunks = await rag.retrieve(
      '${widget.lessonTitle} $q',
      provider: provider,
    );
    final (contextBlock, citations) = RagService.buildContext(chunks);
    final t = widget.transcript;
    final nearby = <String>[];
    if (t != null) {
      final ms = widget.position.inMilliseconds;
      for (final s in t.segments.where(
        (s) => s.startMs >= ms - 120000 && s.startMs <= ms + 120000,
      )) {
        nearby.add(
          '[${formatClock(Duration(milliseconds: s.startMs))}] ${s.text}',
        );
      }
    }
    final system =
        '''
You are klaro.'s lesson tutor. Answer from the supplied material first.
Cite sources with [n]. If the material does not contain the answer, say so and then answer from general knowledge, clearly labelled.
Course: ${widget.courseTitle}
Lesson: ${widget.lessonTitle}
Current position: ${formatClock(widget.position)}
${nearby.isEmpty ? '' : 'Nearby transcript:\n${nearby.join('\n')}'}
${contextBlock.isEmpty ? '' : 'Retrieved material:\n$contextBlock'}
''';
    final buffer = StringBuffer();
    await _client.streamChat(
      provider: provider,
      messages: [
        ChatTurn(role: 'system', content: system),
        ChatTurn(role: 'user', content: q),
      ],
      onDelta: (d) {
        buffer.write(d);
        if (mounted) setState(() => _answer = buffer.toString());
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _busy = false;
            _citations = citations;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = e.toString();
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: MType.body.copyWith(color: c.ink, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Ask about this moment, or the whole lessonâ€¦',
                  prefixIcon: Icon(
                    Icons.auto_awesome_outlined,
                    size: 16,
                    color: c.inkFaint,
                  ),
                ),
                onSubmitted: (_) => _ask(),
              ),
            ),
            const SizedBox(width: 8),
            MButton(
              label: _busy ? 'Thinkingâ€¦' : 'Ask',
              kind: MButtonKind.primary,
              onPressed: _busy ? null : _ask,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_error != null)
          Text(
            _error!,
            style: MType.small.copyWith(color: c.danger, fontSize: 12),
          ),
        if (_answer.isNotEmpty || _busy)
          MCard(
            padding: const EdgeInsets.all(16),
            color: c.surfaceAlt,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _answer.isEmpty ? 'â€¦' : _answer,
                  style: MType.body.copyWith(
                    color: c.ink,
                    height: 1.6,
                    fontSize: 13,
                  ),
                ),
                if (_citations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < _citations.length; i++)
                        MChip(
                          label: '${i + 1}. ${_citations[i].label}',
                          tone: MChipTone.accent,
                          onTap: () {
                            final loc = _citations[i].locator;
                            if (loc == null) return;
                            final parts = loc.split(':');
                            if (parts.length == 2) {
                              final m = int.tryParse(parts[0]) ?? 0;
                              final s = int.tryParse(parts[1]) ?? 0;
                              widget.onSeek(Duration(minutes: m, seconds: s));
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
    );
  }
}

/// The study panel when collapsed: a slim, quiet rail that reopens it.
class _CollapsedPanel extends StatelessWidget {
  const _CollapsedPanel({required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return MCard(
      padding: EdgeInsets.zero,
      radius: MRadius.xl,
      child: Column(
        children: [
          const SizedBox(height: 8),
          MIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Show the study panel',
            size: 34,
            onPressed: onExpand,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: Center(
                child: Text(
                  'Files Â· Notes Â· AI Tutor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MType.small.copyWith(
                    color: c.inkFaint,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
