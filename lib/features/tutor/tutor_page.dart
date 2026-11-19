import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/ai.dart';
import '../../services/rag.dart';
import '../shell.dart';

const _uuid = Uuid();

class TutorPage extends StatefulWidget {
  const TutorPage({super.key, this.initialContext});
  final (String?, String?, String?)? initialContext;

  @override
  State<TutorPage> createState() => _TutorPageState();
}

class _TutorPageState extends State<TutorPage> {
  AiProvider? _provider;
  List<Map<String, Object?>> _threads = const [];
  List<Course> _courses = const [];
  List<Lesson> _lessons = const [];
  String? _threadId;
  List<ChatMessage> _messages = const [];
  String? _courseId;
  String? _lessonId;
  bool _includeNotes = true;
  bool _includeLibrary = true;
  bool _useMaterials = true;
  bool _busy = false;
  bool _cancelled = false;
  String _stream = '';
  List<Citation> _streamCitations = const [];
  String? _error;
  int _chunkCount = 0;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _client = AiClient();

  @override
  void initState() {
    super.initState();
    AppState.i.addListener(_onAppState);
    _init();
  }

  void _onAppState() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    final providers = await Store.i.providers();
    final threads = await Store.i.threads();
    final courses = await Store.i.courses();
    final chunkRows = await Store.i.db.rawQuery(
      'SELECT COUNT(*) AS n FROM chunks',
    );
    final chunks = chunkRows.isEmpty ? 0 : (chunkRows.first['n'] as int? ?? 0);
    _courseId = widget.initialContext?.$1 ?? AppState.i.activeCourseId;
    _lessonId = widget.initialContext?.$2 ?? AppState.i.activeLessonId;
    final prompt = widget.initialContext?.$3;
    if (_courseId != null) {
      _lessons = await Store.i.lessons(_courseId!);
    }
    if (!mounted) return;
    setState(() {
      _provider =
          providers.where((p) => p.isDefault).firstOrNull ??
          providers.firstOrNull;
      _threads = threads;
      _courses = courses;
      _chunkCount = chunks;
    });
    if (prompt != null && prompt.isNotEmpty) {
      _input.text = prompt;
      WidgetsBinding.instance.addPostFrameCallback((_) => _send());
    }
  }

  Future<void> _selectCourse(String? id) async {
    setState(() {
      _courseId = id;
      _lessonId = null;
      _lessons = const [];
    });
    if (id != null) {
      final lessons = await Store.i.lessons(id);
      if (mounted) setState(() => _lessons = lessons);
    }
  }

  Future<void> _newThread() async {
    setState(() {
      _threadId = null;
      _messages = const [];
      _stream = '';
      _error = null;
    });
  }

  Future<void> _openThread(String id) async {
    final messages = await Store.i.messages(id);
    final thread = _threads.firstWhere(
      (t) => t['id'] == id,
      orElse: () => const {},
    );
    if (!mounted) return;
    setState(() {
      _threadId = id;
      _messages = messages;
      _courseId = thread['course_id'] as String?;
      _lessonId = thread['lesson_id'] as String?;
      _stream = '';
    });
    if (_courseId != null) {
      final lessons = await Store.i.lessons(_courseId!);
      if (mounted) setState(() => _lessons = lessons);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    if (_provider == null) {
      setState(() => _error = 'No AI provider configured yet.');
      return;
    }
    _input.clear();
    setState(() {
      _busy = true;
      _cancelled = false;
      _stream = '';
      _streamCitations = const [];
      _error = null;
    });
    _threadId ??= await Store.i.createThread(
      title: text.length > 48 ? '${text.substring(0, 48)}…' : text,
      mode: _lessonId != null
          ? 'lesson'
          : (_courseId != null ? 'course' : 'general'),
      courseId: _courseId,
      lessonId: _lessonId,
    );
    final userMsg = await Store.i.addMessage(
      threadId: _threadId!,
      role: 'user',
      content: text,
    );
    setState(() => _messages = [..._messages, userMsg]);
    await Store.i.touchThread(_threadId!);

    final context = await _buildContext(text);
    final provider = _provider!;
    final history = <ChatTurn>[];
    for (final m in _messages.reversed.take(8).toList().reversed) {
      history.add(ChatTurn(role: m.role, content: m.content));
    }
    final buffer = StringBuffer();
    _scrollToEnd();
    await _client.streamChat(
      provider: provider,
      messages: [
        ChatTurn(role: 'system', content: context),
        ...history,
        ChatTurn(role: 'user', content: text),
      ],
      cancelled: () => _cancelled,
      onDelta: (d) {
        buffer.write(d);
        if (mounted) {
          setState(() => _stream = buffer.toString());
          _scrollToEnd();
        }
      },
      onDone: () async {},
      onError: (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = e.toString();
          });
        }
      },
    );
    if (_cancelled) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (buffer.isEmpty) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _error ?? 'The provider returned an empty answer.';
        });
      }
      return;
    }
    final saved = await Store.i.addMessage(
      threadId: _threadId!,
      role: 'assistant',
      content: buffer.toString(),
      citations: _streamCitations,
    );
    if (!mounted) return;
    setState(() {
      _messages = [..._messages, saved];
      _stream = '';
      _busy = false;
    });
    final threads = await Store.i.threads();
    if (mounted) setState(() => _threads = threads);
    _scrollToEnd();
  }

  Future<String> _buildContext(String question) async {
    final b = StringBuffer();
    b.writeln(
      'You are klaro., a learning tutor inside a local-first study platform. '
      'Answer precisely and briefly. Use the supplied material when it is relevant and cite it as [n]. '
      'Never invent a citation. If the material does not answer the question, say so, then give a clearly labelled general answer.',
    );
    final course = _courses.where((c) => c.id == _courseId).firstOrNull;
    b.writeln(
      '\nThe learner is currently in the app section: ${AppState.i.activeSectionLabel}.',
    );
    if (course != null) {
      b.writeln('\nCurrent course: ${course.title}');
      if (course.author?.isNotEmpty == true)
        b.writeln('Author: ${course.author}');
      if (course.description?.isNotEmpty == true)
        b.writeln('Description: ${course.description}');
      if (course.objectives?.isNotEmpty == true)
        b.writeln('Objectives:\n${course.objectives}');
    }
    if (_lessonId != null) {
      final lesson = await Store.i.lesson(_lessonId!);
      if (lesson != null) {
        b.writeln('\nCurrent lesson: ${lesson.title}');
        final t = await Store.i.transcriptFor('lesson', lesson.id);
        if (t != null) {
          final text = t.segments.take(120).map((s) => s.text).join(' ');
          b.writeln(
            'Transcript excerpt:\n${text.length > 6000 ? text.substring(0, 6000) : text}',
          );
        }
      }
    }
    if (AppState.i.activeNoteId != null) {
      final activeNote = await Store.i.note(AppState.i.activeNoteId!);
      if (activeNote != null) {
        b.writeln(
          '\nCurrently open Note page: "${activeNote.title}"\n${activeNote.body}',
        );
      }
    }
    if (AppState.i.activeMapId != null) {
      final activeMap = await Store.i.conceptMap(AppState.i.activeMapId!);
      if (activeMap != null) {
        final nodes = await Store.i.conceptNodes(activeMap.id);
        final nodesText = nodes
            .map((n) => '- ${n.title}${n.body.isNotEmpty ? ': ${n.body}' : ''}')
            .join('\n');
        b.writeln(
          '\nCurrently open Schema (${activeMap.kind}): "${activeMap.title}"\n$nodesText',
        );
      }
    }
    if (AppState.i.activeResourceId != null) {
      final res = await Store.i.resource(AppState.i.activeResourceId!);
      if (res != null) {
        b.writeln(
          '\nCurrently open Library Document: "${res.title}" (${res.kind})',
        );
      }
    }
    if (_useMaterials) {
      final rag = RagService(Store.i, _client);
      final chunks = await rag.retrieve(question, provider: _provider);
      final filtered = chunks.where((ch) {
        if (!_includeNotes && ch.sourceType == 'note') return false;
        if (!_includeLibrary && ch.sourceType == 'resource') return false;
        return true;
      }).toList();
      final (block, citations) = RagService.buildContext(filtered);
      if (block.isNotEmpty) {
        b.writeln('\nRetrieved material from the learner\'s own library:');
        b.writeln(block);
        _streamCitations = citations;
      }
    }
    return b.toString();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    AppState.i.removeListener(_onAppState);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final width = MediaQuery.sizeOf(context).width;
    final showPanels = width > 1020;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 28, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showPanels) ...[
            SizedBox(
              width: 244,
              child: MCard(
                padding: const EdgeInsets.all(14),
                radius: MRadius.xl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Conversations',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MType.h3.copyWith(
                              color: c.ink,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        MIconButton(
                          icon: Icons.add_rounded,
                          tooltip: 'New conversation',
                          size: 32,
                          onPressed: _newThread,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _threads.isEmpty
                          ? Center(
                              child: Text(
                                'Your Tutor sessions will appear here.',
                                textAlign: TextAlign.center,
                                style: MType.small.copyWith(
                                  color: c.inkFaint,
                                  fontSize: 11.5,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: _threads.length,
                              itemBuilder: (context, i) {
                                final t = _threads[i];
                                final selected = t['id'] == _threadId;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: InkWell(
                                    onTap: () => _openThread(t['id'] as String),
                                    borderRadius: BorderRadius.circular(
                                      MRadius.md,
                                    ),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 140,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? c.surfaceSunken
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          MRadius.md,
                                        ),
                                      ),
                                      child: Text(
                                        t['title'] as String? ?? 'Conversation',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: MType.small.copyWith(
                                          fontSize: 12,
                                          color: selected ? c.ink : c.inkMuted,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    _ProviderBadge(
                      provider: _provider,
                      onTap: () => Nav.settings(context, section: 'ai'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: MCard(
              padding: EdgeInsets.zero,
              radius: MRadius.xl,
              child: Column(
                children: [
                  Expanded(
                    child: _messages.isEmpty && _stream.isEmpty
                        ? _hero(context)
                        : _conversation(context),
                  ),
                  _composer(context),
                ],
              ),
            ),
          ),
          if (showPanels) ...[
            const SizedBox(width: 16),
            SizedBox(width: 280, child: _contextCard(context)),
          ],
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final c = context.c;
    final suggestions = [
      'Explain the hardest concept in my notes or PDFs in plain language.',
      'Generate 5 active-recall flashcards from my latest study material.',
      'Compare two concepts across my documents and courses.',
      'Create a structured schema and two-week study plan.',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(36, 40, 36, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const KlaroMark(size: 42),
              const SizedBox(height: 18),
              Text(
                'What are you studying today?',
                style: MType.h1.copyWith(color: c.ink, fontSize: 28),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask about your PDFs, books, notes, formulas, concept maps or video lessons. '
                'Every answer cites the exact passage it used.',
                style: MType.body.copyWith(color: c.inkMuted, height: 1.55),
              ),
              const SizedBox(height: 22),
              for (final s in suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      _input.text = s;
                      _send();
                    },
                    borderRadius: BorderRadius.circular(MRadius.md),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius: BorderRadius.circular(MRadius.md),
                        border: Border.all(color: c.line),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s,
                              style: MType.small.copyWith(
                                color: c.ink,
                                fontSize: 12.8,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                            color: c.inkFaint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_provider == null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surfaceSunken,
                    borderRadius: BorderRadius.circular(MRadius.md),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined, size: 17, color: c.ink),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Connect Ollama or an OpenAI-compatible model in Settings to activate the AI Tutor.',
                          style: MType.small.copyWith(
                            color: c.ink,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      MButton(
                        label: 'Set up',
                        kind: MButtonKind.primary,
                        dense: true,
                        onPressed: () => Nav.settings(context, section: 'ai'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _conversation(BuildContext context) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
      itemCount: _messages.length + (_stream.isNotEmpty || _busy ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _messages.length) {
          return _MessageBubble(
            role: 'assistant',
            content: _stream,
            citations: _streamCitations,
            streaming: _busy,
          );
        }
        final m = _messages[i];
        return _MessageBubble(
          role: m.role,
          content: m.content,
          citations: m.citations,
        );
      },
    );
  }

  Widget _composer(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: MType.small.copyWith(color: c.danger, fontSize: 11.5),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(MRadius.lg),
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  style: MType.body.copyWith(color: c.ink, fontSize: 13.5),
                  decoration: const InputDecoration(
                    hintText:
                        'Ask about your books, notes, formulas, or courses…',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                  ),
                  onSubmitted: (_) => _send(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(
                    children: [
                      if (_lessonId != null)
                        MChip(label: 'Lesson context', tone: MChipTone.accent),
                      if (_courseId != null && _lessonId == null)
                        MChip(label: 'Course context', tone: MChipTone.accent),
                      const Spacer(),
                      if (_busy)
                        MButton(
                          label: 'Stop',
                          dense: true,
                          onPressed: () => setState(() => _cancelled = true),
                        )
                      else
                        MButton(
                          label: 'Send',
                          icon: Icons.arrow_upward_rounded,
                          kind: MButtonKind.primary,
                          dense: true,
                          onPressed: _send,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Right-hand Study Context card: consistent with the rest of the app,
  /// scrollable, with custom pickers instead of raw Material dropdowns.
  Widget _contextCard(BuildContext context) {
    final c = context.c;
    final courseLabel =
        _courses.where((x) => x.id == _courseId).firstOrNull?.title ??
        'All study materials';
    final lessonLabel =
        _lessons.where((x) => x.id == _lessonId).firstOrNull?.title ??
        'Entire course';

    return MCard(
      padding: EdgeInsets.zero,
      radius: MRadius.xl,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c.surfaceSunken,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.tune_rounded, size: 16, color: c.ink),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Study Context',
                        style: MType.h3.copyWith(color: c.ink, fontSize: 14.5),
                      ),
                      Text(
                        'What the tutor may read',
                        style: MType.small.copyWith(
                          color: c.inkMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const MDivider(),
          Expanded(
            child: MSmoothScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'LIVE WORKSPACE',
                    style: MType.label.copyWith(
                      color: c.inkFaint,
                      fontSize: 9.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.surfaceSunken,
                      borderRadius: BorderRadius.circular(MRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.my_location_rounded, size: 15, color: c.ink),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _liveContextLabel(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: MType.small.copyWith(
                              color: c.ink,
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'SCOPE',
                    style: MType.label.copyWith(
                      color: c.inkFaint,
                      fontSize: 9.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ContextPickerTile(
                    icon: Icons.school_outlined,
                    label: 'Course',
                    value: courseLabel,
                    onTap: () => _pickCourse(context),
                  ),
                  if (_lessons.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _ContextPickerTile(
                      icon: Icons.play_lesson_outlined,
                      label: 'Lesson',
                      value: lessonLabel,
                      onTap: () => _pickLesson(context),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'SOURCES',
                    style: MType.label.copyWith(
                      color: c.inkFaint,
                      fontSize: 9.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SourceSwitchTile(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Personal notes',
                    value: _includeNotes,
                    onChanged: (v) => setState(() => _includeNotes = v),
                  ),
                  const SizedBox(height: 6),
                  _SourceSwitchTile(
                    icon: Icons.menu_book_rounded,
                    label: 'Library PDFs & docs',
                    value: _includeLibrary,
                    onChanged: (v) => setState(() => _includeLibrary = v),
                  ),
                  const SizedBox(height: 6),
                  _SourceSwitchTile(
                    icon: Icons.manage_search_rounded,
                    label: 'Passage citations',
                    value: _useMaterials,
                    onChanged: (v) => setState(() => _useMaterials = v),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(MRadius.md),
                      border: Border.all(color: c.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.storage_rounded,
                              size: 13,
                              color: c.inkFaint,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'KNOWLEDGE BASE',
                              style: MType.label.copyWith(
                                color: c.inkFaint,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$_chunkCount indexed passages',
                          style: MType.bodyStrong.copyWith(
                            color: c.ink,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ready for retrieval',
                          style: MType.small.copyWith(
                            color: c.inkMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
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

  String _liveContextLabel() {
    final section = AppState.i.activeSectionLabel;
    final parts = <String>[section];
    final course = _courses
        .where((x) => x.id == AppState.i.activeCourseId)
        .firstOrNull;
    if (course != null) parts.add(course.title);
    if (AppState.i.activeLessonId != null) {
      final lesson = _lessons
          .where((l) => l.id == AppState.i.activeLessonId)
          .firstOrNull;
      if (lesson != null) parts.add(lesson.title);
    }
    if (AppState.i.activeResourceId != null) parts.add('document open');
    if (AppState.i.activeNoteId != null) parts.add('note page open');
    if (AppState.i.activeMapId != null) parts.add('schema open');
    return parts.join(' · ');
  }

  Future<void> _pickCourse(BuildContext context) async {
    final choice = await showMSheet<String?>(
      context,
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MDialogHeader(
            title: 'Course scope',
            subtitle: 'Limit the tutor to one course.',
          ),
          _PickerRow(
            label: 'All study materials',
            selected: _courseId == null,
            onTap: () => Navigator.of(context).pop(null),
          ),
          for (final course in _courses)
            _PickerRow(
              label: course.title,
              selected: _courseId == course.id,
              onTap: () => Navigator.of(context).pop(course.id),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
    if (!context.mounted) return;
    await _selectCourse(choice);
  }

  Future<void> _pickLesson(BuildContext context) async {
    final choice = await showMSheet<String?>(
      context,
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MDialogHeader(
            title: 'Lesson scope',
            subtitle: 'Focus on a single lesson.',
          ),
          _PickerRow(
            label: 'Entire course',
            selected: _lessonId == null,
            onTap: () => Navigator.of(context).pop(null),
          ),
          for (final l in _lessons)
            _PickerRow(
              label: l.title,
              selected: _lessonId == l.id,
              onTap: () => Navigator.of(context).pop(l.id),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
    if (!context.mounted) return;
    setState(() => _lessonId = choice);
  }
}

class _ContextPickerTile extends StatelessWidget {
  const _ContextPickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(MRadius.md),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: c.inkMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: MType.small.copyWith(
                      color: c.inkFaint,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.small.copyWith(
                      color: c.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.unfold_more_rounded, size: 15, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MType.body.copyWith(
                  color: c.ink,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected) Icon(Icons.check_rounded, size: 16, color: c.ink),
          ],
        ),
      ),
    );
  }
}

class _SourceSwitchTile extends StatelessWidget {
  const _SourceSwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(MRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value ? c.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(MRadius.md),
          border: Border.all(color: value ? c.lineStrong : c.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: value ? c.ink : c.inkMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: MType.small.copyWith(
                  color: value ? c.ink : c.inkMuted,
                  fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Container(
              width: 30,
              height: 18,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? c.ink : c.surfaceSunken,
                borderRadius: BorderRadius.circular(99),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: value ? c.surface : c.inkFaint,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.provider, required this.onTap});
  final AiProvider? provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MRadius.md),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(MRadius.md),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: provider == null ? c.inkFaint : c.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider?.name ?? 'No AI provider',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.small.copyWith(
                      color: c.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    provider?.model ?? 'Configure in Settings',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MType.small.copyWith(
                      color: c.inkFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.role,
    required this.content,
    this.citations = const [],
    this.streaming = false,
  });
  final String role;
  final String content;
  final List<Citation> citations;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isUser = role == 'user';
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18, left: 60),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: c.ink,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(MRadius.lg),
                topRight: Radius.circular(MRadius.lg),
                bottomLeft: Radius.circular(MRadius.lg),
                bottomRight: Radius.circular(MSpace.x1),
              ),
            ),
            child: Text(
              content,
              style: MType.body.copyWith(
                color: c.surface,
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22, right: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const KlaroMark(size: 18),
              const SizedBox(width: 8),
              Text(
                'klaro. Tutor',
                style: MType.small.copyWith(
                  color: c.inkMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (streaming) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: c.inkFaint,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (content.isEmpty)
            Text('…', style: MType.body.copyWith(color: c.inkMuted))
          else
            MarkdownBody(
              data: content,
              styleSheet: MarkdownStyleSheet(
                p: MType.body.copyWith(
                  color: c.ink,
                  height: 1.7,
                  fontSize: 13.5,
                ),
                h1: MType.h2.copyWith(color: c.ink, fontSize: 18),
                h2: MType.h2.copyWith(color: c.ink, fontSize: 16),
                h3: MType.h3.copyWith(color: c.ink),
                listBullet: MType.body.copyWith(color: c.ink),
                code: MType.mono.copyWith(color: c.ink, fontSize: 12.5),
                codeblockDecoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(MSpace.x2),
                  border: Border.all(color: c.line),
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(left: BorderSide(color: c.ink, width: 2)),
                ),
                blockquote: MType.body.copyWith(color: c.inkMuted),
              ),
            ),
          if (citations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < citations.length; i++)
                  MChip(
                    label: '${i + 1}. ${citations[i].label}',
                    tone: MChipTone.neutral,
                  ),
              ],
            ),
          ],
          if (!streaming && content.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MChip(
                  label: '+ Save as Note (in your words)',
                  icon: Icons.note_add_outlined,
                  onTap: () => _saveReplyAsNote(context, content),
                ),
                MChip(
                  label: '+ Save as Flashcard',
                  icon: Icons.style_outlined,
                  onTap: () => _saveReplyAsCard(context, content),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveReplyAsNote(BuildContext context, String aiText) async {
    final titleCtrl = TextEditingController();
    final ownWordsCtrl = TextEditingController();
    final ok = await showMSheet<bool>(
      context,
      maxWidth: 520,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MDialogHeader(
              title: 'Save to Notes (Personal Elaboration)',
              subtitle: 'Summarize the core insight in your own words to lock it into memory.',
            ),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Note title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ownWordsCtrl,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'In your own words (what did you understand?)…',
              ),
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
                  label: 'Save Note',
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
    final now = DateTime.now();
    final own = ownWordsCtrl.text.trim();
    await Store.i.saveNote(
      Note(
        id: _uuid.v4(),
        title: titleCtrl.text.trim().isEmpty
            ? 'Tutor Insight'
            : titleCtrl.text.trim(),
        body: own.isNotEmpty ? '$own\n\n---\n> Reference:\n$aiText' : aiText,
        createdAt: now,
        updatedAt: now,
      ),
    );
    AppState.i.bump();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved to Notes.')));
    }
  }

  Future<void> _saveReplyAsCard(BuildContext context, String aiText) async {
    final qCtrl = TextEditingController();
    final aCtrl = TextEditingController(
      text: aiText.length > 260 ? '${aiText.substring(0, 260)}…' : aiText,
    );
    final ok = await showMSheet<bool>(
      context,
      maxWidth: 500,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MDialogHeader(
              title: 'Create Atomic Flashcard',
              subtitle: 'One clear question, one concise answer.',
            ),
            TextField(
              controller: qCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Question'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: aCtrl,
              minLines: 3,
              maxLines: 5,
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
                  label: 'Add to Review',
                  kind: MButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || qCtrl.text.trim().isEmpty) return;
    await Store.i.saveCard(
      Flashcard(
        id: _uuid.v4(),
        deck: 'AI Tutor',
        front: qCtrl.text.trim(),
        back: aCtrl.text.trim(),
        dueAt: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );
    AppState.i.bump();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flashcard added to Review queue.')),
      );
    }
  }
}
