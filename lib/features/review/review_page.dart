import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../design/smooth_scroll.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/ai.dart';
import '../shell.dart';

const _uuid = Uuid();

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  List<Flashcard> _queue = const [];
  int _index = 0;
  bool _revealed = false;
  bool _loading = true;
  Map<String, Object?> _stats = const {};
  int _totalCards = 0;
  final List<int> _session = [];
  bool _generating = false;

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
    final due = await Store.i.dueCards(limit: 60);
    final stats = await Store.i.reviewStats();
    final total = await Store.i.cardCount();
    if (!mounted) return;
    setState(() {
      _queue = due;
      _stats = stats;
      _totalCards = total;
      _loading = false;
      if (_index >= _queue.length) {
        _index = 0;
        _revealed = false;
      }
    });
  }

  Future<void> _rate(int rating) async {
    if (_queue.isEmpty) return;
    final card = _queue[_index];
    await Store.i.reviewCard(card, rating);
    _session.add(rating);
    if (_index + 1 >= _queue.length) {
      setState(() {
        _index = _queue.length;
        _revealed = false;
      });
      await _load();
    } else {
      setState(() {
        _index++;
        _revealed = false;
      });
    }
    AppState.i.bump();
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.space && !_revealed) {
      setState(() => _revealed = true);
      return KeyEventResult.handled;
    }
    if (_revealed) {
      final map = {
        LogicalKeyboardKey.digit1: 0,
        LogicalKeyboardKey.digit2: 1,
        LogicalKeyboardKey.digit3: 2,
        LogicalKeyboardKey.digit4: 3,
      };
      final r = map[e.logicalKey];
      if (r != null) {
        _rate(r);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: MSmoothScrollView(
        padding: const EdgeInsets.fromLTRB(22, 10, 32, 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, cons) {
                    final title = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Flashcards & Review',
                          style: MType.h1.copyWith(color: c.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Active recall with spaced repetition. Ratings schedule the next review.',
                          style: MType.small.copyWith(color: c.inkMuted),
                        ),
                      ],
                    );
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        MButton(
                          label: 'Practice & Simulate',
                          icon: Icons.psychology_outlined,
                          onPressed: _openActivePracticeSheet,
                        ),
                        MButton(
                          label: _generating
                              ? 'Generating.'
                              : 'Generate flashcards',
                          icon: Icons.auto_awesome_outlined,
                          kind: MButtonKind.primary,
                          onPressed: _generating ? null : _generate,
                        ),
                      ],
                    );
                    if (cons.maxWidth < 720) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 12), actions],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 12),
                        actions,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: MStat(
                        label: 'Due now',
                        value: '${_queue.length}',
                        hint: '$_totalCards flashcards in total',
                        icon: Icons.style_outlined,
                      ),
                    ),
                    Expanded(
                      child: MStat(
                        label: 'Retention 30d',
                        value: _stats['retention'] == null
                            ? '—'
                            : '${((_stats['retention'] as double) * 100).round()}%',
                        hint: 'Good and Easy answers',
                        icon: Icons.trending_up_rounded,
                      ),
                    ),
                    Expanded(
                      child: MStat(
                        label: 'Reviews 30d',
                        value: '${_stats['total30'] ?? 0}',
                        hint: 'All ratings',
                        icon: Icons.history_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_totalCards == 0)
                  _emptyDeck(context)
                else if (_index >= _queue.length)
                  _done(context)
                else
                  _card(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyDeck(BuildContext context) {
    return MEmpty(
      icon: Icons.style_outlined,
      title: 'No flashcards yet',
      message:
          'Flashcards come from your own study sources: turn a note, keyword or formula into a flashcard, '
          'or let the AI draft atomic questions from a course.',
      action: MButton(
        label: 'Generate flashcards',
        kind: MButtonKind.primary,
        onPressed: _generate,
      ),
    );
  }

  Widget _done(BuildContext context) {
    final c = context.c;
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, size: 18, color: c.accent),
              ),
              const SizedBox(width: 12),
              Text('Session complete', style: MType.h2.copyWith(color: c.ink)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _session.isEmpty
                ? 'Nothing was due right now. Come back later, or add new flashcards.'
                : 'You reviewed ${_session.length} flashcards. '
                      '${_session.where((r) => r >= 2).length} were recalled at Good or Easy.',
            style: MType.body.copyWith(color: c.inkMuted, height: 1.6),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              MButton(label: 'Refresh queue', onPressed: _load),
              const SizedBox(width: 8),
              MButton(
                label: 'Generate flashcards',
                kind: MButtonKind.primary,
                onPressed: _generate,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) {
    final c = context.c;
    final card = _queue[_index];
    final progress = _queue.isEmpty ? 0.0 : _index / _queue.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              card.deck,
              style: MType.small.copyWith(color: c.inkMuted, fontSize: 11.5),
            ),
            const Spacer(),
            Text(
              '${_index + 1} / ${_queue.length}',
              style: MType.small.copyWith(color: c.inkFaint, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),
        MProgress(value: progress, height: 4),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(minHeight: 300),
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(MRadius.xl),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QUESTION',
                style: MType.label.copyWith(color: c.inkFaint, fontSize: 9.5),
              ),
              const SizedBox(height: 14),
              Text(
                card.front,
                style: MType.h1.copyWith(
                  color: c.ink,
                  fontSize: 26,
                  height: 1.3,
                ),
              ),
              if (_revealed) ...[
                const SizedBox(height: 26),
                const Divider(),
                const SizedBox(height: 18),
                Text(
                  'ANSWER',
                  style: MType.label.copyWith(color: c.accent, fontSize: 9.5),
                ),
                const SizedBox(height: 10),
                Text(
                  card.back,
                  style: MType.body.copyWith(
                    color: c.ink,
                    height: 1.65,
                    fontSize: 15,
                  ),
                ),
                if (card.page != null ||
                    card.resourceId != null ||
                    card.courseId != null) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (card.page != null)
                        MChip(
                          label: 'Source p. ${card.page}',
                          tone: MChipTone.accent,
                        ),
                      if (card.resourceId != null)
                        MChip(
                          label: 'Active reread in source',
                          icon: Icons.open_in_new_rounded,
                          onTap: () => Nav.resource(context, card.resourceId!),
                        ),
                      if (card.courseId != null && card.lessonId != null)
                        MChip(
                          label: 'Open source lesson',
                          icon: Icons.play_lesson_outlined,
                          onTap: () => Nav.lesson(
                            context,
                            card.courseId!,
                            card.lessonId!,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    MChip(
                      label: 'AI: Explain with analogy',
                      icon: Icons.auto_awesome_outlined,
                      onTap: () => _coachCurrentCard(card, 'analogy'),
                    ),
                    MChip(
                      label: 'AI: Test my own explanation',
                      icon: Icons.record_voice_over_outlined,
                      onTap: () => _coachCurrentCard(card, 'feynman'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!_revealed)
          Align(
            alignment: Alignment.centerLeft,
            child: MButton(
              label: 'Show answer   Space',
              icon: Icons.visibility_outlined,
              kind: MButtonKind.primary,
              onPressed: () => setState(() => _revealed = true),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: _RatingButton(
                  label: 'Again',
                  keyHint: '1',
                  tone: c.danger,
                  onTap: () => _rate(0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RatingButton(
                  label: 'Hard',
                  keyHint: '2',
                  tone: c.amber,
                  onTap: () => _rate(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RatingButton(
                  label: 'Good',
                  keyHint: '3',
                  tone: c.accent,
                  onTap: () => _rate(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RatingButton(
                  label: 'Easy',
                  keyHint: '4',
                  tone: c.success,
                  onTap: () => _rate(3),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _generate() async {
    final provider = await Store.i.defaultProvider();
    if (provider == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Configure an AI provider first, or create flashcards from a note.',
            ),
          ),
        );
      }
      return;
    }
    final source = await _pickSource();
    if (source == null) return;
    final (label, text, courseId, lessonId) = source;
    setState(() => _generating = true);
    final client = AiClient();
    final buffer = StringBuffer();
    try {
      await client.streamChat(
        provider: provider,
        messages: [
          ChatTurn(
            role: 'system',
            content:
                'You write retrieval-practice flashcards for a serious learner. Return ONLY a JSON array of objects '
                'with keys "q" and "a". Questions must be answerable from the material, atomic, and not yes/no. '
                'Write 8 flashcards maximum.',
          ),
          ChatTurn(role: 'user', content: 'Material from "$label":\n\n$text'),
        ],
        onDelta: (d) => buffer.write(d),
        onDone: () {},
        onError: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Generation failed: $e')));
          }
        },
      );
      final cards = _parseCards(buffer.toString());
      for (final card in cards) {
        await Store.i.saveCard(
          Flashcard(
            id: _uuid.v4(),
            deck: label,
            front: card.$1,
            back: card.$2,
            courseId: courseId,
            lessonId: lessonId,
            dueAt: DateTime.now(),
            createdAt: DateTime.now(),
          ),
        );
      }
      AppState.i.bump();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${cards.length} flashcards to review.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  List<(String, String)> _parseCards(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return [];
    try {
      final list = jsonDecode(raw.substring(start, end + 1)) as List;
      return list
          .whereType<Map>()
          .map((m) => (m['q']?.toString() ?? '', m['a']?.toString() ?? ''))
          .where((e) => e.$1.isNotEmpty && e.$2.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<(String, String, String?, String?)?> _pickSource() async {
    final courses = await Store.i.courses();
    if (courses.isEmpty || !mounted) return null;
    final choice = await showMSheet<Course>(
      context,
      maxWidth: 480,
      child: Builder(
        builder: (sheetCtx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MDialogHeader(
              title: 'Generate cards',
              subtitle: 'The tutor drafts cards from one course. You review them in the queue.',
            ),
            for (final course in courses)
              InkWell(
                onTap: () => Navigator.of(sheetCtx).pop(course),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          course.title,
                          style: MType.body.copyWith(
                            color: sheetCtx.c.ink,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: sheetCtx.c.inkFaint,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == null) return null;
    final notes = await Store.i.notes(courseId: choice.id);
    final lessons = await Store.i.lessons(choice.id);
    final text = StringBuffer();
    if (choice.objectives != null) {
      text.writeln('Objectives:\n${choice.objectives}\n');
    }
    for (final n in notes.take(20)) {
      text.writeln('${n.title}\n${n.body}\n');
    }
    if (notes.isEmpty) {
      for (final l in lessons.take(12)) {
        final t = await Store.i.transcriptFor('lesson', l.id);
        if (t != null) {
          text.writeln(l.title);
          for (final s in t.segments.take(40)) {
            text.writeln(s.text);
          }
        }
      }
    }
    if (text.toString().trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That course has no notes or transcripts to work from yet.',
            ),
          ),
        );
      }
      return null;
    }
    return (choice.title, text.toString(), choice.id, null);
  }

  Future<void> _coachCurrentCard(Flashcard card, String mode) async {
    final provider = await Store.i.defaultProvider();
    if (provider == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure an AI provider in Settings first.'),
        ),
      );
      return;
    }
    final inputCtrl = TextEditingController();
    final output = ValueNotifier<String>('');
    final busy = ValueNotifier<bool>(false);

    Future<void> runExplanation() async {
      busy.value = true;
      output.value = '';
      final buf = StringBuffer();
      final system = mode == 'analogy'
          ? 'You are a learning tutor. Explain why this flashcard answer holds using a concrete analogy, '
                'plain words, and highlight the key technical detail to remember.'
          : 'You evaluate the learner\'s self-explanation (Feynman technique). Compare their explanation '
                'against the reference answer. Point out what is accurate, what technical detail is missing or imprecise, '
                'and ask 1 follow-up question.';
      final userMsg = mode == 'analogy'
          ? 'Question: ${card.front}\nReference answer: ${card.back}'
          : 'Question: ${card.front}\nReference answer: ${card.back}\nMy explanation in my own words: ${inputCtrl.text.trim()}';
      await AiClient().streamChat(
        provider: provider,
        messages: [
          ChatTurn(role: 'system', content: system),
          ChatTurn(role: 'user', content: userMsg),
        ],
        onDelta: (d) {
          buf.write(d);
          output.value = buf.toString();
        },
        onDone: () => busy.value = false,
        onError: (e) {
          busy.value = false;
          output.value = 'Error: $e';
        },
      );
    }

    if (mode == 'analogy') {
      runExplanation();
    }

    if (!mounted) return;
    await showMSheet<void>(
      context,
      maxWidth: 560,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MDialogHeader(
              title: mode == 'analogy'
                  ? 'Explain with analogy'
                  : 'Test your own explanation',
              subtitle: card.front,
            ),
            if (mode == 'feynman') ...[
              TextField(
                controller: inputCtrl,
                minLines: 3,
                maxLines: 5,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText:
                      'Explain the concept in your own words without looking…',
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: MButton(
                  label: 'Evaluate my explanation',
                  icon: Icons.auto_awesome_outlined,
                  kind: MButtonKind.primary,
                  dense: true,
                  onPressed: runExplanation,
                ),
              ),
              const SizedBox(height: 12),
            ],
            ValueListenableBuilder<String>(
              valueListenable: output,
              builder: (context, text, _) {
                if (text.isEmpty) return const SizedBox.shrink();
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.c.surfaceAlt,
                        borderRadius: BorderRadius.circular(MRadius.md),
                        border: Border.all(color: context.c.line),
                      ),
                      child: SelectableText(
                        text,
                        style: MType.body.copyWith(
                          color: context.c.ink,
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openActivePracticeSheet() async {
    final provider = await Store.i.defaultProvider();
    if (provider == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure an AI provider in Settings first.'),
        ),
      );
      return;
    }
    final topicCtrl = TextEditingController();
    final attemptCtrl = TextEditingController();
    final output = ValueNotifier<String>('');
    final busy = ValueNotifier<bool>(false);
    var practiceMode = 'freerecall'; // freerecall | fers | exam

    if (!mounted) return;
    await showMSheet<void>(
      context,
      maxWidth: 620,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          final c = context.c;
          Future<void> runSession() async {
            if (topicCtrl.text.trim().isEmpty) return;
            busy.value = true;
            output.value = '';
            final notes = await Store.i.notes(query: topicCtrl.text.trim());
            final extracts = await Store.i.extracts();
            final sourceContext = StringBuffer();
            for (final n in notes.take(8)) {
              sourceContext.writeln('Note "${n.title}": ${n.body}');
            }
            for (final ex in extracts.take(20)) {
              sourceContext.writeln(
                '[${ex.kind}] ${ex.content} ${ex.description ?? ''}',
              );
            }
            final system = switch (practiceMode) {
              'freerecall' =>
                'The learner practiced Free Recall (writing down everything remembered on a topic from memory, without guiding questions). '
                    'Compare their attempt against their study notes and extracts below. Highlight: (1) accurately recalled points, '
                    '(2) missing key concepts or technical details, and (3) which specific passage they should revisit.',
              'feynman' =>
                'The learner practiced a Simple Explanation (explaining a topic in plain language, analogies and examples as if teaching a beginner). '
                    'Point out any logical gaps, circular definitions, or unclear steps, and help them sharpen the explanation.',
              _ =>
                'You are running a Practice Q&A session grounded strictly in the learner\'s own study sources below. '
                    'Evaluate their answer if provided, then ask 2 progressive follow-up questions that connect related ideas.',
            };
            final buf = StringBuffer();
            await AiClient().streamChat(
              provider: provider,
              messages: [
                ChatTurn(
                  role: 'system',
                  content:
                      '$system\n\nLearner\'s study sources:\n$sourceContext',
                ),
                ChatTurn(
                  role: 'user',
                  content:
                      'Topic: ${topicCtrl.text.trim()}\nMy attempt:\n${attemptCtrl.text.trim()}',
                ),
              ],
              onDelta: (d) {
                buf.write(d);
                output.value = buf.toString();
              },
              onDone: () => busy.value = false,
              onError: (e) {
                busy.value = false;
                output.value = 'Error: $e';
              },
            );
          }

          return Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const MDialogHeader(
                    title: 'Self-Testing & Explain-It Practice',
                    subtitle: 'Test what you remember, explain ideas in plain words, or practice Q&A from your own sources.',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      MChip(
                        label: 'Free Recall (from memory)',
                        selected: practiceMode == 'freerecall',
                        onTap: () =>
                            setModalState(() => practiceMode = 'freerecall'),
                      ),
                      MChip(
                        label: 'Explain in Plain Words',
                        selected: practiceMode == 'feynman',
                        onTap: () =>
                            setModalState(() => practiceMode = 'feynman'),
                      ),
                      MChip(
                        label: 'Practice Q&A',
                        selected: practiceMode == 'exam',
                        onTap: () => setModalState(() => practiceMode = 'exam'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: topicCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Topic (e.g. Nuclear fission, Calvin cycle, Eigenvalues)',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: attemptCtrl,
                    minLines: 4,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: practiceMode == 'freerecall'
                          ? 'Write everything you remember on this topic without checking your notes…'
                          : practiceMode == 'feynman'
                          ? 'Explain the concept in plain words, examples and analogies…'
                          : 'Write an answer to get feedback, or leave blank to receive questions first…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: MButton(
                      label: 'Evaluate with AI Coach',
                      icon: Icons.auto_awesome_outlined,
                      kind: MButtonKind.primary,
                      onPressed: runSession,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: output,
                    builder: (context, text, _) {
                      if (text.isEmpty) return const SizedBox.shrink();
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: SingleChildScrollView(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: BorderRadius.circular(MRadius.md),
                              border: Border.all(color: c.line),
                            ),
                            child: SelectableText(
                              text,
                              style: MType.body.copyWith(
                                color: c.ink,
                                fontSize: 13,
                                height: 1.55,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.label,
    required this.keyHint,
    required this.tone,
    required this.onTap,
  });
  final String label;
  final String keyHint;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isDark = context.isDark;
    return Material(
      color: isDark ? Colors.white.withValues(alpha: 0.075) : c.surface,
      borderRadius: BorderRadius.circular(MRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MRadius.md),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MRadius.md),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.15) : c.line,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 3, height: 16, color: tone),
              const SizedBox(width: 8),
              Text(
                label,
                style: MType.bodyStrong.copyWith(color: c.ink, fontSize: 12.5),
              ),
              const SizedBox(width: 6),
              Text(
                keyHint,
                style: MType.small.copyWith(color: c.inkFaint, fontSize: 9.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
